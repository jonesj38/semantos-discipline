---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mfp/flow-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.868565+00:00
---

# core/protocol-types/src/mfp/flow-adapter.ts

```ts
/**
 * MFP consumer-side flow adapter.
 *
 * The device (e.g. a $4 C6 actuator) is the trusted meter and the
 * verifier — it measures commodity usage and only acts while it holds a
 * signed commitment covering the consumed value. This adapter is the
 * *consumer* half: given a BRC-100 `WalletPort`, it keeps the payment
 * channel funded from a Tier-0 budget grant (scoped by the MFP
 * protocolID) and signs commitments acknowledging the device's reported
 * consumption — until the granted cap is exhausted.
 *
 * Two funding modes (one adapter):
 *   - "block":   bounded, known quantity ("8 hours of light"). A single
 *                signed grant; NO channel. Cheapest. The device draws
 *                against the grant until the bound is consumed.
 *   - "metered": open-ended ("charged while the switch is on"). A
 *                prepaid draining channel, auto-refilled from the Tier-0
 *                vault when low, exhausting when the cap is hit.
 *
 * The adapter is transport-agnostic: it returns commitment / grant
 * objects and the caller wires them to the mesh (or an HTTP↔cell
 * bridge for an x402 client). It never holds keys — all signing goes
 * through the injected WalletPort, which fronts whichever BRC-100 wallet
 * the consumer runs (Metanet Desktop, browser iframe, embedded agent).
 *
 * Cross-refs: docs/design/WALLET-TIER-CUSTODY.md §7.1 (Tier-0 no-prompt
 * budget), esp32-hackkit/docs/x402-over-cells.md (cell-mesh binding),
 * core/protocol-types/src/mfp/protocol-id.ts (the protocolID).
 */

import type { WalletProtocol } from '@bsv/sdk';
import { mfpProtocolID, mfpKeyID } from './protocol-id.js';

export type FundMode = 'block' | 'metered';

export interface MfpFlowConfig {
  /** Commodity being metered, e.g. "energy.wh", "bandwidth.mb". */
  commodityId: string;
  /** Value rate applied pro-rata: cost = unitsConsumed × ratePerUnitSats. */
  ratePerUnitSats: number;
  /** Provider identity key (compressed pubkey hex) — the counterparty. */
  counterparty: string;
  /** Opaque per-flow id (e.g. 16-byte hex). Scopes the BRC-42 keyID. */
  flowId: string;

  fundMode: FundMode;

  // ── metered-mode config ──
  /** Tier-0 spending cap for this flow — the single grant decision. */
  vaultCapSats?: bigint;
  /** How much to commit per funding/refill createAction. */
  channelChunkSats?: bigint;
  /** Refill when (funded − consumed) drops below this. */
  refillThresholdSats?: bigint;

  // ── block-mode config ──
  /** Bounded quantity for a block grant (units). */
  blockUnits?: number;
}

export type FlowStatus = 'idle' | 'open' | 'active' | 'exhausted' | 'closed';

export interface MfpFlowState {
  status: FlowStatus;
  /** Total committed into the channel (or the block grant amount). */
  fundedSats: bigint;
  /** Pro-rata cost accrued from the device's reported consumption. */
  consumedSats: bigint;
  /** Total drawn from the Tier-0 cap so far. */
  vaultDrawnSats: bigint;
  /** Monotonic channel-commitment sequence (= nSequence). */
  seq: number;
  /** Latest cumulative units the device has reported. */
  unitsConsumed: number;
}

/** A signed channel commitment the consumer hands back to the device. */
export interface ChannelCommitment {
  flowId: string;
  seq: number;
  cumulativeSats: bigint;
  /** ECDSA signature over the commitment preimage (from the WalletPort). */
  signature: Uint8Array;
}

/** A one-shot signed grant (block mode — no channel). */
export interface BlockGrant {
  flowId: string;
  maxUnits: number;
  maxSats: bigint;
  signature: Uint8Array;
}

/** Result of feeding the adapter a device consumption report. */
export type FlowStep =
  | { kind: 'commitment'; commitment: ChannelCommitment; state: MfpFlowState }
  | { kind: 'exhausted'; state: MfpFlowState }      // cap hit / vault empty → device should cut off
  | { kind: 'noop'; state: MfpFlowState };          // nothing to do this report

// ── BRC-100 wallet seam ──────────────────────────────────────────────
//
// Modeled on the wallet-headers dispatcher surface (createAction with
// tier classification, createSignature under the BRC-42 tuple). The
// adapter only needs these two. The wallet enforces the Tier-0 cap:
// draws under the cap return ok with no prompt; over the cap return
// { ok:false, reason:'cap_exceeded' } (or 'tier_locked' if a higher
// tier factor is required to raise it).

export interface WalletCreateActionArgs {
  protocolID: WalletProtocol;
  keyID: string;
  counterparty: string;
  amountSats: bigint;
  description: string;
}
export type WalletCreateActionResult =
  | { ok: true; txid: string; committedSats: bigint }
  | { ok: false; reason: 'cap_exceeded' | 'tier_locked' | string };

export interface WalletCreateSignatureArgs {
  protocolID: WalletProtocol;
  keyID: string;
  counterparty: string;
  data: Uint8Array;
}
export type WalletCreateSignatureResult =
  | { ok: true; signature: Uint8Array }
  | { ok: false; reason: string };

export interface WalletPort {
  createAction(args: WalletCreateActionArgs): Promise<WalletCreateActionResult>;
  createSignature(args: WalletCreateSignatureArgs): Promise<WalletCreateSignatureResult>;
}

// ── The adapter ──────────────────────────────────────────────────────

export class MfpFlowAdapter {
  private readonly protocolID: WalletProtocol;
  private readonly keyID: string;
  private state: MfpFlowState = {
    status: 'idle',
    fundedSats: 0n,
    consumedSats: 0n,
    vaultDrawnSats: 0n,
    seq: 0,
    unitsConsumed: 0,
  };

  constructor(
    private readonly cfg: MfpFlowConfig,
    private readonly wallet: WalletPort,
  ) {
    this.protocolID = mfpProtocolID(cfg.commodityId);
    this.keyID = mfpKeyID(cfg.flowId);
    if (cfg.fundMode === 'metered') {
      if (cfg.vaultCapSats == null || cfg.channelChunkSats == null) {
        throw new Error('metered mode requires vaultCapSats + channelChunkSats');
      }
    } else if (cfg.blockUnits == null) {
      throw new Error('block mode requires blockUnits');
    }
  }

  getState(): Readonly<MfpFlowState> {
    return this.state;
  }

  /**
   * Open the flow. block → a single signed grant (no channel). metered →
   * fund the channel with the first chunk drawn from the Tier-0 vault.
   */
  async open(): Promise<BlockGrant | { kind: 'opened'; state: MfpFlowState } | { kind: 'exhausted' }> {
    if (this.state.status !== 'idle') {
      throw new Error(`open() in status ${this.state.status}`);
    }
    if (this.cfg.fundMode === 'block') {
      // One signed grant: "you may draw up to blockUnits = maxSats."
      const maxUnits = this.cfg.blockUnits!;
      const maxSats = BigInt(Math.ceil(maxUnits * this.cfg.ratePerUnitSats));
      const sig = await this.wallet.createSignature({
        protocolID: this.protocolID,
        keyID: this.keyID,
        counterparty: this.cfg.counterparty,
        data: encodeBlockGrant(this.cfg.flowId, maxUnits, maxSats),
      });
      if (!sig.ok) return { kind: 'exhausted' };
      this.state.status = 'active';
      this.state.fundedSats = maxSats;
      return { flowId: this.cfg.flowId, maxUnits, maxSats, signature: sig.signature };
    }

    // metered: draw the first chunk from the vault into the channel.
    const drew = await this.drawFromVault(this.cfg.channelChunkSats!);
    if (!drew) {
      this.state.status = 'exhausted';
      return { kind: 'exhausted' };
    }
    this.state.status = 'active';
    return { kind: 'opened', state: this.state };
  }

  /**
   * Feed the device's latest cumulative consumption (units). The adapter
   * accrues pro-rata cost, refills the channel from the vault if it's
   * running low, and (metered) returns a fresh signed commitment for the
   * device. Returns 'exhausted' when the cap can no longer cover cost.
   */
  async onConsumptionReport(cumulativeUnits: number): Promise<FlowStep> {
    if (this.state.status !== 'active') {
      return { kind: 'noop', state: this.state };
    }
    if (cumulativeUnits < this.state.unitsConsumed) {
      // device reported a lower total than before — ignore (no rollback)
      return { kind: 'noop', state: this.state };
    }
    this.state.unitsConsumed = cumulativeUnits;
    const cost = BigInt(Math.ceil(cumulativeUnits * this.cfg.ratePerUnitSats));
    this.state.consumedSats = cost;

    // block mode: no channel, no commitments. Just enforce the bound.
    if (this.cfg.fundMode === 'block') {
      if (cost > this.state.fundedSats) {
        this.state.status = 'exhausted';
        return { kind: 'exhausted', state: this.state };
      }
      return { kind: 'noop', state: this.state };
    }

    // metered: keep the channel funded ahead of consumption.
    const threshold = this.cfg.refillThresholdSats ?? 0n;
    while (this.state.fundedSats - cost < threshold) {
      const drew = await this.drawFromVault(this.cfg.channelChunkSats!);
      if (!drew) {
        // Can't fund the consumed amount → exhausted. The device will
        // stop seeing fresh commitments and cut off.
        this.state.status = 'exhausted';
        return { kind: 'exhausted', state: this.state };
      }
    }

    // Sign a fresh commitment acknowledging cumulative cost.
    this.state.seq += 1;
    const sig = await this.wallet.createSignature({
      protocolID: this.protocolID,
      keyID: this.keyID,
      counterparty: this.cfg.counterparty,
      data: encodeCommitment(this.cfg.flowId, this.state.seq, cost),
    });
    if (!sig.ok) {
      this.state.seq -= 1;
      return { kind: 'noop', state: this.state };
    }
    return {
      kind: 'commitment',
      commitment: {
        flowId: this.cfg.flowId,
        seq: this.state.seq,
        cumulativeSats: cost,
        signature: sig.signature,
      },
      state: this.state,
    };
  }

  /** Close the flow (settlement happens via the final commitment). */
  close(): MfpFlowState {
    if (this.state.status !== 'closed') this.state.status = 'closed';
    return this.state;
  }

  // Draw `chunk` sats from the Tier-0 vault into the channel via the
  // wallet's createAction. Returns false when the wallet denies (cap
  // exceeded / tier locked) — the exhaustion signal.
  private async drawFromVault(chunk: bigint): Promise<boolean> {
    const cap = this.cfg.vaultCapSats!;
    if (this.state.vaultDrawnSats + chunk > cap) {
      // Last partial draw up to the cap, if any room remains.
      const remaining = cap - this.state.vaultDrawnSats;
      if (remaining <= 0n) return false;
      chunk = remaining;
    }
    const res = await this.wallet.createAction({
      protocolID: this.protocolID,
      keyID: this.keyID,
      counterparty: this.cfg.counterparty,
      amountSats: chunk,
      description: `mfp refill ${this.cfg.commodityId} flow ${this.cfg.flowId}`,
    });
    if (!res.ok) return false;
    this.state.vaultDrawnSats += res.committedSats;
    this.state.fundedSats += res.committedSats;
    if (this.state.status === 'idle') this.state.status = 'open';
    return true;
  }
}

// ── Commitment / grant encoders (stable wire for the device) ─────────

/** seq(4 LE) || cumulativeSats(8 LE) || flowId(utf8). */
export function encodeCommitment(flowId: string, seq: number, cumulativeSats: bigint): Uint8Array {
  const fid = new TextEncoder().encode(flowId);
  const buf = new Uint8Array(4 + 8 + fid.length);
  const dv = new DataView(buf.buffer);
  dv.setUint32(0, seq, true);
  dv.setBigUint64(4, cumulativeSats, true);
  buf.set(fid, 12);
  return buf;
}

/** maxUnits(4 LE) || maxSats(8 LE) || flowId(utf8). */
export function encodeBlockGrant(flowId: string, maxUnits: number, maxSats: bigint): Uint8Array {
  const fid = new TextEncoder().encode(flowId);
  const buf = new Uint8Array(4 + 8 + fid.length);
  const dv = new DataView(buf.buffer);
  dv.setUint32(0, maxUnits, true);
  dv.setBigUint64(4, maxSats, true);
  buf.set(fid, 12);
  return buf;
}

```
