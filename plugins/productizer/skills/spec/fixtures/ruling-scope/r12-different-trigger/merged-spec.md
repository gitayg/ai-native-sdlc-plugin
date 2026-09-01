# Fixture spec — a pending ruling and what may merge beside it

Not a living spec. A committed input to `check-pending-ruling-scope.sh`'s own
self-assertion: the script copies these four files into a temporary git
repository, replays them as commits, and runs itself against the result. The
files are data. Nothing here is ever executed, and nothing here is written to.

This is THE AUDIT'S CASE. R3 is the incoming behaviour of D1, merged while D1
is pending, under a state-driven `While` where R1 uses an unwanted-behaviour
`If`. R1's own sentence is untouched, no marker points forward at R3, and R3's
wording is not the sentence D1 quotes — so every recognition rule this check
shipped with lets it through. It must be refused.

## Requirements

### Unwanted behaviour

- **R1** — If an intent contradicts an active requirement, then the lifecycle shall merge nothing.

### Event-driven

- **R2** — When a release is prepared, the lifecycle shall regenerate the user guide from the active requirements.

### State-driven

- **R3** — While an intent contradicts an active requirement, the lifecycle shall merge nothing.

## Areas of concern

| # | Concern | Requirements | Policy / owner | Raised by | Status |
|---|---|---|---|---|---|
| C1 | An intent restates R1 as a state-driven obligation | R1 | — | — | open: D1 |
