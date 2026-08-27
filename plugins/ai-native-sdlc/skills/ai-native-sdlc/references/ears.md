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
4. **Number every requirement** (`R1`, `R2`, …) and never renumber. Tests, review
   findings and the plan all cite these ids; renumbering silently redirects every
   citation.
5. **No unquantified adjectives.** Fast, robust, user-friendly, appropriate, as
   needed, etc. Each is an argument deferred to review. Give a number or drop it.
6. **Unwanted-behaviour requirements are not optional.** A spec with no `If`
   requirements has not considered failure, and the tests will inherit that gap.

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
