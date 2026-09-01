# Classification provenance — what a classification was made from

Intake classifies every arriving intent against the living spec as exactly one
of extend, refine, duplicate or contradict. Two requirements govern that act,
and neither of them is about the answer:

- **R6** — *When an intent arrives, the lifecycle shall classify it against the
  whole living spec as exactly one of extend, refine, duplicate or contradict.*
- **R19** — *If the spec home is unreachable, then the lifecycle shall stop
  rather than classify against a remembered copy.*

Both are about the **input**. Neither can be proven by looking at the output.

A graded eval of the classifier scored 16 out of 16 on outcomes. That number is
equally consistent with two very different systems: one that read all
twenty-five active requirements and reasoned over them, and one that read the
first eight and got lucky on a small spec. Outcomes cannot separate those, and
the gap widens with every requirement added — the classifier that sees half a
spec is right most of the time right up until the half it did not see is the
half that mattered. What separates them is not the verdict; it is **the list of
ids that were in front of it**.

R19 has the same shape. "Do not classify against a remembered copy" is a rule,
and a rule is enforced by whoever remembers it. Written down as a rule it fails
in exactly the way the rest of this lifecycle is built to prevent: silently, in
a session that ends, with a plausible answer left behind.

So a classification carries **provenance**: the spec commit and content hash it
was made against, and every active requirement id that was in scope. An
unreachable spec home yields no hash; the writer refuses to emit a record
without one; the check refuses a record that has none. Classifying from a
remembered copy stops being *forbidden* and becomes *impossible to record*,
which is the only half a script can enforce.

## Where records live

```
.claude/productizer/classifications/<intent-slug>.md
```

One file per classified intent, committed to the repo beside the spec — a
sibling of `rulings/`, and for the same reasons set out in
`references/rulings.md`:

- **Committed, not ticketed.** A record that lives only in a session transcript
  or an issue comment leaves the repo when the tracker is migrated, and the
  audit trail then depends on a vendor nobody in the room controls. The spec
  diff and the provenance record are reviewed by the same people through the
  same gate.
- **Beside the spec, not inside it.** The spec records what is agreed now. A
  provenance record is evidence about one past act. At two hundred intents,
  inlining them buries the requirements they exist to protect.
- **`.claude/` is routinely gitignored.** Run `git check-ignore` on the first
  record path; the bare form must exit non-zero. A store that cannot be
  committed is a local notes folder that looks like an audit trail.

## Ids: keyed by the intent, deliberately unlike rulings

Rulings get their own `D` space because a citation to a ruling has to outlive
the tracker that raised it — a superseded requirement names the ruling that
superseded it, forever.

A provenance record is not cited by anything. Nothing in the spec points at it;
it is evidence read by a check, not a handle read by a human. So the argument
that bought rulings an allocator does not apply, and the cost of a second
monotonic counter — one more thing to get wrong, one more thing to keep in step
across a split spec — is not worth paying.

**A record is named for its intent.** That buys the R6 uniqueness property for
free: exactly one classification per intent is held at the filename, so a
second classification of the same intent is a collision the writer refuses
rather than a second file nobody notices.

The filename is the intent identifier with every character outside
`A-Za-z0-9._-` replaced by `-`, then trimmed. `#123` becomes `123.md`;
`PROJ-123` becomes `PROJ-123.md`.

**The filename is a convenience, not the contract.** A record filed under any
other name walks straight past the uniqueness check, so the check re-derives
the expected filename from the record's own `Intent:` field and flags a
mismatch, and separately groups every record by `Intent:` to catch duplicates
that the filename could never see. Two mechanisms, because the cheap one is
defeated by a rename.

## The record

```markdown
# Classification — PROJ-123

Intent: PROJ-123
Classification: extend
Recorded: 2026-08-30
Spec path: .claude/productizer/spec.md
Spec commit: f5bfdae9492c793d5b3af4fb4ad9eab1d24b1ae4
Spec hash: sha256:d12a3a0ed21a58d5776ffebe024615aefd7734a0a1c1fb951208f889d6a6d8b8
In scope count: 25

## Requirement ids in scope

R1
R2
...
```

A header block of `Key: value` lines above the first `##` heading, then one
section listing ids. Same shape as a ruling's header, read the same way, for
the same reason: anything can count these files without parsing prose.

| Field | What it is | Refused when |
|---|---|---|
| `Intent` | the tracker key or identifier, and nothing else about the intent | not id-shaped: letters, digits and `#._/-`, at most 64 characters, no spaces |
| `Classification` | exactly one of `extend`, `refine`, `duplicate`, `contradict` | absent, blank, repeated, or a fifth value |
| `Recorded` | UTC date the record was written, `YYYY-MM-DD` | not that shape — staleness is derived from it |
| `Spec path` | spec location relative to the repo root | absent or blank |
| `Spec commit` | 40-character lowercase hex sha of the commit the spec was read at | absent, blank, or a placeholder |
| `Spec hash` | `sha256:` and 64 lowercase hex of the spec **as read** | absent, blank, or a placeholder |
| `In scope count` | how many ids the section below lists | disagreeing with the list it counts |

