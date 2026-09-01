#!/usr/bin/env bash
# check-classification-provenance.sh [--version] [--help] [--root DIR]
#                                    [--spec-path PATH] [--store DIR]
#                                    [--backlog PATH]
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
# and once for the store as a whole:
#
#   6. THE STORE IS NOT EMPTY IN A REPO THAT DEMONSTRABLY CLASSIFIED. See the
#      section below; this is the assertion 2.0 adds, and the reason for it is
#      that the five above had never once been evaluated.
#
# ASSERTIONS ARE COUNTED SEPARATELY, NOT ROLLED INTO ONE FLAG. The summary
# names each assertion and how many records upheld it, how many failed it, and
# how many did not assert it at all - a record whose commit could not be
# resolved asserts nothing about its hash, and is counted in neither column.
# One `ok` boolean, divided at the end, is how a check comes to report a
# denominator it never measured. Assertions 1, 4 and 5 share one counter and
# say so: they are raised inside `classification-record.py`, the parser the
# writer and this check deliberately share, and it does not label which of the
# three a finding came from.
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
# AN EMPTY STORE IS NOT A PASS - AND IS NOT AUTOMATICALLY A FAILURE EITHER
#
#   Through 1.0 this check exited 0 over an empty store, saying in its own pass
#   line that it had asserted nothing. The sentence was true and the exit code
#   was not: a clean exit from a blocking check is read as "R6 holds here", and
#   this one had swept an empty set every run since the day it was written,
#   because Stage 2 intake never invoked `record-classification.sh`. The
#   mechanism was written and never wired, and nothing said so out loud.
#
#   Failing outright is the other wrong answer. A repo scaffolded this morning
#   has classified nothing and has violated nothing, and a check that cries
#   wolf there teaches everybody to ignore it.
#
#   So an empty store is not judged on its own. It is judged against evidence
#   held OUTSIDE the store about whether this repo classified anything at all:
#
#     empty store, evidence classification happened   FINDING       exit 1
#     empty store, no such evidence                   UNMEASURED    exit 2
#
#   Never 0, and never the same sentence twice: the first says records are
#   missing, the second says nothing was measured. Collapsing them would be the
#   1.0 defect again in a different costume.
#
# THE CORROBORATING SOURCE IS THE BACKLOG, AND HERE IS WHY IT AND NOT THE REST
#
#   `.claude/productizer/backlog.md`, scanned for the classification word
#   itself - the backticked `extend`, `refine`, `duplicate` or `contradict`
#   following the word `classified`. Stage 1 already writes that line onto an
#   item when it goes through intake, so the evidence is committed in the repo,
#   readable offline, in a file the lifecycle maintains for its own reasons. It
#   names the classification rather than an effect of one, and it is written
#   for all four outcomes.
#
#   The spec's `## Change log` was considered and REJECTED. It records MERGES,
#   not classifications. Two of the four outcomes - duplicate and contradict -
#   merge nothing by definition, so a lifecycle classifying correctly and
#   refusing what it should refuse leaves an empty change log. Evidence that
#   vanishes exactly when the requirement is working hardest is not evidence.
#   Its rows also cover spec edits that were never an arriving intent at all -
#   this repo's own row cites no issue, because it records a split made under a
#   decision record - so counting a row as "an intent was classified" would
#   assert something the row does not say.
#
#   Tracker labels were considered and REJECTED. They live in a service, behind
#   a network and a token: a check that reads them reports unmeasured every time
#   it runs offline, and they leave with the tracker at the next migration. That
#   is the same reason this lifecycle commits its records beside the spec
#   instead of in issue comments.
#
#   KNOWN LIMITATION, written down rather than discovered later: the pattern
#   requires the backticked spelling. A backlog saying "classified as extend"
#   in running prose is not matched. The direction of that error is the safe
#   one - a missed match yields exit 2, unmeasured, and never a pass. The
#   backticks are required on purpose: an unbackticked pattern also matches
#   this repo's own prose about what intake WILL classify, and a corroborator
#   that fires on a sentence in the future tense manufactures findings.
#
#   The backlog is read on every run, not only when the store is empty, so the
#   set of files this check declares as examined does not depend on the verdict
#   it is about to reach. When both counts are non-zero their difference is
#   printed as a note and never as a verdict: a backlog line and a store record
#   are not in one-to-one correspondence, and lines written before the store
#   existed can never have one.
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
# echoed is a classification word, checked against a closed set of four first -
# and that rule governs the backlog scan too: a corroborated line is reported
# as a line number and a classification word, never as the item's text.
# Paths are printed RELATIVE to the root, because an absolute one names
# somebody's home directory and this output is committed.
#
# ONE LINE PER FILE EXAMINED, on stdout, unindented - the spec, the backlog
# when it could be read, then every record read. The runner treats a check that
# exits clean having examined less than it declared as HOLLOW, which is a
# failure. A check that looks at nothing must not look like a pass.
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
#   0  clean - and never over an empty store
#   1  findings, including an empty store in a repo that classified
#   2  could not run - no work tree, no spec, an unreadable store or record, a
#      recorded commit this clone cannot resolve, or an empty store with
#      nothing corroborating that any classification was ever made. Never
#      confused with 0.
set -euo pipefail

