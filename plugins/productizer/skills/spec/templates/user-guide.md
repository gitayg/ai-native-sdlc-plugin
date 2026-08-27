# User guide — <product>

The guide is generated per release from what the release actually changed, and
it is a **document about the product**, never a changelog with headings. A guide
regenerated from scratch each time reads like a different product every release;
a guide that is only ever appended to accumulates instructions for features that
no longer exist. Both are worse than no guide, because both are believed.

Source of truth
: The living spec. Every section maps to **active** requirement ids, and a
requirement with no section is a gap the release did not document. Superseded
and withdrawn requirements have no section — that is how removed behaviour
leaves the guide without anyone remembering to delete it.

Written for
: The person using the product, not the person who built it. Requirement ids
never appear in the prose. They live in the mapping table at the bottom, which
is for the writer and the reviewer.

Screenshots
: Every screenshot is captured from the released build, in the same session that
generates the guide, with the version stamped in the filename. A screenshot
from a previous release is a lie with a picture attached, and it is the single
most common way documentation goes quietly wrong.

## <Product> — <one line, what it is for>

<Two or three sentences: who this is for, and the problem it removes. No
feature list — that is the rest of the document.>

## Getting started

<The shortest path from nothing to the first useful result. Numbered steps, each
one an action the reader performs, each with the observable result of having
done it correctly. A step with no observable result cannot be got wrong, so it
does not need to be a step.>

1. <action> → <what you should see>
2. <action> → <what you should see>

![<what this shows>](images/<product>-<version>-getting-started.png)

## <Task the reader wants to do>

One section per **task**, ordered by how often it is done, not by how the
product is built. A section per screen or per menu documents the architecture;
the reader does not have the architecture in their head, they have a job.

<What it is for, then how, then what a correct result looks like.>

**If it goes wrong.** <The failure the reader will actually hit, and what to do
about it. Every unwanted-behaviour requirement in the spec earns one of these —
they are the requirements that describe what the product refuses to do, and they
are exactly what generates support tickets when undocumented.>

## What changed in <version>

Short, and **only user-visible change**. A refactor with no observable
difference does not belong here; it belongs in the release notes for engineers.

| Change | What it means for you |
|---|---|
| <the behaviour, in the reader's words> | <what they can now do, or must now do differently> |

Behaviour that was **removed** is listed here too, with what to use instead.
Removals are the changes readers most need and least often get.

## Requirement mapping

Not published — kept in the source file so the next generation knows what was
covered, and so a reviewer can answer *is anything undocumented* without reading
the whole spec.

| Section | Requirements | Screenshot from |
|---|---|---|
| Getting started | R7, R12 | <version> |
| <task> | R41, R42, R43 | <version> |

**Undocumented actives:** <ids, or `none`>. An active requirement with no
section is a gap. State it rather than omitting it — an omission looks identical
to full coverage.
