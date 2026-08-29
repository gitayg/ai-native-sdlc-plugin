#!/usr/bin/env bash
# .git/hooks/prepare-commit-msg — writes the requirement trailer into the
#                                 message before you are asked to approve it.
#
# Install it (it is a git hook, not a Claude Code hook — it takes no JSON on
# stdin and it is registered by living at a path, not by settings.json):
#
#     cp templates/prepare-commit-msg.sh .git/hooks/prepare-commit-msg
#     chmod +x .git/hooks/prepare-commit-msg
#
# It adds this, and nothing else, to the commit message:
#
#     Productizer-Req: R14,R22
#
# WHERE THE IDS COME FROM, IN ORDER.
#
#   1. $PRODUCTIZER_REQ in the environment. Explicit, and it wins:
#
#          PRODUCTIZER_REQ=R14,R22 git commit -m "halt on contradiction"
#
#   2. The current branch name. `feat/R14-halt-on-contradiction` yields R14;
#      `R14-R22-intake` yields both. An `R<n>` run is only read when it stands
#      on its own — `PR2`, `CORS`, `v2R` are not ids and are not taken as ids.
#
#   3. Nothing. The hook says so on stderr once and gets out of the way.
#
# WHY THIS DOES NOT BLOCK YOUR COMMIT.
#
#   A prepare-commit-msg hook that exits non-zero aborts the commit. This one
#   exits 0 on every path but one, because a missing trailer is a gap in a
#   record, not an unsafe act — and a hook that stops you committing because it
#   could not guess an id from a branch name gets deleted within a day, which
#   costs the record everything.
#
#   The one exception: ids you stated YOURSELF in $PRODUCTIZER_REQ that the
#   spec does not contain. That is not a failed guess, it is a false provenance
#   record being written on purpose, and it stops the commit. Ids merely
#   inferred from a branch name never stop anything; they are dropped with a
#   note.
#
#   The real enforcement lives where it can see the whole change:
#   `req-trailer.sh --validate` in a pre-push hook or in CI, and
#   `req-trailer.sh --orphans` on the spec.
#
# ---------------------------------------------------------------------------
# THE FAILURE THIS HOOK CANNOT FIX: `git commit --amend -m`
#
#   Measured, not assumed (git 2.50.1):
#
#     git commit -m "..."          -> hook gets ($1=file, $2=message)
#     git commit --amend -m "..."  -> hook gets ($1=file, $2=message)
#     git commit --amend           -> hook gets ($1=file, $2=commit, $3=HEAD)
#
#   `--amend -m` replaces the message wholesale, and it is INDISTINGUISHABLE
#   from an ordinary `-m` in the arguments the hook is handed. So the hook
#   cannot recover the old trailer from HEAD: on a plain `-m` that same code
#   would copy the parent commit's ids onto an unrelated change, which is a
#   worse failure than a missing trailer — a provenance record that is
#   confidently wrong.
#
#   The trailer is therefore LOST by `git commit --amend -m`, unless the ids
#   are recoverable from the branch name or from $PRODUCTIZER_REQ, in which
#   case this hook puts them straight back. `git commit --amend` WITHOUT `-m`
#   is safe: git seeds the editor with the old message, trailer included.
#
#   KNOWN_LIMITATIONS.md carries this with the reproduction.
# ---------------------------------------------------------------------------
set -euo pipefail

MSG_FILE="${1:-}"
MSG_SOURCE="${2:-}"
TRAILER_KEY="Productizer-Req"

note() { printf 'prepare-commit-msg: %s\n' "$1" >&2; }

[ -n "$MSG_FILE" ] || { note "called with no message file; nothing to do."; exit 0; }
[ -f "$MSG_FILE" ] || { note "no such message file: $MSG_FILE"; exit 0; }

# A merge or squash message is git's own summary of other people's commits.
# Stamping one requirement id across it claims something nobody asserted.
case "$MSG_SOURCE" in
  merge | squash) exit 0 ;;
esac

