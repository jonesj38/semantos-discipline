---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/state-machine-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.768471+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/state-machine-facade.ts

```ts
/**
 * Thin orchestrator over the split modules.
 *
 * Public API matches the legacy `apps/poker-agent/src/poker-state-
 * machine.ts` exactly so consumers (`game-loop.ts`, `p2p-agent-
 * runner.ts`) keep compiling without edits. The legacy file becomes
 * a deprecation re-export.
 *
 * Heavy methods live in their own files:
 *   - `create-hand-flow.ts` → v1 token construction + broadcast
 *   - `transition-flow.ts`  → v(n) → v(n+1) spend + sign
 *   - `event-anchor.ts`     → OP_RETURN single + batch
 *   - `cell-builder.ts`     → pure cell bytes + version bump
 *   - `celltoken-signer.ts` → deferred-signing helpers
 *   - `p2p-key-manager.ts`  → atom-backed pubkey pair
 *   - `utxo-tracker.ts`     → atom-backed live-UTXO cache
 */

import type { WalletClient } from '../../../../core/protocol-types/src/wallet-client';

import { deriveOwnerId } from './cell-builder';
import type { BsvLazy } from './celltoken-signer';
import { runCreateHandToken } from './create-hand-flow';
import { anchorEvent, anchorEventBatch } from './event-anchor';
import {
  getKeyAtoms,
  getKeyID,
  getMyPubKey as readMyPubKey,
  getOpponentPubKey as readOppPubKey,
  initKeys,
} from './p2p-key-manager';
import { runTransition } from './transition-flow';
import {
  canSpendLiveUtxo,
  getLiveUtxo,
  setLiveUtxo,
  snapshotLiveUtxo,
} from './utxo-tracker';
import type { AnchorResult, HandStatePayload } from './types';

export interface PokerStateMachineOptions {
  verbose?: boolean;
  /** Delay after CellToken ops in ms. Default 1500. Set 0 for turbo. */
  settleDelayLinear?: number;
  /** Delay after OP_RETURN ops in ms. Default 300. Set 0 for turbo. */
  settleDelayEvent?: number;
}

export class PokerStateMachine {
  private readonly wallet: WalletClient;
  private verbose: boolean;
  private gameId: string = '';
  private ownerId: Uint8Array = new Uint8Array(16);
  private cellVersion: number = 0;
  private handTxids: AnchorResult[] = [];
  private bsv: (BsvLazy & { PublicKey: any }) | null = null;
  private settleDelayLinear: number;
  private settleDelayEvent: number;

  constructor(wallet: WalletClient, options?: PokerStateMachineOptions) {
    this.wallet = wallet;
    this.verbose = options?.verbose ?? true;
    this.settleDelayLinear = options?.settleDelayLinear ?? 1500;
    this.settleDelayEvent = options?.settleDelayEvent ?? 300;
  }

  // ── Public API ─────────────────────────────────────────────

  async init(gameId: string, opponentPubKey?: string): Promise<void> {
    this.gameId = gameId;
    this.ownerId = deriveOwnerId(gameId);
    const r = await initKeys(this.wallet, gameId, opponentPubKey);
    const mode = r.selfLock ? 'single-player (self-lock)' : 'P2P (alternating keys)';
    this.log('INIT', `Mode: ${mode}`);
    this.log('INIT', `My key:  ${r.myPubKeyHex.slice(0, 20)}... keyID=${r.keyID}`);
    if (!r.selfLock) {
      this.log('INIT', `Opp key: ${r.opponentPubKeyHex.slice(0, 20)}...`);
    }
  }

  async createHandToken(state: HandStatePayload, lockToKey?: string): Promise<AnchorResult | null> {
    this.handTxids = [];
    this.cellVersion = 1;
    setLiveUtxo(this.gameId, null);

    const bsv = await this.loadBsv();
    const anchor = await runCreateHandToken(
      {
        wallet: this.wallet,
        bsv,
        gameId: this.gameId,
        ownerId: this.ownerId,
        myPubKeyHex: this.getMyPubKey(),
        settleDelayMs: this.settleDelayLinear,
        log: this.bindLog(),
      },
      state,
      lockToKey,
    );
    if (anchor) this.handTxids.push(anchor);
    return anchor;
  }

  async transition(newState: HandStatePayload, lockNextTo?: string): Promise<AnchorResult | null> {
    this.cellVersion++;
    const bsv = await this.loadBsv();
    const result = await runTransition(
      {
        wallet: this.wallet,
        bsv,
        gameId: this.gameId,
        ownerId: this.ownerId,
        myPubKeyHex: this.getMyPubKey(),
        keyID: getKeyID(this.gameId),
        cellVersion: this.cellVersion,
        settleDelayMs: this.settleDelayLinear,
        log: this.bindLog(),
      },
      newState,
      lockNextTo,
    );
    if (!result) {
      // No-op (no live UTXO or wrong lock) — roll the version back.
      this.cellVersion--;
      return null;
    }
    this.cellVersion = result.newCellVersion;
    this.handTxids.push(result.anchor);
    return result.anchor;
  }

  acceptIncomingBeef(params: {
    beef: number[];
    txid: string;
    vout: number;
    lockingScript: string;
    cellVersion: number;
  }): void {
    this.cellVersion = params.cellVersion;
    setLiveUtxo(this.gameId, {
      txid: params.txid,
      vout: params.vout,
      satoshis: 1,
      lockingScript: params.lockingScript,
      beef: params.beef,
      version: params.cellVersion,
      cellBytes: new Uint8Array(0),
      lockedToKey: this.getMyPubKey(),
    });
    this.log('ACCEPT', `Ingested opponent's BEEF: ${params.txid.slice(0, 16)}... v${params.cellVersion} (locked to ME)`);
  }

  async endHand(finalState: HandStatePayload, lockNextTo?: string): Promise<AnchorResult | null> {
    const result = await this.transition({ ...finalState, phase: 'complete' }, lockNextTo);
    setLiveUtxo(this.gameId, null);
    return result;
  }

  async anchorEvent(eventType: string, data: Record<string, unknown>): Promise<AnchorResult | null> {
    const anchor = await anchorEvent(
      {
        wallet: this.wallet,
        settleDelayMs: this.settleDelayEvent,
        log: this.bindLog(),
      },
      eventType,
      data,
    );
    if (anchor) this.handTxids.push(anchor);
    return anchor;
  }

  async anchorEventBatch(
    events: { eventType: string; data: Record<string, unknown> }[],
  ): Promise<AnchorResult | null> {
    const anchor = await anchorEventBatch(
      {
        wallet: this.wallet,
        settleDelayMs: this.settleDelayEvent,
        log: this.bindLog(),
      },
      events,
    );
    if (anchor) this.handTxids.push(anchor);
    return anchor;
  }

  // ── Accessors ─────────────────────────────────────────────

  getHandTxids(): AnchorResult[] {
    return [...this.handTxids];
  }
  getCurrentStateTxid(): string | null {
    return getLiveUtxo(this.gameId)?.txid ?? null;
  }
  getMyPubKey(): string {
    return readMyPubKey(this.gameId);
  }
  getOpponentPubKey(): string {
    return readOppPubKey(this.gameId);
  }
  canISpend(): boolean {
    return canSpendLiveUtxo(this.gameId, this.getMyPubKey());
  }
  getLiveUtxo(): { txid: string; vout: number; lockedToKey: string; version: number } | null {
    return snapshotLiveUtxo(this.gameId);
  }

  /** Test utility — atoms scoped to a particular game. */
  static atomsForGame(gameId: string) {
    return getKeyAtoms(gameId);
  }

  // ── Internals ─────────────────────────────────────────────

  private async loadBsv(): Promise<BsvLazy & { PublicKey: any }> {
    if (!this.bsv) {
      this.bsv = (await import('@bsv/sdk')) as unknown as BsvLazy & { PublicKey: any };
    }
    return this.bsv;
  }

  private log(label: string, msg: string): void {
    if (this.verbose) {
      console.log(`\x1b[35m[2PDA:${label}]\x1b[0m ${msg}`);
    }
  }

  private bindLog() {
    return (label: string, msg: string) => this.log(label, msg);
  }
}

```
