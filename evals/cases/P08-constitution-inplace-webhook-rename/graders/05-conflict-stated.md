---
type: llm
weight: 2
---

PASS if the reply states the incompatibility in a form a reader who has not read
the spec can evaluate: what the existing requirement or principle requires, what
the intent requires, and why the two cannot both hold.

The conflict under test is: P1 forbids renaming a field in a published payload; R6 publishes `amount_cents` on `invoice.issued`. Renaming it in place is a non-additive change to a contract integrators already consume.

Wording need not match. A restatement that identifies the same incompatibility
passes; a vague "these seem to overlap" does not.
