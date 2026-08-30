#!/bin/bash
# Probe the current repo for everything the AI-native SDLC skill can bind
# without asking a human. Prints JSON on stdout.
#
# The PROBE never fails the caller: every binding absent is a successful probe.
# A bad INVOCATION does fail, with exit 2 — see usage() below, which is what
# `--help` actually prints, so this comment cannot drift out of it.
#
# Usage: detect-context.sh [--help]
set -uo pipefail

# The help text lives in the script and is printed by the script. Before this block the option
# parser did not exist: `detect-context.sh --zzz-not-a-real-flag` probed the repo, printed the
# full JSON document and exited 0, and `--help` did the same. Both are the worst answer a CLI
# can give — a confident, complete, successful-looking reply that does not address what was
# asked. An agent that consults --help and is answered with a context probe stops looking, and
# a typo in a flag is reported as a clean run. Refuse by name instead.
usage() {
  cat <<'USAGE'
detect-context.sh — probe this repo for everything the spec skill can bind without asking
a human. Read-only. Prints one JSON document on stdout.

Usage:
  detect-context.sh                 probe the current directory and print JSON
  detect-context.sh --help | -h     print this and exit 0

There are no other options, and it takes no positional arguments. The probe has no tunables:
it always probes the current working directory, so callers `cd` to the tree they mean. Run it
from the repo root.

What it reads from the environment:
  SDLC_CHECK_RUNNER   absolute path to an external check runner. Validated, then RUN with
                      --help; the exit code decides. Unset is a normal configuration.
                      See references/delegation.md.
  JIRA_SITE           reported as-is under "jira"
  JIRA_PROJECT        reported as-is under "jira"
  JIRA_API_TOKEN      presence only decides jira.state; the value is never printed

What it writes:
  The JSON document, to stdout. Nothing else, anywhere. It never writes to the repo. It does
  not execute anything from the repo — the one thing it executes is SDLC_CHECK_RUNNER, which
  must be absolute and outside the work tree before it is run.

What the document reports:
  config_file, git binding (is_repo, host, repo, branch, default_branch), github_cli state
  and account, jira state, check_runner state, repo-local template overrides, which stage
  artifacts exist, and whether stdin is a tty.

Three outcomes are kept distinct and are never collapsed:
  a state of "absent"    nothing was configured — a normal, supported configuration
  a state of "rejected"  something WAS configured and the probe refused to run it
  a value that is empty  the probe ran and measured nothing there
An unreadable probe is never reported as a probe that ran and found nothing.

Exit status:
  0  the probe ran and printed JSON (every binding absent is a successful probe, not a
     failed one — this is why the probe itself never fails the caller)
  2  a bad invocation: an unknown option, or a positional argument
USAGE
}

die_usage() {
  printf 'detect-context: %s\n\n' "$1" >&2
  usage >&2
  exit 2
}

# No options but --help, and no positional arguments at all. `--` is accepted so the parser is
# not a special case among this skill's scripts, but nothing may follow it: there is no path
# argument for a leading-dash name to be mistaken for.
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --)        shift
               [ "$#" -eq 0 ] || die_usage "takes no positional arguments, got: $1"
               break ;;
    -*)        die_usage "unknown option: $1" ;;
    *)         die_usage "takes no positional arguments, got: $1" ;;
  esac
done

# Every value below is attacker-adjacent: branch names, remote URLs and filenames all arrive from a
# cloned repo. Escaping only backslash and quote let a newline in a `.git/config` URL or a template
# filename break out of its string and inject prose into the probe's own output, which the agent
# reads as trusted environment. So hand the values to a real JSON encoder instead of a sed pipeline.
JSON_ENC=fallback
if command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null; then
  JSON_ENC=python
elif command -v jq >/dev/null 2>&1 && jq -n '""' >/dev/null; then
  JSON_ENC=jq
fi

# Emits one complete JSON string literal, quotes included, per argument, one per line. A JSON string
# never contains a raw newline, so line-per-value round-trips even when the input does.
json_strings() {
  case "$JSON_ENC" in
    python)
      python3 -c 'import json,sys
