#!/usr/bin/env bash
# check-superseded-text.sh [--version] [--help] [--root DIR]
#
# Asserts R3: THE LIFECYCLE SHALL KEEP A REPLACED REQUIREMENT'S ORIGINAL TEXT
# IN THE SPEC, MARKED SUPERSEDED.
#
# R3 is two obligations wearing one sentence, and only one of them is cheap.
#
#   MARKED SUPERSEDED is readable in the file in front of you: the marker is
#   there or it is not, it points forward or it does not, and the id it points
#   at is active or it is not.
#
#   THE ORIGINAL TEXT is not readable in the file in front of you AT ALL. The
#   spec always says whatever it currently says; a superseded requirement whose
#   sentence was quietly rewritten last month looks exactly like one that was
#   never touched. The only place the original survives is git.
#
# So this check reads what a commit USED TO SAY, not what a commit changed.
# That distinction is the whole design. A diff-only gate sees an edit at the
# moment it is proposed and never again; it cannot answer "is R14 still the
# sentence that was agreed", because the answer lives in a commit nobody is
# diffing today. This repo has twice found in history what a diff could not
# see, and this is the first check here to take git history as an input.
#
# WHY A PURPOSE-BUILT BASELINE, AND NOT `validate-spec.py --baseline`
#
# The validator already reports SUPERSEDED_TEXT_CHANGED, and it is the right
# code - but it compares against ONE baseline the caller supplies, which in
# practice is HEAD~1. That catches an edit made in the last commit and nothing
# else: an edit made three commits ago is, from HEAD~1's point of view, the
# agreed text. The baseline that answers R3 is DIFFERENT FOR EVERY
# REQUIREMENT - it is the last commit before THAT requirement was superseded -
# and no single ref is it. This check finds each one.
#
# WHAT IT ASSERTS
#
#   1. THE TEXT IS UNALTERED. For every superseded or withdrawn requirement,
#      the sentence in the spec today is the sentence it carried at the last
#      commit at which it was still active. Whitespace and re-wrapping are
#      normalised away; words are not.
#
#      Withdrawn is included with superseded. R3 names supersession, but
#      `references/format-spec.md` section 3 puts both under the same
#      retention rule, and the failure is identical: a status line without the
#      text it applies to is not a record. Excluding withdrawn would leave the
#      same defect undetected under a different marker.
#
#   2. THE MARKER WAS NOT REMOVED. A requirement that carried a supersede or
#      withdraw marker in any reachable commit and carries none today has had
#      its status quietly reverted - the text may well be intact, and the spec
#      now presents replaced behaviour as agreed behaviour.
#
#   3. THE MARKER IS WELL FORMED. `Superseded by R<n>.` or `Withdrawn.`,
#      exactly, on the line beneath the requirement. `Superseded.` with no
#      pointer is a dead end: the citation from two years ago leads nowhere,
#      which is the one thing supersession exists to prevent.
#
#   4. THE POINTER RESOLVES, AND RESOLVES TO SOMETHING LIVE. The target id
#      must be defined in the spec and must itself be active. A pointer to an
#      id that does not exist is a broken forward reference; a pointer to
#      another superseded requirement is a chain that ends in nothing agreed,
#      and a reader following it finds no current behaviour at either end.
#      Self-supersession is refused for the same reason.
#
# SHALLOW CLONES AND MISSING HISTORY ARE UNKNOWN, NOT CLEAN
#
# CI clones with fetch-depth: 0. A contributor's `--depth 1` clone reaches the
# spec, reaches the supersede marker, and CANNOT reach the version before it.
# There is exactly one honest answer to "was the text altered" in that repo -
# it is not known - and it is exit 2. Reporting clean there would mean the
# check passes most reliably in precisely the repo where it measured nothing.
#
# The unmeasured cases, each named separately in the output:
#
#   the repo is shallow                      the prior version was never fetched
#   the spec is not tracked                  there is no previous version at all
#   the requirement is not in any commit      it exists only in the working tree
#   the spec holds no requirements            nothing to examine; not a clean run
#
# A REQUIREMENT THAT WAS ALREADY SUPERSEDED IN ITS FIRST COMMIT, in a repo with
# complete history, is NOT unmeasured. Nothing preceded that commit, so the
# text as first committed IS the original, and it is compared against. This is
# the ordinary shape of an imported spec, and calling it unmeasured forever
# would make the check permanently refuse on every repo that imported one.
#
# EXIT PRECEDENCE: UNMEASURED BEATS FINDINGS BEATS CLEAN. A run that could not
# reach some baseline exits 2 even when it also found a real alteration; the
# findings are still printed. The reason is that 1 is a complete verdict and
# this run does not have one. This mirrors `check-hygiene.sh`, where one
# unreadable file makes the whole run exit 2 rather than reporting the files it
# did manage to read as a pass.
#
# REPORTED BY LOCATION, NEVER BY QUOTING CONTENT. A finding names the id, the
# file, the line and the short sha of the commit that holds the original. It
# never prints the requirement text, and never prints a diff of it. This
# output is written into a committed result file, and a check that quotes the
# text it is protecting publishes it on every run.
#
# ONE LINE PER FILE EXAMINED, on stdout, unindented: the spec, then every
# historical version of the spec that was read, as `<path>@<short sha>`. The
# runner treats a clean exit having examined less than declared as HOLLOW,
# which is a failure - and a git check is exactly where hollowness hides,
# because a loop over commits that never executes prints nothing and succeeds.
#
# COST. Every commit that touched the spec is read and parsed once, so the run
# is linear in the spec's own history, not the repo's. That is six commits in
# this repo and a few hundred in a mature one; it is not linear in the number
# of requirements, which is the axis that actually grows.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - A requirement that enters the repo ALREADY SUPERSEDED and already
#     rewritten cannot be caught, because its first commit is the only
#     baseline there is and the rewrite is inside it. This is the residual
#     risk of the imported-spec case above, and it is the price of not
#     refusing every imported spec forever.
#     (Superseding and rewriting in one ORDINARY commit IS caught: the
#     baseline is the commit before, where the requirement was still active
#     carrying its original sentence. Proven on a fixture.)
#   - A requirement moved between spec files in a split spec reads as
#     disappeared here; this check reads one spec path.
#   - A rewritten history (rebase, filter-branch) is trusted as given. The
#     check reads what the repo now says the past was.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  clean
#   1  findings
#   2  could not run, or could not measure - no work tree, no spec, no parser,
#      a spec with no requirements, or a baseline out of reach. Never 0.
set -euo pipefail

