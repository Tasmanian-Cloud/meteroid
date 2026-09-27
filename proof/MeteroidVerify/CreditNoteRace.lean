/-!
# meteroid / CreditNoteRace — invoice lock acquired, then discarded, before the guard it exists to protect

`repositories/credit_notes.rs`'s `DebtCancellation` guard is a real TOCTOU bug,
confirmed by tracing the exact data flow, not inferred from the presence of a
lock call:

1. `create_user_credit_note_tx` (`:610-778`) reads the invoice with
   `InvoiceRow::find_detailed_by_id` (`:618`, **no lock**) and binds it to
   `invoice`.
2. It calls `create_credit_note_tx` (`:676`) passing that same `invoice`
   inside `CreateCreditNoteTxParams`.
3. `create_credit_note_tx` (`:778`) rebinds it at `:785`
   (`let invoice = params.invoice;`) — still the pre-lock value — then at
   `:789` calls `InvoiceRow::select_for_update_by_id`, which **does** lock the
   row and returns a fresh `InvoiceLockRow { invoice: InvoiceRow, .. }`
   (`diesel-models/src/invoices.rs:154-157`). This return value is bound to
   `_invoice_lock` and never read again.
4. The `DebtCancellation` guard at `:1035-1038` checks
   `total.unsigned_abs() as i64 > invoice.amount_due` — against the
   **pre-lock** binding from step 1/3, not the fresh, post-lock row the
   database just handed back at step 3.

The row lock genuinely serializes concurrent `create_credit_note_tx` calls
against the same invoice (confirmed: `select_for_update_by_id` blocks on
Postgres's row lock). But serialization only prevents *dirty writes* — it
does nothing for a guard that never re-reads the row it just waited to lock.
Two concurrent `DebtCancellation` credit notes against the same invoice each
carry their OWN pre-lock `amount_due` snapshot from their own outer read
(step 1), taken before either one queued on the lock. The second call to
unblock still validates against its own stale snapshot, not the first call's
committed effect — so the guard's "can't cancel more debt than is
outstanding" invariant does not hold across concurrent requests, even though
a lock is visibly present in the code.

This file models the guard's decision function exactly (`amountDue`,
`total ↦ total ≤ amountDue`) and exhibits a concrete two-request witness:
both individually pass the guard against the same starting `amountDue`, yet
their combined effect cancels more debt than the invoice ever had
outstanding. The witness is deliberately small and `decide`-checked, in the
same style as `ComponentMatching.lean`'s double-match example — this is not
a claim about Postgres's MVCC semantics in general, only about what this
specific guard does and does not check.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- The `DebtCancellation` guard (`credit_notes.rs:1035`), verbatim: reject
    iff the credit note's total exceeds the invoice's `amount_due` at the
    time of the check. -/
def debtCancellationAllowed (amountDue total : Int) : Bool :=
  total ≤ amountDue

/-- Running two `DebtCancellation` requests against the SAME stale
    `amountDue` snapshot (exactly what the real code does, per the module
    doc above): each is checked independently, neither sees the other's
    effect. -/
def bothAllowed (amountDue total1 total2 : Int) : Bool :=
  debtCancellationAllowed amountDue total1 && debtCancellationAllowed amountDue total2

/-- Concrete witness: an invoice with `amount_due = 1000`, and two
    `DebtCancellation` requests of 700 each. -/
def amountDueExample : Int := 1000
def total1Example : Int := 700
def total2Example : Int := 700

/-- Both requests individually pass the real guard against the shared
    pre-lock snapshot. -/
theorem both_pass_the_guard :
    bothAllowed amountDueExample total1Example total2Example = true := by decide

/-- Yet their combined effect (1400) exceeds the invoice's actual
    `amount_due` (1000) — the guard the lock exists to protect does not hold
    once both requests are allowed through. This is the formalized shape of
    the race: the lock serializes the two calls, but neither call's decision
    depends on the other, because neither re-reads `amount_due` after
    acquiring it. -/
theorem combined_effect_exceeds_amount_due :
    total1Example + total2Example > amountDueExample := by decide

/-- General statement: for ANY invoice and ANY pair of individually-valid
    requests, the guard alone gives no bound on their sum — it is possible
    to choose two requests that each pass yet jointly overshoot. Existence,
    not a universal claim: witnessed by the example above via `decide`,
    stated here as an explicit existential so the shape of the gap is
    machine-checked, not just illustrated. -/
theorem guard_gives_no_joint_bound :
    ∃ amountDue total1 total2 : Int,
      bothAllowed amountDue total1 total2 = true ∧ total1 + total2 > amountDue :=
  ⟨amountDueExample, total1Example, total2Example, both_pass_the_guard, combined_effect_exceeds_amount_due⟩

end MeteroidVerify
