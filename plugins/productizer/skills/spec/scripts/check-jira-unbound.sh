#!/usr/bin/env bash
# check-jira-unbound.sh [--root DIR] [--config PATH] [--backlog PATH]... [--version] [--help]
#
# MEASURES THE PRECONDITION OF R27 AND R28, WHICH IS THE ONLY HONEST THING TO
# SAY ABOUT THEM HERE.
#
#   R27 - Where a backlog item names a Jira key, the lifecycle shall read that
#         item's status from Jira.
#   R28 - Where a backlog item names a Jira key, the lifecycle shall write
#         nothing back to Jira.
#
# Both are EARS optional-feature clauses. Their obligation exists only where a
# backlog item names a Jira key, and nothing in this repository does: `jira` is
# null in the config, which is the "Skip Jira - GitHub only" answer, and no
# backlog row carries a key. Neither requirement is unimplemented here. Neither
# one is reachable.
#
# So this check does NOT claim the behaviour works. It claims the guard is shut,
# and it claims it BY MEASURING, every run, from the two files that decide it.
# In `checks.yaml` it claims R27 and R28 as `n/a` with that reason, which takes
# them out of the coverage denominator - and the claim is only live while this
# check PASSES. The runner voids a coverage claim from a check that failed. So
# the moment Jira is bound or a key appears in the backlog, this check fails,
# both claims void, R27 and R28 fall to `Missing`, and the suite refuses. The
# n/a expires by itself; nobody has to remember to withdraw it.
#
# THAT IS THE WHOLE DESIGN. An n/a that cannot expire is an excuse with a
# reason attached. This one is a measurement of a precondition, and it reverts
# the instant the precondition changes.
#
# WHAT IT READS.
#
#   THE CONFIG. `jira` must be null - the recorded decision not to bind Jira.
#   Any other value means Jira IS bound, the guarded behaviour is reachable,
#   and nothing implements it.
#
#   THE BACKLOG. Every row is scanned for a Jira key, `[A-Z][A-Z0-9]+-[0-9]+`.
#   There is NO exclusion list, deliberately. That pattern also matches things
#   that are not Jira keys - `UTF-8` and `SHA-256` are the obvious ones - and
#   when one of those appears in the backlog this check will fail on it. That
#   is the direction to be wrong in. A false positive costs somebody five
#   minutes and a deliberate exclusion; a false negative leaves two
#   requirements sitting in an n/a nobody notices, which is the failure this
#   whole file exists to prevent. An exclusion list written before it was
#   needed is a list of holes drilled in advance.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  Jira is unbound and no backlog row names a key. R27 and R28 are out of
#      force here, and the n/a claims in `checks.yaml` stand.
#   1  findings - Jira is bound, or something in the backlog looks like a key.
#      The claims void and the two requirements go back to `Missing`.
#   2  could not run - bad usage, no work tree, an absent or unparseable
#      config, an unreadable backlog. The precondition is then UNKNOWN, and
#      unknown is never the same as shut: a config nobody could read has not
#      been shown to say `null`.
#
# WHAT IT PRINTS. One BARE repo-relative path per line for every file examined,
# which is what the runner parses as coverage. Findings and notes are INDENTED.
# Nothing absolute is ever printed - this output is tailed into a committed
# result file, and an absolute path there is somebody's home directory
# published to everyone who clones the repo.
set -euo pipefail

VERSION="check-jira-unbound 1.0"

ROOT=""
CONFIG_REL=""
BACKLOGS=()

die_unmeasured() { printf 'check-jira-unbound: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    --root)       [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";       shift 2 ;;
    --root=*)     ROOT="${1#--root=}";           shift ;;
    --config)     [ "$#" -ge 2 ] || die_unmeasured "--config needs a path";  CONFIG_REL="$2"; shift 2 ;;
    --config=*)   CONFIG_REL="${1#--config=}";   shift ;;
    --backlog)    [ "$#" -ge 2 ] || die_unmeasured "--backlog needs a path"; BACKLOGS+=("$2"); shift 2 ;;
    --backlog=*)  BACKLOGS+=("${1#--backlog=}"); shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1. Files are named with --config and --backlog." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1. Files are named with --config and --backlog."

