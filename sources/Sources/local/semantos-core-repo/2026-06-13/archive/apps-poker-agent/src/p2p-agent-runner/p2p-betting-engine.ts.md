---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/p2p-betting-engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.787588+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/p2p-betting-engine.ts

```ts
/**
 * Mutating betting helper for the P2P runner.
 *
 * The single-process `game-loop/betting-engine.ts` returns
 * immutable deltas; here the legacy P2P code mutates the
 * `me`/`opponent` references in place because the P2P runner
 * holds them as named fields rather than an array. We keep the
 * mutation pattern (matches legacy behaviour byte-for-byte) but
 * isolate it so the orchestrator stays focused on flow.
 */

import type { PlayerState, TableState } from './types';

export interface BettingDecision {
  action: string;
  amount?: number;
}

export function placeBet(player: PlayerState, table: TableState, amount: number): void {
  const actual = Math.min(amount, player.chips);
  player.chips -= actual;
  player.currentBet += actual;
  table.pot += actual;
  if (player.chips === 0) player.allIn = true;
}

export function executeAction(
  player: PlayerState,
  opponent: PlayerState,
  table: TableState,
  decision: BettingDecision,
  bigBlind: number,
): void {
  switch (decision.action) {
    case 'fold':
      player.folded = true;
      player.hasActed = true;
      break;
    case 'check':
      player.hasActed = true;
      break;
    case 'call': {
      const toCall = table.currentBet - player.currentBet;
      placeBet(player, table, toCall);
      player.hasActed = true;
      break;
    }
    case 'bet': {
      const amt = decision.amount ?? bigBlind;
      placeBet(player, table, amt);
      table.currentBet = player.currentBet;
      table.minRaise = amt;
      player.hasActed = true;
      if (!opponent.folded && !opponent.allIn) opponent.hasActed = false;
      break;
    }
    case 'raise': {
      const total = decision.amount ?? table.currentBet + table.minRaise;
      const toWager = total - player.currentBet;
      placeBet(player, table, toWager);
      table.currentBet = player.currentBet;
      table.minRaise = Math.max(table.minRaise, total - table.currentBet);
      player.hasActed = true;
      if (!opponent.folded && !opponent.allIn) opponent.hasActed = false;
      break;
    }
    case 'all-in': {
      placeBet(player, table, player.chips);
      if (player.currentBet > table.currentBet) {
        table.minRaise = Math.max(table.minRaise, player.currentBet - table.currentBet);
        table.currentBet = player.currentBet;
        if (!opponent.folded && !opponent.allIn) opponent.hasActed = false;
      }
      player.hasActed = true;
      break;
    }
  }
}

```
