# Traceability — from a requirement id to the commits and the tests

The spec already owns the hard half of traceability: **permanent requirement
ids**, never reused and never renumbered (R2). That gives every agreement a
name that stays valid for the life of the product.

What it did not give you is the reverse lookup. Given `R14`, nothing could
answer *which commits built this*, and given a commit, nothing recorded *which
agreement it served*. This file closes both directions with two conventions and
one script, `scripts/req-trailer.sh`.

| Direction | Mechanism | Failure it makes visible |
|---|---|---|
| requirement → commits | `Productizer-Req:` git trailer | a requirement nothing was ever committed for |
| requirement → tests | `COV_<id>_<slug>` coverage id | a requirement nothing tests |
| commit → requirement | the same trailer, read backwards | a commit citing an id that does not exist |
| test → requirement | the same coverage id, read backwards | a test still guarding a superseded requirement |

## 1 · The commit trailer

```
Productizer-Req: R14,R22
```

One line, at the end of the commit message, in the trailer block. Ids are
comma-separated and carry no other punctuation. `R14` — this repo's format, not
`R-014` and not `REQ-14`; `req-trailer.sh` refuses anything else by name rather
than repairing it, because a repaired id is a shape the spec's own readers do
not match.

### Why a trailer, and not a database

Because it costs nothing and survives everything. A trailer is part of the
commit object, so it clones, fetches, rebases, cherry-picks, mirrors and
`format-patch`es with it, and it is queryable on a machine that has never heard
of this repo's tooling:

```sh
TZ=UTC git log --grep='Productizer-Req:.*R14'
```

There is no service to run, no table to migrate, no id map to keep in step with
the spec, and nothing that rots the day the tool that wrote it is uninstalled.
Every alternative — an issue link, a PR label, a spreadsheet, a row in a
database — is a second store that drifts from the first the moment someone edits
one and not the other. This one cannot drift, because there is only one copy of
it and it is inside the thing it describes.

### Installing the hook

```sh
cp plugins/productizer/skills/spec/templates/prepare-commit-msg.sh \
   .git/hooks/prepare-commit-msg
chmod +x .git/hooks/prepare-commit-msg
mkdir -p .claude/productizer/bin
cp plugins/productizer/skills/spec/scripts/req-trailer.sh .claude/productizer/bin/
```

It is a **git** hook, not a Claude Code hook: it is registered by living at that
path, it takes no JSON on stdin, and `settings.json` knows nothing about it.
`.git/hooks/` is not committed and not cloned, so every clone installs it again
— that is git's design, not an oversight of this one.

The hook takes the ids from, in order:

1. `$PRODUCTIZER_REQ` — `PRODUCTIZER_REQ=R14,R22 git commit -m "…"`.
2. The branch name. `feat/R14-halt-on-contradiction` gives R14;
   `R14-R22-intake` gives both. An `R<n>` run counts only when it stands alone,
   so `PR2`, `CORS` and `v2R` are not read as ids.
3. Nothing — it says so once on stderr and gets out of the way.

**It does not block your commit**, with one exception. A missing trailer is a
gap in a record, not an unsafe act, and a hook that refuses to let you commit
because it could not guess an id from a branch name is a hook that gets deleted
within a day, which costs the record everything. The exception is an id **you
named yourself** in `$PRODUCTIZER_REQ` that the spec does not contain: that is a
false provenance record being written deliberately, and it aborts. Ids merely
inferred from a branch name never abort anything.

Enforcement belongs where it can see the whole change — `--validate` in a
pre-push hook or in CI, `--orphans` against the spec.

## 2 · Coverage ids

```
COV_<requirement-id>_<slug>

COV_R14_halts_on_contradiction
COV_R16_unmeasured_is_not_zero
```

Put one in the name of the test, or in a comment on it — anywhere in a tracked
file. What matters is that the token exists in the tree and that a reader can
see which test it belongs to.

### The rule that makes this work: there is no second id authority

The requirement id appears **verbatim** inside the coverage id. Consequences,
all of them deliberate:

