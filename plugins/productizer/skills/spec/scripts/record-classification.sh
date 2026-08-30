#!/usr/bin/env bash
# record-classification.sh [--version] [--help] --intent ID --classification VALUE
#                          [--root DIR] [--spec-path PATH] [--store DIR]
#
# Writes the provenance record for one intake classification: the spec commit
# and content hash it was made against, every active requirement id that was in
# scope, the intent's identifier, and the single classification value.
#
# WHY A RECORD AT ALL. Two acceptance rows share this one mechanism.
#
#   R6  When an intent arrives, the lifecycle shall classify it against the
#       WHOLE living spec as exactly one of extend, refine, duplicate or
#       contradict.
#
#       A graded eval scored 16/16 on outcomes, which is equally consistent
#       with a classifier that saw half the spec and got lucky on a small one.
#       Outcomes cannot tell those apart; the ids that were in front of it can.
#
#   R19 If the spec home is unreachable, then the lifecycle shall stop rather
#       than classify against a remembered copy.
#
#       Made mechanical here rather than written as a rule: an unreachable spec
#       home yields no hash, this script refuses to emit a record without one,
#       and the check refuses a record that has none. Classifying from a
#       remembered copy stops being forbidden and starts being impossible to
#       RECORD, which is the only half a script can enforce.
#
# THE REFUSAL PATH IS THE POINT. Every reason the spec home might not be
# readable ends the same way - exit 2, nothing written, no partial file:
#
#   the spec file is missing, or cannot be read
#   the work tree is not a git repository, so there is no commit to cite
#   the spec is not tracked at HEAD, so `git show` has nothing to hash
#   the spec in the work tree differs from the spec at HEAD
#
# THE LAST ONE DESERVES ITS SENTENCE. A record cites a commit, and the check
# rehashes the spec AT that commit. A classification made against uncommitted
# edits could never be verified against anything, so the record would be
# unfalsifiable - which is the same as no record. Commit the spec, then
# classify against it.
#
# The record is built in a temporary directory and moved into place in one
# step, so an interrupted run leaves the store exactly as it found it.
#
# EXACTLY ONE CLASSIFICATION PER INTENT is enforced at the filename: the record
# is named for the intent, so a second classification of the same intent is a
# collision this script refuses rather than a second file nobody notices.
#
# THE INTENT'S ID, NEVER ITS WORDS. An intent is text a stranger can write - on
# a public repo anyone can open an issue - and this store is committed and read
# back into a model's context. The identifier is checked against a closed shape
# before it is written, and nothing else from the intent is recorded here.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no `date -d`, no in-place sed. Nothing suppresses stderr - an
# error and a genuine no-match look identical once it is discarded, and this
# script's whole job is telling those two apart.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  the record was written; its path is the last line of stdout
#   1  refused - a record for this intent already exists. The store already
#      holds exactly one classification for it, and that is the invariant
#      holding, not a crash.
#   2  could not run - bad usage, or NO HASH: an unreachable spec home, an
#      untracked spec, a work tree that disagrees with HEAD. Never a record
#      with a blank or placeholder hash.
set -euo pipefail

# Byte-identical output across runs and machines: collation, number formatting
# and case folding all follow the locale otherwise.
export LC_ALL=C

VERSION="record-classification 1.0"

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/classification-record.py"

ROOT=""
SPEC_REL=".claude/productizer/spec.md"
STORE_REL=".claude/productizer/classifications"
INTENT=""
CLASSIFICATION=""

usage() {
  printf 'usage: record-classification.sh --intent ID --classification VALUE\n'
  printf '                                [--root DIR] [--spec-path PATH] [--store DIR]\n'
  printf '  --intent ID          the tracker key or identifier of the intent (#123, PROJ-123)\n'
  printf '  --classification V   exactly one of extend, refine, duplicate, contradict\n'
  printf '  --root DIR           the repo work tree. Defaults to the git top level,\n'
  printf '                       never to the working directory.\n'
  printf '  --spec-path PATH     spec location relative to the root\n'
  printf '                       (default .claude/productizer/spec.md)\n'
  printf '  --store DIR          record store relative to the root\n'
  printf '                       (default .claude/productizer/classifications)\n'
}

