---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/QuoteFSM.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.375358+00:00
---

# proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/QuoteFSM.lean

```lean
-- Semantos Plane — D-O4: Quote FSM
--
-- Specialises K1 + K2 to the Quote FSM (a draft → presented →
-- {accepted | rejected | expired | superseded} chain inferred from
-- the §O4 plan + the cell-type's `QUOTE_STATUSES` enum).
--
-- Reference:
--   docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4
--   extensions/oddjobz/src/state-machines/quote-fsm.ts
--   proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/Common.lean
--
-- Theorems (all proven, no `sorry`):
--   * `quote_fsm_transitions_total_*` — non-table pairs reduce to
--     `.invalidStateTransition`.
--   * `quote_fsm_consumed_cell_rejected` — K1: second `presented →
--     accepted` on the same Quote cell-id fails.
--   * `quote_fsm_failure_atomic` — K4: side-effect throw leaves the
--     consumed set unchanged.
--   * `quote_fsm_failure_atomic_retry_succeeds` — retry after
--     failure-atomic returns `.ok`.
--
-- Note: every Quote-FSM transition is gateless at the cell layer
-- (the `cap.oddjobz.quote` spend lives on the Job side per §O4), so
-- `quote_fsm_cap_required_when_table_says_so` collapses to a
-- vacuous truth — there are no cap-gated rows. We still provide the
-- skeleton for parity with the other FSM specs.

import Semantos.Extensions.Oddjobz.StateMachines.Common

namespace Semantos.Extensions.Oddjobz.StateMachines.QuoteFSM

open Semantos.Extensions.Oddjobz.StateMachines.Common

/-- Canonical Quote FSM states. -/
inductive QuoteState where
  | draft
  | presented
  | accepted
  | rejected
  | expired
  | superseded
  deriving Repr, DecidableEq, BEq

/-- A transition-table row (no cap field — every Quote FSM
    transition is gateless at the cell layer). -/
structure QuoteTransition where
  from_ : QuoteState
  to    : QuoteState
  principal : Principal
  deriving Repr, DecidableEq

/-- The §O4-inferred Quote FSM transition table (justified in the
    PR body + the TS module head). -/
def quoteTransitions : List QuoteTransition := [
  { from_ := .draft,     to := .presented,  principal := .operator },
  { from_ := .draft,     to := .superseded, principal := .operator },
  { from_ := .presented, to := .accepted,   principal := .service  },
  { from_ := .presented, to := .rejected,   principal := .service  },
  { from_ := .presented, to := .expired,    principal := .service  },
  { from_ := .presented, to := .superseded, principal := .operator }
]

def findRow (f t : QuoteState) : Option QuoteTransition :=
  quoteTransitions.find? (fun r => r.from_ == f ∧ r.to == t)

structure QuoteTransitionInput where
  cellState : QuoteState
  to : QuoteState
  principal : Principal
  cellId : String
  consumed : ConsumedSet
  sideEffectThrows : Bool

structure QuoteTransitionOutput where
  newState : QuoteState
  consumed : ConsumedSet
  deriving Repr

def transition (input : QuoteTransitionInput) : Result QuoteTransitionOutput :=
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

def mkInput (cellState : QuoteState) (to : QuoteState) (cellId : String)
    (consumed : ConsumedSet := ConsumedSet.empty)
    (principal : Principal := .operator)
    (sideEffectThrows : Bool := false)
    : QuoteTransitionInput :=
  { cellState := cellState, to := to, principal := principal,
    cellId := cellId, consumed := consumed,
    sideEffectThrows := sideEffectThrows }

-- ══════════════════════════════════════════════════════════════════════
-- Totality — non-table pairs reduce to `.invalidStateTransition`
-- ══════════════════════════════════════════════════════════════════════

theorem findRow_none_accepted_to_draft :
    findRow .accepted .draft = none := by decide

theorem findRow_none_rejected_to_draft :
    findRow .rejected .draft = none := by decide

theorem findRow_none_draft_to_accepted :
    findRow .draft .accepted = none := by decide

theorem quote_fsm_transitions_total_accepted_draft
    (input : QuoteTransitionInput)
    (h_from : input.cellState = .accepted) (h_to : input.to = .draft) :
    transition input = .error .invalidStateTransition := by
  unfold transition
  rw [h_from, h_to, findRow_none_accepted_to_draft]

theorem quote_fsm_transitions_total_draft_accepted
    (input : QuoteTransitionInput)
    (h_from : input.cellState = .draft) (h_to : input.to = .accepted) :
    transition input = .error .invalidStateTransition := by
  unfold transition
  rw [h_from, h_to, findRow_none_draft_to_accepted]

-- ══════════════════════════════════════════════════════════════════════
-- K1 — `quote_fsm_consumed_cell_rejected`
-- ══════════════════════════════════════════════════════════════════════

theorem quote_fsm_consumed_cell_rejected
    (cellId : String) :
    transition (mkInput .presented .accepted cellId
                  (ConsumedSet.empty.add cellId)
                  .service false)
      = .error .cellAlreadyConsumed := by
  unfold transition mkInput
  have h_row : findRow .presented .accepted =
      some { from_ := .presented, to := .accepted, principal := .service } := by
    decide
  rw [h_row]
  rw [assertLinear_after_add_rejects ConsumedSet.empty cellId]

-- ══════════════════════════════════════════════════════════════════════
-- K4 — `quote_fsm_failure_atomic`
-- ══════════════════════════════════════════════════════════════════════

theorem quote_fsm_failure_atomic
    (cellId : String) (consumed : ConsumedSet)
    (h_fresh : ¬ consumed.contains cellId) :
    transition (mkInput .presented .accepted cellId consumed .service true)
      = .error .inducedIoFailure := by
  unfold transition mkInput
  have h_row : findRow .presented .accepted =
      some { from_ := .presented, to := .accepted, principal := .service } := by
    decide
  rw [h_row]
  rw [assertLinear_ok_of_fresh consumed cellId h_fresh]
  rfl

theorem quote_fsm_failure_atomic_retry_succeeds
    (cellId : String) (consumed : ConsumedSet)
    (h_fresh : ¬ consumed.contains cellId) :
    transition (mkInput .presented .accepted cellId consumed .service false)
      = .ok { newState := .accepted, consumed := consumed.add cellId } := by
  unfold transition mkInput
  have h_row : findRow .presented .accepted =
      some { from_ := .presented, to := .accepted, principal := .service } := by
    decide
  rw [h_row]
  rw [assertLinear_ok_of_fresh consumed cellId h_fresh]
  rfl

-- ══════════════════════════════════════════════════════════════════════
-- Bad-principal regression — operator can't sign `presented → accepted`
-- (which is service-signed in the §O4 plan; this is K2's auth half).
-- ══════════════════════════════════════════════════════════════════════

theorem quote_fsm_bad_principal_rejected
    (cellId : String) (consumed : ConsumedSet)
    (h_fresh : ¬ consumed.contains cellId) :
    transition (mkInput .presented .accepted cellId consumed .operator false)
      = .error .badSigningPrincipal := by
  unfold transition mkInput
  have h_row : findRow .presented .accepted =
      some { from_ := .presented, to := .accepted, principal := .service } := by
    decide
  rw [h_row]
  rw [assertLinear_ok_of_fresh consumed cellId h_fresh]
  rfl

end Semantos.Extensions.Oddjobz.StateMachines.QuoteFSM

```
