# Per-stage governance and measurement

Leading indicators move within a sprint and tell you the change is taking.
Lagging indicators take a quarter and tell you it was worth it. Most leading
indicators are already sitting in your git timestamps.

## 1 · Plan
- **Governance:** the evidence is the committed artifact; full revision history in git.
- **Leading:** time from first conversation to the issue being opened — hours, not weeks.
- **Lagging:** share of issues that reach a merged spec delta versus those closed unspecified; and how often an intent turns out to be a duplicate of something already specified.
- **Needs:** Claude access for non-engineers; an agreed template; a shared version-controlled home; optionally a Git connector for non-technical contributors.

## 2 · Design
- **Governance:** live policy applied at writing time; prompt, spec and skill versions logged; product owner signs off; tech lead consulted on higher-risk changes.
- **Leading:** elapsed time from the issue being opened to its spec delta being merged.
- **Lagging:** requirements rework after build starts — edits to the same requirement ids dated after the first `plan.md` commit. Also the contradiction rate: intents that stopped at intake, which is a healthy number only while it is falling.

## 3 · Build
| Play | Governance | Leading | Lagging |
|---|---|---|---|
| 3A Plan mode | design review before code generation, approver attributed | share of changes merging from the first pass | rework cycles; does the merged diff match `plan.md` |
| 3B CLAUDE.md | version controlled, reviewed like code | frequency of mistakes CLAUDE.md should have caught | time to first merged PR for new joiners |
| 3C Skills | advisory control; invocations logged in session traces | time from policy-owner approval to merged skill | PR findings citing policy — should trend to zero |
| 3D Hooks | deterministic, no exception path; executions logged | hook block rate on protected paths | incidents of a class a hook should have prevented |
| 3E Parallel sessions | repo hooks and permissions apply to every session | concurrent sessions per engineer while quality holds | changes merged per engineer per week, read with rework rate |

Skills rule of thumb: write one for institutional knowledge enforced
inconsistently today. Not for component-level knowledge, not for a one-off prompt.

## 4 · Test
| Play | Governance | Leading | Lagging |
|---|---|---|---|
| 4A Feedback loop | verification before done enforced; test edits blocked during a fix | first-pass CI success rate for agent-written changes | review time per PR; change failure rate |
| 4B Evals in CI | pass-rate threshold as a merge check; runs logged; config owner approves | eval pass rate over time; time from incident to permanent eval | regressions caught in CI vs in production |

## 5 · Deploy
| Play | Governance | Leading | Lagging |
|---|---|---|---|
| 5A PR review | agent cannot approve its own code; policy applies to every PR; human approval via branch protection | time to first review (minutes) | defects caught before merge vs escaping |
| 5B Approval gates | enforced every time for everyone; decisions timestamped | gate trip rate; time waiting at gates | unauthorised production changes (must stay zero) |
| 5C CI/CD | agent acts up to the production gate, never past it; per-environment tiers; agent runs under its own identity | share of pipeline failures triaged without paging a human | DORA: lead time, deploy frequency, change failure rate, MTTR |

Autonomy ladder: read-only judgement → write steps behind existing gates →
environment-tiered deploys (dev free, staging middle, production prepared by the
agent and authorised by a release manager). Rollback is the most rehearsed path.

## 6 · Maintain
- **Governance:** tier boundaries from version-controlled config; managed settings deny production access; invocations, findings and triage decisions timestamped; changes go through the normal PR gate; runbooks approved in advance.
- **Leading:** time from band breach to an issue in the triage queue.
- **Lagging:** share of findings becoming merged fixes; repeat incidents of the same class.
- **Examples:** CI failure at 3σ → quarantine the flaky test or open a revert PR. Post-deploy 5xx at 3σ with a recent deployment → trigger the rollback pipeline. PR cycle-time drift → write a report for engineering leadership.

## Legacy systems — pick one source of truth
1. **Repo as truth** — markdown is authoritative, the legacy system holds a copy or link.
2. **Legacy as truth** — Jira/ServiceNow is authoritative, markdown working copies arrive via MCP.
3. **Linkage minimum** — both exist, linked by record ID and commit SHA. The usual starting point.

## Infrastructure this assumes
Claude Code (interactive and `claude -p`) · git · CI/CD · model access (API,
Bedrock, Vertex or Foundry) · MCP servers for deploy/incident/metrics tooling ·
OpenTelemetry and Prometheus · a sandbox · managed settings for regulated orgs.
