# Deciding contradiction, instead of judging it

The plugin's one promise is that it halts when an incoming requirement
contradicts an agreed one. Today that judgement is a model reading two
sentences. The failure mode is silence: a missed contradiction produces a spec
that is internally tidy, downstream-citable, and describing behaviour nobody
signed off. Nothing errors. Nothing goes red.

EARS is unusually amenable to a mechanical answer, because every requirement
already names a guard, a subject and an observable response. A subset of
contradictions between such sentences is arithmetic, not interpretation. This
document states which subset, how it is decided, where the boundary sits, and
what the decided part is worth.

## What the research actually shows

Read this section as: two things are demonstrated, one thing is repeatedly
claimed and does not survive contact with a real spec.

**Structured requirements plus a solver beats human review on the classes it
covers, and it is fast.** Twenty-five avionics high-level requirements written
in a controlled grammar were parsed to logical expressions and checked
pairwise; the method found six contradictions in twenty-five seconds, including
one arising through a hypothetical syllogism — an operation in one requirement
serving as a condition of another — that none of ten reviewers with two to five
years' experience found in half an hour. Those reviewers found four
contradictions, taking twenty-one minutes on average.
<https://arxiv.org/abs/2405.00163>. The stated limitation is the one that
matters here: the method carries no natural-language processing at all, so the
translation to logic is manual, and a grammar must be written per requirements
standard.

**Realizability checking of structured requirements is a shipped, industrial
capability, and its expressiveness limits are published.** A NASA requirements
tool formalises a restricted natural language of six fields — scope, condition,
component, shall, timing, response — into past-time metric temporal logic, then
checks whether an implementation satisfying the whole set can exist, returning
minimal unrealizable cores and simulable counterexamples. Eight scopes, ten
timings and an optional condition give one hundred and sixty distinct
formalisation templates. Its authors state plainly what the language cannot
express: arbitrary nesting of temporal operators, and timed operators with
intermediate bounds.
<https://ntrs.nasa.gov/api/citations/20220007510/downloads/TechnicalReport__FRET_Realizability_Checking.pdf>.
The same report notes that a widely used k-induction backend "is not sound with
respect to unrealizable results" — a solver saying *conflict* is not
automatically a conflict, which is the single most important sentence in the
literature for this plugin. A separate tool takes EARS specifically to a
decidable LTL fragment for controller synthesis, so EARS-to-formal is a trodden
path rather than a novel one <https://ceur-ws.org/Vol-2019/demos_2.pdf>.

**The headline LLM-plus-solver numbers are from curated sets and do not
transfer.** The satisfiability-aided approach commonly cited for this idea
reports precision 1.00, recall 0.83, F1 0.91 on conflicting-requirement
detection, ahead of a chat model alone
<https://doi.org/10.1145/3691620.3695302>; the figure is repeated in survey
work <https://arxiv.org/html/2507.14330v2>. Against that, a system combining
formal logic with language models, evaluated on a real electric-bus project,
reports roughly 99% precision and 60% recall
<https://dl.acm.org/doi/abs/10.1007/s10515-024-00452-x>. The gap between 0.83
and 0.60 is the gap between a benchmark and a specification someone actually
wrote. Assume the lower number. Note also which figure holds up in both:
precision. Formalise-then-decide is reliably quiet when it is quiet, and
reliably incomplete.

The general translation step is the weak link, not the solving step. Survey
results put natural-language-to-formal conversion in the seventy-to-ninety-plus
percent band depending on scope, and identify the pattern directly: small,
well-defined scopes translate; whole specifications do not
<https://arxiv.org/html/2507.14330v2>. EARS exists to make the scope small.
That is the entire reason this is worth attempting here and not on prose.

## The pipeline

Four stages. Each one either produces a structure or declines to, and declining
is a supported outcome at every stage.

**1. EARS to a parse.** Six sentence templates, matched longest-first so that
`While <state>, when <trigger>, …` is not mis-read as a bare state pattern. Out
comes `{id, pattern, guard, system, response}`. A sentence matching no template
is reported as unparsed and never silently skipped — a requirement dropped for
being ill-formed is a requirement never checked, which reproduces the exact
silence the tool exists to remove.

**2. Parse to a structured form.** Three extractions, all shallow and all
reversible by eye:

