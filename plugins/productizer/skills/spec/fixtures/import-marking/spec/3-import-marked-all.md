# Fixture spec — an import that marked every requirement

## Requirements

### Ubiquitous — always active

- **R1** — The service shall serve a health endpoint.
  Inferred from `app/health.py:12`. Unconfirmed.
- **R2** — The service shall log every request once.
  Inferred from test `every request is logged once`. Unconfirmed.

### Event-driven

- **R3** — When a token expires, the service shall refuse the request.
  Inferred (weak evidence) from `app/auth.py:88`. Unconfirmed.
- **R4** — When a job fails, the service shall retry it exactly once.
  Withdrawn. Rejected at import: the retry is a bug nobody agreed to.

## Change log

| Date | Added | Summary |
|---|---|---|
| 2026-01-02 | R1–R4 | Stage 0c drafted these from the existing repository. |

## Decision record

| Date | Decision | Why | Who |
|---|---|---|---|
