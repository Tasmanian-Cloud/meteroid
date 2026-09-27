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
`roundToP_relative_bound` below composes these into the general, fully
symbolic IEEE-754 unit-roundoff bound (`error ≤ v * 2^(1-p)`, derived, not
assumed) — the real bound Coq's Flocq library exists specifically to
provide; this file builds the narrow slice of it actually needed here from
scratch, on top of `song`'s existing `roundU`.

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

/-- `roundToP` rounds to WITHIN the `p`-bit ulp — `roundToP_bound`'s two-sided
    `Int` inequality restated as a single `natAbs` bound. -/
theorem roundToP_abs_bound (p : Nat) (v : Int) :
    (v - roundToP p v).natAbs < ulpFor p v.natAbs := by
  have ⟨h1, h2⟩ := roundToP_bound p v
  omega

/-- **The general relative-error bound**: rounding to `p` significant bits
    (`p ≥ 1`) moves `v` by at most a `2^(1-p)` fraction of `|v|` — the
    standard IEEE-754 "unit roundoff" bound, derived here (not assumed) from
    `Nat.log2`'s real spec (`Nat.log2_self_le`) and `roundToP_abs_bound`.
    Two cases: if `v` already fits in fewer than `p` bits the rounding is
    exact (error `0`); otherwise the ulp itself is `2^(v.natAbs.log2)`
    scaled by `2^(1-p)`, and `Nat.log2_self_le` bounds that by `v.natAbs`. -/
theorem roundToP_relative_bound (p : Nat) (hp : 1 ≤ p) (v : Int) :
    2 ^ (p - 1) * (v - roundToP p v).natAbs ≤ v.natAbs := by
  by_cases h0 : v.natAbs = 0
  · have hbound := roundToP_abs_bound p v
    have hlog0 : Nat.log2 0 = 0 := by decide
    have hulp1 : ulpFor p v.natAbs = 1 := by
      unfold ulpFor
      rw [h0, hlog0]
      have : (0 : Nat) + 1 - p = 0 := by omega
      rw [this]
    have herr0 : (v - roundToP p v).natAbs = 0 := by omega
    rw [herr0, Nat.mul_zero]
    exact Nat.zero_le _
  · by_cases halign : p ≤ v.natAbs.log2 + 1
    · have hulp_eq : 2 ^ (p - 1) * ulpFor p v.natAbs = 2 ^ v.natAbs.log2 := by
        unfold ulpFor
        rw [← Nat.pow_add]
        congr 1
        omega
      have hbound := roundToP_abs_bound p v
      have hle : 2 ^ v.natAbs.log2 ≤ v.natAbs := Nat.log2_self_le h0
      have hpow_pos : 0 < 2 ^ (p - 1) := Nat.pow_pos (by decide)
      have step1 : 2 ^ (p - 1) * (v - roundToP p v).natAbs < 2 ^ (p - 1) * ulpFor p v.natAbs :=
        (Nat.mul_lt_mul_left hpow_pos).mpr hbound
      apply Nat.le_of_lt
      calc 2 ^ (p - 1) * (v - roundToP p v).natAbs
          < 2 ^ (p - 1) * ulpFor p v.natAbs := step1
        _ = 2 ^ v.natAbs.log2 := hulp_eq
        _ ≤ v.natAbs := hle
    · have hulp1 : ulpFor p v.natAbs = 1 := by
        unfold ulpFor
        have : v.natAbs.log2 + 1 - p = 0 := by omega
        rw [this]
      have hbound := roundToP_abs_bound p v
      have herr0 : (v - roundToP p v).natAbs = 0 := by omega
      rw [herr0, Nat.mul_zero]
      exact Nat.zero_le _

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

/-- Pure bookkeeping: `2*b*(2^k*X) = 2^(k+1)*(b*X)` — the associativity/
    commutativity reshuffle `omega` cannot do on its own (it treats
    syntactically distinct products as unrelated atoms), proved by hand
    since `ring`/`ring_nf` aren't available without Mathlib. -/
