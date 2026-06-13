---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.444094+00:00
---

# cartridges/bsv-anchor-bundle/brain/src/index.ts

```ts
/**
 * BSV Anchor Bundle — public entry point.
 *
 * SCAFFOLD STATUS: re-exports the manifest + capabilities only. The
 * AnchorAdapter implementation, wallet protocol, payment + headers
 * code arrives via DLBA.1c (TS-side delegation rewire of
 * `core/protocol-types/src/adapters/bsv-anchor-adapter.ts`) +
 * DLBA.2/.3/.4 (Zig-side file lifts).
 *
 * See `docs/prd/D-LIFT-BSV-ANCHOR.md` for the full carve plan.
 */

export {
  BSV_ANCHOR_MANIFEST,
  BSV_ANCHOR_CAPABILITIES,
  BSV_ANCHOR_CAP_NAMES,
  BSV_ANCHOR_DOMAIN_FLAG_RANGE,
  type ExtensionManifest,
  type BsvAnchorCapability,
} from './manifest.js';

export {
  IdempotentBatchAnchorer,
  computeBatchId,
  type IdempotentBatchAnchorInput,
  type IdempotentBatchAnchorResult,
} from './idempotent-batch-anchorer.js';

export {
  AnchorHistoryChain,
  InMemoryAnchorHistoryStore,
  encodeAnchorHistoryCanonical,
  decodeAnchorHistoryCanonical,
  anchorHistoryRecordFromManifest,
  ANCHOR_HISTORY_MAGIC,
  ANCHOR_HISTORY_VERSION,
  STATUS_CODE,
  type AnchorAndRecordResult,
  type AnchorHistoryRecord,
  type AnchorHistoryStore,
} from './anchor-history-chain.js';

```
