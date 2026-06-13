---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/paid-seeder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.053580+00:00
---

# runtime/session-protocol/src/swarm/paid-seeder.ts

```ts
/**
 * Paid loop — serve-this-cached-cell-for-sats.
 *
 * v1 uses a PREPAY model: the leecher signs a spend before requesting and
 * attaches the `txAnchor` to the REQUEST; the seeder verifies the payment via
 * `EconomicPort.verifyPayment` BEFORE serving. This avoids serve-then-stiff.
 * The residual risk (a leecher pays for a cell a malicious seeder never
 * delivers) is bounded by small per-cell amounts + ban-on-bad-merkle (only
 * verified cells count) — escrow/streaming payment is out of scope for v1.
 *
 *   leecher: PayPolicy   — signSpend → attach txAnchor to the request
 *   seeder:  PaidSeeder  — verifyPayment → serve + record a receipt
 *
 * Settlement: the seeder accumulates receipts in memory and `drainReceipts()`
 * hands a batch to `SwarmSession.flushReceipts()` → brain `swarm.settle` (cold
 * path, batched — never per cell on the wire).
 */

import { fromHex, toHex, type SwarmManifest } from '@semantos/protocol-types';
import type { EconomicPort } from '@semantos/identity-ports';
import type { ServePolicy, PayPolicy } from './swarm-session';
import type { SwarmRequest } from './swarm-wire';
import type { SwarmReceipt } from './brain-client';

const SATS = 'sat';

/**
 * Leecher-side pay policy: sign a per-cell spend and attach it to the request.
 * `targetId` for the spend is the seeder's transport address (cross-internet
 * deployments would use the seeder's cert id).
 */
export function makePayPolicy(opts: {
  economic: EconomicPort;
  payerCertId: string;
  pricePerCellSats: number;
  currency?: string;
  /** Override the spend target. With a real (on-chain) EconomicPort this MUST
   *  be the seeder's payment pubkey hex; defaults to the transport address. */
  payeeId?: string;
}): PayPolicy {
  const currency = opts.currency ?? SATS;
  return {
    async payFor(infohash, cellIndex, seederAddress) {
      const spend = await opts.economic.signSpend({
        payerCertId: opts.payerCertId,
        targetId: opts.payeeId ?? seederAddress,
        amount: opts.pricePerCellSats,
        currency,
        memo: `${toHex(infohash)}:${cellIndex}`,
      });
      const anchor = fromHex(spend.txAnchor);
      if (anchor.length !== 32) {
        throw new Error(`makePayPolicy: txAnchor must be a 32-byte (64-hex) reference, got ${anchor.length}B`);
      }
      return { payment: { txAnchor: anchor, amount: BigInt(spend.amount), currency: spend.currency } };
    },
  };
}

/**
 * Seeder-side serve gate: require a valid prepayment of at least the quoted
 * price, then authorise the serve and record a receipt for later settlement.
 */
export class PaidSeeder implements ServePolicy {
  private readonly economic: EconomicPort;
  private readonly pricePerCellSats: number;
  private readonly currency: string;
  private readonly receipts: SwarmReceipt[] = [];
  /** Guards against double-counting a replayed txAnchor for the same cell. */
  private readonly settledKeys = new Set<string>();

  constructor(opts: { economic: EconomicPort; pricePerCellSats: number; currency?: string }) {
    this.economic = opts.economic;
    this.pricePerCellSats = opts.pricePerCellSats;
    this.currency = opts.currency ?? SATS;
  }

  async authorizeServe(req: SwarmRequest): Promise<boolean> {
    const pay = req.payment;
    if (!pay) return false; // no prepayment → refuse
    if (pay.currency !== this.currency) return false;
    if (pay.amount < BigInt(this.pricePerCellSats)) return false; // underpaid

    const txAnchor = toHex(pay.txAnchor);
    const verification = await this.economic.verifyPayment({
      txAnchor,
      amount: Number(pay.amount),
      currency: pay.currency,
    });
    if (!verification.valid) return false;

    const key = `${txAnchor}:${req.cellIndex}`;
    if (!this.settledKeys.has(key)) {
      this.settledKeys.add(key);
      this.receipts.push({
        cellIndex: req.cellIndex,
        payerCertId: toHex(req.requesterBca),
        txAnchor,
        amount: Number(pay.amount),
        currency: pay.currency,
      });
    }
    return true;
  }

  /** Hand off the accumulated receipts (and clear them) for batched settle. */
  drainReceipts(): SwarmReceipt[] {
    const batch = this.receipts.splice(0, this.receipts.length);
    return batch;
  }

  /** Total sats collected so far (for introspection/tests). */
  collectedSats(): number {
    return this.receipts.reduce((acc, r) => acc + r.amount, 0);
  }
}

/**
 * Quote a per-cell price for a file. v1 returns a flat price; a richer
 * implementation would read it from a signed `RelayAdvertisement` on
 * `tm_mnca_relay_ads`. `_manifest` is accepted so callers can later price by
 * size/scarcity without a signature change.
 */
export function quotePricePerCell(_manifest: SwarmManifest, flatPriceSats: number): number {
  return flatPriceSats;
}

```
