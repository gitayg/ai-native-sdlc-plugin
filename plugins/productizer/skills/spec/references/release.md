# Documentation and go-to-market, per release

Two stages that run **once per release**, not once per intent. Stages 1–5 move
one change; a release is the batch a user actually receives, and it is the first
moment anyone outside the team is affected by any of it.

- **5B · Document** — the user guide, regenerated from the spec and the release.
- **5C · Announce** — the release post and the release email, drafted from the
  delta and the merged PRs.

Templates: `templates/user-guide.md`, `templates/release-blog.md`,
`templates/release-email.md`.

## Why per release rather than per intent

Per-intent documentation produces a changelog with headings on it. Each entry is
accurate and the document as a whole describes no product — the reader gets
twelve small announcements and no account of what the thing does now. It also
documents work nobody has received yet: an intent merged behind a flag is in the
guide before it is in the product.

Per release is also the only cadence at which the **removals** are visible.
Within one intent, a superseded requirement looks like an edit. Across a
release, the set of superseded and withdrawn ids is the list of things that used
to work and no longer do — the changes readers most need and least often get.

## What the stage reads

Nothing is authored from memory of the work. Both stages read:

| Source | Gives |
|---|---|
| The living spec, active requirements | what the product does now — the guide's sections |
| Superseded and withdrawn since the last release | what changed and what was removed |
| The spec deltas in the release's PRs | which change served which requirement, and why |
| The merged PRs | what actually shipped, as opposed to what was planned |
| The released build | the screenshots, and the commands, run |

The spec answers *what is true*; the PRs answer *what shipped in this batch*.
Both are needed, and they disagree more often than anyone expects — a merged PR
that changed no requirement is either undocumented behaviour or a refactor, and
the difference matters enough to ask.

## The rules that are not negotiable

**The agent drafts, a person approves, the agent runs it.** 5C is an agent
stage like the rest: it writes both artefacts, captures the screenshots,
verifies the release is live and installable, runs the pre-publish checklist,
and says which items it could not verify itself. Then it stops and asks.

What the person owns is the **decision**, not the typing. Handing them a command
to paste is a worse design in both directions: it drops them into a terminal to
run something they did not compose and cannot easily check, and it makes the
approval a chore - and a chore becomes a rubber stamp. Asking plainly and then
executing on an explicit yes keeps the judgement with the human and the
mechanics with the agent, which is the split the whole lifecycle uses.

An explicit yes means this publish. Not silence, not an inferred yes, and not a
yes given to some earlier question. The publish is enforced as a hook
(`templates/publish-gate.sh`) rather than left as a convention — a rule the
agent is asked to remember is a rule it eventually reasons past.

The gate denies the commands that reach an audience — `gh release create`,
`npm publish`, a tag push, a mail API, a site deploy — and allows everything
the agent needs to do its own work, including committing drafts and rendering
images. Same shape as the production gate at Stage 5, for the same reason:
every other artefact here is a commit someone can revert; a post is indexed and
forwarded within minutes, and mail cannot be recalled.

**Screenshots come from the released build, in this session, with the version in
the filename.** A screenshot from the previous release is a lie with a picture
attached, and it is the most common way documentation goes silently wrong: the
prose gets reviewed, the image does not.

**Every number was measured.** "Twice as fast" requires two measurements, the
machine, and what was measured. A benchmark reasoned about rather than run is
the fastest way to lose the readers this is written for.

**Every claim traces to a merged PR or a requirement id.** A post is a claim
about the product made in public. If the trace cannot be produced, the sentence
comes out — including the ones that are probably true.

**Name what is not in the release.** The adjacent thing this release does not
do, and whether it is coming. Readers find that out in ten minutes regardless;
the only choice is whether they hear it from you first.

**Scrub before it leaves.** Customer names, repo names, internal hostnames and
the employer's name are all reasons a draft never becomes a post. Check the
screenshots too — a terminal title bar, a browser tab and a sidebar each carry
more than the person capturing them intends.

## Coverage, stated rather than assumed

The guide's requirement mapping names, for each section, which active
requirements it covers — and then names the **actives with no section**. An
omission and full coverage look identical unless the gap is stated, which is the
same reason a check declares what it must have examined (`references/checks.md`).

Undocumented is a legitimate state. Silently undocumented is not.
