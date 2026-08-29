#!/usr/bin/env bash
# spec-diff.sh [repo-root] [--base REF] [--format text|prompt]
#
# The living spec keeps every requirement id for ever, and a superseded or
# withdrawn requirement keeps its original sentence in place. That invariant is
# what makes the spec a record rather than a snapshot - and it is also what
# hides a removal from Stage 3. Handed only the current spec, the Build stage
# reads a document the existing code already satisfies, finds nothing to do,
# and the dropped behaviour survives in the code.
#
# So Build is handed the spec *and* how the spec moved. This assembles the
# second half: the diff of the living spec and the constitution between a base
# ref and HEAD, fenced so it can be pasted into the Build prompt, followed by
# the instruction to reconcile the code with the change rather than with the
# current text.
#
# Nothing here is rendered as an empty success. "The spec did not change", "the
# file is new and has no baseline" and "the base ref does not resolve" are three
# different answers leading to three different actions; an empty diff would read
# as the first one in all three cases, so each has its own message and its own
# exit code.
#
# Exit: 0 a diff was emitted
#       2 usage
#       3 not a git repository, or no such directory
#       4 the files are unchanged against the base - nothing to reconcile
#       5 no baseline - no commits, or the files are new / absent at the base
#       6 the base ref does not resolve
#       7 the diff exceeds the cap; the run must work from the spec alone
set -euo pipefail

# A spec edit is small. Anything larger is not a spec edit, and a truncated diff
# pasted into a prompt is worse than no diff at all - it reads as complete. Same
# order of magnitude as the AI Unified Process workflow this is adapted from.
DIFF_MAX_CHARS=20000

ROOT=""
BASE=""
FORMAT=text
while [ $# -gt 0 ]; do
  case "$1" in
    --base)     BASE="${2:-}"; [ -n "$BASE" ] || { echo "spec-diff: --base needs a ref" >&2; exit 2; }; shift 2 ;;
    --base=*)   BASE="${1#--base=}"; [ -n "$BASE" ] || { echo "spec-diff: --base needs a ref" >&2; exit 2; }; shift ;;
    --format)   FORMAT="${2:-}"; [ -n "$FORMAT" ] || { echo "spec-diff: --format needs text or prompt" >&2; exit 2; }; shift 2 ;;
    --format=*) FORMAT="${1#--format=}"; shift ;;
    -h|--help)  echo "usage: spec-diff.sh [repo-root] [--base REF] [--format text|prompt]"; exit 0 ;;
    -*)         echo "spec-diff: unknown option: $1" >&2; exit 2 ;;
    *)          [ -z "$ROOT" ] || { echo "spec-diff: only one repo-root" >&2; exit 2; }; ROOT="$1"; shift ;;
  esac
done
case "$FORMAT" in
  text|prompt) ;;
  *) echo "spec-diff: --format must be text or prompt, not: $FORMAT" >&2; exit 2 ;;
esac
[ -n "$ROOT" ] || ROOT="."
cd "$ROOT" || { echo "spec-diff: no such directory: $ROOT" >&2; exit 3; }
git rev-parse --is-inside-work-tree >/dev/null || { echo "spec-diff: not a git repository: $ROOT" >&2; exit 3; }

# Anchor at the repository root before any pathspec is used. `git ls-tree` and
# `git diff` resolve a pathspec against the *current directory*, not against the
# repository, so the same commit read from a subdirectory reported the spec as
# tracked nowhere - a false "absent", delivered with prose calling it a
# considered verdict. A skill script normally runs from its own directory, so
# that was the ordinary case rather than the corner one. The answer must not
# depend on where the script was invoked from, and the repo root is printed
# below so the reader can see which repository was actually read.
TOPLEVEL="$(git rev-parse --show-toplevel)"
cd "$TOPLEVEL"

SPEC=".claude/productizer/spec.md"
CONST=".claude/productizer/constitution.md"

say() { printf '%s\n' "$*"; }

