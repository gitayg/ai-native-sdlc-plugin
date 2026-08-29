---
name: N09-extend-complies-with-principle
tags: [negative, constitution, records]
plugins: ["../../../plugins/productizer"]
runs: 3
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Run intake on the intent below for the `records service`.

Everything this product has ever agreed is reproduced in full in this message.
There is no repository state for it: do not look for `.claude/productizer/`, do
not read or write any file outside the plugin you are running with, and do not
assume any requirement or principle that is not written below.

## Living spec

# Records service — living spec

System
: `records service` — the exact noun every requirement below uses. Never vary it.

Next requirement id
: `R12`

Requirements
: 8 active, 1 superseded, 0 withdrawn.

## Requirements

### Ubiquitous — always active

- **R1** — The records service shall write an access-log entry naming the subject
  and the operator for every read of a personal-data field.
- **R3** — The records service shall retain the audit log of every administrative
  action indefinitely.

### Event-driven

- **R2** — When a subject requests erasure, the records service shall remove all
  personal data held for that subject within 30 days.
- **R4** — When an operator requests an export, the records service shall include
  archived records.
- **R7** — When a tenant administrator requests a usage report, the records
  service shall report only that tenant's records.
  Superseded by R11. Ruled 2026-01-15: the original wording constrained the rows
  read but not the figures derived from them.
- **R11** — When a tenant administrator requests a usage report, the records
  service shall report only that tenant's records and shall exclude any figure
  derived from another tenant's records.

### State-driven

- **R6** — While a subject has an open legal hold, the records service shall
  preserve every record naming that subject.

### Unwanted behaviour

- **R5** — If the retention store is unreachable, then the records service shall
  refuse the erasure request and raise an incident.

### Optional

- **R8** — Where the tenant has enabled archival, the records service shall move
  records older than 365 days to cold storage.

## Acceptance criteria

| Requirement | Verified by | How |
|---|---|---|
| R1 | `test_access_log_written` | one log row per personal-data read, naming subject and operator |
| R2 | `test_erasure_completes_within_30d` | fixture clock advanced 30 days, no subject rows remain |
| R3 | `test_audit_log_never_pruned` | retention job leaves audit rows untouched |
| R4 | `test_export_includes_archived` | export row count equals live plus archived |
| R5 | `test_erasure_refused_when_store_down` | retention store stubbed unreachable, request refused |
| R6 | `test_legal_hold_blocks_deletion` | held subject survives an erasure run |
| R8 | `test_archival_moves_at_365d` | record aged 366 days is in cold storage |
| R11 | `test_usage_report_is_tenant_scoped` | report over a two-tenant fixture cites no other-tenant figure |

## Constitution

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

## Arriving intent

Tenant admins want to see whether their own volume is going up or down. Add a
month-over-month trend line for the tenant's own figures to the usage report.

## What to produce

Classify this intent against the spec and the constitution above as exactly one
of **extend**, **refine**, **duplicate** or **contradict**. Cite every
requirement id (`R…`) and principle id (`P…`) that bears on the decision, state
what happens to the spec next, and say plainly what has and has not been merged.

End your reply with exactly this line, and nothing after it:

VERDICT: <EXTEND|REFINE|DUPLICATE|CONTRADICT>
