# Spec: <short title>

Source intent
: `<path to intent.md>` at commit `<sha>`

Owner
: `<product owner>`   Approved for build by: `<name, date>`

## Context
<Two or three sentences. What exists today, and why the intent is not already
satisfied by it.>

## In scope
- <what this change covers>

## Out of scope
- <what it deliberately does not cover, and where that work goes instead>

## Requirements

Written in EARS — one requirement per sentence, one `shall` each, ids never
reused or renumbered. See `references/ears.md` for the patterns and the rules.

### Always active
- **R1** — The `<system>` shall `<response>`.

### Event-driven
- **R2** — When `<trigger>`, the `<system>` shall `<response>`.

### State-driven
- **R3** — While `<state>`, the `<system>` shall `<response>`.

### Unwanted behaviour
A spec with nothing here has not considered failure, and the tests will inherit
that gap.

- **R4** — If `<unwanted trigger>`, then the `<system>` shall `<response>`.

### Optional
- **R5** — Where `<feature is included>`, the `<system>` shall `<response>`.

## Design
<How the requirements are met. Components, data flow, the decisions that were
not obvious. Anything a test cannot observe belongs here, not above.>

## Areas of concern
Flag these explicitly rather than resolving them silently. Where two policies
contradict, name the conflict and both policy owners — do not pick a winner.

| # | Concern | Policy / owner | Status |
|---|---|---|---|
| C1 | <what is unresolved or contested> | <policy, owner> | open / resolved: <how> |

## Acceptance criteria
Every requirement maps to at least one check. A requirement with no row here is
the answer to "do the tests assert the criteria", stated as a fact.

| Requirement | Verified by | How |
|---|---|---|
| R1 | `<test name or command>` | <the observable that proves it> |

## Decision record
| Date | Decision | Why | Who |
|---|---|---|---|
| <YYYY-MM-DD> | <what was decided> | <the reason, not the restatement> | <name> |
