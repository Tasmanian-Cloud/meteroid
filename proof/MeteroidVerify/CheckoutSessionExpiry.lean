/-! # Checkout Session Expiry Boundary Condition Bug

## Real code reference

File: `modules/meteroid/crates/meteroid-store/src/domain/checkout_sessions.rs:81-84`

```rust
pub fn is_expired(&self) -> bool {
    self.status == CheckoutSessionStatus::Expired
        || self.expires_at.is_some_and(|exp| Utc::now() > exp)
}
```

## Finding

The `is_expired()` function checks if `now > expires_at` (strictly greater), which means a session
does NOT expire exactly at the expiration time `T` — it remains valid at `T` and only expires after `T`.

Standard semantic: "expires at time T" means the session is valid only during `[created_at, T)`,
i.e., valid up to but not including `T`. This requires checking `now >= expires_at` (inclusive), not `>`.

This is a boundary condition bug: at exactly `T`, the function returns false (session not expired),
allowing completion of an expired session if the completion attempt is made in the infinitesimal
window exactly at the expiration instant.

## Model

Model the expiry check as a pure integer comparison on timestamps (modeling time as microseconds
since epoch, without loss of generality). The bug is that the actual code uses strict inequality
where inclusive inequality is the intended guard.

## What is NOT modeled

- The actual chrono::DateTime<Utc> representation or precision
- Whether the boundary condition window is practically exercisable (depends on system clock granularity)
- The concrete provider (e.g., whether Stripe's session expiry matches Meteroid's check)

## Cross-check

The correct guard should be the one used elsewhere, e.g., invoice grace-period checks or other
time-boundary guards in the codebase. Grepping for similar patterns confirms that time-boundary
checks in other modules use `>=` for "at or after" semantics.
-/

namespace MeteroidVerify

-- Model checkout session expiry as a comparison on integer timestamps
-- where t_now is "now" and t_exp is the expiration time.

/-- Strict inequality check (the buggy implementation) -/
def sessionNotExpiredBuggy (t_now t_exp : Int) : Bool :=
  t_now <= t_exp

/-- Inclusive inequality check (the correct implementation) -/
def sessionNotExpiredCorrect (t_now t_exp : Int) : Bool :=
  t_now < t_exp

/-- Concrete witness: at time 1000 expiring at time 1000, the buggy check allows access. -/
theorem expiry_boundary_bug_concrete_witness :
    sessionNotExpiredBuggy 1000 1000 = true := by decide

/-- Concrete witness: at the same time, the correct check denies access. -/
theorem expiry_boundary_correct_denies :
    sessionNotExpiredCorrect 1000 1000 = false := by decide

/-- Concrete witness showing the bug: both should NOT agree at the boundary. -/
theorem expiry_boundary_bug_exists :
    sessionNotExpiredBuggy 1000 1000 ≠ sessionNotExpiredCorrect 1000 1000 := by decide

/-- The concrete bug case formatted as a witness -/
theorem expiry_bug_allows_at_boundary_when_should_deny :
    sessionNotExpiredBuggy 1000 1000 = true ∧ sessionNotExpiredCorrect 1000 1000 = false := by
  constructor <;> decide

/-- Before expiration, both checks agree (allow access). -/
theorem expiry_pre_boundary_both_allow :
    sessionNotExpiredBuggy 999 1000 = true ∧ sessionNotExpiredCorrect 999 1000 = true := by
  constructor <;> decide

/-- After expiration, both checks agree (deny access). -/
theorem expiry_post_boundary_both_deny :
    sessionNotExpiredBuggy 1001 1000 = false ∧ sessionNotExpiredCorrect 1001 1000 = false := by
  constructor <;> decide

end MeteroidVerify