- *Bounds*: comparator, magnitude and unit, normalised to one base per
  dimension, folded into a half-open interval per dimension. `under 200 ms`
  becomes `(-inf, 200)`; `at least 500 ms` becomes `[500, inf)`. Inclusivity is
  tracked, because `at most 200` and `under 200` differ at exactly 200 and
  requirements are argued over at exactly the boundary.
- *Content tokens*: the words of a phrase with numbers, units, comparators and
  function words removed — what is being measured, stripped of how much. Two
  bounds are only ever compared when the things bounded are the same. Without
  this, every latency budget in the spec conflicts with every retention window.
- *Exclusion signals*: explicit negation, a closed lexicon of opposed verbs, a
  single-attribute assignment form, and a response status code.

**3. Structured form to a decision.** Guard relation first, response second.
The guard relation answers *can these two requirements ever be in force at the
same time* and returns EQUAL, OVERLAP, DISJOINT, UNRELATED or UNKNOWN.
Requirements whose guards cannot both hold do not conflict however opposed
their responses look, and this is where most naive contradiction checkers
generate their false positives. Only under EQUAL or OVERLAP does an
incompatible response become a contradiction.

**4. Decision to a verdict.** Four values, not two.

| Verdict | Meaning | Action |
|---|---|---|
| CONTRADICTION | Decided incompatible under a guard that can hold | Halt, quote both ids, ask |
| REFINEMENT | One requirement is strictly stricter, same guard | Edit in place, same id |
| CONSISTENT | No incompatibility inside the decidable fragment | Proceed |
| UNDECIDED | Signals conflict, guard relation unresolved | Hand to judgement |

UNDECIDED is not a failure to answer. It is the whole reason the check is
safe to run. A three-valued tool that only ever said CONTRADICTION or
CONSISTENT would be asserting coverage it does not have, and its CONSISTENT
would carry the same silent-miss risk as the model's. CONSISTENT here means
*nothing decidable was found*, and the model still reads the pair.

## What is decidable

Three classes, and they are narrow on purpose.

**Numeric bounds that cannot both hold.** Same subject, same measured quantity,
guards that can co-occur, intervals whose intersection is empty. This subsumes
the refine-versus-contradict rule the spec already states: tightening 200 ms to
100 ms is containment, moving 200 ms to 500 ms is disjointness, and the two are
told apart by interval inclusion rather than by which number looks bigger.

**Mutually exclusive responses under an overlapping guard.** Explicit negation
of the same response; a closed lexicon of opposed verbs matched on stems; one
attribute assigned two values; one trigger answered with two status codes.

**Overlapping state guards with incompatible outcomes.** The state-driven and
complex patterns, where the guards are ranges over the same quantity or where
one guard is a strict narrowing of the other. `While a session is idle` and
`While a session is idle for 30 minutes` overlap; the narrower one implies the
broader, so opposed responses under them collide.

## What is not decidable, and never will be by this route

**Meaning.** `The API shall be responsive` against a latency bound. There is no
proposition to intersect. EARS already bans unquantified adjectives for exactly
this reason, which converts some of this class into a lint failure rather than
a contradiction — but only some.

**Vocabulary drift on the same trigger.** *A customer cancels their
subscription* and *a subscriber terminates their plan* are one event in two
wordings. Nothing lexical resolves them, and a lexical checker faced with them
reports UNRELATED, which is a miss. This is the largest single source of missed
contradictions in a real spec, because specs are written by different people
over months.

**Domain entailment.** *Remove all personal data within 30 days* against
*retain the audit log indefinitely* is a contradiction if and only if the audit
log holds personal data. That fact lives outside both sentences.

**Cross-cutting and n-ary conflicts.** Three requirements that are pairwise
fine and jointly unsatisfiable. Pairwise checking cannot see them; realizability
checking over the whole set can, at the cost of a temporal-logic encoding and a
model-checking backend, with the soundness caveat noted above.

**Ordering and real-time interaction.** *Within 5 ticks* against *for 5 ticks*
needs metric temporal logic, not interval arithmetic. Reachable, but a
different tool.

### Where the line falls

