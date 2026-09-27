use meteroid_pure_core::pure_core;

/// Models the fixed-amount coupon discount bug: when consumed_amount > amount,
/// the resulting discount is negative, which when subtracted from the subtotal
/// actually increases it (the opposite of the intended discount).
///
/// The bug: `discount.rs:110-114` computes `amount - consumed_amount` without
/// clamping to non-negative. If consumed_amount > amount, the discount is negative.
/// When min(negative_discount, positive_subtotal) is taken, the min is the negative value.
/// Subtracting a negative value increases the subtotal — wrong!
///
/// The fix: clamp the remaining amount to [0, ∞) before conversion:
/// ```ignore
/// let remaining_amount = (amount - consumed_amount).max(Decimal::ZERO);
/// let discount_subunits = remaining_amount
///     .to_subunit_opt(cur.exponent as u8)
///     .unwrap_or(0);
/// ```
#[pure_core]
pub fn coupon_fixed_amount_negative_bug(
    amount_subunits: i64,
    consumed_subunits: i64,
    subtotal_subunits: i64,
) -> bool {
    // The bug: unclamped discount calculation
    let unclamped_discount = amount_subunits - consumed_subunits;
    let applied_discount = std::cmp::min(unclamped_discount, subtotal_subunits);

    // When consumed > amount, the unclamped discount is negative.
    // If subtotal is positive, min(negative, positive) = negative.
    // Subtracting a negative increases the subtotal.
    let new_subtotal = subtotal_subunits - applied_discount;

    // The bug is present if subtotal increased (new_subtotal > original_subtotal)
    new_subtotal > subtotal_subunits
}

/// The correct version: clamp the remaining amount to non-negative.
#[pure_core]
pub fn coupon_fixed_amount_correct(
    amount_subunits: i64,
    consumed_subunits: i64,
    subtotal_subunits: i64,
) -> i64 {
    // The fix: clamp to [0, ∞)
    let remaining_amount = std::cmp::max(amount_subunits - consumed_subunits, 0);
    let applied_discount = std::cmp::min(remaining_amount, subtotal_subunits);
    subtotal_subunits - applied_discount
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn negative_consumed_amount_increases_subtotal_bug() {
        // Bug scenario: consumed_amount (50) > amount (30)
        let amount_subunits = 3000;      // 30 dollars
        let consumed_subunits = 5000;    // 50 dollars already consumed
        let subtotal_subunits = 10_000;  // 100 dollars subtotal

        // The bug should trigger
        assert!(coupon_fixed_amount_negative_bug(
            amount_subunits,
            consumed_subunits,
            subtotal_subunits
        ));

        // Trace the bug:
        // unclamped_discount = 3000 - 5000 = -2000 (negative!)
        // applied_discount = min(-2000, 10_000) = -2000
        // new_subtotal = 10_000 - (-2000) = 10_000 + 2000 = 12_000 (increased!)
    }

    #[test]
    fn normal_case_discount_decreases_subtotal() {
        // Normal case: consumed_amount < amount
        let amount_subunits = 10_000;    // 100 dollars
        let consumed_subunits = 3000;    // 30 dollars already consumed
        let subtotal_subunits = 50_000;  // 500 dollars subtotal

        // Bug should NOT trigger in normal case
        assert!(!coupon_fixed_amount_negative_bug(
            amount_subunits,
            consumed_subunits,
            subtotal_subunits
        ));
    }

    #[test]
    fn correct_version_never_increases_subtotal() {
        // Even with consumed > amount, the correct version should never increase subtotal
        let amount_subunits = 3000;
        let consumed_subunits = 5000;
        let subtotal_subunits = 10_000;

        let new_subtotal = coupon_fixed_amount_correct(
            amount_subunits,
            consumed_subunits,
            subtotal_subunits,
        );

        // Corrected calculation:
        // remaining_amount = max(3000 - 5000, 0) = max(-2000, 0) = 0
        // applied_discount = min(0, 10_000) = 0
        // new_subtotal = 10_000 - 0 = 10_000 (unchanged, not increased)
        assert_eq!(new_subtotal, subtotal_subunits);
    }

    #[test]
    fn correct_version_applies_valid_remaining() {
        // Normal case: both functions agree
        let amount_subunits = 10_000;
        let consumed_subunits = 3000;
        let subtotal_subunits = 50_000;

        let new_subtotal = coupon_fixed_amount_correct(
            amount_subunits,
            consumed_subunits,
            subtotal_subunits,
        );

        // remaining_amount = max(10_000 - 3000, 0) = 7000
        // applied_discount = min(7000, 50_000) = 7000
        // new_subtotal = 50_000 - 7000 = 43_000
        assert_eq!(new_subtotal, 43_000);
    }
}
