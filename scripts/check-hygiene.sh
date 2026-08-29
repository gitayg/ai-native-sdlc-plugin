#!/usr/bin/env bash
# check-hygiene.sh [--version] <file>...
#
# Refuses content that must never reach a public repo: the maintainer's
# employer, private repo names, personal filesystem paths, the machine's
# hostname, and anything shaped like a credential.
#
# Exit: 0 clean · 1 findings · 2 could not run
set -euo pipefail

[ "${1:-}" = "--version" ] && { echo "check-hygiene 1.0"; exit 0; }
[ $# -gt 0 ] || { echo "usage: check-hygiene.sh <file>..." >&2; exit 2; }

# Each pattern is a thing that has actually leaked into this repo before, or
# would be a credential. Added to only with a reason.
PATTERNS='opswat|deployhub|appCrane|agentclub|raisemehost|nanoai|LMmOS-[A-Z0-9]+|/Users/[a-z.]+|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY|beads|gascity|gastownhall'

found=0
for f in "$@"; do
  [ -f "$f" ] || continue
  # This file is checked like every other. Skipping it made the checker exempt
  # from its own rule AND made the run hollow - it never named the file, so
  # coverage saw it as unexamined. The only genuine false positive is the line
  # that DEFINES the pattern list, so drop exactly that line and nothing else.
  echo "$f"                          # coverage: one line per file examined
  # Report by LOCATION, never by quoting the match. Printing the offending line
  # put the leaked path into run-checks' `output_tail`, which is committed in
  # checks-result.json - so finding a leak created one, and the next run found
  # its own report. Same rule the delegated agents follow for injected text:
  # name where it is and what class it is; the reader opens the file.
  # -i because the real-world spelling of these names is CamelCase while the
  # pattern list is lower case. The check was not case-folding, so a capitalised
  # spelling walked straight past the rule that names it - and did, into a
  # public commit. Do not write an example here: this file is checked too.
  hits=$(grep -EnIi "$PATTERNS" "$f" | grep -v '^[0-9]*:PATTERNS=' || true)
  if [ -n "$hits" ]; then
    while IFS=: read -r ln _; do
      printf '    %s:%s: matches a forbidden pattern (employer, private repo, personal path, hostname or credential) - open the file to see it\n' "$f" "$ln"
    done <<< "$hits"
    found=1
  fi
done
exit "$found"
