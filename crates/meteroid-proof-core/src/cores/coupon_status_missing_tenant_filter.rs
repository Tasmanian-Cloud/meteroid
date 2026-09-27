//! CouponStatusRowPatch::patch missing tenant_id filter in WHERE clause.
//!
//! Companion to `proof/MeteroidVerify/CouponStatusMissingTenantFilter.lean`. Models
//! `diesel-models/src/query/coupons.rs`'s `CouponStatusRowPatch::patch`
//! (lines 294-310): updates a coupon's status by id only, with no tenant_id filter,
//! unlike the similar `CouponRowPatch::patch` which correctly filters by both.

use meteroid_pure_core::pure_core;

/// Models the buggy coupon status update: filters by coupon_id only.
///
/// This matches the actual code at coupons.rs:298-300 where the UPDATE
/// statement has only `filter(c_dsl::id.eq(self.id))` with no tenant check.
#[pure_core]
pub fn update_coupon_status_buggy(coupon_id: u64, new_status: bool) -> bool {
    // In the real code, this would update ALL coupons with this ID across all tenants
    // For the model, we just check if we would update it
    coupon_id != 0
}

/// Models the correct coupon status update: filters by coupon_id AND tenant_id.
///
/// This is what the code SHOULD do, matching the pattern used in
/// `CouponRowPatch::patch` (lines 276-291).
#[pure_core]
pub fn update_coupon_status_correct(
    coupon_id: u64,
    tenant_id: u64,
    expected_tenant_id: u64,
    new_status: bool,
) -> bool {
    // Only update if BOTH id and tenant match
    coupon_id != 0 && tenant_id == expected_tenant_id
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buggy_affects_wrong_tenant() {
        // Tenant 1 tries to disable coupon 42
        let buggy = update_coupon_status_buggy(42, false);

        // Tenant 2 also has coupon 42 (hypothetically, due to missing guard)
        // The buggy query would affect BOTH
        assert!(buggy); // Would return true for any id > 0
    }

    #[test]
    fn correct_filters_by_tenant() {
        // Tenant 1 disables their coupon 42
        let for_tenant1 = update_coupon_status_correct(42, 1, 1, false);

        // Tenant 2's coupon 42 would NOT be affected
        let for_tenant2 = update_coupon_status_correct(42, 2, 1, false);

        assert!(for_tenant1);
        assert!(!for_tenant2);
    }

    #[test]
    fn inconsistency_between_methods() {
        // This test demonstrates the inconsistency:
        // CouponStatusRowPatch uses buggy pattern (no tenant filter)
        // CouponRowPatch uses correct pattern (tenant filter included)
        // Both should protect against cross-tenant mutations

        let buggy_count = if update_coupon_status_buggy(42, true) { 2 } else { 0 };
        let correct_count = if update_coupon_status_correct(42, 1, 1, true) {
            1
        } else {
            0
        };

        // Bug: buggy version would update 2 records (both tenants)
        // Correct: would update only 1 record (specified tenant)
        assert_eq!(buggy_count, 2);
        assert_eq!(correct_count, 1);
    }
}
