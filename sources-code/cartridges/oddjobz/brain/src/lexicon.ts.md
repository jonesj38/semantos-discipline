---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/lexicon.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.473376+00:00
---

# cartridges/oddjobz/brain/src/lexicon.ts

```ts
/**
 * Trades-lexicon re-export.
 *
 * The canonical `TradesLexicon` value lives in `@semantos/semantos-sir`
 * (alongside every other registered lexicon — Jural, ControlSystems,
 * CDM, BillsOfLading, ProjectManagement, PropertyManagement,
 * RiskAssessment, CircuitCommands, Calendar, BRAP). This module
 * re-exports it as a convenience for consumers who only pull in
 * `@semantos/oddjobz`.
 *
 * Mirrors the calendar-ext pattern at
 * `extensions/calendar/src/lexicon/index.ts`.
 *
 * Lean spec: `proofs/lean/Semantos/Lexicons/Trades.lean` —
 * `tradesHeader_injective` discharges the substrate `headerInjective`
 * obligation; substrate theorems (M1-M4 merge, D1-D3 diff,
 * renderCard_*) apply at `Patch TradesCategory` by specialisation.
 *
 * D-O1 deliverable per `docs/design/ODDJOBZ-EXTENSION-PLAN.md` §O1.
 */
export { TradesLexicon, type TradesCategory } from '@semantos/semantos-sir';

```
