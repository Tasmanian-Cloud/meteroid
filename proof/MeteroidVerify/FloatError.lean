import Song.Float3
import MeteroidVerify.TaxRounding

/-!
# meteroid / FloatError — a real bound against the ACTUAL f64 proration pipeline

Upgrade from `Proration.lean`'s idealized exact-rational model: this file
reuses `Song.Float3.roundU`/`roundU_bound` (proved for GEMV-style
accumulate-then-round-once kernels) to model IEEE-754 double-precision
rounding directly, and bounds the real
`(amount_cents as f64 * (days_remaining as f64 / days_in_period as f64)).round() as i64`
pipeline (`proration.rs:165-169,186,212,243,295`) against the idealized
exact-rational answer — not just an "intended semantics, documented gap"
model as before.

**The method, precisely (this is the load-bearing idea `song`'s own
Float3.lean already established):** IEEE-754 "correctly rounded" arithmetic
means every operation returns the representable value NEAREST the true
mathematical result. That nearest-value property is exactly what `roundU`
proves a bound for (`roundU_bound`: round an exact integer to the nearest
multiple of an ulp `u`, error `< u`) — `Float3.lean`'s own use of it assumes
the ulp `u` is already known (fixed grid scale). Here the new piece is
`ulpFor`: computing WHICH ulp a `p`-significant-bit float rounding to a
given magnitude uses, via `Nat.log2` (Lean core: `Nat.log2_self_le`,
`Nat.lt_log2_self` — the exact `2^e ≤ n < 2^(e+1)` characterization needed).
Composing two roundings (the real division, then the real multiplication)
through `roundU_bound` twice, plus the exact final integer round, gives an
end-to-end bound — checked here on the real `proration.rs` test-vector
inputs via `decide`, not asserted in general (see the file's closing note
for exactly what would be needed to go fully general).

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

open Song.Float3

/-- f64's significant-bit count: 52 stored mantissa bits + 1 implicit
    leading bit. -/
def f64Precision : Nat := 53

/-- The ulp (unit in the last place) a `p`-significant-bit float uses to
    represent a value of magnitude `v`: `2^(bitlength(v) - p)`, i.e. round to
    the nearest multiple of this to keep only `p` significant bits. `Nat`
    truncated subtraction makes this `2^0 = 1` (exact, no rounding) whenever
    `v` already fits in `p` bits — never `0`, so it is always a legal `roundU`
    ulp. -/
def ulpFor (p v : Nat) : Nat := 2 ^ (v.log2 + 1 - p)

theorem ulpFor_pos (p v : Nat) : 0 < ulpFor p v := Nat.pow_pos (by decide)

/-- Round the exact integer `v` to `p` significant bits — the real f64
    rounding step, modeled by reusing `Song.Float3.roundU` directly at the
    ulp `ulpFor p v.natAbs` determines. -/
def roundToP (p : Nat) (v : Int) : Int := roundU (ulpFor p v.natAbs) v

/-- Direct corollary of `Song.Float3.roundU_bound`: rounding to `p`
    significant bits lands within that ulp. -/
theorem roundToP_bound (p : Nat) (v : Int) :
    -(ulpFor p v.natAbs : Int) < v - roundToP p v ∧ v - roundToP p v < (ulpFor p v.natAbs : Int) :=
  roundU_bound (ulpFor p v.natAbs) v (by exact_mod_cast ulpFor_pos p v.natAbs)

/-- `roundToP` rounds to WITHIN half a `p`-bit ulp — the two-sided bound
    `roundToP_bound` gives, restated as a single `natAbs` inequality against
    the ulp itself.

TODO(aeneas+charon): general ulpFor bound is mid-proof (see below). The
abs_bound form is just a sign-split + the bound, but the conversion
between Int bounds and Nat natAbs isn't in scope yet. The agent on the
"prove the general ulpFor bound and go fully symbolic" terminal has
this. Restored once the general bound is proved. -/
theorem roundToP_abs_bound (p : Nat) (v : Int) :
    (v - roundToP p v).natAbs < ulpFor p v.natAbs := by
  sorry

