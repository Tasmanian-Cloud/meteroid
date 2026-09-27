import MeteroidVerify.IntervalBasis

/-!
# meteroid / CouponFixedAmountNegative — the consumed-amount clamp gap

`services/invoice_lines/discount.rs::calculate_coupons_discount` (lines 97-115)
computes a fixed-amount coupon discount. For each fixed-amount coupon, the code:

1. Gets `amount` (the coupon's face value) and `consumed_amount` (from database).
2. Computes `remaining = amount - consumed_amount` (line 110).
3. Converts to subunits via `to_subunit_opt` (line 111), yielding an i64.
4. Takes `min(discount_subunits, subtotal_subunits)` to cap the discount (line 114).

**The bug:** if `consumed_amount > amount`, step 2 produces a negative Decimal,
which `to_subunit_opt` converts to a negative i64. When this is clamped with min()
against a positive subtotal, the min is the negative value. Line 118 then subtracts
this negative discount (equivalently, adds), increasing the subtotal — the
opposite of a coupon's intended effect.

**What is modeled:** the bug at the integer subunit level. Treating the Decimal
conversion as an opaque mapping to i64 (since `to_subunit_opt` is already
correct per `TaxRounding.lean`), we model:
- `amount_subunits` and `consumed_subunits` are integers (in the coupon's currency).
- `remaining_subunits = amount_subunits - consumed_subunits`.
- If `consumed_subunits > amount_subunits`, then `remaining_subunits < 0`.
- Taking `min(remaining_subunits, subtotal_subunits)` with positive `subtotal_subunits`
  yields the negative value.
- Subtracting this negative increases the subtotal (violates the discount invariant).

**The fix:** clamp the remaining amount to [0, ∞) before the conversion:
```rust
let remaining_amount = (amount - consumed_amount).max(Decimal::ZERO);
let discount_subunits = remaining_amount
    .to_subunit_opt(cur.exponent as u8)
    .unwrap_or(0);
```

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/`native_decide`.
-/

namespace MeteroidVerify

/-- Fixed coupon discount logic (unclamped version, the bug).
    - `amount_subunits`: face value of the coupon in subunits.
    - `consumed_subunits`: already-consumed portion (from database).
    - Returns: `amount_subunits - consumed_subunits`, which can be negative. -/
def fixedDiscountUnclamped (amountSubunits consumedSubunits : Int) : Int :=
  amountSubunits - consumedSubunits

/-- Fixed coupon discount logic (clamped version, the fix).
    Clamps the remaining amount to [0, ∞) before use. -/
def fixedDiscountClamped (amountSubunits consumedSubunits : Int) : Int :=
  max (amountSubunits - consumedSubunits) 0

/-- When a coupon is applied, its discount is capped by the current subtotal.
    If the discount is negative (the bug), and we take min with a positive
    subtotal, the min is the negative discount. -/
def appliedDiscountNegativeCase (amountSubunits consumedSubunits subtotalSubunits : Int) : Int :=
  min (fixedDiscountUnclamped amountSubunits consumedSubunits) subtotalSubunits

/-- When we subtract this applied discount from the subtotal (the bug path):
    subtracting a negative value increases the subtotal. -/
theorem negative_discount_increases_subtotal (amountSubunits consumedSubunits subtotalSubunits : Int)
    (hamt : 0 ≤ amountSubunits)
    (hsubtotal : 0 < subtotalSubunits)
    (h_consumed_exceeds : amountSubunits < consumedSubunits) :
    subtotalSubunits < subtotalSubunits - appliedDiscountNegativeCase amountSubunits consumedSubunits subtotalSubunits := by
  unfold appliedDiscountNegativeCase fixedDiscountUnclamped
  omega

/-- The clamped version always produces a non-negative discount. -/
theorem fixedDiscountClamped_nonnegative (amountSubunits consumedSubunits : Int) :
    0 ≤ fixedDiscountClamped amountSubunits consumedSubunits := by
  unfold fixedDiscountClamped
  omega

/-- The clamped version ensures subtracting the discount never increases the subtotal. -/
theorem clamped_discount_decreases_subtotal (amountSubunits consumedSubunits subtotalSubunits : Int)
    (hsubtotal : 0 ≤ subtotalSubunits) :
    subtotalSubunits - fixedDiscountClamped amountSubunits consumedSubunits ≤ subtotalSubunits := by
  unfold fixedDiscountClamped
  omega

end MeteroidVerify
