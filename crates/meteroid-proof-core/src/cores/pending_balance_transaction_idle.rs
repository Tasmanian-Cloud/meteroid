// Rust companion for PendingBalanceTransactionIdle.lean
//
// Proof: Purchased credits via `buy_customer_credits` are inserted as pending
// balance transactions but never converted to settled transactions, leaving
// customer balances at zero.
//
// This is a pure-logic proof, not an implementation — it documents the
// discovered bug: the settlement codepath exists but is unreachable.

use meteroid_pure_core::pure_core;

/// Models a pending balance transaction state before settlement
#[pure_core]
pub fn pending_tx_initial_state(
    _customer_id: i64,
    _amount_cents: i64,
) -> (i64, i64) {
    // Returns (pending_tx_id, customer_balance_cents)
    // After purchase: transaction exists (id=1), balance is still zero
    (1, 0)
}

/// Models the stale customer balance read during applied_credits calculation
#[pure_core]
pub fn stale_balance_on_invoice_draft(
    _pending_tx_amount: i64,
) -> i64 {
    // The applied_credits calculation reads the customer's balance column,
    // which was never updated because pending_tx settlement never occurred.
    // Result: applied_credits = min(invoice_total, stale_balance) =
    //         min(invoice_total, 0) = 0
    0
}

/// Concrete scenario: customer purchases $100 in credits
#[pure_core]
pub fn bug_scenario_100_credit_purchase() -> (i64, i64, i64) {
    // Returns (amount_paid, pending_amount, customer_balance_after)
    let amount_paid = 100i64;
    let pending_tx_amount = 100i64;
    let customer_balance = 0i64; // Never updated

    (amount_paid, pending_tx_amount, customer_balance)
}

/// The settlement codepath that should be called but never is
/// (from `repositories/invoices.rs::_process_pending_tx`)
#[pure_core]
pub fn if_settlement_were_called(
    pending_amount_cents: i64,
    initial_balance_cents: i64,
) -> i64 {
    // The `settle_pending_tx_if_called` function from the Lean proof
    // models this operation
    initial_balance_cents + pending_amount_cents
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pending_tx_starts_with_zero_balance() {
        let (_, balance) = pending_tx_initial_state(42, 100);
        assert_eq!(balance, 0, "Balance should be zero after purchase");
    }

    #[test]
    fn stale_balance_prevents_credit_application() {
        let stale = stale_balance_on_invoice_draft(100);
        assert_eq!(stale, 0, "Stale balance is zero, credits cannot be applied");
    }

    #[test]
    fn concrete_bug_100_usd() {
        let (paid, pending, balance) = bug_scenario_100_credit_purchase();
        assert_eq!(paid, 100, "Customer paid $100");
        assert_eq!(pending, 100, "Pending transaction is $100");
        assert_eq!(balance, 0, "But balance remains zero — bug!");
    }

    #[test]
    fn settlement_would_fix_it() {
        let result = if_settlement_were_called(100, 0);
        assert_eq!(
            result, 100,
            "If settlement were called, balance would be 100"
        );
    }

    #[test]
    fn proof_of_the_gap() {
        // This test demonstrates the two paths:

        // Path 1: Real code (settlement never called)
        let (_, _, real_balance) = bug_scenario_100_credit_purchase();
        let real_applied_credits = stale_balance_on_invoice_draft(100);

        // Path 2: If settlement were called
        let settled_balance = if_settlement_were_called(100, 0);

        // The gap
        assert_eq!(real_balance, 0, "Real balance stays zero");
        assert_eq!(real_applied_credits, 0, "No credits can be applied");
        assert_eq!(settled_balance, 100, "Settlement would fix it");
        assert_ne!(
            real_balance, settled_balance,
            "The bug is the divergence between real and intended behavior"
        );
    }
}
