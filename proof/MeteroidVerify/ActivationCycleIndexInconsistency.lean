-- Bug #22: Subscription activation cycle_index inconsistency
--
-- Two independent activation paths set cycle_index differently for the same business state:
-- - activate_subscription_manual without trial: cycle_index = 1
-- - activate_subscription_after_payment (any type including no-trial): cycle_index = 0
--
-- cycle_index == 0 has special semantic meaning in periods.rs:
-- Triggers proration-factor calculation instead of arrear-period calculation.
-- This causes the same "newly activated subscription" business intent to compute
-- different billing-period proration factors depending on which activation path handled it.
--
-- File: subscriptions/activate.rs, lines 60-115 (manual) vs 203-214 (payment)
-- Real impact: proration factor mismatch for first billing cycle

namespace MeteroidVerify

-- Model: Two activation paths with inconsistent cycle_index for no-trial case
--
-- Path A: activate_subscription_manual (no trial)
-- Sets: status=Active, cycle_index=1, next_cycle_action=RenewSubscription
--
-- Path B: activate_subscription_after_payment (no trial)
-- Sets: status=Active, cycle_index=0, next_cycle_action=RenewSubscription
--
-- Both lead to the same subscription state (Active, RenewSubscription) but
-- different cycle_index values, triggering different proration logic.

def manual_activation_no_trial_cycle_index : Int := 1
def payment_activation_no_trial_cycle_index : Int := 0

theorem activation_cycle_index_inconsistency_for_no_trial :
    manual_activation_no_trial_cycle_index ≠ payment_activation_no_trial_cycle_index := by
  decide

-- The cycle_index value gates proration-vs-arrear logic in periods.rs (periods.rs ~line 224-237):
-- if cycle_index == 0 then compute_proration_factor else None
-- if cycle_index == 0 then None else compute_arrear_period
--
-- Since the two paths set different values, the same subscription state
-- triggers different billing-period calculations.

def cycle_index_zero_gates_proration (idx : Int) : Bool :=
  idx == 0

theorem paths_diverge_on_proration_gate :
    cycle_index_zero_gates_proration manual_activation_no_trial_cycle_index ≠
    cycle_index_zero_gates_proration payment_activation_no_trial_cycle_index := by
  simp [cycle_index_zero_gates_proration, manual_activation_no_trial_cycle_index, payment_activation_no_trial_cycle_index]

-- This violates the principle that identical business intent (activate a new subscription
-- with no trial, transitioning to Active status) should produce identical billing state.
-- The proration factor for the first billing period will differ based on which codepath
-- the subscription took.

theorem bug_impacts_proration_factor_calculation :
    (cycle_index_zero_gates_proration manual_activation_no_trial_cycle_index = true ∧
     cycle_index_zero_gates_proration payment_activation_no_trial_cycle_index = false) ∨
    (cycle_index_zero_gates_proration manual_activation_no_trial_cycle_index = false ∧
     cycle_index_zero_gates_proration payment_activation_no_trial_cycle_index = true) := by
  decide

end MeteroidVerify
