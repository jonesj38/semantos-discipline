---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.761510+00:00
---

# archive/apps-poker-agent/src/payment-channel.ts

```ts
/**
 * PaymentChannelManager — 2-of-2 multisig payment channels for poker.
 *
 * Each poker match operates inside a payment channel:
 *   1. NEGOTIATE: Both agents' public keys are known (from discovery)
 *   2. FUND: Build a 2-of-2 multisig output from the engine's UTXO pool
 *   3. ACTIVE: Each bet is a "tick" — an HMAC-authenticated state update
 *   4. SETTLE: At game end, spend the multisig to pay winner/loser
 *
 * The channel state (balances per player) is tracked alongside the
 * CellToken game state. Each CellToken transition carries the channel
 * state in its payload, creating a dual-proof: the 2PDA kernel validates
 * the game state, and the HMAC tick proofs validate the payments.
 *
 * Cross-references:
 *   metering/src/channel-fsm.ts    — 8-state channel FSM
 *   metering/src/settlement.ts     — TickProof + SettlementBatch
 *   direct-broadcast-engine.ts     — BSV tx construction + ARC broadcast
 *
 * @deprecated for new code — use the reducer-backed facade in
 * `apps/poker-agent/src/payment-channel/` (`fund`, `extract`,
 * `bindConsumer`, `internalizeConsumer`, `internalizeProvider`,
 * `settle`, `close`) which routes through the prompt-13 reducer + the
 * prompt-14 ports + the prompt-15 effect atoms. The poker
 * `PaymentChannelManager` remains the runtime path for kernel-validated
 * tick proofs until a future poker-stack prompt migrates it onto the
 * new facade.
 */

import {
  PrivateKey,
  PublicKey,
  Transaction,
  P2PKH,
  Hash,
  Signature,
  TransactionSignature,
  LockingScript,
  Script,
} from '@bsv/sdk';
import { broadcasterPort } from './payment-channel/ports';
import {
  bindDefaultPaymentChannelPorts,
  makeArcBroadcaster,
} from './payment-channel/ports/default-bindings';
import type { Broadcaster } from './payment-channel/ports';
import {
  createChannel,
  fund,
  activate,
  tick as channelTick,
  requestClose,
  confirmClose,
  settle as channelSettle,
  type MeteringChannel,
  ChannelState,
} from '../../../packages/metering/src/channel-fsm';
import {
  computeTickProof,
  createSettlementBatch,
  type TickProof,
  type SettlementBatch,
} from '../../../packages/metering/src/settlement';
import type { DirectBroadcastEngine, FundingUtxo } from './direct-broadcast-engine';
import { CellToken } from '../../../core/protocol-types/src/cell-token';
import { CellStore } from '../../../core/protocol-types/src/cell-store';
import { MemoryAdapter } from '../../../core/protocol-types/src/adapters/memory-adapter';
import { Linearity, TaxonomyDimension, CommercePhase } from '../../../core/protocol-types/src/constants';
import { TransitionValidator, type CellEngineHandle } from '../../../core/protocol-types/src/transition-validator';
import { createHash } from 'crypto';

// ── Types ──

export interface ChannelConfig {
  /** Agent A's identity */
  agentA: { id: string; name: string; pubKey: PublicKey; privKey: PrivateKey };
  /** Agent B's identity */
  agentB: { id: string; name: string; pubKey: PublicKey; privKey: PrivateKey };
  /** ECDH shared secret (for HMAC tick proofs) */
  sharedSecret: Uint8Array;
  /** Total sats to lock in the channel */
  fundingSats: number;
  /** On-chain txid of the discovery match confirmation (for traceability) */
  matchTxid?: string;
  /** On-chain txids of agent discovery announcements */
  announceTxidA?: string;
  announceTxidB?: string;
  /** Stream ID for channel funding/settlement txs + OP_RETURNs */
  streamId: number;
  /** Stream ID for channel state CellTokens (should be the cell stream, not OP_RETURN stream) */
  cellStreamId?: number;
}

export interface ChannelInstance {
  /** Channel ID from the metering FSM */
  channelId: string;
  /** The metering FSM channel state */
  channel: MeteringChannel;
  /** Config for this channel */
  config: ChannelConfig;
  /** Funding transaction */
  fundingTxid: string;
  fundingVout: number;
  fundingTx: Transaction;
  /** Current balances (in sats) */
  balanceA: number;
  balanceB: number;
  /** All tick proofs accumulated during the game */
  tickProofs: TickProof[];
  /** Settlement transaction (set when channel is settled) */
  settlementTxid?: string;

  // ── CellToken state chain (kernel-validated) ──
  /** Live CellToken UTXO tracking channel state */
  cellTxid?: string;
  cellVout?: number;
  cellSourceTx?: Transaction;
  cellVersion: number;
  /** Previous cell bytes for kernel v1→v2 validation */
  prevCellBytes?: Uint8Array;
  prevContentHash?: Uint8Array;
  /** All CellToken transition txids (the verifiable state chain) */
  cellTransitions: { txid: string; version: number; prevStateHash: string; kernelValidated: boolean }[];
}

export interface ChannelEvent {
  type: 'channel-open' | 'channel-tick' | 'channel-settle' | 'channel-violation' | 'watchlist-hit';
  channelId: string;
  matchId?: number;
  txid?: string;
  data: Record<string, unknown>;
  ts: number;
}

/**
 * Per-offender watchlist state (stage-3).
 *
 * Each offender (identified by SHA256(pubKey)[:16]) gets their own LINEAR
 * CellToken state chain tracking their violation history. The 2PDA kernel
 * validates every v_n → v_{n+1} transition, so the watchlist is a real
 * kernel-enforced reputation substrate — not a database entry.
 */
export interface WatchlistInstance {
  /** 16-hex segment = SHA256(offenderPubKey)[:16] */
  offenderIdHex: string;
  /** Full compressed-hex pubkey of the offender */
  offenderPubKey: string;
  /** Human-readable name (for log output only) */
  offenderName: string;
  /** How many violations have been anchored against this offender */
  hitCount: number;
  /** Timestamp of first violation */
  firstSeenTs: number;
  /** Timestamp of most recent violation */
  lastSeenTs: number;
  /** Rolling tail of recent violation cell txids (max 10) */
  violationTxids: string[];
  /** Kernel reason from the most recent violation (truncated) */
  lastKernelReason: string;

  // ── CellToken state chain (kernel-validated) ──
  cellTxid: string;
  cellVout: number;
  cellSourceTx: Transaction;
  cellVersion: number;
  prevCellBytes: Uint8Array;
  prevContentHash: Uint8Array;
  cellTransitions: { txid: string; version: number; hitCount: number; kernelValidated: boolean }[];
}

/**
 * Adversarial tamper modes for stage-1 violation demos.
 *
 * Each mode corrupts a specific field of the candidate cell header so the
 * 2PDA kernel will reject the transition on a specific K-theorem path:
 *
 *   flip-linearity       → K1 (Linearity)           offset 16
 *   zero-owner           → K3 (Domain Isolation)    offset 62
 *   break-prev-hash      → K6 (State Continuity)    offset 128
 *   bump-version-double  → K6 (Monotonicity)        offset 20
 *   corrupt-magic        → K7 (Cell Immutability)   offset 0
 *
 * The tamper is applied *after* buildChannelCell runs, so the corruption
 * is purely at the wire-level header — the payload is untouched.
 */
export type TamperMode =
  | 'flip-linearity'
  | 'zero-owner'
  | 'break-prev-hash'
  | 'bump-version-double'
  | 'corrupt-magic';

/**
 * Thrown by recordBet() when a candidate state transition fails kernel
 * validation. Callers (game loop) can catch this to forfeit the hand,
 * or simply log and continue. The violation has already been anchored
 * on-chain as an OP_RETURN marker before the throw.
 */
export class ChannelViolationError extends Error {
  readonly name = 'ChannelViolationError';
  constructor(
    public readonly kernelReason: string,
    public readonly tamperMode: TamperMode | undefined,
    public readonly channelId: string,
    public readonly violationTxid?: string,
  ) {
    super(
      `Channel ${channelId} violation${tamperMode ? ` (tamper=${tamperMode})` : ''}: ${kernelReason}`,
    );
  }
}

// ── Manager ──

/** Semantic type hash for channel state cells */
const CHANNEL_STATE_TYPE_HASH = createHash('sha256').update('semantos/poker/channel-state/v1').digest();

/**
 * Semantic type hash for channel violation cells (stage-2).
 *
 * Violation cells are broadcast as AFFINE CellTokens — they may be consumed
 * at most once (e.g. by a future reputation roll-up), but unlike LINEAR state
 * cells they don't *have* to be. The ownerId is SHA256(offenderPubKey)[:16],
 * so every offender has their own domain in the cell-space and all their
 * violations are enumerable by owner via the 2PDA kernel.
 */
const CHANNEL_VIOLATION_TYPE_HASH = createHash('sha256').update('semantos/poker/violation/v1').digest();

/**
 * Semantic type hash for per-offender watchlist cells (stage-3).
 *
 * Watchlist cells are LINEAR CellTokens (one per offender). Each violation
 * cell anchor triggers a watchlist transition: v_n → v_{n+1}, incrementing
 * the offender's hit count. The 2PDA kernel validates every transition, so
 * an offender's violation history becomes a kernel-enforced, publicly
 * verifiable state chain — the on-chain reputation primitive.
 *
 * Taxonomy: dimension=INSTRUMENT (it's a gating tool, not a process step),
 * phase=ACTION (each hit is an active state update).
 */
const CHANNEL_WATCHLIST_TYPE_HASH = createHash('sha256').update('semantos/poker/watchlist/v1').digest();

export class PaymentChannelManager {
  private engine: DirectBroadcastEngine;
  private broadcaster: Broadcaster;
  private channels: Map<string, ChannelInstance> = new Map();
  private verbose: boolean;

  /** 2PDA kernel validator for channel state CellTokens */
  private validator: TransitionValidator | null = null;
  private kernelLoaded = false;

  /** Per-offender watchlists — keyed by SHA256(offenderPubKey)[:16] hex. */
  private watchlists: Map<string, WatchlistInstance> = new Map();

  /** Optional observer for ChannelEvents (dashboards, loggers, red-team consoles). */
  private onChannelEvent?: (event: ChannelEvent) => void;

  /** Stats */
  totalChannelsOpened = 0;
  totalChannelsSettled = 0;
  totalSatsTransferred = 0;
  totalTicks = 0;
  // Channel state chain kernel checks (create + transition + violation-detect)
  totalKernelValidations = 0;
  totalKernelFailures = 0;
  // Adversarial stats
  totalViolationsCaught = 0;   // kernel caught a tamper (rejected state transition)
  totalViolationsAnchored = 0; // violation cells successfully broadcast on-chain
  // Watchlist state chain kernel checks
  totalWatchlistValidations = 0;
  totalWatchlistFailures = 0;
  totalWatchlistHits = 0;      // recordWatchlistHit() calls that committed

  /**
   * Scheduled tamper injections. Keyed by channelId → list of trigger entries.
   * Each entry fires at most once, when recordBet() is called on the channel
   * and the candidate tick number matches. Used for deterministic red-team demos.
   */
  private tamperSchedule: Map<string, { tick: number; mode: TamperMode; fired: boolean }[]> = new Map();

  constructor(
    engine: DirectBroadcastEngine,
    arcUrl: string = 'https://arc.gorillapool.io',
    verbose = true,
    onChannelEvent?: (event: ChannelEvent) => void,
  ) {
    this.engine = engine;
    // Wire ARC through the broadcaster port so tests bind in-memory
    // doubles without a network. If a caller already bound the port
    // we honour it; otherwise fall back to the legacy ARC URL.
    bindDefaultPaymentChannelPorts({ arcUrl });
    this.broadcaster = broadcasterPort.isBound()
      ? broadcasterPort.get()
      : makeArcBroadcaster(arcUrl);
    this.verbose = verbose;
    this.onChannelEvent = onChannelEvent;
  }

  /**
   * Install or replace the ChannelEvent observer after construction.
   * Useful when the consumer (e.g. the arena dashboard) is set up after
   * the manager but before any channels open.
   */
  setChannelEventHandler(handler: (event: ChannelEvent) => void): void {
    this.onChannelEvent = handler;
  }

  /**
   * Emit a ChannelEvent to the installed observer (if any). Errors in the
   * observer are swallowed so a broken dashboard never kills the arena.
   */
  private emit(
    type: ChannelEvent['type'],
    channelId: string,
    data: Record<string, unknown>,
    opts: { matchId?: number; txid?: string } = {},
  ): void {
    if (!this.onChannelEvent) return;
    try {
      this.onChannelEvent({
        type,
        channelId,
        matchId: opts.matchId,
        txid: opts.txid,
        data,
        ts: Date.now(),
      });
    } catch (err: any) {
      // Observer bugs must never break gameplay.
      if (this.verbose) {
        this.log('EVENT', `⚠ onChannelEvent observer threw: ${err.message}`);
      }
    }
  }

  /**
   * Schedule a deliberate tamper injection on a specific channel + tick.
   *
   * When recordBet() is next called on this channel with `candidateTick === tick`,
   * it will corrupt the candidate cell header per `mode`. The 2PDA kernel will
   * reject the transition, a violation marker will be anchored on-chain, and
   * recordBet() will throw ChannelViolationError. The entry fires once and is
   * marked `fired: true` — it will not re-trigger.
   *
   * Used by the arena CLI for deterministic red-team demos.
   */
  scheduleTamper(channelId: string, tick: number, mode: TamperMode): void {
    const arr = this.tamperSchedule.get(channelId) ?? [];
    arr.push({ tick, mode, fired: false });
    this.tamperSchedule.set(channelId, arr);
    this.log('TAMPER', `⚡ Scheduled: channel=${channelId} tick=${tick} mode=${mode}`);
  }

  /**
   * Look up and consume a scheduled tamper for the given channel + tick.
   * Returns the mode if one fires, or undefined otherwise.
   */
  private popScheduledTamper(channelId: string, atTick: number): TamperMode | undefined {
    const arr = this.tamperSchedule.get(channelId);
    if (!arr) return undefined;
    for (const entry of arr) {
      if (!entry.fired && entry.tick === atTick) {
        entry.fired = true;
        return entry.mode;
      }
    }
    return undefined;
  }

  /** Load the 2PDA kernel for channel state validation */
  async loadKernel(): Promise<void> {
    if (this.kernelLoaded) return;
    try {
      const { loadCellEngine } = await import('@semantos/cell-engine/bindings/bun/loader');
      const cellEngine = await loadCellEngine({ profile: 'embedded' });
      // debug: false — the channel manager logs its own condensed output per tick.
      // Set debug: true to see full 2PDA step-by-step for every channel tick.
      this.validator = new TransitionValidator(cellEngine as CellEngineHandle, { debug: false });
      this.kernelLoaded = true;
      this.log('KERNEL', '2PDA kernel loaded for channel state validation');
    } catch (err: any) {
      this.log('KERNEL', `⚠ Failed to load kernel: ${err.message} (channel state CellTokens will not be kernel-validated)`);
    }
  }

  /**
   * Open a payment channel: create 2-of-2 multisig funding tx.
   *
   * The funding output is locked to: OP_2 <pubA> <pubB> OP_2 OP_CHECKMULTISIG
   * Both agents must sign to spend it (settlement).
   *
   * Initial balances: each agent starts with fundingSats/2.
   */
  async openChannel(config: ChannelConfig): Promise<ChannelInstance> {
    const { agentA, agentB, fundingSats, streamId, sharedSecret } = config;

    // 1. Create metering FSM channel
    let channel = createChannel(agentA.id, agentB.id);

    // 2. Build 2-of-2 multisig locking script
    // OP_2 <pubA> <pubB> OP_2 OP_CHECKMULTISIG
    const multisigScript = this.build2of2Script(agentA.pubKey, agentB.pubKey);

    // 3. Build and broadcast the funding transaction
    // We use the engine's UTXO pool for the funding input
    const fundingResult = await this.buildFundingTx(
      streamId, multisigScript, fundingSats, config,
    );

    // 4. Advance FSM: NEGOTIATING → FUNDED → ACTIVE
    const fundResult = fund(channel, `${fundingResult.txid}.${fundingResult.vout}`);
    if (!fundResult.ok) throw new Error(fundResult.error);
    channel = fundResult.value;

    const activateResult = activate(channel);
    if (!activateResult.ok) throw new Error(activateResult.error);
    channel = activateResult.value;

    const instance: ChannelInstance = {
      channelId: channel.channelId,
      channel,
      config,
      fundingTxid: fundingResult.txid,
      fundingVout: fundingResult.vout,
      fundingTx: fundingResult.tx,
      balanceA: Math.floor(fundingSats / 2),
      balanceB: Math.floor(fundingSats / 2),
      tickProofs: [],
      // CellToken state chain — initialized by createChannelStateCellToken()
      cellVersion: 0,
      cellTransitions: [],
    };

    this.channels.set(channel.channelId, instance);
    this.totalChannelsOpened++;

    this.log('CHANNEL', `Opened: ${channel.channelId}`);
    this.log('CHANNEL', `  2-of-2 multisig: ${fundingResult.txid.slice(0, 16)}... (${fundingSats} sats)`);
    this.log('CHANNEL', `  ${agentA.name}: ${instance.balanceA} sats | ${agentB.name}: ${instance.balanceB} sats`);
    this.log('CHANNEL', `  https://whatsonchain.com/tx/${fundingResult.txid}`);

    this.emit('channel-open', channel.channelId, {
      agentA: agentA.name,
      agentB: agentB.name,
      agentAPubKey: agentA.pubKey.toString(),
      agentBPubKey: agentB.pubKey.toString(),
      fundingSats,
      balanceA: instance.balanceA,
      balanceB: instance.balanceB,
      matchTxid: config.matchTxid,
    }, { txid: fundingResult.txid });

    // Create the initial channel state CellToken (v1)
    // This is a LINEAR CellToken representing the channel's state.
    // Every tick transitions it (v1→v2→v3...) through the 2PDA kernel.
    await this.createChannelStateCellToken(instance);

    return instance;
  }

  /**
   * Record a bet (tick) in the payment channel.
   *
   * **Staged validate-then-commit flow (stage-1 violation support):**
   *   1. STAGE — compute candidate balances, FSM tick, tick proof (no mutation)
   *   2. BUILD — construct candidate cell bytes; optionally tamper for adversarial tests
   *   3. VALIDATE — run the candidate through the 2PDA kernel
   *   4a. VIOLATION — if kernel rejects, anchor a violation OP_RETURN marker
   *       on-chain, do NOT mutate instance state, throw ChannelViolationError
   *   4b. COMMIT — if kernel accepts, apply balances + FSM + stats, then broadcast
   *       the transition tx (with nSequence = prev cell version)
   *
   * @param channelId  The channel to update
   * @param fromAgent  'A' or 'B' — who is paying
   * @param satoshis   How many sats are being wagered/moved
   * @param tamperMode Optional: deliberately corrupt the candidate cell header so
   *                   the kernel will reject it. Used for adversarial testing / red-team.
   *                   Normal gameplay should not pass this.
   * @returns The tick proof (HMAC-authenticated)
   * @throws ChannelViolationError when the candidate transition fails kernel validation
   */
  async recordBet(
    channelId: string,
    fromAgent: 'A' | 'B',
    satoshis: number,
    tamperMode?: TamperMode,
  ): Promise<TickProof> {
    const instance = this.channels.get(channelId);
    if (!instance) throw new Error(`Channel ${channelId} not found`);

    // ── STAGE 1: Compute candidate state (no mutation yet) ──
    let candidateBalanceA = instance.balanceA;
    let candidateBalanceB = instance.balanceB;
    if (fromAgent === 'A') {
      candidateBalanceA -= satoshis;
      candidateBalanceB += satoshis;
    } else {
      candidateBalanceB -= satoshis;
      candidateBalanceA += satoshis;
    }
    candidateBalanceA = Math.max(0, candidateBalanceA);
    candidateBalanceB = Math.max(0, candidateBalanceB);

    // FSM tick is pure — returns a new value, doesn't mutate instance.channel
    const tickResult = channelTick(instance.channel, satoshis);
    if (!tickResult.ok) throw new Error((tickResult as any).error);
    const candidateChannel = tickResult.value;

    const proof = await computeTickProof(
      channelId,
      candidateChannel.currentTick,
      candidateChannel.cumulativeSatoshis,
      instance.config.sharedSecret,
    );

    // ── STAGE 2: Build candidate cell bytes ──
    const newVersion = instance.cellVersion + 1;
    const prevContentHex = instance.prevContentHash
      ? Buffer.from(instance.prevContentHash).toString('hex')
      : '0'.repeat(64);

    const statePayload = {
      proto: 'semantos:poker:channel-state',
      v: newVersion,
      channelId: instance.channelId,
      tick: candidateChannel.currentTick,
      balanceA: candidateBalanceA,
      balanceB: candidateBalanceB,
      lastAction: { from: fromAgent, sats: satoshis },
      hmacProof: proof.hmac.slice(0, 16),
      cumulativeSats: candidateChannel.cumulativeSatoshis,
      prevStateHash: prevContentHex,
      ts: Date.now(),
    };

    // K6 hash-chain binding: successor cells must carry sha256(prevCell) in
    // their header so TransitionValidator can cryptographically link v_n→v_{n+1}.
    const prevCellHashBytes = instance.prevCellBytes
      ? new Uint8Array(createHash('sha256').update(Buffer.from(instance.prevCellBytes)).digest())
      : undefined;

    let cellBuild = await this.buildChannelCell(
      instance.channelId, statePayload, newVersion, false, prevCellHashBytes,
    );
    let cellBytes = cellBuild.cellBytes;
    const contentHash = cellBuild.contentHash;
    const semanticPath = cellBuild.semanticPath;

    // If caller didn't explicitly pass a tamperMode, consult the schedule.
    // (The arena CLI uses scheduleTamper() to pre-arm deterministic demos.)
    let effectiveTamperMode = tamperMode;
    if (!effectiveTamperMode) {
      effectiveTamperMode = this.popScheduledTamper(channelId, candidateChannel.currentTick);
      if (effectiveTamperMode) {
        this.log(
          'TAMPER',
          `⚡ Firing scheduled tamper on channel=${channelId} tick=${candidateChannel.currentTick} mode=${effectiveTamperMode}`,
        );
      }
    }

    // Apply tamper if requested — deliberately corrupts the wire-level header
    // so the kernel's invariant checks will reject it on a specific K-theorem path.
    if (effectiveTamperMode) {
      cellBytes = applyTamper(cellBytes, effectiveTamperMode);
    }

    // ── STAGE 3: Kernel validation ──
    // If there's no prior cell or no validator loaded, we can't validate — fall
    // through to commit (preserves behavior on engines without the kernel loaded).
    let kernelChecked = false;
    let kernelValidated = true;
    let kernelReason = '';
    if (this.validator && instance.prevCellBytes && instance.prevContentHash && instance.cellTxid) {
      kernelChecked = true;
      const ownerPubKey = PublicKey.fromString(this.engine.getPubKeyHex());
      const result = this.validator.validate({
        v1CellBytes: instance.prevCellBytes,
        v2CellBytes: cellBytes,
        semanticPath,
        v1ContentHash: instance.prevContentHash,
        v2ContentHash: contentHash,
        ownerPubKey,
      });
      kernelValidated = result.valid;
      kernelReason = result.reason ?? '';
    }

    // ── STAGE 4A: VIOLATION path ──
    if (kernelChecked && !kernelValidated) {
      this.totalKernelFailures++;
      this.totalViolationsCaught++;
      const offender = fromAgent === 'A' ? instance.config.agentA : instance.config.agentB;
      this.log(
        'KERNEL',
        `✗ VIOLATION caught: channel=${instance.channelId} v${instance.cellVersion}→v${newVersion} by ${offender.name}${effectiveTamperMode ? ` tamper=${effectiveTamperMode}` : ''}: ${kernelReason}`,
      );

      // Build a rich violation payload — full context of the failed transition.
      const offenderPubKeyHex = offender.pubKey.toString();
      const violationPayload = {
        proto: 'semantos:poker:violation',
        v: 1,
        stage: 2,
        channelId: instance.channelId,
        fromVersion: instance.cellVersion,
        attemptedVersion: newVersion,
        kernelReason: kernelReason.slice(0, 200),
        tamperMode: effectiveTamperMode ?? null,
        offender: offender.name,
        offenderPubKey: offenderPubKeyHex,
        offenderPubKeyShort: offenderPubKeyHex.slice(0, 16),
        attemptedCellSha256: sha256Hex(cellBytes),
        attemptedContentHash: Buffer.from(contentHash).toString('hex'),
        prevCellSha256: instance.prevCellBytes ? sha256Hex(instance.prevCellBytes) : null,
        prevCellTxid: instance.cellTxid ?? null,
        ts: Date.now(),
      };

      // Stage 2: broadcast a proper AFFINE violation cell owned by the offender.
      // The cell is a 1024-byte kernel-valid CellToken carrying the full violation
      // context in its payload. Path: channels/violations/{offenderId16Hex} so
      // all of an offender's violations are enumerable by path prefix.
      //
      // If the cell broadcast fails for any reason (UTXO pool empty, ARC error,
      // etc.), fall back to the cheaper OP_RETURN marker so we still have an
      // on-chain breadcrumb. Either way the game continues.
      let violationTxid: string | undefined;
      let anchorKind: 'violation-cell' | 'op-return' | 'none' = 'none';

      try {
        const violationCell = await this.buildViolationCell(offenderPubKeyHex, violationPayload);

        // Sanity-check the violation cell itself through the kernel — if our own
        // violation-cell builder produced an invalid cell, that's a bug we want
        // to know about immediately, not silently.
        if (this.validator) {
          const selfCheck = this.validator.validateCell(violationCell.cellBytes);
          if (!selfCheck.valid) {
            throw new Error(`violation cell self-check failed: ${selfCheck.reason}`);
          }
        }

        const cellStream = instance.config.cellStreamId ?? instance.config.streamId;
        const r = await this.engine.createCellToken(
          cellStream,
          violationCell.cellBytes,
          violationCell.semanticPath,
          violationCell.contentHash,
        );
        violationTxid = r.txid;
        anchorKind = 'violation-cell';
        this.totalViolationsAnchored++;
        this.log(
          'VIOLATION',
          `📝 AFFINE cell anchored: ${r.txid.slice(0, 16)}... path=${violationCell.semanticPath} https://whatsonchain.com/tx/${r.txid}`,
        );

        // Stage-3: record the hit on the offender's LINEAR watchlist.
        // Errors inside recordWatchlistHit are logged, not thrown — the game
        // continues even if the reputation update fails.
        await this.recordWatchlistHit(
          offenderPubKeyHex,
          offender.name,
          r.txid,
          kernelReason,
          instance.channelId,
        );
      } catch (cellErr: any) {
        this.log('VIOLATION', `⚠ Violation cell broadcast failed (${cellErr.message}), falling back to OP_RETURN marker`);
        try {
          const r = await this.engine.anchorOpReturn(
            instance.config.streamId,
            JSON.stringify(violationPayload),
          );
          violationTxid = r.txid;
          anchorKind = 'op-return';
          this.totalViolationsAnchored++;
          this.log(
            'VIOLATION',
            `📝 OP_RETURN fallback anchored: ${r.txid.slice(0, 16)}... https://whatsonchain.com/tx/${r.txid}`,
          );
        } catch (fallbackErr: any) {
          this.log('VIOLATION', `⚠ Fallback OP_RETURN also failed: ${fallbackErr.message}`);
        }
      }

      // Emit a structured violation event so the hypervisor console (and any
      // other observer) can surface it without parsing log lines. We compute
      // the offender's 16-hex ownerId here so the dashboard can correlate
      // violations with watchlist-hit events by the same key.
      const offenderOwnerHash = createHash('sha256').update(offenderPubKeyHex).digest();
      const offenderIdHex = offenderOwnerHash.subarray(0, 16).toString('hex');
      const watchlistAfter = this.watchlists.get(offenderIdHex);
      this.emit('channel-violation', instance.channelId, {
        offenderName: offender.name,
        offenderPubKey: offenderPubKeyHex,
        offenderIdHex,
        fromVersion: instance.cellVersion,
        attemptedVersion: newVersion,
        kernelReason,
        tamperMode: effectiveTamperMode ?? null,
        kTheorem: tamperModeToKTheorem(effectiveTamperMode),
        anchorKind,
        hitCountAfter: watchlistAfter?.hitCount ?? 0,
        watchlistVersionAfter: watchlistAfter?.cellVersion ?? 0,
        watchlistTxidAfter: watchlistAfter?.cellTxid,
      }, { txid: violationTxid });

      throw new ChannelViolationError(
        `${kernelReason} [anchor=${anchorKind}]`,
        effectiveTamperMode,
        instance.channelId,
        violationTxid,
      );
    }

    // ── STAGE 4B: COMMIT candidate state ──
    instance.balanceA = candidateBalanceA;
    instance.balanceB = candidateBalanceB;
    instance.channel = candidateChannel;
    instance.tickProofs.push(proof);
    this.totalTicks++;
    this.totalSatsTransferred += satoshis;
    if (kernelChecked) this.totalKernelValidations++;

    // ── STAGE 5: Broadcast transition ──
    // (If there's no live prior cell, we can't transition; the cell chain
    // was never established for this channel. Just skip the broadcast.)
    if (instance.cellTxid && instance.cellSourceTx) {
      const txCellStream = instance.config.cellStreamId ?? instance.config.streamId;
      try {
        const result = await this.engine.transitionCellToken(
          txCellStream,
          instance.cellTxid,
          instance.cellVout!,
          instance.cellSourceTx,
          cellBytes,
          semanticPath,
          contentHash,
          instance.cellVersion, // nSequence on input 0 = prev state version being replaced
        );

        instance.cellTxid = result.txid;
        instance.cellVout = 0;
        instance.cellSourceTx = result.tx;
        instance.cellVersion = newVersion;
        instance.prevCellBytes = cellBytes;
        instance.prevContentHash = contentHash;
        instance.cellTransitions.push({
          txid: result.txid,
          version: newVersion,
          prevStateHash: prevContentHex,
          kernelValidated: true,
        });

        this.log(
          'CELL',
          `Channel v${newVersion}: ${fromAgent} ${satoshis}sat → A:${instance.balanceA} B:${instance.balanceB} | ${result.txid.slice(0, 12)}... [2PDA ✓]`,
        );

        this.emit('channel-tick', instance.channelId, {
          version: newVersion,
          fromAgent,
          sats: satoshis,
          balanceA: instance.balanceA,
          balanceB: instance.balanceB,
          agentAName: instance.config.agentA.name,
          agentBName: instance.config.agentB.name,
          kernelValidated: kernelChecked,
          prevStateHash: prevContentHex,
        }, { txid: result.txid });
      } catch (err: any) {
        this.log('CELL', `⚠ Channel state transition broadcast failed: ${err.message}`);
      }
    }

    return proof;
  }

  /**
   * Award the pot to the winner at hand end.
   * This is a convenience method that moves `potSats` from loser to winner.
   */
  async awardPot(
    channelId: string,
    winnerIsA: boolean,
    potSats: number,
  ): Promise<TickProof> {
    // The pot has already been accumulated from individual bets.
    // This tick records the final transfer.
    return this.recordBet(channelId, winnerIsA ? 'B' : 'A', potSats);
  }

  /**
   * Settle the channel: close the 2-of-2 multisig and pay out final balances.
   *
   * Builds a settlement tx that:
   *   Input: spends the 2-of-2 multisig (both agents sign)
   *   Output 0: Agent A's final balance (P2PKH)
   *   Output 1: Agent B's final balance (P2PKH)
   */
  async settleChannel(channelId: string): Promise<{ txid: string; batch: SettlementBatch }> {
    const instance = this.channels.get(channelId);
    if (!instance) throw new Error(`Channel ${channelId} not found`);

    const { config, fundingTx, fundingTxid, fundingVout, balanceA, balanceB, tickProofs, channel } = instance;

    // Advance FSM: ACTIVE → CLOSING_REQUESTED → CLOSING_CONFIRMED → SETTLED
    let ch = channel;
    const closeReq = requestClose(ch);
    if (!closeReq.ok) throw new Error(closeReq.error);
    ch = closeReq.value;

    const closeConf = confirmClose(ch);
    if (!closeConf.ok) throw new Error(closeConf.error);
    ch = closeConf.value;

    // Build settlement transaction
    const fee = 150; // fixed fee, same as other engine txs
    const totalIn = balanceA + balanceB;
    const totalOut = totalIn - fee;

    // Proportional split after fee
    const ratioA = totalIn > 0 ? balanceA / totalIn : 0.5;
    const outA = Math.floor(totalOut * ratioA);
    const outB = totalOut - outA;

    const p2pkh = new P2PKH();
    const tx = new Transaction();

    // Input: spend the 2-of-2 multisig
    const signatureScope = TransactionSignature.SIGHASH_FORKID | TransactionSignature.SIGHASH_ALL;

    // nSequence encodes the FINAL kernel-validated state version this settlement closes.
    // Traditional Bitcoin payment channels used nSequence for off-chain state versioning;
    // we anchor every state on-chain, so this field is redundant for race resolution but
    // serves as a Bitcoin-native, self-describing attestation of the state version being
    // settled ("this multisig spend closes state vN"). Independent of the cell header's
    // version field — any mismatch would be a provable bug.
    // Kept strictly below 0xFFFFFFFF so nLockTime (if ever added) remains honored.
    const finalStateSequence = Math.min(instance.cellVersion, 0xFFFFFFFE);

    tx.addInput({
      sourceTXID: fundingTxid,
      sourceOutputIndex: fundingVout,
      sourceTransaction: fundingTx,
      sequence: finalStateSequence,
      unlockingScriptTemplate: {
        sign: async (tx: Transaction, inputIndex: number): Promise<any> => {
          const preimage = tx.preimage(inputIndex, signatureScope);
          const preimageHash = Hash.sha256(preimage);

          // Both agents sign
          const sigA = config.agentA.privKey.sign(preimageHash);
          const txSigA = new TransactionSignature(sigA.r, sigA.s, signatureScope);
          const sigBytesA = txSigA.toChecksigFormat();

          const sigB = config.agentB.privKey.sign(preimageHash);
          const txSigB = new TransactionSignature(sigB.r, sigB.s, signatureScope);
          const sigBytesB = txSigB.toChecksigFormat();

          // OP_0 <sigA> <sigB> (OP_0 is the dummy for CHECKMULTISIG bug)
          const { UnlockingScript: US } = await import('@bsv/sdk');
          return new US([
            { op: 0x00 }, // OP_0 dummy
            sigBytesA.length <= 75
              ? { op: sigBytesA.length, data: Array.from(sigBytesA) }
              : { op: 0x4c, data: Array.from(sigBytesA) },
            sigBytesB.length <= 75
              ? { op: sigBytesB.length, data: Array.from(sigBytesB) }
              : { op: 0x4c, data: Array.from(sigBytesB) },
          ]);
        },
        estimateLength: async (): Promise<number> => 1 + 73 + 73, // OP_0 + 2 sigs
      },
    });

    // Output 0: Agent A's payout
    if (outA > 0) {
      tx.addOutput({
        lockingScript: p2pkh.lock(config.agentA.pubKey.toAddress()),
        satoshis: outA,
      });
    }

    // Output 1: Agent B's payout
    if (outB > 0) {
      tx.addOutput({
        lockingScript: p2pkh.lock(config.agentB.pubKey.toAddress()),
        satoshis: outB,
      });
    }

    await tx.sign();
    const txid = tx.id('hex') as string;

    // Broadcast settlement through the bound broadcaster port (ARC by default).
    const result = await this.broadcaster.broadcast(tx.toHex());
    if (!result.ok) {
      this.log('SETTLE', `⚠ Settlement broadcast failed: ${result.error ?? result.status ?? 'unknown'}`);
      // Continue anyway — the tx is built and signed
    }

    // Finalize FSM
    const settleResult = channelSettle(ch, txid);
    if (settleResult.ok) {
      instance.channel = settleResult.value;
    }
    instance.settlementTxid = txid;

    // Create settlement batch
    const batch = createSettlementBatch(channelId, tickProofs);
    batch.settlementTxId = txid;

    this.totalChannelsSettled++;

    this.log('SETTLE', `Channel ${channelId} settled: ${txid.slice(0, 16)}...`);
    this.log('SETTLE', `  ${config.agentA.name}: ${outA} sats | ${config.agentB.name}: ${outB} sats`);
    this.log('SETTLE', `  ${tickProofs.length} ticks, ${instance.channel.cumulativeSatoshis} sats transferred`);
    this.log('SETTLE', `  final state v${instance.cellVersion} (nSequence=${finalStateSequence}) — taxonomy: HOW/OUTCOME`);
    this.log('SETTLE', `  https://whatsonchain.com/tx/${txid}`);

    this.emit('channel-settle', channelId, {
      agentA: config.agentA.name,
      agentB: config.agentB.name,
      outA,
      outB,
      finalBalanceA: balanceA,
      finalBalanceB: balanceB,
      tickCount: tickProofs.length,
      satsTransferred: instance.channel.cumulativeSatoshis,
      finalCellVersion: instance.cellVersion,
      nSequence: finalStateSequence,
    }, { txid });

    return { txid, batch };
  }

  /** Get a channel instance by ID */
  getChannel(channelId: string): ChannelInstance | undefined {
    return this.channels.get(channelId);
  }

  /** Get all channel instances */
  getAllChannels(): ChannelInstance[] {
    return [...this.channels.values()];
  }

  // ── Channel State CellToken (kernel-validated state chain) ──

  /**
   * Create the initial (v1) channel state CellToken.
   *
   * This is a LINEAR CellToken whose payload contains the channel's opening state.
   * Every tick (bet) will transition this cell to the next version, validated
   * through the 2PDA kernel. The result is a verifiable on-chain state chain:
   *
   *   v1 (open) → v2 (bet 1) → v3 (bet 2) → ... → vN (pre-settle)
   *
   * Each transition preserves: type-hash, owner-ID, linearity (LINEAR).
   * Each cell's content includes prevStateHash = SHA256 of previous cell content,
   * creating a hash chain that's independently verifiable.
   */
  private async createChannelStateCellToken(instance: ChannelInstance): Promise<void> {
    const { channelId, config, fundingTxid, balanceA, balanceB } = instance;

    const statePayload = {
      proto: 'semantos:poker:channel-state',
      v: 1,
      channelId,
      tick: 0,
      balanceA,
      balanceB,
      fundingTxid,
      matchTxid: config.matchTxid ?? null,        // ← traces back to discovery match
      announceTxA: config.announceTxidA ?? null,   // ← traces back to agent A discovery
      announceTxB: config.announceTxidB ?? null,   // ← traces back to agent B discovery
      agentA: config.agentA.name,
      agentB: config.agentB.name,
      prevStateHash: '0'.repeat(64), // genesis — no previous state
      ts: Date.now(),
    };

    const { cellBytes, contentHash, semanticPath } = await this.buildChannelCell(
      channelId, statePayload, 1,
    );

    // Validate through kernel
    let kernelValidated = false;
    if (this.validator) {
      const check = this.validator.validateCell(cellBytes);
      kernelValidated = check.valid;
      if (kernelValidated) {
        this.totalKernelValidations++;
        this.log('KERNEL', `✓ Channel ${channelId} v1 cell valid (linearity=${check.linearity})`);
      } else {
        this.totalKernelFailures++;
        this.log('KERNEL', `✗ Channel ${channelId} v1 invalid: ${check.reason}`);
      }
    }

    // Broadcast on-chain (use cell stream, not OP_RETURN stream)
    const cellStream = instance.config.cellStreamId ?? instance.config.streamId;
    try {
      const result = await this.engine.createCellToken(
        cellStream,
        cellBytes,
        semanticPath,
        contentHash,
      );

      instance.cellTxid = result.txid;
      instance.cellVout = 0;
      instance.cellSourceTx = result.tx;
      instance.cellVersion = 1;
      instance.prevCellBytes = cellBytes;
      instance.prevContentHash = contentHash;
      instance.cellTransitions = [{
        txid: result.txid,
        version: 1,
        prevStateHash: '0'.repeat(64),
        kernelValidated,
      }];

      this.log('CELL', `Channel ${channelId} state v1 → ${result.txid.slice(0, 16)}...${kernelValidated ? ' [2PDA ✓]' : ''}`);
    } catch (err: any) {
      this.log('CELL', `⚠ Channel state CellToken create failed: ${err.message}`);
      instance.cellVersion = 0;
      instance.cellTransitions = [];
    }
  }

  // NOTE: the previous transitionChannelStateCellToken() helper was inlined
  // into recordBet() when the validate-then-commit staging was introduced.
  // Everything it did (build → validate → broadcast) now happens in recordBet
  // with a clear violation-vs-commit branch.

  /**
   * Build a 1024-byte CellToken for channel state.
   *
   * Taxonomy classification (universal who/what/how/instrument):
   *   who       → ownerId     = SHA256(channelId)[:16]     (the channel identity)
   *   what      → typeHash    = SHA256('semantos/poker/channel-state/v1')
   *   how       → dimension   = TaxonomyDimension.HOW      (process-state, not thing-state)
   *   instrument→ (separate)  — the 2-of-2 multisig funding is the instrument
   *   phase     → CommercePhase.ACTION for interim ticks,
   *               CommercePhase.OUTCOME when `isFinal` is set (pre-settle state)
   */
  private async buildChannelCell(
    channelId: string,
    statePayload: Record<string, unknown>,
    version: number,
    isFinal: boolean = false,
    prevCellHash?: Uint8Array,
  ): Promise<{ cellBytes: Uint8Array; contentHash: Uint8Array; semanticPath: string }> {
    const storage = new MemoryAdapter();
    const cellStore = new CellStore(storage);
    const path = `channels/state/${channelId}`;

    const data = new TextEncoder().encode(JSON.stringify(statePayload));
    const ownerId = hexToBytes(
      createHash('sha256').update(channelId).digest('hex').slice(0, 32),
    );

    // For v_n>1, inject the predecessor's full-cell sha256 into the cell header's
    // commercePrevState slot so TransitionValidator can verify K6 hash-chain
    // continuity. Genesis (v1) cells pass `undefined` and default to zeros.
    const cellRef = await cellStore.put(path, data, {
      linearity: Linearity.LINEAR,
      ownerId,
      typeHash: CHANNEL_STATE_TYPE_HASH,
      dimension: TaxonomyDimension.HOW,
      phase: isFinal ? CommercePhase.OUTCOME : CommercePhase.ACTION,
      prevStateHash: prevCellHash,
    });

    const cellBytes = await storage.read(path);
    if (!cellBytes) throw new Error('Failed to read channel cell');

    // Bump version in header
    if (version > 1) {
      const dv = new DataView(cellBytes.buffer, cellBytes.byteOffset, cellBytes.byteLength);
      dv.setUint32(20, version, true);
    }

    return {
      cellBytes,
      contentHash: hexToBytes(cellRef.contentHash),
      semanticPath: path,
    };
  }

  /**
   * Build a 1024-byte AFFINE violation CellToken (stage-2).
   *
   * A violation cell captures the full context of a failed transition so the
   * chain becomes a reputation substrate. Unlike channel state (which is LINEAR
   * and must be consumed exactly once), violation cells are AFFINE — they can
   * be consumed at most once by a future reputation roll-up, but need not be.
   *
   * Taxonomy classification:
   *   who        → ownerId     = SHA256(offenderPubKey)[:16]   (per-offender domain)
   *   what       → typeHash    = SHA256('semantos/poker/violation/v1')
   *   how        → dimension   = TaxonomyDimension.HOW         (a process event)
   *   phase      → CommercePhase.OUTCOME                       (terminal — the rejection)
   *
   * Semantic path `channels/violations/{offenderId}` makes every offender's
   * violation history enumerable by path prefix.
   */
  private async buildViolationCell(
    offenderPubKeyHex: string,
    violationPayload: Record<string, unknown>,
  ): Promise<{ cellBytes: Uint8Array; contentHash: Uint8Array; semanticPath: string }> {
    const storage = new MemoryAdapter();
    const cellStore = new CellStore(storage);

    // ownerId = first 16 bytes of SHA256(offenderPubKey) → per-offender domain
    const ownerHash = createHash('sha256').update(offenderPubKeyHex).digest();
    const ownerId = new Uint8Array(ownerHash.subarray(0, 16));

    // Use the owner's 16-byte hash (hex) as the path segment so all violations
    // by this offender cluster together in the semantic tree.
    const ownerIdHex = Buffer.from(ownerId).toString('hex');
    const path = `channels/violations/${ownerIdHex}`;

    const data = new TextEncoder().encode(JSON.stringify(violationPayload));

    const cellRef = await cellStore.put(path, data, {
      linearity: Linearity.AFFINE,
      ownerId,
      typeHash: CHANNEL_VIOLATION_TYPE_HASH,
      dimension: TaxonomyDimension.HOW,
      phase: CommercePhase.OUTCOME,
    });

    const cellBytes = await storage.read(path);
    if (!cellBytes) throw new Error('Failed to read violation cell');

    return {
      cellBytes,
      contentHash: hexToBytes(cellRef.contentHash),
      semanticPath: path,
    };
  }

  /**
   * Build a 1024-byte LINEAR watchlist CellToken (stage-3).
   *
   * Each offender has their own LINEAR state chain under
   * `watchlist/offenders/{offenderIdHex}`. Every violation cell anchor
   * triggers a v_n → v_{n+1} transition, and the 2PDA kernel validates
   * every transition — making the offender's reputation history
   * kernel-enforced and publicly verifiable.
   *
   * Taxonomy classification:
   *   who        → ownerId     = SHA256(offenderPubKey)[:16]   (same domain as their violations)
   *   what       → typeHash    = SHA256('semantos/poker/watchlist/v1')
   *   how        → dimension   = TaxonomyDimension.INSTRUMENT  (a gating tool, not a process step)
   *   phase      → CommercePhase.ACTION                        (each hit is an active update)
   */
  private async buildWatchlistCell(
    offenderIdHex: string,
    statePayload: Record<string, unknown>,
    version: number,
    prevCellHash?: Uint8Array,
  ): Promise<{ cellBytes: Uint8Array; contentHash: Uint8Array; semanticPath: string }> {
    const storage = new MemoryAdapter();
    const cellStore = new CellStore(storage);
    const path = `watchlist/offenders/${offenderIdHex}`;

    const data = new TextEncoder().encode(JSON.stringify(statePayload));
    const ownerId = hexToBytes(offenderIdHex);

    // Repeat-offender transitions (v_n>1) inject sha256(prevCell) into the
    // header so the kernel can verify hash-chain continuity. First-hit cells
    // pass `undefined` (genesis → zeros).
    const cellRef = await cellStore.put(path, data, {
      linearity: Linearity.LINEAR,
      ownerId,
      typeHash: CHANNEL_WATCHLIST_TYPE_HASH,
      dimension: TaxonomyDimension.INSTRUMENT,
      phase: CommercePhase.ACTION,
      prevStateHash: prevCellHash,
    });

    const cellBytes = await storage.read(path);
    if (!cellBytes) throw new Error('Failed to read watchlist cell');

    // Bump version in header for v_n>1
    if (version > 1) {
      const dv = new DataView(cellBytes.buffer, cellBytes.byteOffset, cellBytes.byteLength);
      dv.setUint32(20, version, true);
    }

    return {
      cellBytes,
      contentHash: hexToBytes(cellRef.contentHash),
      semanticPath: path,
    };
  }

  /**
   * Record a watchlist hit for an offender (stage-3).
   *
   * If this is the offender's first violation, creates the LINEAR watchlist
   * cell at v1. If they're a repeat offender, transitions v_n → v_{n+1}
   * through the 2PDA kernel. Every state update is kernel-validated.
   *
   * Never throws — watchlist failures are logged but don't break gameplay.
   * Returns the transition txid if broadcast succeeded, or undefined.
   */
  private async recordWatchlistHit(
    offenderPubKeyHex: string,
    offenderName: string,
    violationTxid: string,
    kernelReason: string,
    channelId: string,
  ): Promise<string | undefined> {
    const ownerHash = createHash('sha256').update(offenderPubKeyHex).digest();
    const offenderIdHex = ownerHash.subarray(0, 16).toString('hex');
    const now = Date.now();

    let watchlist = this.watchlists.get(offenderIdHex);
    const isFirstHit = !watchlist;

    try {
      if (isFirstHit) {
        // ── FIRST HIT: create v1 watchlist cell ──
        const state = {
          proto: 'semantos:poker:watchlist/v1',
          v: 1,
          offenderPubKey: offenderPubKeyHex,
          offenderId: offenderIdHex,
          offenderName,
          hitCount: 1,
          firstSeen: now,
          lastSeen: now,
          violationTxids: [violationTxid],
          lastKernelReason: kernelReason.slice(0, 200),
          lastChannelId: channelId,
          prevStateHash: '0'.repeat(64), // genesis
        };

        const built = await this.buildWatchlistCell(offenderIdHex, state, 1);

        // Single-cell kernel check (standalone validity)
        if (this.validator) {
          const check = this.validator.validateCell(built.cellBytes);
          if (check.valid) {
            this.totalWatchlistValidations++;
          } else {
            this.totalWatchlistFailures++;
            throw new Error(`watchlist v1 self-check failed: ${check.reason}`);
          }
        }

        // Broadcast via createCellToken on the cell stream (fall back to default stream 0).
        const cellStream = 0;
        const result = await this.engine.createCellToken(
          cellStream,
          built.cellBytes,
          built.semanticPath,
          built.contentHash,
        );

        watchlist = {
          offenderIdHex,
          offenderPubKey: offenderPubKeyHex,
          offenderName,
          hitCount: 1,
          firstSeenTs: now,
          lastSeenTs: now,
          violationTxids: [violationTxid],
          lastKernelReason: kernelReason.slice(0, 200),
          cellTxid: result.txid,
          cellVout: 0,
          cellSourceTx: result.tx,
          cellVersion: 1,
          prevCellBytes: built.cellBytes,
          prevContentHash: built.contentHash,
          cellTransitions: [{ txid: result.txid, version: 1, hitCount: 1, kernelValidated: this.validator !== null }],
        };
        this.watchlists.set(offenderIdHex, watchlist);
        this.totalWatchlistHits++;

        this.log(
          'WATCHLIST',
          `🆕 ${offenderName} (${offenderIdHex.slice(0, 8)}...): v1 opened, hitCount=1 → ${result.txid.slice(0, 16)}...${this.validator ? ' [2PDA ✓]' : ''}`,
        );

        this.emit('watchlist-hit', channelId, {
          offenderName,
          offenderPubKey: offenderPubKeyHex,
          offenderIdHex,
          hitCount: 1,
          cellVersion: 1,
          isFirstHit: true,
          kernelReason: kernelReason.slice(0, 200),
          kernelValidated: this.validator !== null,
          violationTxid,
        }, { txid: result.txid });

        return result.txid;
      } else {
        // ── REPEAT OFFENDER: transition v_n → v_{n+1} ──
        const newVersion = watchlist!.cellVersion + 1;
        const newHitCount = watchlist!.hitCount + 1;
        const prevContentHex = Buffer.from(watchlist!.prevContentHash).toString('hex');

        // Rolling tail of last 10 violation txids
        const rollingTxids = [...watchlist!.violationTxids, violationTxid].slice(-10);

        const state = {
          proto: 'semantos:poker:watchlist/v1',
          v: newVersion,
          offenderPubKey: offenderPubKeyHex,
          offenderId: offenderIdHex,
          offenderName,
          hitCount: newHitCount,
          firstSeen: watchlist!.firstSeenTs,
          lastSeen: now,
          violationTxids: rollingTxids,
          lastKernelReason: kernelReason.slice(0, 200),
          lastChannelId: channelId,
          prevStateHash: prevContentHex,
        };

        // K6 hash-chain binding: v_n→v_{n+1} requires sha256(prevCell) in header.
        const prevWatchlistHash = new Uint8Array(
          createHash('sha256').update(Buffer.from(watchlist!.prevCellBytes)).digest(),
        );
        const built = await this.buildWatchlistCell(
          offenderIdHex, state, newVersion, prevWatchlistHash,
        );

        // Kernel transition check v_n → v_{n+1}
        if (this.validator) {
          const ownerPubKey = PublicKey.fromString(this.engine.getPubKeyHex());
          const result = this.validator.validate({
            v1CellBytes: watchlist!.prevCellBytes,
            v2CellBytes: built.cellBytes,
            semanticPath: built.semanticPath,
            v1ContentHash: watchlist!.prevContentHash,
            v2ContentHash: built.contentHash,
            ownerPubKey,
          });
          if (result.valid) {
            this.totalWatchlistValidations++;
          } else {
            this.totalWatchlistFailures++;
            throw new Error(`watchlist v${watchlist!.cellVersion}→v${newVersion} kernel check failed: ${result.reason}`);
          }
        }

        // Broadcast via transitionCellToken on the cell stream
        const cellStream = 0;
        const result = await this.engine.transitionCellToken(
          cellStream,
          watchlist!.cellTxid,
          watchlist!.cellVout,
          watchlist!.cellSourceTx,
          built.cellBytes,
          built.semanticPath,
          built.contentHash,
          watchlist!.cellVersion, // nSequence = prev state version
        );

        // Commit new watchlist state
        watchlist!.cellTxid = result.txid;
        watchlist!.cellVout = 0;
        watchlist!.cellSourceTx = result.tx;
        watchlist!.cellVersion = newVersion;
        watchlist!.prevCellBytes = built.cellBytes;
        watchlist!.prevContentHash = built.contentHash;
        watchlist!.hitCount = newHitCount;
        watchlist!.lastSeenTs = now;
        watchlist!.violationTxids = rollingTxids;
        watchlist!.lastKernelReason = kernelReason.slice(0, 200);
        watchlist!.cellTransitions.push({
          txid: result.txid,
          version: newVersion,
          hitCount: newHitCount,
          kernelValidated: this.validator !== null,
        });
        this.totalWatchlistHits++;

        this.log(
          'WATCHLIST',
          `🔁 ${offenderName} (${offenderIdHex.slice(0, 8)}...): REPEAT OFFENDER v${newVersion}, hitCount=${newHitCount} → ${result.txid.slice(0, 16)}...${this.validator ? ' [2PDA ✓]' : ''}`,
        );

        this.emit('watchlist-hit', channelId, {
          offenderName,
          offenderPubKey: offenderPubKeyHex,
          offenderIdHex,
          hitCount: newHitCount,
          cellVersion: newVersion,
          isFirstHit: false,
          kernelReason: kernelReason.slice(0, 200),
          kernelValidated: this.validator !== null,
          violationTxid,
        }, { txid: result.txid });

        return result.txid;
      }
    } catch (err: any) {
      this.log('WATCHLIST', `⚠ Watchlist update failed for ${offenderName}: ${err.message}`);
      return undefined;
    }
  }

  /**
   * Query the current watchlist entry for an offender (by their pubkey hex).
   * Returns undefined if the offender has no recorded violations.
   *
   * Used by pairing / matchmaking logic (stage-4) to gate repeat offenders.
   */
  getWatchlist(offenderPubKeyHex: string): WatchlistInstance | undefined {
    const ownerHash = createHash('sha256').update(offenderPubKeyHex).digest();
    const offenderIdHex = ownerHash.subarray(0, 16).toString('hex');
    return this.watchlists.get(offenderIdHex);
  }

  /** Get all watchlist entries (all offenders with at least one violation). */
  getAllWatchlists(): WatchlistInstance[] {
    return [...this.watchlists.values()];
  }

  // ── Private ──

  /**
   * Build OP_2 <pubA> <pubB> OP_2 OP_CHECKMULTISIG locking script.
   */
  private build2of2Script(pubA: PublicKey, pubB: PublicKey): LockingScript {
    // encode(true) returns number[] (compressed 33-byte SEC1)
    const pubABytes = pubA.encode(true) as number[];
    const pubBBytes = pubB.encode(true) as number[];

    return new LockingScript([
      { op: 0x52 },  // OP_2
      { op: pubABytes.length, data: pubABytes },  // PUSH <pubA> (33 bytes)
      { op: pubBBytes.length, data: pubBBytes },  // PUSH <pubB> (33 bytes)
      { op: 0x52 },  // OP_2
      { op: 0xae },  // OP_CHECKMULTISIG
    ]);
  }

  /**
   * Build and broadcast a funding transaction for the 2-of-2 multisig.
   * Uses the engine's shared UTXO pool (funded by the arena's pre-split).
   */
  private async buildFundingTx(
    streamId: number,
    multisigScript: LockingScript,
    fundingSats: number,
    config: ChannelConfig,
  ): Promise<{ txid: string; vout: number; tx: Transaction }> {
    // Consume enough UTXOs from the engine's pool to cover the channel funding.
    // Each UTXO is typically ~500 sats (from pre-split). We need fundingSats + fee.
    const fee = 250; // slightly higher fee for multi-input tx
    const needed = fundingSats + fee;

    // Figure out how many UTXOs we need
    // Peek at the pool to see UTXO size (they're all the same from pre-split)
    let consumed: FundingUtxo[] = [];
    let totalIn = 0;
    const maxUtxos = 10; // safety cap

    // Consume UTXOs one at a time until we have enough
    for (let i = 0; i < maxUtxos; i++) {
      try {
        const [utxo] = this.engine.consumeUtxos(streamId, 1);
        consumed.push(utxo);
        totalIn += utxo.satoshis;
        if (totalIn >= needed) break;
      } catch {
        // Pool exhausted — return what we took and throw
        if (consumed.length > 0) this.engine.returnUtxos(streamId, consumed);
        throw new Error(`Stream ${streamId}: insufficient UTXOs for channel funding (need ${needed} sats)`);
      }
    }

    if (totalIn < needed) {
      this.engine.returnUtxos(streamId, consumed);
      throw new Error(`Stream ${streamId}: consumed ${consumed.length} UTXOs (${totalIn} sats) but need ${needed}`);
    }

    const engineKey = this.getEnginePrivKey();
    const engineAddress = this.engine.getFundingAddress();
    const p2pkh = new P2PKH();
    const changeLock = p2pkh.lock(engineAddress);

    const tx = new Transaction();

    // Inputs: all consumed UTXOs
    for (const utxo of consumed) {
      tx.addInput({
        sourceTXID: utxo.txid,
        sourceOutputIndex: utxo.vout,
        sourceTransaction: utxo.sourceTx,
        unlockingScriptTemplate: p2pkh.unlock(engineKey),
      });
    }

    // Output 0: OP_RETURN channel-fund announcement
    const payload = JSON.stringify({
      proto: 'semantos:poker:channel-fund',
      v: 1,
      type: '2-of-2-multisig',
      sats: fundingSats,
      agentA: { name: config.agentA.name, pubKey: config.agentA.pubKey.toString().slice(0, 16) },
      agentB: { name: config.agentB.name, pubKey: config.agentB.pubKey.toString().slice(0, 16) },
      matchTxid: config.matchTxid ?? null,       // ← link back to discovery match
      announceTxA: config.announceTxidA ?? null,  // ← link back to agent A discovery
      announceTxB: config.announceTxidB ?? null,  // ← link back to agent B discovery
      ts: Date.now(),
    });
    const opReturnScript = new LockingScript([
      { op: 0x00 }, // OP_FALSE
      { op: 0x6a }, // OP_RETURN
      { op: payload.length <= 75 ? payload.length : 0x4c, data: Array.from(Buffer.from(payload, 'utf-8')) },
    ]);
    tx.addOutput({ lockingScript: opReturnScript, satoshis: 0 });

    // Output 1: 2-of-2 multisig
    tx.addOutput({
      lockingScript: multisigScript,
      satoshis: fundingSats,
    });

    // Output 2: remaining change back to engine pool
    const remainingChange = totalIn - fundingSats - fee;
    if (remainingChange > 0) {
      tx.addOutput({
        lockingScript: changeLock,
        satoshis: remainingChange,
      });
    }

    await tx.sign();
    const txid = tx.id('hex') as string;

    // Broadcast funding through the bound broadcaster port (ARC by default).
    const broadcastResult = await this.broadcaster.broadcast(tx.toHex());
    if (!broadcastResult.ok) {
      // Return consumed UTXOs on failure (they weren't actually spent)
      this.engine.returnUtxos(streamId, consumed);
      throw new Error(
        `Channel funding broadcast failed: ${broadcastResult.error ?? broadcastResult.status ?? 'unknown'}`,
      );
    }

    this.log('CHANNEL', `Funding tx: ${consumed.length} UTXOs (${totalIn} sats) → ${fundingSats} sats locked, ${remainingChange} change, ${fee} fee`);

    return { txid, vout: 1, tx }; // vout 1 = multisig output (vout 0 = OP_RETURN)
  }

  /**
   * Get the engine's private key for signing change outputs.
   * This is a workaround — in production the engine would expose a signing method.
   */
  private getEnginePrivKey(): PrivateKey {
    // The engine's WIF is available via getPrivateKeyWIF()
    return PrivateKey.fromWif(this.engine.getPrivateKeyWIF());
  }

  private log(label: string, msg: string): void {
    if (this.verbose) {
      console.log(`\x1b[36m[${label}]\x1b[0m ${msg}`);
    }
  }
}

