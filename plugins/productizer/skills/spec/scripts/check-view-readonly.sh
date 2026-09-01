#!/usr/bin/env bash
# check-view-readonly.sh [--root DIR] [--builder PATH] [--fixture DIR]
#                       [--version] [--help]
#
# Asserts R4: EVERY PUBLISHED VIEW SHALL BE READ-ONLY WITH RESPECT TO THE SPEC.
# It also asserts the page-side half of R30 and of R31; see THE R31 BOUNDARY
# below, which is the one place this check must not be read as more than it is.
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
#   HALF TWO - WHAT THE PAGE DECLARES. The generated page is read and every
#   capability it reaches for is classified. `downloads` is OUTPUT: the page
#   hands the viewer a file built from its own bytes and reads nothing back,
#   which is exactly what R30 requires of a view that hands over its evidence.
#   A capability that publishes new versions of the page is not output - it
#   makes the page a second source of truth that can disagree with the repo,
#   and the provenance line under every panel, the sentence saying every figure
#   was read from the repository at generation time, stops being true the
#   moment it can. See references/views.md.
#
# WHY 2.0 EXISTS. The 1.0 check read half two by matching one literal source
# pattern, `claude.use("<name>")`. An audit defeated it in a single line:
#
#     window.claude["use"]("artifact")
#
# reaches the same capability, and 1.0 reported `capability declarations read:
# 0` and passed clean. Not a hypothetical - a reproduced evasion, and the worst
# possible shape of one, because the check answered ZERO rather than answering
# "I could not tell". Everything below follows from that: the page is read for
# WHAT IT REACHES, not for how it is spelled, and anything reached in a way
# that cannot be resolved to a name is a FINDING rather than silence.
#
# WHAT IS MATCHED, EXACTLY. Two nets, and the second is deliberately the louder
# one.
#
#   NET ONE, ANCHORED ON THE RECEIVER. The identifier `claude`, optionally
#   written `window.claude`, followed by a property access. The access is then
#   resolved: a dotted name is read as written; a bracketed name is read only
#   when the key is a plain quoted string with no backslash in it. Whitespace,
#   newlines and optional chaining (`?.`, `?.()`) are all crossed, so
#   `claude [ 'use' ] ( "x" )` and a call split over four lines resolve the
#   same as the compact form. When the property is `use` and it is called, the
#   first argument is read: a plain quoted string is a NAME, and anything else
#   - a variable, a concatenation, a template literal, a string carrying an
#   escape - is a finding.
#
#   NET TWO, ANCHORED ON THE PROPERTY. Any `.use(...)` or `["use"](...)` that
#   net one did not already claim, on ANY receiver. This is what catches an
#   alias: `var c = window.claude; c.use("artifact")` never names the
#   capability object at the call site, so nothing anchored on the receiver can
#   see it. Net two cannot tell that receiver from an unrelated object, and it
#   does not pretend to - it reports the reach and says the receiver was not
#   resolved.
#
#   NET THREE, ANCHORED ON THE BINDING. `var {use} = window.claude` binds the
#   request to a bare name, and after that neither the receiver nor the
#   property appears anywhere - the call is `use("artifact")` and nets one and
#   two both walk past it. Found by probing this check with spellings it had
#   not been written for, which is the only way any of these were found. So a
#   destructuring pattern that binds `use` off the capability object is read
#   as a reach in its own right. It is anchored on all three of braces, the
#   bound name and the assignment to `claude`, so prose cannot trip it.
#
# WHAT IS DELIBERATELY NOT MATCHED, SO THIS DOES NOT CRY WOLF. This runs
# against a half-megabyte generated page carrying prose, JSON, file listings
# and code, and a check that fires on discussion of capabilities gets switched
# off within a week. So NONE of the following is matched: the words
# `capability`, `downloads`, `artifact` or `publish` in text; `use` as an
# English word; `{use: 1}` as an object key; `.claude/...` and `.claude-plugin`
# as path text, of which the real page carries over a hundred. Only the CALL
# SYNTAX on a property named `use` matches. Measured, not assumed: on the real
# generated page the two nets together match exactly two places, and both are
# the one `downloads` request the builder emits.
#
#   THE PRICE OF NET TWO, WRITTEN DOWN. A page that embeds unrelated
#   JavaScript spelling `.use(` - middleware, a plug-in registry - is a false
#   positive, and it is a loud one that names what it found. That is the trade:
#   an alias of the capability object and an unrelated object are the same
#   bytes without an evaluator, and the safe reading of an unresolved receiver
#   is "not shown to be absent". The other price is the same one in prose: a
#   page that QUOTES the call syntax in its text, rather than executing it, is
#   a finding too. This check reads bytes, not an abstract syntax tree, and it
#   cannot tell a quoted example from code.
#
# THE RULE THAT MATTERS: AN UNREADABLE DECLARATION IS NEVER COUNTED AS AN
# ABSENT ONE. Every outcome below is a finding for the same reason, and it is
# the reason 1.0 failed: silence is what let the bracket form through.
#
#   an output capability          `downloads` - reported, not a finding
#   a self-publishing capability  a finding, named
#   any other readable name       a finding. An unrecognised name is not
#                                 evidence of safety
#   a computed or escaped key     a finding - what the page reached cannot be
#                                 read out of the file
#   a non-literal argument        a finding - a name computed at run time is
#                                 not in the page at all
#   `use` taken as a value        a finding, unless it sits in a truthiness
#                                 test (`!window.claude.use`, `typeof`, an
#                                 `if (...)` head), which declares nothing.
#                                 The shipped page uses that guard, and a
#                                 check that fails the real dashboard is
#                                 useless
#   any other property reached    a finding. This check classifies the
#   on the capability object      capability request and nothing else
#
# THE R31 BOUNDARY, AND THIS CHECK DOES NOT CLOSE IT. R31's obligation is that
# THE LIFECYCLE REFUSES TO PUBLISH. That refusal is asserted by
# check-view-publish-refused.sh, which drives the real hook and watches it
# decline. What this check asserts is the earlier and weaker half: the page
# does not ASK. 2.0 strengthens that half - it now holds against a spelling
# 1.0 walked past - and it moves R31's verdict not at all on its own.
#
# THE SAME BOUNDARY FOR R30. R30 says the lifecycle SHALL USE a capability that
# writes only to the viewer's device. This reads what the page asks for and
# accepts only `downloads`. It does not observe the file arriving on the
# viewer's device, and it cannot see a capability GRANTED IN THE PUBLISH CALL
# and never requested by the page - that surface belongs to the publish gate.
#
# THIS CHECK WRITES NOTHING INTO THE REPOSITORY IT IS CHECKING. A check that
# mutates what it is checking is the bug it exists to catch. The page is
# generated into a temporary directory that is removed on exit, and the
# repository is opened read-only.
#
# THE FIXTURE CORPUS, AND WHY THE CLASSIFIER IS NOT TRUSTED ON THE REAL PAGE
# ALONE. The real page is clean, and a classifier that matched nothing at all
# would also call it clean. So the same classifier is run over a corpus of
# small pages under fixtures/view-readonly, each one declaring something known,
# and the corpus carries both directions: pages that MUST be flagged, spelled
# every way the audit and this file could think of, and pages that MUST NOT be,
# including one that discusses capabilities at length and declares none.
#
# SIX ASSERTIONS, COUNTED SEPARATELY. A single `ok` flag reported above six
# lines of evidence is how a check in this repo printed `upheld: 0` while
# holding six things; each group below carries its own case count and its own
# upheld count, and a group is upheld only when every case in it is.
#
#   A1  the generator moved no repository file
#   A2  the real generated page declares nothing beyond output
#   A3  an evasive SPELLING of the capability request is still classified -
#       bracket, quote, whitespace, newline, optional chaining, alias
#   A4  a declaration this check CANNOT READ is a finding, never an absence
#   A5  a readable capability name that is not output-only is a finding
#   A6  a page that declares nothing forbidden is NOT flagged. A gate that
#       flags every page is as broken as one that flags none, and it is
#       switched off just as fast
#
# THE PREMISE IS GUARDED. If the fixture corpus is missing, or holds no case
# for one of A3-A6, or if the classifier read no capability name anywhere in
# it, then it swept an empty set and this run asserts nothing about it - exit
# 2, unmeasured, never a pass. An assertion with no positive case has already
# shipped in this repo once and sat green for weeks.
#
# KNOWN LIMITATION, WRITTEN DOWN RATHER THAN HIDDEN. The grant is made when the
# page is published, not inside the page. This check reads the page's bytes, so
# it sees what the page ASKS FOR. A capability granted at publish time and
# never used by the page leaves no trace in the file and is out of reach here;
# check-view-publish-refused.sh reaches that surface.
#
# THE OTHER KNOWN LIMITATION. The two hashes bracket the generator's run, so
# anything else that writes to the tree inside that window is attributed to the
# generator. That is the honest reading - the check cannot tell one writer from
# another - and it is a false positive when an editor saves, or a second agent
# works in the same tree, while this is running. A finding here names the file,
# so the first thing to do with one is look at whether that file has anything
# to do with building a view.
#
# AND ONE MORE. The classifier does not strip JavaScript comments or string
# context. A capability request inside a commented-out block is reported as
# though it were live, and a request assembled from bytes no reader can follow
# - a name pulled out of an array, an eval - is reported as unreadable rather
# than resolved. Both fail loud. Nothing here defeats an evaluator.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every file hashed, nothing changed, no capability beyond output, and
#      every fixture case reached the classification it must
#   1  findings - a repository file moved, the page declared something it may
#      not, or the classifier called a case wrong
#   2  could not run - bad usage, no work tree, no builder, no fixture corpus,
#      an unreadable file, or a page that could not be generated at all. A page
#      that was never built has an UNKNOWN number of capability declarations,
#      never a measured zero.
#
# WHAT IT PRINTS. One BARE PATH per line for every repository file examined,
# repo-relative, which is what the runner parses as coverage. Findings and
# notes are INDENTED. Nothing absolute is ever printed: this output is tailed
# into a committed result file, and an absolute path there is somebody's home
# directory published to everyone who clones the repo.
#
# PORTABILITY. Developed on macOS/BSD and must hold on GNU. No GNU-only and no
# BSD-only behaviour: no `stat` flags, no `mapfile`, no `grep -P`, no in-place
# `sed`. This repo once shipped a `stat -f %m` that SUCCEEDS on GNU meaning
# something else, so CI was red while macOS was green. Everything that reads a
# file here is python3 through a quoted here-doc. Nothing suppresses stderr.
set -euo pipefail

