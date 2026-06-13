---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/betting-round-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.777875+00:00
---

# archive/apps-poker-agent/src/game-loop/betting-round-flow.ts

```ts
/**
 * The per-phase betting loop — extracted from `playHand()` so the
 * top-level orchestrator stays under the prompt-19 ≤250 LOC budget.
 *
 * The loop runs until every non-folded, non-all-in player has
 * acted, OR until one player is the only one left standing
 * (`fold-out`). The caller passes a context with everything the
 * loop needs to make agent decisions, validate against the kernel,
 * push deltas through the betting engine, and anchor each action
 * as an OP_RETURN.
 */

import type { AgentRuntime } from '../agent-runtime';
import type { GameStateDB } from '../game-state-db';
import type { AnchorResult } from '../poker-state-machine';

import { recordEvent, type AnchorAccumulators } from './anchor-helpers';
import { executeAction } from './betting-engine';
import { buildHandContext } from './hand-context-builder';
import type { PolicyValidator } from './policy-validator';
import type {
  GameLoopConfig,
  HandResult,
  Phase,
  SimplePlayer,
  SimpleTable,
} from './types';

export interface BettingRoundContext {
  config: GameLoopConfig;
  players: SimplePlayer[];
  table: SimpleTable;
  agents: AgentRuntime[];
  db: GameStateDB;
  validator: PolicyValidator;
  currentHandId: number;
  /** Accumulator for all per-hand actions. */
  handActions: HandResult['actions'];
  accs: AnchorAccumulators;
  /** Optional anchor + log hooks injected by the facade. */
  anchorEvent: (
    eventType: string,
    data: Record<string, unknown>,
  ) => Promise<AnchorResult | null>;
  recordChannelBet?: (
    fromAgent: 'A' | 'B',
    satsBet: number,
  ) => Promise<void>;
  emitAction: (data: Record<string, unknown>) => void;
  log: (label: string, msg: string) => void;
}

/**
 * Run a single betting round. Mutates `players` + `table` in place
 * (matching the legacy semantics) and returns `true` if the hand
 * ended via fold-out.
 */
export async function runBettingRound(
  ctx: BettingRoundContext,
  phase: Phase,
): Promise<{ handOver: boolean }> {
  let roundDone = false;
  let safety = 20;
  while (!roundDone && safety-- > 0) {
    const active = ctx.players[ctx.table.activeIndex];
    if (active.folded || active.allIn) {
      ctx.table.activeIndex = 1 - ctx.table.activeIndex;
      continue;
    }

    const opponent = ctx.players[1 - ctx.table.activeIndex];
    const agent = ctx.agents[ctx.table.activeIndex];
    const handCtx = buildHandContext({
      player: active,
      opponent,
      table: ctx.table,
      config: ctx.config,
      agentName: agent.agentName,
      db: ctx.db,
    });
    const decision = await agent.decide(ctx.config.gameId, handCtx);

    if (!ctx.validator.validate(active, ctx.table, decision)) {
      ctx.log(
        'POLICY',
        `\x1b[31m✗ ${active.name} ${decision.action} rejected by kernel policy — downgrading to fold\x1b[0m`,
      );
      decision.action = 'fold';
      decision.amount = undefined;
    }

    const chipsBefore = active.chips;
    applyDecision(active, ctx.table, decision, ctx.players, ctx.config.bigBlind);
    const chipsWagered = chipsBefore - active.chips;

    ctx.handActions.push({
      player: active.name,
      action: decision.action,
      amount: decision.amount ?? chipsWagered,
      phase,
    });

    const seq = ctx.db.recordAction(ctx.currentHandId, {
      playerId: active.id,
      actionType: decision.action,
      amount: decision.amount ?? 0,
      phase,
      chipsAfter: active.chips,
      potAfter: ctx.table.pot,
    });
    agent.advanceSeq(seq);

    ctx.log(
      `${active.name}`,
      `${decision.action}${decision.amount ? ' ' + decision.amount : ''} (${decision.reasoning})`,
    );

    if (ctx.recordChannelBet && chipsWagered > 0) {
      const satsPerChip = ctx.config.satsPerChip ?? 1;
      const satsBet = chipsWagered * satsPerChip;
      const fromAgent = ctx.table.activeIndex === 0 ? ('A' as const) : ('B' as const);
      try {
        await ctx.recordChannelBet(fromAgent, satsBet);
      } catch (err) {
        ctx.log('CHANNEL', `⚠ Tick failed: ${(err as Error).message}`);
      }
    }

    ctx.emitAction({
      player: active.name,
      action: decision.action,
      amount: decision.amount ?? 0,
      reasoning: decision.reasoning,
      phase,
      pot: ctx.table.pot,
      chips: active.chips,
    });

    if (!ctx.config.lean) {
      const actionTxid = recordEvent(
        ctx.accs,
        await ctx.anchorEvent('action', {
          player: active.name,
          action: decision.action,
          amount: decision.amount ?? 0,
          phase,
          pot: ctx.table.pot,
          chipsAfter: active.chips,
          reasoning: decision.reasoning.slice(0, 80),
          seq,
        }),
      );
      if (actionTxid) {
        ctx.log(
          'TX',
          `\x1b[33m✓ OP_RETURN\x1b[0m ${actionTxid.txid} \x1b[90m(${active.name} ${decision.action})\x1b[0m`,
        );
      }
    }

    if (ctx.players.some((p) => p.folded)) {
      const winner = ctx.players.find((p) => !p.folded)!;
      winner.chips += ctx.table.pot;
      ctx.db.endHand(ctx.currentHandId, winner.id, ctx.table.pot);
      ctx.log('WIN', `${winner.name} wins ${ctx.table.pot} (opponent folded)`);
      return { handOver: true };
    }

    const canAct = ctx.players.filter((p) => !p.folded && !p.allIn && !p.hasActed);
    if (canAct.length === 0) {
      roundDone = true;
    } else {
      ctx.table.activeIndex = 1 - ctx.table.activeIndex;
    }

    if (ctx.config.actionDelay > 0) {
      await new Promise((r) => setTimeout(r, ctx.config.actionDelay));
    }
  }
  return { handOver: false };
}

/**
 * Apply a betting decision: run the pure engine, mutate the
 * supplied `player` + `table`, and re-arm `hasActed` on others
 * when the engine signals a raise/bet/all-in that pushed the bar.
 */
function applyDecision(
  player: SimplePlayer,
  table: SimpleTable,
  decision: { action: string; amount?: number },
  players: SimplePlayer[],
  bigBlind: number,
): void {
  const { player: pd, table: td } = executeAction(player, table, decision, bigBlind);
  player.chips += pd.chipsDelta;
  player.currentBet += pd.currentBetDelta;
  if (pd.folded !== undefined) player.folded = pd.folded;
  if (pd.allIn !== undefined) player.allIn = pd.allIn;
  player.hasActed = pd.hasActed;
  table.pot += td.potDelta;
  if (td.newCurrentBet !== undefined) table.currentBet = td.newCurrentBet;
  if (td.newMinRaise !== undefined) table.minRaise = td.newMinRaise;
  if (td.resetHasActedOnOthers) {
    for (const p of players) {
      if (p !== player && !p.folded && !p.allIn) p.hasActed = false;
    }
  }
}

```
