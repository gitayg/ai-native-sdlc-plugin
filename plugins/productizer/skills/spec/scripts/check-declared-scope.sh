#!/usr/bin/env bash
# check-declared-scope.sh [--root DIR] [--fixture DIR] [--version] [--help]
#
# Asserts two requirements about DECLARED SCOPE, separately.
#
#   R5   EVERY CHECK SHALL DECLARE WHAT IT MUST HAVE EXAMINED FOR ITS PASS TO
#        COUNT.
#   R15  IF A CHECK EXITS ZERO HAVING EXAMINED LESS THAN IT DECLARED, THEN THE
#        LIFECYCLE SHALL REPORT IT AS HOLLOW AND TREAT IT AS A FAILURE.
#
# R15's behaviour is in run-checks.sh and its acceptance row says it was proven
# on a stub and on real semgrep. That is a DEMONSTRATION, NOT A TEST: nothing
# stopped a refactor turning the hollow refusal back into a pass while every
# run stayed green, because a hollow pass is the quietest failure there is -
# exit 0, no finding, no line anyone reads. R5 had no check at all, and it is
# the requirement that makes R15 mean anything: a check with no declared scope
# cannot be hollow, because there is nothing for it to fall short of.
#
# WHAT IT DOES. It copies `fixtures/declared-scope/` into a temporary directory
# and runs run-checks.sh against that copy TWICE:
#
#   1. against `checks.yaml`, which declares two checks differing in exactly
#      one thing - how many paths the tool prints. `hollow-shortfall` prints
#      one while declaring a minimum of two; `honest-pass` prints both. Same
#      tool, same exit code, same pattern, same minimum.
#   2. against `no-coverage.yaml`, whose single check is `honest-pass` with
#      the `coverage:` block deleted and nothing else changed.
#
# The temporary copy is the point: the runner writes a result file inside the
# repository it is checking, and pointing it at this repository would make a
# test of the runner a writer to the tree under test.
#
# WHAT IT ASSERTS, AND WHY EACH ONE IS SEPARATE. A single boolean over ten
# facts says only that something broke.
#
#   R15
#   1  the run's EXIT CODE is 3 - refused. This is the assertion that matters:
#      a `hollow` string written into a JSON file over a run that still exits 0
#      is a skip wearing a different name.
#   2  the result records status `hollow` for the shortfall check.
#   3  the recorded coverage says it FELL SHORT - not satisfied, and fewer
#      examined than the declared minimum. A status without the count behind
#      it cannot be told from a status somebody hardcoded.
#   4  the human-readable report line reads HOLLOW for that check. A machine
#      status nobody sees is half the obligation; R15 says REPORT.
#   5  it counts as a BLOCKING failure and the verdict is `refused`.
#
#   R5
#   6  a config whose check declares no `coverage` is REFUSED AT LOAD, exit 2.
#      Measured, not assumed: the runner does not warn, and does not default
#      the missing declaration to a minimum of zero.
#   7  that refusal NAMES the check and says it declares no `coverage`.
#   8  NO RESULT FILE IS WRITTEN for that config. This is the load-bearing
#      half - an undeclared check leaves behind no green document at all for a
#      later stage to read as a pass.
#   9  a declaration that WAS made survives into the result: the passing
#      check's row carries the minimum and the must_cover it was held to, so
#      a reader can see what its pass was worth.
#
#   THE MIRROR IMAGE
#  10  a check that exits zero having examined EVERYTHING it declared still
#      PASSES, with its coverage recorded satisfied. Deleting a real pass is
#      the same bug inverted, and a coverage rule that fails honest work is a
#      coverage rule somebody switches off.
#
# THE PREMISES ARE CHECKED FIRST, and a premise that did not hold is exit 2 -
# could not run - never a pass. If the shortfall check did not exit ZERO, R15's
# antecedent never fired and the case was never tested. Same for the honest
# check: if it did not exit zero, the mirror image is untested and a green here
# would be a lie.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every assertion held
#   1  an assertion failed - the runner no longer treats declared scope the way
#      R5 and R15 require
#   2  could not run - bad usage, no fixture, no runner, no python3, an
#      unreadable result, or a premise that did not hold
#
# WHAT IT PRINTS. One BARE PATH per line for every file examined, relative to
# the repository, which is what the runner parses as coverage. Assertions are
# INDENTED. The runner's own stderr is NOT reproduced: it names the temporary
# directory it ran in, and this output is tailed into a committed result file
# where an absolute path is somebody's home directory published to everyone who
# clones the repo.
set -euo pipefail

