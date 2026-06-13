---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/phase-loop.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.777585+00:00
---

# archive/apps-poker-agent/src/game-loop/phase-loop.ts

```ts
/**
 * Per-phase walk: preflop → flop → turn → river. Calls
 * `runBettingRound` between board reveals; anchors v(n+1) state
 * transitions + community-card OP_RETURNs.
 */

import type { AgentRuntime } from '../agent-runtime';
import type { GameStateDB } from '../game-state-db';
import type { AnchorResult, HandStatePayload, PokerPhase } from '../poker-state-machine';

import { recordEvent, recordLinear, type AnchorAccumulators } from './anchor-helpers';
import { runBettingRound } from './betting-round-flow';
import { drawCard, drawCards, type Deck } from './deck-manager';
import type { PolicyValidator } from './policy-validator';
import { buildState, emitTx } from './state-payload-builder';
import { totalsByName } from './showdown';
import type {
  GameLoopConfig,
  HandResult,
  Phase,
  SimplePlayer,
  SimpleTable,
} from './types';

export interface PhaseLoopContext {
  config: GameLoopConfig;
  players: SimplePlayer[];
  table: SimpleTable;
  agents: AgentRuntime[];
  db: GameStateDB;
  validator: PolicyValidator;
  stateMachine: {
    transition(state: HandStatePayload, lockNextTo?: string): Promise<AnchorResult | null>;
    anchorEvent(eventType: string, data: Record<string, unknown>): Promise<AnchorResult | null>;
  } | null;
  accs: AnchorAccumulators;
  handActions: HandResult['actions'];
  currentHandId: number;
  recordChannelBet?: (
    fromAgent: 'A' | 'B',
    satsBet: number,
  ) => Promise<void>;
  log: (label: string, msg: string) => void;
  emit: (
    type: 'hand-start' | 'deal' | 'phase' | 'action' | 'tx' | 'hand-end' | 'game-over',
    data: Record<string, unknown>,
  ) => void;
}

/** Returns true if the hand ended via fold-out. */
export async function runPhaseLoop(
  ctx: PhaseLoopContext,
  deck: Deck,
): Promise<boolean> {
  let handOver = false;
  const phases: Phase[] = ['preflop', 'flop', 'turn', 'river'];
  for (const phase of phases) {
    if (handOver) break;
    if (phase === 'flop' || phase === 'turn' || phase === 'river') {
      await advanceBoard(ctx, deck, phase);
    }
    const result = await runBettingRound(
      {
        config: ctx.config,
        players: ctx.players,
        table: ctx.table,
        agents: ctx.agents,
        db: ctx.db,
        validator: ctx.validator,
        currentHandId: ctx.currentHandId,
        handActions: ctx.handActions,
        accs: ctx.accs,
        anchorEvent: async (eventType, data) =>
          ctx.stateMachine?.anchorEvent(eventType, {
            gameId: ctx.config.gameId,
            hand: ctx.table.handNumber,
            ...data,
          }) ?? null,
        recordChannelBet: ctx.recordChannelBet,
        emitAction: (data) => ctx.emit('action', data),
        log: ctx.log,
      },
      phase,
    );
    if (result.handOver) {
      handOver = true;
      ctx.emit('hand-end', {
        winner: ctx.players.find((p) => !p.folded)?.name,
        pot: ctx.table.pot,
        decidedBy: 'fold',
        players: totalsByName(ctx.players),
      });
    }
  }
  return handOver;
}

async function advanceBoard(
  ctx: PhaseLoopContext,
  deck: Deck,
  phase: 'flop' | 'turn' | 'river',
): Promise<void> {
  ctx.table.phase = phase;
  drawCard(deck); // burn
  const newCards = phase === 'flop' ? drawCards(deck, 3) : [drawCard(deck)];
  ctx.table.communityCards.push(...newCards);
  for (const p of ctx.players) {
    p.currentBet = 0;
    p.hasActed = false;
  }
  ctx.table.currentBet = 0;
  ctx.table.minRaise = ctx.config.bigBlind;
  ctx.table.activeIndex = 1 - ctx.table.dealerIndex;
  ctx.db.recordSnapshot(ctx.currentHandId, {
    phase,
    pot: ctx.table.pot,
    communityCards: ctx.table.communityCards.map((c) => c.label),
    activePlayers: ctx.players.filter((p) => !p.folded).length,
    currentBet: 0,
  });
  ctx.log(
    phase.toUpperCase(),
    `Board: ${ctx.table.communityCards.map((c) => c.label).join(' ')}`,
  );
  ctx.emit('phase', {
    phase,
    communityCards: ctx.table.communityCards.map((c) => c.label),
    pot: ctx.table.pot,
  });
  if (!ctx.stateMachine) return;
  const phaseState = buildState({
    config: ctx.config,
    players: ctx.players,
    table: ctx.table,
    phase: phase as PokerPhase,
    actions: ctx.handActions,
  });
  const anchor = recordLinear(ctx.accs, await ctx.stateMachine.transition(phaseState));
  if (anchor) emitTx({ log: ctx.log, emit: ctx.emit, anchor, label: phase, version: ctx.accs.stateChain.length });
  if (!ctx.config.lean) {
    recordEvent(
      ctx.accs,
      await ctx.stateMachine.anchorEvent('community-cards', {
        gameId: ctx.config.gameId,
        hand: ctx.table.handNumber,
        phase,
        cards: newCards.map((c) => c.label),
        board: ctx.table.communityCards.map((c) => c.label),
      }),
    );
  }
}

```
