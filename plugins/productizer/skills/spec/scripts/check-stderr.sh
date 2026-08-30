#!/usr/bin/env bash
# check-stderr.sh [--version] [--allow ENTRY]... <file>...
#
# Refuses shell that throws stderr away. Discarding stderr makes an ERROR and a
# genuine NO-MATCH look identical, and once they look identical the run is
# green either way. In one session that cost three real defects: a count that
# was wrong, an absence that was not an absence, and a check that examined
# nothing and reported a pass.
#
# WHAT IT REFUSES (any of these on a line of shell):
#
#   stderr redirected to the bit bucket   - 2 > /dev/null, 2 >> /dev/null
#   stderr closed outright                - 2 >&-
#   both streams to the bit bucket        - &> /dev/null, >& /dev/null
#   stdout binned, then stderr folded in  - > /dev/null 2>&1
#
# Spelled with spaces above only so the list reads; the check matches the usual
# spelling with no spaces too. These lines are comments, and a comment cannot
# redirect anything, so they are skipped either way.
#
# WHAT IT DOES NOT REFUSE, ON PURPOSE:
#
#   > /dev/null on its own. Binning stdout says nothing about errors; stderr
#   still reaches the terminal, the log and the caller. Only stderr is at
#   stake here.
#
#   `command -v x > /dev/null 2>&1`. This is an existence TEST: the answer is
#   the exit status, and the only thing on stderr is "not found" noise about a
#   question already answered. It is exempt structurally, with no allowlist
#   entry, because writing it out per call site would train people to write
#   allowlist entries. Nothing else is exempt structurally.
#
#   A line whose first non-blank character is `#`. A comment cannot redirect
#   anything. KNOWN LIMITATION: a here-doc that writes a file in a language
#   where `#` is not a comment could hide a suppression on such a line. No
#   such case exists in this repo; it is a hole, and it is written down.
#
# HOW TO EXEMPT SOMETHING, AND WHY IT COSTS A SENTENCE
#
# Two mechanisms. Both demand a written reason, and BOTH REFUSE THE RUN when
# the reason is missing or shorter than MIN_REASON characters. A check that can
# be silenced without saying why is the thing this check exists to prevent, so
# a bare silencer is exit 2 - not a pass, and not even a finding.
#
#   1. INLINE, for code you can edit. Put a marker on the same line:
#
#          risky_thing 2>/dev/null   # stderr-ok: <reason>
#
#      The reason is everything after the colon. It exempts that whole line.
#
#   2. ALLOWLIST, for code you cannot or should not edit - a vendored script,
#      or a file another owner is holding. Entries are passed as arguments, so
#      they live in the committed checks.yaml next to the check that grants
#      them and are reviewed in the same diff:
#
#          --allow 'FILE::SNIPPET::REASON'
#
#      FILE     the scanned path, or any trailing path-segment suffix of it
#      SNIPPET  a LITERAL substring of the offending line, which MUST ITSELF
#               contain the redirection. An entry that does not is refused:
#               a snippet naming only the surrounding code exempts the whole
#               line forever, including a suppression added tomorrow. Every
#               occurrence of the snippet is cut out of the line and what
#               remains is scanned again, so an entry can only ever excuse the
#               exact redirection it quotes.
#      REASON   >= MIN_REASON characters. Empty is exit 2.
#
# THIS FILE IS SCANNED LIKE EVERY OTHER. It carries no self-exemption: the
# patterns are written so that the definitions do not match themselves. Run it
# on itself; that is the positive control.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every file read, no suppressed stderr
#   1  suppressed stderr found - reported by file and line
#   2  COULD NOT MEASURE. An unreadable file, or an exemption with no reason.
#      Never confused with 0: a file nobody could open is not a clean file.
set -euo pipefail

VERSION="check-stderr 1.0"
MIN_REASON=12

usage() { printf 'usage: check-stderr.sh [--version] [--allow FILE::SNIPPET::REASON]... <file>...\n' >&2; }

ALLOW_TMP="$(mktemp "${TMPDIR:-/tmp}/check-stderr.XXXXXX")"
trap 'rm -f "$ALLOW_TMP"' EXIT HUP INT TERM

FILES=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --allow)
      [ "$#" -ge 2 ] || { printf 'check-stderr: --allow needs FILE::SNIPPET::REASON\n' >&2; exit 2; }
      printf '%s\n' "$2" >> "$ALLOW_TMP"
      shift 2
      ;;
    --) shift; while [ "$#" -gt 0 ]; do FILES+=("$1"); shift; done ;;
    -*) printf 'check-stderr: unknown option %s\n' "$1" >&2; usage; exit 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

if [ "${#FILES[@]}" -eq 0 ]; then
  printf 'check-stderr: no files given. Nothing scanned is not a clean scan.\n' >&2
  usage
  exit 2
fi

for f in "${FILES[@]}"; do
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    printf 'check-stderr: cannot read %s. Unmeasured, not clean.\n' "$f" >&2
    exit 2
  fi
