# Suspect links — what a rewritten sentence invalidates

`references/traceability.md` gave the id a permanent name and two directions of
lookup. This file covers the thing permanence buys and never pays for: **the
citation that still resolves, and is now wrong.**

Rewrite R5's sentence in place. Its id does not move, its status does not move,
so:

- the acceptance-criteria row still says R5 is verified by a named check — a
  check that was written against the old sentence;
- that check's `coverage.spec_units` still claims R5 `Covered`, and the run
  still goes green;
- a downstream requirement still says "as required by R5";
- `git log --grep='Productizer-Req:.*R5'` still lists the commits, which built
  the old sentence.

Nothing errors. Nothing is red. Every link resolves, and every one of them may
now be about a different agreement. The trailer records **which requirement a
commit served**, which is provenance; provenance never invalidates anything.

## What the incumbents do, and what this takes from each

| Tool | Mechanism | Cost |
|---|---|---|
| DOORS | changing an object marks every linked object **suspect**; a person clears the flag | needs a person, and a place to record the clearing |
| OpenFastTrace | the revision is **inside** the id (`req~name~3`); bumping it voids existing links by construction | requirement ids are no longer permanent |
| this repo, before | permanent ids + `Productizer-Req:` trailers | records provenance, invalidates nothing |

OpenFastTrace's answer is not available here: `references/ears.md` makes ids
permanent, never reused and never renumbered, and that is R2. A revision inside
the id is precisely a renumbering with a nicer name.

So the mechanism is DOORS' half. The id stays permanent; **the change raises a
flag against everything downstream**, and the flag is cleared by the dependant
moving too, in the same change.

## The three cases, which must not be collapsed

Everything below turns on telling these apart. A tool that reports them alike
is either silent about the one that matters or so loud about the other two that
people switch it off.

| What happened | Who owns it | Why |
|---|---|---|
| the **id** changed, or the **status** changed — a supersede, a withdrawal, a split | `check-superseded-text.sh` | a supersede leaves a forward pointer. The old sentence is retained and marked, and the citation still leads somewhere a reader can follow |
| the **sentence** changed in place, id and status unchanged | `check-suspect-links.sh` | the citation resolves and leads to different words. Nothing marks it, nothing points anywhere, and no diff after the merge shows it |
| a **typo fix** or a **re-wrap** | nobody can tell | see below. This is the honest limit, and it is not a small one |

## The limit: a typo and an inversion are the same event

`scripts/spec-requirements.sh` normalises whitespace, so a re-wrap never
reaches the comparison at all. Everything past that is a word change, and the
check measures **the shape of the edit, never its meaning**:

```
R5 status active unchanged, sentence CHANGED at .claude/productizer/spec.md:23 (1 word(s) removed, 1 added)
```

That line is identical for `renumberred` → `renumbered` and for `shall` →
`shall not`. It is identical for `all` → `most`. No measurement available to a
shell script separates them, and the check says so on **every** run, clean or
not:

```
LIMITATION, on every run: this check CANNOT tell a semantic rewrite from a typo fix.
```

This is why the check is declared `advise` and not `block`. A gate that holds
the merge on a distinction it cannot make is a gate people learn to route
around, and a routed-around gate measures nothing at all. Its **exit 2** still
blocks whatever the severity says, which is the right asymmetry: a flag you can
disagree with is cheap, and not knowing is not.

## What counts as a dependant

Every tracked file that names the id, minus the requirement's own definition
line. In this repository that is, in rough order of how much it matters:

1. the **acceptance-criteria row** — the row asserting how the requirement is
   verified. If the sentence moved and this did not, the row now claims a check
   verifies something the check was never written against;
2. the **coverage claim** in `checks.yaml` — `spec_units: - id: R5` and the
   `evidence` beside it;
3. **another requirement's sentence** or its forward pointer;
4. the **change-log** and **decision-record** rows;
5. reference documentation, the backlog, and the classification records — which
   are provenance: a flag on one of those says the decision was made against
   different words, not that the file should be edited.

### Two trees are excluded, and the reason was measured

Any path with a `fixtures/` or `evals/` component. Those hold their **own**
example specs, with their own R-numbering, so an `R3` there is a different
requirement wearing the same name. Measured on this repository: 81 tracked
files match `R3`; 19 of them are outside those two trees. Reporting all 81
would not be a false positive at the margin — it would be three quarters of the
output, and a check whose findings are mostly noise is one nobody reads.

## Clearing a flag

A citation is cleared when **its own line moved in the same change**. Somebody
had both texts open; that is the whole of what clearing means here, and
demanding a second signal would make the flag unclearable.

**Per line, never per file** — and this is not a detail. The first version of
the check asked whether the *file* had been edited, and on the very first
fixture it reported the acceptance-criteria row as reviewed. It had not been.
The row lives in the spec, and the spec is by definition the file the
requirement was rewritten in, so every dependant inside the spec cleared itself
the moment the requirement moved. A per-file rule is structurally blind to
exactly the dependants that matter most. That was found by running the fixture,
not by reading the script.

The cost of per-line is a **third state**, which is reported and is *not* a
clearance:

```
SUSPECT .claude/productizer/checks.yaml:5  check declaration - this line is untouched,
  so it still points at wording that moved. The file WAS edited in this change and this
  line was not, so read this one first.
```

A coverage claim's `- id: R5` line never changes by construction, so rewriting
the evidence beside it does not clear the claim. Rather than invent a
clearance, the check says the file was touched and hands the reader a triage
order.

## Empty is not clean

Four ways to compare nothing, all **exit 2**, never 0:

| Situation | Why it is not a pass |
|---|---|
| the base ref does not resolve | a shallow clone, or a wrong ref. Whether anything moved is unknown |
| the spec did not exist at the base | there is no earlier sentence for anything to have moved from |
| either version of the spec holds no requirements | nothing was compared |
| the dependant scope resolved to no tracked files | a scan that opened nothing found nothing, and the two are not the same |

A spec **byte-identical** to the base is not one of them. That is a comparison
that ran, and it exits 0.

## Running it

```sh
plugins/productizer/skills/spec/scripts/check-suspect-links.sh
plugins/productizer/skills/spec/scripts/check-suspect-links.sh --base origin/main
```

`--base` defaults to `HEAD`, which compares the work tree against the last
commit — the shape of a pre-push run. In CI, pass the merge base, and fetch
full history: a shallow clone is refused, never passed.

Exit codes: `0` compared and no suspect dependant · `1` findings · `2` could
not run or could not measure.

## What it cannot do

- **Tell a semantic rewrite from a typo fix.** Stated above, stated again in
  the output of every run. This is the whole residual risk.
- **Tell a template from a citation.** `templates/spec.md` carries an `R3` that
  cites nothing.
- **See past one base ref.** An edit merged before the base is, to this check,
  the agreed text. `check-superseded-text.sh` covers the other side of that
  blindness for superseded requirements only; for an active requirement
  rewritten three commits ago, nothing does.
- **See a citation that does not name the id** — a paragraph quoting the
  sentence instead. Nothing here resolves prose.
- **Record an acknowledgement.** DOORS clears a suspect flag by a person's act.
  Nothing in this repository records such an act, so a dependant re-read and
  found still correct stays flagged until its line is touched.
- **Follow a requirement across files.** It reads one spec path; a requirement
  moved between files in a split spec reads as gone.
