#!/usr/bin/env bash
# pr-spec-comment.sh [repo-root] [--base REF] [--checks PATH] [--version] [--help]
#
# Renders what a change did to the living spec, as markdown, for a human to
# paste onto a pull request.
#
# IT RENDERS TO STDOUT AND POSTS NOTHING. That is not a missing feature; it is
# the design. Posting to a pull request is a PUBLISH, and this repository routes
# every publish through `.claude/hooks/publish-gate.sh`, which demands a written
# checklist naming the exact command and a person who decided to run it. A
# script that posted this by itself would be a publish routed around the
# product's own central mechanism, inside the repository that ships it. So
# `--post` is REFUSED with a sentence rather than left unimplemented, and the
# footer of every report names the command a person may choose to run.
#
# WHAT IT DOES NOT COMPUTE ITSELF. The spec delta comes from `spec-diff.sh`,
# which already resolves the base ref, reads both files at both ends, caps an
# oversized diff instead of truncating it, and separates "unchanged" from "no
# baseline" from "the ref does not resolve". Re-deriving any of that here would
# give this repository two answers to one question. This reads spec-diff.sh's
# output, and the base commit spec-diff.sh reports is the base EVERY other
# section is measured against, so one resolution of one ref anchors the whole
# report.
#
# NOTHING UNMEASURED IS RENDERED AS ZERO. "The change adds no requirement",
# "the base ref does not resolve", "the diff was over the cap so it was not
# read" and "the spec is not readable" all end in an empty id list, and they are
# four different facts. Each gets its own sentence; the ones that are an absence
# of measurement rather than a measured absence are marked NOT MEASURED and
# change the exit code, so a caller can tell the report is partial without
# reading it.
#
# Exit: 0 rendered, every section measured
#       2 usage, or a refused publish
#       3 not a git work tree, no such directory, or spec-diff.sh is unusable
#       5 rendered, but at least one section could NOT be measured and says so
set -euo pipefail

VERSION="pr-spec-comment 1.0"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SPEC_DIFF="$HERE/spec-diff.sh"

SPEC_REL=".claude/productizer/spec.md"
CLASS_REL=".claude/productizer/classifications"
PROBE_REL="evals/solver-probe.py"
CHECKS_REL=".claude/productizer/checks-result.json"

ROOT=""
BASE=""
CHECKS=""

usage() {
  echo "usage: pr-spec-comment.sh [repo-root] [--base REF] [--checks PATH]"
  echo "Renders markdown to stdout. It posts nothing, by design - see the file header."
}

while [ $# -gt 0 ]; do
  case "$1" in
    --base)     BASE="${2:-}"; [ -n "$BASE" ] || { echo "pr-spec-comment: --base needs a ref" >&2; exit 2; }; shift 2 ;;
    --base=*)   BASE="${1#--base=}"; [ -n "$BASE" ] || { echo "pr-spec-comment: --base needs a ref" >&2; exit 2; }; shift ;;
    --checks)   CHECKS="${2:-}"; [ -n "$CHECKS" ] || { echo "pr-spec-comment: --checks needs a path" >&2; exit 2; }; shift 2 ;;
    --checks=*) CHECKS="${1#--checks=}"; [ -n "$CHECKS" ] || { echo "pr-spec-comment: --checks needs a path" >&2; exit 2; }; shift ;;
    --version)  echo "$VERSION"; exit 0 ;;
    -h|--help)  usage; exit 0 ;;
    # Named explicitly, because somebody will try it and deserves the reason
    # rather than "unknown option".
    --post|--comment|--publish|--gh|--pr)
      echo "pr-spec-comment: $1 is REFUSED, and deliberately not implemented." >&2
      echo "Posting to a pull request is a publish. This repository puts every publish behind" >&2
      echo ".claude/hooks/publish-gate.sh, which requires a written checklist naming the exact" >&2
      echo "command and a person who decided to run it. Auto-posting from here would route" >&2
      echo "around that gate inside the repository that ships it." >&2
      echo "The markdown goes to stdout; the report's footer names the command." >&2
      exit 2 ;;
    -*)         echo "pr-spec-comment: unknown option: $1" >&2; exit 2 ;;
    *)          [ -z "$ROOT" ] || { echo "pr-spec-comment: only one repo-root" >&2; exit 2; }; ROOT="$1"; shift ;;
  esac
