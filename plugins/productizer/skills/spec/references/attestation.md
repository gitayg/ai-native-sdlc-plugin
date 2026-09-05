# Attestation — what this repository can prove, and the one thing no standard can hold

`scripts/emit-attestation.sh` turns the living spec into a **CycloneDX
Attestations** document: requirement → claim → evidence, with the conformance
each check actually measured. Everything it emits is already in the repository;
nothing is invented for the document.

One thing it cannot emit, and does not fake: **a model wrote most of these
changes, and no supply-chain provenance standard has a field that says so.**
That gap is written into the document rather than papered over, and the last
section of this file is a proposed in-toto predicate that would close it,
written to in-toto's own template so it can be sent as-is.

---

## 1. What the emitter produces

```
emit-attestation.sh [--repo DIR] [--spec PATH] [--result PATH] [--out PATH]
```

Reads `.claude/productizer/spec.md`, `.claude/productizer/checks-result.json`,
`.claude/productizer/classifications/`, `.claude/productizer/rulings/` and the
commit trailers. Writes one CycloneDX 1.6 BOM.

| Repository fact | CycloneDX field |
|---|---|
| requirement id, sentence, status | `definitions.standards[].requirements[]` — `bom-ref`, `identifier`, `title`, `text`, `properties` |
| the product being attested | `declarations.targets.components[]` |
| the requirement, asserted | `declarations.claims[]` — `target`, `predicate`, `reasoning`, `evidence` |
| the check that asserts it, and what it said | `declarations.evidence[]` — `bom-ref`, `propertyName`, `description`, `created` |
| the coverage verdict | `declarations.attestations[].map[]` — `requirement`, `claims`, `conformance` |
| the spec's own sha256 at HEAD | `declarations.evidence[]` |
| how each intent was classified | `declarations.evidence[]` |
| a decision with a **named human** | `declarations.evidence[].reviewer` |
| everything with no field | root `properties[]`, labelled as such |

Every field name above was read out of the schema, not remembered:
<https://raw.githubusercontent.com/CycloneDX/specification/master/schema/bom-1.6.schema.json>

**Exit codes.** `0` emitted and every active requirement carries a *measured*
conformance · `1` emitted, with findings · `2` could not measure, and nothing
was emitted. These are `check-hygiene.sh`'s three, not `req-trailer.sh`'s five:
this tool either produced a document or it did not.

**It never scores what it did not measure.** A `Covered` verdict gets
`conformance.score: 1`. A `Missing` verdict gets `0`, and that zero *is* a
measurement — the run examined every declared check and none named the
requirement. A `Partial` or an `n/a` gets **no score at all**, only a
`rationale` naming which part is unasserted, because the fraction was never
measured and `0.5` would be an invention. An absent rulings directory is
reported as absent, never as zero rulings.

**It is reproducible.** Every timestamp is HEAD's commit time pinned to UTC, so
two runs over one commit produce identical bytes, and the document dates the
*state* rather than the *run*.

---

## 2. Which standards this targets, and what was checked

Four formats were read before CycloneDX was picked. The measurements, not the
impressions:

**in-toto attestation predicates** — the vetted list is 12 bullets naming 13
predicate types (SPDX2 and SPDX3 share a bullet). Fetching all fifteen
predicate specifications and grepping every one of them for
`artificial intelligence|machine.learning|LLM|AI|ai agent|authorship|co-author|assisted`
returns **one line**: `spdx3.md:11`, and it is about an AI model as the
*subject* of a BOM — "This can represent software artifacts, software supply
chains, AI models and more" — not as the author of work. The predicates README
itself matches none of those words.
<https://github.com/in-toto/attestation/tree/main/spec/predicates>

**SLSA** — Provenance v1 describes a build: `buildDefinition`, `buildType`,
`externalParameters`, `builder.id`, `resolvedDependencies`, `runDetails`. The
words *AI* and *agent* occur **zero** times on the v1.1 provenance page, and
zero times across the v1.2 `about`, `threats`, `terminology`, `faq` and
`future-directions` pages. <https://slsa.dev/spec/v1.1/provenance>

