#!/usr/bin/env bash
# .claude/hooks/production-gate.sh — PreToolUse hook on the Bash tool.
#
# Blocks a production deploy unless a human has authorised the release.
#
# Register it, matched to Bash and nothing else:
#
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command",
#                   "command": ".claude/hooks/production-gate.sh" }]
#     }]
#   }
#
# Exit codes are the contract, not a detail:
#   2  BLOCKED. Claude Code's blocking status for PreToolUse — the command
#      does not run, and the message on stderr goes back to the agent.
#   0  allowed.
# There is no third outcome. Every failure path below exits 2, including the
# ones that are this script's own fault: a missing jq, a payload shape it did
# not expect, an empty command, a bug. Claude Code treats any other non-zero
# status as a non-blocking error and runs the command anyway, so a gate that
# crashes with status 1 or 127 is a gate that approves the deploy. The EXIT
# trap rewrites anything that is not 0 or 2 into 2.
#
# ---------------------------------------------------------------------------
# THIS IS A TEMPLATE. AN UNEDITED COPY PROTECTS NOTHING.
#
# The deny list below describes an imaginary repo's deploy commands. It does
# not know yours. Before this file is worth committing:
#   1. Run the commands that actually ship your software past it and watch
#      them exit 2.
#   2. Run your ordinary build, test and read-only commands past it and watch
#      them exit 0.
#   3. Delete the entries that do not apply, and add the ones that do.
# A pattern nobody ever triggers is a pattern nobody notices is wrong. A gate
# never seen blocking a real deploy is decoration.
#
# Where a pattern is ambiguous it is written to over-block, because a false
# block costs a conversation and a false pass costs an outage. As shipped,
# `make deploy-staging`, `./deploy.sh preprod` and `helm upgrade --dry-run`
# are all blocked. That is the intended direction of the error, not a bug —
# but if your team meets it daily they will route around the gate, so tighten
# those entries to your real environment names.
# ---------------------------------------------------------------------------
#
# WHAT THIS GATE CANNOT SEE.
#
# It is a PreToolUse hook on the Bash tool, so a Bash command is the only
# thing it is ever handed. It does not see, and cannot block:
#   - a deploy through an MCP server — a cloud provider's deploy tool, a
#     platform's release tool. That is a different tool call entirely.
#   - a deploy caused by a file write — committing to a watched branch,
#     writing a GitOps manifest, editing a workflow file.
#   - anything CI does after the push. That runs on another machine where
#     this hook does not exist.
#   - a human typing the deploy in their own terminal.
# Those routes need their own controls: permission deny rules for the deploy
# MCP tools, branch protection and required review for the writes, a
# protected environment with required reviewers in the CI provider. This hook
# is one layer. A repo holding only this one is unprotected.
#
# RELEASE_APPROVAL — WHAT IT ACTUALLY MEANS.
#
# A matched command is let through only when RELEASE_APPROVAL is set and
# non-blank in the environment of the Claude Code process itself. A human
# exports it before starting the session:
#
#     RELEASE_APPROVAL="CHG-4412 approved by j.okafor" claude
#
# The agent cannot set it from a Bash tool call. Hooks inherit Claude Code's
# environment, not the environment of the command being judged, so neither
# `export RELEASE_APPROVAL=1` in a tool call nor `RELEASE_APPROVAL=1 make
# release-prod` reaches this script.
#
# The agent CAN set it if it can write anything that feeds that environment:
# `env` in .claude/settings.json, a shell profile, a .env the launcher
# sources, or this file. Unprotected, the variable is a speed bump and not an
# authorisation. Deny those writes and pin them where neither the agent nor
# the engineer can edit them — managed-settings.json:
#
#     "permissions": { "deny": ["Edit(.claude/hooks/**)",
#                               "Edit(.claude/settings.json)",
#                               "Edit(~/.zshrc)", "Edit(.env*)"] }
#
# If you need an authorisation the agent has no route to at all, do not use an
# environment variable. Replace the body of require_approval() with one of:
#   - an out-of-band lookup — query the change-management API for an open,
#     human-approved release ticket naming this commit;
#   - a signature the agent cannot mint — verify a detached signature over the
#     commit SHA against a public key it cannot read;
#   - no local deploy path at all, which is the strongest and the simplest.
#     Deploys happen only in CI behind a protected environment with required
#     reviewers, and this gate refuses every local deploy unconditionally.

set -euo pipefail

# --- failing closed -------------------------------------------------------

block() {
  printf 'BLOCKED by production-gate: %s\n' "$1" >&2
  exit 2
}

# Anything that is not a deliberate 0 or 2 becomes a 2. Covers set -e aborts,
# missing interpreters, and any bug introduced when this template is edited.
on_exit() {
  status=$?
  if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
    printf 'BLOCKED by production-gate: exited %s before reaching a verdict. Failing closed.\n' "$status" >&2
    exit 2
  fi
}
trap on_exit EXIT

