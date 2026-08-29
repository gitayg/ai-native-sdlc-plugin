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
