---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/p2p-agent-runner-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.789619+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/p2p-agent-runner-facade.ts

```ts
/**
 * Thin facade — public class shape matches the legacy
 * `P2PAgentRunner` exactly. Delegates to the split modules.
 */

import { AgentRuntime } from '../agent-runtime';
import { GameStateDB } from '../game-state-db';
import type { WalletClient } from '../../../../core/protocol-types/src/wallet-client';
import { PokerStateMachine } from '../poker-state-machine';

import { renderAuditLog } from './audit-log-renderer';
import { awaitControl } from './beef-transceiver';
import { bindDefaultP2PTransport } from './default-bindings';
import { enqueueMove, resetMessageQueueAtoms } from './message-queue';
import { playHand } from './p2p-hand-flow';
import { resetTurnAtoms } from './turn-coordinator';
import {
  transportPort,
  type Transport,
} from './transport-port';
import type {
  AuditLogEntry,
  P2PAgentConfig,
  P2PHandResult,
  PlayerState,
  TableState,
} from './types';

export class P2PAgentRunner {
  private config: P2PAgentConfig;
  private db: GameStateDB;
  private agent: AgentRuntime;
  private wallet: WalletClient;
  private stateMachine: PokerStateMachine;
  private transport: Transport;

  private me: PlayerState;
  private opponent: PlayerState;
  private table: TableState;
  private handResults: P2PHandResult[] = [];
  private allTxids: AuditLogEntry[] = [];

  constructor(
    config: P2PAgentConfig,
    db: GameStateDB,
    agent: AgentRuntime,
    wallet: WalletClient,
  ) {
    this.config = config;
    this.db = db;
    this.agent = agent;
    this.wallet = wallet;

    bindDefaultP2PTransport({ wallet });
    const factory = transportPort.get();
    this.transport = factory({
      gameId: config.gameId,
      opponentIdentityKey: config.opponentIdentityKey,
      verbose: config.verbose,
    });

    this.stateMachine = new PokerStateMachine(wallet, { verbose: config.verbose });

    const myName = agent.personality.name;
    const opponentName = config.seat === 0 ? 'Turtle' : 'Shark';
    this.me = freshPlayer(myName, config.startingChips);
    this.opponent = freshPlayer(opponentName, config.startingChips);
    this.table = {
      phase: 'complete',
      pot: 0,
      currentBet: 0,
      minRaise: config.bigBlind,
      communityCards: [],
      dealerSeat: 0,
      handNumber: 0,
    };
  }

  async run(): Promise<{ results: P2PHandResult[]; allTxids: AuditLogEntry[] }> {
    await this.stateMachine.init(this.config.gameId, this.config.opponentIdentityKey);
    await this.transport.init();
    this.log('READY', `${this.me.name} (seat ${this.config.seat}) — waiting for opponent...`);

    await this.transport.sendControl('handshake', {
      seat: this.config.seat,
      name: this.me.name,
      chips: this.config.startingChips,
    });

    await this.transport.startListening(
      async (move) => enqueueMove(this.config.gameId, move),
      async (ctrl) => this.log('CTRL', `${ctrl.type}: ${JSON.stringify(ctrl.payload)}`),
    );

    const opHandshake = await awaitControl(this.transport, 'handshake', 60_000);
    this.log('MATCHED', `Opponent: ${opHandshake.payload.name} (seat ${opHandshake.payload.seat})`);
    await this.transport.sendControl('handshake-ack', { ready: true });

    while (
      this.table.handNumber < this.config.maxHands &&
      this.me.chips > 0 &&
      this.opponent.chips > 0
    ) {
      const result = await playHand({
        config: this.config,
        me: this.me,
        opponent: this.opponent,
        table: this.table,
        agent: this.agent,
        stateMachine: this.stateMachine,
        transport: this.transport,
        log: (l, m) => this.log(l, m),
        recordTx: (txid, type, detail) => this.recordTx(txid, type, detail),
      });
      this.handResults.push(result);
    }

    await this.transport.sendControl('game-over', {
      winner: this.me.chips > this.opponent.chips ? this.me.name : this.opponent.name,
      myChips: this.me.chips,
    });
    this.log('GAME OVER', `${this.me.name}: ${this.me.chips} chips`);
    await this.transport.stopListening();

    return { results: this.handResults, allTxids: this.allTxids };
  }

  printAuditLog(): void {
    console.log('\n' + renderAuditLog(this.me.name, this.handResults, this.allTxids));
  }

  /** Test/teardown hook. */
  static resetAll(): void {
    resetTurnAtoms();
    resetMessageQueueAtoms();
  }

  private recordTx(txid: string, type: string, detail: string): void {
    this.allTxids.push({ txid, type, hand: this.table.handNumber, detail });
    this.log('TX', `${type === 'CellToken' ? '\x1b[32m✓' : '\x1b[33m✓'} ${type}\x1b[0m ${txid} \x1b[90m(${detail})\x1b[0m`);
    if (type === 'CellToken') {
      this.log('TX', `  https://whatsonchain.com/tx/${txid}`);
    }
  }

  private log(label: string, msg: string): void {
    if (this.config.verbose) {
      console.log(`\x1b[36m[${this.me.name}:${label}]\x1b[0m ${msg}`);
    }
  }
}

function freshPlayer(name: string, chips: number): PlayerState {
  return {
    name,
    chips,
    currentBet: 0,
    folded: false,
    allIn: false,
    hasActed: false,
    holeCards: [],
  };
}

```
