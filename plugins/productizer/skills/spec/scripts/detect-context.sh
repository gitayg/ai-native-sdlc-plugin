#!/bin/bash
# Probe the current repo for everything the AI-native SDLC skill can bind
# without asking a human. Prints JSON on stdout. Never fails the caller.
set -uo pipefail

# Every value below is attacker-adjacent: branch names, remote URLs and filenames all arrive from a
# cloned repo. Escaping only backslash and quote let a newline in a `.git/config` URL or a template
# filename break out of its string and inject prose into the probe's own output, which the agent
# reads as trusted environment. So hand the values to a real JSON encoder instead of a sed pipeline.
JSON_ENC=fallback
if python3 -c 'import json' >/dev/null 2>&1; then
  JSON_ENC=python
elif jq -n '""' >/dev/null 2>&1; then
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

if git rev-parse --git-dir >/dev/null 2>&1; then IS_REPO=true; else IS_REPO=false; fi
REMOTE=$(git remote get-url origin 2>/dev/null || true)
REPO=""
HOST=""
case "$REMOTE" in
  git@*:*)   HOST="${REMOTE#git@}"; HOST="${HOST%%:*}"; REPO="${REMOTE#*:}" ;;
  https://*) REPO="${REMOTE#https://}"; HOST="${REPO%%/*}"; REPO="${REPO#*/}" ;;
esac
REPO="${REPO%.git}"

BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || true)
DEFAULT=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)

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
if stat -f '%Lp' / >/dev/null 2>&1; then
  STAT_MODE='stat -f %Lp'; STAT_UID='stat -f %u'
else
  STAT_MODE='stat -c %a'; STAT_UID='stat -c %u'
fi

# Group- or world-writable means someone other than the owner can swap the contents between this
# check and the exec. Treat unreadable as writable rather than guessing.
insecure_mode() {
  m=$($STAT_MODE "$1" 2>/dev/null) || return 0
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
  cd "$(dirname "$p")" 2>/dev/null || return 1
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
    RESOLVED=$(resolve_path "$SDLC_CHECK_RUNNER" 2>/dev/null || true)
    if [ -n "$RESOLVED" ] && [ -f "$RESOLVED" ]; then
      RUNNER_PATH="$RESOLVED"
      WORKTREE=$(pwd -P)
      TMPROOT=$(resolve_path "${TMPDIR:-/tmp}" 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}")
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
      if [ -z "$REJECT" ] && [ "$($STAT_UID "$RESOLVED" 2>/dev/null || echo -1)" != "$(id -u)" ]; then
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
      elif "$RESOLVED" --help >/dev/null 2>&1; then
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
    -o -type f -name "$1" -print -quit 2>/dev/null)" ] && echo true || echo false
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
