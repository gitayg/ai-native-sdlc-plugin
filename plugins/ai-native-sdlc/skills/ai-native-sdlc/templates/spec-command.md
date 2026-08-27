---
description: Turn an approved intent.md into a requirements and design spec
---
Read the attached intent.md and produce a requirements and design spec, using
the spec.md template as the structure.

Apply the available skills for brand, security, UX and compliance while you
write — not as a review pass afterwards.

Write every requirement in EARS, following `references/ears.md`:

- One requirement per sentence, one `shall` each. An `and` in the response is
  two requirements wearing one id.
- Number them R1, R2, … and never renumber — tests, plans and review findings
  cite these ids.
- Name the system explicitly and identically every time.
- The response must be observable from outside the system. If a test cannot see
  it, it is a design note; put it under Design.
- No unquantified adjectives. Fast, robust, graceful and appropriate are each an
  argument deferred to review — give a number or drop the word.
- Include unwanted-behaviour requirements (`If <trigger>, then …`). A spec with
  none has not considered failure.

Fill the acceptance criteria table so every requirement maps to at least one
check. List any requirement you could not map, rather than leaving the row out.

Describe areas of concern clearly and explicitly, especially anywhere two
policies contradict each other. Do not silently pick a winner: flag the conflict
and name the policy owners.

Document the result fully as spec.md.