The header is scoped to the run of `Key: value` lines around the
`Classification:` line, above the first `##` heading. Scoping it that way is
what makes a `Classification:` written inside a body paragraph not a
classification — the same rule `check-ruling-requested.sh` applies to a
ruling's `Status`.

### The intent's id, never its words

An intent is text a stranger can write — on a public repo anyone can open an
issue. This store is committed, is read by a check whose output lands in
`checks-result.json`, and is read back into a model's context. So the record
holds the intent's **identifier** and nothing else from it, the identifier is
validated against a closed shape before it is written, and every finding the
check emits names a file, a line and a class of problem. The only value ever
echoed back is a classification word, checked against the closed set of four
first.

### The one place an em dash is refused

The constitution's first principle is that a value which could not be measured
is never rendered as zero: unknown is an em dash. Every other store in this
lifecycle requires an em dash for an unset field, because a blank value and a
missing line are indistinguishable to anything counting them.

`Spec commit` and `Spec hash` are the exception, and R19 is the reason. An
unreachable spec home yields no commit and no hash — and the correct response to
that is **no record at all**, not a record with the gap honestly written in. A
record admitting it does not know what it read is not a more truthful record; it
is a classification that should never have happened, wearing the paperwork of
one that did. So an em dash in either field is a finding, and so is `unknown`,
`n/a`, `TODO`, a bare `sha256:` and every other way of writing *I have no hash*.

The distinction is worth stating plainly, because it looks like an exception to
the principle and is not: the principle governs how you **report** an unmeasured
value. It does not license **producing** an artifact whose entire purpose was
the measurement you failed to take.

## Writing one

```
scripts/record-classification.sh --intent PROJ-123 --classification extend
```

At the moment intake settles on one of the four, before the delta is written.
**Stage 2 names this as a step of the stage**, not as a nicety at the end of
it, because a script that exists and is never invoked is written rather than
wired — and this one spent its whole first life that way, with a check quietly
passing over the empty store it left behind.
The writer reads the spec, hashes it, computes the active id set with the same
parser the check uses, and moves a fully-built file into place in one step — so
an interrupted run leaves the store exactly as it found it.

**Every reason the spec home might not be readable ends the same way: exit 2,
nothing written, no partial file.**

| What is wrong | Why it is a refusal and not a record |
|---|---|
| the spec file is missing | there is nothing to hash, and nothing to classify against |
| the spec cannot be read | unreachable is not empty, and neither is a licence to classify from memory |
| no git work tree | no commit to cite, so nothing could ever verify the record |
| the spec is untracked at HEAD | `git show` has nothing to hash, so the citation would be fiction |
| the work tree spec differs from HEAD | the check rehashes the spec **at the cited commit**, so a record made against uncommitted edits could never be verified against anything — and an unfalsifiable record is the same as no record |

That last row is the one people push back on. It means: **commit the spec, then
classify against it.** In the normal intake flow this costs nothing, because
the spec is edited *after* the classification, not before.

A record already existing for the intent is a different answer again — exit 1,
not 2. Nothing is wrong and nothing could not be measured; the R6 invariant is
holding, and the writer says so.

## Reading the store — the counting contract

The state is a directory of files with a fixed header, so anything can count it
without parsing the spec. The contract for anything that does:

- **No file means no count, not zero.** Three states, three different
  sentences, and only the third is a zero:

  | State | What it means | Reported as |
  |---|---|---|
  | no `classifications/` directory | this repo has recorded no classification | a note, and no count |
  | a directory that cannot be listed | UNKNOWN. Exit 2 | refused, never folded into "none" |
  | a directory holding no records | a measured zero | said so, in those words |

  Reporting the first or second as `0 records` states "nothing is missing" as a
  fact, which is the one wrong answer that looks healthy. A directory nobody can
  open is exactly where a truncated classification hides.

- **An unmatched glob is not an empty directory.** In `bash` it reaches the
  command as its own literal text. Distinguish the cases with an explicit
  directory test, never by trusting a count.

- **A run with no records must not exit clean.** Through the check's 1.0 it
  did — it said in its own pass line that it had asserted nothing, and exited
  `0` anyway. The sentence was true and the exit code was not: a clean exit
  from a blocking check is read as *the requirement holds here*, and this one
  had swept an empty set every run since the day it was written, because Stage
  2 never called the writer. Written, and never wired.

  Failing outright is the other wrong answer — a repo scaffolded this morning
  has classified nothing and violated nothing. So the empty store is judged
  against evidence held **outside** the store, and the two cases are two
  sentences and two exit codes:

  | Empty store, and… | Verdict |
  |---|---|
  | something corroborates that this repo classified | a **finding**, exit 1 |
  | nothing does | **unmeasured**, exit 2 — never a pass |

- **Emit ids, never text.** Same rule the session-start hook applies to the
  spec, for the same reason.

- **The store is only as good as the writer.** A classification made in a
  session with no record written is a classification nothing can see. This is
  the same limitation rulings carry, and it is why the record is written at the
  moment of classification rather than at the end of the stage.

## What the check asserts

```
scripts/check-classification-provenance.sh
```

