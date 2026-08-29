#!/usr/bin/env bash
# req-trailer.sh — the join between a permanent requirement id and the commits
#                  that implement it, and between a requirement and its tests.
#
# The spec already owns the hard half: ids that are never reused and never
# renumbered. What was missing is the other direction. Given R14, nothing could
# answer "which commits built this", and given a commit, nothing recorded which
# agreement it served. The join is one git trailer:
#
#     Productizer-Req: R14,R22
#
# A trailer is the cheapest provenance mechanism there is. It is part of the
# commit message, so it survives clone, fetch, rebase, cherry-pick, format-patch
# and mirroring with no infrastructure at all, and it is queryable with
# `git log --grep` on a machine that has never heard of this repo's tooling.
# There is no database to keep in step, nothing to migrate, and nothing that
# rots when the tool that wrote it is uninstalled.
#
# THE OTHER HALF: COVERAGE IDS.
#
#   A commit says a requirement was built. It does not say it is tested. A
#   coverage id says that, and it is deliberately NOT a second id authority:
#
#     COV_<requirement-id>_<slug>
#
#   For R14 that is COV_ followed by R14 followed by _halts_on_contradiction.
#   This file does not spell a whole one out on purpose. --coverage scans every
#   tracked file in the repository it is pointed at, and this script gets
#   vendored INTO those repositories — a literal example in this header would
#   be read as genuine coverage of a genuine requirement, which is the exact
#   false positive the mode exists to expose. references/traceability.md does
#   spell them out, and says so.
#
#   The requirement id is quoted verbatim inside the coverage id, so a coverage
#   id cannot exist without naming a requirement, cannot be renumbered
#   independently, and stops resolving the moment the requirement it names stops
#   existing. That is the point: it makes an orphan mechanically detectable in
#   both directions — a requirement nothing covers, and a coverage id pointing
#   at a requirement that is gone or superseded.
#
#   Full convention: references/traceability.md.
#
# MODES.
#
#   --add <ids> --file <msg>   merge the trailer into a commit-message file.
#                              Idempotent: run twice, and the file is unchanged.
#   --validate [--file <msg> | --rev <rev>]
#                              every id in the trailer must exist in the spec.
#                              An unknown id is an error that names it.
#   --query <id>               the commits carrying that id.
#   --orphans                  active requirements no commit claims.
#   --coverage                 active requirements no COV_ id covers, plus
#                              COV_ ids naming a requirement that is gone or
#                              superseded.
#
# HOW IT REFUSES TO REPORT A ZERO IT DID NOT MEASURE.
#
#   "0 orphans" reads as a clean bill of health, and four different situations
#   can produce it. They are kept apart and none of them is printed as a zero:
#
#     no living spec                     -> exit 2. Nothing to trace.
#     not a git repository, or git broke -> exit 4. Nothing to trace against.
#     a repository with no commits yet   -> exit 4. No history to search.
#     commits, but not one carries a
#     trailer                            -> exit 4. The mechanism is not in use
#                                          here; coverage is UNKNOWN, not zero.
#
#   Only the fifth case — commits exist and some of them carry trailers — is a
#   measurement, and its report prints the counts it was measured from.
#   The same discipline applies to --coverage: no file could be listed, or not
#   one file carries a COV_ id, are both "cannot determine", not "0 uncovered".
#
# WHAT IT SEARCHES, AND WHAT IT THEREFORE CANNOT SEE.
#
#   --query and --orphans read `git log HEAD` — the full ancestry of HEAD, every
#   parent of every merge included, and nothing outside it. A commit that exists
#   only on another branch, or only on a remote that has not been fetched, is
#   invisible, and its requirement therefore looks orphaned. A shallow
#   clone is worse: it looks like a short history rather than a truncated one.
#   The report always names how many commits it actually walked, so a suspicious
#   answer can be recognised as one. KNOWN_LIMITATIONS.md has the rest.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  ran, and there is nothing to report. Backed by printed counts.
#   1  crashed before reaching a report. Read as undetermined, never as clean.
#   2  bad usage, or no spec / no requirement ids in it — nothing was compared.
#   3  a finding: an unknown id, an orphaned requirement, a dangling coverage
#      id. The run succeeded; what it found did not.
#   4  CANNOT DETERMINE. Not a pass, and not a zero.
#
# It never suppresses stderr. An error and a genuine no-match look identical
# once hidden, and telling those two apart is the whole job.
#
# Every date it prints is pinned to UTC. A traceability record whose timestamps
# depend on the reader's laptop is not a record.
set -euo pipefail
export LC_ALL=C

