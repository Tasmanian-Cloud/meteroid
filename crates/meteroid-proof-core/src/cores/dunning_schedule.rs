//! The dunning retry-ladder index arithmetic.
//!
//! Companion to `proof/MeteroidVerify/DunningSchedule.lean`. Models
//! `schedule_next_dunning_attempt`'s lookup
//! (`services/orchestration/payment_transaction_failed.rs:123-181`):
//! `DUNNING_RETRY_SCHEDULE_DAYS.get(failed_attempts.saturating_sub(1) as
//! usize)`, schedule `[3, 5, 7]` days (`:22`).

use meteroid_pure_core::pure_core;

/// Verbatim (`:22,135-136`).
#[pure_core]
pub fn dunning_delay(failed_attempts: u64) -> Option<u64> {
    const SCHEDULE: [u64; 3] = [3, 5, 7];
    SCHEDULE.get(failed_attempts.saturating_sub(1) as usize).copied()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_the_ladder_exactly() {
        assert_eq!(dunning_delay(0), Some(3)); // can't occur in practice; degenerates safely
        assert_eq!(dunning_delay(1), Some(3));
        assert_eq!(dunning_delay(2), Some(5));
        assert_eq!(dunning_delay(3), Some(7));
        assert_eq!(dunning_delay(4), None); // exhausted
        assert_eq!(dunning_delay(100), None); // stays exhausted
    }
}
