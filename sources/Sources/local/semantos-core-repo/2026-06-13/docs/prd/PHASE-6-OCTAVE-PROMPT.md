---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-6-OCTAVE-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.704378+00:00
---

# Phase 6 Prompt — Octave Memory Scaling

Copy everything below the line into a fresh Claude Code session.

---

## Prompt Start

Read these two documents in full before producing any output:

1. `/Users/toddprice/projects/semantos-core/docs/prd/README.md`
2. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-6-OCTAVE-MEMORY.md`

Then read these source files to understand the existing patterns you are extending:

3. `/Users/toddprice/projects/semantos/bitcoin-script/semantic/coordinators-proven.fs` — The `BYTES>CELLS` formula and `CREATE-PUSHDATA4-COORDINATOR` pattern. Key: `COORD-STORE-2`/`COORD-FETCH-2` stores two values (address + size) in an object's data area — this is exactly what the PointerPayload does.
4. `/Users/toddprice/projects/semantos/bitcoin-script/semantic/coordinators-flexible.fs` — The `CHOOSE-STORAGE-STRATEGY` and `CREATE-SMART-OBJECT` pattern. Shows auto-selection of inline vs. coordination storage based on size thresholds.
5. `/Users/toddprice/projects/semantos/bitcoin-script/semantic/dual-storage-coordinators.fs` — **Critical**: Three storage strategies: (1) `SET-INLINE-CONFIG` for < 768B, (2) `CREATE-CELL-COORDINATOR` computing `BYTES>CELLS` and storing (start-cell, count), (3) `CREATE-HYBRID-WORKSPACE` with metadata inline + cells for data. The 10MB demo proves coordination scales. This is the direct ancestor of `allocForSize`.
6. `/Users/toddprice/projects/semantos/v4-improvements/linear-memory.fs` — **Critical**: Pool-per-linearity allocation. 4 pools (LINEAR 16KB, AFFINE 16KB, RELEVANT 32KB, DEBUG 8KB). 8-byte block headers (size, state, refcount, linearity). `ALLOC-FROM-POOL` with alignment. `CONSUME-LINEAR` with double-consumption ABORT. `COLLECT-RELEVANT-GARBAGE` sweeps zero-refcount objects. `SlotMeta` in the octave pool maps directly to this block header. Pool states `POOL-FREE(0)`/`POOL-ALLOCATED(1)`/`POOL-CONSUMED(2)` are identical to `SlotState`.
7. `/Users/toddprice/projects/semantos/docs/memory-management-plan.md` — Memory management roadmap: `INCREF`/`DECREF` with zero-refcount → `GC-MARK-FREE`. Maps to RELEVANT slot ref_count tracking.
8. `/Users/toddprice/projects/semantos-core/src/cell-engine/cellPacker.ts` — The production multi-cell packer. Read the full file. Pay close attention to `CONTINUATION_TYPE`, `ContinuationHeader`, and the cell layout comments.
9. `/Users/toddprice/projects/semantos-core/src/cell-engine/typeHashRegistry.ts` — The canonical wire-format header. Note `cellCount` at bytes 86-90 and `totalSize` at bytes 90-94.
10. `/Users/toddprice/projects/semantos/semantos-gift-pack/forth/bitcoin-2pda.fs` — The 2-PDA stack reference. 1024 main cells × 1KB = 1MB. This is the Octave 0 address space.

### What already exists (Phases 0-5 output)

Phases 0-5 are complete and verified. Everything lives at `/Users/toddprice/projects/semantos-core/`:

```
semantos-core/
├── package.json                   # @semantos/core v0.3.0
├── src/cell-engine/
│   ├── typeHashRegistry.ts        # Canonical wire-format header builder
│   ├── cellPacker.ts              # Multi-cell packer with BUMP/BEEF/DATA/STATE continuations
│   ├── merkleEnvelope.ts          # Merkle envelope serialization
│   ├── wasm-interface.ts          # PlexusKernelWasm + PlexusKernelHostImports
│   └── opcodes.ts                 # Plexus opcodes 0xC0-0xC7
├── packages/
│   └── cell-engine/
│       ├── build.zig
│       ├── src/
│       │   ├── main.zig           # WASM exports
│       │   ├── cell.zig           # Cell pack/unpack
│       │   ├── multicell.zig      # Multi-cell pack/unpack + continuation headers
│       │   ├── pda.zig            # 2-PDA dual-stack engine
│       │   ├── linearity.zig      # Linearity enforcement
│       │   ├── host.zig           # Host function externs
│       │   ├── errors.zig         # Error codes
│       │   └── opcodes/
│       │       ├── standard.zig   # Standard Bitcoin opcodes
│       │       ├── macro.zig      # Craig macros 0xB0-0xBF
│       │       └── plexus.zig     # Plexus opcodes 0xC0-0xC7
│       ├── bindings/
│       │   └── host-functions.ts  # TS host function implementations
│       └── tests/                 # All existing test files
```

28KB WASM binary. All Phase 0-5 tests pass.

### What you are building

**Phase 6: Octave Memory Scaling** — Hierarchical cell addressing that lets the engine reference objects larger than the Octave 0 (1MB) address space.

The core insight: when an object exceeds what continuation chaining can handle at Octave 0, a cell becomes a **pointer cell** that references a cell at a higher octave. The 2-PDA pops the pointer, dereferences it via a host function, and the execution engine scales up to the next octave. The same binary, same deterministic execution — only the memory backing changes.

### Implementation sequence (follow this order exactly)

**Step 1**: Add `octave.zig` — Octave enum, OctaveAddress struct, `cellSizeForOctave`, `bytesToCellsAtOctave`. Write tests first (`tests/octave_test.zig`). Tests T6.01-T6.06 must pass.

**Step 2**: Add `CONTINUATION_TYPE.POINTER = 0x06` to `cellPacker.ts`. Add `PointerPayload` interface, `createPointerCell`, `parsePointerCell`, `isPointerCell` functions. The pointer payload is 89 bytes: octave(u8) + cellAddress(u64) + contentHash(32) + typeHash(32) + totalSize(u64) + flags(u8) + fragmentCount(u16) + reserved(6). Zero-pad to 1024.

**Step 3**: Add Zig pointer cell packing in `multicell.zig` (or a new `pointer.zig`). Must produce byte-identical output to TypeScript. Tests T6.07-T6.08, T6.13-T6.14 must pass.

**Step 4**: Add `OP_DEREF_POINTER = 0xC8` to `opcodes/plexus.zig`. Pops cell, checks continuation type 0x06, extracts octave + address, calls `host_fetch_cell`. Push result onto stack. Tests T6.09-T6.12 must pass.

**Step 5**: Add `host_fetch_cell` extern to `host.zig` and implement in `host-functions.ts` with an in-memory HashMap backend. Tests T6.09 through T6.12 require this.

**Step 6**: Implement `CellRegistry` in TypeScript with CAS (typeHash) + location (OctaveAddress) dual addressing. Implement `storeWithEscalation`. Tests T6.15-T6.19 must pass.

**Step 7**: Add MFP cost calculation: `cost = 1000^octave` sats per cell read. Test T6.20 must pass.

**Step 8**: Run ALL existing Phase 0-5 tests. Zero regressions allowed.

### Critical constraints

- Pointer cells are always RELEVANT linearity — they can be copied and dropped freely. The referenced content keeps its own linearity from its header.
- Do NOT auto-dereference nested pointers. Each level requires explicit `OP_DEREF_POINTER`.
- Do NOT change the existing 1024-byte cell format or the 256-byte header layout.
- Do NOT implement disk-backed storage. In-memory HashMap only for this phase.
- Do NOT adjust tests to match broken output. Fix the code.
- WASM binary must remain under 50KB after this phase.

### The Forth reference pattern you are generalising

From `coordinators-proven.fs`:
```forth
: BYTES>CELLS ( bytes -- cells )
  1024 + 1023 - 1024 / ;
