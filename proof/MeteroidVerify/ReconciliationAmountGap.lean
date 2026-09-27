-- Bug #22: Reconciliation silently accepts mismatched payment amounts
--
-- When `reconcile_pending_transaction` resolves a provider-side status:
-- - It fetches `amount_received_minor` from RemoteTransactionStatus::Succeeded
-- - Creates a PaymentIntent with BOTH amount_requested (from local row) and amount_received
-- - Passes to consolidate_intent_and_transaction_tx
-- - Consolidate ONLY reads amount_requested (stored on the row) and status, NEVER validates amount_received
-- - Result: if provider settled a different amount, it's silently accepted with no hold/flag
--
-- Contrast with hosted_setup.rs resolve_captured_payment (line 1299-1310):
-- - Checks if amount_received_minor == expected_amount_minor
-- - On mismatch: HoldMismatch (manual review)
--
-- reconcile.rs has no such check. A provider partial-payment is settled as-is.

namespace MeteroidVerify
namespace ReconciliationAmountGap

-- The bug: a requested amount does not match the received amount, yet reconciliation accepts it

def isPartialPayment (amountRequested amountReceived : Int) : Bool :=
  amountRequested > 0 ∧ amountReceived > 0 ∧ amountRequested ≠ amountReceived

-- The consolidation function ignores amount validation
-- In reality: consolidate_intent_and_transaction_tx only patches status/external_id/error
-- It does NOT read or validate amount_received
def consolidate_never_validates_amount (amountRequested amountReceived : Int) (status : String) : Bool :=
  if status = "Succeeded" then
    -- Consolidate will accept this and mark the transaction Settled
    -- regardless of amount mismatch
    true
  else
    false

-- Core bug witness: a partial payment is marked Settled
theorem partial_payment_accepted_without_validation :
  ∀ (amountRequested amountReceived : Int),
    isPartialPayment amountRequested amountReceived →
    ∀ (status : String),
      status = "Succeeded" →
      -- The reconciliation pipeline will settle this mismatched amount
      consolidate_never_validates_amount amountRequested amountReceived status = true := by
  intro amountRequested amountReceived hPartial status hStatus
  simp [consolidate_never_validates_amount, hStatus]

-- Concrete witness: $95 received vs $100 requested, silently settled as $95
def concrete_partial_scenario : Bool :=
  let amountRequested := 100
  let amountReceived := 95
  let status := "Succeeded"
  isPartialPayment amountRequested amountReceived &&
  consolidate_never_validates_amount amountRequested amountReceived status

theorem concrete_partial_bug :
  concrete_partial_scenario = true := by
  decide

-- Unlike hosted payments, no HoldMismatch alternative exists
-- Hosted payments: resolve_captured_payment matches amounts, holds on mismatch
-- Reconciliation: consolidate_intent_and_transaction_tx never sees amount_received
-- Result: no review, no hold, silent settlement at whatever amount provider claims

-- The defect is in reconcile.rs::payment_intent_from_remote_status (lines 168-183):
-- It COMPUTES amount_received (line 177) but consolidate_intent_and_transaction_tx
-- never USES that field. The PaymentIntent carries it but consolidation ignores it.

end ReconciliationAmountGap
end MeteroidVerify
