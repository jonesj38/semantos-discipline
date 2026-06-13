---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/LegalCards/RoundTrip.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.361633+00:00
---

# proofs/lean/Semantos/LegalCards/RoundTrip.lean

```lean
-- Semantos Plane — LegalPatch ↔ ObjectPatchCompat Round-Trip
--
-- Theorems:
--   RT1: `fromObjectPatch ∘ toObjectPatch = id` on LegalPatch
--   RT2: the transport envelope's `wireKind` is well-defined for every
--        LegalPatchKind
--   RT3: `facetId` on the wire receives `hatId` from the render layer
--        (transport compatibility during the facet → hat rename)
--
-- Proof target:  scripts/lib/legal-cards.ts (toObjectPatch, fromObjectPatch)

import Semantos.LegalCards.Types

namespace Semantos.LegalCards

-- ══════════════════════════════════════════════════════════════════════
-- Transport conversion functions
-- ══════════════════════════════════════════════════════════════════════

/-- Lower a LegalPatch into its transport envelope. Matches toObjectPatch
    in legal-cards.ts — fields that have no direct wire equivalent are
    stashed in the compat struct so fromObjectPatch can restore them. -/
def toObjectPatch (p : LegalPatch) : ObjectPatchCompat where
  id          := p.id
  wireKind    := p.kind.toWire
  timestamp   := p.timestamp
  facetId     := p.hatId
  legalKind   := p.kind
  category    := p.category
  trustClass  := p.trustClass
  proofReq    := p.proofReq
  companionOf := p.companionOf
  targetId    := p.targetId

/-- Raise a transport envelope back to a LegalPatch. -/
def fromObjectPatch (op : ObjectPatchCompat) : LegalPatch where
  id          := op.id
  kind        := op.legalKind
  hatId       := op.facetId
  timestamp   := op.timestamp
  category    := op.category
  trustClass  := op.trustClass
  proofReq    := op.proofReq
  companionOf := op.companionOf
  targetId    := op.targetId

-- ══════════════════════════════════════════════════════════════════════
-- RT1: Round-trip is the identity
-- ══════════════════════════════════════════════════════════════════════

/-- RT1: For every LegalPatch p, `fromObjectPatch (toObjectPatch p) = p`.
    The transport round-trip is lossless; every field is either restored
    directly or carried through an auxiliary slot on the compat envelope.
    This is the single strongest claim in the renderer/transport boundary:
    a curator's ratified patch on one machine reconstructs bit-for-bit on
    another after the bundle is transported. -/
theorem rt1_round_trip_identity (p : LegalPatch) :
    fromObjectPatch (toObjectPatch p) = p := by
  cases p
  rfl

-- ══════════════════════════════════════════════════════════════════════
-- RT2: Wire kind is well-defined
-- ══════════════════════════════════════════════════════════════════════

/-- RT2: Every LegalPatchKind maps to a non-empty wire-kind string. -/
theorem rt2_wire_kind_nonempty (k : PatchKind) :
    k.toWire ≠ "" := by
  cases k <;> decide

-- ══════════════════════════════════════════════════════════════════════
-- RT3: hatId flows to facetId on the wire
-- ══════════════════════════════════════════════════════════════════════

/-- RT3: The render-layer `hatId` becomes the transport `facetId`. This
    lemma documents the shim maintained during the facet → hat rename in
    the upstream SIR types — once the rename lands, `facetId` renames to
    `hatId` at the wire layer too and this lemma becomes rfl on both. -/
theorem rt3_hatid_to_facetid (p : LegalPatch) :
    (toObjectPatch p).facetId = p.hatId := by
  rfl

/-- RT3b: Round-trip preserves hatId (composes RT1 with RT3). -/
theorem rt3b_round_trip_preserves_hatid (p : LegalPatch) :
    (fromObjectPatch (toObjectPatch p)).hatId = p.hatId := by
  rw [rt1_round_trip_identity]

-- ══════════════════════════════════════════════════════════════════════
-- RT4: Category survives transport
-- ══════════════════════════════════════════════════════════════════════

/-- RT4: The jural category is preserved across the round-trip. This is
    load-bearing for the claim that a curator's ratified card, once
    transported and re-rendered, still displays the same jural relation. -/
theorem rt4_category_preserved (p : LegalPatch) :
    (fromObjectPatch (toObjectPatch p)).category = p.category := by
  rw [rt1_round_trip_identity]

end Semantos.LegalCards

```