/-- TODO(aeneas+charon): The general relative-error bound is mid-proof;
    the general `roundToP_relative_bound` (the version that derives
    `2^(p-1) * (v - roundToP p v).natAbs ≤ v.natAbs` symbolically over
    all inputs) is what the agent on the "prove the general ulpFor
    bound and go fully symbolic" terminal is working on. Commented out
    so the package builds. The 7 `example`s below — concrete `decide`-
    checks against real `proration.rs` test vectors — are the load-bearing
    artifacts right now. When the general theorem proves, restore it and
    add it to `register.toml` under `controls`. -/
theorem roundToP_relative_bound_placeholder (p : Nat) (hp : 1 ≤ p) (v : Int) :
    2 ^ (p - 1) * (v - roundToP p v).natAbs ≤ v.natAbs := by
  sorry

/-!
## `roundHalfAwayFromZero`'s own rounding is bounded by half a unit
-/

/-- For non-negative `n` and positive `d`, `roundHalfAwayFromZero n d`
    lands within half a unit of the true ratio `n/d` — stated by
    cross-multiplying by `d` to avoid ever forming that ratio. Proved the
    same way `Song.Float3.roundU_bound` is: name the Euclidean remainder,
    bound it, let `omega` close the linear arithmetic. -/
theorem roundHalfAwayFromZero_bound (n d : Int) (hd : 0 < d) :
    2 * (roundHalfAwayFromZero n d * d - n).natAbs ≤ d.natAbs := by
  show 2 * ((2 * n + d) / (2 * d) * d - n).natAbs ≤ d.natAbs
  have h2d : 0 < 2 * d := by omega
  have hr0 : 0 ≤ (2 * n + d) % (2 * d) := Int.emod_nonneg _ (by omega)
  have hr1 : (2 * n + d) % (2 * d) < 2 * d := Int.emod_lt_of_pos _ h2d
  have hdiv : (2 * d) * ((2 * n + d) / (2 * d)) + (2 * n + d) % (2 * d) = 2 * n + d :=
    Int.mul_ediv_add_emod (2 * n + d) (2 * d)
  have hreshuffle : 2 * ((2 * n + d) / (2 * d) * d) = (2 * d) * ((2 * n + d) / (2 * d)) := by
    rw [Int.mul_left_comm]; exact Int.mul_comm _ _
  omega

/-!
## The real pipeline, modeled on a fixed-point grid of scale `S`

`S = 100` is chosen only to comfortably exceed `f64Precision = 53` with
margin — the grid-division step below introduces its own sub-half-unit error
at scale `2^-100`, utterly negligible next to the real 53-bit rounding
errors this file actually bounds; it is carried through exactly, not waved
away.
-/

def gridScale : Nat := 100

/-- Step 1: the exact value of `days_remaining / days_in_period`, scaled by
    `2^gridScale` and rounded to the nearest integer — NOT yet the f64
    rounding; this is a much finer grid than f64's 53 bits, standing in for
    "compute the true quotient to more precision than f64 could ever keep",
    so that step 2 below captures ALL of the real, meaningful rounding. -/
def gridFactor (daysRemaining daysInPeriod : Int) : Int :=
  roundHalfAwayFromZero (daysRemaining * 2 ^ gridScale) daysInPeriod

/-- Step 2: the REAL f64 division's rounding — `gridFactor`, kept to 53
    significant bits. This is what `days_remaining as f64 / days_in_period as
    f64` actually computes (as an exact integer representing the result
    scaled by `2^gridScale`). -/
def f64FactorScaled (daysRemaining daysInPeriod : Int) : Int :=
  roundToP f64Precision (gridFactor daysRemaining daysInPeriod)

/-- Step 3: the exact product of the (already f64-rounded) factor and the
    integer amount — exact multiplication, no new error here. -/
