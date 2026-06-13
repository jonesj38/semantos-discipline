---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/LegalCards/Render.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.361075+00:00
---

# proofs/lean/Semantos/LegalCards/Render.lean

```lean
-- Semantos Plane — Legal Card Rendering
--
-- Theorems:
--   R1:  `renderCard` is total
--   R2:  `categoryHeader` is injective — distinct categories render to
--        distinct header tokens, so a rendered card unambiguously
--        identifies the jural relation it encodes
--   R3:  `renderCard` is deterministic (pure function)
--   R3b: `renderCard` depends only on (category, hatId, id) — the
--        fields the template actually reads

import Semantos.LegalCards.Types

namespace Semantos.LegalCards

-- ══════════════════════════════════════════════════════════════════════
-- Category header dispatch
-- ══════════════════════════════════════════════════════════════════════

/-- The header token rendered for each jural category. -/
def categoryHeader : JuralCategory → String
  | .declaration => "DECLARATION"
  | .obligation  => "OBLIGATION"
  | .permission  => "PERMISSION"
  | .prohibition => "PROHIBITION"
  | .power       => "POWER"
  | .condition   => "CONDITION"
  | .transfer    => "TRANSFER"

/-- Render a legal patch to a minimal card string. The production TypeScript
    renderer emits a richer multi-section card; this Lean model captures
    the header dispatch — the part the theorems below constrain. -/
def renderCard (p : LegalPatch) : String :=
  "PROPOSED: " ++ categoryHeader p.category ++
  "   (by " ++ p.hatId ++ ")\n  patch id: " ++ p.id

-- ══════════════════════════════════════════════════════════════════════
-- R1: Totality
-- ══════════════════════════════════════════════════════════════════════

/-- R1: `renderCard` is total — for every LegalPatch, it returns some
    String. Immediate from Lean's type system; stated as a theorem so
    audit documents can cite it. -/
theorem r1_render_total (p : LegalPatch) : ∃ s : String, renderCard p = s :=
  ⟨renderCard p, rfl⟩

-- ══════════════════════════════════════════════════════════════════════
-- R2: Category-header injectivity
-- ══════════════════════════════════════════════════════════════════════

/-- R2: Distinct jural categories produce distinct header tokens. Decidable
    by exhaustive case analysis over the 7×7 grid — `simp_all` unfolds
    `categoryHeader` and resolves each case via `rfl` (diagonal) or by
    string-literal inequality (off-diagonal). -/
theorem r2_category_header_injective (c₁ c₂ : JuralCategory)
    (h : categoryHeader c₁ = categoryHeader c₂) : c₁ = c₂ := by
  cases c₁ <;> cases c₂ <;> simp_all [categoryHeader]

/-- R2b (contrapositive): Different categories render to different header
    tokens, so a rendered card uniquely identifies its patch's category. -/
theorem r2b_category_header_distinct (c₁ c₂ : JuralCategory) (h : c₁ ≠ c₂) :
    categoryHeader c₁ ≠ categoryHeader c₂ := by
  intro heq
  exact h (r2_category_header_injective c₁ c₂ heq)

-- ══════════════════════════════════════════════════════════════════════
-- R3: Determinism (purity)
-- ══════════════════════════════════════════════════════════════════════

/-- R3: `renderCard` is deterministic — same patch in, same string out.
    Reflexivity in Lean because every `def` is a pure function. Stated so
    it can be cited alongside the kernel K-theorems. -/
theorem r3_render_deterministic (p : LegalPatch) :
    renderCard p = renderCard p := rfl

/-- R3b: Two patches whose (category, hatId, id) agree produce the same
    card. The renderer reads ONLY those three fields, so other fields
    (timestamp, trustClass, etc.) cannot affect the output. -/
theorem r3b_render_depends_only_on_render_fields
    (p q : LegalPatch)
    (h_cat : p.category = q.category)
    (h_hat : p.hatId = q.hatId)
    (h_id  : p.id = q.id) :
    renderCard p = renderCard q := by
  simp [renderCard, h_cat, h_hat, h_id]

end Semantos.LegalCards

```
