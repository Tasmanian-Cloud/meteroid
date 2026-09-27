/-!
# meteroid / EntitlementGracePeriod — `grace_period_pct` is documented, never implemented

`domain/entitlements.rs:41-46`'s own doc comment states the intended
semantics of `OverageBehavior::Block { grace_period_pct: Option<u32> }`:
"requests are rejected once the limit (plus optional `grace_period_pct`) is
reached." The only function that computes whether a metered entitlement is
`enabled` from actual usage, `services/entitlements.rs::build_metered_entitlement`
(`:317-337`):

```
let enabled = meta.enabled && meta.limit.is_none_or(|l| consumed < l);
```

never references `grace_period_pct` — the field simply isn't in scope at
that point in the function. Grepped every construction site of
`OverageBehavior::Block` across the codebase (`repositories/entitlements.rs`,
~30 occurrences): all pass `grace_period_pct: None`, so nothing today
configures a real value — except one, `services/entitlements.rs:527`'s own
test, `Some(10)`. Checked what that test actually exercises: it calls
`build_unavailable_metered_entitlement`, a DIFFERENT function that takes
`enabled: bool` as a direct parameter (no usage computation at all) — it
covers the "metric row deleted" preservation path, not the grace-period
arithmetic. `build_metered_entitlement`'s `enabled` decision — the one
place `grace_period_pct` would need to matter — has no test that ever sets
it to `Some(_)`.

**What is modeled:** the real formula (`enabled = consumed < limit`, grace
term absent) against the documented intended one (`enabled = consumed <
limit * (1 + grace_period_pct / 100)`), cross-multiplied by 100 to stay in
exact integer arithmetic. The two diverge for any `consumed` in the grace
window `[limit, limit * (1 + grace_period_pct/100))` — customers configured
for a grace allowance would be blocked immediately at the raw limit, with
no grace at all.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- The real formula (`entitlements.rs:320`): `gracePct` isn't even a
    parameter, because the real code never reads it. -/
def entitlementEnabledReal (consumed limit : Int) : Bool :=
  decide (consumed < limit)

/-- The documented intended formula (`domain/entitlements.rs:43-44`):
    `consumed < limit * (1 + gracePct/100)`, cross-multiplied by 100. -/
def entitlementEnabledIntended (consumed limit gracePct : Int) : Bool :=
  decide (100 * consumed < limit * (100 + gracePct))

/-- With no configured grace period (`gracePct = 0`, matching every real
    construction site today, all `None`), the two formulas agree — exactly
    why this has stayed latent: nothing in the current codebase actually
    sets `grace_period_pct`, so the missing term has never mattered yet. -/
theorem agrees_with_no_grace_period (consumed limit : Int) :
    entitlementEnabledIntended consumed limit 0 = entitlementEnabledReal consumed limit := by
  unfold entitlementEnabledIntended entitlementEnabledReal
  simp only [decide_eq_decide]
  omega

/-- Concrete witness: a $0/1000-unit limit, 10% configured grace (so the
    intended cutoff is 110, matching the doc comment), 105 consumed —
    squarely inside the grace window. The real code blocks immediately;
    the documented behavior would still allow it. -/
theorem grace_window_witness :
    entitlementEnabledReal 105 100 = false ∧
      entitlementEnabledIntended 105 100 10 = true := by decide

end MeteroidVerify
