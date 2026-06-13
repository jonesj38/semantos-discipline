---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/audit-chain/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.941486+00:00
---

# core/anchor-attestation/src/audit-chain/types.ts

```ts
/**
 * Audit-chain types — L12 spend-chain audit primitive.
 *
 * Reference: docs/canon/cw-lift-matrix.yml L12.
 *
 * Patents cited: US12375287B2, EP3259724B1 (Craig Wright). The
 * underlying derivation rests on EP3259724B1 (L11 base primitive).
 *
 * Wire-format constants:
 *   AUDIT_CHAIN_MAGIC    : the canonical magic for entry-hash domain
 *                          separation. Frozen at 'L12AC' ASCII.
 *   AUDIT_CHAIN_VERSION  : entry-format version. v1.
 *   AUDIT_CHAIN_DOMAIN   : the L12 domain separator. Frozen at
 *                          'semantos.audit-chain/v1' UTF-8.
 *   ZERO_HASH            : 32 zero bytes — the genesis prevHash.
 *   ENTRY_HASH_SIZE      : 32 bytes (SHA-256).
 *
 * Both ports (TS today + Zig mirror tomorrow) must hold these constants
 * byte-identical to preserve cross-language audit-chain interop.
 */

export const AUDIT_CHAIN_MAGIC = new Uint8Array([0x4c, 0x31, 0x32, 0x41, 0x43]); // 'L12AC'
export const AUDIT_CHAIN_VERSION = 1;
export const AUDIT_CHAIN_DOMAIN_STR = 'semantos.audit-chain/v1';
// Frozen-by-convention: callers MUST NOT mutate ZERO_HASH. We can't
// Object.freeze a typed array (typed-array elements are not configurable),
// so we rely on convention + the producer-side `copyBytes` for genesis.
export const ZERO_HASH: Uint8Array = new Uint8Array(32);
export const ENTRY_HASH_SIZE = 32;
export const CANONICAL_HASH_SIZE = 32;

/**
 * One audit-chain entry. Append-only — the chain is a sequence of these,
 * each binding to the previous via `prevHash`. `seq` is monotonic and
 * gap-free across the chain (starts at 0).
 *
 * `canonical` is the bytes the chain commits to (the audit fact); the
 * chain mechanism is agnostic to its shape — could be a serialized cell,
 * a JSON-canonicalised event, a hat-lifecycle record, etc.
 */
export interface AuditChainEntry {
  /** Human label identifying this chain (e.g. "oddjobz:invoice:abc-123"). */
  readonly entityId: string;
  /** Zero-indexed monotonic sequence. 0 = genesis. */
  readonly seq: number;
  /** The audit fact bytes. */
  readonly canonical: Uint8Array;
  /** SHA-256(canonical) — 32B. */
  readonly canonicalHash: Uint8Array;
  /** SHA-256(prev entry's entryHash) — 32B. Zero32 at genesis (seq=0). */
  readonly prevHash: Uint8Array;
  /** SHA-256(AUDIT_CHAIN_MAGIC || u8(version) || u32be(seq) || prevHash || canonicalHash). */
  readonly entryHash: Uint8Array;
}

/**
 * An AuditChainEntry signed by the link-specific key derived from the
 * entity's master key via L11's `deriveSegment` over a per-seq segment.
 * Verifier reconstructs `linkPubKeyHex` independently and checks the
 * signature over `entry.entryHash`.
 */
export interface SignedAuditChainEntry {
  readonly entry: AuditChainEntry;
  /** SEC1-compressed link pub key, hex. Verifier checks this matches
   *  `deriveSegmentPub(masterPub, linkSegment(entityId, seq))`. */
  readonly linkPubKeyHex: string;
  /** ECDSA(entryHash) under linkPriv. DER-encoded. */
  readonly signature: Uint8Array;
}

/**
 * Per-link segment derivation seam. The chain doesn't fix the segment
 * shape — callers supply it so domain separation can match the broader
 * derivation policy (cartridge naming, hat scoping, etc.).
 *
 * Default `linkSegment(entityId, seq)` lives in `./append.ts` and is what
 * the chain self-verifies against; supply your own if you need a
 * different convention.
 */
export type LinkSegmentDeriver = (entityId: string, seq: number) => string;

export type ChainVerifyResult =
  | { ok: true }
  | {
      ok: false;
      /** Index of the failing entry in the input array. */
      failedAtIndex: number;
      /** seq of the failing entry, if available. */
      seq: number;
      code:
        | 'GENESIS_PREV_HASH_NOT_ZERO'
        | 'PREV_HASH_MISMATCH'
        | 'SEQ_GAP'
        | 'SEQ_NOT_MONOTONIC'
        | 'CANONICAL_HASH_MISMATCH'
        | 'ENTRY_HASH_MISMATCH'
        | 'LINK_PUB_KEY_MISMATCH'
        | 'INVALID_SIGNATURE'
        | 'ENTITY_ID_MISMATCH';
      message: string;
    };

```
