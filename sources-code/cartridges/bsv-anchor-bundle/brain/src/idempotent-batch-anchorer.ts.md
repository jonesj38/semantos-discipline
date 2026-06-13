---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/src/idempotent-batch-anchorer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.443498+00:00
---

# cartridges/bsv-anchor-bundle/brain/src/idempotent-batch-anchorer.ts

```ts
/**
 * Idempotent batch anchoring for the bsv-anchor-bundle cartridge —
 * first consumer of L5's `requestAnchor` + `IdempotentAnchorStore`
 * primitive (shipped in #815).
 *
 * Reference:
 *   docs/canon/cw-lift-matrix.yml L5 (per-batchId idempotent anchoring).
 *
 * What this does:
 *   Wraps an existing `AnchorAdapter.batchAnchor(items)` with L5's
 *   idempotency layer. Same cell-roots + window twice → returns the
 *   same manifest + the same array of AnchorProofs, WITHOUT calling
 *   inner.batchAnchor again. Retries on network failure are safe
 *   (failed batches re-submit; broadcast/confirmed ones cache).
 *
 *   The cell-roots are the L5 idempotency key: two callers asking to
 *   anchor the same set of (sorted) cell roots get the same on-chain
 *   anchor manifest. Window is a caller-supplied scoping bytes (e.g.
 *   a 10-minute epoch label, a hat/session id) so the same set of
 *   roots in different operational contexts can produce distinct
 *   anchors.
 *
 * Layered shape:
 *
 *     ┌─ caller (brain mint walker, cell-mint cartridge, etc.) ──┐
 *     │ anchorer.anchorBatchIdempotent({                          │
 *     │   cellRoots,        ← used for batchId                     │
 *     │   items,            ← passed verbatim to inner.batchAnchor │
 *     │   window?,                                                 │
 *     │   submitMode?,      ← 'auto' | 'force'                     │
 *     │ })                                                         │
 *     └────────────────────────────────────────────────────────────┘
 *                                ↓
 *     ┌─ requestAnchor (L5) ───────────────────────────────────────┐
 *     │  computeBatchId(cellRoots, window) → batchId                │
 *     │  store.get(batchId)?                                        │
 *     │    cached (not failed) → return manifest                    │
 *     │    miss / failed       → submit() → persist → return         │
 *     └────────────────────────────────────────────────────────────┘
 *                                ↓
 *     ┌─ submit() — the wrapper's bridge into the AnchorAdapter ──┐
 *     │  inner.batchAnchor(items) → AnchorProof[]                  │
 *     │  Convert first proof's txid into BatchSubmitResult         │
 *     │  Cache the AnchorProof[] alongside manifest in attestation │
 *     │  Payload (base64 of canonical-JSON) so retries reproduce   │
 *     │  the same proofs                                           │
 *     └────────────────────────────────────────────────────────────┘
 *
 * What this does NOT do:
 *   - Build the batchAnchor inner impl — caller supplies any
 *     `AnchorAdapter` (StubAnchorAdapter for tests, real BSV adapter
 *     in production)
 *   - Verify the resulting proofs — that's L4
 *     (verifyAnchorAttestationInclusion in #835)
 *   - Persist the proofs separately — they ride inside the manifest's
 *     `attestationPayload` field so a single store read reconstitutes
 *     everything
 */

import {
  computeBatchId,
  requestAnchor,
  type BatchManifest,
  type BatchSubmitResult,
  type BatchWindow,
  type IdempotentAnchorStore,
} from '@semantos/anchor-attestation';
import type {
  AnchorAdapter,
  AnchorItem,
  AnchorProof,
} from '@semantos/protocol-types';

// ── Types ─────────────────────────────────────────────────────────

export interface IdempotentBatchAnchorInput {
  /** Cell roots (32B each) — used as the L5 idempotency key. Two
   *  callers passing the same SET of roots (any order) compute the
   *  same batchId. */
  readonly cellRoots: readonly Uint8Array[];
  /** Items to anchor — passed verbatim to inner.batchAnchor on cache
   *  miss. Must be in the SAME order as cellRoots so the resulting
   *  AnchorProof[] aligns; if you want order-independence on the
   *  items side, sort them yourself by stateHash. */
  readonly items: readonly AnchorItem[];
  /** Optional window scoping bytes. Default: empty bytes. */
  readonly window?: BatchWindow;
}

export interface IdempotentBatchAnchorResult {
  /** L5 batch manifest (batchId, cellRoots, status, txid, etc.). */
  readonly manifest: BatchManifest;
  /** AnchorProof[] in the SAME ORDER as input.items. Decoded from
   *  the manifest's attestationPayload on cache hit; freshly produced
   *  on cache miss. */
  readonly proofs: readonly AnchorProof[];
  /** true if returned from cache without calling inner.batchAnchor. */
  readonly fromCache: boolean;
}

/**
 * Idempotent batch anchor wrapper. Holds an `AnchorAdapter` + an
 * `IdempotentAnchorStore` and exposes `anchorBatchIdempotent` as the
 * single entry point.
 */
export class IdempotentBatchAnchorer {
  constructor(
    private readonly inner: AnchorAdapter,
    private readonly store: IdempotentAnchorStore,
  ) {}

  /**
   * Anchor the batch idempotently. Same (cellRoots, window) twice →
   * same manifest + same proofs without re-broadcasting.
   *
   * On cache miss: calls inner.batchAnchor(items), persists the
   * result. The proofs are JSON-serialised and stored inside the
   * manifest's `attestationPayload` field, so a subsequent cache hit
   * reconstitutes the exact AnchorProof[] without needing to call
   * inner.verify() or hit the network.
   *
   * On cache hit (status === 'broadcast' or 'confirmed'): returns
   * stored manifest + decoded proofs.
   *
   * On previous-failure cache hit (status === 'failed'): re-submits
   * (failed manifests are not cached by L5 by design).
   */
  async anchorBatchIdempotent(
    input: IdempotentBatchAnchorInput,
  ): Promise<IdempotentBatchAnchorResult> {
    const window = input.window ?? new Uint8Array(0);

    const { manifest, fromCache } = await requestAnchor({
      cellRoots: input.cellRoots,
      window,
      store: this.store,
      submit: async (req): Promise<BatchSubmitResult> => {
        // Cache miss path: call inner adapter, serialise proofs,
        // return them packed into attestationPayload.
        try {
          const proofs = await this.inner.batchAnchor([...input.items]);
          if (proofs.length === 0) {
            return {
              status: 'failed',
              reason: 'inner.batchAnchor returned an empty proof array',
              // L5's BatchManifest drops the `reason` field on persist,
              // so we also stash it in attestationPayload to surface it
              // in the wrapper's caller-facing error message.
              attestationPayload: new TextEncoder().encode(
                'inner.batchAnchor returned an empty proof array',
              ),
            };
          }
          // All proofs in a batch share the same anchoring tx; take
          // identifying fields from the first.
          const txidBytes = hexToBytes(proofs[0].txid);
          return {
            status: 'broadcast',
            txid: txidBytes,
            vout: proofs[0].vout,
            anchorHeight: BigInt(proofs[0].blockHeight),
            attestationPayload: encodeProofsAsPayload(proofs),
          };
        } catch (e) {
          // Inner adapter exceptions become L5 failed manifests so
          // the next call re-submits cleanly.
          const reason = `inner.batchAnchor threw: ${(e as Error).message}`;
          return {
            status: 'failed',
            reason,
            attestationPayload: new TextEncoder().encode(reason),
          };
        }
      },
    });

    if (manifest.status === 'failed') {
      throw new Error(
        `anchorBatchIdempotent: batch ${bytesHex(manifest.batchId).slice(0, 16)}... ` +
          `failed at submission: ${manifest.attestationPayload ? new TextDecoder().decode(manifest.attestationPayload) : 'no reason recorded'}`,
      );
    }

    const proofs = decodePayloadAsProofs(
      manifest.attestationPayload,
      manifest.batchId,
    );

    return {
      manifest,
      proofs,
      fromCache,
    };
  }
}

// ── Helpers ───────────────────────────────────────────────────────

export { computeBatchId };

function encodeProofsAsPayload(
  proofs: readonly AnchorProof[],
): Uint8Array {
  return new TextEncoder().encode(JSON.stringify(proofs));
}

function decodePayloadAsProofs(
  payload: Uint8Array | undefined,
  batchId: Uint8Array,
): AnchorProof[] {
  if (payload === undefined) {
    throw new Error(
      `decodePayloadAsProofs: manifest ${bytesHex(batchId).slice(0, 16)}... ` +
        `missing attestationPayload — cannot reconstitute AnchorProof[]`,
    );
  }
  try {
    const decoded = JSON.parse(new TextDecoder().decode(payload));
    if (!Array.isArray(decoded)) {
      throw new Error('not an array');
    }
    return decoded as AnchorProof[];
  } catch (e) {
    throw new Error(
      `decodePayloadAsProofs: failed to decode attestationPayload as ` +
        `AnchorProof[] (${(e as Error).message})`,
    );
  }
}

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0) {
    throw new Error(`hexToBytes: odd-length hex string`);
  }
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function bytesHex(b: Uint8Array): string {
  return Buffer.from(b).toString('hex');
}

```