> A caveat this document owes its reader: SLSA is often quoted as saying in so
> many words that it "does not address AI agents". That sentence was looked for
> and **not found** on any page checked. What was measured is stronger and
> duller — SLSA's specification does not mention AI at all.

**GitHub Artifact Attestations** — `actions/attest-build-provenance` generates
"a SLSA build provenance predicate using the in-toto format", so it inherits
exactly SLSA's vocabulary. Its README contains no occurrence of *AI*, *agent*,
*author*, *model* or *LLM*.
<https://github.com/actions/attest-build-provenance>

**CycloneDX Attestations** — requirements with permanent `bom-ref`s, mapped
requirement → claims → evidence, conformance and confidence scores, signatures
at every level. That is the shape this repository is already in, which is why
the emitter targets it. <https://cyclonedx.org/use-cases/attestations/>

---

## 3. What CycloneDX cannot express

Measured against the 1.6 schema, not inferred:

- **`declarations.evidence.author` and `.reviewer` are both
  `#/definitions/organizationalContact`**, whose properties are exactly
  `bom-ref`, `name`, `email`, `phone`. That is a person. Putting a model's name
  in `author` makes the same false claim `Co-authored-by:` does, one layer
  further from anyone who could catch it. **The emitter leaves both fields out**
  when a tool did the work — 41 of 41 evidence entries in this repository's own
  document carry no `author`.
- **`declarations.assessors[]` has `bom-ref`, `thirdParty` and `organization`.**
  There is no assessor-is-a-tool. The assessor here is a shell script, so it is
  emitted with `thirdParty: false` and **no** `organization`.
- **`claim` and `evidence` have no `properties` name-value store**, and
  `additionalProperties` is `false` on both. Adding an `aiAuthor` field to an
  evidence entry is rejected by the schema with *"Additional properties are not
  allowed ('aiAuthor' was unexpected)"* — measured, by trying it. There is no
  extension point at that level. `requirement` has `properties`, and so does the
  BOM root; those two are the only sanctioned homes for a fact CycloneDX has no
  field for.
- **`metadata.tools`** names the tool that *generated the document*, never the
  agent that did the work the document describes. It is the one place CycloneDX
  acknowledges a tool at all, and it is the wrong one.
- **The `cdx:ai-ml` property taxonomy does not help.** Every property in it
  describes a model as a *component* — modality, parameter count, tuning method,
  tokenizer, context length. Nothing in it says a model *performed work*.
  <https://github.com/CycloneDX/cyclonedx-property-taxonomy/blob/main/cdx/ai-ml.md>

So the emitter writes the gap into the BOM's root `properties[]` array — the
place the schema describes as being for "data not officially supported in the
standard" — under `productizer:attestation:ai-authorship:*`, with the counts
behind it. A reader who parses only CycloneDX fields gets a true document with
a hole in it; a reader who reads the properties is told where the hole is and
how big.

## 3a. The commit-message half

The Linux kernel is the only major project that has written the rule down, so
`req-trailer.sh` follows it verbatim rather than inventing a house style
(`Documentation/process/coding-assistants.rst`):

> "AI agents MUST NOT add Signed-off-by tags. Only humans can legally certify
> the Developer Certificate of Origin (DCO)."

> "Contributions should include an Assisted-by tag in the following format::
> `Assisted-by: LLM [TOOL1] [TOOL2]`"

<https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/Documentation/process/coding-assistants.rst>

`req-trailer.sh --add --assisted-by [--tools "..."]` writes that trailer and
never writes the other two. `req-trailer.sh --authorship` reads a message back
and refuses a `Signed-off-by` or a `Co-authored-by` whose identity looks like an
agent. Run against this repository's own HEAD it exits 3 — and 23 of the last
100 commits here carry a `Co-Authored-By:` naming a model, which is exactly the
claim the kernel's rule forbids.