done

[ -n "$ROOT" ] || ROOT="."
cd "$ROOT" || { echo "pr-spec-comment: no such directory: $ROOT" >&2; exit 3; }
git rev-parse --is-inside-work-tree >/dev/null || { echo "pr-spec-comment: not a git repository: $ROOT" >&2; exit 3; }
cd "$(git rev-parse --show-toplevel)"
[ -n "$CHECKS" ] || CHECKS="$CHECKS_REL"

[ -x "$SPEC_DIFF" ] || {
  echo "pr-spec-comment: spec-diff.sh is not executable at $SPEC_DIFF." >&2
  echo "The delta is computed there and nowhere else. Refusing rather than reimplementing it." >&2
  exit 3; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SD_OUT="$WORK/spec-diff.txt"

say() { printf '%s\n' "$*"; }

# Set only by an absence of MEASUREMENT. A measured empty set never sets it.
UNMEASURED=0

# --- the delta -------------------------------------------------------------
# spec-diff.sh's stderr is neither captured nor discarded: it reprints git's own
# errors there, and an error nobody was shown is the silent empty diff both
# scripts exist to prevent.
SD_ARGS=()
[ -z "$BASE" ] || SD_ARGS=(--base "$BASE")
SD_RC=0
"$SPEC_DIFF" . ${SD_ARGS[@]+"${SD_ARGS[@]}"} >"$SD_OUT" || SD_RC=$?

case "$SD_RC" in
  0|4|5|7) ;;
  6) UNMEASURED=1 ;;
  2|3) echo "pr-spec-comment: spec-diff.sh exited $SD_RC - see its message above." >&2; exit 3 ;;
  *)   echo "pr-spec-comment: spec-diff.sh exited $SD_RC, which this script cannot read." >&2; exit 3 ;;
esac

HEAD_SHA="$(git rev-parse --verify 'HEAD^{commit}')"
# One resolution of the base, lifted from spec-diff.sh's own header, so every
# section below is measured against the ref the delta was measured against.
BASE_SHA="$(sed -n 's/^Base: .* at \([0-9a-f]\{7,\}\),.*/\1/p' "$SD_OUT" | head -n 1)"
# shellcheck disable=SC2016  # the backticks are literal, in a sed regex matching spec-diff.sh's markdown; single quotes are what keeps them literal
BASE_LABEL="$(sed -n 's/^Base: `\([^`]*\)`.*/\1/p' "$SD_OUT" | head -n 1)"
[ -n "$BASE_LABEL" ] || BASE_LABEL="did not resolve"

# --- requirement ids, out of the fenced diff -------------------------------
# The spec's section only. spec-diff.sh emits the constitution too, and a
# principle carries no requirement id.
spec_section() {
  awk -v want="$SPEC_REL" '
    index($0, "### `") == 1 { insec = (index($0, "`" want "`") > 0); next }
    insec { print }
  ' "$SD_OUT"
}

ADDED=""; DROPPED=""; SUPERSEDED=""; WITHDRAWN=""
if [ "$SD_RC" = 0 ] && [ -s "$SD_OUT" ] && [ -n "$(spec_section)" ]; then
  # awk walks the body in order, so a `Superseded by` or `Withdrawn.` line is
  # attributed to the id above it - which is where the spec puts it. The id line
  # may arrive as context, as a removal or as an addition; all three move the
  # cursor, because the annotation belongs to whichever one it was.
  spec_section | awk '
    /^(\+\+\+|---) / { next }
    { body = substr($0, 2) }
    body ~ /^- \*\*R[0-9]+\*\*/ {
      id = body; sub(/^- \*\*/, "", id); sub(/\*\*.*$/, "", id); cur = id
      if (substr($0, 1, 1) == "+") add[id] = 1
      if (substr($0, 1, 1) == "-") drop[id] = 1
      next
    }
    substr($0, 1, 1) == "+" && body ~ /Superseded by R[0-9]+\./ && cur != "" { sup[cur] = 1; next }
    substr($0, 1, 1) == "+" && body ~ /^[[:space:]]*Withdrawn\./ && cur != "" { wd[cur] = 1; next }
    END {
      for (i in add)  printf "ADDED %s\n", i
      for (i in drop) printf "DROPPED %s\n", i
      for (i in sup)  printf "SUPERSEDED %s\n", i
      for (i in wd)   printf "WITHDRAWN %s\n", i
    }
  ' >"$WORK/ids.txt"
  ADDED="$(awk '$1=="ADDED"{print $2}' "$WORK/ids.txt" | sort -uV)"
  DROPPED="$(awk '$1=="DROPPED"{print $2}' "$WORK/ids.txt" | sort -uV)"
  SUPERSEDED="$(awk '$1=="SUPERSEDED"{print $2}' "$WORK/ids.txt" | sort -uV)"
  WITHDRAWN="$(awk '$1=="WITHDRAWN"{print $2}' "$WORK/ids.txt" | sort -uV)"
