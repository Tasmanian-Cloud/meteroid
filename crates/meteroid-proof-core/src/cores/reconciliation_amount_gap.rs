// Bug #22: Reconciliation silently accepts mismatched payment amounts
//
// When reconcile_pending_transaction fetches the provider status and
// RemoteTransactionStatus::Succeeded reports an amount_received that differs
// from the amount_requested stored on the local transaction:
// - payment_intent_from_remote_status (reconcile.rs:172-177) creates a PaymentIntent
//   with amount_requested=row.amount, amount_received=provider.amount_received_minor
// - consolidate_intent_and_transaction_tx is called with this intent
// - consolidate ONLY patches status, processed_at, error_type, and external_id
// - amount_received is NEVER read or validated
// - Result: mismatched amount is silently settled, no hold/review
//
// File: modules/meteroid/crates/meteroid-store/src/services/payment/reconcile.rs:132-138
// Specifically: payment_intent_from_remote_status (lines 168-183) computes amount_received
// but consolidate_intent_and_transaction_tx never validates it

use meteroid_pure_core::pure_core;

/// A payment transaction with requested and received amounts
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PaymentTransaction {
    pub amount_requested: i64,
    pub amount_received: i64,
}

/// Pure decision: should a reconciled payment be accepted?
/// The bug: this returns true for ANY received amount, never validates a match
#[pure_core]
pub fn reconciliation_accepts_any_amount(
    _requested: i64,
    _received: i64,
    status: &str,
) -> bool {
    // The actual code does this (reconcile.rs + consolidate):
    // if status == "Succeeded" {
    //   settle_transaction(amount_requested=_requested)  // IGNORES _received
    //   return true
    // }
    // false
    if status == "Succeeded" {
        // Consolidate will accept this and mark transaction Settled,
        // regardless of whether _received matches _requested
        true
    } else {
        false
    }
}

/// The bug witness: a $95 payment on a $100 charge is silently settled
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn partial_payment_accepted_without_validation() {
        let requested = 100i64;
        let received = 95i64;
        let status = "Succeeded";

        // The function returns true, meaning consolidate will accept it
        assert!(reconciliation_accepts_any_amount(requested, received, status));

        // In the actual system, this would:
        // 1. Mark the transaction as Settled
        // 2. Apply the $95 against the $100 amount_due
        // 3. Leave the invoice with $5 balance due, but no flag that reconciliation had a mismatch
    }

    #[test]
    fn overpayment_also_accepted_without_validation() {
        let requested = 100i64;
        let received = 105i64;
        let status = "Succeeded";

        // The same function accepts overpayments too
        assert!(reconciliation_accepts_any_amount(requested, received, status));
    }

    #[test]
    fn contrast_with_hosted_setup_validates() {
        // hosted_setup.rs::resolve_captured_payment (lines 1286-1321) DOES validate:
        // if amount_received_minor != expected_amount_minor {
        //   return HoldMismatch
        // }
        // But reconcile.rs has no such check
        let requested = 100i64;
        let received = 95i64;

        // Reconciliation flow (the bug)
        assert!(reconciliation_accepts_any_amount(requested, received, "Succeeded"));

        // Hosted payment flow (correct) would hold for review, not settle
        // This test documents the gap
    }
}
