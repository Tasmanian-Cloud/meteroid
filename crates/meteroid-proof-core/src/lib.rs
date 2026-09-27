//! `meteroid-proof-core` — companion re-implementations for `proof/`.
//!
//! Everything under `cores/` is a from-scratch, hand-written model of a piece
//! of meteroid's real semantics (metering aggregation, tiered/volume/package
//! pricing, ...) kept in-fragment (integers/enums/bool/bounded loops, no
//! floats, no I/O — `proof/PROOF.md`'s fragment law) so it can be proved
//! directly in Lean (`proof/MeteroidVerify/*.lean`) without a Charon/Aeneas
//! round-trip. It is NOT the real meteroid Rust and is not linked into any
//! meteroid service — it is cross-checked against the real crates only via
//! shared `vectors/*.json` test vectors, matching `linkfold`'s own pattern of
//! keeping the Lean-proved core and the real implementation as two separate
//! artifacts agreeing on concrete inputs, not one machine-derived from the
//! other. Where real Rust arithmetic complexity (proration, tax rate
//! conversion) is extracted through Charon+Aeneas instead, that lives in a
//! separate `proof-extract/` package (`proof/RESEARCH.md`), not here.

pub mod cores;
