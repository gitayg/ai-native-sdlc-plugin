# CLAUDE.md

## Commands
- Build: make build
- Test:  make test
- Lint:  make lint

## Conventions
- Java 21.
- Money is BigDecimal, never double.
- Errors return the problem-detail shape in core/errors.

## Architecture
- api/      HTTP layer, no business logic
- core/     domain rules
- adapters/ everything that talks to the outside world

## Things you get wrong here
- Do not bump dependencies. The package set is frozen.
- Do not add a new module without asking.

<!-- Rule: when Claude makes the same mistake twice, the correction lands here. -->
