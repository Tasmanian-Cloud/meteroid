# Bug index — meteroid formal verification

Every confirmed defect found by this effort, in one place. Each entry links to its
proof (a `[[core]]` row in `register.toml` and a theorem in `MeteroidVerify/*.lean`,
or — where the defect is a locking/call-graph/timing fact rather than decidable
arithmetic — a traced section of `RESEARCH.md`). "Positive results" (things checked
and found correct) are not listed here; see `RESEARCH.md` for those.

## Origin: 100% upstream `meteroid-oss`, 0% Ptyktos/Tasmanian-Cloud infra

Checked directly, not assumed: `git remote -v` shows `origin` is
`https://github.com/meteroid-oss/meteroid.git` — the real, public, open-source
project — and `tasmanian-cloud` is this fork.

```
git diff origin/main main -- . ':!proof' ':!crates/meteroid-proof-core' ':!crates/meteroid-pure-core'
```

returns exactly 10 files (`.gitignore`, `Cargo.lock`/`Cargo.toml`, `README.md`,
`scripts/proof-register.py`, five `vectors/*.json` files) — every one of them this
verification effort's own scaffolding, none of them application logic. Every bugged
file below is byte-identical between `origin/main` and this fork. **Every bug in this
index is a bug in upstream `meteroid-oss` itself** — reachable by any deployment of
the real project, not something Tasmanian Cloud's fork introduced or is uniquely
exposed to. None are in Ptyktos infrastructure (`syndesi`, `sangdb`, `hashtrinity`,
etc.) — this entire effort has been scoped to the `meteroid` billing engine, a
completely different codebase from the Ptyktos stack.

If a fix is ever written for any of these, it belongs in a PR against
`meteroid-oss/meteroid`, not a Tasmanian-Cloud-only patch — the fork carries none of
its own divergent application code to patch instead.

## Confirmed bugs

