---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/p2p-state-payload.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.787302+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/p2p-state-payload.ts

```ts
/**
 * Pure HandStatePayload builder for the P2P runner.
 *
 * Mirrors `P2PAgentRunner.buildStatePayload()` byte-for-byte —
 * including the seat-aware ordering of the players array (seat 0
 * always appears first regardless of which side `me` is on).
 */

import type { HandStatePayload, PokerPhase } from '../poker-state-machine';

import type {
  P2PAgentConfig,
  PlayerState,
  TableState,
} from './types';

export interface BuildPayloadArgs {
  config: P2PAgentConfig;
  me: PlayerState;
  opponent: PlayerState;
  table: TableState;
  phase: PokerPhase;
}

export function buildStatePayload(args: BuildPayloadArgs): HandStatePayload {
  const players =
    args.config.seat === 0
      ? [args.me, args.opponent]
      : [args.opponent, args.me];
  return {
    gameId: args.config.gameId,
    handNumber: args.table.handNumber,
    phase: args.phase,
    dealer:
      args.table.dealerSeat === args.config.seat ? args.me.name : args.opponent.name,
    players: players.map((p) => ({
      name: p.name,
      chips: p.chips,
      folded: p.folded,
      allIn: p.allIn,
    })),
    pot: args.table.pot,
    communityCards: args.table.communityCards.map((c) => c.label),
    currentBet: args.table.currentBet,
    actions: [],
  };
}

```
