# Research log — meteroid formal verification

Working directly inside the vendored `meteroid` fork (per Clay's direction
2026-09-27) rather than a separate `<name>fold` companion repo — the proof
package (`proof/`) and its Rust companion crates
(`crates/meteroid-{pure,proof}-core`) live alongside the code they model.

## The basis pivot: `LedgerFold.lean`, actually reusing `Song.Foundation`

`proof/lakefile.lean`'s own comment always said the point of `require song`
was to reuse `Song.Foundation`'s `Term`/`state` fold "rather than
redefining a parallel one." Up to this point that never happened — every
one of the (at the time) 21 Lean files here was self-contained, each
defining its own local, disconnected types (`MrrSlotStaleness.lean`'s own
`mrrGenericSlot`, `PaymentReversal.lean`'s own four ad-hoc clamp formulas,
etc.) with no shared vocabulary between them, and the only real reuse of
`song` was `FloatError.lean` citing `Float3`'s `roundU`/`roundU_bound` for
the one f64-rounding seam.

Corrected 2026-09-27, at Clay's direction: the goal is to model meteroid's
logic against a genuine shared basis — in the same spirit as
`Song.Float3` ("a float IS three integers," proved once, every rounding
site since composes that instead of a fresh model per site) — rather than
as N independent one-off proofs of similar-shaped facts.

**The first basis module, `LedgerFold.lean`.** Read `Song/Foundation.lean`
directly (not from memory): `Term α` is a binary tree over a carrier,
`state op` folds it under a chosen operation, and `spine`/`state_spine`
(`:138-151`) prove that growing a term by a stream of values and reading
it is EXACTLY `List.foldl` over that stream — the abstract shape of
"a seed plus an append-only ledger of deltas, read by folding." This is
not a metaphor stretched onto meteroid's domain: `slot_transactions` (a
seed row plus an append-only stream of `(delta, prev_active_slots)` rows,
`domain/slot_transactions.rs`) IS this shape, verbatim. So are the dunning
failure count, invoice/credit-note sequential numbering, and MRR movement
logs — every "current value from history" pattern this session kept
re-deriving independently.

`LedgerFold.lean` genuinely `import Song.Foundation` and instantiates
`ledgerTerm`/`ledgerCurrentValue` at `op = (+)`, proves
`ledgerCurrentValue_eq_foldl` by citing `state_spine` (not re-deriving
it), and names the bug shape generally: `stale_seed_diverges_from_true_ledger`
states that reading a ledger's SEED alone (`ledgerCurrentValue seed []`,
an un-extended `Term.K seed 0`) diverges from its TRUE current value
whenever the recorded stream would actually move it. This is exactly
`MrrSlotStaleness.lean`'s finding, restated as the general case rather
than a slot-specific coincidence: `calculate_mrr`'s bug is precisely
"reads the ledger's seed, not its fold." Wired the connection as a real,
machine-checked theorem, not prose: `MrrSlotStaleness.lean` now
`import`s `LedgerFold` and proves `staleness_is_the_ledger_fold_bug` —
the SAME 5→10-slot-upgrade numbers as `stale_after_upgrade_witness`,
derived by feeding `mrrGenericSlot`/`mrrSlotAware` the shared basis's
`ledgerCurrentValue 5 []`/`ledgerCurrentValue 5 [5]` instead of bare
integers. If this weren't a real fit, that link would not build; it does.

**What this is NOT claiming.** Not every stateful computation in this
codebase is a ledger fold. `PaymentReversal.lean`'s four clamp invariants
and `EntitlementGracePeriod.lean`'s threshold check are a different shape
— bounded-interval composition (clamp/max/min preserving a range), not
stream-folding — and belong in a separate basis module (a `Basis.lean` for
interval arithmetic: `clamp`, and how `+`/`max`/`min` compose bounds,
proved once, so each of `PaymentReversal.lean`'s four proofs becomes
"compose these primitives" instead of an independent `omega` search) —
not yet built, next candidate for the same treatment. Retrofitting every
existing file onto a shared basis, and identifying which OTHER files are
secretly the same ledger-fold shape (a candidate list, not yet audited:
the dunning failure count, invoice/credit-note numbering, MRR movement
logs) is ongoing, not complete after one file.

## Scope and staging

Staged across the three subsystems that carry meaningful semantics in an
858-file repo: metering (usage ingestion/aggregation) → store (subscription
state + pricing) → invoicing/tax (proration + tax computation). The rest
(auth, UI, billing-webhook plumbing, migrations, the `meteroid-invoicing`
crate's pure PDF/XML rendering) is out of scope — confirmed by direct source
reading, not inferred from file names.

## `sanguine` is excluded

`sanguine` shares `song`'s Lean toolchain (`v4.30.0-rc2`) but its actual proof
corpus (`SanguineOS.lean`, `UniversalThreat.lean`, physics-prediction claims
from a "x = B/U" universal encoding) is a separate, speculative, foundational
project with nothing reusable for billing arithmetic or state machines.
`song` alone is the native-Lean dependency here.

## Two Lean toolchains, two Lake packages

`song`/`linkfold` pin Lean `v4.30.0-rc2`. The real `apeiron` checkout (at
`~/orca/apeiron`, not under `~/projects` — `calamine-apeiron` is unrelated,
just a `calamine` fork depending on `apeiron::Map`) pins Lean `4.31.0` with
Aeneas `nightly-2026.09.09-505b6ca`/Charon `0.1.254`. These cannot coexist in
one Lake package. `proof/` (this package) is native-Lean-only, `require song`.
A `proof-extract/` package for real Charon+Aeneas extraction was built and
tried (below) — never merged into `proof/` while it existed, for the
toolchain-mismatch reason above, and removed after the extraction itself
proved impractical for this codebase's targets (float/Decimal arithmetic).
The two proof styles cross-check only through shared `vectors/*.json` test
vectors, matching `linkfold`'s own pattern.

## Charon+Aeneas toolchain: RESOLVED 2026-09-27 (was reported broken/parked)

The rustup component-download race blocking `linkfold` (and this repo,
initially) was narrower than it looked: `rustup toolchain install
nightly-2026-08-18 --profile minimal --component rustc,cargo,rust-std`
succeeds fine — only the optional `clippy`/`rustfmt` components (needed by
charon's `Makefile`'s `format` target, not by the compiler itself) were
hitting the download race, and stale `~/.rustup/downloads/*.partial` files
from the earlier failed attempts were compounding it. Clearing those and
installing with a minimal profile (skipping `format`, calling `cargo build`
directly) got past that specific block — but a from-source `charon` build
still fails on unrelated rustc-internal API drift (`E0463`/`E0599`/`E0533`
in `rustc_trait_elaboration`, needs `rustc-dev`/`rust-src`/`llvm-tools`
components too, and even with those, charon's pinned commit doesn't
type-check cleanly against this specific nightly snapshot) — not chased
further since it's unnecessary:

**Apeiron's pinned prebuilt release archive
(`aeneas-linux-x86_64.tar.gz`, sha256 `d5ba53b1370d30866bcd86de5e34abfbadf09e76b3689a7f70f458cd0c133591`,
matches the published hash exactly) bundles working `charon`, `charon-driver`,
AND `aeneas` binaries at the exact pinned versions** (`charon version` →
`0.1.254 (b104e24fea7d721b71e6c39fd70f26ff20bc0980)`; `aeneas -version` →
`nightly-2026.09.09-505b6ca`) — no from-source build needed at all. Verified
2026-09-27 with a real end-to-end round-trip on a one-function dummy crate
(`charon cargo --preset=aeneas` → `.llbc` → `aeneas -backend lean` →
clean `.lean` output, zero `axiom`/`sorry`/`admit`). Unpacked into
`target/aeneas/` (already covered by the existing `target/` gitignore entry),
matching apeiron's own `proof/lakefile.lean` wiring exactly.

This supersedes `linkfold/proof/register.toml`'s "parked, not retried a
third time" note for *this* repo's Phase 3 — worth flagging back to that
project separately, not fixed here.

## Phase 3 Aeneas extraction attempt: real toolchain, real structural blocker

With the toolchain working, a `proof-extract/` package was built following
apeiron's `proof/extract/lib.rs` pattern exactly: a standalone
`charon rustc --preset aeneas` translation unit wrapping
`nominal_period_days`/`component_proration_factor` (verbatim copies of
`proration.rs:78-86,96-113`) and a new `prorated_amount_cents` isolating the
real inlined `(amount as f64 * factor).round() as i64` pattern
(`proration.rs:186,212,243,295`).

**It could not be a live `#[path]` link to the real file**, unlike apeiron's:
`proration.rs`'s `use` statements pull in `rust_decimal::Decimal`,
`chrono::NaiveDate`, and several `crate::domain::*` types from OTHER
functions in the same file (`calculate_proration`, `net_override_lines`)
that Charon's single-file `rustc` invocation must type-check even though
they're unreachable from the extraction roots. Apeiron's own extraction only
works because its kernel modules (`scalar.rs`, `cell.rs`, ...) were
engineered from the start to have zero dependencies outside what's
`#[path]`-included together — meteroid's proration logic, embedded in a
large domain-driven crate, doesn't meet that bar. Worked around with a
disclosed verbatim copy against a local mirror enum instead (see the removed
`proof-extract/extract/lib.rs`'s own doc comment, preserved in git history if
this is revisited).

**Running the actual extraction found a harder, structural blocker: Aeneas
has no float support at all.** `charon rustc --preset aeneas` on the wrapper
above failed with `Improperly typed constant value` (on the literal `30.0`)
and `Invalid inputs for binop` (on `amount_cents as f64 * factor`). Traced to
the actual cause, not assumed: `~/Workspace/aeneas/src/interp/InterpExpressions.ml`'s
constant-value and binop evaluators pattern-match explicit cases for
`TBool`/`TChar`/`TInteger (Signed/Unsigned)` — there is no `TFloat` case at
all, so any float literal or float operation falls through to the generic
error. This is not a missing flag or a preset issue; it's confirmed by
reading the interpreter source. `rust_decimal::Decimal` (tax) has the same
practical outcome for a different reason: it's a third-party type with no
Aeneas builtin, so wrapping `determine_tax_details`'s real arithmetic would
face an equivalent wall even before reaching the float question.

**Conclusion, per the workspace's anti-loop rule (one real, working-toolchain
attempt made, structural cause confirmed by source — not retried further):
Phase 3 proceeds entirely via Path B** (native Lean against `song`,
hand-transcribed, honestly flagged as such) for both proration and tax. The
toolchain fix (previous section) remains genuinely useful — it's now
verified working for the fragment Aeneas *does* support (bools, chars,
integers, simple ADTs, matching everything Phase 1/2 and apeiron's own
kernels use) — floats and `Decimal` are the located boundary, not the whole
toolchain.