// ── Helpers ──

function hexToBytes(hex: string): Uint8Array {
  const h = hex.length % 2 !== 0 ? '0' + hex : hex;
  const bytes = new Uint8Array(h.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(h.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function sha256Hex(bytes: Uint8Array): string {
  return createHash('sha256').update(Buffer.from(bytes)).digest('hex');
}

/**
 * Apply a deliberate corruption to a freshly-built cell's header so the 2PDA
 * kernel will reject the candidate transition on a specific K-theorem path.
 *
 * This is ONLY for adversarial / red-team testing. Each mode maps cleanly
 * to a single header field so the violation's kernel reason is diagnosable.
 *
 * Header offsets (see packages/cell-engine/src/constants.zig):
 *   0    magic (16 bytes; we clobber the first 4)
 *   16   linearity (4 bytes LE: LINEAR=1, AFFINE=2, RELEVANT=3)
 *   20   version (4 bytes LE)
 *   62   ownerId (16 bytes)
 *   128  prevStateHash (32 bytes, a.k.a. commercePrevState)
 */
/**
 * Map a tamper mode to the K-theorem it's designed to violate.
 * Used by the hypervisor console to label violations with the exact
 * Lean theorem the 2PDA kernel enforced when it caught the tamper.
 */
function tamperModeToKTheorem(mode: TamperMode | undefined): string {
  switch (mode) {
    case 'flip-linearity':      return 'K1 Linearity';
    case 'zero-owner':          return 'K3 Domain Isolation';
    case 'break-prev-hash':     return 'K6 State Continuity';
    case 'bump-version-double': return 'K6 Monotonicity';
    case 'corrupt-magic':       return 'K7 Cell Immutability';
    default:                    return 'kernel invariant';
  }
}

function applyTamper(cellBytes: Uint8Array, mode: TamperMode): Uint8Array {
  const tampered = new Uint8Array(cellBytes);
  const dv = new DataView(tampered.buffer, tampered.byteOffset, tampered.byteLength);
  switch (mode) {
    case 'flip-linearity':
      // LINEAR (1) → AFFINE (2). Breaks K1 linearity preservation.
      dv.setUint32(16, 2, true);
      break;
    case 'zero-owner':
      // Zero the 16-byte ownerId — breaks K3 domain isolation / owner continuity.
      for (let i = 0; i < 16; i++) tampered[62 + i] = 0x00;
      break;
    case 'break-prev-hash':
      // Clobber the 32-byte prevStateHash — breaks K6 state continuity.
      for (let i = 0; i < 32; i++) tampered[128 + i] = 0xAA;
      break;
    case 'bump-version-double':
      // Skip a version (v+2 instead of v+1) — breaks K6 monotonic successor rule.
      dv.setUint32(20, dv.getUint32(20, true) + 1, true);
      break;
    case 'corrupt-magic':
      // Corrupt the magic word — breaks K7 cell immutability / format check.
      dv.setUint32(0, 0xBAADF00D, true);
      break;
  }
  return tampered;
}

```
