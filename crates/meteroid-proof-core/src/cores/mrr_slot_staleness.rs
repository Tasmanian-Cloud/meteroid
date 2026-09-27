//! `calculate_mrr` reports the ORIGINAL slot count forever.
//!
//! Companion to `proof/MeteroidVerify/MrrSlotStaleness.lean`. Traced:
//! `SubscriptionFee::Slot`'s `initial_slots` is set once at creation
//! (`subscription_components.rs:288-296`), never updated by
//! `update_subscription_slots` (`services/subscriptions/slots.rs:37-173`,
//! which only appends to the `slot_transactions` ledger). The generic
//! `utils.rs::calculate_mrr` (`:101-105`) uses `initial_slots` directly;
//! the slot-aware `plan_change.rs::calculate_components_mrr_with_slots`
//! (`:1695-1741`) correctly queries the live count but is called from only
//! one site — 9 other real call sites use the generic, stale version.

use meteroid_pure_core::pure_core;

/// `calculate_mrr`'s `Slot` arm, collapsed to integer division (`utils.rs:101-105,113-116`).
#[pure_core]
pub fn mrr_generic_slot(initial_slots: i64, rate_cents: i64, months: i64) -> i64 {
    initial_slots * rate_cents / months
}

/// `calculate_components_mrr_with_slots`'s `Slot` arm (`plan_change.rs:1730-1734`).
#[pure_core]
pub fn mrr_slot_aware(current_active_slots: i64, rate_cents: i64, months: i64) -> i64 {
    current_active_slots * rate_cents / months
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agree_before_any_slot_change() {
        assert_eq!(mrr_generic_slot(5, 1000, 1), mrr_slot_aware(5, 1000, 1));
    }

    #[test]
    fn stale_after_upgrade() {
        // Created with 5 slots, later upgraded to 10, $10.00/slot/month.
        assert_eq!(mrr_generic_slot(5, 1000, 1), 5000); // still reports the original count
        assert_eq!(mrr_slot_aware(10, 1000, 1), 10000); // the true, current MRR
    }
}
