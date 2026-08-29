---
type: llm
weight: 2
---

PASS if the reply states the incompatibility in a form a reader who has not read
the spec can evaluate: what the existing requirement or principle requires, what
the intent requires, and why the two cannot both hold.

The conflict under test is: 'a subscriber terminates their plan' and 'a customer cancels their subscription' are one event in two vocabularies. R2 says stop charging at the end of the cycle; the intent says charge again after that. Nothing lexical connects cancel to terminate or subscription to plan, so a word-matching check reports the two as unrelated.

Wording need not match. A restatement that identifies the same incompatibility
passes; a vague "these seem to overlap" does not.
