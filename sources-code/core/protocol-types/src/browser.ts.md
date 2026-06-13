---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/browser.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.849312+00:00
---

# core/protocol-types/src/browser.ts

```ts
/**
 * @semantos/protocol-types/browser
 *
 * Browser-safe subset of protocol-types. Exports only constants, core types,
 * and cell-header layout — everything the loom needs without pulling in
 * @semantos/cell-ops (which uses Node.js crypto and Buffer).
 *
 * Use this import path in browser code (loom, extensions):
 *   import { Linearity, MAGIC_1, ... } from '@semantos/protocol-types/browser'
 *
 * Use the full barrel (index.ts) in Node.js/Bun code (tests, CLI, build scripts).
 */

// ── Generated constants from constants.json ──
export {
  CELL_SIZE, HEADER_SIZE, PAYLOAD_SIZE,
  CONTINUATION_HEADER_SIZE, CONTINUATION_PAYLOAD_SIZE, VERSION,
  MAIN_STACK_CELLS, AUX_STACK_CELLS, MAIN_STACK_BYTES, AUX_STACK_BYTES,
  MAGIC_1, MAGIC_2, MAGIC_3, MAGIC_4,
  Linearity, CommercePhase, TaxonomyDimension, CellType,
  HeaderOffsets,
} from "./constants";

// ── Re-exports from @semantos/core barrel (pure types + enums, no Node.js deps) ──
export {
  SemanticType,
  isLinear, isAffine, isRelevant,
  type SemanticObject, type LinearObject, type AffineObject, type RelevantObject,
  type ConsumptionProof, type RevocationProof,
  CapabilityType,
  type CapabilityConstraints, type CapabilityToken,
  type DomainFlag,
  EDGE_CREATION, SIGNING, ENCRYPTION, MESSAGING, ATTESTATION,
  CHILD_CREATION, PERMISSION_GRANT, DATA_SOVEREIGNTY, SCHEMA_SIGNING, METERING,
  PLEXUS_WELL_KNOWN_MIN, PLEXUS_WELL_KNOWN_MAX,
  EXTENDED_STANDARD_MIN, EXTENDED_STANDARD_MAX,
  CLIENT_SOVEREIGN_MIN, CLIENT_SOVEREIGN_MAX,
  classifyFlag, isReserved, toProtocolId,
} from "@semantos/core";

// ── Cell-header layout (pure TypeScript, no Node.js deps) ──
export { CellHeaderLayout, serializeCellHeader, deserializeCellHeader, type FieldLayout, type CellHeader } from "./cell-header";

// ── Cell-engine-specific interfaces (pure types) ──
export type { BCAInput, BCAOutput, BCAVerifyInput, ScriptContext, ScriptResult, LinearityOperation, LinearityResult, CapabilityTokenRef } from "./interfaces";

// ── WASM contract (pure types) ──
export { REQUIRED_WASM_EXPORTS, type WasmExportName } from "./wasm-contract";

```
