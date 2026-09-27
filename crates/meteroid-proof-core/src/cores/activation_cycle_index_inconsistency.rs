/// Bug #22: Subscription activation cycle_index inconsistency
///
/// Two independent code paths (`activate_subscription_manual` and
/// `activate_subscription_after_payment`) set `cycle_index` differently for
/// the same business state (newly activated no-trial subscription in Active status).
///
/// - `activate_subscription_manual` (no trial): cycle_index = 1
/// - `activate_subscription_after_payment` (any, including no trial): cycle_index = 0
///
/// `cycle_index == 0` has special semantic meaning in `periods.rs` (line ~224-237):
/// it gates whether to compute proration_factor (if 0) vs None (if != 0),
/// and whether to compute None (if 0) vs arrear_period (if != 0).
///
/// Two identical subscriptions (Active status, RenewSubscription action) will
/// compute different billing-period proration factors depending on which
/// activation path handled them.
///
/// File: `subscriptions/activate.rs`, lines 60-115 (manual) vs 203-214 (payment)
/// Severity: Real — impacts first-cycle billing calculation

use meteroid_pure_core::pure_core;

#[pure_core]
pub fn activation_manual_no_trial_cycle_index() -> i32 {
    1
}

#[pure_core]
pub fn activation_payment_no_trial_cycle_index() -> i32 {
    0
}

/// cycle_index == 0 gates proration-vs-arrear logic
#[pure_core]
pub fn cycle_index_zero_gates_proration(idx: i32) -> bool {
    idx == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths_diverge_on_cycle_index_for_no_trial() {
        let manual = activation_manual_no_trial_cycle_index();
        let payment = activation_payment_no_trial_cycle_index();
        assert_ne!(manual, payment, "manual path sets 1, payment path sets 0");
    }

    #[test]
    fn paths_diverge_on_proration_gate() {
        let manual = activation_manual_no_trial_cycle_index();
        let payment = activation_payment_no_trial_cycle_index();

        let manual_gates_proration = cycle_index_zero_gates_proration(manual);
        let payment_gates_proration = cycle_index_zero_gates_proration(payment);

        assert_ne!(
            manual_gates_proration, payment_gates_proration,
            "manual path (idx=1) gates proration OFF, payment path (idx=0) gates it ON"
        );
    }

    #[test]
    fn bug_impacts_first_billing_cycle_proration() {
        // Manual path: no trial → cycle_index=1 → proration_gate=false
        let manual_idx = activation_manual_no_trial_cycle_index();
        assert_eq!(manual_idx, 1);
        assert!(!cycle_index_zero_gates_proration(manual_idx), "manual: proration gate is OFF");

        // Payment path: no trial → cycle_index=0 → proration_gate=true
        let payment_idx = activation_payment_no_trial_cycle_index();
        assert_eq!(payment_idx, 0);
        assert!(cycle_index_zero_gates_proration(payment_idx), "payment: proration gate is ON");

        // Same subscription state, different proration treatment
    }
}
