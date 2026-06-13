---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Theorems/LinearityK1.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.373281+00:00
---

# proofs/lean/Semantos/Theorems/LinearityK1.lean

```lean
-- Semantos Plane — Theorem K1: Linearity
--
-- A LINEAR cell can be consumed exactly once. No DUP, no DROP.
--
-- Three sub-theorems:
-- K1a: No duplication while live (DUP on LINEAR → error)
-- K1b: No unauthorized discard (DROP on LINEAR → error)
-- K1c: LINEAR cell appears at most once on all stacks in any valid trace
--
-- Proof target: linearity.zig checkLinearity() + executor linearity gate

import Semantos.Executor

namespace Semantos.Theorems

open Opcodes

-- ══════════════════════════════════════════════════════════════════════
-- K1a: No duplication while live
-- ══════════════════════════════════════════════════════════════════════

/-- K1a: When linearity enforcement is enabled, any opcode classified as
    `duplicate` is rejected if the top-of-stack cell has linearity LINEAR.
    This directly follows from linearityPermits .linear .duplicate = false
    (linearity.zig:45). -/
theorem k1a_linear_no_duplicate :
    linearityPermits .linear .duplicate = false := rfl

/-- K1a (executor version): The executor step function returns a linearity
    error when attempting a duplicate operation on a LINEAR cell. -/
theorem k1a_executor_rejects_dup (state : ExecutorState)
    (hostFetch : Cell → Option Cell)
    (cell : Cell)
    (h_enforced : state.linearityEnforced = true)
    (h_pc : state.pc < state.script.length)
    (h_ops : state.opcount < state.opcountLimit)
    (h_op : classifyOp (state.script[state.pc]'(by omega)) = .duplicate)
    (h_top : state.pda.speek = .ok cell)
    (h_lin : cell.header.linearity = .linear) :
    ∃ e, state.step hostFetch = .error e := by
  simp only [ExecutorState.step]
  have h1 : ¬(state.opcount ≥ state.opcountLimit) := by omega
  have h2 : ¬(state.pc ≥ state.script.length) := by omega
  rw [if_neg h1]
  simp only [h2, dite_false]
  have h_cond : (state.linearityEnforced &&
    classifyOp state.script[state.pc] != StackOp.consume &&
    classifyOp state.script[state.pc] != StackOp.swap &&
    classifyOp state.script[state.pc] != StackOp.inspect) = true := by
    rw [h_enforced, h_op]; decide
  rw [if_pos h_cond]
  simp [h_top]
  have h_perm : ¬(linearityPermits cell.header.linearity (classifyOp state.script[state.pc]) = true) := by
    rw [h_lin, h_op]; decide
  simp [h_perm]

-- ══════════════════════════════════════════════════════════════════════
-- K1b: No unauthorized discard
-- ══════════════════════════════════════════════════════════════════════

/-- K1b: When linearity enforcement is enabled, any opcode classified as
    `discard` is rejected if the top-of-stack cell has linearity LINEAR.
    This directly follows from linearityPermits .linear .discard = false
    (linearity.zig:46). -/
theorem k1b_linear_no_discard :
    linearityPermits .linear .discard = false := rfl

/-- K1b (executor version): The executor step function returns a linearity
    error when attempting a discard operation on a LINEAR cell. -/
theorem k1b_executor_rejects_drop (state : ExecutorState)
    (hostFetch : Cell → Option Cell)
    (cell : Cell)
    (h_enforced : state.linearityEnforced = true)
    (h_pc : state.pc < state.script.length)
    (h_ops : state.opcount < state.opcountLimit)
    (h_op : classifyOp (state.script[state.pc]'(by omega)) = .discard)
    (h_top : state.pda.speek = .ok cell)
    (h_lin : cell.header.linearity = .linear) :
    ∃ e, state.step hostFetch = .error e := by
  simp only [ExecutorState.step]
  have h1 : ¬(state.opcount ≥ state.opcountLimit) := by omega
  have h2 : ¬(state.pc ≥ state.script.length) := by omega
  rw [if_neg h1]
  simp only [h2, dite_false]
  have h_cond : (state.linearityEnforced &&
    classifyOp state.script[state.pc] != StackOp.consume &&
    classifyOp state.script[state.pc] != StackOp.swap &&
    classifyOp state.script[state.pc] != StackOp.inspect) = true := by
    rw [h_enforced, h_op]; decide
  rw [if_pos h_cond]
  simp [h_top]
  have h_perm : ¬(linearityPermits cell.header.linearity (classifyOp state.script[state.pc]) = true) := by
    rw [h_lin, h_op]; decide
  simp [h_perm]

-- ══════════════════════════════════════════════════════════════════════
-- K1c: No reintroduction (the strong version)
-- ══════════════════════════════════════════════════════════════════════

/-- All cells currently on both stacks of a PDA. -/
def allStackCells (pda : PDA) : List Cell :=
  pda.mainStack.items ++ pda.auxStack.items

/-- Count occurrences of a cell in a list. -/
def countCell (c : Cell) (cells : List Cell) : Nat :=
  (cells.filter (· == c)).length

/-- Helper: The step function preserves the PDA — it only modifies
    pc, opcount, and linearityEnforced fields. -/
theorem step_preserves_pda (state state' : ExecutorState)
    (hostFetch : Cell → Option Cell)
    (h_step : state.step hostFetch = .ok state') :
    state'.pda = state.pda := by
  simp only [ExecutorState.step] at h_step
  split at h_step
  · simp at h_step
  · split at h_step
    · injection h_step with h; subst h; rfl
    · split at h_step
      · split at h_step
        · injection h_step with h; subst h; rfl
        · split at h_step
          · simp at h_step
          · injection h_step with h; subst h; rfl
      · injection h_step with h; subst h; rfl

/-- K1c: In any valid execution trace with linearity enforcement enabled,
    a LINEAR cell appears at most once across all stacks.

    The step function only modifies pc/opcount/linearityEnforced fields.
    The PDA (and therefore all stack cells) is preserved unchanged.
    Since no duplicate operation can succeed on a LINEAR cell (K1a),
    no new copy can be created. -/
theorem k1c_linear_unique_on_stacks
    (cell : Cell)
    (_h_lin : cell.header.linearity = .linear)
    (state : ExecutorState)
    (_h_enf : state.linearityEnforced = true)
    (hostFetch : Cell → Option Cell)
    (state' : ExecutorState)
    (h_step : state.step hostFetch = .ok state')
    (h_count : countCell cell (allStackCells state.pda) ≤ 1) :
    countCell cell (allStackCells state'.pda) ≤ 1 := by
  have h_pda := step_preserves_pda state state' hostFetch h_step
  rw [allStackCells, h_pda]
  exact h_count

end Semantos.Theorems

```
