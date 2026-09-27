//! `grace_period_pct` is documented, never implemented.
//!
//! Companion to `proof/MeteroidVerify/EntitlementGracePeriod.lean`.
//! `domain/entitlements.rs:41-46`'s doc comment: "requests are rejected
//! once the limit (plus optional `grace_period_pct`) is reached." The real
//! `enabled` computation, `services/entitlements.rs::build_metered_entitlement`
//! (`:320`), never reads `grace_period_pct` at all.

use meteroid_pure_core::pure_core;

/// The real formula (`entitlements.rs:320`) — `grace_pct` isn't even a parameter,
/// because the real code never reads it.
#[pure_core]
pub fn entitlement_enabled_real(consumed: i64, limit: i64) -> bool {
    consumed < limit
}

/// The documented intended formula (`domain/entitlements.rs:43-44`).
#[pure_core]
pub fn entitlement_enabled_intended(consumed: i64, limit: i64, grace_pct: i64) -> bool {
    100 * consumed < limit * (100 + grace_pct)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agrees_with_no_grace_period() {
        for (consumed, limit) in [(50, 100), (100, 100), (150, 100), (0, 0)] {
            assert_eq!(
                entitlement_enabled_intended(consumed, limit, 0),
                entitlement_enabled_real(consumed, limit)
            );
        }
    }

    #[test]
    fn grace_window_witness() {
        // $100-unit limit, 10% configured grace (intended cutoff 110), 105 consumed.
        assert!(!entitlement_enabled_real(105, 100)); // blocked immediately
        assert!(entitlement_enabled_intended(105, 100, 10)); // should still be allowed
    }
}
