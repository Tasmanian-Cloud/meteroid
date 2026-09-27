//! `#[pure_core]` — the register marker (`proof/PROOF.md`).
//!
//! A no-op attribute macro. Its only job is to be greppable: every function that
//! carries it MUST have exactly one row in `proof/register.toml` naming a proof
//! status, and every row MUST name a function that carries it.
//!
//! Pattern copied from `linkfold-pure-core` (`~/projects/linkfold`), itself
//! copied from `intent-pure-core` (`~/projects/intent`) — same shape, same
//! reason: don't re-derive a mechanism that already exists in this workspace
//! for exactly this job.

use proc_macro::TokenStream;

/// Mark a pure decision function as belonging to the proof register.
///
/// Inert at compile time — the item is returned unchanged.
#[proc_macro_attribute]
pub fn pure_core(_attr: TokenStream, item: TokenStream) -> TokenStream {
    item
}
