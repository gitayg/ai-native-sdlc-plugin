# Import — adopting a codebase that already exists

The rest of this skill assumes a repo starts with an empty spec and accretes
requirements one intent at a time. Almost no repo is in that state. The ordinary
case is six hundred commits, no spec, and nobody left who can say why half of it
is the way it is.

Import is the bridge: from an existing codebase to a living spec that describes
what it already does, so change tracking can start from today rather than from a
rewrite. It runs once per product, as **Stage 0c**, after Stage 0a has scaffolded
the empty spec and before the first intake.

Prompt: `templates/import.md`. Survey: `scripts/import-survey.sh`.

## The thing that makes this hard

Extraction is not the hard part. Reading routes and test names out of a repo is
mechanical, and the survey does it in under a second.

The hard part is that **a requirement reverse-engineered from code is a
description of behaviour, not an agreed decision.** Nobody ratified it. Some of
it describes bugs. Some of it describes behaviour three people have been quietly
working around for a year.

Write those sentences into the spec as though they were agreed and three things
break at once, none of them visibly:

- **The audit trail becomes fiction.** The spec's whole claim is that
  `git log -p .claude/sdlc/spec.md` is a history of decisions. An import that
  writes two hundred requirements in one commit makes the first and largest entry
  in that history a record of nothing having been decided.
- **The contradiction halt starts defending accidents.** Stage 2 stops the work
  when an intent conflicts with an active requirement, and that stop is expensive
  and correct — precisely because an active requirement means somebody agreed.
  Point it at an imported bug and the process now blocks the fix, with the
  authority of a decision nobody made.
- **Every downstream citation inherits the confidence.** Plans cite ids, tests
  cite ids, review findings cite ids. A requirement gets more solid the more it
  is referenced, and none of those references re-check where it came from.

So the design question is not how to extract more. It is how to keep imported
requirements permanently distinguishable from agreed ones until somebody looks.

## The mechanism: an inferred status that cannot halt

Imported requirements land as **inferred** and become active only when a human
confirms them.

An inferred requirement is a normal EARS sentence with a marker line beneath it,
in the same position `templates/spec.md` already puts `Superseded by R58.` and
`Withdrawn.`:

```
- **R8** — When a client requests an app icon, the `crane` server shall send a
  publicly cacheable response.
  Inferred from test `app icons stay cacheable — public, unchanging, fetched
  constantly` (`test/api-cache-control.test.js`). Unconfirmed.
```

Four properties follow from that, and they are the whole design:

1. **It carries its provenance.** Anyone reading the requirement, or a plan
   citing it, can reach the evidence in one hop. A requirement whose citation no
   longer resolves is a requirement to re-check, and that is now visible.
2. **It cannot stop work.** Only active requirements trigger the Stage 2
   contradiction halt. A conflict with an inferred requirement is downgraded to
   the confirmation question — *the code does X today; is X intended?* — which is
   the question that needed asking anyway. This is the single rule that stops the
   lifecycle defending imported accidents.
3. **It is not counted as verified.** Inferred requirements get no acceptance
   criteria row. The comparison between active requirements and criteria rows is
   what answers "do the tests assert the criteria", and inferred rows would
   inflate that answer with behaviour nobody agreed to test.
4. **Promotion is a commit.** Confirming a requirement deletes one line and adds
   a criteria row and a decision-record entry. The spec diff then names which
   sentences a specific person ratified on a specific day — which is the audit
   trail the lifecycle claims to sell, now genuinely earned rather than asserted.

### Alternatives considered, and why they lose

**A separate provisional id space (`I1`, `I2`), promoted to `R` ids.** Cleaner
looking, and fatal: promotion would have to renumber, and renumbering silently
redirects every citation made in the meantime. Ids are never renumbered is the
one absolute rule in `references/ears.md`, and this would break it on a schedule.
Inferred requirements therefore take real ids from the normal counter, and a
rejected one is withdrawn with its id spent. Spending an id on a rejected
inference is a real cost and the right one.

**A separate file — `spec.inferred.md` — merged on confirmation.** Splits the id
allocator, which is the mistake the products-and-repos section already refuses
for the same reason. Two allocators eventually hand out the same number.

**Import nothing; let intake discover the spec over time.** Honest, and it is
what happens today by default. It fails because the first intake has nothing to
classify against, so every early intent classifies as *extend*, and the
contradiction detection — the only reason the living spec earns its cost — does
not start working until the spec has accidentally caught up with the code, which
takes years.

**Import everything and mark the whole spec provisional at the header.** A file-
level caveat is read once and then never again, while ids are cited forever. The
status has to travel with the requirement.

## The procedure

1. **Bind and scaffold first** (Stages 0 and 0a). Import writes into an existing
   empty spec; it does not create one.
2. **Run the survey.** `scripts/import-survey.sh <repo-path>`. Read all of it.
3. **Name the system**, once, from the manifest or entry point.
4. **Draft up to thirty inferred requirements**, in the order
   `templates/import.md` sets: test names, then observable surface, then error
   paths, then config-gated behaviour. Every one carries a citation.
5. **Write the refusals down as gaps**, in the same pass. The list of what could
   not be inferred is worth more than the draft, because it is the list of
   questions only a person can answer.
6. **Raise contested behaviour under *Areas of concern***, not as a corrected
   requirement.
7. **Confirm in batches of about ten**, in the session, by id.
8. **Record the import as one change-log row**, and each ratification batch in
   the decision record.

