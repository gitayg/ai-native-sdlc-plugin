#!/usr/bin/env bash
# stage-status.sh [repo-root]
#
# Every stage of the lifecycle and where it actually stands, read from the
# files. Reporting one stage's result alone is misleading: a green checks stage
# in a repo whose spec was never scaffolded says nothing about the work.
#
# Every state below is derived from something on disk. Where a stage cannot be
# determined it says so - "unknown" is a real answer and is never rendered as
# "not run", because the two lead to different actions.
#
# Exit: 0 always. This reports; it does not gate. Stage 5 gates.
set -euo pipefail

SORT=stage
while [ $# -gt 0 ]; do
  case "$1" in
    --by-status) SORT=status; shift ;;
    --by-stage)  SORT=stage;  shift ;;
    -h|--help)   echo "usage: stage-status.sh [--by-stage|--by-status] [repo-root]"; exit 0 ;;
    *)           break ;;
  esac
done
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "stage-status: no such directory: $ROOT" >&2; exit 2; }

SPEC=".claude/productizer/spec.md"
CONST=".claude/productizer/constitution.md"
BACKLOG=".claude/productizer/backlog.md"
CFG=".claude/productizer/config.json"
CHECKS=".claude/productizer/checks-result.json"

bold=""; dim=""; red=""; amber=""; green=""; reset=""
if [ -t 1 ]; then
  bold=$'\033[1m'; dim=$'\033[2m'; red=$'\033[31m'; amber=$'\033[33m'
  green=$'\033[32m'; reset=$'\033[0m'
fi

# Rows are collected, not printed, so they can be ordered two ways. Stage order
# is the pipeline; status order is what needs you. Neither is a filter - every
# stage appears in both, because a stage hidden by a sort reads as absent.
ROWS=""
row() { # row <id> <name> <state> <detail>
  local rank
  case "$3" in
    blocked)  rank=0 ;;
    waiting)  rank=1 ;;
    unknown)  rank=2 ;;
    "not run") rank=3 ;;
    ok)       rank=4 ;;
    *)        rank=5 ;;
  esac
  # printf -v, not string concat: "\t" inside double quotes is a literal
  # backslash-t, which read -r will not split on.
  local line
  printf -v line '%s\t%s\t%s\t%s\t%s\n' "$rank" "$1" "$2" "$3" "$4"
  ROWS="${ROWS}${line}"
}

emit() {
  local c
  while IFS=$'\t' read -r rank id name state detail; do
    [ -n "$id" ] || continue
    case "$state" in
      blocked) c="$red" ;; waiting) c="$amber" ;;
      ok)      c="$green" ;; *) c="$dim" ;;
    esac
    printf '  %-4s %-13s %s%-9s%s %s\n' "$id" "$name" "$c" "$state" "$reset" "$detail"
  done
}

printf '%sLifecycle status%s  %s\n' "$bold" "$reset" "$(pwd)"
printf '%s%s%s\n' "$dim" "-------------------------------------------------------------" "$reset"

# --- Stage 0 ---------------------------------------------------------------
if [ -f "$CFG" ]; then row 0 Bind ok "$CFG"
else row 0 Bind "not run" "no $CFG - nothing downstream can run"; fi

if [ -f "$SPEC" ]; then
  # The spec template writes requirements as list items - "- **R1** - ...". A
  # pattern anchored on "**R" alone matched none of them and reported a full
  # spec as 0 requirements: a measured zero that was not one. Keep this in step
  # with the same pattern in build-view.sh; two counters for one number
  # disagree the moment someone edits one of them.
  actives=$(grep -cE '^([-*][[:space:]]+)?\*\*R[0-9]+\*\*' "$SPEC" || true)
  row 0a Scaffold ok "$SPEC - $actives requirement(s)"
else
  row 0a Scaffold "not run" "no living spec; Stage 2 has nothing to merge into"
fi

if [ -f "$SPEC" ] && grep -q 'Inferred from' "$SPEC" 2>/dev/null; then
  n=$(grep -c 'Inferred from' "$SPEC" || true)
  row 0c Import waiting "$n inferred requirement(s) awaiting confirmation"
else
  row 0c Import "n/a" "no imported requirements"
fi

if [ -f "$CONST" ]; then
  p=$(grep -cE '^### P[0-9]+' "$CONST" || true)
  [ "$p" -gt 0 ] && row 0d Constitution ok "$p principle(s)" \
                 || row 0d Constitution waiting "file exists, no principles ratified"
