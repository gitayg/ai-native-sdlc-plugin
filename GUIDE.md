# Productizer — one-page guide

Code stopped being the bottleneck. The stages around it — planning, review,
deployment, maintenance — still run at human speed, and that is where the time
now goes. This plugin runs a nine-stage lifecycle where **every stage leaves a
committed record and the next stage begins by reading it**.

An intent is an **input**, not a file you keep. It is classified against the
repo's living spec, merged in, and the work is built from what the spec gained:

```
intent (issue | text box | file)
  → intake → living spec → plan.md → diff + tests → PR → incident → new intent
```

The spec lives at `.claude/productizer/spec.md` — one per product, always
current, and inside `.claude/` so no build, packaging step or doc generator
ever picks it up. The record of any single change is the spec diff, joined to
its issue by the branch name and PR title.

## Install

```bash
claude plugin marketplace add gitayg/productizer
claude plugin install productizer
```

Already have a personal copy at `~/.claude/skills/spec/`? Move it
aside. Plugin skills are namespaced, so they do not replace it — both load, both
compete for the same triggers, and `claude plugin update` moves only one of
them. Two copies is silent drift.

### Three commands, typed with a slash

Everything below can also be reached by asking in English — the skill triggers
on what you are trying to do, not on a keyword. The slash forms exist because a
capability nobody can find is one nobody uses, and a menu you can scroll beats
remembering the sentence that triggers it.

| | |
|---|---|
| `/productizer:help` | every command, read from the installed plugin rather than from memory |
| `/productizer:dashboard` | regenerate the view from this repo's files and publish it |
| `/productizer:check` | run the declared checks over the current change |
| `/productizer:backlog` | the queue in front of the lifecycle — see it, add to it, start an item |
| `/productizer:answer` | every question the repo is holding open for a person, one at a time |
| `/productizer:import` | a repo that already exists — draft from its evidence, or read that evidence as drift if it already has a spec |
| `/productizer:spec` | the whole lifecycle — intake, classification, deltas, releases |

Type `/productizer` and the menu lists them. The bare forms — `/dashboard`,
`/check` — work too unless another plugin has claimed the name.

All four are marked so the model will not invoke them on its own. One publishes
a page, one runs every declared tool in the repo, one edits the queue and one
starts asking you questions — none of those should happen because a sentence
sounded like a request for it. You type those. `spec` is the opposite: it is
meant to trigger from what you are doing.

`answer` is the one worth knowing about. It reads the spec, the rulings and the
backlog and finds what is genuinely waiting on a person — a requirement nothing
asserts, a contradiction nobody ruled, an item that named what it is blocked on
— then puts them **one at a time**, with what it already found about each. It
caught nine stale rows on its first run: requirements whose verifiers had been
built and declared while the table still said nothing asserted them.

## First run in a repo

Just describe what you want. The skill works out which stage you are in from
the issue and the branch, so it knows whether you are starting or resuming.

The first time it needs GitHub or Jira, it asks once — repo, source of truth,
project key — and writes `.claude/productizer/config.json`. It never asks again
in that repo, and it never asks at all in a scheduled run, where nobody is
there to answer.

"Skip Jira — GitHub only" is a real answer, not a half-configuration.

Scaffolding writes an **empty** spec and an **empty** constitution. The templates
carry worked examples so you can see the shape — `R1`…`R6`, `P1`…`P5` — and
`scripts/scaffold.sh` strips them on the way in. A seeded requirement is one
nobody agreed to, and it gets cited before anyone notices it was a sample. The
script also refuses to overwrite, and refuses a destination `.gitignore` would
swallow, because a spec that cannot be committed is not an audit trail.

If the repo already has history, Stage 0c surveys it first. When the survey
finds too little to work from it says so and stops, rather than handing the
drafting step an empty page to invent on.

## The stages

