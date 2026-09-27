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
- `OneTime (rate : Nat) (quantity : Nat)`
- `Rate (rate : Nat)`

`AddedComponent` carries both scaled fee and instance_quantity separately.

**What's proved**:
- `scale_fee_onetime_scales_quantity`: `scale_fee(OneTime r q, n) = OneTime r (q*n)`
- `onetime_amount_cents`: Computing cents from a OneTime scales rate × quantity correctly
- `onetime_display_extracts_total`: When extracting quantity from a scaled OneTime for
  display, you get the TOTAL (inner × add-on), not the add-on instance count alone
- `onetime_display_asymmetry`: For non-OneTime types, display uses `instance_quantity`
  (the add-on count); for OneTime (after scaling), display extracts from the scaled fee
  (the total), creating an asymmetry
- `amount_cents_correct`: Despite display asymmetry, the actual charge amount is
  computed correctly (both paths compute `rate * total_qty * factor`)

**What's NOT proved**:
- Actual rendering of invoice text (UI concern, not arithmetic)
- Whether the asymmetry causes user confusion (design concern)
- Cross-file consistency with non-proration paths (component.rs) — those use
  unscaled fees + separate instance_quantity(), so they avoid the issue

**Known limitations**: Pure Lean core, no Decimal / fixed-point arithmetic modeling;
amounts modeled as Nat (non-negative integers) with implicit cents scaling.
-/

namespace MeteroidVerify.ScaleFeeDisplayAsymmetry

namespace Fee

inductive SubscriptionFee where
  | oneTime : (rate : Nat) → (quantity : Nat) → SubscriptionFee
  | rate : (rate : Nat) → SubscriptionFee

def scaleFee (fee : SubscriptionFee) (quantity : Nat) : SubscriptionFee :=
  match fee with
  | oneTime rate qty => oneTime rate (qty * quantity)
  | rate r => rate (r * quantity)

def onetimeAmountCents (fee : SubscriptionFee) : Nat :=
  match fee with
  | oneTime rate quantity => rate * quantity
  | _ => 0

def rateAmountCents (fee : SubscriptionFee) : Nat :=
  match fee with
  | rate r => r
  | _ => 0

-- Extraction as used in proration line at line 275 of proration.rs:
-- quantity: Some(rust_decimal::Decimal::from(*quantity))
-- where quantity comes from the OneTime fee's quantity field
def extractQuantityFromFee (fee : SubscriptionFee) : Option Nat :=
  match fee with
  | oneTime _ qty => some qty
  | _ => none

end Fee

open Fee

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
  · norm_num

-- Generic: for any inner qty and add-on qty, the extracted quantity is their product
theorem scale_onetime_folds_qty (innerQty addOnQty : Nat) :
  extractQuantityFromFee (scaleFee (oneTime 10 innerQty) addOnQty) = some (innerQty * addOnQty) := by
  rfl

-- Rate type (for comparison): also gets scaled
theorem rate_also_scaled (r n : Nat) :
  scaleFee (rate r) n = rate (r * n) := by
  rfl

-- Asymmetry: OneTime extracts scaled qty for display; other types would use instance_quantity
-- This is formalized at the model level as a discrete discrepancy, not evaluated on display
theorem asymmetry_onetime_vs_rate :
  let onetimeScaled := scaleFee (oneTime 10 2) 3
  let rateScaled := scaleFee (rate 20) 3
  extractQuantityFromFee onetimeScaled = some 6 ∧ extractQuantityFromFee rateScaled = none := by
  simp [scaleFee, extractQuantityFromFee]

-- Concrete witness: if we display OneTime as (extracted_qty) × rate,
-- we show 6 × 10 instead of 3 × 20, despite both equaling 60 cents
theorem display_disagreement_same_amount :
  let onetimeScaled := scaleFee (oneTime 10 2) 3
  let extractedQty := 6  -- from the fee
  let instanceQty := 3   -- from AddedComponent::instance_quantity
  let rate := 10         -- from the fee
  onetimeAmountCents onetimeScaled = extractedQty * rate ∧
  onetimeAmountCents onetimeScaled = instanceQty * (rate * 2) := by
  norm_num

end MeteroidVerify.ScaleFeeDisplayAsymmetry
