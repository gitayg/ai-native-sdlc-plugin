# Living spec — changelog-row fixture

A minimal spec, shaped like the real one, used to falsify
`check-changelog-row.sh` deterministically. It is not a product spec and
nothing reads it as one.

Next requirement id
: `R3` — allocate from here, then increment.

## Requirements

### Event-driven

- **R1** — When a fixture is built, the lifecycle shall build it in a temporary directory.
- **R2** — When a fixture is finished with, the lifecycle shall remove it.

## Change log

One row per commit to this file.

| Date | Issue | Branch / PR | Added | Refined | Superseded / withdrawn | Summary |
|---|---|---|---|---|---|---|
| <YYYY-MM-DD> | <#123 / PROJ-123> | `<branch>` / <pr> | R41–R43 | R12 | R7 → R41 | <what changed and why> |
| 2026-01-01 | — | — | R2 | — | — | The founding commit, carrying the log it was imported with. |