| | You do | You get |
|---|---|---|
| **1 Plan** | describe the problem in plain language | a labelled issue |
| **2 Design** | rule on anything that contradicts the spec | a spec delta, in EARS |
| **3 Build** | interrogate the plan before any code | `plan.md`, then the implementation |
| **4 Test** | nothing — it verifies before you look | passing checks, pasted |
| **5 Check** | declare which checks matter, once | a result that says what was examined |
| **6 Deploy** | judge intent and risk, not mechanics | draft PR, review findings |
| **7 Document** | nothing — it reads the spec | the user guide, regenerated per release |
| **8 Announce** | publish it yourself | a drafted post and release email |
| **9 Maintain** | triage what production surfaced | a new issue, back to stage 1 |

Stages never skip forward, and nothing plans from an intent that has not been
through intake — until then you cannot know whether the work extends the spec or
contradicts it, and the second one is a stop, not a task.

## The backlog, in front of all of it

Stage 1 assumes an intent exists. In practice somebody wanted the thing weeks
earlier, and in between it lived in a head or a Slack thread. The backlog is
where that waiting happens on purpose — `.claude/productizer/backlog.md`,
`B`-numbered, ordered by priority.

**There is no priority field.** The order of the file is the ranking. Two
representations of one ordering disagree the first time someone edits one and
not the other, and then nobody can say which is the real queue.

**Nothing in it is agreed.** An item can be picked up, taken through intake, and
refused for contradicting a requirement settled two years ago. That is intake
working, and it is exactly why the backlog is not a second spec.

Five statuses: `todo`, `long-term`, `in-progress`, `blocked`, `done` — where
`done` means *left the queue*, not *shipped*. What shipped is a question for the
spec and the release history.

**An item can name a Jira key, and then Jira owns its status.** The mapping is
declared once in `.claude/productizer/config.json`, and nothing is ever written
back: a markdown table arguing with a Jira workflow, a board filter and three
automation rules loses, and loses silently. Move the ticket in Jira.

The published backlog view is the one view you may rearrange, because reordering
changes nothing that was agreed. Even then it does not write the file — it hands
you the reordered table to paste. Files stay the only edit surface.

## The four answers intake can give

Every intent is classified against the whole current spec, and only two of the
four produce work:

| | Meaning | What happens |
|---|---|---|
| **Extend** | not covered yet | new requirement ids, written in EARS |
| **Refine** | right but imprecise | same id, tightened, recorded |
| **Duplicate** | already specified | cite the id and stop |
| **Contradict** | the spec forbids what you asked for | **stop and ask which wins** |

That last row is the point of the whole design, and it is the one thing this does
that the alternatives do not. Spec Kit, OpenSpec and BMAD are all good and all
more popular; two of them can even name a conflict. None of them stop — Spec Kit
"recommends resolving", BMAD surfaces the conflict and applies the change anyway.
Detection that does not halt is advice, and advice gets skimmed.

This is not a new idea. Requirements engineering has argued for set-level
consistency since Nuseibeh and Easterbrook in 2000, and ISO/IEC/IEEE 29148 lists
it as a property a requirement set must have. What seems to be new is shipping it
inside an AI coding agent, where the halt actually lands on the thing writing the
code.

Requirement ids are permanent. Nothing is deleted; a replaced requirement is
marked `Superseded by R58.` and keeps its original text, because plans, tests,
review findings and PR titles all cite these ids, and a reused id redirects every
one of those citations silently. BMAD holds the same rule in nearly the same
words, so this is table stakes done properly rather than a differentiator — but
most tools renumber per feature, which breaks every citation you ever wrote.

## Where all the intents live

There is no folder of intents to manage. Under the `issues` model an intent is a
labelled issue on the repo it concerns, which makes "what is in flight across
every repo" one query:

```bash
gh search issues --owner YOUR-ORG --label sdlc:intent --state open --limit 100
```

Two things to know before relying on that: `--limit` caps at 1000 with no paging
past it, and an empty result is indistinguishable from a label that exists
nowhere — both print nothing and exit 0. Validate a negative with a label you
know exists.

## What makes stage 2 matter

Requirements are written in EARS — one requirement per sentence, one `shall`
each, numbered and never renumbered:

> When `<trigger>`, the `<system>` shall `<response>`.
> If `<unwanted trigger>`, then the `<system>` shall `<response>`.

