---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/BoundedStack.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.358637+00:00
---

# proofs/lean/Semantos/BoundedStack.lean

```lean
-- Semantos Plane — Bounded Stack Model
--
-- Generic bounded LIFO stack used by the 2-PDA.
-- Models the stack operations from packages/cell-engine/src/pda.zig.

namespace Semantos

/-- Error types for stack operations.
    Matches PDAError in pda.zig:15-19. -/
inductive StackError where
  | stack_overflow
  | stack_underflow
  | execution_limit
  deriving Repr, DecidableEq, BEq

/-- A bounded LIFO stack. Items are stored in a list where the head is
    the top of the stack. The depth invariant ensures the stack never
    exceeds maxDepth elements.

    Models the main_stack/aux_stack arrays from pda.zig:23-29. -/
structure BoundedStack (α : Type) (maxDepth : Nat) where
  items : List α
  depth_invariant : items.length ≤ maxDepth
  deriving Repr

variable {α : Type} {maxDepth : Nat}

/-- Create an empty bounded stack. -/
def BoundedStack.empty (α : Type) (maxDepth : Nat) : BoundedStack α maxDepth :=
  ⟨[], Nat.zero_le maxDepth⟩

/-- Stack depth (number of elements). Matches pda.zig sdepth(). -/
def BoundedStack.depth (s : BoundedStack α maxDepth) : Nat :=
  s.items.length

/-- Push an element onto the stack. Returns stack_overflow if full.
    Matches pda.zig spush(): checks main_sp >= MAIN_STACK_DEPTH. -/
def BoundedStack.push (s : BoundedStack α maxDepth) (x : α) :
    Except StackError (BoundedStack α maxDepth) :=
  if h : s.items.length < maxDepth then
    .ok ⟨x :: s.items, by simp [List.length_cons]; omega⟩
  else
    .error .stack_overflow

/-- Pop the top element. Returns stack_underflow if empty.
    Matches pda.zig spop(): checks main_sp == 0. -/
def BoundedStack.pop (s : BoundedStack α maxDepth) :
    Except StackError (α × BoundedStack α maxDepth) :=
  match s.items, s.depth_invariant with
  | [], _ => .error .stack_underflow
  | x :: rest, h => .ok (x, ⟨rest, by simp [List.length_cons] at h; omega⟩)

/-- Peek at the top element without removing it. Returns stack_underflow if empty.
    Matches pda.zig speek(): checks main_sp == 0. -/
def BoundedStack.peek (s : BoundedStack α maxDepth) :
    Except StackError α :=
  match s.items with
  | [] => .error .stack_underflow
  | x :: _ => .ok x

/-- Peek at element at given depth (0 = top). Returns stack_underflow if depth ≥ stack size.
    Matches pda.zig speekAt(): checks depth >= main_sp. -/
def BoundedStack.peekAt (s : BoundedStack α maxDepth) (depth : Nat) :
    Except StackError α :=
  if h : depth < s.items.length then
    .ok (s.items.get ⟨depth, h⟩)
  else
    .error .stack_underflow

/-- Check if stack is empty. -/
def BoundedStack.isEmpty (s : BoundedStack α maxDepth) : Bool :=
  s.items.isEmpty

-- ══════════════════════════════════════════════════════════════════════
-- Basic stack properties
-- ══════════════════════════════════════════════════════════════════════

/-- Push to a full stack returns overflow error. -/
theorem BoundedStack.push_full_overflow (s : BoundedStack α maxDepth)
    (x : α) (h : s.items.length = maxDepth) :
    s.push x = .error .stack_overflow := by
  simp [push]
  omega

/-- Pop from an empty stack returns underflow error. -/
theorem BoundedStack.pop_empty_underflow :
    (BoundedStack.empty α maxDepth).pop = .error StackError.stack_underflow := by
  simp [pop, empty]

/-- Push then pop returns the original element and stack (LIFO). -/
theorem BoundedStack.push_pop_identity (s : BoundedStack α maxDepth)
    (x : α) (h : s.items.length < maxDepth) :
    ∃ (s' : BoundedStack α maxDepth),
      s.push x = .ok s' ∧
      s'.pop = .ok (x, s) := by
  refine ⟨⟨x :: s.items, by simp [List.length_cons]; omega⟩, ?_, ?_⟩
  · simp [push, h]
  · simp [pop]

/-- Push then peek returns the pushed element. -/
theorem BoundedStack.push_peek_identity (s : BoundedStack α maxDepth)
    (x : α) (h : s.items.length < maxDepth) :
    ∃ (s' : BoundedStack α maxDepth),
      s.push x = .ok s' ∧
      s'.peek = .ok x := by
  refine ⟨⟨x :: s.items, by simp [List.length_cons]; omega⟩, ?_, ?_⟩
  · simp [push, h]
  · simp [peek]

/-- Depth increases by 1 after push. -/
theorem BoundedStack.push_depth (s : BoundedStack α maxDepth)
    (x : α) (h : s.items.length < maxDepth) :
    ∃ (s' : BoundedStack α maxDepth),
      s.push x = .ok s' ∧ s'.depth = s.depth + 1 := by
  refine ⟨⟨x :: s.items, by simp [List.length_cons]; omega⟩, ?_, ?_⟩
  · simp [push, h]
  · simp [depth, List.length_cons]

end Semantos

```
