---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Substrate/Merge.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.367164+00:00
---

# proofs/lean/Semantos/Substrate/Merge.lean

```lean
-- Semantos Plane — Polymorphic Merge Theorems
--
-- M1-M4 proved for any `Patch α`. These are the substrate-level safety
-- properties of `mergePatches` — they depend only on `id` / `timestamp`
-- and list operations, so they transfer to every lexicon.
--
-- Each lexicon (Jural, ControlSystems, …) instantiates `α` and gets
-- these theorems for free by specialisation.

import Semantos.Substrate.Types

namespace Semantos.Substrate

/-- Ids present in a patch list. -/
def patchIds {α : Type} (ps : List (Patch α)) : List String := ps.map (·.id)

/-- Patches in `selected` whose id does not appear in `existing`. -/
def novel {α : Type} (existing selected : List (Patch α)) : List (Patch α) :=
  selected.filter (fun p => decide (p.id ∉ patchIds existing))

/-- Merge: append fresh `novel` patches onto `existing`. Works for any α. -/
def mergePatches {α : Type} (existing selected : List (Patch α)) : List (Patch α) :=
  existing ++ novel existing selected

-- ══════════════════════════════════════════════════════════════════════
-- M1: Preservation
-- ══════════════════════════════════════════════════════════════════════

theorem m1_merge_preserves_existing {α : Type}
    (existing selected : List (Patch α)) (p : Patch α)
    (h : p ∈ existing) :
    p ∈ mergePatches existing selected := by
  show p ∈ existing ++ novel existing selected
  exact List.mem_append_left _ h

-- ══════════════════════════════════════════════════════════════════════
-- M2: Novel-fresh
-- ══════════════════════════════════════════════════════════════════════

theorem m2_novel_ids_fresh {α : Type}
    (existing selected : List (Patch α)) (p : Patch α)
    (h : p ∈ novel existing selected) :
    p.id ∉ patchIds existing := by
  have hf := List.mem_filter.mp h
  exact of_decide_eq_true hf.2

-- ══════════════════════════════════════════════════════════════════════
-- M3: Authorship preservation
-- ══════════════════════════════════════════════════════════════════════

theorem m3_merge_preserves_authorship {α : Type}
    (existing selected : List (Patch α)) (p : Patch α)
    (h : p ∈ mergePatches existing selected) :
    p ∈ existing ∨ p ∈ selected := by
  rcases List.mem_append.mp h with h | h
  · exact Or.inl h
  · exact Or.inr (List.mem_filter.mp h).1

-- ══════════════════════════════════════════════════════════════════════
-- M4: Idempotence (helpers + main theorem)
-- ══════════════════════════════════════════════════════════════════════

theorem patchIds_append {α : Type} (a b : List (Patch α)) :
    patchIds (a ++ b) = patchIds a ++ patchIds b := by
  simp [patchIds]

theorem id_in_patchIds_of_mem {α : Type}
    {existing : List (Patch α)} {p : Patch α}
    (h : p ∈ existing) : p.id ∈ patchIds existing := by
  simp [patchIds]
  exact ⟨p, h, rfl⟩

theorem selected_ids_covered_after_merge {α : Type}
    (existing selected : List (Patch α)) (p : Patch α)
    (h : p ∈ selected) :
    p.id ∈ patchIds (mergePatches existing selected) := by
  show p.id ∈ patchIds (existing ++ novel existing selected)
  rw [patchIds_append]
  by_cases h_in : p.id ∈ patchIds existing
  · exact List.mem_append_left _ h_in
  · apply List.mem_append_right
    have h_novel : p ∈ novel existing selected := by
      show p ∈ selected.filter (fun q => decide (q.id ∉ patchIds existing))
      rw [List.mem_filter]
      exact ⟨h, decide_eq_true h_in⟩
    exact id_in_patchIds_of_mem h_novel

theorem novel_empty_of_ids_covered {α : Type}
    (existing selected : List (Patch α))
    (h : ∀ p ∈ selected, p.id ∈ patchIds existing) :
    novel existing selected = [] := by
  show selected.filter (fun p => decide (p.id ∉ patchIds existing)) = []
  rw [List.filter_eq_nil_iff]
  intro p hp h_pred
  exact (of_decide_eq_true h_pred) (h p hp)

theorem m4_merge_idempotent {α : Type}
    (existing selected : List (Patch α)) :
    mergePatches (mergePatches existing selected) selected
      = mergePatches existing selected := by
  have h_empty : novel (mergePatches existing selected) selected = [] := by
    apply novel_empty_of_ids_covered
    intro p hp
    exact selected_ids_covered_after_merge existing selected p hp
  show (mergePatches existing selected) ++ novel (mergePatches existing selected) selected
       = mergePatches existing selected
  rw [h_empty, List.append_nil]

end Semantos.Substrate

```
