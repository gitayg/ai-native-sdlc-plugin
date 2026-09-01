#!/usr/bin/env bash
# selftest.sh [--version] [--help] [--check PATH]
#
# The falsification suite for `check-changelog-row.sh`, committed so it can be
# re-run rather than described. A check that has only ever been SEEN passing is
# not evidence; every assertion below was watched going red before it was
# trusted going green, and this file is how anyone else watches it too.
#
# It builds throwaway git repositories in a temporary directory from the spec
# versions in `spec/`, runs the check against each, and compares the EXIT CODE
# and one load-bearing line of output against what that history should produce.
# Nothing is written into the repository this file lives in.
#
# The spec versions differ from each other by exactly one thing each, which is
# the point - a case that changes two things proves neither:
#
#   1-founding.md             two requirements, counter at R3, a change log
#                             carrying the template row and one real row
#   2-word-only.md            1, with a requirement REWORDED and a paragraph
#                             REFLOWED. No id, no status, no counter moves.
#   3-classified-recorded.md  2, plus R3 added, R2 superseded by R3, the
#                             counter moved, and one row recording both halves
#   4-classified-unrecorded.md  3 MINUS THAT ROW, and nothing else. The single
#                             line between a green run and a red one.
#   5-counter-only.md         2 with the counter moved and nothing else moved
#   6-refine-recorded.md      2 with ONE change-log row added, naming R1 in
#                             the `Refined` column. 2 and 6 differ by exactly
#                             that row, which is the whole of R32.5: the same
#                             in-place rewrite, once recorded as a refine and
#                             once not.
#
# THE TEMPLATE ROW IS LEFT IN 1-founding.md ON PURPOSE. It names R41-R43, R12
# and R7, none of which the fixture spec defines. If the check ever stops
# skipping placeholder rows, its own probe refuses the run - so these cases are
# the positive control for that skip, not just for the assertions.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every case produced the verdict it should
#   1  a case produced the wrong verdict - the check is not measuring what it
#      says it measures, whatever it reports against the real spec
#   2  could not run - no git, no check to test, no temporary directory
set -euo pipefail

VERSION="changelog-row-selftest 2.0"

HERE="$(cd "$(dirname "$0")" && pwd -P)"
CHECK="$HERE/../../scripts/check-changelog-row.sh"

usage() {
  printf 'usage: selftest.sh [--version] [--help] [--check PATH]\n'
  printf '  --check PATH  the check to falsify. Defaults to\n'
  printf '                ../../scripts/check-changelog-row.sh beside this fixture.\n'
}

die_unmeasured() { printf 'changelog-row-selftest: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --check)
      [ "$#" -ge 2 ] || die_unmeasured "--check needs a path"
      CHECK="$2"; shift 2 ;;
    --check=*) CHECK="${1#--check=}"; shift ;;
    -*) printf 'changelog-row-selftest: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'changelog-row-selftest: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -f "$CHECK" ] && [ -r "$CHECK" ] ||
  die_unmeasured "cannot read the check at $CHECK. There is nothing to falsify, which is not the same as nothing being wrong."
command -v git >/dev/null ||
  die_unmeasured "git is not on PATH, and every case here is a git history"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/changelog-row-selftest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

SPECREL=".claude/productizer/spec.md"
passed=0
failed=0

# build_repo <name> <version file>... - one commit per version, in order.
build_repo() {
  repo="$WORK/$1"; shift
  mkdir -p "$repo/$(dirname "$SPECREL")"
  git -c init.defaultBranch=main init -q "$repo"
  git -C "$repo" config user.email "fixture@example.invalid"
  git -C "$repo" config user.name "changelog-row fixture"
  for version in "$@"; do
    [ -f "$HERE/spec/$version" ] ||
      die_unmeasured "fixture version spec/$version is missing; the case it builds would be a history nobody wrote"
    cp "$HERE/spec/$version" "$repo/$SPECREL"
    git -C "$repo" add "$SPECREL"
    git -C "$repo" commit -q -m "$version"
  done
  printf '%s\n' "$repo"
}

# expect <case> <expected exit> <stream: out|err> <substring> <root>
expect() {
  name="$1"; want="$2"; stream="$3"; needle="$4"; root="$5"
  got=0
  bash "$CHECK" --root "$root" > "$WORK/out" 2> "$WORK/err" || got=$?
  file="$WORK/out"
  [ "$stream" = "err" ] && file="$WORK/err"
  # grep's non-zero exit is the ANSWER here, not a failure, so it is taken as
  # a value rather than allowed to kill the script under `set -e`.
  hit=0
  grep -qF "$needle" "$file" || hit=$?
  if [ "$got" -eq "$want" ] && [ "$hit" -eq 0 ]; then
    printf 'PASS  %-22s exit %d, %s says: %s\n' "$name" "$got" "$stream" "$needle"
    passed=$((passed + 1))
  else
    printf 'FAIL  %-22s exit %d (wanted %d), %s %s: %s\n' "$name" "$got" "$want" \
      "$stream" "$([ "$hit" -eq 0 ] && printf 'says' || printf 'DOES NOT say')" "$needle"
    sed -n '1,40p' "$WORK/out"
    sed -n '1,10p' "$WORK/err"
    failed=$((failed + 1))
  fi
}

