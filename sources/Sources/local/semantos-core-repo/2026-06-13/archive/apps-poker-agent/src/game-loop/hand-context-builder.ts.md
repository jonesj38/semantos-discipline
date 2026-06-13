---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/hand-context-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.779656+00:00
---

# archive/apps-poker-agent/src/game-loop/hand-context-builder.ts

```ts
/**
 * Pure builder for the per-decision Claude context.
 *
 * Extracted from the legacy `GameLoop.buildHandContext()` so the
 * shape can be tested without firing up the agent runtime. Reads
 * from the GameStateDB happen at the call site; this module just
 * stitches the shapes.
 */

import type { GameStateDB, HandContext } from '../game-state-db';

import type { GameLoopConfig, SimplePlayer, SimpleTable } from './types';

export interface BuildHandContextOptions {
  player: SimplePlayer;
  opponent: SimplePlayer;
  table: SimpleTable;
  config: GameLoopConfig;
  /** Agent name (matches what GameStateDB indexes by). */
  agentName: string;
  db?: GameStateDB;
}

/**
 * Read the persisted DB context (if available) and overlay the
 * current in-memory state. Mirrors the legacy field-by-field.
 */
export function buildHandContext(opts: BuildHandContextOptions): HandContext {
  const ctx = opts.db?.getCurrentHandContext(opts.config.gameId, opts.agentName) ?? null;

  const handCtx: HandContext = ctx ?? {
    handNumber: opts.table.handNumber,
    dealerSeat: opts.table.dealerIndex,
    myCards: [],
    communityCards: [],
    phase: opts.table.phase,
    pot: opts.table.pot,
    myChips: opts.player.chips,
    opponentChips: opts.opponent.chips,
    actions: [],
    legalActions: [],
  };

  handCtx.myCards = opts.player.holeCards.map((c) => c.label);
  handCtx.communityCards = opts.table.communityCards.map((c) => c.label);
  handCtx.pot = opts.table.pot;
  handCtx.myChips = opts.player.chips;
  handCtx.opponentChips = opts.opponent.chips;
  handCtx.legalActions = getLegalActions(opts.player, opts.table, opts.config);
  return handCtx;
}

/** Compute the legal-action menu shown to the agent. */
export function getLegalActions(
  player: SimplePlayer,
  table: SimpleTable,
  config: GameLoopConfig,
): string[] {
  const actions: string[] = ['fold'];
  const toCall = table.currentBet - player.currentBet;
  if (toCall === 0) {
    actions.push('check');
    actions.push(`bet (min ${config.bigBlind})`);
  } else {
    actions.push(`call ${toCall}`);
    const minRaise = table.currentBet + table.minRaise;
    if (player.chips + player.currentBet > table.currentBet) {
      actions.push(`raise (min ${minRaise})`);
    }
  }
  actions.push(`all-in ${player.chips}`);
  return actions;
}

```
