#!/bin/bash
# Productizer SessionStart hook — announce lifecycle state when a session opens in a bound repo.
#
# Registered against the SessionStart event, which fires "when a session begins or resumes". The
# session never waits on anything it does not have to: an unbound repo exits before reading a byte
# of the spec, and the only network call is bounded and cached.
#
# Contract this relies on, from the hooks reference:
#   - stdout, exit 0: "The exceptions are UserPromptSubmit, UserPromptExpansion, and SessionStart,
#     where Claude Code adds plain-text stdout as context that Claude can see and act on." JSON on
#     stdout is parsed instead, so this hook returns JSON and fills both channels explicitly.
#   - additionalContext: "Text added to Claude's context." systemMessage: "To surface a message to
#     the user on any platform, return systemMessage in JSON output." One reaches the model, the
#     other reaches the human; the announcement has to do both, so it sets both.
#   - "Handlers run in the current directory with Claude Code's environment", and hook commands are
#     spawned with CLAUDE_PROJECT_DIR exported, which is preferred here over the current directory
#     because a session started in a subdirectory would otherwise miss the binding.
#   - SessionStart cannot block: exit 2 "renders in the transcript as a <hook name> hook error".
#     Every path below exits 0 so a broken spec never decorates a session with an error notice.
set -u

# Silence is the failure mode. Anything this script writes to stderr surfaces in the transcript as a
# hook error, which is a worse outcome than not announcing the state at all.
exec 2>/dev/null  # stderr-ok: a SessionStart hook that writes to stderr surfaces in the transcript as a hook error, which is a worse outcome than not announcing the state at all - see the note directly above

emit_nothing() { exit 0; }

# Draining stdin matters even though little of it is used: leaving the pipe unread risks the writer
# taking a SIGPIPE. Guarded on -t 0 so running the script by hand in a terminal does not hang.
HOOK_STDIN=""
[ -t 0 ] || HOOK_STDIN=$(head -c 65536)

ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$ROOT" ]; then
  # Fall back to the cwd field of the hook payload, then to the process's own directory. The payload
  # comes from Claude Code rather than from the repo, but it is still parsed defensively: only a
  # value that resolves to an existing directory is used.
  ROOT=$(printf '%s' "$HOOK_STDIN" | tr '\n' ' ' \
         | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
fi
[ -n "$ROOT" ] && [ -d "$ROOT" ] || ROOT="$PWD"
cd "$ROOT" || emit_nothing

# Most repos are not bound and must pay nothing. This test is the gate: nothing below it runs — no
# spec read, no awk, no lookup for gh — until the repo has declared itself bound.
BINDING=".claude/productizer/config.json"
SPEC=".claude/productizer/spec.md"
[ -f "$BINDING" ] || emit_nothing

# Everything read below is attacker-authorable: a binding, a spec and issue titles all arrive with a
# clone, from anyone who can open a pull request. The hook therefore counts and never quotes. No
# requirement text, no concern description and no issue title is echoed — those are the fields that
# could carry "ignore your instructions" into the model's context on the first turn of every session,
# before any human has read a line. The only free text that survives to the output is the product
# name, stripped to a conservative character set and truncated, because a name is what makes the
# announcement legible and a 40-character alphanumeric string cannot carry a sentence.
PRODUCT=$(head -c 65536 "$BINDING" | tr '\n' ' ' \
          | grep -oE '"product"[^{]*\{[^}]*"name"[[:space:]]*:[[:space:]]*"[^"]*"' \
          | head -1 | sed 's/.*"\([^"]*\)"$/\1/' \
          | tr -cd 'A-Za-z0-9._ -' | cut -c1-40 | sed 's/^ *//; s/ *$//')

# No parseable product name means the binding is malformed or is not a Productizer binding. Announcing
# state read out of a file this hook does not understand is how a wrong number gets trusted, so stop.
[ -n "$PRODUCT" ] || emit_nothing
# -r, not -f: a spec that exists but cannot be read must not be reported as a spec with no
# requirements. A wrong number stated as a fact is worse than no announcement.
[ -r "$SPEC" ] || emit_nothing

# One awk pass over the spec, bounded, producing four numbers and a short list of concern ids.
#
#   range        lowest and highest requirement id, from the "- **R<n>**" bullet form only
#   superseded   the status marker on its own line, not the word appearing in prose or in the
#                requirement index, which would double-count every superseded requirement
#   concerns     rows of the Areas of concern table whose status column says open. A status
#                mentioning "resolved" is never open, which also discards the template's own
#                "open / resolved:" placeholder row instead of reporting a phantom contradiction.
read -r RMIN RMAX SUPERSEDED CONCERNS CIDS <<AWK
$(head -c 2000000 "$SPEC" | awk '
  /^[[:space:]]*##[[:space:]]/ { in_concerns = ($0 ~ /Areas of concern/) ? 1 : 0 }
  {
    if (match($0, /^- \*\*R[0-9]+\*\*/)) {
      id = substr($0, 6, RLENGTH - 7) + 0
      if (rmin == 0 || id < rmin) rmin = id
      if (id > rmax) rmax = id
    }
    if ($0 ~ /^[[:space:]]*Superseded by R[0-9]+/) sup++
    if (in_concerns && $0 ~ /^[[:space:]]*\|[[:space:]]*C[0-9]+[[:space:]]*\|/) {
      n = split($0, f, "|")
      status = ""
      for (i = n; i > 1; i--) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[i]); if (f[i] != "") { status = f[i]; break } }
      if (status !~ /resolved/ && status ~ /open/) {
        con++
        if (match($0, /C[0-9]+/) && con <= 5) ids = ids (ids == "" ? "" : ",") substr($0, RSTART, RLENGTH)
      }
    }
  }
  END { printf "%d %d %d %d %s\n", rmin, rmax, sup, con, (ids == "" ? "-" : ids) }
