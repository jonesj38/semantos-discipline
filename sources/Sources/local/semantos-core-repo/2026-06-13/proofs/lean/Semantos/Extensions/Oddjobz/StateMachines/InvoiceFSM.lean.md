---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/InvoiceFSM.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.375974+00:00
---

# proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/InvoiceFSM.lean

```lean
-- Semantos Plane — D-O4: Invoice FSM
--
-- Specialises K1 + K4 to the Invoice FSM (a draft → sent →
-- {viewed, partial, paid, overdue, cancelled} chain). Like the
-- Quote and Visit FSMs, every Invoice transition is gateless at
-- the cell layer per §O4 — the `cap.oddjobz.invoice` spend lives
-- on the Job FSM's `completed → invoiced` row, which mints the
-- Invoice cell in `draft` state.
--
-- The §O4 K4 acceptance test grounds in this FSM's `sent → paid`
-- (and ancestor → paid) — an induced HTTP failure on the Stripe
-- webhook leaves the Invoice cell unchanged and a retry succeeds.
-- That is what `invoice_fsm_failure_atomic` + the
-- `invoice_fsm_failure_atomic_retry_succeeds` corollary prove.
--
-- Reference:
--   docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4
--   extensions/oddjobz/src/state-machines/invoice-fsm.ts
--   proofs/lean/Semantos/Theorems/FailureAtomicK4.lean

import Semantos.Extensions.Oddjobz.StateMachines.Common

namespace Semantos.Extensions.Oddjobz.StateMachines.InvoiceFSM

open Semantos.Extensions.Oddjobz.StateMachines.Common

inductive InvoiceState where
  | draft
  | sent
  | viewed
  | partial_
  | paid
  | overdue
  | cancelled
  deriving Repr, DecidableEq, BEq

structure InvoiceTransition where
  from_ : InvoiceState
  to : InvoiceState
  principal : Principal
  deriving Repr, DecidableEq

def invoiceTransitions : List InvoiceTransition := [
  { from_ := .draft,    to := .sent,      principal := .operator },
  { from_ := .draft,    to := .cancelled, principal := .operator },
  { from_ := .sent,     to := .viewed,    principal := .service  },
  { from_ := .sent,     to := .partial_,   principal := .service  },
  { from_ := .sent,     to := .paid,      principal := .service  },
  { from_ := .sent,     to := .overdue,   principal := .service  },
  { from_ := .sent,     to := .cancelled, principal := .operator },
  { from_ := .viewed,   to := .partial_,   principal := .service  },
  { from_ := .viewed,   to := .paid,      principal := .service  },
  { from_ := .viewed,   to := .overdue,   principal := .service  },
  { from_ := .viewed,   to := .cancelled, principal := .operator },
  { from_ := .partial_,  to := .paid,      principal := .service  },
  { from_ := .partial_,  to := .overdue,   principal := .service  },
  { from_ := .overdue,  to := .paid,      principal := .service  },
  { from_ := .overdue,  to := .partial_,   principal := .service  }
]

def findRow (f t : InvoiceState) : Option InvoiceTransition :=
  invoiceTransitions.find? (fun r => r.from_ == f ∧ r.to == t)

structure InvoiceTransitionInput where
  cellState : InvoiceState
  to : InvoiceState
  principal : Principal
  cellId : String
  consumed : ConsumedSet
  sideEffectThrows : Bool

structure InvoiceTransitionOutput where
  newState : InvoiceState
  consumed : ConsumedSet
  deriving Repr

def transition (input : InvoiceTransitionInput) : Result InvoiceTransitionOutput :=
  match findRow input.cellState input.to with
  | none => .error .invalidStateTransition
  | some row =>
    match assertLinear input.consumed input.cellId with
    | .error e => .error e
    | .ok _ =>
      if row.principal != input.principal then
        .error .badSigningPrincipal
      else if input.sideEffectThrows then
        .error .inducedIoFailure
      else
        .ok { newState := row.to, consumed := input.consumed.add input.cellId }

def mkInput (cellState : InvoiceState) (to : InvoiceState) (cellId : String)
    (consumed : ConsumedSet := ConsumedSet.empty)
    (principal : Principal := .operator)
    (sideEffectThrows : Bool := false)
    : InvoiceTransitionInput :=
  { cellState := cellState, to := to, principal := principal,
    cellId := cellId, consumed := consumed,
    sideEffectThrows := sideEffectThrows }

-- Totality

theorem findRow_none_paid_to_draft :
    findRow .paid .draft = none := by decide

theorem findRow_none_draft_to_paid :
    findRow .draft .paid = none := by decide

theorem findRow_none_cancelled_to_paid :
    findRow .cancelled .paid = none := by decide

theorem invoice_fsm_transitions_total_draft_paid
    (input : InvoiceTransitionInput)
    (h_from : input.cellState = .draft) (h_to : input.to = .paid) :
    transition input = .error .invalidStateTransition := by
  unfold transition
  rw [h_from, h_to, findRow_none_draft_to_paid]

theorem invoice_fsm_transitions_total_paid_draft
    (input : InvoiceTransitionInput)
    (h_from : input.cellState = .paid) (h_to : input.to = .draft) :
    transition input = .error .invalidStateTransition := by
  unfold transition
  rw [h_from, h_to, findRow_none_paid_to_draft]

-- K1 — second `sent → paid` on the same cell rejected

theorem invoice_fsm_consumed_cell_rejected
    (cellId : String) :
    transition (mkInput .sent .paid cellId
                  (ConsumedSet.empty.add cellId)
                  .service false)
      = .error .cellAlreadyConsumed := by
  unfold transition mkInput
  have h_row : findRow .sent .paid =
      some { from_ := .sent, to := .paid, principal := .service } := by
    decide
  rw [h_row]
  rw [assertLinear_after_add_rejects ConsumedSet.empty cellId]

-- K4 — `sent → paid` failure-atomic (the §O4 acceptance scenario)

theorem invoice_fsm_failure_atomic
    (cellId : String) (consumed : ConsumedSet)
    (h_fresh : ¬ consumed.contains cellId) :
    transition (mkInput .sent .paid cellId consumed .service true)
      = .error .inducedIoFailure := by
  unfold transition mkInput
  have h_row : findRow .sent .paid =
      some { from_ := .sent, to := .paid, principal := .service } := by
    decide
  rw [h_row]
  rw [assertLinear_ok_of_fresh consumed cellId h_fresh]
  rfl

theorem invoice_fsm_failure_atomic_retry_succeeds
    (cellId : String) (consumed : ConsumedSet)
    (h_fresh : ¬ consumed.contains cellId) :
    transition (mkInput .sent .paid cellId consumed .service false)
      = .ok { newState := .paid, consumed := consumed.add cellId } := by
  unfold transition mkInput
  have h_row : findRow .sent .paid =
      some { from_ := .sent, to := .paid, principal := .service } := by
    decide
  rw [h_row]
  rw [assertLinear_ok_of_fresh consumed cellId h_fresh]
  rfl

-- K2 — bad principal

theorem invoice_fsm_bad_principal_rejected
    (cellId : String) (consumed : ConsumedSet)
    (h_fresh : ¬ consumed.contains cellId) :
    transition (mkInput .sent .paid cellId consumed .operator false)
      = .error .badSigningPrincipal := by
  unfold transition mkInput
  have h_row : findRow .sent .paid =
      some { from_ := .sent, to := .paid, principal := .service } := by
    decide
  rw [h_row]
  rw [assertLinear_ok_of_fresh consumed cellId h_fresh]
  rfl

end Semantos.Extensions.Oddjobz.StateMachines.InvoiceFSM

```