VERSION="check-superseded-text 1.0"
ROOT=""

usage() {
  printf 'usage: check-superseded-text.sh [--version] [--help] [--root DIR]\n'
  printf '  --root DIR  the repo work tree to examine. Defaults to the git\n'
  printf '              top level, never to the working directory.\n'
}

die_unmeasured() { printf 'check-superseded-text: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    -*) printf 'check-superseded-text: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'check-superseded-text: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# Defaulting to the working directory has caused four separate silent-wrong-
# answer bugs here: the script reads a directory that is not the repo and
# reports a confident clean result. git names the work tree or nothing does.
if [ -z "$ROOT" ]; then
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_unmeasured "no git work tree here, and --root was not given. Refusing rather than reading the working directory, which is not the repo often enough to matter."
  fi
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"

SELFDIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="$SELFDIR/spec-requirements.sh"
[ -x "$PARSER" ] ||
  die_unmeasured "spec-requirements.sh is not beside this script and executable. Without the parser nothing here read the spec, and a run that read nothing is not a run that found nothing."

SPECREL=".claude/productizer/spec.md"
SPEC="$ROOT/$SPECREL"
[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "cannot read $SPECREL under $ROOT. Without the spec there is no superseded requirement to check the retention of."

TOP="$(git -C "$ROOT" rev-parse --show-toplevel)" ||
  die_unmeasured "--root $ROOT is not inside a git work tree. R3's second half is only answerable from history, and there is no history here."
case "$ROOT/" in
  "$TOP"/*) ;;
  *) die_unmeasured "--root $ROOT resolves outside its own git top level $TOP" ;;
esac
SPECGIT="${SPEC#"$TOP"/}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-superseded-text.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

found=0
unmeasured=0
finding() { printf '    %s\n' "$1"; found=1; }
unmeasurable() { printf '    UNMEASURED %s\n' "$1"; unmeasured=1; }

# --- the spec as it stands now ---------------------------------------------
printf '%s\n' "$SPECREL"                 # coverage: one line per file examined
"$PARSER" "$SPEC" > "$WORK/cur.tsv" ||
  die_unmeasured "the parser refused $SPECREL"

if [ ! -s "$WORK/cur.tsv" ]; then
  printf 'requirements examined: 0\n'
  die_unmeasured "$SPECREL holds no requirement definitions. That is nothing measured, not nothing wrong."
fi

# --- every version of the spec that git can still reach ---------------------
TRACKED="$(git -C "$TOP" ls-files -- "$SPECGIT")"
SHALLOW="$(git -C "$TOP" rev-parse --is-shallow-repository)"

: > "$WORK/hist.tsv"
versions=0
if [ -n "$TRACKED" ]; then
  git -C "$TOP" log --format=%H -- "$SPECGIT" > "$WORK/commits" ||
    die_unmeasured "git log over $SPECREL failed; the history this check reads is unavailable"

  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    # ls-tree, not `git show`, as the existence probe: it prints nothing and
    # exits 0 for a path absent at that commit, so a deletion commit costs no
    # error output. Suppressing git's stderr to find that out is exactly how a
    # sweep over git objects in this repo once reported CLEAN while every
    # command inside the loop was failing.
    [ -n "$(git -C "$TOP" ls-tree "$sha" -- "$SPECGIT")" ] || continue
    short="$(git -C "$TOP" rev-parse --short "$sha")"
    git -C "$TOP" show "$sha:$SPECGIT" > "$WORK/v.md" ||
      die_unmeasured "cannot read $SPECREL at $short, which git listed as a commit that touched it"
    printf '%s@%s\n' "$SPECREL" "$short"  # coverage: one line per file examined
    versions=$((versions + 1))
    "$PARSER" "$WORK/v.md" |
      awk -F'\t' -v s="$short" 'BEGIN{OFS="\t"} {print s, $1, $2, $3, $4, $5}' >> "$WORK/hist.tsv"
  done < "$WORK/commits"
fi

printf 'spec versions examined: %d\n' "$versions"

# --- the requirements whose text must not have moved ------------------------
retained=0
compared=0

while IFS="$(printf '\t')" read -r id line status target text; do
  [ -n "${id:-}" ] || continue

  # ---- 3 and 4: the marker itself, readable in the file in front of you ----
  if [ "$status" = "malformed" ]; then
    finding "$SPECREL:$line: $id carries a status marker that is neither 'Superseded by R<n>.' nor 'Withdrawn.', or carries two. A marker with no resolvable pointer is a citation that leads nowhere, which is the one thing supersession exists to prevent."
  fi

  if [ "$status" = "superseded" ]; then
    tstatus="$(awk -F'\t' -v t="$target" '$1 == t { print $3; exit }' "$WORK/cur.tsv")"
    if [ "$target" = "$id" ]; then
      finding "$SPECREL:$line: $id is superseded by itself. The forward pointer has to leave the requirement it is written on."
    elif [ -z "$tstatus" ]; then
      finding "$SPECREL:$line: $id points forward at $target, which is not defined in $SPECREL. A citation following that pointer resolves to nothing, and nothing errors."
    elif [ "$tstatus" != "active" ]; then
      finding "$SPECREL:$line: $id points forward at $target, which is itself $tstatus. The chain ends in behaviour nobody agreed to, so a reader following it finds no current requirement at either end."
    fi
  fi

  # ---- 2: a marker that was there and is not now --------------------------
  if [ "$status" = "active" ]; then
    was="$(awk -F'\t' -v i="$id" '$2 == i && ($4 == "superseded" || $4 == "withdrawn") { print $1; exit }' "$WORK/hist.tsv")"
    if [ -n "$was" ]; then
      finding "$SPECREL:$line: $id is active today and was $(awk -F'\t' -v i="$id" '$2 == i && ($4 == "superseded" || $4 == "withdrawn") { print $4; exit }' "$WORK/hist.tsv") at $was. The marker was removed, so replaced behaviour now reads as agreed behaviour."
    fi
    continue
  fi

  [ "$status" = "superseded" ] || [ "$status" = "withdrawn" ] || continue
  retained=$((retained + 1))

  # ---- 1: the text, which only git can answer -----------------------------
  #
  # The baseline is the newest commit at which THIS requirement was still
  # active - a different commit for every requirement, which is why one
  # `--baseline` ref cannot answer this.
  base_sha="$(awk -F'\t' -v i="$id" '$2 == i && $4 == "active" { print $1; exit }' "$WORK/hist.tsv")"
  base_kind="pre-supersede"

  if [ -z "$base_sha" ]; then
    # Never active in any reachable commit. Either the history is short, or
    # the requirement entered the repo already superseded.
    oldest_sha="$(awk -F'\t' -v i="$id" '$2 == i { s = $1 } END { if (s != "") print s }' "$WORK/hist.tsv")"
    if [ -z "$oldest_sha" ]; then
      printf '  %s %-10s baseline —  text —\n' "$id" "$status"
      unmeasurable "$SPECREL:$line: $id appears in no commit that touched $SPECREL. It exists only in the working tree, so there is no previous version of its text to compare against. Commit it and re-run; this is not a clean result."
      continue
    fi
    if [ "$SHALLOW" = "true" ]; then
      printf '  %s %-10s baseline —  text —\n' "$id" "$status"
      unmeasurable "$SPECREL:$line: $id is $status in every commit this clone can reach, and the clone is shallow. The version before the supersede was never fetched, so whether the text was altered is UNKNOWN. Fetch full history (fetch-depth: 0) and re-run."
      continue
    fi
    # Full history, and the requirement was already superseded when it first
    # appeared: nothing preceded that commit, so what it said there IS the
    # original. This is the ordinary shape of an imported spec.
    base_sha="$oldest_sha"
    base_kind="first-commit"
  fi

  base_text="$(awk -F'\t' -v i="$id" -v s="$base_sha" '$1 == s && $2 == i { print $6; exit }' "$WORK/hist.tsv")"
  compared=$((compared + 1))

  if [ "$base_text" = "$text" ]; then
    printf '  %s %-10s baseline %s (%s)  text unchanged\n' "$id" "$status" "$base_sha" "$base_kind"
  else
    printf '  %s %-10s baseline %s (%s)  text CHANGED\n' "$id" "$status" "$base_sha" "$base_kind"
    finding "$SPECREL:$line: $id is $status, and its sentence is not the sentence it carried at $base_sha - the last commit at which it was still active. The original text was rewritten at or after the point the requirement was replaced, so the spec no longer records what was agreed, only what someone would prefer it had said. The text is deliberately not quoted here; read it with: git show $base_sha:$SPECGIT"
  fi
done < "$WORK/cur.tsv"

printf 'requirements examined: %d\n' "$(wc -l < "$WORK/cur.tsv" | tr -d ' ')"
printf 'superseded or withdrawn: %d\n' "$retained"
if [ "$retained" -eq "$compared" ]; then
  printf 'text compared against history: %d\n' "$compared"
else
  printf 'text compared against history: %d of %d — the rest are unmeasured above, not clean\n' "$compared" "$retained"
fi
if [ -z "$TRACKED" ]; then
  printf 'note: %s is not tracked by git, so no previous version of any requirement exists. That is no measurement, not a measured zero.\n' "$SPECREL"
  unmeasurable "$SPECREL:1: the spec is untracked. R3's retention half is unanswerable until it is committed."
fi

if [ "$unmeasured" -ne 0 ]; then
  printf 'UNMEASURED: at least one superseded requirement has no reachable earlier version, so this run has no verdict on whether its text was altered. Not a pass.\n' >&2
  exit 2
fi
if [ "$found" -ne 0 ]; then
  printf 'FAIL: a replaced requirement no longer carries the text that was agreed, or no longer points anywhere. R3 keeps the original; these findings are where it stopped being kept.\n' >&2
  exit 1
fi

printf 'PASS: every superseded or withdrawn requirement still carries the sentence it had at the commit before it was replaced, and every forward pointer resolves to an active id.\n'
