/-!
# meteroid / TrialEndBeforeEffectiveBillingStart — migration mode can produce a backwards period

`services/subscriptions/insert/process.rs`'s migration-mode branch
(`skip_past_invoices = true`, `:340-388`) handles a subscription whose
`end_date` is already in the past (`:363-364`,
`end_date < now.date()`) by computing its final period directly, without
cycle-worker involvement.

For a subscription with a free trial, `effective_billing_start` is computed
as `billing_start_date + trial_days` (`:344-347`). This value — not
`billing_start_date` itself — is passed as the anchor into
`find_period_containing_date(effective_billing_start, end_date, ..)`
(`:374-379`, `utils/periods.rs:187-227`). That function's own first branch
(`periods.rs:193-199`, `if target_date < billing_start_date { ... }`)
degrades gracefully when `end_date < effective_billing_start` — but
`process.rs` doesn't use the period `find_period_containing_date` actually
returns for the END boundary: it sets `current_period_start =
last_period.start` (`:384`, which resolves to `effective_billing_start` in
this branch) but **independently overwrites** `current_period_end =
Some(end_date)` (`:385`) with the raw `end_date`, not
`last_period.end`.

**The bug**: when a migrated subscription's `end_date` falls DURING what
would have been its free trial (`end_date < effective_billing_start`), the
resulting period is `[effective_billing_start, end_date]` with
`effective_billing_start > end_date` — a backwards period, `start > end`.
This is not a contrived edge case: any historical subscription being
migrated in that churned or was cancelled before its trial completed hits
this branch (`skip_past_invoices` exists specifically for backdated/migrated
subscription import).

**What is modeled:** the two date values `process.rs` actually sets
(`effective_billing_start`, `end_date`) and the ordering violation between
them, as exact `Int` day-offsets — not `find_period_containing_date`'s
own internal branching, which is a correctly-defended function; the bug is
entirely in how `process.rs` uses two of its outputs inconsistently
(the START from one call, the END raw and unrelated to it).

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- `effective_billing_start` (`process.rs:344-347`): `billing_start_date + trial_days`. -/
def effectiveBillingStart (billingStart trialDays : Int) : Int :=
  billingStart + trialDays

/-- The period `process.rs` actually constructs in the migration-mode,
    already-ended branch (`:384-385`): start from the trial-adjusted
    anchor, end from the raw `end_date` — two independently-sourced
    values, never checked against each other. -/
def migrationModePeriod (billingStart trialDays endDate : Int) : Int × Int :=
  (effectiveBillingStart billingStart trialDays, endDate)

/-- A period is well-formed when its start doesn't come after its end. -/
def isBackwards (period : Int × Int) : Prop :=
  period.fst > period.snd

/-- **The bug.** Whenever a migrated subscription's `end_date` falls during
    what would have been its free trial, the resulting period is
    backwards — proved for ALL such inputs, not just the witness below. -/
theorem migration_free_trial_period_backwards
    (billingStart trialDays endDate : Int)
    (h : endDate < effectiveBillingStart billingStart trialDays) :
    isBackwards (migrationModePeriod billingStart trialDays endDate) := by
  unfold isBackwards migrationModePeriod
  simp only
  omega

/-- Concrete witness matching the real scenario: billing started day 1,
    a 10-day trial (`effective_billing_start` = day 11), but the
    subscription's own `end_date` was day 5 — cancelled 6 days into what
    would have been a 10-day trial. Real code computes the period
    `[11, 5]`, start after end. -/
theorem concrete_witness_migration_trial_ends_during :
    isBackwards (migrationModePeriod 1 10 5) := by
  unfold isBackwards migrationModePeriod effectiveBillingStart
  decide

/-- The fix's shape: anchor the period at `billing_start_date` (not the
    trial-adjusted `effective_billing_start`) whenever `end_date` falls
    before the trial would have ended — matching what
    `find_period_containing_date`'s own degenerate branch already
    computes for its START boundary; `process.rs` just needs to use it
    for the END boundary too instead of the raw `end_date` unconditionally. -/
def correctedPeriodStart (billingStart trialDays endDate : Int) : Int :=
  if endDate < effectiveBillingStart billingStart trialDays then
    billingStart
  else
    effectiveBillingStart billingStart trialDays

/-- The corrected start is never after `end_date`, given `end_date` is
    itself after `billing_start_date` (a subscription can't end before it
    starts) — so the corrected period is never backwards. -/
theorem corrected_start_never_backwards
    (billingStart trialDays endDate : Int)
    (hstarted : billingStart ≤ endDate) :
    correctedPeriodStart billingStart trialDays endDate ≤ endDate := by
  unfold correctedPeriodStart
  split
  · exact hstarted
  · omega

end MeteroidVerify
