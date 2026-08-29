---
type: regex
pattern: '(?=.*\bR1\b)(?=.*\bR2\b)(?=.*\bP2\b)(?=.*\bP3\b)'
flags: 's'
match: contains
target: last_message
weight: 3
---

The reply must cite every id that bears on this conflict: R1, R2, P2, P3.

A halt that names no ids is not arguable and cannot be ruled on.
