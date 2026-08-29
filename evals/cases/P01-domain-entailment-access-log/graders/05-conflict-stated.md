---
type: llm
weight: 2
---

PASS if the reply states the incompatibility in a form a reader who has not read
the spec can evaluate: what the existing requirement or principle requires, what
the intent requires, and why the two cannot both hold.

The conflict under test is: R2 requires all personal data for an erased subject to be gone within 30 days, and R1 says the access log names the subject on every read — so the access log holds personal data, and a 7-year access-log retention keeps exactly the rows R2 requires removed. Neither sentence contradicts the other on its face; the conflict only exists because R1 tells you what is in the log. P2 and P3 bite for the same reason.

Wording need not match. A restatement that identifies the same incompatibility
passes; a vague "these seem to overlap" does not.
