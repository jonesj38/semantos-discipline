---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-6-OCTAVE-MEMORY.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.713079+00:00
---

# Phase 6: Octave Memory Scaling — Hierarchical Cell Addressing

**Duration**: 3 weeks (with 40% buffer: ~30 days)
**Prerequisites**: Phase 5 complete — BEEF/BUMP host functions working, capability token verification passing. Must be complete before Phase 7 (TS Bindings) so the Bun bindings can expose octave addressing.
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` (in this directory: `semantos-core/docs/prd/`)

---

## Context

The Semantos cell engine currently operates at a single scale: 1024 × 1KB cells (1MB address space). This is sufficient for semantic objects, capability tokens, BCA addresses, evidence items, and patches — but it cannot represent objects larger than ~1024KB (chained continuation cells). Real-world payloads — large documents, PDF extractions, image evidence, video frames, full BREM assessments, agent memory archives — exceed this limit.

This phase introduces **octave-based hierarchical memory scaling**: a system where cells at one level can act as pointers to cells at the next level, scaling by factors of 1024 at each octave.

### The Octave Model

```
Octave 0  —  1KB cells      (1024 × 1KB   = 1MB   address space)
Octave 1  —  1MB cells      (1024 × 1MB   = 1GB   address space)
Octave 2  —  1GB cells      (1024 × 1GB   = 1TB   address space)
Octave N  —  1KB × 1024^N   per cell
```

### The Shipping Container Analogy

A cell is like a shipping container — standardised external dimensions, arbitrary internal contents. A container full of shoes and a container full of electronics move through the same infrastructure identically. A half-full container that moves through global logistics infrastructure efficiently is better than a perfectly packed custom crate that requires bespoke handling at every port.

When a single container isn't enough, you don't redesign the container — you chain multiple containers. When the object is too large for chaining at one level, you escalate: a container (Octave 0 cell) becomes a pointer to a pallet (Octave 1 cell). Pallets contain boxes, warehouses contain pallets. Same interface at every level, same handling machinery scaled up.

### CAS + Location Duality

The registry resolves through two complementary addressing modes:

```
Primary address   →  typeHash (content-addressed, what it is)
Secondary address →  octave + cell depth + offset (location-addressed, where it is)
```

Semantic recall finds the cell slot by content hash. Spatial navigation within that slot finds the specific item by offset within the octave hierarchy.

### Existing Patterns Being Extended

The Forth reference implementation already establishes:

- **`BYTES>CELLS`**: `( bytes + 1023 ) / 1024` — deterministic cell count calculation
- **Continuation headers**: 8-byte headers (type, index, total, size, reserved) + 1016-byte payload
- **Coordinator system**: `CREATE-SMART-OBJECT` in `coordinators-flexible.fs` auto-selects inline (< 768 bytes) vs. coordination (> 768 bytes)
- **`CREATE-PUSHDATA4-COORDINATOR`**: handles large data push coordination across multiple cells
- **Multi-cell packing in `cellPacker.ts`**: Cell 0 (semantic object), Cell 1 (BUMP), Cell 2 (BEEF), Cell 3+ (data/state continuation)

This phase generalises that pattern to handle objects that exceed what continuation chaining can address within a single octave.

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `FORTH:COORDS-PROVEN` | `semantos/bitcoin-script/semantic/coordinators-proven.fs` | `BYTES>CELLS` formula, `CREATE-PUSHDATA4-COORDINATOR` (large data coordination), `CREATE-STACK-RANGE` (stack region tracking with offset access). **Key pattern**: `COORD-STORE-2`/`COORD-FETCH-2` stores two values (address + size) in an object's data area — this is exactly what the PointerPayload does: store an octave address + metadata in the 768-byte payload. |
| `FORTH:COORDS-FLEXIBLE` | `semantos/bitcoin-script/semantic/coordinators-flexible.fs` | `CHOOSE-STORAGE-STRATEGY` (768-byte threshold), `CREATE-SMART-OBJECT` (auto-select inline vs coordination) |
| `FORTH:COORDS-HYBRID` | `semantos/bitcoin-script/semantic/coordinators-hybrid.fs` | `INLINE-STORE-STRING` (< 768 inline), `CREATE-SMART-COORDINATOR` (size-based strategy selection) |
| `FORTH:DUAL-STORAGE` | `semantos/bitcoin-script/semantic/dual-storage-coordinators.fs` | **Three storage strategies in one file**: (1) `SET-INLINE-CONFIG` for data < 768 bytes with overflow abort, (2) `CREATE-CELL-COORDINATOR` that computes `BYTES>CELLS` and stores (start-cell, count) via `SET-CELL-COORDINATION` — this is the direct ancestor of `allocForSize` routing to the correct octave, (3) `CREATE-HYBRID-WORKSPACE` with metadata inline + cell count at offset 0 + metadata at offset 8. The 10MB demo (`10485760 CREATE-CELL-COORDINATOR`) proves the coordination model scales. |
| `FORTH:LINEAR-MEM` | `semantos/v4-improvements/linear-memory.fs` | **Pool-per-linearity allocation model**: 4 separate pools (LINEAR 16KB, AFFINE 16KB, RELEVANT 32KB, DEBUG 8KB). 8-byte block headers: size(4B), state(1B), refcount(1B), linearity(1B), pad(1B). `ALLOC-FROM-POOL` with 8-byte alignment. `CONSUME-LINEAR` with double-consumption detection and ABORT. `COLLECT-RELEVANT-GARBAGE` sweeps zero-refcount RELEVANT objects. `SlotMeta` in the octave pool maps directly to this block header. Pool states: `POOL-FREE(0)`, `POOL-ALLOCATED(1)`, `POOL-CONSUMED(2)` → identical to `SlotState`. |
| `DOC:MEM-PLAN` | `semantos/docs/memory-management-plan.md` | **Memory management roadmap**: reference counting in Thing structures, mark-and-sweep GC, type discrimination (`IS-SEMANTIC-OBJECT?`), state persistence via serialise/deserialise. The `INCREF`/`DECREF` pattern with zero-refcount → `GC-MARK-FREE` maps to the RELEVANT slot ref_count tracking in octave pools. |
| `PACKER:MAIN` | `semantos-core/src/cell-engine/cellPacker.ts` | Multi-cell layout, continuation header format (`ContinuationHeader`), `CONTINUATION_TYPE` enum, `CELL_SIZE`, `PAYLOAD_SIZE`, `CONTINUATION_PAYLOAD_SIZE` |
| `PACKER:TYPE-REGISTRY` | `semantos-core/src/cell-engine/typeHashRegistry.ts` | Canonical wire-format header layout — 256 bytes. Offsets for `cellCount` (86-90), `totalSize` (90-94). Commerce extension (94-128). |
| `FORTH:2PDA` | `semantos-gift-pack/forth/bitcoin-2pda.fs` | 1024 main cells × 1KB = 1MB, 256 aux cells × 1KB = 256KB. Stack pointer arithmetic. |
| `CORE:SEMOBJ` | `semantos-core/src/types/semantic-objects.ts` | `LinearObject`, `AffineObject`, `RelevantObject` interfaces. The pointer cell must respect linearity rules. |
| `CORE:WASM` | `semantos-core/src/cell-engine/wasm-interface.ts` | Existing WASM export contract. New exports must not break existing interface. |
| `ZIG:ALLOC` | `semantos-core/packages/cell-engine/src/allocator.zig` | Current arena allocator — deterministic script execution memory, no individual frees in hot paths. Octave pools must extend this discipline. |
| `ZIG:LINEARITY` | `semantos-core/packages/cell-engine/src/linearity.zig` | Current linearity enforcement woven into DUP/DROP/SWAP at opcode level. Pointer cells must inherit linearity semantics from referenced content. |

---

## Deliverables

### D6.1 — Pointer Cell Type Definition

Add `POINTER` to the continuation type enum in both TypeScript and Zig:

```typescript
// cellPacker.ts addition
export const CONTINUATION_TYPE = {
  BUMP:         0x01,
  ATOMIC_BEEF:  0x02,
  ENVELOPE:     0x03,
  DATA:         0x04,
  STATE:        0x05,
  POINTER:      0x06,   // NEW: references a cell at a higher octave
} as const;
```

**Pointer cell wire format** (1024 bytes total):

```
[8-byte continuation header]
  cellType:    0x06 (POINTER)
  cellIndex:   position in continuation sequence
  totalCells:  total continuation cells
  payloadSize: actual data bytes (fixed: 90)
  reserved:    0x00

