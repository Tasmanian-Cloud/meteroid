//! `convert_currency` never accounts for differing subunit exponents.
//!
//! Companion to `proof/MeteroidVerify/CurrencyConversion.lean`. Models
//! `repositories/customer_balance.rs`'s `convert_currency` (`:16-42`): a
//! real, checked omission — no `rusty_money::iso::find(currency).exponent`
//! lookup anywhere in that file, unlike every other money-conversion site
//! in the codebase.

use meteroid_pure_core::pure_core;

/// The real formula (`customer_balance.rs:40`), exact-arithmetic version.
#[pure_core]
pub fn convert_currency(amount_cents: i64, rate: i64) -> i64 {
    amount_cents * rate
}

/// The correct formula: scale by `10^(to_exponent - from_exponent)`.
#[pure_core]
pub fn convert_currency_scaled(amount_cents: i64, rate: i64, from_exponent: u32, to_exponent: u32) -> i64 {
    amount_cents * rate * 10i64.pow(to_exponent) / 10i64.pow(from_exponent)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_exponent_pairs_are_unaffected() {
        // USD/EUR/GBP/AUD all use exponent 2 -- the real formula IS correct here.
        assert_eq!(convert_currency_scaled(100, 92, 2, 2), convert_currency(100, 92));
    }

    #[test]
    fn usd_to_jpy_exponent_mismatch_inflates_by_100x() {
        // $1.00 (100 USD cents) at 150 JPY/USD. JPY has exponent 0 (no
        // subunit smaller than a whole yen), so the correct result is 150.
        assert_eq!(convert_currency(100, 150), 15000);
        assert_eq!(convert_currency_scaled(100, 150, 2, 0), 150);
    }
}
