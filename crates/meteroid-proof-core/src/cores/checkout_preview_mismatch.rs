// Checkout Preview vs Completion Amount Mismatch (Bug #19)
//
// The self-serve checkout flow computes the preview amount using virtual
// subscription details, validates it against client confirmation (with 1-cent
// tolerance), then creates the subscription and bills it using FRESH data from
// the database. If data changed between preview and billing, the customer is
// charged an unexpected amount.
//
// Code locations:
// - Preview compute: edge.rs:2158 compute_invoice(virtual_subscription)
// - Preview validate: edge.rs:2220 |amount_preview - confirmation| <= 1
// - Subscription create: edge.rs:2273 insert_subscription_tx(...)
// - Fresh billing: bill.rs:120 get_subscription_details_with_conn (fresh from DB)
// - Actual compute: draft.rs:137 compute_invoice(fresh_subscription)
// - Final validate: bill.rs:219 |amount_actual - confirmation| == 0 (exact match)
//
// BUG: There is NO re-validation with tolerance between the preview and the
// fresh billing computation. If subscription data changed (coupon state, pricing,
// customer balance, etc.), the customer is charged without confirmation of the
// new amount.

use meteroid_pure_core::pure_core;

#[pure_core]
pub fn checkout_preview_validation_passes(
    shown_amount_cents: i64,
    confirmed_amount_cents: i64,
) -> bool {
    // Edge.rs line 2220-2226: |amount_preview - confirmation| <= 1
    (shown_amount_cents - confirmed_amount_cents).abs() <= 1
}

#[pure_core]
pub fn checkout_billing_validation_passes(
    actual_amount_cents: i64,
    confirmed_amount_cents: i64,
) -> bool {
    // Bill.rs line 219: amount_actual == confirmation (exact match, no tolerance)
    actual_amount_cents == confirmed_amount_cents
}

#[pure_core]
pub fn mismatch_possible(
    shown_amount_cents: i64,
    confirmed_amount_cents: i64,
    actual_charge_cents: i64,
) -> bool {
    // It's possible to have:
    // - Preview validation passes: |shown - confirmed| <= 1
    // - Billing fails: actual != confirmed
    // - Customer sees disputed charge
    checkout_preview_validation_passes(shown_amount_cents, confirmed_amount_cents)
        && !checkout_billing_validation_passes(actual_charge_cents, confirmed_amount_cents)
        && actual_charge_cents != shown_amount_cents
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preview_validation_exact_match() {
        assert!(checkout_preview_validation_passes(10000, 10000));
    }

    #[test]
    fn preview_validation_one_cent_tolerance() {
        assert!(checkout_preview_validation_passes(10000, 10001));
        assert!(checkout_preview_validation_passes(10001, 10000));
    }

    #[test]
    fn preview_validation_rejects_two_cent_difference() {
        assert!(!checkout_preview_validation_passes(10000, 10002));
    }

    #[test]
    fn billing_validation_requires_exact_match() {
        assert!(checkout_billing_validation_passes(10000, 10000));
        assert!(!checkout_billing_validation_passes(10000, 10001));
        assert!(!checkout_billing_validation_passes(10001, 10000));
    }

    #[test]
    fn bug_scenario_witnessed() {
        // Customer sees $100.00, confirms it
        let shown = 10000;
        let confirmed = 10000;
        // But billing computes $120.00 (e.g., due to data change)
        let actual = 12000;

        // Preview validation passes
        assert!(checkout_preview_validation_passes(shown, confirmed));

        // But billing validation fails
        assert!(!checkout_billing_validation_passes(actual, confirmed));

        // And the bug scenario is real
        assert!(mismatch_possible(shown, confirmed, actual));
    }
}