```

This formula scales naturally across octaves. At Octave 0, cell size is 1024. At Octave 1, cell size is 1,048,576. The formula stays the same — only the divisor changes:

```
bytesToCellsAtOctave(bytes, octave) = (bytes + cellSize - 1) / cellSize
where cellSize = 1024 << (octave * 10)
```

From `coordinators-flexible.fs`:
```forth
: CHOOSE-STORAGE-STRATEGY ( data-size -- inline? )
  768 < ;
```

This threshold-based escalation pattern extends to octaves: if data exceeds what Octave N can address, escalate to Octave N+1 and leave a pointer cell at Octave N.

### Registry as cell slots

The mental model is a registry with cell slots:

```
Slot 0x0001  →  [cell: trades.job.plumbing.hire        ]  Octave 0
Slot 0x0002  →  [cell: library.book.isbn.9780140449136 ]  Octave 0
Slot 0x0003  →  [cell: POINTER → Octave 1, slot 0x0001 ]  (large BREM assessment)
Slot 0x0004  →  [cell: asset.tool.makita.angle-grinder ]  Octave 0
Slot 0x0005  →  [cell: agent.reasoning.step.extraction ]  Octave 0
```

All the same shape. All stackable. All routable. All verifiable with the same engine. The pointer cell is just another 1KB cell — its payload happens to be an address at a higher octave rather than inline data.

### Forth patterns you are porting (read the PRD's Forth → Zig Pattern Mapping table)

The PRD contains a detailed table mapping every Forth pattern to its Zig equivalent. The most critical translations:

- **`BYTES>CELLS`** → `bytesToCellsAtOctave` — same formula, parameterised by octave cell size
- **`CREATE-CELL-COORDINATOR`** → `OctaveRegistry.allocForSize()` — compute cells needed, allocate at correct octave
- **`COORD-STORE-2`** → `PointerPayload` struct fields — two values (address + metadata) in object data area
- **`CHOOSE-STORAGE-STRATEGY`** → `storeWithEscalation` thresholds — ≤768B inline, ≤1MB continuation, >1MB octave pointer
- **Pool-per-linearity** → `SlotMeta.linearity` — each octave slot tracks its content's linearity class
- **`POOL-FREE/ALLOCATED/CONSUMED`** → `SlotState` enum — identical state machine, identical values (0, 1, 2)
- **`CONSUME-LINEAR` with double-consumption ABORT** → octave pool `readSlot` must check consumed state
- **`COLLECT-RELEVANT-GARBAGE`** → not in Phase 6 scope, but `SlotMeta.ref_count` must support future GC

### Done criteria

All 20 TDD gate tests pass. WASM binary < 50KB. Zero regressions on Phase 0-5 tests. Both TS and Zig pointer cell packers produce identical bytes.
