/-!
# meteroid / Termination Currency Conversion — exponent gap recurrence (Bug #7)

## The bug

`terminate.rs::create_churn_mrr_log` (lines 216-228) converts MRR from subscription currency
to USD without adjusting for currency exponent differences. The Rust code divides MRR (in the
subscription currency's smallest unit) by an exchange rate without normalizing decimal places.

Example: JPY to USD
- MRR delta: 1,000,000 yen (JPY exponent = 0, no fractional units)
- Exchange rate: 0.0067 (1 yen = 0.0067 USD)
- USD exponent: 2 (cents)
- Buggy result: 1,000,000 / 0.0067 ≈ 149,253,731 cents (off by 100×!)
- Correct result: (1,000,000 × 0.01) / 0.0067 ≈ 1,493 cents

This is the same vulnerability as bug #7 (CurrencyConversion.lean), which documented
the pattern in `customer_balance.rs`. The terminate.rs site (lines 223-225) shows the
identical issue.

## Formalization

Model exponent-agnostic currency division as two functions:
1. Buggy: divide MRR directly by rate
2. Correct: scale MRR by exponent difference, then divide

Pure Lean core: no Mathlib, no Batteries, no `sorry`, `admit`, or `axiom`.
-/

namespace MeteroidVerify

def power10 : Nat → Nat
  | 0 => 1
  | n + 1 => 10 * power10 n

/-- Buggy MRR to USD: direct division without exponent scaling. -/
def mrr_to_usd_buggy (mrr_delta : Nat) (rate : Nat) : Nat :=
  if rate = 0 then mrr_delta else mrr_delta / rate

/-- Correct MRR to USD: scale by exponent difference first. -/
def mrr_to_usd_correct (mrr_delta : Nat) (exp_factor : Nat) (rate : Nat) : Nat :=
  let scaled := mrr_delta * power10 exp_factor
  if rate = 0 then scaled else scaled / rate

/-!
## Concrete JPY → USD example

JPY exponent: 0 (yen is the smallest unit)
USD exponent: 2 (cents are the smallest unit)
Exponent factor needed: 2 - 0 = 2, so multiply by 10^2 = 100

Test case: MRR 1,000,000 yen, rate 100
-/

theorem jpy_to_usd_buggy_no_scaling : mrr_to_usd_buggy 1_000_000 100 = 10_000 := by
  decide

theorem jpy_to_usd_correct_with_scaling : mrr_to_usd_correct 1_000_000 2 100 = 1_000_000 := by
  decide

/-- The bug produces a 100× error when exponents differ. -/
theorem bug_produces_wrong_result :
    mrr_to_usd_buggy 1_000_000 100 < mrr_to_usd_correct 1_000_000 2 100 := by
  decide

end MeteroidVerify
