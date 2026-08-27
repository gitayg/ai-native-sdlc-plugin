#!/bin/bash
# Probe the current repo for everything the AI-native SDLC skill can bind
# without asking a human. Prints JSON on stdout. Never fails the caller.
set -uo pipefail

j() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

CONFIG=""
for p in .claude/sdlc.json .sdlc.json; do
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
RUNNER_STATE="absent"
RUNNER_PATH=""
RUNNER_REASON="SDLC_CHECK_RUNNER not set"

if [ -n "${SDLC_CHECK_RUNNER:-}" ]; then
  RUNNER_PATH="$SDLC_CHECK_RUNNER"
  RUNNER_REASON="nothing at SDLC_CHECK_RUNNER"
  if [ -f "$SDLC_CHECK_RUNNER" ]; then
    RUNNER_STATE="present-but-broken"
    RUNNER_REASON="found, but it does not run"
    if "$SDLC_CHECK_RUNNER" --help >/dev/null 2>&1; then
      RUNNER_STATE="usable"; RUNNER_REASON="--help exited 0"
    elif command -v node >/dev/null 2>&1 && node "$SDLC_CHECK_RUNNER" --help >/dev/null 2>&1; then
      RUNNER_STATE="usable"; RUNNER_REASON="node --help exited 0"
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

cat <<JSON
{
  "config_file": "$(j "$CONFIG")",
  "git": {
    "is_repo": $IS_REPO,
    "host": "$(j "$HOST")",
    "repo": "$(j "$REPO")",
    "branch": "$(j "$BRANCH")",
    "default_branch": "$(j "$DEFAULT")"
  },
  "github_cli": { "state": "$GH_STATE", "account": "$(j "$GH_ACCOUNT")" },
  "jira": { "state": "$JIRA_STATE", "site": "$(j "${JIRA_SITE:-}")", "project": "$(j "${JIRA_PROJECT:-}")" },
  "check_runner": { "state": "$RUNNER_STATE", "path": "$(j "$RUNNER_PATH")", "reason": "$(j "$RUNNER_REASON")" },
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
