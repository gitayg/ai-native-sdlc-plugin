#!/usr/bin/env bash
# stage-snapshot.sh <snapshot|delta|list> [repo-root] --stage N --artifact PATH [--run LABEL]
#
# Score the draft the stage produced, then score what the human changed - as two
# separate numbers.
#
# Every artifact in this lifecycle is edited by a human before anyone looks at
# it. Measuring the file that survives that measures the writer-plus-agent
# workflow and reports it as the agent's output. The contamination runs one way
# and always flatters: a bad draft rescued by a careful edit scores as a good
# draft.
#
# So the draft is captured the moment the stage produces it, before a human
# opens it, and locked. The snapshot is what gets scored. The human delta -
# what changed between the snapshot and the artifact as it stands now - is the
# second measurement, and it is the one that says what the process contributed.
# A stage whose output is rewritten wholesale contributed less than its final
# artifact suggests, and only the delta shows that.
#
# WHAT THE DELTA IS, AND WHAT IT IS NOT
#
# It is a line count: lines a human added, lines a human removed, and those two
# as a percentage of the snapshot's line count. That is a PROXY for editorial
# effort, not a measure of quality. A one-line correction of a wrong number and
# a one-line typo fix are the same delta, and a reformat that rewrites every
# line is a 100% delta that changed nothing. Read it as volume of human
# intervention over time, per stage, and never as a score.
#
# IMMUTABILITY
#
# A snapshot is written once. `snapshot` refuses to overwrite an existing one,
# and the files it writes are made read-only. A snapshot that can be refreshed
# after the human edit is not a snapshot; it is the artifact again, and the
# delta silently collapses to zero. Use --run to take a second, separately named
# snapshot rather than replacing the first.
#
# HOUSE RULE: a value that could not be measured is never rendered as zero. No
# snapshot, an artifact that has since been deleted, and a stage that produced
# nothing at all are three different answers - and none of them is "the human
# changed nothing", which is what a zero delta means.
#
# Snapshots live in `.claude/productizer/snapshots/stage-<N>/`, two files each:
#   <slug>.snap   the draft, byte for byte, read-only
#   <slug>.meta   stage, artifact, run, state, bytes, lines, sha256
#
# Exit: 0 snapshot written, or delta measured
#       1 a snapshot already exists - refusing to overwrite it
#       2 usage
#       3 no such directory
#       5 no snapshot for this stage and artifact - nothing to compare against
#       6 the artifact is gone, though a snapshot of it exists
#       7 the snapshot records that the stage produced nothing - no delta exists
#       8 the stage produced nothing; that fact was recorded (`snapshot` only)
set -euo pipefail
export LC_ALL=C

MODE=""
ROOT=""
STAGE=""
ARTIFACT=""
RUN=""
while [ $# -gt 0 ]; do
  case "$1" in
    snapshot|delta|list) [ -z "$MODE" ] || { echo "stage-snapshot: only one mode" >&2; exit 2; }; MODE="$1"; shift ;;
    --stage)      STAGE="${2:-}"; [ -n "$STAGE" ] || { echo "stage-snapshot: --stage needs a number" >&2; exit 2; }; shift 2 ;;
    --stage=*)    STAGE="${1#--stage=}"; shift ;;
    --artifact)   ARTIFACT="${2:-}"; [ -n "$ARTIFACT" ] || { echo "stage-snapshot: --artifact needs a path" >&2; exit 2; }; shift 2 ;;
    --artifact=*) ARTIFACT="${1#--artifact=}"; shift ;;
    --run)        RUN="${2:-}"; [ -n "$RUN" ] || { echo "stage-snapshot: --run needs a label" >&2; exit 2; }; shift 2 ;;
    --run=*)      RUN="${1#--run=}"; shift ;;
    -h|--help)    echo "usage: stage-snapshot.sh <snapshot|delta|list> [repo-root] --stage N --artifact PATH [--run LABEL]"; exit 0 ;;
    -*)           echo "stage-snapshot: unknown option: $1" >&2; exit 2 ;;
    *)            [ -z "$ROOT" ] || { echo "stage-snapshot: only one repo-root" >&2; exit 2; }; ROOT="$1"; shift ;;
  esac
