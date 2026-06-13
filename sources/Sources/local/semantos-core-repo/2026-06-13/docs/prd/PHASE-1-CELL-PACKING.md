---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-1-CELL-PACKING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.676004+00:00
---

# Phase 1: Cell Packing in Zig

**Duration**: 2 weeks (with 40% buffer: ~20 days)
**Prerequisites**: Phase 0 complete — `constants.json`, `constants.zig`, `constants.ts`, protocol-types package, Zig scaffold all compiling.
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` (in this directory: `semantos-core/docs/prd/`)

---

## Context

The 1KB semantic cell is the atomic unit of the Semantos system. Every semantic object — whether it represents a payment channel state, a capability token, a BCA address binding, or a typed commerce object — is serialised into one or more 1024-byte cells.

This phase implements the cell serialisation layer in Zig, producing output that is **bit-identical** to the existing TypeScript cell packer (`cellPacker.ts` + `typeHashRegistry.ts`). If the Zig packer produces different bytes for the same input, the phase has failed.

**Why bit-identical matters**: Cells anchored on BSV by the TypeScript tooling must be verifiable by the Zig WASM engine, and vice versa. A single byte difference in header packing means the type hash won't match, linearity checks will fail, and SPV verification breaks.

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `PACKER:TYPE-REGISTRY` | `semantos-core/src/cell-engine/typeHashRegistry.ts` | **Primary reference (canonical, in this repo).** `buildCellHeader()` — the exact byte-by-byte header construction. `packCell()` — header + payload → 1024 bytes. `unpackCell()` — 1024 bytes → header fields + payload. `computeTypeHash()` — SHA256(WHAT:HOW:INST). Field offsets: magic(0,16B), linearity(16,4B), version(20,4B), flags(24,4B), refCount(28,2B), typeHash(30,32B), ownerId(62,16B), timestamp(78,8B), cellCount(86,4B), totalSize(90,4B). |
| `PACKER:MAIN` | `semantos-core/src/cell-engine/cellPacker.ts` | **Multi-cell reference (canonical, in this repo).** `packMultiCell()` — structured packing with continuation cells. `unpackMultiCell()` — reassembly. `createBumpCells()`, `createAtomicBeefCells()`, `createEnvelopeCells()`, `createDataCells()`. Continuation header: 8 bytes (cellType:1B, cellIndex:2B, totalCells:2B, payloadSize:2B, reserved:1B). LIFO alt-stack ordering. |
| `PACKER:MERKLE` | `semantos-core/src/cell-engine/merkleEnvelope.ts` | **Merkle envelope (canonical, in this repo).** Dependency of cellPacker. `buildMerkleTree()`, `serializeMerkleEnvelope()`. |
| `FORTH:SEMOBJ` | `semantos-gift-pack/forth/semantic-objects.fs` | Design reference for header fields and their semantics. Object factories for LINEAR/AFFINE/RELEVANT. Magic number validation logic. |
| `FORTH:COMMERCE` | `semantos-gift-pack/forth/commerce-header.fs` | Commerce extension layout within reserved block. Phase(1B@94), Dimension(1B@95), ParentHash(32B@96), PrevState(32B@128). Type hash = SHA256(WHAT + ":" + HOW + ":" + INST). |
| `FORTH:SEMOBJ-ENH` | `semantos-gift-pack/forth/semantic-objects-enhanced.fs` | On-chain binding: TXID(32B@160), VOUT(4B@192), BUMP-HASH(24B@196), DERIVATION-INDEX(4B@220). |
| `FORTH:STORAGE` | `semantos-gift-pack/forth/semantic-storage-patterns.fs` | Payload usage patterns for the 768-byte data area. |

---

## Deliverables

### D1.1 — `cell.zig`

Implements single-cell packing and unpacking:

```zig
pub const CellHeader = struct {
    magic: [16]u8,        // 0xDEADBEEF CAFEBABE 13371337 42424242
    linearity: u32,       // 1=LINEAR, 2=AFFINE, 3=RELEVANT, 4=DEBUG
    version: u32,
    flags: u32,
    ref_count: u16,
    type_hash: [32]u8,    // SHA256 of WHAT:HOW:INST taxonomy
    owner_id: [16]u8,
    timestamp: u64,
    cell_count: u32,
    total_size: u32,
    reserved: [162]u8,    // Commerce extension + on-chain binding + padding
};

