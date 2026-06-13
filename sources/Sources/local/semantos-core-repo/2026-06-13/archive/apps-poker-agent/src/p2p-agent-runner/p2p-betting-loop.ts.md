---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/p2p-betting-loop.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.788426+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/p2p-betting-loop.ts

```ts
/**
 * P2P phase + betting walk. For each phase (preflop → river):
 *   - if not preflop: burn + reveal community + reset bets
 *   - run the betting round, alternating turns each iteration
 *
 * On my turn we agent-decide → execute → spend the v(n) UTXO and
 * lock v(n+1) to the opponent → send the move + BEEF over the
 * transport.
 *
 * On opponent's turn we wait for their move + BEEF, ingest it
 * (locking the UTXO back to me), and replay their action locally.
 */

import type { AgentRuntime } from '../agent-runtime';
import type { AnchorResult, PokerPhase, PokerStateMachine } from '../poker-state-machine';

import { sendMove } from './beef-transceiver';
import { waitForMove } from './message-queue';
import { buildHandContext } from './p2p-context-builder';
import { executeAction } from './p2p-betting-engine';
import { buildStatePayload } from './p2p-state-payload';
import type { P2PAgentConfig, PlayerState, TableState } from './types';
import type { Transport } from './transport-port';

export interface BettingLoopArgs {
  config: P2PAgentConfig;
  me: PlayerState;
  opponent: PlayerState;
  table: TableState;
  agent: AgentRuntime;
  stateMachine: PokerStateMachine;
  transport: Transport;
  iAmDealer: boolean;
  myKey: string;
  oppKey: string;
  draw: () => any;
  burn: () => void;
  handTxids: string[];
  stateChain: string[];
  log: (label: string, msg: string) => void;
  recordTx: (txid: string, type: string, detail: string) => void;
}

/** Returns true if the hand ended via fold-out. */
export async function runP2PBettingLoop(args: BettingLoopArgs): Promise<boolean> {
  const phases: PokerPhase[] = ['preflop', 'flop', 'turn', 'river'];
  let myTurn = args.iAmDealer;
  let handOver = false;

  for (const phase of phases) {
    if (handOver) break;
    if (phase !== 'preflop') {
      myTurn = await advanceBoard(args, phase as 'flop' | 'turn' | 'river', myTurn);
    }
    handOver = await runRound(args, phase, myTurn);
    if (!handOver) {
      myTurn = computeNextTurnHead(args.iAmDealer, phase);
    }
  }
  return handOver;
}

/** Advance board (burn + reveal); fire phase-transition CellToken if it's my turn. */
async function advanceBoard(
  args: BettingLoopArgs,
  phase: 'flop' | 'turn' | 'river',
  _prevMyTurn: boolean,
): Promise<boolean> {
  args.table.phase = phase;
  args.burn();
  if (phase === 'flop') {
    args.table.communityCards.push(args.draw(), args.draw(), args.draw());
  } else {
    args.table.communityCards.push(args.draw());
  }
  for (const p of [args.me, args.opponent]) {
    p.currentBet = 0;
    p.hasActed = false;
  }
  args.table.currentBet = 0;
  args.table.minRaise = args.config.bigBlind;
  const myTurn = !args.iAmDealer;
  args.log(phase.toUpperCase(), `Board: ${args.table.communityCards.map((c) => c.label).join(' ')}`);

  if (myTurn && args.stateMachine.canISpend()) {
    const phaseState = buildStatePayload({
      config: args.config,
      me: args.me,
      opponent: args.opponent,
      table: args.table,
      phase,
    });
    const anchor = await args.stateMachine.transition(phaseState, args.myKey);
    if (anchor) recordCellToken(args, anchor, `${phase} transition (v${args.stateChain.length + 1}) locked→ME`);
  }
  return myTurn;
}

/** One betting round; returns true if the hand ended via fold. */
async function runRound(args: BettingLoopArgs, phase: PokerPhase, startTurn: boolean): Promise<boolean> {
  let myTurn = startTurn;
  let roundDone = false;
  let safety = 20;
  while (!roundDone && safety-- > 0) {
    if (myTurn) {
      const folded = await actAndSendMove(args, phase);
      if (folded) return true;
    } else {
      const folded = await receiveAndApplyMove(args);
      if (folded) return true;
    }
    const meCanAct = !args.me.folded && !args.me.allIn && !args.me.hasActed;
    const opCanAct = !args.opponent.folded && !args.opponent.allIn && !args.opponent.hasActed;
    if (!meCanAct && !opCanAct) {
      roundDone = true;
    } else {
      myTurn = !myTurn;
    }
  }
  return false;
}

async function actAndSendMove(args: BettingLoopArgs, phase: PokerPhase): Promise<boolean> {
  const ctx = buildHandContext({
    me: args.me,
    opponent: args.opponent,
    table: args.table,
    config: args.config,
  });
  const decision = await args.agent.decide(args.config.gameId, ctx);
  executeAction(args.me, args.opponent, args.table, decision, args.config.bigBlind);
  args.log(args.me.name, `${decision.action}${decision.amount ? ' ' + decision.amount : ''} (${decision.reasoning})`);

  let moveAnchor: AnchorResult | null = null;
  if (args.stateMachine.canISpend()) {
    const moveState = buildStatePayload({
      config: args.config,
      me: args.me,
      opponent: args.opponent,
      table: args.table,
      phase,
    });
    moveState.actions = [
      { player: args.me.name, action: decision.action, amount: decision.amount ?? 0, phase },
    ];
    moveAnchor = await args.stateMachine.transition(moveState, args.oppKey);
    if (moveAnchor) recordCellToken(args, moveAnchor, `${args.me.name} ${decision.action} → locked→OPPONENT`);
  }

  const eventResult = await args.stateMachine.anchorEvent('action', {
    gameId: args.config.gameId,
    hand: args.table.handNumber,
    player: args.me.name,
    action: decision.action,
    amount: decision.amount ?? 0,
    phase,
    pot: args.table.pot,
  });
  if (eventResult) {
    args.handTxids.push(eventResult.txid);
    args.recordTx(eventResult.txid, 'OP_RETURN', `${args.me.name} ${decision.action}`);
  }

  await sendMove(args.transport, {
    handNumber: args.table.handNumber,
    phase,
    action: decision.action,
    amount: decision.amount,
    beef: moveAnchor?.beef ?? [],
    txid: moveAnchor?.txid ?? eventResult?.txid ?? '',
    vout: moveAnchor?.vout ?? 0,
    lockingScript: moveAnchor?.lockingScript ?? '',
    cellVersion: moveAnchor?.cellVersion ?? 0,
  });

  if (decision.action === 'fold') {
    args.me.folded = true;
    return true;
  }
  return false;
}

async function receiveAndApplyMove(args: BettingLoopArgs): Promise<boolean> {
  args.log('WAIT', `Waiting for ${args.opponent.name}...`);
  const move = await waitForMove(args.config.gameId);
  executeAction(args.opponent, args.me, args.table, { action: move.action, amount: move.amount }, args.config.bigBlind);
  args.log(args.opponent.name, `${move.action}${move.amount ? ' ' + move.amount : ''}`);

  if (move.txid) {
    args.handTxids.push(move.txid);
    args.stateChain.push(move.txid);
    args.recordTx(move.txid, 'CellToken', `${args.opponent.name} ${move.action} (received) → locked→ME`);
  }
  if (move.beef && move.beef.length > 0 && move.lockingScript) {
    args.stateMachine.acceptIncomingBeef({
      beef: move.beef,
      txid: move.txid,
      vout: move.vout,
      lockingScript: move.lockingScript,
      cellVersion: move.cellVersion,
    });
  }
  if (move.action === 'fold') {
    args.opponent.folded = true;
    return true;
  }
  return false;
}

function recordCellToken(args: BettingLoopArgs, anchor: AnchorResult, detail: string): void {
  args.stateChain.push(anchor.txid);
  args.handTxids.push(anchor.txid);
  args.recordTx(anchor.txid, 'CellToken', detail);
}

function computeNextTurnHead(iAmDealer: boolean, phase: PokerPhase): boolean {
  // Heads-up: post-flop the non-dealer acts first.
  if (phase === 'preflop') return !iAmDealer;
  return !iAmDealer;
}

```
