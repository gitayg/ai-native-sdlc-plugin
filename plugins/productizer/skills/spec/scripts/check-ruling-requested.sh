#!/usr/bin/env bash
# check-ruling-requested.sh [--version] [--help] [--root DIR]
#
# Asserts the ASK half of R23: IF AN INTENT CONTRADICTS AN ACTIVE REQUIREMENT,
# THEN THE LIFECYCLE SHALL STOP AND ASK WHICH WINS.
#
# The stop is already asserted elsewhere. Nothing asserted the ask, and that is
# backlog item B11: on a contradiction the lifecycle correctly stops, nobody is
# prompted for the decision, and work stops and stays stopped. A stop that asks
# nobody is indistinguishable from a stop that was never resolved.
#
# So this check does not re-observe the stop. It observes the artefact of the
# ask: a ruling file a human can actually act on, reachable from the spec.
#
# WHAT IT ASSERTS
#
#   1. EVERY OPEN CONCERN CITES A RULING THAT EXISTS. For each row in the
#      spec's *Areas of concern* whose status is `open: D<n>`, the file
#      `rulings/D<n>-*.md` must be there. A concern raised with no ruling file
#      is B11 exactly: halted, nothing written, nobody asked. A row whose
#      status is open and cites no ruling at all is the same failure one step
#      earlier - a question with nowhere to be answered.
#
#   2. EVERY PENDING RULING HAS ITS CONCERN ROW. For each `D<n>` whose header
#      status is `pending`, some `C<m>` row must cite it. Otherwise the ask is
#      invisible to everyone who reads the spec rather than the directory, and
#      the spec is where intake looks.
#
#   3. A PENDING RULING IS A REAL ASK, NOT A STUB. In a file whose status is
#      `pending`: `## The conflict`, `## The question` and both columns of the
#      `## What each side costs` table must be present and filled. Unfilled
#      means empty, or still carrying an angle-bracket placeholder copied out
#      of templates/ruling.md. A ruling still wearing the template is a file,
#      not a question.
#
#   4. THE HEADER BLOCK IS MACHINE-READABLE. `Status:` carries exactly one of
#      `pending`, `ruled`, `lapsed`, `superseded` and nothing else on the
#      line; every header field is present; an unset field is an em dash and
#      never blank. A blank value and a missing line are indistinguishable to
#      anything counting these files, and a counter that cannot tell them
#      apart reports a pending ruling as ruled - which is the count reading
#      clean while a contradiction is live.
#
# WHAT IT DELIBERATELY NEVER LOOKS AT
#
# Everything from `## Ruling` downward. Those sections are the human's, and a
# pending ruling is SUPPOSED to still carry their template guidance. Flagging
# them would demand that the agent pre-write the decision, which is the exact
# harm the whole design exists to prevent. The three sections above are named
# one by one rather than scanned as "everything before Ruling", so a file that
# is missing its `## Ruling` heading still cannot drag Reasoning, Not decided
# or Consequences into scope.
#
# NO FILE MEANS NO COUNT, NOT ZERO
#
#   no rulings/ directory        this repo has never raised a contradiction.
#                                Clean IF no concern row is open citing one -
#                                and a finding for every row that is, because
#                                that is precisely the halted-and-silent case.
#   a directory it cannot read   UNKNOWN. Exit 2. Never folded into "none
#                                pending": a directory nobody could open is
#                                where the unasked question hides.
#
# An unmatched glob reaches the command as a literal path in bash, so the two
# are distinguished by an explicit directory test, never by trusting a count.
#
# `grep -x -F`-equivalent matching, never a substring. `Status: pending`
# appears in the template's own prose and in any ruling that discusses being
# pending; an unanchored match reports questions that do not exist. The status
# is read from the header block only, so the string in a body paragraph is
# not a status.
#
# REPORTED BY LOCATION, NEVER BY QUOTING THE MATCH. File, line, and the class
# of problem. A checker in this repo that printed the offending line put the
# leaked content into a committed result file, so finding a leak created one.
# A ruling also quotes an incoming intent, which is text a stranger can write.
#
# Paths are printed RELATIVE to the root for the same reason: an absolute path
# names somebody's home directory, and this output is committed.
#
# ONE LINE PER FILE EXAMINED, on stdout, unindented - the spec, then every
# ruling file read. The runner asserts that a check examined what it declared
# and calls a clean exit with nothing examined HOLLOW, which is a failure. A
# check that looks at nothing must not look like a pass.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - A literal angle-bracket pair in quoted requirement text inside one of the
#     three scanned sections reads as a template placeholder. Backtick it -
#     inline code spans are stripped before the scan, which is how the repo
#     already writes `D<n>`.
#   - The cost table's second pipe line is assumed to be the column separator.
#     A table written without one loses its first data row from the scan.
#   - Running as a user who can read anything (root) defeats the unreadable-
#     directory test, as it defeats every such test.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  clean
#   1  findings
#   2  could not run - no work tree, no spec, or a rulings directory or file
#      that could not be read. Never confused with 0.
set -euo pipefail

