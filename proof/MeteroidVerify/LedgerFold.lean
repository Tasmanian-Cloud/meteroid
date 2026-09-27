import Song.Foundation

/-!
# meteroid / LedgerFold — the append-only-ledger basis, on `Song.Foundation.Term`

This is the piece the lakefile's own comment always intended and this proof package never
actually used: `require song` was meant to reuse `Song.Foundation`'s `Term`/`state` fold rather
than each domain file redefining a parallel notion of "current value from history." Up to now
every file here has been a self-contained, disconnected model. This is the first basis module —
a small set of composable facts meteroid's domain instances build on, in the spirit of
`Song.Float3` (float IS three integers, proved once; every rounding site since composes that,
not a fresh model) rather than re-deriving the same shape file by file.

**The recurring real shape.** `repositories/subscriptions/slots.rs`'s `slot_transactions` table —
a seed row (`SlotTransactionNewInternal::from_fee`, `domain/slot_transactions.rs:39-53`,
`delta = 0, prev_active_slots = initial_slots`) followed by an append-only stream of
`(delta, prev_active_slots)` rows — is a `Song.Foundation.Term Int` in exactly the sense
`Foundation.lean` defines: a seed (`Term.K seed 0`) grown by a `spine` of deltas, and its current
value is `Term.state (·+·)` over that whole term. `Term.state_spine` (`Song/Foundation.lean:145`)
already proves this equals `deltas.foldl (·+·) seed` — not a new fact this file needs to derive,
a fact this file INSTANTIATES.

The dunning failure count (`count_failed_for_invoice`, a running COUNT over a stream of failure
events), invoice/credit-note sequential numbering (a running total over a stream of `+1`s), and
MRR movement logs (`BiMrrMovementLogRowNew`, a running total over a stream of churn/expansion
deltas) are all the same shape — a seed plus an append-only stream, read by folding, not by
re-reading the seed.

**The bug shape this basis names.** `MrrSlotStaleness.lean` found `calculate_mrr`'s `Slot` arm
reading `initial_slots` (the ledger's SEED) while `calculate_components_mrr_with_slots` correctly
reads `current_active_slots` (the ledger's FOLD over every recorded delta). Restated in this
file's vocabulary: the bug is `ledgerCurrentValue seed []` (an unextended term — just the seed)
where the correct read is `ledgerCurrentValue seed deltas` (the term properly extended over the
whole recorded stream). `stale_seed_diverges_from_true_ledger` below states this generally, not
as a slot-specific fact — any future "cached/snapshot field vs. re-fold the ledger" bug this
codebase has (this session did not check every candidate; `MrrSlotStaleness` is the one
confirmed instance) is the SAME shape, provable by the SAME lemma, not a new one.

**What is NOT claimed:** that every one of meteroid's stateful computations is a ledger fold —
`PaymentReversal.lean`'s clamp invariants and `EntitlementGracePeriod.lean`'s threshold are a
different shape (bounded-interval composition, not stream-folding) and belong in a separate
basis module, not force-fit into this one.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/`native_decide`.
-/

namespace MeteroidVerify

open Song

/-- A ledger term: a seed value, extended by a left-spine of recorded deltas — the abstract shape
    of `slot_transactions`' seed row plus its append-only stream, dunning's failure-event stream,
    and sequential-numbering's `+1` stream. `Term.K seed 0` is the seed alone (`state (+) = seed +
    0 = seed`); `Term.spine` (`Song/Foundation.lean:138-140`) grows it by the recorded deltas. -/
def ledgerTerm (seed : Int) (deltas : List Int) : Term Int :=
  spine (.K seed 0) deltas

/-- The ledger's current value: fold the term under `(+)`. -/
def ledgerCurrentValue (seed : Int) (deltas : List Int) : Int :=
  Term.state (·+·) (ledgerTerm seed deltas)

/-- Not a new derivation — `Term.state_spine` already proves reading a growing spine is exactly
    `List.foldl`; this is that theorem read at `op = (+)`, `t = Term.K seed 0`. -/
theorem ledgerCurrentValue_eq_foldl (seed : Int) (deltas : List Int) :
    ledgerCurrentValue seed deltas = deltas.foldl (·+·) seed := by
  unfold ledgerCurrentValue ledgerTerm
  rw [state_spine]
  simp

/-- The seed alone (`deltas = []`) reads as `seed` itself — the un-extended term. -/
theorem ledgerCurrentValue_seed_only (seed : Int) :
    ledgerCurrentValue seed [] = seed := by
  rw [ledgerCurrentValue_eq_foldl]
  rfl

/-- **The bug shape, named generally.** Reading a ledger's SEED alone diverges from its TRUE
    current value exactly when the recorded stream would actually move it — i.e. whenever the
    deltas don't fold back to the seed itself (the "nothing happened yet" case). This is
    `Term.state_spine` read as a warning: an unfolded term (`.K seed 0`, never `spine`-extended)
    denotes the seed, full stop — it does not, and cannot, reflect anything appended after it. -/
theorem stale_seed_diverges_from_true_ledger (seed : Int) (deltas : List Int)
    (h : deltas.foldl (·+·) seed ≠ seed) :
    ledgerCurrentValue seed [] ≠ ledgerCurrentValue seed deltas := by
  rw [ledgerCurrentValue_seed_only, ledgerCurrentValue_eq_foldl]
  exact fun heq => h heq.symm

/-- Concrete instantiation of the exact `MrrSlotStaleness.lean` witness: a subscription seeded
    with 5 slots (`initial_slots`), later upgraded by +5 (one recorded `slot_transactions` delta,
    the 5→10 upgrade). The stale seed-only read stays at 5; the true ledger value is 10 — the same
    numbers `MrrSlotStaleness.stale_after_upgrade_witness` proves independently, now derived from
    this shared basis instead of a bespoke model. -/
theorem mrr_slot_staleness_is_a_ledger_fold_bug :
    ledgerCurrentValue 5 [] ≠ ledgerCurrentValue 5 [5] := by
  apply stale_seed_diverges_from_true_ledger
  decide

end MeteroidVerify
