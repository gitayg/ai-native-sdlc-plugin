#!/usr/bin/env bash
# spec-requirements.sh [--version] [--help] <spec-file>
#
# Parses the `## Requirements` section of a living spec and emits one TSV
# record per requirement DEFINITION:
#
#     <id> TAB <line> TAB <status> TAB <target> TAB <text>
#
#   status  one of active, superseded, withdrawn, malformed
#   target  R<n> for `superseded`, otherwise a single `-`
#   text    the requirement sentence with the status marker removed and all
#           whitespace collapsed to single spaces, so two spellings of the
#           same sentence across a re-wrap do not read as an edit
#
# NOT A CHECK. It has no findings and no coverage output; it is the one parser
# both `check-superseded-text.sh` and `check-pending-ruling-scope.sh` read the
# spec through. Two checks that must agree on what R14's text IS cannot each
# carry their own parser: the day the two disagree, one of them reports a
# requirement unchanged and the other reports it edited, and both are green in
# their own terms.
#
# THE GRAMMAR IS `references/format-spec.md`, not this file. Section 1 for the
# id form, section 3 for the status markers. Where this parser is deliberately
# more permissive than the normative grammar it is noted below - a parser that
# refuses a non-canonical spelling reports a requirement as absent, which is
# the one wrong answer that looks like nothing to do.
#
#   - The id separator may be an em dash, an en dash or a hyphen. format-spec
#     says a hyphen "parses but is non-canonical"; `validate-spec.py` warns on
#     it and this parser accepts it, because a warning about punctuation must
#     not make a superseded requirement invisible to the retention check.
#   - A requirement that wraps over several lines is joined. Only the first
#     marker-shaped line in the item is read as the status.
#   - A continuation line is read as a MARKER only when it begins with
#     `Superseded` or `Withdrawn` in any case. Anything else is requirement
#     text. Guessing more widely would let ordinary continuation prose flip a
#     requirement's status, and the status is what the whole retention rule
#     turns on.
#   - A second marker in one item is `malformed`, never "the first one wins".
#     Two markers is a requirement whose status is undefined, and picking one
#     is inventing the answer.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  parsed. Zero records is a legitimate parse of a spec with no
#      requirements, and it is the CALLER's job to refuse that as unmeasured
#      rather than to read it as nothing wrong.
#   2  could not run - bad usage, or a file that could not be read.
#
# There is no exit 1: this parser has no opinion about what it read.
set -euo pipefail

VERSION="spec-requirements 1.0"

usage() {
  printf 'usage: spec-requirements.sh [--version] [--help] <spec-file>\n'
  printf '  Emits: <id> TAB <line> TAB <status> TAB <target> TAB <text>\n'
}

die_unmeasured() { printf 'spec-requirements: %s\n' "$1" >&2; exit 2; }

FILE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'spec-requirements: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *)
      [ -z "$FILE" ] || die_unmeasured "one spec file at a time; got a second argument"
      FILE="$1"; shift ;;
  esac
done

[ -n "$FILE" ] || die_unmeasured "no spec file given"
[ -f "$FILE" ] && [ -r "$FILE" ] || die_unmeasured "cannot read $FILE"

awk '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

function emit(   t, i) {
  if (curid == "") return
  t = ""
  for (i = 1; i <= nbuf; i++) t = (t == "" ? buf[i] : t " " buf[i])
  gsub(/[\t]+/, " ", t)
  gsub(/  +/, " ", t)
  printf "%s\t%d\t%s\t%s\t%s\n", curid, curline, curstatus, curtarget, trim(t)
  curid = ""; nbuf = 0
}

function open_item(line,   rest, sep) {
  emit()
  match(line, /R[0-9]+/)
  curid = substr(line, RSTART, RLENGTH)
  curline = FNR
  curstatus = "active"
  curtarget = "-"
  nbuf = 0
  rest = substr(line, RSTART + RLENGTH)
  sub(/^\*\*/, "", rest)
  rest = trim(rest)
  # The separator: em dash, en dash or hyphen. See the header on why a
  # non-canonical one is accepted rather than treated as no requirement.
  # The dashes are written as octal escapes inside a STRING, not as \x inside
  # a regex literal: \x is a gawk extension that mawk does not read, and a
  # parser that silently stops recognising the em dash reports every
  # requirement in the file as text that begins with a dash.
  if (!sub("^" EMDASH "[ \t]*", "", rest))
    if (!sub("^" ENDASH "[ \t]*", "", rest))
      sub(/^-[ \t]*/, "", rest)
  if (rest != "") { nbuf++; buf[nbuf] = rest }
}

function marker(line,   l, t) {
  l = trim(line)
  if (l !~ /^[Ss]uperseded/ && l !~ /^[Ww]ithdrawn/) return 0
  if (curstatus != "active") { curstatus = "malformed"; curtarget = "-"; return 1 }
  if (match(l, /^Superseded by R[0-9]+\.([ \t].*)?$/)) {
    curstatus = "superseded"
    t = l; sub(/^Superseded by /, "", t)
    match(t, /^R[0-9]+/)
    curtarget = substr(t, RSTART, RLENGTH)
    return 1
  }
  if (l ~ /^Withdrawn\.([ \t].*)?$/) { curstatus = "withdrawn"; curtarget = "-"; return 1 }
  curstatus = "malformed"; curtarget = "-"
  return 1
}

BEGIN { ins = 0; curid = ""; nbuf = 0; EMDASH = "\342\200\224"; ENDASH = "\342\200\223" }

/^## / {
  emit()
  ins = ($0 ~ /^##[ \t]+Requirements[ \t]*$/) ? 1 : 0
  next
}
ins == 0 { next }
/^#/ { emit(); next }

/^-[ \t]+\*\*R[0-9]+\*\*/ { open_item($0); next }

# A blank line closes the list item. Anything unindented that is not a new
# item closes it too - the item ended and prose took over.
/^[ \t]*$/ { emit(); next }
/^[^ \t]/ { emit(); next }

curid != "" {
  if (marker($0)) next
  nbuf++; buf[nbuf] = trim($0)
  next
}

END { emit() }
' "$FILE"
