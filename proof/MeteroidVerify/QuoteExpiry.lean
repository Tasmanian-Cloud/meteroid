/-!
# meteroid / QuoteExpiry — quote-to-subscription conversion skips expiry validation

`services/quotes.rs::convert_quote_to_subscription` (`:21-61`) validates that
a quote has `status == Accepted` (`:36`) and hasn't already been converted
(`:44`), but does NOT validate that the quote's `expires_at` hasn't passed.

Compare to the coupon-expiry check at `services/subscriptions/utils.rs:378`:
```rust
if coupon.expires_at.is_some_and(|x| x <= now) {
    return Err(...);
}
```

A quote can be created with an expiry date (`:47` in `domain/quotes.rs`),
accepted before expiration (accepted_at recorded at `repositories/quotes.rs:506`),
then converted to a subscription arbitrarily long after its expiry — the real
code makes no check. This violates the expected semantics that an expired quote
should not be usable for creating a live subscription, especially since the quote
was calculated at creation time and pricing may have changed.

Further evidence the expiry is *meant* to be enforced: when a quote is accepted,
`expires_at` is set to `None` (`repositories/quotes.rs:509`), suggesting the design
intent is that expiry should be checked *before* acceptance — yet no such check
exists. A customer can simply not accept the quote until after its expiry, then
accept and convert it.

**What is modeled:** the real guard condition (`status == Accepted &&
!converted && expires_at.is_none()` — the last part is implicit because once a
quote is accepted, expires_at becomes None in the current codebase, but this
happens WITHOUT checking that it hadn't already expired) against the intended
guard (`status == Accepted && !converted && (expires_at.is_none() || expires_at >
now)`), cross-mapped to a simpler boolean model where a quote is either
`expired` or `notExpired`.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- Real guard in `convert_quote_to_subscription` (`:21-61`): checks status
    and whether already converted, but NOT expiry. Model as: accepted &&
    !converted (ignoring expiry entirely). -/
def quoteConversionGuardReal (status : String) (alreadyConverted : Bool) : Bool :=
  status == "Accepted" && !alreadyConverted

/-- Intended guard: should also reject if the quote is expired. -/
def quoteConversionGuardIntended (status : String) (alreadyConverted : Bool) (expired : Bool) : Bool :=
  status == "Accepted" && !alreadyConverted && !expired

/-- When a quote is not expired, both guards agree (the bug stays latent). -/
theorem agrees_when_not_expired (status : String) (alreadyConverted : Bool) :
    quoteConversionGuardIntended status alreadyConverted false =
      (quoteConversionGuardReal status alreadyConverted && true) := by
  unfold quoteConversionGuardIntended quoteConversionGuardReal
  simp

/-- Concrete witness: a quote with status "Accepted", never converted
    (alreadyConverted = false), but expired (expired = true). The real code
    allows conversion; the intended code rejects it. -/
theorem expired_quote_conversion_bug :
    quoteConversionGuardReal "Accepted" false = true ∧
      quoteConversionGuardIntended "Accepted" false true = false := by
  decide

end MeteroidVerify