Steps 4 to 8 are one round. A large system gets several, scoped by area, spaced
by whatever pace a human can genuinely review at.

## The survey script

`scripts/import-survey.sh [repo-path]` gathers the evidence and nothing else. It
emits a plain-text report: languages, manifests, declared and inferred entry
points, HTTP routes and RPC handlers, file-based routes, config and feature flag
reads, config files, test files, test names, error paths, docs and doc headings,
CI and gate files, and change history.

Design constraints it holds to:

- **It never writes to the surveyed repo.** Temp files live under `TMPDIR` and
  are removed on exit. Verified by comparing modification times across a run.
- **It never executes anything from the repo.** A `package.json` script and a
  `Makefile` target are quoted as text, never run.
- **It degrades silently.** Every probe prints `(none found)` rather than
  failing. A repo with no tests, no routes and no readable git is a normal input.
  Git being unreadable — a sandboxed path, an export, a bare checkout — removes
  the churn signal and nothing else, and is reported as a line rather than an
  abort. This is not hypothetical: one of the two repos it was developed against
  returns `fatal: unable to access '.git/config': Operation not permitted`.
- **It is bounded.** Vendor, build and VCS directories are pruned; the file list
  is capped; each section is capped; each file gets a quota within a section, so
  one large router cannot spend the whole budget and leave the survey describing
  a corner of the repo as though it were the repo. Where a cap bit, the section
  says `(truncated at N)`. Both development repos survey in under a second.
- **Live secret files never enter the file list** — `.env`, keys, certificates,
  `*.local`. `.env.example` is kept deliberately, and its values are redacted to
  the key names. A survey that quotes the right-hand side of a dotenv line has
  copied a secret into a report that gets pasted into a chat.
- **Repo content cannot forge structure.** Every evidence line is indented, so
  only the script's own headers start at column 0; paths containing control
  characters are dropped before any probe sees them, and the header reports how
  many of the files found were actually scanned. A file whose contents read
  `## Requirements` cannot impersonate a section in a report the agent reads as
  structure.

## What this will get wrong

Concretely, not as a disclaimer.

**The survey**

- **Test names are trusted more than they deserve.** A test named
  *"rejects expired tokens"* that asserts nothing still reads as intent. The
  survey reports names, never assertions, and a skipped or vacuous test looks
  identical to a passing one.
- **Route lists are declarations, not the surface.** A mounted router shows
  where it is mounted, not what it exposes; middleware ordering, auth wrappers
  and dynamic registration are invisible. Routes built by string concatenation or
  registered in a loop do not appear at all.
- **Regex extraction produces false positives.** A file named
  `server/routes/config.js` is listed under config files because it matches on
  name; `process.env[m[1]]` yields a config hit with no name in it. Read the
  citation, not the count.
- **Framework coverage is a list, not a rule.** Express-shaped JavaScript,
  Flask/FastAPI/Django, Go router methods, Spring annotations, Rails routes,
  Tauri commands and the MCP SDK's `server.tool` / `addTool` shapes are
  recognised. Anything else — gRPC service definitions, GraphQL schemas,
  message-queue consumers, cron entries, serverless handler manifests — is missed
  silently, and a missed transport looks exactly like a system that does not have
  one. Worse, a covered framework can still be missed: a repo that builds its MCP
  tool catalogue dynamically rather than calling `server.tool` produces an empty
  handler section while plainly having handlers. Of the probes here, only the
  JavaScript, Rust and attribute-following ones have been exercised against a
  real repo; the Python, Go, Java, Ruby and MCP probes are unverified, and an
  unverified probe returning nothing is not evidence of absence.
- **Build output that shadows source is counted twice.** A `dist`-like directory
  under a name not on the prune list produces a duplicate of every finding.
- **Pruning by directory name over-prunes.** A legitimate source directory named
  `build`, `out`, `target` or `vendor` is skipped entirely.
- **Churn is not importance.** The most-changed files on a young repo are the
  version-bumped manifests, every time.

**The requirements drafted from it**

- **Bugs will be written down as behaviour.** This is intended — the alternative
  is a spec that silently disagrees with the running system — but it means a
  fraction of any import is a catalogue of defects phrased as `shall`.
- **Coverage is skewed to whatever is tested.** Well-tested areas produce
  requirements; the untested core produces almost none, which inverts where a
  spec is most needed. Say so in the report rather than letting the shape of the
  draft imply the shape of the system.
- **Everything unobservable is missing.** Batch jobs, migrations, retries,
  caching, back-pressure, anything whose effect is only visible in production.
- **Cross-component behaviour is missing.** The survey reads one repo. A product
  spanning repos gets one repo's surface described as though it were the product.
- **The `Where <feature is included>` requirements will be wrong about
  defaults.** A flag read in code says the branch exists; it does not say which
  way it is set in production, and the survey cannot see production.
- **Thirty requirements will not describe a large system.** The cap is chosen so
  a person can read the draft, not so the draft is complete. An import that feels
  complete has almost certainly stopped being read.

## Limits worth stating to the user before starting

- Import produces a **starting point that is honest about being one**, not a
  finished spec. The finished spec accretes through intake, as designed.
- The value arrives at **confirmation**, not at drafting. An import nobody
  reviews is worse than no import, because it looks like coverage.
- Requirements that stay `Unconfirmed.` indefinitely are a signal, not debt to
  hide: they are the parts of the system nobody currently owns.
