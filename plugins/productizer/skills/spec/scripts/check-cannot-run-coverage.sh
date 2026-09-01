#!/usr/bin/env bash
# check-cannot-run-coverage.sh [--root DIR] [--fixture DIR] [--runner PATH] [--version] [--help]
#
# A CHECK THAT REACHED NO VERDICT MUST RECORD NO COVERAGE COUNT.
#
# R26 and P1. This is the sibling of `no-fabricated-zero`, and it exists because
# that check's seventh assertion - sweep every cannot-run row for a recorded
# coverage count - had been sweeping an EMPTY SET since the day it was written.
# Its fixture produces only a `missing_tool` row, and `missing_tool` is the one
# status that never carried a coverage block. The assertion was correct and had
# never once seen the thing it was looking for.
#
# Measured, not argued: on the runner before this fixture existed, four of the
# five cannot-run statuses recorded `covered: 0`.
#
#   timeout        a scanner killed at its limit, before it printed anything
#   no_version     a tool that could not say what it was
#   refused        a command the runner would not run
#   unmapped_exit  a code the check's own map does not cover
#   missing_tool   the only clean one
#
# A killed scanner printed nothing. Nothing is not zero. A month later that 0
# reads exactly like a real one, and nobody can tell which they are looking at.
#
# WHAT IT ASSERTS. Two things, separately.
#
#   1. No row whose status means "no verdict" carries a `coverage` key at all.
#      Absent, not null and not zero - matching what the runner already does for
#      `missing_tool`, so no third convention is invented.
#   2. A check that RAN and genuinely covered nothing still records its zero.
#      That is a measurement and deleting it would be the same bug inverted.
#      The fixture carries such a check specifically so this cannot regress.
#
# THE PREMISE IS GUARDED, AND IT IS THE POINT. The fixture must actually produce
# a cannot-run row by a mechanism OTHER than an absent tool - otherwise this is
# just the existing fixture again and the empty-set problem is unfixed. If every
# cannot-run row is a `missing_tool`, or there is no cannot-run row at all, the
# case was never tested: exit 2, unmeasured, never a pass.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  no cannot-run row records coverage, and the measured zero survived
#   1  a check that reached no verdict recorded a coverage count
#   2  could not run - no fixture, no runner, an unreadable result, or a premise
#      that did not hold
#
# WHAT IT PRINTS. One BARE repo-relative path per file examined, which is what
# the runner parses as coverage. Findings and notes are INDENTED. Nothing
# absolute is printed: this text is tailed into a committed result file.
set -euo pipefail

VERSION="check-cannot-run-coverage 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=""; FIXTURE=""; RUNNER=""

die_unmeasured() { printf 'check-cannot-run-coverage: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)      [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)    ROOT="${1#--root=}";       shift ;;
    --fixture)   [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*) FIXTURE="${1#--fixture=}"; shift ;;
    --runner)    [ "$#" -ge 2 ] || die_unmeasured "--runner needs a path";  RUNNER="$2";  shift 2 ;;
    --runner=*)  RUNNER="${1#--runner=}";   shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1."

[ -n "$FIXTURE" ] || FIXTURE="$HERE/../fixtures/timeout-zero"
[ -d "$FIXTURE" ] || die_unmeasured "no fixture directory; the standing case is missing, which is unmeasured and not a pass"
[ -n "$RUNNER" ]  || RUNNER="$HERE/run-checks.sh"
[ -f "$RUNNER" ]  || die_unmeasured "no runner to drive; nothing was measured"
# Canonicalise both. Without this a default fixture path carries its `..`
# segment into the coverage lines, and the runner parses those lines as the
# files this check examined - a path it cannot match is a path it counts as
# uncovered.
FIXTURE="$(cd "$FIXTURE" && pwd -P)"
RUNNER="$(cd "$(dirname "$RUNNER")" && pwd -P)/$(basename "$RUNNER")"
command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the result could not be read"

