---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/constants.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.847302+00:00
---

# core/protocol-types/src/constants.d.ts

```ts
export declare const CELL_SIZE: 1024;
export declare const CONTINUATION_HEADER_SIZE: 8;
export declare const CONTINUATION_PAYLOAD_SIZE: 1016;
export declare const HEADER_SIZE: 256;
export declare const PAYLOAD_SIZE: 768;
export declare const VERSION: 1;
export declare const AUX_STACK_BYTES: 262144;
export declare const AUX_STACK_CELLS: 256;
export declare const MAIN_STACK_BYTES: 1048576;
export declare const MAIN_STACK_CELLS: 1024;
export declare const MAGIC_1: 3735928559;
export declare const MAGIC_2: 3405691582;
export declare const MAGIC_3: 322376503;
export declare const MAGIC_4: 1111638594;
export declare const enum Linearity {
    AFFINE = 2,
    DEBUG = 4,
    LINEAR = 1,
    RELEVANT = 3
}
export declare const enum CommercePhase {
    ACTION = 6,
    AST = 2,
    CODEGEN = 5,
    OPTIMISE = 4,
    OUTCOME = 7,
    PARSE = 1,
    SOURCE = 0,
    TYPECHECK = 3,
    UNKNOWN = 255
}
export declare const enum TaxonomyDimension {
    COMPOSITE = 0,
    HOW = 2,
    INSTRUMENT = 3,
    WHAT = 1
}
export declare const enum CellType {
    ATOMIC_BEEF = 2,
    BUMP = 1,
    DATA = 4,
    ENVELOPE = 3,
    POINTER = 6,
    STATE = 5
}
export declare const HeaderOffsets: {
    readonly bindingBumpHash: 196;
    readonly bindingBumpHashSize: 24;
    readonly bindingDerivationIndex: 220;
    readonly bindingDerivationIndexSize: 4;
    readonly bindingTxid: 160;
    readonly bindingTxidSize: 32;
    readonly bindingVout: 192;
    readonly bindingVoutSize: 4;
    readonly cellCount: 86;
    readonly cellCountSize: 4;
    readonly commerceDimension: 95;
    readonly commerceParentHash: 96;
    readonly commerceParentHashSize: 32;
    readonly commercePhase: 94;
    readonly commercePrevState: 128;
    readonly commercePrevStateSize: 32;
    readonly flags: 24;
    readonly flagsSize: 4;
    readonly linearity: 16;
    readonly linearitySize: 4;
    readonly magic: 0;
    readonly magicSize: 16;
    readonly ownerId: 62;
    readonly ownerIdSize: 16;
    readonly payloadTotal: 90;
    readonly payloadTotalSize: 4;
    readonly refCount: 28;
    readonly refCountSize: 2;
    readonly timestamp: 78;
    readonly timestampSize: 8;
    readonly typeHash: 30;
    readonly typeHashSize: 32;
    readonly version: 20;
    readonly versionSize: 4;
};
//# sourceMappingURL=constants.d.ts.map
```
