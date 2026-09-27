//! `amendment.rs`'s immediate-amendment path has no period-bounds check on `effective_date`.
//!
//! Companion to `proof/MeteroidVerify/AmendmentDateValidation.lean`. Confirmed against the real
//! source directly: `amendment_effective_date` (`services/subscriptions/amendment.rs:1140-1149`)
//! returns `Utc::now().naive_utc().date()` verbatim for the immediate case, with no check against
//! `current_period_start`/`current_period_end` before it reaches `calculate_proration`
//! (`:161`). `plan_change.rs::prepare_plan_change` (`:745-750`) has the exact contrasting guard:
//! `if change_date < period_start || change_date > period_end { return Err(...) }`. Traced the
//! downstream effect in `proration.rs`: `days_remaining = (period_end - change_date).num_days()`
//! (`:163`) goes negative when `change_date > period_end`, and `component_proration_factor`'s
//! ALIGNED branch (`:109`) returns `base_factor` unclamped, while the misaligned branch (`:111`)
//! explicitly `.clamp(0.0, 1.0)`s it — so an aligned component (the common case) silently turns a
//! credit into a charge when this precondition is violated.

use meteroid_pure_core::pure_core;

/// The aligned branch (`proration.rs:109`): `base_factor` passed through with no clamp.
#[pure_core]
pub fn prorated_amount_aligned(amount_cents: i64, factor: i64) -> i64 {
    amount_cents * factor
}

/// The misaligned branch (`proration.rs:111`): `base_factor.clamp(0.0, 1.0)` first.
#[pure_core]
pub fn prorated_amount_misaligned(amount_cents: i64, factor: i64) -> i64 {
    amount_cents * factor.clamp(0, 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aligned_branch_lets_a_negative_factor_through() {
        assert_eq!(prorated_amount_aligned(10000, -2), -20000);
    }

    #[test]
    fn misaligned_branch_clamps_the_same_negative_factor() {
        assert_eq!(prorated_amount_misaligned(10000, -2), 0);
    }

    #[test]
    fn amendment_rs_scenario_becomes_a_charge_instead_of_a_credit() {
        // Period [2025-01-01, 2025-02-01), effective_date 2025-02-15 (14 days past
        // period_end), a $100.00 aligned monthly component. days_remaining/days_in_period
        // scaled to an integer factor of -14 for this witness (real code uses f64).
        assert_eq!(prorated_amount_aligned(10000, -14), -140000);
    }
}
