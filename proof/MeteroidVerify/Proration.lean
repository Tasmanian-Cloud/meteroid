import Song.Foundation

/-!
# meteroid / Proration — Path B (native Lean, not Aeneas-extracted)

`RESEARCH.md` records why: a real, working Charon+Aeneas toolchain was
brought up and a genuine extraction attempt was made on this exact code
(`proration.rs`'s `nominal_period_days`/`component_proration_factor` and the
real inlined `(amount as f64 * factor).round() as i64` pattern at
`proration.rs:186,212,243,295`) — it failed with a confirmed structural
cause: Aeneas's interpreter (`~/Workspace/aeneas/src/interp/InterpExpressions.ml`)
has no `TFloat` case in its constant/binop evaluators at all. This file is
the disclosed substitute: a hand-transcribed native-Lean model against
`Song.Foundation`, cross-checked by test vectors
(`vectors/proration_tax.json`, ported from `proration.rs`'s own 15 tests),
not machine-verified against the real f64 bytes.

**What is modeled exactly, not approximated:** `nominal_period_days`'s four
non-`OneTime` values (30.0, 91.0, 182.0, 365.0) are exact integers in the
real f64 code too — no float/int gap there. The real
`(days_in_period - nominal).abs() <= nominal * 0.25` comparison
(`proration.rs:108`) is reproduced EXACTLY (not approximated) by scaling
×4: `nominal * 0.25` is exact for all four real nominal values (7.5, 22.75,
45.5, 91.25 — each a whole number of quarters), so `4 * |diff| ≤ nominal` is
the identical comparison, not a rounding of it.

**What is NOT modeled:** how `baseFactor` itself is computed
(`proration.rs:165-169`'s `days_remaining / days_in_period`, itself `f64`
and never clamped by its caller) — it is a parameter here, exactly as it is
a parameter to the real `component_proration_factor`. The exact rounding
convention of `.round() as i64` is likewise not modeled bit-for-bit; the
conservation theorem below states a bound that holds under ANY standard
rounding convention, precisely to avoid needing one.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- Structural mirror of `SubscriptionFeeBillingPeriod`
    (`meteroid-store/src/domain/enums.rs`). -/
inductive BillingPeriod where
  | monthly | quarterly | semiannual | annual | oneTime
deriving DecidableEq, Repr

/-- Verbatim (`proration.rs:78-86`). -/
def nominalPeriodDays : BillingPeriod → Int
  | .monthly => 30
  | .quarterly => 91
  | .semiannual => 182
  | .annual => 365
  | .oneTime => 0

/-- The real `(days_in_period - nominal).abs() <= nominal * 0.25` comparison
    (`proration.rs:108`), scaled ×4 to stay in `Int` — see module doc for why
    this is exact, not approximate, for the four real nominal values. -/
def isAligned (daysInPeriod nominal : Int) : Bool :=
  4 * (daysInPeriod - nominal).natAbs ≤ nominal.natAbs

/-- `component_proration_factor` (`proration.rs:96-113`), mirrored exactly,
    including the asymmetry the theorems below formalize: the aligned branch
    returns `baseFactor` untouched, the misaligned branch clamps to `[0,1]`
    via `max 0 (min 1 ·)` — the real `.clamp(0.0, 1.0)`. -/
def componentProrationFactor
    (period : BillingPeriod) (daysInPeriod baseFactor : Int) : Int :=
  let nominal := nominalPeriodDays period
  if nominal ≤ 0 then baseFactor
  else if isAligned daysInPeriod nominal then baseFactor
  else max 0 (min 1 baseFactor)

/-!
## The real asymmetry, formalized

`proration.rs` never itself checks that `baseFactor` (the real
`proration_factor = days_remaining / days_in_period`, `proration.rs:165-169`)
is in `[0,1]` — that is an implicit precondition on the caller (`change_date`
between `period_start` and `period_end`), not something `calculate_proration`
or `component_proration_factor` defends. If that precondition is ever
violated (a timezone bug, a bad migration, dates passed out of order), the
ALIGNED branch — the common case, since most components share the
subscription's own billing cadence — silently propagates an out-of-range
factor straight into a real dollar amount. The MISALIGNED branch cannot: it
clamps unconditionally.

Both theorems below use the SAME out-of-range `baseFactor = 2` (representing
what `days_remaining / days_in_period` would be if, say, `days_remaining =
60` when `days_in_period = 30` — invalid, but not excluded by this
function's types) against two different `daysInPeriod` values, to isolate
the branch decision as the only variable.
-/

/-- Aligned case (`daysInPeriod = 30 = nominal .monthly`): the out-of-range
    factor `2` passes straight through. -/
theorem aligned_branch_can_escape_unit_interval :
    componentProrationFactor .monthly 30 2 = 2 := by decide

/-- Misaligned case (`daysInPeriod = 1000`, far from `nominal .monthly = 30`):
    the SAME out-of-range factor `2` is clamped to `1`. -/
theorem misaligned_branch_clamps_out_of_range_factor :
    componentProrationFactor .monthly 1000 2 = 1 := by decide

/-!
## Conservation, under the idealized exact ratio

The real inlined pattern (`proration.rs:186,212,243,295`) is
`(amount_cents as f64 * factor).round() as i64`. Modeled here at the level
of an idealized exact ratio `p / q` (not a float, and not committing to one
rounding convention — round-half-up vs round-half-even doesn't change
whether the *unrounded* product stays within bounds, which is the property
below): given `0 ≤ p ≤ q` (the factor is a valid fraction of the full
period) and a non-negative amount, the prorated product never exceeds the
full-period product. Stated multiplicatively (`amount * p ≤ amount * q`
rather than dividing) specifically so it needs no rounding semantics at all.
-/

theorem prorated_product_never_exceeds_full_period_product
    (amountCents p q : Int) (hp : 0 ≤ p) (hpq : p ≤ q) (hamt : 0 ≤ amountCents) :
    0 ≤ amountCents * p ∧ amountCents * p ≤ amountCents * q := by
  constructor
  · exact Int.mul_nonneg hamt hp
  · exact Int.mul_le_mul_of_nonneg_left hpq hamt

/-- Spot-check against the real `test_simple_upgrade_half_period`
    (`proration.rs:417-450`): 15/30 remaining, old amount 10000 cents. The
    unrounded product `10000 * 15 = 150000` sits between `0` and the
    full-period product `10000 * 30 = 300000`, matching
    `prorated_product_never_exceeds_full_period_product` on the real test's
    own numbers. -/
example : (0 : Int) ≤ 10000 * 15 ∧ (10000 : Int) * 15 ≤ 10000 * 30 := by decide

end MeteroidVerify
