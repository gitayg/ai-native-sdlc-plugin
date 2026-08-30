# Productizer — living spec

System
: `<system-name>` — the exact noun every requirement below uses. Never vary it.

Spec location
: `.claude/productizer/spec.md`. Inside `.claude/` deliberately: build tooling, static
site generators, doc builds and packaging all skip that directory, so the spec
is never rendered as a page or shipped in a release.

Next requirement id
: `R29` — allocate from here, then increment. This is the highest id the spec
has ever used, not a count of the rows on screen. Ids are never reused and
never renumbered, and stay unique across the whole repo even if this spec is
later split into several files.

Requirements
: 25 active, 3 superseded, 0 withdrawn.

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
  Superseded by R23. Split into R23 and R24 — the sentence carried two obligations under one id, so a test could satisfy one half and leave the other unasserted.

- **R15** — If a check exits zero having examined less than it declared, then the lifecycle shall report it as hollow and treat it as a failure.
- **R16** — If a value could not be measured, then the lifecycle shall report it as unmeasured and shall not record it as zero.
  Superseded by R25. Split into R25 and R26 — the sentence carried two obligations under one id, so a test could satisfy one half and leave the other unasserted.

- **R17** — If a command would publish or deploy, then the gate shall block it until a person approves.
- **R18** — If a configured command names a shell or an interpreter with an inline program, then the lifecycle shall refuse to run it.
- **R19** — If the spec home is unreachable, then the lifecycle shall stop rather than classify against a remembered copy.
- **R20** — If a survey finds too little evidence to draft from, then the lifecycle shall refuse to draft a spec from it.
- **R23** — If an intent contradicts an active requirement, then the lifecycle shall stop and ask which wins.
- **R24** — If an intent contradicts an active requirement, then the lifecycle shall merge nothing.
- **R25** — If a value could not be measured, then the lifecycle shall report it as unmeasured.
- **R26** — If a value could not be measured, then the lifecycle shall not record it as zero.

### Optional

- **R21** — Where a backlog item names a Jira key, the lifecycle shall read that item's status from Jira and shall write nothing back.
  Superseded by R27. Split into R27 and R28 — the sentence carried two obligations under one id, so a test could satisfy one half and leave the other unasserted.

