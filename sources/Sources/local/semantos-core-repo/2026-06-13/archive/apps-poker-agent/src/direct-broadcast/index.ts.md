---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.781675+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/index.ts

```ts
/**
 * Direct-broadcast module barrel — re-exports the prompt-18 split.
 */

export {
  DEFAULT_ARC_URL,
  FEE_RATE,
  FIXED_CELL_FEE,
  MIN_FEE,
  MIN_USEFUL_SATS,
  type BroadcastEvent,
  type BroadcastResult,
  type DirectBroadcastConfig,
  type FundingUtxo,
  type StreamStats,
} from './types';

export {
  DirectBroadcastEngine,
} from './direct-broadcast-engine';

export {
  bindArcBroadcaster,
  getArcBroadcaster,
  makeArcBroadcaster,
} from './arc-broadcaster';

export {
  buildFanOutTx,
  estimateFanOutFee,
  ingestFundingTx,
  partitionFanOut,
  pollWhatsOnChainFunding,
  type PollFundingOptions,
  type PreSplitOptions,
  type PreSplitResult,
} from './funding-acquisition';

export {
  createCellTokenTx,
  transitionCellTokenTx,
  type BuildCreateOptions,
  type BuildTransitionOptions,
  type BuildResult,
} from './celltoken-tx-builder';

export {
  buildPokerCell,
  opReturnTx,
  POKER_HAND_TYPE_HASH,
  type BuildOpReturnOptions,
  type BuildOpReturnResult,
  type BuildPokerCellResult,
} from './op-return-builder';

export {
  getLocalKeyAtom,
  initLocalKeypair,
  requireLocalKeypair,
  resetLocalKeyAtoms,
  setLocalKeypair,
  type LocalKeyPair,
} from './local-keypair-manager';

export {
  addToPool,
  consumeUtxos,
  getPoolSizes,
  getUtxoPoolsAtom,
  initPools,
  pickFundingUtxo,
  recycleUtxo,
  resetUtxoPoolAtoms,
  returnUtxos,
  type PickFundingResult,
  type PoolMap,
} from './utxo-pool-manager';

export {
  attachStatsCollector,
  getDirectBroadcastEvents,
  getDirectBroadcastStatsAtom,
  resetDirectBroadcastStats,
  selectStats,
  type DirectBroadcastStats,
  type SelectedStats,
  type StatsCollectorHandle,
} from './tx-stats-collector';

```
