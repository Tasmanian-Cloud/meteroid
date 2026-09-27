/-!
# meteroid / SubscriptionStatus — a documented, not fully proved, transition graph

Unlike `Metering.lean`/`TierPricing.lean`, this file does not prove a
theorem about a bug — it documents what direct reading of the real code
found, because there is no centralized guard to formalize a mismatch
against. `proof/PROOF.md`'s "Lean (native)" status requires a real proved
theorem; this file's status is honestly "documented" for that reason, not
upgraded to look stronger than it is.

`SubscriptionStatusEnum` (`meteroid-store/src/domain/enums.rs:312-324`, 11
states, verified by direct read):

```
PendingActivation  -- before trial
PendingCharge      -- after billing start date, while awaiting payment
TrialActive
Active
TrialExpired       -- trial ended on paid plan without payment method
Paused
Suspended          -- due to non-payment
Cancelled
Completed
Superseded         -- upgrade/downgrade
Errored            -- failed to process after max retries
```

**No centralized transition-guard function exists anywhere in
`meteroid-store`** — confirmed by reading every status-assignment call site,
not by grep-absence. The Postgres enum (`diesel_enums::SubscriptionStatusEnum`)
restricts the *value set* only; there is no `CHECK` constraint or trigger on
transition order. Enforcement, where it exists at all, is ad hoc per call
site:

- `services/subscriptions/insert/process.rs` sets the initial status on
  subscription creation (not transitioned FROM another status).
- `services/lifecycle/period_transitions.rs:344` — `→ TrialActive`
- `services/lifecycle/period_transitions.rs:393` — `→ Active` (free-plan path)
- `services/lifecycle/period_transitions.rs:434` — `→ TrialExpired`
  (on-checkout path)
- `services/lifecycle/period_transitions.rs:463` — `→ Active`
  (`renew_subscription`)
- `services/lifecycle/period_transitions.rs:478` — `→ Completed`
  (`end_subscription`)
- `services/lifecycle/billing_events.rs:218,811` —
  `terminate_subscription(..., Cancelled | Paused)`
- `services/orchestration/payment_transaction_settled.rs:167,182` —
  `TrialExpired → TrialActive | Active`

`Superseded` and `Errored` are declared in the enum but neither appears as an
assignment target in these five files — either set elsewhere (not yet
located) or currently dead states. This is a gap in this file's own
coverage, not a claim that they're unreachable.

**What would upgrade this file to a real theorem:** if a centralized
transition-guard function is ever added to `meteroid-store` (the natural fix
for the gap this file documents), the intended graph above could become a
Lean `inductive`/relation with a decidable `validTransition` predicate, and
`lake build` could then prove the guard function matches it — the same shape
as `TierPricing.lean`'s bug theorems, but confirming an invariant instead of
refuting one. Until that guard exists, there is nothing in the real code to
prove correct or incorrect; only what's observed above.
-/