VERSION="check-ruling-requested 1.0"
ROOT=""

usage() {
  printf 'usage: check-ruling-requested.sh [--version] [--help] [--root DIR]\n'
  printf '  --root DIR  the repo work tree to examine. Defaults to the git\n'
  printf '              top level, never to the working directory.\n'
}

die_unmeasured() { printf 'check-ruling-requested: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    -*) printf 'check-ruling-requested: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'check-ruling-requested: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# Defaulting to the working directory has caused four separate silent-wrong-
# answer bugs here: the script reads a directory that is not the repo and
# reports a confident clean result. git names the work tree or nothing does.
if [ -z "$ROOT" ]; then
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_unmeasured "no git work tree here, and --root was not given. Refusing rather than reading the working directory, which is not the repo often enough to matter."
  fi
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"

SPEC="$ROOT/.claude/productizer/spec.md"
RULINGS="$ROOT/.claude/productizer/rulings"

[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "cannot read .claude/productizer/spec.md under the given root. Without the spec there is no list of open concerns, so nothing can be said about whether anyone was asked."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-ruling-requested.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

rel() { printf '%s' "${1#"$ROOT"/}"; }

found=0
finding() { printf '    %s\n' "$1"; found=1; }

# ---------------------------------------------------------------------------
# The spec's Areas of concern rows. One record per cited ruling id:
#   line <TAB> open|other|open-nocite <TAB> C<n> <TAB> D<n>
# Rows inside an HTML comment are example scaffolding, not live concerns.
# ---------------------------------------------------------------------------
AWK_CONCERNS='
BEGIN { ins = 0; incomment = 0 }
/^## / { ins = ($0 ~ /^##[ \t]+Areas of concern[ \t]*$/) ? 1 : 0; next }
ins == 0 { next }
incomment == 1 { if ($0 ~ /-->/) incomment = 0; next }
/<!--/ { if ($0 !~ /-->/) incomment = 1; next }
$0 !~ /^[ \t]*\|/ { next }
{
  line = $0
  sub(/^[ \t]*\|/, "", line)
  sub(/\|[ \t]*$/, "", line)
  nf = split(line, f, "|")
  for (i = 1; i <= nf; i++) gsub(/^[ \t]+|[ \t]+$/, "", f[i])
  if (nf < 2) next
  if (f[1] !~ /^C[0-9]+$/) next
  status = f[nf]
  isopen = (status ~ /^open([ \t]*:|[ \t]*$)/) ? 1 : 0
  cited = 0
  rest = status
  while (match(rest, /D[0-9]+/)) {
    printf "%d\t%s\t%s\t%s\n", FNR, (isopen ? "open" : "other"), f[1], substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
    cited = 1
  }
  if (isopen == 1 && cited == 0)
    printf "%d\topen-nocite\t%s\t-\n", FNR, f[1]
}'

printf '%s\n' "$(rel "$SPEC")"        # coverage: one line per file examined
awk "$AWK_CONCERNS" "$SPEC" > "$WORK/concerns.tsv"

OPEN_IDS=""     # ids an open concern row points at
CITED_IDS=""    # ids any concern row points at, open or not
while IFS="$(printf '\t')" read -r cline cstate cid did; do
  [ -n "${cline:-}" ] || continue
  case "$cstate" in
    open)
      OPEN_IDS="$OPEN_IDS$did"$'\n'
      CITED_IDS="$CITED_IDS$did"$'\n'
      printf '%s\n' "$cline	$cid	$did" >> "$WORK/open.tsv"
      ;;
    other) CITED_IDS="$CITED_IDS$did"$'\n' ;;
    open-nocite)
      finding "$(rel "$SPEC"):$cline: concern $cid is open but cites no ruling id. An open concern with nowhere to be answered is a stop that asked nobody - allocate a D id and write the ruling file."
      ;;
  esac
