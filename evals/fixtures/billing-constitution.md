# Billing — constitution

Product
: `billing`

Next principle id
: `P4`

## Principles

### P1 — A published contract is never changed in place
Active. Ratified 2026-01-05 by the API owners.

A field, endpoint, event shape or webhook payload published to anyone outside
this product's repos changes only by adding a new version alongside the old one.
Removing a field, renaming one, narrowing a type or changing the meaning of an
existing value is a new version, not an edit.

Prevents
: Breaking an integration we cannot see, cannot test and cannot roll back on the
caller's behalf.

Checked by
: The contract diff job in CI, which fails on any non-additive change to a
published schema.

Enforced by
: R6.

### P2 — Money never moves without an auditable authorisation record
Active. Ratified 2026-01-05 by the finance and platform owners.

Every charge, refund and adjustment resolves to a stored authorisation naming
who or what authorised it and when. A movement whose authorisation cannot be
produced is a movement that must not happen.

Prevents
: A charge nobody can account for at audit, which is indistinguishable from
fraud after the fact.

Checked by
: `test_every_movement_has_authorisation`.

Enforced by
: R1, R7.

### P3 — A closed account is never charged
Active. Ratified 2026-01-05 by the finance and platform owners.

Once a customer has closed their account, no further charge, retry, dunning
attempt or minimum-term recovery is applied to it. Outstanding balances are
pursued as receivables, never as new charges.

Prevents
: Charging people who believe they have left, which is the single most
expensive support and reputational failure this product has.

Checked by
: `test_no_charge_after_close`.

Enforced by
: R2.
