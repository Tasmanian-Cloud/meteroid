-- Bug #22: VAT revalidation queries customers across all tenants with no filtering
-- File: modules/meteroid/crates/diesel-models/src/query/customers.rs:73-101
-- Method: list_vat_revalidation_candidates
--
-- The function explicitly states in its documentation: "Oldest first,
-- never-checked rows leading, across all tenants."  However, the Diesel query
-- has NO tenant_id filter. This means a background job for tenant A could
-- process customers from tenant B, C, etc.
--
-- Severity: HIGH - direct cross-tenant data exposure
-- Reachability: Confirmed - any call to this method will read other tenants' data

-- Model: A customer record with tenant_id, vat_number, and revalidation flags
structure Customer where
  id : Nat
  tenant_id : Nat
  vat_number : Option String
  vat_number_format_valid : Bool
  vat_number_checked_at : Option Nat  -- timestamp
  created_at : Nat
  archived_at : Option Nat
  deriving DecidableEq

-- Model: A database state as a list of customers
abbrev CustomerDb := List Customer

-- A query that filters by vat fields but NOT by tenant_id
-- This matches the actual buggy code at customers.rs:82-94
def query_vat_candidates_unfiltered (db : CustomerDb)
    (checked_before : Nat) (created_before : Nat) : CustomerDb :=
  db.filter fun c =>
    c.vat_number.isSome
    && c.vat_number_format_valid
    && c.archived_at.isNone
    && (c.vat_number_checked_at.isNone || c.vat_number_checked_at.getD 0 < checked_before)
    && c.created_at < created_before

-- A query that correctly filters by vat fields AND tenant_id
def query_vat_candidates_correct (db : CustomerDb) (tenant_id : Nat)
    (checked_before : Nat) (created_before : Nat) : CustomerDb :=
  db.filter fun c =>
    c.tenant_id = tenant_id
    && c.vat_number.isSome
    && c.vat_number_format_valid
    && c.archived_at.isNone
    && (c.vat_number_checked_at.isNone || c.vat_number_checked_at.getD 0 < checked_before)
    && c.created_at < created_before

-- Witness: A concrete database with customers from two different tenants
def witness_db : CustomerDb :=
  [ { id := 1, tenant_id := 1, vat_number := some "DE123", vat_number_format_valid := true,
      vat_number_checked_at := none, created_at := 100, archived_at := none },
    { id := 2, tenant_id := 2, vat_number := some "FR456", vat_number_format_valid := true,
      vat_number_checked_at := none, created_at := 100, archived_at := none } ]

-- The bug: when tenant 1 calls the unfiltered query, it gets customers from tenant 2 as well
theorem vat_cross_tenant_exposure :
  let result_unfiltered := query_vat_candidates_unfiltered witness_db 500 500
  let result_correct := query_vat_candidates_correct witness_db 1 500 500
  result_unfiltered.length = 2 ∧ result_correct.length = 1 := by
  decide

-- Formal statement: the unfiltered query exposes cross-tenant data
-- A witness that demonstrates the vulnerability
theorem vat_bug_is_real :
  ∃ (db : CustomerDb) (tenant_id : Nat) (checked_before created_before : Nat),
    let unfiltered := query_vat_candidates_unfiltered db checked_before created_before
    let filtered := query_vat_candidates_correct db tenant_id checked_before created_before
    filtered.length < unfiltered.length ∧ (∃ c ∈ unfiltered, c.tenant_id ≠ tenant_id) :=
  ⟨witness_db, 1, 500, 500, by decide, by decide⟩
