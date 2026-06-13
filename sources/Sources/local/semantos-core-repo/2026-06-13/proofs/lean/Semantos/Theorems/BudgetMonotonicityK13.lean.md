---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Theorems/BudgetMonotonicityK13.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.370916+00:00
---

# proofs/lean/Semantos/Theorems/BudgetMonotonicityK13.lean

```lean
-- Semantos Plane — Theorem K13: Budget Monotonicity  (Phase W3)
--
-- Two sub-theorems:
--
-- K13a: OP_DECREMENT_BUDGET strictly decreases `remaining_satoshis`
--       when the call succeeds with amount > 0.
-- K13b: OP_REFILL_BUDGET strictly increases `remaining_satoshis`
--       when the call succeeds with amount > 0 and a valid parent signature.
--
-- The cell-engine model (Semantos.Opcodes.Plexus, Semantos.Opcodes.Sign)
-- abstracts cell payload bytes and does not mechanically track
-- `remaining_satoshis`. We instead model the budget arithmetic as a thin
-- separate layer (`BudgetState` below) and state the monotonicity property
-- on it. The differential tests in `tests/budget_conformance.zig` verify
-- that the on-stack cell behavior matches this layer (the test K13 cases).

import Semantos.Opcodes.Standard

namespace Semantos.Theorems

open Semantos Semantos.Opcodes

/-- Abstract budget accounting state. Mirrors the `remaining_satoshis` field
    at payload byte 32..40 of a Tier-0 budget cell (§6.1 of the design). -/
structure BudgetState where
  remaining : Nat
  deriving Repr, DecidableEq

/-- Abstract debit operation. Models OP_DECREMENT_BUDGET's effect on the
    `remaining_satoshis` field. Errors with `insufficient_budget` if the
    amount exceeds the available balance. -/
def opDecrementBudgetAbs (s : BudgetState) (amount : Nat) : Except OpcodeError BudgetState :=
  if amount > s.remaining then .error .invalidOpcode  -- abstract failure tag
  else .ok ⟨s.remaining - amount⟩

/-- Abstract refill operation. Models OP_REFILL_BUDGET's effect on the
    `remaining_satoshis` field. Treats sig verification as an opaque
    boolean — the cell-level model already binds verification to
    `host.checksig` via the `ecdsa_existential_unforgeability` axiom. -/
def opRefillBudgetAbs (s : BudgetState) (amount : Nat) (sig_ok : Bool) :
    Except OpcodeError BudgetState :=
  if !sig_ok then .error .invalidOpcode
  else .ok ⟨s.remaining + amount⟩

-- ══════════════════════════════════════════════════════════════════════
-- K13a: Decrement strictly reduces remaining (with positive amount)
-- ══════════════════════════════════════════════════════════════════════

/-- K13a: Successful debit with a positive amount strictly decreases
    `remaining_satoshis`. -/
theorem k13a_decrement_strictly_decreases
    (s s' : BudgetState) (amount : Nat)
    (h_pos : amount > 0)
    (h_ok : opDecrementBudgetAbs s amount = .ok s') :
    s'.remaining < s.remaining := by
  unfold opDecrementBudgetAbs at h_ok
  split at h_ok
  · cases h_ok  -- amount > remaining ⇒ error, contradiction with h_ok = .ok _
  · -- amount ≤ remaining: result is ⟨s.remaining - amount⟩
    rename_i h_le
    have h_le' : ¬ amount > s.remaining := h_le
    simp at h_le'
    injection h_ok with h_eq
    have h_rem : s'.remaining = s.remaining - amount := by rw [← h_eq]
    rw [h_rem]
    omega

/-- K13a (corollary): Decrement is monotone non-increasing — the result is
    always at most the input remaining. -/
theorem k13a_decrement_monotone
    (s s' : BudgetState) (amount : Nat)
    (h_ok : opDecrementBudgetAbs s amount = .ok s') :
    s'.remaining ≤ s.remaining := by
  unfold opDecrementBudgetAbs at h_ok
  split at h_ok
  · cases h_ok
  · injection h_ok with h_eq
    have h_rem : s'.remaining = s.remaining - amount := by rw [← h_eq]
    rw [h_rem]
    omega

-- ══════════════════════════════════════════════════════════════════════
-- K13b: Refill strictly increases remaining (with positive amount, valid sig)
-- ══════════════════════════════════════════════════════════════════════

/-- K13b: Successful refill with a positive amount and valid parent signature
    strictly increases `remaining_satoshis`. -/
theorem k13b_refill_strictly_increases
    (s s' : BudgetState) (amount : Nat)
    (h_pos : amount > 0)
    (h_ok : opRefillBudgetAbs s amount true = .ok s') :
    s'.remaining > s.remaining := by
  unfold opRefillBudgetAbs at h_ok
  -- !true = false, so the if takes the else branch and h_ok becomes
  -- `Except.ok ⟨s.remaining + amount⟩ = Except.ok s'`.
  simp at h_ok
  have h_rem : s'.remaining = s.remaining + amount := by rw [← h_ok]
  rw [h_rem]
  omega

/-- K13b (sig-required): Refill with `sig_ok = false` always errors —
    no credit happens without a valid parent signature. -/
theorem k13b_refill_requires_sig (s : BudgetState) (amount : Nat) :
    opRefillBudgetAbs s amount false = .error .invalidOpcode := by
  unfold opRefillBudgetAbs
  simp

end Semantos.Theorems

```
