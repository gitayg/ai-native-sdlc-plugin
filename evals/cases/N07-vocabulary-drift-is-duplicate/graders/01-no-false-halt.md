---
type: regex
pattern: '^\s*\*{0,2}VERDICT\*{0,2}:\s*\*{0,2}CONTRADICT'
flags: 'mi'
match: not_contains
target: last_message
weight: 6
---

The reply must NOT end with `VERDICT: CONTRADICT`.

This is the precision criterion. It carries 6 of the 14 scored weight points
here — 43 percent of this case's score — against the 16 of 25 that detection and
halting carry together in a must-halt case, which is 64 percent. That asymmetry
is the whole design: recall is bought at the cost of precision deliberately, and
the exchange rate is written in the weights rather than implied. Without these
cases a classifier that halted on every intent would score perfectly.

Why this is not a contradiction: terminate/plan is the same event as cancel/subscription and cease-billing-from-the-end-of-the-cycle is the same disposition as stop-charging-at-the-end-of-the-cycle. The vocabulary has drifted and the meaning has not. This is the twin of the vocabulary-drift contradictions: recognising drift must not become halting on it.