[90-byte pointer payload]
  octave:         u8          (target octave level: 0, 1, 2, 3)
  slot:           u16 LE      (slot within that octave, 0-1023)
  offset:         u32 LE      (byte offset within the cell)
  _pad:           u8          (padding byte, always 0)
  contentHash:    [32]u8      (SHA256 hash of the referenced content)
  typeHash:       [32]u8      (type hash of the referenced object — for CAS lookup)
  totalSize:      u64 LE      (actual byte size of referenced object)
  flags:          u8          (bit 0: immutable, bit 1: encrypted, bit 2: compressed)
  fragmentCount:  u16 LE      (number of sub-cells at the target octave, 0 = single cell)
  reserved:       [7]u8

[926-byte padding → zero-filled]
```

**Key constraint**: A pointer cell is always RELEVANT linearity (can be copied, can be dropped). The referenced content inherits the linearity of its original semantic object header. This prevents the pointer from being consumed while the underlying data is still needed.

### D6.2 — Octave Address Space in Zig

```zig
// octave.zig
pub const Octave = enum(u8) {
    base = 0,       // 1KB cells, 1024 slots = 1MB
    kilo = 1,       // 1MB cells, 1024 slots = 1GB
    mega = 2,       // 1GB cells, 1024 slots = 1TB
    giga = 3,       // 1TB cells, 1024 slots = 1PB
};