done

rc=0
awk -v allowfile="$ALLOW_TMP" -v minreason="$MIN_REASON" '
function strip_literal(s, lit,   i) {
  if (lit == "") return s
  while ((i = index(s, lit)) > 0)
    s = substr(s, 1, i - 1) substr(s, i + length(lit))
  return s
}
function suffix_match(path, f,   tail) {
  if (path == f) return 1
  tail = "/" f
  if (length(path) <= length(tail)) return 0
  return substr(path, length(path) - length(tail) + 1) == tail
}
function rindex(s, t,   i, at, last) {
  last = 0; i = 1
  while ((at = index(substr(s, i), t)) > 0) {
    last = i + at - 1
    i = last + 1
  }
  return last
}
function trim(s) {
  sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
  return s
}
BEGIN {
  # The one definition of "stderr was thrown away". Deliberately written so
  # that this very line does not match it: every branch needs a literal
  # /dev/null or a - immediately after the redirection, and here a bracket
  # follows instead. That is why this file needs no self-exemption.
  SUP = "2[ \t]*>>?[ \t]*/dev/null|2[ \t]*>&[ \t]*-|&>>?[ \t]*/dev/null|>&[ \t]*/dev/null|1?>>?[ \t]*/dev/null[ \t]+2[ \t]*>&[ \t]*1"
  CMDV = "command[ \t]+-v[ \t]+[^ \t;|&()]+[ \t]*(1?>>?[ \t]*/dev/null([ \t]*2[ \t]*>&[ \t]*1)?|&>>?[ \t]*/dev/null)"
  MARK = "#[ \t]*stderr-ok:"

  na = 0; bad = 0; found = 0
  while ((getline entry < allowfile) > 0) {
    if (entry == "") continue
    p1 = index(entry, "::")
    if (p1 == 0) {
      printf("check-stderr: allow entry %s is not FILE::SNIPPET::REASON\n", entry) > "/dev/stderr"
      bad = 1; continue
    }
    af = substr(entry, 1, p1 - 1)
    rest = substr(entry, p1 + 2)
    # LAST separator, not the first. A snippet very often ends in a colon -
    # `2>/dev/null || :` is the commonest shape in this repo - and splitting on
    # the first `::` silently ate the trailing colon, widening the snippet to
    # `2>/dev/null || ` and exempting every line that happened to contain it.
    # That was a real bug in this file, caught by fixture 4f. The cost is that
    # a REASON may not contain `::`.
    p2 = rindex(rest, "::")
    if (p2 == 0) {
      printf("check-stderr: allow entry for %s carries no reason. An exemption with no reason is refused, not honoured.\n", af) > "/dev/stderr"
      bad = 1; continue
    }
    as = substr(rest, 1, p2 - 1)
    ar = trim(substr(rest, p2 + 2))
    if (af == "" || as == "") {
      printf("check-stderr: allow entry %s names no file or no snippet\n", entry) > "/dev/stderr"
      bad = 1; continue
    }
    if (length(ar) < minreason) {
      printf("check-stderr: allow entry for %s gives reason %s (%d chars); a reason must be at least %d characters. Refused.\n", af, "\"" ar "\"", length(ar), minreason) > "/dev/stderr"
      bad = 1; continue
    }
    if (as !~ SUP) {
      printf("check-stderr: allow entry for %s quotes %s, which contains no stderr redirection. An entry that does not quote the redirection exempts the whole line forever. Refused.\n", af, "\"" as "\"") > "/dev/stderr"
      bad = 1; continue
    }
    na++
    AF[na] = af; AS[na] = as; AR[na] = ar
  }
  close(allowfile)
  if (bad) exit 2
}
FNR == 1 { print FILENAME }          # one line per file examined
{
  line = $0
  if (line ~ /^[ \t]*#/) next        # a comment cannot redirect

  if (match(line, MARK)) {
    reason = trim(substr(line, RSTART + RLENGTH))
    if (length(reason) < minreason) {
      printf("    %s:%d: stderr-ok marker with reason %s (%d chars); a reason must be at least %d characters. Refused, not exempted.\n", FILENAME, FNR, "\"" reason "\"", length(reason), minreason) > "/dev/stderr"
      bad = 1
    }
    next
  }

  gsub(CMDV, "", line)               # `command -v` is an existence test

  for (i = 1; i <= na; i++)
    if (suffix_match(FILENAME, AF[i]))
      line = strip_literal(line, AS[i])

  if (line ~ SUP) {
    printf("    %s:%d: stderr suppressed. An error and a genuine no-match are now indistinguishable. Remove it, or add a same-line `# stderr-ok: <reason>`, or an --allow entry quoting the redirection and giving a reason.\n", FILENAME, FNR)
    found = 1
  }
}
END {
  if (bad) exit 2
  if (found) exit 1
  exit 0
}
' "${FILES[@]}" || rc=$?
exit "$rc"
