/-!
# meteroid / InvoiceAmountDue — settled-payment recomputation is monotone and exact

`recompute_amount_due_from_settled_payments`
(`diesel-models/src/query/invoices.rs:663-732`) idempotently recomputes an
invoice's `amount_due` from current DB state: `max(0, total -
applied_credits - cancelled_sum - settled_sum)`, where `settled_sum` sums
`amount - amount_refunded` over payment-transaction rows already filtered to
`status = Settled, payment_type = Payment` (`:672-682`), and `cancelled_sum`
sums the absolute value of `Finalized`/`DebtCancellation` credit-note totals
(`:687-698`, stored negative in the DB).

"Migrations" was scoped as a priority and found not to be a real
formal-verification target as stated (raw SQL DDL isn't provable in this
style) — but the migration that added `PaymentStatusEnum::Refunded` and
`payment_transaction.amount_refunded` documented exactly this function as
the invariant it exists to support, which IS tractable: pure integer
arithmetic over already-filtered rows, no floats or strings in the formula
itself.

**What is modeled:** the aggregation formula, as a pure function of already-
filtered inputs — not the SQL `WHERE` filtering itself (that's a DB-level
concern, not an arithmetic one), and not whether the `Refunded` status
transition and `amount_refunded` field are kept consistent by whatever code
sets them (an open, undischarged assumption — flagged, not verified).

**`applied_credits` vs `cancelled_sum`, traced and closed:** these do NOT
double-count the same credit. Every write site of `invoice.applied_credits`
(`invoice_lines.rs:107-127,433-447,498-512`, `draft.rs`, `consolidate.rs`)
sets it once, at draft/finalize time, to
`min(total, customer_balance)` — a prepaid-account-balance mechanism applied
at invoice creation. `cancelled_sum` is summed fresh, every call, from
`Finalized`/`DebtCancellation` credit notes, which never write
`applied_credits` (`credit_notes.rs`'s `credited_amount_cents` — the field
that DOES feed `applied_credits` downstream, for `CreditToBalance` credit
notes — is hardcoded `0` for `CreditType::DebtCancellation`). The two
mechanisms are structurally disjoint columns/sources, not two views of one
number.

**A second, independently-written copy of this exact formula exists** in
`payment_transactions.rs`'s `exists_live_for_invoice`
(`:101-183`, guarding re-charge/merge/line-mutation on an invoice a
live payment still owns): `settled_net >= total - applied_credits -
cancelled_sum`. `existsLiveCheck` below models that inequality and
`exists_live_iff_amount_due_zero` proves it is exactly
`newAmountDue = 0` — the two independently-written checks in two different
files are provably the same condition, not just similarly named.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- Net contribution of one settled payment transaction: `amount -
    amount_refunded` (`invoices.rs:681`). -/
def settledNet (row : Int × Int) : Int := row.1 - row.2

/-- `settled_sum` (`invoices.rs:680-682`): summed over already-filtered
    (`Settled` status, `Payment` type) rows. -/
def settledSum (rows : List (Int × Int)) : Int := (rows.map settledNet).sum

/-- `new_amount_due` (`invoices.rs:715`). -/
def newAmountDue (total appliedCredits cancelledSum settled : Int) : Int :=
  max 0 (total - appliedCredits - cancelledSum - settled)

/-- Non-negativity — by construction, never drives an invoice into debt. -/
theorem newAmountDue_nonneg (total appliedCredits cancelledSum settled : Int) :
    0 ≤ newAmountDue total appliedCredits cancelledSum settled := by
  unfold newAmountDue
  omega

/-- Monotonicity: more net settled payment never *increases* `amount_due`.
    A sign-flip bug (e.g. `+ settled` instead of `- settled`, or crediting
    `amount_refunded` instead of debiting it) would break this immediately
    on any concrete pair of inputs — this is the property that would have
    caught it. -/
theorem newAmountDue_mono (total appliedCredits cancelledSum s1 s2 : Int) (h : s1 ≤ s2) :
    newAmountDue total appliedCredits cancelledSum s2 ≤
      newAmountDue total appliedCredits cancelledSum s1 := by
  unfold newAmountDue
  omega

/-- Exact-threshold characterization: the invoice reaches `amount_due = 0`
    exactly when net settled payments cover the remaining balance after
    credits and cancellations — not before (still owing) and not
    "overshooting into negative", matching the docstring's "idempotent,
    never driven negative" claim precisely rather than just non-negatively. -/
theorem newAmountDue_eq_zero_iff (total appliedCredits cancelledSum settled : Int) :
    newAmountDue total appliedCredits cancelledSum settled = 0 ↔
      total - appliedCredits - cancelledSum ≤ settled := by
  unfold newAmountDue
  omega

/-- A fully clawed-back transaction (`amount_refunded = amount`) contributes
    exactly `0` — matching the docstring's claim that it "drops out of the
    sum" whether it stays `Settled` with a full refund recorded, or its
    status flips to `Refunded` and the row is excluded from the query
    entirely: both paths are observationally equivalent AT THIS FORMULA,
    which is exactly why the docstring can make that claim without the two
    code paths needing to agree on anything beyond this. -/
theorem settledNet_full_refund_is_zero (amount : Int) :
    settledNet (amount, amount) = 0 := by
  unfold settledNet
  omega

/-- `exists_live_for_invoice`'s post-early-return check
    (`payment_transactions.rs:183`): the invoice is still owned by a live
    settled payment iff net settled amount covers what remains after credits
    and cancellations. -/
def existsLiveCheck (total appliedCredits cancelledSum settled : Int) : Bool :=
  decide (total - appliedCredits - cancelledSum ≤ settled)

/-- The two independently-implemented formulas agree exactly:
    `exists_live_for_invoice`'s guard is true iff
    `recompute_amount_due_from_settled_payments` would compute `amount_due =
    0`. Neither file's code references the other; this is a genuine
    cross-file consistency result, not a restatement of one definition. -/
theorem exists_live_iff_amount_due_zero (total appliedCredits cancelledSum settled : Int) :
    existsLiveCheck total appliedCredits cancelledSum settled = true ↔
      newAmountDue total appliedCredits cancelledSum settled = 0 := by
  rw [newAmountDue_eq_zero_iff]
  unfold existsLiveCheck
  simp

end MeteroidVerify
