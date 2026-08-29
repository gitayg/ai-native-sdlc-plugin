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

## The rules it will not bend

1. Leave the record. Work that changed no spec and cites no issue did not happen.
2. Read the whole spec before changing it, not just the conversation.
3. A contradiction stops the work until a human rules.
4. Flag policy conflicts; never silently pick a winner.
5. Verify before reporting done, and paste the output.
6. Fix the code, not the test.
7. The agent acts up to the production gate and never past it.

Humans keep every judgement. Configuration handles the mechanics.
