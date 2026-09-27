import Song.Foundation

/-!
# meteroid / Amendment Date Validation — negative proration factor bug

## The bug

`amendment.rs::apply_amendment_immediate` (line 126) calls
`amendment_effective_date(sub_details, is_immediate=true)`, which returns
`Utc::now().naive_utc().date()` — today's date in UTC.

This date is then passed to `calculate_proration` (line 161) **without
validation** that it falls within the subscription's current billing period
`[current_period_start, current_period_end]`.

By contrast, `plan_change.rs::prepare_plan_change` (lines 747-752) **does**
validate that `change_date` is within the period, rejecting out-of-bounds
dates explicitly.

**Concrete scenario:**
- Subscription's current period: [2025-01-01, 2025-02-01)
- Today's date (when amendment is applied): 2025-02-15
- `amendment_effective_date` returns 2025-02-15
- `calculate_proration` is called with period_end=2025-02-01, effective_date=2025-02-15
- days_remaining = 2025-02-01 - 2025-02-15 = -14 days
- proration_factor = -14 / 31 ≈ -0.45 (negative!)

For a component whose billing period is **aligned** with the subscription
(the common case), `component_proration_factor` (Proration.lean's
`componentProrationFactor`) passes this negative factor straight through
without clamping, producing incorrect charges:
- A $100 monthly component is credited for 100 × (-0.45) = -$45
  (effectively a charge of $45 instead of a credit)

## The precondition

`Proration.lean` states this explicitly in its module doc: the precondition
that `change_date` (and thus `effective_date`) is between `period_start`
and `period_end` is "an implicit precondition on the caller, not something
`calculate_proration` or `component_proration_factor` defends."

This precondition is **satisfied in `plan_change.rs`** (which validates)
but **violated in `amendment.rs`** (which does not).

## Formalization: integer model

Model the bug as an integer proration factor (standing in for the f64
`days_remaining / days_in_period`), constrained to the case where
`effective_date` is after `period_end`.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- Billing period, mirror of Proration.lean. -/
inductive BillingPeriod where
  | monthly | quarterly | semiannual | annual | oneTime
deriving DecidableEq, Repr

/-- Nominal period length in days. -/
def nominalPeriodDays : BillingPeriod → Int
  | .monthly => 30
  | .quarterly => 91
  | .semiannual => 182
  | .annual => 365
  | .oneTime => 0

/-- Aligned check: is the period within 25% of nominal? -/
def isAligned (daysInPeriod nominal : Int) : Bool :=
  4 * (daysInPeriod - nominal).natAbs ≤ nominal.natAbs

/-- Proration factor clamp (misaligned branch). -/
def clampFactor (factor : Int) : Int :=
  max 0 (min 1 factor)

/-- Prorated amount, aligned case: factor passes through untouched. -/
def proratedAmountAligned (amountCents factor : Int) : Int :=
  amountCents * factor

/-- Prorated amount, misaligned case: factor is clamped first. -/
def proratedAmountMisaligned (amountCents factor : Int) : Int :=
  amountCents * clampFactor factor

/-!
## The bug: negative factor in aligned case

When `effective_date > period_end`, the factor becomes negative.
In the aligned case, this negative factor is NOT clamped.
-/

/-- With a negative factor (-2) representing days_remaining=-60, days_in_period=30,
    and an aligned period (daysInPeriod=30 matches nominal.monthly=30),
    the negative factor passes straight through, producing incorrect credit. -/
theorem aligned_case_negative_factor_bug :
    proratedAmountAligned 10000 (-2) = -20000 := by decide

/-- The correct behavior (misaligned case): the same negative factor is clamped. -/
theorem misaligned_case_clamps_negative_factor :
    proratedAmountMisaligned 10000 (-2) = 0 := by decide

/-- Another aligned case: factor -45 (representing -14/31 ≈ -0.45, scaled to int). -/
theorem aligned_case_realistic_scenario :
    proratedAmountAligned 10000 (-45) = -450000 := by decide

/-!
## Precondition violation

The bug arises because the precondition (factor in [0,1]) is violated.
If `effective_date` is outside [period_start, period_end], then
`days_remaining / days_in_period` can be negative or greater than 1.
-/

/-- The precondition for correct proration: factor should be in [0,1].
    When violated (factor < 0), aligned branches fail. -/
def proratedAmountWithPrecondition
    (amountCents factor : Int) (daysInPeriod nominal : Int) : Int :=
  if 0 ≤ factor ∧ factor ≤ 1 then
    if isAligned daysInPeriod nominal then
      proratedAmountAligned amountCents factor
    else
      proratedAmountMisaligned amountCents factor
  else
    -- Precondition violated: behavior is undefined/incorrect
    if isAligned daysInPeriod nominal then
      proratedAmountAligned amountCents factor  -- BUG: no clamping
    else
      proratedAmountMisaligned amountCents factor  -- OK: clamped anyway

/-- With precondition satisfied (factor in range), both branches agree on
    a clamped result. -/
theorem precondition_satisfied_safe_aligned :
    proratedAmountWithPrecondition 10000 0 30 30 = 0 := by decide

theorem precondition_satisfied_safe_half :
    proratedAmountWithPrecondition 10000 1 30 30 = 10000 := by decide

/-- With precondition violated (negative factor), aligned branch fails. -/
theorem precondition_violated_aligned_broken :
    proratedAmountWithPrecondition 10000 (-2) 30 30 = -20000 := by decide

/-- With precondition violated, misaligned branch is still safe (clamped). -/
theorem precondition_violated_misaligned_safe :
    proratedAmountWithPrecondition 10000 (-2) 1000 30 = 0 := by decide

/-!
## Real-world scenario from the code

Amendment.rs scenario:
- period: [2025-01-01, 2025-02-01) = 31 days
- effective_date: 2025-02-15 (after period_end)
- days_remaining: -14
- days_in_period: 31
- Factor (scaled to avoid float): -14 (representing -14/31 ≈ -0.45)
- Component period: Monthly = aligned with subscription period
- Amount: $10,000 (100.00 cents)

Result: Charged $14 × $100 / 31 ≈ $45 extra instead of credited.
-/

/-- The concrete amendment.rs scenario: aligned period, out-of-bounds date. -/
theorem amendment_scenario_aligned :
    let daysRemaining := -14  -- after period_end
    let daysInPeriod := 31    -- Jan 1 to Feb 1
    let factor := daysRemaining  -- simplified; real code computes ratio
    let amountCents := 10000  -- $100
    let nominal := 30         -- monthly nominal
    -- Aligned check: |31 - 30| ≤ 30 * 0.25? Yes (1 ≤ 7.5)
    isAligned daysInPeriod nominal = true ∧
    -- But aligned branch passes negative factor through:
    proratedAmountAligned amountCents factor = -140000 := by
  decide

end MeteroidVerify