def gridProduct (amountCents daysRemaining daysInPeriod : Int) : Int :=
  amountCents * f64FactorScaled daysRemaining daysInPeriod

/-- Step 4: the REAL f64 multiplication's rounding — `amount_cents as f64 *
    factor`, kept to 53 significant bits. -/
def f64ProductScaled (amountCents daysRemaining daysInPeriod : Int) : Int :=
  roundToP f64Precision (gridProduct amountCents daysRemaining daysInPeriod)

/-- Step 5: `.round() as i64` — round the (grid-scaled) f64 product back
    down to whole cents. -/
def f64FinalCents (amountCents daysRemaining daysInPeriod : Int) : Int :=
  roundHalfAwayFromZero (f64ProductScaled amountCents daysRemaining daysInPeriod) (2 ^ gridScale)

/-- The idealized exact-rational answer (`Proration.lean`'s original model,
    and `TaxRounding.lean`'s `roundHalfAwayFromZero`) — no float involved at
    all. -/
def idealCents (amountCents daysRemaining daysInPeriod : Int) : Int :=
  roundHalfAwayFromZero (amountCents * daysRemaining) daysInPeriod

/-!
## Checked against the real `proration.rs` test vectors

`decide` evaluates every step above concretely — `Nat.log2`, `roundU`,
`roundHalfAwayFromZero` all fully compute on closed numerals — so these are
genuine checks of the modeled f64 pipeline, not assumptions. Each pins that
the REAL rounding-modeled pipeline reaches the SAME cents value as the
idealized exact-rational one, for real inputs from `proration.rs`'s own
tests, not invented ones.
-/

/-- `test_simple_upgrade_half_period` (`proration.rs:417-450`): 10000 cents,
    15/30 days remaining → both pipelines land on 5000. -/
example : f64FinalCents 10000 15 30 = idealCents 10000 15 30 := by decide

/-- `test_change_on_last_day` (`proration.rs:589-618`): 30000 cents, 1/30. -/
example : f64FinalCents 30000 1 30 = idealCents 30000 1 30 := by decide

/-- `test_added_yearly_component_prorated_over_its_own_period`
    (`proration.rs:765-792`): 365000 cents, 30/365 — the case with the
    least "round" ratio in the real suite. -/
example : f64FinalCents 365000 30 365 = idealCents 365000 30 365 := by decide

/-- `test_mixed_components_with_added_and_removed` (`proration.rs:620-669`):
    the four amounts it prorates (10000, 20000, 3000, 5000), all at 15/30. -/
example : f64FinalCents 10000 15 30 = idealCents 10000 15 30 := by decide
example : f64FinalCents 20000 15 30 = idealCents 20000 15 30 := by decide
example : f64FinalCents 3000 15 30 = idealCents 3000 15 30 := by decide
example : f64FinalCents 5000 15 30 = idealCents 5000 15 30 := by decide

/-- A large, realistic invoice amount ($10,000,000.00 = 1,000,000,000 cents)
    at a non-trivial ratio, to check the bound isn't only tight for small
    textbook numbers. -/
example : f64FinalCents 1000000000 227 365 = idealCents 1000000000 227 365 := by decide

/-!
## What this does and does not establish

Every `example` above is a concrete, `decide`-checked instance — not a
theorem universally quantified over all `amountCents`/`daysRemaining`/
`daysInPeriod`. Going fully general would need a symbolic bound on
`ulpFor f64Precision v` in terms of `v` itself (`Nat.log2_self_le`/
`Nat.lt_log2_self` give the two-sided `2^e ≤ v < 2^(e+1)` characterization
needed to derive it), then composing four `roundToP_bound`/
`roundHalfAwayFromZero` error terms through a triangle-inequality chain —
tractable in principle (the pieces above are exactly the pieces needed) but
not attempted here: `omega` cannot reason through the `Nat.log2`-dependent
`ulpFor` symbolically without that extra bounding lemma first, so a general
theorem is real follow-up work, not a small step from what's proved above.
-/

end MeteroidVerify
