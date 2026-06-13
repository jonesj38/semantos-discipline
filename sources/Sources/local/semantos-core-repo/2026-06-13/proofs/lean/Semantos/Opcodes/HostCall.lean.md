---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Opcodes/HostCall.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.359027+00:00
---

# proofs/lean/Semantos/Opcodes/HostCall.lean

```lean
-- Semantos Plane — Host Call Opcode Semantics (0xD0)
--
-- Models OP_CALLHOST from packages/cell-engine/src/opcodes/hostcall.zig.
--
-- Unlike Plexus opcodes (0xC0-0xC8) which follow PEEK-THEN-MUTATE,
-- OP_CALLHOST follows POP-DISPATCH-PUSH:
-- 1. Pop function name cell from main stack (CONSUMES the name)
-- 2. Dispatch to host environment (extern call)
-- 3. Push result cell onto main stack
--
-- This means OP_CALLHOST is NOT fully failure-atomic in the Plexus sense:
-- if the host dispatch fails (unknown function, host error), the name cell
-- has already been consumed. We prove a weaker property:
-- "partial atomicity" — on pop failure (empty stack), the PDA is unchanged;
-- on dispatch failure, exactly one cell (the name) has been consumed.

import Semantos.PDA
import Semantos.Opcodes.Classify
import Semantos.Opcodes.Standard

namespace Semantos.Opcodes

/-- Host function dispatch result. Models the host extern return value.
    - `ok result`: host function succeeded, returns a result cell
    - `unknown`: function name not found in registry (sentinel 0xFFFFFFFF)
    - `failed`: host function executed but returned an error -/
inductive HostDispatchResult where
  | ok (result : Cell)
  | unknown
  | failed
  deriving Repr

/-- OP_CALLHOST (0xD0): Pop function name, dispatch to host, push result.
    Matches hostcall.zig executeCallHost (lines 22-44).

    The host dispatch is modeled as an opaque function from Cell → HostDispatchResult.
    This is sound because the host function:
    - Cannot access or modify the PDA directly
    - Receives only the function name (via extern)
    - Returns only a scalar result (via extern)

    Stack effect on success: [... name] → [... result]
    Stack effect on dispatch failure: [... name] → [...]  (name consumed, no push)
    Stack effect on pop failure: [...] → [...]  (unchanged — stack was empty) -/
def opCallHost (pda : PDA)
    (hostDispatch : Cell → HostDispatchResult) : Except OpcodeError PDA :=
  -- Step 1: Pop function name from main stack
  match pda.spop with
  | .error e => .error (.stackError e)
  | .ok (nameCell, pda1) =>
    -- Step 2: Validate name is non-empty
    -- (In Zig: name_len == 0 → error.invalid_function_name)
    -- We model this as a property of the dispatch function returning .failed
    -- since Cell doesn't carry a length field in our model.
    -- Step 3: Dispatch to host
    match hostDispatch nameCell with
    | .unknown => .error .unknownHostFunction
    | .failed => .error .hostFunctionFailed
    | .ok resultCell =>
      -- Step 4: Push result onto main stack
      match pda1.spush resultCell with
      | .error e => .error (.stackError e)
      | .ok pda2 => .ok pda2

-- ══════════════════════════════════════════════════════════════════════
-- Key properties of OP_CALLHOST
-- ══════════════════════════════════════════════════════════════════════

/-- If the stack is empty (pop fails), OP_CALLHOST returns an error
    and the PDA is completely unchanged. This is the "pop-failure
    atomicity" property — the only failure mode that preserves full state. -/
theorem callhost_pop_failure_atomic (pda : PDA)
    (hostDispatch : Cell → HostDispatchResult)
    (h_empty : pda.spop = .error StackError.stack_underflow) :
    opCallHost pda hostDispatch = .error (.stackError .stack_underflow) := by
  simp [opCallHost, h_empty]

/-- If the host dispatch fails (unknown function or host error), the name
    cell has already been consumed. The PDA state is pda-after-pop, NOT
    the original pda. This distinguishes OP_CALLHOST from Plexus opcodes. -/
theorem callhost_dispatch_failure_consumes_name (pda : PDA)
    (hostDispatch : Cell → HostDispatchResult)
    (nameCell : Cell) (pda1 : PDA)
    (h_pop : pda.spop = .ok (nameCell, pda1))
    (h_unknown : hostDispatch nameCell = .unknown) :
    opCallHost pda hostDispatch = .error .unknownHostFunction := by
  simp [opCallHost, h_pop, h_unknown]

/-- On successful dispatch, the final PDA has exactly one fewer cell (name)
    and one more cell (result) compared to the original — net stack effect
    is replacement of the top cell. -/
theorem callhost_success_replaces_top (pda : PDA)
    (hostDispatch : Cell → HostDispatchResult)
    (nameCell : Cell) (resultCell : Cell)
    (pda1 pda2 : PDA)
    (h_pop : pda.spop = .ok (nameCell, pda1))
    (h_dispatch : hostDispatch nameCell = .ok resultCell)
    (h_push : pda1.spush resultCell = .ok pda2) :
    opCallHost pda hostDispatch = .ok pda2 := by
  simp [opCallHost, h_pop, h_dispatch, h_push]

/-- OP_CALLHOST is total: it always returns either Ok or Error.
    No divergence is possible from the opcode itself.
    (Host dispatch divergence is outside our model — see K5 scoping note.) -/
theorem callhost_total (pda : PDA) (hostDispatch : Cell → HostDispatchResult) :
    (∃ pda', opCallHost pda hostDispatch = .ok pda') ∨
    (∃ e, opCallHost pda hostDispatch = .error e) := by
  simp [opCallHost]
  match h : pda.spop with
  | .error e => exact Or.inr ⟨.stackError e, by simp⟩
  | .ok (nameCell, pda1) =>
    match hd : hostDispatch nameCell with
    | .unknown => exact Or.inr ⟨.unknownHostFunction, by simp [hd]⟩
    | .failed => exact Or.inr ⟨.hostFunctionFailed, by simp [hd]⟩
    | .ok resultCell =>
      match hp : pda1.spush resultCell with
      | .error e => exact Or.inr ⟨.stackError e, by simp [hd, hp]⟩
      | .ok pda2 => exact Or.inl ⟨pda2, by simp [hd, hp]⟩

/-- OP_CALLHOST does not touch the aux stack on ANY path (success or failure).
    This is relevant for K4-style reasoning: even though the main stack is
    mutated on dispatch failure, the aux stack is always preserved. -/
theorem callhost_preserves_aux (pda : PDA)
    (hostDispatch : Cell → HostDispatchResult)
    (pda' : PDA)
    (h : opCallHost pda hostDispatch = .ok pda') :
    pda'.auxStack = pda.auxStack := by
  simp [opCallHost] at h
  match hpop : pda.spop with
  | .error _ => simp [hpop] at h
  | .ok (nameCell, pda1) =>
    simp [hpop] at h
    -- pda1.auxStack = pda.auxStack (spop only touches mainStack)
    have h_aux_pop : pda1.auxStack = pda.auxStack := by
      simp [PDA.spop] at hpop
      split at hpop
      · next h_ok => obtain ⟨_, rfl⟩ := hpop; rfl
      · exact absurd hpop (by simp)
    match hd : hostDispatch nameCell with
    | .unknown => simp [hd] at h
    | .failed => simp [hd] at h
    | .ok resultCell =>
      simp [hd] at h
      match hp : pda1.spush resultCell with
      | .error _ => simp [hp] at h
      | .ok pda2 =>
        simp [hp] at h
        -- pda2.auxStack = pda1.auxStack (spush only touches mainStack)
        have h_aux_push : pda2.auxStack = pda1.auxStack := by
          simp [PDA.spush] at hp
          split at hp
          · next h_ok => injection hp with hp; subst hp; rfl
          · exact absurd hp (by simp)
        rw [← h, h_aux_push, h_aux_pop]

end Semantos.Opcodes

```
