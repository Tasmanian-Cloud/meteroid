# Proof register — how to read `register.toml`

## License

This directory (`proof/` — the Lean sources under `MeteroidVerify/`,
`register.toml`, `RESEARCH.md`, `lakefile.lean`, and this file) and the two
Rust companion crates it depends on, `crates/meteroid-proof-core/` and
`crates/meteroid-pure-core/`, are licensed under **Apache License 2.0**
(see `proof/LICENSE` and each crate's own `LICENSE` file), distinct from
the **AGPL-3.0-only** license covering the rest of this repository (see the
top-level `LICENSE`). This carve-out reflects that the proof code is a
self-contained, independently-authored verification harness that is not
linked into meteroid's own binaries and can be used, forked, or referenced
under permissive terms independent of the AGPL obligations that apply to
meteroid's application code.

Every `#[pure_core]` function in `crates/meteroid-proof-core` has exactly one
`[[core]]` row in `register.toml`. Rules a `scripts/proof-register.py` gate
(ported from `linkfold`/`intent`, not yet added here) will enforce statically:

- every `#[pure_core]` function has exactly one `[[core]]` row;
- every `[[core]]` row names a `#[pure_core]` function;
- a row claiming `status = "Lean (native)"` names a real theorem in
  `proof/MeteroidVerify/*.lean` and `lake build` there is green;
- a row claiming `status = "Aeneas"` carries a proof-repo commit and artifact
  hash, once `proof-extract/` exists;
- a row without either MUST say `"owed"`.

`Lean (native)` is not claimed until `lake build` has actually been run and
is green — an honest `"owed"` beats a premature stronger status.

## Fragment law for `crates/meteroid-proof-core/src/cores/`

Integers, enums, bool, bounded loops — no floats, no I/O, no allocation
beyond a fixed-size/linear pass. These functions are from-scratch models of
meteroid's *intended* semantics (not extracted from the real Rust), so the
fragment law exists to keep them provable directly in Lean via
`decide`/`rfl`/`omega`, the same reason `linkfold` and `apeiron` both keep it.
