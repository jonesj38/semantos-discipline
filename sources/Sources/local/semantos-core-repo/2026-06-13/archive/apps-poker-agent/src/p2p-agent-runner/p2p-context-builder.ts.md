---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/p2p-context-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.787859+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/p2p-context-builder.ts

```ts
/**
 * Pure HandContext + legalActions builder for the P2P runner.
 *
 * Mirrors the shape produced by the legacy
 * `P2PAgentRunner.buildHandContext()` so the agent's decide() call
 * sees an identical context object — the only difference vs the
 * single-process runner is that "me" + "opponent" are explicit
 * fields rather than indices into a players array.
 */

import type { HandContext } from '../game-state-db';

import type {
  P2PAgentConfig,
  PlayerState,
  TableState,
} from './types';

export interface BuildContextArgs {
  me: PlayerState;
  opponent: PlayerState;
  table: TableState;
  config: P2PAgentConfig;
}

export function buildHandContext(args: BuildContextArgs): HandContext {
  return {
    handNumber: args.table.handNumber,
    dealerSeat: args.table.dealerSeat,
    myCards: args.me.holeCards.map((c) => c.label),
    communityCards: args.table.communityCards.map((c) => c.label),
    phase: args.table.phase,
    pot: args.table.pot,
    myChips: args.me.chips,
    opponentChips: args.opponent.chips,
    actions: [],
    legalActions: getLegalActions(args.me, args.table, args.config),
  };
}

export function getLegalActions(
  me: PlayerState,
  table: TableState,
  config: P2PAgentConfig,
): string[] {
  const actions: string[] = ['fold'];
  const toCall = table.currentBet - me.currentBet;
  if (toCall === 0) {
    actions.push('check');
    actions.push(`bet (min ${config.bigBlind})`);
  } else {
    actions.push(`call ${toCall}`);
    if (me.chips + me.currentBet > table.currentBet) {
      actions.push(`raise (min ${table.currentBet + table.minRaise})`);
    }
  }
  actions.push(`all-in ${me.chips}`);
  return actions;
}

```
