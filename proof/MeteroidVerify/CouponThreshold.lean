/-!
# meteroid / CouponThreshold — the early-break check fires one subunit too early

`calculate_coupons_discount` (`services/invoice_lines/discount.rs:65-135`)
loops over applicable coupons, checking `if subtotal_subunits <=
Decimal::ONE { break; }` (`:90-92`) **before** computing and applying that
iteration's discount (`:93-116`).

**The real bug, confirmed by reading the loop directly:** a subtotal of
exactly `1` subunit breaks out of the loop before considering ANY further
coupon — including the current one. A "100% off, no exceptions" coupon on
a `$0.01` invoice is never applied: the customer pays the full cent despite
holding a coupon that should reduce it to `$0.00`. This is the boundary
condition specifically at `1`, not "discounts never fire near zero" in
general — the identical coupon on a `2`-subunit subtotal fires normally.

This file does not model the surrounding `Decimal` percentage/fixed-amount
computation (`:94-114`, the same modeling ceiling as the tax rate work) —
only the break-then-apply ordering and its threshold, which is where the
bug actually lives and is fully expressible in integers.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- One loop iteration's real structure (`discount.rs:89-116`): if
    `remaining` is already `≤ 1`, skip this coupon entirely (`none`);
    otherwise apply `discount` (itself `≤ remaining`, matching the real
    code's own `.min(subtotal_subunits)` clamp at `:96,114`) and return the
    new remaining subtotal. -/
def processOneCoupon (remaining discount : Int) : Option Int :=
  if remaining ≤ 1 then none else some (remaining - discount)

/-- The bug: a subtotal of exactly `1` subunit with a coupon that would
    fully discount it (`discount = remaining = 1`) never gets that discount
    applied. -/
theorem subtotal_one_never_discounted :
    processOneCoupon 1 1 = none := by decide

/-- Contrast: the identical "fully discount everything" coupon on a
    `2`-subunit subtotal DOES apply — pinning that the bug is specifically
    the boundary at exactly `1` remaining, not a general failure to reach
    zero. -/
theorem subtotal_two_fully_discounted :
    processOneCoupon 2 2 = some 0 := by decide

end MeteroidVerify
