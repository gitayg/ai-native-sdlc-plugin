#!/usr/bin/env bash
# merge-checks-result.sh — the git merge driver for the checks result file.
#
# THE PROBLEM IT EXISTS FOR.
#
# `.claude/productizer/checks-result.json` is written by `run-checks.sh` and
# committed, because `build-view.sh` reads it out of the repository so the
# dashboard renders offline from a fresh clone. Any two branches that both ran
# the suite therefore differ in it, and every merge of the two conflicts.
#
# The conflict is not merely noisy. The ordinary resolutions are all wrong:
#
#   take ours    records a run whose `change.files` names one side's files,
#                against a tree that also carries the other side's
#   take theirs  the same lie, mirrored
#   hand-edit    a result nobody measured, assembled from two that were
#
# Every one of them writes a measurement that was never taken, which is P1 —
# "a value that was not measured is never recorded as a measurement" — broken
# with a merge tool holding the pen. So the only correct resolution is to
# MEASURE THE MERGED TREE, and that is what this driver does.
#
# WHEN IT REFUSES, IT REFUSES LOUDLY.
#
# A driver that cannot measure has exactly one honest move: leave a real
# conflict for a human. It never falls back to a side. Refusing is the
# designed behaviour of this script and not a fault in it — the fault would
# be resolving to a number nobody took. Every refusal writes the ordinary
# conflict markers into the result path (so `git status` and the file agree
# that it is unresolved), names its reason on stderr, and exits 1.
#
# WHAT IT DOES, IN ORDER. Each step can only refuse, never guess:
#
#   1. Refuse re-entry. `git merge-tree` below honours merge drivers, so
#      without a guard this script would invoke itself.
#   2. Refuse unless the repository has been trusted (see P4, below).
#   3. Name the three sides of the merge and PROVE each one, by hashing the
#      blob it holds at this path and requiring it to equal the temp file git
#      handed over. A side that does not verify is not used.
#   4. Rebuild the merged tree with `git merge-tree`, off the proven base.
#   5. Refuse if anything OTHER than this file conflicted. A human is about to
#      edit those, so the tree measured here would not be the tree committed.
#   6. Materialise that tree as a real git work tree and run the real suite in
#      it. Nothing is copied from either input.
#   7. Move the result into place only once it is written and parses.
#
# P4 — A REPOSITORY BEING EXAMINED NEVER CHOOSES WHAT RUNS.
#
# This is the sharp edge, and it is worth stating plainly rather than burying.
# A merge driver runs while merging somebody else's branch, and the suite it
# runs is selected by `.claude/productizer/checks.yaml` FROM THE MERGED TREE,
# whose check scripts also come from the merged tree. This repository's config
# sets `allow_repo_local_tools: true`, so those scripts do execute. A merge of
# a hostile branch would therefore run the hostile branch's check scripts.
#
# That is not fixable from inside this script: measuring the merged tree means
# running the merged tree's tooling, and the two cannot be separated. So the
# decision is made explicit and local instead, exactly as
# `allow_repo_local_tools` makes it explicit and committed:
#
#   git config merge.productizer-checks-result.trustrepo true
#
# Unset, this driver refuses every merge. The flag lives in `.git/config`,
# which no branch can write, so the repository being merged cannot grant
# itself the trust. Set it on your own repository and nowhere else. Merging an
# untrusted branch of a repository you have trusted still runs that branch's
# code — trust the repository, and read the diff, as you would before running
# its test suite.
#
# THE DRIVER IS NOT ACTIVE UNTIL SOMEONE CONFIGURES IT LOCALLY.
#
# `.gitattributes` names the driver; it cannot define it. `merge.<name>.driver`
# is local config, and a fresh clone has none — by design, since otherwise a
# cloned repository would choose a program to run on the machine that cloned
# it. So a fresh clone gets the ORDINARY CONFLICT, and that is the safe
# failure: nothing silently resolves. What is dangerous is believing the driver
# is active when it is not, so `--status` reports what git actually sees.
#
# USAGE. Git calls it through the configured driver line, never by hand:
#
#   merge-checks-result.sh %O %A %B %L %P %X %Y
#
#   %O  ancestor's version         %L  conflict marker size
#   %A  our version — THE OUTPUT   %P  the pathname in the work tree
#   %B  their version              %X %Y  labels for our/their side
#
# Exit: 0 resolved, and the file was measured · 1 unresolved, with markers
# written and a reason on stderr · 0 for --version, --help and --status.
set -euo pipefail

