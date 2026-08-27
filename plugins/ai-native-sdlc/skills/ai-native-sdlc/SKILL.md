---
name: ai-native-sdlc
description: "Run the AI-native software lifecycle: capture an idea as intent.md, turn it into spec.md, plan it as plan.md, build with CLAUDE.md/skills/hooks, verify with evals, review and gate deploys, and close the loop from production back to intent.md. Use whenever the user starts a new feature, idea or change and wants it done properly end-to-end; asks for an intent, spec, implementation plan, CLAUDE.md, review policy, approval gate, eval suite or control bands; asks how to adopt Claude across an SDLC or make agentic development governable/auditable; or asks what stage a piece of work is in and what comes next. Also use when wiring this lifecycle to Jira or GitHub — picking a source of truth, binding a project key or repo, or moving tickets and opening PRs as stages complete. Triggers on 'AI-native SDLC', 'intent.md', 'spec.md', 'plan.md', 'REVIEW.md', 'bands.yaml', 'agent governance', 'plan mode first'."
---

# AI-Native SDLC

Code is no longer the bottleneck. The stages around it are. This skill runs a
six-stage lifecycle where **each stage ends by committing an artifact and the
next stage begins by reading it**. That chain is the audit trail:

```
intent.md → spec.md → plan.md → diff + tests → PR + review findings → incident record → intent.md
```

## Stage 0 · Bind to your systems

Before the first stage that touches Jira or GitHub, run:

```bash
~/.claude/skills/ai-native-sdlc/scripts/detect-context.sh
```

It reports the git remote and repo slug, `gh` auth state and account, Jira env
state, which artifacts already exist, and whether this session is interactive.

Resolve every setting in this order, stopping at the first hit: **detected →
`.claude/sdlc.json` → ask → environment → fail loudly.**

- **Assume nothing exists. Ask for both.** Detection *prefills* the answer, it
  does not replace the question. There may be no git repo at all, no remote, a
  non-GitHub remote, or an `origin` that is not where these artifacts belong —
  all normal starting states, none of them an error.
- **One `AskUserQuestion` call, three questions**, so the user answers a single
  prompt: GitHub repo, source of truth, Jira site/project. Put the detected
  value first and label it `(detected)` when there is one.
- **Every question has an escape hatch.** "No repo yet — local only" and "Skip
  Jira — GitHub only" are valid configurations, recorded as `null` and never
  asked about again. A half-answered config is still a finished config.
- **Ask once per repo**, on the first stage that touches an external system —
  Stage 1 if a ticket carries the intent, Stage 5 if it is GitHub only.
- **Write the answers to `.claude/sdlc.json`** (template:
  `templates/sdlc-config.json`) and name the path. That file is why you only
  ask once.
- **Never ask where nobody is present.** Gate on the detected `interactive`
  flag, not on the stage number. This lifecycle runs on two surfaces: the
  **interactive session**, which is the default for every stage, and **local
  scheduled tasks** for the nightly eval regression (4B) and the band check
  (6A). A scheduled run starts fresh with no memory of any conversation, so it
  cannot ask — it reads `.claude/sdlc.json`, which the interactive session
  wrote. If the config is missing, the run reports what it needs and stops; it
  never prompts. `JIRA_API_TOKEN` still comes from the environment. Surfaces
  and their limits: `references/running-it.md`.
- **Secrets never enter the config file.** It gets committed; it holds
  identifiers only. `JIRA_API_TOKEN` lives in the environment. Do not ask the
  user to paste a token into the chat and do not write one to disk.

Commands, the REST recipes, transition handling and the three source-of-truth
models are in `references/integrations.md`. Read it before the first Jira or
GitHub write.

## Stage 0b · Install the scheduled tasks

The two unattended plays are installed **by this skill**, not by hand. Do it
once per repo, after `.claude/sdlc.json` exists — never before, because the task
prompt has to carry a real repo path.

**Always list before creating.** Call `list_scheduled_tasks` first. Task ids are
namespaced per repo so several repos can coexist:

| Task id | Source prompt | Default cron | Installs when |
|---|---|---|---|
| `sdlc-evals-<repo-slug>` | `templates/scheduled-evals.md` | `0 2 * * *` | `evals/` exists **and holds at least one eval** |
| `sdlc-bands-<repo-slug>` | `templates/scheduled-bands.md` | match the metric | `ops/bands.yaml` exists |

If the id is already there, call `update_scheduled_task` — never create a second
task with a new id, which silently doubles the nightly run.

