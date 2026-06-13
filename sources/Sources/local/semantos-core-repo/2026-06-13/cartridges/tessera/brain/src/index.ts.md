---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.637829+00:00
---

# cartridges/tessera/brain/src/index.ts

```ts
/**
 * Tessera — public entry point.
 *
 * SCAFFOLD STATUS (V0.2): re-exports the manifest + capabilities only.
 *
 * Subsequent V-rows populate the surface:
 *   - V0.4 (pre-loader)    — lexicon re-export (`src/lexicon.ts`)
 *   - V0.6 (pre-loader)    — Zig project at `zig/`
 *   - V0.3 (post-loader)   — twelve walker declarations under `src/walkers/`
 *   - V0.5 (post-loader)   — nine cell-type schemas under `src/object-types/`
 *                            and adapter consumption wiring under `src/adapters/`
 *
 * See `docs/prd/TESSERA-CARTRIDGE.md` §3 for the canonical directory
 * layout and `docs/canon/commissions/wave-tessera.md` §7 for the wave
 * manifest of deliverables.
 */

export {
  TESSERA_MANIFEST,
  TESSERA_CAPABILITIES,
  TESSERA_CAP_NAMES,
  TESSERA_DOMAIN_FLAG_RANGE,
  type ExtensionManifest,
  type TesseraCapability,
} from './manifest.js';

export {
  buildTesseraFieldTree,
  discloseTesseraField,
  verifyTesseraFieldDisclosure,
  computeTesseraFieldCommitments,
  tesseraSchemaFingerprint,
} from './field-tree-adapter.js';

export { type TesseraCellType } from './store-adapter.js';

export {
  TesseraKeyDerivation,
  tesseraDerivationSegment,
  type TesseraRole,
} from './key-derivation.js';

export {
  authoriseTesseraDisclosure,
  verifyAuthorisedTesseraDisclosure,
  buildFullAuthorisedTesseraDisclosure,
  type AuthoriseTesseraDisclosureInput,
  type VerifyAuthorisedTesseraDisclosureInput,
  type VerifyAuthorisedTesseraDisclosureResult,
  type DisclosureSigner,
} from './disclosure-authoriser.js';

```
