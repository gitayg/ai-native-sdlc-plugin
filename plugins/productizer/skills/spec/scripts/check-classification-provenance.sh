#!/usr/bin/env bash
# check-classification-provenance.sh [--version] [--help] [--root DIR]
#                                    [--spec-path PATH] [--store DIR]
#
# Validates the provenance records `record-classification.sh` writes. Two
# acceptance rows share this one mechanism, and this is the half that refuses.
#
#   R6  When an intent arrives, the lifecycle shall classify it against the
#       WHOLE living spec as exactly one of extend, refine, duplicate or
#       contradict.
#
#   R19 If the spec home is unreachable, then the lifecycle shall stop rather
#       than classify against a remembered copy.
#
# WHAT IT ASSERTS, per record:
#
#   1. THE CLASSIFICATION IS EXACTLY ONE OF THE FOUR. Not zero - a record with
#      no Classification line, or a blank one, records nothing. Not two - a
#      second Classification line makes which value is authoritative undefined.
#      Not a fifth value, which nothing downstream knows how to act on.
#
#   2. EXACTLY ONE RECORD PER INTENT. The writer holds this at the filename;
#      this holds it at the content, because a second file under a different
#      name declaring the same intent walks straight past the filename.
#
#   3. THE HASH MATCHES THE SPEC AT THE RECORDED COMMIT. The spec is refetched
#      with `git show <commit>:<path>` and rehashed. This is the R19 assertion:
#      a classification made from a remembered copy either carries no hash - in
#      which case it is refused by 4 - or carries a hash of the remembered copy,
#      which does not match the spec at the commit it stamped.
#
#   4. NO RECORD WITHOUT A HASH. A blank, absent or placeholder `Spec hash` or
#      `Spec commit` is a finding, and so is an em dash. This is the ONE place
#      in this lifecycle where an em dash is refused rather than required: an
#      unmeasured value is normally reported honestly as unknown, but here the
#      correct response to an unreachable spec home is to write NO RECORD, so a
#      record that writes the gap in is a record that should not exist.
#
#   5. EVERY REQUIREMENT ACTIVE IN THAT SPEC WAS IN SCOPE. The active ids are
#      recomputed from the refetched spec and compared with the record's list.
#      A missing id is the truncation case: a classifier that saw part of the
#      spec can be right by luck, and a graded eval scoring 16/16 on outcomes
#      cannot tell that apart from one that saw all of it. An id in the list
#      that the spec does not have active is the same failure inverted.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   A record made against an OLDER spec is not a finding. The normal intake
#   flow is classify, then merge the delta - so the spec moves immediately
#   after almost every correct record. Anchoring the comparison to the commit
#   the record cites is what stops this check going red on every historical
#   record the first time a requirement is added. Currency is reported per
#   record as a note, and a note is not a verdict.
#
#   It does not observe the classification being MADE. Nothing in a file can.
#   It observes the record, which is why the writer refuses to emit one it
#   cannot stand behind.
#
# NO FILE MEANS NO COUNT, NOT ZERO
#
#   no classifications/ directory   this repo has recorded none. Reported as a
#                                   note, never as "0 classifications are
#                                   fine": the two are different sentences.
#   a directory it cannot list      UNKNOWN. Exit 2. A directory nobody can
#                                   open is exactly where a truncated
#                                   classification hides.
#   a directory holding no records  a measured zero, and said so.
#
# An unmatched glob reaches a command as its own literal text in bash, so the
# cases are told apart by an explicit directory test and never by a count.
#
# UNRESOLVABLE IS NOT WRONG. A record citing a commit this clone does not hold
# - a shallow clone, a rewritten history - cannot be checked. That is exit 2,
# refused, and it is never folded into a pass. The one ordering rule is
# check-spec-home's: findings already in hand are a definite answer, so they
# exit 1 even when another record was unresolvable. Unresolvability only
# refuses when it could still change the verdict.
#
# REPORTED BY LOCATION, NEVER BY QUOTING CONTENT. File, line, and the class of
# problem. A record names an intent a stranger can write, and this output
# reaches a committed results file and a model's context. The only value ever
# echoed is a classification word, checked against a closed set of four first.
# Paths are printed RELATIVE to the root, because an absolute one names
# somebody's home directory and this output is committed.
#
# ONE LINE PER FILE EXAMINED, on stdout, unindented - the spec, then every
# record read. The runner treats a check that exits clean having examined less
# than it declared as HOLLOW, which is a failure. A check that looks at nothing
# must not look like a pass.
#
# KNOWN LIMITATIONS, written down rather than discovered later:
#   - The active-id rules are build-view.sh's, reproduced in
#     classification-record.py. A spec written in a shape that parser does not
#     recognise yields a smaller active set, and a record matching it passes.
#     The mitigation is that both halves use the one parser, so the writer and
#     the check are wrong together and visibly - never in disagreement.
#   - A record can be hand-written to cite an ancient commit whose spec was
#     genuinely small, and it will pass. What the record proves is that its
#     scope list matches the spec it names; that the commit named is the right
#     one is what the writer, not this check, establishes.
#   - Running as a user who can read anything (root) defeats the unreadable-
#     directory test, as it defeats every such test.
#
# PORTABILITY. Developed on macOS/BSD. No GNU-only behaviour: no mapfile, no
# `grep -P`, no `date -d`, no in-place sed. Nothing suppresses stderr.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  clean
#   1  findings
#   2  could not run - no work tree, no spec, an unreadable store or record, or
#      a recorded commit this clone cannot resolve. Never confused with 0.
set -euo pipefail

