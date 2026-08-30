#!/usr/bin/env bash
# check-import-marking.sh [--version] [--help] [--root PATH] [--spec PATH]
#                         [--max-commits N]
#
# Asserts R10: WHEN A REPOSITORY WITH HISTORY IS IMPORTED, THE LIFECYCLE SHALL
# MARK EVERY DRAFTED REQUIREMENT INFERRED AND UNCONFIRMED.
#
# `build-view.sh` RENDERS the inferred status and nothing asserted it was ever
# applied. A forgotten marker therefore produces a requirement that reads as
# agreed - which that file's own comment calls the precise failure the
# inferred status exists to prevent. Three things follow from an unmarked
# import, all silent: the audit trail records a decision nobody made, the
# Stage 2 contradiction halt starts defending an imported accident with the
# authority of a ratification, and every plan, test and PR title citing the id
# inherits that confidence without re-checking it.
#
# ==========================================================================
# HOW AN IMPORT IS DETECTED. READ THIS BEFORE TRUSTING A CLEAN RUN.
# ==========================================================================
#
# THERE IS NO RELIABLE SIGNAL THAT AN IMPORT HAPPENED. Stage 0c writes no
# artifact, sets no config key and leaves no record of its own:
# `import-survey.sh` deliberately never writes to the repo it surveys, the
# draft is a hand edit, and promotion is another one. Nothing in the config,
# the filesystem or git says "an import ran here".
#
# The obvious signal - the English word "import" in a change-log summary or a
# commit message - was built first and MEASURED AGAINST A FIXTURE, and it is
# not usable. It attributed six requirements to an import in a spec where four
# of them were agreed one at a time, because one commit message mentioned the
# word. On this product's own spec that failure mode is not hypothetical: this
# is a lifecycle tool WITH an import stage, so a requirement ABOUT importing,
# or a change-log row naming the import survey, both carry the word while
# having nothing to do with a Stage 0c run. A check that fails on a correct
# spec gets switched off, and then nothing is checked at all.
#
# So detection is anchored on STRUCTURE, not on prose. The signal is the
# marking itself: A SPEC HOLDING AN INFERRED REQUIREMENT IS A SPEC AN IMPORT
# TOUCHED. From each requirement that IS marked, the check reaches the batch
# it arrived in and demands the same marking of every sibling in that batch.
#
#   A  CHANGE-LOG COHORT. `references/import.md` step 8 records the import as
#      one change-log row. A row whose `Added` column names a marked
#      requirement is an import row, and every other id in that same `Added`
#      cell belongs to the same import. The column is located by the table's
#      OWN HEADER, never by position, and ranges are expanded.
#
#   B  COMMIT COHORT. The commit that INTRODUCED a marked requirement's bullet
#      introduced the rest of that batch too. Oldest introduction wins, so a
#      later reformat that re-adds every bullet in the diff is not mistaken
#      for the import. Independent of A in the way that matters: it survives
#      someone trimming the change log afterwards.
#
#   C  A DECLARED STAGE. `Stage 0c` named in a change-log row or a commit
#      message. This is the ONE piece of prose used, because it is a stage
#      identifier rather than an English word - `import` is a substring of
#      `important` and a topic half this repo's requirements are about;
#      `stage 0c` is neither.
#
# WHAT SATISFIES THE OBLIGATION for an id the cohort attributes to an import:
#
#   `Inferred ... Unconfirmed.`              the marking itself
#   `Withdrawn. Rejected at import: ...`     refused at ratification, id spent
#   a decision-record row naming the id and reading as a confirmation of an
#   imported requirement - because promotion DELETES the marker line, so a
#   ratified requirement is bare BY DESIGN and reporting it as never-marked
#   would make the check red for the one outcome the stage is aiming at
#
# THE HOLES, NAMED, BECAUSE A CLEAN RUN HERE MEANS LESS THAN IT LOOKS:
#
#   - AN IMPORT THAT MARKED NOTHING AT ALL IS INVISIBLE TO A AND B. They start
#     from a marker, so a draft where the convention was never applied once
#     leaves nothing to anchor on. C is the only cover for that case and it
#     depends on somebody having typed the stage name. THIS IS THE LARGEST
#     GAP AND IT IS NOT CLOSEABLE WITHOUT AN ARTIFACT STAGE 0C DOES NOT WRITE.
#     The fix is upstream: have the import write a machine record of its own
#     id range, and read that here instead.
#   - A SHALLOW CLONE removes evidence from B without removing it from the
#     repository, and B silently sees fewer introductions.
#   - AN IMPORT SPLIT ACROSS SEVERAL CHANGE-LOG ROWS only pulls in the rows
#     that happen to name a marked id; a row where every marker was forgotten
#     is a row this check never reaches.
#
# All three cohort tallies are printed on every run for exactly this reason:
# `0` next to them means NO IMPORT WAS FOUND, not that an import was found and
# came back clean, and the run says so in words underneath.
#
# GIT IS PART OF THE INPUT, SO GIT BEING UNREADABLE IS NOT A CLEAN RUN. A root
# that is not a git work tree, or a history that cannot be walked, is exit 2
# with cohort B printed as an em dash - never as 0 commits. The one ordering
# rule: findings already found are a definite answer, so they exit 1 even when
# B could not be read.
#
# WHAT IT PRINTS. One BARE PATH per line for every file examined; everything
# else INDENTED. Findings name the ID AND THE LINE. No requirement text is
# ever echoed - this output lands in a committed result file.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  no requirement attributed to an import lacks the inferred marking
#   1  at least one does - reported by id, line, and the cohort that
#      attributed it
#   2  COULD NOT MEASURE - bad usage, a spec that could not be parsed, or a
#      git history that could not be walked
set -euo pipefail

