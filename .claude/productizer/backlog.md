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
: `B24`

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
| B9 | Split the requirements carrying two `shall` clauses | `done` | — | validate-spec, 2026-08-29 | Done 2026-08-29. R14/R16/R21 superseded with text retained, replaced by R23-R28. The split alone could not clear `--strict`: the EARS rules were being applied to superseded requirements, whose text must be retained verbatim, so the warning was unclearable. Fixed in the validator; `--strict` now exits 0 |
| B10 | The eval corpus has never been graded | `done` | — | maintainer, 2026-08-29 | Graded 2026-08-29: **16/16 recall, 0.94 precision** end to end, against **13/16** for a no-plugin baseline. The three it uniquely catches are domain entailment, an unquantified adjective against a bound, and vocabulary drift. 52 runs, $14.79. n is small and the corpus is self-authored; the harness is early-access |
| B11 | The agent halts on a contradiction and does not ask for the ruling | `todo` | — | eval, 2026-08-29 | `06-ruling-requested` failed on P01, P11 and P12 in the graded run. The halt is correct and nobody is prompted for the decision, so the work stops and stays stopped |
| B12 | No cross-session memory of any kind | `todo` | — | maintainer, 2026-08-29 | Every session re-reads the files and reconstructs the rest. a comparable tool ships a `SessionStart` hook plus one reload command; the mechanism is ~1 day. Their retrieval is alphabetical over untimestamped free text, so the selection problem is ours to do better - we would be selecting from spec, rulings and stage state |
| B13 | A check has no rendering after a human overrides it | `todo` | — | maintainer, 2026-08-29 | A ruling is recorded; what the *check* shows afterwards was never decided. Gas City's `FAIL - WAIVED BY <authority>` keeps the failure and adds a named authority rather than flipping green. Note theirs is emergent convention, not policy - `grep -ci waiv` on their own conventions doc returns 0 |
| B14 | Nothing asserts one living spec per product (R1) | `todo` | — | interrogation, 2026-08-29 | `product.spec_home` is declared in config.json and never read back. No declared check, no script that refuses on an ambiguous or unreachable home, none of validate-spec's 53 codes. R1 is the requirement most exposed to what it exists to prevent: two allocators both handing out R42 |
| B15 | 11 active requirements have no acceptance row | `todo` | — | maintainer, 2026-08-29 | R1, R3, R4, R6, R7, R8, R9, R10, R12, R13, R19. The table answers "do the tests assert this" as a fact, so a row must come from an answer, never from reading the code and guessing. The dashboard's copy-prompt now interrogates rather than fills |
| B16 | The runner JSON format ships with no executor | `todo` | — | maintainer, 2026-08-29 | `templates/runners/*.json` defines id, agent, timeout, sandbox scope, an anchored rubric and an output contract. Nothing in the repo runs one. It is a format, not a gate, and the site says so |
| B17 | Try two-factor contradiction detection | `long-term` | — | maintainer, 2026-08-29 | Scope overlap and directive polarity as independent gates rather than one similarity score, which conflates "same subject" with "opposite requirement". Trial against the 26-case corpus where the symbolic check scores 0.12. Do not take Gas City's lexicon: 12 hardcoded antonym pairs, reports without blocking |
| B18 | The measurement suite has never run against a real model | `todo` | — | maintainer, 2026-08-29 | `ab-harness.sh` arms were printf and sleep; `retrieval-budget.sh` measures a character proxy that has never been calibrated against a token count. Both are honest about it in their own output; neither has produced a figure about this product |
| B19 | Graduated hook and CI-gate rungs are stubs that assert nothing | `todo` | — | graduate, 2026-08-29 | The escalation ladder picks the right rung and writes a file that checks nothing. The lexicon knows a cluster is mechanically checkable; it cannot write the check |
| B20 | Control-framework tags for ISO 27001 and 42001 | `long-term` | — | maintainer, 2026-08-29 | `checks.yaml` already triggers on requirement tags. Tagging a requirement `A.8.28` or `42001-6.1.2` fires that control's checks on exactly the changes that touch it. Scope is the evidence layer under an ISMS - not risk assessment, SoA, asset inventory or internal audit |
| B21 | Nothing lints markdown template frontmatter | `todo` | — | delegation review, 2026-08-29 | Declared checks cover all files (hygiene), `**/*.sh` and the solver corpus. The agent templates carry frontmatter that decides tool access, and no check reads it |
| B22 | Scripts are untested off macOS | `long-term` | — | maintainer, 2026-08-29 | Every script was developed and run on macOS with bash 5.3 and BSD userland. GNU coreutils, GNU awk and bash 3.2 are argued, not measured |
| B23 | The dashboard could hand over its evidence as a file | `long-term` | — | maintainer, 2026-08-29 | A published artifact may declare `downloads`, which is still output. It must not declare `artifact` - a page that saves new versions of itself becomes a second source of truth that can disagree with the repo, and the provenance line stops being true |

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
