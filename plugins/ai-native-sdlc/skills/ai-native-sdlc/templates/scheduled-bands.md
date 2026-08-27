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
   - **3σ** — diagnose, then **open an issue** carrying the finding: anomaly,
     evidence, proposed outcome, affected systems, open questions. Label it as
     an intent so it lands in the same triage queue as everything else. Take a
     pre-approved runbook route only if bands.yaml lists it; otherwise stop at
     the issue. Do not edit the spec — a production signal goes through intake
     like any other intent, which is what stops it silently contradicting an
     agreed requirement.
4. Never deploy, never roll back, and never touch production credentials — the
   tier config is the boundary, and a breach is not authorisation.
5. Report: the metric, the band it breached, the evidence, and the number of any
   issue you opened, so it can be triaged.
6. End with exactly one verdict line, always. The evidence above never stands in
   for it, and a long diagnosis is precisely when the reader most needs the tier
   stated rather than inferred. Name the tier explicitly — use one of:
   - `VERDICT: BREACH 3σ — <metric> at <value>, issue #<n> opened` — triage now.
   - `VERDICT: BREACH 2σ — <metric> at <value>, diagnosis above` — read it today.
   - `VERDICT: BREACH 1σ — <metric> at <value>, logged only` — no action. This is
     the one line step 3 allows; it is the whole report.
   - `VERDICT: WITHIN BAND — <metric> at <value>` — no action.
   - `VERDICT: DID NOT RUN — <reason>` — see below.

A missing `sdlc.json` or `bands.yaml`, a detection script that failed or returned
nothing, or a metric the data source could not supply is `DID NOT RUN`, naming
what blocked it. Never report it as within band — a band that was not measured is
not a band that held.
