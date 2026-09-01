#!/usr/bin/env bash
# falsify.sh [--version] [--help] [--check PATH] [--repo DIR] [--keep]
#
# THE FALSIFICATION HARNESS FOR `check-spec-integrity.sh`. It is not a check
# and is not wired into checks.yaml: it has no coverage output and nothing in
# the lifecycle depends on it. It exists so that "each of the nine assertions
# goes red on its own" is a claim anybody can re-run in one command, instead of
# a sentence in a commit message.
#
# WHY A CLONE AND NOT A FIXTURE DIRECTORY. Every assertion this harness
# falsifies except two is a claim about GIT HISTORY, and history is the one
# thing a committed fixture directory cannot carry. A fixture spec sitting in
# a folder has no previous version, so pointing the check at it produces exit
# 2 - unmeasured - for every case, which proves nothing about the findings
# path. So each case starts from a throwaway `git clone` of the repository
# under test, mutates the clone, and runs the check against it with `--root`.
#
# THE REAL REPOSITORY IS NEVER WRITTEN TO. Every mutation lands in a temporary
# clone under $TMPDIR, removed on exit unless --keep is given. The check is run
# from wherever it lives - it is never copied into the clone - so the clone is
# only ever an input.
#
# EACH CASE NAMES THE ASSERTION KEYS IT EXPECTS TO GO RED, AND THE HARNESS
# COMPARES THE WHOLE SET. A mutation that turns everything red proves nothing
# about the assertion it was aimed at, so a case fails here if it reddens MORE
# assertions than it declared, not only if it reddens fewer. That is the whole
# reason the expected set is written out rather than a single "it failed".
#
# CASES
#
#   findings (exit 1)
#     second-living-spec        R1.3   a second file in the spec home
#     config-home-not-in-repos  R1.1   the home repo is not one of the repos
#     ids-permanent-false       R2.1   the config disclaims the invariant
#     delete-active-id          R2.2   an id present in history, gone today
#     renumber-id               R2.2   the same sentence under a new number,
#                               R2.3   which is a disappearance AND a move
#     swap-text-under-id        R2.4   a different requirement, same id
#     counter-below-used-id     R8.1   the counter would reissue a used id
#     add-unrecorded-id         R8.2   an addition with no change-log row
#
#   premises (exit 2, unmeasured, never a pass)
#     shallow-clone             a real --depth 1 clone
#     untracked-spec            the spec exists but git has never seen it
#     unreadable-spec           the spec cannot be opened
#     no-spec-at-all            the declared path does not exist
#     history-bound-exceeded    --max-versions below the number of commits
#     unparseable-config        the config is not JSON
#
#   contract
#     --version / --help exit 0, an unknown flag exits 2
#
# EXIT CODES
#
#   0  every case behaved as declared
#   1  at least one case did not - the diff is printed per case
#   2  the harness could not run: no check, no repository, no git
set -euo pipefail

VERSION="falsify 1.0"
CHECK=""
REPO=""
KEEP=""

usage() {
  printf 'usage: falsify.sh [--version] [--help] [--check PATH] [--repo DIR] [--keep]\n'
  printf '  --check PATH  the check under test. Defaults to\n'
  printf '                ../../scripts/check-spec-integrity.sh beside this file.\n'
  printf '  --repo DIR    the repository to clone for each case. Defaults to the\n'
  printf '                git top level of this file.\n'
  printf '  --keep        leave the temporary clones in place for inspection.\n'
}

die() { printf 'falsify: %s\n' "$1" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --check) [ "$#" -ge 2 ] || die "--check needs a path"; CHECK="$2"; shift 2 ;;
    --repo) [ "$#" -ge 2 ] || die "--repo needs a directory"; REPO="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -*) printf 'falsify: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'falsify: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "$0")" && pwd -P)"
[ -n "$CHECK" ] || CHECK="$HERE/../../scripts/check-spec-integrity.sh"
[ -x "$CHECK" ] || die "the check under test is not executable: $CHECK"
if [ -z "$REPO" ]; then
  REPO="$(git -C "$HERE" rev-parse --show-toplevel)" ||
    die "this file is not inside a git work tree and --repo was not given"
fi
REPO="$(cd "$REPO" && pwd -P)"
[ -d "$REPO/.git" ] || die "--repo $REPO holds no .git, so it cannot be cloned"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/falsify-spec-integrity.XXXXXX")"
cleanup() { [ -n "$KEEP" ] || rm -rf "$WORK"; }
trap cleanup EXIT HUP INT TERM

SPEC_REL=".claude/productizer/spec.md"
CONFIG_REL=".claude/productizer/config.json"
CLONE=""
OUT=""
STATUS=0
failed=0
cases=0

# A clone per case, so no mutation can leak into the next one and turn a
# passing case green for the wrong reason.
fresh() {
  CLONE="$WORK/$1"
  git clone --quiet "file://$REPO" "$CLONE" ||
    die "could not clone $REPO into $CLONE"
}

