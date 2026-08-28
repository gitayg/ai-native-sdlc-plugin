# The checks stage

Security and quality checks are a stage a team configures, not a list baked
into the tool. The declaration is `.claude/productizer/checks.yaml`
(`templates/checks.yaml`); the runner is `scripts/run-checks.sh`; the output is
`.claude/productizer/checks-result.json`, which the review stage reads.

The runner decides nothing. Which checks exist, what triggers each one, whether
it blocks, and what it must have covered all come out of the config. A change
to the checks stage is a diff against that file, reviewed like code, with the
same audit trail as everything else in this lifecycle.

## Where it sits

```
3 · build  →  4 · test  →  [ CHECKS ]  →  5 · deploy (review, gate)  →  6 · maintain
```

It runs after the change builds and its tests pass, and before a human is asked
to look at it. That position is deliberate in both directions:

- **After build**, because a check needs a diff to scope itself against. Before
  the code exists there is nothing to scan and every check is hollow.
- **Before review**, because a reviewer's attention is the scarcest thing in the
  pipeline. Sending a diff to review with an unrun scanner spends it on
  something a machine settles in ninety seconds.

It runs **locally, before the push**. Wiring it into CI alone breaks the secret
scan: a required CI check blocks the merge, but it runs after the push, and by
then the secret is on the remote and must be rotated. Blocking the merge is the
whole remedy for a failing test; for a secret it fixes nothing. Run it as a
pre-push step, and run it again in CI if you want the merge blocked too.

## What the review stage gets

`checks-result.json` is the handover, and it is evidence rather than a summary.
Per check it records the exact argv, the tool's version string, the exit code,
what triggered it, what it covered, and what it did not. A review that opens
that file can tell the difference between "the SAST pass found nothing" and
"the SAST pass loaded no rules", which is the difference this whole stage
exists to make legible.

Exit codes follow the same convention as the rest of the skill
(`references/delegation.md`, `templates/threshold.sh`):

| Exit | Meaning | What to do |
|---|---|---|
| 0 | every blocking check ran, covered what it declared, and found nothing | continue |
| 3 | **refused** — a deliberate no | read which check and why; fix the change or the config |
| 2 | bad usage, or a config that will not parse or validate | fix the invocation or the config, not the code |
| 1 | the runner crashed | unverified. Not a pass, and not a finding either |

3 and 1 stay distinct because a gate that exits the same way when it says no as
when it falls over is unreadable in a log, and the wrong thing gets fixed.

## Who owns the file

One named person accountable for the checks stage — in most orgs a security or
engineering manager, not the tech lead of whichever team is shipping today.

Three rules make that ownership real:

- **Changes go through review like code.** The file is committed. Loosening a
  check is a diff someone approved, with a date on it.
- **The owner is not in the change's critical path.** An owner who can be
  reached mid-change to soften a check is not a gate, they are a queue.
- **The agent does not edit it.** If the agent can rewrite the checks stage
  when a check blocks it, the stage is advisory. Deny it in managed settings
  alongside the hooks directory:
  `"deny": ["Edit(.claude/productizer/checks.yaml)"]`.

## Per-item scoping

A requirement touching authentication deserves more than a copy edit. Each
check declares `when`, and any one of three things can trigger it:

| Trigger | Written as | Scoped to |
|---|---|---|
| always | `always: true` | every change |
| path | `paths: ["**/*.sh"]` | changes touching matching files |
| tag | `tags: [auth, pii]` | changes whose requirements carry that tag |

**Paths scope to what the change touched. Tags scope to what it means.** A path
trigger hands the check only the files that matched its globs. A tag or an
`always` trigger says something about the change as a whole, so the check gets
every changed file. That distinction matters: a change tagged `auth` that edits
one template and one route should have both scanned by the auth ruleset, not
just the file whose extension happened to match.

Tags come from the living spec. The requirement ids a change cites carry the
tags; the checks stage reads them off the change and scopes accordingly. This
is the payoff for keeping requirements in one place — the scanner list follows
the meaning of the work, and nobody maintains a second classification.

Observed, on the same two files:

```
### N. a copy edit, no tags -> only the baseline triggers
checks stage: 2 declared, 1 triggered by 2 changed files
  PASS      copy-edit-baseline block  exit 0    wc (coreutils)  covered 2

### O. same files, requirement tagged auth -> the auth pass triggers too
checks stage: 2 declared, 2 triggered by 2 changed files and tags [auth, pii]
  PASS      copy-edit-baseline block  exit 0    wc (coreutils)  covered 2
  PASS      sast-auth          block  exit 0    sast-auth 2.1  covered 2/2 files
```

