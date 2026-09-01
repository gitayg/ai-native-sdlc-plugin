# Fixture spec — a pending ruling and what may merge beside it

Not a living spec. A committed input to `check-pending-ruling-scope.sh`'s own
self-assertion: the script copies these four files into a temporary git
repository, replays them as commits, and runs itself against the result. The
files are data. Nothing here is ever executed, and nothing here is written to.

This is the state BEFORE the contradiction was raised.

## Requirements

### Unwanted behaviour

- **R1** — If an intent contradicts an active requirement, then the lifecycle shall merge nothing.

### Event-driven

- **R2** — When a release is prepared, the lifecycle shall regenerate the user guide from the active requirements.

## Areas of concern

| # | Concern | Requirements | Policy / owner | Raised by | Status |
|---|---|---|---|---|---|
