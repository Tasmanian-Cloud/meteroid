//! `.find()`-by-product_id double-matching bug.
//!
//! Companion to `proof/MeteroidVerify/ComponentMatching.lean`. Models
//! `build_plan_change_preview`'s matching loop
//! (`services/subscriptions/plan_change.rs:1551-1583`).

use meteroid_pure_core::pure_core;

/// A component as `(id, product_id)`.
pub type Component = (i64, i64);

/// `.find()`'s exact effect (`plan_change.rs:1554-1558`).
#[pure_core]
pub fn find_match(current: &[Component], target_product: i64) -> Option<i64> {
    current.iter().find(|c| c.1 == target_product).map(|c| c.0)
}

/// The real matching loop's structure: independently search the full,
/// unmodified current list per target.
#[pure_core]
pub fn match_all(current: &[Component], targets: &[Component]) -> Vec<(i64, Option<i64>)> {
    targets.iter().map(|t| (t.0, find_match(current, t.1))).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn double_match_bug() {
        // Two current components (100, 200) share product 1; two targets
        // (10, 20) both want product 1.
        let current: Vec<Component> = vec![(100, 1), (200, 1)];
        let targets: Vec<Component> = vec![(10, 1), (20, 1)];
        let matches = match_all(&current, &targets);
        assert_eq!(matches, vec![(10, Some(100)), (20, Some(100))]);
        // Component 200 is unreachable for either target.
        for (_, m) in &matches {
            assert_ne!(*m, Some(200));
        }
    }
}
