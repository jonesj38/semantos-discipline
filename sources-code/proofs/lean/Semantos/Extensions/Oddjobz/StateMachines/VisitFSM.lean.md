---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/VisitFSM.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.375673+00:00
---

# proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/VisitFSM.lean

```lean
-- Semantos Plane — D-O4: Visit FSM
--
-- Specialises K1 + K4 to the Visit FSM (a scheduled → in_progress →
-- completed | cancelled chain). Visit transitions are gateless at
-- the cell layer per §O4 — the dispatch cap is spent on the Job FSM
-- side; mark-done is a free operator action. So K2 collapses to
-- principal-mismatch only.
--
-- Reference:
--   docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4
--   extensions/oddjobz/src/state-machines/visit-fsm.ts
--   proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/Common.lean

import Semantos.Extensions.Oddjobz.StateMachines.Common

namespace Semantos.Extensions.Oddjobz.StateMachines.VisitFSM

open Semantos.Extensions.Oddjobz.StateMachines.Common

inductive VisitState where
  | scheduled
  | inProgress
  | completed
  | cancelled
  deriving Repr, DecidableEq, BEq

structure VisitTransition where
  from_ : VisitState
  to : VisitState
  principal : Principal
  deriving Repr, DecidableEq

def visitTransitions : List VisitTransition := [
  { from_ := .scheduled,  to := .inProgress, principal := .service  },
  { from_ := .scheduled,  to := .cancelled,  principal := .operator },
  { from_ := .inProgress, to := .completed,  principal := .operator },
  { from_ := .inProgress, to := .cancelled,  principal := .operator }
]

def findRow (f t : VisitState) : Option VisitTransition :=
  visitTransitions.find? (fun r => r.from_ == f ∧ r.to == t)

structure VisitTransitionInput where
  cellState : VisitState
  to : VisitState
  principal : Principal
  cellId : String
  consumed : ConsumedSet
  sideEffectThrows : Bool

structure VisitTransitionOutput where
  newState : VisitState
  consumed : ConsumedSet
  deriving Repr

def transition (input : VisitTransitionInput) : Result VisitTransitionOutput :=
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

def mkInput (cellState : VisitState) (to : VisitState) (cellId : String)
    (consumed : ConsumedSet := ConsumedSet.empty)
    (principal : Principal := .operator)
    (sideEffectThrows : Bool := false)
    : VisitTransitionInput :=
  { cellState := cellState, to := to, principal := principal,
    cellId := cellId, consumed := consumed,
    sideEffectThrows := sideEffectThrows }

-- Totality

theorem findRow_none_completed_to_scheduled :
    findRow .completed .scheduled = none := by decide

theorem findRow_none_scheduled_to_completed :
    findRow .scheduled .completed = none := by decide

theorem visit_fsm_transitions_total_scheduled_completed
    (input : VisitTransitionInput)
    (h_from : input.cellState = .scheduled) (h_to : input.to = .completed) :
    transition input = .error .invalidStateTransition := by
  unfold transition
  rw [h_from, h_to, findRow_none_scheduled_to_completed]

theorem visit_fsm_transitions_total_completed_scheduled
    (input : VisitTransitionInput)
    (h_from : input.cellState = .completed) (h_to : input.to = .scheduled) :
    transition input = .error .invalidStateTransition := by
  unfold transition
  rw [h_from, h_to, findRow_none_completed_to_scheduled]

-- K1

theorem visit_fsm_consumed_cell_rejected
    (cellId : String) :
    transition (mkInput .inProgress .completed cellId
                  (ConsumedSet.empty.add cellId)
                  .operator false)
      = .error .cellAlreadyConsumed := by
  unfold transition mkInput
  have h_row : findRow .inProgress .completed =
      some { from_ := .inProgress, to := .completed, principal := .operator } := by
    decide
  rw [h_row]
  rw [assertLinear_after_add_rejects ConsumedSet.empty cellId]

-- K4

theorem visit_fsm_failure_atomic
    (cellId : String) (consumed : ConsumedSet)
    (h_fresh : ¬ consumed.contains cellId) :
    transition (mkInput .scheduled .inProgress cellId consumed .service true)
      = .error .inducedIoFailure := by
  unfold transition mkInput
  have h_row : findRow .scheduled .inProgress =
      some { from_ := .scheduled, to := .inProgress, principal := .service } := by
    decide
  rw [h_row]
  rw [assertLinear_ok_of_fresh consumed cellId h_fresh]
  rfl

theorem visit_fsm_failure_atomic_retry_succeeds
    (cellId : String) (consumed : ConsumedSet)
    (h_fresh : ¬ consumed.contains cellId) :
    transition (mkInput .scheduled .inProgress cellId consumed .service false)
      = .ok { newState := .inProgress, consumed := consumed.add cellId } := by
  unfold transition mkInput
  have h_row : findRow .scheduled .inProgress =
      some { from_ := .scheduled, to := .inProgress, principal := .service } := by
    decide
  rw [h_row]
  rw [assertLinear_ok_of_fresh consumed cellId h_fresh]
  rfl

-- K2 — bad principal

theorem visit_fsm_bad_principal_rejected
    (cellId : String) (consumed : ConsumedSet)
    (h_fresh : ¬ consumed.contains cellId) :
    transition (mkInput .scheduled .inProgress cellId consumed .operator false)
      = .error .badSigningPrincipal := by
  unfold transition mkInput
  have h_row : findRow .scheduled .inProgress =
      some { from_ := .scheduled, to := .inProgress, principal := .service } := by
    decide
  rw [h_row]
  rw [assertLinear_ok_of_fresh consumed cellId h_fresh]
  rfl

end Semantos.Extensions.Oddjobz.StateMachines.VisitFSM

```