commit_clone() {
  git -C "$CLONE" add -A
  git -C "$CLONE" \
    -c user.name=falsify -c user.email=falsify@example.invalid \
    commit --quiet -m "$1"
}

run_check() {
  OUT="$WORK/$1.out"
  STATUS=0
  "$CHECK" --root "$CLONE" "${@:2}" > "$OUT" 2>&1 || STATUS=$?
}

# The assertion keys the run reported as NOT HELD, space separated and sorted.
red_keys() {
  awk '$1 ~ /^R[0-9]+\.[0-9]+$/ && /NOT HELD/ { print $1 }' "$OUT" |
    sort | tr '\n' ' ' | sed 's/ $//'
}

report() {
  local name="$1" want_exit="$2" want_red="$3" got_red
  cases=$((cases + 1))
  got_red="$(red_keys)"
  if [ "$STATUS" = "$want_exit" ] && [ "$got_red" = "$want_red" ]; then
    printf 'ok    %-26s exit %s  red: %s\n' \
      "$name" "$STATUS" "${got_red:-<none>}"
  else
    failed=$((failed + 1))
    printf 'FAIL  %-26s exit %s (wanted %s)  red: %s (wanted %s)\n' \
      "$name" "$STATUS" "$want_exit" "${got_red:-<none>}" "${want_red:-<none>}"
    sed 's/^/        | /' "$OUT"
  fi
}

# --- the baseline. An unmutated clone must be clean, or every red below is
# --- evidence about the clone rather than about the mutation.
fresh baseline
run_check baseline
report baseline 0 ""

# --- R1.3 a second file in the spec home presents itself as a living spec ---
fresh second-living-spec
cat > "$CLONE/.claude/productizer/spec-v2.md" <<'SPEC'
# A second living spec, which is exactly what R1 forbids

Next requirement id
: `R7` - allocate from here, then increment.

## Requirements

### Ubiquitous - always active

- **R6** - The service shall hold one spec.
SPEC
commit_clone "a second living spec in the spec home"
run_check second-living-spec
report second-living-spec 1 "R1.3"

# --- R1.1 the declared home is not one of the product's repos ---------------
fresh config-home-not-in-repos
python3 - "$CLONE/$CONFIG_REL" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as fh:
    cfg = json.load(fh)
cfg["product"]["spec_home"] = "somewhere/else"
with open(path, "w") as fh:
    json.dump(cfg, fh, indent=2)
PY
commit_clone "the spec home is not a repo the product owns"
run_check config-home-not-in-repos
report config-home-not-in-repos 1 "R1.1"

# --- R2.1 the config disclaims the invariant --------------------------------
fresh ids-permanent-false
python3 - "$CLONE/$CONFIG_REL" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as fh:
    cfg = json.load(fh)
cfg["spec"]["ids_are_permanent"] = False
with open(path, "w") as fh:
    json.dump(cfg, fh, indent=2)
PY
commit_clone "ids_are_permanent turned off"
run_check ids-permanent-false
report ids-permanent-false 1 "R2.1"

# --- R2.2 an id present in history is deleted -------------------------------
fresh delete-active-id
python3 - "$CLONE/$SPEC_REL" <<'PY'
import sys
path = sys.argv[1]
with open(path) as fh:
    lines = fh.readlines()
kept = [l for l in lines if not l.startswith("- **R5** ")]
assert len(kept) == len(lines) - 1, "R5 was not found to delete"
with open(path, "w") as fh:
    fh.writelines(kept)
PY
commit_clone "R5 deleted outright"
run_check delete-active-id
report delete-active-id 1 "R2.2"

# --- R2.2 and R2.3 the same sentence moved to a new number ------------------
#
# THE MUTATION HAS TO COVER ITS TRACKS, and that is the point of doing it this
# way. A renumber is, to every other assertion, an ordinary edit: move the
# counter past the new id and R8.1 stays green, write the new id a change-log
# row and R8.2 stays green. Leaving either out reddens four assertions instead
# of two and proves less about the two it was aimed at. What survives all that
# housekeeping is exactly R2.2 and R2.3 - which is the claim: a renumber is
# invisible to everything except the two assertions written to see it.
fresh renumber-id
python3 - "$CLONE/$SPEC_REL" <<'PY'
import sys
path = sys.argv[1]
with open(path) as fh:
    body = fh.read()
assert "- **R5** " in body, "R5 was not found to renumber"
assert ": `R29` " in body, "the counter line was not found"
body = body.replace("- **R5** ", "- **R30** ", 1)
body = body.replace(": `R29` ", ": `R31` ", 1)
lines = body.split("\n")
for index, line in enumerate(lines):
    if line.startswith("| 2026-08-29 |"):
        lines.insert(index + 1,
                     "| 2026-08-30 | - | - | R30 | - | - | R5 renumbered, and "
                     "recorded, so only R2.2 and R2.3 can see it. |")
        break
else:
    raise SystemExit("no change-log row to insert after")