TMP=""
on_exit() {
  status=$?
  if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then rm -rf "$TMP"; fi
  case "$status" in
    0 | 2 | 3 | 4) exit "$status" ;;
    *)
      printf 'req-trailer: exited %s before reaching a report. Undetermined, not clean.\n' "$status" >&2
      exit 1
      ;;
  esac
}
trap on_exit EXIT

TRAILER_KEY="Productizer-Req"
SPEC_REL=".claude/productizer/spec.md"

die_usage() { printf 'req-trailer: %s\n' "$1" >&2; exit 2; }
undetermined() { printf 'req-trailer: CANNOT DETERMINE — %s\n' "$1" >&2; exit 4; }

usage() {
  cat <<'USAGE'
req-trailer.sh — requirement-id traceability, both directions.

  req-trailer.sh --add R14,R22 --file .git/COMMIT_EDITMSG
  req-trailer.sh --validate [--file <msg> | --rev <rev>]
  req-trailer.sh --query R14 [--limit N]
  req-trailer.sh --orphans
  req-trailer.sh --coverage [--include-ignored]

Common options:
  --repo <dir>     repository root (default: current directory)
  --spec <path>    living spec (default: <repo>/.claude/productizer/spec.md)
  --limit <n>      most rows to print per section (default 50)
  -h, --help       this text

Exit: 0 nothing to report · 1 crashed · 2 usage/no spec · 3 a finding
      4 cannot determine (never printed as a zero)
USAGE
}

MODE=""
IDS_ARG=""
FILE=""
REV=""
QUERY_ID=""
ROOT=""
SPEC=""
LIMIT=50
INCLUDE_IGNORED=0

set_mode() {
  [ -z "$MODE" ] || die_usage "--$1 and --$MODE are two different jobs; run one at a time"
  MODE="$1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --add)        set_mode add; [ "$#" -ge 2 ] || die_usage "--add needs one or more ids, e.g. --add R14,R22"; IDS_ARG="$2"; shift 2 ;;
    --add=*)      set_mode add; IDS_ARG="${1#--add=}"; shift ;;
    --validate)   set_mode validate; shift ;;
    --query)      set_mode query; [ "$#" -ge 2 ] || die_usage "--query needs a requirement id, e.g. --query R14"; QUERY_ID="$2"; shift 2 ;;
    --query=*)    set_mode query; QUERY_ID="${1#--query=}"; shift ;;
    --orphans)    set_mode orphans; shift ;;
    --coverage)   set_mode coverage; shift ;;
    --file)       [ "$#" -ge 2 ] || die_usage "--file needs a path"; FILE="$2"; shift 2 ;;
    --file=*)     FILE="${1#--file=}"; shift ;;
    --rev)        [ "$#" -ge 2 ] || die_usage "--rev needs a revision"; REV="$2"; shift 2 ;;
    --rev=*)      REV="${1#--rev=}"; shift ;;
    --repo)       [ "$#" -ge 2 ] || die_usage "--repo needs a directory"; ROOT="$2"; shift 2 ;;
    --repo=*)     ROOT="${1#--repo=}"; shift ;;
    --spec)       [ "$#" -ge 2 ] || die_usage "--spec needs a path"; SPEC="$2"; shift 2 ;;
    --spec=*)     SPEC="${1#--spec=}"; shift ;;
    --limit)      [ "$#" -ge 2 ] || die_usage "--limit needs a number"; LIMIT="$2"; shift 2 ;;
    --limit=*)    LIMIT="${1#--limit=}"; shift ;;
    --include-ignored) INCLUDE_IGNORED=1; shift ;;
    -h | --help)  usage; exit 0 ;;
    -*)           die_usage "unknown option: $1" ;;
    *)            die_usage "unexpected argument '$1'. Paths go after --file, revisions after --rev." ;;
  esac
done

[ -n "$MODE" ] || { usage >&2; die_usage "pick one of --add, --validate, --query, --orphans, --coverage"; }
case "$LIMIT" in '' | *[!0-9]*) die_usage "--limit must be a whole number, not '$LIMIT'" ;; esac
[ "$LIMIT" -gt 0 ] || die_usage "--limit must be at least 1"

[ -n "$ROOT" ] || ROOT="."
[ -d "$ROOT" ] || die_usage "no such directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"
[ -n "$SPEC" ] || SPEC="$ROOT/$SPEC_REL"

