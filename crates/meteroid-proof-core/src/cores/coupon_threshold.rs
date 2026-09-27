//! The coupon-loop early-break threshold fires one subunit too early.
//!
//! Companion to `proof/MeteroidVerify/CouponThreshold.lean`. Models only
//! `calculate_coupons_discount`'s break-then-apply ordering
//! (`services/invoice_lines/discount.rs:89-116`), not the surrounding
//! `Decimal` percentage/fixed-amount computation.

use meteroid_pure_core::pure_core;

/// One loop iteration's real structure (`discount.rs:89-116`).
#[pure_core]
pub fn process_one_coupon(remaining: i64, discount: i64) -> Option<i64> {
    if remaining <= 1 { None } else { Some(remaining - discount) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subtotal_one_never_discounted() {
        // A 100%-off coupon on a 1-subunit subtotal never applies.
        assert_eq!(process_one_coupon(1, 1), None);
    }

    #[test]
    fn subtotal_two_fully_discounted() {
        // The identical coupon on 2 subunits applies normally.
        assert_eq!(process_one_coupon(2, 2), Some(0));
    }
}