Per record:

1. **Exactly one classification, from the four.** Not zero — a record with no
   `Classification` line records nothing. Not two — a second line makes which
   value is authoritative undefined. Not a fifth value, which nothing
   downstream knows how to act on.
2. **Exactly one record per intent**, checked at the content as well as the
   filename.
3. **The hash matches the spec at the recorded commit.** The spec is refetched
   with `git show <commit>:<path>` and rehashed. This is the R19 assertion: a
   classification made from a remembered copy either carries no hash — refused
   by 4 — or carries the hash of the remembered copy, which does not match the
   spec at the commit it stamped.
4. **No record without a hash**, per the em-dash rule above.
5. **Every requirement active in that spec was in scope.** The active ids are
   recomputed from the refetched spec and compared with the record's list. A
   missing id is the truncation case. An id in the list the spec does not have
   active is the same failure inverted.

Once for the store as a whole:

6. **The store is not an empty one in a repo that demonstrably classified.**
   The corroborating source is **the backlog** — `backlog.md`, scanned for the
   classification word itself, the backticked `extend`, `refine`, `duplicate`
   or `contradict` following the word `classified`. Stage 1 already writes that
   line onto an item when it goes through intake, so the evidence is committed
   in the repo, readable offline, in a file the lifecycle maintains anyway. It
   names the classification rather than an effect of one, and it is written for
   all four outcomes.

   The spec's `## Change log` was considered and **rejected**: it records
   *merges*, not classifications. Duplicate and contradict merge nothing by
   definition, so a lifecycle refusing what it should refuse leaves an empty
   change log — evidence that vanishes exactly when the requirement is working
   hardest is not evidence. Its rows also cover spec edits that were never an
   arriving intent at all, so reading a row as *an intent was classified*
   asserts something the row does not say.

   Tracker labels were considered and **rejected**: they live behind a network
   and a token, so a check that reads them reports unmeasured every time it
   runs offline, and they leave with the tracker at the next migration — the
   same reason this store is committed beside the spec rather than kept in
   issue comments.

   Known limitation, and the direction of its error: the pattern requires the
   backticked spelling, so a backlog saying *classified as extend* in running
   prose is not matched. A missed match yields exit 2, unmeasured, and never a
   pass. The backticks are required deliberately — an unbackticked pattern also
   matches prose about what intake *will* classify, and a corroborator that
   fires on a future-tense sentence manufactures findings.

Every assertion is **counted on its own**, and the check prints how many
records upheld each, how many failed it, and how many did not assert it at all
— a record whose commit cannot be resolved asserts nothing about its hash and
is counted in neither column. One `ok` flag divided at the end is how a check
comes to report a denominator it never measured. Assertions 1, 4 and 5 share
one counter and say so: they are raised inside the shared parser, which does
not label which of the three a finding came from, and a second copy of its
rules in the check is how two parsers come to disagree.

When the hash does not match, or the commit cannot be resolved, **the scope
comparison is not made and is reported as not made**. Comparing the list
against a spec the record does not claim to have read would print a confident
sentence about the wrong file. Unknown is an em dash there, and the caller
already holds a finding or a refusal.

### What it deliberately does not do

- **A record made against an older spec is not a finding.** The normal intake
  flow is classify, then merge the delta, so the spec moves immediately after
  almost every correct record. Anchoring the comparison to the commit the record
  cites is what stops this check going red on every historical record the first
  time a requirement is added. Currency is reported per record as a note, and a
  note is not a verdict.
- **It does not observe the classification being made.** Nothing in a file can.
  It observes the record — which is why the writer refuses to emit one it cannot
  stand behind. The two halves are one mechanism, and the check alone is half of
  it.

### Known limitations, written down rather than discovered later

- The active-id rules are `build-view.sh`'s, reproduced once in
  `classification-record.py` and shared by both halves. A spec written in a
  shape that parser does not recognise yields a smaller active set, and a record
  matching it passes. The mitigation is that one parser serves the writer and
  the check, so they are wrong together and visibly — never in disagreement.
- A record can be hand-written to cite an ancient commit whose spec was
  genuinely small, and it will pass. What the record proves is that its scope
  list matches the spec it names. That the commit named is the right one is
  established by the writer, not by the check.
- Running as a user who can read anything defeats the unreadable-store test, as
  it defeats every such test.

## Exit codes

Both scripts use the repo's three, so no caller has to translate.

| | `record-classification.sh` | `check-classification-provenance.sh` |
|---|---|---|
| `0` | the record was written | clean — and never over an empty store |
| `1` | refused: this intent is already classified | findings, including an empty store in a repo that classified |
| `2` | could not run — bad usage, or NO HASH: an unreachable spec home, an untracked spec, a work tree that disagrees with HEAD | could not run — no work tree, no spec, an unreadable store or record, a recorded commit this clone cannot resolve, or an empty store with nothing corroborating that any classification was ever made |

The ordering rule for the check is `check-spec-home.sh`'s: findings already in
hand are a definite answer, so a run exits 1 even when another record was
unresolvable. Unresolvability only refuses when it could still change the
verdict.
