import Lake
open Lake DSL

-- meteroid's native-Lean proof package. song-style, not intent-style: the
-- algebra is proved *directly* in pure Lean (decide/omega), not written in
-- Rust first and pulled through Charon/Aeneas extraction. `require song`
-- reuses `Song.Foundation`'s `Term`/`state` fold rather than redefining a
-- parallel one. Real Rust arithmetic complexity that DOES warrant
-- Charon+Aeneas extraction (proration, tax rate conversion) lives in a
-- separate `proof-extract/` package once the toolchain is available
-- (`RESEARCH.md`) — never in this one, since `song` pins a different Lean
-- version than apeiron's Aeneas output.
package meteroid_verify

-- Note: Song dependency commented out for isolated proof testing.
-- Uncomment below and ensure ../song symlink exists to use Song.Foundation.
-- require song from "../../song"

@[default_target]
lean_lib MeteroidVerify where
  globs := #[.submodules `MeteroidVerify]