**Refuse to install an eval task with no evals.** An empty suite reports green
every single night, which is worse than no task at all: it manufactures evidence
that nothing regressed. Say the suite is empty, skip the install, and offer to
build the first evals from recent real tasks.

**Pick the band cron from how fast the metric moves**, not by habit — hourly for
post-deploy error rate, daily for CI failure rate or PR cycle-time drift. Ask if
`ops/bands.yaml` does not make it obvious.

To install: read the template, replace `<REPO PATH>` with the absolute path,
and pass the result as `prompt` with `notifyOnCompletion: true` so findings reach
a session where a human can triage them. Then tell the user the task id, the
schedule and the next run time.

Warn once, at install: **tasks only run while the desktop app is open.** A task
due while it was closed runs at next launch instead, so an hourly band check will
have holes on days the app stays shut. If a metric genuinely cannot tolerate
gaps, that one belongs in CI.

To remove, disable the task by id — do not delete the template.

## First: locate the work

Before doing anything, find which stage this is and say so. Look for the
artifacts in the repo — they are the state machine.

| Present in repo | Stage to run |
|---|---|
| nothing yet | **1 · Plan** — write `intent.md` |
| `intent.md` committed | **2 · Design** — write `spec.md` |
| `spec.md` committed | **3 · Build** — plan mode, then `plan.md`, then implement |
| code changed, unverified | **4 · Test** — close the feedback loop before a human looks |
| change verified | **5 · Deploy** — review passes, gates, PR |
| running in production | **6 · Maintain** — bands, diagnosis, back to `intent.md` |

Never skip forward. If `spec.md` is missing, do not write `plan.md` — say what
is missing and offer to produce it.

## What this skill owns, and what it hands off

The lifecycle is six stages, but this skill is not the best tool for all of
them. Where a repo has a real check runner available — something that computes
plan-vs-diff, tests-vs-criteria and a pre-push gate, and exits non-zero when it
refuses — stages 3-5 are already covered by enforced code. Prose cannot compete
with that, and running both over the same work produces two sets of findings and
one confused engineer.

| Stages | Owner | Why |
|---|---|---|
| **1-2 · Plan, Design** | **this skill** | nothing else covers the step before a coding task exists |
| 3-5 · Build, Test, Deploy | delegate when available | enforced beats advisory; see `references/delegation.md` |
| **6 · Maintain** | **this skill** | nothing else turns a production signal back into an intent |

Probe before assuming either way, and **say which way it resolved** — being told
a tool is there when it is not is the more expensive mistake. When the probe
says absent, run stages 3-5 from the prose below and state that you are doing
so. Never reimplement their checks.

## The six stages

### 1 · Plan — capture as intent.md
Brainstorm conversationally until the idea is concrete, then write
`templates/intent.md`. The originator corrects the misunderstandings; you do
not decide what they meant. Commit it — git records author and timestamp, and
that commit *is* the approval evidence.

### 2 · Design — requirements and design in one pass
Read the approved `intent.md`. Produce `spec.md` (`templates/spec.md`, prompt
`templates/spec-command.md`) with the org's brand, security, compliance and UX
skills applied **while writing**, not as a review pass afterwards. Flag every
area of concern explicitly, especially where two policies contradict — name the
conflict and the policy owners, never silently pick a winner.

**Requirements are written in EARS** (`references/ears.md`): one requirement per
sentence, one `shall` each, numbered `R1`, `R2`, … and never renumbered. The
response must be observable from outside the system, or it is a design note
rather than a requirement. Unquantified adjectives — fast, robust, graceful,
appropriate — are arguments deferred to review; give a number or drop the word.
A spec with no `If <trigger>, then …` requirements has not considered failure,
and the tests will inherit that gap.

This is what makes Stage 4A's question — *do the tests actually assert the
criteria* — computable instead of a matter of opinion, and it is what a criteria
checker consumes downstream. Every requirement gets a row in the acceptance
criteria table; list the ones you could not map rather than omitting them.

### 3 · Build — plan first, knowledge as files
- **Plan mode is not optional.** Read-only first. Produce `plan.md`
  (`templates/plan.md`) naming files, order of work, risks and proof. Interrogate
  it — what breaks, what are the alternatives — until an unfamiliar engineer could
  implement from it. Commit it, then implement.
- **`CLAUDE.md`** (`templates/CLAUDE.md`) holds day-one knowledge, under one page.
  When the same mistake happens twice, the correction lands here.
- **Skills** for policy enforced inconsistently today
  (`templates/SKILL-secure-api-review.md`). Not for component-level knowledge,
  not for one-off prompts. Advisory: rare violations, not impossible ones.