VERSION='merge-checks-result 1.0'

# Fixed, because it is half of the config keys this script reads and half of
# the one line in `.gitattributes`. Renaming the driver in `.gitattributes`
# without renaming it here makes the lookups miss, which refuses. Fail-closed
# is the right direction for that mistake.
DRIVER_NAME='productizer-checks-result'
RESULT_REL='.claude/productizer/checks-result.json'

usage() {
  cat <<EOF
$VERSION — git merge driver for $RESULT_REL

Resolves the checks result file by RE-MEASURING the merged tree, never by
picking a side. Refuses, with ordinary conflict markers and a reason, whenever
it cannot measure. Git invokes it; you do not.

  --version   print the version and exit 0
  --help      print this and exit 0
  --status    report whether git can actually see the driver here, and exit 0

Activate it in a clone (both lines; neither is inherited by a fresh clone):

  git config merge.$DRIVER_NAME.driver \\
    '<repo>/plugins/productizer/skills/spec/scripts/merge-checks-result.sh %O %A %B %L %P %X %Y'
  git config merge.$DRIVER_NAME.trustrepo true

Config keys read, both local and both deliberately not committable:

  merge.$DRIVER_NAME.trustrepo   must be true, or every merge refuses
  merge.$DRIVER_NAME.runner      path to run-checks.sh; defaults to the copy
                                 beside this script
EOF
}

case "${1:-}" in
  --version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) usage; exit 0 ;;
  --status)
    printf '%s\n' "$VERSION"
    # Each lookup answers "is it set", so a miss is the answer and not an
    # error. `|| :` keeps `set -e` from killing the report on the very state
    # the report exists to describe: unconfigured.
    d="$(git config --get "merge.$DRIVER_NAME.driver" || :)"
    t="$(git config --get "merge.$DRIVER_NAME.trustrepo" || :)"
    r="$(git config --get "merge.$DRIVER_NAME.runner" || :)"
    printf 'merge.%s.driver    : %s\n' "$DRIVER_NAME" "${d:-<unset> — THE DRIVER IS NOT ACTIVE; merges take the ordinary conflict}"
    printf 'merge.%s.trustrepo : %s\n' "$DRIVER_NAME" "${t:-<unset> — every merge will refuse}"
    printf 'merge.%s.runner    : %s\n' "$DRIVER_NAME" "${r:-<unset> — defaults to run-checks.sh beside this script}"
    exit 0 ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Refusing
# ---------------------------------------------------------------------------
# The result of a refusal is not "leave %A alone". Git uses whatever is in %A
# whatever the exit status, and %A arrives holding OUR side verbatim — so a
# driver that exits 1 without touching it leaves a file that is marked
# unresolved and reads as perfectly clean. Somebody stages it, and the merge
# commits our side's numbers over the merged tree: the exact fabrication this
# driver exists to stop, now wearing a conflict flag nobody can see in the
# text. So every refusal writes the ordinary three-way markers first.
ARG_O=''; ARG_A=''; ARG_B=''; ARG_L='7'

write_conflict() {
  [ -n "$ARG_A" ] && [ -f "$ARG_A" ] || return 0
  [ -n "$ARG_O" ] && [ -n "$ARG_B" ] || return 0
  local rc=0
  # git merge-file exits with the NUMBER OF CONFLICTS it left, so a non-zero
  # status here is the expected outcome and not an error. Only >=128 is a real
  # failure. Without this the `set -e` would kill the refusal path halfway,
  # leaving the clean-looking %A described above.
  git merge-file --marker-size="$ARG_L" \
    -L 'ours (this branch)' -L 'base (common ancestor)' -L 'theirs (incoming)' \
    "$ARG_A" "$ARG_O" "$ARG_B" >&2 || rc=$?
  if [ "$rc" -ge 128 ]; then
    printf 'merge-checks-result: could not even write conflict markers into %s (git merge-file exit %d).\n' \
      "$ARG_A" "$rc" >&2
  fi
  return 0
}

