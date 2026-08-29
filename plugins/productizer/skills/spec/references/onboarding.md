# Onboarding — one command, and what it refuses to do

Stage 0 was six steps: run `detect-context.sh`, scaffold four files one at a
time, verify `.claude/` is not gitignored, run `import-survey.sh`, draft up to
thirty requirements, have a human promote them. Each with its own failure mode
and no single entry point.

The cost was never time. Detection takes about 1.5s and the survey about 0.7s.
The cost was the number of orders you could do them in, and the number of them
you could silently skip.

```
scripts/init.sh                 # the whole of Stage 0
scripts/init.sh --dry-run       # every action, no writes
scripts/init.sh --repo <path>   # somewhere other than the cwd
```

## What it does, in order

1. **Refuses outside a git work tree.** Every claim this lifecycle makes about
   an audit trail is a claim about `git log -p` over the spec. Four files and a
   promise nothing can keep is worse than no files.
2. **Runs `scripts/detect-context.sh`** and reads three things from it: the
   `interactive` flag, whether `.claude/productizer/config.json` exists, and
   which repo templates override this skill's. It does not re-implement the
   probe, and it does not bind anything — binding is a question, and this
   command never asks one.
3. **Verifies the spec path is committable, before writing anything.** Below.
4. **Scaffolds four files through `scripts/scaffold.sh`, never `cp`.**
5. **Asserts nothing agreed-by-nobody got seeded**, and reports the counts.
6. **Runs `scripts/import-survey.sh`** on a repo with history, and surfaces its
   verdict rather than re-deriving one.
7. **Prints what was written, what was skipped, and what it needs from you.**

That third section is the deliverable. The rest is bookkeeping: a run should
end with a person knowing exactly what is still required of them.

## The gitignore check

The single most important thing the command does.

`.claude/` is routinely gitignored — it is where tooling puts caches, and a
`.gitignore` written before this skill existed will not have made an exception.
A scaffold that reports success while the spec stays untracked leaves an audit
trail that **looks present and is not**, which is strictly worse than no spec:
the spec exists, gets cited, gets read as history, and none of it is in any
commit.

So the check runs before the first write, and a failure is a refusal — exit 4,
nothing written, with the matching rule quoted.

Two details, both measured, both wrong in an earlier version:

**The verdict comes from bare `git check-ignore`, never from `-v`.** With `-v`,
git exits 0 whenever any pattern matches — and a *negation* counts as a match.
On git 2.50.1, against a `.gitignore` carrying `!.claude/productizer/**`:

```
$ git check-ignore -v .claude/productizer/spec.md
.gitignore:4:!.claude/productizer/**	.claude/productizer/spec.md
$ echo $?
0                       # "ignored", says the -v form
$ git check-ignore .claude/productizer/spec.md ; echo $?
1                       # not ignored, says the bare form
$ git add .claude/productizer/spec.md ; git status --porcelain
A  .claude/productizer/spec.md          # the bare form was right
```

The `-v` form would refuse a perfectly committable spec on exactly the repos
that had already fixed their `.gitignore` correctly. `-v` is used only to name
the rule once a refusal is decided.

**Exit 128 is never folded into exit 1.** `check-ignore` exits 0 for ignored, 1
for not ignored, and 128 for "I cannot tell you" — a corrupt index, an
unreadable `.gitignore`, a permissions problem. Discarding stderr made 128
indistinguishable from 1, so the one case where the check did not run reported
as the case where it ran and passed. An unanswered check is not a passed check;
init refuses.

### Fixing a gitignored spec path

Git cannot re-include a file whose parent directory is excluded, so adding
`!.claude/productizer/` under a `.claude/` rule does nothing at all. Widen the
parent rule instead:

```
.claude/*
!.claude/productizer/
```

Verified on git 2.50.1: the spec then stages, and everything else under
`.claude/` stays ignored. The refusal prints this.

## What it writes

Four files, through `scripts/scaffold.sh`, which strips the templates' fenced
worked examples on the way in.

| File | Left as |
|---|---|
| `.claude/productizer/spec.md` | empty, next id `R1` |
| `.claude/productizer/constitution.md` | **no principles** |
| `REVIEW.md` | repo root, as-is |
| `CLAUDE.md` | repo root, only if absent |

Never `cp`. The templates carry worked examples — `R1`…`R6` in the spec,
`P1`…`P5` in the constitution — so a human can see the shape, and copying them
verbatim seeds a repo with requirements and principles nobody agreed to. That
is not a hypothetical: an end-to-end run did it with a plain `cp`, which is why
scaffolding is a script and not a sentence.

**An empty spec is the correct starting state.** A seeded `R1` is a requirement
nobody agreed to and it gets cited before anyone notices it was a sample. The
constitution is left with no principles for the stronger version of the same
reason: a principle is a bound on every future change, and a scaffolded one
governs with the authority of one somebody ratified.

Init asserts this rather than trusting it — it greps the files it just wrote
for requirement definitions and principle sections and reports the counts, so a
template edited to move an example outside its fence is caught rather than
shipped. It also reports the placeholder rows that live *outside* the fences
(the spec's index and criteria tables, the constitution's amendment record).
Those survive scaffolding by design of the templates, they are shape rather
than content, and a reader cannot tell — so they are named under *what it needs
from you*, not passed over.

