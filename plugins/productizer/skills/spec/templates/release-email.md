# Release note email — <product> <version>

Sent to people who already use the product. They are not being sold to; they
need to know what changed before it changes under them. Different document from
the blog post, same release, and the difference is the audience's stake:
**a reader of this email may have to do something.**

Subject
: `<Product> <version> — <the one thing that matters>`
Not "Release notes" and not the version alone. The subject is read in a list of
forty, and it is the only part most recipients will read.

Send it after the release is live
: A note announcing a version nobody can install yet generates support load and
teaches recipients to ignore the next one. Confirm the released artefact is
actually reachable first, and say how you confirmed it.

Never publish this from an agent
: Drafting is delegated; sending is not. Mail cannot be recalled.

---

**<Product> <version> is out.** <One sentence: what a reader can now do.>

**Action needed**

<This block comes first or is deleted entirely — never buried below the
features. Anything the reader must do: a migration, a config change, a
deprecation with a date, a default that changed. If nothing is required, say
"Nothing to do — upgrade when convenient", because its absence is otherwise
indistinguishable from an oversight.>

**What's new**

- **<change>** — <what it means for the reader, one line>
- **<change>** — <what it means for the reader, one line>

Three to five items. A list of twenty is read as none. Anything cut belongs in
the full notes, linked below — cut by what the reader must know, not by what was
hardest to build.

**Changed or removed**

- **<behaviour>** — <what it does now, and what to use instead>

Removals and behaviour changes go above new features when both are present. A
reader who missed a removal finds out through a broken workflow.

**Upgrade**

```
<upgrade command>
```

Full notes: <link> · Guide: <link> · Something wrong: <where to report it>

---

**Pre-send checks.**

- [ ] The version named is live and installable, and that was verified, not assumed.
- [ ] The upgrade command was run against a clean environment and worked.
- [ ] Every action-needed item has a date or a version by which it applies.
- [ ] Removed behaviour is named, not implied by its absence.
- [ ] The recipient list is the one intended, and no address is exposed to the others.
- [ ] No customer, repo, internal hostname or employer name appears anywhere.
- [ ] A human is sending this.