')
AWK
case "${RMIN:-}${RMAX:-}${SUPERSEDED:-}${CONCERNS:-}" in
  ''|*[!0-9]*) emit_nothing ;;
esac

# The spec's Areas of concern table is one source for "what is waiting on a person". The ruling
# files are the other, and rulings.md makes this hook a named consumer of that second contract.
# They are counted separately and on purpose: a concern row with no ruling file behind it is a
# contradiction that halted without ever asking, which is the failure this whole path exists to
# prevent. Reconciling them here would hide it - the disagreement is the signal, and
# check-ruling-requested.sh is what fails on it. This hook only has to avoid claiming the
# healthy answer when it does not know.
#
# Never a bare count from a glob: an unmatched glob arrives as a literal path, and an unreadable
# directory and an empty one are not the same fact. No directory means never raised; unreadable
# means unknown; and unknown is reported as unknown, never as zero, for the same reason the intent
# count below is - a zero reads as "nothing is waiting" and is the one wrong answer that looks
# like a healthy one.
RULINGS_DIR=".claude/productizer/rulings"
PENDING=""          # "" = unknown, "0" = genuinely none, "N" = that many
PIDS="-"
if [ ! -e "$RULINGS_DIR" ]; then
  PENDING=0
elif [ -d "$RULINGS_DIR" ] && [ -r "$RULINGS_DIR" ] && [ -x "$RULINGS_DIR" ]; then
  # -l -x -F, never a substring match: "Status: pending" appears in the template's own prose and
  # in any ruling that discusses being pending, and an unanchored match reports questions that do
  # not exist. Ids only, never a line of the file - a ruling quotes an incoming intent, which is
  # text a stranger can write, and this string lands in the model's context before a human has
  # read a word of it.
  PFILES=$(find "$RULINGS_DIR" -maxdepth 1 -type f -name 'D*.md' -exec grep -lxF 'Status: pending' {} +) || PFILES=""
  if [ -z "$PFILES" ]; then
    PENDING=0
  else
    PENDING=$(printf '%s\n' "$PFILES" | grep -c .)
    PIDS=$(printf '%s\n' "$PFILES" | sed -n 's#^.*/\(D[0-9][0-9]*\)[-.].*#\1#p' \
             | sort -t D -k2 -n | head -5 | paste -sd, -)
    [ -n "$PIDS" ] || PIDS="-"
  fi
fi
case "$PENDING" in
  ''|*[!0-9]*) PENDING="" ;;
esac

