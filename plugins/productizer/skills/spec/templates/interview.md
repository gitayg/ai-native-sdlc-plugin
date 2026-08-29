# Interview — five questions, when the repo will not say

Stage 0c, the branch the survey cannot take. Runs after `scripts/init.sh` has
scaffolded an empty `.claude/productizer/spec.md` and the survey has come back
under its floor — `DRAFT TIER: WEAK`, or no tier at all.

The survey reads what the code states to a machine: routes, CLI surface, test
names, error paths, config keys. A repo that expresses none of that is not a
repo with no product. It is a repo whose product lives in someone's head. **The
correct response to thin evidence is to ask, not to stop and not to guess** —
and the person at the keyboard is a better source than a README nobody has
opened since the rewrite.

What this produces is exactly what the survey produces: **`inferred`
requirements, unconfirmed**, each carrying its provenance. Not better ones. An
answer typed by a human is a statement about a system, not an agreement about
it, and the distinction is the whole point of the status.

## Before you ask anything

1. **Check that anybody is there.** Gate on the `interactive` flag from
   `scripts/detect-context.sh` — not on the stage, not on the time of day.
   `init.sh` reports it on the `interactive` line. If it is `false` or
   `unknown`, do not ask. Report what the repo needs and stop; a nightly task
   has no one to answer and a prompt into an empty room hangs a scheduled run
   until it times out.
2. **Refuse to interview into a spec that already has requirements.** Like
   import, this is a first-fill. A second pass allocates new ids for behaviour
   the first one covered, and the duplicates split every downstream citation.
   If the spec has rows, stop and route the new behaviour through intake
   (`templates/intake.md`).
3. **Run the survey first anyway, and show what it found.** Even a weak-tier
   survey names files, and naming them makes the answers concrete. Open with
   what you already know, so the person is correcting rather than dictating.
4. **Five questions, in one pass.** Not a branching interrogation. Someone who
   agreed to five will answer five; someone facing an open-ended interview
   answers two and leaves.

## The five questions

Ask them in this order. The order is not cosmetic: 1 and 2 fix the noun and the
audience that every later sentence depends on, 3 changes file, and 4 and 5 are
the two that reliably produce specifics after three questions of abstraction.

### 1. What does this system own — what is it responsible for that nothing else is?

Produces the **system name and the scope section**. Take the noun from the
answer and use it, unvaried, in every requirement. Push once for the boundary:
the useful half of the answer is what it does *not* own and which system owns
that instead.

### 2. Who uses it, and what do they use it for?

Produces **ubiquitous and event requirements** — the observable surface, in the
users' own words. Ask for the last three real things somebody did with it, not
a persona list. A concrete action becomes an EARS sentence; a persona becomes a
paragraph nobody can test.

### 3. What must never happen?

**This one maps to constitution principles, not requirements.** A "must never"
is a bound on every future change, which is a `P`, not an `R`. Writing it as a
requirement files a permanent constraint in the place reserved for behaviour
that supersedes freely.

But **principles are ratified, never scaffolded.** So this question drafts a
*candidate* — in `.claude/productizer/constitution.md`'s shape, in the *Open
questions* table where a draft cannot be cited, never as a numbered `### P<n>`
section:

```
| Q1 | No export, report or support tool moves one tenant's data out of the
       tenant that owns it. | interview Q3, <who answered>, <date> | proposed |
```

A named human ratifies it — which allocates the `P` id, moves it into the body
and records the ratification on the principle itself. Nothing else promotes it.
An agent that writes `### P1` because someone said "we must never leak customer
data" has manufactured a governing constraint out of a sentence in a
conversation, and every later change is refused or allowed on its authority.

If the answer is also a testable behaviour, it can produce **both** a candidate
principle and an `If <unwanted trigger>, then …` requirement. Say which is
which.

### 4. What breaks most often?

Produces **`If <unwanted trigger>, then …` requirements** and the first rows in
*Areas of concern*. This is the question that gets you the failure modes a
first spec is otherwise guaranteed to be missing, because nobody writes down
the thing they are tired of.

Write what the system does today, not what it should do. A corrected
requirement no test asserts is a spec that disagrees with the running system
with nothing to reveal which is right. Where the answer describes a defect, say
so under *Areas of concern* in the same pass and offer to open an issue.

### 5. What shipped most recently, and why?

