---
type: llm
weight: 2
---

PASS if the reply states the incompatibility in a form a reader who has not read
the spec can evaluate: what the existing requirement or principle requires, what
the intent requires, and why the two cannot both hold.

The conflict under test is: Each requirement is individually satisfiable with the intent. The conflict only appears when all three are held at once: serving a cached report while the policy service is slow means answering without a policy decision, which R3 says must be a deny and P1 says must fail closed — and the only reason the intent is being asked for is R2's 500 ms budget. No pair of these three conflicts on its own.

Wording need not match. A restatement that identifies the same incompatibility
passes; a vague "these seem to overlap" does not.
