#!/usr/bin/env bash
# check-view-readonly.sh [--root DIR] [--builder PATH] [--version] [--help]
#
# Asserts R4: EVERY PUBLISHED VIEW SHALL BE READ-ONLY WITH RESPECT TO THE SPEC.
#
# Read-only has two halves and they fail in different places, so one check
# covers both rather than one of them being asserted and the other assumed.
#
#   HALF ONE - THE GENERATOR WRITES NOTHING BACK. The view builder is run
#   against this repository with its output pointed at a temporary directory,
#   and every file in the work tree is hashed before and after. Content AND
#   modification time, because a rewrite with identical bytes is still a write
#   and a build that touches a file it was only supposed to read will be
#   noticed the next time something else compares timestamps. An added file, a
#   removed file and a changed file are three findings, not one.
#
#   HALF TWO - THE PAGE CANNOT REPUBLISH ITSELF. The generated page is read and
#   every capability it declares is classified. `downloads` is OUTPUT: the page
#   hands the viewer a file built from its own bytes and reads nothing back.
#   A capability that publishes new versions of the page is not output - it
#   makes the page a second source of truth that can disagree with the repo,
#   and the provenance line under every panel, the sentence saying every figure
#   was read from the repository at generation time, stops being true the
#   moment it can. See references/views.md.
#
# THIS CHECK WRITES NOTHING INTO THE REPOSITORY IT IS CHECKING. A check that
# mutates what it is checking is the bug it exists to catch. The page is
# generated into a temporary directory that is removed on exit, and the
# repository is opened read-only.
#
# WHAT COUNTS AS A CAPABILITY DECLARATION. A published page reaches a
# capability through `claude.use("<name>")`, so that is what is read. Three
# outcomes, and only the first is silent:
#
#   an output capability          `downloads` - reported, not a finding
#   a self-publishing capability  a finding, named
#   anything else                 a finding. An unrecognised name is not
#                                 evidence of safety; a name this check cannot
#                                 classify has not been shown to be output.
#
# A `use()` whose argument is not a string literal is a finding for the same
# reason: a name computed at run time cannot be read out of the page, and an
# unreadable declaration is never counted as an absent one.
#
# KNOWN LIMITATION, WRITTEN DOWN RATHER THAN HIDDEN. The grant is made when the
# page is published, not inside the page. This check reads the page's bytes, so
# it sees what the page ASKS FOR. A capability granted at publish time and
# never used by the page leaves no trace in the file and is out of reach here.
# What it does close is the generator emitting the request, which is the only
# way this repository's pages have ever obtained one.
#
# THE OTHER KNOWN LIMITATION. The two hashes bracket the generator's run, so
# anything else that writes to the tree inside that window is attributed to the
# generator. That is the honest reading - the check cannot tell one writer from
# another - and it is a false positive when an editor saves, or a second agent
# works in the same tree, while this is running. A finding here names the file,
# so the first thing to do with one is look at whether that file has anything
# to do with building a view.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every file hashed, nothing changed, no capability beyond output
#   1  findings - a repository file moved, or the page declared something it
#      may not declare
#   2  could not run - bad usage, no work tree, no builder, an unreadable
#      file, or a page that could not be generated at all. A page that was
#      never built has an UNKNOWN number of capability declarations, never a
#      measured zero.
#
# WHAT IT PRINTS. One BARE PATH per line for every repository file examined,
# repo-relative, which is what the runner parses as coverage. Findings and
# notes are INDENTED. Nothing absolute is ever printed: this output is tailed
# into a committed result file, and an absolute path there is somebody's home
# directory published to everyone who clones the repo.
set -euo pipefail

VERSION="check-view-readonly 1.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT=""
BUILDER=""

die_unmeasured() { printf 'check-view-readonly: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)      [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)    ROOT="${1#--root=}";       shift ;;
    --builder)   [ "$#" -ge 2 ] || die_unmeasured "--builder needs a path"; BUILDER="$2"; shift 2 ;;
    --builder=*) BUILDER="${1#--builder=}"; shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1. The tree to check is named with --root." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1. The tree to check is named with --root."

# The work tree, never the working directory. Running this from a subdirectory
# must check the same tree it checks from the root, or the answer depends on
# where the person stood when they asked.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no git work tree here, and --root was not given. The tree to hash could not be identified; unmeasured, not clean."
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

[ -n "$BUILDER" ] || BUILDER="$HERE/build-view.sh"
[ -f "$BUILDER" ] || die_unmeasured "no view builder at the path given; there is nothing to run, so read-only is unmeasured"

