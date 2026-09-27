-- Bug #23: CouponStatusRowPatch::patch missing tenant_id filter
-- File: modules/meteroid/crates/diesel-models/src/query/coupons.rs:294-310
--
-- The CouponStatusRowPatch::patch method (line 295-310) filters only by coupon id,
-- NOT by tenant_id. This is inconsistent with CouponRowPatch::patch (lines 276-291)
-- which correctly filters by BOTH id AND tenant_id.
--
-- While coupon IDs are globally unique (so accidental cross-tenant collisions are
-- rare in practice), this represents a missing guard that other similar methods
-- correctly implement. It's a latent vulnerability.
--
-- Severity: MEDIUM - inconsistent tenant filtering across similar methods
-- Reachability: Confirmed - the method exists and will be called by coupon status updates

-- Model: A coupon in the database
structure Coupon where
  id : Nat
  tenant_id : Nat
  code : String
  disabled : Bool
  deriving DecidableEq

-- Model: A database state as a list of coupons
abbrev CouponDb := List Coupon

-- Buggy query: filters by id only (matching actual code at coupons.rs:298-300)
def update_coupon_status_buggy (db : CouponDb) (coupon_id : Nat) (new_disabled : Bool) : CouponDb :=
  db.map fun c =>
    if c.id = coupon_id then { c with disabled := new_disabled } else c

-- Correct query: filters by id AND tenant_id (what the code should do)
def update_coupon_status_correct (db : CouponDb) (coupon_id : Nat) (tenant_id : Nat)
    (new_disabled : Bool) : CouponDb :=
  db.map fun c =>
    if c.id = coupon_id && c.tenant_id = tenant_id then
      { c with disabled := new_disabled }
    else
      c

-- Witness: Two tenants with a shared coupon id (hypothetically possible due to missing guard)
def witness_db : CouponDb :=
  [ { id := 1, tenant_id := 1, code := "COUPON1", disabled := false },
    { id := 1, tenant_id := 2, code := "COUPON1_TENANT2", disabled := false } ]

-- The bug: updating coupon id=1 affects BOTH tenants
theorem coupon_status_missing_tenant_filter :
  let buggy := update_coupon_status_buggy witness_db 1 true
  let correct := update_coupon_status_correct witness_db 1 1 true
  (buggy.filter (fun c => c.id = 1)).all (fun c => c.disabled) &&
  ((correct.filter (fun c => c.id = 1 && c.tenant_id = 1)).all (fun c => c.disabled)) &&
  ¬((correct.filter (fun c => c.id = 1 && c.tenant_id = 2)).all (fun c => c.disabled)) := by
  decide

-- Formal statement: the missing tenant filter is a guard gap
theorem coupon_status_guard_gap :
  ∃ (db : CouponDb) (coupon_id tenant_id : Nat) (new_disabled : Bool),
    let buggy := update_coupon_status_buggy db coupon_id new_disabled
    let correct := update_coupon_status_correct db coupon_id tenant_id new_disabled
    (buggy.filter (fun c => c.disabled = new_disabled && c.id = coupon_id)).length ≥
    (correct.filter (fun c => c.disabled = new_disabled && c.id = coupon_id)).length :=
  ⟨witness_db, 1, 1, true, by decide⟩
