---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/type-hash.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.846695+00:00
---

# core/protocol-types/src/type-hash.ts

```ts
/**
 * Canonical typeHash construction — kernel primitive (TS mirror).
 *
 * Owns the single function every cell-type identity in the system flows
 * through: `buildTypeHash(s1, s2, s3, s4)`.  Type identities themselves
 * live in cartridge manifests (cartridge.json `cellTypes[].triple`),
 * not in this module.  This file just provides the HOW; cartridges
 * declare the WHAT at load time.
 *
 * Spec:    docs/design/STRUCTURED-TYPEHASH-CANONICAL.md
 * Tracker: docs/STRUCTURED-TYPEHASH-TRACKER.md
 *
 * Algorithm: structured |8|8|8|8| construction (T5.a, 2026-05-25)
 *   typeHash[ 0: 8] = sha256(s1)[0:8]    namespace
 *   typeHash[ 8:16] = sha256(s2)[0:8]    domain
 *   typeHash[16:24] = sha256(s3)[0:8]    sub-type
 *   typeHash[24:32] = sha256(s4)[0:8]    qualifier / version
 *
 * The 32 bytes ARE the four truncated inner hashes concatenated
 * directly — NO outer hash wrapper (that would collapse the structure
 * back to opaque and defeat the whole purpose).  See decision record
 * §2.1 + §7 for the routing/indexing wins this construction unlocks.
 *
 * Pre-T5.a history: the algorithm was flat `SHA256(s1:s2:s3:s4)`
 * during T1-T4 migration.  Function signature stayed identical across
 * the flip; callers don't move.  Wire-breaking change isolated to T5.a.
 *
 * Zig mirror: core/cell-engine/src/type_hash.zig (parity-tested).
 */

import { createHash } from 'crypto';

/** Size of a canonical typeHash, in bytes. */
export const TYPE_HASH_SIZE = 32 as const;

/** Number of canonical segments in a typeHash construction. */
export const TYPE_HASH_SEGMENT_COUNT = 4 as const;

/**
 * Width of a single segment's contribution under the structured (T5.a)
 * algorithm.  Unused in the flat phase but exported now so consumers
 * designing prefix-match logic can begin building against the final
 * constant.
 */
export const TYPE_HASH_SEGMENT_BYTES = 8 as const;

/**
 * Reserved wildcard prefix sentinel.
 *
 * A typeHash whose `bytes[0..8]` equal this constant signals
 * "no namespace owner — promiscuous routing, any subscriber may pick
 * this up."  Distinct from `sha256("")[0..8]` (which is a specific
 * deterministic constant produced by the empty-segment-1 case).
 *
 * Wildcard mints are reserved for substrate cartridges by default; see
 * decision record §2.2 and Q5 in the tracker.
 */
// Uint8Array doesn't support Object.freeze (typed-array elements aren't
// configurable property descriptors).  The compile-time `readonly` and
// `as const`-typed `length` give the same protection at the type layer;
// any runtime mutator would be a programming error caught in review.
export const WILDCARD_NAMESPACE_PREFIX: Readonly<Uint8Array> = new Uint8Array(
  TYPE_HASH_SEGMENT_BYTES,
);

/**
 * Compute the canonical typeHash for a 4-segment identity tuple under
 * the structured |8|8|8|8| construction (T5.a).
 * Synchronous; uses Node's `crypto.createHash` (Bun-compatible).
 */
export function buildTypeHash(
  s1: string,
  s2: string,
  s3: string,
  s4: string,
): Uint8Array {
  const out = new Uint8Array(TYPE_HASH_SIZE);
  const segments = [s1, s2, s3, s4];
  for (let i = 0; i < TYPE_HASH_SEGMENT_COUNT; i++) {
    const digest = createHash('sha256').update(segments[i]!, 'utf-8').digest();
    out.set(
      digest.subarray(0, TYPE_HASH_SEGMENT_BYTES),
      i * TYPE_HASH_SEGMENT_BYTES,
    );
  }
  return out;
}

/**
 * Extract the namespace prefix (bytes 0:8) — the routing-layer peek
 * window.  Relays compare this 8-byte slice to a subscribed namespace
 * hash to decide whether to forward a cell, without resolving the
 * full triple or reading the payload.
 */
export function namespacePrefix(typeHash: Uint8Array): Uint8Array {
  return typeHash.slice(0, TYPE_HASH_SEGMENT_BYTES);
}

/**
 * Return true when the first 8 bytes of `typeHash` equal the reserved
 * wildcard sentinel.  Trivial helper, but documents the routing-layer
 * peek pattern: relays compare these 8 bytes to decide promiscuous
 * fan-out membership without further inspection of the cell.
 */
export function isWildcard(typeHash: Uint8Array): boolean {
  if (typeHash.length < TYPE_HASH_SEGMENT_BYTES) return false;
  for (let i = 0; i < TYPE_HASH_SEGMENT_BYTES; i++) {
    if (typeHash[i] !== 0x00) return false;
  }
  return true;
}

/** Lowercase hex encoding of a typeHash. */
export function typeHashToHex(typeHash: Uint8Array): string {
  let out = '';
  for (let i = 0; i < typeHash.length; i++) {
    out += typeHash[i]!.toString(16).padStart(2, '0');
  }
  return out;
}

```
