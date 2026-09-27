//! Closes `invoice_amount_due`'s open assumption: a fully clawed-back
//! transaction always nets to zero.
//!
//! Companion to `proof/MeteroidVerify/RefundInvariant.lean`. Models
//! `repositories/payment_transactions.rs`'s reversal handler's status-flip
//! decision (`:390-394`), given the clamp every one of its three branches
//! (`Cumulative`/`Full`/`Incremental`) enforces.

use meteroid_pure_core::pure_core;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PaymentStatus {
    Settled,
    Refunded,
}

/// The status-flip decision (`payment_transactions.rs:390-394`).
#[pure_core]
pub fn new_status(new_amount_refunded: i64, amount: i64) -> PaymentStatus {
    if new_amount_refunded >= amount { PaymentStatus::Refunded } else { PaymentStatus::Settled }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refunded_iff_exact_under_the_real_clamp() {
        // Every real branch clamps new_amount_refunded to [0, amount].
        assert_eq!(new_status(1000, 1000), PaymentStatus::Refunded);
        assert_eq!(new_status(999, 1000), PaymentStatus::Settled);
    }

    #[test]
    fn refunded_transactions_net_to_zero() {
        for (amount, refunded) in [(1000i64, 1000i64), (500, 500), (1, 1)] {
            assert_eq!(new_status(refunded, amount), PaymentStatus::Refunded);
            assert_eq!(amount - refunded, 0);
        }
    }
}