command -v git >/dev/null || die_usage "git is not on PATH. Every mode here is a git operation."

TMP="$(mktemp -d "${TMPDIR:-/tmp}/req-trailer.XXXXXX")"

SOH=$'\001'
STX=$'\002'

# --- the ids the spec actually holds ---------------------------------------
#
# Matches the requirement pattern stage-status.sh, build-view.sh and
# drift-reverse.sh already count on: a list item whose first bold run is the
# id, with the status marker on the line after it. Four readers of one shape
# disagree the moment one of them is edited, so the pattern is copied
# deliberately and said out loud in each place.
read_spec() {
  [ -f "$SPEC" ] || die_usage "no living spec at ${SPEC#"$ROOT"/}. There is nothing to trace ids against, so nothing was traced."
  awk '
    /^([-*][ \t]+)?\*\*R[0-9]+\*\*/ {
      if (match($0, /R[0-9]+/)) {
        cur = substr($0, RSTART, RLENGTH)
        st[cur] = "active"
        if (!(cur in seen)) { seen[cur] = 1; order[++n] = cur }
      }
      next
    }
    cur != "" {
      t = $0; sub(/^[ \t]+/, "", t)
      if (t ~ /^Superseded by/) { st[cur] = "superseded"; cur = ""; next }
      if (t ~ /^Withdrawn\./)   { st[cur] = "withdrawn";  cur = ""; next }
      cur = ""
    }
    END { for (i = 1; i <= n; i++) printf "%s\t%s\n", order[i], st[order[i]] }
  ' "$SPEC" >"$TMP/ids.tsv"

  N_IDS=$(awk 'END { print NR + 0 }' "$TMP/ids.tsv")
  if [ "$N_IDS" -eq 0 ]; then
    die_usage "${SPEC#"$ROOT"/} holds no ids matching '**R<n>**'. Nothing to trace against; this is not a clean tree."
  fi
  awk -F'\t' '$2 == "active"     { print $1 }' "$TMP/ids.tsv" | sort -u >"$TMP/active"
  awk -F'\t' '$2 == "superseded" { print $1 }' "$TMP/ids.tsv" | sort -u >"$TMP/superseded"
  awk -F'\t' '$2 == "withdrawn"  { print $1 }' "$TMP/ids.tsv" | sort -u >"$TMP/withdrawn"
  sort -u "$TMP/ids.tsv" | cut -f1 | sort -u >"$TMP/known"
  N_ACTIVE=$(awk 'END { print NR + 0 }' "$TMP/active")
  N_SUPER=$(awk 'END { print NR + 0 }' "$TMP/superseded")
  N_WITHDRAWN=$(awk 'END { print NR + 0 }' "$TMP/withdrawn")
}

# --- ids handed to us on the command line ----------------------------------
#
# Refuses rather than guesses. 'r14' and 'R-14' are not this repo's id format,
# and quietly repairing them would put a shape into commit history that the
# spec's own readers do not match.
normalise_ids() {
  printf '%s' "$1" | tr ',;' '  ' | tr -s '[:space:]' '\n' | awk '
    NF {
      if ($1 !~ /^R[0-9]+$/) {
        printf "req-trailer: '\''%s'\'' is not a requirement id. This spec numbers requirements R<n> — R14, R22 — and ids are never reused or renumbered.\n", $1 > "/dev/stderr"
        bad = 1
        next
      }
      print $1
    }
    END { if (bad) exit 2 }
  ' | sort -u -V
}

# --- what the history says --------------------------------------------------
N_COMMITS=0
N_TRAILED=0

