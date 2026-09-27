//! Largest-remainder discount distribution — a conservation theorem, not a
//! found bug.
//!
//! Companion to `proof/MeteroidVerify/DiscountConservation.lean`. A first
//! read of `meteroid-store/src/services/invoice_lines/discount.rs`'s
//! `distribute_discount` suspected a conservation-invariant break when
//! `discount` exceeds one line's own subtotal while others still have
//! room — working the arithmetic by hand first (not from memory) showed
//! that bug doesn't exist: floor division guarantees `discount * x / total
//! < x` whenever `discount < total` and `x > 0`, so the real code's
//! `.max(0)` clamp never fires in that regime. This models the pass-1
//! floor-share step only (`discount.rs:36`) — the two theorems this
//! cross-checks (`pass1_sum_le_discount`, `pass1_taxable_pos`) are about
//! the arithmetic identity, not a full re-implementation of pass 2's
//! sort-by-remainder selection.

use meteroid_pure_core::pure_core;

/// Pass 1's per-item floor-proportional share (`discount.rs:36`).
#[pure_core]
pub fn pass1_discount(discount: u64, total: u64, x: u64) -> u64 {
    discount * x / total
}

/// The per-item remainder pass 2 sorts by, descending (`discount.rs:48-49`).
#[pure_core]
pub fn pass1_remainder(discount: u64, total: u64, x: u64) -> u64 {
    discount * x % total
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_test_simple_distribution() {
        // discount.rs's test_simple_distribution: 6000/4000 subtotals, discount 1000.
        assert_eq!(pass1_discount(1000, 10000, 6000), 600);
        assert_eq!(pass1_discount(1000, 10000, 4000), 400);
    }

    #[test]
    fn matches_test_remainder_distribution() {
        // discount.rs's test_remainder_distribution: 333/333/334, discount 100.
        let subtotals = [333u64, 333, 334];
        let total: u64 = subtotals.iter().sum();
        let shares: Vec<u64> = subtotals.iter().map(|&x| pass1_discount(100, total, x)).collect();
        let remainders: Vec<u64> = subtotals.iter().map(|&x| pass1_remainder(100, total, x)).collect();
        // sum_pass1_eq's identity, concretely: discount*total = total*sum(shares) + sum(remainders).
        let lhs = 100u64 * total;
        let rhs = total * shares.iter().sum::<u64>() + remainders.iter().sum::<u64>();
        assert_eq!(lhs, rhs);
    }

    #[test]
    fn pass1_never_clamps_when_discount_lt_total() {
        // pass1_taxable_pos: share < subtotal whenever discount < total and subtotal > 0.
        for (discount, total, x) in [(999u64, 1000u64, 1u64), (1u64, 1000, 999), (500, 1010, 10)] {
            assert!(pass1_discount(discount, total, x) < x);
        }
    }

    /// Cross-check against `vectors/discount.json`.
    #[test]
    fn matches_shared_vectors() {
        #[derive(serde::Deserialize)]
        struct Case {
            discount: u64,
            subtotals: Vec<u64>,
        }
        #[derive(serde::Deserialize)]
        struct Vectors {
            cases: Vec<Case>,
        }
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../vectors/discount.json");
        let data = std::fs::read_to_string(path).expect("read vectors/discount.json");
        let vectors: Vectors = serde_json::from_str(&data).expect("parse vectors/discount.json");
        for case in vectors.cases {
            let total: u64 = case.subtotals.iter().sum();
            assert!(case.discount <= total, "vector must respect discount <= total");
            let shares: Vec<u64> = case
                .subtotals
                .iter()
                .map(|&x| pass1_discount(case.discount, total, x))
                .collect();
            let remainders: Vec<u64> = case
                .subtotals
                .iter()
                .map(|&x| pass1_remainder(case.discount, total, x))
                .collect();
            let lhs = case.discount * total;
            let rhs = total * shares.iter().sum::<u64>() + remainders.iter().sum::<u64>();
            assert_eq!(lhs, rhs, "sum_pass1_eq identity failed for case {case:?}", case = case.subtotals);
            for (&x, &s) in case.subtotals.iter().zip(shares.iter()) {
                if x > 0 && case.discount < total {
                    assert!(s < x, "pass1_taxable_pos failed: share {s} >= subtotal {x}");
                }
            }
        }
    }
}