## Closing the float gap anyway: `FloatError.lean`, reusing `song`'s own Float3

Clay pointed back at `song/AGENTS.md`'s own line — "float = 3 ints ...
Float3/NullCell = the proof" — as prior art for exactly this problem.
Checked directly (`song/Song/Float3.lean`): `NullCell` doesn't exist
anywhere in `song` or the real `apeiron` checkout (grepped both, zero hits —
likely stale/condensed notation in the AGENTS.md line). What's real is
`F3`/`toGrid`/`gridSum`/`gridSum_order_free`/`roundU`/`roundU_bound` — but
it's narrower than "floats are solved": every lemma there assumes you start
from EXACT, already-rounded values and introduces exactly ONE controlled
integer-rounding step at the end (`roundU` rounds an exact wide integer to
the nearest ulp multiple). It does not model the error of freshly rounding a
*computed* real value (a division, a multiplication) to a float — that's a
different, harder theory (unit-roundoff / relative-error analysis, the kind
Coq's Flocq library exists specifically for) that doesn't exist here.

**What was actually buildable, and built** (`FloatError.lean`): reuse
`roundU`/`roundU_bound` DIRECTLY, not by copying them, by supplying the ulp
they need. `ulpFor p v := 2^(v.log2 + 1 - p)` (Lean core's `Nat.log2`, with
its real spec lemmas `Nat.log2_self_le`/`Nat.lt_log2_self` — `2^e ≤ v <
2^(e+1)`) computes which ulp a `p`-significant-bit float uses at magnitude
`v`; `roundToP p v := roundU (ulpFor p v.natAbs) v` models "round to `p`
significant bits" as one call into the existing, already-proved `roundU`.
The real `proration.rs` pipeline (division → multiplication → round-to-int,
`proration.rs:165-169,186,212,243,295`) is modeled as five composed steps on
a fixed-point grid (scale 100, comfortably past f64's 53 bits): grid-divide
→ round to 53 bits (models the REAL f64 division) → exact multiply → round
to 53 bits again (models the REAL f64 multiplication) → round back to whole
cents. Checked via `decide` (which fully evaluates `Nat.log2`/`roundU`
composed five layers deep on closed numerals — a genuine computation, not an
assumption) against 6 concrete cases pulled from `proration.rs`'s own real
tests, including a $10M invoice amount and the least-round ratio in the
suite (30/365): **the f64-rounding-modeled pipeline reaches the exact same
cents value as the idealized exact-rational one in every case checked.**

**Update, same day: the general bound is now proved, not just spot-checked.**
`roundToP_relative_bound (p : Nat) (hp : 1 ≤ p) (v : Int) : 2^(p-1) *
(v - roundToP p v).natAbs ≤ v.natAbs` — the standard IEEE-754 unit-roundoff
bound (`error ≤ v * 2^(1-p)`), universally quantified over every `v`, proved
by cases on whether `v` already fits in fewer than `p` bits (exact, error 0)
or not (the ulp itself, `2^(v.natAbs.log2+1-p)`, scaled by `2^(p-1)`,
collapses to `2^(v.natAbs.log2)`, which `Nat.log2_self_le` bounds by
`v.natAbs` directly). `roundHalfAwayFromZero_bound` (the analogous bound for
the exact-rational rounding steps) is proved the same way `roundU_bound`
itself is — name the Euclidean remainder via `Int.mul_ediv_add_emod`, bound
it, let `omega` close the linear arithmetic. Neither needed `ring` (checked:
not available without Mathlib) — the few nonlinear reshuffles needed
(`2*(a*b) = a*(2*b)`) go through `Int.mul_left_comm`/`Int.mul_comm`
explicitly, since `omega` treats syntactically-distinct products as
unrelated atoms and won't reassociate them itself; the fix each time was
`show`/an explicit `have` reshuffle so the atom shapes matched exactly, not
a smarter tactic. `lake build` green, zero `sorry`/`admit`/`axiom`.

**A real hazard from this shared workspace, worth recording plainly:** a
different, genuinely concurrent Claude session running its own separate
"policy-engine Aeneas/Charon/Lean" work in this same `~/projects` checkout
overwrote this file mid-proof with `sorry` placeholders and a coordination
comment, and added a `[[core]]` register row and a `[[future_core]]` entry —
the former claiming a status that was already false by the time it landed
(the `sorry`s it referenced were already fixed), the latter citing
`Decimal::from_f64` at `meteroid-tax/src/lib.rs:124-138`, which does not
exist there (checked directly — that range is region/VAT-scenario
resolution, not rate conversion; the real conversion is
`shared.rs:194-195,217-218`, already correctly cited above). Both were
removed. Confirms the root `CLAUDE.md`'s own warning about concurrent
agents sharing `~/projects` is not hypothetical — this file was live
evidence of it, not a close call.

The end-to-end composition (`f64FinalCents` vs `idealCents`, chaining
`roundToP_relative_bound` through the multiplication by `amountCents` and
`roundHalfAwayFromZero_bound` at both ends) is the natural next step now
that both foundational bounds are proved — not attempted in this pass.

## Known gaps in meteroid formalized so far (not silently patched)

1. **Metering dedup gap** (`Metering.lean`): no `RawEvent::key()` dedup
   anywhere in `EventProcessor::process_events`
   (`metering/src/ingest/common.rs:39-246`); dedup delegated to ClickHouse's
   async `ReplacingMergeTree` merge, zero query SQL uses `FINAL`. Formalized
   as `sum_double_counts_duplicates`/`count_double_counts_duplicates`.
2. **Pricing bugs** (`TierPricing.lean`, lake build green 2026-09-27): two
   *separate* bugs, corrected from the original scoping note after reading
   `fees.rs` directly — `tiered_charges` and `volume_charge` are not meant to
   agree with each other (deliberately different pricing models), so "the
   two functions disagree" was the wrong frame. The real bugs: (a)
   `_block_size` is accepted but never read by `compute_tier_price`/
   `compute_volume_price` (`fees.rs:117-124,160-167`, `// TODO block_size` at
   `:32,123,166`) — proved as a non-dependence theorem
   (`tiered_price_ignores_block_size`), not a guessed "correct" semantics,
   since the intended behavior was never specified; (b) `volume_charge`'s
   `next.first_unit - 1` (`fees.rs:90`) is an unguarded `u64` subtraction
   where the sibling `tiered_charges` uses `saturating_sub` (`fees.rs:48`) —
   two tiers sharing `first_unit = 0` make it go negative, a debug-panic /
   release-wrap hazard, proved reachable via an `Int`-valued model
   (`duplicate_zero_tier_upper_bound_goes_negative`).
   `SubscriptionStatus.lean` documents (does not prove — no centralized
   guard exists to prove against) the 11-state enum and 8 observed
   transition call sites; `Superseded`/`Errored` are declared but not found
   as assignment targets in the files checked — a gap in this file's
   coverage, not a claim of unreachability.
3. **Proration factor asymmetry** (`Proration.lean`, lake build green
   2026-09-27, Path B — see the Aeneas-attempt section above): the aligned
   branch of `component_proration_factor` (`proration.rs:96-113`) returns its
   `baseFactor` parameter completely unclamped, while the misaligned branch
   clamps to `[0,1]`. Since `baseFactor` (the real `proration_factor`,
   `proration.rs:165-169`) is never itself validated against
   `0 ≤ days_remaining ≤ days_in_period` by any caller, the common/aligned
   case has no defense against an out-of-range factor reaching a real dollar
   amount — a previously-unflagged asymmetry, formalized as two concrete
   `decide` theorems on the same out-of-range input
   (`aligned_branch_can_escape_unit_interval` vs
   `misaligned_branch_clamps_out_of_range_factor`). A separate conservation
   bound (`prorated_product_never_exceeds_full_period_product`) proves the
   *unrounded* exact-ratio product stays within `[0, amount]` given a valid
   `p ≤ q` factor, without needing to model rounding itself.
4. **Tax rounding strategy** (`TaxRounding.lean`, lake build green
   2026-09-27, Path B): `RoundingStrategy::MidpointAwayFromZero` modeled
   exactly as round-half-away-from-zero over an assumed-exact rational rate,
   matching `meteroid-tax/src/tests.rs`'s own hand-verified cases
   (999×0.21→210, 997×0.21→209) plus a genuine-midpoint case pinning it as
   distinct from banker's rounding. Does NOT resolve whether
   `Decimal::from_f64(rate.rate)` (`shared.rs:194-195,217-218`) is always
   exact for every real tax rate — an open gap, documented in the file
   itself, not silently assumed away.

## Modeling floats

None of this proof style's `cores::` functions use floats — pure Lean core
here has no IEEE-754 fragment without Mathlib, which `song` explicitly
excludes, AND (confirmed empirically, not just by `song`'s own house rule)
Aeneas's own interpreter has no float support to extract them through
either. Where the real Rust genuinely computes in `f64` (metering's
`Usage.value`, proration) or `Decimal` (tax), the native-Lean spec models
the *intended* exact-arithmetic semantics (e.g. integer minor units, exact
rational ratios) and notes the float/Decimal representation as a documented
divergence, never claimed to be proved identical to the real float/Decimal
computation. **Update below: for proration specifically, this divergence is
now closed by a real, general, symbolic bound — not just documented.**

## `f64_pipeline_bound`: the full end-to-end theorem, fully symbolic

Clay pushed back twice on stopping at the concrete `decide`-checked examples:
first pointing at `song`'s own Float3/`roundU` machinery as underused prior
art, then insisting on going the rest of the way to a fully general theorem
rather than case-by-case checks. Both pushes were right and led to real
additions, built incrementally and verified against the compiler at every
step (this is not a paper derivation asserted to work — every lemma below
is `lake build` green):

1. **`roundToP_relative_bound`** (`p ≥ 1 → 2^(p-1) * (v - roundToP p v).natAbs
   ≤ v.natAbs`) — the general IEEE-754 unit-roundoff bound, universally
   quantified over every `v : Int`, derived from `Nat.log2`'s real spec
   (`Nat.log2_self_le`, `Nat.lt_log2_self`), not asserted. Two cases: `v`
   already fits in fewer than `p` bits (error exactly `0`) or not (the ulp
   itself collapses to `2^(v.natAbs.log2)`, which `Nat.log2_self_le` bounds
   by `v.natAbs` directly).
2. **`roundHalfAwayFromZero_bound`** — the matching bound for the
   exact-rational rounding steps, proved the same way `Song.Float3.roundU_bound`
   itself is (name the Euclidean remainder via `Int.mul_ediv_add_emod`,
   bound it, `omega` closes the rest).
3. **`f64_division_accurate`** — composes (1) and (2) through the real
   division stage (`gridFactor` → `f64FactorScaled`) via the triangle
   inequality, cross-multiplied by `daysInPeriod` to avoid ever forming the
   ratio.
4. **`f64_product_accurate`** — composes (3), scaled by `amountCents`, with
   another application of (1) for the multiplication stage
   (`gridProduct` → `f64ProductScaled`).
5. **`f64_pipeline_bound`** — the full close: composes (4) with two more
   applications of (2) (`f64FinalCents`'s own final round and
   `idealCents`'s own round) into one bound directly relating
   `f64FinalCents` to `idealCents`, cross-multiplied by
   `2^f64Precision * (2^gridScale).natAbs * b.natAbs`:
   ```
   2^53 * (|fc - ic| * G.natAbs * b.natAbs) ≤
     2^53 * (G.natAbs * b.natAbs) +
     (amt.natAbs * (2*(b.natAbs*gridFactor.natAbs) + 2^52*b.natAbs) + 2*(b.natAbs*gridProduct.natAbs))
   ```
   The leading `2^53*(G.natAbs*b.natAbs)` term is not slack to be tightened
   away — it is the real, expected shape: two *independently* rounded
   integers (`f64FinalCents`'s own round, `idealCents`'s own round) can
   differ by up to 1 even with zero propagated float error, which is exactly
   real-world floating-point behavior, not a proof artifact.

**What made this tractable, and what didn't work:** `ring`/`ring_nf`/`set`
are all Mathlib-only — checked directly, not assumed — so every
associativity/commutativity reshuffle (`2*(a*b) = a*(2*b)`,
`a*(b*c) = b*(a*c)`, etc.) needed an explicit `Int.mul_left_comm`/
`Nat.mul_assoc`/`Nat.mul_comm` application, and `set` was replaced with
`generalize` + `unfold` throughout. `omega` cannot see through a single one
of these reassociations on its own — it treats syntactically distinct
products as unrelated atoms — which is why the file has several small
`private` reassociation lemmas (`two_mul_pow_reassoc`, `pow_succ_mul_reassoc`)
rather than relying on a tactic to find them. Two real Nat/Int type
ambiguities also cost iteration cycles: `2 ^ gridScale` silently elaborating
as `Nat` instead of `Int` in isolated positions (no `.natAbs` on `Nat`), and
`le_refl`/`Nat.le_refl` naming.

**A genuine mid-session hazard, not a hypothetical:** partway through this
work, a different, genuinely concurrent Claude session doing its own
unrelated "policy-engine Aeneas/Charon/Lean" work in this same shared
`~/projects` checkout overwrote this file with `sorry` placeholders and a
coordination comment, and added a `[[core]]` register row (already false by
the time it landed) and a `[[future_core]]` entry (citing a
`Decimal::from_f64` conversion at a file:line that does not exist — checked
directly). Both were removed; the correct citation
(`meteroid-tax/shared.rs:194-195,217-218`) was already documented above. This
confirms the root `CLAUDE.md`'s concurrent-agent warning is not
hypothetical for this workspace.

## Rebasing onto the real fork, and a tax-model rewrite mid-stream

The local checkout's `origin` was `meteroid-oss/meteroid` (the public
upstream) — never repointed to `Tasmanian-Cloud/meteroid` (the real,
actively-developed internal fork, confirmed via `gh repo view` and a push
timestamped the day before this session). Fixed by adding a
`tasmanian-cloud` remote, fetching, and rebasing (clean, no conflicts) —
`fees.rs`, `proration.rs`, and the metering files were untouched by the 9
commits the real fork had moved ahead by, so those proofs needed no changes.
`meteroid-tax/shared.rs` WAS substantially rewritten
(`feat: rewrite custom tax model and add tax categories`, #1212) into an
explicit precedence ladder (exemption → reverse-charge → override → engine
rate) — the `round_dp_with_strategy`/`Decimal::from_f64` call sites
`TaxRounding.lean` targets are still there, just moved into new
`resolve_override`/`resolve_engine_rate` helper functions at new line
numbers; only the citations needed updating, not the proof. Investigated the
new ladder itself for a bug (per the workspace's read-primary-sources rule,
not assumed clean from the rewrite's own doc comment) — found none: the
control flow enforces exemption-outranks-override correctly, `CustomerTax`'s
new `ReverseCharge` variant is wired into the customer-wide check, and
`resolve_engine_rate`'s match is exhaustively compiler-checked (no
wildcard). One numeric detail worth a future deliberate proof, not asserted
as broken: `ResolvedMultipleTaxRates`'s compound-tax branch (e.g. Canadian
QST-on-GST) sums independently-rounded per-line amounts into
`total_tax_amount` rather than rounding a single combined total.

## `distribute_discount`: a conservation theorem, not a bug

Scoped "migrations" as a priority and found it isn't really a
formal-verification target as stated — the DB DDL files themselves aren't
provable in this style, though they surfaced one real, tractable invariant
worth a future proof: `recompute_amount_due_from_settled_payments`
(`diesel-models/src/query/invoices.rs:664-684`) must exclude `Refunded` rows
entirely and net partial refunds via `(amount − amount_refunded)` — not yet
formalized.

Scoping `meteroid-store` more broadly surfaced `distribute_discount`
(`services/invoice_lines/discount.rs:10-63`), a largest-remainder
(Hamilton apportionment) split of a flat discount across line items. First
suspicion: the same class of bug as `fees.rs`'s `block_size` or
proration's unclamped factor — conservation breaking when `discount`
exceeds one line's own subtotal while others still have room. Working the
arithmetic by hand (not from the suspicion alone) disproved it: floor
division guarantees `discount * x / total < x` whenever `discount < total`
and `x > 0`, so the real code's `.max(0)` clamp (`discount.rs:38`) provably
never fires in that regime; when `discount == total` every item floors to
exactly its own subtotal with zero remainder, so pass 2 never even runs.
`discount > total` genuinely is non-conservative, but the existing tests
already know this — `test_discount_gt_sub_total` checks the result lands at
`0`, not that anything is conserved.

`DiscountConservation.lean`: proves the POSITIVE result instead —
`sum_pass1_eq` (a floor-division identity summed over a list, by induction)
and `pass1_sum_le_discount`/`pass1_taxable_pos` (the pass-1 total never
exceeds the discount; every item's pass-1 share is strictly less than its
own subtotal when `discount < total`) establish that the real algorithm is
exactly conservative and never clamps whenever `discount ≤ total_excl_vat` —
and that the count of pass-2 corrections is fixed by the floor-sum identity
independent of which items are chosen (the remainder sort is for fairness
of WHO absorbs the correction, not for the total to come out right — so
pass 2's selection logic itself isn't modeled, deliberately). Cross-checked
against `discount.rs`'s own `test_simple_distribution`/
`test_remainder_distribution` plus authored skewed-subtotal vectors
(`vectors/discount.json`).

## `calculate_coupons_discount`: the early-break threshold fires one subunit too early

Re-reading `calculate_coupons_discount` (`discount.rs:65-135`) to confirm it
was out of scope (`Decimal`-typed, same ceiling as tax rates) surfaced a
separate, narrower, fully-integer bug worth formalizing on its own: the
loop's `if subtotal_subunits <= Decimal::ONE { break; }` (`:90-92`) runs
**before** computing and applying that iteration's discount. A subtotal of
exactly `1` subunit breaks out before considering ANY further coupon,
including a "100% off, no exceptions" one — the customer pays the full cent
despite holding a coupon that should zero it out. `CouponThreshold.lean`'s
`subtotal_one_never_discounted` proves this concretely, contrasted with
`subtotal_two_fully_discounted` (the identical coupon applies normally at 2
subunits) to pin the bug to exactly this boundary, not a general
near-zero failure. Models only the break-then-apply ordering, not the
surrounding `Decimal` percentage/fixed-amount computation.

## `RefundInvariant.lean`: closes the open refund/status assumption

`InvoiceAmountDue.lean` flagged, as an open assumption, whether a
transaction's `Refunded` status and its `amount_refunded` field are kept
consistent by whatever code sets them. Traced it:
`repositories/payment_transactions.rs`'s reversal handler (`:329-394`)
clamps `new_amount_refunded` to `[0, transaction.amount]` in every one of
its three branches (`Cumulative` `.clamp(0, amount)` `:346`, `Full` sets it
to exactly `amount` `:369`, `Incremental` `.min(amount)` `:386`) and flips
status to `Refunded` iff `new_amount_refunded >= amount` (`:390-394`) — which
combined with the clamp means iff it equals `amount` exactly. **The
assumption holds; this is a positive result, closing a real gap, not
finding a bug.** The function is also genuinely careful about redelivery
idempotency (`refunded_at` high-water-mark checks, an explicit no-op guard)
— not modeled here, a different concern from the arithmetic this closes.
`RefundInvariant.lean` imports `InvoiceAmountDue.lean` and connects the two
directly: `refunded_transactions_net_to_zero` proves a fully clawed-back
transaction nets to exactly `0` in `settledSum`'s formula.

Scoped credit-note issuance alongside this: `repositories/credit_notes.rs:1035-1043`
rejects a `DebtCancellation` credit note whose total exceeds
`invoice.amount_due` at creation time — a real, correct-looking guard.
Whether the invoice row is locked before that check was left genuinely
unconfirmed at the time — **now traced and resolved as a real, confirmed
bug, see "Credit-note race" below.** Whether `applied_credits` and
`cancelled_sum`'s `DebtCancellation` credit notes could ever share the same
underlying credit remains unconfirmed, not yet traced.

## Credit-note race: the lock is real, the guard never reads its result

Followed up the locking question flagged above by reading the exact data
flow in `repositories/credit_notes.rs`, not just checking whether a lock
call is present anywhere in the function:

1. `create_user_credit_note_tx` (`:610-778`) reads the invoice via
   `InvoiceRow::find_detailed_by_id` (`:618`) — **no lock** — and binds it
   to `invoice`.
2. It calls `create_credit_note_tx` (`:676`), passing that same pre-lock
   `invoice` inside `CreateCreditNoteTxParams`.
3. `create_credit_note_tx` (`:778`) rebinds it unchanged at `:785`
   (`let invoice = params.invoice;`), THEN at `:789` calls
   `InvoiceRow::select_for_update_by_id` — confirmed (`diesel-models/src/query/invoices.rs:54-75`)
   to genuinely lock the row (customer-then-invoice ordering to avoid
   deadlocks) and return a fresh `InvoiceLockRow { invoice: InvoiceRow,
   customer_balance: i64 }` (`diesel-models/src/invoices.rs:154-157`). This
   return value is bound to `_invoice_lock` and never read again — grepped
   the full function body (`:789-1040`) for any reassignment of `invoice`
   or read of `_invoice_lock`; there is none.
4. The `DebtCancellation` guard (`:1035-1038`,
   `total.unsigned_abs() as i64 > invoice.amount_due`) checks the **pre-lock**
   binding from step 1/3, not the fresh, post-lock row the database just
   handed back in step 3.

## `applied_credits` vs `cancelled_sum`: closed, structurally disjoint (plus a bonus cross-file proof)

The other open question from the credit-note scope: could `applied_credits`
and `cancelled_sum`'s `DebtCancellation` credit notes ever reference the
same underlying credit and get double-subtracted in
`recompute_amount_due_from_settled_payments`'s formula? Traced every write
site of `invoice.applied_credits`
(`invoice_lines.rs:107-127,433-447,498-512`, `draft.rs`, `consolidate.rs`):
all of them set it once, at draft/finalize time, to
`min(total, customer_balance)` — a prepaid-account-balance mechanism applied
at invoice creation, unrelated to credit notes issued afterward. Confirmed
`credit_notes.rs`'s `credited_amount_cents` (the field that DOES feed
`applied_credits` downstream, for `CreditType::CreditToBalance`) is
hardcoded to `0` for `CreditType::DebtCancellation`
(`credit_notes.rs:1073`). **The two mechanisms are structurally disjoint —
no double count, closed as a positive result, not a bug.**

While tracing this, found a second, independently-written copy of
`recompute_amount_due_from_settled_payments`'s exact formula:
`payment_transactions.rs`'s `exists_live_for_invoice` (`:101-183`, guards
re-charge/merge/line-mutation on an invoice a live payment still owns)
computes `settled_net >= total - applied_credits - cancelled_sum` from
scratch, in a file that shares no code with `recompute_amount_due_from_settled_payments`.
Added `existsLiveCheck`/`exists_live_iff_amount_due_zero` to
`InvoiceAmountDue.lean`, proving this second formula is **exactly**
`newAmountDue = 0` — a genuine cross-file consistency result (two
independently-maintained checks provably agree, not merely similarly
named), not a restatement of the existing theorem.

**A third copy of the formula, checked and found consistent by construction.**
`services/invoices/consolidate.rs:229-241` computes
`amount_due = max(0, total - applied_credits)` for a newly-merged
consolidated invoice — textually missing the `cancelled_sum` term that the
other two copies have. Traced why: `build_and_finalize_consolidated`'s
`members` are always `Draft`-status invoices (the `members.len() <= 1`
branch right above it calls `finalize_invoice_tx`, i.e. these members have
never been finalized), and `create_user_credit_note_tx`
(`repositories/credit_notes.rs:623-627`) rejects credit-note creation
against any invoice that isn't `Finalized`. A draft invoice structurally
cannot have a `DebtCancellation` credit note against it yet, so
`cancelled_sum` is always `0` for every input to this formula — the shorter
form is consistent by construction, not an omitted term. Not modeled in
Lean: the discharging fact is a cross-function state invariant
("credit notes require Finalized"), not decidable arithmetic — recorded
here rather than forced into a theorem it doesn't fit.

## Dunning retry ladder: correct concurrency, and the off-by-one is pinned as a proof

Scouted `payment_transaction_failed.rs`'s retry-scheduling path next
(previously untouched territory — dunning/collections, not
pricing/invoicing). `on_payment_transaction_failed` is a genuinely
well-designed contrast to the credit-note race above: it locks the invoice
row FIRST (`select_for_update_by_id`, `:54`), then recomputes `amount_due`
from scratch on the SAME connection (`:62-68`, reusing
`recompute_amount_due_from_settled_payments`) — the fresh, post-lock value
actually drives the decision, unlike `credit_notes.rs`'s discarded
`_invoice_lock`. No bug here.

The ladder-index arithmetic
(`DUNNING_RETRY_SCHEDULE_DAYS.get(failed_attempts.saturating_sub(1))`,
`:135-136`, schedule `[3, 5, 7]` days) is exactly the off-by-one shape that
turned out to be real bugs elsewhere (`TierPricing.lean`'s tier-boundary
underflow, `CouponThreshold.lean`'s early break). Hand-traced it first:
confirmed `count_failed_for_invoice` always includes the CURRENT failure
(the handler is driven by a transactional-outbox event, which by
construction only publishes after the triggering `payment_transaction`
row's `Failed` status is already committed — no undercounting window) and
the indexing itself is correct (`failed_attempts=1` → first rung, `=4` →
exhausted). Found correct, not a bug — but pinned as `DunningSchedule.lean`
rather than left as a hand-trace, since the array or the subtraction
drifting out of sync on a future edit is exactly the kind of change a
proof, not a comment, would catch. `exhausted_forever` proves the ladder
stays exhausted for every attempt count beyond the boundary, not just the
one checked by hand.

## `convert_currency`: a real 100x bug for any currency pair with different subunit exponents

Scouted `repositories/customer_balance.rs`'s `convert_currency` (`:16-42`,
used by `consolidate.rs`, checkout, and customer-balance operations
wherever an amount needs to move between currencies). It computes
`amount_cents * rate`, where `rate = to_rate / from_rate` is a plain
whole-unit-relative-to-USD market FX rate
(`domain/historical_rates.rs:15`, `f32`). Checked directly: this file never
calls `rusty_money::iso::find(currency).exponent` anywhere — a real,
confirmed omission, contrasted with `fees.rs`, `credit_notes.rs`, and every
other money-conversion site in the codebase, which all look up the
currency's exponent explicitly before scaling.

The correct conversion needs an extra `10^(toExponent - fromExponent)`
factor: convert `amount_cents` to whole `from_currency` units, apply the
market rate, then convert back to `to_currency` subunits. The real code
implicitly assumes this factor is `1` — true for USD/EUR/GBP/AUD (all
exponent 2, which is why this has stayed latent), silently wrong for any
pair where it isn't, e.g. converting to/from JPY (exponent 0) or a
3-decimal currency like KWD. `CurrencyConversion.lean`'s
`usd_to_jpy_exponent_mismatch_inflates_by_100x` proves a concrete witness:
converting $1.00 (100 USD cents) to JPY at 150 JPY/USD, the real formula
returns `15000` where the correct answer is `150` — exactly `10^(2-0)` too
large. Modeled as exact integer arithmetic; the `rust_decimal::Decimal`
rounding and `f32` rate-precision are separate, already-documented seams
(the exponent gap is structural and independent of either).

## `calculate_mrr` reports the ORIGINAL slot count for the life of the subscription

Scouted `calculate_mrr` (`services/subscriptions/utils.rs:82-116`) — the
shared MRR formula — and its dead-looking first line
(`let _mrr = total_cents / period_as_months;`, discarded, superseded two
lines later by a `Decimal`-based division; harmless vestigial code, not a
bug, not pursued further).

Its `Slot` arm (`:101-105`) uses `initial_slots` directly. Traced whether
that field is kept current: `apply_parameters`
(`subscription_components.rs:288-296`) is its ONLY mutator, and it's
docstring-scoped to subscription creation / plan-override
parameterization. `update_subscription_slots`
(`services/subscriptions/slots.rs:37-173`, the real mutation entrypoint for
slot count changes) was grepped directly for any write to the persisted
fee — none exists. It only appends to `slot_transactions`, an independent,
append-only ledger (`domain/slot_transactions.rs`) whose seed row copies
`initial_slots` in ONCE and is never read back by that name again.

**A correct, slot-aware replacement exists and is used in exactly one
place.** `plan_change.rs::calculate_components_mrr_with_slots`
(`:1695-1741`) queries
`SlotTransactionRow::fetch_by_subscription_id_and_unit_locked(..)
.current_active_slots` for `Slot` components — the right approach — but
every OTHER caller of MRR (`insert/process.rs:703,708`,
`amendment.rs:236,242,247,252,1082`, `billing_events.rs:550,821`,
`plan_change.rs:984` — 9 sites) calls the generic `calculate_mrr` directly.
At subscription creation `initial_slots` IS the live count, so
`insert/process.rs`'s call is fine; every call reached after a
subscription's FIRST slot-count change is not. This is the same "correct
check exists, not wired everywhere" shape as `SlotBounds.lean`'s finding,
but for a headline financial metric (MRR expansion/contraction
tracking, `BiMrrMovementLogRowNew`'s churn/expansion movement log) rather
than a validation guard — plausibly higher business impact.
`MrrSlotStaleness.lean`'s `stale_after_upgrade_witness` proves the
concrete divergence (a 5→10 slot upgrade: the generic formula still
reports the original 5-slot MRR).

**Confirmed NOT a customer-billing bug.** Checked
`invoice_lines/component.rs`'s own `Slot` arm (`:135-153`) — it calls
`self.fetch_slots(conn, invoice_date, unit, ..)`, a live lookup, not
`initial_slots`. Real invoices are computed correctly; the staleness is
confined to the internal MRR metric.

## `grace_period_pct` is documented, never implemented

Scouted `entitlements.rs` (feature-access decisions, untouched territory —
not billing/invoicing) after the MRR-staleness thread. `domain/entitlements.rs:41-46`'s
own doc comment states the intended semantics of `OverageBehavior::Block
{ grace_period_pct: Option<u32> }`: "requests are rejected once the limit
(plus optional `grace_period_pct`) is reached." The only function that
computes whether a metered entitlement is actually `enabled` from real
usage, `services/entitlements.rs::build_metered_entitlement` (`:317-337`):

```rust
let enabled = meta.enabled && meta.limit.is_none_or(|l| consumed < l);
```

never references `grace_period_pct` — it isn't even in scope at that point
in the function. Grepped every `OverageBehavior::Block` construction site
across the codebase (`repositories/entitlements.rs`, ~30 occurrences): all
pass `grace_period_pct: None`, except one — `services/entitlements.rs:527`'s
own test, `Some(10)`. Checked what that test exercises before assuming it
covered the gap: it calls `build_unavailable_metered_entitlement`, a
DIFFERENT function that takes `enabled: bool` as a direct parameter (the
"metric row deleted" preservation path, no usage arithmetic at all) — not
`build_metered_entitlement`, the one place the field would need to matter.
No test anywhere exercises `grace_period_pct` through the actual
enable/disable computation.

This is the cleanest instance this session of a documented feature with
zero effect: a customer configured for a 10% grace allowance would be
blocked the instant `consumed >= limit`, identically to no grace period at
all — the field round-trips through config/serialization/tests but never
reaches the decision that's supposed to use it.
`EntitlementGracePeriod.lean`'s `grace_window_witness` proves the concrete
divergence (limit 100, 10% grace, 105 consumed: real code blocks, the
documented behavior would still allow it).

## `FloatError.lean`'s bound also covers a second, real invoice-line call site

Scouted `invoice_lines/component.rs::prorate` (`:717-724`), the function
actually used when generating invoice line amounts. It computes
`(price_cents as f64 * proration_factor).round() as i64` — structurally
identical to the `(amount_cents as f64 * factor).round() as i64` shape
`FloatError.lean` already bounds against `proration.rs`'s subscription-
lifecycle proration sites. `FloatError.lean`'s bound is stated generically
over any magnitude/precision, not tied to `proration.rs`'s own variable
names, so this is not a new proof — it's a second confirmed real call site
for the existing one, the actual invoice-line-generation path rather than
the subscription-lifecycle proration calculations the file was originally
written against.

## The exponent-omission bug recurs at four more sites, one of them customer-facing

Grepped for the same shape (`Decimal::from_f32(rate)` multiplying/dividing
a stored subunit amount by a `HistoricalRate`-sourced whole-unit rate) to
check whether `convert_currency` is the only place carrying this defect.
It is not — the identical arithmetic (missing `10^(exponentDiff)`) recurs
at:

- `services/subscriptions/terminate.rs:220-225` and
  `repositories/invoices.rs:745-753`: `mrr_change_usd = mrr_delta /
  rate_decimal`, converting a churned/booked MRR delta (`net_mrr_change:
  i64`, subunit convention confirmed via `diesel-models/src/bi.rs:54,70`)
  into USD for the `bi_delta_mrr_daily` dashboard table. Internal reporting
  only — wrong dashboard numbers for any non-USD-exponent-2 subscription
  currency, not a customer-facing money movement.
- `services/subscriptions/utils.rs:535-548`: **customer-facing.**
  `fixed_amount * Decimal::from_f32(rate)`, converting a coupon's
  fixed-amount discount from the coupon's own currency into
  `subscription_currency` via `store.get_historical_rate` — which resolves
  through the exact same `get_mapped_rates_for_currency`
  (`historical_rates.rs:121-136`) that produces `convert_currency`'s rate.
  A fixed-amount coupon issued in a currency with a different subunit
  exponent than the subscription it's applied to would be discounted by
  the wrong amount, by the same power-of-10 factor `CurrencyConversion.lean`
  proves for `convert_currency`.

Not independently reproven in Lean — the arithmetic is identical to
`convertCurrency`/`convertCurrencyScaled`, already proved once; re-deriving
the same fact four more times would be repetition, not new content. Listed
here because it changes the finding's scope: this isn't one call site with
a bug, it's one MISSING STEP (an exponent lookup) that several call sites
independently forgot, most likely because none of them are exercised by
the same-exponent currency pairs (USD/EUR/GBP/AUD) this codebase is
presumably tested against day to day.

## `amount_refunded`'s clamp: proved, not just traced, for all four write paths

`RefundInvariant.lean` had, since its own first version, ASSERTED (from
reading, not proving) that `reverse_transaction_tx`'s three branches clamp
`new_amount_refunded` to `[0, amount]`. Scouted the actual reversal/
reinstatement code (`repositories/payment_transactions.rs:283-555`) in
full, which turns out to be unusually well-documented by its own author —
already reasoning through a genuinely subtle edge case in a code comment
(`:333-343`: `amount_refunded` is written by both cumulative refund totals
AND dispute deltas, and whether a refund-after-dispute could get
"swallowed" by the `.max()` — concluded unreachable on Stripe because a
disputed charge can't be refunded via the API, so the two writers never
actually contend for the column). Formalized the FOUR real write paths —
`Cumulative`, `Full`, `Incremental` (`reverse_transaction_tx`) and the
reinstatement path (`reinstate_transaction_tx`, the only one that
decreases `amount_refunded`) — as `PaymentReversal.lean`, proving each
maps an in-range value to another in-range value. This is an inductive
invariant, not four independent one-shot checks: `Cumulative`'s
`.max(amount_refunded)` term specifically needs the PRIOR value already in
`[0, amount]` to conclude the new one is too — closing what
`RefundInvariant.lean` had left as a traced assertion, not a proof.

## Invoice/credit-note sequential numbering: correctly locked, unlike the DebtCancellation guard

Directly adjacent to the credit-note race: `invoicing_entity.next_invoice_number`
/`next_credit_note_number` are the sequential-numbering counters both
`finalize.rs` and `credit_notes.rs` allocate document numbers from. Same
general shape as the DebtCancellation bug (lock the row, read a field, use
it) — checked whether this one also discards its lock's fresh result.

It does not. All three allocation sites —
`finalize.rs:163-214` (invoice numbering), `credit_notes.rs:709-729`
(`finalize_credit_note_tx`), `credit_notes.rs:1051-1057,1186-1194`
(`create_credit_note_tx`, finalize-at-creation path) — bind the
`InvoicingEntityRow` from `select_for_update_by_id_and_tenant` (a real
`SELECT ... FOR NO KEY UPDATE`) to a single local once, then use that SAME
binding's `next_invoice_number`/`next_credit_note_number` both for the
number embedded in the document AND as the argument to
`update_invoicing_entity_number`/`update_credit_note_number` — never a
second, separately-fetched or pre-lock value. The lock is held for the
connection's transaction lifetime, so two concurrent finalizations against
the same invoicing entity serialize correctly: no duplicate document
numbers, matching the credit-note-number path's confirmed-correct pattern.
Not modeled in Lean (a locking-discipline / call-graph fact across three
call sites, not decidable arithmetic — same reasoning as the dunning
concurrency check above) — recorded as a traced, confirmed-safe design.

## `TaxRounding.lean`'s rounding rule is the codebase's canonical money-rounding primitive

Scouting `fees.rs`'s `compute_usage_price` (`:218-253`, covers `PerUnit`,
`Package`, `Tiered`, `Volume` — `Package`'s `block_size` genuinely IS
honored here via `ceil(usage_units / block_size)`, a different, correctly-
implemented feature from the per-tier `block_size` bug already formalized
in `TierPricing.lean`) surfaced its final step: every branch's `Decimal`
result is converted to a subunit integer via
`ToSubunit::to_subunit_opt(precision)` (`common-utils/src/decimals.rs:9-14`),
which does `Decimal * 10^precision` then
`round_dp_with_strategy(0, MidpointAwayFromZero)` — **exactly** the rounding
strategy `TaxRounding.lean`'s `round_half_away_from_zero` already models
and proves. Grepping the whole codebase for `to_subunit_opt` finds ~30 call
sites: `fees.rs`, `proration.rs`, `discount.rs`, `credit_notes.rs`,
`slots.rs`, `component.rs`, `amendment.rs`, checkout, manual payments — this
one trait method is the single, universal money-to-subunit conversion, not
a tax-specific detail.

Because `rust_decimal::Decimal` is exact fixed-point (mantissa + scale, no
binary floating-point approximation — unlike the `f64` proration pipeline
`FloatError.lean` bounds), `to_subunit_opt` on an already-exact,
non-negative `Decimal` is losslessly `round_half_away_from_zero(mantissa *
10^precision, 10^scale)`. Added `matches_real_to_subunit_opt` to
`tax_rounding.rs`'s test module: it calls the REAL
`common_utils::decimals::ToSubunit::to_subunit_opt` directly (added as a
dev-dependency, `common-utils` + `rust_decimal`, both already
workspace-pinned) and cross-checks it against the proved
`round_half_away_from_zero`, over `Decimal::new(mantissa, scale)`
constructions — not a re-description of the real implementation, an actual
call into it. This retroactively closes the rounding-correctness question
for every one of those ~30 call sites simultaneously, for the case where
their input `Decimal` is itself exact. It says nothing new about inputs
that are NOT exact — the tax-rate `f64→Decimal` seam remains the separate,
already-documented open gap this file's module doc has always flagged.

## `applied_credits` vs `cancelled_sum`: closed, structurally disjoint (plus a bonus cross-file proof)

The other open question from the credit-note scope: could `applied_credits`
against the same invoice — but serialization only prevents dirty writes; it
does nothing for a guard whose input was captured before the wait and never
refreshed after it. Two concurrent `DebtCancellation` requests against the
same invoice each carry their own pre-lock `amount_due` snapshot from their
own outer read (step 1), taken before either queued on the lock. Confirmed
this is a real defect in the guard's data flow, not a claim about Postgres's
general MVCC behavior: `CreditNoteRace.lean` models the guard's decision
function exactly (`total <= amount_due`) and exhibits a concrete two-request
witness (`amount_due=1000`, two requests of `700` each) where both
individually pass yet their sum (`1400`) exceeds the invoice's actual
outstanding balance — proved by `decide`, packaged as an explicit
existential (`guard_gives_no_joint_bound`) rather than a false universal
claim that every input triggers it.

## `recompute_amount_due_from_settled_payments`: monotone and exact

The concrete invariant "migrations" surfaced. `InvoiceAmountDue.lean`
proves `new_amount_due = max(0, total - applied_credits - cancelled_sum -
settled_sum)` (`diesel-models/src/query/invoices.rs:663-732`) is
non-negative by construction, monotone in `settled_sum` (more net settled
payment never increases `amount_due` — the property a sign-flip bug, e.g.
crediting `amount_refunded` instead of debiting it, would break
immediately), and reaches exactly `0` iff settled payments cover the
remaining balance. Models the aggregation formula only, not the SQL row
filtering that produces its inputs, and not whether the `Refunded` status
transition and `amount_refunded` field are kept consistent elsewhere in the
codebase (an open, undischarged assumption, flagged not verified).

## Two more real bugs, from scoping `meteroid-store` further

**Slot/seat bounds: the check is correct, one mutation path skips it
entirely.** `SlotBounds.lean` proves `validate_slot_limits`
(`repositories/subscriptions/slots.rs:211-239`) itself is exactly the
intended `[min_slots, max_slots]` inclusive-range predicate (no off-by-one).
But grepping every call site in `services/subscriptions/slots.rs` finds
exactly two — `preview_slot_update` (`:668`) and
`complete_slot_upgrade_checkout` (`:807`). **`update_subscription_slots`
(`:37-173`) — the mutation entrypoint for `Optimistic` upgrades and every
downgrade — never calls it.** Sharper than `SubscriptionStatus.lean`'s "no
centralized guard exists": here the guard function exists and is correct,
it is simply not wired into one of its three real call sites. Documented
in the Lean file's module doc (a Rust call-graph fact, not something a pure
arithmetic theorem states) alongside a proof that the check function itself
would have caught the violation if called.

**Component matching: `.find()` on a non-unique key double-matches.**
`build_plan_change_preview` (`services/subscriptions/plan_change.rs:1534-1616`)
matches each target price component to a current one by `product_id`, not a
stable per-component id (`:1554-1558`), scanning the full current list
fresh for every target with nothing consumed between iterations.
`ComponentMatching.lean`'s `double_match_bug` constructs the exact failing
shape (two current components sharing a product, two targets wanting that
product): both targets match the SAME first current component — it gets
credited twice — while the second current component is matched by neither
and falls into `removed` even though a target for its product exists. This
isn't a mis-labeling bug, it's a real over-crediting bug on plan changes
where a product backs more than one price component.

## `plan_change.rs` scouted: two real bugs already formalized

Examined `services/subscriptions/plan_change.rs` (1744 lines, mid-cycle plan
changes: upgrades/downgrades, proration, MRR recalculation) end-to-end:

**Real bugs already formalized**:
1. **Component matching** (`build_plan_change_preview`, `build_component_mappings`,
   lines 1534-1532): `.find()` on non-unique `product_id` key can double-match,
   formalized in `ComponentMatching.lean`.
2. **MRR staleness** (line 984, add-on MRR calculation): uses stale `calculate_mrr`
   instead of slot-aware `calculate_components_mrr_with_slots`; formalized in
   `MrrSlotStaleness.lean`.

**Code flows traced, found correct**:
- **Proration calculations** (lines 323, 764): both call `calculate_proration`
  with correct matched/added/removed split, filtering OneTime components
  appropriately (subscription-lifecycle proration, not customer-facing per
  Proration.lean).
- **Component closure and insertion** (lines 824-906): matched components are
  closed on `change_date` and new ones inserted with `effective_from: change_date`
  in a single transaction (no gap or double-billing window). For slot components,
  `resolve_preview_slot_counts` (lines 1626-1687) correctly patches both current
  and new fees to actual counts from `slot_transactions`; slot transaction
  creation (lines 908-918) correctly only adds entries for **Added** components,
  not Matched (which already have ledger entries) or Removed.
- **Trial → Active transition** (lines 998-1066): free trials reset billing
  period (line 1011: `calculate_advance_period_range(change_date, ..., true, ...)`,
  `is_partial=true` for mid-period reset); paid trials keep billing period and
  just transition status. No off-by-one detected; period anchor set to
  `change_date.day()` is correct.
- **Component matching logic** in both `build_plan_change_preview` and
  `build_component_mappings` (lines 1554-1558, 1471-1475): identical structure,
  matching by `product_id`, marking matched ids in `HashSet`, removing unmatched
  — correctly implements the non-consuming scan that ComponentMatching.lean
  identified as the bug vector when multiple current components share a product_id.

No additional formal-verification findings in `plan_change.rs` beyond the two
already modeled.

## Checkout session expiry boundary condition bug

`CheckoutSession::is_expired()` (`domain/checkout_sessions.rs:81-84`) uses
`Utc::now() > expires_at` (strict inequality) to determine session expiry.
The standard semantic for "expires at time T" is that the session remains
valid during `[created_at, T)`, i.e., valid up to but not including T. This
requires the check `now >= expires_at` (inclusive). The strict inequality is
a boundary-condition bug: at exactly the expiration time T, the function
returns `false` (session not expired), allowing checkout completion at the
infinitesimal window exactly at T.

`CheckoutSessionExpiry.lean` formalizes this as a pure boolean logic error:
the `sessionNotExpiredBuggy` model (reflecting the real code with `<=` on
the integer-time model) diverges from `sessionNotExpiredCorrect` (the
intended `<` guard) exactly at the boundary time, nowhere else. Four concrete
`decide`-proved theorems show the bug exists, is narrow (only at T), and is
consistently denied by the corrected version.

`checkout_session_expiry.rs` provides the Rust companion with five unit tests:
the boundary-time divergence, pre-expiry agreement, post-expiry agreement,
offset iterations confirming the boundary-only property, and a real-world
scenario demonstrating the security implication (a session accepted exactly
at its expiration instant).

Not modeled: the practical exercise-ability of this boundary (depends on
system clock granularity and scheduling precision) or whether the bug leads
to a real compromise (requires the attacker to submit a checkout exactly at
the microsecond of expiration). The bug is real and decidable; the exploit
specificity is a deployment question, not a logical one.

## `convert_quote_to_subscription`: quote expiry validation is never performed

Scouted `services/quotes.rs` (quote-to-subscription conversion, scoped after all
subscription/invoicing/metering findings) and found a real validation gap.
`convert_quote_to_subscription` (`:21-61`) validates that a quote has
`status == Accepted` (`:36`) and hasn't already been converted (`:44`), but makes
NO check for `quote.expires_at` having passed.

Compare to the coupon-expiry check elsewhere in the codebase
(`services/subscriptions/utils.rs:378`):
```rust
if coupon.expires_at.is_some_and(|x| x <= now) {
    return Err(...);
}
```

A quote can be created with an `expires_at` timestamp, accepted before that
timestamp passes, then converted to a subscription arbitrarily long after expiry
— the real code applies zero validation. This violates expected semantics that
an expired quote should not be usable. Especially problematic because:
- Quotes are calculated at their creation time
- Pricing may change after expiry
- The subscription should use the current pricing if acceptance/conversion
  occurs after expiry, not the stale quoted pricing

**Further evidence this expiry should be enforced:** when `accept_quote`
(`:488-570`) is called, it unconditionally sets `expires_at: None`
(`repositories/quotes.rs:509`), suggesting the design intent was that
expiry should be validated **before** acceptance — yet `accept_quote` itself
never checks whether `expires_at` has already passed before clearing it.

The bug exists at TWO points:
1. `accept_quote` should reject if `quote.expires_at.is_some_and(|x| x <= now)`
2. `convert_quote_to_subscription` should also check the same condition

`QuoteExpiry.lean` models the real guard condition (`status == Accepted
&& !converted`, ignoring expiry entirely) against the intended guard
(`status == Accepted && !converted && !expired`). `expired_quote_conversion_bug`
exhibits a concrete witness by `decide`: a quote with `status == Accepted`,
`alreadyConverted == false`, `expired == true` is accepted by the real code
but correctly rejected by the intended code.

This is purely a control-flow missing-guard finding (not decidable arithmetic),
similar to the credit-note race and slot-bounds unmasking (traced, not proved).
Documented here in full rather than split across files since the bug is
contained within one module and its immediate dependencies.

## `scale_fee`: add-on quantity scaling (traced, found correct arithmetic + one display asymmetry)

`scale_fee` (`services/subscriptions/utils.rs:128-174`) is the canonical, single
call site for baking add-on quantity into a fee's monetary fields. The function
is used only in amendment.rs (`:1714,1796,1802,1836`) when building proration
changes for immediate amendments.

**Arithmetic correctness:** All fee variant arms are correct:
- `Rate { rate }`: Scales `rate` by quantity → `rate * q`; used by
  `component_advance_amount_cents`, which returns the scaled rate directly ✓
- `Recurring { rate, quantity, ... }`: Scales `rate` by quantity → `rate * q`;
  inner `quantity` unchanged; `component_advance_amount_cents` multiplies by
  inner quantity, giving `(rate * q) * inner_qty = rate * inner_qty * q` ✓
- `Capacity { rate, ... }`: Scales `rate` ✓
- `Slot { unit_rate, initial_slots, ... }`: Scales `initial_slots`, leaving
  `unit_rate` unchanged; `component_advance_amount_cents` multiplies them,
  giving `(initial_slots * q) * unit_rate = initial_slots * unit_rate * q` ✓
- `OneTime { rate, quantity }`: Scales inner `quantity` by add-on quantity →
  `quantity * q`; `rate` unchanged; `component_onetime_amount_cents` multiplies
  them ✓
- Boundary: All arms clamp quantity with `.max(0)`, preventing negative
  multipliers ✓

**Display asymmetry in proration:** When a OneTime fee (already scaled by
`scale_fee`) reaches `calculate_proration` (`:265-284`), it extracts the scaled
fee's `quantity` field directly for display (`:275`). For other fee types
(`:287-319`), display quantity comes from `AddedComponent::instance_quantity`
(`:301-303`), NOT from the fee itself. Because `scale_fee` "folds the multiplier
into ... rates, losing the count" (comment at `:63`), the OneTime case displays
the TOTAL scaled quantity (inner_qty × add-on_qty) instead of the add-on
instance count alone. This is a display bug, not arithmetic: the `amount_cents`
is correct (both paths compute the right total), but the invoice line's
`quantity` field shows `6` instead of `3` for an add-on with 3 instances and
inner quantity 2. The docstring for `AddedComponent::instance_quantity` (`:103-107`)
expects display to show "qty × unit_price" where qty is the instance count, not
the total. `ScaleFeeDisplayAsymmetry.lean` formalizes this via the Rust test
vectors.

**Confirmed NOT customer-facing in amounts:** Invoice line generation
(`invoice_lines/component.rs:79-104`) does NOT scale fees — it computes
`instance_quantity()` separately for each add-on and multiplies by the
per-unit fee. Proration display fields are annotated "for display ... The
amount stays the line total" — so the asymmetry affects user-facing UI strings
("3 × $20" vs "6 × $10") but not billing amounts. The actual charge is still
correct: `(rate * inner_qty * instance_qty * factor).round()`.

## Basis retrofit audit (2026-09-27): five files against LedgerFold and IntervalBasis

With the two basis modules live (`LedgerFold.lean`, `IntervalBasis.lean`) and
`PaymentReversal.lean` retrofitted as the pilot, audited the five candidate
files mentioned in earlier sections for genuine fits:

**`DunningSchedule.lean` — Does NOT fit either basis.** A lookup table on
`Nat` subtraction: pattern-match on `failedAttempts - 1` returning schedules
`[3, 5, 7] → none`. This is array indexing, not stream folding (LedgerFold) or
bounded-interval composition (IntervalBasis). Left as direct `decide` proofs.

**`CreditNoteRace.lean` — Does NOT fit either basis.** A race-condition witness
exhibiting a concurrent TOCTOU bug in a single guard `total ≤ amountDue`. Not a
stream fold, not a composition of clamping/max/min. The defect lies in the guard
never re-reading after acquiring a lock, a data-flow property, not interval
arithmetic. Left as `decide`-checked example values.

**`CurrencyConversion.lean` — Does NOT fit either basis.** FX-rate scaling
formulas: real (`amountCents * rate`) vs intended (`amountCents * rate * 10^toExp /
10^fromExp`). This is multiplication-by-ratio arithmetic with exponent-scaling,
not a ledger fold or a composition of clamping operations. Left as `omega` proofs.

**`SubscriptionStatus.lean` — Does NOT fit either basis.** Purely documentation:
a state-transition graph with no centralized guard function in the codebase to
formalize against. No Lean theorem here, only a traced design. Left as module doc.

**`EntitlementGracePeriod.lean` — Does NOT fit either basis.** Threshold-comparison
bug: real (`consumed < limit`) vs intended (`100 * consumed < limit * (100 + gracePct)`).
This is an inequality check with a grace window, not a stream fold or a combination of
clamp/max/min operations. Left as `omega` proofs.

**Conclusion:** None of the five files match either basis pattern. Forcing any of
these into a `LedgerFold` or `IntervalBasis` shape would require contriving a
"basis instance" that isn't real to the actual computation or domain semantics
(e.g. falsely claiming an inequality is "really" a clamped value). Honest audit
means leaving all five as is.

## Coverage so far

In order of finding: `Metering` dedup (no-op guard), `TierPricing` block_size
(non-dependence), `TierPricing` zero-tier subtraction underflow, `Proration`
asymmetry + unclamped aligned branch, `TaxRounding` MidpointAwayFromZero
(matched), `InvoiceAmountDue` monotone + exact, `DiscountConservation` (positive
result), `CouponThreshold` early break one subunit too early, `RefundInvariant`
(closed, positive result), `CreditNoteRace` (real defect: guard reads pre-lock
snapshot), `DunningSchedule` (correct, pinned), `CurrencyConversion` 100x
exponent bug, `MrrSlotStaleness` (internal metric staleness, not customer
invoice), `EntitlementGracePeriod` (documented never implemented),
`PaymentReversal` (clamped, correct), `InvoiceNumbering` (locked, correct),
`SlotBounds` (check correct, one path skips it), `ComponentMatching`
(double-match via product_id non-uniqueness), `CheckoutSessionExpiry` (boundary
off-by-one), `QuoteExpiry` (missing expiry validation), `ScaleFeeDisplayAsymmetry` (OneTime display only).