export LC_ALL=C

VERSION="check-classification-provenance 1.0"

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/classification-record.py"

ROOT=""
SPEC_REL=".claude/productizer/spec.md"
STORE_REL=".claude/productizer/classifications"

usage() {
  printf 'usage: check-classification-provenance.sh [--version] [--help] [--root DIR]\n'
  printf '                                          [--spec-path PATH] [--store DIR]\n'
  printf '  --root DIR        the repo work tree to examine. Defaults to the git\n'
  printf '                    top level, never to the working directory.\n'
  printf '  --spec-path PATH  spec location relative to the root\n'
  printf '  --store DIR       record store relative to the root\n'
}

die_unmeasured() { printf 'check-classification-provenance: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --root) [ "$#" -ge 2 ] || die_unmeasured "--root needs a directory"; ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --spec-path) [ "$#" -ge 2 ] || die_unmeasured "--spec-path needs a path"; SPEC_REL="$2"; shift 2 ;;
    --spec-path=*) SPEC_REL="${1#--spec-path=}"; shift ;;
    --store) [ "$#" -ge 2 ] || die_unmeasured "--store needs a path"; STORE_REL="$2"; shift 2 ;;
    --store=*) STORE_REL="${1#--store=}"; shift ;;
    -*) printf 'check-classification-provenance: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'check-classification-provenance: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null ||
  die_unmeasured "python3 is not on PATH, so no record can be parsed or rehashed. Refusing rather than reporting unparsed records as clean."
[ -f "$LIB" ] && [ -r "$LIB" ] ||
  die_unmeasured "cannot read classification-record.py beside this script. The active-id rules live there, and a second copy of them here is how two parsers come to disagree."

if [ -z "$ROOT" ]; then
  if ! ROOT="$(git rev-parse --show-toplevel)"; then
    die_unmeasured "no git work tree here, and --root was not given. Refusing rather than reading the working directory, which is not the repo often enough to matter."
  fi
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"

SPEC="$ROOT/$SPEC_REL"
STORE="$ROOT/$STORE_REL"

