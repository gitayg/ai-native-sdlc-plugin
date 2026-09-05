#!/usr/bin/env bash
# spec-doctor.sh [--version] [--help] [--root DIR] [--spec PATH]
#
# ONE COMMAND, ONE PAGE, EVERY SELF-CHECK THE SPEC ALREADY HAS. It runs the
# existing tools and lays their answers out together; it computes nothing a
# tool already computes, and it CHANGES NOTHING. A doctor that edits the file
# it is diagnosing is a doctor nobody can run twice and compare.
#
# WHY IT EXISTS. The checks are all here, and they are all separate. Nobody
# runs five scripts before touching the spec, so a defect that only one of
# them reports sits in that one script's output and becomes furniture. The
# repo's own header said `28 active, 4 superseded` while the file held 32 and
# 6 - reported the whole time, by a tool nobody was running.
#
# WHAT IT REPORTS.
#
#   1. GRAMMAR AND ID PERMANENCE      `validate-spec.py`
#   2. COUNTS, DECLARED v COUNTED     `validate-spec.py --counts`
#   3. SUPERSEDED CHAINS              `spec-requirements.sh`, walked
#   4. ACCEPTANCE ROWS                `check-acceptance-rows.sh`
#   5. RULINGS AWAITING A HUMAN       `pending-rulings.sh`
#
# Section 3 is the only place this script does arithmetic of its own, and it
# does it over the shared parser's output rather than over the file: one hop
# is what `validate-spec.py` already checks, and a CHAIN - R14 to R23 to R33 -
# is what no single check sees. A citation that lands on a superseded
# requirement leads a reader to a sentence nobody may act on.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every section ran, nothing found
#   1  every section ran, findings reported above
#   2  a section COULD NOT RUN - a missing tool, an unreadable spec, a tool
#      that refused. Never 0, and never 1 either: a report with a hole in it
#      has not found nothing, it has not looked. Constitution P1.
#
# COULD-NOT-MEASURE OUTRANKS FINDINGS, deliberately. Both are printed and
# both are counted on the summary line, so nothing is hidden by the ranking -
# but the exit code says the loudest true thing, which is that the page is
# incomplete.
#
# A WARN IS A FINDING HERE. `validate-spec.py` exits 0 on warnings because it
# gates CI and a pre-existing WARN must not block a merge. This is not a gate;
# it is the page you read before you touch the spec, and a warning nobody is
# told about is the failure mode it exists to end.
#
# STDERR IS NEVER SUPPRESSED. Each tool is run with its stderr merged into the
# section it belongs to, so a refusal is printed where it happened rather than
# vanishing. Nothing here writes `2>/dev/null`.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no in-place sed.
set -euo pipefail

VERSION="spec-doctor 1.0"

ROOT="."
SPEC=""

refuse() { printf 'spec-doctor: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)
      [ "$#" -ge 2 ] || refuse "--root needs a directory"
      ROOT="$2"; shift 2 ;;
    --spec)
      [ "$#" -ge 2 ] || refuse "--spec needs a file"
      SPEC="$2"; shift 2 ;;
    *) refuse "unknown argument: $1" ;;
  esac
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[ -n "$SPEC" ] || SPEC="$ROOT/.claude/productizer/spec.md"

VALIDATE="$SCRIPT_DIR/validate-spec.py"
PARSE="$SCRIPT_DIR/spec-requirements.sh"
ROWS="$SCRIPT_DIR/check-acceptance-rows.sh"
RULINGS="$SCRIPT_DIR/pending-rulings.sh"

FINDINGS=0
UNMEASURED=0

finding() { FINDINGS=$((FINDINGS + 1)); }
unmeasured() {
  UNMEASURED=$((UNMEASURED + 1))
  printf '    COULD NOT MEASURE: %s\n' "$1"
}

section() { printf '\n%s\n' "$1"; printf '%s\n' "----------------------------------------------------------------------"; }

# A tool that is not there is REPORTED, never skipped - R13. `runnable`
# answers for the file; the caller decides what its section says without it.
# `validate-spec.py` is handed to `python3`, so only the shell tools, which
# are executed directly, need the execute bit.
runnable() { [ -f "$1" ] && [ -x "$1" ]; }

printf 'spec-doctor %s\n' "${VERSION#spec-doctor }"
printf 'spec: %s\n' "$SPEC"
if [ ! -f "$SPEC" ] || [ ! -r "$SPEC" ]; then
  printf 'spec-doctor: cannot read %s. An unreadable spec is unmeasured, not clean - no section below could run.\n' "$SPEC" >&2
  exit 2
