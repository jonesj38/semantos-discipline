---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/constants.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.976962+00:00
---

# core/cell-engine/src/constants.zig

```zig
// AUTO-GENERATED from constants.json — DO NOT EDIT
// Run `bun run generate-constants` to regenerate.

// ── Protocol ──
pub const CELL_SIZE: u32 = 1024;
pub const CONTINUATION_HEADER_SIZE: u32 = 8;
pub const CONTINUATION_PAYLOAD_SIZE: u32 = 1016;
pub const HEADER_SIZE: u32 = 256;
pub const PAYLOAD_SIZE: u32 = 768;
pub const VERSION: u32 = 2;

// ── Stacks ──
pub const AUX_STACK_BYTES: u32 = 262144;
pub const AUX_STACK_CELLS: u32 = 256;
pub const MAIN_STACK_BYTES: u32 = 1048576;
pub const MAIN_STACK_CELLS: u32 = 1024;

// ── Magic Numbers ──
pub const MAGIC_1: u32 = 0xDEADBEEF;
pub const MAGIC_2: u32 = 0xCAFEBABE;
pub const MAGIC_3: u32 = 0x13371337;
pub const MAGIC_4: u32 = 0x42424242;

// ── Linearity ──
pub const LINEARITY_AFFINE: u8 = 2;
pub const LINEARITY_DEBUG: u8 = 4;
pub const LINEARITY_LINEAR: u8 = 1;
pub const LINEARITY_RELEVANT: u8 = 3;

// ── Commerce Phase ──
pub const COMMERCE_PHASE_ACTION: u8 = 6;
pub const COMMERCE_PHASE_AST: u8 = 2;
pub const COMMERCE_PHASE_CODEGEN: u8 = 5;
pub const COMMERCE_PHASE_OPTIMISE: u8 = 4;
pub const COMMERCE_PHASE_OUTCOME: u8 = 7;
pub const COMMERCE_PHASE_PARSE: u8 = 1;
pub const COMMERCE_PHASE_SOURCE: u8 = 0;
pub const COMMERCE_PHASE_TYPECHECK: u8 = 3;
pub const COMMERCE_PHASE_UNKNOWN: u8 = 255;

// ── Taxonomy Dimension ──
pub const TAXONOMY_DIM_COMPOSITE: u8 = 0;
pub const TAXONOMY_DIM_HOW: u8 = 2;
pub const TAXONOMY_DIM_INSTRUMENT: u8 = 3;
pub const TAXONOMY_DIM_WHAT: u8 = 1;

// ── Cell Type ──
pub const CELL_TYPE_ATOMIC_BEEF: u8 = 2;
pub const CELL_TYPE_BUMP: u8 = 1;
pub const CELL_TYPE_DATA: u8 = 4;
pub const CELL_TYPE_ENVELOPE: u8 = 3;
pub const CELL_TYPE_POINTER: u8 = 6;
pub const CELL_TYPE_STATE: u8 = 5;

// ── Header Offsets (packed wire format from typeHashRegistry.ts) ──
pub const HEADER_OFFSET_CELL_COUNT: u16 = 86;
pub const HEADER_SIZE_CELL_COUNT: u16 = 4;
pub const HEADER_OFFSET_DOMAIN_PAYLOAD_ROOT: u16 = 224;
pub const HEADER_SIZE_DOMAIN_PAYLOAD_ROOT: u16 = 32;
pub const HEADER_OFFSET_FLAGS: u16 = 24;
pub const HEADER_SIZE_FLAGS: u16 = 4;
pub const HEADER_OFFSET_LINEARITY: u16 = 16;
pub const HEADER_SIZE_LINEARITY: u16 = 4;
pub const HEADER_OFFSET_MAGIC: u16 = 0;
pub const HEADER_SIZE_MAGIC: u16 = 16;
pub const HEADER_OFFSET_OWNER_ID: u16 = 62;
pub const HEADER_SIZE_OWNER_ID: u16 = 16;
pub const HEADER_OFFSET_PARENT_HASH: u16 = 96;
pub const HEADER_SIZE_PARENT_HASH: u16 = 32;
pub const HEADER_OFFSET_PAYLOAD_TOTAL: u16 = 90;
pub const HEADER_SIZE_PAYLOAD_TOTAL: u16 = 4;
pub const HEADER_OFFSET_PREV_STATE_HASH: u16 = 128;
pub const HEADER_SIZE_PREV_STATE_HASH: u16 = 32;
pub const HEADER_OFFSET_REF_COUNT: u16 = 28;
pub const HEADER_SIZE_REF_COUNT: u16 = 2;
pub const HEADER_OFFSET_TIMESTAMP: u16 = 78;
pub const HEADER_SIZE_TIMESTAMP: u16 = 8;
pub const HEADER_OFFSET_TYPE_HASH: u16 = 30;
pub const HEADER_SIZE_TYPE_HASH: u16 = 32;
pub const HEADER_OFFSET_VERSION: u16 = 20;
pub const HEADER_SIZE_VERSION: u16 = 4;

// ── Opcode Ranges ──
pub const OPCODE_CRAIG_MACRO_MAX: u8 = 191;
pub const OPCODE_CRAIG_MACRO_MIN: u8 = 176;
pub const OPCODE_HOST_CALL_MAX: u8 = 223;
pub const OPCODE_HOST_CALL_MIN: u8 = 208;
pub const OPCODE_PLEXUS_MAX: u8 = 207;
pub const OPCODE_PLEXUS_MIN: u8 = 192;
pub const OPCODE_ROUTING_MAX: u8 = 239;
pub const OPCODE_ROUTING_MIN: u8 = 224;
pub const OPCODE_STANDARD_MAX: u8 = 175;
pub const OPCODE_STANDARD_MIN: u8 = 0;

// ── Opcodes ──
pub const OP_CALLHOST: u8 = 208;
pub const OP_CHECKDOMAINFLAG: u8 = 198;
pub const OP_CHECKTYPEHASH: u8 = 199;
pub const OP_DEREF_POINTER: u8 = 200;

// ── Routing opcodes (0xE0..0xEF) ──
// Spec: docs/design/OP-BRANCHONOUTPUT-SPEC.md
pub const OP_BRANCHONOUTPUT: u8 = 0xE0;

// ── Domain Flags ──
pub const DOMAIN_FLAG_ANCHOR_ATTESTATION_V1: u32 = 0x0001FE02;
pub const DOMAIN_FLAG_CHANGE: u32 = 11;
pub const DOMAIN_FLAG_CLIENT_DEFINED_MAX: u32 = 4294967295;
pub const DOMAIN_FLAG_CLIENT_DEFINED_MIN: u32 = 65536;
pub const DOMAIN_FLAG_COMMERCE_V1: u32 = 0x0001FE01;
pub const DOMAIN_FLAG_EDGE_CREATION: u32 = 1;
pub const DOMAIN_FLAG_EXTENDED_MAX: u32 = 65535;
pub const DOMAIN_FLAG_EXTENDED_MIN: u32 = 256;
pub const DOMAIN_FLAG_HAT_SIGNING: u32 = 256;
pub const DOMAIN_FLAG_METERING: u32 = 10;
pub const DOMAIN_FLAG_PLEXUS_RESERVED_MAX: u32 = 255;
pub const DOMAIN_FLAG_PLEXUS_RESERVED_MIN: u32 = 1;
pub const DOMAIN_FLAG_SCG_RELATION_V1: u32 = 0x0001FE03;
pub const DOMAIN_FLAG_SIGNING: u32 = 2;
pub const DOMAIN_FLAG_WALLET_SPEND: u32 = 258;
pub const DOMAIN_FLAG_WALLET_TIER0: u32 = 257;

// ── Binding ──
pub const BINDING_ANCHOR_HEIGHT_SIZE: u32 = 8;
pub const BINDING_DERIVATION_INDEX_SIZE: u32 = 4;
pub const BINDING_TOTAL_BINDING_SIZE: u32 = 48;
pub const BINDING_TXID_SIZE: u32 = 32;
pub const BINDING_VOUT_SIZE: u32 = 4;

// ── BCA ──
pub const BCA_COLLISION_COUNT_MAX: u32 = 2;
pub const BCA_IPV6_ADDRESS_SIZE: u32 = 16;
pub const BCA_MODIFIER_SIZE: u32 = 16;
pub const BCA_PUBLIC_KEY_SIZE: u32 = 33;
pub const BCA_SUBNET_PREFIX_SIZE: u32 = 8;

// ── Extension Pages ──
pub const BSV_ANCHOR_PAGE: u32 = 0x00010200;
pub const LOOM_SHELL_PAGE: u32 = 0x00010000;
pub const ODDJOBZ_PAGE: u32 = 0x00010100;
pub const SUBSTRATE_SCHEMA_PAGE: u32 = 0x0001FE00;
pub const TESSERA_HAT_CLUB_MEMBER: u32 = 0x00010404;
pub const TESSERA_HAT_CONSUMER: u32 = 0x00010405;
pub const TESSERA_HAT_DISTRIBUTOR: u32 = 0x00010402;
pub const TESSERA_HAT_DOCK_HANDLER: u32 = 0x0001042A;
pub const TESSERA_HAT_FIELD_WORKER: u32 = 0x0001041A;
pub const TESSERA_HAT_PRODUCER: u32 = 0x00010401;
pub const TESSERA_HAT_RETAILER: u32 = 0x00010403;
pub const TESSERA_PAGE: u32 = 0x00010400;

```
