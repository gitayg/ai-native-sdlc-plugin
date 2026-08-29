# Productizer — backlog

Everything wanted and not yet agreed. This is the queue **in front of** the
lifecycle: nothing here has been through intake, so nothing here is a
requirement. An item leaves this file by becoming an intent at Stage 1, and what
happens to it after that is decided by intake, not by whoever wrote it down.

Location
: `.claude/productizer/backlog.md`, beside the living spec, in the spec home repo.

Order is priority
: Top is next. The file's order **is** the ranking — there is no priority field,
because two orderings disagree the moment someone edits one and not the other.
Reordering is an ordinary edit and needs no ceremony: nothing here is agreed, so
nothing is being changed by moving it.

Ids
: Backlog items take `B<n>` and keep it. `B` never shares a counter with `R`
(requirements), `P` (principles) or `D` (rulings). An item that becomes an
intent keeps its `B` id in the intent so the trail from "someone wanted this" to
"the spec now says this" survives.

Next backlog id
: `B11`

## Status

| Status | Means | Who moves it |
|---|---|---|
| `todo` | wanted, ready to be picked up | anyone |
| `long-term` | wanted, deliberately not now | anyone, with a reason |
| `in-progress` | Stage 1 has started on it | whoever started |
| `blocked` | cannot proceed, and the blocker is named | whoever found the blocker |
| `done` | it went through intake and reached the spec, or was refused | intake |

**`done` does not mean built.** It means the item left this queue — merged as a
requirement, ruled a duplicate, or refused. The spec records which. A backlog
that reuses `done` to mean shipped starts competing with the spec for the
answer to "what does this system do", and loses.

**An item with a Jira key does not carry its own status.** See below.

## Items

Highest priority first.


| Id | What is wanted | Status | Jira | Raised | Notes |
|---|---|---|---|---|---|
| B1 | Take one intent through all nine stages on this repo, through a PR | `todo` | — | maintainer, 2026-08-28 | Stage 8 has no deltas or PRs to draft from until this happens |
| B2 | The gates cannot see inside a script | `long-term` | — | security review, 2026-08-28 | `./release.sh` is judged as its own name; no command-text gate can fix this |
| B3 | The solver misses semantic contradictions | `long-term` | — | maintainer, 2026-08-28 | 0.70 recall on the 21 cases we wrote first, **0.12 on a harder 26-case corpus** — the figure tracked the corpus, not the checker |
| B4 | `jira.status_map` has never met a real Jira | `todo` | — | maintainer, 2026-08-28 | eleven states mapped, zero tested |
| B5 | Release assets for offline install | `long-term` | — | maintainer, 2026-08-28 | only worth it if an install path without git is wanted |
| B6 | Scaffolded specs still carry placeholder rows | `todo` | — | maintainer, 2026-08-29 | `| R1 | <area> |` index rows and `P4`/`P5` amendment rows sit outside the example fences `scaffold.sh` strips. The parsers ignore them, so this is a documentation wart, not a seeded requirement |
| B7 | Two scripts have no option contract | `todo` | — | usage-audit, 2026-08-29 | `detect-context.sh` accepts any flag and exits 0; `scaffold.sh --help` exits 2. `import-survey.sh` had the same defect and is fixed |
| B8 | Make suppressed stderr a declared check | `todo` | — | maintainer, 2026-08-29 | `2>/dev/null` hid three real defects in one session. A check over our own scripts would have caught each |
| B9 | Split the requirements carrying two `shall` clauses | `todo` | — | validate-spec, 2026-08-29 | R14, R16 and R21 each state two obligations under one id, so each will be half-tested. `--strict` fails on the real spec until they are split |
| B10 | The eval corpus has never been graded | `todo` | — | maintainer, 2026-08-29 | `claude plugin eval` is early-access gated. 26 cases load and both ablation arms configure; no case has been scored by a model, so end-to-end recall stays unmeasured |

## Items tracked in Jira

An item may name a Jira key. When it does:

- **Jira owns the status.** The `Status` column shows what Jira last said, and
  the local status vocabulary above does not apply. Two systems tracking one
  item's state disagree within a week, and the one people update is the one
  people look at.
- **The mapping is declared once**, in `.claude/productizer/config.json` under
  `jira.status_map`, so "In Progress" and "In Dev" resolve to the same thing
  without anyone guessing per item.
- **Nothing is written back to Jira from here.** Reading is safe; writing puts
  this file in an argument with a workflow, a board and an automation rule that
  it will lose. Moving a Jira ticket happens in Jira.
- **The key is the join.** Never re-title an item to match its ticket — titles
  drift, keys do not.
- **If Jira cannot be read**, say so on the row rather than showing a stale
  status as if it were current. `status: unknown (Jira unreachable <when>)`.

## Starting work

Moving an item to `in-progress` is Stage 1: it becomes an intent, gets an issue,
and enters intake. Record the issue number in Notes so the item and the intent
point at each other.

**Starting work does not agree anything.** An item can be picked up, taken
through intake, and refused because it contradicts a requirement someone agreed
to two years ago. That is intake working, not a mistake — and it is the reason
the backlog is not the spec.

## What does not belong here

- **Requirements.** If it is agreed, it belongs in the spec with an `R` id.
- **Bugs against agreed behaviour.** Those are drift or incidents: they enter at
  Stage 1 as their own intent and get fixed against a requirement that already
  exists.
- **Anything already in the spec.** Intake will classify it a duplicate, which
  is the correct answer arrived at expensively.