export LC_ALL=C

VERSION="check-classification-provenance 2.0"

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/classification-record.py"

ROOT=""
SPEC_REL=".claude/productizer/spec.md"
STORE_REL=".claude/productizer/classifications"
BACKLOG_REL=".claude/productizer/backlog.md"

# The corroborating pattern. Backticks are load-bearing; see the header.
EVIDENCE_RE='classified `(extend|refine|duplicate|contradict)`'

usage() {
  printf 'usage: check-classification-provenance.sh [--version] [--help] [--root DIR]\n'
  printf '                                          [--spec-path PATH] [--store DIR]\n'
  printf '                                          [--backlog PATH]\n'
  printf '  --root DIR        the repo work tree to examine. Defaults to the git\n'
  printf '                    top level, never to the working directory.\n'
  printf '  --spec-path PATH  spec location relative to the root\n'
  printf '  --store DIR       record store relative to the root\n'
  printf '  --backlog PATH    the file corroborating that classification happened,\n'
  printf '                    relative to the root. An empty store is a FINDING when\n'
  printf '                    this file records a classification and UNMEASURED when\n'
  printf '                    it does not - it is never a pass either way.\n'
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
    --backlog) [ "$#" -ge 2 ] || die_unmeasured "--backlog needs a path"; BACKLOG_REL="$2"; shift 2 ;;
    --backlog=*) BACKLOG_REL="${1#--backlog=}"; shift ;;
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
BACKLOG="$ROOT/$BACKLOG_REL"

[ -f "$SPEC" ] && [ -r "$SPEC" ] ||
  die_unmeasured "cannot read $SPEC_REL under the given root. Without the spec there is no active set to compare a record against, and a check that cannot compare must not report a pass."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-classification-provenance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

found=0
unresolved=0
finding() { printf '    %s\n' "$1"; found=1; }

