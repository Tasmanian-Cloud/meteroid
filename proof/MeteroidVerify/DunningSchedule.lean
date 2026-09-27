/-!
# meteroid / DunningSchedule — the retry-ladder index arithmetic is exactly right

`schedule_next_dunning_attempt`
(`services/orchestration/payment_transaction_failed.rs:123-181`) looks up
`DUNNING_RETRY_SCHEDULE_DAYS.get(failed_attempts.saturating_sub(1) as
usize)` (`:135-136`, schedule `[3, 5, 7]` days, `:22`), where
`failed_attempts` counts Failed/Cancelled attempts already persisted for
this invoice — confirmed to include the CURRENT failure by tracing the
call path: `on_payment_transaction_failed` is driven by an outbox event
(`domain/outbox_event.rs`'s `payment_transaction_saved`/`PaymentTransactionSaved`),
which the transactional-outbox pattern guarantees is only published after
the triggering `payment_transaction` row's `Failed` status is committed —
so `count_failed_for_invoice` (`diesel-models/src/query/payment_transactions.rs:189-214`)
always sees the failure being reacted to.

This is exactly the off-by-one shape this session keeps finding bugs in
elsewhere (`TierPricing.lean`'s underflow, `CouponThreshold.lean`'s early
break) — checked by hand-tracing here and found correct, but pinned as a
proof rather than left as a trace, since the array or the subtraction could
silently drift out of sync on a future edit. `saturating_sub` needs no
separate model: Lean's `Nat` subtraction is *already* truncated at `0`, so
`failedAttempts - 1` in this file is the exact same operation as the real
Rust code's `.saturating_sub(1)`.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- The real lookup (`DUNNING_RETRY_SCHEDULE_DAYS.get(failed_attempts
    .saturating_sub(1))`, `:22,135-136`): `Nat` subtraction is already
    saturating, so `failedAttempts - 1` here is `.saturating_sub(1)`
    verbatim, not an approximation of it. Written as an explicit match on
    the schedule's 3 slots rather than `List.get? [3,5,7]`, so `decide`
    reduces directly instead of getting stuck unfolding `List.get?`'s
    recursion. -/
def dunningDelay (failedAttempts : Nat) : Option Nat :=
  match failedAttempts - 1 with
  | 0 => some 3
  | 1 => some 5
  | 2 => some 7
  | _ => none

/-- Attempt 1 (the first-ever failure) picks the first rung — matching the
    real code's own comment ("attempt 1 picks the first delay"). -/
theorem first_attempt_picks_first_rung : dunningDelay 1 = some 3 := by decide

/-- `failedAttempts = 0` cannot occur in practice (a dunning attempt is only
    scheduled reacting to a failure that was just counted), but the
    saturating subtraction makes it degenerate safely to the same rung as
    attempt 1, not a crash or a wrong rung. -/
theorem zero_attempts_degenerates_to_first_rung : dunningDelay 0 = some 3 := by decide

theorem second_attempt_picks_second_rung : dunningDelay 2 = some 5 := by decide

theorem third_attempt_picks_third_rung : dunningDelay 3 = some 7 := by decide

/-- Exactly at the ladder's length: the 4th failure exhausts retries. -/
theorem fourth_attempt_exhausts_the_ladder : dunningDelay 4 = none := by decide

/-- No attempt count beyond the ladder's length ever revives a delay —
    once exhausted, stays exhausted for every larger attempt count, not
    just the boundary case checked above. -/
theorem exhausted_forever (n : Nat) (h : 4 ≤ n) : dunningDelay n = none := by
  obtain ⟨k, rfl⟩ : ∃ k, n = k + 4 := ⟨n - 4, by omega⟩
  rfl

end MeteroidVerify
