// Bug #17: Migration mode free trial — period backwards when trial ends before effective billing start
//
// In services/subscriptions/insert/process.rs, when a subscription with a free trial is created
// in migration mode (skip_past_invoices=true), the code path at lines 344-349 computes:
//   effective_billing_start = billing_start_date + chrono::Duration::days(trial_days)
//
// Then at lines 373-378, if the subscription.end_date is in the past and before now, it calls:
//   find_period_containing_date(effective_billing_start, end_date, ...)
//
// But if end_date is during the trial (end_date < effective_billing_start), find_period_containing_date
// returns the first period at effective_billing_start (lines 187-200 in periods.rs).
//
// At lines 387-388, the subscription is then set up with:
//   current_period_start = last_period.start = effective_billing_start
//   current_period_end = Some(end_date)
//
// This creates a backwards period: [effective_billing_start, end_date] where
// effective_billing_start > end_date.
//
// Example:
// - billing_start_date = 1 (2024-01-01 as day number)
// - trial_days = 10
// - effective_billing_start = 11
// - subscription.end_date = 5 (2024-01-05, during trial)
// - Result: period [11, 5] (backwards!)

use meteroid_pure_core::pure_core;

/// Pure function: compute the period start when a migration-mode free trial
/// subscription ends during the trial period.
///
/// # Arguments
/// * `billing_start` - The subscription start day (as day number)
/// * `trial_days` - The free trial duration in days
/// * `end_date` - When the subscription ends (as day number)
///
/// # Returns
/// The computed period start (demonstrates the bug when >= end_date)
#[pure_core]
pub fn migration_trial_period_start_buggy(
    billing_start: i32,
    trial_days: i32,
    _end_date: i32,
) -> i32 {
    // This is what the code currently does (the bug)
    let effective_billing_start = billing_start + trial_days;
    // When end_date < effective_billing_start, the period computation
    // returns the period at effective_billing_start, not respecting that
    // end_date is actually earlier.
    effective_billing_start
}

/// Pure function: the corrected version that should be used instead.
///
/// When end_date is during the trial, we should use billing_start, not effective_billing_start.
#[pure_core]
pub fn migration_trial_period_start_correct(
    billing_start: i32,
    trial_days: i32,
    end_date: i32,
) -> i32 {
    let effective_billing_start = billing_start + trial_days;

    if end_date < effective_billing_start {
        // End date is during the trial — use billing_start
        billing_start
    } else {
        // End date is after trial — use effective_billing_start
        effective_billing_start
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_migration_trial_ends_during_creates_backwards_period() {
        // Day 1 = 2024-01-01, day 5 = 2024-01-05, day 11 = 2024-01-11
        let billing_start = 1i32;
        let trial_days = 10i32;
        let end_date = 5i32; // During trial

        let buggy_start = migration_trial_period_start_buggy(billing_start, trial_days, end_date);

        // The bug: period_start >= period_end (backwards)
        assert!(buggy_start >= end_date,
            "Bug witness: period_start {} >= period_end {}", buggy_start, end_date);
        assert_eq!(buggy_start, 11);
    }

    #[test]
    fn test_corrected_version_produces_valid_period() {
        let billing_start = 1i32;
        let trial_days = 10i32;
        let end_date = 5i32; // During trial

        let correct_start = migration_trial_period_start_correct(billing_start, trial_days, end_date);

        // Corrected version: period_start < period_end (valid)
        assert!(correct_start < end_date,
            "Correct version: period_start {} < period_end {}", correct_start, end_date);
        assert_eq!(correct_start, billing_start);
    }

    #[test]
    fn test_corrected_version_after_trial_still_uses_effective() {
        let billing_start = 1i32;
        let trial_days = 10i32;
        let end_date = 46i32; // After trial (day 46 = ~Feb 15, well after day 11 trial end)

        let correct_start = migration_trial_period_start_correct(billing_start, trial_days, end_date);

        // When end_date > trial, should use effective_billing_start
        let effective = billing_start + trial_days;
        assert_eq!(correct_start, effective);
    }

    #[test]
    fn test_concrete_date_numbers() {
        // Day 1 = Jan 1, day 11 = Jan 11, day 5 = Jan 5
        let billing_start = 1i32;
        let trial_days = 10i32;
        let end_date = 5i32;

        // Buggy version shows the issue clearly
        let buggy = migration_trial_period_start_buggy(billing_start, trial_days, end_date);
        assert_eq!(buggy, 11); // Period starts on day 11
        assert_eq!(end_date, 5); // But ends on day 5

        // Day 11 >= day 5, so period is backwards
        assert!(buggy >= end_date);
    }
}
