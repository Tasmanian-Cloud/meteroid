/-!
# meteroid / CheckoutPreviewMismatch — preview and billing validate against different data

Self-serve checkout (`services/edge.rs:2135-2432`) computes an amount TWICE, against
TWO different data sources, with no guard ensuring they agree:

1. **Preview** (`edge.rs:2158`): computes an invoice on a virtual (in-memory,
   not-yet-persisted) subscription, then validates the customer's confirmed amount
   against it with a 1-cent tolerance (`edge.rs:2220`,
   `|amount_preview - customer_confirmation| ≤ 1`).
2. **Subscribe** (`edge.rs:2273`): creates and persists the real subscription.
3. **Bill** (`services/invoices/bill.rs:120-123`): re-fetches FRESH subscription
   details from the database (components, applied coupons, customer balance — all
   reloaded, not reused from the preview step) and computes the invoice again
   (`services/invoices/draft.rs:137`), this time validating for an EXACT match
   (`bill.rs:219`, `amount_actual == customer_confirmation`, no tolerance).

**The gap:** between steps 1 and 3, nothing re-validates that the underlying data
(pricing, coupon state, customer balance) hasn't changed. If it has, the two
`compute_invoice` calls diverge — the customer confirmed one amount, and the
system computes (and either rejects, or would charge) a different one.

**What is modeled:** the two validation predicates exactly as they compare against
the customer's confirmed amount — a 1-cent-tolerance check at preview time and an
exact-match check at billing time — and that a divergent `actual_charge` can
simultaneously pass the first and fail the second. Not modeled: WHY the underlying
amounts diverge (that's the traced Rust call path above, a data-freshness fact, not
arithmetic) — only that the two validation gates disagree once they do.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/`native_decide`.
-/

namespace MeteroidVerify

/-- Preview's validation gate (`edge.rs:2220`): a 1-cent tolerance. -/
def previewValidationPasses (shown confirmed : Int) : Bool :=
  decide (Int.natAbs (shown - confirmed) ≤ 1)

/-- Billing's validation gate (`bill.rs:219`): exact match, no tolerance. -/
def billingValidationPasses (actual confirmed : Int) : Bool :=
  decide (actual = confirmed)

/-- Concrete witness: customer is shown $100.00 (10000 cents), confirms $100.00,
    but by billing time the underlying data has changed and the actual charge
    computes to $120.00 (12000 cents). -/
theorem bug_is_real :
    previewValidationPasses 10000 10000 = true ∧
      billingValidationPasses 12000 10000 = false := by
  constructor <;> decide

end MeteroidVerify
