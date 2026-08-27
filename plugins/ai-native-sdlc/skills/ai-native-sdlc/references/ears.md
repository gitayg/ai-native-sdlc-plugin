# EARS — requirements a test can assert

Easy Approach to Requirements Syntax. Five sentence patterns, one requirement
per sentence. The point is not tidiness: prose requirements read fine and cannot
be tested, so Stage 4A's question — *do the tests actually assert the criteria* —
stays a matter of opinion. EARS makes it checkable, because every requirement
already names its trigger, its precondition and an observable response.

## The five patterns

**Ubiquitous** — always active, no precondition.
> The `<system>` shall `<response>`.

**Event-driven** — a discrete trigger.
> When `<trigger>`, the `<system>` shall `<response>`.

**State-driven** — true for the duration of a state.
> While `<state>`, the `<system>` shall `<response>`.

**Unwanted behaviour** — the error and abuse cases. Use `if`, never `when`; the
distinction is what separates a designed path from a defended one.
> If `<unwanted trigger>`, then the `<system>` shall `<response>`.

**Optional feature** — only when the feature is present in the build.
> Where `<feature is included>`, the `<system>` shall `<response>`.

**Complex** — a state and a trigger together. Stack them in this order only.
> While `<state>`, when `<trigger>`, the `<system>` shall `<response>`.

## Rules that make them testable

1. **One requirement per sentence, one `shall` per requirement.** An `and` in the
   response is two requirements wearing one id, and they will be half-tested.
2. **Name the system explicitly**, the same way every time. "The service", "it"
   and "the system" used interchangeably across a spec hide which component owns
   the behaviour.
3. **The response must be observable** from outside the thing being specified. If
   a test cannot see it, it is a design note, not a requirement — move it.
4. **Number every requirement** (`R1`, `R2`, …). The id is the handle everything
   downstream cites, and it is permanent — see *Requirement identity and
   lifecycle* below for allocation, supersession and the rules against reuse.
5. **No unquantified adjectives.** Fast, robust, user-friendly, appropriate, as
   needed, etc. Each is an argument deferred to review. Give a number or drop it.
6. **Unwanted-behaviour requirements are not optional.** A spec with no `If`
   requirements has not considered failure, and the tests will inherit that gap.

## Requirement identity and lifecycle

The spec is not a per-feature document that gets thrown away. One living spec per
repo at `.claude/sdlc/spec.md` accumulates every intent that has been merged into
it, so a requirement outlives the change that introduced it. The id is the only
stable handle the rest of the lifecycle has on a requirement, which makes id
discipline the load-bearing part of the spec rather than its housekeeping.

### Allocation

Ids are monotonic. The next requirement takes the next number, and the counter
never rewinds. Removing a requirement does not free its id: if `R14` is gone and
the highest id ever allocated is `R57`, the next requirement is `R58`. Allocate
from the highest id the spec has ever used, not from the highest one still
active, and not from a count of the rows on screen.

The counter belongs to the repo, not to a file or a section. A spec that grows
past one file — split by area, by service, by anything — must still hand out ids
that are unique across the whole repo, because every citation elsewhere names
only `R14`, never the file it was living in that week.

### Never reuse, never renumber

Reusing an id is the single most damaging thing that can happen to the spec, and
it is silent. A test asserting `R14`, a plan naming `R14`, a PR titled for `R14`,
a review finding filed against `R14` — all of them keep resolving, and all of
them now point at a different requirement. Nothing errors. The suite stays green
while it asserts behaviour nobody agreed to. Renumbering does the same damage
wholesale, in one commit, to every id after the insertion point.

There is no repair short of reading every citation in the repo's history and
deciding which requirement each one meant. Treat both as prohibited.

### Supersession, not deletion

A requirement never leaves the spec. It changes status.

| Status | When | Recorded as |
|---|---|---|
| Active | Current agreed behaviour | The requirement, plain |
| Superseded | The behaviour is replaced by another requirement | `Superseded by R58.` plus one line on why |
| Withdrawn | The behaviour no longer exists at all | `Withdrawn.` plus one line on why |

The marker goes on the line directly beneath the requirement, which already
carries the id — repeating it there adds nothing. Keep the original sentence in
place under either marker; a status line without the text it applies to is not a
record. Superseded requirements point forward to
what replaced them, so a citation from two years ago still leads somewhere.
Withdrawn ones state the reason, so the next person to propose the same thing
finds out it was considered and dropped.

Deleting the row instead saves nothing and costs the spec its second job: being
a readable record of what was agreed and when.

### Contradiction is a stop, not a merge

