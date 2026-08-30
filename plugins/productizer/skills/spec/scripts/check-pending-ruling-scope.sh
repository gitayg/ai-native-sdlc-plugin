#!/usr/bin/env bash
# check-pending-ruling-scope.sh [--version] [--help] [--root DIR]
#
# Asserts R12: WHILE A CONTRADICTION IS UNRULED, THE LIFECYCLE SHALL MERGE NO
# SPEC CHANGE THAT DEPENDS ON IT.
#
# The load-bearing word is DEPENDS. `references/rulings.md` states the scope in
# one sentence and gives the reason in the next: "A pending ruling blocks its
# own delta and nothing else. Unrelated intents keep flowing. A halt that stops
# all work in the repo teaches people to route around intake, and an intake
# nobody runs detects no contradictions at all."
#
# So a check that refuses every spec change while any ruling is pending would
# be enforcing the opposite of R12 while passing for it. Blocking too much is
# not the safe direction here - it is the failure mode the requirement was
# written against, and it fails slowly, by teaching people to stop using the
# gate at all.
#
# WHAT COUNTS AS DEPENDING ON D<n>
#
# Dependence is derived from the ruling itself, never guessed from the diff.
# A pending `D<n>` names the requirement it was raised against in two places,
# and both are read:
#
#   - `## The conflict`, where the active requirement is quoted under its own
#     id as `**R<m>** — …`. This is the ruling's own statement of what it is
#     about.
#   - the spec's *Areas of concern* row whose status cites `D<n>`. Its cells
#     name the requirements the concern involves.
#
# The union of the two is the GUARDED SET. A spec change is refused when,
# between the commit that raised the ruling and the spec as it stands now, it:
#
#   1. EDITS a guarded requirement's sentence. The contested requirement cannot
#      be re-worded while the question of whether it survives is open.
#   2. SUPERSEDES or WITHDRAWS a guarded requirement. This is the ruling being
#      made by whoever committed last, which is the one thing the stop exists
#      to prevent.
#   3. ALLOCATES AN ID FOR THE INCOMING BEHAVIOUR. `rulings.md`: "Do not
#      allocate a requirement id for the incoming behaviour. An id in the spec
#      is a merge, whatever the surrounding prose says."
#
# A NEWLY ALLOCATED ID IS NOT AUTOMATICALLY THE INCOMING BEHAVIOUR, and that
# distinction is the whole difference between this check and a halt. An id
# added for an unrelated feature is an unrelated intent, and it keeps flowing.
# A new id `N` is treated as the incoming behaviour only on a structural tie
# back to the ruling:
#
#   (a) a guarded requirement's own marker points forward at `N` - the merge is
#       stated in the spec;
#   (b) `N` carries the same EARS trigger and system as a guarded requirement.
#       `references/ears.md` is explicit that requirements are matched "on
#       trigger and system, not on wording", and a second requirement with the
#       same trigger as the contested one is by construction the other side of
#       the contradiction;
#   (c) `N`'s sentence matches the `**Incoming**` behaviour the ruling quotes.
#       The ruling records that sentence verbatim precisely so the merge can be
#       recognised later.
#
# Anything else that was allocated is reported as allocated and NOT refused,
# on its own line, so the decision not to block it is visible rather than
# silent.
#
# THE WINDOW IS THE RULING'S OWN LIFETIME, NOT A DIFF RANGE. The baseline is
# the commit that ADDED the ruling file - which, per `rulings.md`, is the same
# commit that added its concern row. That is what "while unruled" means, and it
# needs no `--base` from the caller: a check whose window depends on a ref
# someone passes correctly is a check that reports clean when they do not. It
# also means the concern row added alongside the ruling is inside the baseline
# and never reads as a change. A ruling not yet committed has no such commit,
# and its window opens at HEAD.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   - It does not read `ruled`, `lapsed` or `superseded` rulings. A decided
#     question blocks nothing; that is what deciding it was for.
#   - It does not judge whether the ruling SHOULD have been raised, whether the
#     conflict is real, or which side ought to win. `contradiction-check.py`
#     answers the first and a human answers the third.
#   - It does not block changes elsewhere in the spec, to the backlog, to the
#     constitution, or to any code. R12 is about the spec change that depends
#     on the ruling.
#
# NO RULINGS DIRECTORY IS CLEAN, AND SAYS SO. R12 is state-driven: with no
# contradiction raised, the state it governs is never entered and there is
# nothing to refuse. That is different from COUNTING pending rulings, where an
# absent directory is no count rather than zero - and the difference is why the
# absence is printed as a note instead of folded into a number. A rulings
# directory that exists and cannot be read is exit 2, never clean: a directory
# nobody can open is exactly where an unruled contradiction hides.
#
# UNMEASURED CASES, each named separately, each exit 2:
#
#   a pending ruling naming no requirement    its scope cannot be derived, so
#                                             nothing can be said about what
#                                             depends on it
#   the ruling's commit is out of reach       a shallow clone; the window has
#                                             no start
#   the spec absent at that commit            there is nothing to compare to
#
# EXIT PRECEDENCE: UNMEASURED BEATS FINDINGS BEATS CLEAN, the same way
# `check-hygiene.sh` lets one unreadable file decide the whole run. A partial
# answer to "did anything merge" is not an answer.
#
# REPORTED BY LOCATION, NEVER BY QUOTING CONTENT. Ids, files, lines and short
# shas only. This matters more here than anywhere else in the repo: a ruling
# quotes an incoming intent, which is text a stranger can write, and this
# output lands in a committed result file. The incoming sentence is read into a
# temporary file, compared, and never printed.
#
# ONE LINE PER FILE EXAMINED, on stdout, unindented: the spec, every ruling
# file opened, and every historical spec version read as `<path>@<short sha>`.
# A loop over rulings that never executes prints nothing and exits 0, and the
# runner calls that hollow, which is a failure.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - The incoming behaviour merged under a REWORDED sentence with a DIFFERENT
#     trigger than the contested requirement is not recognised as the incoming
#     behaviour. Nothing structural connects it to the ruling at that point,
#     and inventing a similarity threshold would start refusing unrelated
#     intents, which is the failure at the top of this header.
#   - A ruling raised and merged in a single commit leaves no window. Review of
#     that diff is what stands between the spec and that merge.
#   - Requirement ids are read from the whole concern row, not from the
#     Requirements column by position, so an id mentioned in the row's prose
#     joins the guarded set. Over-guarding one named requirement is the
#     cheaper error; the row named it.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  clean - no pending ruling, or none whose delta reached the spec
#   1  findings - a spec change that depends on an unruled contradiction
#   2  could not run, or could not measure. Never 0.
set -euo pipefail