fi
printf 'root: %s\n' "$ROOT"

# ------------------------------------------------- 1. grammar and id permanence

section "1. GRAMMAR AND ID PERMANENCE  (validate-spec.py)"
if [ ! -f "$VALIDATE" ]; then
  unmeasured "$VALIDATE is not there; the grammar and the ids were not checked"
else
  set +e
  VALIDATE_OUT="$(python3 "$VALIDATE" "$SPEC" 2>&1)"
  VALIDATE_RC=$?
  set -e
  printf '%s\n' "$VALIDATE_OUT" | sed 's/^/    /'
  case "$VALIDATE_RC" in
    0|1) ;;
    *) unmeasured "validate-spec.py exited $VALIDATE_RC; its own contract calls that unmeasured or a usage error, not a pass" ;;
  esac
  V_ERRORS="$(printf '%s\n' "$VALIDATE_OUT" | grep -c ' ERROR ' || true)"
  V_WARNS="$(printf '%s\n' "$VALIDATE_OUT" | grep -c ' WARN ' || true)"
  printf '    -> %s error line(s), %s warning line(s)\n' "$V_ERRORS" "$V_WARNS"
  [ "$V_ERRORS" -eq 0 ] || finding
  [ "$V_WARNS" -eq 0 ] || finding
fi

# --------------------------------------------------- 2. counts, declared v counted

section "2. COUNTS, DECLARED VERSUS COUNTED  (validate-spec.py --counts)"
if [ ! -f "$VALIDATE" ]; then
  unmeasured "$VALIDATE is not there; the header counts were compared against nothing"
else
  set +e
  COUNTS_OUT="$(python3 "$VALIDATE" --counts "$SPEC" 2>&1)"
  COUNTS_RC=$?
  set -e
  printf '    %-12s %10s %10s   %s\n' status declared counted verdict
  printf '%s\n' "$COUNTS_OUT" | awk -F'\t' '
    $1 == "COUNT" {
      verdict = ($4 == "-") ? "NOT DECLARED" : ($4 == $5 ? "agrees" : "STALE")
      printf "    %-12s %10s %10s   %s\n", $3, $4, $5, verdict
    }'
  printf '%s\n' "$COUNTS_OUT" | awk -F'\t' '
    $1 == "DECLARED" { printf "    the header says   : %s   (line %s)\n", $4, $3 }
    $1 == "DERIVED"  { printf "    the file counts to: %s\n", $4 }
    $1 !~ /^(COUNT|DECLARED|DERIVED)$/ { printf "    %s\n", $0 }'
  case "$COUNTS_RC" in
    0) ;;
    1) finding ;;
    *) unmeasured "validate-spec.py --counts exited $COUNTS_RC; no comparison was made" ;;
  esac
fi

# ------------------------------------------------------- 3. superseded chains

section "3. SUPERSEDED CHAINS  (spec-requirements.sh, walked)"
if ! runnable "$PARSE"; then
  unmeasured "$PARSE is not there; the supersede pointers were not followed"
else
  set +e
  PARSE_OUT="$("$PARSE" "$SPEC" 2>&1)"
  PARSE_RC=$?
  set -e
  if [ "$PARSE_RC" -ne 0 ]; then
    printf '%s\n' "$PARSE_OUT" | sed 's/^/    /'
    unmeasured "spec-requirements.sh exited $PARSE_RC; no chain was followed"
  else
    CHAIN_OUT="$(printf '%s\n' "$PARSE_OUT" | awk -F'\t' '
      { status[$1] = $3; target[$1] = $4; order[++n] = $1 }
      END {
        bad = 0
        shown = 0
        for (i = 1; i <= n; i++) {
          id = order[i]
          if (status[id] != "superseded") continue
          shown++
          chain = id
          cur = id
          hops = 0
          note = ""
          while (1) {
            nxt = target[cur]
            if (nxt == "" || nxt == "-") { note = "POINTS AT NOTHING"; break }
            chain = chain " -> " nxt
            if (!(nxt in status)) { note = "TARGET NOT IN THIS FILE"; break }
            if (++hops > 50) { note = "CYCLE"; break }
            if (status[nxt] != "superseded") break
            cur = nxt
          }
          # A chain longer than one hop means this marker points at a
          # requirement that is ITSELF superseded - the exact thing the R14
          # note in this repo says was avoided by moving the pointer, because
          # a citation has to reach a sentence someone may still act on. It is
          # a finding, not decoration.
          if (note == "" && hops > 1) note = "POINTS AT A SUPERSEDED ID, " hops " HOPS TO A LIVE ONE"
          if (note != "") bad++
          if (note == "") note = "ends on active " nxt
          printf "    %-52s %s\n", chain, note
        }
        printf "COUNTS %d %d\n", shown, bad
      }')"
    printf '%s\n' "$CHAIN_OUT" | grep -v '^COUNTS ' || true
    CHAIN_SHOWN="$(printf '%s\n' "$CHAIN_OUT" | awk '/^COUNTS /{print $2}')"
    CHAIN_BAD="$(printf '%s\n' "$CHAIN_OUT" | awk '/^COUNTS /{print $3}')"
    printf '    -> %s superseded requirement(s), %s chain(s) a reader cannot follow to a live id in one hop\n' \
      "$CHAIN_SHOWN" "$CHAIN_BAD"
    [ "$CHAIN_BAD" -eq 0 ] || finding
  fi
