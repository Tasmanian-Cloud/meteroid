import Song.Foundation

/-!
# meteroid / TierPricing — tiered/volume pricing, and two real bugs

Companion to `crates/meteroid-proof-core/src/cores/tier_pricing.rs`. Models
`meteroid-store/src/services/invoice_lines/fees.rs`'s tier-selection
arithmetic (NOT its `Decimal` rounding — out of scope here, Phase 3's job)
assuming `tiers` is already sorted ascending by `first_unit`, matching the
real code's own `sort_by_key` step, which this file doesn't re-implement:
sorting isn't in question, the arithmetic after sorting is. `rate`/flat
fee/cap are irrelevant to both bugs below and are deliberately not modeled
here (see `cores::tier_pricing.rs` for the fuller re-implementation, used for
the `vectors/tier_pricing.json` cross-check).

**Bug 1 — `block_size` is dead on arrival.** `compute_tier_price` and
`compute_volume_price` (`fees.rs:117-124`, `:160-167`) both take
`_block_size: &Option<u64>` — underscore-prefixed, never read — and
`tiered_charges`/`volume_charge` (`fees.rs:33-81`, `:84-115`) don't take a
block size at all (`// TODO block_size`, `fees.rs:32,123,166`). `Package`
pricing (`fees.rs:229-234`) DOES use its `block_size`
(`ceil(units/block_size)*rate`) — so this isn't "block sizing is
unimplemented everywhere", it's specifically dead for `Tiered`/`Volume`.
`tiered_price_ignores_block_size` below proves this for `Tiered`; the
identical unused-parameter shape at `compute_volume_price` means the same
fact holds for `Volume` by the same argument, not separately proved here.

**Bug 2 — an unguarded subtraction where a sibling function has a guard.**
`volume_charge`'s `last_unit = iter.peek().map(|row| row.first_unit - 1)`
(`fees.rs:90`) is a literal `u64` subtraction with no guard. Contrast
`tiered_charges`'s analogous computation, `tier_units = ... last -
tier.first_unit` via `.saturating_sub(...)` (`fees.rs:48`) — same file, same
"distance to the next tier boundary" idea, hardened in one function and not
the other. Two tiers sharing `first_unit = 0` after sorting (not excluded by
`TierRow`'s type — e.g. a duplicate entry) make `first_unit - 1` compute a
value `u64` cannot represent: a debug-build arithmetic-overflow panic, or a
release-build silent wrap to `u64::MAX` (Rust's overflow-checks profile
setting decides which — this file does not model the wraparound value
itself, only that the subtraction goes negative, which is the shared cause
of both outcomes; `RESEARCH.md`).

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- One tier row (`price_components.rs:296-302`), already in ascending
    `firstUnit` order. `rate` is an abstract `Int` amount per unit — exact
    `Decimal` precision is out of scope for this file. -/
structure TierRow where
  firstUnit : Nat
  rate : Int
deriving DecidableEq, Repr

/-- Graduated tiers (`tiered_charges`, `fees.rs:33-81`): each tier is charged
    for the units in its band `[firstUnit, next.firstUnit)` (unbounded for
    the last tier), via `Nat` subtraction — which truncates at 0 exactly like
    the real `saturating_sub` (`fees.rs:48`), not a simplification but an
    exact match. -/
def tieredAmount : Nat → List TierRow → Int
  | _, [] => 0
  | remaining, [t] => (remaining : Int) * t.rate
  | remaining, t :: (next :: rest) =>
    let width := next.firstUnit - t.firstUnit
    let units := min remaining width
    (units : Int) * t.rate + tieredAmount (remaining - units) (next :: rest)

/-- Mirrors `compute_tier_price`'s real signature (`fees.rs:160-167`)
    exactly, including the unused `_blockSize` parameter — so the theorem
    below is about the actual function shape, not a strawman. -/
def computeTierPrice (usage : Nat) (tiers : List TierRow) (_blockSize : Option Nat) : Int :=
  tieredAmount usage tiers

/-- Bug 1, `Tiered`: the priced amount does not depend on `block_size` at
    all, because `_blockSize` never appears in `computeTierPrice`'s body —
    exactly mirroring the real `compute_tier_price`. -/
theorem tiered_price_ignores_block_size
    (usage : Nat) (tiers : List TierRow) (bs1 bs2 : Option Nat) :
    computeTierPrice usage tiers bs1 = computeTierPrice usage tiers bs2 := rfl

/-- The real `volume_charge`'s boundary computation (`fees.rs:90`):
    `next.first_unit - 1`, modeled over `Int` (not `Nat`/`UInt64`)
    specifically so the subtraction can go negative and be OBSERVED doing
    so — a `Nat` model would truncate to `0` and a `UInt64` model would wrap
    to its max value, either of which would silently hide the exact failure
    mode being formalized here. -/
def tierUpperBound (nextFirstUnit : Int) : Int := nextFirstUnit - 1

/-- Bug 2: two tiers sharing `first_unit = 0` after sorting — not excluded
    by `TierRow`'s type — make `tierUpperBound` compute `-1`, a value `u64`
    cannot represent. This is the shared precondition behind both the
    debug-mode panic and the release-mode wraparound the real
    `volume_charge` is exposed to at `fees.rs:90`. -/
theorem duplicate_zero_tier_upper_bound_goes_negative :
    tierUpperBound 0 < 0 := by decide

end MeteroidVerify
