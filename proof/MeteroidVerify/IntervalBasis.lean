/-!
# meteroid / IntervalBasis — the bounded-quantity basis

The second basis module (`LedgerFold.lean` is the first). `PaymentReversal.lean`'s four
`amount_refunded` write paths each proved "stays in `[0, amount]`" independently, by calling
`omega` on that formula's own fully-expanded `max`/`min` arithmetic — four separate proof
searches for what is really one shape, composed four different ways: Rust's `.clamp(lo, hi)`,
and how bounds compose under `+`/`max`/`min`.

**The primitives**, proved once:
- `clampInterval_mem`: `x.clamp(lo, hi)` always lands in `[lo, hi]`.
- `add_mem`/`max_mem`/`min_mem`: if two quantities are each bounded, their sum/max/min is bounded
  by the combination of those bounds — so composing bounded quantities with `+`/`max`/`min`
  automatically yields a bounded result, without re-deriving the bound from scratch each time.

Every one of `PaymentReversal.lean`'s four formulas is literally a composition of these
primitives — not similar in shape, the same expressions, just written out by hand there instead
of through named combinators. `PaymentReversal.lean` now expresses each formula using
`clampInterval` directly (matching the real Rust `.clamp()` calls it models even more closely)
and proves the bound by composing `clampInterval_mem`/`add_mem`/`max_mem`/`min_mem`, not by a
fresh `omega` search per formula.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/`native_decide`.
-/

namespace MeteroidVerify

/-- `x.clamp(lo, hi)` (Rust `i64::clamp`, requires `lo ≤ hi`): `max lo (min x hi)`. -/
def clampInterval (lo hi x : Int) : Int := max lo (min x hi)

/-- The one fact a clamp exists to guarantee: its result always lands in `[lo, hi]`. -/
theorem clampInterval_mem (lo hi x : Int) (h : lo ≤ hi) :
    lo ≤ clampInterval lo hi x ∧ clampInterval lo hi x ≤ hi := by
  unfold clampInterval
  omega

/-- Two bounded quantities' sum is bounded by the sum of their bounds. -/
theorem add_mem {a b loA hiA loB hiB : Int}
    (ha : loA ≤ a ∧ a ≤ hiA) (hb : loB ≤ b ∧ b ≤ hiB) :
    loA + loB ≤ a + b ∧ a + b ≤ hiA + hiB := by
  omega

/-- Two quantities bounded by the SAME interval: their `max` stays in that interval. -/
theorem max_mem {a b lo hi : Int} (ha : lo ≤ a ∧ a ≤ hi) (hb : lo ≤ b ∧ b ≤ hi) :
    lo ≤ max a b ∧ max a b ≤ hi := by
  omega

/-- Two quantities bounded by the SAME interval: their `min` stays in that interval. -/
theorem min_mem {a b lo hi : Int} (ha : lo ≤ a ∧ a ≤ hi) (hb : lo ≤ b ∧ b ≤ hi) :
    lo ≤ min a b ∧ min a b ≤ hi := by
  omega

/-- Subtracting a bounded-within-`[0,x]` quantity from `x` stays within `[0,x]` — the shape of
    "hand back up to what's already been taken." -/
theorem sub_from_mem {c x : Int} (hc : 0 ≤ c ∧ c ≤ x) :
    0 ≤ x - c ∧ x - c ≤ x := by
  omega

end MeteroidVerify