VERSION="check-import-marking 1.0"
ROOT=""
SPEC=".claude/productizer/spec.md"
MAX_COMMITS="500"

die_unmeasured() { printf 'check-import-marking: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root) [ "$#" -ge 2 ] || die_unmeasured "--root needs a path"; ROOT="$2"; shift 2 ;;
    --spec) [ "$#" -ge 2 ] || die_unmeasured "--spec needs a path"; SPEC="$2"; shift 2 ;;
    --max-commits)
      [ "$#" -ge 2 ] || die_unmeasured "--max-commits needs a number"
      case "$2" in
        ''|*[!0-9]*) die_unmeasured "--max-commits is not a number: $2" ;;
      esac
      MAX_COMMITS="$2"; shift 2
      ;;
    *) die_unmeasured "unknown argument: $1" ;;
  esac
done

# The working directory is NEVER the default. A check rooted at wherever it
# happened to be invoked from reads a different spec and a different history
# depending on the caller, and answers confidently either way.
if [ -z "$ROOT" ]; then
  ROOT=$(git rev-parse --show-toplevel) \
    || die_unmeasured "no --root given and this is not a git work tree"
fi
[ -d "$ROOT" ] || die_unmeasured "--root is not a directory: $ROOT"

python3 - "$ROOT" "$SPEC" "$MAX_COMMITS" <<'PY'
import os
import re
import subprocess
import sys

root, spec_rel, max_commits = sys.argv[1], sys.argv[2], int(sys.argv[3])
spec_path = spec_rel if os.path.isabs(spec_rel) else os.path.join(root, spec_rel)
shown = os.path.relpath(spec_path, root)

RE_REQ = re.compile(r'^(?:[-*]\s+)?\*\*(R[0-9]+)\*\*')
RE_ADDED_REQ = re.compile(r'^\+(?:[-*]\s+)?\*\*(R[0-9]+)\*\*')
RE_INFER = re.compile(r'^Inferred(\s*\([^)]*\))?\s+from\b')
RE_REJIMP = re.compile(r'^Withdrawn\.\s*Rejected at import\b', re.I)
RE_RID = re.compile(r'\bR[0-9]+\b')
RE_RANGE = re.compile(r'\bR([0-9]+)\s*[–—-]\s*R?([0-9]+)\b')
RE_SEP = re.compile(r'^[\s:|-]+$')

# The one piece of prose this check trusts, and it is a stage identifier
# rather than an English word. `import` matches `important` and matches half
# the requirements of a product whose subject IS importing; `stage 0c` does
# neither.
RE_STAGE0C = re.compile(r'\bstage\s*0c\b', re.I)
# Promotion is recorded in the decision record, and only a row that reads as a
# confirmation AND says the id came from the import counts as one. The same
# pair build-view.sh uses, so the two files agree about what a promotion is.
RE_RATIFY = re.compile(r'confirm|promot|ratif', re.I)
RE_FROMIMP = re.compile(r'import|inferred', re.I)

RE_MD_PIPE = re.compile(r'(?<!\\)\|')


def cells(row):
    return [c.strip().replace('\\|', '|') for c in RE_MD_PIPE.split(row)]


