import MeteroidVerify.InvoiceAmountDue

/-!
# meteroid / RefundInvariant — closes `InvoiceAmountDue.lean`'s open assumption

`InvoiceAmountDue.lean` modeled `recompute_amount_due_from_settled_payments`'s
aggregation formula and flagged, as an open, undischarged assumption,
"whether the `Refunded` status transition and `amount_refunded` field are
kept consistent by whatever code sets them." Traced that code directly:
`repositories/payment_transactions.rs`'s reversal handler (`:329-394`)
clamps `new_amount_refunded` to `[0, transaction.amount]` in every one of
its three branches — `Cumulative` via `.clamp(0, transaction.amount)`
(`:346`), `Full` sets it to exactly `transaction.amount` (`:369`),
`Incremental` via `.min(transaction.amount)` (`:386`) — and sets `status =
Refunded` iff `new_amount_refunded >= transaction.amount` (`:390-394`),
which combined with the clamp means iff `new_amount_refunded ==
transaction.amount` exactly. **The assumption holds — this is a positive
result, not a bug.**

**The clamp itself was initially only traced by reading, not proved.**
`PaymentReversal.lean` closes that gap: `cumulativeRefund_clamped`,
`fullRefund_clamped`, `incrementalRefund_clamped` prove all three branches
(plus `reinstateRefund_clamped` for `reinstate_transaction_tx`, the fourth
and only decreasing write path) map an already-in-`[0, amount]` value to
another one — an inductive invariant, not a one-shot check, since
`Cumulative`'s `.max(amount_refunded)` term specifically depends on the
PRIOR value already being in range.

The function is also genuinely careful about idempotency (`refunded_at`
high-water-mark checks at `:358-368`/`:375-385` reject stale/redelivered
reversal events, and `:397-399` is an explicit no-op guard) — not modeled
here, since it's about event redelivery ordering, a different concern from
the arithmetic this file closes.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- Mirrors `PaymentStatusEnum::{Settled, Refunded}` for this narrow slice. -/
inductive PaymentStatus where
  | settled | refunded
deriving DecidableEq, Repr

/-- The status-flip decision (`payment_transactions.rs:390-394`). -/
def newStatus (newAmountRefunded amount : Int) : PaymentStatus :=
  if newAmountRefunded ≥ amount then .refunded else .settled

/-- Given the clamp every branch enforces (`0 ≤ new_amount_refunded ≤
    amount`), the status decision is exactly an equality test, not merely a
    `≥` one — the clamp is what turns `≥` into `=`. -/
theorem newStatus_refunded_iff_exact (newAmountRefunded amount : Int)
    (hlo : 0 ≤ newAmountRefunded) (hhi : newAmountRefunded ≤ amount) :
    newStatus newAmountRefunded amount = .refunded ↔ newAmountRefunded = amount := by
  unfold newStatus
  by_cases h : newAmountRefunded ≥ amount
  · simp [h]; omega
  · simp [h]; omega

/-- Closes `InvoiceAmountDue.lean`'s open assumption: whenever status
    becomes `Refunded` (under the real clamp), the transaction nets to
    exactly `0` in `settledSum`'s per-row contribution — so whether a fully
    clawed-back transaction is excluded from the query entirely (status
    flipped to `Refunded`) or counted via `amount - amount_refunded` (still
    `Settled`, fully refunded), both paths are provably equivalent AT the
    aggregation formula, not merely assumed to be. -/
theorem refunded_transactions_net_to_zero (amount newAmountRefunded : Int)
    (hlo : 0 ≤ newAmountRefunded) (hhi : newAmountRefunded ≤ amount)
    (h : newStatus newAmountRefunded amount = .refunded) :
    settledNet (amount, newAmountRefunded) = 0 := by
  have heq := (newStatus_refunded_iff_exact newAmountRefunded amount hlo hhi).mp h
  unfold settledNet
  omega

end MeteroidVerify
