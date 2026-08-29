#!/usr/bin/env bash
# init.sh [--dry-run] [--repo <path>]
#
# The whole of Stage 0 as one command: detect, verify the spec path can be
# committed, scaffold the four files, survey a repo that has history, and
# report what a human still has to do.
#
# It exists because Stage 0 was six steps — detect, scaffold ×4, check the
# gitignore, survey, draft, promote — with no single entry point and a distinct
# way to get each one wrong. The cost was never time: detection takes ~1.5s and
# the survey ~0.7s. The cost was the number of orders you could do them in.
#
# Three properties are load-bearing:
#
#   1. It never overwrites. Every existing file is skipped and named. Running
#      it twice is safe, and the second run says it is resuming rather than
#      quietly redoing the first.
#   2. It verifies the spec path is committable BEFORE it writes anything.
#      `.claude/` is routinely gitignored. A scaffold that reports success
#      while the spec stays untracked leaves an audit trail that looks present
#      and is not, which is worse than no spec at all.
#   3. A step that did not run is never reported as a step that ran cleanly,
#      and a value that could not be measured is never rendered as zero. "no
#      commits, so the survey did not run" and "the survey found no evidence"
#      are different facts and print differently.
#
# It scaffolds through scripts/scaffold.sh, never `cp`: the templates carry
# worked examples (R1…R6, P1…P5) and copying them verbatim seeds a repo with
# requirements nobody agreed to. It leaves the constitution with no principles
# and the spec empty at R1, because an empty spec is the correct starting
# state.
#
# It prints no timestamps. The report is a function of the repo and nothing
# else, so two runs on an unchanged repo are byte-identical and a diff between
# them means something. Any date this skill does write is UTC-pinned elsewhere.
#
# It never prompts. Where a human is needed it says so and stops — see the
# `interactive` flag from detect-context.sh, and templates/interview.md.
#
# Exit codes:
#   0  done — everything written, or everything already present
#   2  usage
#   3  prerequisite missing: not a git work tree, no python3, or a helper
#      script or template this skill owns is absent
#   4  refused: the spec path is gitignored. Nothing was written.
#   5  partial: some work done, at least one step failed or was skipped for a
#      reason that needs a human. The report names each one.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd -P)

DRY=0
REPO=.
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --repo)
      shift
      [ $# -gt 0 ] || { echo "init: --repo needs a path" >&2; exit 2; }
      REPO=$1
      ;;
    -h|--help)
      sed -n '2,47p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "usage: init.sh [--dry-run] [--repo <path>]" >&2; exit 2 ;;
  esac
  shift
done

cd "$REPO" || { echo "init: cannot enter $REPO" >&2; exit 3; }
REPO_ABS=$(pwd -P)

# ── Report accumulators ──────────────────────────────────────────────────────
# Collected as we go and printed once at the end, so the report reads as three
# answers rather than a scroll of interleaved tool output.
WRITTEN=()
SKIPPED=()
NEEDS=()
STATUS=0

note_need() { NEEDS+=("$1"); }
fail_soft() { STATUS=5; note_need "$1"; }

die() { # <exit-code> <message...>
  local code=$1; shift
  printf 'init: %s\n' "$*" >&2
  exit "$code"
}

# ── Prerequisites ────────────────────────────────────────────────────────────
command -v python3 >/dev/null || die 3 "python3 not found. scaffold.sh and the detection parser both need it."

for helper in scaffold.sh detect-context.sh import-survey.sh; do
  [ -x "$SKILL_DIR/scripts/$helper" ] || die 3 "missing or non-executable helper: $SKILL_DIR/scripts/$helper"
done

# Not a git work tree is a refusal, not a warning. Every claim this lifecycle
# makes about an audit trail is a claim about `git log -p` over the spec, and
# the committable check below cannot even be asked outside a repo. Scaffolding
# anyway would produce four files and a promise nothing can keep.
if git_probe=$(git rev-parse --is-inside-work-tree 2>&1); then
  [ "$git_probe" = "true" ] || die 3 "not inside a git work tree (git said: $git_probe)"
else
  die 3 "not a git repository: $git_probe"
fi

# ── Detection ────────────────────────────────────────────────────────────────
DETECT_RAW=$("$SKILL_DIR/scripts/detect-context.sh")

