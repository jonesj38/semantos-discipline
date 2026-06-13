---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.766722+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/index.ts

```ts
/**
 * Poker state-machine module barrel — public surface for the prompt-17
 * split. Mirrors the legacy `poker-state-machine.ts` exports plus the
 * helper modules (cell-builder, signer, key-manager, anchor, tracker).
 */

export {
  PokerStateMachine,
  type PokerStateMachineOptions,
} from './state-machine-facade';

export {
  type AnchorResult,
  type HandStatePayload,
  type LiveUtxo,
  type PokerPhase,
  CELLTOKEN_COUNTERPARTY,
  CELLTOKEN_PROTOCOL,
} from './types';

export {
  POKER_HAND_TYPE_HASH,
  buildCell,
  bumpCellVersion,
  deriveOwnerId,
  hexToBytes,
  semanticPath,
  type BuildCellOptions,
  type BuildCellResult,
} from './cell-builder';

export {
  createPushDropUnlock,
  findOurInputIndex,
  linkSourceTransaction,
  signAndFinalize,
  type BsvLazy,
  type SignableInput,
  type SignableTx,
} from './celltoken-signer';

export {
  anchorEvent,
  anchorEventBatch,
  buildOpReturnScript,
  type EventAnchorOptions,
  type EventBatchEntry,
} from './event-anchor';

export {
  getKeyAtoms,
  getKeyID,
  getMyPubKey,
  getOpponentPubKey,
  initKeys,
  resetKeyAtoms,
  type InitKeysResult,
  type KeyAtoms,
} from './p2p-key-manager';

export {
  canSpendLiveUtxo,
  clearLiveUtxo,
  getLiveUtxo,
  getUtxoAtoms,
  resetUtxoAtoms,
  setLiveUtxo,
  snapshotLiveUtxo,
  type UtxoAtoms,
} from './utxo-tracker';

```
