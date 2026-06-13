---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/game-loop-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.779931+00:00
---

# archive/apps-poker-agent/src/game-loop/game-loop-facade.ts

```ts
/**
 * Thin facade over the prompt-19 game-loop modules.
 *
 * Public API matches the legacy `apps/poker-agent/src/game-loop.ts`
 * exactly so consumers (`p2p-agent-runner.ts`, the arena CLI) keep
 * compiling unchanged. The legacy file becomes a deprecation
 * re-export.
 */

import type { AgentRuntime } from '../agent-runtime';
import type { GameStateDB } from '../game-state-db';
import type { ChannelInstance, PaymentChannelManager } from '../payment-channel';
import { PokerStateMachine } from '../poker-state-machine';
import type { DirectPokerStateMachine } from '../direct-poker-state-machine';
import type { WalletClient } from '../../../../core/protocol-types/src/wallet-client';

import { emitGameEvent, getGameEventBus } from './game-events';
import { playHand } from './hand-flow';
import { makePolicyValidator } from './policy-validator';
import {
  DEFAULT_GAME_CONFIG,
  type GameEvent,
  type GameLoopConfig,
  type HandResult,
  type SimplePlayer,
  type SimpleTable,
} from './types';

type AnyStateMachine = PokerStateMachine | DirectPokerStateMachine;

export class GameLoop {
  private config: GameLoopConfig;
  private db: GameStateDB;
  private agents: AgentRuntime[];
  private wallet: WalletClient | null;
  private stateMachine: AnyStateMachine | null = null;
  private players: SimplePlayer[];
  private table: SimpleTable;
  private totalTxCount = 0;
  private linearTxCount = 0;
  private eventTxCount = 0;
  private handResults: HandResult[] = [];
  private channelInstance: ChannelInstance | null = null;
  private validator = makePolicyValidator({ bigBlind: 0 });

  constructor(
    config: Partial<GameLoopConfig>,
    db: GameStateDB,
    agents: [AgentRuntime, AgentRuntime],
    wallet: WalletClient | null,
    injectedStateMachine?: AnyStateMachine,
  ) {
    this.config = { ...DEFAULT_GAME_CONFIG, ...config };
    this.db = db;
    this.agents = agents;
    this.wallet = wallet;
    if (injectedStateMachine) this.stateMachine = injectedStateMachine;
    this.validator = makePolicyValidator({ bigBlind: this.config.bigBlind });
    this.players = agents.map((agent, i) => ({
      id: `player-${i}`,
      name: agent.personality.name,
      chips: this.config.startingChips,
      currentBet: 0,
      folded: false,
      allIn: false,
      hasActed: false,
      holeCards: [],
    }));
    this.table = {
      phase: 'complete',
      pot: 0,
      currentBet: 0,
      minRaise: this.config.bigBlind,
      communityCards: [],
      dealerIndex: 0,
      activeIndex: 0,
      handNumber: 0,
    };
    if (this.config.onEvent) {
      getGameEventBus(this.config.gameId).on(this.config.onEvent);
    }
  }

  async run(): Promise<{ results: HandResult[]; totalTx: number }> {
    this.db.createSession(this.config.gameId, {
      smallBlind: this.config.smallBlind,
      bigBlind: this.config.bigBlind,
      startingChips: this.config.startingChips,
    });
    for (let i = 0; i < this.agents.length; i++) {
      const agent = this.agents[i];
      this.db.addPlayer(this.config.gameId, {
        playerId: this.players[i].id,
        agentName: agent.agentName,
        certId: agent.getIdentity().keys.certId,
        walletPubKey: agent.getIdentity().keys.walletPubKey,
        seat: i,
        startingChips: this.config.startingChips,
      });
    }

    if (this.stateMachine) {
      await this.stateMachine.init(this.config.gameId);
      this.log(
        '2PDA',
        `DirectBroadcast state machine — LINEAR CellToken transitions via ARC${
          this.config.turbo ? ' (TURBO)' : ''
        }`,
      );
    } else if (this.config.anchorOnChain && this.wallet) {
      this.stateMachine = new PokerStateMachine(this.wallet, {
        verbose: this.config.verbose,
        settleDelayLinear: this.config.turbo ? 0 : 1500,
        settleDelayEvent: this.config.turbo ? 0 : 300,
      });
      await this.stateMachine.init(this.config.gameId);
      this.log(
        '2PDA',
        `Wallet state machine — LINEAR CellToken transitions enabled${
          this.config.turbo ? ' (TURBO)' : ''
        }`,
      );
    }

    while (
      this.table.handNumber < this.config.maxHands &&
      this.players.every((p) => p.chips > 0)
    ) {
      await playHand({
        config: this.config,
        players: this.players,
        table: this.table,
        agents: this.agents,
        db: this.db,
        validator: this.validator,
        stateMachine: this.stateMachine,
        handResults: this.handResults,
        bumpLinear: () => {
          this.linearTxCount++;
          this.totalTxCount++;
        },
        bumpEvent: () => {
          this.eventTxCount++;
          this.totalTxCount++;
        },
        recordChannelBet: this.recordChannelBet(),
        recordChannelBlinds: this.recordChannelBlinds(),
        log: (label, msg) => this.log(label, msg),
        emit: (type, data) => this.emit(type, data),
      });
    }

    const winner =
      this.players[0].chips > this.players[1].chips
        ? this.players[0]
        : this.players[1];
    this.log('GAME OVER', `${winner.name} wins! (${winner.chips} chips)`);
    this.log(
      'STATS',
      `${this.table.handNumber} hands, ${this.totalTxCount} on-chain txns (${this.linearTxCount} LINEAR + ${this.eventTxCount} OP_RETURN)`,
    );

    let settlementTxid: string | undefined;
    if (this.config.channelManager && this.config.channelId) {
      try {
        const settlement = await this.config.channelManager.settleChannel(this.config.channelId);
        settlementTxid = settlement.txid;
        this.totalTxCount++;
        this.log('SETTLE', `Channel settled: ${settlement.txid.slice(0, 16)}...`);
        this.emit('tx', {
          txid: settlement.txid,
          kind: 'settlement',
          label: 'channel-settle',
          kernelValidated: false,
          kernelOpcodeCount: 0,
        });
      } catch (err) {
        this.log('SETTLE', `⚠ Channel settlement failed: ${(err as Error).message}`);
      }
    }

    this.emit('game-over', {
      winner: winner.name,
      hands: this.table.handNumber,
      totalTx: this.totalTxCount,
      players: this.players.map((p) => ({ name: p.name, chips: p.chips })),
      settlementTxid,
    });

    return { results: this.handResults, totalTx: this.totalTxCount };
  }

  private recordChannelBet() {
    if (!this.config.channelManager || !this.config.channelId) return undefined;
    const manager = this.config.channelManager;
    const channelId = this.config.channelId;
    return async (fromAgent: 'A' | 'B', satsBet: number) => {
      await manager.recordBet(channelId, fromAgent, satsBet);
    };
  }

  private recordChannelBlinds() {
    if (!this.config.channelManager || !this.config.channelId) return undefined;
    const manager = this.config.channelManager;
    const channelId = this.config.channelId;
    return async (
      sb: { agent: 'A' | 'B'; amount: number },
      bb: { agent: 'A' | 'B'; amount: number },
    ) => {
      const spc = this.config.satsPerChip ?? 1;
      await manager.recordBet(channelId, sb.agent, sb.amount * spc);
      await manager.recordBet(channelId, bb.agent, bb.amount * spc);
    };
  }

  private log(label: string, msg: string): void {
    if (this.config.verbose) {
      console.log(`\x1b[36m[${label}]\x1b[0m ${msg}`);
    }
  }

  private emit(type: GameEvent['type'], data: Record<string, unknown>): void {
    emitGameEvent({
      gameId: this.config.gameId,
      matchId: this.config.matchId,
      type,
      handNumber: this.table.handNumber,
      data,
    });
  }
}

```
