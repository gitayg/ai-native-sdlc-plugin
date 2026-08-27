# Scheduled task prompt — control band check (Stage 6A)

Create with `create_scheduled_task`, taskId `sdlc-bands`, cron to match how fast
the metric moves (hourly for deploy health, daily for cycle-time drift).

---

Check the control bands for <REPO PATH> and report breaches.

1. cd to <REPO PATH>. Read `.claude/sdlc.json` for the binding and
   `ops/bands.yaml` for the metric, baseline and tier actions. If either is
   missing, stop and report which — do not guess thresholds.
2. Run the detection script named in bands.yaml. Detection is deterministic:
   compute the breach from the data, never judge it by eye.
3. Act strictly by tier:
   - **1σ** — log the value and stop. No diagnosis, no report beyond one line.
   - **2σ** — diagnose read-only using the tools bands.yaml permits. Report the
     evidence. Change nothing.
   - **3σ** — diagnose, then write the finding as an `intent.md` in Stage 1
     format: anomaly, evidence, proposed outcome, affected systems, open
     questions. Commit it to the artifact path. Take a pre-approved runbook
     route only if bands.yaml lists it; otherwise stop at the intent.md.
4. Never deploy, never roll back, and never touch production credentials — the
   tier config is the boundary, and a breach is not authorisation.
5. Report: the metric, the band it breached, the evidence, and the path of any
   intent.md you committed, so it can be triaged.
6. End with exactly one verdict line, always. The evidence above never stands in
   for it, and a long diagnosis is precisely when the reader most needs the tier
   stated rather than inferred. Name the tier explicitly — use one of:
   - `VERDICT: BREACH 3σ — <metric> at <value>, intent.md at <path>` — triage now.
   - `VERDICT: BREACH 2σ — <metric> at <value>, diagnosis above` — read it today.
   - `VERDICT: BREACH 1σ — <metric> at <value>, logged only` — no action. This is
     the one line step 3 allows; it is the whole report.
   - `VERDICT: WITHIN BAND — <metric> at <value>` — no action.
   - `VERDICT: DID NOT RUN — <reason>` — see below.

A missing `sdlc.json` or `bands.yaml`, a detection script that failed or returned
nothing, or a metric the data source could not supply is `DID NOT RUN`, naming
what blocked it. Never report it as within band — a band that was not measured is
not a band that held.
