//! Round-half-away-from-zero over an exact integer ratio.
//!
//! Companion to `proof/MeteroidVerify/TaxRounding.lean`. Path B (native
//! Lean) — `rust_decimal::Decimal` has no Aeneas builtin, so the real
//! `determine_tax_details` (`meteroid-tax/src/shared.rs:56-242`) was not a
//! Charon extraction candidate (`proof/RESEARCH.md`).

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
