# Records — constitution

Product
: `records`

Next principle id
: `P4`

## Principles

### P1 — Tenant data never leaves the tenant boundary
Active. Ratified 2026-01-05 by the platform and security owners.

No request, export, report, log line, telemetry event or support tool moves one
tenant's data out of the tenant that owns it. Data derived from it — counts,
medians, aggregates, benchmarks — is that tenant's data.

Prevents
: One customer's figures surfacing in another customer's account.

Checked by
: `test_usage_report_is_tenant_scoped`, plus a review pass on any query without a
tenant predicate.

Enforced by
: R11.

### P2 — Nothing identifying a person is retained without a stated basis and an expiry
Active. Ratified 2026-01-05 by the platform and security owners.

Every store holding a name, an identifier, an address or a device fingerprint
declares the lawful basis for holding it and the date it is removed. "Useful
later" is not a basis and "indefinitely" is not an expiry.

Prevents
: Retention that nobody chose, discovered at the first subject-access request.

Checked by
: `test_every_personal_store_declares_expiry`, which enumerates the schema.

Enforced by
: R2, R8.

### P3 — An erasure request is honoured across every store
Active. Ratified 2026-01-05 by the platform and security owners.

Erasure covers primary tables, caches, search indexes, backups within their own
cycle and any derived extract. A store exempted from erasure is a store that
must not hold personal data at all.

Prevents
: A subject told they were erased while a copy survives in a second system.

Checked by
: `test_erasure_sweeps_every_declared_store`.

Enforced by
: R2, R5.