# Parsed in one pass into shell-safe KEY=VALUE lines. If the JSON will not
# parse, that is reported as unknown — never silently defaulted, because the
# interactive flag decides whether a human can be asked anything at all and
# guessing it wrong in either direction is a real failure.
INTERACTIVE=unknown
CONFIG_FILE=""
OVERRIDES=""
if DETECT_KV=$(printf '%s' "$DETECT_RAW" | python3 -c '
import json, sys
d = json.load(sys.stdin)
def flat(v):
    if v is True:  return "true"
    if v is False: return "false"
    if v is None:  return ""
    return str(v)
ov = d.get("template_overrides") or []
print("INTERACTIVE=" + flat(d.get("interactive")))
print("CONFIG_FILE=" + flat(d.get("config_file")).replace("\n", " "))
print("OVERRIDES=" + " ".join(str(x) for x in ov if str(x).isprintable()))
'); then
  while IFS='=' read -r k v; do
    case $k in
      INTERACTIVE) [ -n "$v" ] && INTERACTIVE=$v ;;
      CONFIG_FILE) CONFIG_FILE=$v ;;
      OVERRIDES)   OVERRIDES=$v ;;
    esac
  done <<EOF
$DETECT_KV
EOF
else
  fail_soft "detect-context.sh output did not parse as JSON. Treating the session as non-interactive, which is the safe direction — but the detection did not run cleanly and nothing below should be read as if it had."
fi

# ── Is the spec path committable? ────────────────────────────────────────────
# This is the single most important check in the script, and it runs before any
# write.
#
# The verdict comes from BARE `git check-ignore`, never from `-v`. Measured on
# git 2.50.1: with -v, git exits 0 whenever any pattern matches, and a NEGATION
# counts as a match. On a repo carrying the correct remediation below,
# `check-ignore -v .claude/productizer/spec.md` printed `!.claude/productizer/**`
# and exited 0 while `git add` staged the same file without complaint — so the
# -v form would have refused a perfectly committable spec. The bare form exited
# 1 and was right. -v is used only to name the rule in a real refusal.
#
# Exit 0 is ignored, 1 is not ignored, anything else is "I could not tell you"
# — a corrupt index, an unreadable .gitignore, a permission problem. That third
# case is never folded into 1: an unanswered check is not a passed check.
SPEC_PATH=.claude/productizer/spec.md
CONST_PATH=.claude/productizer/constitution.md

committable() { # <path> -> prints "ok" | "ignored:<rule>" | "unknown:<msg>"
  local p=$1 out rc rule
  if out=$(git check-ignore -- "$p" 2>&1); then
    rule=$(git check-ignore -v -- "$p" 2>&1 || true)
    printf 'ignored:%s\n' "${rule:-$out}"
  else
    rc=$?
    if [ "$rc" -eq 1 ]; then
      printf 'ok\n'
    else
      printf 'unknown:git check-ignore exit %s: %s\n' "$rc" "${out:-(no output)}"
    fi
  fi
}

SPEC_VERDICT=$(committable "$SPEC_PATH")
case $SPEC_VERDICT in
  ok) ;;
  ignored:*)
    {
      echo "init: REFUSED. $SPEC_PATH is gitignored, so the spec could never be committed."
      echo "  ${SPEC_VERDICT#ignored:}"
      echo
      echo "  Nothing was written. A scaffold that reports success while the spec stays"
      echo "  untracked leaves an audit trail that looks present and is not."
      echo
      echo "  Fix .gitignore first, keeping the rest of .claude/ ignored. Git cannot"
      echo "  re-include a file whose parent directory is excluded, so a bare"
      echo "  \`!.claude/productizer/\` under a \`.claude/\` rule does nothing. Widen the"
      echo "  parent rule instead — replace"
      echo "      .claude/"
      echo "  with"
      echo "      .claude/*"
      echo "      !.claude/productizer/"
      echo "  Verified on git 2.50.1: the spec then stages and .claude/<anything-else>"
      echo "  stays ignored. Then re-run: $0"
    } >&2
    exit 4
    ;;
  unknown:*)
    {
      echo "init: REFUSED. Could not determine whether $SPEC_PATH is committable."
      echo "  ${SPEC_VERDICT#unknown:}"
      echo "  Nothing was written. An unanswered check is not a passed check."
    } >&2
    exit 4
    ;;
esac

# ── What is already here? ────────────────────────────────────────────────────
# Read before anything is written, so "resumed" is a fact about the state this
# run found rather than the state it created.
TARGETS=(
  "spec.md|$SPEC_PATH"
  "constitution.md|$CONST_PATH"
  "REVIEW.md|REVIEW.md"
  "CLAUDE.md|CLAUDE.md"
)

