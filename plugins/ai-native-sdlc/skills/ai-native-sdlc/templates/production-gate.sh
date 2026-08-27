#!/bin/bash
# .claude/hooks/production-gate.sh — PreToolUse hook on Bash
cmd=$(jq -r '.tool_input.command' < /dev/stdin)

if [[ "$cmd" == *"deploy"* && "$cmd" == *"production"* ]]; then
  if [ -z "$RELEASE_APPROVAL" ]; then
    echo "Production deploys need release authorisation." >&2
    exit 2
  fi
fi
exit 0
