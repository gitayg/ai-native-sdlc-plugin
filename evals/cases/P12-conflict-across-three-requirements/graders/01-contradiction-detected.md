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

Conflict under test: Each requirement is individually satisfiable with the intent. The conflict only appears when all three are held at once: serving a cached report while the policy service is slow means answering without a policy decision, which R3 says must be a deny and P1 says must fail closed — and the only reason the intent is being asked for is R2's 500 ms budget. No pair of these three conflicts on its own.
