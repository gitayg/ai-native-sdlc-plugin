# Fixture spec — an import whose requirements were all promoted

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
| 2026-01-02 | R1–R4 | Stage 0c drafted these from the existing repository. |

## Decision record

| Date | Decision | Why | Who |
|---|---|---|---|
| 2026-01-20 | Confirmed R1, R2, R3 and R4, the inferred requirements from the import | Read against the code and agreed one at a time. | — |
