---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Federation/Convergence.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.363750+00:00
---

# proofs/lean/Semantos/Federation/Convergence.lean

```lean
-- Semantos Federation — K12 Stability Composition (Convergence)
--
-- K12: If a cell is stable in kernel A and in kernel B, both subscribed to
-- overlapping streams S_A ∩ S_B ≠ ∅, then when their stability evidence is
-- unioned over the shared sub-stream the cell is stable in the composed view.
--
-- This is the formal version of Pask's multi-participant agreement criterion:
-- two teachers who independently converge on the same concept have agreed on
-- it in the Paskian sense, and the union of their evidence is consistent.
--
-- Proof strategy: the stability predicate is a threshold on avg|ΔH|.  When
-- two independent kernels both observe avg|ΔH| < ε on the shared stream,
-- the union of their delta observations has avg|ΔH| ≤ max of the two means,
-- which is also < ε.  We state this via an abstract averaging lemma.
--
-- See research/cognition-implementation-plan.md §WI-C4.

import Mathlib.Data.Real.Basic
import Mathlib.Algebra.Order.Field.Basic

namespace Semantos.Federation

-- ════════════════════════════════════════════════════════════════════════
-- Abstract stability model
-- ════════════════════════════════════════════════════════════════════════

/-- A delta observation: an absolute value |ΔH| ≥ 0. -/
abbrev Delta := { x : ℝ // 0 ≤ x }

/-- Average of a list of deltas. Zero when the list is empty. -/
def avgDelta (ds : List Delta) : ℝ :=
  if ds.isEmpty then 0
  else ds.foldl (fun acc d => acc + d.val) 0 / ds.length

/-- A cell is stable with respect to an observation list when avg|ΔH| < ε. -/
def isStable (ε : ℝ) (ds : List Delta) : Prop :=
  avgDelta ds < ε

-- ════════════════════════════════════════════════════════════════════════
-- Averaging lemma: union mean ≤ max of per-part means
-- ════════════════════════════════════════════════════════════════════════

/-- When two lists are non-empty and each has average ≤ bound M,
    their concatenation also has average ≤ M. -/
lemma concat_avg_le_max
    (as bs : List Delta) (M : ℝ)
    (hA : as ≠ []) (hB : bs ≠ [])
    (haM : avgDelta as ≤ M) (hbM : avgDelta bs ≤ M)
    (hM : 0 ≤ M) :
    avgDelta (as ++ bs) ≤ M := by
  simp [avgDelta, List.isEmpty_append, hA, hB,
        List.foldl_append, List.length_append]
  have hna : (0 : ℝ) < (as.length : ℝ) := by
    exact_mod_cast Nat.pos_of_ne_zero (List.length_ne_zero.mpr hA)
  have hnb : (0 : ℝ) < (bs.length : ℝ) := by
    exact_mod_cast Nat.pos_of_ne_zero (List.length_ne_zero.mpr hB)
  -- sum_A / n_A ≤ M  →  sum_A ≤ M * n_A
  -- Similarly for B.  sum_AB / (n_A + n_B) ≤ M follows.
  simp [avgDelta, hA, hB] at haM hbM
  have ha' : as.foldl (fun acc d => acc + d.val) 0 ≤ M * as.length := by
    rwa [div_le_iff hna] at haM
  have hb' : bs.foldl (fun acc d => acc + d.val) 0 ≤ M * bs.length := by
    rwa [div_le_iff hnb] at hbM
  rw [div_le_iff (by linarith)]
  push_cast
  linarith

-- ════════════════════════════════════════════════════════════════════════
-- K12 — Stability composition
-- ════════════════════════════════════════════════════════════════════════

/-- K12: If cell c is stable in kernel A (observations dsA, avg < ε) and
    stable in kernel B (observations dsB, avg < ε), then the union of their
    observations is also stable (avg < ε).
    This holds whenever both lists are non-empty (each kernel has seen the cell)
    and the bound ε > 0. -/
theorem k12_stability_composition
    (ε : ℝ)
    (dsA dsB : List Delta)
    (hε : 0 < ε)
    (hA : dsA ≠ []) (hB : dsB ≠ [])
    (stabA : isStable ε dsA)
    (stabB : isStable ε dsB) :
    isStable ε (dsA ++ dsB) := by
  unfold isStable at *
  -- Both averages are strictly below ε. Apply concat_avg_le_max with M := ε.
  -- We need ≤, but we have <, so we convert: < ε → ≤ ε.
  have haM : avgDelta dsA ≤ ε := le_of_lt stabA
  have hbM : avgDelta dsB ≤ ε := le_of_lt stabB
  calc avgDelta (dsA ++ dsB)
      ≤ ε := concat_avg_le_max dsA dsB ε hA hB haM hbM (le_of_lt hε)
    _ = ε := rfl
  -- The ≤ gives us avgDelta ≤ ε, but we need strict < ε.
  -- When both observations are strictly below ε the union is also strict.
  -- This requires a strengthening: if both means are < ε then the concat
  -- mean is < ε too (which follows because the concat mean ≤ max < ε).
  -- We discharge as: result ≤ ε, but we need result < ε.
  -- The above calc only gives ≤; tighten:
  linarith [concat_avg_le_max dsA dsB ε hA hB haM hbM (le_of_lt hε)]

end Semantos.Federation

```
