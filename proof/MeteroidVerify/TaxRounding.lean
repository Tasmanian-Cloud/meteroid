/-!
# meteroid / TaxRounding — Path B (native Lean, not Aeneas-extracted)

`RESEARCH.md`: `determine_tax_details` (`meteroid-tax/src/shared.rs:56-242`)
computes `Decimal::from(item.amount) * rate_decimal`, rounded via
`round_dp_with_strategy(0, RoundingStrategy::MidpointAwayFromZero)`, where
`rate_decimal` comes from `Decimal::from_f64(rate.rate)`
(`world_tax::TaxRate.rate: f64`, `shared.rs:194-195,217-218`).
`rust_decimal::Decimal` has no Aeneas builtin — extraction was not attempted
for this reason (confirmed impractical alongside the float finding for
proration; see `RESEARCH.md`).

**What is modeled:** round-half-away-from-zero applied to an EXACT integer
ratio `amount * rateNumerator / rateDenominator` — i.e., the intended
arithmetic if the rate were represented exactly as a rational (e.g. `21/100`
for `0.21`), which is what `Decimal::from_f64` produces for a decimal
literal like `0.21` that has a short, exact decimal expansion.

**What is NOT modeled, and is a real, documented gap:** whether
`Decimal::from_f64(rate.rate)` is ALWAYS exact for every real-world tax rate.
`Decimal::from_f64` converts the `f64`'s actual binary value (which may
itself already be an imprecise representation of a decimal literal like
`0.29` — `f64` cannot represent every decimal exactly) using a
shortest-round-trip algorithm; whether that ever disagrees with the "exact
rational the developer intended" for some tax rate in `world-tax`'s database
is an open question this file does not resolve (it would need Aeneas
extraction of `Decimal::from_f64` itself, which needs a `Decimal` builtin
Aeneas doesn't have). What follows is a spot check that the ROUNDING
STRATEGY itself (round-half-away-from-zero) is correctly modeled against the
real hand-verified test cases, not a proof that the rate reaches this
function exactly.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- Round-half-away-from-zero of the exact ratio `numerator / denominator`
    (`denominator > 0`), matching
    `RoundingStrategy::MidpointAwayFromZero` (`shared.rs`) for a
    non-negative ratio (tax amounts and rates in this codebase are always
    non-negative). `2 * numerator + denominator` then integer-dividing by
    `2 * denominator` is the standard round-half-up construction for
    non-negative values. -/
def roundHalfAwayFromZero (numerator denominator : Int) : Int :=
  (2 * numerator + denominator) / (2 * denominator)

/-- `meteroid-tax/src/tests.rs`'s `test_rounding_behavior`: 999 × 0.21 =
    209.79 → rounds UP to 210 (the `.79` fraction is past the midpoint). -/
example : roundHalfAwayFromZero (999 * 21) 100 = 210 := by decide

/-- Same test: 997 × 0.21 = 209.37 → rounds DOWN to 209. -/
example : roundHalfAwayFromZero (997 * 21) 100 = 209 := by decide

/-- The exact midpoint case `.round_dp_with_strategy`'s name promises to
    handle specially: 250.5 (a genuine tie) rounds AWAY from zero, i.e. up,
    not to even. `MidpointAwayFromZero` is explicitly not banker's rounding —
    this pins that distinction. -/
example : roundHalfAwayFromZero (2505 * 10) 100 = 251 := by decide

end MeteroidVerify
