#!/usr/bin/env bash
# pending-rulings.sh [--root DIR] [--format ids|count|table] [--stale-after DAYS]
#                    [--version] [--help]
#
# Reports which rulings are waiting on a human, so a session-start line can say
# so before anyone types. references/rulings.md specifies this count and names
# the session-start hook as its consumer; nothing implemented it, so a
# contradiction could be raised and stopped and nobody was ever told it was
# waiting.
#
# WHAT IT READS. One directory, one fixed-string match, no network:
#
#     <root>/.claude/productizer/rulings/D*.md
#
# matched with `grep -lxF 'Status: pending'`. The -x and the -F are the
# contract, not a style choice: `Status: pending` appears in the template's own
# prose and will appear in any ruling that discusses being pending, so an
# unanchored substring match counts those and reports questions that do not
# exist.
#
# IT EMITS IDS, NEVER TEXT. A ruling quotes an incoming intent, which is text a
# stranger can write, and a session-start announcement lands in a model's
# context before a human has read a word of it. `D7` cannot carry a sentence.
# That holds for --format table too: ids, dates and ages, never the conflict,
# never the question, never the requirement text. The id is taken from the
# filename through a `D[0-9][0-9]*` match and the date through a YYYY-MM-DD
# match, so nothing that failed to match is ever printed - not to stdout and
# not to stderr.
#
# NO FILE MEANS NO COUNT, NOT ZERO. Three states, never collapsed:
#
#   no rulings directory         never raised one    reported as such, exit 0
#   directory cannot be read     UNKNOWN             exit 2
#   directory readable, empty    a true zero         `0 pending`, exit 0
#
# Reporting either of the first two as `0 pending` states "nothing is waiting"
# as a fact, which is the one wrong answer that looks healthy. In bash an
# unmatched glob reaches grep as a literal path, so these are told apart by
# testing the directory itself, never by trusting the count that came back.
#
# STALENESS IS DERIVED, NEVER STORED. Age comes from the `Raised:` line and is
# computed as a difference of Julian day numbers, so there is no `date -d` to
# depend on and no stored `stalled` flag for someone to forget to update. A
# `Raised:` line that is missing, blank, an em dash or not YYYY-MM-DD gives an
# age of em dash - UNKNOWN, and never 0. A value that could not be measured is
# never recorded as a measurement.
#
# OUTPUT, PER FORMAT.
#
#   ids    (default)  one id per line, sorted numerically so D2 precedes D10.
#                     When there are none, a single `#` line naming WHICH kind
#                     of none it is - the two empty outputs would otherwise be
#                     the same output. Notes go to stderr so the ids stay
#                     clean for `grep '^D'`.
#   count             exactly one token on stdout: an integer, or the word
#                     `none` when there is no rulings directory. `none` is not
#                     `0`, and a caller doing arithmetic on it fails loudly
#                     rather than believing a zero nobody measured. Every
#                     other word goes to stderr.
#   table             ID, RAISED and AGE, plus STALE when --stale-after is
#                     given. Notes are `#` lines, which no id can be confused
#                     with.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  ran and reported, including a true zero
#   1  at least one pending ruling exists, so a caller can gate on it
#   2  could not determine the state - an unreadable directory, an unreadable
#      file, or bad usage
set -euo pipefail

VERSION="pending-rulings 1.0"
ROOT="."
FORMAT="ids"
STALE_AFTER=""
DASH="—"

# Every refusal is exit 2. There is no path in this script that reports a
# number it could not measure.
refuse() { printf 'pending-rulings: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || refuse "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --format)
      [ "$#" -ge 2 ] || refuse "--format needs one of ids, count, table"
      case "$2" in
        ids|count|table) FORMAT="$2" ;;
        *) refuse "unknown --format: $2 (want ids, count or table)" ;;
      esac
      shift 2 ;;
    --stale-after)
      [ "$#" -ge 2 ] || refuse "--stale-after needs a whole number of days"
      case "$2" in
        ''|*[!0-9]*) refuse "--stale-after takes a whole number of days, not: $2" ;;
      esac
      STALE_AFTER="$2"; shift 2 ;;
    *) refuse "unknown argument: $1" ;;
  esac
done

DIR="$ROOT/.claude/productizer/rulings"

# A note lands where it cannot be mistaken for output: a `#` line for the
# formats whose stdout is read by eye, stderr for the two whose stdout is read
# by a machine.
say() {
  case "$FORMAT" in
    table) printf '# %s\n' "$1" ;;
    *)     printf 'pending-rulings: %s\n' "$1" >&2 ;;
  esac
}

# printf pads to a BYTE count, and the em dash is three bytes wide and one
# column wide, so an unknown age silently knocked the table out of alignment.
# Widen the budget by the difference rather than reaching for a locale-
# dependent character count.
col() {
  local text="$1" width="$2"
  [ "$text" = "$DASH" ] && width=$((width + 2))
  printf '%-*s' "$width" "$text"
}

