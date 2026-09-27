//! Quote expiry validation is missing in quote-to-subscription conversion.
//!
//! Companion to `proof/MeteroidVerify/QuoteExpiry.lean`.
//! `services/quotes.rs::convert_quote_to_subscription` (`:21-61`) validates that
//! a quote has `status == Accepted` and hasn't already been converted, but does NOT
//! validate that the quote's `expires_at` hasn't passed. Compare to coupon expiry
//! check at `services/subscriptions/utils.rs:378`.

use meteroid_pure_core::pure_core;

/// The real guard in `convert_quote_to_subscription` (`:21-61`): checks status
/// and whether already converted, but NOT expiry.
#[pure_core]
pub fn quote_conversion_guard_real(status: &str, already_converted: bool) -> bool {
    status == "Accepted" && !already_converted
}

/// The intended guard: should also reject if the quote is expired.
#[pure_core]
pub fn quote_conversion_guard_intended(status: &str, already_converted: bool, expired: bool) -> bool {
    status == "Accepted" && !already_converted && !expired
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agrees_when_not_expired() {
        // When a quote is not expired, both guards agree (the bug stays latent).
        assert_eq!(
            quote_conversion_guard_intended("Accepted", false, false),
            quote_conversion_guard_real("Accepted", false)
        );
    }

    #[test]
    fn expired_quote_conversion_bug() {
        // Concrete witness: a quote with status "Accepted", never converted,
        // but expired. The real code allows conversion; the intended code rejects it.
        assert!(quote_conversion_guard_real("Accepted", false));
        assert!(!quote_conversion_guard_intended("Accepted", false, true));
    }

    #[test]
    fn not_accepted_quote_blocked_by_both() {
        // When quote is not Accepted, both guards reject it.
        assert!(!quote_conversion_guard_real("Draft", false));
        assert!(!quote_conversion_guard_intended("Draft", false, false));
    }

    #[test]
    fn already_converted_quote_blocked_by_both() {
        // When quote is already converted, both guards reject it.
        assert!(!quote_conversion_guard_real("Accepted", true));
        assert!(!quote_conversion_guard_intended("Accepted", true, false));
    }
}