refuse() {
  printf 'merge-checks-result: REFUSED — %s\n' "$1" >&2
  write_conflict
  cat >&2 <<EOF
merge-checks-result: $RESULT_REL is left CONFLICTED on purpose.
merge-checks-result: do NOT resolve it by choosing a side or by editing the
merge-checks-result: markers — either records a run that never happened.
merge-checks-result: finish the rest of the merge, then regenerate it:
merge-checks-result:
merge-checks-result:   git checkout --ours -- $RESULT_REL
merge-checks-result:   <run the checks suite over the merged tree>
merge-checks-result:   git add $RESULT_REL
EOF
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Re-entry
# ---------------------------------------------------------------------------
# `git merge-tree` below performs a real content merge, and a real content
# merge honours merge drivers — measured, not assumed: a probe driver logged
# its own arguments from inside a merge-tree call. Unguarded, step 4 would
# call this script, which would call merge-tree, without end. The inner call
# refusing is exactly right: it leaves this one path conflicted in the
# rebuilt tree, which step 5 expects and ignores.
if [ -n "${PRODUCTIZER_MERGE_CHECKS_RESULT:-}" ]; then
  ARG_O="${1:-}"; ARG_A="${2:-}"; ARG_B="${3:-}"; ARG_L="${4:-7}"
  refuse "re-entered from the driver's own merge-tree call; the outer run owns this merge"
fi

# ---------------------------------------------------------------------------
# 2. Arguments
# ---------------------------------------------------------------------------
# Bound early so that any refusal from here on can still write markers.
ARG_O="${1:-}"; ARG_A="${2:-}"; ARG_B="${3:-}"; ARG_L="${4:-7}"
ARG_P="${5:-}"; ARG_X="${6:-}"; ARG_Y="${7:-}"

case "$ARG_L" in
  ''|*[!0-9]*) ARG_L=7 ;;
esac

if [ "$#" -ne 7 ]; then
  refuse "expected 7 arguments (%O %A %B %L %P %X %Y), got $#. Fix the driver line: see --help"
fi
[ -f "$ARG_A" ] || refuse "the output path %A ($ARG_A) is not a file"
[ -f "$ARG_O" ] || refuse "no common ancestor version was supplied; this driver cannot measure a merge it cannot base"
[ -f "$ARG_B" ] || refuse "the incoming version %B ($ARG_B) is not a file"
[ -n "$ARG_P" ] || refuse "git supplied no pathname (%P)"

# ---------------------------------------------------------------------------
# 3. Trust, and the work tree
# ---------------------------------------------------------------------------
ROOT="$(git rev-parse --show-toplevel || :)"
[ -n "$ROOT" ] || refuse "not inside a git work tree"

# `--get` exits 1 when the key is unset, which is an answer, not a failure.
TRUST="$(git config --bool --get "merge.$DRIVER_NAME.trustrepo" || :)"
if [ "$TRUST" != 'true' ]; then
  refuse "this repository has not been trusted. Measuring the merged tree runs
merge-checks-result:            that tree's check scripts, and the branch being merged wrote them
merge-checks-result:            (P4). Grant it, for your own repository only, with:
merge-checks-result:              git config merge.$DRIVER_NAME.trustrepo true"
fi

RUNNER="$(git config --get "merge.$DRIVER_NAME.runner" || :)"
# Where this script sits inside the repository, so the runner can be taken
# from the MEASURED tree at the same place rather than from this checkout.
# Measured: running the checkout's runner against the temp tree made several
# checks report paths relative to the runner's own skill directory - so the
# same tree measured twice produced `scripts/run-checks.sh` one way and
# `plugins/productizer/skills/spec/scripts/run-checks.sh` the other. Two trees
# in one run is not a measurement of either.
HERE_REL="${HERE#"$ROOT"/}"