pub const OctaveAddress = struct {
    octave: Octave,
    slot: u16,          // 0-1023 within the octave
    offset: u32,        // byte offset within the cell (0 for start)
};

pub fn cellSizeForOctave(oct: Octave) u64 {
    return @as(u64, 1024) << (@as(u6, @intFromEnum(oct)) * 10);
}

pub fn addressSpaceForOctave(oct: Octave) u64 {
    return cellSizeForOctave(oct) * 1024;
}

pub fn bytesToCellsAtOctave(bytes: u64, oct: Octave) u64 {
    const cell_size = cellSizeForOctave(oct);
    return (bytes + cell_size - 1) / cell_size;
}
```

### D6.3 — Pointer Cell Packer/Unpacker (TypeScript)

Extend `cellPacker.ts` with:

```typescript
export interface PointerPayload {
  octave: number;           // 0-3
  cellAddress: bigint;      // u64
  contentHash: Uint8Array;  // 32 bytes
  typeHash: Uint8Array;     // 32 bytes
  totalSize: bigint;        // u64
  flags: number;            // u8
  fragmentCount: number;    // u16
}

export function createPointerCell(payload: PointerPayload): Uint8Array;
export function parsePointerCell(cell: Uint8Array): PointerPayload;
export function isPointerCell(cell: Uint8Array): boolean;
```

Must produce bit-identical output between TypeScript and Zig implementations.

### D6.4 — 2-PDA Pointer Dereference Opcode

Add a new Plexus opcode for pointer dereference:

```
OP_DEREF_POINTER (0xC8)
```

Behaviour:
1. Pop top cell from main stack
2. Verify it has `POINTER_CELL` flag (continuation type 0x06)
3. Extract octave + cellAddress from pointer payload
4. Call host function `host_fetch_cell(octave, address, out_ptr, out_len)` to retrieve the referenced cell
5. Push the retrieved cell onto the main stack
6. If the retrieved cell is itself a pointer, do NOT auto-dereference (explicit dereference only)

The host function is the escalation point — the 2-PDA engine stays the same, only the memory backing changes at each octave.

### D6.5 — Host Function for Octave Storage

```typescript
// host-functions.ts addition
host_fetch_cell(octave: number, slot: number, offset: number, outPtr: number): number;
// Returns: 1 on success (1024 bytes written to outPtr), 0 on failure.
// Always writes exactly 1KB. For octave 1+ fetches, the host slices at offset.
```

```zig
// host.zig addition
pub extern "host" fn host_fetch_cell(octave: u8, slot: u32, offset: u32, out_ptr: [*]u8) u32;
```

The host implementation is a pluggable backend:
- **In-memory** (dev/test): Map keyed by `${octave}:${slot}`
- **File-backed** (Plexus node): mmap'd files at each octave
- **BSV-anchored** (production): BEEF envelope fetch by txid + vout

### D6.6 — Octave-Aware Cell Registry

Extend the registry concept so cells can be looked up by either:
- **typeHash** (CAS lookup): returns the cell wherever it lives
- **OctaveAddress** (location lookup): direct fetch by octave + slot

```typescript
interface CellRegistry {
  // CAS: content-addressed storage
  store(cell: Uint8Array, octave?: number): OctaveAddress;
  fetchByTypeHash(typeHash: Uint8Array): Uint8Array | null;

  // Location: direct addressing
  fetchByAddress(addr: OctaveAddress): Uint8Array | null;

