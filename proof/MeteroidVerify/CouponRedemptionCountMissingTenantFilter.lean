-- Bug #24: CouponRow::inc_redemption_count missing tenant_id filter
-- File: modules/meteroid/crates/diesel-models/src/query/coupons.rs:191-209
--
-- The inc_redemption_count method updates a coupon's redemption_count field
-- based on coupon_id alone, with NO tenant_id filter. This means:
--
-- 1. If a coupon ID were somehow shared across tenants (due to other missing guards),
--    incrementing redemption count for one tenant would affect all
--
-- 2. More critically, it's inconsistent with the pattern used elsewhere:
--    - CouponRowPatch::patch (line 276-291) filters by BOTH id AND tenant_id
--    - BankAccountRow methods all filter by tenant_id
--    - This missing filter is a gap in the consistency model
--
-- Severity: MEDIUM - potential cross-tenant mutation if id collisions occur
-- Reachability: Confirmed - method exists and increments redemption_count on every coupon use

-- Model: A coupon with tenant scope
structure Coupon where
  id : Nat
  tenant_id : Nat
  redemption_count : Int
  deriving DecidableEq

-- Model: Database state
abbrev CouponDb := List Coupon

-- Buggy increment: filters by id only (matches coupons.rs:198-200)
def inc_redemption_count_buggy (db : CouponDb) (coupon_id : Nat) (delta : Int) : CouponDb :=
  db.map fun c =>
    if c.id = coupon_id then { c with redemption_count := c.redemption_count + delta } else c

-- Correct increment: filters by id AND tenant_id (what it should do)
def inc_redemption_count_correct (db : CouponDb) (coupon_id : Nat) (tenant_id : Nat)
    (delta : Int) : CouponDb :=
  db.map fun c =>
    if c.id = coupon_id && c.tenant_id = tenant_id then
      { c with redemption_count := c.redemption_count + delta }
    else
      c

-- Witness: Two tenants sharing a coupon ID (hypothetical, due to missing tenant filter)
def witness_db : CouponDb :=
  [ { id := 100, tenant_id := 1, redemption_count := 0 },
    { id := 100, tenant_id := 2, redemption_count := 0 } ]

-- The bug: incrementing coupon 100 increments BOTH tenants' versions
theorem inc_redemption_count_missing_tenant_filter :
  let buggy := inc_redemption_count_buggy witness_db 100 1
  let correct := inc_redemption_count_correct witness_db 100 1 1
  (buggy.filter (fun c => c.id = 100)).all (fun c => c.redemption_count = 1) &&
  (buggy.filter (fun c => c.id = 100)).length = 2 &&
  (correct.filter (fun c => c.id = 100 && c.tenant_id = 1)).all (fun c => c.redemption_count = 1) &&
  (correct.filter (fun c => c.id = 100 && c.tenant_id = 2)).all (fun c => c.redemption_count = 0) := by
  decide

-- Formal statement: the bug affects all instances of a coupon ID
theorem redemption_count_unscoped_increment :
  ∃ (db : CouponDb) (coupon_id tenant_id : Nat) (delta : Int),
    let buggy := inc_redemption_count_buggy db coupon_id delta
    let correct := inc_redemption_count_correct db coupon_id tenant_id delta
    let buggy_count := (buggy.filter (fun c => c.id = coupon_id)).length
    let correct_count := (correct.filter (fun c => c.id = coupon_id && c.tenant_id = tenant_id)).length
    buggy_count ≥ correct_count ∧ 1 ≤ buggy_count :=
  ⟨witness_db, 100, 1, 1, by decide⟩
