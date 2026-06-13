---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Executor.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.356941+00:00
---

# proofs/lean/Semantos/Executor.lean

```lean
-- Semantos Plane — Executor Model
--
-- Models the execution loop from packages/cell-engine/src/executor.zig.
-- Key properties:
-- - No backward jumps (pc increments monotonically)
-- - Bounded execution (opcount ≤ opcountLimit)
-- - Linearity gate checks before each opcode when enforcement is enabled
--
-- The executor is modeled as a step function that advances the program
-- counter by one opcode per call. This makes termination proofs
-- straightforward: pc increases monotonically and opcount is bounded.

import Semantos.PDA
import Semantos.Linearity
import Semantos.Opcodes.Classify
import Semantos.Opcodes.Standard
import Semantos.Opcodes.Plexus
import Semantos.Opcodes.HostCall

namespace Semantos

open Opcodes

/-- Execution step result. Matches executor.zig StepResult (lines 15-20). -/
inductive StepResult where
  | continueExecution  -- 0: more opcodes to execute
  | doneTrue           -- 1: script succeeded (top of stack is truthy)
  | doneFalse          -- 2: script failed (stack empty or top falsy)
  | doneError          -- -1: error occurred
  deriving Repr, DecidableEq, BEq

/-- Executor state. Models executor.zig ExecutionContext (lines 59-96).
    Simplified: we model a single script (no unlock/lock phase distinction)
    since the phase transition is a sequential composition that doesn't
    affect K1-K5 proofs. -/
structure ExecutorState where
  pda : PDA
  script : List Opcode
  pc : Nat
  opcount : Nat
  opcountLimit : Nat
  linearityEnforced : Bool
  deriving Repr

/-- Executor error type. -/
inductive ExecutorError where
  | opcountExceeded
  | opcodeError (e : OpcodeError)
  | linearityViolation (e : LinearityError)
  deriving Repr, DecidableEq, BEq

/-- Check if execution is complete (pc past end of script). -/
def ExecutorState.isTerminal (state : ExecutorState) : Bool :=
  state.pc ≥ state.script.length || state.opcount ≥ state.opcountLimit

/-- Execute a single step of the executor.
    Models executor.zig executeOneOpcode (lines 243-345).

    Key invariants maintained:
    1. pc increments by at least 1 on each call (no backward jumps)
    2. opcount increments by 1 on each call
    3. If opcount ≥ opcountLimit, returns error immediately
    4. If linearityEnforced, checks linearity before executing -/
def ExecutorState.step (state : ExecutorState)
    (_hostFetch : Cell → Option Cell) :
    Except ExecutorError ExecutorState :=
  -- Check execution limit (executor.zig:245)
  if state.opcount ≥ state.opcountLimit then
    .error .opcountExceeded
  -- Check if script is complete
  else if h : state.pc ≥ state.script.length then
    .ok state  -- script complete, no more opcodes
  else
    let op := state.script[state.pc]'(by omega)
    let stackOp := classifyOp op
    -- Linearity gate (executor.zig:179, standard.zig:179)
    if state.linearityEnforced && stackOp != .consume && stackOp != .swap && stackOp != .inspect then
      -- Check if top-of-stack cell permits this operation
      match state.pda.speek with
      | .error _ =>
        -- Empty stack — allow the opcode to fail naturally
        .ok { state with
          pc := state.pc + 1
          opcount := state.opcount + 1 }
      | .ok topCell =>
        if ¬(linearityPermits topCell.header.linearity stackOp) then
          .error (.linearityViolation (linearityError topCell.header.linearity stackOp))
        else
          -- Linearity check passed — execute the opcode
          .ok { state with
            pc := state.pc + 1
            opcount := state.opcount + 1 }
    else
      -- No linearity check needed — execute the opcode
      .ok { state with
        pc := state.pc + 1
        opcount := state.opcount + 1 }

/-- Run the executor for up to n steps. Returns the final state. -/
def ExecutorState.run (state : ExecutorState)
    (hostFetch : Cell → Option Cell)  -- used by step
    (fuel : Nat) : ExecutorState :=
  match fuel with
  | 0 => state
  | n + 1 =>
    if state.isTerminal then state
    else
      match state.step hostFetch with
      | .error _ => state
      | .ok state' => state'.run hostFetch n

-- ══════════════════════════════════════════════════════════════════════
-- Key executor properties
-- ══════════════════════════════════════════════════════════════════════

/-- In every successful step where pc < script.length and opcount < opcountLimit,
    the resulting state has pc + 1 and opcount + 1. This is the key structural
    property of the executor: no backward jumps. -/
theorem ExecutorState.step_advances (state : ExecutorState)
    (hostFetch : Cell → Option Cell)
    (state' : ExecutorState)
    (h_step : state.step hostFetch = .ok state')
    (h_pc : state.pc < state.script.length)
    (h_ops : state.opcount < state.opcountLimit) :
    state'.pc = state.pc + 1 ∧ state'.opcount = state.opcount + 1 := by
  simp only [step] at h_step
  -- The first if (opcount ≥ opcountLimit) is false
  have : ¬(state.opcount ≥ state.opcountLimit) := by omega
  rw [if_neg this] at h_step
  -- The second if (pc ≥ script.length) is false — this is dite
  have : ¬(state.pc ≥ state.script.length) := by omega
  simp only [dite_false, this] at h_step
  -- Now h_step is about the linearity/opcode branch
  -- All ok-returning branches create state with pc+1, opcount+1
  -- Use split to case-analyze the remaining ifs
  split at h_step <;> (
    try (split at h_step)
    all_goals (
      try (split at h_step)
      all_goals (first | (injection h_step with h_step; subst h_step; exact ⟨rfl, rfl⟩) | (simp at h_step))
    )
  )

/-- PC monotonically increases: after a successful step, pc is strictly greater. -/
theorem ExecutorState.step_pc_increases (state : ExecutorState)
    (hostFetch : Cell → Option Cell)
    (state' : ExecutorState)
    (h_step : state.step hostFetch = .ok state')
    (h_pc : state.pc < state.script.length)
    (h_ops : state.opcount < state.opcountLimit) :
    state'.pc = state.pc + 1 :=
  (step_advances state hostFetch state' h_step h_pc h_ops).1

/-- Opcount monotonically increases: after a successful step, opcount increases by 1. -/
theorem ExecutorState.step_opcount_increases (state : ExecutorState)
    (hostFetch : Cell → Option Cell)
    (state' : ExecutorState)
    (h_step : state.step hostFetch = .ok state')
    (h_pc : state.pc < state.script.length)
    (h_ops : state.opcount < state.opcountLimit) :
    state'.opcount = state.opcount + 1 :=
  (step_advances state hostFetch state' h_step h_pc h_ops).2

/-- Step at opcount limit always returns error. -/
theorem ExecutorState.step_at_limit (state : ExecutorState)
    (hostFetch : Cell → Option Cell)
    (h : state.opcount ≥ state.opcountLimit) :
    state.step hostFetch = .error .opcountExceeded := by
  simp only [step]
  rw [if_pos h]

/-- Step is total: it always returns either Ok or Error (never diverges).
    This is structural — the function is defined by pattern matching
    with no recursion, so Lean's termination checker accepts it. -/
theorem ExecutorState.step_total (state : ExecutorState)
    (hostFetch : Cell → Option Cell) :
    (∃ s', state.step hostFetch = .ok s') ∨
    (∃ e, state.step hostFetch = .error e) := by
  simp only [step]
  split
  · exact Or.inr ⟨_, rfl⟩
  · split
    · exact Or.inl ⟨_, rfl⟩
    · split
      · split
        · exact Or.inl ⟨_, rfl⟩
        · split
          · exact Or.inr ⟨_, rfl⟩
          · exact Or.inl ⟨_, rfl⟩
      · exact Or.inl ⟨_, rfl⟩

end Semantos

```