# ---------------------------------------------------------------------------
# 4. Name the three sides, and prove each one
# ---------------------------------------------------------------------------
# %X and %Y are CONFLICT LABELS, and git makes no promise that either is a
# revision. Measured across the three operations that hurt here:
#
#   git merge        %X=HEAD  %Y=feat-b                    both are revisions
#   git cherry-pick  %X=HEAD  %Y=da15df2 (branch B)        a sentence
#   git rebase       %X=HEAD  %Y=da15df2 (branch B)        a sentence
#
# So the leading token is taken as a CANDIDATE and then proved: the blob that
# candidate holds at this path must hash to exactly the temp file git handed
# over. A candidate that does not verify is discarded and the merge refuses.
# The label is never trusted, only tested — which is the same rule P4 applies
# to everything else a repository says.
first_token() { printf '%s\n' "${1%% *}"; }

blob_matches() {  # <rev> <path> <expected-file>
  local rev="$1" path="$2" want="$3" got
  want="$(git hash-object -- "$want")"
  # `git rev-parse <rev>:<path>` exits non-zero when the path is absent in that
  # revision, which is an ordinary answer here — a file added on one side only.
  got="$(git rev-parse --verify -q "$rev:$path" || :)"
  [ -n "$got" ] && [ "$got" = "$want" ]
}

resolve_side() {  # <label> <expected-file>
  local label="$1" want="$2" cand rev
  cand="$(first_token "$label")"
  [ -n "$cand" ] || return 1
  rev="$(git rev-parse --verify -q "$cand^{commit}" || :)"
  [ -n "$rev" ] || return 1
  blob_matches "$rev" "$ARG_P" "$want" || return 1
  printf '%s\n' "$rev"
}

OURS="$(resolve_side "$ARG_X" "$ARG_A" || :)"
[ -n "$OURS" ] || refuse "could not identify and verify our side of the merge from the label %X=\"$ARG_X\""

THEIRS="$(resolve_side "$ARG_Y" "$ARG_B" || :)"
[ -n "$THEIRS" ] || refuse "could not identify and verify the incoming side from the label %Y=\"$ARG_Y\". \
During a rebase or cherry-pick git passes a sentence here, not a revision, and this one did not resolve to a commit \
holding the exact bytes of %B"

# The base has to be the base the operation is actually using. A merge's is
# merge-base(ours, theirs); a cherry-pick's or rebase's is the PARENT of the
# commit being applied, and using the merge-base there rebuilds a different
# tree than the one being committed. Both candidates are tried and the one
# whose blob equals %O wins; if neither does, the base is unknown and the
# driver refuses rather than measure a tree assembled off the wrong ancestor.
BASE=''
for cand in "$(git merge-base "$OURS" "$THEIRS" || :)" "$(git rev-parse --verify -q "$THEIRS^" || :)"; do
  [ -n "$cand" ] || continue
  if blob_matches "$cand" "$ARG_P" "$ARG_O"; then BASE="$cand"; break; fi
done
[ -n "$BASE" ] || refuse "could not identify the common ancestor this merge is using; neither the merge base of the two sides nor the parent of the incoming commit holds the bytes git supplied as %O"

# ---------------------------------------------------------------------------
# 5. Rebuild the merged tree, and refuse if a human still has to touch it
# ---------------------------------------------------------------------------
# Scratch space, opened here because merge-tree's output has to land in a FILE.
# `-z` separates its sections with NUL bytes and a command substitution drops
# NUL bytes outright — bash even says so — which silently collapsed the two
# sections into one and made the tree unparseable on the first run of this.
# `pwd -P` because the path has to be the PHYSICAL one. On macOS $TMPDIR sits
# under /var, which is a symlink to /private/var, and the checks normalise
# their root with `pwd -P` before stripping it off the paths they report. Hand
# them the symlinked spelling and the strip silently misses: measured, the same
# merged tree reported `scripts/run-checks.sh` instead of
# `plugins/productizer/skills/spec/scripts/run-checks.sh`, and one check wrote
# the temp directory's ABSOLUTE path into the result — a machine-specific path
# in a file that is then committed to a public repository.
TMPDIR_D="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/merge-checks-result.XXXXXX")" && pwd -P)"
WT=''

