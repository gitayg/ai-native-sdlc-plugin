#!/usr/bin/env bash
# scaffold.sh <template> <destination>
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
# Exit codes:
#   0  written
#   1  refused: destination exists, or the spec path is not committable
#   2  usage
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: scaffold.sh <template> <destination>" >&2; exit 2; }
src=$1; dst=$2
[ -f "$src" ] || { echo "scaffold: no template at $src" >&2; exit 2; }

if [ -e "$dst" ]; then
  echo "scaffold: $dst exists. Refusing to overwrite — scaffolding never replaces work." >&2
  exit 1
fi

# .claude/ is routinely gitignored, and a spec that cannot be committed is not
# an audit trail. Check before writing, not after.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git check-ignore -q "$dst" 2>/dev/null; then
    echo "scaffold: $dst is gitignored, so it could never be committed." >&2
    echo "  Fix .gitignore first — an untracked spec is a chain with a hole in it." >&2
    echo "  git check-ignore -v $dst" >&2
    exit 1
  fi
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
