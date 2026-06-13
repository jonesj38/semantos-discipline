---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-header.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.843288+00:00
---

# core/protocol-types/src/cell-header.ts

```ts
/**
 * CellHeader types and layout — derived from constants.json headerOffsets.
 * Matches the packed wire-format from typeHashRegistry.ts.
 */

import { HeaderOffsets, HEADER_SIZE, MAGIC_1, MAGIC_2, MAGIC_3, MAGIC_4 } from "./constants";

export interface FieldLayout { offset: number; size: number; }

export const CellHeaderLayout = {
  magic: { offset: HeaderOffsets.magic, size: HeaderOffsets.magicSize },
  linearity: { offset: HeaderOffsets.linearity, size: HeaderOffsets.linearitySize },
  version: { offset: HeaderOffsets.version, size: HeaderOffsets.versionSize },
  flags: { offset: HeaderOffsets.flags, size: HeaderOffsets.flagsSize },
  refCount: { offset: HeaderOffsets.refCount, size: HeaderOffsets.refCountSize },
  typeHash: { offset: HeaderOffsets.typeHash, size: HeaderOffsets.typeHashSize },
  ownerId: { offset: HeaderOffsets.ownerId, size: HeaderOffsets.ownerIdSize },
  timestamp: { offset: HeaderOffsets.timestamp, size: HeaderOffsets.timestampSize },
  cellCount: { offset: HeaderOffsets.cellCount, size: HeaderOffsets.cellCountSize },
  totalSize: { offset: HeaderOffsets.payloadTotal, size: HeaderOffsets.payloadTotalSize },
  parentHash: { offset: HeaderOffsets.parentHash, size: HeaderOffsets.parentHashSize },
  prevStateHash: { offset: HeaderOffsets.prevStateHash, size: HeaderOffsets.prevStateHashSize },
  domainPayloadRoot: { offset: HeaderOffsets.domainPayloadRoot, size: HeaderOffsets.domainPayloadRootSize },
} as const satisfies Record<string, FieldLayout>;

/**
 * Phase H §3.1 / RM-032b — domain-agnostic cell header.
 *
 * Commerce-taxonomy fields (`phase`, `dimension`) have been removed
 * from this clean surface. Commerce semantics now live in the cell
 * payload under `commerceSchemaV1` registered at Plexus
 * (`@semantos/plexus-schema-registry/schemas/commerce`); the resulting
 * 32B root is bound here as `domainPayloadRoot`.
 *
 * `parentHash` and `prevStateHash` are kept as first-class header
 * fields (renamed out of the commerce namespace) — they encode
 * cross-cutting chain semantics consumed by `cell-verifier` and
 * `queryByParent`, independent of commerce taxonomy.
 *
 * The legacy commerce surface still exists on `@semantos/cell-ops`'s
 * `CellHeader` interface (the cell-ops `unpackCell` return type) for
 * back-compat with downstream consumers (cdm, game-sdk, cell-engine
 * tests). New code should prefer this clean surface + the schema
 * registry.
 */
export interface CellHeader {
  magic: Uint8Array;
  linearity: number;
  version: number;
  flags: number;
  refCount: number;
  typeHash: Uint8Array;
  ownerId: Uint8Array;
  timestamp: bigint;
  cellCount: number;
  totalSize: number;
  /** Parent cell hash (32B) — chain-of-custody linkage, offset 96. */
  parentHash: Uint8Array;
  /** Previous-state hash (32B) — version chain linkage, offset 128. */
  prevStateHash: Uint8Array;
  /**
   * Phase H §3.3 / RM-023 — 32B SHA-256 binding the payload bytes to
   * the header. Computed via `computeDomainPayloadRoot(schema, values)`
   * from `@semantos/plexus-schema-registry`. Stored at offset 224.
   */
  domainPayloadRoot: Uint8Array;
}

// `OnChainBinding` interface removed in RM-042. Anchoring a cell now
// creates an `AnchorAttestation` cell (see `@semantos/anchor-attestation`)
// whose payload binds (targetCellId, txid, anchorHeight, vout,
// derivationIndex) via `anchorAttestationSchemaV2` at Plexus. The pre-
// RM-042 header bytes 160–223 are now unnamed reserved space. The v2
// schema cut retired the 24B `bumpHash` field (zombie — BRC-74 BUMP
// carries `blockHeight` natively, not a 24B Merkle-root variant) and
// promoted `anchor_height: u64` to a first-class queryable field that
// the brain's reorg substrate range-queries.

/**
 * Serialize a CellHeader into a 256-byte little-endian wire buffer.
 * Bytes 160–255 are zeroed (reserved for on-chain binding fields).
 */
export function serializeCellHeader(header: CellHeader): Uint8Array {
  const buf = new Uint8Array(HEADER_SIZE);
  const dv = new DataView(buf.buffer);

  // Magic (4 × u32 LE)
  dv.setUint32(0, MAGIC_1, true);
  dv.setUint32(4, MAGIC_2, true);
  dv.setUint32(8, MAGIC_3, true);
  dv.setUint32(12, MAGIC_4, true);

  // Scalar fields
  dv.setUint32(HeaderOffsets.linearity, header.linearity, true);
  dv.setUint32(HeaderOffsets.version, header.version, true);
  dv.setUint32(HeaderOffsets.flags, header.flags, true);
  dv.setUint16(HeaderOffsets.refCount, header.refCount, true);

  // Raw byte fields
  buf.set(header.typeHash.subarray(0, 32), HeaderOffsets.typeHash);
  buf.set(header.ownerId.subarray(0, 16), HeaderOffsets.ownerId);

  // Timestamp (u64 LE)
  dv.setBigUint64(HeaderOffsets.timestamp, header.timestamp, true);

  dv.setUint32(HeaderOffsets.cellCount, header.cellCount, true);
  dv.setUint32(HeaderOffsets.payloadTotal, header.totalSize, true);

  // Chain semantics (Phase H §3.1, post-RM-032b naming).
  buf.set(header.parentHash.subarray(0, 32), HeaderOffsets.parentHash);
  buf.set(header.prevStateHash.subarray(0, 32), HeaderOffsets.prevStateHash);

  // Phase H §3.3 — domainPayloadRoot (32B SHA-256 of encoded payload).
  // Zero-filled if the caller hasn't computed it yet.
  if (header.domainPayloadRoot.length > 0) {
    buf.set(header.domainPayloadRoot.subarray(0, 32), HeaderOffsets.domainPayloadRoot);
  }

  // Bytes 94-95 (former commercePhase, commerceDimension — RM-032b)
  // and 160-223 (former OnChainBinding region — RM-042) are unnamed
  // reserved space.
  return buf;
}

/**
 * Deserialize a 256-byte wire buffer into a CellHeader.
 * Validates magic bytes. Tolerates non-zero data in bytes 160–255 (binding fields).
 */
export function deserializeCellHeader(buf: Uint8Array): CellHeader {
  if (buf.length < HEADER_SIZE) {
    throw new Error(`Buffer too small: ${buf.length} bytes, need ${HEADER_SIZE}`);
  }
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);

  // Validate magic
  if (
    dv.getUint32(0, true) !== MAGIC_1 ||
    dv.getUint32(4, true) !== MAGIC_2 ||
    dv.getUint32(8, true) !== MAGIC_3 ||
    dv.getUint32(12, true) !== MAGIC_4
  ) {
    throw new Error('Invalid cell header magic bytes');
  }

  return {
    magic: buf.slice(0, 16),
    linearity: dv.getUint32(HeaderOffsets.linearity, true),
    version: dv.getUint32(HeaderOffsets.version, true),
    flags: dv.getUint32(HeaderOffsets.flags, true),
    refCount: dv.getUint16(HeaderOffsets.refCount, true),
    typeHash: buf.slice(HeaderOffsets.typeHash, HeaderOffsets.typeHash + 32),
    ownerId: buf.slice(HeaderOffsets.ownerId, HeaderOffsets.ownerId + 16),
    timestamp: dv.getBigUint64(HeaderOffsets.timestamp, true),
    cellCount: dv.getUint32(HeaderOffsets.cellCount, true),
    totalSize: dv.getUint32(HeaderOffsets.payloadTotal, true),
    parentHash: buf.slice(
      HeaderOffsets.parentHash,
      HeaderOffsets.parentHash + HeaderOffsets.parentHashSize,
    ),
    prevStateHash: buf.slice(
      HeaderOffsets.prevStateHash,
      HeaderOffsets.prevStateHash + HeaderOffsets.prevStateHashSize,
    ),
    domainPayloadRoot: buf.slice(
      HeaderOffsets.domainPayloadRoot,
      HeaderOffsets.domainPayloadRoot + HeaderOffsets.domainPayloadRootSize,
    ),
  };
}

```
