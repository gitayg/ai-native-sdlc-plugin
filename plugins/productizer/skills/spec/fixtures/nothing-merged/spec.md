# Fixture spec — a living spec with exactly one active requirement

R24 — IF AN INTENT CONTRADICTS AN ACTIVE REQUIREMENT, THEN THE LIFECYCLE SHALL
MERGE NOTHING.

This file is the standing case for that, and `scripts/check-nothing-merged.sh`
is what runs it. It is a real spec, not a stub: the contradiction path reads
requirement definitions, the *Areas of concern* table and the id counter out of
a file shaped exactly like this one, and a fixture missing any of them would
exercise the refusal path instead of the path under test.

SELF-CONTAINED ON PURPOSE. It names no path outside itself and no id above R2,
so it works in a fresh clone on any machine and can never be confused with the
repository's own spec. An absolute path here would have made the test pass on
one machine and refuse on every other one.

System
: `service` — the noun the requirement below uses.

Next requirement id
: `R2` — allocate from here, then increment. The whole point of the case is
that after a contradiction this line still reads `R2`. An id in the spec is a
merge, whatever the surrounding prose says.

Requirements
: 1 active, 0 superseded, 0 withdrawn.

## Requirements

### Unwanted behaviour

- **R1** — If a request body fails schema validation, then the service shall reject it with 400.

## Areas of concern

The contradiction path is required to write one row here — that is the stop
being recorded, and `check-ruling-requested.sh` fails when it is missing. It is
the one table this fixture expects to change.

| # | Concern | Requirements | Policy / owner | Raised by | Status |
|---|---|---|---|---|---|

## Acceptance criteria

| Requirement | Verified by |
|---|---|
| R1 | the fixture's own premise check — the incoming intent really does contradict this sentence |

## Change log

| Date | Issue | Branch / PR | Added | Refined | Superseded / withdrawn | Summary |
|---|---|---|---|---|---|---|
| 2026-08-31 | — | — | R1 | — | — | The one requirement the incoming intent is written to contradict. |

## Decision record

| Date | Decision | Why | Who |
|---|---|---|---|