def refuse(message):
    sys.stdout.write('    requirements attributed to an import: —\n')
    sys.stdout.write('    attributed requirements with no inferred marking: —\n')
    sys.stderr.write('check-import-marking: %s\n' % message)
    raise SystemExit(2)


def ids_in(field):
    found = set(RE_RID.findall(field))
    for low, high in RE_RANGE.findall(field):
        low, high = int(low), int(high)
        if low <= high and high - low <= 999:
            found.update('R%d' % n for n in range(low, high + 1))
    return found


try:
    with open(spec_path, encoding='utf-8') as handle:
        text = handle.read()
except OSError as exc:
    refuse('cannot read %s: %s' % (shown, exc.strerror or exc))

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
    refuse('%s has no `## Requirements` section, so there is nothing an '
           'import could have drafted into it' % shown)

# --- every requirement, with whatever marker sits under it ------------------
requirements = {}
first, last = req_bounds
for index in range(first, last):
    match = RE_REQ.match(lines[index])
    if not match:
        continue
    # The entry runs to the first blank line or the next requirement, not a
    # fixed window: a marker under a sentence that wrapped over four lines is
    # still found. A marker this check fails to see is a requirement it
    # reports as never having been marked.
    entry = []
    for follow in lines[index + 1:last]:
        if not follow.strip() or RE_REQ.match(follow):
            break
        entry.append(follow.strip())
    requirements[match.group(1)] = {
        'line': index + 1,
        'inferred': any(RE_INFER.match(e) for e in entry),
        'rejected': any(RE_REJIMP.match(e) for e in entry),
    }

if not requirements:
    refuse('%s has a `## Requirements` section holding no `- **R<n>**` '
           'requirement' % shown)

# --- promotions, from the decision record -----------------------------------
promoted = set()
dr_bounds = section_bounds('Decision record')
if dr_bounds is not None:
    first, last = dr_bounds
    for index in range(first, last):
        row = lines[index]
        if not row.lstrip().startswith('|'):
            continue
        if RE_RATIFY.search(row) and RE_FROMIMP.search(row):
            promoted.update(r for r in RE_RID.findall(row) if r in requirements)

# An id is EVIDENCE OF AN IMPORT when it still wears the marking, when it was
# refused at ratification, or when the decision record says a person promoted
# it out of an import. All three are outcomes of the same stage.
marked = set(r for r, v in requirements.items()
             if v['inferred'] or v['rejected']) | promoted

# --- cohort A: change-log rows, and cohort C where the row names the stage ---
attributed = {}
a_rows = 0
c_rows = 0
cl_bounds = section_bounds('Change log')
if cl_bounds is not None:
    first, last = cl_bounds
    header = None
    added_col = None
    rows = []
    for index in range(first, last):
        raw = lines[index]
        if not raw.lstrip().startswith('|'):
            continue
        row = cells(raw)
        if header is None:
            header = row
            # The column is located by the table's own header. Reading it by
            # position is how a table that gained a column starts reporting a
            # different column's contents as requirement ids.
            for position, name in enumerate(row):
                if name.strip().lower() == 'added':
                    added_col = position
            continue
        if RE_SEP.match(raw):
            continue
        if len(row) != len(header):
            refuse('%s:%d - the change log row has %d cells where its own '
                   'header declares %d; a row this check cannot line up with '
                   'its columns is a row whose `Added` ids it cannot read'
                   % (shown, index + 1, len(row), len(header)))
        rows.append((index + 1, raw, row))
    if rows and added_col is None:
        refuse('%s - the change log table declares no `Added` column, so the '
               'ids an import row added cannot be read out of it' % shown)
    for lineno, raw, row in rows:
        found = ids_in(row[added_col])
        by_marker = bool(found & marked)
        by_stage = bool(RE_STAGE0C.search(raw))
        if not (by_marker or by_stage):
            continue
        if by_marker:
            a_rows += 1
        if by_stage:
            c_rows += 1
        for rid in found:
            attributed.setdefault(rid, set()).add(
                'change log %s:%d' % (shown, lineno))

# --- cohort B: the commit that introduced a marked requirement --------------
# Plus cohort C again, where a commit message names the stage.
b_commits = None
walked = None
git_note = None


def git(*args):
    return subprocess.run(('git', '-C', root) + args, capture_output=True,
                          text=True)


probe = git('rev-parse', '--is-inside-work-tree')
if probe.returncode != 0:
    git_note = (probe.stderr.strip().split('\n')[-1]
                if probe.stderr.strip() else 'git rev-parse failed')
