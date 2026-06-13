---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/p2p-hand-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.786955+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/p2p-hand-flow.ts

```ts
/**
 * Per-hand orchestrator. Delegates to:
 *   - `setupHand()` for state reset, deal, blinds, v1 anchor
 *   - `runP2PBettingLoop()` for the phase walk
 *   - inline showdown + complete-state anchor
 */

import type { AgentRuntime } from '../agent-runtime';
import type { PokerStateMachine } from '../poker-state-machine';

import { runP2PBettingLoop } from './p2p-betting-loop';
import { setupHand } from './p2p-pre-hand';
import { buildStatePayload } from './p2p-state-payload';
import type { Transport } from './transport-port';
import type {
  P2PAgentConfig,
  P2PHandResult,
  PlayerState,
  TableState,
} from './types';

export interface PlayHandArgs {
  config: P2PAgentConfig;
  me: PlayerState;
  opponent: PlayerState;
  table: TableState;
  agent: AgentRuntime;
  stateMachine: PokerStateMachine;
  transport: Transport;
  log: (label: string, msg: string) => void;
  recordTx: (txid: string, type: string, detail: string) => void;
}

export async function playHand(args: PlayHandArgs): Promise<P2PHandResult> {
  const setup = await setupHand({
    config: args.config,
    me: args.me,
    opponent: args.opponent,
    table: args.table,
    stateMachine: args.stateMachine,
    transport: args.transport,
    log: args.log,
    recordTx: args.recordTx,
  });

  const handOver = await runP2PBettingLoop({
    config: args.config,
    me: args.me,
    opponent: args.opponent,
    table: args.table,
    agent: args.agent,
    stateMachine: args.stateMachine,
    transport: args.transport,
    iAmDealer: setup.iAmDealer,
    myKey: setup.myKey,
    oppKey: setup.oppKey,
    draw: setup.draw,
    burn: setup.burn,
    handTxids: setup.handTxids,
    stateChain: setup.stateChain,
    log: args.log,
    recordTx: args.recordTx,
  });

  const winnerName = resolveWinner(args, handOver);
  const winner = winnerName === args.me.name ? args.me : args.opponent;
  winner.chips += args.table.pot;
  args.log('WIN', `${winnerName} wins ${args.table.pot} (${handOver ? 'fold' : 'showdown'})`);

  const finalState = buildStatePayload({
    config: args.config,
    me: args.me,
    opponent: args.opponent,
    table: args.table,
    phase: 'complete',
  });
  (finalState as { winner?: string }).winner = winnerName;
  (finalState as { decidedBy?: string }).decidedBy = handOver ? 'fold' : 'showdown';
  const endAnchor = await args.stateMachine.endHand(finalState);
  if (endAnchor) {
    setup.stateChain.push(endAnchor.txid);
    setup.handTxids.push(endAnchor.txid);
    args.recordTx(endAnchor.txid, 'CellToken', `complete (v${setup.stateChain.length})`);
  }

  args.log(
    'CHAIN',
    `Hand #${args.table.handNumber}: ${setup.handTxids.length} txs (${setup.stateChain.length} LINEAR + ${setup.handTxids.length - setup.stateChain.length} OP_RETURN)`,
  );
  if (setup.stateChain.length > 0) {
    args.log('CHAIN', `State: ${setup.stateChain.map((t) => t.slice(0, 10)).join(' → ')}`);
  }
  args.log('CHIPS', `${args.me.name}: ${args.me.chips} | ${args.opponent.name}: ${args.opponent.chips}`);

  return {
    handNumber: args.table.handNumber,
    winner: winnerName,
    potSize: args.table.pot,
    txids: setup.handTxids,
    stateChain: setup.stateChain,
  };
}

/** Legacy rank-sum showdown — pinned for byte parity with single-process runner. */
function resolveWinner(args: PlayHandArgs, handOver: boolean): string {
  if (handOver) {
    return args.me.folded ? args.opponent.name : args.me.name;
  }
  const myScore =
    args.me.holeCards.reduce((s, c) => s + c.rank, 0) +
    args.table.communityCards.reduce((s, c) => s + c.rank, 0);
  const opScore =
    args.opponent.holeCards.reduce((s, c) => s + c.rank, 0) +
    args.table.communityCards.reduce((s, c) => s + c.rank, 0);
  return myScore >= opScore ? args.me.name : args.opponent.name;
}

```
