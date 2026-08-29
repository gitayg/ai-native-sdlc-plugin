---
name: N05-near-miss-negated-guard
tags: [negative, false-positive-bait, gateway]
plugins: ["../../../plugins/productizer"]
runs: 3
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Run intake on the intent below for the `api gateway`.

Everything this product has ever agreed is reproduced in full in this message.
There is no repository state for it: do not look for `.claude/productizer/`, do
not read or write any file outside the plugin you are running with, and do not
assume any requirement or principle that is not written below.

## Living spec

# API gateway — living spec

System
: `api gateway` — the exact noun every requirement below uses. Never vary it.

Next requirement id
: `R9`

Requirements
: 8 active, 0 superseded, 0 withdrawn.

## Requirements

### Ubiquitous — always active

- **R1** — The api gateway shall resolve a principal for every request before
  routing it.
- **R5** — The api gateway shall be available for at least 99.9 percent of each
  calendar month.

### Event-driven

- **R2** — When a client requests a report, the api gateway shall respond in
  under 500 ms.
- **R6** — When a request carries an expired token, the api gateway shall respond
  with 401.
- **R8** — When a client requests an export, the api gateway shall respond in
  under 5000 ms.

### State-driven

- **R4** — While a client has made more than 100 requests in the last minute, the
  api gateway shall reject further requests with 429.

### Unwanted behaviour

- **R3** — If the policy service does not answer within 200 ms, then the api
  gateway shall deny the request.

### Optional

- **R7** — Where a route is marked public, the api gateway shall resolve an
  anonymous principal before routing.

## Acceptance criteria

| Requirement | Verified by | How |
|---|---|---|
| R1 | `test_every_route_resolves_a_principal` | router enumerated, no route without a principal |
| R2 | `test_report_latency_budget` | p99 over the fixture corpus below 500 ms |
| R3 | `test_policy_timeout_denies` | policy service stubbed to hang, request denied |
| R4 | `test_rate_limit_429` | request 101 in a minute returns 429 |
| R5 | `test_monthly_availability_budget` | synthetic probe uptime for the month |
| R6 | `test_expired_token_401` | token past expiry yields 401 |
| R7 | `test_public_route_anonymous_principal` | public route carries an anonymous principal |
| R8 | `test_export_latency_budget` | p99 over the fixture corpus below 5000 ms |

## Constitution

# API gateway — constitution

Product
: `gateway`

Next principle id
: `P4`

## Principles

### P1 — A decision that cannot be made fails closed
Active. Ratified 2026-01-05 by the platform and security owners.

When an authorisation, policy or licence check cannot reach the service that
would answer it, the gateway denies. Timeouts, deploys, partial outages and cold
starts are all "cannot be made". Availability work never removes a control by
converting its failure into a pass.

Prevents
: An outage in a control plane silently becoming an outage of the control
itself.

Checked by
: `test_policy_timeout_denies`, run with the policy service stubbed to hang.

Enforced by
: R3.

### P2 — Every endpoint resolves a principal before it does work
Active. Ratified 2026-01-05 by the platform and security owners.

Every route, health probe, metrics scrape and internal call resolves a principal
first — anonymous is a principal, absent is not. There is no allowlisted caller,
no endpoint exempted for being read-only, and none exempted for being behind the
load balancer.

Prevents
: The gradual accumulation of unauthenticated internal endpoints, each
individually justified, which together are the flat network an attacker needs.

Checked by
: `test_every_route_resolves_a_principal`, which enumerates the router.

Enforced by
: R1, R7.

### P3 — A published contract is never changed in place
Active. Ratified 2026-01-05 by the API owners.

A route, status code, header or error shape published to a caller outside this
product changes only by adding a new version alongside the old one.

Prevents
: Breaking an integration we cannot see and cannot roll back on the caller's
behalf.

Checked by
: The contract diff job in CI.

Enforced by
: R6.

## Arriving intent

When the policy service does answer inside its 200 ms budget, put the policy
decision id in a response header so support can trace a decision.

## What to produce

Classify this intent against the spec and the constitution above as exactly one
of **extend**, **refine**, **duplicate** or **contradict**. Cite every
requirement id (`R…`) and principle id (`P…`) that bears on the decision, state
what happens to the spec next, and say plainly what has and has not been merged.

End your reply with exactly this line, and nothing after it:

VERDICT: <EXTEND|REFINE|DUPLICATE|CONTRADICT>