The response must be observable from outside the system, or it is a design note,
not a requirement. This is what turns "do the tests actually assert the
criteria?" from an argument into a check. A spec with no `If` requirements has
not considered failure, and the tests will inherit that gap.

## Products can span repos

A product is one or more repos. Exactly one of them is the **spec home** and
holds `.claude/productizer/spec.md`; the others point at it:

```json
"product": {
  "name": "orders",
  "spec_repo": "acme/orders-api",
  "repos": ["acme/orders-api", "acme/orders-web"]
}
```

One spec, one id space, one allocator. It has to work this way: two allocators
both hand out `R42`, and a reused id silently redirects every test, plan and PR
that cites it. It also means contradiction detection covers the whole product —
a front end and its API can no longer agree to opposite behaviour, which is
exactly where that bug lives.

A single-repo product is the ordinary case: it is its own spec home and nothing
extra happens.

## Seeing it

Files are what you edit. When you want to *look* instead, ask — "show me the
pipeline", "let me see the spec" — and you get a published view: the fleet
across every repo, one product's spec, an intake classification, or a band's
history. Each is regenerated from the files and republished to the same URL, so
you get one link per view rather than one per glance.

Views are read-only by design. Nothing is ever read back out of one into the
spec: the moment a view became the thing you edit, the committed chain would
stop being the audit trail.

## Make it yours, per repo

Everything the lifecycle produces already lives in the repo: the binding
(`.claude/productizer/config.json`), the artifacts (`docs/sdlc/`), the review
policy (`REVIEW.md`), the bands (`ops/bands.yaml`). The templates that shape
them can be too:

```
.claude/productizer/templates/spec.md     this repo's spec shape
.claude/productizer/templates/REVIEW.md   this repo's review passes
```

Repo-first, plugin as fallback. Commit only what differs — one file overrides
one template and inherits the rest — and a plugin update never touches them.
Same idea as `CLAUDE.md`: the repo's conventions belong to the repo.

## Two things that run without you

- **Nightly evals** regression-test your agent configuration — `CLAUDE.md`,
  skills, hooks — against real past tasks. It reports; it cannot block a merge.
  If you need a gate, that one belongs in CI.
- **Control bands** — Anthropic's design from the playbook, not ours — watch a
  metric and act by tier: 1σ log, 2σ diagnose
  read-only, 3σ propose via PR. Detection is deterministic — no model decides
  whether something broke. A finding is opened as an issue and goes through
  intake like any other intent, which is how the loop closes — and what stops a
  production signal silently contradicting an agreed requirement.

The skill installs both, refuses to install an eval task against an empty suite,
and warns that scheduled tasks only run while the app is open.

## The checks are yours to declare

Stage 5 runs whatever you put in `.claude/productizer/checks.yaml` — a secret
scan on every change, a linter on the paths that have one, a heavier ruleset on
anything touching auth. Triggers are `always`, path globs, or **requirement
tags**, which is what makes the scrutiny per-item: an auth requirement earns
the auth ruleset, a copy edit does not.

Every check states what it must have examined, and that is the part that
matters. A scanner reporting *Grade A (100/100)* after opening one file of
forty-eight is not a pass, and without a coverage assertion it is
indistinguishable from one. A check that exits clean having examined less than
it declared comes back **hollow**, and hollow blocks like a failure.

Commands are argv lists, never shell strings. The file is committed, so a string
would let anyone who lands a commit choose what runs on the machine of whoever
pulls it.

### The hygiene check is two checks

The one that ships carries **generic** rules only — credential shapes, personal
filesystem paths, machine hostnames, private key headers. Everything any repo
needs, and nothing that identifies anyone.

Names you cannot publish go in a **local list** the shipped check reads at
runtime: `--patterns FILE`, else `$PRODUCTIZER_HYGIENE_PATTERNS`, else
`.claude/productizer/hygiene-local.txt`, which you gitignore.

The split exists because a single list has to spell the private names in order
to catch them — so in a public repo the gate publishes exactly which names its
author is hiding. A deny list is a map of what someone is protecting.

