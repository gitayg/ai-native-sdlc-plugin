# AI-Native SDLC — one-page guide

Code stopped being the bottleneck. The stages around it — planning, review,
deployment, maintenance — still run at human speed, and that is where the time
now goes. This plugin runs a six-stage lifecycle where **every stage ends by
committing an artifact and the next stage begins by reading it**.

That chain is the whole idea. It is also the audit trail:

```
intent.md → spec.md → plan.md → diff + tests → PR + findings → incident → intent.md
```

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

Just describe what you want. The skill locates the work by looking at which
artifacts already exist, so it knows whether you are starting or resuming.

The first time it needs GitHub or Jira, it asks once — repo, source of truth,
project key — and writes `.claude/sdlc.json`. It never asks again in that repo,
and it never asks at all in a scheduled run, where nobody is there to answer.

"Skip Jira — GitHub only" is a real answer, not a half-configuration.

## The six stages

| | You do | You get |
|---|---|---|
| **1 Plan** | describe the problem in plain language | `intent.md`, committed |
| **2 Design** | review the spec against your intent | `spec.md` with EARS requirements |
| **3 Build** | interrogate the plan before any code | `plan.md`, then the implementation |
| **4 Test** | nothing — it verifies before you look | passing checks, pasted |
| **5 Deploy** | judge intent and risk, not mechanics | draft PR, review findings |
| **6 Maintain** | triage what production surfaced | a new `intent.md` |

Stages never skip forward. No `spec.md` means no `plan.md` — it will say what is
missing rather than invent it.

## What makes stage 2 matter

Requirements are written in EARS — one requirement per sentence, one `shall`
each, numbered and never renumbered:

> When `<trigger>`, the `<system>` shall `<response>`.
> If `<unwanted trigger>`, then the `<system>` shall `<response>`.

The response must be observable from outside the system, or it is a design note,
not a requirement. This is what turns "do the tests actually assert the
criteria?" from an argument into a check. A spec with no `If` requirements has
not considered failure, and the tests will inherit that gap.

## Two things that run without you

- **Nightly evals** regression-test your agent configuration — `CLAUDE.md`,
  skills, hooks — against real past tasks. It reports; it cannot block a merge.
  If you need a gate, that one belongs in CI.
- **Control bands** watch a metric and act by tier: 1σ log, 2σ diagnose
  read-only, 3σ propose via PR. Detection is deterministic — no model decides
  whether something broke. Findings arrive as an `intent.md` in your triage
  queue, which is how the loop closes.

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

1. Commit the artifact. Uncommitted means it did not happen.
2. Read the upstream artifact, do not re-derive it from conversation.
3. Flag policy conflicts; never silently pick a winner.
4. Verify before reporting done, and paste the output.
5. Fix the code, not the test.
6. The agent acts up to the production gate and never past it.

Humans keep every judgement. Configuration handles the mechanics.
