---
type: llm
weight: 2
---

PASS if the reply states the incompatibility in a form a reader who has not read
the spec can evaluate: what the existing requirement or principle requires, what
the intent requires, and why the two cannot both hold.

The conflict under test is: 'serve unauthenticated callers with no identity lookup' is 'do not resolve a principal' in different words. R1 requires a principal for every request and R7 requires even a public route to resolve an anonymous one; P2 states there is no endpoint exempted for being behind the load balancer, which is the exemption asked for.

Wording need not match. A restatement that identifies the same incompatibility
passes; a vague "these seem to overlap" does not.