fi

# --------------------------------------------------------- 4. acceptance rows

section "4. ACCEPTANCE ROWS  (check-acceptance-rows.sh)"
if ! runnable "$ROWS"; then
  unmeasured "$ROWS is not there; whether every active requirement has a row is unknown"
else
  set +e
  ROWS_OUT="$("$ROWS" --root "$ROOT" --spec "$SPEC" 2>&1)"
  ROWS_RC=$?
  set -e
  # The per-citation dump is that check's own page. What belongs on THIS page
  # is the tallies and the ids it could not verify - the rest is one command
  # away and printing it here buries the two lines somebody came for.
  printf '%s\n' "$ROWS_OUT" \
    | grep -E 'requirements read:|active requirements examined:|no row required:|acceptance criteria rows read:|requirements missing an acceptance row:|rows naming something that does not resolve:|^ *NOT VERIFIED|^ *R[0-9]+ +[^ ]+:[0-9]+$' \
    | sed 's/^ */    /' || true
  case "$ROWS_RC" in
    0) ;;
    1) finding
       printf '    -> check-acceptance-rows.sh reported findings; run it directly for the full page\n' ;;
    *) printf '%s\n' "$ROWS_OUT" | sed 's/^/    /'
       unmeasured "check-acceptance-rows.sh exited $ROWS_RC" ;;
  esac
fi

# ------------------------------------------------------------- 5. rulings

section "5. RULINGS AWAITING A HUMAN  (pending-rulings.sh)"
if ! runnable "$RULINGS"; then
  unmeasured "$RULINGS is not there; whether a contradiction is waiting is unknown"
else
  set +e
  RULINGS_OUT="$("$RULINGS" --root "$ROOT" --format count 2>&1)"
  RULINGS_RC=$?
  set -e
  printf '%s\n' "$RULINGS_OUT" | sed 's/^/    /'
  case "$RULINGS_RC" in
    0) PENDING="$(printf '%s\n' "$RULINGS_OUT" | awk '/^[0-9]+$/{print; exit}')"
       if [ -z "$PENDING" ]; then
         printf '    -> `none` is the word that tool uses for "never raised one". It is\n'
         printf '       not a measured 0, and it is not a hole in this page either: nothing\n'
         printf '       can be waiting where nothing was ever raised.\n'
       elif [ "$PENDING" -gt 0 ]; then
         finding
         printf '    -> %s ruling(s) pending; R12 says nothing that depends on them may merge\n' "$PENDING"
       else
         printf '    -> 0 pending, measured.\n'
       fi ;;
    *) unmeasured "pending-rulings.sh exited $RULINGS_RC" ;;
  esac
fi

# ------------------------------------------------------------------ summary

section "SUMMARY"
printf '    sections that could not run: %d\n' "$UNMEASURED"
printf '    sections reporting findings: %d\n' "$FINDINGS"
printf '    this command reports; it changes nothing. Nothing above was fixed.\n'

if [ "$UNMEASURED" -gt 0 ]; then
  printf '    EXIT 2 - the page has a hole in it. What did not run is not what was found to be clean.\n'
  exit 2
fi
if [ "$FINDINGS" -gt 0 ]; then
  printf '    EXIT 1 - findings above.\n'
  exit 1
fi
printf '    EXIT 0 - every section ran and found nothing.\n'
exit 0
