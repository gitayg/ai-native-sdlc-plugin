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