# Open intents live in the tracker, not in the tree: the shipped binding sets intent.persist false,
# so there is no committed file to count and a folder scan would report a different quantity from the
# one the fleet view calls open intents. That justifies the one network call — and bounds it:
#
#   - served from a cache with a 15 minute TTL, so the common case is a stat and a read;
#   - killed after 1.5s by a watchdog, because a hung gh must not hold the session open;
#   - skipped entirely when SDLC_HOOK_NO_NETWORK is set, or when gh is not installed;
#   - not retried for 5 minutes after it fails, recorded as the marker `x`. Without that, an
#     unauthenticated gh costs every session in the repo the full 1.5s watchdog wait, for ever;
#   - reported as unknown, never as zero, when it cannot be read. A zero here would read as "nothing
#     in flight" and is the one wrong answer that looks like a healthy one.
CACHE=".claude/productizer/.session-start-intents"
INTENTS=""
TRY_NETWORK=1
if [ -f "$CACHE" ]; then
  CACHED=$(head -c 128 "$CACHE")
  CTIME=${CACHED%% *}
  CCOUNT=${CACHED##* }
  case "$CTIME" in
    ''|*[!0-9]*) CTIME=0 ;;
  esac
  AGE=$(( $(date +%s) - CTIME ))
  case "$CCOUNT" in
    x) [ "$CTIME" -gt 0 ] && [ "$AGE" -lt 300 ] && TRY_NETWORK=0 ;;
    ''|*[!0-9]*) ;;
    *) [ "$CTIME" -gt 0 ] && [ "$AGE" -lt 900 ] && INTENTS="$CCOUNT" ;;
  esac
fi
if [ -z "$INTENTS" ] && [ "$TRY_NETWORK" -eq 1 ] && [ -z "${SDLC_HOOK_NO_NETWORK:-}" ] && command -v gh >/dev/null 2>&1; then
  TMP=$(mktemp) || TMP=""
  if [ -n "$TMP" ]; then
    gh issue list --label sdlc:intent --state open --limit 100 --json number --jq length >"$TMP" &
    GH_PID=$!
    ( sleep 1.5; kill -9 "$GH_PID" ) >/dev/null &
    WD_PID=$!
    wait "$GH_PID"
    kill "$WD_PID" >/dev/null
    FETCHED=$(head -c 32 "$TMP" | tr -d '[:space:]')
    rm -f "$TMP"
    case "$FETCHED" in
      ''|*[!0-9]*) printf '%s x\n' "$(date +%s)" >"$CACHE" ;;
      *) INTENTS="$FETCHED"; printf '%s %s\n' "$(date +%s)" "$FETCHED" >"$CACHE" ;;
    esac
  fi
fi

case "$INTENTS" in
  "")  INTENT_TEXT="open intents unknown" ;;
  0)   INTENT_TEXT="no open intents" ;;
  1)   INTENT_TEXT="1 open intent" ;;
  *)   INTENT_TEXT="$INTENTS open intents" ;;
esac

if [ "$RMAX" -eq 0 ]; then
  SPEC_TEXT="spec has no requirements yet"
else
  SPEC_TEXT="spec R${RMIN}–R${RMAX}"
  [ "$SUPERSEDED" -gt 0 ] && SPEC_TEXT="$SPEC_TEXT, $SUPERSEDED superseded"
fi

LINE="$PRODUCT · $INTENT_TEXT"
LINE2=""
if [ "$CONCERNS" -gt 0 ]; then
  if [ "$CONCERNS" -eq 1 ]; then
    LINE="$LINE · 1 CONTRADICTION waiting on your ruling"
  else
    LINE="$LINE · $CONCERNS CONTRADICTIONS waiting on your ruling"
  fi
  case "$CIDS" in
    ''|-|*[!C0-9,]*) LINE2="Nothing merges into the spec until it is ruled on." ;;
    *) LINE2="Open in Areas of concern: $CIDS. Nothing merges into the spec until it is ruled on." ;;
  esac
fi

# A concern that never became a ruling file is a halt nobody was asked to answer.
if [ -z "$PENDING" ]; then
  LINE="$LINE · rulings unreadable, pending count unknown"
elif [ "$PENDING" -gt 0 ]; then
  case "$PIDS" in
    -|*[!D0-9,]*) LINE="$LINE · $PENDING drafted" ;;
    *) LINE="$LINE · $PENDING drafted: $PIDS" ;;
  esac
elif [ "$CONCERNS" -gt 0 ]; then
  LINE="$LINE · NO RULING DRAFTED - nobody has been asked"
fi
LINE="$LINE · $SPEC_TEXT"

# Both fields carry the same sentence: additionalContext is what the model reads, systemMessage is
# what the human sees. Neither is escaped, and neither needs to be — every character that reaches
# here is either fixed text or came through the sanitiser above, so no quote or backslash exists to
# break the string literal and inject a second JSON field.
MSG="$LINE"
[ -n "$LINE2" ] && MSG="$LINE\\n$LINE2"
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
  "$MSG" "$MSG"
exit 0
