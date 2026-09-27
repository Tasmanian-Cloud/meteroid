/-!
# meteroid / PaymentReversal — `amount_refunded`'s clamp, closed for all four write paths

`RefundInvariant.lean` proves `newStatus` is `Refunded` exactly when
`new_amount_refunded >= amount`, but only under an ASSUMED clamp: "every
real branch clamps `new_amount_refunded` to `[0, amount]`" — stated, not
proved. This file proves it, against the actual formulas in
`repositories/payment_transactions.rs`'s `reverse_transaction_tx`
(`:283-420`) and `reinstate_transaction_tx` (`:460-555`), the only two
functions that ever write `amount_refunded`.

`reverse_transaction_tx`'s `Settled` branch (`:322-373`) computes
`new_amount_refunded` one of three ways, chosen by `ReversalAmount`:

- `Cumulative(total)` (`:329-347`, Stripe's running `charge.amount_refunded`):
  `total.clamp(0, amount).max(amount_refunded)`.
- `Full` (`:359-372`, a chargeback claiming the whole charge):
  `amount` (verbatim).
- `Incremental(delta)` (`:381-386`, a dispute delta stacking on a prior
  refund): `(amount_refunded + delta.max(0)).min(amount)`.

`reinstate_transaction_tx` (`:505-511`, money handed back after a dispute
is won) is the only path that ever DECREASES `amount_refunded`:
`amount_refunded - reinstated_amount.clamp(0, amount_refunded)`.

**What is modeled:** the four arithmetic formulas exactly as written, and
that each maps `[0, amount]`-valued `amount_refunded` to another
`[0, amount]`-valued result — an inductive invariant (true at the initial
value `0`, preserved by every subsequent write, therefore true always).
Not modeled: the redelivery/staleness guards around each branch
(`refunded_at` timestamp comparisons) — those decide WHETHER a write
happens, not what value it produces if it does; irrelevant to the clamp.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- `total.clamp(0, amount).max(amount_refunded)` (`:346-347`). -/
def cumulativeRefund (amount amountRefunded total : Int) : Int :=
  max (max 0 (min total amount)) amountRefunded

/-- `amount` verbatim (`:372`). -/
def fullRefund (amount : Int) : Int := amount

/-- `(amount_refunded + delta.max(0)).min(amount)` (`:386`). -/
def incrementalRefund (amount amountRefunded delta : Int) : Int :=
  min (amountRefunded + max delta 0) amount

/-- `amount_refunded - reinstated_amount.clamp(0, amount_refunded)` (`:505-511`). -/
def reinstateRefund (amountRefunded reinstatedAmount : Int) : Int :=
  amountRefunded - max 0 (min reinstatedAmount amountRefunded)

/-- `Cumulative`: given the invariant held before, it holds after. The
    `.max(amountRefunded)` term is exactly why `amountRefunded ≤ amount`
    must be a HYPOTHESIS, not derivable from `total`/`amount` alone — a
    prior write that ever broke the invariant would let this one propagate
    the break, which is precisely why this is an inductive proof, not a
    one-shot arithmetic fact. -/
theorem cumulativeRefund_clamped (amount amountRefunded total : Int)
    (hamt : 0 ≤ amount) (hlo : 0 ≤ amountRefunded) (hhi : amountRefunded ≤ amount) :
    0 ≤ cumulativeRefund amount amountRefunded total ∧
      cumulativeRefund amount amountRefunded total ≤ amount := by
  unfold cumulativeRefund
  omega

theorem fullRefund_clamped (amount : Int) (hamt : 0 ≤ amount) :
    0 ≤ fullRefund amount ∧ fullRefund amount ≤ amount := by
  unfold fullRefund
  omega

theorem incrementalRefund_clamped (amount amountRefunded delta : Int)
    (hamt : 0 ≤ amount) (hlo : 0 ≤ amountRefunded) :
    0 ≤ incrementalRefund amount amountRefunded delta ∧
      incrementalRefund amount amountRefunded delta ≤ amount := by
  unfold incrementalRefund
  omega

/-- Reinstatement never needs `amount` at all: it only ever hands back up to
    what was already refunded, so the result stays within
    `[0, amountRefunded] ⊆ [0, amount]` regardless of `amount`'s value. -/
theorem reinstateRefund_clamped (amountRefunded reinstatedAmount : Int)
    (hlo : 0 ≤ amountRefunded) :
    0 ≤ reinstateRefund amountRefunded reinstatedAmount ∧
      reinstateRefund amountRefunded reinstatedAmount ≤ amountRefunded := by
  unfold reinstateRefund
  omega

end MeteroidVerify