fi

# An id on both sides kept its id and changed its sentence: a refinement. On the
# added side only, it is new. On the dropped side only it VANISHED - and R2 says
# an id is permanent, so that is a finding and not a bullet.
set_op() { # set_op -12|-23 <a> <b>
  comm "$1" <(printf '%s\n' "$2" | grep -v '^$' | sort -u) \
            <(printf '%s\n' "$3" | grep -v '^$' | sort -u) | sort -V
}
REFINED="$(set_op -12 "$ADDED" "$DROPPED")"
NEW="$(set_op -23 "$ADDED" "$DROPPED")"
VANISHED="$(set_op -23 "$DROPPED" "$ADDED")"

# One awk, not a pipeline: `set -o pipefail` is on, and a `grep` that matches
# nothing exits 1, which would kill the run on the ordinary case of an empty id
# set. It did, on the first run of this script.
fmt_ids() { printf '%s\n' "$1" | awk 'NF { a = (a == "" ? "`" $0 "`" : a ", `" $0 "`") } END { print a }'; }
row() { # row <label> <ids> <what a measured empty set means here>
  local ids; ids="$(fmt_ids "$2")"
  if [ -n "$ids" ]; then say "| $1 | $ids |"
  else say "| $1 | none — $3 |"; fi
}

# --- report ----------------------------------------------------------------
say "## What this change did to the spec"
say ""
say "| | |"
say "|---|---|"
say "| Base | \`$BASE_LABEL\`${BASE_SHA:+ at \`$BASE_SHA\`} |"
say "| Head | \`${HEAD_SHA:0:12}\` |"
say "| Spec | \`$SPEC_REL\` |"
say ""

say "### Requirements"
say ""
case "$SD_RC" in
  0)
    say "| Movement | Ids |"
    say "|---|---|"
    row "Added" "$NEW" "the diff was read end to end and defines no id that was not there before"
    row "Refined (id kept, sentence changed)" "$REFINED" "no requirement kept its id and changed its wording"
    row "Superseded" "$SUPERSEDED" "nothing gained a \`Superseded by R<n>.\` line"
    row "Withdrawn" "$WITHDRAWN" "nothing gained a \`Withdrawn.\` line"
    say ""
    if [ -n "$(fmt_ids "$VANISHED")" ]; then
      say "> **An id left the file.** $(fmt_ids "$VANISHED") is defined at the base and not at HEAD."
      say "> R2 makes ids permanent and R3 keeps a replaced requirement's original text in place, so"
      say "> this is not a supersession — a superseded requirement keeps its line. Check the diff."
      say ""
    fi
    ;;
  4)
    say "**No requirement moved.** \`$SPEC_REL\` is byte-identical at \`$BASE_LABEL\` and at HEAD."
    say "This is a measured absence of change: both ends were read and compared."
    say ""
    ;;
  5)
    say "**NOT MEASURED — no baseline.** \`$SPEC_REL\` does not exist at \`$BASE_LABEL\`, so it has no"
    say "history to diff against and every line of it is an addition. An empty movement table here"
    say "would read as \"nothing changed\", which is a different and untrue answer."
    say ""
    UNMEASURED=1
    ;;
  6)
    say "**NOT MEASURED — the base ref does not resolve.** \`spec-diff.sh\` refused to fall back to an"
    say "empty diff, and so does this. Pass \`--base REF\` with a ref this clone actually carries;"
    say "a shallow clone is the usual cause."
    say ""
    ;;
  7)
    say "**NOT MEASURED — the diff is over \`spec-diff.sh\`'s cap and was left out whole.** It was not"
    say "truncated: a cut-off diff reads as a complete one. The movement table cannot be derived"
    say "from a diff that was not emitted, so it is absent rather than empty."
    say ""
    UNMEASURED=1
    ;;
