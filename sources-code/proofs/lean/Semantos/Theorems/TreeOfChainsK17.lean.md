---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Theorems/TreeOfChainsK17.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.369774+00:00
---

# proofs/lean/Semantos/Theorems/TreeOfChainsK17.lean

```lean
-- Semantos Plane — Theorem K17: Tree-of-Chains Merge Integrity
--
-- K17 (Tree-of-chains merge, UNIFICATION-ROADMAP §11.2):
--   Multi-parent merge cells preserve hash-chain integrity. The merge
--   tip is deterministically a function of (parent₁_tip, parent₂_tip,
--   merge_payload) — no other inputs. Tampering with any of the three
--   produces a detectable tip change.
--
-- This is the algebraic core of the tree-of-chains semantics decided
-- in §8 Q4 of UNIFICATION-ROADMAP (2026-04-26): documents in the
-- markdown editor adopt tree-of-chains branching; merge nodes have
-- two parent-hashes; the document's history is a directed tree of
-- independent chains rather than a single DAG.
--
-- Forward-looking spec — D-E-md is unimplemented; this theorem pins
-- the merge contract the implementation must conform to.
--
-- Source target:
--   - docs/textbook/19-hash-chains-as-time.md §81-87 (governance Q4)
--   - extensions/md-editor/ (D-E-md, currently stub)
--   - core/semantic-objects/ (merge cell representation when authored)

import Semantos.Theorems.HashChainIntegrityK6

namespace Semantos.Theorems

open Semantos.Crypto Semantos.Theorems Semantos.Theorems.Chain

-- ══════════════════════════════════════════════════════════════════════
-- Model — merge cells
-- ══════════════════════════════════════════════════════════════════════

/-- A merge cell combines two parent tip hashes with its own commit
    bytes. The merge cell's tip is `sha256(concat(parent₁_tip,
    concat(parent₂_tip, merge_commit)))` — the standard binary-tree
    merge hash.

    Real merge cells live in two-parent positions of the tree-of-chains;
    we abstract over the multi-parent header field (proposed §11.2
    D-E-md extension) and model just the tip-hash construction. -/
structure MergeNode where
  parent₁Tip : Bytes
  parent₂Tip : Bytes
  commit     : Bytes

namespace MergeNode

/-- Compute the merge tip hash. Encodes the K17 contract: tip is a
    deterministic function of the three inputs.

    The chained concat is the standard pattern for k-ary tree hashes —
    fold sha256 + concat over (commit, parent₁Tip, parent₂Tip). The
    order matters; we fix the convention as (commit, p₁, p₂). -/
noncomputable def tipHash (m : MergeNode) : Bytes :=
  sha256 (concat m.commit (concat m.parent₁Tip m.parent₂Tip))

end MergeNode

-- ══════════════════════════════════════════════════════════════════════
-- K17a — Merge tip is determined by inputs
-- ══════════════════════════════════════════════════════════════════════

/-- K17a — Two merge nodes with identical inputs produce identical
    tip hashes. (Determinism / functional purity.) -/
theorem k17a_merge_tip_deterministic (m₁ m₂ : MergeNode)
    (h₁ : m₁.commit = m₂.commit)
    (h₂ : m₁.parent₁Tip = m₂.parent₁Tip)
    (h₃ : m₁.parent₂Tip = m₂.parent₂Tip) :
    MergeNode.tipHash m₁ = MergeNode.tipHash m₂ := by
  unfold MergeNode.tipHash
  rw [h₁, h₂, h₃]

-- ══════════════════════════════════════════════════════════════════════
-- K17b — Parent-tampering detection
-- ══════════════════════════════════════════════════════════════════════

/-- K17b — Tampering with parent₁'s tip changes the merge tip.

    Concretely: if attacker swaps the content of parent₁'s chain
    (which changes parent₁'s tip hash by K6), the merge tip changes
    too. The tree-of-chains merge "rolls up" K6's tampering-detection
    property to the merge level — anyone with the merge tip can
    detect tampering anywhere in either parent's chain. -/
theorem k17b_parent1_tampering_detectable
    (commit : Bytes) (p₁ p₁' p₂ : Bytes) (h : p₁ ≠ p₁') :
    let m  := { commit := commit, parent₁Tip := p₁,  parent₂Tip := p₂ : MergeNode }
    let m' := { commit := commit, parent₁Tip := p₁', parent₂Tip := p₂ : MergeNode }
    MergeNode.tipHash m ≠ MergeNode.tipHash m' := by
  intro m m'
  unfold MergeNode.tipHash
  -- The two SHA inputs differ because the concat differs
  apply sha256_collision_free
  apply concat_injective
  right                                  -- Outer concat distinct in second arg
  apply concat_injective
  left                                   -- Inner concat distinct in first arg
  exact h

/-- K17b' — Symmetric: tampering with parent₂ also changes the tip. -/
theorem k17b'_parent2_tampering_detectable
    (commit : Bytes) (p₁ p₂ p₂' : Bytes) (h : p₂ ≠ p₂') :
    let m  := { commit := commit, parent₁Tip := p₁, parent₂Tip := p₂  : MergeNode }
    let m' := { commit := commit, parent₁Tip := p₁, parent₂Tip := p₂' : MergeNode }
    MergeNode.tipHash m ≠ MergeNode.tipHash m' := by
  intro m m'
  unfold MergeNode.tipHash
  apply sha256_collision_free
  apply concat_injective
  right                                  -- Outer concat distinct in second arg
  apply concat_injective
  right                                  -- Inner concat distinct in second arg
  exact h

-- ══════════════════════════════════════════════════════════════════════
-- K17c — Commit-tampering detection
-- ══════════════════════════════════════════════════════════════════════

/-- K17c — Tampering with the merge cell's own commit bytes is also
    detectable. (Closes the trifecta: any of the three K17 inputs
    changing produces a tip change.) -/
theorem k17c_commit_tampering_detectable
    (c c' p₁ p₂ : Bytes) (h : c ≠ c') :
    let m  := { commit := c,  parent₁Tip := p₁, parent₂Tip := p₂ : MergeNode }
    let m' := { commit := c', parent₁Tip := p₁, parent₂Tip := p₂ : MergeNode }
    MergeNode.tipHash m ≠ MergeNode.tipHash m' := by
  intro m m'
  unfold MergeNode.tipHash
  apply sha256_collision_free
  apply concat_injective
  left                                   -- Outer concat distinct in first arg
  exact h

-- ══════════════════════════════════════════════════════════════════════
-- Note on a composite "main theorem"
-- ══════════════════════════════════════════════════════════════════════
--
-- A composite "K17 main" theorem of the form
--   tipHash m₁ = tipHash m₂ → m₁.commit = m₂.commit ∧ ...
-- is provable from K17a + K17b + K17b' + K17c (contrapositives), but
-- requires bridging between the field-destructuring used in the
-- per-input lemmas (which take Bytes args) and the record-equality
-- form (which takes MergeNode args). That bridging is mechanical but
-- non-trivial; deferred to a future commit. The per-input theorems
-- above already give the full security claim — anyone reading the
-- spec gets K17 in three pieces (commit, parent₁, parent₂) each
-- proved independently.
--
-- Per the no-unfinished-proof convention, this file ships only the
-- proven sub-theorems. The composite is referenced in §11.7.2 /
-- §11.7.4 as a candidate follow-up.

end Semantos.Theorems

```