done < "$WORK/concerns.tsv"

in_list() { printf '%s' "$2" | grep -qxF -- "$1"; }

# ---------------------------------------------------------------------------
# The rulings directory. Absent and unreadable are different sentences.
# ---------------------------------------------------------------------------
DIRSTATE="absent"
if [ -e "$RULINGS" ]; then
  [ -d "$RULINGS" ] ||
    die_unmeasured ".claude/productizer/rulings exists but is not a directory. Unmeasured - a path that is not the directory the contract names says nothing about how many rulings there are."
  if [ -r "$RULINGS" ] && [ -x "$RULINGS" ]; then
    DIRSTATE="present"
  else
    die_unmeasured ".claude/productizer/rulings exists but cannot be listed. The number of pending rulings is UNKNOWN, not zero - a directory nobody can open is exactly where an unasked question hides."
  fi
fi

FILE_IDS=""
pending_count=0
ruling_count=0

if [ "$DIRSTATE" = "present" ]; then
  for f in "$RULINGS"/D*.md; do
    # An unmatched glob arrives as its own literal text, so test the path.
    [ -e "$f" ] || continue
    base="${f##*/}"
    printf '%s\n' "$(rel "$f")"       # coverage: one line per file examined
    ruling_count=$((ruling_count + 1))

    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
      die_unmeasured "cannot read $(rel "$f"). A ruling nobody could open is not a ruling that is fine."
    fi

    case "$base" in
      D[0-9]*) ;;
      *) finding "$(rel "$f"):1: filename is not D<n>[-<slug>].md, so no counter can key it to a concern row"; continue ;;
    esac
    id="${base%.md}"
    id="${id%%-*}"
    case "$id" in
      D[0-9]*)
        rest="${id#D}"
        case "$rest" in
          *[!0-9]*) finding "$(rel "$f"):1: filename is not D<n>[-<slug>].md, so no counter can key it to a concern row"; continue ;;
        esac
        ;;
      *) finding "$(rel "$f"):1: filename is not D<n>[-<slug>].md, so no counter can key it to a concern row"; continue ;;
    esac
    FILE_IDS="$FILE_IDS$id"$'\n'

    awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function strip_code(s) { gsub(/`[^`]*`/, "", s); return s }
    function sect_start(name,   i) {
      for (i = 1; i <= TOP; i++)
        if (L[i] ~ ("^##[ \t]+" name "[ \t]*$")) return i
      return 0
    }
    function sect_end(s,   i) {
      for (i = s + 1; i <= TOP; i++)
        if (L[i] ~ /^## /) return i - 1
      return TOP
    }
    # Empty, or still wearing an angle-bracket placeholder from the template.
    # The placeholder scan carries state across lines because the templates
    # own placeholders wrap: the opening bracket and the closing one are on
    # different lines, and a per-line match sees neither.
    function check_prose(name,   s, e, i, j, nb, line, ch, isopen, oline) {
      s = sect_start(name)
      if (s == 0) { printf "SECTMISSING\t1\t%s\n", name; return }
      e = sect_end(s)
      nb = 0
      for (i = s + 1; i <= e; i++) if (L[i] !~ /^[ \t]*$/) nb++
      if (nb == 0) { printf "SECTEMPTY\t%d\t%s\n", s, name; return }
      isopen = 0; oline = 0
      for (i = s + 1; i <= e; i++) {
        line = strip_code(L[i])
        for (j = 1; j <= length(line); j++) {
          ch = substr(line, j, 1)
          if (isopen == 0) { if (ch == "<") { isopen = 1; oline = i } }
          else if (ch == ">") { printf "SECTPLACEHOLDER\t%d\t%s\n", oline, name; return }
          else if (ch == "<") oline = i
        }
      }
    }
    function check_costs(   name, s, e, i, c, m, P, row, nf, cells, cell) {
      name = "What each side costs"
      s = sect_start(name)
      if (s == 0) { printf "SECTMISSING\t1\t%s\n", name; return }
      e = sect_end(s)
      m = 0
      for (i = s + 1; i <= e; i++) if (L[i] ~ /^[ \t]*\|/) { m++; P[m] = i }
      if (m < 3) { printf "COSTNOTABLE\t%d\t%s\n", s, name; return }
      for (i = 3; i <= m; i++) {
        row = L[P[i]]
        sub(/^[ \t]*\|/, "", row)
        sub(/\|[ \t]*$/, "", row)
        nf = split(row, cells, "|")
        if (nf < 2) { printf "COSTSHORTROW\t%d\t%s\n", P[i], name; continue }
        for (c = 1; c <= 2; c++) {
          cell = trim(strip_code(cells[c]))
          if (cell == "") printf "COSTBLANK\t%d\t%d\n", P[i], c
          else if (cell ~ /<[^<>]*>/) printf "COSTPLACEHOLDER\t%d\t%d\n", P[i], c
        }
      }
    }
    { L[NR] = $0 }
    END {
      N = NR
      if (N == 0) { printf "EMPTYFILE\t1\t\n"; exit }

      firsth = 0
      for (i = 1; i <= N; i++) if (L[i] ~ /^## /) { firsth = i; break }
      lim = (firsth ? firsth - 1 : N)

      # The header block is the run of Key: value lines around the Status
      # line, above the first section heading. Scoping it this way is what
      # makes a Status: pending inside a body paragraph not a status.
      sidx = 0
      for (i = 1; i <= lim; i++) if (L[i] ~ /^Status:/) { sidx = i; break }
      if (sidx == 0) printf "NOSTATUS\t1\t\n"
      else {
        hs = sidx; while (hs > 1 && L[hs-1] !~ /^[ \t]*$/) hs--
        he = sidx; while (he < lim && L[he+1] !~ /^[ \t]*$/) he++
        for (i = hs; i <= he; i++)
          if (match(L[i], /^[A-Za-z][A-Za-z ]*:/)) {
            k = substr(L[i], 1, RLENGTH - 1)
            cnt[k]++; ln[k] = i; val[k] = trim(substr(L[i], RLENGTH + 1))
          }
      }

      nreq = split("Status,Raised,Concern,Intent,Ruled,Ruled by,Supersedes,Superseded by", REQ, ",")
      for (i = 1; i <= nreq; i++) {
        k = REQ[i]
        if (cnt[k] == 0) {
          if (k != "Status" || sidx > 0) printf "MISSINGFIELD\t%d\t%s\n", (sidx ? sidx : 1), k
        } else if (cnt[k] > 1) printf "DUPFIELD\t%d\t%s\n", ln[k], k
        else if (val[k] == "") printf "BLANKFIELD\t%d\t%s\n", ln[k], k
      }

      st = ""
      if (cnt["Status"] == 1) {
        s = L[ln["Status"]]
        if (s == "Status: pending") st = "pending"
        else if (s == "Status: ruled") st = "ruled"
        else if (s == "Status: lapsed") st = "lapsed"
        else if (s == "Status: superseded") st = "superseded"
        else printf "BADSTATUS\t%d\t\n", ln["Status"]
      }
      printf "STATUS\t%d\t%s\n", (cnt["Status"] == 1 ? ln["Status"] : 0), st

      if (st != "pending") exit

      # Everything from ## Ruling down belongs to the human and MUST still
      # carry its template guidance in a pending ruling. The three sections
      # below are named explicitly, so a file with no ## Ruling heading still
      # cannot pull Reasoning or Consequences into scope.
      rl = 0
      for (i = 1; i <= N; i++) if (L[i] ~ /^##[ \t]+Ruling[ \t]*$/) { rl = i; break }
      TOP = (rl ? rl - 1 : N)

      check_prose("The conflict")
      check_prose("The question")
      check_costs()
    }' "$f" > "$WORK/r.tsv"

    status=""
    while IFS="$(printf '\t')" read -r kind kline detail; do
      [ -n "${kind:-}" ] || continue
      loc="$(rel "$f"):$kline"
      case "$kind" in
        STATUS) status="$detail" ;;
        EMPTYFILE) finding "$loc: the ruling file is empty. An empty file is not an ask." ;;
        NOSTATUS) finding "$loc: no Status: line in the header block. Nothing can count this ruling, so a live contradiction reads as none." ;;
        BADSTATUS) finding "$loc: Status: carries something other than exactly one of pending, ruled, lapsed, superseded with nothing else on the line." ;;
        MISSINGFIELD) finding "$loc: header field '$detail' is missing. A missing line and a blank value are indistinguishable to a counter, and the counter then reports a pending ruling as ruled." ;;
        DUPFIELD) finding "$loc: header field '$detail' appears more than once, so which value is authoritative is undefined." ;;
        BLANKFIELD) finding "$loc: header field '$detail' is blank. An unset field is an em dash, never blank." ;;
        SECTMISSING) finding "$loc: pending ruling has no '## $detail' section. Without it there is no question for a human to answer." ;;
        SECTEMPTY) finding "$loc: pending ruling's '## $detail' section is empty. A stop that states no question asked nobody." ;;
        SECTPLACEHOLDER) finding "$loc: pending ruling's '## $detail' section still carries a template placeholder. A ruling wearing the template is a file, not an ask." ;;
        COSTNOTABLE) finding "$loc: pending ruling's '## $detail' section has no filled cost table. A ruler handed no costs is being asked to guess." ;;
        COSTSHORTROW) finding "$loc: cost table row has fewer than two columns." ;;
        COSTBLANK) finding "$loc: column $detail of the cost table is blank. A ruler handed one side's costs is being steered, and a steered ruling is the agent's decision wearing a human name." ;;
        COSTPLACEHOLDER) finding "$loc: column $detail of the cost table still carries a template placeholder." ;;
      esac
    done < "$WORK/r.tsv"

    if [ "$status" = "pending" ]; then
      pending_count=$((pending_count + 1))
      if ! in_list "$id" "$CITED_IDS"; then
        finding "$(rel "$f"):1: $id is pending but no C row in the spec's Areas of concern cites it. The ask is invisible to anyone reading the spec, which is where intake looks."
      fi
    fi
  done
fi

# ---------------------------------------------------------------------------
# B11 itself: an open concern whose ruling file was never written.
# ---------------------------------------------------------------------------
if [ -f "$WORK/open.tsv" ]; then
  while IFS="$(printf '\t')" read -r oline ocid odid; do
    [ -n "${oline:-}" ] || continue
    if ! in_list "$odid" "$FILE_IDS"; then
      if [ "$DIRSTATE" = "absent" ]; then
        finding "$(rel "$SPEC"):$oline: concern $ocid is open citing $odid, and there is no .claude/productizer/rulings directory at all. The lifecycle stopped and nobody was asked."
      else
        finding "$(rel "$SPEC"):$oline: concern $ocid is open citing $odid, but no rulings/$odid-*.md exists. The lifecycle stopped and nobody was asked."
      fi
    fi
  done < "$WORK/open.tsv"
fi

printf 'rulings examined: %d\n' "$ruling_count"
printf 'pending rulings: %d\n' "$pending_count"
if [ "$DIRSTATE" = "absent" ]; then
  printf 'note: no .claude/productizer/rulings directory - this repo has never raised a contradiction. That is no count, not a measured zero.\n'
fi

if [ "$found" -ne 0 ]; then
  printf 'FAIL: a contradiction was stopped without a question anyone can answer. R23 asks which wins; these findings are the ask that never landed.\n' >&2
  exit 1
fi

printf 'PASS: every open concern cites a ruling that exists, every pending ruling is cited back and is filled in enough to answer.\n'