[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "cannot read $SPEC_REL under the given root. Without the spec there is no active set to compare a record against, and a check that cannot compare must not report a pass."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-classification-provenance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

found=0
unresolved=0
finding() { printf '    %s\n' "$1"; found=1; }

printf '%s\n' "$SPEC_REL"          # coverage: one line per file examined

# ---------------------------------------------------------------------------
# The store. Absent, unreadable and empty are three different answers.
# ---------------------------------------------------------------------------
DIRSTATE="absent"
if [ -e "$STORE" ]; then
  [ -d "$STORE" ] ||
    die_unmeasured "$STORE_REL exists but is not a directory. A path that is not the directory the contract names says nothing about how many classifications were recorded - unmeasured, not zero."
  if [ -r "$STORE" ] && [ -x "$STORE" ]; then
    DIRSTATE="present"
  else
    die_unmeasured "$STORE_REL exists but cannot be listed. How many classifications were recorded is UNKNOWN, not zero - a directory nobody can open is exactly where a truncated classification hides."
  fi
fi

records=0
: > "$WORK/intents.tsv"

if [ "$DIRSTATE" = "present" ]; then
  for f in "$STORE"/*.md; do
    # An unmatched glob arrives as its own literal text, so test the path.
    [ -e "$f" ] || continue
    base="${f##*/}"
    rel="$STORE_REL/$base"
    printf '%s\n' "$rel"           # coverage: one line per file examined
    records=$((records + 1))

    [ -f "$f" ] && [ -r "$f" ] ||
      die_unmeasured "cannot read $rel. A record nobody could open is not a record that is fine."

    # --- pass one: header fields, without the spec ------------------------
    python3 "$LIB" --validate "$f" "-" > "$WORK/pass1.tsv"

    rec_commit=""; rec_hash=""; rec_specpath=""; rec_intent=""; rec_class=""
    while IFS="$(printf '\t')" read -r kind kline detail; do
      [ "${kind:-}" = "VALUE" ] || continue
      case "$detail" in
        "Spec commit="*) rec_commit="${detail#Spec commit=}" ;;
        "Spec hash="*)   rec_hash="${detail#Spec hash=}" ;;
        "Spec path="*)   rec_specpath="${detail#Spec path=}" ;;
        Intent=*)        rec_intent="${detail#Intent=}" ;;
        Classification=*) rec_class="${detail#Classification=}" ;;
      esac
      : "$kline"
    done < "$WORK/pass1.tsv"

    # --- refetch the spec at the recorded commit and rehash it ------------
    SPECSRC="-"
    if [ -n "$rec_commit" ] && [ -n "$rec_hash" ] && [ -n "$rec_specpath" ]; then
      if git -C "$ROOT" show "$rec_commit:$rec_specpath" > "$WORK/at-commit" 2> "$WORK/git-err"; then
        got="$(python3 "$LIB" --sha256 "$WORK/at-commit")"
        if [ "$got" = "$rec_hash" ]; then
          SPECSRC="$WORK/at-commit"
        else
          finding "$rel:1: the recorded Spec hash does not match the spec at the recorded Spec commit. The record stamps one spec and hashed another, which is what classifying from a remembered copy looks like once it is written down. The in-scope list was NOT compared - what this record read is unknown, not empty."
        fi
      else
        printf '    %s:1: the recorded Spec commit cannot be resolved in this clone. git said:\n' "$rel"
        sed 's/^/      /' < "$WORK/git-err"
        unresolved=$((unresolved + 1))
      fi
    fi

    # --- pass two: everything, now that the spec is in hand ---------------
    python3 "$LIB" --validate "$f" "$SPECSRC" > "$WORK/pass2.tsv"

    active_at="—"
    while IFS="$(printf '\t')" read -r kind kline detail; do
      case "${kind:-}" in
        FINDING) finding "$rel:$kline: $detail" ;;
        VALUE)
          case "$detail" in
            "Active at commit="*) active_at="${detail#Active at commit=}" ;;
          esac
          ;;
      esac
    done < "$WORK/pass2.tsv"

    # --- the filename is the writer's uniqueness guarantee; verify it -----
    if [ -n "$rec_intent" ]; then
      want="$(python3 "$LIB" --slug "$rec_intent")"
      if [ "$base" != "$want.md" ]; then
        finding "$rel:1: the filename does not match the intent this record declares. The store holds one record per intent BY NAME, so a record filed under any other name is a second classification the filename can never catch."
      fi
      printf '%s\t%s\n' "$rec_intent" "$rel" >> "$WORK/intents.tsv"
    fi

    printf '  %s classification: %s, ids in scope claimed against %s active at that commit\n' \
      "$base" "${rec_class:-—}" "$active_at"

    if [ -n "$rec_hash" ] && [ "$rec_hash" != "$(python3 "$LIB" --sha256 "$SPEC")" ]; then
      printf '  %s note: the spec has moved since this record was written. Historical, not a finding - the normal intake flow is classify, then merge the delta.\n' "$base"
    fi
  done
fi

# ---------------------------------------------------------------------------
# Exactly one record per intent, checked at the content and not the filename.
# ---------------------------------------------------------------------------
if [ -s "$WORK/intents.tsv" ]; then
  sort "$WORK/intents.tsv" > "$WORK/intents-sorted.tsv"
  cut -f1 "$WORK/intents-sorted.tsv" | uniq -d > "$WORK/dupes"
  while IFS= read -r dup; do
    [ -n "$dup" ] || continue
    while IFS="$(printf '\t')" read -r who where; do
      [ "$who" = "$dup" ] || continue
      finding "$where:1: this intent is classified more than once in the store. R6 says exactly one of the four, and two records for one intent is two answers with nothing choosing between them."
    done < "$WORK/intents-sorted.tsv"
  done < "$WORK/dupes"
fi

printf 'records examined: %d\n' "$records"
if [ "$DIRSTATE" = "absent" ]; then
  printf 'note: no %s directory - this repo has recorded no classification. That is no count, not a measured zero.\n' "$STORE_REL"
elif [ "$records" -eq 0 ]; then
  printf 'note: %s exists and holds no records. This one IS a measured zero.\n' "$STORE_REL"
fi
printf 'unresolvable commits: %d\n' "$unresolved"

if [ "$found" -ne 0 ]; then
  printf 'FAIL: a classification record does not stand up. R6 needs the whole active set to have been in scope; R19 needs a hash that matches the spec at the commit it names.\n' >&2
  exit 1
fi

if [ "$unresolved" -gt 0 ]; then
  printf 'REFUSED: %d record(s) cite a commit this clone cannot resolve, so whether they were classified against the whole spec is UNKNOWN - not yes, and not no.\n' "$unresolved" >&2
  exit 2
fi

# The pass line says what was actually asserted. A run with no records has
# asserted nothing about records, and a PASS claiming otherwise is the green
# summary line this whole stage exists to distrust.
if [ "$records" -eq 0 ]; then
  printf 'PASS: nothing to contradict. No classification record was examined, so this run asserts nothing about R6 or R19 - it is clean, not evidence.\n'
else
  printf 'PASS: all %d record(s) carry a hash that matches the spec at the commit they name, exactly one classification from the four, and every requirement active in that spec in scope.\n' "$records"
fi
