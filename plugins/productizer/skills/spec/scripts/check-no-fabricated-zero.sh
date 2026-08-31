#!/usr/bin/env bash
# check-no-fabricated-zero.sh [--root DIR] [--fixture DIR] [--version] [--help]
#
# Asserts R26: IF A VALUE COULD NOT BE MEASURED, THEN THE LIFECYCLE SHALL NOT
# RECORD IT AS ZERO. Enforces P1 - a value that was not measured is never
# recorded as a measurement.
#
# WHY THIS EXISTS SEPARATELY FROM R25. R25 - report it as unmeasured - is
# already asserted, and it is a different claim. A run can print
# `spec coverage: UNMEASURED` on the terminal and, in the same breath, write
# `units_total: 0` into the result file that every downstream reader parses.
# R25 passes on that run. R26 fails on it, and nobody notices, because the
# fabricated zero is the one failure in this product that is invisible: a month
# later it reads exactly like a real zero. So this check reads THE RESULT FILE
# and never the printed line. The printed line is R25's evidence, not R26's.
#
# WHAT IT DOES. It copies `fixtures/fabricated-zero/` into a temporary
# directory and runs run-checks.sh against that copy. The temporary copy is the
# point: the runner writes a result file inside the repository it is checking,
# and pointing it at this repository would make a test of the runner a writer
# to the tree under test.
#
# The fixture makes TWO values genuinely unmeasurable in one run, because the
# runner records them in two different shapes and R26 has to hold for both:
#
#   THE DENOMINATOR. `policy.spec` names a file that is not there, so the count
#   of active requirements cannot be derived. Its fields must come back NULL.
#
#   ONE CHECK'S OWN COVERAGE. The declared tool is absent, so the check never
#   ran. Its coverage block must be ABSENT from the row.
#
# ABSENT, NULL AND ZERO ARE THREE STATES, and collapsing them is the whole
# defect. Every field below is classified into one of them and the
# classification is printed, so a failure says which state the field is in
# rather than only that something was wrong.
#
# WHAT IT ASSERTS, AND WHY EACH ONE IS SEPARATE.
#
#   1  `spec_coverage.units_total` is null. This is the field a reader divides
#      by; 0 here makes every "n of m covered" line downstream read 0 of 0.
#   2  `spec_coverage.counts` is null, not an object of zeros. An object whose
#      every value is 0 is the most convincing fabrication available: it has
#      the shape of a real measurement.
#   3  `spec_coverage.units` is null, not an empty list. A list of length 0 is
#      a recorded count of zero requirements.
#   4  `spec_coverage.satisfied` is null, not a boolean. `true` over an
#      underived denominator is the hollow green this whole stage refuses.
#   5  `counts.spec_units_unsatisfied` is null. Separate from 1-4 because it
#      sits in a different object, written by different code, and a fix to one
#      does not fix the other.
#   6  the unmeasurable check's `coverage` key is ABSENT from its row - not
#      present carrying `observed.covered: 0`. Asserted as absence, not as
#      null, because that is what the runner actually does and a check that
#      accepted either would not notice the two being swapped.
#   7  a sweep over EVERY check row whose status means it could not run: none
#      of them records a coverage count. Assertion 6 names the one row this
#      fixture creates; this one holds for rows a later runner adds.
#
# THE PREMISES ARE CHECKED FIRST AND ARE NOT ASSERTIONS. If the fixture's tool
# turns out to be installed, or its absent spec turns out to be readable, then
# nothing was unmeasurable and R26 was never exercised. That is exit 2 - could
# not run - and never a pass.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every assertion held
#   1  an assertion failed - the runner records a fabricated zero where a value
#      could not be measured
#   2  could not run - bad usage, no fixture, no runner, no python3, an
#      unreadable result, or a premise that did not hold
#
# WHAT IT PRINTS. One BARE PATH per line for every file examined, relative to
# the repository, which is what the runner parses as coverage. Classifications
# and assertions are INDENTED. The runner's own stderr is NOT reproduced: it
# names the temporary directory it ran in, and this output is tailed into a
# committed result file where an absolute path is somebody's home directory
# published to everyone who clones the repo.
set -euo pipefail

VERSION="check-no-fabricated-zero 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname "$HERE")"

ROOT=""
FIXTURE="$SKILL/fixtures/fabricated-zero"

die_unmeasured() { printf 'check-no-fabricated-zero: %s\n' "$1" >&2; exit 2; }

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