VERSION="check-view-readonly 2.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT=""
BUILDER=""
FIXTURE=""

die_unmeasured() { printf 'check-view-readonly: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)      [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)    ROOT="${1#--root=}";       shift ;;
    --builder)   [ "$#" -ge 2 ] || die_unmeasured "--builder needs a path"; BUILDER="$2"; shift 2 ;;
    --builder=*) BUILDER="${1#--builder=}"; shift ;;
    --fixture)   [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*) FIXTURE="${1#--fixture=}"; shift ;;
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

[ -n "$FIXTURE" ] || FIXTURE="$HERE/../fixtures/view-readonly"
[ -d "$FIXTURE" ] \
  || die_unmeasured "no fixture corpus at the path given. The classifier would run only against a page that is clean, and a classifier that matched nothing would call that page clean too. Unmeasured, not a pass"
FIXTURE="$(cd "$FIXTURE" && pwd -P)"
CASES="$FIXTURE/cases.tsv"
[ -f "$CASES" ] && [ -r "$CASES" ] \
  || die_unmeasured "no readable cases.tsv in the fixture corpus; there is nothing to hold the classifier to"

command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the tree could not be hashed"

# The case file's shape is checked BEFORE any case is judged. `read` pads
# missing fields with empty strings, so a short row would otherwise arrive
# looking like a case with an empty expectation and be judged rather than
# refused.
#
# `|| :` is load-bearing and is not tolerance of an unknown failure: awk exits 1
# exactly when it found a bad row, which is the condition being detected, and
# under `set -e` with `pipefail` that status would kill the script here - right
# exit code, and no reason printed at all.
_badrow="$(awk -F'\t' '/^#/ || NF == 0 { next } NF != 5 { printf "%d ", NR; bad = 1 } END { exit bad ? 1 : 0 }' "$CASES" || :)"
[ -z "$_badrow" ] || die_unmeasured "cases.tsv has rows that are not five tab-separated fields (line(s): $_badrow). A case file this check cannot read is not one it may guess at"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Paths are printed repo-relative. An absolute path in this output is somebody's
# home directory in a committed file.
rel() { case "$1" in "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;; *) printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;; esac; }

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
"""Compare two snapshots.

stdout is ONE BARE PATH per examined file and nothing else - the caller prints
it straight through as coverage, so a summary line loose in this stream would
be read as a file path. Counts and findings go to the report file named as
argv[3], as `hashed<TAB>n`, `moved<TAB>n` and `finding<TAB>text`.

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

with open(sys.argv[3], "w") as rep:
    rep.write("hashed\t%d\n" % len(set(before) | set(after)))
    rep.write("moved\t%d\n" % len(findings))
    for f in findings:
        rep.write("finding\t%s\n" % f)
PY

cat > "$TMP/caps.py" <<'PY'
"""Read what a page REACHES FOR, not how it spells it.

Called with PATH DISPLAY pairs; emits one block per file:

    file<TAB>DISPLAY
    bytes<TAB>n | readable<TAB>n | note<TAB>text | finding<TAB>text | findings<TAB>n
    end

or `unreadable<TAB>reason` in place of the counts. The caller decides what to
print; nothing here writes an absolute path.

Two nets. Net one is anchored on the RECEIVER - the identifier `claude`,
optionally `window.claude` - and resolves the property and the argument across
whitespace, newlines, bracket keys and optional chaining. Net two is anchored
on the PROPERTY - any `.use(` or `["use"](` net one did not claim - and catches
an alias, whose call site never names the capability object at all.

An unreadable declaration is never counted as an absent one: a computed key, an
escaped key and a computed argument are findings, because a name that is not in
the file has not been shown to be output-only.
"""
import re
import sys

OUTPUT_ONLY = {"downloads"}
SELF_PUBLISHING = {
    "artifact": "publishes new versions of the page itself",
    "self": "publishes new versions of the page itself",
}

IDENT = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
# `claude` as a whole identifier, not the `.claude/...` path text the real page
# carries over a hundred times - those are followed by `/` or `-`, never by a
# property access, and the access is what the caller below insists on.
RECV = re.compile(r"(?<![A-Za-z0-9_$])(?:window\s*(?:\?\s*)?\.\s*)?claude(?![A-Za-z0-9_$])")
PROP = re.compile(r"""\.\s*use(?![A-Za-z0-9_$])|\[\s*(['"])use\1\s*\]""")
# A truthiness test declares nothing, and the shipped page uses one. Kept tight
# on purpose: `,` and `=` are NOT here, because passing or storing the method is
# how it gets called somewhere this file cannot see.
GUARD = re.compile(r"""(?:!|&&|\|\||typeof|\bif\s*\(|\bwhile\s*\()\s*$""")
# `var {use} = window.claude` - the request bound to a bare name, after which
# neither the receiver nor the property is written anywhere. Anchored on braces,
# on the bound name and on the assignment, so prose about capabilities cannot
# reach it.
DESTRUCT = re.compile(r"\{[^{}]*(?<![A-Za-z0-9_$])use(?![A-Za-z0-9_$])[^{}]*\}\s*=\s*$")
WS = " \t\r\n"


def skip(src, i):
    while i < len(src) and src[i] in WS:
        i += 1
    return i


def read_access(src, i):
    """Resolve the property reached at i. -> (kind, name, end)."""
    j = skip(src, i)
    if j < len(src) and src[j] == "?":
        k = skip(src, j + 1)
        if k < len(src) and src[k] in ".[":
            j = k
        else:
            # `claude ? a : b` is a ternary on the object, not a property of it.
            return ("none", None, i)
    if j >= len(src):
        return ("none", None, i)
    if src[j] == ".":
        j = skip(src, j + 1)
        m = IDENT.match(src, j)
        if not m:
            return ("unreadable", None, j)
        return ("name", m.group(0), m.end())
    if src[j] == "[":
        end = src.find("]", j + 1)
        if end < 0:
            return ("unreadable", None, j + 1)
        inner = src[j + 1:end].strip()
        # A plain quoted key and nothing else. A backslash means the bytes in
        # the file are not the name the runtime receives, which is unreadable
        # rather than resolved.
        if (len(inner) >= 2 and inner[0] == inner[-1] and inner[0] in "\"'"
                and "\\" not in inner and inner[0] not in inner[1:-1]):
            return ("name", inner[1:-1], end + 1)
        return ("unreadable", None, end + 1)
    return ("none", None, i)


def read_call(src, i):
    """Index of the opening paren of a call at i, or -1."""
    j = skip(src, i)
    if j < len(src) and src[j] == "?":
        k = skip(src, j + 1)
        if k < len(src) and src[k] == ".":
            k = skip(src, k + 1)
            if k < len(src) and src[k] == "(":
                return k
        return -1
    if j < len(src) and src[j] == "(":
        return j
    return -1


def read_arg(src, i):
    """First argument of the call whose paren is at i. -> (kind, raw)."""
    j = skip(src, i + 1)
    if j >= len(src):
        return ("nonliteral", None)
    if src[j] == ")":
        return ("absent", None)
    q = src[j]
    if q not in "\"'":
        # A backtick template, an identifier, a call - none of them is a name
        # this file can read.
        return ("nonliteral", None)
    k = j + 1
    esc = False
    while k < len(src):
        ch = src[k]
        if esc:
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == q:
            break
        elif ch == "\n":
            return ("nonliteral", None)
        k += 1
    else:
        return ("nonliteral", None)
    raw = src[j + 1:k]
    after = skip(src, k + 1)
    # `"art" + "ifact"` is two literals and an operator, not one name.
    if after < len(src) and src[after] not in ",)":
        return ("nonliteral", None)
    if "\\" in raw:
        return ("escaped", raw)
    return ("literal", raw)


def guarded(src, start):
    return bool(GUARD.search(src[max(0, start - 24):start]))


def classify_name(name, how):
    if name in SELF_PUBLISHING:
        return ("finding", "declares `%s`, which %s. A view is output; a page that saves over "
                           "itself is a second source of truth that can disagree with the "
                           "repository (%s)" % (name, SELF_PUBLISHING[name], how))
    if name in OUTPUT_ONLY:
        return ("note", "declares `%s` - output: it hands the viewer a file and reads nothing "
                        "back (%s)" % (name, how))
    return ("finding", "declares `%s`, which this check cannot classify. An unrecognised "
                       "capability has not been shown to be output-only; classify it here or "
                       "stop declaring it (%s)" % (name, how))


def call_verdict(src, callpos, how):
    """-> ((kind, text), resolved_a_name)."""
    kind, raw = read_arg(src, callpos)
    if kind == "literal":
        return classify_name(raw, how), True
    if kind == "escaped":
        return ("finding", "a capability name written with a string escape, so the bytes in the "
                           "file are not the name the runtime receives. It cannot be read out "
                           "of the page, and unreadable is never absent (%s)" % how), False
    if kind == "absent":
        return ("finding", "a capability request with no name in it. Nothing was declared that "
                           "this check could read, which is not the same as nothing being "
                           "declared (%s)" % how), False
    return ("finding", "a capability name that is not a string literal; it is computed at run "
                       "time and cannot be read out of the page, so it is not readable as "
                       "absent either (%s)" % how), False


def scan(src):
    findings, notes, readable, claimed = [], [], 0, []
    for m in RECV.finditer(src):
        kind, name, end = read_access(src, m.end())
        if kind == "none":
            if DESTRUCT.search(src[max(0, m.start() - 160):m.start()]):
                findings.append("binds the capability request off the capability object by "
                                "destructuring, so the call site names neither the object nor "
                                "the property. What it goes on to ask for cannot be read from "
                                "this line, and unknown is not none")
            continue
        claimed.append((m.end(), end))
        if kind == "unreadable":
            findings.append("a property of the capability object whose name this check cannot "
                            "read out of the file - computed at run time, or written with a "
                            "string escape so the bytes are not the name. Unreadable is never "
                            "counted as absent")
            continue
        if name != "use":
            findings.append("reaches `%s` on the capability object. This check classifies the "
                            "capability request only; a page reaching anything else on that "
                            "object has not been shown to be read-only" % name)
            continue
        callpos = read_call(src, end)
        if callpos < 0:
            if guarded(src, m.start()):
                notes.append("names the capability request in a truthiness test without calling "
                             "it; a test declares nothing")
            else:
                findings.append("takes the capability request as a value without calling it "
                                "here. Where it is called cannot be read from this line, so "
                                "what it asks for is unknown - and unknown is not none")
            continue
        (vk, vt), ok = call_verdict(src, callpos, "named on the capability object")
        (findings if vk == "finding" else notes).append(vt)
        if ok:
            readable += 1
    for m in PROP.finditer(src):
        if any(a <= m.start() < b for a, b in claimed):
            continue
        callpos = read_call(src, m.end())
        if callpos < 0:
            if guarded(src, m.start()):
                notes.append("a property named `use` read on a receiver this check cannot "
                             "resolve, inside a truthiness test")
                continue
            findings.append("a property named `use` taken as a value on a receiver this check "
                            "cannot resolve to the capability object. If that receiver is the "
                            "capability object, this is a request whose name never appears here")
            continue
        (vk, vt), _ = call_verdict(
            src, callpos,
            "called as `use` on a receiver this check cannot resolve to the capability object")
        # Even an output-only name is a finding here: the NAME is readable and
        # the RECEIVER is not, and an alias of the capability object is the
        # same bytes as an unrelated one. Loud, and it says which it is.
        findings.append(vt if vk == "finding" else
                        "calls `use` with an output-only name on a receiver this check cannot "
                        "resolve to the capability object. The name is readable and the "
                        "receiver is not")
    return findings, notes, readable


def emit(path, display):
    out = sys.stdout
    out.write("file\t%s\n" % display)
    try:
        with open(path, errors="replace") as fh:
            src = fh.read()
    except OSError as exc:
        out.write("unreadable\t%s\n" % (exc.strerror or "could not be opened"))
        out.write("end\n")
        return
    if not src.strip():
        out.write("unreadable\tthe file is empty\n")
        out.write("end\n")
        return
    findings, notes, readable = scan(src)
    out.write("bytes\t%d\n" % len(src))
    out.write("readable\t%d\n" % readable)
    for n in notes:
        out.write("note\t%s\n" % n)
    for f in findings:
        out.write("finding\t%s\n" % f)
    out.write("findings\t%d\n" % len(findings))
    out.write("end\n")


args = sys.argv[1:]
if not args or len(args) % 2:
    sys.stderr.write("caps.py: expects PATH DISPLAY pairs\n")
    sys.exit(2)
for a in range(0, len(args), 2):
    emit(args[a], args[a + 1])
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

python3 "$TMP/cmp.py" "$TMP/before_union" "$TMP/after" "$TMP/tree.report" > "$TMP/tree.paths" \
  || die_unmeasured "the before/after comparison did not complete"

# --- coverage ---------------------------------------------------------------
#
# The tree listing already names every repository file, fixtures included, so a
# fixture path is printed only when it is NOT in that listing - a duplicate
# would claim the same file twice. `grep -q` exits 1 on no-match, which is the
# answer being asked for and not an error, so it is asked inside an `if` and
# never left to `set -e` to act on.
cat "$TMP/tree.paths"
print_if_unlisted() {
  local r; r="$(rel "$1")"
  if grep -qxF "$r" "$TMP/tree.paths"; then return 0; fi
  printf '%s\n' "$r"
}
print_if_unlisted "$CASES"

# --- A1: the generator moved no repository file -----------------------------
A1_N="$(awk -F'\t' '$1 == "hashed" { print $2 }' "$TMP/tree.report")"
A1_MOVED="$(awk -F'\t' '$1 == "moved" { print $2 }' "$TMP/tree.report")"
A1_OK=$((A1_N - A1_MOVED))
awk -F'\t' '$1 == "finding" { printf "  FINDING: %s\n", $2 }' "$TMP/tree.report"

# --- the page, and the corpus that holds the classifier to its job ----------
if [ "$BRC" -ne 0 ]; then
  printf '  the view generator exited %s. Its output is not reproduced here: it can carry an absolute path, and this text is tailed into a committed result file.\n' "$BRC"
  printf '  capability declarations read: unknown\n'
  printf '  REFUSED: the page could not be generated, so the number of capabilities it declares is unknown. Unknown is not zero.\n'
  if [ "$A1_MOVED" -ne 0 ]; then printf '  the tree comparison above still stands and found something.\n'; fi
  exit 2
fi

# One python invocation for the real page and the whole corpus. Sixteen
# interpreter starts for sixteen tiny files is the kind of cost that gets a
# check moved out of the default run.
set -- "$PAGE" "generated-page"
while IFS=$'\t' read -r _id _expect _group page _note; do
  case "${_id:-}" in ''|'#'*) continue ;; esac
  fp="$FIXTURE/pages/$page"
  [ -f "$fp" ] && [ -r "$fp" ] \
    || die_unmeasured "case '$_id' names a page that is not there or cannot be read. A corpus this check cannot read is not one that passed"
  print_if_unlisted "$fp"
  set -- "$@" "$fp" "$page"
done < "$CASES"

python3 "$TMP/caps.py" "$@" > "$TMP/caps.tsv" \
  || die_unmeasured "the classifier did not complete, so what the page and the corpus declare is unknown"

blockfield() {
  # $1 display name, $2 field. Empty when the block carries no such field.
  awk -F'\t' -v want="$1" -v key="$2" \
    '$1 == "file" { cur = ($2 == want); next }
     cur && $1 == key { print $2; exit }' "$TMP/caps.tsv"
}

# --- A2: the real generated page declares nothing beyond output -------------
A2_N=1
A2_OK=0
PAGE_UNREADABLE="$(blockfield generated-page unreadable)"
if [ -n "$PAGE_UNREADABLE" ]; then
  printf '  the generated page could not be read: %s\n' "$PAGE_UNREADABLE"
  printf '  capability declarations read: unknown\n'
  printf '  REFUSED: the page could not be read, so the number of capabilities it declares is unknown. Unknown is not zero.\n'
  if [ "$A1_MOVED" -ne 0 ]; then printf '  the tree comparison above still stands and found something.\n'; fi
  exit 2
fi
PAGE_BYTES="$(blockfield generated-page bytes)"
PAGE_READABLE="$(blockfield generated-page readable)"
PAGE_FINDINGS="$(blockfield generated-page findings)"
printf '  page bytes read: %s\n' "$PAGE_BYTES"
printf '  capability declarations read on the generated page: %s\n' "$PAGE_READABLE"
awk -F'\t' '$1 == "file" { cur = ($2 == "generated-page"); next }
            cur && $1 == "note" { printf "  the generated page %s\n", $2 }
            cur && $1 == "finding" { printf "  FINDING: the generated page %s\n", $2 }' "$TMP/caps.tsv"
if [ "$PAGE_FINDINGS" -eq 0 ]; then A2_OK=1; fi

# --- A3-A6: the corpus ------------------------------------------------------
#
# Per-assertion tallies. Never one flag: a group is upheld only when its own
# count of upheld cases equals its own count of cases.
A3_N=0; A3_OK=0     # an evasive spelling is still classified
A4_N=0; A4_OK=0     # a declaration that cannot be read is a finding
A5_N=0; A5_OK=0     # a readable name that is not output-only is a finding
A6_N=0; A6_OK=0     # a page declaring nothing forbidden is not flagged
CORPUS_READABLE=0
CASE_FINDINGS=0
CASE_LINES="$TMP/caselines"
: > "$CASE_LINES"

while IFS=$'\t' read -r id expect group page _note; do
  case "${id:-}" in ''|'#'*) continue ;; esac
  un="$(blockfield "$page" unreadable)"
  if [ -n "$un" ]; then
    die_unmeasured "case '$id' named a page the classifier could not read. A corpus case that was never classified is unmeasured, not a pass"
  fi
  n="$(blockfield "$page" findings)"
  r="$(blockfield "$page" readable)"
  CORPUS_READABLE=$((CORPUS_READABLE + r))

  got=clean
  if [ "$n" -gt 0 ]; then got=finding; fi
  ok=0
  case "$expect" in
    finding) if [ "$got" = finding ]; then ok=1; fi ;;
    clean)   if [ "$got" = clean ];   then ok=1; fi ;;
    *) die_unmeasured "case '$id' expects '$expect', which is not one of finding, clean. An expectation this check cannot read is not one it may skip" ;;
  esac

  case "$group" in
    spelling)   A3_N=$((A3_N + 1)); if [ "$ok" = 1 ]; then A3_OK=$((A3_OK + 1)); fi ;;
    unreadable) A4_N=$((A4_N + 1)); if [ "$ok" = 1 ]; then A4_OK=$((A4_OK + 1)); fi ;;
    forbidden)  A5_N=$((A5_N + 1)); if [ "$ok" = 1 ]; then A5_OK=$((A5_OK + 1)); fi ;;
    clean)      A6_N=$((A6_N + 1)); if [ "$ok" = 1 ]; then A6_OK=$((A6_OK + 1)); fi ;;
    *) die_unmeasured "case '$id' names group '$group', which this check cannot count. A case counted under nothing is a case that asserts nothing" ;;
  esac

  if [ "$ok" = 1 ]; then
    printf '  case %s (%s): expected %s, got %s\n' "$id" "$group" "$expect" "$got" >> "$CASE_LINES"
  else
    printf '  case %s (%s): expected %s, GOT %s\n' "$id" "$group" "$expect" "$got" >> "$CASE_LINES"
    CASE_FINDINGS=$((CASE_FINDINGS + 1))
    if [ "$expect" = finding ]; then
      printf '  FINDING: %s: a page that reaches the capability was classified clean. This is the 1.0 hole exactly: a declaration the check cannot see is reported as a declaration that is not there\n' "$id" >> "$CASE_LINES"
    else
      printf '  FINDING: %s: a page that declares nothing forbidden was flagged. A check that cries wolf on the real dashboard gets switched off, and then nothing is asserted at all\n' "$id" >> "$CASE_LINES"
    fi
  fi