| # | Bug | File(s) | Severity / reachability | Proof |
|---|---|---|---|---|
| 1 | Usage-event dedup gap: no `RawEvent::key()` dedup anywhere in ingest; relies entirely on ClickHouse's async `ReplacingMergeTree` merge, and zero query SQL uses `FINAL` | `metering/src/ingest/common.rs:39-246` | Real — duplicate usage events can be double-counted in usage-based billing until ClickHouse's background merge completes; direct billing impact | `Metering.lean` (`sum_double_counts_duplicates`, `count_double_counts_duplicates`) |
| 2 | Tiered/volume pricing silently ignores `block_size` — the parameter is accepted but never read (a `// TODO block_size` in the real source acknowledges the gap) | `fees.rs:117-124,160-167,32,123,166` | Real — any tier/volume price component configured with a `block_size` bills as if it weren't set at all | `TierPricing.lean` (`tiered_price_ignores_block_size`) |
| 3 | Volume pricing's `next.first_unit - 1` is an unguarded `u64` subtraction (sibling `tiered_charges` uses `saturating_sub`) | `fees.rs:90` vs `:48` | Real — two tiers sharing `first_unit = 0` underflows; a debug-panic / release-mode-wrap hazard | `TierPricing.lean` (`duplicate_zero_tier_upper_bound_goes_negative`) |
| 4 | `component_proration_factor`'s ALIGNED branch (the common case) returns `base_factor` completely unclamped; the misaligned branch clamps to `[0,1]`. No caller validates the precondition before calling in — a latent vulnerability, confirmed concretely reachable by #15 below | `proration.rs:96-113,165-169` | Real, general — the aligned branch has no defense if any caller ever passes an out-of-range factor | `Proration.lean` (`aligned_branch_can_escape_unit_interval` vs `misaligned_branch_clamps_out_of_range_factor`) |
| 5 | 100%-off coupon never applies to a 1-subunit subtotal — check-before-apply threshold is `<=1`, should be `<=0` | `discount.rs:89-116` | Real — off-by-one at exactly the smallest nonzero subtotal | `CouponThreshold.lean` (`subtotal_one_never_discounted`) |
| 6 | Credit-note creation: the invoice row is locked (`SELECT ... FOR UPDATE`), but the fresh post-lock result is discarded — the `DebtCancellation` guard checks the stale pre-lock snapshot | `credit_notes.rs:618,676,785,789,1035-1038` | Real — two concurrent credit-note requests for the same invoice (an ordinary double-click/retry, no attacker needed) can jointly overshoot `amount_due`; the lock serializes nothing the guard actually reads | `CreditNoteRace.lean` (`both_debt_cancellations_pass_the_guard_but_jointly_overshoot`) |
| 7 | `convert_currency` never looks up either currency's subunit exponent — silently assumes both use the same number of decimal places | `customer_balance.rs` | Real, 100x error for any currency pair with mismatched exponents (e.g. USD↔JPY); latent for USD/EUR/GBP/AUD (all exponent 2, why it's stayed hidden). Recurs at 4 more sites: `terminate.rs`, `invoices.rs` (MRR-to-USD, internal only), and **`subscriptions/utils.rs`'s coupon currency conversion — customer-facing** | `CurrencyConversion.lean` (`usd_to_jpy_exponent_mismatch_inflates_by_100x`) |
| 8 | `calculate_mrr`'s `Slot` arm reads the frozen `initial_slots` field instead of the live `slot_transactions` ledger; a slot-aware replacement exists but is wired into only 1 of 10 real call sites | `subscriptions/utils.rs`, `plan_change.rs:1695-1741` | Real, but confirmed NOT to touch customer invoicing (`invoice_lines/component.rs` uses a live lookup) — the internal MRR expansion/contraction metric is wrong after any seat-count change, which is one of the most common SaaS actions there is | `MrrSlotStaleness.lean` (`stale_after_upgrade_witness`) |
| 9 | `grace_period_pct` on `OverageBehavior::Block` is documented in the domain type's own doc comment, but the entitlement enable/disable decision never reads it | `entitlements.rs` | Real code defect, confirmed currently DORMANT — the incoming-API mapping hardcodes `grace_period_pct: None`, so no customer can configure this today; zero live impact until both the API is wired and someone sets it | `EntitlementGracePeriod.lean` (`grace_window_witness`) |
| 10 | `validate_slot_limits` (the min/max slot-count guard) is itself correct, but `update_subscription_slots` — the mutation entrypoint for optimistic upgrades and every downgrade — never calls it | `repositories/subscriptions/slots.rs:37-173,211-239,668,807` | Real — a customer can downgrade below a plan's minimum slot count, or exceed its maximum, with zero validation, via the one call site that skips the (correct) check | `SlotBounds.lean` (documents the call-graph gap; `validSlotCount_iff` proves the check itself is correct) |
| 11 | Plan-change component matching uses `.find()` by `product_id` (not a stable per-component id) against the full current-component list, with nothing consumed between iterations | `plan_change.rs:1534-1616,1554-1558` | Real, over-crediting bug — when one product backs 2+ price components, both matching targets bind to the SAME first current component (double-credited), and the second current component is spuriously dropped into "removed" | `ComponentMatching.lean` (`double_match_bug`) |
| 12 | Checkout session expiry uses `now > expires_at` (strict) instead of `now >= expires_at` | `domain/checkout_sessions.rs:81-84` | Real, narrow — a genuine off-by-one, but the reachable window is one Postgres microsecond (`Timestamptz` precision) coinciding exactly with `now`'s nanosecond read; not something ordinary traffic hits by chance | `CheckoutSessionExpiry.lean` (`expiry_boundary_bug_concrete_witness`) |
| 13 | `convert_quote_to_subscription` never checks `quote.expires_at` at all before converting | `services/quotes.rs:21-61` | Real, the most trivially reachable finding in this index — zero special conditions, any quote accepted then converted after its own expiry timestamp triggers it every time, using stale pricing | `QuoteExpiry.lean` (`expired_quote_conversion_bug`) |
| 14 | Scaling a `OneTime` add-on fee's quantity bakes the total into the fee, and the proration line item displays that total instead of the separate `instance_quantity` field other fee types use | `subscriptions/utils.rs` (`scale_fee`), `proration.rs:275` | Real but cosmetic only — confirmed the actual charged amount is identical under both framings; a UI/invoice-line display bug, not a money bug | `ScaleFeeDisplayAsymmetry.lean` |
| 15 | **The concrete, reachable instance of #4.** Immediate amendments compute `effective_date = Utc::now()` with zero validation against the subscription's current billing period; the sibling `plan_change.rs` path has the exact guard amendment.rs lacks | `subscriptions/amendment.rs:1140-1149` vs `plan_change.rs:745-750` | Real, and financially serious if triggered — for an aligned component (the common case), an out-of-period effective date turns what should be a customer credit into an extra charge. Reachable when a subscription sits past its nominal period end before the periodic rollover job catches up | `AmendmentDateValidation.lean` (`amendment_scenario_aligned`: a $100 monthly component computes a $45 charge instead of a credit) |
| 16 | Historical FX-rate cache has a 5-minute TTL with no invalidation on write, plus `clear_historical_rates_cache()` — the function that exists specifically to invalidate it — is never called anywhere in the codebase | `repositories/historical_rates.rs` | Real, timing-dependent — a rate update can be shadowed by a stale cached value for up to 5 minutes across invoicing, termination MRR tracking, and BI dashboards. Not formalized in Lean (cache-timing isn't decidable arithmetic); traced and documented | `RESEARCH.md` § "Historical-rate caching" |
| 17 | Migration mode free trial: when a subscription with a free trial ends during the trial period, the computed `current_period_start` equals `effective_billing_start` (trial + start_date), but `current_period_end` equals the subscription's `end_date` (during trial), creating a backwards period where start > end | `subscriptions/insert/process.rs:344-349,373-388` | Real, specific to migration mode (`skip_past_invoices=true`) + free trial + end-during-trial; produces invalid subscription state with start date > end date. Reachable by any deployment that uses migration mode for backfill (e.g. past-dated free trial subscription ending mid-trial) | `TrialEndBeforeEffectiveBillingStart.lean` (`migration_free_trial_period_backwards`), `trial_end_before_effective_billing_start.rs` (bug witness: day 11 > day 5) |

## Severity, roughly ordered by real-world reach

**Reachable via completely ordinary use, no special timing or config needed:**
#13 (quote expiry), #8 (MRR staleness on any seat change), #11 (component double-match on any multi-component-per-product plan change), #10 (slot bounds bypass on any downgrade), #1 (usage dedup gap on any duplicate event delivery).

**Reachable under realistic but more specific conditions:**
#6 (credit-note race — needs concurrent requests), #15/#4 (amendment date — needs a subscription past its period-end rollover window), #7 (currency exponent — needs a non-2-decimal currency in the mix), #16 (rate cache — needs a rate update landing inside the 5-minute window), #2, #3, #5 (specific pricing configurations: `block_size` set, a zero `first_unit` tier, or a 1-subunit subtotal).

**Currently dormant (real code defect, confirmed no live path to trigger it today):**
#9 (`grace_period_pct` — the API layer doesn't expose it yet).

**Real but low-stakes:**
#14 (display-only, amounts are correct), #12 (a genuine off-by-one, but a microsecond-wide race window in practice).

## Not in this index

Findings that were investigated and found CORRECT (no bug) are documented in
`RESEARCH.md`, not here: `DiscountConservation`, `RefundInvariant`/`PaymentReversal`'s
clamp, `DunningSchedule`'s ladder arithmetic, invoice/credit-note sequential
numbering, `TaxRounding`'s `MidpointAwayFromZero` matching the real code,
`InvoiceAmountDue`'s monotonicity, `consolidate.rs`'s formula, invoice
void/cancellation guards, net-terms/due-date arithmetic, tax jurisdiction/rate
lookup, and webhook idempotency. Two candidate "third basis" unifications
(a shared shape across the currency/grace-period bugs, and a shared shape across
the three boundary-inequality bugs) were investigated and rejected — see
`RESEARCH.md`'s "Basis retrofit audit" sections for why.
