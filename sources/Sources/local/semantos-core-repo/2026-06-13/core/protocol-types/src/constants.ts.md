---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/constants.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.852410+00:00
---

# core/protocol-types/src/constants.ts

```ts
// AUTO-GENERATED from constants.json — DO NOT EDIT
// Run `bun run generate-constants` to regenerate.

// ── Protocol ──
export const CELL_SIZE = 1024 as const;
export const CONTINUATION_HEADER_SIZE = 8 as const;
export const CONTINUATION_PAYLOAD_SIZE = 1016 as const;
export const HEADER_SIZE = 256 as const;
export const PAYLOAD_SIZE = 768 as const;
export const VERSION = 2 as const;

// ── Stacks ──
export const AUX_STACK_BYTES = 262144 as const;
export const AUX_STACK_CELLS = 256 as const;
export const MAIN_STACK_BYTES = 1048576 as const;
export const MAIN_STACK_CELLS = 1024 as const;

// ── Magic Numbers ──
export const MAGIC_1 = 0xDEADBEEF as const;
export const MAGIC_2 = 0xCAFEBABE as const;
export const MAGIC_3 = 0x13371337 as const;
export const MAGIC_4 = 0x42424242 as const;

// ── Linearity ──
export const enum Linearity {
  AFFINE = 2,
  DEBUG = 4,
  LINEAR = 1,
  RELEVANT = 3,
}

// ── Commerce Phase ──
export const enum CommercePhase {
  ACTION = 6,
  AST = 2,
  CODEGEN = 5,
  OPTIMISE = 4,
  OUTCOME = 7,
  PARSE = 1,
  SOURCE = 0,
  TYPECHECK = 3,
  UNKNOWN = 255,
}

// ── Taxonomy Dimension ──
export const enum TaxonomyDimension {
  COMPOSITE = 0,
  HOW = 2,
  INSTRUMENT = 3,
  WHAT = 1,
}

// ── Cell Type ──
export const enum CellType {
  ATOMIC_BEEF = 2,
  BUMP = 1,
  DATA = 4,
  ENVELOPE = 3,
  POINTER = 6,
  STATE = 5,
}

// ── Header Offsets (packed wire format) ──
export const HeaderOffsets = {
  cellCount: 86,
  cellCountSize: 4,
  domainPayloadRoot: 224,
  domainPayloadRootSize: 32,
  flags: 24,
  flagsSize: 4,
  linearity: 16,
  linearitySize: 4,
  magic: 0,
  magicSize: 16,
  ownerId: 62,
  ownerIdSize: 16,
  parentHash: 96,
  parentHashSize: 32,
  payloadTotal: 90,
  payloadTotalSize: 4,
  prevStateHash: 128,
  prevStateHashSize: 32,
  refCount: 28,
  refCountSize: 2,
  timestamp: 78,
  timestampSize: 8,
  typeHash: 30,
  typeHashSize: 32,
  version: 20,
  versionSize: 4,
} as const;

// ── Extension Pages ──
export const BSV_ANCHOR_PAGE = 0x00010200 as const;
export const LOOM_SHELL_PAGE = 0x00010000 as const;
export const ODDJOBZ_PAGE = 0x00010100 as const;
export const SUBSTRATE_SCHEMA_PAGE = 0x0001FE00 as const;
export const TESSERA_HAT_CLUB_MEMBER = 0x00010404 as const;
export const TESSERA_HAT_CONSUMER = 0x00010405 as const;
export const TESSERA_HAT_DISTRIBUTOR = 0x00010402 as const;
export const TESSERA_HAT_DOCK_HANDLER = 0x0001042A as const;
export const TESSERA_HAT_FIELD_WORKER = 0x0001041A as const;
export const TESSERA_HAT_PRODUCER = 0x00010401 as const;
export const TESSERA_HAT_RETAILER = 0x00010403 as const;
export const TESSERA_PAGE = 0x00010400 as const;

```
