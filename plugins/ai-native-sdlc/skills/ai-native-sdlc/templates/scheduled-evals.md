# Scheduled task prompt — nightly eval regression (Stage 4B)

Create with `create_scheduled_task`, taskId `sdlc-evals`, cron `0 2 * * *`
(local time). The prompt below must stay self-contained: each run starts fresh
with no memory of the conversation that created it.

---

Run the agent eval suite for <REPO PATH> and report drift.

1. cd to <REPO PATH>. Read `.claude/sdlc.json` for the repo binding. If it is
   missing, stop and report that Stage 0 has not been run — do not guess and do
   not prompt.
2. Read `evals/` — each subdirectory holds `prompt.md` and the checks that
   define an acceptable result.
3. For each eval, run it non-interactively and record pass or fail with the
   reason. Do not fix anything you find.
4. Compare tonight's pass rate against `evals/history.jsonl`. Append today's
   result as one JSON line: date, pass, total, and the ids of any eval that
   changed state since the last run.
5. Report, in this order:
   - pass rate tonight vs. the last run, and vs. 7 days ago
   - every eval that flipped pass→fail, with the failure output verbatim
   - every eval that flipped fail→pass
   - evals that have been failing for more than 3 consecutive runs
6. If nothing changed state, say so in one line. Do not summarise passing evals.
7. End with exactly one verdict line, always. Findings above never stand in for
   it, and a wall of failures is precisely when the reader most needs the answer
   stated rather than inferred. Use one of:
   - `VERDICT: REGRESSED — <n> eval(s) flipped pass→fail` — triage tonight.
   - `VERDICT: STILL FAILING — <n> eval(s) failing, none flipped` — no new
     damage, but the suite is not green.
   - `VERDICT: CLEAN — <pass>/<total>, nothing flipped` — no action needed.
   - `VERDICT: DID NOT RUN — <reason>` — see below.

`CLEAN` requires every eval to have passed. A missing suite, a binding you
stopped on at step 1, a harness that would not start, or any eval that could not
be executed is `DID NOT RUN`, naming what blocked it and which evals were
skipped. Never report an unexecuted or partial suite as clean — a check that did
not run is not a check that passed.