# The work tree, never the working directory. Running this from a subdirectory
# must read the same files it reads from the root, or the answer depends on
# where the person stood when they asked.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no git work tree here, and --root was not given. The config could not be located; unmeasured, not clean."
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

[ -n "$CONFIG_REL" ] || CONFIG_REL=".claude/productizer/config.json"
[ "${#BACKLOGS[@]}" -gt 0 ] || BACKLOGS=(".claude/productizer/backlog.md")

command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the config could not be parsed"

FINDINGS=0

# --- the config: is Jira bound? ---------------------------------------------
printf '%s\n' "$CONFIG_REL"
[ -f "$ROOT/$CONFIG_REL" ] \
  || die_unmeasured "no config at the path given, so whether Jira is bound is UNKNOWN. An absent config has not been shown to say null."

JIRA_STATE="$(python3 - "$ROOT/$CONFIG_REL" <<'PY' || true
import json
import sys

try:
    with open(sys.argv[1], errors="replace") as fh:
        cfg = json.load(fh)
except (OSError, ValueError):
    # Deliberately silent about WHY. The message would carry the path, and this
    # text lands in a committed file. The caller turns an empty answer into
    # exit 2 with its own wording.
    sys.exit(1)

if not isinstance(cfg, dict):
    sys.exit(1)
if "jira" not in cfg:
    print("absent")
elif cfg["jira"] is None:
    print("null")
else:
    print("bound")
PY
)"

case "$JIRA_STATE" in
  null)
    printf '  `jira` is null - the recorded decision to run GitHub-only. Jira is not bound.\n'
    ;;
  bound)
    printf '  FINDING: `jira` is bound in the config. R27 and R28 are in force from here on, and nothing in this repository reads a Jira status or refuses a Jira write. They are not n/a; they are unimplemented.\n'
    FINDINGS=$((FINDINGS + 1))
    ;;
  absent)
    printf '  FINDING: the config has no `jira` key at all. Absent is not the same as null: null is a decision somebody recorded, absent is a question nobody answered, and this check will not read one as the other.\n'
    FINDINGS=$((FINDINGS + 1))
    ;;
  *)
    die_unmeasured "the config could not be parsed as a JSON object, so whether Jira is bound is UNKNOWN"
    ;;
esac

# --- the backlog: does any row name a key? ----------------------------------
KEYS_SEEN=0
for rel in "${BACKLOGS[@]}"; do
  printf '%s\n' "$rel"
  [ -f "$ROOT/$rel" ] \
    || die_unmeasured "no backlog at one of the paths given, so whether any row names a Jira key is UNKNOWN"
  [ -r "$ROOT/$rel" ] \
    || die_unmeasured "a backlog file could not be read, so whether any row names a Jira key is UNKNOWN"
  hits="$(grep -onE '[A-Z][A-Z0-9]+-[0-9]+' "$ROOT/$rel" || true)"
  if [ -n "$hits" ]; then
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      KEYS_SEEN=$((KEYS_SEEN + 1))
      printf '  FINDING: %s line %s reads `%s`, which has the shape of a Jira key. If it is one, R27 and R28 are in force and unimplemented. If it is not - an encoding or a standard, say - exclude it here deliberately rather than widening the pattern.\n' \
        "$rel" "${hit%%:*}" "${hit#*:}"
    done <<< "$hits"
  else
    printf '  no row in this file names anything shaped like a Jira key.\n'
  fi
done
FINDINGS=$((FINDINGS + KEYS_SEEN))

printf '  backlog files scanned: %d\n' "${#BACKLOGS[@]}"
printf '  Jira-key-shaped tokens found: %d\n' "$KEYS_SEEN"

if [ "$FINDINGS" -ne 0 ]; then
  printf '  R27 and R28 are NOT n/a here: see the findings above. The n/a claims in checks.yaml void with this failure, and both requirements go back to Missing.\n'
  exit 1
fi
printf '  R27 and R28 are out of force in this repository: Jira is unbound and no backlog row names a key. Their n/a claims stand for this run only, and are re-measured on the next one.\n'
exit 0
