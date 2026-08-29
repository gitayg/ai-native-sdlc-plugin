# Views — showing the lifecycle as an artifact

Files are the source of truth and the only edit surface. Views are read-only
pictures of those files, published as artifacts when someone wants to *look* at
the lifecycle rather than change it.

Never invert that. A view is regenerated from the files every time; it never
holds state, never becomes the thing people edit, and nothing is ever read back
out of a published view into the spec. The moment a view is authoritative, the
committed chain stops being the audit trail — which is the only thing this
lifecycle is selling.

## When to publish one, and when not to

| Ask | Response |
|---|---|
| "what stage is this in", "is X specified" | answer in the session — one line, no artifact |
| "show me the pipeline", "let me see the spec" | publish a view |
| "what's in flight across everything" | publish the fleet view |
| anything that changes something | edit the file, then offer the view |

Publishing costs a round trip, so do not publish for a question a sentence
answers. Do publish when the answer is a table, a trend, or more than about six
rows of anything — that is when reading it in the terminal starts costing more
than the artifact does.

Say the URL and one line about what it shows. Do not explain that it is
read-only unless asked; it is obvious from the content.

## The four views

**Overview** — one product at a glance, and the first thing a view should open
on. Two halves: counted state, and what is moving.

The counts come from the files, never from anything the view stores — the spec
for requirement totals and how many are superseded or withdrawn, the acceptance
criteria table for how many active requirements still have no test,
`backlog.md` for the queue, `checks-result.json` for the last check run, the git
log for releases and when the spec last changed. A number a view keeps for
itself is a number that goes stale without anyone noticing.

**Colour means "this needs you", never decoration.** Healthy is the *absence*
of colour, not a green of its own. A board where every tile is coloured has four
things shouting, which is the same as none — the eye has nowhere to land and the
reader learns to scan past all of it. Two levels are enough: one for *stop*, one
for *soon*. Everything else is neutral, and the heading says how many need
attention so the count is legible before any tile is read.

**Show the uncomfortable ones at the same size as the comfortable ones.** Open
contradictions, active requirements with no test, the last check run if it
refused, drift findings. A dashboard where the good numbers are large and the
bad ones are a footnote is a dashboard people learn to feel reassured by.

**A half-finished import has to look half-finished.** Stage 0c drafts
requirements out of code that already runs. Every one lands `inferred` and
unconfirmed, carries the file or test it was read from, and cannot trigger the
Stage 2 contradiction halt until a person promotes it — which is a commit, not a
click. Counted nowhere, a spec holding thirty unpromoted sentences and a spec
holding none draw identically, and an import that has barely started reads as
finished. So the overview carries **`N inferred, awaiting promotion`** against
the size of the spec, with the promotions and import rejections recorded so far
beside it, and the queue itself underneath: one row per requirement with the
citation it was drafted from, so the list can be worked from the page instead of
grepped out of the spec. Where the marker says `Inferred (weak evidence)` the
row says so too: a sentence cited from a doc or a CI job name is a weaker claim
than one cited from a route and the test that exercises it, and a queue that
flattened the two would be handing back the distinction the marker exists to
carry.

That tile is amber, never red. An unpromoted requirement blocks nothing — which
is the whole point of the status, and also why nobody notices it — so it belongs
with *soon*, beside requirements with no test, rather than with *stop* beside an
open contradiction.

**The queue has four empty states and they are not interchangeable**, because
each one leads somewhere different. No spec at all is *cannot determine*, drawn
as an em dash: a page that could not read a file does not know how long the
queue is. A spec that is there and could not be opened is *unknown*, a `?` —
same ignorance, different cause, and the cause is the actionable part. A spec
carrying no import markers at all is *not applicable*: nothing was ever inferred
here, so there is no queue to be part-way through. And a spec whose markers have
all gone, with promotions recorded against ids the import drafted, is a
**measured zero** — somebody read those sentences and said so. Only the last of
the four is a zero, and drawing any of the other three as one is exactly the
failure the inferred status exists to prevent, committed on the tile that
reports it.

**What the number does not tell you goes under it.** Nothing in the queue has
been judged true: a citation says where a sentence was read from, not that the
sentence is right, and a citation that no longer resolves still counts as one.
Promotion deletes the marker line outright, so the promoted figure is only what
the decision record records — a row naming an id the spec has, reading as a
confirmation, and saying the id came from the import. A promotion written down
any other way is invisible to the page and is not counted, and the page says so
rather than inventing a denominator to make the fraction look finished. The
queued ids also appear under *requirements with no test*, because the acceptance
table is for agreed requirements and an inferred one is given no row on purpose.

**Board** — a **kanban of what is actually moving**, one card per item, each
sitting in the column of the stage that is *holding* it — not the stage it will
reach next. Columns follow the lifecycle: backlog, intake, build, check, review,
gated. Cards carry what is blocking them, in words.

It is its own tab rather than the second half of the dashboard, because the two
answer different questions: the dashboard answers *how is this repo doing*, in
numbers that are true whether or not anything is moving, and the board answers
*what is moving right now*. The tab carries the number of cards in flight, and
carries an em dash instead when a column could not be counted — an unreadable
`checks-result.json` leaves the check column drawing a confident zero over a
number nobody read, so the count says unknown and the panel says why.