# Every assertion carries its OWN pair of counters. Nothing here is derived by
# subtracting one number from another at the end.
a_hash_up=0;  a_hash_bad=0;  a_hash_none=0
a_name_up=0;  a_name_bad=0
a_uniq_up=0;  a_uniq_bad=0
a_body_up=0;  a_body_bad=0
a_store_up=0; a_store_bad=0; a_store_none=0

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
    # ASSERTION 3, counted on its own. A record with no commit or no hash at
    # all is assertion 4's to refuse, and asserts NOTHING here.
    SPECSRC="-"
    if [ -n "$rec_commit" ] && [ -n "$rec_hash" ] && [ -n "$rec_specpath" ]; then
      if git -C "$ROOT" show "$rec_commit:$rec_specpath" > "$WORK/at-commit" 2> "$WORK/git-err"; then
        got="$(python3 "$LIB" --sha256 "$WORK/at-commit")"
        if [ "$got" = "$rec_hash" ]; then
          SPECSRC="$WORK/at-commit"
          a_hash_up=$((a_hash_up + 1))
        else
          a_hash_bad=$((a_hash_bad + 1))
          finding "$rel:1: the recorded Spec hash does not match the spec at the recorded Spec commit. The record stamps one spec and hashed another, which is what classifying from a remembered copy looks like once it is written down. The in-scope list was NOT compared - what this record read is unknown, not empty."
        fi
      else
        printf '    %s:1: the recorded Spec commit cannot be resolved in this clone. git said:\n' "$rel"
        sed 's/^/      /' < "$WORK/git-err"
        unresolved=$((unresolved + 1))
        a_hash_none=$((a_hash_none + 1))
      fi
    else
      a_hash_none=$((a_hash_none + 1))
    fi

    # --- pass two: everything, now that the spec is in hand ---------------
    # ASSERTIONS 1, 4 and 5, in one counter, because the shared parser does
    # not label which of the three a finding belongs to and a second copy of
    # its rules here is how two parsers come to disagree.
    python3 "$LIB" --validate "$f" "$SPECSRC" > "$WORK/pass2.tsv"

    body_bad=0
    active_at="—"
    while IFS="$(printf '\t')" read -r kind kline detail; do
      case "${kind:-}" in
        FINDING) finding "$rel:$kline: $detail"; body_bad=1 ;;
        VALUE)
          case "$detail" in
            "Active at commit="*) active_at="${detail#Active at commit=}" ;;
          esac
          ;;
      esac
    done < "$WORK/pass2.tsv"
    if [ "$body_bad" -eq 0 ]; then
      a_body_up=$((a_body_up + 1))
    else
      a_body_bad=$((a_body_bad + 1))
    fi

    # --- ASSERTION 2a: the filename is the writer's uniqueness guarantee --
    if [ -n "$rec_intent" ]; then
      want="$(python3 "$LIB" --slug "$rec_intent")"
      if [ "$base" != "$want.md" ]; then
        a_name_bad=$((a_name_bad + 1))
        finding "$rel:1: the filename does not match the intent this record declares. The store holds one record per intent BY NAME, so a record filed under any other name is a second classification the filename can never catch."
      else
        a_name_up=$((a_name_up + 1))
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
# ASSERTION 2b: exactly one record per intent, checked at the content and not
# the filename. Counted per record, so the number below is a count of records
# that held it and never a count of intents.
# ---------------------------------------------------------------------------
if [ -s "$WORK/intents.tsv" ]; then
  sort "$WORK/intents.tsv" > "$WORK/intents-sorted.tsv"
  cut -f1 "$WORK/intents-sorted.tsv" | uniq -d > "$WORK/dupes"
  while IFS="$(printf '\t')" read -r who where; do
    dup=0
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      if [ "$d" = "$who" ]; then dup=1; fi
    done < "$WORK/dupes"
    if [ "$dup" -eq 1 ]; then
      a_uniq_bad=$((a_uniq_bad + 1))
      finding "$where:1: this intent is classified more than once in the store. R6 says exactly one of the four, and two records for one intent is two answers with nothing choosing between them."
    else
      a_uniq_up=$((a_uniq_up + 1))
    fi
  done < "$WORK/intents-sorted.tsv"
fi

# ---------------------------------------------------------------------------
# ASSERTION 6: the store is not an empty one in a repo that classified.
#
# Read on EVERY run, not only when the store is empty, so the set of files
# this check declares as examined does not depend on the verdict it reaches.
# ---------------------------------------------------------------------------
corroborated=0
BACKSTATE="absent"
: > "$WORK/evidence"

if [ -e "$BACKLOG" ]; then
  if [ -f "$BACKLOG" ] && [ -r "$BACKLOG" ]; then
    BACKSTATE="read"
    printf '%s\n' "$BACKLOG_REL"   # coverage: one line per file examined
    set +e
    grep -n -E "$EVIDENCE_RE" "$BACKLOG" > "$WORK/evidence"
    grc=$?
    set -e
    case "$grc" in
      0) corroborated="$(wc -l < "$WORK/evidence" | tr -d ' ')" ;;
      1) corroborated=0 ;;          # a genuine no-match, which is an answer
      *) die_unmeasured "grep exited $grc reading $BACKLOG_REL, so whether this repo ever classified anything is UNKNOWN. An empty store is only innocent once that question has an answer." ;;
    esac
  else
    BACKSTATE="unreadable"
  fi
fi

if [ "$records" -gt 0 ]; then
  a_store_up=1
elif [ "$corroborated" -gt 0 ]; then
  a_store_bad=1
  shown=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    lno="${line%%:*}"
    word="$(printf '%s\n' "$line" | sed -n 's/.*classified `\([a-z]*\)`.*/\1/p')"
    case "$word" in extend|refine|duplicate|contradict) ;; *) word="—" ;; esac
    shown=$((shown + 1))
    if [ "$shown" -le 20 ]; then
      finding "$BACKLOG_REL:$lno: an intake classification of \`$word\` is recorded here, and the store holds no provenance record for it. R6 needs the ids that were in scope and R19 needs the hash of what was read; neither exists for this classification, so neither can ever be checked."
    fi
  done < "$WORK/evidence"
  if [ "$corroborated" -gt 20 ]; then
    printf '    ... and %d more corroborated classification(s), not listed.\n' "$((corroborated - 20))"
  fi
