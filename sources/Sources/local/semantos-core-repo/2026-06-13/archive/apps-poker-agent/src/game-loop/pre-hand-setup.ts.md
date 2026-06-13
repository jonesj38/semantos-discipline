---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/pre-hand-setup.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.778447+00:00
---

# archive/apps-poker-agent/src/game-loop/pre-hand-setup.ts

```ts
/**
 * Pre-hand setup — reset state, deal hole cards, post blinds, fire
 * the v1 CellToken anchor + the blind/deal OP_RETURN(s).
 */

import { createHash } from 'crypto';

import type { AnchorResult } from '../poker-state-machine';

import { recordEvent, recordLinear, type AnchorAccumulators } from './anchor-helpers';
import { deckCommitment, drawCards, newDeck, type Deck } from './deck-manager';
import { buildState, emitTx, placeBlind } from './state-payload-builder';
import { totalsByName } from './showdown';
import type {
  GameLoopConfig,
  HandResult,
  SimplePlayer,
  SimpleTable,
} from './types';

export interface PreHandSetupContext {
  config: GameLoopConfig;
  players: SimplePlayer[];
  table: SimpleTable;
  stateMachine: {
    createHandToken(state: any, lockToKey?: string): Promise<AnchorResult | null>;
    anchorEvent(eventType: string, data: Record<string, unknown>): Promise<AnchorResult | null>;
    anchorEventBatch(
      events: { eventType: string; data: Record<string, unknown> }[],
    ): Promise<AnchorResult | null>;
  } | null;
  recordChannelBlinds?: (
    sb: { agent: 'A' | 'B'; amount: number },
    bb: { agent: 'A' | 'B'; amount: number },
  ) => Promise<void>;
  log: (label: string, msg: string) => void;
  emit: (
    type: 'hand-start' | 'deal' | 'phase' | 'action' | 'tx' | 'hand-end' | 'game-over',
    data: Record<string, unknown>,
  ) => void;
}

export interface PreHandSetupResult {
  deck: Deck;
  shuffleHash: string;
  sbIdx: number;
  bbIdx: number;
}

/** Reset table + players, deal hole cards, post blinds. */
export function setupHand(ctx: PreHandSetupContext): PreHandSetupResult {
  ctx.table.handNumber++;
  ctx.table.pot = 0;
  ctx.table.currentBet = 0;
  ctx.table.minRaise = ctx.config.bigBlind;
  ctx.table.communityCards = [];
  ctx.table.phase = 'preflop';
  if (ctx.table.handNumber > 1) {
    ctx.table.dealerIndex = 1 - ctx.table.dealerIndex;
  }
  for (const p of ctx.players) {
    p.currentBet = 0;
    p.folded = false;
    p.allIn = false;
    p.hasActed = false;
    p.holeCards = [];
  }

  const sbIdx = ctx.table.dealerIndex;
  const bbIdx = 1 - sbIdx;
  const deck = newDeck();
  const shuffleHash = createHash('sha256')
    .update(deckCommitment(deck))
    .digest('hex')
    .slice(0, 16);
  for (const p of ctx.players) {
    p.holeCards = drawCards(deck, 2);
  }

  placeBlind(ctx.players[sbIdx], ctx.table, ctx.config.smallBlind);
  placeBlind(ctx.players[bbIdx], ctx.table, ctx.config.bigBlind);
  ctx.table.currentBet = ctx.config.bigBlind;
  ctx.table.activeIndex = sbIdx;
  return { deck, shuffleHash, sbIdx, bbIdx };
}

/** Fire the per-hand-start emit + db side-effects + initial anchors. */
export async function announceAndAnchorOpening(
  ctx: PreHandSetupContext,
  setup: PreHandSetupResult,
  accs: AnchorAccumulators,
  handActions: HandResult['actions'],
): Promise<void> {
  ctx.log('HAND', `#${ctx.table.handNumber} — Dealer: ${ctx.players[setup.sbIdx].name}`);
  ctx.emit('hand-start', {
    dealer: ctx.players[setup.sbIdx].name,
    players: totalsByName(ctx.players),
  });
  ctx.emit('deal', {
    players: ctx.players.map((p) => ({
      name: p.name,
      cards: p.holeCards.map((c) => c.label),
    })),
  });
  if (ctx.recordChannelBlinds) {
    try {
      await ctx.recordChannelBlinds(
        { agent: setup.sbIdx === 0 ? 'A' : 'B', amount: ctx.config.smallBlind },
        { agent: setup.sbIdx === 0 ? 'B' : 'A', amount: ctx.config.bigBlind },
      );
    } catch (err) {
      ctx.log('CHANNEL', `⚠ Blind tick failed: ${(err as Error).message}`);
    }
  }
  if (!ctx.stateMachine) return;
  const initState = buildState({
    config: ctx.config,
    players: ctx.players,
    table: ctx.table,
    phase: 'preflop',
    actions: handActions,
  });
  initState.shuffleCommit = setup.shuffleHash;
  const anchor = recordLinear(accs, await ctx.stateMachine.createHandToken(initState));
  if (anchor) emitTx({ log: ctx.log, emit: ctx.emit, anchor, label: 'hand birth', version: 1 });
  await anchorPreHandOpReturns(ctx, accs, setup.sbIdx, setup.bbIdx);
}

async function anchorPreHandOpReturns(
  ctx: PreHandSetupContext,
  accs: AnchorAccumulators,
  sbIdx: number,
  bbIdx: number,
): Promise<void> {
  if (!ctx.stateMachine) return;
  const sb = { player: ctx.players[sbIdx].name, amount: ctx.config.smallBlind };
  const bb = { player: ctx.players[bbIdx].name, amount: ctx.config.bigBlind };
  if (ctx.config.turbo) {
    const batchEvents: { eventType: string; data: Record<string, unknown> }[] = [
      {
        eventType: 'blind-post',
        data: {
          gameId: ctx.config.gameId,
          hand: ctx.table.handNumber,
          sb,
          bb,
          pot: ctx.table.pot,
        },
      },
    ];
    for (const p of ctx.players) {
      batchEvents.push({
        eventType: 'deal-hole',
        data: {
          gameId: ctx.config.gameId,
          hand: ctx.table.handNumber,
          player: p.name,
          cardHash: createHash('sha256')
            .update(p.holeCards.map((c) => c.label).join(','))
            .digest('hex')
            .slice(0, 16),
        },
      });
    }
    recordEvent(accs, await ctx.stateMachine.anchorEventBatch(batchEvents));
    return;
  }
  recordEvent(
    accs,
    await ctx.stateMachine.anchorEvent('blind-post', {
      gameId: ctx.config.gameId,
      hand: ctx.table.handNumber,
      sb,
      bb,
      pot: ctx.table.pot,
    }),
  );
  for (const p of ctx.players) {
    recordEvent(
      accs,
      await ctx.stateMachine.anchorEvent('deal-hole', {
        gameId: ctx.config.gameId,
        hand: ctx.table.handNumber,
        player: p.name,
        cardHash: createHash('sha256')
          .update(p.holeCards.map((c) => c.label).join(','))
          .digest('hex')
          .slice(0, 16),
      }),
    );
  }
}

```