# ---------------------------------------------------------------- dates
# Julian day number, integer arithmetic only. No `date -d`, which is GNU, and
# no `date -v`, which is BSD; this runs on both because it parses nothing.
jdn() {
  local y="$1" m="$2" d="$3" a yy mm
  a=$(( (14 - m) / 12 ))
  yy=$(( y + 4800 - a ))
  mm=$(( m + 12 * a - 3 ))
  printf '%s\n' "$(( d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045 ))"
}

TODAY="$(date -u +%Y-%m-%d)"
if [[ "$TODAY" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
  TODAY_JDN="$(jdn "$((10#${BASH_REMATCH[1]}))" "$((10#${BASH_REMATCH[2]}))" "$((10#${BASH_REMATCH[3]}))")"
else
  refuse "date -u did not return a YYYY-MM-DD date, so no age can be computed."
fi

# Echoes the age in days, or nothing at all when the date could not be read.
# Nothing is the point: the caller renders it as an em dash, never as 0.
age_of() {
  local raised="$1" y m d
  [[ "$raised" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]] || return 0
  y="$((10#${BASH_REMATCH[1]}))"; m="$((10#${BASH_REMATCH[2]}))"; d="$((10#${BASH_REMATCH[3]}))"
  { [ "$m" -ge 1 ] && [ "$m" -le 12 ] && [ "$d" -ge 1 ] && [ "$d" -le 31 ]; } || return 0
  printf '%s\n' "$(( TODAY_JDN - $(jdn "$y" "$m" "$d") ))"
}

# ---------------------------------------------------------------- state
# The directory test comes FIRST and decides everything. Asking the glob or the
# count first is how "unreadable" becomes "zero".
if [ ! -e "$DIR" ]; then
  case "$FORMAT" in count) printf 'none\n' ;; esac
  say "no rulings directory at $DIR: this repo has never raised one. That is not a measured zero."
  exit 0
fi

[ -d "$DIR" ] ||
  refuse "$DIR exists but is not a directory, so what is waiting is UNKNOWN - not zero."

{ [ -r "$DIR" ] && [ -x "$DIR" ]; } ||
  refuse "$DIR cannot be read, so the number waiting is UNKNOWN - not zero. A directory nobody can open is exactly where a live contradiction hides."

shopt -s nullglob
FILES=("$DIR"/D*.md)
shopt -u nullglob

for f in "${FILES[@]}"; do
  [ -r "$f" ] ||
    refuse "one of the ${#FILES[@]} ruling files in $DIR cannot be read, so the count is UNKNOWN - not zero. (The filename is withheld: it is not an id, and this line can reach a model's context.)"
done

# ---------------------------------------------------------------- match
PENDING=()
if [ "${#FILES[@]}" -gt 0 ]; then
  set +e
  MATCHED="$(grep -lxF -e 'Status: pending' -- "${FILES[@]}")"
  GREP_RC=$?
  set -e
  # 0 found, 1 none found, 2 or more an error. grep's own message is already on
  # stderr, unsuppressed, which is why an error and a no-match cannot be
  # confused here.
  [ "$GREP_RC" -ge 2 ] &&
    refuse "grep could not read every ruling file under $DIR (exit $GREP_RC), so the count is UNKNOWN - not zero."
  while IFS= read -r line; do
    [ -n "$line" ] && PENDING+=("$line")
  done <<< "$MATCHED"
fi

# ---------------------------------------------------------------- records
# One record per pending ruling: number, id, raised date. The number exists
# only so the sort is numeric - a string sort puts D10 before D2, and an order
# that changes with the id width is not a reproducible report.
RECORDS=()
UNNAMED=0
for f in "${PENDING[@]}"; do
  base="${f##*/}"
  if [[ "$base" =~ ^(D([0-9]+))[-.] ]]; then
    id="${BASH_REMATCH[1]}"
    num="${BASH_REMATCH[2]}"
  else
    UNNAMED=$((UNNAMED + 1))
    continue
  fi

  set +e
  RAISED_LINE="$(grep -m1 -e '^Raised:' -- "$f")"
  RC=$?
  set -e
  [ "$RC" -ge 2 ] &&
    refuse "a pending ruling file under $DIR could not be read while looking for its Raised: line."

  raised=""
  if [[ "$RAISED_LINE" =~ ^Raised:[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]*$ ]]; then
    raised="${BASH_REMATCH[1]}"
  fi
  RECORDS+=("$(printf '%s\t%s\t%s' "$((10#$num))" "$id" "$raised")")
done

[ "$UNNAMED" -eq 0 ] ||
  refuse "$UNNAMED pending ruling file(s) under $DIR are not named D<n>-<slug>.md, so their ids are UNKNOWN. The count cannot be reported without them, and the filename cannot be printed in place of an id."

SORTED=""
if [ "${#RECORDS[@]}" -gt 0 ]; then
  SORTED="$(printf '%s\n' "${RECORDS[@]}" | sort -t $'\t' -k1,1n)"
fi

COUNT="${#RECORDS[@]}"

# ---------------------------------------------------------------- stale
STALE_IDS=()
STALE_COUNT=0
UNKNOWN_AGE=0
if [ -n "$SORTED" ]; then
  while IFS=$'\t' read -r _num id raised; do
    age="$(age_of "$raised")"
    if [ -z "$age" ]; then
      UNKNOWN_AGE=$((UNKNOWN_AGE + 1))
      continue
    fi
    if [ -n "$STALE_AFTER" ] && [ "$age" -gt "$STALE_AFTER" ]; then
      STALE_IDS+=("$id")
      STALE_COUNT=$((STALE_COUNT + 1))
    fi
  done <<< "$SORTED"
fi

stale_notes() {
  [ -n "$STALE_AFTER" ] || return 0
  if [ "$STALE_COUNT" -gt 0 ]; then
    say "$STALE_COUNT of $COUNT pending are older than $STALE_AFTER days: $(IFS=', '; printf '%s' "${STALE_IDS[*]}")"
  else
    say "0 of $COUNT pending are older than $STALE_AFTER days."
  fi
  [ "$UNKNOWN_AGE" -eq 0 ] ||
    say "$UNKNOWN_AGE of $COUNT pending have no readable Raised: date, so their age is UNKNOWN and they are neither stale nor fresh."
  # Explicit: without it the failing test above is this function's exit status,
  # and `set -e` would end the run on the ordinary case of nothing being stale.
  return 0
}

# The contract's own rule, applied to the number this script just measured.
queue_note() {
  [ "$COUNT" -ge 3 ] || return 0
  say "$COUNT pending in one repo: intake is running ahead of whoever has to rule. Stop taking intents in that area until the queue drains - a bulk ruling is a rubber stamp."
}

# ---------------------------------------------------------------- report
case "$FORMAT" in
  count)
    printf '%s\n' "$COUNT"
    if [ "$COUNT" -eq 0 ]; then
      say "0 pending, measured: $DIR is readable and holds ${#FILES[@]} ruling file(s), none with Status: pending."
    fi
    stale_notes
    queue_note
    ;;

  ids)
    if [ "$COUNT" -eq 0 ]; then
      printf '# 0 pending, measured: %s is readable and holds %s ruling file(s), none with Status: pending.\n' \
        "$DIR" "${#FILES[@]}"
    else
      printf '%s\n' "$SORTED" | while IFS=$'\t' read -r _num id _raised; do
        printf '%s\n' "$id"
      done
    fi
    stale_notes
    queue_note
    ;;

  table)
    if [ "$COUNT" -eq 0 ]; then
      printf '# 0 pending, measured: %s is readable and holds %s ruling file(s), none with Status: pending.\n' \
        "$DIR" "${#FILES[@]}"
    else
      printf '# %s pending in %s\n' "$COUNT" "$DIR"
      if [ -n "$STALE_AFTER" ]; then
        printf '%s%s%s%s\n' "$(col ID 9)" "$(col RAISED 13)" "$(col AGE 7)" "STALE"
      else
        printf '%s%s%s\n' "$(col ID 9)" "$(col RAISED 13)" "AGE"
      fi
      while IFS=$'\t' read -r _num id raised; do
        age="$(age_of "$raised")"
        # RAISED shows only a date an age was actually computed from. A
        # `Raised: 2026-13-40` passes the digit shape and fails the calendar,
        # and printing it beside an unknown age would show a date the report
        # does not stand behind.
        shown_raised="$DASH"
        if [ -z "$age" ]; then
          shown_age="$DASH"
          shown_stale="$DASH"
        else
          shown_raised="$raised"
          shown_age="$age"
          shown_stale="no"
          if [ -n "$STALE_AFTER" ] && [ "$age" -gt "$STALE_AFTER" ]; then
            shown_stale="yes"
          fi
        fi
        if [ -n "$STALE_AFTER" ]; then
          printf '%s%s%s%s\n' "$(col "$id" 9)" "$(col "$shown_raised" 13)" "$(col "$shown_age" 7)" "$shown_stale"
        else
          printf '%s%s%s\n' "$(col "$id" 9)" "$(col "$shown_raised" 13)" "$shown_age"
        fi
      done <<< "$SORTED"
      stale_notes
    fi
    queue_note
    ;;
esac

[ "$COUNT" -eq 0 ] || exit 1
exit 0