require_approval() {
  # See RELEASE_APPROVAL above before trusting this check.
  if [ -z "$(printf '%s' "${RELEASE_APPROVAL:-}" | tr -d '[:space:]')" ]; then
    block "$1
This command deploys to production. It needs a named human's release
authorisation, which the agent cannot grant itself. A human restarts the
session with RELEASE_APPROVAL set, or the deploy goes through CI."
  fi
  printf 'production-gate: allowed (%s) under RELEASE_APPROVAL=%s\n' "$1" "$RELEASE_APPROVAL"
  exit 0
}

# --- the deny list --------------------------------------------------------
#
# EDIT THIS. It is the whole gate; everything else is plumbing.
#
# Each entry is a label and an anchored extended regular expression, matched
# case-insensitively against the whole command line. $CMD anchors a pattern to
# the START of a command — the beginning of the input or just after a shell
# separator (; & | && || ( newline), with an optional sudo. That anchoring is
# the point: it is why `echo make release-prod` is not a deploy, and why
# `git pull && make release-prod` still is.

NL='
'
CMD="(^|[;&|(${NL}])[[:space:]]*(sudo[[:space:]]+)?"   # start of a command
ARG="[^[:space:];&|]*"                                 # one bare argument
MID="([^;&|]*[[:space:]]+)?"                           # intervening flags

DENY_LABELS=()
DENY_PATTERNS=()
deny() { DENY_LABELS+=("$1"); DENY_PATTERNS+=("$2"); }

# A make target naming release, deploy or prod. `make test`, `make build` and
# `make lint` are deliberately not here.
deny "make release/deploy/prod target" \
     "${CMD}make[[:space:]]+${MID}${ARG}(release|deploy|prod|publish)"

# kubectl aimed at a production context or namespace. Coarse on purpose: this
# also blocks reads against prod. Narrow it to
# (apply|delete|rollout|scale|patch|create) if that is too much.
deny "kubectl against a production context or namespace" \
     "${CMD}kubectl[^;&|]*(--context|--kube-context|--namespace|-n)[=[:space:]]+${ARG}(prod|live)"

# helm writing to a cluster. Add install and rollback if you use them.
deny "helm upgrade" \
     "${CMD}helm[[:space:]]+${MID}upgrade"

# terraform changing real infrastructure. plan is not here, on purpose.
deny "terraform apply/destroy" \
     "${CMD}terraform[[:space:]]+${MID}(apply|destroy)"

# A push to a production registry. REPLACE prod|release|live WITH YOUR OWN
# REGISTRY HOSTNAME — it is the one pattern here most likely to be both
# wrong and silently wrong.
deny "docker push to a production registry" \
     "${CMD}docker[[:space:]]+${MID}push[[:space:]]+${ARG}(prod|release|live)"

# A deploy script invoked with a prod-ish argument. Note the limits: a bare
# `./deploy.sh` with no argument is NOT caught, so if your script defaults to
# production, drop the argument requirement. `bash scripts/deploy.sh prod`
# is not caught either — add a pattern for how your repo actually calls it.
deny "./deploy* script with a production argument" \
     "${CMD}\\./deploy${ARG}([[:space:]]+[^;&|]*)?(prod|live|release)"

# --- reading the payload --------------------------------------------------

command -v jq >/dev/null 2>&1 ||
  block "jq is not on PATH, so this gate cannot read the command it is meant to judge."

payload="$(cat)"
[ -n "$(printf '%s' "$payload" | tr -d '[:space:]')" ] ||
  block "empty hook payload on stdin. Nothing to judge, so nothing is approved."

# Every branch here is a shape this script does not understand. It refuses
# rather than guesses. jq's own diagnostic is folded into $cmd so the message
# says which shape arrived.
cmd="$(printf '%s' "$payload" | jq -er '
  if type != "object" then
    error("payload is not a JSON object")
  elif ((.tool_name // "Bash") != "Bash") then
    error("fired on tool \(.tool_name) — register this hook on the Bash matcher only")
  elif ((.tool_input | type) != "object") then
    error("payload has no .tool_input object")
  elif ((.tool_input.command | type) != "string") then
    error(".tool_input.command is not a string")
  else .tool_input.command end' 2>&1)" ||
  block "cannot read the hook payload: ${cmd:-jq failed and said nothing}"

[ -n "$(printf '%s' "$cmd" | tr -d '[:space:]')" ] ||
  block "the payload carried an empty command. A gate that cannot see the command does not approve it."

[ "${#DENY_PATTERNS[@]}" -gt 0 ] ||
  block "the deny list is empty, so this gate decides nothing. Fill it in or remove the hook."

# --- the verdict ----------------------------------------------------------

shopt -s nocasematch
for ((i = 0; i < ${#DENY_PATTERNS[@]}; i++)); do
  if [[ $cmd =~ ${DENY_PATTERNS[$i]} ]]; then
    require_approval "${DENY_LABELS[$i]}"
  fi
done

exit 0
