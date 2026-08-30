#!/usr/bin/env bash
# check-missing-tool.sh [--root DIR] [--fixture DIR] [--version] [--help]
#
# Asserts R13: WHILE A CHECK TOOL NAMED BY THE CONFIGURATION IS ABSENT, THE
# LIFECYCLE SHALL REPORT THAT CHECK AS MISSING RATHER THAN SKIPPED.
#
# The behaviour is in run-checks.sh and was demonstrated by hand. A
# demonstration is not a test. Nothing stopped a refactor turning
# `missing_tool` back into a skip while every run stayed green, because a
# skipped check is invisible: it produces no finding, no failure and no line
# anybody reads. This is the standing case that would go red.
#
# WHAT IT DOES. It copies `fixtures/missing-tool/` into a temporary directory,
# runs run-checks.sh against that copy, and asserts what came back. The fixture
# declares one check whose tool nothing will ever install. The temporary copy
# is the point: the runner writes a result file inside the repository it is
# checking, and pointing it at this repository would make a test of the runner
# a writer to the tree under test.
#
# WHAT IT ASSERTS, AND WHY EACH ONE IS SEPARATE.
#
#   1  the run exits 3 - REFUSED. A missing tool has to stop the stage.
#   2  the human-readable line reads MISSING_TOOL for that check. A machine
#      status nobody sees is half the obligation; R13 says REPORT.
#   3  that line says it was not skipped, in those words.
#   4  the result JSON records `missing_tool` for the check.
#   5  the check is recorded as TRIGGERED, and its status is none of the
#      statuses that would mean it was passed over. This is the assertion that
#      actually catches a regression to skipping: a refactor that dropped the
#      check would leave `not_triggered`, `disabled` or `pass` behind, and each
#      of those reads green.
#   6  it counts as a BLOCKING failure and the verdict is `refused`. A status
#      recorded in a file that does not change the verdict is a skip wearing a
#      different name.
#
# THE PREMISE IS CHECKED FIRST. If the fixture's tool turns out to be present
# on this machine the test proves nothing, so that is exit 2 - could not run -
# and never a pass.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every assertion held
#   1  an assertion failed - the runner no longer reports an absent tool the
#      way R13 requires
#   2  could not run - bad usage, no fixture, no runner, no python3, or a
#      premise that did not hold
#
# WHAT IT PRINTS. One BARE PATH per line for every file examined, relative to
# the repository, which is what the runner parses as coverage. Assertions are
# INDENTED. The runner's own stderr is NOT reproduced: it names the temporary
# directory it ran in, and this output is tailed into a committed result file
# where an absolute path is somebody's home directory published to everyone
# who clones the repo.
set -euo pipefail

VERSION="check-missing-tool 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"

ROOT=""
FIXTURE="$SKILL/fixtures/missing-tool"

die_unmeasured() { printf 'check-missing-tool: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)       [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)     ROOT="${1#--root=}";       shift ;;
    --fixture)    [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*)  FIXTURE="${1#--fixture=}"; shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1" ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1"

# The work tree, never the working directory. --root does not decide what is
# tested - the fixture and the runner are found beside this script, so the test
# is the same one wherever it is invoked from - it decides what the printed
# paths are relative to, so nothing absolute reaches the committed result.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" || ROOT=""
fi
if [ -n "$ROOT" ] && [ -d "$ROOT" ]; then
  ROOT="$(cd "$ROOT" && pwd -P)"
else
  # No work tree: an installed plugin is not a repository. Paths are then
  # printed relative to the skill directory, which is still not absolute.
  ROOT="$SKILL"
fi

RUNNER="$HERE/run-checks.sh"
[ -f "$RUNNER" ] || die_unmeasured "no run-checks.sh beside this script; there is nothing to test"
[ -d "$FIXTURE" ] || die_unmeasured "no fixture directory; the standing case is missing, which is unmeasured and not a pass"
[ -f "$FIXTURE/checks.yaml" ] || die_unmeasured "the fixture has no checks.yaml"
[ -f "$FIXTURE/changed.txt" ] || die_unmeasured "the fixture has no changed.txt"
command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the result could not be read"

rel() {
  case "$1" in
    "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
    *)         printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;;
  esac
}

