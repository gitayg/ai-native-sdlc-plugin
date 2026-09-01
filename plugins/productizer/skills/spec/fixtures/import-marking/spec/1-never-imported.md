# Fixture spec — a repository that has never been imported

## Requirements

### Ubiquitous — always active

- **R1** — The service shall serve a health endpoint.
- **R2** — The service shall log every request once.

### Event-driven

- **R3** — When a token expires, the service shall refuse the request.
- **R4** — When a job fails, the service shall retry it exactly once.

## Change log

| Date | Added | Summary |
|---|---|---|
| 2026-01-02 | R1 | Agreed at intake after the first outage. |
| 2026-01-09 | R2 | Agreed at intake; the log had no request line. |
| 2026-01-16 | R3 | Agreed at intake. |
| 2026-01-23 | R4 | Agreed at intake. |

## Decision record

| Date | Decision | Why | Who |
|---|---|---|---|
