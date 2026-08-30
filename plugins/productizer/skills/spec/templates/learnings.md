# L<n> — an observation, not a requirement

Status: unverified
Observed: <YYYY-MM-DD>
Observed by: <where this came from — a session id, a CI run, an issue, a person>
Corroborated: —
Corroborated by: —
About: —
Graduated to: —

That block is read by machine as well as by people. One `Key: value` per line,
no blank line inside the block, and `Status:` carries exactly one of
`unverified`, `verified`, `graduated` or `withdrawn` — nothing else on the line.
An unset field is an em dash, never blank: a blank value and a missing line are
indistinguishable to anything counting these files, and a counter that cannot
tell them apart reports an unverified observation as a corroborated one.

`Observed:` is the only source of age. There is no `stale` field and there will
not be one — a stored flag has to be updated by someone and nobody will. A date
that does not parse gives an age of an em dash, never an age of forever: the
entries with the least provenance are the ones that most need recovering, and
treating them as infinitely old buries them.

`About:` is a comma-separated list of requirement ids, or an em dash. This is
the one thing this store can do that a notes file cannot: ids are permanent, so
a citation stays meaningful, and a learning about a requirement that has since
been superseded or withdrawn is mechanically detectable. Cite `R14`, never a
path and never a heading — a tidy-up rename breaks a path reference silently.

## What was observed

> <What was seen, quoted. Write what happened, not what anyone should do about
> it: "the build failed until the generator was run" is an observation; "you
> must run the generator first" is an obligation, and obligations belong in the
> spec under an `R` id or nowhere. `learnings.sh check` refuses obligation
> language in an unverified observation for exactly this reason.>

## Why this is not a requirement

<One or two sentences. If this cannot be written, the entry is probably a
requirement in the wrong file — take it through intake instead. The test is
simple: name who is obliged. If the answer is "nobody", it is a learning.>

## What would corroborate it

<One thing a DIFFERENT source could do that would confirm or refute this.
Written NOW, while the observation is fresh. Written afterwards, any evidence
that happened to turn up looks exactly like the evidence that was wanted.>

## Corroboration

<Filled by `learnings.sh verify --id L<n> --by <source>`, and only by a source
that is not the one on the `Observed by:` line. That refusal is the whole
mechanism: a run that can confirm its own learning promotes whatever it just
wrote, and every verified learning after it is worth nothing.

One line per corroboration, dated, naming the source. A second corroboration
adds a line here; it does not change the status again.>

## Graduated

<Filled by `learnings.sh graduate --id L<n> --to R<n>` when the observation
turns out to be a real obligation. The requirement is merged into the spec
first — an id in the spec is the merge — and this only records that it
happened.

The learning keeps its id and stops being served. Nothing above is edited: the
observation was true as an observation when it was written, and rewriting it
destroys the only evidence of how it looked before anyone agreed to it.>