When an incoming intent contradicts an active requirement, the work stops and a
human decides which wins. Not the agent, not the author of the intent by
implication, not whichever sentence happens to be merged last.

The reason is asymmetry of failure. A contradiction resolved silently changes
agreed behaviour with nobody approving the change, and produces a spec that is
confidently wrong — internally tidy, downstream-citable, and describing something
no one signed off. A contradiction surfaced produces a spec that is obviously
incomplete, which is a state everyone can see and act on. Prefer the visible
failure every time.

A good stop is short and decidable:

> Stop — conflict with the existing spec.
> `R14`: While a session is idle for 30 minutes, the service shall end it.
> Incoming: While a session is idle, the service shall keep it alive until the
> user signs out.
> These cannot both hold: R14 ends idle sessions, the new intent preserves them.
> Which governs?

Three things make it usable: both requirement ids quoted with their text, the
conflict stated in one sentence rather than argued, and one explicit question.
Once the human decides, record the decision — the losing requirement is marked
superseded with a pointer to the winner, and the reason line names the decision,
not just the mechanics.

### Classifying an incoming intent

At intake, every requirement in an incoming intent is one of four things against
the existing spec. Classify each one before writing anything.

| Class | Test | Action |
|---|---|---|
| **Extend** | No active requirement covers this trigger and response | Allocate new ids and append |
| **Refine** | An active requirement covers it, and the intent makes it stricter, more specific or more measurable without changing what is agreed | Edit in place, same id, record what changed and why |
| **Contradict** | An active requirement covers it and the two cannot both hold | Stop and ask |
| **Duplicate** | An active requirement already says this | Cite the id, add nothing, stop |

Practical guidance for telling them apart:

- **Match on trigger and system, not on wording.** Two sentences about "the
  export endpoint" that fire on different triggers are two requirements. Two
  sentences with the same trigger and the same system are the same requirement
  wearing different prose, however differently they read.
- **Refine versus contradict** turns on whether the old requirement stays true.
  Tightening 200 ms to 100 ms is a refinement: everything that satisfies the new
  requirement satisfied the old one. Moving 200 ms to 500 ms is a contradiction,
  however small the number looks, because behaviour previously forbidden is now
  required.
- **Refine versus extend** turns on whether the trigger is the same. Adding a
  precondition that narrows an existing requirement is a refinement. Adding a
  second trigger is a new requirement — do not bolt an `and` onto an existing
  one, which is rule 1 broken by another route.
- **Duplicate is a real outcome, not a failure to find anything to do.** Saying
  "already specified as `R23`" and stopping is the correct result for an intent
  that restates settled behaviour. Adding a near-identical requirement under a
  new id splits the citations for one behaviour across two ids, and the tests
  will follow only one of them.
- **When the classification is genuinely unclear, treat it as a contradiction**
  and ask. The cost of a needless question is one round trip; the cost of a
  wrong silent merge is a spec that lies.

Unwanted-behaviour requirements need the same pass. An incoming `if` that
defends the same trigger as an existing one with a different response is a
contradiction, not a second defence.

## Anti-patterns, with the fix

| Written as | Why it fails | Rewrite |
|---|---|---|
| The system should handle invalid input gracefully. | No trigger, no observable response, "gracefully" is unquantified | If the request body fails schema validation, then the API shall reject it with 400 and an error naming the failing field. |
| When a user logs in and their session expires, the system shall notify them. | Two requirements in one | Split: one event-driven for login, one state-driven or unwanted-behaviour for expiry. |
| The service shall be fast. | Untestable | While under 100 concurrent requests, the service shall return p95 latency under 200 ms. |
| The system shall support export. | No trigger, no actor, no shape | When an operator requests an export, the service shall write a CSV containing one row per record. |

## How this feeds the later stages

- **Stage 3** — `plan.md` names which requirement ids each file change serves. A
  requirement no file claims is a gap; a file serving no requirement is scope
  creep, and the plan-vs-diff check will say so.
- **Stage 4A** — each requirement maps to at least one test. The trigger becomes
  the arrange-and-act, the response becomes the assert. A requirement with no
  test is the answer to "do the tests assert the criteria", stated as a fact
  rather than argued.
- **Stage 5A** — the compliance pass reads the diff against these ids instead of
  against a paragraph of prose.

Point a criteria checker at the requirements section directly — that is what the
numbering and the one-response rule are for.

## What EARS does not do

It does not make a requirement correct, only unambiguous. A precisely worded
requirement can still be the wrong thing to build, which is what Stage 2's review
against `intent.md` is for. It also does not suit everything: a genuinely
narrative constraint ("this must not surprise existing API consumers") is better
as a design note than as a `shall` sentence contorted into a pattern.