  // Escalation: store large object, return pointer cell at Octave 0
  storeWithEscalation(data: Uint8Array, typeHash: Uint8Array): Uint8Array;
}
```

The `storeWithEscalation` method:
1. If `data.length <= 768` → store inline in a single Octave 0 cell
2. If `data.length <= ~1016 * 1024` → use continuation cells at Octave 0
3. If larger → store at Octave 1, return an Octave 0 pointer cell
4. Recursively escalate if Octave 1 is also insufficient

### D6.7 — MFP Payment Scaling by Octave

The payment rate scales linearly with octave:

```
Octave 0 read  →  1 sat per cell      (1KB)
Octave 1 read  →  1000 sat per cell   (1MB)
Octave 2 read  →  1000000 sat per cell (1GB)

Formula: cost_sats = 1000^octave per cell
```

This maps directly into the existing MFP metering FSM (`channel-fsm.ts`). The `tick` payload includes the octave, and the settlement price adjusts accordingly.

---

## TDD Gate

All tests must pass before this phase is complete.

### Zig Tests (in `tests/octave_conformance.zig`)

```
T6.01  cellSizeForOctave(.base) == 1024
T6.02  cellSizeForOctave(.kilo) == 1_048_576
T6.03  cellSizeForOctave(.mega) == 1_073_741_824
T6.04  addressSpaceForOctave(.base) == 1_048_576
T6.05  bytesToCellsAtOctave(10240, .base) == 10
T6.06  bytesToCellsAtOctave(2_000_000, .kilo) == 2
T6.07  Pointer cell pack → unpack round-trip (bit-identical)
T6.08  isPointerCell correctly identifies CONTINUATION_TYPE 0x06
T6.09  OP_DEREF_POINTER pops pointer cell and calls host_fetch_cell
T6.10  OP_DEREF_POINTER on non-pointer cell → error
T6.11  Pointer cell linearity is always RELEVANT
T6.12  Nested pointer (pointer → pointer) does NOT auto-dereference
```

### TypeScript Cross-Language Tests (in `tests-ts/octave_compat.test.ts`)

```
T6.13  TS createPointerCell output == Zig pointer cell output (byte-for-byte)
T6.14  TS parsePointerCell correctly reads Zig-packed pointer cell
T6.15  storeWithEscalation: 500-byte object → single Octave 0 cell (no pointer)
T6.16  storeWithEscalation: 2MB object → Octave 1 cell + Octave 0 pointer
T6.17  storeWithEscalation: round-trip (store → fetch pointer → dereference → verify content hash)
T6.18  CellRegistry CAS lookup by typeHash returns correct cell
T6.19  CellRegistry location lookup by OctaveAddress returns correct cell
T6.20  MFP cost calculation: octave 0 = 1 sat, octave 1 = 1000 sat, octave 2 = 1_000_000 sat
```

---

## Phase Completion Criteria

- [x] `CONTINUATION_TYPE.POINTER` (0x06) added to both TS (`cellPacker.ts`) and Zig (`constants.zig`)
- [x] Pointer cell wire format is 1024 bytes with 90-byte payload at defined offsets
- [x] `octave.zig` implements `Octave`, `OctaveAddress`, `cellSizeForOctave`, `bytesToCellsAtOctave`
- [x] `pointer.zig` implements pack/unpack/identify with slot+offset fields (no ambiguous cell_address)
- [x] `OP_DEREF_POINTER` (0xC8) added to Plexus opcode set, failure-atomic
- [x] `host_fetch_cell` host function defined in both TS and Zig
- [x] WASM integration test: seed cell → push pointer → execute 0xC8 → verify fetch
- [x] Embedded WASM binary remains under 50KB (~29KB)
- [x] No existing Phase 0-5 tests broken
- [x] MFP cost scaling formula implemented and tested
- [ ] ~~Zig and TS pointer cell packers produce bit-identical output~~ — deferred to Phase 7 (TS packer not needed until Bun bindings)
- [ ] ~~In-memory CellRegistry with CAS + location dual addressing~~ — deferred to Phase 7
- [ ] ~~`storeWithEscalation` correctly routes objects to the right octave~~ — deferred to Phase 7

**Known limitation (BUG-5)**: T6.09-T6.12 (OP_DEREF_POINTER opcode tests) cannot run in the Zig native test runner because `host_fetch_cell` returns false in native builds (same pattern as `host_checksig`). These tests are covered by the WASM integration tests in `tests-ts/octave_compat.test.ts` instead.

---

## What NOT To Do

- **Do NOT implement disk-backed or BSV-anchored storage** — that's infrastructure, not engine. Use in-memory HashMap for this phase.
- **Do NOT auto-dereference nested pointers** — the 2-PDA must explicitly `OP_DEREF_POINTER` at each level. Implicit dereferencing hides costs and breaks determinism.
- **Do NOT change the Octave 0 cell format** — the existing 1024-byte cell with 256-byte header and 768-byte payload is sacred. Pointer cells are a new continuation type, not a header change.
- **Do NOT implement Octave 2+ storage backends** — define the addressing math, but only implement Octave 0 and Octave 1 storage for this phase.
- **Do NOT adjust tests to pass** — if byte output differs between TS and Zig, fix the code, not the test.
- **Do NOT break the existing continuation header format** — pointer cells use the same 8-byte continuation header as BUMP/BEEF/DATA cells.

---

## Practical Octave Map

```
Octave 0  (1KB)   —  semantic object cells, capability tokens,
                      BCA addresses, evidence items, patches,
                      pointer cells to higher octaves