### Never overwrites, and says so

Every existing file is skipped and named. Running the command twice is safe:
the second run reports `state: already initialised — this run is a resume, not
a redo`, skips all four, and does not re-run the survey (it is a first-fill
step; the command names how to run it by hand). Partial state produces a mixed
report — the missing files written, the present ones listed as untouched, and
the files that were already there left byte-identical.

Repo templates in `.claude/productizer/templates/` win over this skill's, and
when one is in play the report says which, because a spec that does not match
the documented shape otherwise reads as a bug.

## When the interview fires

`import-survey.sh` reports one of three verdicts. Init surfaces it and does not
second-guess it:

| Verdict | What init says to do |
|---|---|
| `DRAFT TIER: STRONG` | Draft up to 30 `inferred` requirements from behaviour (`templates/import.md`) |
| `DRAFT TIER: WEAK` | **Interview.** The survey found no behaviour the code states to a machine and fell back to the repo's prose about itself |
| `NOT ENOUGH EVIDENCE` | **Interview.** Both tiers under their floor |

A repo with no commits is a fourth state, and it is *not* an evidence count of
zero — nothing was measured. Init says so and routes to intake instead: the
next intent that arrives becomes `R1`. Likewise a survey that fails or prints
no recognisable verdict is `unreadable`, never quietly folded into the weakest
tier. "The survey said little" and "I could not read the survey" are different
facts and only one of them is about the repo.

**The interview is gated on the `interactive` flag, not on the stage.** Where
nobody is present — a nightly eval, a scheduled band check, a CI step — init
reports what the repo needs and stops. That is the correct outcome, not a
degraded one. The alternative is a prompt into an empty room, which hangs a
scheduled run until it times out, and the alternative to *that* is drafting
requirements from an empty survey, which is invention that lands in the spec
looking exactly like evidence.

`templates/interview.md` holds the five questions. They are fixed, and the
order matters: 1 and 2 fix the noun and the audience every later sentence
depends on, 3 changes file, and 4 and 5 are the two that produce specifics.

1. What does this system own — what is it responsible for that nothing else is?
2. Who uses it, and what do they use it for?
3. What must never happen?
4. What breaks most often?
5. What shipped most recently, and why?

**Question 3 maps to constitution principles, not requirements** — a "must
never" is a bound on every future change, which is a `P`. But principles are
ratified, never scaffolded, so the interview drafts a *candidate* into the
constitution's *Open questions* table, where a draft cannot be cited, and a
named human moving it into the body is what allocates the `P` id.

## The inferred tier, and promotion

Interview answers land exactly as survey output does: **`inferred` and
unconfirmed**. Not a better grade. An answer typed by a human is a statement
about a system, not an agreement about it.

```
- **R3** — When a support engineer requests a customer export, the `atlas`
  service shall exclude every field marked internal.
  Inferred from interview Q2 (what users use it for), answered by <name>,
  <date>. Unconfirmed.
```

Every drafted requirement names **which question produced it** — `interview
Q2`, not "the interview". The five questions produce five different grades of
evidence, and a reader deciding whether to promote needs to know which one they
are holding. A survey citation resolves to a file and a line forever; an
interview citation resolves to a person, so their name and the date are what
keep it checkable.

Four properties follow, and they are the same four `references/import.md` sets
out — the interview inherits the mechanism rather than adding one:

1. **It carries its provenance**, reachable in one hop.
2. **It cannot stop work.** Only *active* requirements trigger the Stage 2
   contradiction halt. A conflict with an inferred requirement is downgraded to
   the confirmation question — *the system does X today; is X intended?* This
   is the rule that stops the lifecycle defending whatever the code, or
   somebody's memory, happened to say on onboarding day.
3. **It is not counted as verified.** No acceptance criteria row until
   promotion, because the row count against the active count is what answers
   "do the tests assert the criteria".
4. **Promotion is a commit.** Delete the `Unconfirmed.` line, add the criteria
   row, record who ratified it and when.

**Answering the question is not ratifying the requirement.** Present the
sentences back in batches of about ten, take an answer naming ids or an
explicit yes to that batch, and never promote on silence — not even when the
person who answered Q4 is the person reading R7. They answered a question about
a system; the sentence is yours.

Volume caps, and why they differ: **30** from a strong survey, **10** from a
weak one, **15** from an interview. None of them is about token cost. A human
has to read every sentence and say whether it is true, and a list nobody
finishes is approved wholesale — which produces exactly the fiction this stage
exists to prevent.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Done — everything written, or everything already present |
| 2 | Usage |
| 3 | Prerequisite missing: not a git work tree, no `python3`, or a helper script or template is absent |
| 4 | **Refused** — the spec path is gitignored, or git could not say. Nothing written |
| 5 | **Partial** — some work done, at least one step failed or was skipped for a reason that needs a human. The report names each one |

`--dry-run` performs nothing, including the survey, and says so under
*seeded-content check* and *survey* rather than reporting either as clean.

The command prints no timestamps, so two runs against an unchanged repo are
byte-identical and a diff between them means something.
