---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.767323+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/types.ts

```ts
/**
 * Public types for the poker-state-machine module split.
 *
 * Pinned identical to the legacy `poker-state-machine.ts` exports so
 * downstream consumers (`game-loop.ts`, `p2p-agent-runner.ts`) keep
 * compiling without edits.
 */

export type PokerPhase =
  | 'init'
  | 'preflop'
  | 'flop'
  | 'turn'
  | 'river'
  | 'showdown'
  | 'complete';

export interface HandStatePayload {
  gameId: string;
  handNumber: number;
  phase: PokerPhase;
  dealer: string;
  players: { name: string; chips: number; folded: boolean; allIn: boolean }[];
  pot: number;
  communityCards: string[];
  currentBet: number;
  actions: { player: string; action: string; amount: number; phase: string }[];
  shuffleCommit?: string;
  winner?: string;
  decidedBy?: 'fold' | 'showdown';
  /** In P2P mode: which player's key the output is locked to. */
  lockedTo?: string;
}

export interface AnchorResult {
  txid: string;
  eventType: string;
  isLinear: boolean;
  phase: PokerPhase;
  /** BEEF bytes for sending to the opponent. */
  beef?: number[];
  /** Vout of the CellToken output. */
  vout?: number;
  /** Locking script hex of the new CellToken. */
  lockingScript?: string;
  /** Cell version. */
  cellVersion?: number;
  /** Whether the 2PDA kernel validated this transition. */
  kernelValidated?: boolean;
  /** Opcode count from kernel execution. */
  kernelOpcodeCount?: number;
}

/** Tracks the live CellToken UTXO for the current hand. */
export interface LiveUtxo {
  txid: string;
  vout: number;
  satoshis: number;
  lockingScript: string;
  beef: number[] | string;
  version: number;
  cellBytes: Uint8Array;
  /** Public key (hex) the output is locked to. */
  lockedToKey: string;
}

/** Protocol derivation params used for every getPublicKey/createSignature call. */
export const CELLTOKEN_PROTOCOL: [number, string] = [2, 'semantos celltoken'];
export const CELLTOKEN_COUNTERPARTY = 'self';

```
