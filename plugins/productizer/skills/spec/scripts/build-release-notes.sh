#!/usr/bin/env bash
# build-release-notes.sh [repo-root] [--since TAG] [--version VERSION]
#
# Stage 8 says release notes are drafted from the spec deltas and the merged
# PRs, not from memory. This assembles the evidence for that draft and states
# plainly which of those sources was actually available - because "drafted from
# the spec" and "drafted from the commit subjects because there is no spec" are
# different claims, and only one of them is usually true.
#
# It does NOT write the prose. It produces the material a person or an agent
# writes from, with every item carrying its source. Anything it could not find
# is named as missing rather than quietly omitted, so the writer knows what
# they are working without.
#
# Exit: 0 assembled · 2 usage · 3 not a git repo
set -euo pipefail

ROOT="."; SINCE=""; VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since)   SINCE="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: build-release-notes.sh [repo-root] [--since TAG] [--version V]"; exit 0 ;;
    *)         ROOT="$1"; shift ;;
  esac
done
cd "$ROOT" || { echo "no such directory: $ROOT" >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null || { echo "not a git repository: $ROOT" >&2; exit 3; }

# `git describe` writes `fatal: No names found, cannot describe anything.` when the repo has no
# tags at all - normal before a first release. Ask whether a tag exists first, so describe only
# runs when it can succeed and a failure it does report (tags present, none reachable from HEAD)
# is a real one worth reading.
if [ -z "$SINCE" ] && [ -n "$(git tag -l)" ]; then
  SINCE="$(git describe --tags --abbrev=0 || echo "")"
fi
RANGE="${SINCE:+$SINCE..}HEAD"
SPEC=".claude/productizer/spec.md"

say() { printf '%s\n' "$*"; }

say "# Release notes — evidence"
say ""
say "Range: \`${RANGE}\`${SINCE:+  (since $SINCE)}"
[ -n "$VERSION" ] && say "Version: \`$VERSION\`"
say ""

# --- source 1: the spec ------------------------------------------------------
say "## Spec deltas"
say ""
if [ ! -f "$SPEC" ]; then
  say "**None. There is no living spec at \`$SPEC\`.**"
  say ""
  say "Stage 8 says notes are drafted from the spec deltas. Without a spec there"
  say "are none, so anything written here is drawn from commit subjects instead."
  say "That is a weaker source and the draft should say so rather than implying"
  say "the requirements were consulted."
else
  # Requirement ids touched in this range, from the spec's own diff.
  ids="$(git log "$RANGE" -p -- "$SPEC" \
        | grep -E '^\+.*\*\*R[0-9]+\*\*' | grep -oE 'R[0-9]+' | sort -u -V || true)"
  if [ -z "$ids" ]; then
    say "The spec exists but no requirement changed in this range."
  else
    say "Requirement ids added or changed in this range:"
    say ""
    printf '%s\n' "$ids" | sed 's/^/  - /'
  fi
fi
say ""

# --- source 2: merged PRs ----------------------------------------------------
say "## Merged pull requests"
say ""
if ! command -v gh >/dev/null 2>&1; then
  say "**Unknown — \`gh\` is not installed, so no PR could be read.**"
  say "This is not the same as \"no PRs merged\"; nobody looked."
else
  # Without this, a gh auth or network failure came back empty and the branch below announced
  # "None found ... nothing was merged through a PR", which is an absence that was not an absence.
  prs="$(gh pr list --state merged --limit 50 --json number,title,mergedAt \
         --jq '.[] | "  - #\(.number) \(.title)"' || true)"
  if [ -z "$prs" ]; then
    say "**None found.** Either nothing was merged through a PR in this range, or"
    say "the work went straight to the branch. If it went straight to the branch,"
    say "the notes have no PR to trace a claim to and should say so."
  else
    printf '%s\n' "$prs"
  fi
fi
say ""

# --- source 3: the commits ---------------------------------------------------
say "## Commits in range"
say ""
n="$(git log --oneline "$RANGE" | wc -l | tr -d ' ')"
if [ "$n" = "0" ]; then
  say "**None.** \`$RANGE\` is empty — there is nothing to release."
else
  say "$n commit(s):"
  say ""
  git log "$RANGE" --pretty=format:'  - %s  (`%h`)'
  say ""
  say ""
  say "### Files changed"
  say ""
  say '```'
  git diff --stat "$RANGE" | tail -20
  say '```'
fi
say ""

# --- the checklist the writer must not skip ---------------------------------
say "## Before this becomes a post"
say ""
say "Each line is a \`no\` that stops it, not a comment."
say ""
say "- [ ] Every claim traces to a commit, a merged PR, or a requirement id above."
say "- [ ] Every number was measured, and the measurement is stated."
say "- [ ] Every screenshot came from THIS version's build."
say "- [ ] The version named is live and installable, and that was verified."
say "- [ ] No customer, repo, internal hostname or employer name appears anywhere."
say "- [ ] The release names what it does NOT do."
say "- [ ] Names and bylines of anyone credited are correct."
say ""
say "Where a source above says **none** or **unknown**, the draft says so too."
say "A note written from commit subjects while implying it was written from the"
say "spec is the kind of claim this lifecycle exists to prevent."
