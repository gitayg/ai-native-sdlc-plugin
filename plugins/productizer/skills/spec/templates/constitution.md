# <Product> — constitution

Product
: `<product-name>` — the same name `.claude/sdlc.json` declares. One
constitution per product, held in the spec home repo beside the living spec.
Two constitutions in one product means two answers to "is this allowed", and
the intent gets merged against whichever one the reader opened.

Constitution location
: `.claude/sdlc/constitution.md`. Beside `.claude/sdlc/spec.md`, inside
`.claude/` for the same reason: build tooling, static site generators, doc
builds and packaging all skip that directory, so the constitution is never
rendered as a page or shipped in a release.

Next principle id
: `P<n>` — allocate from here, then increment. Principles are numbered `P1`,
`P2`, … and requirements `R1`, `R2`, …. The two id spaces never share a
counter and never share a prefix: a plan, a test, a review finding or a PR
title citing `P2` must resolve to a principle and nothing else. One shared
counter makes that collision a matter of luck, and the collision is silent.

Principles
: `<n>` active, `<n>` superseded, `<n>` withdrawn.

Ratified by
: `<roles or names>` — the only people who may add, amend, supersede or
withdraw a principle.

Amendment
: Its own act, its own commit, ratified by the people named above. Never a side
effect of merging a feature. A principle relaxed inside the change that needed
it relaxed never constrained anything.

Audit trail
: `git log -p .claude/sdlc/constitution.md`. Amendments are also listed below,
because the reason for a change is not recoverable from its diff.

## How to read this file

A principle is a bound on the whole product. It holds for every requirement,
including the ones nobody has written yet. Requirements say what the system
does; principles say what it may never do, whatever it is doing.

- **A requirement must not contradict an active principle.** The check runs at
  intake, before the requirement is written — see `references/constitution.md`.
- **A requirement that contradicts a principle is automatically critical.** It
  is not routed to a human to pick a winner, the way two conflicting
  requirements are. The requirement gives way, or the principle is amended as
  its own act, by the ratifying authority, in its own commit.
- **Every principle carries a status marker** on the line under its heading,
  using the same vocabulary as the spec so nobody has to learn two:

  | Status | Meaning | Recorded as |
  |---|---|---|
  | Active | Currently binding | `Active.` plus the ratification date and who ratified it |
  | Superseded | Replaced by another principle | `Superseded by P9 <date>.` plus one line on why |
  | Withdrawn | The bound no longer applies | `Withdrawn <date>.` plus one line on why |

- **Nothing is ever deleted.** A superseded or withdrawn principle keeps its
  original text in place. Deleting it strands every requirement, review finding
  and design note that cites the id, and hides that the product once refused to
  do the thing it now does.
- **Amending in place keeps the id.** Making a principle clearer or wider
  without changing what it forbids is an edit in place, recorded below. Changing
  what it forbids allocates a new id and supersedes the old one — the same line
  the spec draws between refine and supersede.
- **Every principle names how it is checked.** A principle with no check is a
  slogan: it will be cited in review, argued about, and never enforced.

## What belongs here

Four tests, all of which must pass. The long form, with the failure each test
prevents, is in `references/constitution.md`.

1. **It binds every requirement**, not one trigger. If you can write it in EARS
   with a specific trigger and an observable response, it is a requirement.
2. **A violation is recognisable** by someone who has not read the rest of the
   spec. Name what breaking it looks like.
3. **Something checks it** — a test, a gate, a review pass, an architecture
   rule. Name it.
4. **It is short enough to be read.** Aim for three to eight principles. A
   constitution of forty is a second spec, and a second spec is read by nobody.

Values are not principles. "We care about quality" forbids nothing and so
refuses nothing.

## Principles

### P1 — Customer data never leaves the tenant boundary
Active. Ratified 2026-02-11 by the platform and security owners.

No request, export, report, log line, telemetry event, backup, or support tool
moves one tenant's data out of the tenant that owns it. Data derived from it —
counts, aggregates, embeddings, model inputs — is that tenant's data.

Prevents
: One customer's records surfacing in another customer's account, which is the
only failure in this product that cannot be fixed after the fact.

Checked by
: `test_tenant_isolation` on every data-access path, plus the review pass in
`REVIEW.md` for any change touching a query without a tenant predicate.

Enforced by
: R8, R29, R33.

### P2 — Every endpoint authenticates the caller before it does work
Active. Ratified 2026-02-11 by the platform and security owners.

Every route, queue consumer, scheduled job and internal RPC resolves a
principal first. There is no anonymous path, no allowlisted internal caller,
and no endpoint exempted because it is "read only" or "behind the VPN".

Prevents
: The gradual accumulation of unauthenticated internal endpoints, each
individually justified, which together are the flat network an attacker needs
after one foothold.

Checked by
: `test_all_routes_require_principal`, which enumerates the router and fails on
any route without an authentication decorator.

Enforced by
: R9, R11.

### P3 — A decision that cannot be made fails closed
Active. Ratified 2026-03-04 by the platform and security owners.

When an authorisation, policy or licence check cannot reach the service that
would answer it, the system denies. Timeouts, deploys, partial outages and cold
starts are all "cannot be made".

Prevents
: An outage in a control plane silently becoming an outage of the control
itself — the failure mode where availability work quietly removes a security
boundary.

Checked by
: `test_policy_service_unavailable_denies`, run with the policy service stubbed
to time out.

Enforced by
: R21, R22.

### P4 — A published contract is never changed in place
Active. Ratified 2026-03-04 by the API owners.
Amended 2026-06-18 — widened from public APIs to partner APIs and webhook
payloads, which are equally out of our control once published.

A field, endpoint, event shape or webhook payload that has been published to
anyone outside this product's repos changes only by adding a new version
alongside the old one. Removing a field, narrowing a type, or changing the
meaning of an existing value is a new version, not an edit.

Prevents
: Breaking an integration we cannot see, cannot test and cannot roll back on
the caller's behalf.

Checked by
: The contract diff job in CI, which fails on any non-additive change to a
published schema.

Enforced by
: R17, R38.

### P5 — All services run in a single region
Withdrawn 2026-05-02 — the product now serves EU tenants from an EU region.
The constraint that actually mattered was data residency, which P1 carries.

Every service, queue and datastore in this product runs in one region, so there
is one jurisdiction to reason about and one failure domain to test.

The statement stays; only the check and the enforcing requirements retire with
it. A withdrawn principle with its text removed is a heading nobody can
evaluate, and the next person to propose the same bound has nothing to read.

## Amendment record

Every amendment, supersession and withdrawal after ratification. A principle's
own ratification is recorded on the principle itself and not repeated here —
two records of one event drift, and the reader cannot tell which is stale.

Where the change was prompted by an intent that crossed the principle, name it.
That column is what makes a principle eroded one feature at a time visible as a
pattern, instead of spread across the feature PRs that each relaxed it.

| Date | Principle | Change | Prompted by | Why | Ratified by |
|---|---|---|---|---|---|
| 2026-06-18 | P4 | amended in place | #612 | widened to partner APIs; the original wording let partner-facing breakage through | <names> |
| 2026-05-02 | P5 | withdrawn | #588 | EU residency required a second region; P1 already carries the residency bound | <names> |

## Open questions

A principle under discussion is not binding and must not be cited as if it
were. Keep it here until it is ratified, so nobody enforces a draft and nobody
merges against one.

| # | Proposed principle | Raised by | Status |
|---|---|---|---|
| Q1 | <the bound being proposed> | <issue> | proposed / ratified as P<n> on <date> / rejected: <why> |
