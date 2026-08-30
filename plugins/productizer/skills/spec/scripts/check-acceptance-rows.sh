#!/usr/bin/env bash
# check-acceptance-rows.sh [--version] [--help] [--root PATH] [--spec PATH]
#
# Asserts the second half of R8: WHEN A REQUIREMENT IS ADDED, THE LIFECYCLE
# SHALL ALLOCATE THE NEXT UNUSED ID AND RECORD IT IN THE ACCEPTANCE CRITERIA
# TABLE.
#
# The id half is `validate-spec.py`, and this check does not repeat it. That
# script already refuses a reused id (ID_REUSED), an id at or above the
# declared counter (ID_AT_OR_ABOVE_COUNTER), an id that arrived out of order
# (ID_OUT_OF_ORDER) and a citation naming an id the spec does not define
# (CITATION_UNKNOWN). What nothing asserted is the other clause of the same
# sentence: that the id was RECORDED IN THE ACCEPTANCE CRITERIA TABLE.
#
# The failure it catches is quiet. A requirement lands, is cited by a plan, a
# branch name and a PR title, and never acquires a row saying what would prove
# it. Nothing goes red; the requirement simply becomes one nobody can tell the
# difference between "verified" and "never looked at" for. R27 and R28 in this
# repo's own spec were in that state for a day, inherited from a superseded
# requirement that had carried no row either.
#
# WHAT COUNTS AS NEEDING A ROW, AND WHAT DOES NOT.
#
#   active                       a row is REQUIRED
#   `Superseded by R<n>.`        no row - the requirement is a frozen record
#   `Withdrawn.`                 no row - the behaviour no longer exists
#   `Inferred ... Unconfirmed.`  no row - references/import.md, property 3:
#                                an inferred requirement is not counted as
#                                verified, and a row for one would inflate
#                                the very comparison this check performs
#
# Demanding a row for a dead or unratified requirement is not a stricter
# check, it is a WRONG one: it goes permanently red against a correct spec,
# and a check that is red for a correct spec gets switched off. This repo's
# spec holds three superseded requirements with no row, correctly.
#
# ADVISORY-CAPABLE, AND THE COUNT IS PRINTED ON EVERY RUN. The number of
# requirements missing a row is printed whether it is zero or not, so it is
# visible on a clean run and can be watched shrinking on a dirty one. The
# script itself always exits 1 when the number is above zero; whether that
# blocks is `severity:` in checks.yaml, which is the same route
# `stderr-suppression` took.
#
# WHAT IT PRINTS. One BARE PATH per line for every file examined - the
# runner reads those as coverage. Everything else is INDENTED. Findings name
# the ID AND THE LINE and nothing else: the requirement text is never echoed,
# because this output lands in a committed result file.
#
# A NUMBER THAT COULD NOT BE MEASURED IS PRINTED AS AN EM DASH, NEVER AS
# ZERO. A spec that cannot be read, that has no `## Requirements` section, no
# `## Acceptance criteria` section, or an acceptance table whose rows do not
# have the column count its own header declares, is exit 2 - refused. "0
# missing rows" is a claim about a spec somebody parsed.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every active requirement has an acceptance criteria row
#   1  at least one does not - reported by id and line
#   2  COULD NOT MEASURE - bad usage, or a spec that could not be parsed
set -euo pipefail

VERSION="check-acceptance-rows 1.0"
ROOT=""
SPEC=".claude/productizer/spec.md"

die_unmeasured() { printf 'check-acceptance-rows: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root) [ "$#" -ge 2 ] || die_unmeasured "--root needs a path"; ROOT="$2"; shift 2 ;;
    --spec) [ "$#" -ge 2 ] || die_unmeasured "--spec needs a path"; SPEC="$2"; shift 2 ;;
    *) die_unmeasured "unknown argument: $1" ;;
  esac
done

# The working directory is NEVER the default. A check rooted at wherever it
# happened to be invoked from reads a different spec depending on the caller,
# and answers confidently either way.
if [ -z "$ROOT" ]; then
  ROOT=$(git rev-parse --show-toplevel) \
    || die_unmeasured "no --root given and this is not a git work tree"
fi
[ -d "$ROOT" ] || die_unmeasured "--root is not a directory: $ROOT"

python3 - "$ROOT" "$SPEC" <<'PY'
import os
import re
import sys

root, spec_rel = sys.argv[1], sys.argv[2]
spec_path = spec_rel if os.path.isabs(spec_rel) else os.path.join(root, spec_rel)
shown = os.path.relpath(spec_path, root)

# `- **R14** — ...`, the one shape templates/spec.md writes requirements in.
RE_REQ = re.compile(r'^(?:[-*]\s+)?\*\*(R[0-9]+)\*\*')
RE_SUPER = re.compile(r'^Superseded by\s+R[0-9]+')
RE_WITHDRW = re.compile(r'^Withdrawn\.')
RE_INFER = re.compile(r'^Inferred(\s*\([^)]*\))?\s+from\b')
RE_ACROW = re.compile(r'^\|\s*`?(R[0-9]+)`?\s*(?<!\\)\|')
RE_SEP = re.compile(r'^[\s:|-]+$')

