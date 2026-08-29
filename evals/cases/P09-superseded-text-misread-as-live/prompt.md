---
name: P09-superseded-text-misread-as-live
tags: [positive, superseded, billing]
plugins: ["../../../plugins/productizer"]
runs: 3
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Run intake on the intent below for the `billing service`.

Everything this product has ever agreed is reproduced in full in this message.
There is no repository state for it: do not look for `.claude/productizer/`, do
not read or write any file outside the plugin you are running with, and do not
assume any requirement or principle that is not written below.

## Living spec

# Billing service — living spec

System
: `billing service` — the exact noun every requirement below uses. Never vary it.

Next requirement id
: `R11`

Requirements
: 9 active, 1 superseded, 0 withdrawn.

## Requirements

### Ubiquitous — always active

- **R1** — The billing service shall charge each subscriber exactly once per
  billing cycle.

### Event-driven

- **R2** — When a customer cancels their subscription, the billing service shall
  stop charging them at the end of the current cycle.
- **R4** — When a payment fails, the billing service shall retry the payment once
  every 24 hours for 3 days.
- **R6** — When an invoice is issued, the billing service shall publish an
  `invoice.issued` webhook carrying the field `amount_cents`.
- **R10** — When a customer downgrades their plan, the billing service shall
  apply the new price at the next cycle.

### State-driven

- **R5** — While an account is in arrears for more than 14 days, the billing
  service shall suspend the account.

### Unwanted behaviour

- **R3** — If a provider posts a settlement callback the billing service cannot
  verify, then the billing service shall reject it with 400.
  Superseded by R9. Ruled 2026-01-15: rejecting a callback the provider will not
  resend loses the settlement, so the callback is held instead of refused.
- **R7** — If a refund is requested more than 90 days after the charge, then the
  billing service shall decline the refund.
- **R9** — If a provider posts a settlement callback the billing service cannot
  verify, then the billing service shall queue it for retry and alert the
  on-call engineer.

### Optional

- **R8** — Where the tenant has enabled invoice consolidation, the billing
  service shall issue one invoice per calendar month instead of one per cycle.

## Acceptance criteria

| Requirement | Verified by | How |
|---|---|---|
| R1 | `test_one_charge_per_cycle` | two cycle runs produce two charges, not three |
| R2 | `test_cancel_stops_charging` | no charge after the cancelled cycle closes |
| R4 | `test_failed_payment_retries_3_days` | fixture clock yields exactly 3 retries |
| R5 | `test_arrears_suspends_at_15_days` | account suspended on day 15, active on day 14 |
| R6 | `test_invoice_webhook_shape` | payload validated against the published schema |
| R7 | `test_refund_declined_after_90_days` | day 91 refund declined, day 90 accepted |
| R8 | `test_consolidated_invoice_monthly` | one invoice for two cycles in a month |
| R9 | `test_unverifiable_callback_queued` | callback queued and an alert raised |
| R10 | `test_downgrade_applies_next_cycle` | old price on this cycle, new price on the next |

## Constitution

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

## Arriving intent

Providers are sitting on callbacks we never answer. Reject any settlement
callback we cannot verify with a 400 straight away, so the provider gets
immediate feedback instead of silence.

## What to produce

Classify this intent against the spec and the constitution above as exactly one
of **extend**, **refine**, **duplicate** or **contradict**. Cite every
requirement id (`R…`) and principle id (`P…`) that bears on the decision, state
what happens to the spec next, and say plainly what has and has not been merged.

End your reply with exactly this line, and nothing after it:

VERDICT: <EXTEND|REFINE|DUPLICATE|CONTRADICT>
