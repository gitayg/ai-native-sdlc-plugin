# <System> — living spec

System
: `<system-name>` — the exact noun every requirement below uses. Never vary it.

Spec location
: `.claude/productizer/spec.md`. Inside `.claude/` deliberately: build tooling, static
site generators, doc builds and packaging all skip that directory, so the spec
is never rendered as a page or shipped in a release.

Next requirement id
: `R<n>` — allocate from here, then increment. This is the highest id the spec
has ever used, not a count of the rows on screen. Ids are never reused and
never renumbered, and stay unique across the whole repo even if this spec is
later split into several files.

Requirements
: `<n>` active, `<n>` superseded, `<n>` withdrawn.

Audit trail
: `git log -p .claude/productizer/spec.md`. Each commit is one change, joined to the
issue that drove it by the branch name and the PR title. There is no
per-change copy of this spec.

## How to read this file

This is the one spec for the repo, and it is always current. An intent — a
file, text typed by a user, a GitHub Issue, a Jira ticket — is an **input**. It
is classified against what is already here, merged in, and then done with. Work
is built from the delta this file gained, not from the intent.

- **Requirements are EARS**, one per sentence, one `shall` each, grouped below
  by pattern. Patterns, id discipline and the intake classification — extend,
  refine, contradict, duplicate — are in `references/ears.md`.
- **Every requirement carries a status marker** on the line after it:

  | Status | Meaning | Recorded as |
  |---|---|---|
  | Active | Current agreed behaviour | no marker; the requirement, plain |
  | Superseded | Replaced by another requirement | `Superseded by R58.` plus one line on why |
  | Withdrawn | The behaviour no longer exists at all | `Withdrawn.` plus one line on why |

- **Nothing is ever deleted.** A superseded or withdrawn requirement keeps its
  original sentence, in place, so the file reads as the record of what was
  agreed and when it stopped being true. Deleting one breaks every plan, test,
  review finding and PR title that cites it, silently.
- **Refining keeps the id.** Making a requirement stricter, more specific or
  more measurable without changing what is agreed is an edit in place. Changing
  the behaviour allocates a new id and supersedes the old one.
- **A contradiction stops the process.** When an incoming intent conflicts with
  an active requirement, do not supersede it. Record the conflict under *Areas
  of concern*, name both owners, and ask a human which wins. Record the ruling
  before writing either requirement.

## Scope

The durable boundary of this system, not of any one change.

In scope
- <capability area this system owns>

Out of scope
- <what it deliberately does not own, and which system owns it instead>

## Requirement index

Maintain this once the spec passes roughly thirty requirements — it is how the
file stays skimmable at two hundred. One row per requirement, in id order.

| Id | Area | Pattern | Status | Verified by |
|---|---|---|---|---|
| R1 | <area> | ubiquitous | active | `<test name>` |
| R2 | <area> | event | superseded by R41 | — |
| R3 | <area> | state | withdrawn | — |

## Requirements
<!-- EXAMPLE:BEGIN — worked examples, not agreed content.
     Scaffolding DELETES this block. A seeded requirement or principle is one
     nobody agreed to, and it gets cited before anyone notices it was a sample. -->

Within each pattern, add `####` area sub-headings once that pattern passes
roughly twenty requirements. Ids stay monotonic across every section and every
area regardless of how the file is subdivided.

### Ubiquitous — always active

- **R1** — The `<system>` shall `<response>`.

### Event-driven

- **R2** — When `<trigger>`, the `<system>` shall `<response>`.
  Superseded by R41. <Why, in one line, naming the decision.>

### State-driven

- **R3** — While `<state>`, the `<system>` shall `<response>`.
  Withdrawn. <Why the behaviour no longer exists.>

### Unwanted behaviour

A spec with nothing here has not considered failure, and the tests will inherit
that gap.

- **R4** — If `<unwanted trigger>`, then the `<system>` shall `<response>`.

### Optional

- **R5** — Where `<feature is included>`, the `<system>` shall `<response>`.

### Complex

- **R6** — While `<state>`, when `<trigger>`, the `<system>` shall
  `<response>`.

Superseded and withdrawn requirements stay in the pattern section they were
written in. There is no archive section, because moving them would break the
one thing keeping their ids findable.

<!-- EXAMPLE:END -->

## Design

How the requirements are met. Components, data flow, the decisions that were
not obvious. Anything a test cannot observe belongs here, not above. Organise
by the same areas the requirements use, and cite the ids each note serves.

### <area>
<Design notes. Serves R1, R4.>

## Areas of concern

Flag these explicitly rather than resolving them silently. Where two policies
contradict, name the conflict and both policy owners — do not pick a winner. An
intent that contradicts an active requirement lands here first and stays open
until a human rules on it.

| # | Concern | Requirements | Policy / owner | Raised by | Status |
|---|---|---|---|---|---|
| C1 | <what is unresolved or contested> | R12, R31 | <policy, owner> | <issue> | open / resolved: <ruling, date> |

## Acceptance criteria

Every **active** requirement has at least one row. A requirement with no row is
the answer to "do the tests assert the criteria", stated as a fact. Superseded
and withdrawn requirements have no row — remove theirs when the status changes,
which is what keeps this table the same length as the active set.

| Requirement | Verified by | How |
|---|---|---|
| R1 | `<test name or command>` | <the observable that proves it> |

## Change log

One row per commit to this file. The issue column is the join to the work that
drove the change; the same identifier appears in the branch name and the PR
title, so the spec diff and the delivery record line up without anyone
maintaining a link.

Each row summarises one change; the full statement of that change — every id
that moved, with its text quoted and its constitution check — is the spec delta
(`templates/spec-delta.md`) in the PR body. The delta is never committed as a
file, because a per-change copy of the spec drifts from the spec the first time
someone edits one and not the other.

| Date | Issue | Branch / PR | Added | Refined | Superseded / withdrawn | Summary |
|---|---|---|---|---|---|---|
| <YYYY-MM-DD> | <#123 / PROJ-123> | `<branch>` / <pr> | R41–R43 | R12 | R7 → R41 | <what changed and why> |

## Decision record

Decisions that shaped the spec but are not themselves requirements — including
every contradiction ruling.

| Date | Decision | Why | Who |
|---|---|---|---|
| <YYYY-MM-DD> | <what was decided> | <the reason, not the restatement> | <name> |
