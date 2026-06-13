---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.786669+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/types.ts

```ts
/**
 * Shared types for the prompt-20 p2p-agent-runner split.
 *
 * Pinned identical to the legacy `p2p-agent-runner.ts` exports so
 * downstream consumers (the arena CLI, scripts) keep compiling.
 */

import type { Card } from '../shared';

export interface P2PAgentConfig {
  gameId: string;
  /** My seat (0 or 1). */
  seat: 0 | 1;
  /** Opponent's wallet identity public key (hex, 33 bytes compressed). */
  opponentIdentityKey: string;
  smallBlind: number;
  bigBlind: number;
  startingChips: number;
  maxHands: number;
  verbose: boolean;
}

export interface PlayerState {
  name: string;
  chips: number;
  currentBet: number;
  folded: boolean;
  allIn: boolean;
  hasActed: boolean;
  holeCards: Card[];
}

export interface TableState {
  phase: 'preflop' | 'flop' | 'turn' | 'river' | 'showdown' | 'complete';
  pot: number;
  currentBet: number;
  minRaise: number;
  communityCards: Card[];
  dealerSeat: number;
  handNumber: number;
}

export interface P2PHandResult {
  handNumber: number;
  winner: string;
  potSize: number;
  txids: string[];
  stateChain: string[];
}

export interface AuditLogEntry {
  txid: string;
  type: string;
  hand: number;
  detail: string;
}

```
