/// Termination Currency Conversion bug — recurrence of bug #7
///
/// `terminate.rs::create_churn_mrr_log` (lines 223-225) converts MRR to USD without
/// adjusting for currency exponent differences. The division is unit-agnostic:
/// ```ignore
/// Decimal::from(mrr_delta) / rate_decimal  // ← no exponent normalization
/// ```
///
/// This is identical to bug #7 (CurrencyConversion), which documented the same
/// pattern in `customer_balance.rs`, `invoices.rs`, and `subscriptions/utils.rs`.
/// The terminate.rs site shows it exists in 5 locations within the codebase.

use meteroid_pure_core::pure_core;

#[pure_core]
pub fn mrr_to_usd_buggy(mrr_delta_cents: u64, rate_to_usd: u64) -> u64 {
    if rate_to_usd == 0 {
        mrr_delta_cents
    } else {
        mrr_delta_cents / rate_to_usd
    }
}

#[pure_core]
pub fn power10(exp: usize) -> u64 {
    10_u64.pow(exp as u32)
}

#[pure_core]
pub fn mrr_to_usd_correct(
    mrr_delta: u64,
    exponent_factor: usize,
    rate_to_usd: u64,
) -> u64 {
    let scaled = mrr_delta.saturating_mul(power10(exponent_factor));
    if rate_to_usd == 0 {
        scaled
    } else {
        scaled / rate_to_usd
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jpy_to_usd_buggy_no_scaling() {
        // JPY: 1,000,000 yen (exponent 0)
        // Rate: 100 (simplified)
        // Buggy: 1,000,000 / 100 = 10,000
        assert_eq!(mrr_to_usd_buggy(1_000_000, 100), 10_000);
    }

    #[test]
    fn jpy_to_usd_correct_with_scaling() {
        // JPY to USD: scale by exponent difference (2 - 0 = 2)
        // Correct: (1,000,000 × 10^2) / 100 = 1,000,000
        assert_eq!(mrr_to_usd_correct(1_000_000, 2, 100), 1_000_000);
    }

    #[test]
    fn bug_produces_100x_error() {
        // Same inputs, buggy vs correct
        let buggy = mrr_to_usd_buggy(1_000_000, 100);
        let correct = mrr_to_usd_correct(1_000_000, 2, 100);
        // Buggy is 100× too small
        assert!(buggy * 100 <= correct);
        assert_eq!(buggy, 10_000);
        assert_eq!(correct, 1_000_000);
    }
}
