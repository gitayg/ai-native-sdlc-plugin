# Drift report — <product>, <YYYY-MM-DD>

Spec read
: `<owner/spec-repo>` @ `<sha>`, `.claude/productizer/spec.md` — `<n>` active
requirements. A run that could not read the spec produces no report.

Repos scanned
: `<owner/repo>` @ `<sha>` · `<owner/repo>` @ `<sha>`

Not scanned
: `<owner/repo>` — `<why: unreachable, would not build, no parser>`. Every
requirement verified only here is reported **unverified**, not as a gap.

Test evidence
: `<CI run id>` on `<default branch>` @ `<sha>`, finished `<when>`. Runs older
than the branch head drop every requirement they cover to rank 3.

Configuration evaluated
: `<production defaults / flags on>`

**No requirement was changed by this run.** Rows proposing a spec change are
raised as rulings and wait; nothing below is agreed until a human rules.

## Summary

| Type | Count |
|---|---|
| contradicts | `<n>` |
| specified-not-implemented | `<n>` |
| implemented-not-specified | `<n>` |
| unverified | `<n>` |
| honoured (rank 1) | `<n>` |
| honoured (rank 2-3) | `<n>` |

`<n>` findings reported in full below; `<n>` more suppressed by the cap, listed
by id under *Suppressed*.

## Findings

One row per finding, strongest first. `Evidence` names the test, check or
`file:line` — never a summary of one.

| # | Requirement | Type | Rank | Evidence | Proposed | Ruling |
|---|---|---|---|---|---|---|
| F1 | R14 | contradicts | 1 | `<test name>` failing since `<sha>` | fix the code | none needed — issue `<#n>` |
| F2 | R31 | specified-not-implemented | 4 | no call site; flag `<name>` off since `<date>` | retire the requirement | `open: D<n>` |
| F3 | — | implemented-not-specified | 3 | `src/<path>:<line>` | specify the code | `open: D<n>` |

Rank: 1 acceptance test passed · 2 indirect check · 3 code inspection ·
4 no evidence either way.

Proposed: **fix the code** · **refine the requirement** · **retire the
requirement** · **specify the code**. A proposal is a suggestion to the person
ruling, never a decision. Ruling: `open: D<n>` while it waits, then the ruling
and its date — or `none needed` where the proposal changes no agreed behaviour.

### F1 — R14

Requirement, verbatim
: *<the requirement sentence, exactly as the spec states it>*

Observed
: <what the system actually does, and how that was established>

Why they cannot both hold
: <one sentence>

Consequence of each ruling
: fix the code — <what changes>. Retire the requirement — <what stops being
agreed, and who is relying on it>.

Repeat this block only for findings a table row cannot carry: every
`contradicts`, and anything where the proposed disposition is to change the
spec rather than the code.

## Unverified

Requirements with no evidence either way. Not gaps — the check could not tell.

| Requirement | Why | Fix |
|---|---|---|
| R7 | no acceptance criteria row | add a check, or accept it as unverifiable and say so |
| R22 | verified by `<owner/repo>`, not scanned | scan that repo |
| R28 | test `<name>` is skipped | unskip it, or delete it and record that the requirement is unchecked |

A suite reporting green while these never execute is the usual reason drift goes
unnoticed for a year.

## Suppressed by the cap

`F<n>`–`F<n>`: `<n>` rows, `<types>`. Full list at `<path or run id>`.

## Next

- Findings a human accepts become issues — the Stage 1 door — and re-enter at
  intake. Ids are allocated there, by the one allocator, never here.
- Findings that propose changing the spec are raised as rulings before anyone is
  asked: `D<n>` from `templates/ruling.md`, a `C<n>` row reading `open: D<n>`,
  one commit — `references/rulings.md`. The agent leaves `Ruling` and `Ruled by`
  empty.
- Nothing in this report supersedes, withdraws, deletes or renumbers a
  requirement. Those are spec writes and they follow a recorded ruling.
- `F<n>` ids are local to this report. Cite `R<n>`, `C<n>` and `D<n>` outside
  it; they are the ids that last.
