//! `amount_refunded`'s clamp, closed for all four write paths.
//!
//! Companion to `proof/MeteroidVerify/PaymentReversal.lean`. Closes
//! `RefundInvariant.lean`'s previously-ASSUMED "every real branch clamps
//! new_amount_refunded to [0, amount]" against the actual formulas in
//! `repositories/payment_transactions.rs`'s `reverse_transaction_tx`
//! (`:283-420`) and `reinstate_transaction_tx` (`:460-555`).

use meteroid_pure_core::pure_core;

/// `total.clamp(0, amount).max(amount_refunded)` (`:346-347`).
#[pure_core]
pub fn cumulative_refund(amount: i64, amount_refunded: i64, total: i64) -> i64 {
    total.clamp(0, amount).max(amount_refunded)
}

/// `amount` verbatim (`:372`).
#[pure_core]
pub fn full_refund(amount: i64) -> i64 {
    amount
}

/// `(amount_refunded + delta.max(0)).min(amount)` (`:386`).
#[pure_core]
pub fn incremental_refund(amount: i64, amount_refunded: i64, delta: i64) -> i64 {
    (amount_refunded + delta.max(0)).min(amount)
}

/// `amount_refunded - reinstated_amount.clamp(0, amount_refunded)` (`:505-511`).
#[pure_core]
pub fn reinstate_refund(amount_refunded: i64, reinstated_amount: i64) -> i64 {
    amount_refunded - reinstated_amount.clamp(0, amount_refunded)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_four_paths_stay_within_amount() {
        let amount = 1000i64;
        let amount_refunded = 400i64;

        assert!((0..=amount).contains(&cumulative_refund(amount, amount_refunded, 700)));
        assert!((0..=amount).contains(&cumulative_refund(amount, amount_refunded, -50))); // clamps to 0 first
        assert!((0..=amount).contains(&cumulative_refund(amount, amount_refunded, 5000))); // clamps to amount

        assert_eq!(full_refund(amount), amount);

        assert!((0..=amount).contains(&incremental_refund(amount, amount_refunded, 300)));
        assert!((0..=amount).contains(&incremental_refund(amount, amount_refunded, 5000))); // min clamps

        assert!((0..=amount_refunded).contains(&reinstate_refund(amount_refunded, 250)));
        assert!((0..=amount_refunded).contains(&reinstate_refund(amount_refunded, 5000))); // clamps to amount_refunded
    }
}
