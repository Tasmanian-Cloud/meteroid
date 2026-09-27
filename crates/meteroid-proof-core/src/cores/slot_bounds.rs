//! Slot/seat bounds check — correct in isolation, missing on one real call site.
//!
//! Companion to `proof/MeteroidVerify/SlotBounds.lean`. `validate_slot_limits`
//! (`repositories/subscriptions/slots.rs:211-239`) is proved correct here;
//! the real gap is that `update_subscription_slots`
//! (`services/subscriptions/slots.rs:37-173`) never calls it — a Rust
//! call-graph fact documented in the Lean file's module doc, not something
//! this Rust re-implementation can itself demonstrate.

use meteroid_pure_core::pure_core;

#[pure_core]
pub fn new_slot_count(active: i64, delta: i64) -> i64 {
    active + delta
}

/// Verbatim (`slots.rs:211-239`): accepts iff `new_count` is within
/// `[min, max]`, either bound `None` meaning unbounded.
#[pure_core]
pub fn valid_slot_count(min: Option<i64>, max: Option<i64>, new_count: i64) -> bool {
    min.is_none_or(|m| new_count >= m) && max.is_none_or(|m| new_count <= m)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_exactly_the_inclusive_range() {
        assert!(valid_slot_count(Some(5), Some(10), 5));
        assert!(valid_slot_count(Some(5), Some(10), 10));
        assert!(!valid_slot_count(Some(5), Some(10), 4));
        assert!(!valid_slot_count(Some(5), Some(10), 11));
    }

    #[test]
    fn a_downgrade_below_min_would_be_rejected_if_checked() {
        // The exact shape of input update_subscription_slots's downgrade
        // path (slots.rs:78-100) applies with zero check.
        let count = new_slot_count(5, -1);
        assert!(!valid_slot_count(Some(5), None, count));
    }
}