command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the tree could not be hashed"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/snap.py" <<'PY'
"""Hash one work tree. stdout: sha256<TAB>mtime_ns<TAB>relpath, sorted.

A file that is listed and cannot be opened is recorded as `unreadable`, which
compares equal to itself and unequal to any content - an unreadable file is
never silently dropped out of the denominator.
"""
import hashlib
import os
import sys

root, listing = sys.argv[1], sys.argv[2]
with open(listing, errors="replace") as fh:
    rels = [ln.rstrip("\n") for ln in fh if ln.strip()]

rows = []
for rel in sorted(set(rels)):
    p = os.path.join(root, rel)
    try:
        st = os.lstat(p)
    except OSError:
        rows.append(("absent", "absent", rel))
        continue
    if os.path.islink(p):
        rows.append(("symlink:" + os.readlink(p), str(st.st_mtime_ns), rel))
        continue
    if not os.path.isfile(p):
        rows.append(("not-a-file", str(st.st_mtime_ns), rel))
        continue
    h = hashlib.sha256()
    try:
        with open(p, "rb") as fh:
            for blk in iter(lambda: fh.read(1 << 20), b""):
                h.update(blk)
    except OSError:
        rows.append(("unreadable", str(st.st_mtime_ns), rel))
        continue
    rows.append((h.hexdigest(), str(st.st_mtime_ns), rel))

out = sys.stdout
for row in rows:
    out.write("\t".join(row) + "\n")
PY

cat > "$TMP/cmp.py" <<'PY'
"""Compare two snapshots. One bare path per examined file on stdout; findings
indented. Exit 0 clean, 1 findings.

Content and mtime are separate findings. A rewrite with identical bytes is
still a write, and a build that touches a file it was only supposed to read is
a build that will make something else's timestamp comparison wrong later.
"""
import sys


def load(path):
    rows = {}
    with open(path, errors="replace") as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln:
                continue
            digest, mtime, rel = ln.split("\t", 2)
            rows[rel] = (digest, mtime)
    return rows


before, after = load(sys.argv[1]), load(sys.argv[2])
findings = []
out = sys.stdout
for rel in sorted(set(before) | set(after)):
    out.write(rel + "\n")
    b, a = before.get(rel), after.get(rel)
    # `absent` is the recorded state of a path that was listed and was not
    # there. It is a state, not a hash: a file that appears during the run is
    # a file the generator CREATED, and reporting that as "contents changed"
    # would describe the wrong event.
    b_absent = b is None or b[0] == "absent"
    a_absent = a is None or a[0] == "absent"
    if b_absent and a_absent:
        continue
    if b_absent:
        findings.append("%s: created by the generator; it was not in the tree before the run" % rel)
        continue
    if a_absent:
        findings.append("%s: removed by the generator" % rel)
        continue
    if b[0] != a[0]:
        findings.append("%s: contents changed across the generator run" % rel)
    elif b[1] != a[1]:
        findings.append("%s: modification time changed across the generator run; "
                        "the bytes are the same, so this is a rewrite, not an edit" % rel)

out.write("  repository files hashed before and after: %d\n" % len(set(before) | set(after)))
for f in findings:
    out.write("  FINDING: %s\n" % f)
out.write("  files the generator moved: %d\n" % len(findings))
sys.exit(1 if findings else 0)
PY

cat > "$TMP/caps.py" <<'PY'
"""Read the capabilities a generated page declares. Exit 0 clean, 1 findings,
2 the page could not be read.

`downloads` is output: the page hands the viewer a file built from its own
bytes and reads nothing back. A capability that publishes new versions of the
page is not output - it becomes a second source of truth that can disagree
with the repo. Anything this file cannot classify is a finding, because an
unrecognised name has not been shown to be output; silence there would be the
check certifying what it never read.
"""
import re
import sys

OUTPUT_ONLY = {"downloads"}
SELF_PUBLISHING = {
    "artifact": "publishes new versions of the page itself",
    "self": "publishes new versions of the page itself",
}

try:
    with open(sys.argv[1], errors="replace") as fh:
        src = fh.read()
except OSError as exc:
    sys.stdout.write("  the generated page could not be read: %s\n" % exc.strerror)
    sys.stdout.write("  capability declarations read: unknown\n")
    sys.exit(2)

if not src.strip():
    sys.stdout.write("  the generated page is empty\n")
    sys.stdout.write("  capability declarations read: unknown\n")
    sys.exit(2)

