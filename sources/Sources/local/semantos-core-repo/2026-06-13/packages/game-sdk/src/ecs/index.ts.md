---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/ecs/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.528656+00:00
---

# packages/game-sdk/src/ecs/index.ts

```ts
/**
 * @semantos/game-sdk/ecs — bitECS integration for the game-sdk.
 *
 * Two-tier architecture:
 *
 *   Tier-1 (bitECS)      hot-loop working set, per-frame cost
 *   Tier-2 (cell-engine) authority layer, audit trail, linearity
 *
 * The bridge (`syncFromCell` / `syncToCell`) is the only place those tiers
 * meet. Game code mutates bitECS components, flags entities with the Dirty
 * tag, and lets `syncToCell` handle the tier boundary.
 *
 * See ./README.md for an end-to-end walkthrough.
 */

// Components (also the bitECS schema)
export {
  DEFAULT_CAPACITY,
  CellBacked,
  Dirty,
  Position,
  Velocity,
  Health,
  Owner,
  StateTag,
  TradeIntent,
  hashStateTag,
  shortOwnerId,
} from './components';

// World factory + sidecar helpers
export {
  type GameWorld,
  createGameWorld,
  registerCellBacked,
  getCellBackedEntity,
  setCellBackedEntity,
  stashTradeOffer,
  loadTradeOffer,
  clearTradeOffer,
  markDirty,
  drainDirty,
} from './world';

// Bridge
export { syncFromCell, syncToCell } from './bridge';

// Systems
export {
  tradeSystem,
  TRADE_PENDING,
  TRADE_ACCEPTED,
  TRADE_REJECTED,
} from './systems/trade-system';

```
