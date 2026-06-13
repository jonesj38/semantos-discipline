---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/LegalCards/Diff.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.361360+00:00
---

# proofs/lean/Semantos/LegalCards/Diff.lean

```lean
-- Semantos Plane — diffPatches properties
--
-- Theorems:
--   D1: Correctness  — every patch in the diff has an id not in base
--   D2: Containment  — every patch in the diff came from incoming
--   D3: Completeness — every incoming patch with id ∉ base is in the diff
--
-- Proof target: scripts/lib/legal-cards.ts (diffPatches)
-- Property-test correspondence: §P9 (legal-cards.properties.test.ts)

import Semantos.LegalCards.Types
import Semantos.LegalCards.Merge  -- reuses `patchIds`

namespace Semantos.LegalCards

/-- Patches in `incoming` whose ids do not appear in `base`. -/
def diffPatches (base incoming : List LegalPatch) : List LegalPatch :=
  incoming.filter (fun p => decide (p.id ∉ patchIds base))

-- ══════════════════════════════════════════════════════════════════════
-- D1: Correctness
-- ══════════════════════════════════════════════════════════════════════

/-- D1: Every patch returned by `diffPatches base incoming` has an id NOT
    present in `base`. Core safety property: the diff never proposes a
    patch that would collide on id with the existing chain. -/
theorem d1_diff_returns_fresh_ids
    (base incoming : List LegalPatch) (p : LegalPatch)
    (h : p ∈ diffPatches base incoming) :
    p.id ∉ patchIds base := by
  have hf := List.mem_filter.mp h
  exact of_decide_eq_true hf.2

-- ══════════════════════════════════════════════════════════════════════
-- D2: Containment
-- ══════════════════════════════════════════════════════════════════════

/-- D2: Every patch in the diff came from the `incoming` bundle. The diff
    invents no patches — it is a pure filter. -/
theorem d2_diff_is_subset_of_incoming
    (base incoming : List LegalPatch) (p : LegalPatch)
    (h : p ∈ diffPatches base incoming) :
    p ∈ incoming :=
  (List.mem_filter.mp h).1

-- ══════════════════════════════════════════════════════════════════════
-- D3: Completeness
-- ══════════════════════════════════════════════════════════════════════

/-- D3: Every incoming patch with an id absent from `base` appears in the
    diff. The diff misses no genuine novelty. Combined with D1+D2, this
    characterises `diffPatches` completely. -/
theorem d3_diff_complete
    (base incoming : List LegalPatch) (p : LegalPatch)
    (h_in : p ∈ incoming) (h_fresh : p.id ∉ patchIds base) :
    p ∈ diffPatches base incoming := by
  show p ∈ incoming.filter (fun q => decide (q.id ∉ patchIds base))
  rw [List.mem_filter]
  exact ⟨h_in, decide_eq_true h_fresh⟩

end Semantos.LegalCards

```
