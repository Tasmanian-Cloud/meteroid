/-!
# meteroid / ComponentMatching — `.find()` on a non-unique key double-matches

`build_plan_change_preview` (`services/subscriptions/plan_change.rs:1534-1616`)
matches each target price component to a current one by **`product_id`**,
not a stable per-component id: for every target,
`current_components.iter().find(|c| c.product_id == Some(target_pid))`
(`:1554-1558`) scans the FULL current list fresh and takes the first hit.
Nothing removes a matched current component from consideration before the
next target is processed.

**The real bug, verified by reading the loop directly, not inferred:** if
two current components share a `product_id` (plausible — e.g. a base seat
component and a seat-overage component both tied to one "Seats" product)
and two target components also reference that product, `.find()` returns
the SAME first current component for both targets. The first current
component is double-matched (appears in `matched` twice, crediting its old
fee twice); the second current component is never matched by anything and
falls into the `removed` loop (`:1599-1608`) even though a target for its
product exists — the plan change ends up over-crediting the customer,
not just mis-labeling components.

Pure Lean core: no Mathlib, no Batteries, no `sorry`/`admit`/`axiom`/
`native_decide`.
-/

namespace MeteroidVerify

/-- A component as `(id, productId)` — opaque ids, matching this session's
    convention for symbol-name-shaped values (the algebra doesn't care what
    a component or product id "means"). -/
abbrev Component := Nat × Nat

/-- `.find()`'s exact effect (`plan_change.rs:1554-1558`): the first current
    component (by list order) whose product matches, or none. -/
def findMatch (current : List Component) (targetProduct : Nat) : Option Nat :=
  (current.find? (fun c => c.2 == targetProduct)).map Prod.fst

/-- The real matching loop's structure (`:1551-1583`): for each target,
    independently search the FULL, unmodified current list — nothing
    consumed between iterations, which is the source of the bug. -/
def matchAll (current : List Component) (targets : List Component) : List (Nat × Option Nat) :=
  targets.map (fun t => (t.1, findMatch current t.2))

/-- Two current components (ids 100, 200) share product 1; two targets
    (ids 10, 20) both want product 1. -/
def exampleCurrent : List Component := [(100, 1), (200, 1)]
def exampleTargets : List Component := [(10, 1), (20, 1)]

/-- Both targets match the SAME current component (100) — current
    component 200 is matched by neither, even though a second target
    exists for its product. This is exactly what makes 100 get credited
    twice (once per matching target) while 200 is silently dropped to
    `removed`. -/
theorem double_match_bug :
    matchAll exampleCurrent exampleTargets = [(10, some 100), (20, some 100)] := by decide

/-- Confirms component 200 is unreachable by `findMatch` on this current
    list for ANY of the example targets — it is not that 200 was a worse
    match, it is structurally never considered once 100 exists earlier in
    the list. -/
theorem second_current_component_never_matched :
    ∀ t ∈ exampleTargets, findMatch exampleCurrent t.2 ≠ some 200 := by decide

end MeteroidVerify