esac

# --- contradiction ---------------------------------------------------------
# R33: an intent that contradicts an active requirement STOPS the pipeline, and
# R12 says nothing depending on it merges. A pull request carrying a classified
# contradiction is the single fact a reviewer most needs on the page.
say "### Classified \`contradict\`?"
say ""
if [ ! -d "$CLASS_REL" ]; then
  say "**NOT MEASURED.** There is no classification store at \`$CLASS_REL\`. That is not the same as"
  say "\"no contradiction was recorded\", and it is not reported as one."
  say ""
  UNMEASURED=1
elif [ -z "$BASE_SHA" ]; then
  say "**NOT MEASURED.** The base did not resolve above, so there is no range to read the store over."
  say ""
else
  git diff --name-only "$BASE_SHA" "$HEAD_SHA" -- "$CLASS_REL" >"$WORK/class.txt"
  # Two passes on purpose. The heading asks a yes/no question, and a list of
  # records the reader has to scan for the word `contradict` is not an answer.
  # So the rows are rendered into a buffer first, the verdict is printed, and
  # the buffer follows it.
  : >"$WORK/class.md"
  CHANGED=0
  CONTRADICTS=0
  UNREADABLE=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    CHANGED=$((CHANGED + 1))
    if [ ! -r "$f" ]; then
      # Deleted at HEAD, or unreadable. Either way its classification cannot be
      # read, and "not read" is not "not a contradiction".
      say "- \`$f\` — **NOT MEASURED**: changed in this range and not readable at HEAD." >>"$WORK/class.md"
      UNREADABLE=1
      continue
    fi
    verdict="$(sed -n 's/^Classification:[[:space:]]*//p' "$f" | head -n 1)"
    intent="$(sed -n 's/^Intent:[[:space:]]*//p' "$f" | head -n 1)"
    case "$verdict" in
      contradict)
        CONTRADICTS=$((CONTRADICTS + 1))
        say "- **\`$f\` — \`contradict\`** (intent \`${intent:-unstated}\`). R33 stops the pipeline here," >>"$WORK/class.md"
        say "  and R12 merges nothing that depends on it until somebody rules. This needs a ruling, not a review." >>"$WORK/class.md" ;;
      "")
        UNREADABLE=1
        say "- \`$f\` — **NOT MEASURED**: the record carries no \`Classification:\` line." >>"$WORK/class.md" ;;
      *)
        say "- \`$f\` — \`$verdict\` (intent \`${intent:-unstated}\`)" >>"$WORK/class.md" ;;
    esac
  done <"$WORK/class.txt"

  if [ "$CONTRADICTS" -gt 0 ]; then
    say "**YES — $CONTRADICTS of $CHANGED classification record(s) that changed in this range say \`contradict\`.**"
  elif [ "$UNREADABLE" = 1 ]; then
    say "**NOT MEASURED for at least one record.** $CHANGED record(s) changed in this range and at"
    say "least one could not be read. An unread classification is not a cleared one."
    UNMEASURED=1
  elif [ "$CHANGED" -gt 0 ]; then
    say "**No.** $CHANGED classification record(s) changed in this range; every one was read and none"
    say "says \`contradict\`."
  else
    say "**No.** No file under \`$CLASS_REL\` changed between \`$BASE_SHA\` and HEAD. The store was read"
    say "over the range and is unchanged — a measured absence, not an unread one."
  fi
  if [ -s "$WORK/class.md" ]; then
    say ""
    cat "$WORK/class.md"
  fi
  say ""
fi

# --- check verdicts --------------------------------------------------------
say "### Check verdicts"
say ""
if ! command -v python3 >/dev/null; then
  say "**NOT MEASURED.** \`python3\` is not on PATH, and the result file is JSON."
  say ""
  UNMEASURED=1
elif [ ! -r "$CHECKS" ]; then
  say "**NOT MEASURED.** No readable Stage 5 result at \`$CHECKS\`. Checks that were never run"
  say "are not checks that passed. Run \`run-checks.sh --base <ref> --out $CHECKS\` first."
  say ""
  UNMEASURED=1
elif ! python3 - "$CHECKS" >"$WORK/checks.md" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    r = json.load(fh)

