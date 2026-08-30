---
name: answer
description: "Find every question this repo is holding open for a person and put them one at a time — contradictions waiting on a ruling, requirements nothing asserts, blocked items, checks that refused. Records each answer in the files. Use when asked what needs a decision, what is waiting on me, what questions are open, or to work through the open questions."
argument-hint: "[R<n> | D<n> | B<n>]"
disable-model-invocation: true
allowed-tools: Bash Read Edit AskUserQuestion
---

# What this repo is waiting on a person for

!`set -e; R="$(git rev-parse --show-toplevel)"; python3 - "$R" <<'PY'
import io, os, re, sys
root = sys.argv[1]
def rd(p):
    f = os.path.join(root, p)
    if not os.path.exists(f): return None
    if not os.path.isfile(f) or not os.access(f, os.R_OK): return False
    return io.open(f, encoding='utf-8', errors='replace').read()

spec = rd('.claude/productizer/spec.md')
q = []
if spec is None:
    print('  no spec at .claude/productizer/spec.md - nothing to ask about')
elif spec is False:
    print('  the spec exists and cannot be read. UNKNOWN, not "no questions".')
else:
    body = spec.split('## Requirements')[-1].split('## Design')[0]
    active, dead = [], set()
    for m in re.finditer(r'^- \*\*(R\d+)\*\* — (.+)$', body, re.M):
        rid, txt = m.group(1), m.group(2)
        tail = body[m.end():m.end() + 240]
        if re.match(r'\s*\n\s+(Superseded by|Withdrawn)', tail):
            dead.add(rid); continue
        active.append((rid, txt))
    acc = spec.split('## Acceptance criteria')[-1].split('## Change log')[0]
    rows = {}
    for l in acc.split('\n'):
        mm = re.match(r'^\| (R\d+) \| (.*?) \|\s*$', l)
        if mm: rows[mm.group(1)] = mm.group(2)
    for rid, txt in active:
        cell = rows.get(rid)
        if cell is None:
            q.append(('%s' % rid, 'no acceptance row at all - the table cannot say whether anything asserts it', txt[:70]))
        elif re.search(r'not yet verified|\*\*Nothing', cell, re.I):
            q.append(('%s' % rid, 'its acceptance row says nothing asserts it yet', txt[:70]))
    con = spec.split('## Areas of concern')[-1].split('## Acceptance criteria')[0]
    for l in con.split('\n'):
        mm = re.match(r'^\|\s*(C\d+)\s*\|(.*)\|\s*$', l)
        if mm and 'resolved' not in mm.group(2).lower() and 'open' in mm.group(2).lower():
            q.append((mm.group(1), 'an open concern - nothing merges that depends on it until it is ruled', ''))

rd_dir = os.path.join(root, '.claude/productizer/rulings')
if not os.path.exists(rd_dir):
    pass
elif not os.access(rd_dir, os.R_OK | os.X_OK):
    print('  the rulings directory cannot be listed. Pending rulings UNKNOWN, not zero.')
else:
    for fn in sorted(os.listdir(rd_dir)):
        if not fn.startswith('D') or not fn.endswith('.md'): continue
        t = rd('.claude/productizer/rulings/' + fn)
        if t and re.search(r'^Status: pending$', t, re.M):
            q.append((fn.split('-')[0], 'a contradiction waiting on your ruling - nothing merges until it is decided', ''))

bk = rd('.claude/productizer/backlog.md')
if bk:
    for l in bk.split('\n'):
        c = [x.strip() for x in re.split(r'(?<!\\)\|', l.strip().strip('|'))] if l.startswith('| B') else []
        if len(c) >= 6 and c[2].strip('`').lower() == 'blocked':
            q.append((c[0], 'blocked - it names what it is waiting on', c[1][:70]))

if q:
    for i, (k, why, extra) in enumerate(q, 1):
        print('  %-5s %s' % (k, why))
        if extra: print('        %s' % extra)
    print('')
print('  %d open question(s)' % len(q))
PY`

## How to put them

**One at a time.** Ask, take the answer, record it, then ask the next. A batch of
questions gets a batch of half-answers, and the one that mattered is answered
worst.

**Give real options, and say which you would pick and why.** A question with no
options asks the person to design the answer as well as choose it. If two
readings would produce materially different work, that is a question worth
asking; if one reading is obviously right, make the call and say you made it.

**Bring what you already found.** Before asking about `R7`, read what asserts it
today and say so. Half these questions dissolve once someone sees the current
state, and the ones that survive get a better answer for it.

**Record the answer where it lives, not in the conversation:**

- a requirement's evidence → its acceptance-criteria row
- a contradiction → the `D` ruling file, and the `C` row that cites it
- a backlog decision → the item's Notes
- anything that changes what the product does → an intent, through intake

**Write what will count, not that it is done.** A decision about what would
prove a requirement is not a measurement of it. Say plainly that it is not built
yet — the table answers "do the tests assert this" as a fact, and a row that
overstates makes the gap invisible instead of countable.

**A question you cannot answer is still progress.** If it needs a person and
they are not sure, record the question and what is blocking it rather than
inventing a resolution. An open question written down outlives the conversation;
one resolved by guessing does not.

If the list above is empty, say so plainly — and say it is empty *as measured
now*, not that the repo has nothing outstanding.
