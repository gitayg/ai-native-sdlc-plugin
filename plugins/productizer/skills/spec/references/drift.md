# Drift — checking whether the code still does what the spec says

The lifecycle closes intent → spec → code. Nothing closes the other direction.
A requirement can stop being true without any intent arriving: refactored away,
disabled behind a flag, broken by a change nobody connected to it. The spec goes
on asserting it.

That is a spec that lies, and it is worse than no spec. No spec makes nobody
read it; a lying spec is read, cited in reviews, planned from, and turned into
acceptance criteria that assert behaviour the system no longer has.

The drift check is the reverse read: **does the code still honour the spec?** It
produces findings for a human to rule on. It never changes a requirement.

## What it is not

- Not intake. Intake classifies an *intent* against the spec. Drift compares
  *shipped code* against the spec, and there is no intent involved — that is
  precisely the gap.
- Not a review pass. Review judges a diff against requirements the diff cites.
  Drift judges the whole active requirement set against the whole codebase, and
  the requirements nobody has touched for a year are the ones it exists for.
- Not a gate. It is expensive and partly judgement-based; wiring it into a merge
  gate produces false refusals, and a gate that refuses wrongly gets disabled.

## Evidence that a requirement is honoured

Rank every finding by the strongest evidence available for it. The rank is part
of the finding — a conclusion drawn from code reading must never be reported at
the same weight as a passing test.

| Rank | Evidence | Reads as |
|---|---|---|
| 1 | The requirement's acceptance-criteria test passed in the latest run on the default branch | honoured |
| 2 | An indirect check covers the same observable — contract test, schema check, runtime assertion, a metric with a band | honoured, name the check |
| 3 | Code inspection: the path exists and produces the requirement's observable response, cited `file:line` | likely honoured, low confidence |
| 4 | Nothing found either way | **unverified** — not a gap |

Rules that keep the ladder honest:

- **A test that exists and fails is not weak evidence — it is a finding.** Rank
  1 requires a pass. A failing acceptance test is the strongest possible
  evidence of drift, not an absence of evidence.
- **A skipped, quarantined or `xfail` test is rank 4, not rank 1.** A suite that
  reports green while the case never executes is absence dressed as evidence,
  and it is the single most common way drift goes unnoticed for a year.
- **A stale run is not a run.** Name the run id and its commit. If the newest
  run predates the head of the default branch, drop to rank 3.
- **State the configuration you evaluated.** Behaviour reachable only behind a
  flag that is off in production is not honoured in the default configuration.
  Report it as `specified-not-implemented (flag: <name>, off)` — the requirement
  says the system shall, not that it could if switched on.
- **Not every requirement has a test, and that is expected.** The spec's
  acceptance-criteria table already tracks that; a requirement it lists as
  unmapped starts at rank 3 at best, and the finding is about coverage, not
  about the code being wrong.
- **Absence of evidence is its own bucket.** Never fold rank 4 into
  `specified-not-implemented`. Reporting "unverified" as "not implemented" sends
  a human to look for a bug that does not exist, and after the second time they
  stop reading the report.

## Gap types

Exactly four outcomes of a comparison. Every row in the report is one of them.

**`implemented-not-specified`** — the code does something no active requirement
asks for. Usually a feature that shipped without going through intake, or
behaviour that grew out of a bug fix. It is a candidate intent, not a missing
requirement: it goes to intake as an `extend` if a human wants it agreed, and to
an issue if they want it removed. Scope that nobody agreed to is the ordinary
cause.

**`specified-not-implemented`** — an active requirement with no code and no
check honouring it. Three usual causes, and the report should guess which:
never built (the spec PR merged, the code PR did not), refactored away, or
switched off behind a flag.

**`contradicts`** — the code observably does the opposite of what the
requirement says. The strongest finding class and the rarest. Cite the
requirement sentence and the `file:line` or the failing test that shows the
opposite. Treat it exactly as intake treats a contradiction: a stop, ruled on by
a human.

**`unverified`** — no evidence either way. Report the count and the ids; do not
propose a disposition for these beyond "add a check".

## What the tool does about it

It writes a report and raises questions. It changes no agreed behaviour.

- **It never edits a requirement.** Not the sentence, not the status marker, not
  its acceptance-criteria row, not the counter.
- **It never deletes.** Marking a requirement `Withdrawn.` is a spec write, and
  a spec write follows a recorded ruling. *"Nothing is ever deleted. A
  superseded or withdrawn requirement keeps its original sentence, in place."*
- **It never allocates a requirement id.** Specifying discovered behaviour is an
  intake `extend`, and the allocator has one writer
  (`references/spec-stores.md`).
- **The one thing it does write to the spec is a concern.** Raising a ruling
  adds a `C<n>` row to *Areas of concern* and a `D<n>` ruling file, per
  `references/rulings.md`. That records a question; it agrees nothing.
- **It opens issues, not commits to code.** A finding a human accepts becomes an
  issue — the same door Stage 1 uses — and re-enters the lifecycle at intake.

The output is `templates/converge.md`: a report with one row per finding, a
proposed disposition, and an empty ruling column.