scan_history() {
  if ! git -C "$ROOT" rev-parse --git-dir >"$TMP/gitdir" 2>"$TMP/git.err"; then
    undetermined "$ROOT is not a git repository, or git failed: $(tr '\n' ' ' <"$TMP/git.err")
No history means no commits to trace ids to. This is not zero orphans."
  fi
  if ! git -C "$ROOT" rev-parse --verify HEAD >"$TMP/head" 2>"$TMP/head.err"; then
    undetermined "this repository has no commits yet (no HEAD).
There is no history to search, so no requirement can be shown as traced or as orphaned. This is not zero orphans."
  fi

  TZ=UTC git -C "$ROOT" log \
    --date=format-local:'%Y-%m-%d %H:%M:%S' \
    --format="${SOH}%H${STX}%ad${STX}%s%n%B" >"$TMP/log" 2>"$TMP/log.err" \
    || die_usage "git log failed: $(tr '\n' ' ' <"$TMP/log.err")"

  awk -v SOH="$SOH" -v STX="$STX" -v PAIRS="$TMP/pairs.tsv" -v BAD="$TMP/badtok" -v COUNTS="$TMP/counts" '
    BEGIN { ncommit = 0; ntrail = 0; sha = ""; date = ""; subj = "" }
    substr($0, 1, 1) == SOH {
      ncommit++
      n = split(substr($0, 2), f, STX)
      sha = f[1]; date = (n >= 2 ? f[2] : ""); subj = (n >= 3 ? f[3] : "")
      has = 0
      next
    }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (tolower(substr(line, 1, 16)) != "productizer-req:") next
      val = substr(line, 17)
      gsub(/[,;]/, " ", val)
      m = split(val, ids, /[ \t]+/)
      for (i = 1; i <= m; i++) {
        if (ids[i] == "") continue
        if (ids[i] ~ /^R[0-9]+$/) { s = ids[i] "\t" sha "\t" date "\t" subj; print s > PAIRS }
        else                      { s = ids[i] "\t" sha;                     print s > BAD }
      }
      if (!has) { has = 1; ntrail++ }
    }
    END { s = ncommit "\t" ntrail; print s > COUNTS }
  ' "$TMP/log"

  [ -f "$TMP/pairs.tsv" ] || : >"$TMP/pairs.tsv"
  [ -f "$TMP/badtok" ]    || : >"$TMP/badtok"
  N_COMMITS=$(cut -f1 "$TMP/counts")
  N_TRAILED=$(cut -f2 "$TMP/counts")

  if [ "$N_TRAILED" -eq 0 ]; then
    undetermined "walked $N_COMMITS commit(s) of HEAD's history and not one carries a '${TRAILER_KEY}:' trailer.
The mechanism is not in use in this repository, so requirement coverage here is UNKNOWN. Reporting it as '0 traced' or '$N_ACTIVE orphans' would both be inventions.
Install templates/prepare-commit-msg.sh, or add the trailer by hand, and this becomes measurable."
  fi
  cut -f1 "$TMP/pairs.tsv" | sort -u >"$TMP/traced"
}

# ===========================================================================
# --add
# ===========================================================================
if [ "$MODE" = add ]; then
  [ -n "$FILE" ] || die_usage "--add needs --file <commit-message-file>. It edits a message; it does not edit history."
  [ -f "$FILE" ] || die_usage "no such commit-message file: $FILE"
  [ -w "$FILE" ] || die_usage "commit-message file is not writable: $FILE"

  normalise_ids "$IDS_ARG" >"$TMP/want" || exit 3
  [ -s "$TMP/want" ] || die_usage "--add was given no usable requirement id"

  # If the spec is reachable, an id that is not in it never reaches history.
  # A trailer naming an id nobody can resolve is worse than no trailer: it
  # reads as provenance and is not.
  if [ -f "$SPEC" ]; then
    read_spec
    comm -23 "$TMP/want" "$TMP/known" >"$TMP/unknown"
    if [ -s "$TMP/unknown" ]; then
      printf 'req-trailer: refusing to write a trailer naming %s that %s does not contain:\n' \
        "$(awk 'END { print (NR == 1 ? "an id" : "ids") }' "$TMP/unknown")" "${SPEC#"$ROOT"/}" >&2
      while IFS= read -r bad; do printf '  %s — not in the spec\n' "$bad" >&2; done <"$TMP/unknown"
      printf 'The commit message was NOT modified.\n' >&2
      exit 3
    fi
  fi

  # Existing value, if any. Merging rather than replacing is what makes a
  # second run a no-op AND makes two separate --add calls additive.
  awk '
    { line = $0; sub(/^[ \t]+/, "", line) }
    tolower(substr(line, 1, 16)) == "productizer-req:" { print substr(line, 17) }
  ' "$FILE" >"$TMP/existing.raw"

  if [ -s "$TMP/existing.raw" ]; then
    tr ',;' '  ' <"$TMP/existing.raw" | tr -s '[:space:]' '\n' \
      | awk '$1 ~ /^R[0-9]+$/ { print }' | sort -u -V >"$TMP/have"
  else
    : >"$TMP/have"
  fi

  sort -u -V "$TMP/want" "$TMP/have" >"$TMP/merged"
  MERGED_VALUE="$(paste -sd, - <"$TMP/merged")"

  # git interpret-trailers is the only correct placer of a trailer: it knows
  # where the trailer block ends, that '#' comment lines and a scissors line
  # are not part of the message, and that a subject-only message needs a blank
  # line first. Hand-rolled appending gets all three wrong.
  git interpret-trailers \
      --if-exists replace --if-missing add \
      --trailer "${TRAILER_KEY}: ${MERGED_VALUE}" \
      "$FILE" >"$TMP/msg.new" 2>"$TMP/it.err" \
    || die_usage "git interpret-trailers failed: $(tr '\n' ' ' <"$TMP/it.err")"

  if cmp -s "$FILE" "$TMP/msg.new"; then
    printf '%s: %s already present and unchanged (%s)\n' "$TRAILER_KEY" "$MERGED_VALUE" "$FILE"
  else
    cat "$TMP/msg.new" >"$FILE"
    printf '%s: %s\n' "$TRAILER_KEY" "$MERGED_VALUE"
  fi
  exit 0