rel() {
  case "$1" in
    "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
    *)         printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;;
  esac
}
if [ -z "$ROOT" ]; then ROOT="$(git rev-parse --show-toplevel)" || ROOT=""; fi
[ -z "$ROOT" ] || ROOT="$(cd "$ROOT" && pwd -P)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rel "$RUNNER"
rel "$FIXTURE/checks.yaml"
rel "$FIXTURE/changed.txt"

# The runner is EXPECTED to refuse here - the fixture contains a check that
# cannot reach a verdict, and refusing is the correct response to that. Its exit
# code is not the thing under test; what it RECORDED is.
bash "$RUNNER" --config "$FIXTURE/checks.yaml" --root "$FIXTURE" \
  --changed "$FIXTURE/changed.txt" --out "$TMP/res.json" > "$TMP/out" 2> "$TMP/err" || :
[ -s "$TMP/res.json" ] || die_unmeasured "the runner wrote no result, so nothing about what it records was measured"

python3 - "$TMP/res.json" <<'PY'
import json
import sys

# The runner's own list of statuses meaning "this check reached no verdict".
CANNOT_RUN = {"missing_tool", "timeout", "no_version", "refused", "unmapped_exit"}

out = sys.stdout
try:
    with open(sys.argv[1], errors="replace") as fh:
        res = json.load(fh)
except (OSError, ValueError) as exc:
    out.write("  the runner's result could not be read: %s\n" % type(exc).__name__)
    out.write("  assertions evaluated: 0 of 2. Unmeasured, not a pass.\n")
    sys.exit(2)

rows = res.get("checks") or []
if not rows:
    out.write("  PREMISE did not hold - the result records no checks at all\n")
    out.write("  R26 was not exercised. Unmeasured, not a pass.\n")
    sys.exit(2)

cannot = [r for r in rows if r.get("status") in CANNOT_RUN]
other_mechanism = [r for r in cannot if r.get("status") != "missing_tool"]
ran = [r for r in rows if r.get("status") not in CANNOT_RUN]

# THE PREMISE. Without a cannot-run row produced by something other than an
# absent tool, this is the existing fixture again and the empty set stays empty.
if not other_mechanism:
    out.write("  PREMISE did not hold - the fixture produced no cannot-run row other than "
              "`missing_tool`, which is the one status that never carried a coverage block. "
              "The empty set this check exists to fill is still empty.\n")
    out.write("  R26 was not exercised. Unmeasured, not a pass.\n")
    sys.exit(2)

out.write("  premise held: %d row(s) reached no verdict by a mechanism other than an absent tool (%s).\n"
          % (len(other_mechanism), ", ".join(sorted({r["status"] for r in other_mechanism}))))

upheld = 0
evaluated = 0
findings = []


def say(held, text):
    global upheld, evaluated
    evaluated += 1
    if held:
        upheld += 1
        out.write("  held: %s\n" % text)
    else:
        findings.append(text)
        out.write("  FINDING: did not hold - %s\n" % text)


for r in cannot:
    out.write("  %-16s status=%-14s coverage key present: %s\n"
              % (r.get("id", "?"), r.get("status"), "coverage" in r))

offenders = ["%s records covered=%r"
             % (r.get("id"), (r.get("coverage") or {}).get("observed", {}).get("covered"))
             for r in cannot if "coverage" in r]
say(not offenders,
    "1 no row that reached no verdict records a coverage count%s"
    % ("" if not offenders else "; offenders: " + "; ".join(offenders)))

# THE MIRROR IMAGE. A check that RAN and covered nothing measured a real zero,
# and deleting that would be this same bug pointed the other way.
measured = [r for r in ran if "coverage" in r]
say(bool(measured),
    "2 a check that ran still records its coverage (%d row(s) that reached a verdict carry one)"
    % len(measured))

out.write("  assertions evaluated: %d, upheld: %d\n" % (evaluated, upheld))
if findings:
    out.write("  R26 not satisfied: a check that reached no verdict recorded a count nobody measured.\n")
    sys.exit(1)
out.write("  R26 satisfied for the cannot-run path: no verdict, no count; and a measured zero survives.\n")
PY