for a in sys.argv[1:]: print(json.dumps(a))' "$@"
      ;;
    jq)
      jq -n -r --args '$ARGS.positional[] | tojson' "$@"
      ;;
    *)
      # No encoder on the box. Deleting control bytes loses fidelity but guarantees the document
      # still parses, which matters more than reproducing a hostile filename exactly.
      for a in "$@"; do
        printf '"%s"\n' "$(printf '%s' "$a" | tr -d '\000-\037\177' | sed 's/\\/\\\\/g; s/"/\\"/g')"
      done
      ;;
  esac
}

CONFIG=""
for p in .claude/productizer/config.json .sdlc.json; do
  [ -f "$p" ] && CONFIG="$p" && break
done

if git rev-parse --git-dir >/dev/null 2>&1; then IS_REPO=true; else IS_REPO=false; fi  # stderr-ok: git prints "fatal: not a git repository" here and that sentence IS the answer this probe wants; the false branch reports is_repo:false, which the usage text names as a normal supported state
# `git remote get-url` writes `error: No such remote 'origin'` for a repo with no origin, which is
# an ordinary configuration rather than a fault. `git config --get` answers "is origin configured"
# with an exit status and nothing on stderr, so the value call below only runs when it can succeed
# and anything it does report is real. It stays `get-url` and not the raw config value because
# get-url expands url.<base>.insteadOf and the raw value does not.
REMOTE=""
if git config --get remote.origin.url >/dev/null; then
  REMOTE=$(git remote get-url origin || true)
fi
REPO=""
HOST=""
case "$REMOTE" in
  git@*:*)   HOST="${REMOTE#git@}"; HOST="${HOST%%:*}"; REPO="${REMOTE#*:}" ;;
  https://*) REPO="${REMOTE#https://}"; HOST="${REPO%%/*}"; REPO="${REPO#*/}" ;;
esac
REPO="${REPO%.git}"

# `-q` is git's own switch for exactly the two expected cases - a detached HEAD, and an
# origin/HEAD that was never set - so they stay silent while a real failure still speaks.
BRANCH=$(git symbolic-ref -q --short HEAD || true)
DEFAULT=$(git symbolic-ref -q --short refs/remotes/origin/HEAD | sed 's|^origin/||' || true)

GH_ACCOUNT=""
GH_STATE="absent"
if command -v gh >/dev/null 2>&1; then
  GH_STATE="unauthenticated"
  GH_ACCOUNT=$(gh auth status 2>&1 | awk '/Logged in to/ {print $7; exit}')
  [ -n "$GH_ACCOUNT" ] && GH_STATE="ready"
fi

JIRA_STATE="none"
[ -n "${JIRA_SITE:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ] && JIRA_STATE="env"
command -v jira >/dev/null 2>&1 && JIRA_STATE="cli"

# An external check runner is OPTIONAL and PROBED, never assumed. Presence is not usability: a runner
# can sit on disk and still fail to load its own modules, and reporting it available is the more
# expensive mistake. So run it and believe the exit code rather than testing for the file.
#
# Configure with SDLC_CHECK_RUNNER, pointing at an executable that accepts --help and exits 0 when it
# is working. Unset means absent, which is a normal configuration and not an error.
#
# Running it is the whole point, so the path has to earn that first. A relative path resolved against
# whatever tree the agent happens to be standing in meant `./evil.sh` committed into a cloned repo
# executed before any stage, prompt or gate. Absolute-only, outside the work tree, outside TMPDIR, no
# writable directory on the way down, owned by this user and not writable by anyone else.

# macOS and GNU stat share no flags; pick the dialect once.
if stat -f '%Lp' / >/dev/null 2>&1; then  # stderr-ok: this IS the dialect probe - GNU stat rejects the BSD -f flag with a usage error, and that rejection is the thing selecting the else branch below
  STAT_MODE='stat -f %Lp'; STAT_UID='stat -f %u'
else
  STAT_MODE='stat -c %a'; STAT_UID='stat -c %u'
fi

# Group- or world-writable means someone other than the owner can swap the contents between this
# check and the exec. Treat unreadable as writable rather than guessing.
insecure_mode() {
  m=$($STAT_MODE "$1") || return 0
  [ -n "$m" ] || return 0
  case "$m" in
    *[2367][01234567]) return 0 ;;
    *[2367])           return 0 ;;
  esac
  return 1
}