VERSION="check-declared-scope 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(dirname "$HERE")"

ROOT=""
FIXTURE="$SKILL/fixtures/declared-scope"

die_unmeasured() { printf 'check-declared-scope: %s\n' "$1" >&2; exit 2; }

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

# THE WORK TREE, NEVER THE WORKING DIRECTORY, and the work tree holding THIS
# SCRIPT rather than the one holding the caller's shell - so the answer does
# not change with where the command was typed. --root does not decide what is
# tested; the fixture and the runner are found beside this script. It decides
# only what the printed paths are relative to, so nothing absolute reaches the
# committed result.
if [ -z "$ROOT" ] && command -v git >/dev/null 2>&1; then
  ROOT="$(git -C "$HERE" rev-parse --show-toplevel)" || ROOT=""
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
# Canonicalised so no `..` segment survives into a printed path. A path the
# runner cannot match is coverage the runner does not count.
FIXTURE="$(cd "$FIXTURE" && pwd -P)"
for f in checks.yaml changed.txt no-coverage.yaml; do
  [ -f "$FIXTURE/$f" ] || die_unmeasured "the fixture has no $f; half the case is missing, which is unmeasured and not a pass"
done
command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the result could not be read"

rel() {
  case "$1" in
    "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
    *)         printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SANDBOX="$TMP/repo"
mkdir -p "$SANDBOX"
cp "$FIXTURE/checks.yaml" "$FIXTURE/changed.txt" "$FIXTURE/no-coverage.yaml" "$SANDBOX/"

rel "$RUNNER"
rel "$FIXTURE/checks.yaml"
rel "$FIXTURE/changed.txt"
rel "$FIXTURE/no-coverage.yaml"

# Run 1: the declared-scope cases. Expected to refuse over `hollow-shortfall`
# while `honest-pass` passes in the same run.
RC=0
bash "$RUNNER" --config "$SANDBOX/checks.yaml" --root "$SANDBOX" \
  --changed "$SANDBOX/changed.txt" --out "$TMP/result.json" \
  > "$TMP/runner.out" 2> "$TMP/runner.err" || RC=$?

# Run 2: the undeclared check. The --out path is named so that its ABSENCE
# afterwards is evidence rather than an untested guess.
NC_RC=0
bash "$RUNNER" --config "$SANDBOX/no-coverage.yaml" --root "$SANDBOX" \
  --changed "$SANDBOX/changed.txt" --out "$TMP/nc-result.json" \
  > "$TMP/nc.out" 2> "$TMP/nc.err" || NC_RC=$?

NC_WROTE=absent
[ -f "$TMP/nc-result.json" ] && NC_WROTE=present

cat > "$TMP/assert.py" <<'PY'
"""Read what the runner reported and say whether R5 and R15 still hold.

stdout: one indented line per assertion. Exit 0 all held, 1 at least one did
not, 2 the case could not be evaluated - an unreadable result or a premise
that did not hold, which is never reported as a pass.
"""
import json
import re
import sys

(result_path, err_path, rc_txt, nc_err_path, nc_rc_txt, nc_wrote,
 hollow_id, pass_id, nc_id) = sys.argv[1:10]

out = sys.stdout
held = 0
failed = 0


def say(ok, text):
    """One line, one fact. `upheld` is counted here and nowhere else, so the
    summary cannot disagree with the lines above it."""
    global held, failed
    if ok:
        held += 1
        out.write("  held: %s\n" % text)
    else:
        failed += 1
        out.write("  FINDING: did not hold - %s\n" % text)


def unmeasured(text, n):
    out.write("  %s\n" % text)
    out.write("  assertions evaluated: %d of 10. Unmeasured, not a pass.\n" % n)
    sys.exit(2)


try:
    with open(result_path, errors="replace") as fh:
        doc = json.load(fh)
except (OSError, ValueError) as exc:
    unmeasured("the runner's result could not be read: %s" % exc.__class__.__name__, 0)

