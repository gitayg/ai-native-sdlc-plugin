---
name: help
description: "List every Productizer command with what it does and when to reach for it, read from the installed plugin rather than from memory. Use when asked what productizer can do, what the commands are, how to use it, where to start, or which command to use for something."
disable-model-invocation: true
allowed-tools: Bash Read
---

# Productizer — what you can type

!`set -e; D="${CLAUDE_PLUGIN_ROOT}/skills"; [ -d "$D" ] || D="$(git rev-parse --show-toplevel 2>/dev/null)/plugins/productizer/skills"; if [ ! -d "$D" ]; then echo "cannot find the plugin's skills directory - this list would be from memory, and memory is what it exists to avoid."; exit 0; fi; V="$(basename "$(dirname "$D")" 2>/dev/null)"; python3 - "$D" <<'PY'
import io, os, re, sys
d = sys.argv[1]
rows = []
for name in sorted(os.listdir(d)):
    f = os.path.join(d, name, 'SKILL.md')
    if not os.path.isfile(f):
        continue
    try:
        head = io.open(f, encoding='utf-8', errors='replace').read(4000)
    except (IOError, OSError):
        rows.append((name, '(could not be read - present, but unreadable)', '')); continue
    nm = re.search(r'^name:\s*(\S+)\s*$', head, re.M)
    ds = re.search(r'^description:\s*"(.*?)"\s*$', head, re.M | re.S)
    hint = re.search(r'^argument-hint:\s*"(.*?)"\s*$', head, re.M)
    auto = not re.search(r'^disable-model-invocation:\s*true\s*$', head, re.M)
    first = (ds.group(1).split('. ')[0] + '.') if ds else '(no description)'
    rows.append(((nm.group(1) if nm else name), first, hint.group(1) if hint else '', auto))
if not rows:
    print('  no commands found in %s' % d)
for r in rows:
    nm, first, hint = r[0], r[1], r[2]
    auto = r[3] if len(r) > 3 else False
    print('  /productizer:%-10s %s%s' % (nm, hint, '   [auto]' if auto else ''))
    print('      %s' % first)
print('')
print('  %d command(s), read from %s' % (len(rows), d))
PY`

## Reading that

`[auto]` means Claude may invoke it on its own from what you are doing.
Everything else you type, deliberately — those either publish something, run
every declared tool in the repo, edit the queue, or start asking you questions,
and none of that should happen because a sentence sounded like a request.

**The bare form works too** — `/dashboard`, `/check` — unless another plugin has
claimed the name.

## Where to start

- **A repo that has never used this** → `import`. It surveys read-only and
  refuses to draft from a repo that cannot evidence its own behaviour.
- **A repo already under a spec** → `answer` for what is waiting on a person,
  `dashboard` to see the whole state, `check` before you commit.
- **Something you want built** → `backlog` to queue it, or just describe it and
  the lifecycle skill picks it up.

## What this list is not

It is read from the **installed** plugin at run time, so it cannot list a
command that does not exist or miss one that does. It can still be behind the
source checkout: installing copies a snapshot, and edits there do not reach it
until `claude plugin update productizer`.

A skill whose file cannot be read is listed as unreadable rather than skipped.
A command missing from a list is indistinguishable from one that was never
installed, and only one of those is worth knowing about.
