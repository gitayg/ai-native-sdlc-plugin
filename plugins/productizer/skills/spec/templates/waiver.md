# W<n> — <the failing check, in a few words>

Check: <check id, exactly as `checks.yaml` declares it>
Authority: <the named person who decided>
Reason: <one line: why this finding is accepted for now>
Expires: <YYYY-MM-DD>
Raised: <YYYY-MM-DD>
Intent: <#123 / PROJ-123>

That block is read by machine as well as by people. One `Key: value` per line,
the first occurrence of each key wins, and an unset field is an em dash — never
blank, because a blank value and a missing line are indistinguishable to
anything counting these files. `Check`, `Authority`, `Reason` and `Expires` are
all required: a waiver missing any of them is reported `malformed` and softens
nothing.

## Where this file lives, and what makes it read at all

`.claude/productizer/waivers/W<n>-<check-id>.md`, and it is read **only** when
`checks.yaml` says so:

```yaml
policy:
  waivers: .claude/productizer/waivers
```

**Absent by default, deliberately.** Waiver files sit in the repository being
examined, and P4 says a repository being examined never chooses what runs on
the machine examining it. With no `policy.waivers` key the directory is never
opened, so a repo you cloned arrives with its gates still armed however many
waivers it ships. Turning it on is one line in the committed config — the same
shape, and the same reasoning, as `policy.allow_repo_local_tools` — and like
every `policy` key it cannot be turned on from a `checks.local.yaml`.

## What a waiver does, and the one thing it must never do

It moves **one already-measured failure** out of the blocking set, until
`Expires`. That is all.

It does **not** change the measurement. The check stays `status: fail`, its
findings stay in the result file, and the stage renders it
`FAIL · WAIVED BY <authority>` — never `PASS`. P1 is why: an overridden check
*was* measured, so recording the override is honest, but a failure rendered
green because somebody said so is a judgment wearing a measurement's clothes.

## What cannot be waived

| Situation | Reported as | Why |
|---|---|---|
| the check could not run — `missing_tool`, `timeout`, `no_version`, `refused`, `unmapped_exit` | `not_applicable` | there is no finding to override, only an absence of one, and a person cannot decide an absence away |
| the check is `hollow` — it examined less than it declared | `not_applicable` | same: nothing was measured to overrule |
| the check passed, is disabled, or this change did not trigger it | `not_applicable` | there is nothing to waive |
| the check is `severity: advise` | `not_applicable` | its findings already do not block |
| `Check:` names no declared check | `unknown_check` | it matched nothing, so it waives nothing |
| `Expires` has passed | `expired` | the check blocks again; a waiver is bounded on purpose |
| two waivers name one check | `duplicate` | two authorities over one check is not an override; neither is honoured |

## What `Authority` is, and what it is not

A named person. Never a role, never "the team", never an email alias — an
unattributed override cannot be questioned later, because nobody knows who to
ask.

It is **a label, not a credential.** The runner renders it and nothing else: it
is untrusted repository text, so it is collapsed to one printable line,
truncated, and never executed, resolved as a path, or read as an instruction.
What actually authorises the override is the reviewed commit that added this
file, which is why the run reports the waiver's **location** and lets a reader
open it.

`Reason` is never echoed anywhere. Only whether one is recorded.

## What a waiver does not restore

The waived check is still `fail`, so every `coverage.spec_units` claim it made
is still voided and the requirement it claimed goes back to `Missing`. Under
`policy.spec_coverage: require` the run therefore still refuses — on the
**denominator**, not on the check. A waiver is a decision about one finding, not
a statement that the requirement is verified. Waiving a check does not waive the
spec.

## Expiry

Required, and short. Pick the date the finding is actually expected to be gone,
not a year out. An unbounded waiver outlives the person who wrote it and the
finding it was written for, and the next reader cannot tell a live decision from
an abandoned one.
