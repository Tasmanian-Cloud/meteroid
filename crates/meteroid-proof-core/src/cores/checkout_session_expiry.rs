use crate::pure_core;

/// Model of checkout session expiry boundary condition.
///
/// The real code at `modules/meteroid/crates/meteroid-store/src/domain/checkout_sessions.rs:81-84`
/// uses `now > expires_at` (strict inequality) to check session expiry. The standard semantic for
/// "expires at time T" is that the session is valid during [created_at, T), i.e., valid up to but
/// not including T. This requires `now >= expires_at` (inclusive). The strict inequality is a bug
/// that allows session completion exactly AT the expiration time.
///
/// This function models both the buggy and correct implementations using pure integer arithmetic.
#[pure_core]
pub fn checkout_session_expiry_buggy(now_micros: i64, expires_at_micros: i64) -> bool {
    now_micros <= expires_at_micros
}

#[pure_core]
pub fn checkout_session_expiry_correct(now_micros: i64, expires_at_micros: i64) -> bool {
    now_micros < expires_at_micros
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_expiry_boundary_bug_at_exact_time() {
        // At exactly expiration time 1000000, the buggy version allows access (returns true)
        // while the correct version denies access (returns false).
        let t_exp = 1000000i64;
        assert!(checkout_session_expiry_buggy(t_exp, t_exp), "Buggy version should allow at boundary");
        assert!(!checkout_session_expiry_correct(t_exp, t_exp), "Correct version should deny at boundary");
    }

    #[test]
    fn test_expiry_pre_boundary_both_allow() {
        // Before expiration, both checks should agree and allow
        let t_exp = 1000000i64;
        let t_before = t_exp - 1;
        assert!(checkout_session_expiry_buggy(t_before, t_exp), "Buggy should allow pre-expiry");
        assert!(checkout_session_expiry_correct(t_before, t_exp), "Correct should allow pre-expiry");
    }

    #[test]
    fn test_expiry_post_boundary_both_deny() {
        // After expiration, both checks should agree and deny
        let t_exp = 1000000i64;
        let t_after = t_exp + 1;
        assert!(!checkout_session_expiry_buggy(t_after, t_exp), "Buggy should deny post-expiry");
        assert!(!checkout_session_expiry_correct(t_after, t_exp), "Correct should deny post-expiry");
    }

    #[test]
    fn test_expiry_bug_divergence_only_at_boundary() {
        // The two implementations diverge only at the exact boundary
        let t_exp = 1000000i64;
        assert_ne!(
            checkout_session_expiry_buggy(t_exp, t_exp),
            checkout_session_expiry_correct(t_exp, t_exp),
            "Implementations should diverge at boundary"
        );

        // And nowhere else
        for offset in [-100, -1, 1, 100] {
            let t = t_exp + offset;
            assert_eq!(
                checkout_session_expiry_buggy(t, t_exp),
                checkout_session_expiry_correct(t, t_exp),
                "Implementations should agree at t={} (offset={})",
                t,
                offset
            );
        }
    }

    #[test]
    fn test_expiry_real_world_window() {
        // Real-world scenario: checkout session expires at a specific timestamp
        // Demonstrate the bug in a concrete scenario with realistic timestamps
        // (milliseconds since epoch, as used in many systems)
        let session_created_ms = 1600000000000i64; // Sep 13, 2020
        let session_expires_ms = session_created_ms + 3600000; // 1 hour later
        let current_time_at_boundary_ms = session_expires_ms;

        // The buggy check allows completion at the exact expiration time
        assert!(
            checkout_session_expiry_buggy(current_time_at_boundary_ms, session_expires_ms),
            "Buggy version allows checkout completion exactly at expiration time (security issue)"
        );

        // The correct check would deny it
        assert!(
            !checkout_session_expiry_correct(current_time_at_boundary_ms, session_expires_ms),
            "Correct version denies checkout completion at expiration time"
        );
    }
}
