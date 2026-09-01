# Fixture — the incoming behaviour merged under a different EARS keyword

A committed input to `check-pending-ruling-scope.sh`'s own self-assertion. The
script copies these files into a temporary git repository, replays them as two
commits, and runs itself against the result. The files are data; nothing here
is executed and nothing here is written to.

| File | Role |
|---|---|
| `base-spec.md` | before the contradiction was raised |
| `raised-spec.md` + `D1-merge-nothing.md` | the commit that raises D1 — this is where the window opens |
| `merged-spec.md` | the audit's case: R1's behaviour allocated as R3 under a state-driven `While` where R1 uses an unwanted-behaviour `If`. Must be REFUSED |
| `unrelated-spec.md` | an unrelated requirement allocated in the same window. Must be LET THROUGH |

The second half is not optional. Without it the first would also pass for a
check that refuses everything while any ruling is pending, which is the halt
`references/rulings.md` names as the worse failure: "an intake nobody runs
detects no contradictions at all."

D1 deliberately quotes an `**Incoming**` sentence that is NOT R3's wording, and
nothing in the spec points forward at R3, so neither of the two recognition
rules the check shipped with in version 1.0 can reach it. Version 1.0 reports
R3 as allocated and passes; that is the gap.
