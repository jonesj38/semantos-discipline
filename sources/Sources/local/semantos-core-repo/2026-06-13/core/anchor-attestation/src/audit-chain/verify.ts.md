---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/audit-chain/verify.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.941765+00:00
---

# core/anchor-attestation/src/audit-chain/verify.ts

```ts
/**
 * Audit-chain verifier — L12 (CW Lift Matrix).
 *
 * `verifyAuditChain` walks a sequence of SignedAuditChainEntry values
 * starting at seq=0 and rejects on the first failure. Six fail-closed
 * axes per entry, plus the cross-entry chain invariants:
 *
 *   - entityId is consistent across the chain
 *   - seq is gap-free + monotonic starting at 0
 *   - canonicalHash recomputes from canonical
 *   - prevHash matches prior entry's entryHash (zero32 at genesis)
 *   - entryHash recomputes from {seq, prevHash, canonicalHash}
 *   - linkPubKeyHex matches deriveSegmentPub(masterPub, segment)
 *   - signature verifies over entryHash under linkPub
 *
 * Returns a `ChainVerifyResult` discriminated union. Never throws on
 * verification failures — only on programmer errors (e.g. master pub
 * key supplied in a malformed hex). Empty input is treated as ok.
 */

import PublicKey from '@bsv/sdk/primitives/PublicKey';
import Signature from '@bsv/sdk/primitives/Signature';
import { deriveSegmentPub } from '@plexus/vendor-sdk';
import {
  ENTRY_HASH_SIZE,
  ZERO_HASH,
  type ChainVerifyResult,
  type LinkSegmentDeriver,
  type SignedAuditChainEntry,
} from './types.js';
import { computeCanonicalHash, computeEntryHash, linkSegment } from './append.js';

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) return false;
  for (let i = 0; i < a.byteLength; i++) if (a[i] !== b[i]) return false;
  return true;
}

export interface VerifyAuditChainInput {
  /** Ordered chain (seq must start at 0; empty is ok). */
  readonly entries: readonly SignedAuditChainEntry[];
  /** SEC1-compressed master pub key, hex. */
  readonly masterPubKeyHex: string;
  /** Optional override of the per-link segment shape. */
  readonly segmenter?: LinkSegmentDeriver;
}

export function verifyAuditChain(input: VerifyAuditChainInput): ChainVerifyResult {
  const { entries, masterPubKeyHex } = input;
  const segmenter = input.segmenter ?? linkSegment;

  if (entries.length === 0) return { ok: true };

  const masterPub = PublicKey.fromString(masterPubKeyHex);

  let prevEntryHash = ZERO_HASH;
  let prevSeq = -1;
  let entityId: string | null = null;

  for (let i = 0; i < entries.length; i++) {
    const signed = entries[i];
    const e = signed.entry;

    // entityId consistency
    if (entityId === null) {
      entityId = e.entityId;
    } else if (e.entityId !== entityId) {
      return {
        ok: false,
        failedAtIndex: i,
        seq: e.seq,
        code: 'ENTITY_ID_MISMATCH',
        message: `entry at index ${i} has entityId='${e.entityId}', expected '${entityId}'`,
      };
    }

    // seq monotonicity + gap-free
    if (i === 0) {
      if (e.seq !== 0) {
        return {
          ok: false,
          failedAtIndex: 0,
          seq: e.seq,
          code: 'SEQ_NOT_MONOTONIC',
          message: `first entry must have seq=0 (got ${e.seq})`,
        };
      }
    } else {
      if (e.seq !== prevSeq + 1) {
        return {
          ok: false,
          failedAtIndex: i,
          seq: e.seq,
          code: 'SEQ_GAP',
          message: `entry at index ${i} seq=${e.seq}, expected ${prevSeq + 1}`,
        };
      }
    }

    // prevHash chain
    if (i === 0) {
      if (!bytesEqual(e.prevHash, ZERO_HASH)) {
        return {
          ok: false,
          failedAtIndex: 0,
          seq: e.seq,
          code: 'GENESIS_PREV_HASH_NOT_ZERO',
          message: 'genesis entry must have prevHash = zero32',
        };
      }
    } else {
      if (!bytesEqual(e.prevHash, prevEntryHash)) {
        return {
          ok: false,
          failedAtIndex: i,
          seq: e.seq,
          code: 'PREV_HASH_MISMATCH',
          message: `entry at index ${i} prevHash does not match prior entryHash`,
        };
      }
    }

    // canonicalHash recompute
    if (e.canonicalHash.byteLength !== ENTRY_HASH_SIZE) {
      return {
        ok: false,
        failedAtIndex: i,
        seq: e.seq,
        code: 'CANONICAL_HASH_MISMATCH',
        message: `entry at index ${i} canonicalHash wrong size (${e.canonicalHash.byteLength})`,
      };
    }
    const expectedCanonicalHash = computeCanonicalHash(e.canonical);
    if (!bytesEqual(e.canonicalHash, expectedCanonicalHash)) {
      return {
        ok: false,
        failedAtIndex: i,
        seq: e.seq,
        code: 'CANONICAL_HASH_MISMATCH',
        message: `entry at index ${i} canonicalHash does not match SHA-256(canonical)`,
      };
    }

    // entryHash recompute
    const expectedEntryHash = computeEntryHash(e.seq, e.prevHash, e.canonicalHash);
    if (!bytesEqual(e.entryHash, expectedEntryHash)) {
      return {
        ok: false,
        failedAtIndex: i,
        seq: e.seq,
        code: 'ENTRY_HASH_MISMATCH',
        message: `entry at index ${i} entryHash does not recompute`,
      };
    }

    // linkPubKeyHex check
    const segment = segmenter(e.entityId, e.seq);
    const expectedLinkPub = deriveSegmentPub(masterPub, segment);
    const expectedLinkPubHex = expectedLinkPub.toDER('hex') as string;
    if (expectedLinkPubHex.toLowerCase() !== signed.linkPubKeyHex.toLowerCase()) {
      return {
        ok: false,
        failedAtIndex: i,
        seq: e.seq,
        code: 'LINK_PUB_KEY_MISMATCH',
        message: `entry at index ${i} linkPubKeyHex does not match derived pub`,
      };
    }

    // signature verify
    try {
      const sig = Signature.fromDER(Array.from(signed.signature));
      const ok = expectedLinkPub.verify(Array.from(e.entryHash), sig);
      if (!ok) {
        return {
          ok: false,
          failedAtIndex: i,
          seq: e.seq,
          code: 'INVALID_SIGNATURE',
          message: `entry at index ${i} signature does not verify under linkPub`,
        };
      }
    } catch (err: unknown) {
      return {
        ok: false,
        failedAtIndex: i,
        seq: e.seq,
        code: 'INVALID_SIGNATURE',
        message: `entry at index ${i} signature DER could not be parsed: ${(err as Error).message}`,
      };
    }

    prevEntryHash = e.entryHash;
    prevSeq = e.seq;
  }

  return { ok: true };
}

```
