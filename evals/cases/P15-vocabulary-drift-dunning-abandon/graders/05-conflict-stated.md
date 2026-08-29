---
type: llm
weight: 2
---

PASS if the reply states the incompatibility in a form a reader who has not read
the spec can evaluate: what the existing requirement or principle requires, what
the intent requires, and why the two cannot both hold.

The conflict under test is: 'the first declined authorisation' is 'a payment fails' and 'abandon dunning' is 'do not retry'. R4 requires a retry every 24 hours for 3 days on that trigger; the intent requires no retry at all. Both the trigger and the disposition are renamed, so nothing matches lexically.

Wording need not match. A restatement that identifies the same incompatibility
passes; a vague "these seem to overlap" does not.