pub fn packCell(header: *const CellHeader, payload: []const u8, out: *[1024]u8) PackError!void;
pub fn unpackCell(cell: *const [1024]u8) UnpackError!struct { header: CellHeader, payload: [768]u8 };
pub fn validateMagic(header: *const CellHeader) bool;
pub fn getCommerceExtension(header: *const CellHeader) CommerceExtension;
pub fn setCommerceExtension(header: *CellHeader, ext: CommerceExtension) void;
pub fn getOnChainBinding(header: *const CellHeader) OnChainBinding;
pub fn setOnChainBinding(header: *CellHeader, binding: OnChainBinding) void;
```

**Critical constraints**:
- Header is ALWAYS exactly 256 bytes. If input fields don't fill 256 bytes, zero-pad.
- Payload is ALWAYS exactly 768 bytes. If input payload is shorter, zero-pad.
- Output is ALWAYS exactly 1024 bytes. No variable-length cells.
- Byte order: little-endian for all multi-byte integers (matching TypeScript DataView defaults).
- Magic validation: all 4 magic values must be present and correct, or unpack fails with `InvalidMagic`.

### D1.2 — `commerce.zig`

Commerce extension read/write within the reserved block:

```zig
pub const CommerceExtension = struct {
    phase: u8,            // offset 94 within header
    dimension: u8,        // offset 95
    parent_hash: [32]u8,  // offset 96
    prev_state: [32]u8,   // offset 128
};
```

### D1.3 — `multicell.zig`

Multi-cell packing for objects larger than 768 bytes:

```zig
pub const ContinuationHeader = struct {
    cell_type: u8,       // BUMP=1, ATOMIC_BEEF=2, ENVELOPE=3, DATA=4, STATE=5
    cell_index: u16,
    total_cells: u16,
    payload_size: u16,
    reserved: u8,
};
// Total: 8 bytes. Continuation payload: 1016 bytes.

pub fn packMultiCell(header: *const CellHeader, payload: []const u8, bump: ?[]const u8, beef: ?[]const u8) PackError![]const [1024]u8;
pub fn unpackMultiCell(cells: []const [1024]u8) UnpackError!MultiCellResult;
```

**Cell ordering** (LIFO for alt-stack):
- Cell 0: Semantic object (header + payload)
- Cell 1: BUMP (BRC-74 merkle proof) — if present
- Cell 2: Atomic BEEF (BRC-95 envelope) — if present
- Cell 3+: State/Data continuation cells

### D1.4 — Cross-language test vectors

Generate test vectors by running the TypeScript packer (`PACKER:TYPE-REGISTRY` + `PACKER:MAIN`) on known inputs and capturing the raw bytes. Store as:

```
tests/vectors/
├── single_cell_linear.bin     # LINEAR object, minimal payload
├── single_cell_affine.bin     # AFFINE object, full payload
├── single_cell_relevant.bin   # RELEVANT with commerce extension
├── multi_cell_3.bin           # 3-cell object with BUMP and BEEF
├── commerce_all_phases.bin    # Commerce extension for each phase
└── vectors.json               # Input parameters for each test vector
```

---

## TDD Gate — Tests That Must Pass

### Test 1: Single cell round-trip (Zig)
```zig
// cell_conformance.zig
test "pack/unpack round-trip preserves all header fields" {
    // Create header with known values
    // Pack to 1024 bytes
    // Unpack
    // Assert every field matches original
}

test "packed cell is exactly 1024 bytes" { ... }
test "header is exactly 256 bytes at offset 0" { ... }
test "payload is exactly 768 bytes at offset 256" { ... }
test "magic validation rejects wrong magic" { ... }
test "zero-padding fills unused payload bytes" { ... }
```

### Test 2: Commerce extension (Zig)
```zig
// commerce_conformance.zig
test "commerce extension at correct offsets within reserved" { ... }
test "phase byte at offset 94 of header" { ... }
test "dimension byte at offset 95 of header" { ... }
test "parent hash 32 bytes at offset 96" { ... }
test "prev state hash 32 bytes at offset 128" { ... }
test "all commerce phase constants match Forth reference" { ... }
```

### Test 3: Multi-cell packing (Zig)
```zig
// multicell_conformance.zig
test "continuation header is exactly 8 bytes" { ... }
test "continuation payload is exactly 1016 bytes" { ... }
test "cell ordering: Cell 0 is header, Cell 1 is BUMP, Cell 2 is BEEF" { ... }
test "cell_index increments sequentially" { ... }
test "total_cells field matches actual cell count" { ... }
test "unpack(pack(input)) == input for multi-cell objects" { ... }
```

### Test 4: Cross-language byte identity (TypeScript)
```typescript
// compat.test.ts
test("Zig packCell output matches TypeScript packCell output", () => {
    // Same input → both produce identical 1024 bytes
});

test("TypeScript can unpack Zig-packed cells", () => {
    // Zig packs → TS unpacks → fields match
});

