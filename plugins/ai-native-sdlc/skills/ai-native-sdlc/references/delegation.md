# Delegating stages 3-5 to an external check runner

This skill's stages 3-5 are prose. Prose is advisory: it can be reasoned around,
and it cannot exit non-zero. Where a repo has a real check runner available —
something that computes plan-vs-diff, tests-vs-criteria, a review brief and a
pre-push gate — delegate to it. Enforced beats advisory, and running both over
the same work produces two sets of findings and one confused engineer.

This skill never reimplements those checks. It calls them, or it says it could
not and falls back.

## Configure it

Point `SDLC_CHECK_RUNNER` at an executable that accepts `--help` and exits 0
when it is working:

```bash
export SDLC_CHECK_RUNNER="/path/to/your/check-runner"
```

Unset is a normal configuration, not an error. Plenty of repos have no runner,
and the fallback below is a supported path rather than a degraded one.

## Probe, never assume

`scripts/detect-context.sh` reports `check_runner` as one of three states:

| State | Meaning | What to do |
|---|---|---|
| `usable` | it ran and exited 0 | delegate |
| `present-but-broken` | it exists and does not run | fall back, and report the breakage — do not retry |
| `absent` | not configured, or not there | fall back |

**Presence is not usability.** A runner can sit on disk with every dependency
apparently in place and still fail to load — a packaging mistake one directory
up is enough. So the probe runs it and believes the exit code rather than
testing for the file. An existence check reports a broken runner as available,
and being told a tool is there when it is not is the more expensive mistake.

**Say which way it resolved, every time.** "Delegated to the check runner" and
"no runner configured, using this skill's own checks" are both fine outcomes.
Silently doing the second while the reader assumes the first is not.

## The four checks and what they consume

The artifact chain feeds them directly — that is the point of writing the
artifacts down in the first place.

| Check | Consumes | Stage | Answers |
|---|---|---|---|
| plan-vs-diff | `plan.md` | 3A | did what shipped match what was promised |
| tests-vs-criteria | the living spec's requirements | 4A | do the tests assert the acceptance criteria |
| review brief | the diff | 5A | what a fresh reviewer should look at |
| pre-push gate | the diff | 5 | is this safe to push |

Two rules about how to use them:

- **Hand the review brief to a subagent with a clean context.** Reviewing in the
  session that wrote the code is the failure being avoided; a brief consumed by
  the writing session is not a review.
- **Resolve and state the base first.** Every one of these compares against a
  base, so a wrong base makes all of them confidently wrong together. An empty
  diff is far more often a base problem than a change that did nothing.

## Refusal is not a crash

A gate has to be able to say no, and a reader has to be able to tell "no" from
"broken". Expect a runner to distinguish them by exit code, and treat them
differently:

| Exit | Meaning | Response |
|---|---|---|
| 0 | passed | continue |
| 3 | **refused** — a deliberate no | stop, report what it refused and why |
| 2 | bad usage | fix the invocation, not the code |
| 1 | crashed | the runner is broken, not the change |

Reporting a crash as a refusal sends someone to fix code that was never the
problem. Reporting a refusal as a crash gets the gate ignored. If a runner
collapses both into 1, treat every 1 as unverified rather than as a pass — this
skill's own `templates/threshold.sh` follows the same convention.

## When there is no runner

Run stages 3-5 from `SKILL.md` and say that is what you are doing. The prose
covers the same ground: plan mode before implementation, verification before
done, a written review policy, and a production gate as a hook. What it does not
do is enforce, so the human review gate carries more weight when the runner is
absent. That is a reason to be explicit about it, not to hide it.
