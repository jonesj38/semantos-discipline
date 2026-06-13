---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Substrate/Diff.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.367721+00:00
---

# proofs/lean/Semantos/Substrate/Diff.lean

```lean
-- Semantos Plane — Polymorphic Diff Theorems
--
-- D1-D3 proved for any `Patch α`. Characterises `diffPatches` exactly:
-- it returns the subset of `incoming` whose ids are not in `base`, and
-- nothing else.

import Semantos.Substrate.Types
import Semantos.Substrate.Merge  -- reuses `patchIds`

namespace Semantos.Substrate

def diffPatches {α : Type} (base incoming : List (Patch α)) : List (Patch α) :=
  incoming.filter (fun p => decide (p.id ∉ patchIds base))

theorem d1_diff_returns_fresh_ids {α : Type}
    (base incoming : List (Patch α)) (p : Patch α)
    (h : p ∈ diffPatches base incoming) :
    p.id ∉ patchIds base := by
  have hf := List.mem_filter.mp h
  exact of_decide_eq_true hf.2

theorem d2_diff_is_subset_of_incoming {α : Type}
    (base incoming : List (Patch α)) (p : Patch α)
    (h : p ∈ diffPatches base incoming) :
    p ∈ incoming :=
  (List.mem_filter.mp h).1

theorem d3_diff_complete {α : Type}
    (base incoming : List (Patch α)) (p : Patch α)
    (h_in : p ∈ incoming) (h_fresh : p.id ∉ patchIds base) :
    p ∈ diffPatches base incoming := by
  show p ∈ incoming.filter (fun q => decide (q.id ∉ patchIds base))
  rw [List.mem_filter]
  exact ⟨h_in, decide_eq_true h_fresh⟩

end Semantos.Substrate

```
