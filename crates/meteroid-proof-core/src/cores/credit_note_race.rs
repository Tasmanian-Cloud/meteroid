//! Invoice lock acquired then discarded before the guard it exists to protect.
//!
//! Companion to `proof/MeteroidVerify/CreditNoteRace.lean`. Traced data flow,
//! `repositories/credit_notes.rs`:
//! - `:618` `create_user_credit_note_tx` reads the invoice with
//!   `find_detailed_by_id` (no lock).
//! - `:676` calls `create_credit_note_tx`, passing that same pre-lock invoice.
//! - `:789` `create_credit_note_tx` calls `InvoiceRow::select_for_update_by_id`
//!   (locks the row, returns a fresh `InvoiceLockRow`) but binds the result to
//!   `_invoice_lock` and never reads it again.
//! - `:1035-1038` the `DebtCancellation` guard checks
//!   `total > invoice.amount_due` against the pre-lock binding from `:618`,
//!   not the fresh post-lock row from `:789`.
//!
//! The lock serializes concurrent calls; it does nothing for a guard that
//! never re-reads what it just waited to lock.

use meteroid_pure_core::pure_core;

/// The `DebtCancellation` guard (`credit_notes.rs:1035`), verbatim.
#[pure_core]
pub fn debt_cancellation_allowed(amount_due: i64, total: i64) -> bool {
    total <= amount_due
}

/// Two `DebtCancellation` requests checked independently against the same
/// stale pre-lock `amount_due` snapshot — exactly what the real code does.
#[pure_core]
pub fn both_allowed(amount_due: i64, total1: i64, total2: i64) -> bool {
    debt_cancellation_allowed(amount_due, total1) && debt_cancellation_allowed(amount_due, total2)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_debt_cancellations_pass_the_guard_but_jointly_overshoot() {
        // An invoice with amount_due = 1000, and two concurrent
        // DebtCancellation requests of 700 each.
        let amount_due = 1000i64;
        let total1 = 700i64;
        let total2 = 700i64;

        assert!(both_allowed(amount_due, total1, total2));
        assert!(total1 + total2 > amount_due);
    }
}
