# Fixture spec

Not a product spec. It is the smallest file that carries a `## Requirements`
section and an `## Acceptance criteria` table, so one row shape can be driven
against one `checks.yaml` and the verdict read off the exit code.

## Requirements

### Ubiquitous — always active

- **R1** — The lifecycle shall hold exactly one living spec per product.
- **R2** — The lifecycle shall keep requirement ids permanent.

## Acceptance criteria

| Requirement | Verified by |
|---|---|
| R1 | Reviewed at intake against the drafting rules; not yet verified. |
| R2 | Nothing yet. A verifier would compare the ids in `n/a` state. Not built. |

## Change log