die_unmeasured() { printf 'record-classification: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --intent) [ "$#" -ge 2 ] || die_unmeasured "--intent needs an identifier"; INTENT="$2"; shift 2 ;;
    --intent=*) INTENT="${1#--intent=}"; shift ;;
    --classification) [ "$#" -ge 2 ] || die_unmeasured "--classification needs a value"; CLASSIFICATION="$2"; shift 2 ;;
    --classification=*) CLASSIFICATION="${1#--classification=}"; shift ;;
    --root) [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"; ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --spec-path) [ "$#" -ge 2 ] || die_unmeasured "--spec-path needs a path"; SPEC_REL="$2"; shift 2 ;;
    --spec-path=*) SPEC_REL="${1#--spec-path=}"; shift ;;
    --store) [ "$#" -ge 2 ] || die_unmeasured "--store needs a path"; STORE_REL="$2"; shift 2 ;;
    --store=*) STORE_REL="${1#--store=}"; shift ;;
    -*) printf 'record-classification: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'record-classification: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$INTENT" ] || die_unmeasured "--intent is required. A record with no intent belongs to nothing."
[ -n "$CLASSIFICATION" ] || die_unmeasured "--classification is required, and must be one of extend, refine, duplicate, contradict."

case "$CLASSIFICATION" in
  extend|refine|duplicate|contradict) ;;
  *) die_unmeasured "'$CLASSIFICATION' is not one of the four classifications the lifecycle allows: extend, refine, duplicate, contradict." ;;
esac

command -v python3 >/dev/null ||
  die_unmeasured "python3 is not on PATH, so the spec cannot be hashed or parsed. Refusing rather than writing a record whose provenance nobody computed."
[ -f "$LIB" ] && [ -r "$LIB" ] ||
  die_unmeasured "cannot read classification-record.py beside this script. The active-id rules and the hash live there; guessing them here is how two parsers come to disagree."

# Defaulting to the working directory has caused four separate silent-wrong-
# answer bugs in this repo: the script reads a directory that is not the repo
# and reports a confident result about it. git names the work tree or nothing does.
if [ -z "$ROOT" ]; then
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_unmeasured "no git work tree here, and --root was not given. Without a repository there is no commit to record, and a classification with no commit is the remembered copy R19 forbids."
  fi
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"

SPEC="$ROOT/$SPEC_REL"
STORE="$ROOT/$STORE_REL"

# --- the spec home, or nothing --------------------------------------------
[ -e "$SPEC" ] ||
  die_unmeasured "the spec home is unreachable: $SPEC_REL does not exist under the given root. R19 - stop, rather than classify against a remembered copy. Nothing was written."
[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "the spec home is unreachable: $SPEC_REL exists but cannot be read. Unreachable is not empty, and neither is a reason to classify from memory. Nothing was written."

if ! COMMIT="$(git -C "$ROOT" rev-parse HEAD)"; then
  die_unmeasured "the repository has no HEAD commit, so there is nothing to record the spec against. Nothing was written."
fi
case "$COMMIT" in
  [0-9a-f]*) ;;
  *) die_unmeasured "git named HEAD as something that is not a commit sha. Refusing." ;;
esac

WORK="$(mktemp -d "${TMPDIR:-/tmp}/record-classification.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# `git show` writes its reason to stderr, and that reason is the answer to
# "why is the spec home unreachable". It is captured and printed, never binned.
if ! git -C "$ROOT" show "$COMMIT:$SPEC_REL" > "$WORK/at-head" 2> "$WORK/git-err"; then
  printf 'record-classification: git could not read %s at %s:\n' "$SPEC_REL" "$COMMIT" >&2
  sed 's/^/  /' < "$WORK/git-err" >&2
  die_unmeasured "the spec is not tracked at HEAD, so no commit can be cited for it. A classification with no commit is the remembered copy R19 forbids. Nothing was written."