- A coverage id cannot be minted without naming a requirement.
- Coverage ids are never numbered, allocated, or renumbered. There is no
  `COV` counter to keep, and nothing to reconcile.
- A coverage id stops resolving the moment the requirement it names stops
  standing — which is exactly when someone should look at it.

An independent coverage namespace mapped to requirements by a table would be a
second permanent-id authority, and two id authorities in one repo disagree.
This one is derived, so it cannot.

### Note on the examples above

`COV_R14_halts_on_contradiction` in the paragraph above is a **literal token in
a tracked file**, and `--coverage` scans tracked files textually. If this
reference doc is inside the repository being scanned, it counts as coverage of
R14 and R16. That is why `req-trailer.sh` itself carries no literal example in
its header — it gets vendored into the repositories it scans, and its own
documentation would have shown up as real coverage. See KNOWN_LIMITATIONS.md.

## 3 · The commands

```sh
req-trailer.sh --add R14,R22 --file .git/COMMIT_EDITMSG
req-trailer.sh --validate [--file <msg> | --rev <rev>]
req-trailer.sh --query R14
req-trailer.sh --orphans
req-trailer.sh --coverage [--include-ignored]
```

| Mode | Answers | Notes |
|---|---|---|
| `--add` | — | merges rather than appends; run it twice and the file is byte-identical. Refuses to write an id the spec does not contain, and leaves the file untouched when it refuses. Placement is `git interpret-trailers`, which knows where the trailer block ends and that `#` comment lines are not part of the message. |
| `--validate` | does every cited id exist? | an unknown id is an error naming it. A **superseded or withdrawn** id is a note, not an error — a commit made before the replacement is telling the truth about its own history. |
| `--query` | which commits claim this id? | prints the plain `git log --grep` that answers the same question without this script. |
| `--orphans` | which active requirements does no commit claim? | also reports the reverse: ids claimed by a commit that the spec does not contain. |
| `--coverage` | which active requirements does no `COV_` id name? | also reports **dangling** (names an id the spec never had) and **stale** (names a superseded or withdrawn requirement) coverage ids. |

Exit codes are the contract:

```
0  ran, nothing to report — backed by the counts it printed
1  crashed before reaching a report. Undetermined, never clean
2  bad usage, or no spec / no ids in it — nothing was compared
3  a finding. The run succeeded; what it found did not
4  CANNOT DETERMINE. Not a pass, and not a zero
```

## 4 · The zeros this refuses to print

`0 orphans` reads as a clean bill of health, and several quite different
situations can produce it. R16 says a value that could not be measured is not
recorded as zero, so they are kept apart and each says which one it is:

| Situation | Reported as |
|---|---|
| no living spec | exit 2, "nothing to trace ids against" |
| not a git repository, or git failed | exit 4, naming git's own error |
| a repository with no commits yet | exit 4, "no history to search" |
| commits, but not one carries a trailer | exit 4, "the mechanism is not in use here; coverage is UNKNOWN" |
| commits, some carrying trailers | a measurement — with the counts it was measured from |
| no file could be listed (`--coverage`) | exit 4, "nothing was scanned" |
| files scanned, no `COV_` id anywhere | exit 4, "the convention is not in use here" |

Every measured report prints how many commits it walked and how many carried a
trailer, so an answer that came from a shallow clone or a stray branch can be
recognised as one instead of believed.

## 5 · What this cannot do

The trailer says a commit **claims** an id. It does not say the requirement is
implemented, correct, or finished, and nothing here checks that the diff has
anything to do with the requirement it cites. A coverage id says a token
naming a requirement exists in the tree — not that the test runs, and not that
it passes. Both are pointers for a reader, in the same spirit as
`scripts/drift-reverse.sh`: they find the places worth reading and refuse to
call the rest clean.

The full list, with the reproductions behind it, is in **KNOWN_LIMITATIONS.md**
at the repository root. The one worth knowing before you start:
**`git commit --amend -m` destroys the trailer.**