# git's own stderr is kept and reprinted on the failure paths rather than
# discarded. An error and a genuine no-match look identical once hidden, and a
# base ref that failed to resolve for a reason nobody was shown is exactly the
# silent empty diff this script exists to prevent.
ERR="$(mktemp)"
trap 'rm -f "$ERR"' EXIT
show_err() { [ -s "$ERR" ] && cat "$ERR" >&2 || true; }

# --- HEAD ------------------------------------------------------------------
# Checked before the base, because a repository with no commits has no baseline
# at all and saying "the base ref does not resolve" would name the wrong cause.
if ! HEAD_SHA="$(git rev-parse --verify 'HEAD^{commit}' 2>"$ERR")"; then
  show_err
  echo "spec-diff: HEAD does not resolve - this repository has no commits, so there is no baseline to diff against." >&2
  exit 5
fi

# --- base ------------------------------------------------------------------
# The repository's own default branch, tried in the order a real clone carries
# it. A clone made with --single-branch has no origin/HEAD; a repository created
# locally has no origin at all.
BASE_SOURCE="--base"
if [ -z "$BASE" ]; then
  BASE_SOURCE="default branch"
  for cand in "$(git symbolic-ref --short refs/remotes/origin/HEAD 2>"$ERR" || true)" \
              origin/main origin/master main master; do
    [ -n "$cand" ] || continue
    if git rev-parse --verify "$cand^{commit}" >/dev/null 2>"$ERR"; then BASE="$cand"; break; fi
  done
  if [ -z "$BASE" ]; then
    show_err
    echo "spec-diff: no default branch resolves (tried origin/HEAD, origin/main, origin/master, main, master)." >&2
    echo "spec-diff: pass --base REF. Falling back to an empty diff would report 'no changes', which is a different and untrue answer." >&2
    exit 6
  fi
fi
if ! BASE_SHA="$(git rev-parse --verify "$BASE^{commit}" 2>"$ERR")"; then
  show_err
  echo "spec-diff: the base ref does not resolve: $BASE" >&2
  echo "spec-diff: not falling back to an empty diff - that would report 'no changes', which is a different and untrue answer." >&2
  exit 6
fi
# TZ-pinned. The same repository read in two timezones must produce the same
# text, or two runs of the same stage disagree over a date that did not move.
BASE_DATE="$(TZ=UTC git show -s --date=format-local:'%Y-%m-%d %H:%M' --format='%ad' "$BASE_SHA")"

# --- fencing ---------------------------------------------------------------
# Tildes, not backticks: the spec is Markdown and may carry backtick fences of
# its own. Every line of `git diff` output is prefixed by a diff marker - a
# space, +, -, \, or a header word - so no line of the payload can begin with a
# tilde and close the block early. That is argued rather than measured, so the
# width is measured too: one tilde wider than the longest run of leading tildes
# anywhere in the payload. The opening fence then carries a marker derived from
# HEAD's commit id, the same trick the AI Unified Process workflow uses, so the
# block stays identifiable after it is pasted into a larger prompt.
fence_for() { # fence_for <payload> -> a tilde run no payload line can match
  local widest width
  widest="$(awk '{ n = 0; while (substr($0, n + 1, 1) == "~") n++; if (n > m) m = n } END { print m + 0 }' <<<"$1")"
  width=$((widest + 1))
  [ "$width" -ge 3 ] || width=3
  printf '%*s' "$width" '' | tr ' ' '~'
}

# --- per file --------------------------------------------------------------
# 0 emitted · 4 unchanged · 5 no baseline · 7 over the cap. The run's exit is
# the strongest of the per-file outcomes, in that order: one real diff is worth
# emitting even if the other file is new.
RESULT=4
rank() { case "$1" in 0) echo 3 ;; 7) echo 2 ;; 5) echo 1 ;; *) echo 0 ;; esac; }
record() { [ "$(rank "$1")" -gt "$(rank "$RESULT")" ] && RESULT="$1" || true; }

