# Release post — <product> <version>

One post per release, drafted from the spec delta and the merged PRs, published
by a human. It is the outward-facing claim about what the product now does, so
the standard is the same as the spec's: **nothing here that the release did not
actually ship**.

Never publish this from an agent
: Drafting is delegated; publishing is not. A post is not reversible — it is
indexed, quoted and forwarded within minutes. The draft goes to a person, and
the person posts it.

Never claim a number you did not measure
: "Twice as fast" needs the two measurements, the machine, and what was being
measured. A benchmark that was reasoned about rather than run is the fastest
way to lose the audience this post is written for.

## <Headline — what a reader can now do, in their words>

<Opening paragraph: the problem, as the person having it would describe it. Not
the feature. If the opening sentence contains the feature's name, rewrite it —
the reader does not know that name yet and has no reason to care about it.>

## What this changes

<Two or three paragraphs. Each one: what was hard, what is now different, and
what it looks like. Draw them from the delta's **added** and **superseded**
sections — those are the two that changed what the product does. Refinements
rarely make a post; duplicates never do.>

![<what this shows — describe it, do not caption it "screenshot">](images/<product>-<version>-<what>.png)

Screenshots are captured from the released build, at the released version, in
this session. Stamp the version into the filename so a stale one is visible
rather than plausible.

## How to get it

<Install or upgrade, as a command the reader can run. One command per block.>

```
<upgrade command>
```

## What is not in this release

The section most posts leave out, and the one that earns the most trust. Name
the obvious adjacent thing this release does **not** do, and say whether it is
coming. Readers find that out in ten minutes anyway; the only choice is whether
they find it out from you.

## Credit

<Who contributed, by name, including the people who reported the problem. Check
the byline of anything you cite — an author and an acknowledged contributor are
different people, and getting that wrong in public is worse than not citing at
all.>

---

**Pre-publish checks.** Each is a `no` that stops the post, not a comment.

- [ ] Every claim traces to a merged PR or a requirement id in the delta.
- [ ] Every number was measured, and the measurement is stated or linked.
- [ ] Every screenshot came from this version's build.
- [ ] Every command was run, in this state, and produced what is shown.
- [ ] No customer, repo, internal hostname or employer name appears anywhere.
- [ ] Names and bylines of anyone credited are correct.
- [ ] A human is publishing this.