PRESENT=0
for entry in "${TARGETS[@]}"; do
  [ -e "${entry#*|}" ] && PRESENT=$((PRESENT + 1))
done
RESUMED=0
[ "$PRESENT" -eq "${#TARGETS[@]}" ] && RESUMED=1

# ── Scaffold ─────────────────────────────────────────────────────────────────
template_for() { # <name> -> path, preferring a repo override
  local name=$1
  if [ -f ".claude/productizer/templates/$name" ]; then
    printf '%s\n' ".claude/productizer/templates/$name"
  else
    printf '%s\n' "$SKILL_DIR/templates/$name"
  fi
}

for entry in "${TARGETS[@]}"; do
  name=${entry%%|*}
  dst=${entry#*|}

  if [ -e "$dst" ]; then
    SKIPPED+=("$dst — exists, left untouched")
    continue
  fi

  tpl=$(template_for "$name")
  if [ ! -f "$tpl" ]; then
    fail_soft "$dst — not written: no template at $tpl"
    SKIPPED+=("$dst — no template found")
    continue
  fi
  case $tpl in
    .claude/productizer/templates/*) origin=" (repo override in play: $tpl)" ;;
    *)                               origin="" ;;
  esac

  # Each destination is checked in its own right. The spec refusal above is
  # fatal; a gitignored REVIEW.md is a named skip, because the audit trail
  # survives it and stopping the whole run would be disproportionate.
  v=$(committable "$dst")
  if [ "$v" != "ok" ]; then
    SKIPPED+=("$dst — not committable: ${v#*:}")
    fail_soft "$dst was not written because it is gitignored or unverifiable: ${v#*:}"
    continue
  fi

  if [ "$DRY" -eq 1 ]; then
    if out=$("$SKILL_DIR/scripts/scaffold.sh" --dry-run "$tpl" "$dst" 2>&1); then
      WRITTEN+=("$dst — WOULD be written from $tpl$origin")
    else
      SKIPPED+=("$dst — scaffold refused: $out")
      fail_soft "$dst — scaffold refused in dry run: $out"
    fi
    continue
  fi

  if out=$("$SKILL_DIR/scripts/scaffold.sh" "$tpl" "$dst" 2>&1); then
    WRITTEN+=("$dst — ${out#scaffold: wrote "$dst" }$origin")
  else
    SKIPPED+=("$dst — scaffold refused: $out")
    fail_soft "$dst — scaffold refused: $out"
  fi
done

# ── Did anything agreed-by-nobody get seeded? ────────────────────────────────
# scaffold.sh strips the fenced example blocks. This asserts the result rather
# than trusting it: a template edited to move a requirement outside its fence
# would otherwise seed R1…R6 silently, and a seeded requirement gets cited
# before anyone notices it was a sample.
count_matches() { # <pattern> <file> -> a number, always
  local n
  n=$(grep -cE "$1" "$2" || true)
  printf '%s\n' "${n:-0}"
}

SEED_REPORT=""
if [ "$DRY" -eq 0 ]; then
  if [ -f "$SPEC_PATH" ]; then
    n=$(count_matches '^- \*\*R[0-9]+\*\*' "$SPEC_PATH")
    SEED_REPORT="${SEED_REPORT}  requirement definitions in $SPEC_PATH: $n"$'\n'
    [ "$n" -eq 0 ] || fail_soft "$SPEC_PATH was scaffolded with $n requirement definition(s) in it. An empty spec is the correct starting state — delete them before the first intake."
    # Placeholder rows in the index and criteria tables live outside the fenced
    # example block in templates/spec.md, so they survive. They are shape, not
    # requirements, but a reader cannot tell — say so rather than pass silently.
    r=$(count_matches '^\| R[0-9]+ \|' "$SPEC_PATH")
    SEED_REPORT="${SEED_REPORT}  placeholder table rows in $SPEC_PATH: $r"$'\n'
    [ "$r" -eq 0 ] || note_need "$SPEC_PATH still carries $r placeholder table row(s) (\`| R1 | <area> | …\`). They come from outside the template's example fence, so scaffolding does not strip them. Delete them — a reader cannot tell a shape row from a real one."
  fi
  if [ -f "$CONST_PATH" ]; then
    n=$(count_matches '^### P[0-9]+' "$CONST_PATH")
    SEED_REPORT="${SEED_REPORT}  principle definitions in $CONST_PATH: $n"$'\n'
    [ "$n" -eq 0 ] || fail_soft "$CONST_PATH was scaffolded with $n principle(s) in it. Principles are ratified, never scaffolded — delete them."
    a=$(count_matches '^\| [0-9]{4}-[0-9]{2}-[0-9]{2} \| P[0-9]+ \|' "$CONST_PATH")
    SEED_REPORT="${SEED_REPORT}  placeholder amendment rows in $CONST_PATH: $a"$'\n'
    [ "$a" -eq 0 ] || note_need "$CONST_PATH still carries $a placeholder amendment row(s) recording changes to principles that do not exist. They sit outside the template's example fence. Delete them."
  fi
else
  SEED_REPORT="  not checked — dry run wrote nothing to inspect"$'\n'
fi

# ── Survey (Stage 0c) ────────────────────────────────────────────────────────
# Only for a repo that has history. A repo with no commits has nothing to
# survey, and that is a different answer from "surveyed and found nothing".
SURVEY_STATE=""
SURVEY_DETAIL=""
SURVEY_OUT=""

if [ "$DRY" -eq 1 ]; then
  SURVEY_STATE="skipped"
  SURVEY_DETAIL="dry run — would run scripts/import-survey.sh $REPO_ABS"
elif [ "$RESUMED" -eq 1 ]; then
  SURVEY_STATE="skipped"
  SURVEY_DETAIL="already initialised — the survey is a first-fill step and is not re-run. To run it again by hand: $SKILL_DIR/scripts/import-survey.sh $REPO_ABS"
elif ! head_probe=$(git rev-parse --verify HEAD 2>&1); then
  SURVEY_STATE="not-run"
  SURVEY_DETAIL="the repo has no commits yet, so there is no history to survey (git said: $head_probe). This is NOT an evidence count of zero — nothing was measured."
else
  SURVEY_OUT=$(mktemp "${TMPDIR:-/tmp}/productizer-init.XXXXXX")
  # shellcheck disable=SC2064  # expand SURVEY_OUT now: the trap must survive it going out of scope
  trap "rm -f '$SURVEY_OUT'" EXIT
  # The survey reports one of three verdicts, in its own words. They are matched
  # in order of strength, and anything unrecognised is `unreadable` — never
  # quietly folded into the weakest verdict, because "the survey said little"
  # and "I could not read the survey" are different facts and only one of them
  # is about the repo.
  if "$SKILL_DIR/scripts/import-survey.sh" "$REPO_ABS" >"$SURVEY_OUT" 2>&1; then
    trim() { local s=$1; printf '%s\n' "${s#"${s%%[![:space:]]*}"}"; }
    if grep -q 'DRAFT TIER: STRONG' "$SURVEY_OUT"; then
      SURVEY_STATE="strong"
      SURVEY_DETAIL=$(trim "$(grep -m1 'Enough to draft from:' "$SURVEY_OUT" || echo 'behaviour evidence is above the floor.')")
    elif grep -q 'DRAFT TIER: WEAK' "$SURVEY_OUT"; then
      SURVEY_STATE="weak"
      SURVEY_DETAIL=$(trim "$(grep -m1 'DRAFT TIER: WEAK' "$SURVEY_OUT")")
    elif grep -q 'NOT ENOUGH EVIDENCE TO DRAFT A SPEC' "$SURVEY_OUT"; then
      SURVEY_STATE="none"
      SURVEY_DETAIL="both evidence tiers came back under their floor. Do not draft requirements from this survey."
    elif verdict=$(grep -m1 'Enough to draft from:' "$SURVEY_OUT"); then
      # Pre-tier survey. Kept so a repo pinned to an older copy of the skill
      # still gets a verdict rather than an unreadable.
      SURVEY_STATE="strong"
      SURVEY_DETAIL=$(trim "$verdict")
    else
      SURVEY_STATE="unreadable"
      SURVEY_DETAIL="the survey ran and exited 0, but printed no verdict this script recognises. Read it yourself: $SKILL_DIR/scripts/import-survey.sh $REPO_ABS"
      fail_soft "The survey produced no recognisable verdict. Do not treat that as thin evidence or as rich evidence — it is neither, and it was not measured."
    fi
  else
    SURVEY_STATE="failed"
    SURVEY_DETAIL="import-survey.sh exited non-zero. Last line: $(tail -n 1 "$SURVEY_OUT")"
    fail_soft "The import survey did not run to completion, so there is no evidence verdict for this repo. Run it by hand and read the error: $SKILL_DIR/scripts/import-survey.sh $REPO_ABS"
  fi
fi

# ── What the human still has to do ───────────────────────────────────────────
# This section is the deliverable. Everything above is bookkeeping.
interview_next() { # <why>
  if [ "$INTERACTIVE" = "true" ]; then
    note_need "$1 Ask instead of stopping: work through the five questions in $SKILL_DIR/templates/interview.md. The answers become \`inferred\` requirements exactly like survey output — unconfirmed, unable to halt Stage 2 — each carrying which question produced it."
  else
    note_need "$1 This run is NOT interactive: nobody is present to ask, so nothing more can be done here and stopping is the correct outcome. Re-run in a session with a human, who works through $SKILL_DIR/templates/interview.md. Do not draft requirements from a thin survey — that is invention, and it lands in the spec looking exactly like evidence."
  fi
}

case $SURVEY_STATE in
  strong)
    note_need "Draft at most 30 \`inferred\` requirements from the survey, following templates/import.md. Every one carries the file, line or test it came from, and the word \`Unconfirmed.\` — that marker is what stops the Stage 2 contradiction halt defending behaviour nobody agreed to."
    note_need "Then promote them: an inferred requirement becomes active only when a named human says the behaviour is intended, in batches they have actually read. Promotion is a commit."
    ;;
  weak)
    interview_next "The survey reached the WEAK tier only: it found no behaviour the code states to a machine, and fell back to what the repo says about itself in prose. Doc drift is the normal state of a repo, so a requirement drafted from a README asserts that the README is still true."
    note_need "If you do draft from the weak tier anyway, cap the pass at TEN requirements and mark each one \`Inferred (weak evidence) from <citation>. Unconfirmed.\` The tier travels with the requirement, in the spec, forever."
    ;;
  none)
    interview_next "The survey found too little to draft from: both evidence tiers came back under their floor."
    ;;
  failed|unreadable)
    note_need "Get an evidence verdict before drafting anything. Until then this repo has no measured basis for a spec, and that is a different state from a repo measured as empty."
    ;;
  not-run)
    note_need "There is no history to import from. Start from intake (templates/intake.md): the next intent that arrives becomes R1."
    ;;
esac

if [ "$CONFIG_FILE" = "" ]; then
  note_need "No .claude/productizer/config.json yet. Stage 0 binding writes it on the first stage that touches GitHub or Jira, in one question. Secrets never go in it — JIRA_API_TOKEN comes from the environment."
fi

note_need "Name the system once, in $SPEC_PATH, and use that exact noun in every requirement. A spec that says \"the service\", \"the CLI\" and \"the app\" for one system hides which component owns what."
note_need "Ratify the first constitution principles deliberately. The file was left with none on purpose — a scaffolded principle is a bound nobody agreed to, enforced with the authority of one that was."

# ── Report ───────────────────────────────────────────────────────────────────
mode="run"
[ "$DRY" -eq 1 ] && mode="DRY RUN — nothing was written"

echo "── Productizer · Stage 0 init ────────────────────────────────────────"
echo "mode          : $mode"
echo "repo          : $REPO_ABS"
echo "spec path     : $SPEC_PATH"
echo "committable   : yes — git check-ignore does not match it"
echo "interactive   : $INTERACTIVE"
echo "config        : ${CONFIG_FILE:-none yet}"
echo "repo templates: ${OVERRIDES:-none — the skill defaults are in use}"
[ "$RESUMED" -eq 1 ] && echo "state         : already initialised — this run is a resume, not a redo"
echo

echo "WRITTEN (${#WRITTEN[@]})"
if [ "${#WRITTEN[@]}" -eq 0 ]; then
  echo "  nothing"
else
  for w in "${WRITTEN[@]}"; do echo "  $w"; done
fi
echo

echo "SKIPPED (${#SKIPPED[@]})"
if [ "${#SKIPPED[@]}" -eq 0 ]; then
  echo "  nothing"
else
  for s in "${SKIPPED[@]}"; do echo "  $s"; done
fi
echo

echo "SEEDED-CONTENT CHECK"
printf '%s' "$SEED_REPORT"
echo

echo "SURVEY (Stage 0c)"
echo "  state : ${SURVEY_STATE:-not-run}"
echo "  $SURVEY_DETAIL"
echo

echo "WHAT IT NEEDS FROM YOU (${#NEEDS[@]})"
i=1
for n in "${NEEDS[@]}"; do
  echo "  $i. $n"
  i=$((i + 1))
done
echo
echo "──────────────────────────────────────────────────────────────────────"

exit "$STATUS"