# A markdown cell may hold a pipe by escaping it as `\|`. Splitting on a bare
# pipe tears such a row into an extra cell and silently shifts every column
# after it - the mistake build-view.sh already shipped once, which rendered a
# real note as a single stray backtick. Split on UNESCAPED pipes only, then
# put the real character back.
RE_MD_PIPE = re.compile(r'(?<!\\)\|')


def cells(row):
    return [c.strip().replace('\\|', '|') for c in RE_MD_PIPE.split(row)]


def refuse(message):
    sys.stdout.write('    active requirements examined: —\n')
    sys.stdout.write('    requirements missing an acceptance row: —\n')
    sys.stderr.write('check-acceptance-rows: %s\n' % message)
    raise SystemExit(2)


try:
    with open(spec_path, encoding='utf-8') as handle:
        text = handle.read()
except OSError as exc:
    refuse('cannot read %s: %s' % (shown, exc.strerror or exc))

# The path is printed only once the file has actually been read. A path
# printed before the read would be counted as coverage for a file nobody
# opened.
sys.stdout.write('%s\n' % shown)
lines = text.split('\n')


def section_bounds(title):
    start = None
    for index, line in enumerate(lines):
        if re.match(r'^##\s+%s\s*$' % re.escape(title), line):
            start = index + 1
            break
    if start is None:
        return None
    for index in range(start, len(lines)):
        if re.match(r'^##\s', lines[index]):
            return (start, index)
    return (start, len(lines))


req_bounds = section_bounds('Requirements')
if req_bounds is None:
    refuse('%s has no `## Requirements` section, so there is no set of '
           'requirements to compare the acceptance table against' % shown)

ac_bounds = section_bounds('Acceptance criteria')
if ac_bounds is None:
    refuse('%s has no `## Acceptance criteria` section; the table this check '
           'compares against does not exist, which is not the same fact as '
           'every requirement being missing a row' % shown)

# --- the requirements, with the status marker that sits under each ----------
requirements = []
first, last = req_bounds
for index in range(first, last):
    match = RE_REQ.match(lines[index])
    if not match:
        continue
    # The entry runs to the first blank line or the next requirement, not a
    # fixed window: a marker sitting under a sentence that wrapped over four
    # lines is still found. A marker this check fails to see is a dead
    # requirement it reports as a gap.
    entry = []
    for follow in lines[index + 1:last]:
        if not follow.strip() or RE_REQ.match(follow):
            break
        entry.append(follow.strip())
    status = 'active'
    for line in entry:
        if RE_SUPER.match(line):
            status = 'superseded'
            break
        if RE_WITHDRW.match(line):
            status = 'withdrawn'
            break
        if RE_INFER.match(line):
            status = 'inferred'
            break
    requirements.append({'id': match.group(1), 'line': index + 1,
                         'status': status})

# --- the acceptance criteria table ------------------------------------------
ac_ids = set()
ac_rows = 0
header_width = None
first, last = ac_bounds
for index in range(first, last):
    raw = lines[index]
    if not raw.lstrip().startswith('|'):
        continue
    width = len(cells(raw))
    if header_width is None:
        header_width = width
        continue
    if RE_SEP.match(raw):
        continue
    if width != header_width:
        refuse('%s:%d - the acceptance table row has %d cells where its own '
               'header declares %d; a row this check cannot line up with its '
               'columns is a row it cannot read an id out of'
               % (shown, index + 1, width, header_width))
    match = RE_ACROW.match(raw)
    if match:
        ac_rows += 1
        ac_ids.add(match.group(1))

if header_width is None:
    refuse('%s has an `## Acceptance criteria` section holding no table' % shown)

tally = {'active': 0, 'superseded': 0, 'withdrawn': 0, 'inferred': 0}
for requirement in requirements:
    tally[requirement['status']] += 1
if not requirements:
    refuse('%s has a `## Requirements` section holding no `- **R<n>**` '
           'requirement' % shown)

missing = [r for r in requirements
           if r['status'] == 'active' and r['id'] not in ac_ids]

# The coverage number the runner reads. It is every requirement the check
# actually parsed out of the file, not the subset that produced findings -
# a check that opened the spec and understood none of it must not be able
# to report a pass.
sys.stdout.write('    requirements read: %d\n' % len(requirements))
sys.stdout.write('    active requirements examined: %d\n' % tally['active'])
sys.stdout.write('    no row required: %d superseded, %d withdrawn, '
                 '%d inferred\n'
                 % (tally['superseded'], tally['withdrawn'], tally['inferred']))
sys.stdout.write('    acceptance criteria rows read: %d, naming %d distinct '
                 'ids\n' % (ac_rows, len(ac_ids)))
sys.stdout.write('    requirements missing an acceptance row: %d\n'
                 % len(missing))

for requirement in sorted(missing, key=lambda r: int(r['id'][1:])):
    sys.stdout.write('    MISSING  %s  %s:%d  active, and the acceptance '
                     'criteria table has no row for it\n'
                     % (requirement['id'], shown, requirement['line']))

raise SystemExit(1 if missing else 0)
PY