- **Hooks** for what must be deterministic — protected paths, formatter, secrets.
  Fast and file-scoped. Heavy checks belong in Stage 4, approvals in Stage 5.
- **Parallel work** splits along files, using `plan.md` as the guide. Tasks sharing
  a file stay sequential. Each parallel task gets its own worktree. Repeated jobs
  become subagents (`templates/agent-verifier.md`).

### 4 · Test — verify before a human looks
- One command runs all checks. It is listed in `CLAUDE.md` with an example of
  healthy output and a quantifiable target (`templates/verification-section.md`).
- Bug fix: **write the failing test first and commit it before the fix.** A hook
  blocks edits to test files during the fix — the test is not the thing to fix.
- Never report a task done without running the checks and pasting the output.
- Agent configuration gets regression-tested like code. Default surface is a
  **nightly scheduled task** (`templates/scheduled-evals.md`) that runs the suite
  and reports pass-rate drift into the session. Every production incident earns a
  permanent eval. Note the trade-off: a schedule reports, it does not block — if
  you need it to gate a merge on `CLAUDE.md` / skills / hooks changes, that must
  run in CI (`templates/agent-evals.yml` with `templates/threshold.sh`).
- Keep refusal and crash distinguishable in the exit code. A gate that exits the
  same way when it says no as when it falls over is unreadable in a log, and the
  wrong thing gets fixed.

### 5 · Deploy — review both ways, gate hard
- Review policy is written down (`templates/REVIEW.md`): bugs, security,
  compliance-against-spec passes; Important vs Nit defined; nits capped.
- **Dispatch the review to a subagent with a clean context.** The session that
  wrote the code never reviews it — asked to, it re-derives its own reasoning
  and calls that confirmation.
- **Resolve the diff base before any pass runs**, and state it. A wrong base
  makes every finding confidently wrong at once, and an empty diff is far more
  often a base problem than a change that did nothing.
- **The agent never approves its own code.** Separation of duties holds.
- Agent output arrives as a PR through branch protection. There is no route to
  push main.
- Production is a hook, not a convention (`templates/production-gate.sh`). In
  regulated environments the non-negotiables live in
  `templates/managed-settings.json`, which engineers cannot override.
- **Secret checks go pre-push, not in CI.** A required check blocks a merge, but
  it runs after the push — by then the secret is on the remote and must be
  rotated. Blocking the merge is the whole remedy for a bad base, stray
  gitlinks or a failing eval; for a secret it fixes nothing.
  See `references/running-it.md`.
- Earn autonomy in order: read-only judgement → write steps behind existing
  gates → environment-tiered deploys. Rollback is the most rehearsed path.
- Triage runs **in the session**: bring the failing log or run id in, and read
  it directly (`gh run view <id> --log-failed`). Same judgement the article's
  `if: failure()` step makes, pulled rather than pushed — you decide when to
  ask. The CI form is `templates/triage-step.yml` if you later want it
  automatic.

### 6 · Maintain — close the loop
Detection is deterministic — no model in the detection path. Tiers live in
version-controlled config (`templates/bands.yaml`): 1σ log, 2σ diagnose
read-only, 3σ act via PR or pre-approved runbook. Findings are written as an
`intent.md` in Stage 1 format and enter a human triage queue. Dismissals tune
the bands. When the fix ships, add the eval.

Run it either way: **on a schedule** (`templates/scheduled-bands.md`) so breaches
find you, or **in the session** on demand when you already suspect something.
The scheduled form keeps the article's "no person in the path" property up to the
notification — after that a human triages, which was always the design.

## Non-negotiables

1. **Commit the artifact.** An artifact that is not committed did not happen —
   there is no audit trail without the git history.
2. **Read the upstream artifact.** Every stage starts by reading the previous
   one, not by re-deriving intent from the conversation.
3. **Flag conflicts, never resolve policy silently.**
4. **Verify before reporting done**, and paste the output.
5. **Fix the code, not the test.**
6. **Humans hold every judgement.** Configuration handles mechanics; the agent
   acts up to the production gate and never past it.

## Measurement

Leading indicators come from git timestamps and CI — time between artifact
commits, first-pass CI success, time to first review. Lagging indicators take a
quarter — rework rate, escaped defects, repeat incidents, DORA. Full per-stage
table: `references/stages.md`. Jira and GitHub wiring:
`references/integrations.md`. Requirements syntax: `references/ears.md`.
Handing stages 3-5 to an external runner: `references/delegation.md`.
