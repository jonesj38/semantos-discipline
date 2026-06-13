---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/LegalCards/Types.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.361913+00:00
---

# proofs/lean/Semantos/LegalCards/Types.lean

```lean
-- Semantos Plane — Legal Card Types
--
-- Formal model of the render-layer patch envelope and the seven canonical
-- jural categories. Mirrors scripts/lib/legal-cards.ts with just enough
-- structure to state the rendering, merge, diff, and round-trip theorems.
--
-- Proof target:  scripts/lib/legal-cards.ts (LegalPatch, ObjectPatchCompat)
-- TS ref:        packages/semantos-sir/src/types.ts (JuralCategory, TrustClass)

namespace Semantos.LegalCards

-- ══════════════════════════════════════════════════════════════════════
-- The seven jural categories (SIR source of truth)
-- ══════════════════════════════════════════════════════════════════════

/-- The seven canonical jural categories. Mirrors the TypeScript enum at
    packages/semantos-sir/src/types.ts (JuralCategory). -/
inductive JuralCategory where
  | declaration
  | obligation
  | permission
  | prohibition
  | power
  | condition
  | transfer
  deriving Repr, DecidableEq, BEq

/-- Render-layer patch kinds. Mirrors LegalPatchKind in legal-cards.ts. -/
inductive PatchKind where
  | extraction
  | companion
  | manualOverride
  | rejection
  | stateTransition
  deriving Repr, DecidableEq, BEq

/-- Governance axis #1 — trust class. -/
inductive TrustClass where
  | cosmetic
  | interpretive
  | authoritative
  deriving Repr, DecidableEq, BEq

/-- Governance axis #2 — proof requirement. -/
inductive ProofRequirement where
  | noProof
  | attestation
  | formal
  deriving Repr, DecidableEq, BEq

-- ══════════════════════════════════════════════════════════════════════
-- Patch envelopes
-- ══════════════════════════════════════════════════════════════════════

/-- Render-layer patch. Minimised from legal-cards.ts LegalPatch: the full
    SIRNode is abstracted to the fields the theorems mention (category +
    trust tier). The nested SIR payload is modeled abstractly as `Unit`
    since no theorem here touches it. -/
structure LegalPatch where
  id          : String
  kind        : PatchKind
  hatId       : String
  timestamp   : Nat
  category    : JuralCategory
  trustClass  : TrustClass
  proofReq    : ProofRequirement
  companionOf : Option String := none
  targetId    : Option String := none  -- for rejection patches
  deriving Repr, DecidableEq, BEq

/-- Transport-layer envelope. Round-trip target for toObjectPatch /
    fromObjectPatch. ObjectPatchCompat in legal-cards.ts. -/
structure ObjectPatchCompat where
  id          : String
  wireKind    : String
  timestamp   : Nat
  facetId     : String
  legalKind   : PatchKind
  category    : JuralCategory
  trustClass  : TrustClass
  proofReq    : ProofRequirement
  companionOf : Option String := none
  targetId    : Option String := none
  deriving Repr, DecidableEq, BEq

/-- Map a render-layer kind to its transport wireKind. Matches
    KIND_TO_OBJECT_PATCH in legal-cards.ts. -/
def PatchKind.toWire : PatchKind → String
  | .extraction       => "extraction"
  | .companion        => "evidence_merge"
  | .manualOverride   => "manual_override"
  | .rejection        => "manual_override"
  | .stateTransition  => "state_transition"

end Semantos.LegalCards

```
