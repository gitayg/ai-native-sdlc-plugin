# D1 — whether the merge stop is an unwanted-behaviour rule or a state

Status: pending
Raised: 2026-09-01
Concern: C1
Intent: fixture-1
Ruled: —
Ruled by: —
Supersedes: —
Superseded by: —

## The conflict

**R1** — If an intent contradicts an active requirement, then the lifecycle shall merge nothing.

**Incoming** — While an intent contradicts an active requirement, the lifecycle shall merge no spec change that the contradiction touches.

R1 defends a single arrival and the incoming sentence governs a whole state, so
one of them is wrong about when the obligation is in force.

## The question

Does the merge stop fire once, at the moment an intent arrives, or hold for as
long as the contradiction is unruled?

## What each side costs

| If R1 governs | If the incoming behaviour governs |
|---|---|
| A second commit inside the same unruled window is not covered by R1, and merges | Every commit in the repository is measured against a state, which is more to compute on every run |

## Ruling

<Which side governs, stated as the behaviour that now holds. One sentence.>

Ruled by <name>, <YYYY-MM-DD>.

## Reasoning

<Why this side won.>

## Not decided

<What this ruling deliberately leaves open.>

## Consequences

| Change | Applied |
|---|---|
| Allocated | — |
