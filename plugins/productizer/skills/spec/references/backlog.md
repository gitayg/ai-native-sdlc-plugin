# The backlog — the queue in front of the lifecycle

Stage 1 assumes an intent exists. In practice the intent arrives weeks after
somebody first wanted the thing, and in between it lives in a head, a Slack
thread or a ticket nobody has read since. The backlog is where that waiting
happens on purpose.

Template: `templates/backlog.md`. Lives at `.claude/sdlc/backlog.md`.

## It is not the spec, and the distinction is the whole point

The spec holds what the product has **agreed** to do. The backlog holds what
somebody **wants**. Nothing in it has been classified, so nothing in it is
binding, and an item can be refused at intake for contradicting a requirement
agreed two years ago.

That refusal is the system working. A backlog whose items are treated as
commitments is a second spec written by whoever shouts loudest, and it will
contradict the first one silently — which is precisely the failure the
contradiction halt exists to prevent, arriving through the back door.

So: **`B` ids never merge into `R` ids.** An item that becomes a requirement
keeps its `B` id in the intent and the requirement takes a fresh `R`. The two
spaces stay separate because they answer different questions — "who wanted
this, when" against "what does the system do".

## Order is the priority, and there is no priority field

The file's order is the ranking. No `priority: high` column, no P1/P2/P3.

Two representations of one ordering disagree the first time someone edits one
and not the other, and then nobody can say which is the real queue. A single
ordered list cannot drift from itself.

This also makes reordering cheap, which matters more than it sounds: a priority
scheme with ceremony around it does not get updated, and a backlog nobody
reorders is a list of everything ever suggested, sorted by date. Moving an item
changes nothing that was agreed, so it needs no approval and no record.

## Statuses, and the one that lies

Five: `todo`, `long-term`, `in-progress`, `blocked`, `done`.

`long-term` earns its place by being honest. Without it, everything anyone might
ever want sits in `todo`, the list runs to two hundred items, and people stop
reading it — at which point the backlog has stopped working while still looking
maintained. `long-term` says *wanted, deliberately not now*, and it wants a
reason beside it.

`done` is the one that lies if you let it. It means **the item left this queue**
— merged as a requirement, ruled a duplicate, or refused — not that anything
shipped. What shipped is a question for the spec and the release history. A
backlog that answers it too starts competing with the spec, and the spec is the
one under version control with an id space and a contradiction check.

## Jira: read the status, never write it

An item may carry a Jira key, and when it does, **Jira owns its status**.

- The local vocabulary stops applying. The row shows what Jira last said.
- The mapping between Jira's workflow states and these five is declared once in
  `.claude/sdlc.json` under `jira.status_map`, not guessed per item.
- **Nothing is written back.** This file does not move tickets. A markdown table
  arguing with a Jira workflow, a board filter and three automation rules loses,
  and it loses silently — the write appears to succeed and a rule reverts it an
  hour later. Move the ticket in Jira.
- **The key is the join, never the title.** Titles drift on both sides; keys do
  not. This is the same rule the spec follows for requirement ids and for the
  same reason.
- **Unreachable Jira is a stated fact, not a stale number.** Show
  `unknown (Jira unreachable <when>)`. A status shown without qualification is
  read as current, and a stale "In Progress" is worse than no status at all
  because someone will plan around it.

See `references/integrations.md` for the binding, and `templates/jira-intent.md`
for how an intent joins its ticket once work starts.

## Why the published view may reorder, when no other view may

Every other view in this lifecycle is strictly read-only, and
`references/views.md` is emphatic about it: *nothing is ever read back out of a
view into the spec*, because a view that becomes editable stops the committed
chain being the audit trail.

The backlog view is the one place that rule can relax, and only because of what
the backlog is. Reordering changes **nothing that was agreed** — it does not
touch a requirement, a ruling or a principle, and it produces no claim about the
product. The audit trail is untouched by moving `B7` above `B4`.

Even so, the view does not write the file. It cannot: a published page has no
filesystem. What it does is let you drag items into the order you want and then
hand you the reordered table to paste, or a prompt that applies it. **The file
stays the source of truth and the only edit surface** — the drag is a way of
composing an edit, not a way of skipping one.

Adding an item is the same: the view can compose one, and the file records it.

## What does not belong in it

- **Requirements.** Agreed behaviour has an `R` id and lives in the spec.
- **Bugs against agreed behaviour.** That is drift or an incident, and it enters
  at Stage 1 against the requirement it violates (`references/drift.md`).
- **Anything already specified.** Intake will rule it a duplicate — the right
  answer, reached expensively. Check the spec first.
