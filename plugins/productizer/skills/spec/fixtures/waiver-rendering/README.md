# waiver-rendering fixture

The standing case behind R37 and R38, driven by
`scripts/check-waiver-rendering.sh` through the real `run-checks.sh`.

- `fixture/finding.txt` holds no `WAIVER-FIXTURE-NEEDLE`, so the `finding`
  check exits 1: a real, measured failure, which is the only thing a waiver is
  allowed to override.
- `fixture/clean.txt` holds the needle, so the `clean` check exits 0. It is
  there so a waiver can be aimed at a check that is currently passing.
- One `checks-*.yaml` per case, and one `waivers/*/` directory per case. One
  check per run, and one waiver per run except `waivers/duplicate/`, which
  holds the two that must cancel each other. No case ever borrows a
  neighbour's refusal.

Every config is SELF-CONTAINED: it names no path outside this directory, the
only tool it needs is `grep`, and `spec_coverage` is off so no spec has to
exist beside it. `allow_repo_local_tools` is deliberately left off — the
waiver behaviour must not need the repo-local opt-in to be observable.

`checks-unwaived.yaml` is the P4 case: the waiver file it would have honoured
is present on disk and it declares no `policy.waivers`, so nothing reads it and
the check blocks. That pair — same check, same waiver file, one line of config
apart — is what proves the default is off rather than merely documented.
