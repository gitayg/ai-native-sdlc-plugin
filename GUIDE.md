# AI-Native SDLC — one-page guide

Code stopped being the bottleneck. The stages around it — planning, review,
deployment, maintenance — still run at human speed, and that is where the time
now goes. This plugin runs a six-stage lifecycle where **every stage leaves a
committed record and the next stage begins by reading it**.

An intent is an **input**, not a file you keep. It is classified against the
repo's living spec, merged in, and the work is built from what the spec gained:

```
intent (issue | text box | file)
  → intake → living spec → plan.md → diff + tests → PR → incident → new intent
```

The spec lives at `.claude/sdlc/spec.md` — one per repo, always current, and
inside `.claude/` so no build, packaging step or doc generator ever picks it up.
The record of any single change is the spec diff, joined to its issue by the
branch name and PR title.

## Install

```bash
claude plugin marketplace add gitayg/ai-native-sdlc-plugin
claude plugin install ai-native-sdlc
```

Already have a personal copy at `~/.claude/skills/ai-native-sdlc/`? Move it
aside. Plugin skills are namespaced, so they do not replace it — both load, both
compete for the same triggers, and `claude plugin update` moves only one of
them. Two copies is silent drift.

## First run in a repo

Just describe what you want. The skill works out which stage you are in from
the issue and the branch, so it knows whether you are starting or resuming.

The first time it needs GitHub or Jira, it asks once — repo, source of truth,
project key — and writes `.claude/sdlc.json`. It never asks again in that repo,
and it never asks at all in a scheduled run, where nobody is there to answer.

"Skip Jira — GitHub only" is a real answer, not a half-configuration.

## The six stages

| | You do | You get |
|---|---|---|
| **1 Plan** | describe the problem in plain language | a labelled issue |
| **2 Design** | rule on anything that contradicts the spec | a spec delta, in EARS |
| **3 Build** | interrogate the plan before any code | `plan.md`, then the implementation |
| **4 Test** | nothing — it verifies before you look | passing checks, pasted |
| **5 Deploy** | judge intent and risk, not mechanics | draft PR, review findings |
| **6 Maintain** | triage what production surfaced | a new issue, back to stage 1 |

Stages never skip forward, and nothing plans from an intent that has not been
through intake — until then you cannot know whether the work extends the spec or
contradicts it, and the second one is a stop, not a task.

## The four answers intake can give

Every intent is classified against the whole current spec, and only two of the
four produce work:

| | Meaning | What happens |
|---|---|---|
| **Extend** | not covered yet | new requirement ids, written in EARS |
| **Refine** | right but imprecise | same id, tightened, recorded |
| **Duplicate** | already specified | cite the id and stop |
| **Contradict** | the spec forbids what you asked for | **stop and ask which wins** |

That last row is the point of the whole design. A per-feature spec cannot detect
a contradiction, because it does not know what else was ever agreed. A living
spec can — and when it finds one, nothing is merged until a human rules. Agreed
behaviour never changes because a newer sentence arrived later.

Requirement ids are permanent. Nothing is deleted; a replaced requirement is
marked `Superseded by R58.` and keeps its original text, because plans, tests,
review findings and PR titles all cite these ids, and a reused id redirects every
one of those citations silently.

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
holds `.claude/sdlc/spec.md`; the others point at it:

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
(`.claude/sdlc.json`), the artifacts (`docs/sdlc/`), the review policy
(`REVIEW.md`), the bands (`ops/bands.yaml`). The templates that shape them
can be too:

```
.claude/sdlc/templates/spec.md     this repo's spec shape
.claude/sdlc/templates/REVIEW.md   this repo's review passes
```

Repo-first, plugin as fallback. Commit only what differs — one file overrides
one template and inherits the rest — and a plugin update never touches them.
Same idea as `CLAUDE.md`: the repo's conventions belong to the repo.

## Two things that run without you

- **Nightly evals** regression-test your agent configuration — `CLAUDE.md`,
  skills, hooks — against real past tasks. It reports; it cannot block a merge.
  If you need a gate, that one belongs in CI.
- **Control bands** watch a metric and act by tier: 1σ log, 2σ diagnose
  read-only, 3σ propose via PR. Detection is deterministic — no model decides
  whether something broke. A finding is opened as an issue and goes through
  intake like any other intent, which is how the loop closes — and what stops a
  production signal silently contradicting an agreed requirement.

The skill installs both, refuses to install an eval task against an empty suite,
and warns that scheduled tasks only run while the app is open.

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
