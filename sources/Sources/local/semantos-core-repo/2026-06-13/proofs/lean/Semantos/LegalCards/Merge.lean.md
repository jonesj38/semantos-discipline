---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/LegalCards/Merge.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.360781+00:00
---

# proofs/lean/Semantos/LegalCards/Merge.lean

```lean
-- Semantos Plane — mergePatches properties
--
-- Theorems:
--   M1: Preservation — every existing patch survives the merge
--   M2: Novel-fresh — patches added by the merge have ids absent from
--       the existing chain
--   M3: Authorship — merge never rewrites any patch; every result patch
--       equals some input patch
--   M4: Idempotence — merge(merge(e, s), s) = merge(e, s)
--
-- Proof target: scripts/lib/legal-cards.ts (mergePatches).
-- Property-test correspondence in
-- scripts/lib/__tests__/legal-cards.properties.test.ts:
--   §P5 preserves all existing patches   ↔ M1
--   §P7 deduplicates by id               ↔ M2
--   §P8 preserves authorship              ↔ M3
--   §P4 is idempotent                     ↔ M4

import Semantos.LegalCards.Types

namespace Semantos.LegalCards

-- ══════════════════════════════════════════════════════════════════════
-- Definitions
-- ══════════════════════════════════════════════════════════════════════

/-- Ids present in a patch list. -/
def patchIds (ps : List LegalPatch) : List String := ps.map (·.id)

/-- Patches in `selected` whose id does not appear in `existing`. -/
def novel (existing selected : List LegalPatch) : List LegalPatch :=
  selected.filter (fun p => decide (p.id ∉ patchIds existing))

/-- Merge: append the fresh `novel` patches onto `existing`. The production
    TS implementation also sorts by timestamp; sort-stability is orthogonal
    and proved separately from the invariants below. -/
def mergePatches (existing selected : List LegalPatch) : List LegalPatch :=
  existing ++ novel existing selected

-- ══════════════════════════════════════════════════════════════════════
-- M1: Preservation
-- ══════════════════════════════════════════════════════════════════════

/-- M1: Every patch in the existing chain survives the merge. -/
theorem m1_merge_preserves_existing
    (existing selected : List LegalPatch) (p : LegalPatch)
    (h : p ∈ existing) :
    p ∈ mergePatches existing selected := by
  show p ∈ existing ++ novel existing selected
  exact List.mem_append_left _ h

-- ══════════════════════════════════════════════════════════════════════
-- M2: Novel-fresh
-- ══════════════════════════════════════════════════════════════════════

/-- M2: Every patch added by the merge (i.e. in `novel`) has an id that is
    NOT present in the existing chain. No id collisions are introduced. -/
theorem m2_novel_ids_fresh
    (existing selected : List LegalPatch) (p : LegalPatch)
    (h : p ∈ novel existing selected) :
    p.id ∉ patchIds existing := by
  have hf := List.mem_filter.mp h
  exact of_decide_eq_true hf.2

-- ══════════════════════════════════════════════════════════════════════
-- M3: Authorship preservation
-- ══════════════════════════════════════════════════════════════════════

/-- M3: Every patch in the merged chain equals some input patch. The merge
    never synthesises or rewrites patches — so every field (hatId,
    category, trust class, id) is preserved. No synthetic "merge author"
    is introduced. -/
theorem m3_merge_preserves_authorship
    (existing selected : List LegalPatch) (p : LegalPatch)
    (h : p ∈ mergePatches existing selected) :
    p ∈ existing ∨ p ∈ selected := by
  rcases List.mem_append.mp h with h | h
  · exact Or.inl h
  · exact Or.inr (List.mem_filter.mp h).1

-- ══════════════════════════════════════════════════════════════════════
-- M4: Idempotence (helpers + main theorem)
-- ══════════════════════════════════════════════════════════════════════

/-- Helper: patchIds distributes over append. -/
theorem patchIds_append (a b : List LegalPatch) :
    patchIds (a ++ b) = patchIds a ++ patchIds b := by
  simp [patchIds]

/-- Helper: if p is in a list, its id is in that list's patchIds. -/
theorem id_in_patchIds_of_mem
    {existing : List LegalPatch} {p : LegalPatch}
    (h : p ∈ existing) : p.id ∈ patchIds existing := by
  simp [patchIds]
  exact ⟨p, h, rfl⟩

/-- Helper: every patch in `selected` has its id present in
    `mergePatches existing selected`. Either the id was already in
    `existing` (inherited via the left of the append), or the patch was
    fresh (added via `novel` on the right). -/
theorem selected_ids_covered_after_merge
    (existing selected : List LegalPatch) (p : LegalPatch)
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

/-- Helper: if every id in `selected` already appears in `existing.ids`,
    then no patch is fresh and `novel existing selected = []`. Uses
    `List.filter_eq_nil_iff` to rewrite the goal into a forall over
    membership, which follows from the hypothesis. -/
theorem novel_empty_of_ids_covered
    (existing selected : List LegalPatch)
    (h : ∀ p ∈ selected, p.id ∈ patchIds existing) :
    novel existing selected = [] := by
  show selected.filter (fun p => decide (p.id ∉ patchIds existing)) = []
  rw [List.filter_eq_nil_iff]
  intro p hp h_pred
  exact (of_decide_eq_true h_pred) (h p hp)

/-- M4: Idempotence. Applying the same `selected` a second time has no
    additional effect.

    Proof: after the first merge, every id in `selected` is present in
    the merged chain (via `selected_ids_covered_after_merge`). So the
    second application of `novel` filters out everything, and the outer
    append reduces to a no-op. -/
theorem m4_merge_idempotent
    (existing selected : List LegalPatch) :
    mergePatches (mergePatches existing selected) selected
      = mergePatches existing selected := by
  have h_empty : novel (mergePatches existing selected) selected = [] := by
    apply novel_empty_of_ids_covered
    intro p hp
    exact selected_ids_covered_after_merge existing selected p hp
  show (mergePatches existing selected) ++ novel (mergePatches existing selected) selected
       = mergePatches existing selected
  rw [h_empty, List.append_nil]

end Semantos.LegalCards

```
