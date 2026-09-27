//! `recompute_amount_due_from_settled_payments`'s aggregation formula.
//!
//! Companion to `proof/MeteroidVerify/InvoiceAmountDue.lean`. Models the
//! pure arithmetic (`diesel-models/src/query/invoices.rs:663-732`), not the
//! SQL row filtering that produces its inputs.

use meteroid_pure_core::pure_core;

/// `settled_sum` (`invoices.rs:680-682`).
#[pure_core]
pub fn settled_sum(rows: &[(i64, i64)]) -> i64 {
    rows.iter().map(|(amount, refunded)| amount - refunded).sum()
}

/// `new_amount_due` (`invoices.rs:715`).
#[pure_core]
pub fn new_amount_due(total: i64, applied_credits: i64, cancelled_sum: i64, settled: i64) -> i64 {
    (total - applied_credits - cancelled_sum - settled).max(0)
}

/// `exists_live_for_invoice`'s post-early-return guard
/// (`payment_transactions.rs:183`), independently implemented in a
/// different file but proved equivalent to `new_amount_due(..) == 0`
/// (`MeteroidVerify.InvoiceAmountDue.exists_live_iff_amount_due_zero`).
#[pure_core]
pub fn exists_live_check(total: i64, applied_credits: i64, cancelled_sum: i64, settled: i64) -> bool {
    settled >= total - applied_credits - cancelled_sum
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nonneg_and_monotone() {
        assert!(new_amount_due(1000, 0, 0, 5000) >= 0);
        // More settled payment never increases amount_due.
        assert!(new_amount_due(1000, 0, 0, 500) >= new_amount_due(1000, 0, 0, 900));
    }

    #[test]
    fn exact_threshold() {
        assert_eq!(new_amount_due(1000, 100, 50, 850), 0); // exactly covered
        assert_eq!(new_amount_due(1000, 100, 50, 849), 1); // one cent short
    }

    #[test]
    fn full_refund_is_zero_net() {
        let rows = [(1000i64, 1000i64), (500, 0)];
        assert_eq!(settled_sum(&rows), 500); // the fully-refunded row nets to 0
    }

    #[test]
    fn exists_live_check_matches_new_amount_due_zero() {
        // Same inputs, two independently-written formulas: agree exactly on
        // the boundary and on both sides of it.
        for (total, applied_credits, cancelled_sum, settled) in
            [(1000i64, 100i64, 50i64, 850i64), (1000, 100, 50, 849), (1000, 100, 50, 851), (0, 0, 0, 0)]
        {
            assert_eq!(
                exists_live_check(total, applied_credits, cancelled_sum, settled),
                new_amount_due(total, applied_credits, cancelled_sum, settled) == 0
            );
        }
    }

    /// Cross-check against `vectors/invoice_amount_due.json`.
    #[test]
    fn matches_shared_vectors() {
        #[derive(serde::Deserialize)]
        struct Case {
            total: i64,
            applied_credits: i64,
            cancelled_sum: i64,
            settled_rows: Vec<(i64, i64)>,
            expect: i64,
        }
        #[derive(serde::Deserialize)]
        struct Vectors {
            cases: Vec<Case>,
        }
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../vectors/invoice_amount_due.json");
        let data = std::fs::read_to_string(path).expect("read vectors/invoice_amount_due.json");
        let vectors: Vectors = serde_json::from_str(&data).expect("parse vectors/invoice_amount_due.json");
        for case in vectors.cases {
            let settled = settled_sum(&case.settled_rows);
            let got = new_amount_due(case.total, case.applied_credits, case.cancelled_sum, settled);
            assert_eq!(got, case.expect, "case: total={}", case.total);
        }
    }
}
