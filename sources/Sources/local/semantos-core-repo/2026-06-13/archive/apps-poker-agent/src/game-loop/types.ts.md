---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.777303+00:00
---

# archive/apps-poker-agent/src/game-loop/types.ts

```ts
/**
 * Shared types for the prompt-19 game-loop split.
 *
 * Pinned to the legacy `game-loop.ts` exports so consumers
 * (`p2p-agent-runner.ts`, the arena CLI, settlement) keep compiling
 * against the existing API surface.
 */

import type { PaymentChannelManager } from '../payment-channel';
import type { Card } from '../shared';

export type Phase =
  | 'preflop'
  | 'flop'
  | 'turn'
  | 'river'
  | 'showdown'
  | 'complete';

/** Card descriptor — alias for the shared `Card` so existing field
 * references (`{suit, rank, label}`) keep compiling unchanged. */
export type CardDescriptor = Card;

export interface SimplePlayer {
  id: string;
  name: string;
  chips: number;
  currentBet: number;
  folded: boolean;
  allIn: boolean;
  hasActed: boolean;
  holeCards: CardDescriptor[];
}

export interface SimpleTable {
  phase: Phase;
  pot: number;
  currentBet: number;
  minRaise: number;
  communityCards: CardDescriptor[];
  dealerIndex: number;
  activeIndex: number;
  handNumber: number;
}

export interface HandResult {
  handNumber: number;
  winner: string;
  potSize: number;
  actions: { player: string; action: string; amount: number; phase: string }[];
  txids: string[];
  /** LINEAR state-chain txids (CellToken transitions). */
  stateChain: string[];
}

export interface GameEvent {
  type:
    | 'hand-start'
    | 'deal'
    | 'phase'
    | 'action'
    | 'tx'
    | 'hand-end'
    | 'game-over';
  matchId?: number;
  gameId: string;
  handNumber: number;
  ts: number;
  data: Record<string, unknown>;
}

export type GameEventCallback = (event: GameEvent) => void;

export interface GameLoopConfig {
  gameId: string;
  smallBlind: number;
  bigBlind: number;
  startingChips: number;
  /** Max hands to play. 0 = until bust. */
  maxHands: number;
  /** Whether to anchor state transitions on-chain. */
  anchorOnChain: boolean;
  /** Delay between actions in ms (for UI/logging readability). */
  actionDelay: number;
  /** Log verbosity. */
  verbose: boolean;
  /** Turbo mode: zero settle delays, batch OP_RETURNs. */
  turbo: boolean;
  /** Lean mode: skip per-action OP_RETURNs, only CellTokens + summary. */
  lean: boolean;
  /** Claude model override. */
  model?: string;
  /** Optional match ID for multi-match arena mode. */
  matchId?: number;
  /** Event callback for live visualization. */
  onEvent?: GameEventCallback;
  /** Payment channel manager (real-sats mode). */
  channelManager?: PaymentChannelManager;
  /** Payment channel ID (set after channel is opened). */
  channelId?: string;
  /** Sats per chip (e.g., 1 chip = 1 sat). Default: 1 */
  satsPerChip?: number;
}

export const DEFAULT_GAME_CONFIG: GameLoopConfig = {
  gameId: `game-${Date.now()}`,
  smallBlind: 5,
  bigBlind: 10,
  startingChips: 1000,
  maxHands: 100,
  anchorOnChain: true,
  actionDelay: 500,
  verbose: true,
  turbo: false,
  lean: false,
};

export type PlayerActionKind =
  | 'fold'
  | 'check'
  | 'call'
  | 'bet'
  | 'raise'
  | 'all-in';

export interface PlayerDecision {
  action: PlayerActionKind | string;
  amount?: number;
}

```
