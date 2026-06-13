---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Substrate/Lexicon.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.367447+00:00
---

# proofs/lean/Semantos/Substrate/Lexicon.lean

```lean
-- Semantos Plane — Lexicon typeclass
--
-- A Lexicon is a named category type with an injective header-rendering
-- function. Every semantic-intent vocabulary (jural, control-systems,
-- clinical, trade-lifecycle, …) provides an instance and inherits the
-- substrate theorems automatically.

import Semantos.Substrate.Types

namespace Semantos.Substrate

/-- A lexicon: a category type together with a header function that is
    injective on distinct categories. The injectivity proof is part of
    the interface — it's what makes rendered cards unambiguously identify
    the patch's semantic intent. -/
class Lexicon (α : Type) where
  header : α → String
  headerInjective : ∀ c₁ c₂ : α, header c₁ = header c₂ → c₁ = c₂

/-- A rendered card is a fixed-shape structure. The production TypeScript
    renderer emits strings; this Lean model uses a struct so the
    "distinct category ⟹ distinct card" theorem is tractable without
    string-prefix lemmas. -/
structure RenderedCard where
  header  : String
  hatId   : String
  patchId : String
  deriving Repr, DecidableEq, BEq

/-- Render a patch to a card by dispatching the category through the
    lexicon's header function. Deterministic by construction. -/
def renderCard {α : Type} [Lexicon α] (p : Patch α) : RenderedCard where
  header  := Lexicon.header p.category
  hatId   := p.hatId
  patchId := p.id

-- ══════════════════════════════════════════════════════════════════════
-- Substrate-level render theorems (hold for every lexicon)
-- ══════════════════════════════════════════════════════════════════════

/-- Determinism: same patch, same card. -/
theorem renderCard_deterministic {α : Type} [Lexicon α] (p : Patch α) :
    renderCard p = renderCard p := rfl

/-- The renderer reads only (category, hatId, id). Patches that agree on
    those three fields render to the same card regardless of other
    fields (timestamp, kind, companionOf, targetId). -/
theorem renderCard_depends_only_on_render_fields {α : Type} [Lexicon α]
    (p q : Patch α)
    (h_cat : p.category = q.category)
    (h_hat : p.hatId = q.hatId)
    (h_id  : p.id = q.id) :
    renderCard p = renderCard q := by
  simp [renderCard, h_cat, h_hat, h_id]

/-- Category is load-bearing on the output: patches with distinct
    categories always render to distinct cards. Combines with each
    lexicon's `headerInjective` obligation. -/
theorem renderCard_distinguishes_categories {α : Type} [Lexicon α]
    (p q : Patch α) (h_cat : p.category ≠ q.category) :
    renderCard p ≠ renderCard q := by
  intro h
  apply h_cat
  apply Lexicon.headerInjective
  have h' := congrArg RenderedCard.header h
  simp only [renderCard] at h'
  exact h'

end Semantos.Substrate

```