else
  a_store_none=1
fi

# ---------------------------------------------------------------------------
# The summary. Every number below was counted where it was measured.
# ---------------------------------------------------------------------------
printf 'records examined: %d\n' "$records"
if [ "$DIRSTATE" = "absent" ]; then
  printf 'note: no %s directory - this repo has recorded no classification. That is no count, not a measured zero.\n' "$STORE_REL"
elif [ "$records" -eq 0 ]; then
  printf 'note: %s exists and holds no records. This one IS a measured zero.\n' "$STORE_REL"
fi
printf 'unresolvable commits: %d\n' "$unresolved"

case "$BACKSTATE" in
  read)
    printf 'classifications corroborated in %s: %d\n' "$BACKLOG_REL" "$corroborated"
    ;;
  absent)
    printf 'note: no %s - nothing in this repo corroborates a classification either way. Absent is not the same sentence as none happened.\n' "$BACKLOG_REL"
    ;;
  unreadable)
    printf 'note: %s exists and cannot be read. Whether this repo ever classified anything is UNKNOWN, not none.\n' "$BACKLOG_REL"
    ;;
esac

if [ "$records" -gt 0 ] && [ "$corroborated" -gt "$records" ]; then
  printf 'note: %d corroborated classification(s) against %d record(s). Reported, never judged - the two are not in one-to-one correspondence, and a backlog line written before the store existed can never have a record.\n' \
    "$corroborated" "$records"
fi

printf 'assertions, each counted where it was measured:\n'
printf '  3 hash matches the spec at the recorded commit: %d upheld, %d failed, %d not asserted\n' \
  "$a_hash_up" "$a_hash_bad" "$a_hash_none"
printf '  1+4+5 classification value, hash present, scope list complete: %d upheld, %d failed\n' \
  "$a_body_up" "$a_body_bad"
printf '  2a filename matches the intent the record declares: %d upheld, %d failed\n' \
  "$a_name_up" "$a_name_bad"
printf '  2b exactly one record per intent, at the content: %d upheld, %d failed\n' \
  "$a_uniq_up" "$a_uniq_bad"
printf '  6 the store is not empty in a repo that classified: %d upheld, %d failed, %d not asserted\n' \
  "$a_store_up" "$a_store_bad" "$a_store_none"

if [ "$found" -ne 0 ]; then
  if [ "$records" -eq 0 ]; then
    printf 'FAIL: this repo records %d classification(s) and holds provenance for none of them. An empty store here is not nothing to check - it is R6 and R19 unrecorded, and the store cannot fill itself: Stage 2 intake has to call record-classification.sh at the moment it settles on one of the four.\n' "$corroborated" >&2
  else
    printf 'FAIL: a classification record does not stand up. R6 needs the whole active set to have been in scope; R19 needs a hash that matches the spec at the commit it names.\n' >&2
  fi
  exit 1
fi

if [ "$unresolved" -gt 0 ]; then
  printf 'REFUSED: %d record(s) cite a commit this clone cannot resolve, so whether they were classified against the whole spec is UNKNOWN - not yes, and not no.\n' "$unresolved" >&2
  exit 2
fi

# The verdict line says what was actually asserted. A run with no records has
# asserted nothing about records, and through 1.0 that run exited 0 - which is
# the green summary line this whole stage exists to distrust.
if [ "$records" -eq 0 ]; then
  # The reason differs and is said differently. "Nothing corroborates it" is a
  # measured answer; "the corroborator could not be read" is not one, and
  # printing the first sentence over the second would be this check inventing
  # the measurement it just failed to take.
  case "$BACKSTATE" in
    read)   why="nothing in $BACKLOG_REL corroborates that this repo has ever classified an intent" ;;
    absent) why="there is no $BACKLOG_REL to corroborate that this repo has ever classified an intent" ;;
    *)      why="$BACKLOG_REL could not be read, so whether this repo has ever classified an intent is UNKNOWN - not no" ;;
  esac
  printf 'UNMEASURED: no classification record was examined, and %s. R6 and R19 are NOT asserted by this run. Refusing rather than passing: a clean exit over an empty set is read as the requirement holding, and it is the one wrong answer that looks healthy.\n' "$why" >&2
  exit 2
fi

printf 'PASS: all %d record(s) carry a hash that matches the spec at the commit they name, exactly one classification from the four, and every requirement active in that spec in scope.\n' "$records"