The promotion queue stays on the dashboard. It is read from `spec.md`, not from
what is in flight, and a requirement waiting to be confirmed is not a card
moving through a stage.

That last column is the point of the whole board. **A full `Gated` column means
work is finished and waiting on a person**, which is the only queue on the board
that no amount of agent time will drain. It should be the first thing anyone
looks at, and it is worth keeping it last so the eye lands there.

An empty board is drawn as an empty board. A lifecycle with nothing in flight is
a real answer, and inventing motion to fill columns is the same lie as a scanner
reporting a grade for files it never opened.

**Fleet** — every bound repo: product, current stage, open intents, control band
state, eval pass rate, last spec change. Sorted by attention needed, not
alphabetically: breaches first, then contradictions waiting on a ruling, then
cold starts, then healthy. The point of this view is that a person can stop
reading after the first two rows.

**Spec** — one product's living spec: requirement ids with their EARS text,
status (active / superseded with the forward pointer / withdrawn), grouped by
pattern, with acceptance-criteria coverage and unmapped requirements marked.
Show superseded and withdrawn requirements — dimmed, struck through, never
hidden. A spec that shows only what is currently true is not a record.

**Intake** — the classification of one intent against the spec: which of extend,
refine, duplicate or contradict, and the delta it would produce. For a
contradiction, both requirements quoted in full with the conflict stated in one
sentence, and an explicit line saying nothing has been merged. The ruling still
happens in the session — the view shows what is being ruled on.

**Backlog** — the queue in front of the lifecycle, in priority order, with each
item's status and its Jira state where it has a key
(`references/backlog.md`). It is the one view that may be **rearranged**, and
only because reordering it changes nothing that was agreed: no requirement, no
ruling, no principle, and no claim about the product. Even then it does not
write the file — a published page has no filesystem. Dragging composes the
reordered table and hands it back to paste, so `.claude/productizer/backlog.md` stays
the source of truth and the only edit surface. Each row carries its own
`start work`, naming that item rather than the list — and every action in a view
has to be **wired to the copy mechanism the rest of the page uses**, not styled
to look like it. A button that reports "copied" while the clipboard is untouched
is worse than no button, because the failure is silent and the reader finds out
later. Jira keys render as links built from `jira.site`, never as plain text.

A table's header and its rows are laid out from **one** column template used
twice, not two that happen to agree. Two templates drift the first time someone
edits one and not the other — the same failure the backlog avoids by having no
priority field — and a header sitting a column off its data is read as data. Sorting by status is a way
of **looking**: while it is grouped, the visible order is not the ranking, so
dragging is disabled and the copy-back withdrawn — a priority order silently
rewritten by a sort is worse than a stale one. A Jira status that could not be
read is drawn as unreadable, never as its last known value.

**Band** — one metric's history against its centreline and sigma limits, the
current point, and which rule fired if any. Cold start is drawn as cold start,
never as a flat healthy line.

## Gathering the data

Read files and `gh`; never invent a number to fill a column. Every field comes
from one of:

```bash
scripts/detect-context.sh                       # binding, stage, runner, overrides
cat .claude/productizer/spec.md                        # requirements and statuses
python3 ops/ci-failure-rate.py                  # band state, centreline, limits
tail -n 30 evals/history.jsonl                  # eval trend
gh issue list --label sdlc:intent --state open  # this repo's intents
gh search issues --owner OWNER --label sdlc:intent --state open --limit 100
```

A field you could not read renders as an em dash with a reason on hover or
beneath it — `no workflows`, `spec not started`, `not bound`. Never render a
missing value as a zero, a full bar, or a healthy colour. Half the value of the
fleet view is seeing which repos are not measured at all.

## Building the page

Start from `templates/view.html` — it carries the tokens and the primitives, so
views stay recognisably one family rather than four different dashboards.

- Dark only, self-contained, no external assets. Inline everything; the artifact
  sandbox blocks outside requests apart from Google Fonts.
- Semantic colour is separate from the accent: green within band, amber
  unmapped or degraded, red breach or contradiction. The accent is for
  interactive and identifying elements only, never for status.
- Monospace and tabular numerals for ids, paths, counts and percentages;
  requirement ids read as `R42` everywhere, never `#42` or `R-42`.
- Wide tables scroll inside their own container; the page body never scrolls
  sideways.
- Republish the same file path to keep one URL per view per product rather than
  accumulating a new artifact every time someone looks.

## Generating the pipeline view

The overview does not get hand-written. `scripts/build-view.sh` reads the repo
and emits the whole page, so the sentence at the top of this file — a view is
regenerated from the files every time — is implemented rather than asserted. A
hand-maintained dashboard cannot be wrong, which is the same as saying it cannot
be right.

```bash
scripts/build-view.sh                                  # cwd, to .claude/productizer/pipeline.html
scripts/build-view.sh ../orders-api --out /tmp/v.html  # another repo, another path
```

