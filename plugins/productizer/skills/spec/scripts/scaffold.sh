#!/usr/bin/env bash
# scaffold.sh [--dry-run] <template> <destination>
#
# Copies one of this skill's templates into a repo, with the worked examples
# removed and without ever overwriting a file that already exists.
#
# The templates carry worked examples so a human can read them and see the
# shape. Those examples are numbered — R1…R6 in the spec, P1…P5 in the
# constitution — and copying them verbatim seeds a repo with requirements and
# principles nobody agreed to. The skill's own prose forbids exactly that:
# "An empty spec is the correct starting state"; "Do not seed invented
# principles at scaffold time." An end-to-end run found that a plain `cp` did
# it anyway, which is why this is a script and not a sentence.
#
# --dry-run runs every check and reports what would be written, and writes
# nothing. `init.sh --dry-run` delegates to it, so a dry run exercises these
# refusals rather than a second copy of them that can drift.
#
# Exit codes:
#   0  written (under --dry-run: would be written)
#   1  refused: destination exists, the destination is not committable, or git
#      could not answer whether it is
#   2  usage
set -euo pipefail

DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi

[ $# -eq 2 ] || { echo "usage: scaffold.sh [--dry-run] <template> <destination>" >&2; exit 2; }
src=$1; dst=$2
[ -f "$src" ] || { echo "scaffold: no template at $src" >&2; exit 2; }

if [ -e "$dst" ]; then
  echo "scaffold: $dst exists. Refusing to overwrite — scaffolding never replaces work." >&2
  exit 1
fi

# .claude/ is routinely gitignored, and a spec that cannot be committed is not
# an audit trail. Check before writing, not after.
#
# Two measured facts shape this, and both were wrong in an earlier version:
#
#   * The verdict comes from BARE `git check-ignore`, never from `-v`. With -v
#     git exits 0 when any pattern matches — including a NEGATION. On a repo
#     using the correct remediation (`.claude/*` plus `!.claude/productizer/`),
#     `check-ignore -v` exits 0 and the bare form exits 1; only the bare form
#     is the answer to "is this ignored". Measured on git 2.50.1: the -v form
#     printed `!.claude/productizer/**` and exited 0 for a file `git add`
#     staged without complaint. -v is used only to explain a real refusal.
#   * stderr is captured, never discarded. check-ignore exits 0 ignored,
#     1 not ignored, and 128 for "I cannot tell you" — a corrupt index, an
#     unreadable .gitignore, a permission problem. Sending that to /dev/null
#     made 128 indistinguishable from 1, so the one case where the check did
#     not run reported as the case where it ran and passed, and the file was
#     written anyway.
in_tree=0
if git_probe=$(git rev-parse --is-inside-work-tree 2>&1); then
  [ "$git_probe" = "true" ] && in_tree=1
fi

if [ "$in_tree" -eq 1 ]; then
  if ignore_out=$(git check-ignore -- "$dst" 2>&1); then
    rule=$(git check-ignore -v -- "$dst" 2>&1 || true)
    echo "scaffold: $dst is gitignored, so it could never be committed." >&2
    echo "  matched by: ${rule:-$ignore_out}" >&2
    echo "  Fix .gitignore first — an untracked spec is a chain with a hole in it." >&2
    exit 1
  else
    rc=$?
    if [ "$rc" -ne 1 ]; then
      echo "scaffold: git check-ignore could not answer for $dst (exit $rc)." >&2
      echo "  ${ignore_out:-(git said nothing)}" >&2
      echo "  Refusing rather than writing a file that may never be trackable." >&2
      exit 1
    fi
  fi
fi

if [ "$DRY" -eq 1 ]; then
  python3 - "$src" "$dst" <<'PY'
import io, re, sys
src, dst = sys.argv[1], sys.argv[2]
s = io.open(src, encoding="utf-8").read()
n = len(re.findall(r'<!-- EXAMPLE:BEGIN.*?EXAMPLE:END -->\n', s, flags=re.S))
print("scaffold: would write %s (%d example block%s would be removed)"
      % (dst, n, "" if n == 1 else "s"))
PY
  exit 0
fi

mkdir -p "$(dirname "$dst")"
python3 - "$src" "$dst" <<'PY'
import io, re, sys
src, dst = sys.argv[1], sys.argv[2]
s = io.open(src, encoding="utf-8").read()
out, n = re.subn(r'<!-- EXAMPLE:BEGIN.*?EXAMPLE:END -->\n', '', s, flags=re.S)
io.open(dst, "w", encoding="utf-8").write(out)
print("scaffold: wrote %s (%d example block%s removed)" % (dst, n, "" if n == 1 else "s"))
PY
