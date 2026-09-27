use meteroid_pure_core::pure_core;

/// A component's attributes: (id, product_id, fee_cents)
type ComponentWithFee = (u64, u64, u64);

/// Classifies components as "removed" by checking if their ID is in the matched set.
/// This mirrors the actual logic in plan_change.rs:1599-1608.
#[pure_core]
pub fn classify_as_removed(current_components: &[ComponentWithFee], matched_ids: &[u64]) -> Vec<ComponentWithFee> {
    current_components
        .iter()
        .filter(|(id, _, _)| !matched_ids.contains(id))
        .copied()
        .collect()
}

/// Bug #11 scenario: two current components with the same product_id
fn example_current_with_fees() -> Vec<ComponentWithFee> {
    vec![(100, 1, 10000), (200, 1, 10000)]  // Both charge $100/month
}

/// Bug #11 effect: only component 100 is in the matched set (should be [100, 200])
fn buggy_matched_ids() -> Vec<u64> {
    vec![100]  // Missing 200, which shares product_id = 1
}

/// Correctly matched IDs (the way it should work)
fn correct_matched_ids() -> Vec<u64> {
    vec![100, 200]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spurious_removal_from_double_match() {
        // With bug #11's matching, component 200 is incorrectly classified as removed
        let current = example_current_with_fees();
        let buggy_matched = buggy_matched_ids();
        let buggy_removed = classify_as_removed(&current, &buggy_matched);

        // Component 200 (product=1, fee=10000) is in the removed list
        assert!(buggy_removed.iter().any(|(id, _, _)| *id == 200));

        // Component 100 is NOT in the removed list (it was matched)
        assert!(!buggy_removed.iter().any(|(id, _, _)| *id == 100));
    }

    #[test]
    fn test_spurious_credit_amount() {
        let current = example_current_with_fees();
        let buggy_matched = buggy_matched_ids();
        let buggy_removed = classify_as_removed(&current, &buggy_matched);

        // Find component 200 in the removed list
        let component_200 = buggy_removed.iter().find(|(id, _, _)| *id == 200);
        assert!(component_200.is_some());

        // Component 200's fee is 10000 cents ($100) — this will be credited
        let (_, _, fee) = component_200.unwrap();
        assert_eq!(*fee, 10000);
    }

    #[test]
    fn test_correct_matching_no_spurious_removal() {
        let current = example_current_with_fees();
        let buggy_removed = classify_as_removed(&current, &buggy_matched_ids());
        let correct_removed = classify_as_removed(&current, &correct_matched_ids());

        // Buggy matching leaves component 200 in removed
        assert!(buggy_removed.iter().any(|(id, _, _)| *id == 200));

        // Correct matching leaves no components in removed
        assert!(correct_removed.is_empty());

        // The two are different
        assert_ne!(buggy_removed, correct_removed);
    }

    #[test]
    fn test_both_components_share_product_id() {
        let current = example_current_with_fees();

        // Both components have product_id = 1
        assert!(current.iter().all(|(_, prod_id, _)| *prod_id == 1));

        // But they have different IDs
        assert!(current[0].0 != current[1].0);
    }

    #[test]
    fn test_removal_side_with_amendment_close_safety() {
        // This test documents the database-level safety: if a component
        // is already closed (effective_to IS NOT NULL), calling close_components
        // again will be a no-op due to the WHERE effective_to IS NULL filter.

        // In our model, we just verify the classification logic.
        // The actual database safety is in close_components.rs:265:
        //   .filter(sc_dsl::effective_to.is_null())

        let current = example_current_with_fees();
        let buggy_removed = classify_as_removed(&current, &buggy_matched_ids());

        // Component 200 is classified as removed once
        assert_eq!(buggy_removed.iter().filter(|(id, _, _)| *id == 200).count(), 1);
    }

    #[test]
    fn test_scenario_multiple_products() {
        // Extended scenario: components with different products
        let current = vec![
            (100, 1, 10000),  // Product 1, $100/month
            (200, 1, 10000),  // Product 1, $100/month (same product!)
            (300, 2, 5000),   // Product 2, $50/month
        ];

        // Matched: only component 100 (due to bug #11 on product 1)
        let matched = vec![100];
        let removed = classify_as_removed(&current, &matched);

        // Components 200 and 300 are removed
        assert_eq!(removed.len(), 2);
        assert!(removed.iter().any(|(id, _, _)| *id == 200));
        assert!(removed.iter().any(|(id, _, _)| *id == 300));
    }
}