VERSION="check-pending-ruling-scope 1.0"
ROOT=""

usage() {
  printf 'usage: check-pending-ruling-scope.sh [--version] [--help] [--root DIR]\n'
  printf '  --root DIR  the repo work tree to examine. Defaults to the git\n'
  printf '              top level, never to the working directory.\n'
}

die_unmeasured() { printf 'check-pending-ruling-scope: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    -*) printf 'check-pending-ruling-scope: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'check-pending-ruling-scope: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
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

SELFDIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="$SELFDIR/spec-requirements.sh"
[ -x "$PARSER" ] ||
  die_unmeasured "spec-requirements.sh is not beside this script and executable. Without the parser nothing here read the spec."

SPECREL=".claude/productizer/spec.md"
SPEC="$ROOT/$SPECREL"
RULINGSREL=".claude/productizer/rulings"
RULINGS="$ROOT/$RULINGSREL"

[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "cannot read $SPECREL under $ROOT. Without the spec there is no spec change to judge."

TOP="$(git -C "$ROOT" rev-parse --show-toplevel)" ||
  die_unmeasured "--root $ROOT is not inside a git work tree. The window a pending ruling holds open starts at a commit, and there are none."
case "$ROOT/" in
  "$TOP"/*) ;;
  *) die_unmeasured "--root $ROOT resolves outside its own git top level $TOP" ;;
esac
SPECGIT="${SPEC#"$TOP"/}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-pending-ruling-scope.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

found=0
unmeasured=0
finding() { printf '    %s\n' "$1"; found=1; }
unmeasurable() { printf '    UNMEASURED %s\n' "$1"; unmeasured=1; }

norm() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ //' -e 's/ $//'; }

# The EARS trigger and system: everything up to the obligation. `ears.md` says
# requirements are matched on trigger and system, not on wording, so this is
# the clause that decides whether two sentences are about the same behaviour.
trigger() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' |
    sed -e 's/ shall .*$//' -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ //' -e 's/ $//'
}

# --- the spec as it stands now ---------------------------------------------
printf '%s\n' "$SPECREL"                 # coverage: one line per file examined
"$PARSER" "$SPEC" > "$WORK/cur.tsv" ||
  die_unmeasured "the parser refused $SPECREL"
[ -s "$WORK/cur.tsv" ] ||
  die_unmeasured "$SPECREL holds no requirement definitions. That is nothing measured, not nothing wrong."

# --- Areas of concern: which requirements each D<n> was raised over ---------
# Ids are taken from the whole row rather than from a column by position; see
# the known limitations in the header.
awk '
BEGIN { ins = 0; incomment = 0 }
/^## / { ins = ($0 ~ /^##[ \t]+Areas of concern[ \t]*$/) ? 1 : 0; next }
ins == 0 { next }
incomment == 1 { if ($0 ~ /-->/) incomment = 0; next }
/<!--/ { if ($0 !~ /-->/) incomment = 1; next }
$0 !~ /^[ \t]*\|/ { next }
{
  row = $0
  if (row !~ /\|[ \t]*C[0-9]+[ \t]*\|/) next
  ds = ""; rs = ""; rest = row
  while (match(rest, /D[0-9]+/)) { ds = ds " " substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH) }
  rest = row
  while (match(rest, /R[0-9]+/)) { rs = rs " " substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH) }
  n = split(ds, D, " ")
  for (i = 1; i <= n; i++) printf "%s\t%d\t%s\n", D[i], FNR, rs
}' "$SPEC" > "$WORK/concerns.tsv"

# --- the rulings directory: absent, unreadable and present are three answers
if [ ! -e "$RULINGS" ]; then
  printf 'rulings examined: 0\n'
  printf 'pending rulings: 0\n'
  printf 'note: no %s directory - no contradiction has ever been raised here, so R12 governs a state this repo has not entered. Nothing is blocked. That is an absence, and it is reported as one rather than as a measured zero.\n' "$RULINGSREL"
  printf 'PASS: no unruled contradiction, so no spec change can depend on one.\n'
  exit 0
fi
[ -d "$RULINGS" ] ||
  die_unmeasured "$RULINGSREL exists and is not a directory. A path that is not the directory the contract names says nothing about what is pending."
{ [ -r "$RULINGS" ] && [ -x "$RULINGS" ]; } ||
  die_unmeasured "$RULINGSREL exists and cannot be listed. What is pending is UNKNOWN, not zero - a directory nobody can open is exactly where an unruled contradiction hides."

# --- one pass per ruling ----------------------------------------------------
ruling_count=0
pending_count=0
guarded_total=0

for f in "$RULINGS"/D*.md; do
  [ -e "$f" ] || continue
  base="${f##*/}"
  rel="${f#"$ROOT"/}"
  printf '%s\n' "$rel"                   # coverage: one line per file examined
  ruling_count=$((ruling_count + 1))

  { [ -f "$f" ] && [ -r "$f" ]; } ||
    die_unmeasured "cannot read $rel. A ruling nobody could open is not a ruling that is fine."

  id="${base%.md}"; id="${id%%-*}"
  case "$id" in
    D[0-9]*) ;;
    *) finding "$rel:1: filename is not D<n>[-<slug>].md, so nothing can key this ruling to the requirement it guards"; continue ;;
  esac

  # Status is read from the HEADER BLOCK only, matched whole. `Status: pending`
  # appears in the template's own prose and in any ruling that discusses being
  # pending; a substring match reports questions that do not exist.
  awk '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  { L[NR] = $0 }
  END {
    N = NR
    firsth = 0
    for (i = 1; i <= N; i++) if (L[i] ~ /^## /) { firsth = i; break }
    lim = (firsth ? firsth - 1 : N)
    st = "-"
    for (i = 1; i <= lim; i++) {
      if (L[i] == "Status: pending")     { st = "pending"; break }
      if (L[i] == "Status: ruled")       { st = "ruled"; break }
      if (L[i] == "Status: lapsed")      { st = "lapsed"; break }
      if (L[i] == "Status: superseded")  { st = "superseded"; break }
    }
    printf "STATUS\t%s\n", st

    cs = 0; ce = 0
    for (i = 1; i <= N; i++) if (L[i] ~ /^##[ \t]+The conflict[ \t]*$/) { cs = i; break }
    if (cs) { ce = N; for (i = cs + 1; i <= N; i++) if (L[i] ~ /^## /) { ce = i - 1; break } }
    inc = ""; collecting = 0
    for (i = cs + 1; cs && i <= ce; i++) {
      line = L[i]
      if (line ~ /^\*\*R[0-9]+\*\*/) {
        collecting = 0
        match(line, /R[0-9]+/)
        printf "GUARD\t%s\n", substr(line, RSTART, RLENGTH)
        continue
      }
      if (line ~ /^\*\*Incoming\*\*/) {
        collecting = 1
        sub(/^\*\*Incoming\*\*[ \t]*/, "", line)
        sub("^\342\200\224[ \t]*", "", line)
        sub("^\342\200\223[ \t]*", "", line)
        sub(/^-[ \t]*/, "", line)
        inc = trim(line)
        continue
      }
      if (collecting) {
        if (line ~ /^[ \t]*$/) { collecting = 0; continue }
        inc = inc " " trim(line)
      }
    }
    # The incoming sentence is a quote of somebody else text. It is written to
    # a file for comparison and never reaches this check own stdout.
    if (inc != "") { gsub(/\t/, " ", inc); printf "INCOMING\t%s\n", inc }
  }' "$f" > "$WORK/r.tsv"

  status="$(awk -F'\t' '$1 == "STATUS" { print $2; exit }' "$WORK/r.tsv")"
  [ "$status" = "pending" ] || continue
  pending_count=$((pending_count + 1))

  # The guarded set: the ids the ruling quotes, plus the ids its concern row
  # names. Two independent statements of the same thing, unioned, because a
  # ruling that lost one of them still names what it is about in the other.
  GUARD="$(
    {
      awk -F'\t' '$1 == "GUARD" { print $2 }' "$WORK/r.tsv"
      awk -F'\t' -v d="$id" '$1 == d { n = split($3, R, " "); for (i = 1; i <= n; i++) print R[i] }' "$WORK/concerns.tsv"
    } | sort -u
  )"

  if [ -z "$GUARD" ]; then
    unmeasurable "$rel:1: $id is pending and names no requirement id, in its '## The conflict' section or in any Areas of concern row citing it. What depends on it cannot be derived, so nothing can be said about whether a dependent change merged."
    continue
  fi

  # --- the window: the commit that raised this ruling ----------------------
  RULGIT="${f#"$TOP"/}"
  ADD="$(git -C "$TOP" log --diff-filter=A --format=%H -- "$RULGIT" | tail -1)"
  window="raised"

  # A SHALLOW CLONE MAKES ITS BOUNDARY COMMIT LOOK LIKE A ROOT, so every file
  # present there looks ADDED there and this window would silently open at the
  # wrong commit - reporting clean for everything merged before the boundary.
  # A parentless commit in a shallow clone is a graft until proven otherwise,
  # and unknown is the only honest answer.
  if [ -n "$ADD" ] && [ "$(git -C "$TOP" rev-parse --is-shallow-repository)" = "true" ]; then
    if [ "$(git -C "$TOP" rev-list --parents -n 1 "$ADD" | wc -w | tr -d ' ')" = "1" ]; then
      unmeasurable "$rel:1: $id appears to have been added at $(git -C "$TOP" rev-parse --short "$ADD"), which is a parentless commit in a SHALLOW clone - that is a graft boundary, not necessarily the commit that raised the ruling. The window has no trustworthy start, so whether a dependent change merged inside it is UNKNOWN. Fetch full history (fetch-depth: 0) and re-run."
      continue
    fi
  fi

  if [ -z "$ADD" ]; then
    if [ -n "$(git -C "$TOP" ls-files -- "$RULGIT")" ]; then
      unmeasurable "$rel:1: $id is tracked and the commit that added it is not reachable - a shallow clone. The window this ruling holds open has no start, so whether a dependent change merged inside it is UNKNOWN. Fetch full history (fetch-depth: 0) and re-run."
      continue
    fi
    ADD="$(git -C "$TOP" rev-parse HEAD)" ||
      unmeasurable "$rel:1: $id is not committed and the repo has no commits, so there is no baseline spec to compare the working tree against."
    [ -n "$ADD" ] || continue
    window="uncommitted"
  fi
  SHORT="$(git -C "$TOP" rev-parse --short "$ADD")"

  if [ -z "$(git -C "$TOP" ls-tree "$ADD" -- "$SPECGIT")" ]; then
    unmeasurable "$rel:1: $SPECREL does not exist at $SHORT, the commit this ruling's window opens at. There is no earlier spec to compare against."
    continue
  fi

  if [ ! -f "$WORK/base.$SHORT.tsv" ]; then
    git -C "$TOP" show "$ADD:$SPECGIT" > "$WORK/base.md" ||
      die_unmeasured "cannot read $SPECREL at $SHORT, which git says exists there"
    printf '%s@%s\n' "$SPECREL" "$SHORT"  # coverage: one line per file examined
    "$PARSER" "$WORK/base.md" > "$WORK/base.$SHORT.tsv" ||
      die_unmeasured "the parser refused $SPECREL at $SHORT"
  fi
  BASE="$WORK/base.$SHORT.tsv"

  printf '  %s pending, window opens at %s (%s), guards %s\n' \
    "$id" "$SHORT" "$window" "$(printf '%s' "$GUARD" | tr '\n' ' ' | sed -e 's/ $//')"

  # --- 1 and 2: the contested requirements themselves ----------------------
  for g in $GUARD; do
    guarded_total=$((guarded_total + 1))
    cline="$(awk -F'\t' -v i="$g" '$1 == i { print $2; exit }' "$WORK/cur.tsv")"
    cstat="$(awk -F'\t' -v i="$g" '$1 == i { print $3; exit }' "$WORK/cur.tsv")"
    ctext="$(awk -F'\t' -v i="$g" '$1 == i { print $5; exit }' "$WORK/cur.tsv")"
    bstat="$(awk -F'\t' -v i="$g" '$1 == i { print $3; exit }' "$BASE")"
    btext="$(awk -F'\t' -v i="$g" '$1 == i { print $5; exit }' "$BASE")"

    if [ -z "$bstat" ]; then
      if [ -z "$cstat" ]; then
        unmeasurable "$rel:1: $id guards $g, which is defined neither in $SPECREL now nor at $SHORT. The ruling names a requirement the spec does not have."
      else
        finding "$SPECREL:$cline: $g was allocated while $id is pending against it. An id in the spec is a merge, whatever the surrounding prose says - $id has to be ruled first."
      fi
      continue
    fi
    if [ -z "$cstat" ]; then
      finding "$SPECREL:1: $g was defined at $SHORT and is gone from $SPECREL now, while $id is pending against it. Nothing is ever deleted from the spec, and least of all the requirement a live contradiction is about."
      continue
    fi
    if [ "$cstat" != "$bstat" ]; then
      finding "$SPECREL:$cline: $g went from $bstat to $cstat while $id is unruled. That is the ruling being made by whoever committed last, which is exactly what the stop exists to prevent."
    elif [ "$(norm "$ctext")" != "$(norm "$btext")" ]; then
      finding "$SPECREL:$cline: $g's sentence was edited while $id is pending against it. The contested requirement cannot be re-worded while the question of whether it survives is open. The text is not quoted here; read it with: git show $SHORT:$SPECGIT"
    fi
  done

  # --- 3: an id allocated for the incoming behaviour -----------------------
  INCOMING="$(awk -F'\t' '$1 == "INCOMING" { print $2; exit }' "$WORK/r.tsv")"
  NEWIDS="$(awk -F'\t' 'NR == FNR { seen[$1] = 1; next } !($1 in seen) { print $1 }' "$BASE" "$WORK/cur.tsv")"

  for n in $NEWIDS; do
    ntext="$(awk -F'\t' -v i="$n" '$1 == i { print $5; exit }' "$WORK/cur.tsv")"
    nline="$(awk -F'\t' -v i="$n" '$1 == i { print $2; exit }' "$WORK/cur.tsv")"
    why=""
    for g in $GUARD; do
      [ "$n" != "$g" ] || continue
      gtarget="$(awk -F'\t' -v i="$g" '$1 == i { print $4; exit }' "$WORK/cur.tsv")"
      gtext="$(awk -F'\t' -v i="$g" '$1 == i { print $5; exit }' "$WORK/cur.tsv")"
      if [ "$gtarget" = "$n" ]; then why="$g's marker points forward at it"; break; fi
      if [ -n "$gtext" ] && [ "$(trigger "$ntext")" = "$(trigger "$gtext")" ]; then
        why="it carries the same EARS trigger and system as $g, which ears.md matches requirements on"
        break
      fi
    done
    if [ -z "$why" ] && [ -n "$INCOMING" ] && [ "$(norm "$ntext")" = "$(norm "$INCOMING")" ]; then
      why="its sentence is the incoming behaviour $id quotes"
    fi
    if [ -n "$why" ]; then
      finding "$SPECREL:$nline: $n was allocated while $id is pending, and $why. An id in the spec is a merge, whatever the surrounding prose says."
    else
      printf '  %s allocated at %s:%s while %s is pending — unrelated to it, so not refused. A pending ruling blocks its own delta and nothing else.\n' \
        "$n" "$SPECREL" "$nline" "$id"
    fi
  done
done

printf 'rulings examined: %d\n' "$ruling_count"
printf 'pending rulings: %d\n' "$pending_count"
printf 'guarded requirements: %d\n' "$guarded_total"

if [ "$unmeasured" -ne 0 ]; then
  printf 'UNMEASURED: a pending ruling could not be scoped or its window could not be reached, so this run has no verdict on whether a dependent spec change merged. Not a pass.\n' >&2
  exit 2
fi
if [ "$found" -ne 0 ]; then
  printf 'FAIL: a spec change that depends on an unruled contradiction has reached the spec. R12 merges nothing that depends on a pending ruling; rule the contradiction, then merge.\n' >&2
  exit 1
fi

printf 'PASS: no spec change depending on a pending ruling has reached the spec. Unrelated changes were not examined for approval and were not blocked.\n'