fi

# ===========================================================================
# --validate
# ===========================================================================
if [ "$MODE" = validate ]; then
  [ -z "$FILE" ] || [ -z "$REV" ] || die_usage "--validate reads one message: --file or --rev, not both"
  read_spec

  if [ -n "$FILE" ]; then
    [ -f "$FILE" ] || die_usage "no such commit-message file: $FILE"
    SOURCE="$FILE"
    cp "$FILE" "$TMP/msg"
  else
    [ -n "$REV" ] || REV=HEAD
    SOURCE="commit $REV"
    git -C "$ROOT" log -1 --format=%B "$REV" >"$TMP/msg" 2>"$TMP/rev.err" \
      || die_usage "cannot read $REV: $(tr '\n' ' ' <"$TMP/rev.err")"
  fi

  awk '
    { line = $0; sub(/^[ \t]+/, "", line) }
    tolower(substr(line, 1, 16)) == "productizer-req:" { print substr(line, 17) }
  ' "$TMP/msg" >"$TMP/val.raw"

  if [ ! -s "$TMP/val.raw" ]; then
    undetermined "$SOURCE carries no '${TRAILER_KEY}:' trailer.
There is nothing to validate. An absent trailer is not a valid one — it is an untraced change."
  fi

  tr ',;' '  ' <"$TMP/val.raw" | tr -s '[:space:]' '\n' | awk 'NF' >"$TMP/tokens"
  awk '$1 !~ /^R[0-9]+$/' "$TMP/tokens" | sort -u >"$TMP/malformed"
  awk '$1 ~ /^R[0-9]+$/'  "$TMP/tokens" | sort -u >"$TMP/cited"

  comm -23 "$TMP/cited" "$TMP/known" >"$TMP/unknown"
  comm -12 "$TMP/cited" "$TMP/superseded" >"$TMP/cited.super"
  comm -12 "$TMP/cited" "$TMP/withdrawn"  >"$TMP/cited.withdrawn"

  N_CITED=$(awk 'END { print NR + 0 }' "$TMP/cited")
  fail=0

  if [ -s "$TMP/malformed" ]; then
    fail=1
    while IFS= read -r t; do
      printf "req-trailer: '%s' in the trailer of %s is not a requirement id. Ids are R<n>.\n" "$t" "$SOURCE" >&2
    done <"$TMP/malformed"
  fi
  if [ -s "$TMP/unknown" ]; then
    fail=1
    while IFS= read -r t; do
      printf 'req-trailer: %s is cited by %s but does not exist in %s. Either the id was mistyped, or it was invented, or the spec it was written against is not the spec here.\n' \
        "$t" "$SOURCE" "${SPEC#"$ROOT"/}" >&2
    done <"$TMP/unknown"
  fi

  # Superseded and withdrawn are NOT errors. An id keeps its sentence forever,
  # and a commit that touched a requirement before it was replaced is telling
  # the truth about the history it belongs to. It is worth saying out loud.
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    printf 'req-trailer: note — %s is cited by %s and is superseded in the spec. Correct for a commit made before the replacement; worth a look on a new one.\n' "$t" "$SOURCE" >&2
  done <"$TMP/cited.super"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    printf 'req-trailer: note — %s is cited by %s and is withdrawn in the spec.\n' "$t" "$SOURCE" >&2
  done <"$TMP/cited.withdrawn"

  if [ "$fail" = 1 ]; then
    printf 'req-trailer: %s did not validate.\n' "$SOURCE" >&2
    exit 3
  fi
  printf 'req-trailer: %s — %s cited id(s) all exist in %s (%s active, %s superseded, %s withdrawn on file).\n' \
    "$SOURCE" "$N_CITED" "${SPEC#"$ROOT"/}" "$N_ACTIVE" "$N_SUPER" "$N_WITHDRAWN"
  exit 0
