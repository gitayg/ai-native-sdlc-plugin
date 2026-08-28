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

The second half is a **kanban of what is actually moving**, one card per item,
each sitting in the column of the stage that is *holding* it — not the stage it
will reach next. Columns follow the lifecycle: backlog, intake, build, check,
review, gated. Cards carry what is blocking them, in words.

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
its bullets.

**Stage state is not derived here.** `scripts/stage-status.sh` already reads
every stage off the tree and already keeps `not run`, `unknown` and `n/a` apart;
it is run as a subprocess and its rows are parsed. A second copy of that
reasoning would disagree with the first the day someone edited one of them.

Three things the generator will not do, because each is how a dashboard starts
lying:

- **It never renders an unreadable value as a measured zero.** A tile shows a
  number when a file was read, an em dash when the file does not exist, and a
  `?` when it exists and would not parse — three renderings, each with the
  reason beside it and what its absence costs. `checks-result.json` missing is
  "nothing has been checked"; the same file present and malformed is "unknown",
  never `PASS`.
- **It ships no sample data.** An absent backlog renders as an absent backlog
  and says what that costs; a present but empty one renders as an empty table.
  The only text on the page that is not this repo's own state is the
  traditional-versus-AI-native pair on the Stages panel, which describes the
  lifecycle rather than the repo — and says so, on the page, underneath itself.
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
