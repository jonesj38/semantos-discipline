---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast-engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.763540+00:00
---

# archive/apps-poker-agent/src/direct-broadcast-engine.ts

```ts
/**
 * @deprecated — use the split modules under
 * `apps/poker-agent/src/direct-broadcast/` instead.
 *
 * This file is the legacy single-file home for the wallet-bypass
 * broadcaster. Prompt 18 split it into per-responsibility modules:
 *
 *   - `local-keypair-manager.ts` — atom-backed keypair lifecycle
 *   - `utxo-pool-manager.ts`     — atom-backed pre-split pools
 *   - `funding-acquisition.ts`   — wait/ingest/pre-split flows
 *   - `celltoken-tx-builder.ts`  — pure CellToken create/transition
 *   - `op-return-builder.ts`     — 0-sat OP_RETURN + buildPokerCell
 *   - `arc-broadcaster.ts`       — ARC port wiring (single new ARC)
 *   - `tx-stats-collector.ts`    — event-bus + atom-backed stats
 *   - `direct-broadcast-engine.ts` — thin facade orchestrator
 *
 * Migration target imports:
 *
 *   import { DirectBroadcastEngine } from './direct-broadcast/';
 */

export {
  DirectBroadcastEngine,
  type BroadcastResult,
  type DirectBroadcastConfig,
  type FundingUtxo,
  type StreamStats,
} from './direct-broadcast/index';

```
