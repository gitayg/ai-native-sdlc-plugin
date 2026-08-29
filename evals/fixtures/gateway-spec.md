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