Bash and python3 only; no network, no dependencies. It reads and writes exactly
one file, and running it twice on an unchanged repo produces a byte-identical
one — the only date on the page is HEAD's, never today's, so nothing moves
because a clock did.

Every panel is read at generation time: `.claude/productizer/config.json` for the product name
and the Jira site links are built from, `spec.md` for requirement counts,
contradictions and acceptance rows, `backlog.md` for the queue with its columns
mapped from that table's own header, `constitution.md` for ratified principles,
`checks-result.json` for Stage 5, and `git log` for releases — a release being a
commit whose subject carries a version, with that commit's own message body as
its bullets. The import promotion queue is read from `spec.md` too — from the
literal markers `templates/import.md` mandates, `Inferred from … Unconfirmed.`
with its `Inferred (weak evidence) from …` tier and `Withdrawn. Rejected at
import:`, and from the decision record, which is the only place the promotion
procedure writes a ratification down. Whether a file exists is asked of the
filesystem separately from whether it could be read, so "there is no spec" is
never printed over a spec that is sitting right there.

**Stage state is not derived here.** `scripts/stage-status.sh` already reads
every stage off the tree and already keeps `not run`, `unknown` and `n/a` apart;
it is run as a subprocess and its rows are parsed. A second copy of that
reasoning would disagree with the first the day someone edited one of them.

Four things the generator will not do, because each is how a dashboard starts
lying:

- **It never renders an unreadable value as a measured zero.** A tile shows a
  number when a file was read, an em dash when the file does not exist, a `?`
  when it exists and could not be read or parsed, and `n/a` when it was read and
  the question does not apply here — four renderings, each with the reason
  beside it and what its absence costs. `checks-result.json` missing is "nothing
  has been checked"; the same file present and malformed is "unknown", never
  `PASS`. A spec with no requirement awaiting promotion is `n/a` when the import
  never ran and a measured `0` when every drafted sentence has been ratified,
  because those are two different things to do next.
- **It never asserts a capability it did not read.** The untagged-versions
  banner used to end "push the tags so CI builds the releases". Nothing had
  checked whether the repo has any CI, and in a repo with no workflows the
  sentence was simply false — a maintainer acted on it. The banner now reads
  `.github/workflows/` off the tracked-file list: with a workflow that names a
  tag push in its trigger block it says which one runs, with workflows that do
  not it says so, and with none it drops the claim entirely and keeps only the
  part that is true regardless — an untagged version has no release page. Only
  the trigger block counts, never a `tags:` key under a step's `with:`, which is
  an argument to an action rather than a trigger. If the file list could not be
  read, that is unknown, and an unknown earns no claim at all. The rule about
  not drawing an unknown as a zero is about sentences too, not only numbers.
- **It ships no sample data.** An absent backlog renders as an absent backlog
  and says what that costs; a present but empty one renders as an empty table.
  The only text on the page that is not this repo's own state is the
  traditional-versus-AI-native pair on the Stages panel, which describes the
  lifecycle rather than the repo — and says so, on the page, underneath itself.
**Setup is a checklist, not a tab.** The five once-per-repo steps sit at the top
of the page, in the banner region above the tab bar, for exactly as long as one
of them still needs a person — and then the whole block is gone, not left as an
empty panel behind a tab reading `n/n`. The page exists to show what needs a
person, and a finished setup needs nobody. An unfinished one gates everything
under it, which is not a thing to hide behind the seventh tab.

**The gate is what needs a person, not how many ticks there are.** `ok` needs
nobody. `n/a` needs nobody by definition. `unknown` needs nobody either: `0b` is
always unknown because scheduled tasks live outside the tree, so no work the
reader does will ever flip it from this page. Counting ticks instead would mean
`0b` and `0c` could never both tick and the block could never leave — a
checklist pinned to every page forever, which is worse than the tab it replaced.
Only a genuine `—` holds it open, and the header says which of the others will
never tick so nobody goes hunting for them.

While it is up it renders whole, settled items included, each with its own
marker and its own copy-prompt — a filtered view would leave the reader looking
for ticks that are not coming. **Four states, four renderings**, the same
vocabulary the stat tiles use: a tick is done, `n/a` was read and does not apply
to this repo, `?` was read and could not be determined, `—` has not run. `n/a`
and `—` are the pair most easily collapsed, and collapsing them reports an
inapplicable step as an unperformed one — which is the failure the rest of this
page exists to prevent, committed inside the page.

- **It colours only what needs you.** Banner level follows `stage-status.sh`'s
  own ranking: `blocked` is red, `waiting`/`unknown`/`not run` are amber, and
  everything else has no colour at all. The heading count and the banner list
  name the same set of things, so a red banner can never sit above a heading
  that says nothing is waiting.

`templates/view.html` stays the shared shell — tokens, primitives and the
interaction code — with three substitution points: `@@TITLE@@`, `@@BODY@@` and
`@@DATA@@`. Editing the template changes every generated view; editing the
generator changes what is put into it. Both tables on the page lay their header
and their rows out from one grid template used twice, and where a narrow
viewport collapses the row, the header is hidden rather than left sitting a
column off its data.
