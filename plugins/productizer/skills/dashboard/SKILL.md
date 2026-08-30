---
name: dashboard
description: "Regenerate the Productizer dashboard from this repo's own files and publish it as a page. Shows the living spec, the backlog queue, the board of what is actually in flight, the last check run, releases, and what each declared check cannot see. Use when asked to see the dashboard, the pipeline, the spec at a glance, what is in flight, what is waiting on a person, or the state of the lifecycle."
argument-hint: "[--stale-after SECONDS]"
disable-model-invocation: true
allowed-tools: Bash Read Artifact
---

# The dashboard

Regenerated below, from the files in this repository. Nothing here is remembered
from a previous run.

!`set -e; R="$(git rev-parse --show-toplevel)"; B="${CLAUDE_PLUGIN_ROOT}/skills/spec/scripts/build-view.sh"; O="${TMPDIR:-/tmp}/productizer-dashboard-$(basename "$R").html"; if [ ! -r "$B" ]; then echo "build-view.sh not found under the plugin root. Nothing was generated."; exit 0; fi; bash "$B" "$R" --out "$O" 2>&1; echo "OUT=$O"`

## What to do with that

The line above ends with `OUT=<path>`. That file is the page.

1. **Read it is not required.** It is generated, it is large, and reading it
   costs context for nothing. Publish it as an artifact directly from that path.
2. **Check it first** if this repo has a hygiene gate — `scripts/check-hygiene.sh`
   or the shipped `skills/spec/scripts/check-hygiene.sh`. A dashboard renders
   commit subjects and bodies, which no file edit can correct, so it is the one
   generated file worth gating before it is published. If the gate fails, say so
   and do not publish.
3. **Publish it**, then hand over the link.

## Say what it is, and what it is not

Tell the person two things they cannot see from the page alone:

- **It is a snapshot, not a live view.** Those numbers were true when the script
  ran, not since. Say so.
- **What still needs a person.** The page counts it in the ring's hub; say what
  the items actually are, rather than repeating the number.

If the generation failed, report the failure and stop. A dashboard that could
not be built is not an empty dashboard, and publishing a stale file from a
previous run would present old numbers as current ones — which is the single
worst thing this page can do.
