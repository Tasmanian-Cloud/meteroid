/-!
# meteroid / SlotBounds — the bounds check is correct, but one mutation path skips it

`validate_slot_limits` (`repositories/subscriptions/slots.rs:211-239`) checks
a new slot/seat count against `min_slots`/`max_slots` (`new_slot_count =
active_slots + delta`, rejecting `new_slot_count < min` or `> max` —
inclusive both ends, no off-by-one). This file proves that check itself is
exactly the intended `[min, max]` range predicate.

**The real gap, documented like `SubscriptionStatus.lean`'s (a call-graph
fact about real Rust, not something a pure arithmetic theorem states):**
grepping every call site of `validate_slot_limits` in
`services/subscriptions/slots.rs` finds exactly two —
`preview_slot_update` (`:668`) and `complete_slot_upgrade_checkout` (`:807`).
**`update_subscription_slots` (`:37-173`) — the actual mutation entrypoint
for `Optimistic` upgrades and every downgrade (`:78-100`, which calls
`add_slot_transaction_tx` directly) — never calls it.** Any caller reaching
`update_subscription_slots` without first routing through one of the two
validating functions can push a subscription's slot count outside
`[min_slots, max_slots]` with zero enforcement. This is sharper than
`SubscriptionStatus.lean`'s "no centralized guard exists" finding: here the
guard function exists, is correct, and is simply not wired into one of its
three real call sites.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- `new_slot_count` (`slots.rs:216`). -/
def newSlotCount (active delta : Int) : Int := active + delta

/-- Verbatim (`slots.rs:211-239`): accepts `newCount` iff it is within
    `[min, max]` (either bound `none` = unbounded, matching `Option<u32>`). -/
def validSlotCount (min max : Option Int) (newCount : Int) : Bool :=
  (match min with | some m => decide (newCount ≥ m) | none => true) &&
  (match max with | some m => decide (newCount ≤ m) | none => true)

/-- The check accepts exactly `[min, max]`, both bounds inclusive — no
    off-by-one in either the real `<`/`>` comparisons or this model. -/
theorem validSlotCount_iff (min max newCount : Int) :
    validSlotCount (some min) (some max) newCount = true ↔ min ≤ newCount ∧ newCount ≤ max := by
  unfold validSlotCount
  simp

/-- Concrete instance: a downgrade that violates `min_slots` — the exact
    shape of input `update_subscription_slots`'s downgrade path
    (`slots.rs:78-100`) would apply with zero check, since it never calls
    `validate_slot_limits` at all. This does not (cannot) prove the Rust
    control-flow gap itself — that's the module doc above, backed by the
    grep — it proves the check FUNCTION would correctly reject this input,
    underscoring that the gap is a missing call, not a wrong check. -/
example : validSlotCount (some 5) none (newSlotCount 5 (-1)) = false := by decide

end MeteroidVerify