done < "$CASES"

cat "$CASE_LINES"

# --- the premises, guarded --------------------------------------------------
#
# Each of these is a classification that was never exercised. A group with no
# case in it holds vacuously forever, which is the shape of a check that passes
# for months without once seeing the thing it looks for.
[ "$((A3_N + A4_N + A5_N + A6_N))" -gt 0 ] \
  || die_unmeasured "the corpus held no case at all. The classifier was run against a clean page and nothing else, and a classifier that matched nothing would call that page clean too. Unmeasured, not a pass"
[ "$A3_N" -gt 0 ] || die_unmeasured "no corpus case spells the capability request any way but the plain one, so the evasion that defeated the 1.0 check was never exercised. Unmeasured, not a pass"
[ "$A4_N" -gt 0 ] || die_unmeasured "no corpus case declares something this check cannot read, so whether an unreadable declaration is treated as an absent one was never exercised. Unmeasured, not a pass"
[ "$A5_N" -gt 0 ] || die_unmeasured "no corpus case names a capability that is not output-only, so the classification this check exists for was never exercised. Unmeasured, not a pass"
[ "$A6_N" -gt 0 ] || die_unmeasured "no corpus case must come back CLEAN, so this run cannot tell a classifier that reads from one that flags everything. Unmeasured, not a pass"
[ "$CORPUS_READABLE" -gt 0 ] \
  || die_unmeasured "the classifier read no capability name anywhere in the corpus. Every finding it reported could have come from a pattern that matches nothing and refuses everything, and no positive case proves otherwise. Unmeasured, not a pass"

