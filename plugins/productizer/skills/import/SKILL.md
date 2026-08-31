---
name: import
description: "Onboard a repository that already exists — Stage 0c. Surveys the code read-only for what it can actually evidence, then drafts requirements from that evidence, every one marked inferred and unconfirmed until a person confirms it. Use when adopting the lifecycle in an existing project, bringing a legacy repo under a spec, importing a codebase, or asking what this repo already does."
argument-hint: "[repo-path]"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit
---

# Stage 0c — importing a repo that already exists

!`set -e; T="${1:-}"; R="$(cd "${T:-.}" 2>/dev/null && pwd)" || { echo "no such path: $T"; exit 0; }; S="${CLAUDE_PLUGIN_ROOT}/skills/spec/scripts/import-survey.sh"; [ -r "$S" ] || S="$(git rev-parse --show-toplevel 2>/dev/null)/plugins/productizer/skills/spec/scripts/import-survey.sh"; if [ ! -r "$S" ]; then echo "import-survey.sh not found. No survey was run - which is not the same as a repo with nothing in it."; exit 0; fi; echo "surveying: $R"; echo; bash "$S" "$R" 2>&1 | head -160; echo; echo "(survey truncated at 160 lines for reading; re-run the script directly for the whole report)"`

## Read the Verdict first

The survey ends with a verdict on whether there is enough evidence to draft
from. **If it says there is not, stop.** A spec drafted from a repo that could
not evidence its own behaviour is a spec of guesses wearing the authority of a
committed file — and every later classification is made against it.

Say what was missing and what would fix it. "Add a test that names the
behaviour" is a real answer; inventing the requirement is not.

## What a drafted requirement is, and is not

Everything drafted here is **inferred and unconfirmed**. That is not a
formality:

- It carries the marking in the spec until a person confirms it.
- **It gets no acceptance-criteria row.** That table answers "do the tests
  assert this", and an inferred requirement has not been agreed, so a row for
  it would answer a question nobody asked.
- It cannot trigger the Stage 2 contradiction halt. An imported guess must not
  block a real intent with the authority of a decision nobody made.

Write down what each one was read *from* — the test, the route, the flag, the
doc heading. A requirement whose evidence is not recorded cannot be confirmed
later by anyone except whoever drafted it, and they will not remember either.

## Then confirm them in batches

Do not ask about twenty-five requirements at once. Take them a batch at a time,
quote each sentence in full with the citation it carries, and take the answer by
id. **Promote nothing that was not named, and never treat silence as a yes** —
silence is the most common way an inferred requirement becomes an agreed one
without anybody deciding.

A requirement confirmed loses the marking and earns its acceptance row. One
refused is withdrawn with `Rejected at import:` and the reason. Both are
answers; neither is the default.

## What this does not do

The survey is **read-only and executes nothing** from the repo it reads — a
`package.json` script or a Makefile target is quoted as text, never run. That is
deliberate: a repo being examined never chooses what runs on the machine
examining it.

It reports what it can evidence, which is not the same as what the code does.
Behaviour with no test, no route, no flag and no doc is invisible to it, and the
report says what it looked at rather than implying it looked at everything.
