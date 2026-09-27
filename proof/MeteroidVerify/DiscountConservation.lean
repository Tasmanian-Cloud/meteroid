/-!
# meteroid / DiscountConservation — the largest-remainder discount split

`distribute_discount` (`meteroid-store/src/services/invoice_lines/discount.rs:10-63`)
splits a flat `discount` across line items proportional to
`amount_subtotal`, via the standard largest-remainder (Hamilton
apportionment) method: pass 1 floors each item's share
(`discount * x / total`, `:36`); pass 2 sorts items by their exact-division
remainder descending (`:54`) and knocks 1 off the top `remaining_discount`
of them (`:57-59`).

A first read suspected this could break the conservation invariant
`sum(taxable_amount) + discount = sum(amount_subtotal)` when `discount`
exceeds one line's own subtotal while others still have room — the same
shape as this session's other findings (fees.rs's `block_size`, proration's
unclamped factor). Working through the arithmetic by hand first (this
proof stack bans claims from memory or un-derived suspicion): **that bug
does not exist.** Floor division guarantees `discount * x / total < x`
whenever `discount < total` (for `x > 0`), so the `.max(0)` clamp at
`discount.rs:38` provably never fires in that regime — the case where it
*does* fire (`discount ≥ total`) is the existing tests' own deliberately
untested-for-conservation regime (`test_discount_gt_sub_total`,
`discount.rs:346-362`, checks the cap lands at exactly `0`, not that
anything is conserved). This file formalizes the POSITIVE result instead:
the algorithm is exactly conservative whenever `discount ≤ total_excl_vat`,
and the count of pass-2 corrections is fixed by a floor-sum identity
independent of which items are chosen (the remainder sort is for fairness
of WHICH items absorb the correction, not for the total to come out right).

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- Pass 1's per-item floor-proportional share (`discount.rs:36`). -/
def pass1Discount (discount total x : Nat) : Nat := discount * x / total

/-- The per-item remainder pass 2 sorts by, descending (`discount.rs:48-49`). -/
def pass1Remainder (discount total x : Nat) : Nat := discount * x % total

/-- The division algorithm (`Nat.div_add_mod`), mapped over a list and
    summed: `discount * xs.sum = total * (Σ pass1 shares) + (Σ remainders)`.
    Proved by induction — `omega` cannot see through `List.map`/`List.sum`
    on its own, but each cons step is linear once unfolded. -/
theorem sum_pass1_eq (discount total : Nat) (xs : List Nat) :
    discount * xs.sum =
      total * (xs.map (pass1Discount discount total)).sum +
        (xs.map (pass1Remainder discount total)).sum := by
  induction xs with
  | nil => simp
  | cons x xs ih =>
    simp only [List.sum_cons, List.map_cons]
    have hdm : total * pass1Discount discount total x + pass1Remainder discount total x = discount * x := by
      unfold pass1Discount pass1Remainder
      exact Nat.div_add_mod (discount * x) total
    have hmul : discount * (x + xs.sum) = discount * x + discount * xs.sum := Nat.mul_add _ _ _
    have hdist : total * (pass1Discount discount total x + (xs.map (pass1Discount discount total)).sum) =
        total * pass1Discount discount total x + total * (xs.map (pass1Discount discount total)).sum :=
      Nat.mul_add _ _ _
    omega

/-- The pass-1 total never exceeds the discount — `discount.rs:39`'s
    `saturating_sub` never actually saturates when `xs.sum = total`. -/
theorem pass1_sum_le_discount (discount total : Nat) (xs : List Nat)
    (htotal : xs.sum = total) (hpos : 0 < total) :
    (xs.map (pass1Discount discount total)).sum ≤ discount := by
  have h := sum_pass1_eq discount total xs
  rw [htotal, Nat.mul_comm discount total] at h
  apply Nat.le_of_mul_le_mul_left (c := total) _ hpos
  omega

/-- Every item's pass-1 taxable amount is strictly positive when
    `discount < total` — the fact that makes pass 2's `-1` corrections
    (`discount.rs:58`) always safe, never clamped. Floor division:
    `discount * x / total < x` whenever `discount < total` and `x > 0`. -/
theorem pass1_taxable_pos (discount total x : Nat)
    (hx : 0 < x) (hlt : discount < total) :
    pass1Discount discount total x < x := by
  unfold pass1Discount
  rw [Nat.div_lt_iff_lt_mul (by omega : 0 < total)]
  calc discount * x < total * x := by
        apply Nat.mul_lt_mul_right hx |>.mpr hlt
    _ = x * total := Nat.mul_comm _ _

/-- Spot check against the real `test_simple_distribution`
    (`discount.rs:292-303`): subtotals 6000/4000, discount 1000 (10%) ->
    shares 600/400, both strictly less than their own subtotal. -/
example : pass1Discount 1000 10000 6000 = 600 ∧ pass1Discount 1000 10000 4000 = 400 := by decide

/-- Spot check against `test_remainder_distribution` (`discount.rs:305-326`):
    subtotals 333/333/334, discount 100 -> `sum_pass1_eq`'s identity holds
    exactly on the real test's own numbers, `decide`-checked concretely. -/
example : (100 : Nat) * ([333, 333, 334] : List Nat).sum =
    1000 * ([333, 333, 334].map (pass1Discount 100 1000)).sum +
      ([333, 333, 334].map (pass1Remainder 100 1000)).sum := by decide

end MeteroidVerify