with open(path, "w") as fh:
    fh.write("\n".join(lines))
PY
commit_clone "R5 renumbered to R30, counter moved, change log written"
run_check renumber-id
report renumber-id 1 "R2.2 R2.3"

# --- R2.4 a different requirement under an existing id ----------------------
fresh swap-text-under-id
python3 - "$CLONE/$SPEC_REL" <<'PY'
import re, sys
path = sys.argv[1]
with open(path) as fh:
    lines = fh.readlines()
for index, line in enumerate(lines):
    if line.startswith("- **R5** "):
        lines[index] = ("- **R5** — The operator shall receive a weekly "
                        "digest by email.\n")
        break
else:
    raise SystemExit("R5 was not found to swap")
with open(path, "w") as fh:
    fh.writelines(lines)
PY
commit_clone "R5 now says something else entirely"
run_check swap-text-under-id
report swap-text-under-id 1 "R2.4"

# --- R8.1 the counter would hand out an id that is already used -------------
fresh counter-below-used-id
python3 - "$CLONE/$SPEC_REL" <<'PY'
import sys
path = sys.argv[1]
with open(path) as fh:
    body = fh.read()
assert ": `R29` " in body, "the counter line was not found"
with open(path, "w") as fh:
    fh.write(body.replace(": `R29` ", ": `R20` ", 1))
PY
commit_clone "the counter walked back below ids already used"
run_check counter-below-used-id
report counter-below-used-id 1 "R8.1"

# --- R8.2 a requirement added with no change-log row ------------------------
fresh add-unrecorded-id
python3 - "$CLONE/$SPEC_REL" <<'PY'
import sys
path = sys.argv[1]
with open(path) as fh:
    lines = fh.readlines()
out = []
placed = False
for line in lines:
    if not placed and line.startswith("- **R5** "):
        out.append(line)
        out.append("- **R29** — The lifecycle shall emit a run identifier "
                   "for every check.\n")
        placed = True
        continue
    out.append(line)
assert placed, "R5 was not found to insert after"
body = "".join(out).replace(": `R29` ", ": `R30` ", 1)
body = body.replace("| R8 | `acceptance-rows` check",
                    "| R29 | a row, so only the change log is missing |\n"
                    "| R8 | `acceptance-rows` check", 1)
with open(path, "w") as fh:
    fh.write(body)
PY
commit_clone "R29 added, acceptance row written, change log left alone"
run_check add-unrecorded-id
report add-unrecorded-id 1 "R8.2"

# ===========================================================================
# PREMISES. Every one of these is exit 2 - unmeasured - and never 0.
# ===========================================================================

# A real --depth 1 clone, not a simulated one. CI must fetch full history for
# R2 to measure anything, and a green run on a shallow clone is a green that
# measured nothing.
CLONE="$WORK/shallow-clone"
git clone --quiet --depth 1 "file://$REPO" "$CLONE" ||
  die "could not make a shallow clone of $REPO"
run_check shallow-clone
report shallow-clone 2 ""

fresh untracked-spec
git -C "$CLONE" rm --quiet --cached "$SPEC_REL"
printf '%s\n' "$SPEC_REL" >> "$CLONE/.gitignore"
commit_clone "the spec is no longer tracked"
run_check untracked-spec
report untracked-spec 2 ""

fresh unreadable-spec
chmod 000 "$CLONE/$SPEC_REL"
run_check unreadable-spec
chmod 644 "$CLONE/$SPEC_REL"
report unreadable-spec 2 ""

fresh no-spec-at-all
rm -f "$CLONE/$SPEC_REL"
run_check no-spec-at-all
report no-spec-at-all 2 ""

fresh history-bound-exceeded
run_check history-bound-exceeded --max-versions 1
report history-bound-exceeded 2 ""

fresh unparseable-config
printf 'not json at all\n' > "$CLONE/$CONFIG_REL"
run_check unparseable-config
report unparseable-config 2 ""

# ===========================================================================
# CONTRACT
# ===========================================================================
contract() {
  local name="$1" want="$2" got=0
  shift 2
  cases=$((cases + 1))
  "$CHECK" "$@" > "$WORK/contract.out" 2>&1 || got=$?
  if [ "$got" = "$want" ]; then
    printf 'ok    %-26s exit %s\n' "$name" "$got"
  else
    failed=$((failed + 1))
    printf 'FAIL  %-26s exit %s (wanted %s)\n' "$name" "$got" "$want"
  fi
}
contract flag-version 0 --version
contract flag-help 0 --help
contract flag-unknown 2 --not-a-flag
contract flag-stray-argument 2 stray

printf '\n%d case(s), %d failed\n' "$cases" "$failed"
if [ "$failed" -ne 0 ]; then
  printf 'FALSIFICATION INCOMPLETE: an assertion did not go red where it was aimed, or reddened more than it was aimed at. Either is a check that is not measuring what it claims.\n' >&2
  exit 1
fi
printf 'Every assertion was observed failing on its own, and every premise refused.\n'
