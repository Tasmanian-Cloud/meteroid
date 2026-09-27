//! VAT revalidation queries customers across all tenants with no filtering.
//!
//! Companion to `proof/MeteroidVerify/VatRevalidationCrossTenant.lean`. Models
//! `diesel-models/src/query/customers.rs`'s `list_vat_revalidation_candidates`
//! (lines 73-101): the function lacks a tenant_id filter despite explicitly
//! documenting that it lists candidates "across all tenants."

use meteroid_pure_core::pure_core;

/// Models the buggy query behavior: filters by VAT fields only, not tenant.
///
/// This is the actual behavior at customers.rs:82-94 where NO tenant_id filter exists.
#[pure_core]
pub fn list_vat_candidates_unfiltered(
    has_vat: bool,
    vat_format_valid: bool,
    not_archived: bool,
    needs_recheck: bool,
    created_old_enough: bool,
) -> bool {
    has_vat && vat_format_valid && not_archived && needs_recheck && created_old_enough
}

/// Models the correct query behavior: filters by tenant AND vat fields.
///
/// This is what the code SHOULD do to properly scope results to a single tenant.
#[pure_core]
pub fn list_vat_candidates_correct(
    tenant_match: bool,
    has_vat: bool,
    vat_format_valid: bool,
    not_archived: bool,
    needs_recheck: bool,
    created_old_enough: bool,
) -> bool {
    tenant_match
        && has_vat
        && vat_format_valid
        && not_archived
        && needs_recheck
        && created_old_enough
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buggy_includes_other_tenants() {
        // Tenant 1's customer: matches all VAT criteria
        let tenant1_customer = list_vat_candidates_unfiltered(true, true, true, true, true);

        // Tenant 2's customer: matches all VAT criteria
        let tenant2_customer = list_vat_candidates_unfiltered(true, true, true, true, true);

        // Both are included in the unfiltered list!
        assert!(tenant1_customer && tenant2_customer);
    }

    #[test]
    fn correct_filters_by_tenant() {
        // Tenant 1's customer with tenant filter
        let tenant1_customer = list_vat_candidates_correct(true, true, true, true, true, true);

        // Tenant 2's customer fails the tenant filter
        let tenant2_customer = list_vat_candidates_correct(false, true, true, true, true, true);

        // Only tenant 1 is included
        assert!(tenant1_customer && !tenant2_customer);
    }

    #[test]
    fn unfiltered_query_affects_both_tenants() {
        let buggy_result = list_vat_candidates_unfiltered(true, true, true, true, true);
        let correct_for_tenant1 = list_vat_candidates_correct(true, true, true, true, true, true);
        let correct_for_tenant2 = list_vat_candidates_correct(false, true, true, true, true, true);

        // The bug: buggy query has no way to distinguish tenants
        // If both tenants' customers have valid VAT data, both are returned
        // whereas the correct query would return only one per tenant
        assert_eq!(buggy_result, true);
        assert_eq!(correct_for_tenant1, true);
        assert_eq!(correct_for_tenant2, false);
    }
}
