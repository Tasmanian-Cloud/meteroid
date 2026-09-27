/-!
# meteroid / CurrencyConversion — `convert_currency` never accounts for differing subunit exponents

`repositories/customer_balance.rs`'s `convert_currency` (`:16-42`) computes

```
rate = to_rate / from_rate            -- whole-unit market FX rate (historical_rates.rs:134)
converted = amount_cents * rate       -- (:40)
```

with `amount_cents` in `from_currency`'s subunits (e.g. USD cents).
`rate.rates : BTreeMap<String, f32>` (`domain/historical_rates.rs:15`) is a
standard whole-unit-relative-to-USD FX table (e.g. `{"EUR": 0.92, "JPY":
149.5, ...}`) — NOT pre-scaled for how many subunit decimal places each
currency uses. Nowhere in this file is `rusty_money::iso::find(currency)`
(or any other currency-exponent lookup) called — a real, checked omission,
contrasted with `fees.rs::compute_usage_price` and every other
money-conversion site in the codebase, which all look up `.exponent`
explicitly before scaling.

**The correct conversion** needs an extra factor of
`10^(toExponent - fromExponent)`: convert `amount_cents` to whole
`from_currency` units (`/ 10^fromExponent`), apply the market rate, then
convert back to `to_currency` subunits (`* 10^toExponent`). The real
formula implicitly assumes this factor is `1`, i.e. that
`fromExponent = toExponent` — true for same-decimal-count pairs like
USD/EUR/GBP/AUD (all exponent 2), silently wrong for any pair that isn't,
e.g. JPY (exponent 0) or a 3-decimal currency like KWD.

**This is not an isolated call site.** The identical missing-exponent-factor
shape recurs at `services/subscriptions/terminate.rs:220-225`,
`repositories/invoices.rs:745-753` (both MRR-to-USD dashboard reporting),
and — customer-facing — `services/subscriptions/utils.rs:535-548` (a
fixed-amount coupon converted into the subscription's billing currency).
All four resolve through the same `get_mapped_rates_for_currency`
(`historical_rates.rs:121-136`) rate and the same missing `10^(exponentDiff)`
factor this file proves for `convert_currency` (`RESEARCH.md`); not
independently modeled here since the arithmetic is identical, not merely
similar.

**What is modeled:** the two formulas as exact integer/rational arithmetic
— not `rust_decimal`'s own rounding (`.round()`, `:40`) or `f32`'s
approximation of the stored rate, both separate, already-documented-
elsewhere seams (`RESEARCH.md`). The missing-exponent-factor gap is
structural and exists independently of either rounding concern.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- The real formula (`customer_balance.rs:40`), exact-arithmetic version:
    no exponent factor at all. -/
def convertCurrency (amountCents rate : Int) : Int := amountCents * rate

/-- The correct formula: scale by `10^(toExponent - fromExponent)` to
    convert between the two currencies' subunit conventions. Stated with an
    explicit `Nat` power in the denominator/numerator via `Int` division to
    stay in exact integer arithmetic for the (extremely common) case where
    the scaling is exact, matching this file's witness below. -/
def convertCurrencyScaled (amountCents rate : Int) (fromExponent toExponent : Nat) : Int :=
  amountCents * rate * 10 ^ toExponent / 10 ^ fromExponent

/-- Same-exponent pairs (USD/EUR/GBP/AUD, all exponent 2): the real formula
    already IS the correct one there, since the missing factor is exactly
    `1` — this is why the bug has stayed latent, checked concretely rather
    than via a general nonzero-power lemma this pure-Lean-core setup
    doesn't have to hand. -/
theorem same_exponent_matches_at_2 (amountCents rate : Int) :
    convertCurrencyScaled amountCents rate 2 2 = convertCurrency amountCents rate := by
  unfold convertCurrencyScaled convertCurrency
  omega

/-- Concrete witness: converting $1.00 (100 USD cents, exponent 2) to JPY
    (exponent 0) at a rate of 150 JPY per USD. The correct result is 150
    (JPY has no subunits smaller than a whole yen, so "150" IS ¥150). The
    real formula returns 15000 — 100x too large, exactly `10^(2-0)`. -/
theorem usd_to_jpy_exponent_mismatch :
    convertCurrency 100 150 = 15000 ∧ convertCurrencyScaled 100 150 2 0 = 150 := by decide

end MeteroidVerify