If the local list is named and unreadable the check exits 2, never 0. A
configured private list that quietly fell back to generic-only would report
clean while checking none of the names you cared about.

### A contradiction now writes the question down

Classifying an intent as *contradict* stops the work, and a stop nobody was
asked to answer is indistinguishable from a stop that was abandoned. So the
ruling is drafted **before** the question is asked out loud: `request-ruling.sh`
allocates the ids, writes both requirements verbatim, fills both columns of the
cost table, adds the concern row, and prints the path to name in the message.
Ask first and write after, and the session can end before anything exists.

`pending-rulings.sh` reports what is waiting — keeping *never raised one*,
*cannot read the directory* and *genuinely none* as three different answers,
because only the third one is zero. The `ruling-requested` check fails when a
concern is open with no ruling behind it, when a pending ruling is cited by
nothing, and when a pending ruling is still wearing the template. A ruling that
still reads like the template is a file, not an ask.

## Docs and go-to-market, per release

Two stages run once per **release**, not once per intent.

**7 Document** regenerates the user guide from the active spec. Per intent you
would get a changelog with headings — every entry accurate, the document as a
whole describing no product. Per release is also the only cadence at which
removals are visible: within one change a superseded requirement looks like an
edit, but across a release the superseded and withdrawn ids are exactly the list
of things that used to work and no longer do. Screenshots are captured from the
released build with the version in the filename, because prose gets reviewed and
images do not.

**8 Announce** drafts the release post and the release email from the spec
deltas and the merged PRs. Every claim traces to one of them, every number was
measured, and the post names the adjacent thing the release does *not* do.

**Agent-driven, human-gated.** Stage 8 runs as an agent stage like the others —
it writes both artefacts, captures the screenshots, checks the release is
actually installable, and reports what it could not verify. The publish itself
is a hook (`publish-gate.sh`), not a convention: it blocks `gh release create`,
`npm publish`, a tag push, a mail API and a site deploy, and allows everything
the agent needs for its own work. A rule the agent is only asked to remember is
a rule it eventually reasons past.

## Choosing the model per stage

Each stage names a model and an effort in `.claude/productizer/config.json`,
shipped with recommended defaults. Two halves, and they are not
interchangeable: a stage that starts a **subagent** carries the setting in
frontmatter and it is enforced; a stage that runs **in your session** inherits
your session model whatever the file says, so the skill tells you which stage
it is entering instead of pretending to have applied something.

Effort buys most at **intake** and **review** — low volume, expensive to get
wrong. It buys least on nightly evals and 2σ diagnosis, which run constantly and
have right answers. Running everything at high effort is the same care with a
larger bill, and it makes the nightly suite expensive enough to switch off.

Stage 5 takes **no model at all**. It compares coverage arithmetically; a model
asked *did this check pass* believes the green summary line, which is the
failure the stage exists to prevent.

## Starting from a repo that already exists

Stage 0c surveys a repo with history — routes, tests, error paths, config — and
drafts at most 30 requirements from what it found, each carrying the file, line
or test it came from. **Every one lands `inferred` and unconfirmed.** Inferred
requirements cannot trigger the contradiction stop, or the lifecycle starts
defending whatever the code happened to do on import day, bugs included. A
human confirming one promotes it, and that promotion is a commit.

## Optional: delegate the middle

If you have a real check runner — plan-vs-diff, tests-vs-criteria, a pre-push
gate — point at it and stages 3-5 delegate to it instead:

```bash
export SDLC_CHECK_RUNNER="/path/to/your/check-runner"
```

Enforced beats advisory. The skill probes by *running* it, never by checking the
file exists, and tells you which way it resolved.

## What it guarantees today

Everything above argues for the shape. This is the agreed set — the requirements
the spec holds active right now, in the EARS patterns stage 2 writes them in, and
nothing else. It is the one part of this page nobody edits by hand: stage 7
regenerates it from `.claude/productizer/spec.md` on every release, so a guide
promising behaviour nobody agreed to would have to survive a release to do it.
Edit the spec; this section follows.

