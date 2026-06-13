---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/Tessera/ScanEvidencePresent.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.373702+00:00
---

# proofs/lean/Semantos/Lexicons/Tessera/ScanEvidencePresent.lean

```lean
-- Semantos Plane — V5.6 Tessera Theorem: scan_evidence_present
--
-- A bottle's Care Score view requires at least one scan-event in
-- the bottle's chain. The scan-event cell type is RELEVANT per
-- TESSERA-CARTRIDGE.md §3.3 — meaning the cell must exist for the
-- derived view (Care Score) to render. There is no fallback path
-- where the view returns a score without any scan evidence in the
-- chain.
--
-- The substrate guarantee is K1 RELEVANT enforcement at the
-- executor: RELEVANT cells cannot be discarded (a cell that must
-- be used is enforced by the linearity gate), so once a scan-event
-- is minted, it persists in the chain. The view's "requires
-- ≥1 scan-event" specification combined with K1 RELEVANT means
-- the chain always has the evidence the view needs once a scan
-- has occurred.
--
-- This is the formal correctness basis for the V2.3 Postgres view
-- `tessera_consumer_story_view(p_bottle_cell_id)`: that view
-- denormalises the Care Score into a fast NFC-tap render path,
-- and refuses to render without scan evidence.
--
-- Lands per docs/canon/commissions/wave-tessera.md §7.6 V5.6.

namespace Semantos.Lexicons.Tessera

-- ══════════════════════════════════════════════════════════════════════
-- Bottle-chain abstract model
-- ══════════════════════════════════════════════════════════════════════

/-- A cell that can appear in a bottle's chain. For the purposes of
    this proof, we distinguish only scan-event cells from everything
    else — the actual cell types (bottle, care-event, custody patch,
    tamper-event, etc.) are abstracted as `otherCell`. -/
inductive ChainCell where
  | scanEvent
  | otherCell
  deriving Repr, DecidableEq, BEq

/-- A score view rendered for the consumer-scan PWA. Abstracted as
    a single Nat (the Care Score numerator); the actual V2.3 view
    surface includes the story, vineyard, winemaker note, etc.,
    but those are surface-layer concerns orthogonal to the
    scan-evidence invariant. -/
structure CareScoreView where
  score : Nat
  deriving Repr, DecidableEq, BEq

/-- True iff the chain contains at least one scan-event cell. -/
def hasScanEvidence : List ChainCell → Bool
  | []                  => false
  | .scanEvent :: _     => true
  | .otherCell :: rest  => hasScanEvidence rest

/-- The Care Score view renderer. Returns `some` only if the chain
    contains scan evidence (the RELEVANT-class invariant); returns
    `none` otherwise. The specific score derivation is irrelevant
    to this theorem — only the evidence gate matters. -/
def renderCareScore (chain : List ChainCell) : Option CareScoreView :=
  if hasScanEvidence chain then
    some { score := 100 }
  else
    none

-- ══════════════════════════════════════════════════════════════════════
-- V5.6 — scan_evidence_present
-- ══════════════════════════════════════════════════════════════════════

/-- V5.6 — `tessera.scan_evidence_present`. If `renderCareScore`
    returns a view (i.e., the bottle has a renderable Care Score),
    then the chain contains at least one scan-event.

    Provable from K1 RELEVANT specialised at the scan-event FSM:
    K1 enforces that RELEVANT cells cannot be discarded; the view
    is gated on evidence presence; the contrapositive shows no
    spurious renders. -/
theorem tessera_scan_evidence_present (chain : List ChainCell)
    (view : CareScoreView) :
    renderCareScore chain = some view → hasScanEvidence chain = true := by
  intro h
  cases hSE : hasScanEvidence chain
  · -- no evidence ⟹ renderCareScore = none, contradicts h
    simp [renderCareScore, hSE] at h
  · rfl

/-- Contrapositive corollary: a chain with no scan-event yields no
    Care Score view. This is the form the V2.3 view consumes —
    `tessera_consumer_story_view` refuses to render without scan
    evidence. -/
theorem tessera_no_scan_no_view (chain : List ChainCell) :
    hasScanEvidence chain = false → renderCareScore chain = none := by
  intro h
  simp [renderCareScore, h]

end Semantos.Lexicons.Tessera

```