test("Zig can unpack TypeScript-packed cells", () => {
    // TS packs → Zig unpacks → fields match
});

test("Multi-cell round-trip across languages", () => {
    // TS packs 3-cell object → Zig unpacks → fields match
});
```

### Test 5: On-chain binding (Zig)
```zig
test "on-chain binding TXID at offset 160 within header" { ... }
test "on-chain binding VOUT at offset 192" { ... }
test "on-chain binding does not overlap commerce extension" { ... }
```

---

## Phase Completion Criteria

You are **done with Phase 1** when ALL of the following are true:

1. `zig build test` passes all cell_conformance, commerce_conformance, and multicell_conformance tests
2. `bun test tests-ts/compat.test.ts` passes all cross-language byte-identity tests
3. Test vectors exist in `tests/vectors/` generated from the TypeScript packer
4. Zig-packed bytes are **bit-identical** to TypeScript-packed bytes for the same inputs
5. No hardcoded byte offsets in Zig code — all offsets come from `constants.zig` (generated from `constants.json`)
6. Commerce extension and on-chain binding occupy non-overlapping regions of the reserved block
7. Edge cases handled: empty payload, maximum payload (768 bytes), payload > 768 bytes triggers multi-cell
8. Error handling: InvalidMagic, PayloadTooLarge, InvalidCellCount — no panics, no unreachable

## What NOT To Do

- Do not implement type hash computation (SHA256) — that requires host_sha256, which is Phase 2+. The type_hash field is packed/unpacked as raw 32 bytes.
- Do not implement any crypto operations
- Do not implement stack operations (2-PDA) — that's Phase 3
- Do not normalise or transform byte order differently from typeHashRegistry.ts — match it exactly
- Do not use GForth cell-width offsets (8 bytes per field) — use packed byte offsets
- Do not create mock test vectors — generate them from the actual TypeScript packer

---

## Errata — Issues Discovered During First Phase 1 Attempt

### E-P1.1: Magic bytes are raw bytes, NOT little-endian u32s
The TypeScript packer writes `Buffer.from([0xde, 0xad, 0xbe, 0xef, ...])` and copies the bytes directly at offset 0. If Zig writes magic as `u32` values with `std.mem.writeIntLittle`, the byte order will be `[0xef, 0xbe, 0xad, 0xde]` — wrong. **Fix**: Write magic as a raw `[16]u8` array matching the exact byte sequence from `typeHashRegistry.ts`.

### E-P1.2: Missing constants — on-chain binding offsets
`constants.json` does not include on-chain binding offsets: TXID(32B@160), VOUT(4B@192), BUMP_HASH(24B@196), DERIVATION_INDEX(4B@220). **Fix**: Add these to `constants.json` and re-run the generator before implementing `cell.zig`. Source: `FORTH:SEMOBJ-ENH`.

### E-P1.3: Naming ambiguity in constants.zig
`HEADER_SIZE_TOTAL` (value 90) is the byte offset of the `totalSize` field, not the total header size (which is `HEADER_SIZE` = 256). **Fix**: Verify each constant name against its meaning. The offset constants should follow `HEADER_OFFSET_*` naming.

### E-P1.4: errors.zig needs Phase 1 variants
Current `errors.zig` only has Phase 0 error codes. **Fix**: Add `InvalidMagic`, `PayloadTooLarge`, `InvalidCellCount`, `InvalidContinuationHeader` before implementing unpack functions.

### E-P1.5: Multi-cell WASM exports not wired — RESOLVED
`multicell.zig` implements `packMultiCell` and `unpackMultiCell` but initially `main.zig` did not export them. **Fixed**: `multicell_pack` and `multicell_unpack` now exported from `main.zig`. `multicell_pack` takes flat arrays (types, offsets, sizes, concatenated data) for WASM linear memory compatibility. WASM binary grew from 1.3KB to 3.9KB with these exports.

### E-P1.6: Cross-language multi-cell byte-identity test incomplete — RESOLVED
Initially only single-cell byte identity was tested cross-language. **Fixed**: `compat.test.ts` now includes 4 multi-cell tests:
- Zig multi-cell output matches TS output byte-for-byte (same inputs → identical 3072 bytes)
- Zig multi-cell matches `multi_cell_3.bin` vector
- TS can unpack Zig multi-cell output (fields + continuation data match)
- Zig `multicell_unpack` validates and returns correct cell count for TS-packed input

---

## Next Phase

Phase 1 output feeds into **Phase 2: BCA Derivation and Verification**, which adds the first host function (`host_sha256`) and implements Bitcoin-Certified Address generation.
