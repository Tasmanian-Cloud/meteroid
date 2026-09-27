//! Usage-event aggregation, and the dedup gap it's missing.
//!
//! Companion to `proof/MeteroidVerify/Metering.lean` — same algebra, proved
//! directly in Lean rather than extracted through Charon/Aeneas (no unsafe
//! code, bit-tricks, or lock-free concurrency here to justify that heavier
//! route — `proof/RESEARCH.md`).
//!
//! Modeled over `i64`, not the real `f64` (`metering/src/domain.rs:73-80`'s
//! `Usage.value`) — matching how the real system ultimately persists
//! money/usage quantities as integer minor units downstream. The `f64`
//! in-memory representation and the lossy `Decimal::from_f64` round-trip at
//! `metering/src/query/service.rs:136` are a *representation* gap on top of
//! this aggregation semantics, not modeled here: floats have no fragment in
//! this proof style (`proof/PROOF.md`).
//!
//! The real gap this module formalizes: `metering/src/ingest/common.rs`'s
//! `EventProcessor::process_events` never checks a `RawEvent::key()`
//! (`tenant_id`, `id`) for duplicates before handing events to the Kafka
//! sink — confirmed by direct read, not grep-absence. Dedup is delegated
//! entirely to ClickHouse's `ReplacingMergeTree`/`ReplicatedReplacingMergeTree`
//! (async background merge); zero query SQL in the module uses `FINAL`. So a
//! duplicate event (at-least-once Kafka delivery, a retried ingest call) can
//! be double-counted by `Sum`/`Count` aggregations until an unscheduled merge
//! runs. `sum_double_counts_duplicates` / `count_double_counts_duplicates`
//! below exercise exactly that, matching the Lean theorems by name.

use meteroid_pure_core::pure_core;

/// A usage event's dedup key: `(tenant_id, id)` — `RawEvent::key()`
/// (`metering/src/ingest/domain.rs:21-24`). Opaque ids: the algebra doesn't
/// care what a tenant or event id "means".
pub type EventKey = (i64, i64);

/// One usage event: its dedup key and its (already-parsed) numeric value.
#[derive(Copy, Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Event {
    pub key: EventKey,
    pub value: i64,
}

/// The aggregation kinds `metering/src/domain.rs:7-15` names, minus `Avg` and
/// `CountDistinct` (derived quantities, not folds with their own
/// identity/associativity story — `proof/RESEARCH.md`).
#[derive(Copy, Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AggKind {
    Sum,
    Count,
    Min,
    Max,
    Latest,
}

/// First-occurrence-wins dedup by key — the semantics `RawEvent::key()`
/// documents but that ClickHouse's `ReplacingMergeTree` only approximates
/// asynchronously.
#[pure_core]
pub fn dedup(evts: &[Event]) -> Vec<Event> {
    let mut seen: Vec<EventKey> = Vec::new();
    let mut out = Vec::new();
    for e in evts {
        if !seen.contains(&e.key) {
            seen.push(e.key);
            out.push(*e);
        }
    }
    out
}

/// Aggregate a list of events under one `AggKind`. `Min`/`Max` on an empty
/// list default to `0` (matching a `COALESCE(..., 0)`-style real query, not a
/// documented invariant — flagged in `proof/RESEARCH.md` as unverified
/// against the actual ClickHouse SQL).
#[pure_core]
pub fn aggregate(kind: AggKind, evts: &[Event]) -> i64 {
    match kind {
        AggKind::Sum => evts.iter().map(|e| e.value).sum(),
        AggKind::Count => evts.len() as i64,
        AggKind::Min => evts.iter().map(|e| e.value).fold(0, |a, b| if b < a { b } else { a }),
        AggKind::Max => evts.iter().map(|e| e.value).fold(0, |a, b| if b > a { b } else { a }),
        AggKind::Latest => evts.last().map(|e| e.value).unwrap_or(0),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dup_example() -> Vec<Event> {
        vec![
            Event { key: (1, 100), value: 5 },
            Event { key: (1, 100), value: 5 },
        ]
    }

    #[test]
    fn sum_double_counts_duplicates() {
        let raw = dup_example();
        let deduped = dedup(&raw);
        assert_ne!(aggregate(AggKind::Sum, &raw), aggregate(AggKind::Sum, &deduped));
        assert_eq!(aggregate(AggKind::Sum, &raw), 10);
        assert_eq!(aggregate(AggKind::Sum, &deduped), 5);
    }

    #[test]
    fn count_double_counts_duplicates() {
        let raw = dup_example();
        let deduped = dedup(&raw);
        assert_ne!(aggregate(AggKind::Count, &raw), aggregate(AggKind::Count, &deduped));
        assert_eq!(aggregate(AggKind::Count, &raw), 2);
        assert_eq!(aggregate(AggKind::Count, &deduped), 1);
    }

    #[test]
    fn min_max_ignore_duplicates() {
        let raw = dup_example();
        let deduped = dedup(&raw);
        assert_eq!(aggregate(AggKind::Min, &raw), aggregate(AggKind::Min, &deduped));
        assert_eq!(aggregate(AggKind::Max, &raw), aggregate(AggKind::Max, &deduped));
    }

    /// Loads `vectors/metering_agg.json` and checks every case — the same
    /// vectors `proof/MeteroidVerify/Metering.lean` is checked against.
    #[test]
    fn matches_shared_vectors() {
        #[derive(serde::Deserialize)]
        struct Case {
            kind: AggKind,
            events: Vec<Event>,
            expect: i64,
        }
        #[derive(serde::Deserialize)]
        struct Vectors {
            cases: Vec<Case>,
        }
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../vectors/metering_agg.json");
        let data = std::fs::read_to_string(path).expect("read vectors/metering_agg.json");
        let vectors: Vectors = serde_json::from_str(&data).expect("parse vectors/metering_agg.json");
        for case in vectors.cases {
            assert_eq!(aggregate(case.kind, &case.events), case.expect);
        }
    }
}
