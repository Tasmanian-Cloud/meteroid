# Research log — meteroid formal verification

Working directly inside the vendored `meteroid` fork (per Clay's direction
2026-09-27) rather than a separate `<name>fold` companion repo — the proof
package (`proof/`) and its Rust companion crates
(`crates/meteroid-{pure,proof}-core`) live alongside the code they model.

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

The lock genuinely serializes concurrent `create_credit_note_tx` calls
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
