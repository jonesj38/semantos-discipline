---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mnca/forwarding-payment.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.898635+00:00
---

# core/protocol-types/src/mnca/forwarding-payment.ts

```ts
/**
 * Forwarding-payment plan — the originator's pre-built, per-hop payment +
 * refund structure for a source-routed cell.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §4.1 (originator
 * builds the routing) + §13.5 (refund path via pre-signed nLockTime'd
 * transactions, BSV-correct).
 *
 * ── BSV CONSTRAINT (memory: bsv_no_cltv_use_nlocktime) ─────────────────
 * BSV's Genesis upgrade restored the original protocol and REMOVED
 * OP_CHECKLOCKTIMEVERIFY (CLTV) and OP_CHECKSEQUENCEVERIFY (CSV). This
 * module emits NO CLTV/CSV script. The timeout/refund mechanism is
 * transaction-level `nLockTime` plus a refund transaction that the hop
 * pre-signs at the funding handshake. The funding output is a plain
 * pushdrop (`<cell> OP_DROP <hop_pubkey> OP_CHECKSIG`) with no timelock
 * opcodes; the timelock lives entirely on the refund tx's nLockTime.
 *
 * ── WHAT THIS MODULE IS NOT ────────────────────────────────────────────
 * Pure data. It does NOT sign anything, does NOT build real BSV
 * transactions (no @bsv/sdk dependency), and does NOT talk to ARC. It
 * produces the typed *plan* a wallet consumes to construct, sign, and
 * broadcast the actual funding tx (and to hold the pre-signed refund tx
 * offline). Satoshi values, scripts, and nLockTime are described; the
 * wallet does the rest.
 *
 * ── §13.5 PATTERN, MODELLED ────────────────────────────────────────────
 *  - Funding tx (broadcast immediately): one output per hop, each a
 *    pushdrop locking the cell + that hop's pubkey, valued at the hop's
 *    forwarding payment. The hop spends it with its own signature once it
 *    has forwarded (no timelock in the script).
 *  - Refund tx (pre-built + co-signed offline at funding time, held by the
 *    originator): spends a funding output back to the originator, with
 *    `nLockTime = T`. Requires BOTH the hop's and the originator's
 *    signatures — the hop pre-authorises the refund as part of accepting
 *    the offer. If the hop delivers before T it spends the funding output
 *    first and the refund becomes worthless; if it fails to deliver, the
 *    originator broadcasts the refund after T.
 */

import { buildPushdropLockingScript } from '../cell-pushdrop';

/** A pushdrop funding output locking a cell to a hop's pubkey. */
export interface FundingOutput {
  /** `<cell> OP_DROP <hop_pubkey> OP_CHECKSIG` locking-script bytes. */
  lockingScript: Uint8Array;
  /** Forwarding payment for this hop, in satoshis. */
  satoshis: bigint;
  /** The hop's pubkey (33 or 65 bytes) that can spend the funding output. */
  hopPubkey: Uint8Array;
}

/**
 * Template for the pre-signed refund tx (§13.5). Describes intent — the
 * wallet builds + co-signs the real tx. No script-level timelock: the
 * lock is the tx-level `nLockTime`.
 */
export interface RefundTemplate {
  /** True — the refund spends the funding output of the same plan. */
  spendsFundingOutput: true;
  /** Locking script the refund pays back to (the originator's script). */
  refundToScript: Uint8Array;
  /**
   * Transaction-level nLockTime T. Interpreted by the wallet per BSV
   * nLockTime semantics (block height < 5e8, else unix time). The refund
   * is only minable at/after T.
   */
  nLockTime: number;
  /**
   * Signatures that must be collected at the funding handshake, before
   * the funding tx is broadcast. BOTH parties sign the refund up front.
   */
  requiresSignatures: readonly ['hop', 'originator'];
}

/** The full per-hop plan: how to pay the hop + how to reclaim on timeout. */
export interface ForwardingPaymentPlan {
  /** Index of this hop in the path (aligns with typed-segments / spendSegmentIndex). */
  hopIndex: number;
  funding: FundingOutput;
  refund: RefundTemplate;
}

export interface BuildForwardingPaymentPlanInput {
  /** The 1024-byte cell bytes wrapped into the pushdrop funding output. */
  cellBytes: Uint8Array;
  /** The hop's pubkey (33 compressed or 65 uncompressed). */
  hopPubkey: Uint8Array;
  /** Forwarding payment for this hop, in satoshis (> 0). */
  paymentSats: bigint;
  /** Locking script the refund pays back to the originator. */
  originatorRefundScript: Uint8Array;
  /** Transaction-level nLockTime T for the refund. */
  nLockTime: number;
  /** This hop's index in the path. Defaults to 0. */
  hopIndex?: number;
}

/**
 * Build a single hop's forwarding-payment plan: a pushdrop funding output
 * locking the cell to the hop's pubkey, plus the nLockTime refund template.
 */
export function buildForwardingPaymentPlan(
  input: BuildForwardingPaymentPlanInput,
): ForwardingPaymentPlan {
  const {
    cellBytes,
    hopPubkey,
    paymentSats,
    originatorRefundScript,
    nLockTime,
    hopIndex = 0,
  } = input;

  if (paymentSats <= 0n) {
    throw new Error(`buildForwardingPaymentPlan: paymentSats must be > 0 (got ${paymentSats})`);
  }
  if (nLockTime < 0 || !Number.isInteger(nLockTime)) {
    throw new Error(`buildForwardingPaymentPlan: nLockTime must be a non-negative integer (got ${nLockTime})`);
  }
  if (originatorRefundScript.length === 0) {
    throw new Error('buildForwardingPaymentPlan: originatorRefundScript must be non-empty');
  }

  // The funding output is a plain pushdrop — NO timelock opcodes. (CLTV/CSV
  // are not available on BSV; the timelock lives on the refund tx's
  // nLockTime, not in this script.)
  const lockingScript = buildPushdropLockingScript(cellBytes, hopPubkey);

  return {
    hopIndex,
    funding: {
      lockingScript,
      satoshis: paymentSats,
      hopPubkey: hopPubkey.slice(),
    },
    refund: {
      spendsFundingOutput: true,
      refundToScript: originatorRefundScript.slice(),
      nLockTime,
      requiresSignatures: ['hop', 'originator'] as const,
    },
  };
}

export interface HopPayment {
  /** The hop's pubkey (33 or 65 bytes). */
  hopPubkey: Uint8Array;
  /** Forwarding payment for this hop, in satoshis. */
  paymentSats: bigint;
}

export interface BuildPathPaymentPlansInput {
  /** The cell bytes wrapped into every hop's funding output. */
  cellBytes: Uint8Array;
  /** Ordered per-hop payments. plans[i] corresponds to path hop i. */
  hops: HopPayment[];
  /** Locking script the refunds pay back to the originator. */
  originatorRefundScript: Uint8Array;
  /** Transaction-level nLockTime T for all refunds. */
  nLockTime: number;
}

/**
 * Build one forwarding-payment plan per hop (§4.1 steps 3–4: the
 * originator pre-builds N pushdrop outputs, one per hop). The returned
 * array is index-aligned with the path: `plans[i]` funds the hop the
 * originator placed at typed-segment index `i`, which is the same index
 * `processHop` returns as `spendSegmentIndex` when that hop forwards.
 * So a relay at segment index `i` claims `plans[i].funding`.
 */
export function buildPathPaymentPlans(
  input: BuildPathPaymentPlansInput,
): ForwardingPaymentPlan[] {
  const { cellBytes, hops, originatorRefundScript, nLockTime } = input;
  if (hops.length === 0) {
    throw new Error('buildPathPaymentPlans: at least one hop required');
  }
  return hops.map((hop, i) =>
    buildForwardingPaymentPlan({
      cellBytes,
      hopPubkey: hop.hopPubkey,
      paymentSats: hop.paymentSats,
      originatorRefundScript,
      nLockTime,
      hopIndex: i,
    }),
  );
}

/** Total path cost = sum of every hop's forwarding payment, in satoshis. */
export function totalPathCostSats(plans: ForwardingPaymentPlan[]): bigint {
  return plans.reduce((sum, p) => sum + p.funding.satoshis, 0n);
}

/**
 * Validate that a refund nLockTime is in the future relative to `now`.
 * `now` and `nLockTime` must be in the same unit (both block heights, or
 * both unix seconds). Returns true when `nLockTime > now`.
 *
 * A refund whose nLockTime is already in the past would be immediately
 * minable, defeating the "give the hop a chance to deliver first" intent.
 */
export function isRefundLockTimeInFuture(plan: ForwardingPaymentPlan, now: number): boolean {
  return plan.refund.nLockTime > now;
}

```