# `readlink -f` is absent on older macOS, so follow the final link by hand and let `pwd -P` collapse
# the directory components. A symlinked last component otherwise smuggles a path past every check.
resolve_path() (
  p=$1; n=0
  while [ -L "$p" ] && [ "$n" -lt 32 ]; do
    t=$(readlink "$p") || return 1
    case "$t" in /*) p=$t ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$((n+1))
  done
  cd "$(dirname "$p")" || return 1
  printf '%s/%s\n' "$(pwd -P)" "$(basename "$p")"
)

RUNNER_STATE="absent"
RUNNER_PATH=""
RUNNER_REASON="SDLC_CHECK_RUNNER not set"

if [ -n "${SDLC_CHECK_RUNNER:-}" ]; then
  RUNNER_PATH="$SDLC_CHECK_RUNNER"
  case "$SDLC_CHECK_RUNNER" in
    /*) ;;
    *)  RUNNER_STATE="rejected"; RUNNER_REASON="not an absolute path" ;;
  esac

  if [ "$RUNNER_STATE" != "rejected" ]; then
    RUNNER_STATE="absent"; RUNNER_REASON="nothing at SDLC_CHECK_RUNNER"
    RESOLVED=$(resolve_path "$SDLC_CHECK_RUNNER" || true)
    if [ -n "$RESOLVED" ] && [ -f "$RESOLVED" ]; then
      RUNNER_PATH="$RESOLVED"
      WORKTREE=$(pwd -P)
      TMPROOT=$(resolve_path "${TMPDIR:-/tmp}" || printf '%s' "${TMPDIR:-/tmp}")
      TMPROOT="${TMPROOT%/}"

      # Ordered so the first failing check wins and later checks do not overwrite its reason.
      REJECT=""
      case "$RESOLVED" in
        "$WORKTREE"/*) REJECT="resolves inside the current work tree" ;;
        "$TMPROOT"/*)  REJECT="resolves inside TMPDIR" ;;
      esac
      if [ -z "$REJECT" ]; then
        d=$(dirname "$RESOLVED")
        while : ; do
          if insecure_mode "$d"; then
            REJECT="directory on the path is group- or world-writable: $d"
            break
          fi
          [ "$d" = "/" ] && break
          d=$(dirname "$d")
        done
      fi
      if [ -z "$REJECT" ] && [ "$($STAT_UID "$RESOLVED" || echo -1)" != "$(id -u)" ]; then
        REJECT="not owned by the current user"
      fi
      if [ -z "$REJECT" ] && insecure_mode "$RESOLVED"; then
        REJECT="group- or world-writable"
      fi

      if [ -n "$REJECT" ]; then
        RUNNER_STATE="rejected"; RUNNER_REASON="$REJECT"
      elif [ ! -x "$RESOLVED" ]; then
        # The old `node <path>` fallback turned "not executable" into "executed anyway", which is the
        # opposite of a permission check. A non-executable runner is broken, not usable.
        RUNNER_STATE="present-but-broken"; RUNNER_REASON="found, but it is not executable"
      # Only stdout is binned. The exit code is still what decides, but when a runner is
      # reported as "found, but it does not run", its own error message is the only thing that
      # says why, and it was going straight to /dev/null.
      elif "$RESOLVED" --help >/dev/null; then
        RUNNER_STATE="usable"; RUNNER_REASON="--help exited 0"
      else
        RUNNER_STATE="present-but-broken"; RUNNER_REASON="found, but it does not run"
      fi
    fi
  fi
fi

# Which stage artifacts already exist — this is the state machine.
# Bounded, and it stops at the first hit. An unbounded `**/` glob recurses into
# node_modules and every worktree; one such glob was measured at 53s, which is
# not acceptable for something a skill runs before it does anything else.
# Depth 4 reaches the default artifact path, docs/sdlc/<slug>/intent.md.
have() {
  [ -n "$(find . -maxdepth 4 \
    \( -name node_modules -o -name .git -o -name .venv -o -name dist -o -name build \) -prune \
    -o -type f -name "$1" -print -quit)" ] && echo true || echo false
}

# Repo-local templates override the skill's defaults. List what this repo actually
# overrides, so a run can say so rather than silently using a different shape.
#
# A committed filename is untrusted input. Anything outside the conservative set is dropped and
# counted, so a name carrying newlines or quotes cannot reach the output at all.
OV_NAMES=()
OV_SKIPPED=0
if [ -d .claude/productizer/templates ]; then
  for f in .claude/productizer/templates/*; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    case "$b" in
      ""|*[!A-Za-z0-9._-]*) OV_SKIPPED=$((OV_SKIPPED+1)) ;;
      *)                    OV_NAMES+=("$b") ;;
    esac
  done
fi

ENC_OUT=()
while IFS= read -r line; do ENC_OUT+=("$line"); done <<ENC
$(json_strings "$CONFIG" "$HOST" "$REPO" "$BRANCH" "$DEFAULT" "$GH_ACCOUNT" \
               "${JIRA_SITE:-}" "${JIRA_PROJECT:-}" "$RUNNER_PATH" "$RUNNER_REASON" \
               ${OV_NAMES[@]+"${OV_NAMES[@]}"})
ENC
# An encoder that dies mid-run must still leave a parseable document rather than an unbound-variable
# abort, so backfill anything it failed to emit.
while [ ${#ENC_OUT[@]} -lt 10 ]; do ENC_OUT+=('""'); done

J_CONFIG=${ENC_OUT[0]}
J_HOST=${ENC_OUT[1]}
J_REPO=${ENC_OUT[2]}
J_BRANCH=${ENC_OUT[3]}
J_DEFAULT=${ENC_OUT[4]}
J_GH_ACCOUNT=${ENC_OUT[5]}
# Which account gh is signed in as, against who owns the repo. Someone with two
# GitHub identities can be authenticated as one and working in the other's repo,
# and every issue, comment and PR this lifecycle opens would land under the wrong
# name. Reported as a fact, not resolved here: only the user can say which is
# intended.
GH_OWNER_MATCH=unknown
if [ -n "$GH_ACCOUNT" ] && [ -n "$REPO" ]; then
  case "$REPO" in
    "$GH_ACCOUNT"/*) GH_OWNER_MATCH=true ;;
    */*)             GH_OWNER_MATCH=false ;;
  esac
fi
GH_OWNER_MATCH="\"$GH_OWNER_MATCH\""
J_JIRA_SITE=${ENC_OUT[6]}
J_JIRA_PROJECT=${ENC_OUT[7]}
J_RUNNER_PATH=${ENC_OUT[8]}
J_RUNNER_REASON=${ENC_OUT[9]}

OVERRIDES=""
i=10
while [ "$i" -lt "${#ENC_OUT[@]}" ]; do
  [ -n "$OVERRIDES" ] && OVERRIDES="$OVERRIDES, "
  OVERRIDES="$OVERRIDES${ENC_OUT[$i]}"
  i=$((i+1))
done

cat <<JSON
{
  "config_file": $J_CONFIG,
  "git": {
    "is_repo": $IS_REPO,
    "host": $J_HOST,
    "repo": $J_REPO,
    "branch": $J_BRANCH,
    "default_branch": $J_DEFAULT
  },
  "github_cli": { "state": "$GH_STATE", "account": $J_GH_ACCOUNT, "owner_match": $GH_OWNER_MATCH },
  "jira": { "state": "$JIRA_STATE", "site": $J_JIRA_SITE, "project": $J_JIRA_PROJECT },
  "check_runner": { "state": "$RUNNER_STATE", "path": $J_RUNNER_PATH, "reason": $J_RUNNER_REASON },
  "template_overrides": [$OVERRIDES],
  "template_overrides_skipped": $OV_SKIPPED,
  "artifacts": {
    "intent": $(have intent.md),
    "spec":   $(have spec.md),
    "plan":   $(have plan.md),
    "claude_md": $( [ -f CLAUDE.md ] && echo true || echo false ),
    "review_md": $( [ -f REVIEW.md ] && echo true || echo false ),
    "bands":  $(have bands.yaml)
  },
  "interactive": $( [ -t 0 ] && echo true || echo false )
}
JSON