cleanup() {
  # Best effort, and it must not disturb the exit status of the merge itself.
  [ -n "$WT" ] && [ -d "$WT" ] && git worktree remove --force "$WT" >&2 || :
  rm -rf "$TMPDIR_D" || :
  git worktree prune || :
}
trap cleanup EXIT

MT_OUT="$TMPDIR_D/merge-tree.out"
MT_RC=0
PRODUCTIZER_MERGE_CHECKS_RESULT=1 \
  git merge-tree -z --write-tree --merge-base="$BASE" "$OURS" "$THEIRS" > "$MT_OUT" || MT_RC=$?
# merge-tree exits 1 when the merge conflicted — which it certainly did, since
# this driver is running because of a conflict — and >1 only on a real error.
if [ "$MT_RC" -gt 1 ]; then
  refuse "could not rebuild the merged tree (git merge-tree exit $MT_RC)"
fi

MERGED_TREE="$(tr '\0' '\n' < "$MT_OUT" | sed -n '1p')"
git rev-parse --verify -q "$MERGED_TREE^{tree}" > /dev/null \
  || refuse "git merge-tree did not name a tree"

# Every unmerged index entry merge-tree reported, matched by SHAPE:
# `<6-digit mode> <sha> <stage 1-3><tab><path>`. Any path here other than this
# one is a conflict a person is about to resolve by hand — so the tree just
# rebuilt is NOT the tree that will be committed, and measuring it would
# record a result for a tree that never existed. That is the same fabrication
# as picking a side, so it gets the same answer.
#
# Parsed with tr and grep rather than by NUL records, because BSD awk CANNOT
# split on NUL: `RS="\0"` is read as the empty string, which is awk's
# paragraph mode. Measured — `printf 'a\0b\0c\0' | awk 'BEGIN{RS="\0"}...'`
# returns ONE record here, not three. The first version of this line used that
# form, found only the first conflicted path, and let a merge that also
# conflicted in GUIDE.md resolve this file anyway. KNOWN LIMITATION: a path
# containing a newline would be split by `tr` and could be missed.
#
# The trailing `|| :` is load-bearing: grep exits 1 when it matches nothing,
# and "nothing else conflicted" is the ANSWER here, not a failure. Without it
# `set -e` plus `pipefail` would kill the driver on the successful case.
TAB="$(printf '\t')"
OTHER="$(tr '\0' '\n' < "$MT_OUT" \
  | grep -E "^[0-7]{6} [0-9a-f]{40,64} [123]$TAB" \
  | cut -f2- | sort -u | grep -v -x -F -e "$ARG_P" || :)"
if [ -n "$OTHER" ]; then
  refuse "this merge also conflicts in:
merge-checks-result:              $(printf '%s' "$OTHER" | tr '\n' ' ')
merge-checks-result:            Those need a person, so the merged tree is not settled yet and any
merge-checks-result:            measurement taken now would describe a tree nobody will commit.
merge-checks-result:            Resolve them, finish the merge, then regenerate this file."
fi

# ---------------------------------------------------------------------------
# 6. Materialise that tree and measure it
# ---------------------------------------------------------------------------
# It has to be a REAL work tree, not an unpacked archive. Measured: this repo's
# own `scripts/check-hygiene.sh` and eleven sibling wrappers begin with
# `git rev-parse --show-toplevel` and exit 2 without one, so an extracted
# directory turned twelve of twenty-six checks into refusals — a result that
# would have been recorded as the merged tree's verdict.
WT="$TMPDIR_D/tree"