calls = re.findall(r"claude\s*\.\s*use\s*\(([^)]*)\)", src)
findings, notes = [], []
for raw in calls:
    arg = raw.strip()
    m = re.match(r"""^(['"])(.*)\1$""", arg, re.S)
    if not m:
        findings.append("a capability name that is not a string literal; it is computed at "
                        "run time and cannot be read out of the page, so it is not readable "
                        "as absent either")
        continue
    name = m.group(2)
    if name in SELF_PUBLISHING:
        findings.append("the page declares `%s`, which %s. A view is output; a page that "
                        "saves over itself is a second source of truth that can disagree "
                        "with the repository" % (name, SELF_PUBLISHING[name]))
    elif name in OUTPUT_ONLY:
        notes.append("declares `%s` - output: it hands the viewer a file and reads nothing "
                     "back" % name)
    else:
        findings.append("the page declares `%s`, which this check cannot classify. An "
                        "unrecognised capability has not been shown to be output-only; "
                        "classify it here or stop declaring it" % name)

out = sys.stdout
out.write("  page bytes read: %d\n" % len(src))
out.write("  capability declarations read: %d\n" % len(calls))
for n in notes:
    out.write("  %s\n" % n)
for f in findings:
    out.write("  FINDING: %s\n" % f)
sys.exit(1 if findings else 0)
PY

# The listing is git's, so the .git directory is out of it by construction and
# an index refresh is never mistaken for a repository file moving. Ignored
# files are IN: a generator writing into a gitignored path has still written
# into the tree, and --exclude-standard would have hidden exactly that.
git -C "$ROOT" ls-files -co > "$TMP/filelist" \
  || die_unmeasured "could not list the work tree; the tree was not hashed, which is unmeasured and not clean"
[ -s "$TMP/filelist" ] || die_unmeasured "the work tree lists no files. Nothing was hashed; a run that examined nothing is not a clean run"

python3 "$TMP/snap.py" "$ROOT" "$TMP/filelist" > "$TMP/before" \
  || die_unmeasured "the work tree could not be hashed before the generator ran"

PAGE="$TMP/page.html"
BRC=0
bash "$BUILDER" "$ROOT" --out "$PAGE" > "$TMP/builder.out" 2> "$TMP/builder.err" || BRC=$?

# The tree is re-listed rather than reused: a file the generator CREATED is a
# finding, and reusing the first listing is how it would go unnoticed.
git -C "$ROOT" ls-files -co > "$TMP/filelist2" \
  || die_unmeasured "could not list the work tree after the generator ran"
cat "$TMP/filelist" "$TMP/filelist2" > "$TMP/filelist_union"
python3 "$TMP/snap.py" "$ROOT" "$TMP/filelist_union" > "$TMP/after" \
  || die_unmeasured "the work tree could not be hashed after the generator ran"
# `before` was taken over the first listing only. Widening it to the union
# without re-hashing would invent a value for a file that did not exist yet, so
# the widening is done by absence: anything in the union and not in `before` is
# recorded as having been absent.
python3 - "$TMP/before" "$TMP/filelist_union" > "$TMP/before_union" <<'PY'
import sys
seen = {}
with open(sys.argv[1], errors="replace") as fh:
    for ln in fh:
        ln = ln.rstrip("\n")
        if ln:
            seen[ln.split("\t", 2)[2]] = ln
with open(sys.argv[2], errors="replace") as fh:
    rels = sorted({ln.strip() for ln in fh if ln.strip()})
out = sys.stdout
for rel in rels:
    out.write(seen.get(rel, "absent\tabsent\t" + rel) + "\n")
PY

TREE_RC=0
python3 "$TMP/cmp.py" "$TMP/before_union" "$TMP/after" || TREE_RC=$?
[ "$TREE_RC" -le 1 ] || die_unmeasured "the before/after comparison did not complete"

CAP_RC=0
if [ "$BRC" -ne 0 ]; then
  printf '  the view generator exited %s. Its output is not reproduced here: it can carry an absolute path, and this text is tailed into a committed result file.\n' "$BRC"
  printf '  capability declarations read: unknown\n'
  CAP_RC=2
else
  python3 "$TMP/caps.py" "$PAGE" || CAP_RC=$?
fi

if [ "$CAP_RC" -eq 2 ]; then
  printf '  REFUSED: the page could not be generated or read, so the number of capabilities it declares is unknown. Unknown is not zero.\n'
  [ "$TREE_RC" -eq 0 ] || printf '  the tree comparison above still stands and found something.\n'
  exit 2
fi

if [ "$TREE_RC" -ne 0 ] || [ "$CAP_RC" -ne 0 ]; then
  printf '  R4 not satisfied: see the findings above.\n'
  exit 1
fi
printf '  R4 satisfied: the generator moved no repository file, and the page declares nothing that can publish a new version of itself.\n'
exit 0