# Already trailed — an editor amend, a rebase replaying a message, a second
# run of this hook. Nothing to add, and nothing to say about it.
if awk '
      { line = $0; sub(/^[ \t]+/, "", line) }
      tolower(substr(line, 1, 16)) == "productizer-req:" { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$MSG_FILE"; then
  exit 0
fi

# --- find req-trailer.sh ----------------------------------------------------
# The skill lives outside the repository, so there is no single right path.
# Set $PRODUCTIZER_REQ_TRAILER to skip the search.
TOPLEVEL=""
if ! TOPLEVEL="$(git rev-parse --show-toplevel)"; then
  note "not inside a git work tree; leaving the message alone."
  exit 0
fi

REQ_TRAILER=""
for cand in \
  "${PRODUCTIZER_REQ_TRAILER:-}" \
  "$(dirname "$0")/req-trailer.sh" \
  "$TOPLEVEL/.claude/productizer/bin/req-trailer.sh" \
  "$TOPLEVEL/scripts/req-trailer.sh"
do
  [ -n "$cand" ] || continue
  if [ -x "$cand" ]; then REQ_TRAILER="$cand"; break; fi
done
if [ -z "$REQ_TRAILER" ] && command -v req-trailer.sh >/dev/null; then
  REQ_TRAILER="$(command -v req-trailer.sh)"
fi
if [ -z "$REQ_TRAILER" ]; then
  note "cannot find req-trailer.sh. Set PRODUCTIZER_REQ_TRAILER to its path, or copy it to .claude/productizer/bin/. No trailer was added."
  exit 0
fi

# --- where the ids come from ------------------------------------------------
IDS=""
SOURCE_OF_IDS=""
EXPLICIT=0

if [ -n "${PRODUCTIZER_REQ:-}" ]; then
  IDS="$PRODUCTIZER_REQ"
  SOURCE_OF_IDS="\$PRODUCTIZER_REQ"
  EXPLICIT=1
else
  BRANCH=""
  if BRANCH="$(git symbolic-ref --quiet --short HEAD)" && [ -n "$BRANCH" ]; then
    # An R<n> run is an id only when it stands alone: bounded by the start of
    # the string, the end, or a character that is not a letter or a digit.
    # Without that boundary `PR2` and `CORS` become requirement citations.
    #
    # st/ln are saved before the inner match(), which overwrites RSTART and
    # RLENGTH. Advancing on the inner values instead re-matched the same id
    # three times on `feat/R1-hold-one-spec`.
    IDS="$(printf '%s' "$BRANCH" | awk '
      {
        s = $0
        while (match(s, /(^|[^A-Za-z0-9])R[0-9]+([^A-Za-z0-9]|$)/)) {
          st = RSTART; ln = RLENGTH
          seg = substr(s, st, ln)
          if (match(seg, /R[0-9]+/)) printf "%s ", substr(seg, RSTART, RLENGTH)
          s = substr(s, st + ln - 1)
        }
      }')"
    SOURCE_OF_IDS="branch '$BRANCH'"
  fi
fi

IDS="$(printf '%s' "$IDS" | tr ',;' '  ' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')"

if [ -z "$IDS" ]; then
  note "no requirement id found in \$PRODUCTIZER_REQ or the branch name, so this commit will carry no ${TRAILER_KEY} trailer. Name it with: PRODUCTIZER_REQ=R14 git commit ..."
  exit 0
fi

# --- write it ---------------------------------------------------------------
# req-trailer.sh --add validates against the living spec, merges rather than
# appends, and leaves the file byte-identical when there is nothing to change.
add_err=0
"$REQ_TRAILER" --add "$IDS" --file "$MSG_FILE" >/dev/null || add_err=$?

if [ "$add_err" -eq 0 ]; then
  note "${TRAILER_KEY}: $(printf '%s' "$IDS" | tr ' ' ',')  (from ${SOURCE_OF_IDS})"
  exit 0
fi

if [ "$EXPLICIT" = 1 ]; then
  note "you named ${IDS} in \$PRODUCTIZER_REQ and req-trailer.sh rejected it (exit ${add_err}); the reason is above. Aborting the commit rather than recording provenance that does not resolve."
  exit 1
fi

note "the ids inferred from ${SOURCE_OF_IDS} (${IDS}) were rejected by req-trailer.sh (exit ${add_err}); the reason is above. A guess from a branch name never blocks a commit, so this one is committing without a ${TRAILER_KEY} trailer."
exit 0
