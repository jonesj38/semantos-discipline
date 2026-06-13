---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Theorems/FederationPropagationK18.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.368349+00:00
---

# proofs/lean/Semantos/Theorems/FederationPropagationK18.lean

```lean
-- Semantos Plane — Theorem K18: Federation Propagation Independence
--
-- K18 (Federation propagation independence, UNIFICATION-ROADMAP §11.2):
--   Cells propagate via NetworkAdapter independent of world-host tick.
--   Equivalently: a cell can advance its prevStateHash chain at any
--   time, regardless of whether the world-host's 20 Hz region tick
--   is running, paused, or frozen.
--
-- This is the anti-claim test for the substrate-paper misclassification
-- "20 Hz tick orders all cells" (chapter 36 §36.7). The tick orders
-- SPATIAL ENTITIES inside one region; cells across federation order
-- via their own prevStateHash chains.
--
-- This file is the algebraic core of K18. The full distributed-protocol
-- claim is in `proofs/tla/FederationPropagation.tla` (TLA+ primary for
-- K18 per §11.7.2). Together: Lean proves the cell-advance function
-- doesn't read tick state; TLA+ proves the multi-region propagation
-- protocol honors that property.
--
-- Source target:
--   - core/cell-engine/src/semantic-objects.ts — appendPatch (cell advance)
--   - runtime/world-beam/apps/world_host/ — region tick scheduler
--   - extensions/dispatch/ + runtime/ws-node-adapter/ — federation transport

import Semantos.Theorems.HashChainIntegrityK6

namespace Semantos.Theorems

open Semantos.Crypto Semantos.Theorems

-- ══════════════════════════════════════════════════════════════════════
-- Model
-- ══════════════════════════════════════════════════════════════════════

/-- Region tick state — running or frozen. -/
inductive TickState : Type where
  | running
  | frozen
  deriving DecidableEq

/-- A region identifier. Modeled as Nat for tracking; structurally
    indistinguishable from other Nat-indexed types. -/
abbrev RegionId := Nat

/-- A federation snapshot: a chain (from K6) plus a per-region tick
    state. The K18 claim is that operations on the chain are
    decoupled from the tick state. -/
structure FederationState where
  chain : Chain
  tickStates : RegionId → TickState

namespace FederationState

/-- Advance the chain by appending a patch. K18 invariant: this
    operation does NOT read `tickStates`. -/
def advance (s : FederationState) (p : Patch) : FederationState :=
  { s with chain := { s.chain with patches := s.chain.patches ++ [p] } }

/-- Freeze a region's tick. K18 invariant: this operation does NOT
    affect `chain`. -/
def freezeTick (s : FederationState) (r : RegionId) : FederationState :=
  { s with tickStates := fun r' => if r' = r then TickState.frozen else s.tickStates r' }

/-- Resume a region's tick. Inverse of `freezeTick`. -/
def resumeTick (s : FederationState) (r : RegionId) : FederationState :=
  { s with tickStates := fun r' => if r' = r then TickState.running else s.tickStates r' }

end FederationState

open FederationState

-- ══════════════════════════════════════════════════════════════════════
-- K18a — Advance is independent of tick states
-- ══════════════════════════════════════════════════════════════════════

/-- K18a — The chain after advancing is the same regardless of any
    region's tick state. Formally: advance commutes with freezeTick
    in the sense that they don't interfere on the chain field.

    This is the algebraic core of K18. The TLA+ side proves the
    operational property; this side proves the symbolic claim. -/
theorem k18a_advance_chain_independent_of_tick
    (s : FederationState) (p : Patch) (r : RegionId) :
    (advance (freezeTick s r) p).chain = (advance s p).chain := by
  unfold advance freezeTick
  rfl

/-- K18a (resume direction) — same property for resuming a tick. -/
theorem k18a_advance_chain_independent_of_resume
    (s : FederationState) (p : Patch) (r : RegionId) :
    (advance (resumeTick s r) p).chain = (advance s p).chain := by
  unfold advance resumeTick
  rfl

-- ══════════════════════════════════════════════════════════════════════
-- K18b — Tick freeze doesn't affect chain
-- ══════════════════════════════════════════════════════════════════════

/-- K18b — Freezing a region's tick leaves the cell chain byte-identical.
    The two operations commute trivially because they live on disjoint
    fields. -/
theorem k18b_freeze_preserves_chain
    (s : FederationState) (r : RegionId) :
    (freezeTick s r).chain = s.chain := by
  unfold freezeTick
  rfl

-- ══════════════════════════════════════════════════════════════════════
-- K18c — Tip hash is unaffected by tick state
-- ══════════════════════════════════════════════════════════════════════

/-- K18c — The K6 tip hash of a chain is unaffected by any region's
    tick state. This composes K6 + K18: the cryptographic witness for
    cell-chain integrity (K6) is independent of the world-host tick
    state (K18).

    Operational meaning: if a verifier checks the tip hash to detect
    tampering (K6), they get the same answer whether the world-host
    tick is running or frozen. Federation receivers can verify cells
    even when the originator's region is offline. -/
theorem k18c_tipHash_independent_of_tick
    (s : FederationState) (r : RegionId) :
    Chain.tipHash (freezeTick s r).chain = Chain.tipHash s.chain := by
  rw [k18b_freeze_preserves_chain]

-- ══════════════════════════════════════════════════════════════════════
-- Composite K18
-- ══════════════════════════════════════════════════════════════════════

/-- K18 main statement — the algebraic core. Together with the
    TLA+ distributed-protocol spec, this gives both-sides coverage:

    - Lean (this file): cell-advance and tip-hash are pure functions
      of the chain field; they do not read tick state.
    - TLA+ (`FederationPropagation.tla`): the operational protocol
      that propagates cells across regions honors this independence
      across all reachable interleavings.

    The combination: the implementation must (a) keep advance/tipHash
    independent of tick (algebra) AND (b) implement the federation
    protocol without injecting a tick check (operational). -/
theorem k18_federation_propagation_independence :
    ∀ (s : FederationState) (p : Patch) (r : RegionId),
      (advance (freezeTick s r) p).chain = (advance s p).chain ∧
      Chain.tipHash (freezeTick s r).chain = Chain.tipHash s.chain := by
  intro s p r
  exact ⟨k18a_advance_chain_independent_of_tick s p r,
         k18c_tipHash_independent_of_tick s r⟩

end Semantos.Theorems

```