fi

# ===========================================================================
# --query
# ===========================================================================
if [ "$MODE" = query ]; then
  normalise_ids "$QUERY_ID" >"$TMP/q" || exit 3
  [ "$(awk 'END { print NR + 0 }' "$TMP/q")" -eq 1 ] || die_usage "--query takes exactly one id"
  QID="$(cat "$TMP/q")"

  read_spec
  scan_history

  STATUS="$(awk -F'\t' -v id="$QID" '$1 == id { print $2 }' "$TMP/ids.tsv")"
  [ -n "$STATUS" ] || STATUS="NOT IN THE SPEC"

  # `git log --grep` is the coarse filter — the thing anyone can run without
  # this script, which is the point of using a trailer at all. It is a regex
  # over the message, so R1 would also match the R14 line; the exact
  # membership test happens after, on the parsed ids.
  #
  # The pattern is deliberately NOT anchored with ^. A squash merge indents
  # every line of the messages it swallows, so `--grep='^Productizer-Req:'`
  # silently misses squashed commits — measured, on `git merge --squash`. The
  # unanchored form finds them, at the cost of also matching the words in a
  # commit message that talks about the trailer.
  TZ=UTC git -C "$ROOT" log --grep="${TRAILER_KEY}:" \
    --date=format-local:'%Y-%m-%d %H:%M:%S' --format='%H' >"$TMP/grepped" 2>"$TMP/grep.err" \
    || die_usage "git log --grep failed: $(tr '\n' ' ' <"$TMP/grep.err")"
  N_GREPPED=$(awk 'END { print NR + 0 }' "$TMP/grepped")

  awk -F'\t' -v id="$QID" '$1 == id { print $2 "\t" $3 "\t" $4 }' "$TMP/pairs.tsv" >"$TMP/hits"
  N_HITS=$(awk 'END { print NR + 0 }' "$TMP/hits")

  printf '%s — %s\n' "$QID" "$STATUS"
  printf '%s commit(s) carry this id. Walked %s commit(s); %s carry a %s trailer; git log --grep matched %s.\n\n' \
    "$N_HITS" "$N_COMMITS" "$N_TRAILED" "$TRAILER_KEY" "$N_GREPPED"
  if [ "$N_HITS" -gt 0 ]; then
    awk -F'\t' -v lim="$LIMIT" 'NR <= lim { printf "  %s  %s UTC  %s\n", substr($1, 1, 12), $2, $3 }' "$TMP/hits"
    if [ "$N_HITS" -gt "$LIMIT" ]; then
      printf '  ... and %s more (raise --limit)\n' "$(( N_HITS - LIMIT ))"
    fi
    printf '\nThe same query on any machine, without this script — a regex, so it over-matches\n(%s also matches %s4, %s7...); the exact membership test above is this script'"'"'s only addition.\nNo ^ anchor: a squash merge indents the trailer and an anchored pattern misses it.\n  TZ=UTC git log --grep='"'"'%s:.*%s'"'"'\n' \
      "$QID" "$QID" "$QID" "$TRAILER_KEY" "$QID"
    exit 0
  fi
  printf 'No commit in HEAD'"'"'s history claims %s. It may be unbuilt, built without a trailer, or built on a branch not merged here.\n' "$QID" >&2
  exit 3
fi

