---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Lexicons/Tessera.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.366829+00:00
---

# proofs/lean/Semantos/Lexicons/Tessera.lean

```lean
-- Semantos Plane — Tessera Lexicon
--
-- Care-chain provenance discourse vocabulary for the tessera cartridge.
-- Each category names a distinct discourse move that produces or
-- transitions a typed cell in the care-chain vertical — wine, premium
-- coffee, cold-chain pharma, art transit, and any future vertical
-- where the value of a delivered object depends on its handling
-- history. The categories track speech acts, not cells — same
-- convention as trades / project-management / jural / calendar / brap.
--
-- The thirteen categories trace a physical object's journey:
--
--   harvest         — origin: produces an AFFINE grape-lot
--                     (or analogue) cell
--   ferment         — primary fermentation event
--   rack            — racking / cellar transfer between barrels
--   blend           — blend transition consuming N barrels into one
--                     (K15 conservation: Σinput.amount = Σoutput.amount)
--   addition        — record an oenological / processing addition
--   bottle          — produce N LINEAR bottle cells from one barrel
--   label           — labelling / packaging act
--   custody-transfer — case / pallet / shipment custody handoff
--   care-event      — environmental reading accumulating against
--                     a shipment (AFFINE)
--   excursion       — out-of-spec event (threshold breach)
--   tamper-event    — single LINEAR transition `intact → broken`
--                     on a bottle's tamper-loop seal
--   scan            — consumer NFC scan; RELEVANT
--   tasting-note    — DEBUG class; read-only opaque-to-FSM annotation
--
-- Granularity rationale: harvest / ferment / rack / blend / addition /
-- bottle / label are pairs that look adjacent but carry different
-- capabilities (cap.tessera.{harvest, rack, blend-declare, bottle,
-- care-record}) and different linearity classes. Confusing them
-- breaks the Lean theorems V5.2–V5.6 (tamper_one_shot,
-- care_score_monotonic, blend_conservation, custody_linear,
-- scan_evidence_present). So they earn category-level status.
--
-- Proof obligation per lexicon (matches every other registered lexicon):
--   1. Define the category enum (inductive).
--   2. Provide the header function.
--   3. Prove header injectivity.
--   4. Register the `Lexicon` instance.
--
-- Once registered, the substrate theorems (M1-M4 merge, D1-D3 diff,
-- renderCard_*) apply at `Patch TesseraCategory` by specialisation —
-- no per-lexicon re-proof of those invariants is required.

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate

inductive TesseraCategory where
  | harvest
  | ferment
  | rack
  | blend
  | addition
  | bottle
  | label
  | custodyTransfer
  | careEvent
  | excursion
  | tamperEvent
  | scan
  | tastingNote
  deriving Repr, DecidableEq, BEq

def tesseraHeader : TesseraCategory → String
  | .harvest          => "TESSERA_HARVEST"
  | .ferment          => "TESSERA_FERMENT"
  | .rack             => "TESSERA_RACK"
  | .blend            => "TESSERA_BLEND"
  | .addition         => "TESSERA_ADDITION"
  | .bottle           => "TESSERA_BOTTLE"
  | .label            => "TESSERA_LABEL"
  | .custodyTransfer  => "TESSERA_CUSTODY_TRANSFER"
  | .careEvent        => "TESSERA_CARE_EVENT"
  | .excursion        => "TESSERA_EXCURSION"
  | .tamperEvent      => "TESSERA_TAMPER_EVENT"
  | .scan             => "TESSERA_SCAN"
  | .tastingNote      => "TESSERA_TASTING_NOTE"

-- V5.7 ritual obligation — analogue of `tradesHeader_injective`.
-- Discharged by exhaustive case analysis: each of the 13 × 13 = 169
-- category pairs either trivially reflexively equal or distinguished
-- by a literally-distinct header string. `simp_all` reduces the
-- positive cases and leaves the cross-pair string-inequality goals
-- which Lean's decidable string equality closes.
--
-- This proof lands `docs/canon/lexicons.yml` `tesseraHeader_injective`
-- status `pending → proven` and the A9 Tessera × D-lex matrix cell
-- ⚠ → ✓. Substrate theorems (renderCard_deterministic,
-- renderCard_depends_only_on_render_fields,
-- renderCard_distinguishes_categories) apply at `Patch TesseraCategory`
-- by specialisation — no per-lexicon re-proof required.
theorem tesseraHeader_injective : ∀ c₁ c₂ : TesseraCategory,
    tesseraHeader c₁ = tesseraHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [tesseraHeader]

instance : Lexicon TesseraCategory where
  header          := tesseraHeader
  headerInjective := tesseraHeader_injective

end Semantos.Lexicons

```
