import Song.Foundation

/-!
# meteroid / Metering — usage aggregation, and the dedup gap it's missing

Companion to `crates/meteroid-proof-core/src/cores/metering_agg.rs` — same
algebra, proved directly in Lean rather than pulled through Charon/Aeneas
extraction (no unsafe code, bit-tricks, or lock-free concurrency in the real
`metering` module to justify that heavier route — `RESEARCH.md`).

Modeled over `Int`, not the real `f64` (`metering/src/domain.rs:73-80`'s
`Usage.value`) — matching how the real system ultimately persists money/usage
quantities as integer minor units downstream. The `f64` in-memory
representation and the lossy `Decimal::from_f64` round-trip at
`metering/src/query/service.rs:136` are a *representation* gap on top of the
aggregation semantics proved here, not modeled: floats have no fragment in
this proof style (pure Lean core, no Mathlib/Batteries).

**The real gap this file formalizes:** direct reading of
`metering/src/ingest/common.rs`'s `EventProcessor::process_events` (lines
39-246) found no `RawEvent::key()` (`tenant_id`, `id`) dedup check anywhere in
the ingest path before events are handed to the Kafka sink. Dedup is
delegated entirely to ClickHouse's `ReplacingMergeTree` /
`ReplicatedReplacingMergeTree` table engines (async background merge); a full
grep of every query SQL file in the module found zero uses of `FINAL`. So a
duplicate event (at-least-once Kafka delivery, a retried ingest call) can be
double-counted by `Sum`/`Count` aggregations until an unscheduled merge runs.
`sum_double_counts_duplicates` / `count_double_counts_duplicates` below make
that a concrete, machine-checked fact rather than a note in a doc — this file
does not patch meteroid's Rust, it formalizes what it actually does today.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- A usage event's dedup key: `(tenant_id, id)` — `RawEvent::key()`
    (`metering/src/ingest/domain.rs:21-24`). Opaque ids: the algebra doesn't
    care what a tenant or event id "means", same convention as `linkfold`'s
    comdat signatures. -/
abbrev EventKey := Nat × Nat

/-- One usage event: its dedup key and its (already-parsed) numeric value. -/
structure Event where
  key : EventKey
  value : Int
deriving DecidableEq, Repr

/-- First-occurrence-wins dedup by key — the semantics `RawEvent::key()`
    documents but that ClickHouse's `ReplacingMergeTree` only approximates
    asynchronously (no query in the module ever uses `FINAL`). -/
def dedupGo (seen : List EventKey) : List Event → List Event
  | [] => []
  | e :: rest =>
    if e.key ∈ seen then dedupGo seen rest
    else e :: dedupGo (e.key :: seen) rest

def dedup (evts : List Event) : List Event := dedupGo [] evts

/-- The aggregation kinds `metering/src/domain.rs:7-15` names, minus `Avg`
    and `CountDistinct` (derived quantities, not folds with their own
    identity/associativity story — out of scope for this file, `RESEARCH.md`). -/
inductive AggKind where
  | sum | count | min | max | latest
deriving DecidableEq, Repr

/-- Aggregate a list of events under one `AggKind`. `min`/`max` on an empty
    list default to `0` (matching a `COALESCE(..., 0)`-style real query, not
    a confirmed invariant of the actual ClickHouse SQL — flagged in
    `RESEARCH.md` as unverified). -/
def aggregate (k : AggKind) (evts : List Event) : Int :=
  match k with
  | .sum => (evts.map Event.value).foldl (· + ·) 0
  | .count => (evts.length : Int)
  | .min => (evts.map Event.value).foldl (fun a b => if b < a then b else a) 0
  | .max => (evts.map Event.value).foldl (fun a b => if b > a then b else a) 0
  | .latest => ((evts.map Event.value).getLast?).getD 0

-- ═══════════════════════════════════════════════════════════════════
-- The dedup gap, formalized as a concrete counterexample.
-- ═══════════════════════════════════════════════════════════════════

/-- Two events, same `(tenant_id=1, id=100)` key, same value — exactly the
    shape an at-least-once Kafka redelivery or a retried ingest call
    produces. -/
def dupExample : List Event := [⟨(1, 100), 5⟩, ⟨(1, 100), 5⟩]

theorem dedup_dupExample : dedup dupExample = [⟨(1, 100), 5⟩] := by decide

theorem sum_double_counts_duplicates :
    aggregate .sum dupExample ≠ aggregate .sum (dedup dupExample) := by decide

theorem count_double_counts_duplicates :
    aggregate .count dupExample ≠ aggregate .count (dedup dupExample) := by decide

/-- `min`/`max` are unaffected by this particular duplicate (both events
    carry the same value) — the aggregation kinds where this input does NOT
    produce a wrong answer, matching `metering_agg.rs`'s
    `min_max_ignore_duplicates` test. Stated on the concrete example, not as
    a general theorem over arbitrary duplicate values (a general claim would
    need a separate argument this file doesn't make). -/
theorem min_max_ignore_duplicates_on_dupExample :
    aggregate .min dupExample = aggregate .min (dedup dupExample) ∧
    aggregate .max dupExample = aggregate .max (dedup dupExample) := by decide

end MeteroidVerify