Octave 1  (1MB)   —  large documents, PDF extractions,
                      image evidence, video frames,
                      BREM full assessment with all evidence

Octave 2  (1GB)   —  large media, full job histories,
                      complete agent memory archives,
                      Plexus node storage volumes

Octave 3  (1TB)   —  distributed asset library catalogues,
                      enterprise BREM datasets,
                      full SNS registry shards
```

---

## Forth → Zig Pattern Mapping

The Forth reference implementation contains the conceptual precursors to every octave deliverable. This table maps Forth patterns to their Zig equivalents to ensure nothing is lost in translation:

| Forth Pattern | File | Zig Equivalent | Deliverable |
|---------------|------|---------------|-------------|
| `BYTES>CELLS` (`1024 + 1023 - 1024 /`) | `coordinators-proven.fs` | `bytesToCellsAtOctave(bytes, oct)` with `cellSize = 1024 << (oct * 10)` | D6.2 |
| `CREATE-CELL-COORDINATOR` (compute cells-needed, store start+count) | `dual-storage-coordinators.fs` | `OctaveRegistry.allocForSize()` routing to correct octave | D6.6 |
| `SET-CELL-COORDINATION` (store start-cell + count in object data) | `dual-storage-coordinators.fs` | `PointerPayload` struct (octave + cellAddress + totalSize in 768B payload) | D6.1 |
| `COORD-STORE-2`/`COORD-FETCH-2` (two-value storage in object data area) | `coordinators-proven.fs` | `packPointerCell`/`unpackPointerCell` (read/write pointer fields in cell payload) | D6.1, D6.3 |
| `CHOOSE-STORAGE-STRATEGY` (768-byte threshold → inline vs coordination) | `coordinators-flexible.fs` | `storeWithEscalation` (≤768B inline, ≤1MB continuation, >1MB → octave pointer) | D6.6 |
| `CREATE-HYBRID-WORKSPACE` (metadata inline + cell count at offset 0) | `dual-storage-coordinators.fs` | Pointer cell: header fields inline (256B) + pointer metadata in payload (89B) + zero-pad | D6.1 |
| Pool-per-linearity (LINEAR/AFFINE/RELEVANT/DEBUG pools) | `linear-memory.fs` | `SlotMeta.linearity` per octave slot, inherited from content | D6.2, D6.6 |
| 8-byte block header (size, state, refcount, linearity) | `linear-memory.fs` | `SlotMeta` struct (state, linearity, content_hash, actual_size, ref_count) | D6.2 |
| `POOL-FREE(0)`/`POOL-ALLOCATED(1)`/`POOL-CONSUMED(2)` | `linear-memory.fs` | `SlotState.free(0)`/`allocated(1)`/`consumed(2)` — identical enum values | D6.2 |
| `CONSUME-LINEAR` with double-consumption ABORT | `linear-memory.fs` | `OP_DEREF_POINTER` must respect linearity: LINEAR content consumed once when resolved | D6.4 |
| `COLLECT-RELEVANT-GARBAGE` (sweep zero-refcount objects) | `linear-memory.fs` | Future: octave GC pass that frees slots with ref_count=0. Not in Phase 6 but slot metadata supports it. |
| `INCREF`/`DECREF` with zero-refcount → `GC-MARK-FREE` | `memory-management-plan.md` | `SlotMeta.ref_count` for RELEVANT slots; decrement on pointer cell drop | D6.2 |
| `VALIDATE-ACCESS` (reject reads on consumed memory) | `linear-memory.fs` | Octave pool `readSlot` must check `SlotState != consumed` before returning data | D6.2 |
| `CREATE-PUSHDATA4-COORDINATOR` (large data → cell count → stack range) | `coordinators-proven.fs` | `bytesToCellsAtOctave` + `allocSlot` at the appropriate octave level | D6.2 |

---

## Next Phase

Phase 7 (formerly Phase 6) will build the TypeScript/Bun bindings that expose the octave addressing and pointer cell APIs to the application layer.