An estimate, not a measurement, and the basis is stated so it can be argued
with. On a spec whose requirements were written to the EARS discipline by one
team over a short period, expect the decidable fragment to cover roughly half
of genuine contradictions. On a living spec accumulated over a year by several
people — the case this plugin is actually built for — expect a third, because
vocabulary drift on the trigger is the dominant class and it is squarely on the
undecidable side. The corpus in the prototype catches six of nine, but that
corpus was written by the same hand that wrote the checker and should be read
as an upper bound, not a result. The independently evaluated real-project
figure in the literature is 60% recall with a language model in the loop as
well; a purely lexical fragment with no model should be expected to sit below
it.

## Why false positives govern the design

A missed contradiction costs one wrong requirement. A false halt costs the
tool. A check that stops work on a non-conflict is switched off inside a week,
after which the missed-contradiction rate returns to whatever it was before,
plus the time spent building the check. Precision is therefore not one metric
among several; it is the constraint, and recall is what is spent to buy it.

Three design choices follow, each named by the failure it prevents:

- **Guard relation before response comparison.** Prevents halting on
  complementary requirements — authenticated against not authenticated, under
  100 requests against over 1000 — whose responses are opposed by design.
- **UNKNOWN guards downgrade a hit to UNDECIDED rather than raising it to
  CONTRADICTION.** Prevents the opposed-verb lexicon firing across two
  different triggers, which is the lexicon's characteristic failure.
- **REFINEMENT is only claimed when the guards are equivalent or nested.**
  Prevents a worse error than a false halt: recording *edit in place, same id*
  for two requirements about different triggers, which merges two behaviours
  under one id and splits nothing visibly.

## Measured behaviour

The prototype is `scripts/contradiction-check.py`. It is standard library only;
an SMT solver is used, when importable, purely to cross-check the interval
arithmetic and is never required to run. Over a twenty-pair corpus spanning
decidable contradictions, near-miss non-contradictions and semantic
contradictions:

```
true positives  6   false negatives 3   false positives 0
true negatives 10   undecided       1
precision 1.00      recall 0.67     decided 19/20
```

All three misses are semantic: domain entailment, vocabulary drift, and an
unquantified adjective. Every false-positive bait case — negated guards,
numerically disjoint guards, opposed triggers, duplicate statements, an
opposed-verb pair under unresolved guards — stayed quiet or escalated.

Each defence was verified by breaking it and watching the corpus go red:
disabling interval emptiness lost the numeric class; disabling guard
disjointness produced two false halts; removing the UNKNOWN-guard downgrade
produced a third. Tests never seen failing are not evidence, and a green
confusion matrix from an untested checker is the same silence this document
opens with.

## How it wires into intake

Run it at classification time, before the model classifies. Against each active
requirement in the living spec:

- CONTRADICTION — halt with the ids and the arithmetic. The reason line already
  states the conflict in one sentence, which is what a good stop needs.
- REFINEMENT — offer refine-in-place, same id, with the interval containment as
  the recorded reason.
- UNDECIDED — pass to the model with the reason attached, so it is judging a
  named suspicion rather than reading two sentences cold.
- CONSISTENT — pass to the model unchanged. It means *not decided*, never
  *cleared*.

The check adds a decided lower bound to the model's judgement. It does not
replace it, and any wiring that lets a CONSISTENT verdict skip the model has
reintroduced the original failure with a solver's authority attached to it.

## Recommendation

Ship it as a second opinion that can halt on its own, never as a replacement.

The argument is from the measured shape of the results, not from the papers.
Precision was perfect and recall was two-thirds on a corpus built to be
favourable; against a real accumulated spec, recall will be lower and precision
will be roughly what it is here, because the guard gate that produces the
precision is independent of how the requirements were written. That profile —
reliably right when it speaks, reliably incomplete — is a second opinion. It is
not a replacement, and a tool with two-thirds recall installed as a replacement
would be strictly worse than the model it replaced, because it would attach a
mechanical verdict to the two-thirds and nothing at all to the rest.

It earns its place on three things the model cannot offer. It is deterministic,
so the same pair decides the same way in review as it did at intake. It shows
its arithmetic, so a halt is arguable rather than assertable. And it is
independent, so a model that has talked itself into merging a contradiction
still meets a check that has not.

Do not ship it silent. If the numeric and exclusion classes ever run without
surfacing UNDECIDED and without the model reading the CONSISTENT pairs, the
plugin will have traded a judgement that is sometimes wrong for a decision
procedure that is confidently narrow, which is worse.
