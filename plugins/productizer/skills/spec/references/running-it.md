# Where each stage actually runs

Two surfaces, a third that is optional, and a hook that runs before the push — the
only one of the four that can prevent an escape rather than report one.

| Surface | Can it ask? | Runs when you are away? | Can it block a merge? | Can it prevent an escape? |
|---|---|---|---|---|
| Interactive session | yes | no | no | no |
| Local scheduled task | **no** | only while the app is open | no | no |
| CI (optional) | no | yes | **yes** | no — it runs after the push |
| Pre-push hook | no | no | no | **yes** |

## Interactive session — the default for every stage

Stages 1, 2, 3, 4A, 5A, 5B and on-demand 6A all run here. This is where
`AskUserQuestion` is legitimate, where Stage 0 binding happens, and where
`.claude/productizer/config.json` gets written.

**5C triage runs here too.** Rather than the article's `if: failure()` pipeline
step, bring the failure in: `gh run view <id> --log-failed`, then make the same
call — most likely cause, flaky or real, three lines for the PR thread. Pulled
instead of pushed. You choose when, which also means it never fires on a failure
you already understand.

## Local scheduled task — 4B evals and 6A bands

Created with `create_scheduled_task`; prompts in `templates/scheduled-evals.md`
and `templates/scheduled-bands.md`.

Three properties that shape how the prompts must be written:

1. **Each run starts fresh** with no memory of the conversation that created it.
   The prompt carries the repo path, the config path and the output format, or
   the run is useless.
2. **It cannot ask.** No human is at the keyboard at 02:00. Missing config is
   reported and the run stops — it never prompts, and it never guesses a
   threshold or a project key.
3. **It runs while the app is open.** If the app was closed when the task was
   due, it runs on next launch — late, and the user should know that. A metric
   window that assumes hourly checks will have holes.

Completion notifies the session, so findings arrive in chat and a human triages.
That preserves the article's actual design: no person in the path up to the
finding, a person for every judgement after it.

## CI — only for what must be a gate

Dropping CI costs exactly one thing: **4B stops being a merge check.** The
article gates changes to `CLAUDE.md`, skills and hooks on eval pass rate, which
is a control — it prevents a config regression from landing. A schedule reports
after the fact instead, so drift can ship and sit until morning.

That is a real downgrade, and an acceptable one for a small team that reads its
notifications. If the eval suite ever becomes the thing standing between the
agent and production, move 4B to `templates/agent-evals.yml` and require the
check in branch protection. Nothing else needs to move with it.

### A required check blocks a merge, not an escape

A required status check runs **after the push**. For most of what it catches that
is the whole remedy: a wrong diff base, a stray gitlink, a committed build
artefact, a failing 4B suite. Nothing has left the machine that a follow-up commit
cannot correct, so refusing the merge is enough.

A leaked secret is not in that class. By the time CI fails the credential is on the
remote, in the reflog, and in every clone that fetched. Blocking the merge does not
unring it — the secret has to be rotated. This is the one failure mode CI cannot
fix, and no amount of branch protection changes that; it is structurally too late.

So a secret check belongs in a **pre-push hook**, the only surface that still runs
before the escape, and it is a hook for the same reason Stage 6's production gate
is. CI enforces the rest, for everybody, where nobody can quietly skip it. The two
are not alternatives — choosing CI alone leaves exactly the failure that cannot be
undone.

To place a new check, ask what a failure costs at the moment CI would catch it:

- **Reversible by a follow-up commit** — diff base, gitlinks, build artefacts,
  formatting, tests, eval pass rate. CI, required in branch protection.
- **Irreversible once pushed** — secrets, tokens, credentials, real customer data in
  a fixture. Pre-push hook. Keep the CI check too: the hook is local, and someone
  will eventually pass `--no-verify`.

## What never moves

Stage 6's production gate is a hook (`templates/production-gate.sh`), not a
schedule and not a session. It runs wherever the deploy is attempted, and it
blocks until a named human authorises. Surfaces change; gates do not.