emit_file() { # emit_file <path>
  local path="$1" at_base at_head diff fence
  at_base="$(git ls-tree -r --name-only "$BASE_SHA" -- "$path")"
  at_head="$(git ls-tree -r --name-only "$HEAD_SHA" -- "$path")"

  if [ -z "$at_base" ] && [ -z "$at_head" ]; then
    say "### \`$path\` - absent"
    say ""
    say "The file is tracked at neither \`$BASE\` nor HEAD. There is nothing to diff, and this is not a spec that did not change."
    say ""
    record 5
    return 0
  fi

  if [ -z "$at_base" ]; then
    say "### \`$path\` - new, no baseline"
    say ""
    say "The file does not exist at \`$BASE\` ($BASE_SOURCE), so it has no history to diff against and every line of it is an addition. No diff is fenced below: it would be the file itself, which the Build stage already has. Nothing was removed, because there was nothing there to remove."
    say ""
    record 5
    return 0
  fi

  diff="$(git diff "$BASE_SHA" "$HEAD_SHA" -- "$path")"

  if [ -z "$diff" ]; then
    say "### \`$path\` - unchanged"
    say ""
    say "The file is identical at \`$BASE\` and HEAD. There is no change to reconcile against - this is a measured absence of change, not a missing baseline."
    say ""
    return 0
  fi

  if [ "${#diff}" -gt "$DIFF_MAX_CHARS" ]; then
    say "### \`$path\` - diff too large"
    say ""
    say "The diff against \`$BASE\` is ${#diff} characters, over the $DIFF_MAX_CHARS cap, and is **not included**. It is not truncated either: a cut-off diff reads as a complete one, and the Build stage would treat everything past the cut as unchanged. This run must work from the spec alone, and a removal made in this range will not be visible to it."
    say ""
    record 7
    return 0
  fi

  fence="$(fence_for "$diff")"
  say "### \`$path\` - changed against \`$BASE\`"
  say ""
  say "Diff of \`$path\` between \`$BASE\` ($BASE_SOURCE, ${BASE_SHA:0:12}, $BASE_DATE UTC) and HEAD (${HEAD_SHA:0:12}):"
  say ""
  say "${fence}diff PRODUCTIZER-SPEC-DIFF-$HEAD_SHA"
  printf '%s\n' "$diff"
  say "$fence"
  say ""
  record 0
}

# --- output ----------------------------------------------------------------
if [ "$FORMAT" = text ]; then
  say "# Spec diff - \`$BASE\` to HEAD"
  say ""
  say "Repo: $TOPLEVEL"
  say "Base: \`$BASE\` ($BASE_SOURCE) at ${BASE_SHA:0:12}, committed $BASE_DATE UTC"
  say "Head: ${HEAD_SHA:0:12}"
  say "Cap: $DIFF_MAX_CHARS characters per file"
  say ""
fi

emit_file "$SPEC"
emit_file "$CONST"

if [ "$RESULT" = 0 ]; then
  say "### Reconcile against the change, not the current text"
  say ""
  say "Reconcile the result with every change in the diff above, not only with the current text of the specification. A requirement that was removed, marked \`Superseded by R<n>.\` or marked \`Withdrawn.\` means the behaviour it described was dropped deliberately: delete the code and the tests that exist only for that behaviour."
  say ""
  say "Requirement ids are permanent and are never reused or renumbered, so an id that leaves the active set is a supersession to act on, never a renumbering to ignore. A superseded requirement keeps its original sentence in place, so the current spec cannot tell you it changed - this diff is the only place that says so."
  say ""
fi

if [ "$FORMAT" = text ]; then
  say "---"
  case "$RESULT" in
    0) say "Read from \`git diff\`. A file that did not change says so rather than being drawn as an empty diff." ;;
    4) say "Nothing changed in either file against \`$BASE\`. This is a measured result, not a missing baseline: the files were read at both ends and are identical." ;;
    5) say "At least one file has no baseline at \`$BASE\`. That is not the same as no changes, and it is not reported as one." ;;
    7) say "At least one diff was over the cap and was left out whole. The Build stage must be told it is working from the spec alone." ;;
  esac
fi

exit "$RESULT"