fi

SPEC_HASH="$(python3 "$LIB" --sha256 "$SPEC")"
HEAD_HASH="$(python3 "$LIB" --sha256 "$WORK/at-head")"

if [ "$SPEC_HASH" != "$HEAD_HASH" ]; then
  die_unmeasured "the spec in the work tree differs from the spec at HEAD. A record cites a commit and the check rehashes the spec AT that commit, so a classification made against uncommitted edits could never be verified against anything. Commit the spec, then classify against it. Nothing was written."
fi

case "$SPEC_HASH" in
  sha256:????????????????????????????????????????????????????????????????) ;;
  *) die_unmeasured "the spec hash did not come out in the expected shape. Refusing rather than writing a record whose hash nobody can check." ;;
esac

SLUG="$(python3 "$LIB" --slug "$INTENT")"
RECORDED="$(python3 "$LIB" --today)"

# The intent identifier is written into a committed file, so its shape is
# checked before it is written and not after. Everything else about the intent
# stays out of this store.
python3 "$LIB" --active-ids "$SPEC" > "$WORK/ids"
ID_COUNT="$(awk 'END { print NR }' "$WORK/ids")"

DEST="$STORE/$SLUG.md"

# --- exactly one classification per intent --------------------------------
if [ -e "$DEST" ]; then
  [ -r "$DEST" ] ||
    die_unmeasured "$STORE_REL/$SLUG.md exists but cannot be read, so whether this intent is already classified is UNKNOWN, not no. Nothing was written."
  EXISTING="$(awk '/^Intent:/ { sub(/^Intent:[ \t]*/, ""); print; exit }' "$DEST")"
  if [ "$EXISTING" = "$INTENT" ]; then
    printf '%s\n' "$STORE_REL/$SLUG.md"
    printf 'REFUSED: this intent is already classified. Exactly one classification per intent is the R6 invariant, and it is held here by the filename. Nothing was written.\n' >&2
    exit 1
  fi
  die_unmeasured "$STORE_REL/$SLUG.md already holds a record for a different intent identifier - two identifiers reduced to one filename. Pick a distinguishable id; do not overwrite. Nothing was written."
fi

# --- build it whole, then move it in one step ------------------------------
{
  printf '# Classification — %s\n\n' "$INTENT"
  printf 'Intent: %s\n' "$INTENT"
  printf 'Classification: %s\n' "$CLASSIFICATION"
  printf 'Recorded: %s\n' "$RECORDED"
  printf 'Spec path: %s\n' "$SPEC_REL"
  printf 'Spec commit: %s\n' "$COMMIT"
  printf 'Spec hash: %s\n' "$SPEC_HASH"
  printf 'In scope count: %s\n' "$ID_COUNT"
  printf '\n'
  printf 'The spec commit and hash above are what make this record falsifiable:\n'
  printf 'the spec at that commit is rehashed and its active requirement ids are\n'
  printf 'recomputed, then compared with the list below. A record whose hash is\n'
  printf 'blank, absent or a placeholder is refused rather than believed.\n'
  printf '\n'
  printf '%s\n\n' "## Requirement ids in scope"
  cat "$WORK/ids"
} > "$WORK/record.md"

mkdir -p "$STORE"
mv "$WORK/record.md" "$DEST"

printf '%s\n' "$SPEC_REL"
printf 'spec commit: %s\n' "$COMMIT"
printf 'spec hash: %s\n' "$SPEC_HASH"
printf 'active requirement ids in scope: %s\n' "$ID_COUNT"
printf 'classification: %s\n' "$CLASSIFICATION"
printf '%s\n' "$STORE_REL/$SLUG.md"