groups_ok=0
report() { printf '  %s: cases %s, upheld %s\n' "$2" "$1" "$3"; }
for g in \
  "$A1_N|A1 the generator moved no repository file|$A1_OK" \
  "$A2_N|A2 the real generated page declares nothing beyond output|$A2_OK" \
  "$A3_N|A3 an evasive spelling of the capability request is still classified|$A3_OK" \
  "$A4_N|A4 a declaration this check cannot read is a finding, never an absence|$A4_OK" \
  "$A5_N|A5 a capability name that is not output-only is a finding|$A5_OK" \
  "$A6_N|A6 a page that declares nothing forbidden is not flagged|$A6_OK"
do
  n="${g%%|*}"; restg="${g#*|}"; label="${restg%%|*}"; okn="${restg##*|}"
  report "$n" "$label" "$okn"
  # An `if`, not `[ ... ] && ...`: an AND-list whose test fails is the last
  # command of this loop body, and that is the `set -e` shape that has killed
  # scripts in this repo mid-branch - right exit code, no reason printed.
  if [ "$n" = "$okn" ]; then groups_ok=$((groups_ok + 1)); fi
done
printf '  capability names read across the corpus: %d\n' "$CORPUS_READABLE"
printf '  assertion groups: 6, upheld: %d\n' "$groups_ok"

if [ "$A1_MOVED" -ne 0 ] || [ "$PAGE_FINDINGS" -ne 0 ] || [ "$CASE_FINDINGS" -ne 0 ] || [ "$groups_ok" -ne 6 ]; then
  printf '  R4 not satisfied: see the findings above.\n'
  exit 1
fi
printf '  R4 satisfied: the generator moved no repository file, the page declares nothing beyond output, and the classifier that says so was held to a corpus that spells the same request every other way this file could find.\n'
exit 0
