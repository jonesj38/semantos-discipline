---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Theorems/DemotionK8.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.372110+00:00
---

# proofs/lean/Semantos/Theorems/DemotionK8.lean

```lean
-- Semantos Plane — Theorem K8: Linearity Demotion Safety
--
-- OP_DEMOTE (0xCB) only allows valid transitions.
-- Proof target: plexus.zig opDemote, validDemotion function
--
-- K8a-K8b: Valid demotions
-- K8c-K8i: Invalid demotions (no promotion, no cross-branch)
-- K8_only_linear_demotable: Exhaustive — only LINEAR can be demoted

import Semantos.Executor

namespace Semantos.Theorems

open Semantos Semantos.Opcodes

-- ══════════════════════════════════════════════════════════════════════
-- K8a-K8b: Valid demotion transitions
-- ══════════════════════════════════════════════════════════════════════

/-- K8a: LINEAR→AFFINE is a valid demotion. -/
theorem k8a_linear_to_affine_valid :
    validDemotion .linear .affine = true := rfl

/-- K8b: LINEAR→RELEVANT is a valid demotion. -/
theorem k8b_linear_to_relevant_valid :
    validDemotion .linear .relevant = true := rfl

-- ══════════════════════════════════════════════════════════════════════
-- K8c-K8i: Invalid transitions (exhaustive rejection)
-- ══════════════════════════════════════════════════════════════════════

/-- K8c: AFFINE→LINEAR is invalid (no promotion). -/
theorem k8c_affine_to_linear_invalid :
    validDemotion .affine .linear = false := rfl

/-- K8d: RELEVANT→LINEAR is invalid (no promotion). -/
theorem k8d_relevant_to_linear_invalid :
    validDemotion .relevant .linear = false := rfl

/-- K8e: AFFINE→AFFINE is invalid (not a demotion). -/
theorem k8e_affine_to_affine_invalid :
    validDemotion .affine .affine = false := rfl

/-- K8f: RELEVANT→RELEVANT is invalid. -/
theorem k8f_relevant_to_relevant_invalid :
    validDemotion .relevant .relevant = false := rfl

/-- K8g: RELEVANT→AFFINE is invalid (cross-branch). -/
theorem k8g_relevant_to_affine_invalid :
    validDemotion .relevant .affine = false := rfl

/-- K8h: AFFINE→RELEVANT is invalid (cross-branch). -/
theorem k8h_affine_to_relevant_invalid :
    validDemotion .affine .relevant = false := rfl

/-- K8i: DEBUG→LINEAR is invalid. -/
theorem k8i_debug_to_linear_invalid :
    validDemotion .debug .linear = false := rfl

/-- K8i: DEBUG→AFFINE is invalid. -/
theorem k8i_debug_to_affine_invalid :
    validDemotion .debug .affine = false := rfl

/-- K8i: DEBUG→RELEVANT is invalid. -/
theorem k8i_debug_to_relevant_invalid :
    validDemotion .debug .relevant = false := rfl

/-- K8i: DEBUG→DEBUG is invalid. -/
theorem k8i_debug_to_debug_invalid :
    validDemotion .debug .debug = false := rfl

/-- K8i: LINEAR→LINEAR is invalid (same-level). -/
theorem k8i_linear_to_linear_invalid :
    validDemotion .linear .linear = false := rfl

/-- K8i: LINEAR→DEBUG is invalid. -/
theorem k8i_linear_to_debug_invalid :
    validDemotion .linear .debug = false := rfl

-- ══════════════════════════════════════════════════════════════════════
-- Exhaustive structural properties
-- ══════════════════════════════════════════════════════════════════════

/-- Only LINEAR can be demoted — any valid demotion has source = .linear.

    Proof: case-split on both arguments. For the two valid cases
    (linear→affine, linear→relevant), the goal `linear = linear` is
    closed by `rfl`. For all other 14 cases, `validDemotion` reduces to
    `false`, so `h : false = true` is False, closed by `simp at h`. -/
theorem k8_only_linear_demotable (src tgt : Linearity) :
    validDemotion src tgt = true →
    src = .linear := by
  intro h
  cases src <;> cases tgt <;> first | rfl | simp [validDemotion] at h

/-- Valid demotion targets are AFFINE or RELEVANT only.

    Proof: case-split on both arguments, then for each surviving case
    pick the appropriate disjunct (or close via False from h). -/
theorem k8_target_is_weaker (src tgt : Linearity) :
    validDemotion src tgt = true →
    tgt = .affine ∨ tgt = .relevant := by
  intro h
  cases src <;> cases tgt <;>
    first
      | exact Or.inl rfl
      | exact Or.inr rfl
      | simp [validDemotion] at h

-- ══════════════════════════════════════════════════════════════════════
-- Classification properties for new opcodes
-- ══════════════════════════════════════════════════════════════════════

/-- OP_READHEADER is classified as inspect (read-only, no cell mutation). -/
theorem k8_readheader_is_inspect :
    classifyOp OP_READHEADER = .inspect := by decide

/-- OP_READPAYLOAD is classified as inspect (read-only, no cell mutation). -/
theorem k8_readpayload_is_inspect :
    classifyOp OP_READPAYLOAD = .inspect := by decide

/-- OP_CODESEPARATOR is classified as inspect (no stack effect). -/
theorem k8_codeseparator_is_inspect :
    classifyOp OP_CODESEPARATOR = .inspect := by decide

/-- OP_DEMOTE is classified as consume (consumes input, produces new cell). -/
theorem k8_demote_is_consume :
    classifyOp OP_DEMOTE = .consume := by decide

/-- OP_CELLCREATE is classified as consume (consumes arguments, produces cell). -/
theorem k8_cellcreate_is_consume :
    classifyOp OP_CELLCREATE = .consume := by decide

end Semantos.Theorems

```
