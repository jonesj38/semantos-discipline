---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/metered-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.056132+00:00
---

# runtime/session-protocol/src/swarm/metered-flow.ts

```ts
/**
 * Metered-flow payment for the swarm — the channel alternative to one tx/cell.
 *
 * Built on the Metered Flow Protocol (core/protocol-types/src/mfp). The leecher
 * opens ONE payment channel with a seeder, then signs a `ChannelCommitment`
 * per cell (cumulative sats grow by the price each cell) entirely OFF-CHAIN.
 * The seeder verifies each commitment's BRC-100 signature + that the cumulative
 * covers the cells served, and serves immediately — no on-chain wait per cell.
 *
 * So an N-cell paid download is: 1 on-chain channel funding + N off-chain
 * signed commitments + 1 on-chain settlement — vs the per-cell model's N txs.
 *
 * Crypto is real (ProtoWallet ECDSA under the MFP BRC-42 tuple); no money moves
 * for the commitments themselves. Channel funding/settlement is the on-chain
 * seam (headless wallet — proven separately).
 */

import { ProtoWallet, PrivateKey, type WalletProtocol } from '@bsv/sdk';
import {
  MfpFlowAdapter,
  mfpProtocolID,
  mfpKeyID,
  encodeCommitment,
  type WalletPort,
  type MfpFlowConfig,
  type ChannelCommitment,
  type FlowStep,
} from '@semantos/protocol-types';

const toArr = (u: Uint8Array): number[] => Array.from(u);
const fromArr = (a: number[]): Uint8Array => Uint8Array.from(a);

/**
 * An MFP WalletPort backed by a ProtoWallet (real ECDSA). `createSignature`
 * signs commitments; `createAction` is the on-chain funding-draw seam — here it
 * just authorises the draw (a production binding funds a real channel). The
 * off-chain commitment signatures are real either way.
 */
export function protoWalletPort(privKey: PrivateKey): WalletPort {
  const proto = new ProtoWallet(privKey);
  return {
    async createAction(args) {
      // Funding decision (Tier-0 cap). On-chain funding is the headless-wallet
      // seam; the channel is authorised to `amountSats` here.
      return { ok: true, txid: 'channel-funding', committedSats: args.amountSats };
    },
    async createSignature(args) {
      const { signature } = await proto.createSignature({
        protocolID: args.protocolID,
        keyID: args.keyID,
        counterparty: args.counterparty,
        data: toArr(args.data),
      });
      return { ok: true, signature: fromArr(signature) };
    },
  };
}

/** Leecher side: open a channel, emit a signed commitment per cell. */
export class MeteredFlowPayer {
  private readonly adapter: MfpFlowAdapter;
  constructor(private readonly cfg: MfpFlowConfig, wallet: WalletPort) {
    this.adapter = new MfpFlowAdapter(cfg, wallet);
  }
  open() {
    return this.adapter.open();
  }
  /** Commit for `cumulativeCells` cells delivered so far → fresh commitment. */
  commit(cumulativeCells: number): Promise<FlowStep> {
    return this.adapter.onConsumptionReport(cumulativeCells);
  }
  state() {
    return this.adapter.getState();
  }
}

/**
 * Seeder side: verify a leecher's commitment. The leecher signed under
 * (mfpProtocolID(commodity), mfpKeyID(flowId), counterparty=seeder); the seeder
 * verifies with counterparty = the leecher's identity pubkey (BRC-42 symmetry).
 */
export class MeteredFlowVerifier {
  private readonly proto: ProtoWallet;
  private readonly protocolID: WalletProtocol;
  constructor(
    seederPrivKey: PrivateKey,
    private readonly commodityId: string,
    private readonly ratePerUnitSats: number,
  ) {
    this.proto = new ProtoWallet(seederPrivKey);
    this.protocolID = mfpProtocolID(commodityId);
  }

  /**
   * True iff the commitment's signature is valid for `payerIdentityPubHex` AND
   * its cumulative covers `cellsOwed × rate`.
   */
  async verify(commitment: ChannelCommitment, payerIdentityPubHex: string, cellsOwed: number): Promise<boolean> {
    const owed = BigInt(Math.ceil(cellsOwed * this.ratePerUnitSats));
    if (commitment.cumulativeSats < owed) return false;
    const preimage = encodeCommitment(commitment.flowId, commitment.seq, commitment.cumulativeSats);
    try {
      const { valid } = await this.proto.verifySignature({
        protocolID: this.protocolID,
        keyID: mfpKeyID(commitment.flowId),
        counterparty: payerIdentityPubHex,
        data: toArr(preimage),
        signature: toArr(commitment.signature),
      });
      return valid;
    } catch {
      return false;
    }
  }
}

// ── SwarmSession policies (wire the channel into the live download) ────────────

import type { PayPolicy, ServePolicy } from './swarm-session';
import type { SwarmRequest } from './swarm-wire';

/**
 * Leecher PayPolicy: emit a fresh signed commitment per distinct cell (the
 * cumulative grows by the price each cell). Attaches it to the REQUEST instead
 * of a per-cell tx. Returns null when the channel is exhausted → the seeder
 * sees no proof and refuses.
 */
export function meteredFlowPayPolicy(payer: MeteredFlowPayer): PayPolicy {
  const paid = new Set<number>();
  // The MfpFlowAdapter is a stateful monotonic meter — serialise commits so
  // concurrent in-flight requests don't race seq/cumulative (a reordered lower
  // report returns noop → no commitment → the cell would be refused).
  let chain: Promise<unknown> = Promise.resolve();
  return {
    payFor(_infohash, cellIndex) {
      const run = chain.then(async () => {
        paid.add(cellIndex); // Set dedups retries (same cumulative re-signed)
        const step = await payer.commit(paid.size);
        if (step.kind !== 'commitment') return null;
        const c = step.commitment;
        return { commitment: { flowId: c.flowId, seq: c.seq, cumulativeSats: c.cumulativeSats, signature: c.signature } };
      });
      chain = run.then(() => {}, () => {});
      return run;
    },
  };
}

/**
 * Seeder ServePolicy: verify the request's commitment off-chain (signature +
 * cumulative covers cells served so far) before serving. Tracks the highest
 * commitment for the single on-chain settlement.
 */
export class MeteredFlowServePolicy implements ServePolicy {
  private readonly served = new Set<number>();
  private maxCumulative = 0n;
  private latest: ChannelCommitment | null = null;
  constructor(
    private readonly verifier: MeteredFlowVerifier,
    private readonly payerIdentityPubHex: string,
    private readonly ratePerUnitSats: number,
  ) {}

  async authorizeServe(req: SwarmRequest): Promise<boolean> {
    if (!req.commitment) return false;
    // Signature check only (cellsOwed=0); cumulative accounting is below, so
    // out-of-order commitments still advance the channel correctly.
    if (!(await this.verifier.verify(req.commitment, this.payerIdentityPubHex, 0))) return false;
    if (req.commitment.cumulativeSats > this.maxCumulative) {
      this.maxCumulative = req.commitment.cumulativeSats;
      this.latest = req.commitment;
    }
    const owed = BigInt(Math.ceil((this.served.size + (this.served.has(req.cellIndex) ? 0 : 1)) * this.ratePerUnitSats));
    if (this.maxCumulative < owed) return false; // channel hasn't authorised this cell yet
    this.served.add(req.cellIndex);
    return true;
  }

  /** Cells served under the channel. */
  servedCount(): number {
    return this.served.size;
  }
  /** Highest commitment received — the amount to settle on-chain (one tx). */
  finalCommitment(): ChannelCommitment | null {
    return this.latest;
  }
}

/** One registered channel: a flowId scoped to a specific payer's identity. */
export interface ChannelRegistration {
  flowId: string;
  payerIdentityPubHex: string;
}

interface ChannelState {
  payerPub: string;
  served: Set<number>;
  maxCumulative: bigint;
  latest: ChannelCommitment | null;
}

/**
 * Seeder ServePolicy that manages MANY metered-flow channels at once — one per
 * leecher, keyed by flowId. Each commitment is routed to its channel and
 * verified against THAT channel's registered payer; per-channel state (served
 * cells, owed sats, final commitment) is tracked independently so every channel
 * settles on its own. A request for an unregistered flowId is refused.
 */
export class MultiChannelServePolicy implements ServePolicy {
  private readonly channels = new Map<string, ChannelState>();
  constructor(
    private readonly verifier: MeteredFlowVerifier,
    private readonly ratePerUnitSats: number,
    registrations: ChannelRegistration[] = [],
  ) {
    for (const r of registrations) this.register(r.flowId, r.payerIdentityPubHex);
  }

  /** Open/register a channel (the "funding"/open handshake). */
  register(flowId: string, payerIdentityPubHex: string): void {
    if (!this.channels.has(flowId)) {
      this.channels.set(flowId, { payerPub: payerIdentityPubHex, served: new Set(), maxCumulative: 0n, latest: null });
    }
  }

  async authorizeServe(req: SwarmRequest): Promise<boolean> {
    if (!req.commitment) return false;
    const ch = this.channels.get(req.commitment.flowId);
    if (!ch) return false; // unknown / unfunded channel
    if (!(await this.verifier.verify(req.commitment, ch.payerPub, 0))) return false; // signature
    if (req.commitment.cumulativeSats > ch.maxCumulative) {
      ch.maxCumulative = req.commitment.cumulativeSats;
      ch.latest = req.commitment;
    }
    const owed = BigInt(Math.ceil((ch.served.size + (ch.served.has(req.cellIndex) ? 0 : 1)) * this.ratePerUnitSats));
    if (ch.maxCumulative < owed) return false;
    ch.served.add(req.cellIndex);
    return true;
  }

  /** Snapshot of every channel: flowId → cells served + owed sats. */
  channelSummary(): Array<{ flowId: string; cellsServed: number; owedSats: bigint }> {
    return [...this.channels].map(([flowId, ch]) => ({ flowId, cellsServed: ch.served.size, owedSats: ch.maxCumulative }));
  }
  /** The settlement commitment for one channel. */
  finalCommitment(flowId: string): ChannelCommitment | null {
    return this.channels.get(flowId)?.latest ?? null;
  }
}

export { PrivateKey };

```
