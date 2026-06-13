---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/audit-chain/append.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.942061+00:00
---

# core/anchor-attestation/src/audit-chain/append.ts

```ts
/**
 * Audit-chain producer-side helpers — L12 (CW Lift Matrix).
 *
 * Pure functions for building an append-only audit chain:
 *   - `linkSegment` — default per-seq segment derivation
 *   - `computeCanonicalHash` — SHA-256(canonical)
 *   - `computeEntryHash`     — domain-separated SHA-256 binding
 *                              {seq, prevHash, canonicalHash}
 *   - `genesisEntry`         — build the seq=0 entry with zero prevHash
 *   - `appendEntry`          — build the seq=prev.seq+1 entry chained
 *                              from prev
 *   - `signEntry`            — wrap an unsigned entry with a link-pub
 *                              + ECDSA signature, deriving link key
 *                              from the entity's master via L11.
 *
 * The signer takes an `@bsv/sdk` PrivateKey because the substrate uses
 * @bsv/sdk for crypto. Tessera and similar greenfield cartridges can
 * wrap this surface with a `LinkSigner` callback in their own adapter
 * layer (same pattern as L9's `DisclosureSigner`).
 */

import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import { sha256 } from '@bsv/sdk/primitives/Hash';
import {
  deriveSegment,
  deriveSegmentPub,
} from '@plexus/vendor-sdk';
import {
  AUDIT_CHAIN_MAGIC,
  AUDIT_CHAIN_VERSION,
  ZERO_HASH,
  ENTRY_HASH_SIZE,
  type AuditChainEntry,
  type LinkSegmentDeriver,
  type SignedAuditChainEntry,
} from './types.js';

/**
 * Default per-link segment: `<entityId>/<seq>`. Caller may override
 * via `LinkSegmentDeriver`.
 */
export const linkSegment: LinkSegmentDeriver = (entityId, seq) =>
  `${entityId}/${seq}`;

/** Pure SHA-256 over the canonical bytes. */
export function computeCanonicalHash(canonical: Uint8Array): Uint8Array {
  return Uint8Array.from(sha256(Array.from(canonical)) as number[]);
}

function u32be(n: number): Uint8Array {
  if (!Number.isInteger(n) || n < 0 || n > 0xFFFFFFFF) {
    throw new RangeError(`audit-chain: seq out of u32be range: ${n}`);
  }
  const b = new Uint8Array(4);
  b[0] = (n >>> 24) & 0xff;
  b[1] = (n >>> 16) & 0xff;
  b[2] = (n >>> 8) & 0xff;
  b[3] = n & 0xff;
  return b;
}

function concat(...parts: Uint8Array[]): Uint8Array {
  let len = 0;
  for (const p of parts) len += p.byteLength;
  const out = new Uint8Array(len);
  let off = 0;
  for (const p of parts) {
    out.set(p, off);
    off += p.byteLength;
  }
  return out;
}

/**
 * entry_hash = SHA-256(
 *   AUDIT_CHAIN_MAGIC || u8(VERSION) || u32be(seq) || prevHash(32) || canonicalHash(32)
 * )
 *
 * Domain-separated by the magic + version so a chain entry hash is not
 * confused with any other 32-byte SHA-256 anywhere in the system.
 */
export function computeEntryHash(
  seq: number,
  prevHash: Uint8Array,
  canonicalHash: Uint8Array,
): Uint8Array {
  if (prevHash.byteLength !== ENTRY_HASH_SIZE) {
    throw new RangeError(
      `audit-chain: prevHash must be ${ENTRY_HASH_SIZE} bytes (got ${prevHash.byteLength})`,
    );
  }
  if (canonicalHash.byteLength !== ENTRY_HASH_SIZE) {
    throw new RangeError(
      `audit-chain: canonicalHash must be ${ENTRY_HASH_SIZE} bytes (got ${canonicalHash.byteLength})`,
    );
  }
  const versionByte = new Uint8Array([AUDIT_CHAIN_VERSION & 0xff]);
  const preimage = concat(
    AUDIT_CHAIN_MAGIC,
    versionByte,
    u32be(seq),
    prevHash,
    canonicalHash,
  );
  return Uint8Array.from(sha256(Array.from(preimage)) as number[]);
}

/**
 * Build the seq=0 entry for an entity. prevHash is the all-zeros 32B
 * sentinel (the genesis marker the verifier checks).
 */
export function genesisEntry(
  entityId: string,
  canonical: Uint8Array,
): AuditChainEntry {
  const canonicalHash = computeCanonicalHash(canonical);
  const prevHash = copyBytes(ZERO_HASH);
  const entryHash = computeEntryHash(0, prevHash, canonicalHash);
  return Object.freeze({
    entityId,
    seq: 0,
    canonical: copyBytes(canonical),
    canonicalHash,
    prevHash,
    entryHash,
  });
}

/**
 * Build the next entry on top of `prev`. seq strictly = prev.seq + 1;
 * the chain rejects gaps.
 */
export function appendEntry(
  prev: AuditChainEntry,
  canonical: Uint8Array,
): AuditChainEntry {
  const nextSeq = prev.seq + 1;
  const canonicalHash = computeCanonicalHash(canonical);
  const prevHash = copyBytes(prev.entryHash);
  const entryHash = computeEntryHash(nextSeq, prevHash, canonicalHash);
  return Object.freeze({
    entityId: prev.entityId,
    seq: nextSeq,
    canonical: copyBytes(canonical),
    canonicalHash,
    prevHash,
    entryHash,
  });
}

/**
 * Sign an audit-chain entry with the link-specific key derived from the
 * entity's master via L11. The signature is over `entry.entryHash`
 * (a single 32B value — small + stable).
 *
 * The returned `linkPubKeyHex` is computed from `deriveSegmentPub(
 *   masterPriv.toPublicKey(), segment)`; verifier can reconstruct it
 * independently using `masterPubKeyHex` + the same `LinkSegmentDeriver`.
 */
export function signEntry(
  entry: AuditChainEntry,
  masterPriv: PrivateKey,
  segmenter: LinkSegmentDeriver = linkSegment,
): SignedAuditChainEntry {
  const segment = segmenter(entry.entityId, entry.seq);
  const linkPriv = deriveSegment(masterPriv, segment);
  const linkPub = deriveSegmentPub(masterPriv.toPublicKey(), segment);
  const linkPubKeyHex = linkPub.toDER('hex') as string;
  const sig = linkPriv.sign(Array.from(entry.entryHash));
  return Object.freeze({
    entry,
    linkPubKeyHex,
    signature: Uint8Array.from(sig.toDER() as number[]),
  });
}

/** Convenience: genesis + sign in one call. */
export function genesisSignedEntry(
  entityId: string,
  canonical: Uint8Array,
  masterPriv: PrivateKey,
  segmenter: LinkSegmentDeriver = linkSegment,
): SignedAuditChainEntry {
  return signEntry(genesisEntry(entityId, canonical), masterPriv, segmenter);
}

/** Convenience: appendEntry + sign in one call. */
export function appendSignedEntry(
  prev: AuditChainEntry,
  canonical: Uint8Array,
  masterPriv: PrivateKey,
  segmenter: LinkSegmentDeriver = linkSegment,
): SignedAuditChainEntry {
  return signEntry(appendEntry(prev, canonical), masterPriv, segmenter);
}

function copyBytes(b: Uint8Array): Uint8Array {
  const out = new Uint8Array(b.byteLength);
  out.set(b);
  return out;
}

```
