#!/usr/bin/env bash
# Usage: scaffold.sh [--dry-run] <template> <destination>   (see usage() below, which
# is what `--help` actually prints — this comment is not the help text and cannot
# drift out of it)
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

VERSION="scaffold 1.0"

# The help text lives in the script and is printed by the script. Before this block `--help`
# was not a flag: it fell through to the argument-count guard, which reported it as a usage
# ERROR and exited 2. A reader asking a program to describe itself was told their invocation
# was wrong, and the one line they got back did not describe --dry-run, the destination rules,
# or any of the three exit codes — all of which existed only in the header comment above,
# which `--help` never printed. A help request is not a usage error.
usage() {
  cat <<'USAGE'
scaffold.sh — copy one of this skill's templates into a repo, with the worked examples
removed, never overwriting a file that already exists.

Usage:
  scaffold.sh <template> <destination>            copy template to destination
  scaffold.sh --dry-run <template> <destination>  run every check, report, write nothing
  scaffold.sh --help | -h                         print this and exit 0
  scaffold.sh --version                           print the version and exit 0

There are no other options. --dry-run may appear anywhere among the arguments; the two
paths keep their order.

Both arguments are required and positional:
  <template>     path to a template file, e.g. templates/spec.md. Must exist.
  <destination>  path to write. Must NOT exist, and must not be gitignored.

Why this is a script and not `cp`:
  The templates carry worked examples so a human can read one and see the shape. Those
  examples are numbered — R1..R6 in the spec, P1..P5 in the constitution — and copying them
  verbatim seeds a repo with requirements and principles nobody agreed to. An end-to-end run
  found that a plain `cp` did exactly that. Every fenced EXAMPLE block is stripped on the way
  in, and the count of blocks removed is reported.

What it refuses, and why refusing is the correct outcome:
  * a destination that already exists — scaffolding never replaces work
  * a destination git says is ignored — a spec that cannot be committed is not an audit
    trail, and .claude/ is routinely gitignored
  * a destination git could not answer for — "cannot tell" is not "not ignored". Writing a
    file that may never be trackable is the worse mistake, so it refuses instead.

--dry-run:
  Runs every check above and reports what would be written, and writes nothing. `init.sh
  --dry-run` delegates to it, so a dry run exercises these refusals rather than a second
  copy of them that can drift.

Exit status:
  0  written (under --dry-run: would be written)
  1  refused: the destination exists, is not committable, or git could not say which
  2  a bad invocation: an unknown option, the wrong number of arguments, or no template
     at the given path
USAGE
}

die_usage() {
  printf 'scaffold: %s\n\n' "$1" >&2
  usage >&2
  exit 2
}

# --dry-run, then exactly two positionals. `--` ends option parsing so a path beginning with a
# dash is still scaffoldable. Anything else starting with a dash is refused BY NAME: before
# this guard an unknown flag was counted as one of the two positionals, so `--dry-runn` became
# a template path and the script reported "no template at --dry-runn" — a missing-file error
# for a flag that does not exist, which sends the reader to look for the file.
DRY=0
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)  printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help)  usage; exit 0 ;;
    --dry-run)  DRY=1; shift ;;
    --)         shift
                while [ "$#" -gt 0 ]; do ARGS+=("$1"); shift; done
                break ;;
    -*)         die_usage "unknown option: $1" ;;
    *)          ARGS+=("$1"); shift ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

[ $# -eq 2 ] || die_usage "expected <template> <destination>, got $# argument(s)"
src=$1; dst=$2
[ -f "$src" ] || die_usage "no template at $src"

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
