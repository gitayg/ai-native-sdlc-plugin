# Measuring the halt

The plugin's one promise is Stage 2: an intent that contradicts an agreed
requirement stops the work instead of merging. `references/solver.md` measures
the arithmetic under that promise and reports 0.70 recall over a 21-pair corpus
the checker's own author wrote. This corpus measures the promise itself — the
model, reading the skill, against a whole spec — and it is deliberately built out
of the classes that document names as undecidable.

It runs on `claude plugin eval`, which puts each case in a fresh isolated
session with only this plugin loaded, scores it against a weighted checklist, and
runs the same case again with no plugin at all so the two can be subtracted.

## The shape

Twenty-six cases at `evals/cases/<slug>/`, each one three things:

| Part | File | What it is |
|---|---|---|
| Spec fixture | `prompt.md` body | a whole living spec plus its constitution, inlined |
| Arriving intent | `prompt.md` body | one intent, in the voice of the person who asked for it |
| Weighted checklist | `graders/*.md` | one criterion per file, each with a `weight` |

Sixteen cases must halt and ten must not. 136 scored criteria across them, plus
26 unscored plugin-fired indicators. `evals/check-corpus.py` prints those numbers
off the files rather than from memory; quote it, not this paragraph.

Fixtures live twice on purpose. `evals/fixtures/` holds them once as the editable
source, and each `prompt.md` inlines the one it uses, because an eval run gets a
throwaway workspace with no repository in it — a case that read
`.claude/productizer/spec.md` would be grading whatever happened to be in the
machine it ran on. Two copies drift, so `check-corpus.py` asserts each prompt
still contains its fixture byte for byte and exits 1 when it does not.

Every case ends its prompt with a required last line — `VERDICT: EXTEND`,
`REFINE`, `DUPLICATE` or `CONTRADICT`. Both arms get that instruction, so the
regex reading it measures judgement rather than vocabulary. Without it the
detection criterion would be an LLM judge, and the one number this corpus exists
to produce would be noisy.

## Why recall outweighs precision, in the weights

A false halt costs a human a minute. A missed contradiction ships a requirement
that conflicts with one already agreed, into a spec that stays internally tidy
and downstream-citable while being wrong. The two are not symmetric and the
scoring must not pretend they are: **missing critical information is worse than
including extra information.**

That is stated three times, arithmetically, so it cannot quietly stop being true:

- **Inside a must-halt case.** Detecting the contradiction carries 10 of 25
  scored weight points and halting the work carries 6 — 64% of the case score
  between them. Citing ids, refusing to supersede, stating the conflict and
  asking for a ruling share the other 36%. A run that explains a conflict
  beautifully and then classifies it as an extend scores badly, which is correct:
  it shipped the conflict.
- **Inside a must-not-halt case.** Not halting carries 6 of 14 — 43%. Lower than
  64% on purpose. That difference is the exchange rate, written down.
- **Across the corpus.** 16 of 26 cases must halt, so 62% of the suite score is
  recall-bearing before any weight is applied.

The ten negatives are not decoration. Recall-weighting without them rewards a
classifier that halts on everything, which is the one failure mode that gets the
check switched off inside a week — after which the missed-contradiction rate
returns to what it was, plus the time spent building the check.

## What the cases attack

The classifier already handles lexical and dispositional opposites; the shipped
lexicon carries eight disposition pairs including `reject`/`queue`. Adding more
of those would measure nothing. Every must-halt case here is drawn from a class
`solver.md` names as out of reach of the arithmetic:

| Class | Cases | Why it is hard |
|---|---|---|
| Vocabulary drift | P02, P04, P05, P15 | one event, two wordings, written months apart |
| Constitution-mediated | P06, P07, P08 | the other side is a `P`-numbered principle, not a requirement |
| Superseded text misread | P09 | the retained sentence agrees with the intent; the live one forbids it |
| Numeric across units | P10, P11 | 99.9 percent against 90 minutes; six weeks against 30 days |
| Domain entailment | P01 | conflicts only because a third requirement says what the log contains |
| Spans three requirements | P12, P13 | pairwise fine, jointly unsatisfiable |
| Guard narrowing | P14 | the narrower guard does not escape the broader one |
| Framing | P16, P03 | a contradiction presented as a refinement; a bound stated as an adjective |

The negatives mirror them one for one. `N07` is `P02` with the drift left in and
the meaning unchanged — a duplicate, not a conflict — so a classifier that
learns *different words mean conflict* fails it. `N08` resembles the superseded
text `P09` turns on and must still not halt. `N09` sits in the area `P1` governs
and complies with it.

