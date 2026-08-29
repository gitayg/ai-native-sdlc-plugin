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
