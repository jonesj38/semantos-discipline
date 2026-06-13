---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/post-hand-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.779373+00:00
---

# archive/apps-poker-agent/src/game-loop/post-hand-flow.ts

```ts
/**
 * Post-betting hand flow: showdown reveal, complete-state anchor,
 * pot-award + hand-summary OP_RETURNs (with turbo batching).
 */

import type { AnchorResult, HandStatePayload } from '../poker-state-machine';

import { recordEvent, recordLinear, type AnchorAccumulators } from './anchor-helpers';
import { simpleShowdown, totalsByName } from './showdown';
import { buildState, emitTx } from './state-payload-builder';
import type {
  GameLoopConfig,
  HandResult,
  SimplePlayer,
  SimpleTable,
} from './types';

export interface PostHandFlowContext {
  config: GameLoopConfig;
  players: SimplePlayer[];
  table: SimpleTable;
  stateMachine: {
    endHand(state: HandStatePayload, lockNextTo?: string): Promise<AnchorResult | null>;
    anchorEvent(eventType: string, data: Record<string, unknown>): Promise<AnchorResult | null>;
    anchorEventBatch(
      events: { eventType: string; data: Record<string, unknown> }[],
    ): Promise<AnchorResult | null>;
  } | null;
  db: { endHand(handId: number, winnerId: string, pot: number): void };
  accs: AnchorAccumulators;
  handActions: HandResult['actions'];
  currentHandId: number;
  log: (label: string, msg: string) => void;
  emit: (
    type: 'hand-start' | 'deal' | 'phase' | 'action' | 'tx' | 'hand-end' | 'game-over',
    data: Record<string, unknown>,
  ) => void;
}

export async function runShowdownAndComplete(
  ctx: PostHandFlowContext,
  handOver: boolean,
): Promise<void> {
  if (!handOver) {
    ctx.table.phase = 'showdown';
    const winner = simpleShowdown(ctx.players, ctx.table.communityCards);
    winner.chips += ctx.table.pot;
    ctx.db.endHand(ctx.currentHandId, winner.id, ctx.table.pot);
    ctx.log('SHOWDOWN', `${winner.name} wins ${ctx.table.pot}`);
    ctx.emit('hand-end', {
      winner: winner.name,
      pot: ctx.table.pot,
      decidedBy: 'showdown',
      players: ctx.players.map((p) => ({
        name: p.name,
        chips: p.chips,
        cards: p.holeCards.map((c) => c.label),
      })),
      board: ctx.table.communityCards.map((c) => c.label),
    });
    if (ctx.stateMachine && !ctx.config.lean) {
      recordEvent(
        ctx.accs,
        await ctx.stateMachine.anchorEvent('showdown-reveal', {
          gameId: ctx.config.gameId,
          hand: ctx.table.handNumber,
          players: ctx.players.map((p) => ({
            name: p.name,
            cards: p.holeCards.map((c) => c.label),
            folded: p.folded,
          })),
          board: ctx.table.communityCards.map((c) => c.label),
        }),
      );
    }
  }
  if (!ctx.stateMachine) return;

  const winnerName = ctx.players.find((p) => !p.folded)?.name ?? 'unknown';
  const finalState = buildState({
    config: ctx.config,
    players: ctx.players,
    table: ctx.table,
    phase: 'complete',
    actions: ctx.handActions,
  });
  finalState.winner = winnerName;
  finalState.decidedBy = handOver ? 'fold' : 'showdown';
  const anchor = recordLinear(ctx.accs, await ctx.stateMachine.endHand(finalState));
  if (anchor) {
    emitTx({
      log: ctx.log,
      emit: ctx.emit,
      anchor,
      label: 'complete',
      version: ctx.accs.stateChain.length,
    });
  }

  const summary = {
    gameId: ctx.config.gameId,
    hand: ctx.table.handNumber,
    winner: winnerName,
    pot: ctx.table.pot,
    decidedBy: handOver ? ('fold' as const) : ('showdown' as const),
    actions: ctx.handActions.length,
    stateChain: ctx.accs.stateChain,
  };
  const award = {
    gameId: ctx.config.gameId,
    hand: ctx.table.handNumber,
    winner: winnerName,
    amount: ctx.table.pot,
    chips: totalsByName(ctx.players),
  };

  if (ctx.config.turbo) {
    recordEvent(
      ctx.accs,
      await ctx.stateMachine.anchorEventBatch([
        { eventType: 'pot-award', data: award },
        { eventType: 'hand-summary', data: summary },
      ]),
    );
  } else {
    recordEvent(ctx.accs, await ctx.stateMachine.anchorEvent('pot-award', award));
    recordEvent(ctx.accs, await ctx.stateMachine.anchorEvent('hand-summary', summary));
  }
}

```