def slurp(path):
    try:
        with open(path, errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


err = slurp(err_path)
nc_err = slurp(nc_err_path)

rows = {c.get("id"): c for c in doc.get("checks") or []}

# --- premises ------------------------------------------------------------
# R15's antecedent is "exits zero". If either check did not exit zero, the
# case it stands for was never run, and a green here would be a claim about
# something that did not happen.
hollow_row = rows.get(hollow_id)
pass_row = rows.get(pass_id)
if hollow_row is None or pass_row is None:
    unmeasured("the result has no row for `%s` and/or `%s`, so neither case ran"
               % (hollow_id, pass_id), 0)
for rid, row in ((hollow_id, hollow_row), (pass_id, pass_row)):
    if row.get("triggered") is not True:
        unmeasured("`%s` was not triggered, so nothing was measured about it" % rid, 0)
    if row.get("exit_code") != 0:
        unmeasured("`%s` exited %r, not 0. R15 is about a check that exits ZERO; "
                   "with a non-zero exit its antecedent never fired and this case "
                   "was never tested" % (rid, row.get("exit_code")), 0)

# --- R15 -----------------------------------------------------------------
say(rc_txt == "3",
    "the run exits 3 (refused) over the shortfall; it exited %s. A `hollow` "
    "recorded over a run that still exits 0 changes nothing" % rc_txt)

say(hollow_row.get("status") == "hollow",
    "the result records status `hollow` for `%s`; it records %r"
    % (hollow_id, hollow_row.get("status")))

cov = hollow_row.get("coverage") or {}
req = (cov.get("required") or {}).get("min_covered")
obs = (cov.get("observed") or {}).get("covered")
say(cov.get("satisfied") is False
    and isinstance(req, int) and isinstance(obs, int) and obs < req,
    "the recorded coverage says it fell short: satisfied=%r, examined %r against "
    "a declared minimum of %r" % (cov.get("satisfied"), obs, req))

line = ""
for ln in err.splitlines():
    if re.match(r"^\s*HOLLOW\s+%s\b" % re.escape(hollow_id), ln):
        line = ln
        break
say(bool(line), "the reported line reads HOLLOW for `%s`" % hollow_id)

counts = doc.get("counts") or {}
say(doc.get("verdict") == "refused" and (counts.get("blocking_failures") or 0) >= 1,
    "it counts as a blocking failure and the verdict is `refused`; verdict %r, "
    "blocking failures %r" % (doc.get("verdict"), counts.get("blocking_failures")))

# --- R5 ------------------------------------------------------------------
say(nc_rc_txt == "2",
    "a check declaring no `coverage` is refused at load with exit 2 (bad "
    "config); the runner exited %s. 0 would be a silent acceptance and 3 would "
    "mean it loaded the check and ran it" % nc_rc_txt)

named = [ln for ln in nc_err.splitlines()
         if nc_id in ln and "coverage" in ln]
say(bool(named),
    "the refusal names `%s` and says it declares no `coverage`" % nc_id)

say(nc_wrote == "absent",
    "no result file was written for the undeclared config (it was %s). An "
    "undeclared check leaves no green document behind for a later stage to "
    "read as a pass" % nc_wrote)

preq = (pass_row.get("coverage") or {}).get("required") or {}
say(preq.get("min_covered") == 2 and preq.get("must_cover") == "all_triggering",
    "the declaration a check DID make survives into its row: min_covered=%r, "
    "must_cover=%r - a reader can see what that pass was worth"
    % (preq.get("min_covered"), preq.get("must_cover")))

# --- the mirror image ----------------------------------------------------
pcov = pass_row.get("coverage") or {}
say(pass_row.get("status") == "pass" and pcov.get("satisfied") is True,
    "a check that exits zero having examined everything it declared still "
    "PASSES; `%s` recorded status %r with coverage satisfied=%r"
    % (pass_id, pass_row.get("status"), pcov.get("satisfied")))

out.write("  assertions evaluated: %d, upheld: %d, failed: %d\n"
          % (held + failed, held, failed))
sys.exit(0 if failed == 0 else 1)
PY

ARC=0
python3 "$TMP/assert.py" "$TMP/result.json" "$TMP/runner.err" "$RC" \
  "$TMP/nc.err" "$NC_RC" "$NC_WROTE" \
  hollow-shortfall honest-pass undeclared-scope || ARC=$?

case "$ARC" in
  0) printf '  R5 and R15 satisfied: an undeclared scope is refused at load, and a check that exits zero having examined less than it declared is reported hollow and refuses the stage - while one that examined everything it declared still passes.\n'; exit 0 ;;
  1) printf '  R5 and/or R15 not satisfied: see the findings above. Declared scope is no longer enforced the way those requirements require.\n'; exit 1 ;;
  *) die_unmeasured "the assertions could not be evaluated; unmeasured, not a pass" ;;
esac
