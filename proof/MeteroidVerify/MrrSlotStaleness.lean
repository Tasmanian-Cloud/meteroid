/-!
# meteroid / MrrSlotStaleness — `calculate_mrr` reports the ORIGINAL slot count forever

`SubscriptionFee::Slot`'s `initial_slots` field is set once, at subscription
creation or plan-override parameterization
(`domain/subscription_components.rs:288-296`'s `apply_parameters`, the
field's only mutator), and never again. Every subsequent slot-count change
goes through `services/subscriptions/slots.rs::update_subscription_slots`
(`:37-173`), which — checked directly, grepping the whole function for
`.fee`/`patch`/`update_price_component` — never touches the persisted
`SubscriptionComponent.fee`. Instead it appends to an independent
append-only ledger, `slot_transactions`
(`domain/slot_transactions.rs`'s `SlotTransaction { delta, prev_active_slots,
.. }`), whose seed row (`SlotTransactionNewInternal::from_fee`, `:39-53`)
copies `initial_slots` in ONCE at creation and is never referenced again by
that name.

`services/subscriptions/utils.rs::calculate_mrr` (`:82-116`)'s `Slot` arm
(`:101-105`) computes `i64::from(*initial_slots) * unit_rate...` —
directly off the frozen field, with no query against `slot_transactions`.
**A slot-aware replacement exists**:
`services/subscriptions/plan_change.rs::calculate_components_mrr_with_slots`
(`:1695-1741`) correctly queries
`SlotTransactionRow::fetch_by_subscription_id_and_unit_locked(..)
.current_active_slots` (`:1710-1717`) for `Slot` components, falling back
to the generic `calculate_mrr` only for non-`Slot` fee types. **But it is
called from exactly one site** (itself, at `:1738`, recursing into the
non-`Slot` fallback) — every OTHER caller of `calculate_mrr` calls the
generic, slot-blind version directly:
`insert/process.rs:703,708`, `amendment.rs:236,242,247,252,1082`,
`billing_events.rs:550,821`, `plan_change.rs:984`. At subscription
creation (`insert/process.rs`) `initial_slots` IS the live count, so that
call site is fine; every call reached AFTER a subscription's first slot
change is not — it silently reports the count as of creation/last
parameterization, not the current one.

**What is modeled:** the two formulas' divergence whenever the live slot
count differs from `initial_slots` — a concrete, decidable witness, not a
claim about which specific call sites are reachable post-slot-change
(that's the Rust call-graph fact traced above, not something this file
re-derives).

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- The generic `calculate_mrr`'s `Slot` arm (`utils.rs:101-105`,
    `:113-116`), collapsed to integer division (both formulas ultimately
    truncate here — the generic path via `Decimal` division then
    `to_i64()`, the slot-aware path via plain integer `/` — so this
    comparison isn't confounded by a rounding-convention difference,
    only by which slot count each one uses). -/
def mrrGenericSlot (initialSlots rateCents months : Int) : Int :=
  initialSlots * rateCents / months

/-- `calculate_components_mrr_with_slots`'s `Slot` arm (`plan_change.rs:1730-1734`). -/
def mrrSlotAware (currentActiveSlots rateCents months : Int) : Int :=
  currentActiveSlots * rateCents / months

/-- Whenever the live count hasn't drifted from `initial_slots` (true only
    at/before a subscription's first slot change), the two formulas agree —
    this is exactly why the bug is easy to miss in a quick manual check. -/
theorem agree_before_any_slot_change (initialSlots rateCents months : Int) :
    mrrGenericSlot initialSlots rateCents months =
      mrrSlotAware initialSlots rateCents months := rfl

/-- Concrete witness: a subscription created with 5 slots, later upgraded
    to 10 (a real, ordinary slot-count increase), $10.00/slot/month
    (`rateCents = 1000`), monthly billing. The slot-aware function reports
    the true doubled MRR; `calculate_mrr` — called from 9 of its 10 real
    call sites — still reports the ORIGINAL 5-slot MRR. -/
theorem stale_after_upgrade_witness :
    mrrGenericSlot 5 1000 1 = 5000 ∧ mrrSlotAware 10 1000 1 = 10000 := by decide

end MeteroidVerify