c = r.get("counts", {})
say = print
say("| | |")
say("|---|---|")
say("| Verdict | **%s** (exit %s) |" % (r.get("verdict", "NOT MEASURED"),
                                        r.get("exit_code", "NOT MEASURED")))
for label, key in (("Declared", "declared"), ("Triggered", "triggered"),
                   ("Passed", "passed"), ("Blocking failures", "blocking_failures"),
                   ("Waived", "waived"), ("Advisory failures", "advisory_failures"),
                   ("Not triggered", "not_triggered"),
                   ("Spec units unsatisfied", "spec_units_unsatisfied")):
    say("| %s | %s |" % (label, c.get(key, "NOT MEASURED")))
say("")

bad = [ch for ch in r.get("checks", []) if ch.get("status") not in (None, "pass")]
if bad:
    say("Not passing:")
    say("")
    for ch in bad:
        say("- `%s` — **%s** (%s, exit %s) — %s"
            % (ch.get("id", "?"), ch.get("status", "NOT MEASURED"),
               ch.get("severity", "?"), ch.get("exit_code", "NOT MEASURED"),
               ch.get("why", "")))
    say("")

# The change set is named but CAPPED. One real result file here carried a
# `files` list 150 kB long, and a pull-request comment that long is a comment
# nobody reads. The count is the measurement; the sample is a courtesy, and the
# line says when it is a sample so the reader is never shown a short list that
# looks complete.
files = r.get("change", {}).get("files", [])
LIMIT = 5
shown = ", ".join("`%s`" % f for f in files[:LIMIT]) or "_none listed_"
more = "" if len(files) <= LIMIT else " (first %d of %d shown)" % (LIMIT, len(files))
say("Read from the recorded run over %d changed path(s): %s%s. That run is whatever last "
    "wrote this file — if it is not the run for this pull request, these verdicts are "
    "about a different change."
    % (len(files), shown, more))
PY
then
  say "**NOT MEASURED.** \`$CHECKS\` exists but is not readable as a Stage 5 result — see the error above."
  say ""
  UNMEASURED=1
else
  cat "$WORK/checks.md"
  say ""
fi

# --- the solver probe ------------------------------------------------------
say "### Solver probe"
say ""
if [ ! -r "$PROBE_REL" ]; then
  say "**NOT MEASURED.** \`$PROBE_REL\` is not in this tree, so the 26-case corpus was not run."
  say ""
  UNMEASURED=1
elif ! command -v python3 >/dev/null; then
  say "**NOT MEASURED.** \`python3\` is not on PATH."
  say ""
  UNMEASURED=1
elif ! python3 "$PROBE_REL" >"$WORK/probe.txt"; then
  say "**NOT MEASURED.** \`$PROBE_REL\` did not complete — see the error above. It exits non-zero"
  say "only when the checker it measures is missing, so this is a broken tree, not a bad score."
  say ""
  UNMEASURED=1
else
  PROBE_ROWS="$(grep -E '^  (true|false) (positives|negatives)|^  undecided' "$WORK/probe.txt" || true)"
  if [ -z "$PROBE_ROWS" ]; then
    say "**NOT MEASURED.** The probe ran and exited 0 but printed no counts. An empty score is not a"
    say "perfect one and is not rendered as one."
    say ""
    UNMEASURED=1
  else
    say '```'
    printf '%s\n' "$PROBE_ROWS"
    grep -E '^  (precision|recall)' "$WORK/probe.txt" || true
    say '```'
    say ""
    say "These are gated in \`.github/workflows/checks.yml\` against a dated baseline. The bounds live"
    say "there and are deliberately not restated here — two copies of one measurement drift apart."
    say ""
  fi
fi

# --- footer ----------------------------------------------------------------
say "---"
say ""
say "Rendered by \`pr-spec-comment.sh\` ($VERSION) to stdout. **It posted nothing.**"
say "Posting is a publish, and a publish here needs a checklist and a person:"
say "write \`.claude/productizer/publish-checklist.md\` with \`Command: gh pr comment <n> --body-file -\`"
say "as its first line, then pipe this output into that command yourself."
if [ "$UNMEASURED" = 1 ]; then
  say ""
  say "> **This report is partial.** At least one section above is marked NOT MEASURED."
fi

[ "$UNMEASURED" = 0 ] || exit 5
