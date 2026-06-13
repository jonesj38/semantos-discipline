---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/betting-engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.777011+00:00
---

# archive/apps-poker-agent/src/game-loop/betting-engine.ts

```ts
/**
 * Pure betting engine — mutation-by-return, no `this`, no
 * `Math.random`. Each function takes the current state + decision
 * and returns the patches.
 *
 * The legacy GameLoop's `placeBet` / `executeAction` mutated player
 * + table fields in place; the prompt-19 split lifts those into
 * pure transforms that return the deltas. Callers (the orchestrator)
 * apply the deltas to their atom state.
 */

import type {
  PlayerActionKind,
  PlayerDecision,
  SimplePlayer,
  SimpleTable,
} from './types';

export interface PlayerDelta {
  /** chips to subtract. */
  chipsDelta: number;
  /** currentBet to add. */
  currentBetDelta: number;
  folded?: boolean;
  allIn?: boolean;
  hasActed: boolean;
}

export interface TableDelta {
  potDelta: number;
  /** Only set on bet/raise/all-in that pushes the bar up. */
  newCurrentBet?: number;
  newMinRaise?: number;
  /** True if the action requires re-arming hasActed on others. */
  resetHasActedOnOthers: boolean;
}

export interface BetResult {
  /** sats actually moved (clamped to player.chips). */
  actual: number;
  player: PlayerDelta;
  table: { potDelta: number };
}

/**
 * Take `amount` from `player`'s chips into the pot. Clamped to the
 * player's available chips. Returns a fresh delta — no mutation.
 */
export function placeBet(player: SimplePlayer, amount: number): BetResult {
  const actual = Math.min(amount, player.chips);
  return {
    actual,
    player: {
      chipsDelta: -actual,
      currentBetDelta: actual,
      allIn: player.chips - actual === 0 ? true : undefined,
      hasActed: true,
    },
    table: { potDelta: actual },
  };
}

/**
 * Apply a player decision. Returns the player + table deltas the
 * caller should commit. `decision.action` strings match the legacy
 * GameLoop names: `'fold' | 'check' | 'call' | 'bet' | 'raise' | 'all-in'`.
 */
export function executeAction(
  player: SimplePlayer,
  table: SimpleTable,
  decision: PlayerDecision,
  bigBlind: number,
): { player: PlayerDelta; table: TableDelta } {
  switch (decision.action as PlayerActionKind) {
    case 'fold':
      return foldDelta();
    case 'check':
      return checkDelta();
    case 'call':
      return callDelta(player, table);
    case 'bet':
      return betDelta(player, decision.amount ?? bigBlind);
    case 'raise':
      return raiseDelta(player, table, decision.amount);
    case 'all-in':
      return allInDelta(player, table);
    default:
      // Unknown action — fold is the safe default, mirrors the
      // legacy fall-through behaviour.
      return foldDelta();
  }
}

// ── Per-action helpers (each tested in isolation) ────────────────

function foldDelta() {
  return {
    player: { chipsDelta: 0, currentBetDelta: 0, folded: true, hasActed: true },
    table: { potDelta: 0, resetHasActedOnOthers: false },
  };
}

function checkDelta() {
  return {
    player: { chipsDelta: 0, currentBetDelta: 0, hasActed: true },
    table: { potDelta: 0, resetHasActedOnOthers: false },
  };
}

function callDelta(player: SimplePlayer, table: SimpleTable) {
  const toCall = table.currentBet - player.currentBet;
  const result = placeBet(player, toCall);
  return {
    player: result.player,
    table: { potDelta: result.table.potDelta, resetHasActedOnOthers: false },
  };
}

function betDelta(player: SimplePlayer, amount: number) {
  const result = placeBet(player, amount);
  return {
    player: result.player,
    table: {
      potDelta: result.table.potDelta,
      newCurrentBet: player.currentBet + result.actual,
      newMinRaise: amount,
      resetHasActedOnOthers: true,
    },
  };
}

function raiseDelta(player: SimplePlayer, table: SimpleTable, amount?: number) {
  const totalAmount = amount ?? table.currentBet + table.minRaise;
  const toWager = totalAmount - player.currentBet;
  const result = placeBet(player, toWager);
  const newCurrentBet = player.currentBet + result.actual;
  return {
    player: result.player,
    table: {
      potDelta: result.table.potDelta,
      newCurrentBet,
      newMinRaise: Math.max(table.minRaise, totalAmount - table.currentBet),
      resetHasActedOnOthers: true,
    },
  };
}

function allInDelta(player: SimplePlayer, table: SimpleTable) {
  const result = placeBet(player, player.chips);
  const newCurrentBet = player.currentBet + result.actual;
  const reset = newCurrentBet > table.currentBet;
  return {
    player: result.player,
    table: {
      potDelta: result.table.potDelta,
      newCurrentBet: reset ? newCurrentBet : undefined,
      newMinRaise: reset
        ? Math.max(table.minRaise, newCurrentBet - table.currentBet)
        : undefined,
      resetHasActedOnOthers: reset,
    },
  };
}

```
