---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/constants.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.845596+00:00
---

# core/protocol-types/src/constants.js

```js
// AUTO-GENERATED from constants.json — DO NOT EDIT
// Run `bun run generate-constants` to regenerate.
// ── Protocol ──
export const CELL_SIZE = 1024;
export const CONTINUATION_HEADER_SIZE = 8;
export const CONTINUATION_PAYLOAD_SIZE = 1016;
export const HEADER_SIZE = 256;
export const PAYLOAD_SIZE = 768;
export const VERSION = 1;
// ── Stacks ──
export const AUX_STACK_BYTES = 262144;
export const AUX_STACK_CELLS = 256;
export const MAIN_STACK_BYTES = 1048576;
export const MAIN_STACK_CELLS = 1024;
// ── Magic Numbers ──
export const MAGIC_1 = 0xDEADBEEF;
export const MAGIC_2 = 0xCAFEBABE;
export const MAGIC_3 = 0x13371337;
export const MAGIC_4 = 0x42424242;
// ── Linearity ──
export var Linearity;
(function (Linearity) {
    Linearity[Linearity["AFFINE"] = 2] = "AFFINE";
    Linearity[Linearity["DEBUG"] = 4] = "DEBUG";
    Linearity[Linearity["LINEAR"] = 1] = "LINEAR";
    Linearity[Linearity["RELEVANT"] = 3] = "RELEVANT";
})(Linearity || (Linearity = {}));
// ── Commerce Phase ──
export var CommercePhase;
(function (CommercePhase) {
    CommercePhase[CommercePhase["ACTION"] = 6] = "ACTION";
    CommercePhase[CommercePhase["AST"] = 2] = "AST";
    CommercePhase[CommercePhase["CODEGEN"] = 5] = "CODEGEN";
    CommercePhase[CommercePhase["OPTIMISE"] = 4] = "OPTIMISE";
    CommercePhase[CommercePhase["OUTCOME"] = 7] = "OUTCOME";
    CommercePhase[CommercePhase["PARSE"] = 1] = "PARSE";
    CommercePhase[CommercePhase["SOURCE"] = 0] = "SOURCE";
    CommercePhase[CommercePhase["TYPECHECK"] = 3] = "TYPECHECK";
    CommercePhase[CommercePhase["UNKNOWN"] = 255] = "UNKNOWN";
})(CommercePhase || (CommercePhase = {}));
// ── Taxonomy Dimension ──
export var TaxonomyDimension;
(function (TaxonomyDimension) {
    TaxonomyDimension[TaxonomyDimension["COMPOSITE"] = 0] = "COMPOSITE";
    TaxonomyDimension[TaxonomyDimension["HOW"] = 2] = "HOW";
    TaxonomyDimension[TaxonomyDimension["INSTRUMENT"] = 3] = "INSTRUMENT";
    TaxonomyDimension[TaxonomyDimension["WHAT"] = 1] = "WHAT";
})(TaxonomyDimension || (TaxonomyDimension = {}));
// ── Cell Type ──
export var CellType;
(function (CellType) {
    CellType[CellType["ATOMIC_BEEF"] = 2] = "ATOMIC_BEEF";
    CellType[CellType["BUMP"] = 1] = "BUMP";
    CellType[CellType["DATA"] = 4] = "DATA";
    CellType[CellType["ENVELOPE"] = 3] = "ENVELOPE";
    CellType[CellType["POINTER"] = 6] = "POINTER";
    CellType[CellType["STATE"] = 5] = "STATE";
})(CellType || (CellType = {}));
// ── Header Offsets (packed wire format) ──
export const HeaderOffsets = {
    bindingBumpHash: 196,
    bindingBumpHashSize: 24,
    bindingDerivationIndex: 220,
    bindingDerivationIndexSize: 4,
    bindingTxid: 160,
    bindingTxidSize: 32,
    bindingVout: 192,
    bindingVoutSize: 4,
    cellCount: 86,
    cellCountSize: 4,
    commerceDimension: 95,
    commerceParentHash: 96,
    commerceParentHashSize: 32,
    commercePhase: 94,
    commercePrevState: 128,
    commercePrevStateSize: 32,
    flags: 24,
    flagsSize: 4,
    linearity: 16,
    linearitySize: 4,
    magic: 0,
    magicSize: 16,
    ownerId: 62,
    ownerIdSize: 16,
    payloadTotal: 90,
    payloadTotalSize: 4,
    refCount: 28,
    refCountSize: 2,
    timestamp: 78,
    timestampSize: 8,
    typeHash: 30,
    typeHashSize: 32,
    version: 20,
    versionSize: 4,
};
//# sourceMappingURL=constants.js.map
```
