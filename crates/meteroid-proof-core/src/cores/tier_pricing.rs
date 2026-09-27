//! Tiered/volume pricing, and the two real bugs it formalizes.
//!
//! Companion to `proof/MeteroidVerify/TierPricing.lean`. Faithful
//! re-implementation of `meteroid-store/src/services/invoice_lines/fees.rs`'s
//! `tiered_charges`/`volume_charge`, over `i64` cents instead of `Decimal`
//! (rounding is out of scope here — Phase 3's job, `proof/RESEARCH.md`).
//! Assumes `tiers` is already sorted by `first_unit` ascending, matching the
//! real code's own `sort_by_key` step.

use meteroid_pure_core::pure_core;

#[derive(Copy, Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct TierRow {
    pub first_unit: u64,
    pub rate_cents: i64,
    #[serde(default)]
    pub flat_fee_cents: Option<i64>,
    #[serde(default)]
    pub flat_cap_cents: Option<i64>,
}

/// `tiered_charges` (`fees.rs:33-81`). `_block_size` is accepted and
/// ignored, exactly matching `compute_tier_price`'s real signature
/// (`fees.rs:160-167`) — the bug `tiered_price_ignores_block_size`
/// (`proof/MeteroidVerify/TierPricing.lean`) formalizes.
#[pure_core]
pub fn tiered_amount(usage_units: u64, tiers: &[TierRow], _block_size: Option<u64>) -> i64 {
    let mut remaining = usage_units;
    let mut total = 0i64;
    let mut iter = tiers.iter().peekable();
    while let Some(t) = iter.next() {
        if remaining == 0 {
            break;
        }
        let width = iter.peek().map(|next| next.first_unit.saturating_sub(t.first_unit));
        let units = match width {
            Some(w) => remaining.min(w),
            None => remaining,
        };
        if units > 0 {
            let mut amount = units as i64 * t.rate_cents;
            if let Some(fee) = t.flat_fee_cents {
                amount += fee;
            }
            if let Some(cap) = t.flat_cap_cents {
                amount = amount.min(cap);
            }
            total += amount;
        }
        remaining -= units;
    }
    total
}

/// `volume_charge` (`fees.rs:84-115`). Where the real code computes
/// `next.first_unit - 1` unguarded (`fees.rs:90`) — a debug-panic /
/// release-wrap hazard when two tiers share `first_unit = 0` — this uses
/// `checked_sub` and returns `None` instead of reproducing the panic or the
/// wrap, so the hazard is observable (`Some(None)` below) without actually
/// triggering it.
#[pure_core]
pub fn volume_amount(usage_units: u64, tiers: &[TierRow], _block_size: Option<u64>) -> Option<i64> {
    let mut iter = tiers.iter().peekable();
    while let Some(t) = iter.next() {
        let last_unit = iter.peek().map(|next| next.first_unit.checked_sub(1));
        let upper_ok = match last_unit {
            None => true,
            Some(None) => return None,
            Some(Some(l)) => usage_units <= l,
        };
        if usage_units >= t.first_unit && upper_ok {
            let mut amount = usage_units as i64 * t.rate_cents;
            if let Some(fee) = t.flat_fee_cents {
                amount += fee;
            }
            if let Some(cap) = t.flat_cap_cents {
                amount = amount.min(cap);
            }
            return Some(amount);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tier(first_unit: u64, rate_cents: i64) -> TierRow {
        TierRow { first_unit, rate_cents, flat_fee_cents: None, flat_cap_cents: None }
    }

    #[test]
    fn tiered_graduated_matches_fees_rs() {
        // fees.rs `tiered_graduated_matches_line_total`: 100*1 + 50*0.5 = 125
        let tiers = [tier(0, 100), tier(100, 50), tier(200, 25)];
        assert_eq!(tiered_amount(150, &tiers, None), 12500);
    }

    #[test]
    fn tiered_flat_fee_and_cap_matches_fees_rs() {
        // fees.rs `tiered_applies_flat_fee_and_cap`
        let with_fee = TierRow { first_unit: 0, rate_cents: 100, flat_fee_cents: Some(1000), flat_cap_cents: None };
        assert_eq!(tiered_amount(5, &[with_fee], None), 5 * 100 + 1000);
        let with_cap = TierRow { first_unit: 0, rate_cents: 100, flat_fee_cents: None, flat_cap_cents: Some(300) };
        assert_eq!(tiered_amount(5, &[with_cap], None), 300);
    }

    #[test]
    fn volume_matches_fees_rs() {
        // fees.rs `volume_picks_tier_matches_line_total`: 150 lands in [100,199] -> 150*0.5 = 75
        let tiers = [tier(0, 100), tier(100, 50), tier(200, 25)];
        assert_eq!(volume_amount(150, &tiers, None), Some(150 * 50));
    }

    #[test]
    fn block_size_has_no_effect() {
        let tiers = [tier(0, 100), tier(100, 50)];
        let a = tiered_amount(150, &tiers, None);
        let b = tiered_amount(150, &tiers, Some(20));
        assert_eq!(a, b, "block_size is accepted but ignored — fees.rs:32,123,166's TODO");
    }

    #[test]
    fn duplicate_zero_tier_upper_bound_is_unrepresentable() {
        // Two tiers sharing first_unit = 0 — not excluded by TierRow's type.
        // The real fees.rs:90 (`first_unit - 1`) panics under debug
        // overflow-checks or silently wraps to u64::MAX in release;
        // checked_sub surfaces the same precondition as None instead.
        let tiers = [tier(0, 100), tier(0, 50)];
        assert_eq!(volume_amount(0, &tiers, None), None);
        assert_eq!(0u64.checked_sub(1), None);
    }

    /// Cross-check against `vectors/tier_pricing.json` (ported from the real
    /// `fees.rs` tests).
    #[test]
    fn matches_shared_vectors() {
        #[derive(serde::Deserialize)]
        struct Case {
            model: String,
            usage_units: u64,
            tiers: Vec<TierRow>,
            #[serde(default)]
            block_size: Option<u64>,
            expect_cents: Option<i64>,
        }
        #[derive(serde::Deserialize)]
        struct Vectors {
            cases: Vec<Case>,
        }
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../vectors/tier_pricing.json");
        let data = std::fs::read_to_string(path).expect("read vectors/tier_pricing.json");
        let vectors: Vectors = serde_json::from_str(&data).expect("parse vectors/tier_pricing.json");
        for case in vectors.cases {
            let got = match case.model.as_str() {
                "tiered" => Some(tiered_amount(case.usage_units, &case.tiers, case.block_size)),
                "volume" => volume_amount(case.usage_units, &case.tiers, case.block_size),
                other => panic!("unknown model {other}"),
            };
            assert_eq!(got, case.expect_cents, "case: {case:?}", case = case.model);
        }
    }
}
