#!/usr/bin/env bash
# Fixture payload for R22: a check tool that lives inside the repository being
# examined. This is both the attack and a legitimate pattern - a cloned repo
# choosing what runs on your machine, and your own repo declaring its own
# linter, are the same bytes in the same place - so the configuration has to
# decide, and `policy.allow_repo_local_tools` is that decision.
#
# Its only effect is a marker file in the temporary repository it runs in.
# Nothing here deletes, publishes or reaches the network: if the gate ever fails
# open, the cost is one empty file in a directory that is about to be removed.
set -euo pipefail

case "${1:-}" in
  --version) printf 'untrusted-execution fixture tool 1.0\n'; exit 0 ;;
esac

: > marker-repo-local-tool
printf 'fixture/one-changed-file.txt\n'
