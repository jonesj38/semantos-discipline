---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/verify-against-chain.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.939652+00:00
---

# core/anchor-attestation/src/verify-against-chain.ts

```ts
/**
 * High-level anchor verification — first consumer of L4's composed
 * `verifyInclusion`.
 *
 * Reference:
 *   docs/canon/cw-lift-matrix.yml L4 (two-tree SPV verify composition).
 *
 * What this does:
 *   Wraps `verifyInclusion` (which takes an `assertHeaderChainContains
 *   Block` callback as an *optional* trust-boundary check) with a
 *   `TrustedHeaderChain`-backed default callback. Consumers (wallets,
 *   brain runtime, indexers) get a one-call verifier instead of having
 *   to wire up the header-chain assertion themselves.
 *
 * Layered shape:
 *
 *     ┌─ caller (wallet / brain / cell-mint walker / etc.) ────┐
 *     │ verifyAnchorAttestationInclusion({                     │
 *     │   expectedTargetCellId,                                │
 *     │   attestationPayload,                                  │
 *     │   attestationDomainPayloadRoot,                        │
 *     │   merkleProof,                                         │
 *     │   expectedBlockMerkleRoot,                             │
 *     │   trustedChain,         ← lookup-by-height impl         │
 *     │ })                                                     │
 *     └────────────────────────────────────────────────────────┘
 *                              ↓
 *     ┌─ L4 verifyInclusion (4 fail-closed stages) ─────────────┐
 *     │ attestation → txid_binding → merkle → block_hash        │
 *     │                                       ↑                 │
 *     │       (block_hash stage delegates to trustedChain)      │
 *     └────────────────────────────────────────────────────────┘
 *                              ↓
 *     ┌─ TrustedHeaderChain ────────────────────────────────────┐
 *     │ getHeaderByHeight(anchorHeight) → BlockHeader | null    │
 *     └────────────────────────────────────────────────────────┘
 *
 * What this is NOT:
 *   - Not a header-chain fetcher. Consumers supply their own
 *     `TrustedHeaderChain` impl backed by their preferred trust
 *     source (header-sync daemon, brain-side header store, etc.).
 *   - Not a tx parser. Consumers must extract `merkleProof` from
 *     wherever they get BUMP-shaped proofs (via @bsv/sdk's overlay
 *     tooling, or via the brain's anchor-attestation cell pipeline).
 *   - Not a verifier of the cell PAYLOAD's domain-payload-root —
 *     that's stage 1 of `verifyInclusion` itself; this wrapper just
 *     binds it together with the chain check.
 *
 * The wrapper preserves L4's fail-closed contract: every stage
 * returns `{ ok: false, stage, code, message }` on rejection, with
 * the `stage` label identifying which level failed. A successful
 * verification returns the resolved `BlockHeader` alongside the
 * decoded attestation so callers don't have to look up the header
 * a second time.
 */

import type { MerkleProof } from '../../cell-ops/src/merkleEnvelope.js';
import { verifyInclusion } from './verify-inclusion.js';
import type { AnchorAttestation } from './types.js';

// ── Types ─────────────────────────────────────────────────────────

/**
 * A trusted block header. The fields are the minimum a verifier needs
 * to bind a merkle-root proof to a specific block. Consumers can
 * augment with timestamps / fetched-at metadata in their own impl.
 */
export interface BlockHeader {
  /** Block height (BSV mainnet/testnet uses u32 in practice but we
   *  use bigint here to match the attestation's anchor_height u64). */
  readonly height: bigint;
  /** 32-byte block merkle root. */
  readonly merkleRoot: Buffer;
  /** Optional: 32-byte block hash (helpful in error messages and for
   *  reorg detection but not used by the verifier directly). */
  readonly blockHash?: Buffer;
}

/**
 * Trusted header chain — a lookup-by-height surface that consumers
 * back with their preferred trust source (header-sync daemon,
 * brain-side header store, etc.).
 *
 * Implementations MUST return `null` if no header is available at
 * the requested height (vs throwing); the verifier turns null into
 * a clean failure at the `block_hash` stage.
 */
export interface TrustedHeaderChain {
  /** Fetch a header by block height. */
  getHeaderByHeight(height: bigint): Promise<BlockHeader | null> | BlockHeader | null;
}

/**
 * Input to `verifyAnchorAttestationInclusion`. Mirrors the L4
 * `VerifyInclusionInput` minus `expectedBlockMerkleRoot` /
 * `assertHeaderChainContainsBlock` (which the wrapper derives from
 * the `trustedChain` instead).
 */
export interface VerifyAgainstChainInput {
  // ── Stage 1 (attestation payload) ─────────────────────────────
  readonly expectedTargetCellId: Uint8Array;
  readonly attestationPayload: Uint8Array;
  readonly attestationDomainPayloadRoot: Uint8Array;

  // ── Stages 2-3 (BUMP merkle proof) ────────────────────────────
  readonly merkleProof: MerkleProof;

  // ── Stage 4 (block-hash via trusted chain) ────────────────────
  readonly trustedChain: TrustedHeaderChain;
}

/**
 * Result mirrors L4's `VerifyInclusionResult` with two enrichments
 * on the happy path: the resolved `BlockHeader` and a copy of
 * `anchorHeight` for direct use without re-deconstructing the
 * attestation.
 */
export type VerifyAgainstChainResult =
  | {
      ok: true;
      attestation: AnchorAttestation;
      anchorHeight: bigint;
      header: BlockHeader;
    }
  | {
      ok: false;
      stage:
        | 'attestation'
        | 'txid_binding'
        | 'merkle'
        | 'block_hash';
      code: string;
      message: string;
    };

// ── verifier ─────────────────────────────────────────────────────

/**
 * Verify an anchor attestation against a trusted header chain.
 *
 * Two-step internally: (1) consult the trusted chain for the header
 * at the attestation's claimed anchor_height, (2) hand the resolved
 * merkleRoot to `verifyInclusion`. If the chain returns `null`, the
 * wrapper short-circuits and reports a clean `block_hash` failure
 * BEFORE calling `verifyInclusion` — there's no point doing the
 * merkle walk when the trust anchor can't be established.
 *
 * On success returns the resolved header alongside the verified
 * attestation so callers don't have to look it up a second time.
 */
export async function verifyAnchorAttestationInclusion(
  input: VerifyAgainstChainInput,
): Promise<VerifyAgainstChainResult> {
  // The attestation hasn't been decoded yet, so we don't know
  // `anchor_height` until stage 1 of verifyInclusion runs. The
  // chain lookup needs the height. We resolve this by running a
  // 'pre-flight' attestation-payload decode just to learn the
  // anchor_height; this duplicates a small amount of work that
  // stage 1 also does, but the result of the prelim decode is
  // discarded — verifyInclusion's own stage-1 result is what we
  // trust for the final `attestation` field.
  //
  // The alternative (modify verifyInclusion to expose the height
  // pre-callback) leaks an intermediate value out of an otherwise
  // self-contained stage pipeline; we'd rather pay the prelim cost
  // here than complicate the L4 surface.

  let preliminaryHeight: bigint;
  try {
    preliminaryHeight = peekAnchorHeight(input.attestationPayload);
  } catch (e) {
    return {
      ok: false,
      stage: 'attestation',
      code: 'INVALID_SCHEMA',
      message: `payload did not decode: ${(e as Error).message}`,
    };
  }

  let header: BlockHeader | null;
  try {
    header = await Promise.resolve(
      input.trustedChain.getHeaderByHeight(preliminaryHeight),
    );
  } catch (e) {
    return {
      ok: false,
      stage: 'block_hash',
      code: 'HEADER_CHAIN_LOOKUP_FAILED',
      message: `trustedChain.getHeaderByHeight threw: ${(e as Error).message}`,
    };
  }

  if (header === null) {
    return {
      ok: false,
      stage: 'block_hash',
      code: 'HEADER_NOT_IN_CHAIN',
      message: `trustedChain has no header at height ${preliminaryHeight}`,
    };
  }

  // Now run the composed verifier with the resolved merkle root.
  const inclusion = verifyInclusion({
    expectedTargetCellId: input.expectedTargetCellId,
    attestationPayload: input.attestationPayload,
    attestationDomainPayloadRoot: input.attestationDomainPayloadRoot,
    merkleProof: input.merkleProof,
    expectedBlockMerkleRoot: header.merkleRoot,
    // Default callback: if we got here, the chain DOES contain the
    // header at this height with this merkle root (we just resolved
    // it). Return true.
    assertHeaderChainContainsBlock: () => true,
  });

  if (!inclusion.ok) {
    return inclusion;
  }
  return {
    ok: true,
    attestation: inclusion.attestation,
    anchorHeight: inclusion.anchorHeight,
    header,
  };
}

// ── In-memory header chain (reference impl) ──────────────────────

/**
 * Simple Map-backed `TrustedHeaderChain`. Useful for tests, in-process
 * caches, ephemeral verification flows, and as a reference impl for
 * production-side header stores to mirror.
 */
export class InMemoryHeaderChain implements TrustedHeaderChain {
  private readonly byHeight = new Map<string, BlockHeader>();

  add(header: BlockHeader): void {
    if (typeof header.height !== 'bigint') {
      throw new Error(
        `InMemoryHeaderChain.add: header.height must be bigint, got ${typeof header.height}`,
      );
    }
    if (header.merkleRoot.byteLength !== 32) {
      throw new Error(
        `InMemoryHeaderChain.add: header.merkleRoot must be 32B, got ${header.merkleRoot.byteLength}`,
      );
    }
    this.byHeight.set(header.height.toString(), header);
  }

  getHeaderByHeight(height: bigint): BlockHeader | null {
    return this.byHeight.get(height.toString()) ?? null;
  }

  /** Convenience for tests: count of stored headers. */
  size(): number {
    return this.byHeight.size;
  }
}

// ── Internal: peek anchor_height without full attestation verify ──

/**
 * Decode just the `anchor_height` field from the attestation payload.
 * We need it BEFORE calling verifyInclusion so we can look up the
 * trusted header. Uses the same schema as the full verify path.
 */
function peekAnchorHeight(payload: Uint8Array): bigint {
  // We import lazily so this module's runtime surface stays minimal
  // for callers who only want types.
  //
  // Schema-based decode is what `verifyAnchor` uses internally; we
  // call into the same decoder for byte-equal semantics with stage 1.
  const { anchorAttestationSchemaV2, decodePayload } =
    require('@semantos/plexus-schema-registry');
  const decoded = decodePayload(anchorAttestationSchemaV2, payload) as Record<
    string,
    unknown
  >;
  const height = decoded.anchor_height;
  if (typeof height !== 'bigint') {
    throw new Error(
      `peekAnchorHeight: decoded anchor_height is not bigint (got ${typeof height})`,
    );
  }
  return height;
}

```