else
  row 0d Constitution "not run" "no constitution; intake has no prior gate"
fi

# --- Stage 1 ---------------------------------------------------------------
if [ -f "$BACKLOG" ]; then
  b=$(grep -cE '^\| B[0-9]+' "$BACKLOG" || true)
  row 1 Plan ok "$b backlog item(s)"
else
  row 1 Plan "not run" "no backlog; intents arrive without a queue"
fi

# --- Stage 2 ---------------------------------------------------------------
if [ -f "$SPEC" ]; then
  # An open contradiction blocks everything downstream of it, by design.
  # A row still carrying <angle-bracket> placeholders is template shape, not a
  # live concern. Blocking Stage 2 on one is a false stop, and a gate that
  # fires on nothing gets ignored when it fires on something.
  # grep -c prints its count AND exits 1 when that count is zero, so a naive
  # `|| echo 0` appends a second zero and the test below sees "0\n0".
  con=$(grep -iE '^\| C[0-9]+.*(open|unruled|waiting)' "$SPEC" 2>/dev/null \
        | grep -vc '<[a-z ,]*>' || true)
  con=${con:-0}
  if [ "$con" -gt 0 ]; then row 2 Design blocked "$con open contradiction(s) - nothing merges"
  else row 2 Design ok "no open contradictions"; fi
else
  row 2 Design "not run" "no spec to classify against"
fi

# --- Stage 3, 4 ------------------------------------------------------------
[ -f plan.md ] && row 3 Build ok "plan.md" || row 3 Build "not run" "no plan.md"
if [ -f CLAUDE.md ] && grep -qi 'verification\|how to verify' CLAUDE.md 2>/dev/null; then
  row 4 Test ok "CLAUDE.md declares how to verify"
else
  row 4 Test "not run" "CLAUDE.md does not say how this repo is verified"
fi

# --- Stage 5 --------------------------------------------------------------
if [ -f "$CHECKS" ]; then
  # The result file is the only honest source for this stage. If it will not
  # parse, say so - an unreadable result is not a passing one.
  parsed="$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
cs = d.get("checks", [])
bad = [c for c in cs if c.get("status") not in ("pass", "skipped")]
if bad:
    print("blocked|%d of %d check(s) not passing: %s" % (
        len(bad), len(cs), ", ".join("%s (%s)" % (c["id"], c["status"]) for c in bad)))
else:
    print("ok|%d check(s) passing" % len(cs))
' "$CHECKS" 2>/dev/null || true)"
  if [ -n "$parsed" ]; then
    row 5 Check "${parsed%%|*}" "${parsed#*|}"
  else
    row 5 Check unknown "result file present but would not parse"
  fi
else
  row 5 Check "not run" "no checks-result.json - nothing has been checked"
fi

# --- Stage 6 ---------------------------------------------------------------
# The gate is part of Deploy, not a stage beside it - a separate row meant two
# lines sharing a stage number, which reads as a duplicate.
if [ -x .claude/hooks/production-gate.sh ]; then gate="gate installed"; else gate="UNGATED"; fi
if [ -f REVIEW.md ]; then
  [ "$gate" = "UNGATED" ] && row 6 Deploy waiting "REVIEW.md, but no production gate" \
                          || row 6 Deploy ok "REVIEW.md, $gate"
else
  row 6 Deploy "not run" "no REVIEW.md; $gate"
fi

# --- Stage 7, 5C ----------------------------------------------------------
row 7 Document "unknown" "generated per release; not derivable from the tree"
if [ -x .claude/hooks/publish-gate.sh ]; then row 8 Announce ok "publish gate installed"
else row 8 Announce waiting "no publish gate - publishing is ungated"; fi

# --- Stage 9 ---------------------------------------------------------------
if [ -f ops/bands.yaml ] || [ -f .claude/productizer/bands.yaml ]; then
  row 9 Maintain ok "control bands declared"
else
  row 9 Maintain "not run" "no bands.yaml - production says nothing back"
fi

if [ "$SORT" = status ]; then
  printf '%s' "$ROWS" | sort -s -k1,1n | emit
  order='blocked first, then waiting, unknown, not run, passing'
else
  printf '%s' "$ROWS" | emit
  order='pipeline order'
fi

printf '%s%s%s\n' "$dim" "-------------------------------------------------------------" "$reset"
printf '  %sSorted by %s. Every line is read from a file; "unknown" is not "not run".%s\n' "$dim" "$order" "$reset"