private theorem two_mul_pow_reassoc (b X k : Nat) : 2 * b * (2 ^ k * X) = 2 ^ (k + 1) * (b * X) := by
  have hpow : (2 : Nat) ^ (k + 1) = 2 ^ k * 2 := by rw [Nat.pow_add]
  calc 2 * b * (2 ^ k * X)
      = 2 * (b * (2 ^ k * X)) := Nat.mul_assoc 2 b (2 ^ k * X)
    _ = 2 * (2 ^ k * (b * X)) := by rw [Nat.mul_left_comm b (2 ^ k) X]
    _ = 2 * 2 ^ k * (b * X) := (Nat.mul_assoc 2 (2 ^ k) (b * X)).symm
    _ = 2 ^ k * 2 * (b * X) := by rw [Nat.mul_comm 2 (2 ^ k)]
    _ = 2 ^ (k + 1) * (b * X) := by rw [hpow]

/-- Pure bookkeeping: `2^(k+1)*X = 2^k*(2*X)` — same reason as
    `two_mul_pow_reassoc`, a second shape of the same reassociation. -/
private theorem pow_succ_mul_reassoc (X k : Nat) : 2 ^ (k + 1) * X = 2 ^ k * (2 * X) := by
  have hpow : (2 : Nat) ^ (k + 1) = 2 ^ k * 2 := by rw [Nat.pow_add]
  rw [hpow]; exact Nat.mul_assoc (2 ^ k) 2 X

