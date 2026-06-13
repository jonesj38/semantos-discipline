---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/chain-broadcast/chain-broadcast/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.519204+00:00
---

# packages/chain-broadcast/chain-broadcast/src/index.ts

```ts
/**
 * @semantos/chain-broadcast — on-chain anchoring services.
 *
 * Decomposition of the monolithic hackathon DirectBroadcastEngine into
 * reusable services any extension/app can compose:
 *
 *   - BeefStore            durable BEEF envelope persistence
 *   - CellTxBuilder        build + sign BSV txs from semantic cells
 *   - MapiBroadcaster      MAPI / ARC submission with retries + fallback
 *   - ChainTipManager      parent-UTXO dedup for fleet coordination
 *   - ChainBroadcaster     facade composing the above
 *
 * Ported incrementally; this barrel grows as each piece lands.
 */

export { BeefStore } from "./beef-store.js";
export type { BeefStoreConfig, BeefUtxo } from "./beef-store.js";

export { ChainTipManager } from "./chain-tip-manager.js";
export type {
  ChainTipManagerConfig,
  FundingUtxo,
} from "./chain-tip-manager.js";

export { MapiBroadcaster } from "./mapi-broadcaster.js";
export type {
  MapiBroadcasterConfig,
  BroadcastMode,
  BroadcastStats,
} from "./mapi-broadcaster.js";

export { CellTxBuilder, preimageHashFor } from "./cell-tx-builder.js";
export type {
  CellTxBuilderConfig,
  BuiltTx,
  BuiltPreSplit,
} from "./cell-tx-builder.js";

export { ChainBroadcaster } from "./chain-broadcaster.js";
export type {
  ChainBroadcasterConfig,
  ChainBroadcastStats,
} from "./chain-broadcaster.js";

```