done
[ -n "$MODE" ] || { echo "usage: stage-snapshot.sh <snapshot|delta|list> [repo-root] --stage N --artifact PATH" >&2; exit 2; }
[ -n "$ROOT" ] || ROOT="."
cd "$ROOT" || { echo "stage-snapshot: no such directory: $ROOT" >&2; exit 3; }

SNAPROOT=".claude/productizer/snapshots"

if [ "$MODE" != "list" ]; then
  [ -n "$STAGE" ]    || { echo "stage-snapshot: --stage is required" >&2; exit 2; }
  [ -n "$ARTIFACT" ] || { echo "stage-snapshot: --artifact is required" >&2; exit 2; }
  case "$STAGE" in ''|*[!0-9]*) echo "stage-snapshot: --stage must be a whole number, not: $STAGE" >&2; exit 2 ;; esac
  case "$RUN" in *[!A-Za-z0-9._-]*) echo "stage-snapshot: --run may hold only letters, digits, dot, dash and underscore" >&2; exit 2 ;; esac
fi

# The artifact path becomes the file name, so it has to survive the trip. Every
# character that is not a plain name character becomes an underscore; the
# original path is kept verbatim in the meta, which is what anyone reads.
slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

digest() {
  if command -v shasum >/dev/null; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    printf 'unavailable\n'
  fi
}

# Truncation that survives a short value: `unavailable` is 11 characters, and a
# prefix-strip trick would render it as the empty string - a missing digest shown
# as nothing at all.
short() { if [ "${#1}" -gt 12 ]; then printf '%s' "${1:0:12}"; else printf '%s' "$1"; fi; }

metaget() { # metaget <meta-file> <key>
  awk -F'=' -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$1"
}

# ---------------------------------------------------------------- list -------
if [ "$MODE" = "list" ]; then
  if [ ! -d "$SNAPROOT" ]; then
    echo "stage-snapshot: no snapshots under $SNAPROOT" >&2
    echo "  outcome: none-taken. Nothing has been captured, which is not the same as nothing having changed." >&2
    exit 5
  fi
  printf '%-9s %-17s %-14s %s\n' "stage" "state" "run" "artifact"
  find "$SNAPROOT" -type f -name '*.meta' | sort | while read -r m; do
    printf '%-9s %-17s %-14s %s\n' \
      "$(metaget "$m" stage)" "$(metaget "$m" state)" \
      "$(metaget "$m" run)" "$(metaget "$m" artifact)"
  done
  exit 0
fi

DIR="$SNAPROOT/stage-$STAGE"
BASE="$(slug "$ARTIFACT")"
[ -z "$RUN" ] || BASE="$BASE--$RUN"
META="$DIR/$BASE.meta"
SNAP="$DIR/$BASE.snap"

# ------------------------------------------------------------ snapshot -------
if [ "$MODE" = "snapshot" ]; then
  if [ -e "$META" ]; then
    echo "stage-snapshot: a snapshot already exists at $META" >&2
    echo "  Refusing to overwrite it. A snapshot taken after a human edit measures nothing:" >&2
    echo "  the delta against it collapses to zero and reads as 'the human changed nothing'." >&2
    echo "  Use --run <label> to take a second, separately named snapshot." >&2
    exit 1
  fi
  mkdir -p "$DIR"

  # "Produced nothing" covers absent, empty, and whitespace-only. All three are
  # a stage that did not deliver, and recording a zero-byte snapshot for them
  # would later measure as a zero delta - a stage that produced nothing and a
  # stage a human left untouched would print the same number.
  content=0
  if [ -f "$ARTIFACT" ]; then
    if [ -n "$(tr -d ' \t\n' < "$ARTIFACT")" ]; then content=1; fi
  fi

  if [ "$content" -eq 0 ]; then
    if [ -f "$ARTIFACT" ]; then why="present but empty"; else why="absent"; fi
    {
      echo "stage=$STAGE"
      echo "artifact=$ARTIFACT"
      echo "run=${RUN:--}"
      echo "state=produced-nothing"
      echo "why=$why"
      echo "bytes=unmeasured"
      echo "lines=unmeasured"
      echo "sha256=unmeasured"
    } > "$META"
    chmod 444 "$META"
    echo "stage-snapshot: stage $STAGE produced nothing for $ARTIFACT ($why)."
    echo "  Recorded as state=produced-nothing in $META."
    echo "  This is not a snapshot of an empty draft and it will not yield a delta of zero."
    exit 8
  fi

  cp "$ARTIFACT" "$SNAP"
  bytes="$(wc -c < "$SNAP" | tr -d ' ')"
  lines="$(wc -l < "$SNAP" | tr -d ' ')"
  sha="$(digest "$SNAP")"
  {
    echo "stage=$STAGE"
    echo "artifact=$ARTIFACT"
    echo "run=${RUN:--}"
    echo "state=captured"
    echo "why=-"
    echo "bytes=$bytes"
    echo "lines=$lines"
    echo "sha256=$sha"
  } > "$META"
  # Read-only, so immutability is a property of the file and not of a promise
  # made in a comment.
  chmod 444 "$SNAP" "$META"
  echo "stage-snapshot: captured stage $STAGE draft of $ARTIFACT"
  echo "  snapshot $SNAP ($bytes bytes, $lines lines, sha256 $sha)"
  echo "  meta     $META"
  echo "  Both are read-only. Score this, not the artifact."
  exit 0
