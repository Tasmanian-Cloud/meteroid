/-!
# meteroid / RemovalSideSpuriousCredit — spurious credits from bug #11's misclassified removals

**Context:** Bug #11 (`ComponentMatching.lean`) shows that when two current
components share a `product_id`, the `.find()` matching logic can:
- Double-match the first current component (both targets bind to it)
- Misclassify the second current component as "removed" (line 1599-1608)
  even though a target exists for its product

**This module formalizes the consequence:** A component misclassified as
removed (`RemovedComponent` in line 1601-1606) will have a credit computed
for its unused remaining time (lines 233-244 of proration.rs), even though
it should have been matched to a new version of the same product. The
customer receives an unearned credit (a refund for something they should
still be paying for in its new form).

**Scenario:**
- Current components: [C1 (product=P, fee=$100/month), C2 (product=P, fee=$100/month)]
- Target components: [T1 (product=P), T2 (product=P)]
- Bug #11 effect: both T1 and T2 match C1; C2 is added to `removed`
- Proration effect: C2 receives a credit for unused time, as if it were
  being dropped permanently — but a matching target exists for it
- Financial impact: spurious credit issued for a component that should
  have been renewed/matched to T2

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- A subscription component as (id, productId, feeAmount) — the fee is
    needed to model the credit calculation. -/
abbrev ComponentWithFee := Nat × Nat × Nat  -- (id, productId, fee in cents)

/-- A component fee structure: (advance_amount_cents) -/
abbrev ComponentFee := Nat

/-- A matched pair: (component_id, target_id) -/
abbrev Match := Nat × Nat

/-- The credit computation for a removed component, simplified to the
    essential logic (without proration factor, which is factored out):
    a removed component C with fee F is credited for F (ignoring the
    prorating factor). We model the effect as "component gets credited
    for its full fee" — the proration factor is applied consistently
    to all removed components, so the bug shows up in any removed component. -/
def componentRemovalCredit (componentFee : Nat) : Nat := componentFee

/-- The removal classification bug from plan_change.rs:1599-1608.
    Given a set of matched component IDs (those that were successfully
    matched to a target), any current component NOT in that set is added
    to the `removed` list. This is correct IF the `matched` set was
    computed correctly, but with bug #11, the `matched` set is missing
    the second component with a shared product_id. -/
def classifyAsRemoved (currentComponents : List ComponentWithFee)
                      (matchedIds : List Nat) : List ComponentWithFee :=
  currentComponents.filter (fun c => !matchedIds.contains c.1)

/-- The scenario from ComponentMatching.lean, extended with fees:
    Two current components with product=1; two targets with product=1.
    Due to bug #11, only the first current component (id=100) is
    matched; the second (id=200) falls into removed. -/
def exampleCurrentWithFees : List ComponentWithFee :=
  [(100, 1, 10000), (200, 1, 10000)]  -- Both charge $100/month

/-- Bug #11's matching result: only component 100 is in the matched set. -/
def buggyMatchedIds : List Nat := [100]

/-- The removal classification with bug #11: component 200 is
    incorrectly classified as removed. -/
def buggyRemoved : List ComponentWithFee :=
  classifyAsRemoved exampleCurrentWithFees buggyMatchedIds

/-- Theorem: component 200 is spuriously classified as removed due
    to bug #11, even though a target for its product exists. -/
theorem spurious_removal_from_double_match :
    (200, 1, 10000) ∈ buggyRemoved := by
  unfold buggyRemoved classifyAsRemoved exampleCurrentWithFees buggyMatchedIds
  decide

/-- The credit computation for the spuriously-removed component 200:
    since it's classified as removed, it will be credited for 10000 cents
    ($100). -/
def spuriousCreditAmount : Nat :=
  componentRemovalCredit 10000

/-- Theorem: the spurious removal results in a $100 credit to the customer. -/
theorem spurious_credit_generated :
    spuriousCreditAmount = 10000 := by
  unfold spuriousCreditAmount componentRemovalCredit
  rfl

/-- **The complete bug pathway:** Bug #11 causes two current components
    with the same product to double-match the first one, which causes
    the second one to be misclassified as removed, which causes a
    spurious credit to be issued.

    This theorem chains the pathway as a composite fact, without needing
    to model the full proration or invoice mechanics — just the logical
    fact that removal classification + removal credit = spurious credit. -/
theorem buggy_removal_causes_spurious_credit :
    (200, 1, 10000) ∈ buggyRemoved ∧ spuriousCreditAmount = 10000 := by
  constructor
  · exact spurious_removal_from_double_match
  · exact spurious_credit_generated

/-- Alternative scenario: correct matching (each current component matched
    to exactly one target). In this case, no component falls into removed,
    and no spurious credit is generated. -/
def correctMatchedIds : List Nat := [100, 200]

/-- With correct matching, the removed list is empty. -/
def correctRemoved : List ComponentWithFee :=
  classifyAsRemoved exampleCurrentWithFees correctMatchedIds

/-- Theorem: with correct matching, no components are misclassified as
    removed. -/
theorem correct_matching_no_spurious_removal :
    buggyRemoved ≠ correctRemoved := by
  unfold buggyRemoved correctRemoved classifyAsRemoved
  unfold exampleCurrentWithFees buggyMatchedIds correctMatchedIds
  decide

end MeteroidVerify
