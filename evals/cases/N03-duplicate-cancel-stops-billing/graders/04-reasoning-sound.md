---
type: llm
weight: 2
---

PASS if the reply's reasoning matches the actual reason this is not a
contradiction, which is: R2 already says exactly this. The right answer is to cite R2 and stop, and to ask whether the real report is that R2 is not implemented — which is a defect, not an intent.

FAIL if it reaches the right classification for a reason that is wrong — for
example by not noticing the requirement it resembles at all, or by asserting the
two are unrelated when the reply itself shows they share a trigger.
