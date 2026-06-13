---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Linearity.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.357794+00:00
---

# proofs/lean/Semantos/Linearity.lean

```lean
-- Semantos Plane — Linearity Model
--
-- Models the linearity enforcement rules from
-- packages/cell-engine/src/linearity.zig.
--
-- The permission table is a direct transliteration of the Zig
-- checkLinearity function (linearity.zig:42-58). Every row must match.

import Semantos.Cell

namespace Semantos

/-- Categories of stack operations for linearity checking.
    Matches LinearityOperation enum in linearity.zig:18-24. -/
inductive StackOp where
  | duplicate  -- DUP, OVER, PICK, 2DUP, 3DUP
  | discard    -- DROP, 2DROP, NIP
  | consume    -- Normal read-and-use (CHECKSIG, etc.)
  | swap       -- SWAP, ROT (reorder, no copy/destroy)
  | inspect    -- SPEEK, SIZE, DEPTH (read-only)
  deriving Repr, DecidableEq, BEq

/-- Linearity error types matching linearity.zig:26-38. -/
inductive LinearityError where
  | cannot_duplicate_linear
  | cannot_discard_linear
  | cannot_duplicate_affine
  | cannot_discard_relevant
  | invalid_linearity_type
  | linearity_check_failed
  | domain_flag_mismatch
  | type_hash_mismatch
  | owner_id_mismatch
  | capability_type_mismatch
  | cell_too_short
  deriving Repr, DecidableEq, BEq

/-- Check if a linearity type permits a given operation.
    Direct transliteration of checkLinearity in linearity.zig:42-58.

    Permission table (matches Zig source exactly):
    ┌──────────┬───────────┬─────────┬─────────┬──────┬─────────┐
    │ Type     │ duplicate │ discard │ consume │ swap │ inspect │
    ├──────────┼───────────┼─────────┼─────────┼──────┼─────────┤
    │ LINEAR   │ false     │ false   │ true    │ true │ true    │
    │ AFFINE   │ false     │ true    │ true    │ true │ true    │
    │ RELEVANT │ true      │ false   │ true    │ true │ true    │
    │ DEBUG    │ true      │ true    │ true    │ true │ true    │
    └──────────┴───────────┴─────────┴─────────┴──────┴─────────┘ -/
def linearityPermits (l : Linearity) (op : StackOp) : Bool :=
  match l, op with
  | .linear,   .duplicate => false  -- linearity.zig:45: error.cannot_duplicate_linear
  | .linear,   .discard   => false  -- linearity.zig:46: error.cannot_discard_linear
  | .affine,   .duplicate => false  -- linearity.zig:50: error.cannot_duplicate_affine
  | .relevant, .discard   => false  -- linearity.zig:53: error.cannot_discard_relevant
  | _,         _          => true   -- all other combinations allowed

/-- Get the specific error for a linearity violation.
    Matches the error returns in linearity.zig:42-58. -/
def linearityError (l : Linearity) (op : StackOp) : LinearityError :=
  match l, op with
  | .linear,   .duplicate => .cannot_duplicate_linear
  | .linear,   .discard   => .cannot_discard_linear
  | .affine,   .duplicate => .cannot_duplicate_affine
  | .relevant, .discard   => .cannot_discard_relevant
  | _,         _          => .linearity_check_failed  -- should not be reached

-- ══════════════════════════════════════════════════════════════════════
-- Exhaustive unit lemmas — one for each cell in the 4×5 permission table.
-- These serve as cross-checks against the Zig source.
-- ══════════════════════════════════════════════════════════════════════

-- LINEAR row
theorem linear_no_duplicate : linearityPermits .linear .duplicate = false := rfl
theorem linear_no_discard   : linearityPermits .linear .discard   = false := rfl
theorem linear_yes_consume  : linearityPermits .linear .consume   = true  := rfl
theorem linear_yes_swap     : linearityPermits .linear .swap      = true  := rfl
theorem linear_yes_inspect  : linearityPermits .linear .inspect   = true  := rfl

-- AFFINE row
theorem affine_no_duplicate : linearityPermits .affine .duplicate = false := rfl
theorem affine_yes_discard  : linearityPermits .affine .discard   = true  := rfl
theorem affine_yes_consume  : linearityPermits .affine .consume   = true  := rfl
theorem affine_yes_swap     : linearityPermits .affine .swap      = true  := rfl
theorem affine_yes_inspect  : linearityPermits .affine .inspect   = true  := rfl

-- RELEVANT row
theorem relevant_yes_duplicate : linearityPermits .relevant .duplicate = true  := rfl
theorem relevant_no_discard    : linearityPermits .relevant .discard   = false := rfl
theorem relevant_yes_consume   : linearityPermits .relevant .consume   = true  := rfl
theorem relevant_yes_swap      : linearityPermits .relevant .swap      = true  := rfl
theorem relevant_yes_inspect   : linearityPermits .relevant .inspect   = true  := rfl

-- DEBUG row
theorem debug_yes_duplicate : linearityPermits .debug .duplicate = true := rfl
theorem debug_yes_discard   : linearityPermits .debug .discard   = true := rfl
theorem debug_yes_consume   : linearityPermits .debug .consume   = true := rfl
theorem debug_yes_swap      : linearityPermits .debug .swap      = true := rfl
theorem debug_yes_inspect   : linearityPermits .debug .inspect   = true := rfl

-- Completeness: linearityPermits is decidable (follows from Bool return type)
-- and covers all 20 cases (4 linearity types × 5 stack operations).

/-- If linearityPermits returns false, then the linearity type and
    stack op must be one of the four forbidden combinations. -/
theorem linearityPermits_false_cases (l : Linearity) (op : StackOp) :
    linearityPermits l op = false →
    (l = .linear ∧ op = .duplicate) ∨
    (l = .linear ∧ op = .discard) ∨
    (l = .affine ∧ op = .duplicate) ∨
    (l = .relevant ∧ op = .discard) := by
  intro h
  cases l <;> cases op <;> simp [linearityPermits] at h ⊢

end Semantos

```