# --- 1. the positive control -------------------------------------------------
# A word-only commit and a recorded classification. Green, and the word-only
# commit is excluded rather than demanded.
recorded="$(build_repo recorded 1-founding.md 2-word-only.md 3-classified-recorded.md)"
expect recorded 0 out "assertions upheld: 4 of 4" "$recorded"
expect recorded-excludes 0 out \
  "1 changed the spec, 1 changed no id, status or counter, 0 moved the counter alone" \
  "$recorded"

# --- 2. the same history minus one row ---------------------------------------
# The only difference from case 1 is the deleted change-log row.
unrecorded="$(build_repo unrecorded 1-founding.md 2-word-only.md 4-classified-unrecorded.md)"
expect unrecorded-row 1 out "R32.1  recorded-in-the-change-log               examined   1  upheld   0  NOT HELD" "$unrecorded"
expect unrecorded-added 1 out "R32.2  addition-recorded-as-an-addition         examined   1  upheld   0  NOT HELD" "$unrecorded"
expect unrecorded-supersede 1 out "R32.3  supersession-recorded-as-a-supersession  examined   1  upheld   0  NOT HELD" "$unrecorded"
expect unrecorded-samecommit 1 out "R32.4  recorded-in-the-same-commit              examined   1  upheld   0  NOT HELD" "$unrecorded"

# --- 3. the premise, both ways -----------------------------------------------
# One commit: there is a founding commit and nothing after it.
founding="$(build_repo founding 1-founding.md)"
expect premise-one-commit 2 err "only 1 reachable commit holds" "$founding"

# Two commits, the second word-only: the trigger never fired, so NOTHING was
# asserted. This is also the anti-cry-wolf proof - a reworded requirement is
# not a classification, and the run says so instead of demanding a row.
wordonly="$(build_repo wordonly 1-founding.md 2-word-only.md)"
expect premise-word-only 2 err "not one of them added an id or replaced a requirement" "$wordonly"

# --- 3b. R32.5: the refine that keeps its id, both ways -----------------------
# 2-word-only.md rewrites R1's sentence and keeps the id and the status. That
# is what a refine looks like from the outside, and it is also what a typo fix
# looks like - which is the point. The check REPORTS it and demands nothing,
# and these two cases prove it reports it BOTH ways rather than staying silent.
#
# The exit code is 2 in both: neither history added an id or replaced a
# requirement, so nothing blocking was asserted, and R32.5 does not set the
# exit code by design. What is asserted here is the LINE.
expect r32.5-unresolved 2 out \
  "R32.5  refine-recorded-as-a-refine        examined   1  upheld   0  REPORTED, not a finding" \
  "$wordonly"
expect r32.5-names-the-id 2 out \
  "R1 kept its id and its status at" \
  "$wordonly"

# The same rewrite with a row naming R1 in `Refined`. One row is the whole
# difference, and it moves R32.5 from reported to upheld.
refined="$(build_repo refined 1-founding.md 6-refine-recorded.md)"
expect r32.5-resolved 2 out \
  "R32.5  refine-recorded-as-a-refine        examined   1  upheld   1  held" \
  "$refined"

# And the negative control for R32.5 itself: a history with NO in-place
# rewrite must say it asserted nothing, not that it held. An assertion that
# reports `held` over an empty set is the defect this whole suite exists for.
# 2 -> 3 supersedes R2 and adds R3, so a status moved and no sentence was
# rewritten in place - the one shape that leaves R32.5 with nothing to fire on.
norewrite="$(build_repo norewrite 2-word-only.md 3-classified-recorded.md)"
expect r32.5-not-asserted 0 out \
  "R32.5  refine-recorded-as-a-refine        examined   0  upheld   0  unmeasured - nothing to fire on" \
  "$norewrite"

# --- 4. the counter moved and nothing else -----------------------------------
# The trigger fired and cannot be attributed to an id. No verdict, not a pass.
counter="$(build_repo counter 1-founding.md 5-counter-only.md)"
expect counter-only 2 out "moved the counter alone" "$counter"

# --- 5. a shallow clone is refused, not passed -------------------------------
git clone --quiet --depth 1 "file://$recorded" "$WORK/shallow"
expect shallow 2 err "SHALLOW clone" "$WORK/shallow"

printf 'cases: %d passed, %d failed\n' "$passed" "$failed"
if [ "$failed" -ne 0 ]; then
  printf 'FAIL: the check did not produce the verdict these histories should produce. Its result against the real spec means nothing until this is green.\n' >&2
  exit 1
fi
printf 'PASS: a recorded classification is green, the same history minus its row is red on all four assertions, a reworded requirement is not demanded, an in-place rewrite is REPORTED with and without its `Refined` row and asserts nothing where there is no rewrite at all, and a one-commit history, a counter-only commit and a shallow clone are each refused rather than passed.\n'