else:
    log = git('log', '--max-count=%d' % max_commits, '--reverse',
              '--format=%H%x1f%B%x1e', '--', spec_rel)
    if log.returncode != 0:
        git_note = (log.stderr.strip().split('\n')[-1]
                    if log.stderr.strip() else 'git log failed')
    else:
        commits = []
        for record in log.stdout.split('\x1e'):
            record = record.strip('\n')
            if record and '\x1f' in record:
                commits.append(record.split('\x1f', 1))
        walked = len(commits)
        introduced = {}
        stage_commits = []
        failed = None
        for sha, message in commits:
            show = git('show', '--unified=0', '--format=', sha, '--', spec_rel)
            if show.returncode != 0:
                failed = (show.stderr.strip().split('\n')[-1]
                          if show.stderr.strip()
                          else 'git show %s failed' % sha[:12])
                break
            hits = set()
            for line in show.stdout.split('\n'):
                match = RE_ADDED_REQ.match(line)
                if match:
                    hits.add(match.group(1))
            # Oldest wins: `--reverse` means the first commit seen holding a
            # bullet is the one that introduced it, so a later reformat that
            # re-adds every bullet in its diff is not read as the import.
            for rid in hits:
                introduced.setdefault(rid, sha)
            if RE_STAGE0C.search(message) and hits:
                stage_commits.append((sha, hits))
        if failed is not None:
            git_note = failed
        else:
            by_commit = {}
            for rid, sha in introduced.items():
                by_commit.setdefault(sha, set()).add(rid)
            b_commits = 0
            for sha, batch in by_commit.items():
                if not (batch & marked):
                    continue
                b_commits += 1
                for rid in batch:
                    attributed.setdefault(rid, set()).add('commit %s' % sha[:12])
            for sha, hits in stage_commits:
                c_rows += 1
                for rid in hits:
                    attributed.setdefault(rid, set()).add('commit %s' % sha[:12])

# --- the verdict ------------------------------------------------------------
known = sorted((r for r in attributed if r in requirements),
               key=lambda r: int(r[1:]))
unknown = sorted((r for r in attributed if r not in requirements),
                 key=lambda r: int(r[1:]))
settled = [r for r in known
           if requirements[r]['inferred'] or requirements[r]['rejected']
           or r in promoted]
findings = [r for r in known if r not in settled]

# The coverage number the runner reads. Every requirement the check parsed
# out of the file - never the attribution count, which is legitimately 0 on
# a repo that was never imported and would read as a hollow run.
sys.stdout.write('    requirements read: %d\n' % len(requirements))
sys.stdout.write('    requirements still wearing the marking, refused at '
                 'import, or promoted from one: %d\n' % len(marked))
sys.stdout.write('    cohort A - change log rows naming one of them: %d\n'
                 % a_rows)
if b_commits is None:
    sys.stdout.write('    cohort B - commits introducing one of them: — (git '
                     'could not be walked: %s)\n' % (git_note or 'unknown reason'))
else:
    sys.stdout.write('    cohort B - commits introducing one of them: %d, of '
                     '%d touching the spec\n' % (b_commits, walked))
sys.stdout.write('    cohort C - change log rows or commits naming `Stage 0c`: '
                 '%d\n' % c_rows)
sys.stdout.write('    requirements attributed to an import: %d\n' % len(known))
sys.stdout.write('    of those, already marked, refused or promoted: %d\n'
                 % len(settled))
sys.stdout.write('    attributed requirements with no inferred marking: %d\n'
                 % len(findings))
if not known:
    sys.stdout.write('    NOTE: no import was found. That is not the same '
                     'fact as an import having been marked correctly - an '
                     'import that marked nothing at all and named no stage '
                     'leaves this check nothing to anchor on\n')

for rid in unknown:
    sys.stdout.write('    NOT CHECKED  %s  named by %s, but %s defines no such '
                     'requirement\n'
                     % (rid, sorted(attributed[rid])[0], shown))
for rid in findings:
    sys.stdout.write('    UNMARKED  %s  %s:%d  attributed to an import by %s, '
                     'and carries no `Inferred ... Unconfirmed.` marking\n'
                     % (rid, shown, requirements[rid]['line'],
                        ', '.join(sorted(attributed[rid]))))

if findings:
    raise SystemExit(1)
if b_commits is None:
    raise SystemExit(2)
raise SystemExit(0)
PY