- **R22** — Where a repository declares its own check tools, the lifecycle shall run them only if the configuration explicitly opts in.
- **R27** — Where a backlog item names a Jira key, the lifecycle shall read that item's status from Jira.
- **R28** — Where a backlog item names a Jira key, the lifecycle shall write nothing back to Jira.

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
| R1 | `spec-home` check over `check-spec-home.sh` — reads `product.spec_home`, refuses a repo it cannot open rather than counting it as having no spec. Declared and passing 2026-08-30. Its limitation is declared with it: a product whose repos are not all declared is invisible to it. |
| R2 | `references/ears.md` id-lifecycle rules; reviewed at intake |
| R5 | `scripts/run-checks.sh` coverage assertion; `hollow` path |
| R11 | `scripts/build-view.sh` — byte-identical across runs and timezones |
| R15 | `run-checks.sh` hollow detection — proven on a stub and on real semgrep |
| R17 | `templates/publish-gate.sh` — 42-case block corpus, 41-case allow corpus |
| R18 | `run-checks.sh` argv[0] validation — shells, interpreters, repo-local paths |
| R20 | `scripts/import-survey.sh` Verdict section |
| R22 | `policy.allow_repo_local_tools`, default false |
| R23 | Two halves, asserted separately. **Stop:** `scripts/contradiction-check.py --selftest` — 7 true positives, precision 1.00 (inherited from R14). **Ask:** `ruling-requested` check over `check-ruling-requested.sh` — fails when a concern is open with no ruling file, when a pending ruling is cited by nothing, and when a pending ruling still wears the template. Proven by removing a raised ruling and watching it go red 2026-08-30 |
| R24 | not yet verified — R14's checks asserted the stop; no check yet observes that nothing was merged |
| R25 | `check-hygiene.sh`, `stage-status.sh`, `build-view.sh` unmeasured states (inherited from R16) |
| R26 | not yet verified — inherited from R16, whose checks observe the unmeasured report, not the absence of a recorded zero |
| R27 | not yet verified — R21 carried no acceptance-criteria row |
| R28 | not yet verified — R21 carried no acceptance-criteria row |
| R3 | `superseded-text` check over `check-superseded-text.sh` — diffs each superseded requirement's text against the last commit at which it was still active, choosing that baseline per requirement. The first check here to read git history. Falsified by editing a superseded sentence and watching it go red; a shallow clone is refused, never passed. |
| R4 | `view-read-only` check — both halves. The generator moves no repository file (every file hashed before and after, content and mtime), and the page declares no capability that can publish a new version of itself. Falsified four ways on the first half and three on the second; a page that could not be built is exit 2, never zero capabilities. |
| R6 | `classification-provenance` check — asserts every active requirement id was in the context the classification was made from, and that exactly one classification was recorded. Falsified by dropping an active id from a record's scope list. |
| R7 | **Contested.** 2026-08-30: R7 requires every classification in the spec's change log, but that log is one row per commit to this file, and a classification that merges nothing commits nothing. Ruled too broad; to be refined so only a classification reaching the spec belongs here. Until then two classifications (B23, B26) sit in the backlog and their issues, not here |
| R8 | `acceptance-rows` check — asserts every active requirement has a row here. Superseded, withdrawn and inferred requirements are exempt, the last per `references/import.md:70`. Measured 2026-08-30: 25 active, 25 rows. |
| R9 | `guide-current` check over `build-guide.sh --check` — regenerates the guide's requirements section into memory and reports drift without writing. Falsified by weakening a requirement's wording inside the markers; missing markers are refused rather than guessed at. |
| R10 | `import-marking` check — fails a requirement attributed to an import that carries no inferred marking. Attribution is structural, from a marked sibling's change-log row or introducing commit; the naive signal (the word *import* in a message) was built first and measured as unusable. **Declared limitation:** an import that marked nothing and named no stage is invisible, and the run says so. |
| R12 | `pending-ruling-scope` check — refuses a spec change touching the requirement a pending ruling names, and prints the allocations it lets through so the decision not to block is visible. Falsified both ways: the contested requirement blocks, an unrelated one does not. |
| R13 | `missing-tool-reported` check over a committed fixture in `fixtures/missing-tool/` — six assertions, including that an absent tool changes the VERDICT and not only the status, because a status that does not change the verdict is a skip wearing a different name. The fixture guards its own premise: point it at an installed tool and it reports unmeasured, not a pass. |
| R19 | `classification-provenance` check — every classification records the spec commit and content hash it was made against. An unreachable spec home yields no hash and the writer creates nothing at all, so classifying from a remembered copy is impossible to record rather than merely forbidden. Falsified: unreadable spec, no store directory created. |

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
| 2026-08-29 | — | — | R23–R28 | — | R14 → R23, R24; R16 → R25, R26; R21 → R27, R28 | Each of the three carried two `shall` clauses under one id. Split so every obligation has its own id and neither half can be half-tested. Originals retained verbatim, marked superseded. |

## Decision record

Decisions that shaped the spec but are not themselves requirements — including
every contradiction ruling.

| Date | Decision | Why | Who |
|---|---|---|---|
| <YYYY-MM-DD> | <what was decided> | <the reason, not the restatement> | <name> |
| 2026-08-29 | Split R14, R16 and R21 into new ids rather than editing them in place or amending the one-`shall` rule | A split is not a refinement: two obligations cannot share one id, and the id is what tests and plans cite. Editing in place would leave every existing citation pointing at half of what it used to mean. Amending the rule was the other option `ears.md` names, and was rejected because the rule is what makes a requirement single-assertion testable. | — |