Globs are small on purpose: `**` crosses directory separators, `*` and `?` do
not. `scripts/*.sh` does not match `scripts/deploy/rollback.sh`. Shell-style
globbing that lets `*` cross `/` reads as if it scopes tightly while matching
half the repo, and nobody notices until an audit.

## Blocking and advising

`severity: block` fails the run. `severity: advise` reports into the result and
the review brief without changing the exit code. Advisory is for a check with a
known false-positive rate that is still worth a reviewer's eye.

The failure mode to watch is the check that stays advisory forever. Promote one
to blocking the week its findings stop being argued with; an advisory check
nobody ever promotes is a check nobody reads. The runner names advisory
failures separately in the summary so they cannot be lost in a green run.

## Scanner theatre

**A check that passes tells you nothing unless you know what it examined.**

The worked example is real. This skill was audited by a security scanner called
`ecc-agentshield`. It reported **Grade A, 97 out of 100**. It had opened **one
of the thirty-three files** in the directory, because it only reads files named
`CLAUDE.md` and `settings.json`. Pointed at an empty directory it reports
**Grade A, 100 out of 100, 70 payloads, 70 blocked**. Canaries planted in the
shell scripts — an AWS key, a `curl | bash` — went undetected, and the grade
did not move.

Nothing about that output is a lie. The tool did block seventy payloads in the
one file it read. The grade is arithmetic over what it examined. The failure is
that the report never states the denominator, so a reader supplies their own —
the whole repo — and gets a number that means something entirely different from
what it says.

This is not one bad tool. It is the default shape of a scanner report, and it
survives because a green result is what everyone wanted anyway.

### Three properties that separate a real check from a decorative one

**1 · It reports what it covered, and the runner checks the number.**

Every check declares a `coverage` assertion, and the runner fails the check
when reality falls short — whatever exit code the tool returned. There are four
ways to obtain the number, in rough order of how hard they are to fake:

| `from` | The tool tells you | Fools |
|---|---|---|
| `per_file_exit` | it is invoked once per file; a file it bounced off is a file it did not check | almost nothing |
| `stdout_paths` | it names each file it scanned; compared against the change | a tool that lies in its own report |
| `command` | a separate enumeration command lists what it would cover | a stale enumeration |
| `stdout_count` | it prints how many items it processed | any tool that prints a number regardless |

Prefer `per_file_exit` where the cost is bearable. It is the only one that does
not take the tool's word for anything: the runner watches each file be accepted
or refused, one process at a time. Batch mode lets a scanner choose which files
it feels like opening and still exit 0, which is exactly what happened above.

Run against the config that reproduces the AgentShield behaviour, with the same
forty-eight files:

```
checks stage: 2 declared, 2 triggered by 48 changed files
  PASS      shell-lint         block  exit 0    ShellCheck - shell script analysis tool vers  covered 6/6 files
  HOLLOW    agentshield        block  exit 0    agentshield-stub 0.0  covered 1/48 files
             -> exited 0 but did not examine 47 of the 48 files in scope (SKILL.md, references/constitution.md,
                references/delegation.md, references/drift.md, references/ears.md, ...). A check that examined
                nothing is a failure, not a pass.
REFUSED: agentshield (hollow)
```

`HOLLOW` is the whole point. The tool exited 0 and claimed a perfect grade. The
stage refused it anyway, and named the forty-seven files nobody looked at.

**2 · It records the version of the tool that produced the verdict.**

A blocking check must declare `version_command`; the runner refuses a config
where one does not, and fails a check whose tool cannot state its version. The
version is not parsed or compared against a minimum — it only has to *change*
when the tool changes. A scanner that silently regresses between releases, or a
ruleset that quietly stopped downloading, is invisible in a stream of green
runs and obvious in a diff of two result files.

`min_rules` is the same idea aimed at the rules rather than the binary. A
ruleset that failed to download is an empty ruleset, and an empty ruleset
passes everything at high speed. Declare how many rules must load and enumerate
them with `rules_command`.

**3 · It has been seen failing.**

Break the check on purpose, watch it go red, revert, and note what you broke.
A check never observed failing is decoration, and the decoration is
indistinguishable from the real thing until an incident.

