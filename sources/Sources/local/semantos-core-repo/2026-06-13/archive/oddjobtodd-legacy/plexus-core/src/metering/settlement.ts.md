---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/oddjobtodd-legacy/plexus-core/src/metering/settlement.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.981064+00:00
---

# archive/oddjobtodd-legacy/plexus-core/src/metering/settlement.ts

```ts
/**
 * Settlement and tick proof computation for metering channels.
 */

import { Hash } from '@bsv/sdk';

/**
 * A proof that a tick occurred and the cumulative payment was recorded.
 */
export interface TickProof {
  channelId: string;
  tick: number;
  cumulativeSatoshis: number;
  hmac: string; // hex
  timestamp: number;
}

/**
 * A batch of ticks ready for settlement.
 */
export interface SettlementBatch {
  channelId: string;
  fromTick: number;
  toTick: number;
  totalSatoshis: number;
  providerSignature: string | null; // hex
  consumerSignature: string | null; // hex
  settlementTxId: string | null;
  proofs: TickProof[];
}

/**
 * Converts Uint8Array to hex string.
 */
function uint8ArrayToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Converts hex string to Uint8Array.
 */
function hexToUint8Array(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return bytes;
}

/**
 * Computes an HMAC-SHA256 tick proof.
 * The message is `${channelId}:${tick}:${cumulativeSatoshis}` keyed by sharedSecret.
 *
 * @param channelId - The channel identifier
 * @param tick - The tick number
 * @param cumulativeSatoshis - Cumulative satoshis for this tick
 * @param sharedSecret - The shared secret (key for HMAC)
 * @returns TickProof with computed HMAC
 */
export async function computeTickProof(
  channelId: string,
  tick: number,
  cumulativeSatoshis: number,
  sharedSecret: Uint8Array
): Promise<TickProof> {
  const message = `${channelId}:${tick}:${cumulativeSatoshis}`;
  const messageBytes = new TextEncoder().encode(message);

  // Use @bsv/sdk's HMAC-SHA256
  const hmacDigest = Hash.sha256hmac(sharedSecret, messageBytes);
  const hmac = uint8ArrayToHex(new Uint8Array(hmacDigest));

  return {
    channelId,
    tick,
    cumulativeSatoshis,
    hmac,
    timestamp: Date.now(),
  };
}

/**
 * Verifies a tick proof by recomputing the HMAC and comparing.
 * Uses constant-time comparison to prevent timing attacks.
 *
 * @param proof - The proof to verify
 * @param sharedSecret - The shared secret
 * @returns true if valid, false otherwise
 */
export async function verifyTickProof(
  proof: TickProof,
  sharedSecret: Uint8Array
): Promise<boolean> {
  const computed = await computeTickProof(
    proof.channelId,
    proof.tick,
    proof.cumulativeSatoshis,
    sharedSecret
  );

  return constantTimeCompare(proof.hmac, computed.hmac);
}

/**
 * Constant-time comparison to prevent timing attacks.
 */
function constantTimeCompare(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }

  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

/**
 * Creates a settlement batch from an array of tick proofs.
 * The batch aggregates proofs from the first to the last tick.
 *
 * @param channelId - The channel identifier
 * @param proofs - Array of TickProof objects (should be sorted by tick)
 * @returns SettlementBatch
 */
export function createSettlementBatch(
  channelId: string,
  proofs: TickProof[]
): SettlementBatch {
  if (proofs.length === 0) {
    return {
      channelId,
      fromTick: 0,
      toTick: 0,
      totalSatoshis: 0,
      providerSignature: null,
      consumerSignature: null,
      settlementTxId: null,
      proofs: [],
    };
  }

  const sorted = [...proofs].sort((a, b) => a.tick - b.tick);
  const first = sorted[0];
  const last = sorted[sorted.length - 1];
  const totalSatoshis = last.cumulativeSatoshis;

  return {
    channelId,
    fromTick: first.tick,
    toTick: last.tick,
    totalSatoshis,
    providerSignature: null,
    consumerSignature: null,
    settlementTxId: null,
    proofs: sorted,
  };
}

/**
 * Checks if a settlement batch is complete.
 * A batch is complete when both parties have signed and a settlement tx exists.
 *
 * @param batch - The batch to check
 * @returns true if both signatures and txId are present
 */
export function isSettlementComplete(batch: SettlementBatch): boolean {
  return (
    batch.providerSignature !== null &&
    batch.consumerSignature !== null &&
    batch.settlementTxId !== null
  );
}

```