# PREMISE ONE. The tool the fixture names must really be absent, or the check
# ran, examined something, and its coverage was measurable after all.
DECLARED_TOOL="$(sed -n 's/^ *requires: *\[\([^]]*\)\].*/\1/p' "$FIXTURE/checks.yaml" | head -1 | tr -d ' ')"
[ -n "$DECLARED_TOOL" ] || die_unmeasured "the fixture declares no tool to be absent"
if command -v "$DECLARED_TOOL" >/dev/null 2>&1; then
  die_unmeasured "the fixture's declared tool is installed on this machine, so a check that could not run was never tested. The premise failed; this is unmeasured, not a pass"
fi

# PREMISE TWO. The spec path the fixture names must really be missing from the
# sandbox, or the denominator was derivable and no unmeasured count existed.
DECLARED_SPEC="$(sed -n 's/^ *spec: *\([^ #][^#]*\)$/\1/p' "$FIXTURE/checks.yaml" | head -1 | sed 's/[[:space:]]*$//')"
[ -n "$DECLARED_SPEC" ] || die_unmeasured "the fixture names no spec path, so the denominator's premise cannot be established"
case "$DECLARED_SPEC" in
  /*) die_unmeasured "the fixture's spec path is absolute; it would name a different file on every machine" ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SANDBOX="$TMP/repo"
mkdir -p "$SANDBOX"
cp "$FIXTURE/checks.yaml" "$FIXTURE/changed.txt" "$SANDBOX/"
if [ -e "$SANDBOX/$DECLARED_SPEC" ]; then
  die_unmeasured "the fixture's spec path exists in the sandbox, so the coverage denominator was derivable and an unmeasured denominator was never tested. The premise failed; this is unmeasured, not a pass"
fi

rel "$RUNNER"
rel "$FIXTURE/checks.yaml"
rel "$FIXTURE/changed.txt"

RC=0
bash "$RUNNER" --config "$SANDBOX/checks.yaml" --root "$SANDBOX" \
  --changed "$SANDBOX/changed.txt" --out "$TMP/result.json" \
  > "$TMP/runner.out" 2> "$TMP/runner.err" || RC=$?

cat > "$TMP/assert.py" <<'PY'
"""Read what the runner recorded and say whether R26 still holds.

Reads the RESULT FILE. The printed stream is read only to report, without
asserting, whether R25's half is in the state that makes the two requirements
separable - which is the whole reason R26 needs its own check.

stdout: one indented line per classification and per assertion. Exit 0 all
held, 1 one did not, 2 the result could not be read or a premise did not hold -
neither of which is ever reported as a pass.
"""
import json
import sys

result_path, err_path, check_id = sys.argv[1:4]
out = sys.stdout
ok = True

UPHELD = 0
EVALUATED = 0
# The statuses that mean the check reached no verdict of its own. A row in any
# of these examined nothing measurable, so a recorded coverage count on it is
# a number nobody produced.
VOID_RUN = {"missing_tool", "timeout", "no_version", "refused", "unmapped_exit"}

MISSING = object()


def classify(container, key):
    """-> (state, value). The three states R26 is about, told apart.

    absent      the key is not in the object at all
    null        the key is present and holds null
    zero        the key is present and holds 0, [], {} or an all-zero mapping
    value       anything else, printed so a wrong non-zero is still visible
    """
    if not isinstance(container, dict) or key not in container:
        return "absent", MISSING
    v = container[key]
    if v is None:
        return "null", v
    if v is True or v is False:
        return "value", v
    if isinstance(v, int) and v == 0:
        return "zero", v
    if isinstance(v, (list, dict)) and len(v) == 0:
        return "zero", v
    if isinstance(v, dict) and v and all(x == 0 for x in v.values()):
        return "zero", v
    return "value", v


def show(label, state, value):
    shown = "-" if value is MISSING else json.dumps(value)[:70]
    out.write("  %-38s state=%-6s %s\n" % (label, state, shown))


def say(held, text):
    # UPHELD IS COUNTED, NOT DERIVED FROM `ok`. It used to print `7 if ok else 0`,
    # which reported nothing upheld the moment one assertion failed - six lines
    # saying `held:` above a total saying zero held. That is a summary that
    # disagrees with the evidence directly above it, in the one check that
    # exists to assert P1. Each call now increments its own counter.
    global ok, UPHELD, EVALUATED
    EVALUATED += 1
    if held:
        UPHELD += 1
    else:
        ok = False
    out.write("  %s %s\n" % ("held:" if held else "FINDING: did not hold -", text))


def premise_failed(text):
    out.write("  PREMISE did not hold - %s\n" % text)
    out.write("  R26 was not exercised. Unmeasured, not a pass.\n")
    sys.exit(2)


try:
    with open(result_path, errors="replace") as fh:
        doc = json.load(fh)
except (OSError, ValueError) as exc:
    out.write("  the runner's result could not be read: %s\n" % exc.__class__.__name__)
    out.write("  assertions evaluated: 0 of 7. Unmeasured, not a pass.\n")
    sys.exit(2)

try:
    with open(err_path, errors="replace") as fh:
        err = fh.read()
except OSError:
    err = ""

sc = doc.get("spec_coverage")
if not isinstance(sc, dict):
    premise_failed("the result carries no `spec_coverage` object, so no denominator was reported")
if sc.get("status") == "measured":
    premise_failed("the coverage denominator came back `measured`, so nothing about it was "
                   "unmeasurable and there was no unmeasured value to fabricate")

rows = {c.get("id"): c for c in doc.get("checks") or []}
row = rows.get(check_id)
if row is None:
    premise_failed("the result records no row for `%s`, so the unmeasurable check never ran"
                   % check_id)
if row.get("status") not in VOID_RUN:
    premise_failed("`%s` came back %r, which is a verdict of its own; the check measured "
                   "something and its coverage was not unmeasurable"
                   % (check_id, row.get("status")))

out.write("  premises held: the denominator is %r (not measured) and `%s` is %r (no verdict).\n"
          % (sc.get("status"), check_id, row.get("status")))

# What R25 did with the same run, reported and NOT asserted. If this says the
# printed line reads UNMEASURED while an assertion below fails, that is the
# split: R25 satisfied and R26 violated on one run.
r25 = any(ln.startswith("spec coverage: UNMEASURED") for ln in err.splitlines())
out.write("  note (R25, not asserted here): the printed line %s\n"
          % ("reads UNMEASURED" if r25 else "does NOT read UNMEASURED"))

counts = doc.get("counts") if isinstance(doc.get("counts"), dict) else {}

out.write("  three-state classification of every field that would carry an unmeasured count:\n")
fields = [
    ("spec_coverage.units_total", sc, "units_total", "null"),
    ("spec_coverage.counts", sc, "counts", "null"),
    ("spec_coverage.units", sc, "units", "null"),
    ("spec_coverage.satisfied", sc, "satisfied", "null"),
    ("counts.spec_units_unsatisfied", counts, "spec_units_unsatisfied", "null"),
    ("checks[%s].coverage" % check_id, row, "coverage", "absent"),
]
seen = {}
for label, container, key, want in fields:
    state, value = classify(container, key)
    seen[label] = state
    show(label, state, value)

for label, _c, _k, want in fields:
    state = seen[label]
    say(state == want,
        "%s is %s, the state for a value nobody could measure; it is %s"
        % (label, want, state))

# Assertion 7: the same rule over every row a later runner might add, not only
# the one this fixture creates.
offenders = []
for c in doc.get("checks") or []:
    if c.get("status") not in VOID_RUN:
        continue
    cov = c.get("coverage")
    if not isinstance(cov, dict):
        continue
    obs = cov.get("observed") or {}
    offenders.append("%s records covered=%r" % (c.get("id"), obs.get("covered")))
say(not offenders,
    "no check that reached no verdict records a coverage count%s"
    % ("" if not offenders else "; offenders: " + ", ".join(offenders)))

out.write("  assertions evaluated: %d, upheld: %d\n" % (EVALUATED, UPHELD))
sys.exit(0 if ok else 1)
PY

ARC=0
python3 "$TMP/assert.py" "$TMP/result.json" "$TMP/runner.err" unmeasurable || ARC=$?

case "$RC" in
  3) : ;;
  *) printf '  note: the run exited %s. R26 constrains what was recorded, not the exit code; the exit code is R13 and R15 territory.\n' "$RC" ;;
esac

case "$ARC" in
  0) printf '  R26 satisfied: a value that could not be measured is recorded as absent or null, never as zero.\n'; exit 0 ;;
  1) printf '  R26 not satisfied: see the findings above. A value nobody could measure has been recorded as zero, which a month from now reads exactly like a real zero.\n'; exit 1 ;;
  *) die_unmeasured "the assertions could not be evaluated; unmeasured, not a pass" ;;
esac
