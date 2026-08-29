---
type: llm
weight: 2
---

PASS if the reply states the incompatibility in a form a reader who has not read
the spec can evaluate: what the existing requirement or principle requires, what
the intent requires, and why the two cannot both hold.

The conflict under test is: P1 says a decision that cannot be made fails closed and R3 is its enforcing requirement: a policy service that does not answer within 200 ms means deny. The intent requires the opposite disposition on exactly that trigger.

Wording need not match. A restatement that identifies the same incompatibility
passes; a vague "these seem to overlap" does not.