<!-- productizer:requirements:begin -->
<!-- Generated from `.claude/productizer/spec.md` by
     plugins/productizer/skills/spec/scripts/build-guide.sh. Everything between
     these two markers is rewritten on every release - edit the spec, not this. -->

**Twenty-five requirements are active**, and they are the whole of what has
been agreed.

Three more are superseded and none withdrawn, and neither kind is listed here.
The spec keeps both forever with their text intact, so a citation written two
years ago still leads somewhere — but a guide is read by someone deciding what
to do next, and a superseded sentence gives them no sign it stopped being
true.

**Always, with no trigger.** Five requirements hold whatever else is
happening:

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent: never reused,
  never renumbered.
- **R3** — The lifecycle shall keep a replaced requirement's original text in
  the spec, marked superseded.
- **R4** — Every published view shall be read-only with respect to the spec.
- **R5** — Every check shall declare what it must have examined for its pass
  to count.

**When something arrives.** Six things happen on a discrete trigger:

- **R6** — When an intent arrives, the lifecycle shall classify it against the
  whole living spec as exactly one of extend, refine, duplicate or contradict.
- **R7** — When an intent is classified, the lifecycle shall record the
  classification in the spec's change log.
- **R8** — When a requirement is added, the lifecycle shall allocate the next
  unused id and record it in the acceptance criteria table.
- **R9** — When a release is prepared, the lifecycle shall regenerate the user
  guide from the active requirements.
- **R10** — When a repository with history is imported, the lifecycle shall
  mark every drafted requirement inferred and unconfirmed.
- **R11** — When a published view is regenerated, the lifecycle shall read
  every figure in it from a file in the repository.

**For as long as a state lasts.** Two requirements are true for the duration
of a state, not at a moment inside it:

- **R12** — While a contradiction is unruled, the lifecycle shall merge no
  spec change that depends on it.
- **R13** — While a check tool named by the configuration is absent, the
  lifecycle shall report that check as missing rather than skipped.

**When something goes wrong.** Nine defences, written as `If … then` because a
designed path and a defended one are not the same thing:

- **R15** — If a check exits zero having examined less than it declared, then
  the lifecycle shall report it as hollow and treat it as a failure.
- **R17** — If a command would publish or deploy, then the gate shall block it
  until a person approves.
- **R18** — If a configured command names a shell or an interpreter with an
  inline program, then the lifecycle shall refuse to run it.
- **R19** — If the spec home is unreachable, then the lifecycle shall stop
  rather than classify against a remembered copy.
- **R20** — If a survey finds too little evidence to draft from, then the
  lifecycle shall refuse to draft a spec from it.
- **R23** — If an intent contradicts an active requirement, then the lifecycle
  shall stop and ask which wins.
- **R24** — If an intent contradicts an active requirement, then the lifecycle
  shall merge nothing.
- **R25** — If a value could not be measured, then the lifecycle shall report
  it as unmeasured.
- **R26** — If a value could not be measured, then the lifecycle shall not
  record it as zero.

**Only where the feature is present.** Three requirements apply only to a
build that includes the feature:

- **R22** — Where a repository declares its own check tools, the lifecycle
  shall run them only if the configuration explicitly opts in.
- **R27** — Where a backlog item names a Jira key, the lifecycle shall read
  that item's status from Jira.
- **R28** — Where a backlog item names a Jira key, the lifecycle shall write
  nothing back to Jira.

Every id above is permanent. A plan, a test or a PR title naming `R1` will
still mean this sentence in two years, which is why ids are never reused and
never renumbered. The whole spec — the superseded text included, with the
acceptance criteria and the change log — is at `.claude/productizer/spec.md`.
<!-- productizer:requirements:end -->

## The rules it will not bend

1. Leave the record. Work that changed no spec and cites no issue did not happen.
2. Read the whole spec before changing it, not just the conversation.
3. A contradiction stops the work until a human rules.
4. Flag policy conflicts; never silently pick a winner.
5. Verify before reporting done, and paste the output.
6. Fix the code, not the test.
7. The agent acts up to the production gate and never past it.

Humans keep every judgement. Configuration handles the mechanics.
