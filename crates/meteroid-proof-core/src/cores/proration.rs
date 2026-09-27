//! Proration factor asymmetry, and the exact-ratio conservation bound.
//!
//! Companion to `proof/MeteroidVerify/Proration.lean`. Path B (native Lean,
//! not Aeneas-extracted — see that file's module doc and
//! `proof/RESEARCH.md` for the real extraction attempt and why it failed:
//! Aeneas has no float support).

use meteroid_pure_core::pure_core;

#[derive(Copy, Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BillingPeriod {
    Monthly,
    Quarterly,
    Semiannual,
    Annual,
    OneTime,
}

/// Verbatim (`proration.rs:78-86`).
#[pure_core]
pub fn nominal_period_days(period: BillingPeriod) -> i64 {
    match period {
        BillingPeriod::Monthly => 30,
        BillingPeriod::Quarterly => 91,
        BillingPeriod::Semiannual => 182,
        BillingPeriod::Annual => 365,
        BillingPeriod::OneTime => 0,
    }
}

/// The real `(days_in_period - nominal).abs() <= nominal * 0.25` comparison
/// (`proration.rs:108`), scaled ×4 — exact for all four real nominal values.
#[pure_core]
pub fn is_aligned(days_in_period: i64, nominal: i64) -> bool {
    4 * (days_in_period - nominal).abs() <= nominal.abs()
}

/// `component_proration_factor` (`proration.rs:96-113`), mirrored exactly —
/// including the asymmetry `proof/MeteroidVerify/Proration.lean` formalizes:
/// the aligned branch returns `base_factor` unclamped.
#[pure_core]
pub fn component_proration_factor(period: BillingPeriod, days_in_period: i64, base_factor: i64) -> i64 {
    let nominal = nominal_period_days(period);
    if nominal <= 0 {
        base_factor
    } else if is_aligned(days_in_period, nominal) {
        base_factor
    } else {
        base_factor.clamp(0, 1)
    }
}

/// The exact-ratio conservation bound
/// (`proof/MeteroidVerify/Proration.lean`'s
/// `prorated_product_never_exceeds_full_period_product`): given a valid
/// factor `0 <= p <= q` and a non-negative amount, the unrounded prorated
/// product never falls outside `[0, amount*q]`.
#[pure_core]
pub fn prorated_product_bound_holds(amount_cents: i64, p: i64, q: i64) -> bool {
    0 <= amount_cents * p && amount_cents * p <= amount_cents * q
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aligned_branch_can_escape_unit_interval() {
        assert_eq!(component_proration_factor(BillingPeriod::Monthly, 30, 2), 2);
    }

    #[test]
    fn misaligned_branch_clamps_out_of_range_factor() {
        assert_eq!(component_proration_factor(BillingPeriod::Monthly, 1000, 2), 1);
    }

    #[test]
    fn prorated_product_never_exceeds_full_period_product() {
        // Real test_simple_upgrade_half_period (proration.rs:417-450): 15/30, 10000 cents.
        assert!(prorated_product_bound_holds(10000, 15, 30));
    }

    /// Cross-check against `vectors/proration_tax.json`.
    #[test]
    fn matches_shared_vectors() {
        #[derive(serde::Deserialize)]
        struct FactorCase {
            period: BillingPeriod,
            days_in_period: i64,
            base_factor: i64,
            expect: i64,
        }
        #[derive(serde::Deserialize)]
        struct Vectors {
            factor_cases: Vec<FactorCase>,
        }
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../vectors/proration_tax.json");
        let data = std::fs::read_to_string(path).expect("read vectors/proration_tax.json");
        let vectors: Vectors = serde_json::from_str(&data).expect("parse vectors/proration_tax.json");
        for case in vectors.factor_cases {
            assert_eq!(
                component_proration_factor(case.period, case.days_in_period, case.base_factor),
                case.expect
            );
        }
    }
}
