---
name: backlog
description: "Show the backlog — the queue in front of the lifecycle — and add to it, reorder it, or start work on an item. Everything here is a want, not a requirement: nothing in the backlog has been agreed. Use when asked what is queued, what is next, to add something to the backlog, to reprioritise, or to pick up an item."
argument-hint: "[add <what is wanted> | start <B-id>]"
disable-model-invocation: true
allowed-tools: Bash Read Edit
---

# The backlog

!`set -e; R="$(git rev-parse --show-toplevel)"; F="$R/.claude/productizer/backlog.md"; if [ ! -e "$F" ]; then echo "No backlog at .claude/productizer/backlog.md."; echo "That is no queue, not an empty one: nothing records that something was wanted before it was agreed."; exit 0; fi; if [ ! -r "$F" ]; then echo "backlog.md exists and cannot be read. Unknown, not empty."; exit 0; fi; python3 - "$F" <<'PY'
import io, re, sys
rows = []
for n, l in enumerate(io.open(sys.argv[1], encoding='utf-8'), 1):
    if re.match(r'^\| B\d+ \|', l):
        c = [x.strip() for x in re.split(r'(?<!\\)\|', l.strip().strip('|'))]
        if len(c) < 6:
            print('  MALFORMED row at line %d: %d cells, expected 6' % (n, len(c)))
            continue
        rows.append(c)
live = [c for c in rows if c[2].strip('`').lower() != 'done']
done = len(rows) - len(live)
order = {'in-progress': 0, 'blocked': 1, 'todo': 2, 'long-term': 3}
live.sort(key=lambda c: order.get(c[2].strip('`').lower(), 9))
for c in live:
    print('  %-5s %-13s %s' % (c[0], c[2].strip('`'), c[1][:66]))
print('')
print('  %d in the queue, %d done and not listed. Next id: %s'
      % (len(live), done,
         (re.search(r'Next backlog id\s*\n?:\s*`(B\d+)`',
                    io.open(sys.argv[1], encoding='utf-8').read()) or
          type('x', (), {'group': lambda s, i: '?'})()).group(1)))
PY`

## What this is

**Nothing here is agreed.** These are wants. An item leaves this file by becoming
an intent at Stage 1, and what happens to it then is decided by intake, not by
whoever wrote it down.

**Order is the priority.** There is no priority field, because two orderings
disagree the moment someone edits one and not the other.

**`done` does not mean built.** It means the item left the queue — merged as a
requirement, ruled a duplicate, or refused. The spec records which. Done rows
are hidden above; the count is stated so a shorter list does not read as a
shorter queue.

## Acting on it

- **Adding:** give it the next `B` id, status `todo`, and put it where the
  person says in the order. Do not classify it — that is intake's job, and an
  item classified at the moment it is written down has skipped the only step
  that checks it against what is already agreed.
- **Starting work:** that is Stage 1. Classify it against the whole living spec
  *including the constitution* before anything is planned, set it
  `in-progress`, and record the classification and what it was checked against
  in its Notes. If it contradicts an agreed requirement, stop before changing
  any file, say which requirement, and merge nothing.
- **Reordering:** an ordinary edit needing no ceremony. Nothing here is agreed,
  so nothing is being changed by moving it.
- **Editing the table:** a cell containing a literal `|` must be escaped `\|`,
  or the row tears into extra columns and every column after it shifts. That
  has happened here and rendered a note as a single backtick.