# A tree cannot be checked out directly, so it is wrapped in a commit object.
# The commit is never referenced, so it is unreachable and gets collected.
MERGED_COMMIT="$(printf 'merged tree, measured by the checks merge driver\n' \
  | git commit-tree "$MERGED_TREE" -p "$OURS" -p "$THEIRS")" \
  || refuse "could not wrap the merged tree in a commit"

git worktree add --detach --no-checkout "$WT" "$MERGED_COMMIT" >&2 \
  || refuse "could not create a work tree for the merged tree at $WT"
git -C "$WT" checkout --detach "$MERGED_COMMIT" >&2 \
  || refuse "could not check the merged tree out at $WT"

# The changed set is everything the merge introduces over the ancestor, which
# is the union of both sides — a git tree diff, so it names files and never a
# directory, and there is nothing untracked in a freshly checked-out tree for
# a `git status` walk to have to expand.
#
# This path is left out on purpose. It is the OUTPUT of the run being started;
# feeding the previous run's output back in as input would make the stage
# measure itself, and inside a merge the copy sitting there is a conflict
# artefact rather than content anyone wrote.
CHANGED="$TMPDIR_D/changed.txt"
git diff --name-only "$BASE" "$MERGED_TREE" | grep -v -x -F -e "$ARG_P" > "$CHANGED" || :

CFG="$WT/.claude/productizer/checks.yaml"
[ -f "$CFG" ] || refuse "the merged tree has no $RESULT_REL config at .claude/productizer/checks.yaml"

# One tree, measured by its own runner. The config override wins when someone
# set it; otherwise the runner comes from the tree being measured, and only
# then from this checkout.
if [ -z "$RUNNER" ]; then
  if [ -n "$HERE_REL" ] && [ -f "$WT/$HERE_REL/run-checks.sh" ]; then
    RUNNER="$WT/$HERE_REL/run-checks.sh"
  else
    RUNNER="$HERE/run-checks.sh"
  fi
fi
[ -f "$RUNNER" ] || refuse "no checks runner at $RUNNER (set merge.$DRIVER_NAME.runner)"

OUT="$TMPDIR_D/result.json"
RUN_RC=0
# Run FROM the tree being measured. Measured: with the working directory left
# at the main work tree, checks that name what they examined printed the temp
# tree's ABSOLUTE path - a machine-specific path, written into a file that is
# then committed. That is the leak that shipped in v4.2.0, and this file is
# public.
( cd "$WT" && bash "$RUNNER" --config "$CFG" --root "$WT" --changed "$CHANGED" --out "$OUT" ) >&2 || RUN_RC=$?

# 0 is a pass and 3 is a considered refusal; both are real verdicts reached by
# a real run, and a merged tree that fails its checks must be recorded as
# failing them, not left unmeasured. 1 (crashed) and 2 (bad usage) reached no
# verdict at all, so there is nothing honest to write.
case "$RUN_RC" in
  0|3) : ;;
  *)   refuse "the checks suite reached no verdict on the merged tree (exit $RUN_RC); there is nothing measured to record" ;;
esac

[ -s "$OUT" ] || refuse "the checks suite wrote no result file"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$OUT" \
  || refuse "the checks suite wrote a result that is not valid JSON"

# ---------------------------------------------------------------------------
# 7. Into place, whole or not at all
# ---------------------------------------------------------------------------
# Everything above wrote to $TMPDIR_D. %A is touched exactly once, by a rename
# within the same filesystem, so no reader ever sees a half-written result and
# a failure anywhere above leaves %A holding the markers a refusal put there.
STAGED="$(dirname "$ARG_A")/.merge-checks-result.$$.tmp"
cp "$OUT" "$STAGED" || refuse "could not stage the measured result beside $ARG_A"
mv -f "$STAGED" "$ARG_A" || refuse "could not move the measured result into $ARG_A"

printf 'merge-checks-result: %s regenerated by measuring the merged tree (checks exit %d).\n' \
  "$ARG_P" "$RUN_RC" >&2
exit 0
