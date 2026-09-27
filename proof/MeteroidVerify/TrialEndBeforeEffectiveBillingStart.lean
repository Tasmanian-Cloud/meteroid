-- Bug #17: Migration mode free trial ending before effective billing start
--
-- In process.rs, when a subscription with a free trial is created in migration mode
-- (skip_past_invoices=true) and the subscription end_date is during the trial period,
-- the code computes effective_billing_start as start_date + trial_days.
--
-- Then it calls find_period_containing_date(effective_billing_start, end_date, ...),
-- but end_date < effective_billing_start, so find_period_containing_date returns
-- the first period at effective_billing_start. The result is:
-- - current_period_start = effective_billing_start
-- - current_period_end = end_date
--
-- This creates a backwards period where start > end.
--
-- Concrete example:
-- - start_date = 2024-01-01
-- - trial_days = 10
-- - subscription.end_date = 2024-01-05 (during trial)
-- - now = 2024-02-01
-- - billing_day_anchor = 1
--
-- Expected: period should be [2024-01-01, 2024-01-05]
-- Actual: period is [2024-01-11, 2024-01-05] (backwards!)

import Std
import Lean

def ConcreteDate : Type := Nat

def dateAdd (d : ConcreteDate) (days : Nat) : ConcreteDate := d + days
def dateBeforeLess (d1 d2 : ConcreteDate) : Prop := d1 < d2

structure PeriodBounds where
  start : ConcreteDate
  end_ : ConcreteDate

def isValidPeriod (p : PeriodBounds) : Prop := p.start < p.end_

def trialEndsBefore billStart trialDays endDate : Prop :=
  dateBeforeLess endDate (dateAdd billStart trialDays)

-- Theorem: When a migration-mode free trial subscription ends during the trial,
-- the period computation produces a backwards period (start >= end_).
theorem migration_free_trial_period_backwards :
    ∀ billStart trialDays endDate : Nat,
    trialEndsBefore billStart trialDays endDate →
    ¬isValidPeriod ⟨dateAdd billStart trialDays, endDate⟩ := by
  intro billStart trialDays endDate h
  unfold trialEndsBefore dateAdd at h
  unfold isValidPeriod
  simp at h ⊢
  omega

-- Concrete instance: The bug witness from process.rs
theorem concrete_witness_migration_trial_ends_during :
    let billStart : Nat := 1  -- 2024-01-01 as day 1
    let trialDays : Nat := 10
    let endDate : Nat := 5    -- 2024-01-05
    let effectiveBillStart := dateAdd billStart trialDays
    ¬isValidPeriod ⟨effectiveBillStart, endDate⟩ := by
  unfold isValidPeriod dateAdd
  norm_num

-- The root cause: using effective_billing_start (post-trial) to compute
-- a period that should anchor to billing_start_date (pre-trial) when
-- end_date is during the trial.
def incorrectPeriodStart (billStart trialDays : Nat) : Nat :=
  dateAdd billStart trialDays  -- Should be billStart when end_date < trial_end

def correctPeriodStart (billStart endDate trialDays : Nat) : Nat :=
  if dateBeforeLess endDate (dateAdd billStart trialDays) then
    billStart  -- Use billing_start_date, not effective_billing_start
  else
    dateAdd billStart trialDays

-- The correct behavior always produces a valid period
theorem correct_computation_maintains_period_validity :
    ∀ billStart trialDays endDate : Nat,
    endDate > 0 →
    dateBeforeLess billStart endDate →
    isValidPeriod ⟨correctPeriodStart billStart endDate trialDays, endDate⟩ := by
  intro billStart trialDays endDate _hpos _hbefore
  unfold correctPeriodStart isValidPeriod dateAdd
  split <;> omega