Produces the **most current requirements in the set**, and — uniquely — some
`why`. The survey refuses to infer why anything is the way it is, correctly:
the reason is not in the code. A person who shipped something last month has it.
Put the why in *Design*, cite the ids it serves, and keep it out of the
requirement sentence.

## Writing the answers up

Standard EARS (`references/ears.md`), with the same marker line import uses,
and the same absolute rules.

```
- **R3** — When a support engineer requests a customer export, the `atlas`
  service shall exclude every field marked internal.
  Inferred from interview Q2 (what users use it for), answered by <name>,
  <date>. Unconfirmed.
```

- **Every requirement names the question that produced it.** `interview Q2`,
  not "the interview". Five questions produce five different grades of
  evidence — Q5 is a fresh memory, Q1 is a definition somebody improvised — and
  a reader deciding whether to promote needs to know which one they are
  holding. This is the provenance rule, unchanged: one requirement, one
  citation, or it is not written.
- **Name who answered and when.** A survey citation resolves to a file and a
  line forever. An interview citation resolves to a person, and the only thing
  that keeps it checkable is their name being in it.
- **`Unconfirmed.` is load-bearing punctuation.** It is what every later stage
  keys off. Never write an inferred requirement without it, never edit it away
  as tidying, and never drop it because a human said the sentence out loud —
  saying it and ratifying it are different acts, and the second one is a commit.
- **Inferred requirements cannot halt.** A contradiction against one is
  downgraded to the confirmation question, exactly as in `references/import.md`.
  Only active requirements trigger the Stage 2 stop, because a halt is a claim
  that somebody agreed something.
- **No acceptance criteria row** until promotion. That table is for active
  requirements, and its length against the active count is what answers "do the
  tests assert the criteria".
- **Ids come from the normal counter** in the spec header. No provisional id
  space: promotion would have to renumber, and ids are never renumbered.

### Volume

**No more than fifteen requirements from a five-question interview**, against
import's thirty. The cap is lower because the evidence is: nothing here is a
passing assertion or an executable route, and a human still has to read every
sentence and say whether it is true. Where an answer clearly holds more, say
which areas you left and offer a second pass scoped to one of them.

Where the survey reached only the weak tier, its own cap of **ten** applies to
what you draft from *it* — the interview's fifteen is separate, and each
requirement carries whichever citation it actually came from.

## What to refuse to write down

The same refusals as import, plus one the interview creates.

| Refuse | Because |
|---|---|
| Any number nobody stated — timeouts, limits, retention, p95 | An invented threshold becomes a requirement the system was never built to meet |
| A behaviour nobody was asked about | Five answers do not cover a system; the gaps are findings, not blanks to fill |
| A principle as `### P<n>` | Principles are ratified. A candidate goes in *Open questions* and stays there until a named human moves it |
| A requirement from an aside | "We should probably…" is a plan, not a description. Ask whether it is true today |
| Anything the answer hedged | "I think it still…" is a question for someone else, filed under *Areas of concern* |
| A tidied version of what was said | Rewriting an answer into confident spec prose launders a guess into a citation |

## Promotion

Identical to import, and worth repeating because the interview makes it feel
unnecessary: **a human answering the question is not a human ratifying the
requirement.**

Present the drafted sentences back, in batches of about ten, and take an answer
naming ids or an explicit yes to that batch. Never promote on silence, never on
"looks fine" for a list that was not displayed, and never because the same
person answered the question the sentence came from — they answered a question
about a system, and the sentence you wrote from it is yours.

To promote: delete the `Inferred from … Unconfirmed.` line, add the acceptance
criteria row, and record the ratification in the decision record with the date
and who confirmed it. Promotion is a commit, and the spec diff then names which
sentences a specific person ratified on a specific day.

Rejections are as valuable as confirmations: `Withdrawn. Rejected at interview:
<reason>.` The id is spent, which is the correct cost.

## Report

- The spec path, the id range allocated, and the count drafted.
- **Counts per question** — which of the five produced what. A pass where four
  requirements all cite Q1 is a pass that asked one question.
- Every candidate principle raised, and that each is a candidate awaiting
  ratification, in *Open questions*, citable by nobody.
- Every refusal above, as a named gap.
- Questions that produced nothing. An unanswered Q3 is the most important line
  in the report: nobody could say what must never happen.
- The next action: which batch to confirm first.

Say plainly, in the report and in the spec header line for the change, that
**nothing in this spec is agreed yet.**