# The tool the fixture names must really be absent, or this run proves nothing.
DECLARED_TOOL="$(sed -n 's/^ *requires: *\[\([^]]*\)\].*/\1/p' "$FIXTURE/checks.yaml" | head -1 | tr -d ' ')"
[ -n "$DECLARED_TOOL" ] || die_unmeasured "the fixture declares no tool to be absent"
if command -v "$DECLARED_TOOL" >/dev/null 2>&1; then
  die_unmeasured "the fixture's declared tool is installed on this machine, so an absent tool was never tested. The premise failed; this is unmeasured, not a pass"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SANDBOX="$TMP/repo"
mkdir -p "$SANDBOX"
cp "$FIXTURE/checks.yaml" "$FIXTURE/changed.txt" "$SANDBOX/"

rel "$RUNNER"
rel "$FIXTURE/checks.yaml"
rel "$FIXTURE/changed.txt"

RC=0
bash "$RUNNER" --config "$SANDBOX/checks.yaml" --root "$SANDBOX" \
  --changed "$SANDBOX/changed.txt" --out "$TMP/result.json" \
  > "$TMP/runner.out" 2> "$TMP/runner.err" || RC=$?

cat > "$TMP/assert.py" <<'PY'
"""Read what the runner reported and say whether R13 still holds.

stdout: one indented line per assertion. Exit 0 all held, 1 one did not,
2 the result could not be read at all - which is never reported as a pass,
because a result nobody could read is not a result that said missing_tool.
"""
import json
import re
import sys

result_path, err_path, rc_txt, check_id, tool = sys.argv[1:6]
out = sys.stdout
ok = True


def say(held, text):
    global ok
    if not held:
        ok = False
    out.write("  %s %s\n" % ("held:" if held else "FINDING: did not hold -", text))


try:
    with open(result_path, errors="replace") as fh:
        doc = json.load(fh)
except (OSError, ValueError) as exc:
    out.write("  the runner's result could not be read: %s\n" % exc.__class__.__name__)
    out.write("  assertions evaluated: 0 of 6. Unmeasured, not a pass.\n")
    sys.exit(2)

try:
    with open(err_path, errors="replace") as fh:
        err = fh.read()
except OSError:
    err = ""

say(rc_txt == "3",
    "the run exits 3 (refused); it exited %s" % rc_txt)

# The reported line, not the whole stream: the stream names the temporary
# directory the run happened in and must not be echoed anywhere near a
# committed file.
line = ""
for ln in err.splitlines():
    if re.match(r"^\s*MISSING_TOOL\s+%s\b" % re.escape(check_id), ln):
        line = ln
        break
say(bool(line), "the reported line reads MISSING_TOOL for `%s`" % check_id)

detail = ""
for ln in err.splitlines():
    if "not installed" in ln and tool in ln:
        detail = ln
        break
say("Not skipped" in detail,
    "that report says in words that the check was not skipped")

rows = {c.get("id"): c for c in doc.get("checks") or []}
row = rows.get(check_id)
if row is None:
    say(False, "the result records a row for `%s` at all" % check_id)
    out.write("  assertions that could be evaluated: 3 of 6.\n")
    sys.exit(1)

say(row.get("status") == "missing_tool",
    "the result records status `missing_tool`; it records %r" % (row.get("status"),))

SKIP_LIKE = {"pass", "disabled", "not_triggered", "skipped", "skip"}
say(row.get("triggered") is True and row.get("status") not in SKIP_LIKE,
    "the check is triggered and its status is none of %s - the statuses a skip "
    "would leave behind" % ", ".join(sorted(SKIP_LIKE)))

counts = doc.get("counts") or {}
say(doc.get("verdict") == "refused" and (counts.get("blocking_failures") or 0) >= 1,
    "it counts as a blocking failure and the verdict is `refused`; verdict %r, "
    "blocking failures %r" % (doc.get("verdict"), counts.get("blocking_failures")))

out.write("  assertions evaluated: 6, upheld: %d\n" % (6 if ok else 0))
sys.exit(0 if ok else 1)
PY

ARC=0
python3 "$TMP/assert.py" "$TMP/result.json" "$TMP/runner.err" "$RC" ghost "$DECLARED_TOOL" || ARC=$?

case "$ARC" in
  0) printf '  R13 satisfied: an absent tool is reported as missing and refuses the stage; it is not skipped.\n'; exit 0 ;;
  1) printf '  R13 not satisfied: see the findings above. An absent tool is no longer reported the way R13 requires.\n'; exit 1 ;;
  *) die_unmeasured "the assertions could not be evaluated; unmeasured, not a pass" ;;
esac
