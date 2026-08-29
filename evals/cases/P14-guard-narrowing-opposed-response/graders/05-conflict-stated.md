---
type: llm
weight: 2
---

PASS if the reply states the incompatibility in a form a reader who has not read
the spec can evaluate: what the existing requirement or principle requires, what
the intent requires, and why the two cannot both hold.

The conflict under test is: An enterprise account in arrears for more than 30 days is also an account in arrears for more than 14 days, so R5's guard is in force whenever the intent's guard is. Under that shared state R5 requires suspension and the intent requires the account stay fully active. The narrower guard does not escape the broader one.

Wording need not match. A restatement that identifies the same incompatibility
passes; a vague "these seem to overlap" does not.
