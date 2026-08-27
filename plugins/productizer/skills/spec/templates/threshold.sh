#!/usr/bin/env bash
# evals/threshold.sh — the eval gate. Usage: ./evals/threshold.sh <pass> <total>
#
# Exit codes are the point of this script:
#   0  the pass rate met the threshold
#   3  the gate REFUSED — pass rate below the threshold, a deliberate no
#   2  bad usage — missing, non-numeric or impossible arguments
#   1  crash — the gate could not determine a result
#
# A gate that exits 1 both when it refuses and when it breaks is unreadable in
# CI: a broken script looks exactly like a failed suite, so someone fixes the
# evals when the gate itself is what is wrong. Keep 3 and 1 distinct.

set -eu
trap 'echo "threshold.sh: crashed before reaching a verdict" >&2; exit 1' ERR

# Percentage of evals that must pass. Override with EVAL_THRESHOLD in CI.
THRESHOLD="${EVAL_THRESHOLD:-90}"

is_count() { case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }

if [ "$#" -ne 2 ] || ! is_count "${1:-}" || ! is_count "${2:-}" || ! is_count "$THRESHOLD"; then
  echo "usage: threshold.sh <pass> <total>   (non-negative integers; EVAL_THRESHOLD=$THRESHOLD)" >&2
  exit 2
fi

pass="$1"
total="$2"

if [ "$pass" -gt "$total" ]; then
  echo "threshold.sh: $pass passes out of $total evals is impossible — the caller is wrong, not the suite" >&2
  exit 2
fi

# An empty suite is not a passing suite. Nothing was verified, so the gate has
# nothing to approve: refuse, and say that is what happened.
if [ "$total" -eq 0 ]; then
  echo "REFUSED: no evals ran. An empty suite proves nothing." >&2
  exit 3
fi

# Integer percentage, rounded down — a suite that lands just under the
# threshold should be refused, not rounded into a pass.
rate=$(( pass * 100 / total ))

if [ "$rate" -lt "$THRESHOLD" ]; then
  echo "REFUSED: $pass/$total evals passed (${rate}%), below the ${THRESHOLD}% threshold." >&2
  exit 3
fi

echo "PASS: $pass/$total evals passed (${rate}%), threshold ${THRESHOLD}%."
exit 0
