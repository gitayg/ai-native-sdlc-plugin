# Productizer — living spec

System
: `<system-name>` — the exact noun every requirement below uses. Never vary it.

Spec location
: `.claude/productizer/spec.md`. Inside `.claude/` deliberately: build tooling, static
site generators, doc builds and packaging all skip that directory, so the spec
is never rendered as a page or shipped in a release.

Next requirement id
: `R23` — allocate from here, then increment. This is the highest id the spec
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
- Holding one living spec per product, and classifying every arriving intent
  against the whole of it.
- Halting when an intent contradicts an agreed requirement, and recording the
  ruling that resolves it.
- Declaring and running the checks a change must pass, and refusing a check
  that cannot show what it examined.
- Publishing read-only views of all of the above, regenerated from the files.
- Gating the two irreversible acts — deploying and publishing — behind a person.

Out of scope
- Writing the code. The agent already does that; this governs what it is
  allowed to build and when it must stop.
- Being a ticket tracker. Where a backlog item names a Jira key, Jira owns that
  item's status and nothing is written back to it.
- Hosting, CI, or deployment mechanics. Those belong to the repo's own tooling;
  this only decides whether the change may proceed.

## Requirement index

Maintain this once the spec passes roughly thirty requirements — it is how the
file stays skimmable at two hundred. One row per requirement, in id order.

| Id | Area | Pattern | Status | Verified by |
|---|---|---|---|---|
| R1 | <area> | ubiquitous | active | `<test name>` |
| R2 | <area> | event | superseded by R41 | — |
| R3 | <area> | state | withdrawn | — |

## Requirements

### Ubiquitous — always active

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent: never reused, never renumbered.
- **R3** — The lifecycle shall keep a replaced requirement's original text in the spec, marked superseded.
- **R4** — Every published view shall be read-only with respect to the spec.
- **R5** — Every check shall declare what it must have examined for its pass to count.

### Event-driven

- **R6** — When an intent arrives, the lifecycle shall classify it against the whole living spec as exactly one of extend, refine, duplicate or contradict.
- **R7** — When an intent is classified, the lifecycle shall record the classification in the spec's change log.
- **R8** — When a requirement is added, the lifecycle shall allocate the next unused id and record it in the acceptance criteria table.
- **R9** — When a release is prepared, the lifecycle shall regenerate the user guide from the active requirements.
- **R10** — When a repository with history is imported, the lifecycle shall mark every drafted requirement inferred and unconfirmed.
- **R11** — When a published view is regenerated, the lifecycle shall read every figure in it from a file in the repository.

### State-driven

- **R12** — While a contradiction is unruled, the lifecycle shall merge no spec change that depends on it.
- **R13** — While a check tool named by the configuration is absent, the lifecycle shall report that check as missing rather than skipped.

### Unwanted behaviour

- **R14** — If an intent contradicts an active requirement, then the lifecycle shall stop and ask which wins, and shall merge nothing.
- **R15** — If a check exits zero having examined less than it declared, then the lifecycle shall report it as hollow and treat it as a failure.
- **R16** — If a value could not be measured, then the lifecycle shall report it as unmeasured and shall not record it as zero.
- **R17** — If a command would publish or deploy, then the gate shall block it until a person approves.
- **R18** — If a configured command names a shell or an interpreter with an inline program, then the lifecycle shall refuse to run it.
- **R19** — If the spec home is unreachable, then the lifecycle shall stop rather than classify against a remembered copy.
- **R20** — If a survey finds too little evidence to draft from, then the lifecycle shall refuse to draft a spec from it.

### Optional

- **R21** — Where a backlog item names a Jira key, the lifecycle shall read that item's status from Jira and shall write nothing back.
- **R22** — Where a repository declares its own check tools, the lifecycle shall run them only if the configuration explicitly opts in.

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

## Acceptance criteria

| Requirement | Verified by |
|---|---|
| R2 | `references/ears.md` id-lifecycle rules; reviewed at intake |
| R5 | `scripts/run-checks.sh` coverage assertion; `hollow` path |
| R11 | `scripts/build-view.sh` — byte-identical across runs and timezones |
| R14 | `scripts/contradiction-check.py --selftest` — 7 true positives, precision 1.00 |
| R15 | `run-checks.sh` hollow detection — proven on a stub and on real semgrep |
| R16 | `check-hygiene.sh`, `stage-status.sh`, `build-view.sh` unmeasured states |
| R17 | `templates/publish-gate.sh` — 42-case block corpus, 41-case allow corpus |
| R18 | `run-checks.sh` argv[0] validation — shells, interpreters, repo-local paths |
| R20 | `scripts/import-survey.sh` Verdict section |
| R22 | `policy.allow_repo_local_tools`, default false |

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