/-- **Composed bound, steps 1+2**: the f64-modeled division stays close to
    the true ratio `daysRemaining/daysInPeriod`, scaled by the grid —
    cross-multiplied by `daysInPeriod` to avoid ever forming that ratio.
    Chains `roundHalfAwayFromZero_bound` (the grid step's own error) and
    `roundToP_relative_bound` (the real 53-bit rounding's error, scaled by
    `daysInPeriod`) through the triangle inequality
    (`f64Factor*b - a*G = (f64Factor*b - gridFactor*b) + (gridFactor*b -
    a*G)`). Not simplified to eliminate `gridFactor` from the bound — it
    remains a well-defined auxiliary quantity, not a circularity. -/
theorem f64_division_accurate (a b : Int) (hb : 0 < b) :
    2 ^ f64Precision * (f64FactorScaled a b * b - a * 2 ^ gridScale).natAbs ≤
      2 * (b.natAbs * (gridFactor a b).natAbs) + 2 ^ (f64Precision - 1) * b.natAbs := by
  unfold f64FactorScaled
  generalize hgf : gridFactor a b = gf
  generalize hff : roundToP f64Precision gf = ff
  have hp1 : f64Precision - 1 + 1 = f64Precision := by decide
  have hstep2 : 2 ^ (f64Precision - 1) * (gf - ff).natAbs ≤ gf.natAbs := by
    have h := roundToP_relative_bound f64Precision (by decide) gf
    rwa [hff] at h
  have hstep1 : 2 * (gf * b - a * 2 ^ gridScale).natAbs ≤ b.natAbs := by
    have h : 2 * (gridFactor a b * b - a * 2 ^ gridScale).natAbs ≤ b.natAbs :=
      roundHalfAwayFromZero_bound (a * 2 ^ gridScale) b hb
    rwa [hgf] at h
  have hsplit : ff * b - a * 2 ^ gridScale = (ff * b - gf * b) + (gf * b - a * 2 ^ gridScale) := by
    omega
  have htri : (ff * b - a * 2 ^ gridScale).natAbs ≤
      (ff * b - gf * b).natAbs + (gf * b - a * 2 ^ gridScale).natAbs := by
    rw [hsplit]; exact Int.natAbs_add_le _ _
  have hreshuf1 : ff * b - gf * b = -(b * (gf - ff)) := by
    rw [Int.mul_sub, Int.mul_comm b gf, Int.mul_comm b ff]; omega
  have hcast1 : (ff * b - gf * b).natAbs = b.natAbs * (gf - ff).natAbs := by
    rw [hreshuf1, Int.natAbs_neg, Int.natAbs_mul]
  have hscaled2 : 2 ^ f64Precision * (b.natAbs * (gf - ff).natAbs) ≤ 2 * (b.natAbs * gf.natAbs) := by
    have hmul := Nat.mul_le_mul (Nat.le_refl (2 * b.natAbs)) hstep2
    have hreassoc := two_mul_pow_reassoc b.natAbs (gf - ff).natAbs (f64Precision - 1)
    have hassoc2 : (2 * b.natAbs) * gf.natAbs = 2 * (b.natAbs * gf.natAbs) := Nat.mul_assoc 2 b.natAbs gf.natAbs
    rw [hp1] at hreassoc
    omega
  have hscaled1 : 2 ^ f64Precision * (gf * b - a * 2 ^ gridScale).natAbs ≤
      2 ^ (f64Precision - 1) * b.natAbs := by
    have hreassoc := pow_succ_mul_reassoc (gf * b - a * 2 ^ gridScale).natAbs (f64Precision - 1)
    rw [hp1] at hreassoc
    have hmul := Nat.mul_le_mul (Nat.le_refl (2 ^ (f64Precision - 1))) hstep1
    omega
  calc 2 ^ f64Precision * (ff * b - a * 2 ^ gridScale).natAbs
      ≤ 2 ^ f64Precision * ((ff * b - gf * b).natAbs + (gf * b - a * 2 ^ gridScale).natAbs) :=
        Nat.mul_le_mul (Nat.le_refl _) htri
    _ = 2 ^ f64Precision * (ff * b - gf * b).natAbs + 2 ^ f64Precision * (gf * b - a * 2 ^ gridScale).natAbs :=
        Nat.mul_add _ _ _
    _ ≤ 2 * (b.natAbs * gf.natAbs) + 2 ^ (f64Precision - 1) * b.natAbs := by
        rw [hcast1]; omega

/-- Step 3: the exact product of the (already f64-rounded) factor and the
    integer amount — exact multiplication, no new error here. -/
def gridProduct (amountCents daysRemaining daysInPeriod : Int) : Int :=
  amountCents * f64FactorScaled daysRemaining daysInPeriod

/-- Step 4: the REAL f64 multiplication's rounding — `amount_cents as f64 *
    factor`, kept to 53 significant bits. -/
def f64ProductScaled (amountCents daysRemaining daysInPeriod : Int) : Int :=
  roundToP f64Precision (gridProduct amountCents daysRemaining daysInPeriod)

/-- **Composed bound, steps 1-4**: the f64-modeled division AND
    multiplication together stay close to the true product `amt*a`, scaled
    by the grid. Chains `f64_division_accurate` (scaled by `amt`) and
    `roundToP_relative_bound` (applied to the multiplication) through the
    triangle inequality, the same shape `f64_division_accurate` itself
    uses. -/
theorem f64_product_accurate (amt a b : Int) (hb : 0 < b) :
    2 ^ f64Precision * (f64ProductScaled amt a b * b - amt * a * 2 ^ gridScale).natAbs ≤
      amt.natAbs * (2 * (b.natAbs * (gridFactor a b).natAbs) + 2 ^ (f64Precision - 1) * b.natAbs) +
      2 * (b.natAbs * (gridProduct amt a b).natAbs) := by
  unfold f64ProductScaled gridProduct
  generalize hff : f64FactorScaled a b = ff
  generalize hfp : roundToP f64Precision (amt * ff) = fp
  have hp1 : f64Precision - 1 + 1 = f64Precision := by decide
  have hdiv := f64_division_accurate a b hb
  rw [hff] at hdiv
  have hstep4 : 2 ^ (f64Precision - 1) * (amt * ff - fp).natAbs ≤ (amt * ff).natAbs := by
    have h := roundToP_relative_bound f64Precision (by decide) (amt * ff)
    rwa [hfp] at h
  have hkey1 : amt * ff * b - amt * a * 2 ^ gridScale = amt * (ff * b - a * 2 ^ gridScale) := by
    rw [Int.mul_sub]; simp only [Int.mul_assoc]
  have hcast_amt : (amt * (ff * b - a * 2 ^ gridScale)).natAbs =
      amt.natAbs * (ff * b - a * 2 ^ gridScale).natAbs := Int.natAbs_mul _ _
  have hdiv_scaled : 2 ^ f64Precision * (amt.natAbs * (ff * b - a * 2 ^ gridScale).natAbs) ≤
      amt.natAbs * (2 * (b.natAbs * (gridFactor a b).natAbs) + 2 ^ (f64Precision - 1) * b.natAbs) := by
    have hmul := Nat.mul_le_mul (Nat.le_refl amt.natAbs) hdiv
    have hassoc : amt.natAbs * (2 ^ f64Precision * (ff * b - a * 2 ^ gridScale).natAbs) =
        2 ^ f64Precision * (amt.natAbs * (ff * b - a * 2 ^ gridScale).natAbs) :=
      Nat.mul_left_comm amt.natAbs (2 ^ f64Precision) _
    omega
  have hsplit : fp * b - amt * a * 2 ^ gridScale =
      (fp * b - amt * ff * b) + (amt * ff * b - amt * a * 2 ^ gridScale) := by omega
  have htri : (fp * b - amt * a * 2 ^ gridScale).natAbs ≤
      (fp * b - amt * ff * b).natAbs + (amt * ff * b - amt * a * 2 ^ gridScale).natAbs := by
    rw [hsplit]; exact Int.natAbs_add_le _ _
  have hreshuf2 : fp * b - amt * ff * b = -(b * (amt * ff - fp)) := by
    rw [Int.mul_sub, Int.mul_comm b (amt * ff), Int.mul_comm b fp]; omega
  have hcast2 : (fp * b - amt * ff * b).natAbs = b.natAbs * (amt * ff - fp).natAbs := by
    rw [hreshuf2, Int.natAbs_neg, Int.natAbs_mul]
  have hscaled4 : 2 ^ f64Precision * (b.natAbs * (amt * ff - fp).natAbs) ≤
      2 * (b.natAbs * (amt * ff).natAbs) := by
    have hmul := Nat.mul_le_mul (Nat.le_refl (2 * b.natAbs)) hstep4
    have hreassoc := two_mul_pow_reassoc b.natAbs (amt * ff - fp).natAbs (f64Precision - 1)
    have hassoc2 : (2 * b.natAbs) * (amt * ff).natAbs = 2 * (b.natAbs * (amt * ff).natAbs) :=
      Nat.mul_assoc 2 b.natAbs _
    rw [hp1] at hreassoc
    omega
  calc 2 ^ f64Precision * (fp * b - amt * a * 2 ^ gridScale).natAbs
      ≤ 2 ^ f64Precision * ((fp * b - amt * ff * b).natAbs + (amt * ff * b - amt * a * 2 ^ gridScale).natAbs) :=
        Nat.mul_le_mul (Nat.le_refl _) htri
    _ = 2 ^ f64Precision * (fp * b - amt * ff * b).natAbs +
        2 ^ f64Precision * (amt * ff * b - amt * a * 2 ^ gridScale).natAbs :=
        Nat.mul_add _ _ _
    _ = 2 ^ f64Precision * (b.natAbs * (amt * ff - fp).natAbs) +
        2 ^ f64Precision * (amt.natAbs * (ff * b - a * 2 ^ gridScale).natAbs) := by
        rw [hcast2, hkey1, hcast_amt]
    _ ≤ amt.natAbs * (2 * (b.natAbs * (gridFactor a b).natAbs) + 2 ^ (f64Precision - 1) * b.natAbs) +
        2 * (b.natAbs * (amt * ff).natAbs) := by omega

/-- Step 5: `.round() as i64` — round the (grid-scaled) f64 product back
    down to whole cents. -/
def f64FinalCents (amountCents daysRemaining daysInPeriod : Int) : Int :=
  roundHalfAwayFromZero (f64ProductScaled amountCents daysRemaining daysInPeriod) (2 ^ gridScale)

/-- The idealized exact-rational answer (`Proration.lean`'s original model,
    and `TaxRounding.lean`'s `roundHalfAwayFromZero`) — no float involved at
    all. -/
def idealCents (amountCents daysRemaining daysInPeriod : Int) : Int :=
  roundHalfAwayFromZero (amountCents * daysRemaining) daysInPeriod

/-- **The full end-to-end bound.** `f64FinalCents` (the real, f64-rounding-
    modeled pipeline) differs from `idealCents` (the exact-rational answer)
    by an amount bounded by an explicit, fully derived expression — cross-
    multiplied by `2^f64Precision * (2^gridScale).natAbs * b.natAbs` to
    avoid ever dividing. The bound composes three independent roundings
    (`f64FinalCents`'s own final round, `f64_product_accurate`'s division+
    multiplication error, `idealCents`'s own rounding) via the triangle
    inequality: `fc*G*b - ic*G*b = (fc*G-fp)*b + (fp*b-amt*a*G) -
    (ic*b-amt*a)*G`. The RHS's `2^f64Precision*(2^gridScale).natAbs*b.natAbs`
    term (from the two independent final-rounding steps, each contributing
    up to half a unit that combine to exactly one full unit at this scale)
    is not a slack term to be tightened away — it is the real, expected
    shape: two independently-rounded integers can differ by up to 1 even
    with zero propagated float error, which is exactly the real-world
    floating-point behavior this bound reflects, not a proof artifact. -/
theorem f64_pipeline_bound (amt a b : Int) (hb : 0 < b) :
    2 ^ f64Precision * ((f64FinalCents amt a b - idealCents amt a b).natAbs *
        ((2:Int) ^ gridScale).natAbs * b.natAbs) ≤
      2 ^ f64Precision * (((2:Int) ^ gridScale).natAbs * b.natAbs) +
      (amt.natAbs * (2 * (b.natAbs * (gridFactor a b).natAbs) + 2 ^ (f64Precision - 1) * b.natAbs) +
        2 * (b.natAbs * (gridProduct amt a b).natAbs)) := by
  unfold f64FinalCents idealCents
  have hp1 : f64Precision - 1 + 1 = f64Precision := by decide
  have hG : (0 : Int) < (2:Int) ^ gridScale := by decide
  generalize hfp : f64ProductScaled amt a b = fp
  generalize hfc : roundHalfAwayFromZero fp ((2:Int) ^ gridScale) = fc
  generalize hic : roundHalfAwayFromZero (amt * a) b = ic
  have hprod : 2 ^ f64Precision * (fp * b - amt * a * (2:Int) ^ gridScale).natAbs ≤
      amt.natAbs * (2 * (b.natAbs * (gridFactor a b).natAbs) + 2 ^ (f64Precision - 1) * b.natAbs) +
        2 * (b.natAbs * (gridProduct amt a b).natAbs) := by
    have h := f64_product_accurate amt a b hb
    rwa [hfp] at h
  have hA : 2 * (fc * (2:Int) ^ gridScale - fp).natAbs ≤ ((2:Int) ^ gridScale).natAbs := by
    have h := roundHalfAwayFromZero_bound fp ((2:Int) ^ gridScale) hG
    rwa [hfc] at h
  have hC : 2 * (ic * b - amt * a).natAbs ≤ b.natAbs := by
    have h := roundHalfAwayFromZero_bound (amt * a) b hb
    rwa [hic] at h
  have e1 : (fc * (2:Int) ^ gridScale - fp) * b = fc * (2:Int) ^ gridScale * b - fp * b := Int.sub_mul _ _ _
  have e2 : (ic * b - amt * a) * (2:Int) ^ gridScale = ic * b * (2:Int) ^ gridScale - amt * a * (2:Int) ^ gridScale :=
    Int.sub_mul _ _ _
  have e3 : (fc - ic) * (2:Int) ^ gridScale * b = fc * (2:Int) ^ gridScale * b - ic * (2:Int) ^ gridScale * b := by
    rw [Int.sub_mul, Int.sub_mul]
  have e4 : ic * (2:Int) ^ gridScale * b = ic * b * (2:Int) ^ gridScale := Int.mul_right_comm _ _ _
  have hsplit : (fc - ic) * (2:Int) ^ gridScale * b =
      (fc * (2:Int) ^ gridScale - fp) * b + (fp * b - amt * a * (2:Int) ^ gridScale) -
        (ic * b - amt * a) * (2:Int) ^ gridScale := by
    rw [e1, e2, e3, e4]; omega
  have htri : ((fc - ic) * (2:Int) ^ gridScale * b).natAbs ≤
      ((fc * (2:Int) ^ gridScale - fp) * b).natAbs + (fp * b - amt * a * (2:Int) ^ gridScale).natAbs +
        ((ic * b - amt * a) * (2:Int) ^ gridScale).natAbs := by
    rw [hsplit]
    calc (((fc * (2:Int) ^ gridScale - fp) * b) + (fp * b - amt * a * (2:Int) ^ gridScale) -
            (ic * b - amt * a) * (2:Int) ^ gridScale).natAbs
        ≤ (((fc * (2:Int) ^ gridScale - fp) * b) + (fp * b - amt * a * (2:Int) ^ gridScale)).natAbs +
            ((ic * b - amt * a) * (2:Int) ^ gridScale).natAbs := Int.natAbs_sub_le _ _
      _ ≤ ((fc * (2:Int) ^ gridScale - fp) * b).natAbs + (fp * b - amt * a * (2:Int) ^ gridScale).natAbs +
            ((ic * b - amt * a) * (2:Int) ^ gridScale).natAbs := by
          have := Int.natAbs_add_le ((fc * (2:Int) ^ gridScale - fp) * b) (fp * b - amt * a * (2:Int) ^ gridScale)
          omega
  have hcastL : ((fc - ic) * (2:Int) ^ gridScale * b).natAbs =
      (fc - ic).natAbs * ((2:Int) ^ gridScale).natAbs * b.natAbs := by
    rw [Int.natAbs_mul, Int.natAbs_mul]
  have hcastA : ((fc * (2:Int) ^ gridScale - fp) * b).natAbs = (fc * (2:Int) ^ gridScale - fp).natAbs * b.natAbs :=
    Int.natAbs_mul _ _
  have hcastC : ((ic * b - amt * a) * (2:Int) ^ gridScale).natAbs =
      (ic * b - amt * a).natAbs * ((2:Int) ^ gridScale).natAbs := Int.natAbs_mul _ _
  have hA' : 2 ^ f64Precision * (fc * (2:Int) ^ gridScale - fp).natAbs ≤
      2 ^ (f64Precision - 1) * ((2:Int) ^ gridScale).natAbs := by
    have hreassoc := pow_succ_mul_reassoc (fc * (2:Int) ^ gridScale - fp).natAbs (f64Precision - 1)
    rw [hp1] at hreassoc
    have hmul := Nat.mul_le_mul (Nat.le_refl (2 ^ (f64Precision - 1))) hA
    omega
  have hC' : 2 ^ f64Precision * (ic * b - amt * a).natAbs ≤ 2 ^ (f64Precision - 1) * b.natAbs := by
    have hreassoc := pow_succ_mul_reassoc (ic * b - amt * a).natAbs (f64Precision - 1)
    rw [hp1] at hreassoc
    have hmul := Nat.mul_le_mul (Nat.le_refl (2 ^ (f64Precision - 1))) hC
    omega
  have hAscaled : 2 ^ f64Precision * ((fc * (2:Int) ^ gridScale - fp).natAbs * b.natAbs) ≤
      2 ^ (f64Precision - 1) * (((2:Int) ^ gridScale).natAbs * b.natAbs) := by
    have hmul := Nat.mul_le_mul hA' (Nat.le_refl b.natAbs)
    have hassoc1 : 2 ^ f64Precision * (fc * (2:Int) ^ gridScale - fp).natAbs * b.natAbs =
        2 ^ f64Precision * ((fc * (2:Int) ^ gridScale - fp).natAbs * b.natAbs) :=
      Nat.mul_assoc _ _ _
    have hassoc2 : 2 ^ (f64Precision - 1) * ((2:Int) ^ gridScale).natAbs * b.natAbs =
        2 ^ (f64Precision - 1) * (((2:Int) ^ gridScale).natAbs * b.natAbs) :=
      Nat.mul_assoc _ _ _
    omega
  have hCscaled : 2 ^ f64Precision * ((ic * b - amt * a).natAbs * ((2:Int) ^ gridScale).natAbs) ≤
      2 ^ (f64Precision - 1) * (b.natAbs * ((2:Int) ^ gridScale).natAbs) := by
    have hmul := Nat.mul_le_mul hC' (Nat.le_refl ((2:Int) ^ gridScale).natAbs)
    have hassoc1 : 2 ^ f64Precision * (ic * b - amt * a).natAbs * ((2:Int) ^ gridScale).natAbs =
        2 ^ f64Precision * ((ic * b - amt * a).natAbs * ((2:Int) ^ gridScale).natAbs) :=
      Nat.mul_assoc _ _ _
    have hassoc2 : 2 ^ (f64Precision - 1) * b.natAbs * ((2:Int) ^ gridScale).natAbs =
        2 ^ (f64Precision - 1) * (b.natAbs * ((2:Int) ^ gridScale).natAbs) :=
      Nat.mul_assoc _ _ _
    omega
  have hcombine : 2 ^ (f64Precision - 1) * (((2:Int) ^ gridScale).natAbs * b.natAbs) +
      2 ^ (f64Precision - 1) * (b.natAbs * ((2:Int) ^ gridScale).natAbs) =
      2 ^ f64Precision * (((2:Int) ^ gridScale).natAbs * b.natAbs) := by
    have hreassoc := pow_succ_mul_reassoc (((2:Int) ^ gridScale).natAbs * b.natAbs) (f64Precision - 1)
    rw [hp1] at hreassoc
    have hlc : 2 ^ (f64Precision - 1) * (2 * (((2:Int) ^ gridScale).natAbs * b.natAbs)) =
        2 * (2 ^ (f64Precision - 1) * (((2:Int) ^ gridScale).natAbs * b.natAbs)) :=
      Nat.mul_left_comm _ _ _
    rw [Nat.mul_comm b.natAbs (((2:Int) ^ gridScale).natAbs)]
    omega
  have htri' : 2 ^ f64Precision * ((fc - ic) * (2:Int) ^ gridScale * b).natAbs ≤
      2 ^ f64Precision * (((fc * (2:Int) ^ gridScale - fp) * b).natAbs +
        (fp * b - amt * a * (2:Int) ^ gridScale).natAbs + ((ic * b - amt * a) * (2:Int) ^ gridScale).natAbs) :=
    Nat.mul_le_mul (Nat.le_refl _) htri
  calc 2 ^ f64Precision * ((fc - ic).natAbs * ((2:Int) ^ gridScale).natAbs * b.natAbs)
      = 2 ^ f64Precision * ((fc - ic) * (2:Int) ^ gridScale * b).natAbs := by
        rw [hcastL]
    _ ≤ 2 ^ f64Precision * (((fc * (2:Int) ^ gridScale - fp) * b).natAbs +
          (fp * b - amt * a * (2:Int) ^ gridScale).natAbs + ((ic * b - amt * a) * (2:Int) ^ gridScale).natAbs) := htri'
    _ = 2 ^ f64Precision * ((fc * (2:Int) ^ gridScale - fp).natAbs * b.natAbs) +
          2 ^ f64Precision * (fp * b - amt * a * (2:Int) ^ gridScale).natAbs +
          2 ^ f64Precision * ((ic * b - amt * a).natAbs * ((2:Int) ^ gridScale).natAbs) := by
        rw [hcastA, hcastC]
        rw [Nat.mul_add, Nat.mul_add]
    _ ≤ 2 ^ (f64Precision - 1) * (((2:Int) ^ gridScale).natAbs * b.natAbs) +
          (amt.natAbs * (2 * (b.natAbs * (gridFactor a b).natAbs) + 2 ^ (f64Precision - 1) * b.natAbs) +
            2 * (b.natAbs * (gridProduct amt a b).natAbs)) +
          2 ^ (f64Precision - 1) * (b.natAbs * ((2:Int) ^ gridScale).natAbs) := by omega
    _ = 2 ^ f64Precision * (((2:Int) ^ gridScale).natAbs * b.natAbs) +
          (amt.natAbs * (2 * (b.natAbs * (gridFactor a b).natAbs) + 2 ^ (f64Precision - 1) * b.natAbs) +
            2 * (b.natAbs * (gridProduct amt a b).natAbs)) := by
        rw [← hcombine]; omega

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

end MeteroidVerify
