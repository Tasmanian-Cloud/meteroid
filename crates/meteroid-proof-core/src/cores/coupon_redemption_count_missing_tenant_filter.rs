//! CouponRow::inc_redemption_count missing tenant_id filter in UPDATE.
//!
//! Companion to `proof/MeteroidVerify/CouponRedemptionCountMissingTenantFilter.lean`. Models
//! `diesel-models/src/query/coupons.rs`'s `inc_redemption_count`
//! (lines 191-209): increments a coupon's redemption_count by id only, with no
//! tenant_id filter. This is inconsistent with other mutation methods that
//! correctly filter by both id and tenant_id.

use meteroid_pure_core::pure_core;

/// Models the buggy redemption count increment: filters by coupon_id only.
///
/// This matches the actual code at coupons.rs:198-200 where the UPDATE
/// statement filters only by `id`, not by `tenant_id`.
///
/// Result: if multiple tenants have a coupon with the same ID (hypothetically),
/// ALL of them get incremented.
#[pure_core]
pub fn inc_redemption_count_buggy(coupon_id: u64, delta: i64, current_count: i64) -> i64 {
    // In the real code, this increments for ANY coupon matching the id
    if coupon_id != 0 {
        current_count + delta
    } else {
        current_count
    }
}

/// Models the correct redemption count increment: filters by coupon_id AND tenant_id.
///
/// This is what the code SHOULD do, matching the guard pattern used in
/// other methods like `CouponRowPatch::patch`.
#[pure_core]
pub fn inc_redemption_count_correct(
    coupon_id: u64,
    tenant_id: u64,
    expected_tenant_id: u64,
    delta: i64,
    current_count: i64,
) -> i64 {
    // Only increment if BOTH id and tenant match
    if coupon_id != 0 && tenant_id == expected_tenant_id {
        current_count + delta
    } else {
        current_count
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buggy_increments_all_matching_ids() {
        // Tenant 1's coupon 100 starts at 0
        let buggy_tenant1 = inc_redemption_count_buggy(100, 1, 0);

        // Tenant 2's coupon 100 also starts at 0
        // But the buggy query would increment it too!
        let buggy_tenant2 = inc_redemption_count_buggy(100, 1, 0);

        // Both get incremented despite being different tenants
        assert_eq!(buggy_tenant1, 1);
        assert_eq!(buggy_tenant2, 1);
    }

    #[test]
    fn correct_increments_only_matching_tenant() {
        // Tenant 1's coupon 100 starts at 0
        let correct_tenant1 = inc_redemption_count_correct(100, 1, 1, 1, 0);

        // Tenant 2's coupon 100 is NOT incremented (wrong tenant_id)
        let correct_tenant2 = inc_redemption_count_correct(100, 2, 1, 1, 0);

        assert_eq!(correct_tenant1, 1);
        assert_eq!(correct_tenant2, 0); // Not incremented
    }

    #[test]
    fn guards_cross_tenant_mutation_on_redemption() {
        // Simulating: coupon 50 used 3 times
        // Buggy: both tenants' versions get incremented
        let buggy_t1_before = 5;
        let buggy_t2_before = 5;
        let buggy_t1_after = inc_redemption_count_buggy(50, 1, buggy_t1_before);
        let buggy_t2_after = inc_redemption_count_buggy(50, 1, buggy_t2_before);

        // Correct: only the target tenant increments
        let correct_t1_after = inc_redemption_count_correct(50, 1, 1, 1, buggy_t1_before);
        let correct_t2_after = inc_redemption_count_correct(50, 2, 1, 1, buggy_t2_before);

        // Bug: both affected
        assert_eq!(buggy_t1_after, buggy_t2_after);

        // Correct: only tenant 1 affected
        assert_eq!(correct_t1_after, 6);
        assert_eq!(correct_t2_after, 5); // Unchanged
    }
}
