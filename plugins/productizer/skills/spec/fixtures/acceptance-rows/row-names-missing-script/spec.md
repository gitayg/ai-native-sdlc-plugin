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
| R1 | `alpha` check over `probe.py` — and the corpus at `evidence/corpus.txt`. |
| R2 | `beta` check over `no-such-probe.py` — the script was deleted, the row was not. |

## Change log