## Running it

```
claude plugin eval . --no-publish
```

From the repo root, not the plugin directory: the cases are at `evals/` beside
`plugins/`, and each declares `plugins: ["../../../plugins/productizer"]` so the
plugin loads for the `with` arm. Targeting `plugins/productizer` finds no cases.

`--case '<glob>'` and `--tag <tag>` narrow it; `--runs 1` cuts the cost of a
smoke pass by two thirds. Tags are the miss class (`vocabulary-drift`,
`constitution`, `numeric`, `n-ary`, `superseded`, `false-positive-bait`) plus
`positive` or `negative` and the fixture name.

Then:

```
python3 evals/check-corpus.py --recall evals/results/<timestamp>/aggregate-result.json
```

which reduces the run to the only question the plugin asks — halt, or do not
halt — and prints recall with its n attached. **It prints the n because the n is
the finding.** Sixteen must-halt cases is a cohort: one case is six recall
points, and a figure quoted without its sample size will be compared to the 0.70
in `solver.md`, which is a different measurement of a different thing.

`--threshold` defaults to 1.0, so any imperfect case exits 1. That is the right
default for a gate and the wrong one for a measurement — this corpus is expected
to be red until the classifier improves, and a suite that is green on its first
run is either trivial or measuring nothing.

## Reading the ablation delta

`--ablation with-without` is the default whenever a plugin resolves. Each case
runs twice: once with the plugin, once with nothing but Claude Code. The
difference is the plugin's contribution, and it is the only number in the report
that is about the plugin rather than about the model.

- **Delta near zero on a must-halt case** — the model would have caught it
  anyway. The case is measuring the model, not the skill. Keep it as a
  regression guard, do not count it as evidence the skill works.
- **Delta near zero on a must-not-halt case** — good. The skill should not be
  buying its recall with false halts.
- **Negative delta** — the plugin made it worse. That is the finding, and it is
  the one worth chasing before any improvement is claimed.
- **`99-skill-fired` reported `[with-only, not scored]`** — the indicator that
  the skill loaded at all. It is excluded from both arms' scores so it cannot
  inflate the delta. When a case is red and this indicator is red too, the skill
  never fired and the case says nothing about the skill.

## Adding a case

Copy the nearest existing case directory and edit three things.

1. **`prompt.md`** — set `name` and `tags`, keep the `plugins` line, replace the
   intent. If it needs a spec the fixtures do not cover, add one to
   `evals/fixtures/` and inline it verbatim; `check-corpus.py` enforces that.
2. **`graders/`** — keep the numbering. `01` is the recall or precision
   criterion and stays the heaviest; `99-skill-fired` stays untouched. Write each
   criterion so a reader who has not seen the spec can decide it, and say in the
   body what the conflict actually is — a rubric that only says "correctly
   classified" grades the judge's mood.
3. **`evals/solver-probe.py`** — add the EARS pair, or record that there is none.

Then run `python3 evals/check-corpus.py`, which is the fast structural pass, and
`python3 evals/solver-probe.py`, which tells you whether the deterministic check
already decides your case. If it does, the case is not attacking the gap.

A new case must be **seen failing**. One that is green the first time it runs is
either already handled or wrongly graded, and either way it is not evidence.

## What this corpus does not measure

Say this plainly rather than letting a green report imply otherwise.

- **It does not measure the pipeline.** One turn, one intent, one reply. Nothing
  is written to a spec, no issue is opened, no branch exists, no PR is reviewed.
  Stages 1 and 3 through 9 are untouched.
- **It does not measure retrieval at scale.** Every fixture is one screen of
  requirements, inlined. A real living spec is two hundred requirements the model
  has to find the relevant six in, and that search is a plausible source of
  misses this corpus cannot see.
- **It does not measure the arithmetic check.** `contradiction-check.py` never
  runs inside an eval case. `evals/solver-probe.py` measures it separately, and
  its recall is a different number about a different component.
- **It does not measure repeated exposure.** Each case is cold. A spec accreted
  over a year by several people, where the drift is between two requirements
  neither of which the model wrote, is the real case and is not reproduced here.
- **It does not measure the ruling.** What a human decides after the halt, and
  whether the ruling is recorded so it outlives the conversation, is
  `references/rulings.md` and has no case here.
- **Its precision figure is soft.** Ten negatives across four bait classes is
  enough to stop a halt-on-everything classifier scoring well. It is not enough
  to put a number on precision, and any precision quoted from it must carry
  n=10.
