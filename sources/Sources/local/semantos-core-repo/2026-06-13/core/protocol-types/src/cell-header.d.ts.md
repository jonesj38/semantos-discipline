---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-header.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.841496+00:00
---

# core/protocol-types/src/cell-header.d.ts

```ts
/**
 * CellHeader types and layout — derived from constants.json headerOffsets.
 * Matches the packed wire-format from typeHashRegistry.ts.
 */
export interface FieldLayout {
    offset: number;
    size: number;
}
export declare const CellHeaderLayout: {
    readonly magic: {
        readonly offset: 0;
        readonly size: 16;
    };
    readonly linearity: {
        readonly offset: 16;
        readonly size: 4;
    };
    readonly version: {
        readonly offset: 20;
        readonly size: 4;
    };
    readonly flags: {
        readonly offset: 24;
        readonly size: 4;
    };
    readonly refCount: {
        readonly offset: 28;
        readonly size: 2;
    };
    readonly typeHash: {
        readonly offset: 30;
        readonly size: 32;
    };
    readonly ownerId: {
        readonly offset: 62;
        readonly size: 16;
    };
    readonly timestamp: {
        readonly offset: 78;
        readonly size: 8;
    };
    readonly cellCount: {
        readonly offset: 86;
        readonly size: 4;
    };
    readonly totalSize: {
        readonly offset: 90;
        readonly size: 4;
    };
    readonly commercePhase: {
        readonly offset: 94;
        readonly size: 1;
    };
    readonly commerceDimension: {
        readonly offset: 95;
        readonly size: 1;
    };
    readonly commerceParentHash: {
        readonly offset: 96;
        readonly size: 32;
    };
    readonly commercePrevState: {
        readonly offset: 128;
        readonly size: 32;
    };
};
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
    phase: number;
    dimension: number;
    parentHash: Uint8Array;
    prevStateHash: Uint8Array;
}
export interface CommerceExtension {
    phase: number;
    dimension: number;
    parentHash: Uint8Array;
    prevStateHash: Uint8Array;
}
/**
 * Note: this committed `.d.ts` predates RM-042 and is out of step with
 * `cell-header.ts`. The `OnChainBinding` interface (txid, vout, bumpHash,
 * derivationIndex) was retired in RM-042 — anchoring now produces an
 * `AnchorAttestation` cell (see `@semantos/anchor-attestation`) whose
 * payload binds (targetCellId, txid, anchorHeight, vout, derivationIndex)
 * via `anchorAttestationSchemaV2` at Plexus. The `bumpHash` substrate
 * (zombie field — BRC-74 BUMP carries `blockHeight` natively, not a 24B
 * Merkle-root variant) was retired in the schema-v2 cut.
 */
/**
 * Serialize a CellHeader into a 256-byte little-endian wire buffer.
 * Bytes 160–255 are zeroed (reserved for on-chain binding fields).
 */
export declare function serializeCellHeader(header: CellHeader): Uint8Array;
/**
 * Deserialize a 256-byte wire buffer into a CellHeader.
 * Validates magic bytes. Tolerates non-zero data in bytes 160–255 (binding fields).
 */
export declare function deserializeCellHeader(buf: Uint8Array): CellHeader;
//# sourceMappingURL=cell-header.d.ts.map
```