fi

# --------------------------------------------------------------- delta -------
if [ ! -f "$META" ]; then
  echo "stage-snapshot: no snapshot for stage $STAGE artifact $ARTIFACT" >&2
  echo "  Looked for $META" >&2
  echo "  outcome: no-snapshot. There is nothing to compare against, and that is not a delta of zero." >&2
  exit 5
fi

STATE="$(metaget "$META" state)"
SNAP_LINES="$(metaget "$META" lines)"
SNAP_BYTES="$(metaget "$META" bytes)"
SNAP_SHA="$(metaget "$META" sha256)"

echo "human delta - stage $STAGE"
echo "  artifact  $ARTIFACT"
echo "  snapshot  $META"

if [ "$STATE" = "produced-nothing" ]; then
  echo "  state     produced-nothing ($(metaget "$META" why))"
  echo "  delta     unmeasurable"
  echo
  echo "stage-snapshot: stage $STAGE produced nothing, so there is no draft for a human to have edited." >&2
  echo "  outcome: stage-produced-nothing. Not a delta of zero - a zero would say the draft was accepted as written." >&2
  exit 7
fi

if [ ! -f "$ARTIFACT" ]; then
  echo "  state     artifact-missing"
  echo "  delta     unmeasurable"
  echo
  echo "stage-snapshot: the snapshot exists but $ARTIFACT does not." >&2
  echo "  outcome: artifact-missing. The draft was captured and the file is now gone - deleted, moved or renamed." >&2
  exit 6
fi

# diff exits 1 for "files differ", which is the ordinary case here, and 2 for a
# real failure. Distinguished, not swallowed; diff's own stderr is left alone.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
rc=0
diff "$SNAP" "$ARTIFACT" > "$TMP" || rc=$?
if [ "$rc" -gt 1 ]; then
  echo "stage-snapshot: diff failed (exit $rc) comparing $SNAP with $ARTIFACT" >&2
  exit 3
fi

REMOVED="$(awk '/^< /' "$TMP" | wc -l | tr -d ' ')"
ADDED="$(awk '/^> /' "$TMP" | wc -l | tr -d ' ')"
NOW_BYTES="$(wc -c < "$ARTIFACT" | tr -d ' ')"
NOW_LINES="$(wc -l < "$ARTIFACT" | tr -d ' ')"
NOW_SHA="$(digest "$ARTIFACT")"

TOUCHED=$(( ADDED + REMOVED ))
if [ "$SNAP_LINES" -gt 0 ]; then
  PCT="$(( TOUCHED * 100 / SNAP_LINES ))%"
else
  PCT="unmeasurable"
fi

echo "  state     captured"
echo
printf '%-22s %-14s %s\n' "" "snapshot" "artifact now"
printf '%-22s %-14s %s\n' "bytes" "$SNAP_BYTES" "$NOW_BYTES"
printf '%-22s %-14s %s\n' "lines" "$SNAP_LINES" "$NOW_LINES"
printf '%-22s %-14s %s\n' "sha256" "$(short "$SNAP_SHA")" "$(short "$NOW_SHA")"
echo
printf '%-22s %s\n' "human lines added" "$ADDED"
printf '%-22s %s\n' "human lines removed" "$REMOVED"
printf '%-22s %s\n' "human delta" "$PCT of the snapshot's $SNAP_LINES lines"
echo
echo "A proxy for editorial effort, not a quality score. A reformat reads as a large"
echo "delta and a corrected figure reads as a small one."