For the shell linter in `templates/checks.yaml`, that evidence looks like this
— the same config, run against three scripts and then against the clean one:

```
### A. broken scripts present -> expect FAIL, exit 3
  FAIL      shell-lint         block  exit 1    ShellCheck ...  covered 3/3 files
             -> the check reported findings.
REFUSED: shell-lint (fail)
EXIT=3

### B. same config, only the clean script -> expect PASS, exit 0
  PASS      shell-lint         block  exit 0    ShellCheck ...  covered 1/1 files
PASS: every blocking check ran, covered what it declared, and found nothing.
EXIT=0
```

Do that for every check before you believe the stage. It is twenty minutes once
and it is the only thing that distinguishes this config from the one that
graded an empty directory at 100.

### How the runner fails closed

Six ways a check can look green without being green, and what happens instead:

| Situation | Naive result | Here |
|---|---|---|
| the config will not parse | partially honoured, some checks dropped | exit 2, nothing runs |
| a declared tool is not installed | skipped, run still green | `missing_tool`, the check fails |
| a check hangs | the job is killed, or waits forever | `timeout`, the check fails |
| the tool returns an exit code nobody mapped | treated as success | `unmapped_exit`, the check fails |
| the tool exits 0 having examined nothing | `PASS` | `hollow`, the check fails |
| no declared check matches the change | green, no checks ran | refused, unless `policy.empty_run: pass` |

Observed, all in one run:

```
  MISSING_TOOL missing-tool       block  exit -    version unknown
             -> declared tool not installed: gitleaks. Not skipped — a check whose tool is absent is a check that did not run.
  TIMEOUT   slow-scan          block  exit 124  sleep 1.0  covered 0
             -> hit the 3s limit. A killed scanner has no verdict; it is not a pass.
  UNMAPPED_EXIT unmapped           block  exit 42   sh 1.0  covered 5
             -> exit 42 is not described in `exit_codes`. An exit code the config does not recognise is treated as a failure: tools add codes between releases.
  HOLLOW    advisory-hollow    advise exit 0    version unknown  covered 0
             -> exited 0 but examined 0, which is below the declared minimum of 1. A check that examined nothing is a failure, not a pass.
```

`policy.empty_run: refuse` is the least obvious of the six and the one that
catches the most. A change nothing checks is not a clean change; it is a change
the config does not describe. The `pass` setting exists so a repo mid-adoption
can opt out of that deliberately, in a committed line someone approved, rather
than by accident.

One more, which the runner reports but cannot fix: a check whose exit code says
*findings* and whose coverage says *nothing examined*. Fixing the finding would
turn that red into a hollow green, so the runner says both in the same line
rather than waiting for the next run to surprise someone.

## Adding a check

1. Write it in `checks.yaml` with an argv `command` — never a string. This file
   is committed, so a string handed to a shell lets anyone who lands a commit
   choose what runs on the machine of whoever pulls it. The runner refuses one.
2. Scope it. `always` for anything that can hide in any file type; `paths` for
   a language or a directory; `tags` for a class of requirement.
3. Map its exit codes from the vendor's documentation, and confirm them against
   the build you actually have. Separate *findings* from *the tool refused to
   run*: reporting a crash as a finding sends someone to fix code that was
   never the problem.
4. Declare its coverage, preferring `per_file_exit`.
5. Give it a `version_command`. Blocking checks are refused without one.
6. Break it. Watch it go red. Revert. Note what you broke in the pull request.
7. Start it at `advise` if you expect argument, and diarise the promotion.

## What this stage does not do

- **It does not judge whether the declared checks are the right ones.** A config
  with one weak check passes cleanly. Coverage assertions police each check;
  only a human polices the list. Review the file the way you would review an
  access-control list, on a schedule, and ask what is absent rather than
  whether the present ones passed.
- **It does not sandbox the tools it runs.** Everything in `checks.yaml`
  executes with the runner's privileges. That is why the config is argv-only,
  reviewed like code, and denied to the agent.
- **It does not replace hooks.** A hook is deterministic and fires on every tool
  call; this stage runs once per change. Protected paths and formatting stay in
  hooks (`templates/hooks-settings.json`). Heavy scanners belong here.
- **It does not survive a tool that daemonises.** A timeout kills the check's
  process group. Something that escapes that group outlives the run.
- **It is not a substitute for the review.** It narrows what a reviewer has to
  hold in their head. Every finding it reports is still a human's call, and
  everything it does not know to look for is entirely theirs.