**Finding ids are local to the report.** `F1`, `F2` number the rows of one run
and are cited nowhere else. Permanence belongs to the ids that carry agreements
— the requirement `R<n>`, the concern `C<n>`, the ruling `D<n>` — and inventing
a fourth permanent id space for observations that expire on the next run buys a
counter to get wrong.

## Why not just update the spec to match the code

Because it resolves the argument in favour of whatever was last shipped, which
is backwards for a tool whose entire premise is that agreed behaviour outranks
accidents.

Tessl's spec-driven tile instructs the opposite — *"update the spec to match
current implementation"* when the spec is stale. Concretely, that is wrong for
five reasons:

1. **It launders regressions into requirements.** A requirement broken by a bad
   deploy is rewritten to describe the breakage. The incident is now the agreed
   behaviour, no test will ever fail for it again, and the eval that should have
   been added never is.
2. **It makes the spec redundant.** A file that is regenerated from the code is
   a serialisation of the code, with the added cost of looking like an
   agreement. Nobody needs a second, lossier copy of `main`.
3. **It destroys the audit trail.** The record is `git log -p
   .claude/productizer/spec.md`, where each commit joins to an issue and a decision. A
   commit that joins only to a refactor answers "what did we agree" with "what
   did we happen to ship".
4. **It converts a stop into a silent merge.** A `contradicts` finding is the
   same object as an intake contradiction, and the lifecycle's third
   non-negotiable is that *"a contradiction stops the work"* — never superseded
   without a human deciding, and never because the new one is newer. Code is
   newer by construction.
5. **It hands the pen to whoever last merged.** A careless or hostile change to
   the code becomes the requirement, and the next review — which checks diffs
   against the spec — approves the next change on that basis. The direction of
   authority must run spec → code, or the spec authorises nothing.

The correct output of a drift check is a **finding a human rules on**. Fixing
the code and changing the agreement are both legitimate answers; only a person
gets to pick.

## The ruling

A finding that proposes changing the spec — retire, refine, or specify — is a
contradiction between agreed behaviour and shipped code, and it uses the ruling
mechanism in `references/rulings.md` unchanged. The only substitution is what
stands opposite the requirement: shipped code rather than an incoming intent.
Code being newer is not an argument, for the reason above.

Raise it the way intake raises one, and in the same order: allocate the next
`D<n>` and `C<n>`, write the ruling file from `templates/ruling.md` with both
sides stated verbatim, add the `C<n>` row as `open: D<n>`, commit, **then** ask.
Writing before asking is the mechanism — a question asked in a session that then
ends leaves nothing behind, which is the failure the whole file exists to
prevent.

The agent drafts the conflict, the question and the costs. It never fills
`Ruling`, `Ruled by` or `Reasoning`. A drift finding that resolves itself is the
auto-update above, wearing a form.

A ruling picks one of four outcomes, and each is executed by the stage that owns
it — never by the drift run:

| Ruling | Means | Executed by |
|---|---|---|
| **Fix the code** | the requirement stands; the code is wrong | issue → Stage 1, then the normal lifecycle |
| **Refine the requirement** | it was imprecise, the behaviour is agreed | intake `refine` — same id, changed text |
| **Retire the requirement** | the behaviour is genuinely gone by decision | intake supersede or `Withdrawn.` marker, with a reason line; never a deletion |
| **Specify the code** | the behaviour is wanted and was never written down | intake `extend` — new ids from the one allocator |

Until it is ruled, the finding sits in *Areas of concern* as `C<n>`, in the
table that already exists for exactly this and which *"stays open until a human
rules on it."* A ruling nobody answers lapses; lapsing expires the question and
never the requirement, so the requirement the drift run challenged still stands
— which is the safe default, and the opposite of what an auto-update does.

Not every row needs a ruling. `fix the code` changes no agreed behaviour: open
the issue and let it run the lifecycle. Raise a ruling only where the proposal
is to change what the spec says.

## Running it

**On a schedule** — monthly for a stable product, weekly for one changing fast —
and **before a release**, where the useful question is which requirements were
last proven honoured and when. Also on demand: after a large refactor, or when a
review cites a requirement and nobody can find the test.

Not on every commit. The check reads the whole active requirement set against
the whole codebase; run at that frequency it is slow, noisy and ignored.

**Cap the report.** Rank the findings, report the top ones in full and the rest
as counts by type. A run that emits two hundred rows is a run nobody reads, and
the ten that mattered are lost with the rest.

**Report what you could not check.** A drift run that silently skips a repo, a
language it cannot parse, or a suite that would not build reports green for the
wrong reason. The unscanned list belongs in the report, above the findings.

## Multi-repo products

The check is scoped to the **product**, not the repo. The spec is one file
covering every repo, and the acceptance criteria name which repo verifies each
requirement — *"because the requirement and its test no longer necessarily live
together."*

- Read the spec from the home or the store (`references/spec-stores.md`) and
  record the sha you read. If it is unreachable, the run **stops** — it does not
  report clean.
- A requirement whose criteria name a repo you did not scan is **unverified**,
  never `specified-not-implemented`. Missing this rule makes a run inside one
  service report every front-end requirement as unimplemented, which is how a
  drift report loses its readers on the first run.
- Say which repos were scanned, at which commits, and which were not.
