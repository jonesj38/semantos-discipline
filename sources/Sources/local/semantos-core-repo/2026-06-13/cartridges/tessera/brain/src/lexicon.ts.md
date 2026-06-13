---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/src/lexicon.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.637551+00:00
---

# cartridges/tessera/brain/src/lexicon.ts

```ts
/**
 * Tessera-lexicon re-export.
 *
 * The canonical `TesseraLexicon` value lives in `@semantos/semantos-sir`
 * (alongside every other registered lexicon — Jural, ControlSystems,
 * CDM, BillsOfLading, ProjectManagement, PropertyManagement,
 * RiskAssessment, CircuitCommands, Calendar, Trades, BRAP). This module
 * re-exports it as a convenience for consumers who only pull in
 * `@semantos/tessera`.
 *
 * Mirrors the oddjobz / calendar-ext pattern.
 *
 * Lean spec: `proofs/lean/Semantos/Lexicons/Tessera.lean` —
 * `tesseraHeader_injective` discharges the substrate `headerInjective`
 * obligation (V5.7 — landed as `sorry` skeleton in V0.4, proof
 * completed in V5.7). Substrate theorems (M1-M4 merge, D1-D3 diff,
 * renderCard_*) apply at `Patch TesseraCategory` by specialisation.
 *
 * V0.4 deliverable per `docs/prd/TESSERA-CARTRIDGE.md` §3.4.
 */
export { TesseraLexicon, type TesseraCategory } from '@semantos/semantos-sir';

```