# ===========================================================================
# --orphans
# ===========================================================================
if [ "$MODE" = orphans ]; then
  read_spec
  scan_history

  comm -23 "$TMP/active" "$TMP/traced" >"$TMP/orphans"
  comm -13 "$TMP/known"  "$TMP/traced" >"$TMP/ghosts"
  N_ORPHANS=$(awk 'END { print NR + 0 }' "$TMP/orphans")
  N_GHOSTS=$(awk 'END { print NR + 0 }' "$TMP/ghosts")
  N_TRACED=$(awk 'END { print NR + 0 }' "$TMP/traced")

  printf 'Requirement -> commit traceability, %s\n' "$ROOT"
  printf 'Spec: %s — %s active, %s superseded, %s withdrawn.\n' \
    "${SPEC#"$ROOT"/}" "$N_ACTIVE" "$N_SUPER" "$N_WITHDRAWN"
  printf 'History: walked %s commit(s) of HEAD; %s carry a %s trailer; %s distinct id(s) claimed.\n\n' \
    "$N_COMMITS" "$N_TRAILED" "$TRAILER_KEY" "$N_TRACED"

  if [ "$N_ORPHANS" -gt 0 ]; then
    printf 'ORPHANED — active, and no commit claims it (%s):\n' "$N_ORPHANS"
    awk -v lim="$LIMIT" 'NR <= lim { printf "  %s\n", $0 }' "$TMP/orphans"
    [ "$N_ORPHANS" -le "$LIMIT" ] || printf '  ... and %s more (raise --limit)\n' "$(( N_ORPHANS - LIMIT ))"
    printf '\n'
  fi
  if [ "$N_GHOSTS" -gt 0 ]; then
    printf 'CLAIMED BUT UNKNOWN — a commit cites an id the spec does not contain (%s):\n' "$N_GHOSTS"
    awk -v lim="$LIMIT" 'NR <= lim { printf "  %s\n", $0 }' "$TMP/ghosts"
    [ "$N_GHOSTS" -le "$LIMIT" ] || printf '  ... and %s more (raise --limit)\n' "$(( N_GHOSTS - LIMIT ))"
    printf '\n'
  fi

  if [ "$N_ORPHANS" -eq 0 ] && [ "$N_GHOSTS" -eq 0 ]; then
    printf 'Every active requirement is claimed by at least one commit, and every claimed id exists. Measured from the counts above.\n'
    exit 0
  fi
  exit 3
fi

# ===========================================================================
# --coverage
# ===========================================================================
if [ "$MODE" = coverage ]; then
  read_spec

  FILE_SRC=""
  if [ "$INCLUDE_IGNORED" = 1 ]; then
    FILE_SRC="find (gitignored files included)"
    ( cd "$ROOT" && find . -name .git -prune -o -type f -print0 ) >"$TMP/files.z" 2>"$TMP/find.err" \
      || undetermined "could not walk $ROOT: $(tr '\n' ' ' <"$TMP/find.err")"
  elif git -C "$ROOT" rev-parse --git-dir >"$TMP/gitdir" 2>"$TMP/git.err"; then
    FILE_SRC="git ls-files (gitignored files NOT scanned)"
    git -C "$ROOT" ls-files -z >"$TMP/files.z" 2>"$TMP/ls.err" \
      || undetermined "git ls-files failed: $(tr '\n' ' ' <"$TMP/ls.err")"
  else
    FILE_SRC="find (not a git repository)"
    ( cd "$ROOT" && find . -name .git -prune -o -type f -print0 ) >"$TMP/files.z" 2>"$TMP/find.err" \
      || undetermined "could not walk $ROOT: $(tr '\n' ' ' <"$TMP/find.err")"
  fi

  N_FILES=$(tr -dc '\0' <"$TMP/files.z" | wc -c | tr -d ' ')
  if [ "$N_FILES" -eq 0 ]; then
    undetermined "no file could be listed in $ROOT via $FILE_SRC.
Nothing was scanned, so no requirement can be shown as covered or uncovered. This is not zero uncovered."
  fi

  # xargs exits 123 when any grep in the batch found nothing, which is the
  # normal case for most batches. 124-127 are real failures.
  xrc=0
  ( cd "$ROOT" && xargs -0 grep -oIHE 'COV_R[0-9]+[A-Za-z0-9_]*' ) \
    <"$TMP/files.z" >"$TMP/cov.raw" 2>"$TMP/grep.err" || xrc=$?
  case "$xrc" in
    0 | 1 | 123) ;;
    *) undetermined "the coverage scan failed (xargs/grep exit $xrc): $(tr '\n' ' ' <"$TMP/grep.err")" ;;
  esac

  awk '
    {
      p = match($0, /COV_R[0-9]+[A-Za-z0-9_]*$/)
      if (!p) next
      tok = substr($0, p)
      file = (p >= 3 ? substr($0, 1, p - 2) : "?")
      q = match(tok, /R[0-9]+/)
      id = substr(tok, q, RLENGTH)
      print id "\t" tok "\t" file
    }
  ' "$TMP/cov.raw" | sort -u >"$TMP/cov.tsv"

  N_COV=$(awk 'END { print NR + 0 }' "$TMP/cov.tsv")
  if [ "$N_COV" -eq 0 ]; then
    undetermined "scanned $N_FILES file(s) via $FILE_SRC and found no COV_R<n> identifier.
