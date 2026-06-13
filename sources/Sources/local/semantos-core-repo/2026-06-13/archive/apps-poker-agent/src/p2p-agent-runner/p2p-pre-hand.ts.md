---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/p2p-pre-hand.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.786091+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/p2p-pre-hand.ts

```ts
/**
 * P2P per-hand setup: reset state, compute the deterministic deck,
 * post blinds, and create-or-receive the v1 CellToken.
 *
 * Both seats run this in parallel; only the dealer creates the v1
 * token, the other seat blocks on a `'new-hand'` control message.
 */

import { sendControl } from './beef-transceiver';
import { dealForP2P, makeDeckCursor, shuffleSeedFor } from './hand-shuffle';
import { placeBet } from './p2p-betting-engine';
import { buildStatePayload } from './p2p-state-payload';
import { awaitControl } from './beef-transceiver';
import type { P2PAgentConfig, PlayerState, TableState } from './types';
import type { PokerStateMachine } from '../poker-state-machine';
import type { Transport } from './transport-port';

export interface PreHandSetupArgs {
  config: P2PAgentConfig;
  me: PlayerState;
  opponent: PlayerState;
  table: TableState;
  stateMachine: PokerStateMachine;
  transport: Transport;
  log: (label: string, msg: string) => void;
  recordTx: (txid: string, type: string, detail: string) => void;
}

export interface PreHandSetupResult {
  deck: ReturnType<typeof dealForP2P>['deck'];
  draw: () => any;
  burn: () => void;
  iAmDealer: boolean;
  myKey: string;
  oppKey: string;
  /** TXIDs accumulated during setup (initial CellToken). */
  handTxids: string[];
  stateChain: string[];
}

export async function setupHand(args: PreHandSetupArgs): Promise<PreHandSetupResult> {
  resetTable(args.config, args.me, args.opponent, args.table);
  const deal = dealForP2P(args.config.gameId, args.table.handNumber);
  const cursor = makeDeckCursor(deal.deck, deal.deckIdx);
  args.me.holeCards = args.config.seat === 0 ? deal.seat0Cards : deal.seat1Cards;
  args.opponent.holeCards = args.config.seat === 0 ? deal.seat1Cards : deal.seat0Cards;

  const iAmDealer = args.table.dealerSeat === args.config.seat;
  const sbPlayer = iAmDealer ? args.me : args.opponent;
  const bbPlayer = iAmDealer ? args.opponent : args.me;
  placeBet(sbPlayer, args.table, args.config.smallBlind);
  placeBet(bbPlayer, args.table, args.config.bigBlind);
  args.table.currentBet = args.config.bigBlind;

  args.log('HAND', `#${args.table.handNumber} — ${iAmDealer ? 'I am dealer (SB)' : 'Opponent is dealer'}`);
  args.log('CARDS', `My hand: ${args.me.holeCards.map((c) => c.label).join(' ')}`);

  const myKey = args.stateMachine.getMyPubKey();
  const oppKey = args.stateMachine.getOpponentPubKey();
  const handTxids: string[] = [];
  const stateChain: string[] = [];

  if (iAmDealer) {
    const initState = buildStatePayload({
      config: args.config,
      me: args.me,
      opponent: args.opponent,
      table: args.table,
      phase: 'preflop',
    });
    const anchor = await args.stateMachine.createHandToken(initState, myKey);
    if (anchor) {
      stateChain.push(anchor.txid);
      handTxids.push(anchor.txid);
      args.recordTx(anchor.txid, 'CellToken', `hand birth (v1) locked→ME`);
      await sendControl(args.transport, 'new-hand', {
        handNumber: args.table.handNumber,
        txid: anchor.txid,
        beef: anchor.beef,
        vout: anchor.vout,
        lockingScript: anchor.lockingScript,
        cellVersion: anchor.cellVersion,
        lockedToKey: myKey,
        shuffleSeed: shuffleSeedFor(args.config.gameId, args.table.handNumber),
      });
    }
  } else {
    const newHandCtrl = await awaitControl(args.transport, 'new-hand', 60_000);
    const initTxid = newHandCtrl.payload.txid as string;
    stateChain.push(initTxid);
    handTxids.push(initTxid);
    args.log('RECV', `Hand CellToken v1: ${initTxid.slice(0, 16)}... locked to opponent (dealer acts first)`);
  }

  return {
    deck: deal.deck,
    draw: cursor.draw,
    burn: cursor.burn,
    iAmDealer,
    myKey,
    oppKey,
    handTxids,
    stateChain,
  };
}

function resetTable(
  config: P2PAgentConfig,
  me: PlayerState,
  opponent: PlayerState,
  table: TableState,
): void {
  table.handNumber++;
  table.pot = 0;
  table.currentBet = 0;
  table.minRaise = config.bigBlind;
  table.communityCards = [];
  table.phase = 'preflop';
  if (table.handNumber > 1) table.dealerSeat = 1 - table.dealerSeat;
  for (const p of [me, opponent]) {
    p.currentBet = 0;
    p.folded = false;
    p.allIn = false;
    p.hasActed = false;
    p.holeCards = [];
  }
}

```
