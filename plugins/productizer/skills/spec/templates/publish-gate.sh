#!/usr/bin/env bash
# .claude/hooks/publish-gate.sh — PreToolUse hook on the Bash tool.
#
# Stage 5C is agent-driven: the agent writes the post, writes the release email,
# captures the screenshots from the released build, and runs the pre-publish
# checks. This hook is the human gate on the last step — the one that puts any
# of it in front of people.
#
# Register it exactly as production-gate.sh is registered, matched to Bash:
#
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command",
#                   "command": ".claude/hooks/publish-gate.sh" }]
#     }]
#   }
#
# Exit codes are the contract:
#   2  BLOCKED. The command does not run; stderr goes back to the agent.
#   0  allowed.
# Every failure path exits 2, including this script's own bugs — a missing jq,
# an unexpected payload, an empty command. Claude Code runs the command anyway
# on any other non-zero status, so a gate that crashes with 1 or 127 is a gate
# that published. The EXIT trap rewrites anything that is not 0 or 2 into 2.
#
# ---------------------------------------------------------------------------
# THIS IS A TEMPLATE. AN UNEDITED COPY GATES THE WRONG COMMANDS.
#
# The deny list below describes an imaginary team's publishing commands. Before
# it is worth committing:
#   1. Run the commands that actually publish for you past it, and watch them
#      exit 2.
#   2. Run drafting, screenshotting and preview commands past it, and watch
#      them exit 0. The agent must be able to do all of its own work.
#   3. Delete what does not apply and add what does.
# A gate never seen blocking a real publish is decoration.
#
# Why publishing is gated when the drafting is not: a post is indexed and
# forwarded within minutes, and mail cannot be recalled. Every other artifact
# in this lifecycle is a commit someone can revert. This one is not, and it
# carries claims about the product to people outside the team.
# ---------------------------------------------------------------------------
set -euo pipefail

_rc=2
trap '[ "$_rc" = 0 ] && exit 0; exit 2' EXIT

command -v jq >/dev/null 2>&1 || {
  echo "publish-gate: jq is not installed, so this gate cannot read the command it is meant to check. Blocking." >&2
  exit 2
}

payload="$(cat)" || { echo "publish-gate: could not read the hook payload. Blocking." >&2; exit 2; }
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')" || {
  echo "publish-gate: the hook payload was not the shape this gate expects. Blocking." >&2; exit 2; }
[ -n "$cmd" ] && [ "$cmd" != "null" ] || {
  echo "publish-gate: empty command. Blocking, because a gate that cannot see what it is judging has not judged it." >&2; exit 2; }

# Anchored patterns. Each must match a command that actually reaches an
# audience — not one that prepares something for you to read.
deny=(
  '(^|[;&|[:space:]])gh[[:space:]]+release[[:space:]]+(create|edit|upload)([[:space:]]|$)'
  '(^|[;&|[:space:]])npm[[:space:]]+publish([[:space:]]|$)'
  '(^|[;&|[:space:]])(twine|cargo)[[:space:]]+publish([[:space:]]|$)'
  '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]].*)?[[:space:]]--tags([[:space:]]|$)'
  '(^|[;&|[:space:]])(mail|sendmail|mailx|msmtp)([[:space:]]|$)'
  '(^|[;&|[:space:]])curl[[:space:]].*(api\.mailgun|api\.sendgrid|api\.postmarkapp|api\.buttondown|api\.twitter|api\.x\.com|graph\.facebook|api\.linkedin|hooks\.slack)'
  '(^|[;&|[:space:]])(hugo|jekyll|eleventy|next)[[:space:]]+deploy([[:space:]]|$)'
  '(^|[;&|[:space:]])(netlify|vercel|wrangler)[[:space:]]+(deploy|publish)([[:space:]]|$)'
  '(^|[;&|[:space:]])aws[[:space:]]+s3[[:space:]]+(cp|sync)[[:space:]].*s3://'
)

for pat in "${deny[@]}"; do
  if printf '%s' "$cmd" | grep -Eq "$pat"; then
    cat >&2 <<MSG
BLOCKED by publish-gate.

  $cmd

Stage 5C drafts; a person publishes. This command puts something in front of
people, and neither a post nor an email can be recalled.

Before a human runs it, the pre-publish checklist has to actually pass:
  - every claim traces to a merged PR or a requirement id
  - every number was measured, and the measurement is stated
  - every screenshot came from THIS version's build
  - the version named is live and installable, and that was verified
  - no customer, repo, internal hostname or employer name appears anywhere,
    including in the screenshots
  - names and bylines of anyone credited are correct

Hand the draft and the checklist results to the person publishing. Say plainly
which checks you could not verify yourself.
MSG
    exit 2
  fi
done

_rc=0
exit 0