The coverage convention is not in use in this repository, so test coverage of requirements here is UNKNOWN. Reporting '$N_ACTIVE uncovered' would state as a finding something that was never measured.
references/traceability.md has the convention."
  fi

  cut -f1 "$TMP/cov.tsv" | sort -u >"$TMP/covered"
  comm -23 "$TMP/active" "$TMP/covered" >"$TMP/uncovered"
  N_UNCOVERED=$(awk 'END { print NR + 0 }' "$TMP/uncovered")

  # A coverage id naming an id the spec never had: invented, mistyped, or
  # written against a different spec.
  awk -F'\t' 'NR == FNR { k[$1] = 1; next } !($1 in k)' "$TMP/known" "$TMP/cov.tsv" >"$TMP/dangling"
  # A coverage id naming a requirement that no longer stands. The id resolves,
  # the agreement behind it does not — drift-reverse.sh signal A, seen from the
  # test side instead of the code side.
  awk -F'\t' 'NR == FNR { k[$1] = 1; next } ($1 in k)' "$TMP/superseded" "$TMP/cov.tsv" >"$TMP/stale"
  awk -F'\t' 'NR == FNR { k[$1] = 1; next } ($1 in k)' "$TMP/withdrawn"  "$TMP/cov.tsv" >>"$TMP/stale"
  N_DANGLING=$(awk 'END { print NR + 0 }' "$TMP/dangling")
  N_STALE=$(awk 'END { print NR + 0 }' "$TMP/stale")
  N_COVERED=$(awk 'END { print NR + 0 }' "$TMP/covered")

  printf 'Requirement -> coverage traceability, %s\n' "$ROOT"
  printf 'Spec: %s — %s active, %s superseded, %s withdrawn.\n' \
    "${SPEC#"$ROOT"/}" "$N_ACTIVE" "$N_SUPER" "$N_WITHDRAWN"
  printf 'Scan: %s file(s) via %s; %s COV_ identifier(s) naming %s distinct id(s).\n\n' \
    "$N_FILES" "$FILE_SRC" "$N_COV" "$N_COVERED"

  if [ "$N_UNCOVERED" -gt 0 ]; then
    printf 'UNCOVERED — active, and no COV_ identifier names it (%s):\n' "$N_UNCOVERED"
    awk -v lim="$LIMIT" 'NR <= lim { printf "  %s\n", $0 }' "$TMP/uncovered"
    [ "$N_UNCOVERED" -le "$LIMIT" ] || printf '  ... and %s more (raise --limit)\n' "$(( N_UNCOVERED - LIMIT ))"
    printf '\n'
  fi
  if [ "$N_DANGLING" -gt 0 ]; then
    printf 'DANGLING — a COV_ identifier names an id the spec does not contain (%s):\n' "$N_DANGLING"
    awk -F'\t' -v lim="$LIMIT" 'NR <= lim { printf "  %-34s %s  (no such requirement)\n", $2, $3 }' "$TMP/dangling"
    [ "$N_DANGLING" -le "$LIMIT" ] || printf '  ... and %s more (raise --limit)\n' "$(( N_DANGLING - LIMIT ))"
    printf '\n'
  fi
  if [ "$N_STALE" -gt 0 ]; then
    printf 'STALE — a COV_ identifier names a requirement that no longer stands (%s):\n' "$N_STALE"
    awk -F'\t' -v lim="$LIMIT" 'NR <= lim { printf "  %-34s %s  (%s is superseded or withdrawn)\n", $2, $3, $1 }' "$TMP/stale"
    [ "$N_STALE" -le "$LIMIT" ] || printf '  ... and %s more (raise --limit)\n' "$(( N_STALE - LIMIT ))"
    printf '\n'
  fi

  if [ "$N_UNCOVERED" -eq 0 ] && [ "$N_DANGLING" -eq 0 ] && [ "$N_STALE" -eq 0 ]; then
    printf 'Every active requirement is named by at least one COV_ identifier, and every COV_ identifier names a standing requirement. Measured from the counts above.\n'
    exit 0
  fi
  exit 3
fi

die_usage "unreachable: mode '$MODE' has no implementation"
