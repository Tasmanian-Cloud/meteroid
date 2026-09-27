//! Round-half-away-from-zero over an exact integer ratio.
//!
//! Companion to `proof/MeteroidVerify/TaxRounding.lean`. Path B (native
//! Lean) — `rust_decimal::Decimal` has no Aeneas builtin, so the real
//! `determine_tax_details` (`meteroid-tax/src/shared.rs:56-242`) was not a
//! Charon extraction candidate (`proof/RESEARCH.md`).
//!
//! This same rounding rule is also the codebase's single canonical
//! money-to-subunit conversion: `common-utils/src/decimals.rs:9-14`'s
//! `ToSubunit::to_subunit_opt` (`Decimal * 10^precision`, then
//! `round_dp_with_strategy(0, MidpointAwayFromZero)`) is used at every real
//! pricing/proration/billing site in the codebase (`fees.rs`, `proration.rs`,
//! `discount.rs`, `credit_notes.rs`, `slots.rs`, `component.rs`,
//! `amendment.rs`, checkout, manual payments — ~30 call sites). Because
//! `Decimal` is exact fixed-point (mantissa + scale, no binary
//! floating-point approximation), `to_subunit_opt` on a non-negative,
//! already-exact `Decimal` is losslessly `round_half_away_from_zero(mantissa
//! * 10^precision, 10^scale)` — the SAME function already proved here, not
//! a hand-copied model of it. `matches_real_to_subunit_opt` below cross-checks
//! against the real trait implementation directly, not a re-description of
//! it. This says nothing about whether an upstream `Decimal` value is itself
//! exact (the tax-rate `f64→Decimal` seam is a separate, already-documented
//! gap, `RESEARCH.md`) — only that once it is, this rounding step is exact.

use meteroid_pure_core::pure_core;

/// Matches `RoundingStrategy::MidpointAwayFromZero` for a non-negative ratio.
#[pure_core]
pub fn round_half_away_from_zero(numerator: i64, denominator: i64) -> i64 {
    (2 * numerator + denominator) / (2 * denominator)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_meteroid_tax_test_rounding_behavior() {
        // meteroid-tax/src/tests.rs's test_rounding_behavior.
        assert_eq!(round_half_away_from_zero(999 * 21, 100), 210);
        assert_eq!(round_half_away_from_zero(997 * 21, 100), 209);
    }

    #[test]
    fn midpoint_rounds_away_from_zero_not_to_even() {
        assert_eq!(round_half_away_from_zero(2505 * 10, 100), 251);
    }

    /// Cross-checks the proved model directly against the real
    /// `ToSubunit::to_subunit_opt` trait implementation
    /// (`common-utils/src/decimals.rs:9-14`), the codebase's actual
    /// money-to-subunit conversion used at ~30 pricing/proration/billing
    /// call sites — not a re-description of it. Non-negative, small-scale
    /// values only: `round_half_away_from_zero`'s doc-comment scopes it to
    /// non-negative ratios, and small mantissas avoid any i64 overflow in
    /// this test's own `mantissa * 10^precision` cross-check arithmetic
    /// (the real trait impl has no such restriction — a separate concern
    /// from what this test establishes).
    #[test]
    fn matches_real_to_subunit_opt() {
        use common_utils::decimals::ToSubunit;
        use rust_decimal::Decimal;

        // (mantissa, scale, precision)
        let cases: &[(i64, u32, u8)] = &[
            (999 * 21, 2, 2),   // 9.99 * 21 style rate, precision 2 (cents)
            (2505, 3, 2),       // 2.505 -> 250.5 cents, midpoint away from zero
            (100, 0, 2),        // exact integer amount, precision 2
            (12345, 4, 0),      // 1.2345, rounded to whole units
            (0, 0, 2),          // zero
        ];
        for &(mantissa, scale, precision) in cases {
            let d = Decimal::new(mantissa, scale);
            let real = d.to_subunit_opt(precision).expect("real to_subunit_opt");
            let modeled = round_half_away_from_zero(
                mantissa * 10i64.pow(u32::from(precision)),
                10i64.pow(scale),
            );
            assert_eq!(real, modeled, "mantissa={mantissa} scale={scale} precision={precision}");
        }
    }

    /// Cross-check against `vectors/proration_tax.json`.
    #[test]
    fn matches_shared_vectors() {
        #[derive(serde::Deserialize)]
        struct TaxCase {
            numerator: i64,
            denominator: i64,
            expect: i64,
        }
        #[derive(serde::Deserialize)]
        struct Vectors {
            tax_cases: Vec<TaxCase>,
        }
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../vectors/proration_tax.json");
        let data = std::fs::read_to_string(path).expect("read vectors/proration_tax.json");
        let vectors: Vectors = serde_json::from_str(&data).expect("parse vectors/proration_tax.json");
        for case in vectors.tax_cases {
            assert_eq!(round_half_away_from_zero(case.numerator, case.denominator), case.expect);
        }
    }
}
