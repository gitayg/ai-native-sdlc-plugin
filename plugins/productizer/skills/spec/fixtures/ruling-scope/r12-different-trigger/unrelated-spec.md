# Fixture spec — a pending ruling and what may merge beside it

Not a living spec. A committed input to `check-pending-ruling-scope.sh`'s own
self-assertion: the script copies these four files into a temporary git
repository, replays them as commits, and runs itself against the result. The
files are data. Nothing here is ever executed, and nothing here is written to.

This is the OTHER half of the assertion. R3 here is an unrelated intent
allocated while D1 is pending. A pending ruling blocks its own delta and
nothing else, so this must NOT be refused - it must be reported as allocated
and let through, which is what makes the decision visible instead of silent.

## Requirements

### Unwanted behaviour

- **R1** — If an intent contradicts an active requirement, then the lifecycle shall merge nothing.

### Event-driven

- **R2** — When a release is prepared, the lifecycle shall regenerate the user guide from the active requirements.

### Optional feature

- **R3** — Where a repository declares its own check tools, the lifecycle shall run them only if the configuration explicitly opts in.

## Areas of concern

| # | Concern | Requirements | Policy / owner | Raised by | Status |
|---|---|---|---|---|---|
| C1 | An intent restates R1 as a state-driven obligation | R1 | — | — | open: D1 |