That check is a word list over free text, so a clean run shows that no **named**
agent signed off, never that a human did. A message carrying no authorship
trailer is not a message written without assistance; it is a message that did
not say. Neither of those is reported as a pass.

---

## 4. Proposed in-toto predicate: AI authorship

Written to in-toto's predicate template
(`spec/predicates/template/template.md`) and its field conventions —
lowerCamelCase names, RFC 3339 timestamps with a `Z` zone and an unambiguous
name — so it can be sent to the project as-is.

---

# Predicate type: AI Authorship

Type URI: `https://in-toto.io/attestation/ai-authorship/v0.1`

Version: 0.1

Predicate Name: `AI Authorship`

## Purpose

Records **which parts of a change were produced by an automated agent, which
human took responsibility for it, and what neither of those can be known
about.** It answers the question every existing predicate skips: not *how* an
artifact was built, but *who or what wrote the input to the build*.

The existing predicates describe machinery. SLSA Provenance describes a build
platform executing a `buildDefinition`. SCAI describes attributes of an artifact
or of the supply chain. Test Result describes tests. Reference, Release, VSA,
SVR, VULNS and the SPDX/CycloneDX wrappers describe documents, releases,
decisions and vulnerabilities. **None of the 13 vetted predicates has a field
for an author of any kind, human or otherwise** — grepping all fifteen predicate
specifications for `AI`, `machine learning`, `LLM`, `authorship`, `co-author` or
`assisted` returns exactly one line, in `spdx3.md`, about an AI model as the
*subject* of a BOM rather than as an author.

The gap is not an oversight in those predicates; it is a category they do not
cover. An artifact's provenance currently starts at the build. This predicate
starts one step earlier, at the change.

## Use Cases

1.  **A DCO or CLA policy that must stay honest.** The Linux kernel now states
    that "AI agents MUST NOT add Signed-off-by tags. Only humans can legally
    certify the Developer Certificate of Origin (DCO)." A verifier can enforce
    that today only by pattern-matching names in commit messages. With this
    predicate the policy becomes a machine-checkable statement: *every commit in
    this release with `agentGenerated` true has a `humanAccountable` who is not
    the agent.* No existing predicate can express either half.

2.  **Provenance of a requirement, not of a binary.** A project that tracks
    which agreed requirement each change served — and which human ruled when two
    requirements conflicted — has a claim to make that stops at the CycloneDX
    Attestations boundary, because `evidence.author` and `evidence.reviewer` are
    both `organizationalContact` and neither can hold a tool. Recording the
    agent in one of those fields is a false claim; leaving it out loses the
    fact. A separate predicate loses neither.

3.  **Regulatory disclosure of automated authorship.** Where a licence, a
    procurement rule or a jurisdiction requires disclosure of AI-generated
    content in a delivered artifact, the disclosure has to travel with the
    artifact and be verifiable. Today it travels, if at all, as prose in a
    commit message.

**Policy questions this predicate is designed to answer:**

- Was any part of this artifact generated by an automated agent?
- Which model, at which version, under whose account, and reviewed by whom?
- Is there a named human who accepted responsibility for every agent-generated
  change in this release?
- For the changes where authorship was not recorded — how many are there? A
  policy must be able to distinguish *no agent involved* from *nobody wrote it
  down*, and today those two are the same silence.

## Prerequisites

The in-toto Attestation Framework. Nothing else. The predicate makes no
assumption about the build platform, the version-control system or the agent
vendor.

Producers are expected to emit this at the moment the change is made — a commit
hook, an agent harness, a review tool. Authorship **cannot be reconstructed
afterwards**, and a predicate written after the fact should say so with
`recordedRetrospectively`.

## Model

This predicate applies to the **authoring** step of a supply chain, before the
build. Its functionaries are the human contributor and the automated agent
acting on their behalf, and its subjects are the things a change produces: a
git commit, a source file, a patch series, a release.

It composes with, and does not replace, SLSA Provenance: provenance says a
platform built these bytes from those inputs; this says who wrote the inputs.

