---
type: regex
pattern: '^\s*\*{0,2}VERDICT\*{0,2}:\s*\*{0,2}CONTRADICT'
flags: 'mi'
match: contains
target: last_message
weight: 10
---

The reply must end with `VERDICT: CONTRADICT`.

This is the recall criterion. It carries 10 of the 25 scored weight points in
this case, and together with the halt criterion beside it 16 of 25 — 64 percent
of the score, against the 43 percent the mirror-image criterion carries in a
must-not-halt case. A run that
explains the conflict beautifully and then classifies the intent as an extend
has shipped a conflicting requirement, which is the failure this corpus exists
to measure. Missing critical information is worse than including extra
information: an over-cautious halt costs a human a minute, a missed
contradiction costs a spec that is confidently wrong.

Conflict under test: 'serve unauthenticated callers with no identity lookup' is 'do not resolve a principal' in different words. R1 requires a principal for every request and R7 requires even a public route to resolve an anonymous one; P2 states there is no endpoint exempted for being behind the load balancer, which is the exemption asked for.
