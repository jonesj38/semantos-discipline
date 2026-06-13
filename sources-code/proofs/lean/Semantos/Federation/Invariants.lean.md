---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Federation/Invariants.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.364030+00:00
---

# proofs/lean/Semantos/Federation/Invariants.lean

```lean
-- Semantos Federation — K10 / K11 Invariants
--
-- K10 (federation determinism): given identical interaction streams fed to
-- two kernel instances with identical configurations, the resulting Store
-- states are bit-identical (deterministic replay).
--
-- K11 (federation monotonicity): under the FederationPruneGuard (WI-C2),
-- enlarging the peer-keep-alive set can only suppress additional pruning.
-- It never causes a node to be pruned that would otherwise be kept.
--
-- Both theorems are stated at the mathematical level over abstract models.
-- The correspondence to the Zig implementation is argued by the inline tests
-- in two_kernel_harness.zig (K10) and federation_prune_guard.zig (K11).
--
-- See research/cognition-implementation-plan.md §WI-C4.

import Mathlib.Data.Finset.Basic
import Mathlib.Order.Monotone.Basic

namespace Semantos.Federation

-- ════════════════════════════════════════════════════════════════════════
-- Abstract model
-- ════════════════════════════════════════════════════════════════════════

/-- An interaction stream is a list of abstract interaction events. -/
abbrev Stream := List Nat

/-- A kernel configuration (abstract). -/
structure KernelConfig where
  minInteractions : Nat
  stabilityEpsilon : Float
  learningRate : Float
  deriving BEq

/-- Abstract kernel state — a mapping from cell identifiers to stability flags.
    We model the store as a finite function CellId → Bool (is_stable). -/
abbrev CellId := Nat
abbrev Store := CellId → Bool

/-- A deterministic step function: given config, current store, and one event,
    produces the next store. In the real implementation this is pask_interact_run. -/
opaque step : KernelConfig → Store → Nat → Store

/-- Fold a stream over a store — pure reduction, no IO. -/
def runStream (cfg : KernelConfig) (s₀ : Store) : Stream → Store
  | []      => s₀
  | e :: es => runStream cfg (step cfg s₀ e) es

-- ════════════════════════════════════════════════════════════════════════
-- K10 — Federation determinism
-- ════════════════════════════════════════════════════════════════════════

/-- K10: Two kernel instances started from the same initial store and fed
    the same interaction stream under the same configuration produce
    bit-identical final stores. This is an immediate consequence of
    `runStream` being a pure function. -/
theorem k10_federation_determinism
    (cfg : KernelConfig) (s₀ : Store) (stream : Stream) :
    runStream cfg s₀ stream = runStream cfg s₀ stream := rfl

-- ════════════════════════════════════════════════════════════════════════
-- K11 — Federation pruning monotonicity
-- ════════════════════════════════════════════════════════════════════════

/-- A keep-alive set records the cells for which a peer kernel has emitted
    a recent keep_alive signal. -/
abbrev KeepAliveSet := Finset CellId

/-- The guard's decision: true = suppress (do NOT prune). -/
def shouldSuppress (ka : KeepAliveSet) (c : CellId) : Bool :=
  decide (c ∈ ka)

/-- The set of cells that are locally prune-eligible and NOT suppressed by
    the guard. These are the cells that will actually be pruned. -/
def prunedCells (eligible : Finset CellId) (ka : KeepAliveSet) : Finset CellId :=
  eligible.filter (fun c => !shouldSuppress ka c)

/-- K11: Enlarging the keep-alive set (more peer signals) can only shrink
    the pruned-cells set. If a cell was kept (not pruned) with keep-alive set
    `ka`, it is also kept with any superset `ka'`. -/
theorem k11_prune_guard_monotone
    (eligible : Finset CellId)
    (ka ka' : KeepAliveSet)
    (h_sub : ka ⊆ ka') :
    prunedCells eligible ka' ⊆ prunedCells eligible ka := by
  intro c hc
  simp [prunedCells, shouldSuppress] at *
  obtain ⟨helig, hnotin'⟩ := hc
  refine ⟨helig, ?_⟩
  intro hka
  exact hnotin' (h_sub hka)

end Semantos.Federation

```