## Schema

```jsonc
{
  // Standard attestation fields:
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{ "name": "...", "digest": { "gitCommit": "..." } }],

  // Predicate:
  "predicateType": "https://in-toto.io/attestation/ai-authorship/v0.1",
  "predicate": {
    "agentGenerated": true,
    "agents": [{
      "name": "...",
      "version": "...",
      "vendor": "...",
      "invokedBy": { "name": "...", "email": "..." },
      "tools": ["..."]
    }],
    "humanAccountable": { "name": "...", "email": "..." },
    "humanReview": {
      "reviewed": true,
      "reviewer": { "name": "...", "email": "..." },
      "reviewedAt": "...",
      "scope": "..."
    },
    "scope": { "kind": "...", "paths": ["..."], "fraction": 0.0 },
    "certification": { "dco": true, "certifiedBy": { "name": "...", "email": "..." } },
    "authoredAt": "...",
    "recordedRetrospectively": false,
    "unrecorded": { "reason": "..." }
  }
}
```

### Parsing Rules

This predicate opts in to the framework's [standard parsing
rules](https://github.com/in-toto/attestation/blob/main/spec/v1/README.md#parsing-rules),
including the monotonic principle: **the absence of an AI-authorship
attestation means nothing was recorded, never that no agent was involved.** A
verifier that treats a missing attestation as proof of human authorship has
inverted the predicate's meaning, and the same applies to a present attestation
carrying `unrecorded`.

Versioning follows the type URI. Consumers MUST ignore unrecognised fields.

Three fields exist specifically so that an honest producer never has to lie:

-   `agentGenerated: false` is a **positive claim** that no agent was involved,
    and is only emittable by a producer that could have observed one.
-   `unrecorded` is emitted **instead of** `agents` when a change is known to be
    agent-generated but the identity was not captured. It carries a `reason` and
    keeps the attestation truthful rather than absent.
-   `recordedRetrospectively: true` marks an attestation reconstructed after the
    fact from commit messages or logs. Such a record bounds what was possible; it
    does not observe what happened, and a verifier SHOULD weigh it accordingly.

### Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `agentGenerated` | boolean | yes | Whether any part of the subject was produced by an automated agent. `false` is a positive claim, not a default. |
| `agents` | array of Agent | if `agentGenerated` is true and `unrecorded` is absent | The agents that produced part of the subject. |
| `agents[].name` | string | yes | The agent or model as invoked, e.g. a model family. Not a marketing name. |
| `agents[].version` | string | no | Model or agent version, exactly as reported by the runtime. Omit rather than guess. |
| `agents[].vendor` | string | no | The organisation operating the agent. |
| `agents[].invokedBy` | ContactInfo | no | The human who ran it. Distinct from `humanAccountable`: running an agent is not accepting responsibility for its output. |
| `agents[].tools` | array of string | no | Specialised analysis tools used alongside the agent (`coccinelle`, `sparse`, `clang-tidy`). Basic development tools — `git`, `gcc`, `make`, editors — SHOULD NOT be listed. |
| `humanAccountable` | ContactInfo | yes when `agentGenerated` is true | The human who takes responsibility for the change. MUST be a natural person. An agent MUST NOT appear here. |
| `humanReview` | object | no | Whether a human reviewed the agent's output before it was accepted. |
| `humanReview.reviewed` | boolean | yes within the object | `false` is meaningful and MUST be emittable: unreviewed agent output is exactly what a policy needs to find. |
| `humanReview.reviewer` | ContactInfo | if `reviewed` is true | A natural person. |
| `humanReview.reviewedAt` | RFC 3339 `Z` timestamp | no | When the review completed. |
| `humanReview.scope` | string | no | What was reviewed — the whole change, or a named part of it. |
| `scope` | object | no | Which part of the subject the agent produced. |
| `scope.kind` | string | yes within the object | One of `whole`, `partial`, `unknown`. `unknown` is a legitimate answer and MUST NOT be rendered as `partial` with an invented fraction. |
| `scope.paths` | array of string | no | Paths within the subject attributable to the agent. |
| `scope.fraction` | number, 0–1 | no | Emit **only** if measured. A producer that did not measure it MUST omit it rather than estimate. |
| `certification` | object | no | The legal certification attached to the change. |
| `certification.dco` | boolean | no | Whether the Developer Certificate of Origin was certified. |
| `certification.certifiedBy` | ContactInfo | if `dco` is true | The human who certified. An agent MUST NOT appear here — this is the field the Linux kernel's rule is about. |
| `authoredAt` | RFC 3339 `Z` timestamp | no | When the change was authored. Not when this attestation was written. |
| `recordedRetrospectively` | boolean | no, defaults to `false` | Whether this record was reconstructed after the fact rather than written at the time. |
| `unrecorded` | object | no | Present when authorship is known to be incomplete. |
| `unrecorded.reason` | string | yes within the object | Why the identity could not be captured. |

`ContactInfo` is `{ "name": string, "email": string }`, both optional
individually, at least one required. It is deliberately the shape of a person
and MUST NOT be used for an agent: the whole point of `agents[]` being a
separate array with its own fields is that a tool is not a contact, and every
existing standard that has forced one into the other has produced a record that
reads as a person and is not.

## Example

```jsonc
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{
    "name": "git+https://example.org/project@refs/heads/main",
    "digest": { "gitCommit": "4b4eb51179bfabd041dfcdbae5212acacc13c0b7" }
  }],
  "predicateType": "https://in-toto.io/attestation/ai-authorship/v0.1",
  "predicate": {
    "agentGenerated": true,
    "agents": [{
      "name": "coding-assistant",
      "version": "2026.08",
      "vendor": "Example AI",
      "invokedBy": { "name": "A Maintainer", "email": "maintainer@example.org" },
      "tools": ["coccinelle", "sparse"]
    }],
    "humanAccountable": { "name": "A Maintainer", "email": "maintainer@example.org" },
    "humanReview": {
      "reviewed": true,
      "reviewer": { "name": "A Maintainer", "email": "maintainer@example.org" },
      "reviewedAt": "2026-09-03T11:00:00Z",
      "scope": "the whole change"
    },
    "scope": { "kind": "partial", "paths": ["scripts/emit-attestation.sh"] },
    "certification": {
      "dco": true,
      "certifiedBy": { "name": "A Maintainer", "email": "maintainer@example.org" }
    },
    "authoredAt": "2026-09-03T11:00:00Z",
    "recordedRetrospectively": false
  }
}
```

`scope.fraction` is absent because nobody measured it. That absence is the
predicate working as designed.

## Changelog and Migrations

Initial version.

---

## 5. What this file does not establish

- **The predicate above has not been submitted to in-toto**, discussed with its
  maintainers, or vetted. It is written to their template and their field
  conventions; it is a proposal, not an accepted predicate, and the type URI is
  a placeholder in in-toto's namespace that only they can grant.
- **No CycloneDX validator CLI was reachable** from the environment this was
  built in. The emitted document was validated against the official CycloneDX
  1.6 JSON Schema with `jsonschema` — 0 errors — and the validator was falsified
  four ways first, so that a green result means something. That is schema
  validity, which is not the same as an implementation such as `cyclonedx-cli`
  accepting it.
- **No document produced here is signed.** CycloneDX offers `signature` at the
  BOM, claim, evidence, attestation and affirmation levels, and the emitter uses
  none of them. `declarations.affirmation` is deliberately absent for the same
  reason: an affirmation is a certification by named signatories, and nobody has
  signed. An empty one would be the document's own version of the
  `Signed-off-by` a model must not write.
- **The `Assisted-by` trailer is not yet in this repository's history.** The
  emitter measured 0 of 100 commits carrying one, against 23 carrying a
  `Co-Authored-By:` naming a model. The mechanism exists; the record starts from
  the next commit that uses it, and cannot be backfilled honestly.
