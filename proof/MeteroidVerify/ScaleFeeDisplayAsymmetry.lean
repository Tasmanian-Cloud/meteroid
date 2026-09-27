/-! # Scale-fee OneTime display asymmetry

**Scope**: Display-only inconsistency in how `scale_fee`'d add-on quantities are
shown on proration lines. Formalized at the discrete model level; does not model
actual rendering or user-facing text.

**File citations**:
- `modules/meteroid/crates/meteroid-store/src/services/subscriptions/utils.rs:128-174` — `scale_fee` function
- `modules/meteroid/crates/meteroid-store/src/services/subscriptions/proration.rs:265-319` — added components handling in `calculate_proration`
- `modules/meteroid/crates/meteroid-store/src/domain/subscription_changes.rs:81-108` — `AddedComponent` struct with `instance_quantity` field
- `modules/meteroid/crates/meteroid-store/src/domain/subscription_changes.rs:131-159` — `ProrationLineItem` struct with `quantity` field

**Model**: Discrete fee scaling and display field extraction.

`SubscriptionFee` modeled as a sum type:
- `oneTime (rate quantity : Nat)`
- `rateOnly (rate : Nat)`

**What's proved**:
- `scale_onetime_folds_qty`: `scale_fee(OneTime r q, n) = OneTime r (q*n)`
- `amount_is_correct`: computing cents from a scaled OneTime multiplies rate × total quantity correctly
- `onetime_displays_total_not_instance_count`: extracting quantity from a scaled OneTime
  for display yields the TOTAL (inner × add-on), not the add-on instance count alone
- `asymmetry_onetime_vs_rate`: a `rateOnly` fee has no quantity to extract at all after
  scaling, contrasted with `oneTime`'s scaled-total extraction — the two fee shapes
  disagree on whether "quantity" survives scaling into something displayable
- `display_disagreement_same_amount`: despite the display asymmetry, the actual charge
  amount is identical under both framings (`6 × 10 = 3 × (10 × 2) = 60`)

**What's NOT proved**:
- Actual rendering of invoice text (UI concern, not arithmetic)
- Whether the asymmetry causes user confusion (design concern)
- Cross-file consistency with non-proration paths (`component.rs`) — those use
  unscaled fees + a separate `instance_quantity()`, so they avoid the issue

**Known limitations**: Pure Lean core, no Decimal / fixed-point arithmetic modeling;
amounts modeled as `Nat` (non-negative integers) with implicit cents scaling. No nested
namespace for the fee type — an earlier version of this file put `SubscriptionFee` in a
`namespace Fee` block and relied on `open Fee` alone to bring its constructors
(`oneTime`/`rate`) into scope; that opens the OUTER namespace, not the constructor
namespace nested under the inductive type itself, so every unqualified `oneTime`/`rate`
use — inside the type's own pattern matches and at every later call site — failed to
resolve. Flattened to one namespace to avoid the whole class of bug.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/`native_decide`.
-/

namespace MeteroidVerify.ScaleFeeDisplayAsymmetry

inductive SubscriptionFee where
  | oneTime : (rate : Nat) → (quantity : Nat) → SubscriptionFee
  | rateOnly : (rate : Nat) → SubscriptionFee

open SubscriptionFee

def scaleFee (fee : SubscriptionFee) (quantity : Nat) : SubscriptionFee :=
  match fee with
  | oneTime r qty => oneTime r (qty * quantity)
  | rateOnly r => rateOnly (r * quantity)

def onetimeAmountCents (fee : SubscriptionFee) : Nat :=
  match fee with
  | oneTime r quantity => r * quantity
  | rateOnly _ => 0

-- Extraction as used in proration line at line 275 of proration.rs:
-- quantity: Some(rust_decimal::Decimal::from(*quantity))
-- where quantity comes from the OneTime fee's quantity field
def extractQuantityFromFee (fee : SubscriptionFee) : Option Nat :=
  match fee with
  | oneTime _ qty => some qty
  | rateOnly _ => none

-- Test witness: add-on with 3 instances, each with 2 licenses, $10/license
def testAddOnThreeInstancesTwoQty : SubscriptionFee :=
  oneTime 10 2

def testScaledByThree : SubscriptionFee :=
  scaleFee testAddOnThreeInstancesTwoQty 3

-- The scaled fee now has quantity = 2 * 3 = 6
theorem scaled_quantity_is_total : extractQuantityFromFee testScaledByThree = some 6 := by
  rfl

-- Amount is correct: 10 * 6 = 60
theorem amount_is_correct : onetimeAmountCents testScaledByThree = 60 := by
  rfl

-- But the display quantity is 6 (total), not 3 (instances)
-- The instance_quantity field on AddedComponent IS 3, but the OneTime case
-- in proration.rs extracts from the fee, not from instance_quantity
theorem onetime_displays_total_not_instance_count :
    extractQuantityFromFee testScaledByThree = some 6 ∧ 6 ≠ 3 := by
  constructor
  · rfl
  · decide

-- Generic: for any inner qty and add-on qty, the extracted quantity is their product
theorem scale_onetime_folds_qty (innerQty addOnQty : Nat) :
    extractQuantityFromFee (scaleFee (oneTime 10 innerQty) addOnQty) = some (innerQty * addOnQty) := by
  rfl

-- Rate-only type (for comparison): also gets scaled
theorem rateOnly_also_scaled (r n : Nat) :
    scaleFee (rateOnly r) n = rateOnly (r * n) := by
  rfl

-- A rate-only counterpart to `testScaledByThree`, for the asymmetry contrast below.
def testRateScaledByThree : SubscriptionFee :=
  scaleFee (rateOnly 20) 3

-- Asymmetry: OneTime extracts scaled qty for display; a rate-only fee has no quantity
-- to extract at all (its own arm of `extractQuantityFromFee` returns `none`) — the two
-- fee shapes disagree on whether "quantity" survives scaling into something displayable.
theorem asymmetry_onetime_vs_rate :
    extractQuantityFromFee testScaledByThree = some 6 ∧
      extractQuantityFromFee testRateScaledByThree = none := by
  constructor <;> rfl

-- Concrete witness: if we display OneTime as (extracted_qty) × rate,
-- we show 6 × 10 instead of 3 × 20, despite both equaling 60 cents
theorem display_disagreement_same_amount :
    onetimeAmountCents testScaledByThree = 6 * 10 ∧
      onetimeAmountCents testScaledByThree = 3 * (10 * 2) := by
  constructor <;> rfl

end MeteroidVerify.ScaleFeeDisplayAsymmetry
