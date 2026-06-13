---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/hand-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.778765+00:00
---

# archive/apps-poker-agent/src/game-loop/hand-flow.ts

```ts
/**
 * `playHand()` — the per-hand orchestrator. Heavy lifting delegated
 * to:
 *   - `pre-hand-setup.ts`  → deck/blinds/db init + v1 anchor
 *   - `phase-loop.ts`      → preflop/flop/turn/river walk
 *   - `post-hand-flow.ts`  → showdown + complete-state anchor + summary
 *
 * The facade owns mutable state (players + table); this function
 * mutates them in place to match legacy semantics.
 */

import type { AgentRuntime } from '../agent-runtime';
import type { GameStateDB } from '../game-state-db';
import type { AnchorResult, HandStatePayload } from '../poker-state-machine';

import type { AnchorAccumulators } from './anchor-helpers';
import { runPhaseLoop } from './phase-loop';
import { runShowdownAndComplete } from './post-hand-flow';
import {
  announceAndAnchorOpening,
  setupHand,
  type PreHandSetupContext,
} from './pre-hand-setup';
import type { PolicyValidator } from './policy-validator';
import type {
  GameLoopConfig,
  HandResult,
  SimplePlayer,
  SimpleTable,
} from './types';

type AnyStateMachine = {
  init(gameId: string, opponentPubKey?: string): Promise<void>;
  createHandToken(state: HandStatePayload, lockToKey?: string): Promise<AnchorResult | null>;
  transition(state: HandStatePayload, lockNextTo?: string): Promise<AnchorResult | null>;
  endHand(state: HandStatePayload, lockNextTo?: string): Promise<AnchorResult | null>;
  anchorEvent(eventType: string, data: Record<string, unknown>): Promise<AnchorResult | null>;
  anchorEventBatch(
    events: { eventType: string; data: Record<string, unknown> }[],
  ): Promise<AnchorResult | null>;
};

export interface PlayHandContext {
  config: GameLoopConfig;
  players: SimplePlayer[];
  table: SimpleTable;
  agents: AgentRuntime[];
  db: GameStateDB;
  validator: PolicyValidator;
  stateMachine: AnyStateMachine | null;
  handResults: HandResult[];
  bumpLinear: () => void;
  bumpEvent: () => void;
  recordChannelBet?: (
    fromAgent: 'A' | 'B',
    satsBet: number,
  ) => Promise<void>;
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

export async function playHand(ctx: PlayHandContext): Promise<void> {
  const handActions: HandResult['actions'] = [];
  const accs: AnchorAccumulators = {
    handTxids: [],
    stateChain: [],
    bumpLinear: ctx.bumpLinear,
    bumpEvent: ctx.bumpEvent,
  };

  const setupCtx: PreHandSetupContext = {
    config: ctx.config,
    players: ctx.players,
    table: ctx.table,
    stateMachine: ctx.stateMachine,
    recordChannelBlinds: ctx.recordChannelBlinds,
    log: ctx.log,
    emit: ctx.emit,
  };
  const setup = setupHand(setupCtx);

  const currentHandId = ctx.db.startHand(
    ctx.config.gameId,
    ctx.table.handNumber,
    ctx.table.dealerIndex,
  );
  ctx.db.recordSnapshot(currentHandId, {
    phase: 'preflop',
    pot: ctx.table.pot,
    communityCards: [],
    activePlayers: 2,
    currentBet: ctx.table.currentBet,
  });

  await announceAndAnchorOpening(setupCtx, setup, accs, handActions);

  const handOver = await runPhaseLoop(
    {
      config: ctx.config,
      players: ctx.players,
      table: ctx.table,
      agents: ctx.agents,
      db: ctx.db,
      validator: ctx.validator,
      stateMachine: ctx.stateMachine,
      accs,
      handActions,
      currentHandId,
      recordChannelBet: ctx.recordChannelBet,
      log: ctx.log,
      emit: ctx.emit,
    },
    setup.deck,
  );

  await runShowdownAndComplete(
    {
      config: ctx.config,
      players: ctx.players,
      table: ctx.table,
      stateMachine: ctx.stateMachine,
      db: ctx.db,
      accs,
      handActions,
      currentHandId,
      log: ctx.log,
      emit: ctx.emit,
    },
    handOver,
  );

  ctx.handResults.push({
    handNumber: ctx.table.handNumber,
    winner: ctx.players.find((p) => !p.folded)?.name ?? 'unknown',
    potSize: ctx.table.pot,
    actions: handActions,
    txids: accs.handTxids,
    stateChain: accs.stateChain,
  });
  ctx.log(
    'CHIPS',
    `${ctx.players[0].name}: ${ctx.players[0].chips} | ${ctx.players[1].name}: ${ctx.players[1].chips}`,
  );
}

```
