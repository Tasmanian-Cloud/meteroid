use meteroid_pure_core::pure_core;

/// Demonstrates the display asymmetry in `scale_fee` for OneTime add-on fees.
///
/// When `scale_fee(OneTime { rate, quantity }, add_on_qty)` is computed,
/// the result has `quantity = inner_qty * add_on_qty` (total scaled).
/// But when extracting for display in proration, the OneTime case extracts
/// this total from the fee, while other types use the separate `instance_quantity`
/// field from AddedComponent.
///
/// This causes a display mismatch: OneTime shows "total_qty × unit_rate"
/// instead of "instance_qty × per_instance_rate", despite the actual charge
/// being correct.
///
/// **Real code citation**:
/// - `modules/meteroid/crates/meteroid-store/src/services/subscriptions/utils.rs:128-174` — scale_fee
/// - `modules/meteroid/crates/meteroid-store/src/services/subscriptions/proration.rs:265-284` — OneTime handling in calculate_proration (line 275: quantity extracted from fee)
/// - `modules/meteroid/crates/meteroid-store/src/services/subscriptions/proration.rs:287-319` — Other types using instance_quantity field (line 301-303)
/// - `modules/meteroid/crates/meteroid-store/src/domain/subscription_changes.rs:103-107` — AddedComponent::instance_quantity docstring
#[pure_core]
pub fn onetime_display_asymmetry(
    inner_qty: i64,
    rate: i64,
    add_on_qty: i64,
) -> (i64, i64, i64) {
    // The amount is always correct
    let amount_cents = rate * inner_qty * add_on_qty;

    // For display, the OneTime case extracts from the scaled fee
    let scaled_qty_from_fee = inner_qty * add_on_qty;
    let _unit_price_from_fee = rate;

    // But AddedComponent carries the add-on instance count separately
    let instance_qty = add_on_qty;

    // Both should yield the same amount when multiplied:
    // scaled_qty_from_fee × unit_price_from_fee = amount_cents
    // instance_qty × (unit_price_from_fee × inner_qty) = amount_cents
    // But the display strings would differ:
    // - OneTime: "{scaled_qty_from_fee} × ${unit_price_from_fee}"
    // - Expected: "{instance_qty} × ${unit_price_from_fee * inner_qty}"

    (amount_cents, scaled_qty_from_fee, instance_qty)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_amount_is_correct_despite_display_asymmetry() {
        let (amount, _, _) = onetime_display_asymmetry(2, 10, 3);
        // 2 licenses × $10/license × 3 instances = 60 (in cents, or 2*10*3=60)
        assert_eq!(amount, 60);
    }

    #[test]
    fn test_display_shows_total_not_instances() {
        let inner_qty = 2;
        let rate = 10;
        let add_on_qty = 3;

        let (amount, scaled_qty_from_fee, instance_qty) =
            onetime_display_asymmetry(inner_qty, rate, add_on_qty);

        // The amount is correct (rate * inner_qty * add_on_qty = 10 * 2 * 3 = 60)
        assert_eq!(amount, 60);

        // But displayed as: 6 × $10 (total licenses × rate/license)
        assert_eq!(scaled_qty_from_fee, 6);
        assert_eq!(scaled_qty_from_fee, inner_qty * add_on_qty);

        // Not as: 3 × $20 (instances × rate/instance)
        assert_eq!(instance_qty, 3);
        assert_ne!(scaled_qty_from_fee, instance_qty);

        // Both formulations give the same amount:
        assert_eq!(scaled_qty_from_fee * rate, amount);
        assert_eq!(instance_qty * (rate * inner_qty), amount);
    }

    #[test]
    fn test_witness_3_instances_2_qty_10_rate() {
        // Test witness from Lean: 3 add-on instances, 2 licenses per instance, $10/license
        let (amount, extracted_from_fee, addon_instances) = onetime_display_asymmetry(2, 10, 3);

        // Amount is 2 * 10 * 3 = 60 (unit-agnostic, typically cents in real code)
        assert_eq!(amount, 60);

        // But display extracts 2 * 3 = 6 from the scaled fee
        assert_eq!(extracted_from_fee, 6);

        // While addon_instances is 3
        assert_eq!(addon_instances, 3);

        // Display would show 6 × $10 instead of 3 × $20
        assert_eq!(extracted_from_fee * 10, 60);
        assert_eq!(addon_instances * 20, 60);
    }
}
