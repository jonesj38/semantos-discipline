---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-1-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.708406+00:00
---

# Phase 1 Prompt

Copy everything below the line into a fresh Claude Code session.

---

## Prompt Start

Read these two documents in full before producing any output:

1. `/Users/toddprice/projects/semantos-core/docs/prd/README.md`
2. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-1-CELL-PACKING.md`

### What already exists (Phase 0 output)

Phase 0 is complete and verified. Everything lives at `/Users/toddprice/projects/semantos-core/`:

```
semantos-core/
├── package.json                   # @semantos/core v0.3.0 + cell-engine scripts
├── src/                           # Existing TS core (types, kernel, metering)
├── dist/                          # Built TS output
├── docs/prd/                      # PRD and phase docs (you are here)
└── packages/
    ├── constants/
    │   ├── constants.json         # Single source of truth — all constants
    │   └── generate.ts            # Produces constants.zig + constants.ts
    ├── protocol-types/
    │   ├── package.json           # Bridge over @semantos/core (dep: "file:../../")
    │   └── src/index.ts           # Re-exports + CellHeader, BCA types, enums
    ├── __tests__/
    │   └── phase0-gate.test.ts    # 5 gate tests
    └── cell-engine/
        ├── build.zig              # 3 targets: freestanding, wasi, native test
        ├── src/
        │   ├── main.zig           # WASM entry — 10 exported stubs
        │   ├── constants.zig      # Generated from constants.json
        │   ├── cell.zig           # STUB — you are implementing this
        │   ├── bca.zig            # Stub (Phase 2)
        │   ├── pda.zig            # Stub (Phase 3)
        │   ├── linearity.zig      # Stub (Phase 3)
        │   ├── host.zig           # extern "host" declarations
        │   ├── errors.zig         # KernelError enum
        │   └── opcodes/           # Stubs (Phase 4)
        ├── tests/
        │   └── smoke_test.zig     # Constants validation
        └── bindings/
            ├── index.ts           # Stub loader
            └── host-functions.ts  # Stub
```

WASM binary is currently 319 bytes (stubs only, ReleaseSmall). All 32 Phase 0 tests pass.

### What you are building

Phase 1 implements cell packing — the core serialisation layer. Four deliverables:

- D1.1: `cell.zig` — `packCell`, `unpackCell`, magic validation, commerce/binding accessors
- D1.2: `commerce.zig` — CommerceExtension struct, read/write within reserved block
- D1.3: `multicell.zig` — `packMultiCell`, `unpackMultiCell`, continuation headers, LIFO ordering
- D1.4: Cross-language test vectors generated from the TypeScript packer

### Critical constraint: bit-identical output

The Zig packer MUST produce byte-for-byte identical output to the TypeScript packer for the same inputs. This is the single most important requirement. If one bit differs, the phase has failed.

To verify this:
1. Read `PACKER:TYPE-REGISTRY` (`/Users/toddprice/projects/semantos-core/src/cell-engine/typeHashRegistry.ts`) — this is the byte-level truth for header construction
2. Read `PACKER:MAIN` (`/Users/toddprice/projects/semantos-core/src/cell-engine/cellPacker.ts`) — this is the truth for multi-cell packing
3. Read `PACKER:MERKLE` (`/Users/toddprice/projects/semantos-core/src/cell-engine/merkleEnvelope.ts`) — dependency of cellPacker, merkle envelope serialization
3. Write a TypeScript script that calls the TS packer with known inputs and dumps the raw bytes to `.bin` files in `tests/vectors/`
4. Write Zig tests that pack the same inputs and compare output byte-for-byte against those `.bin` files
5. Write TypeScript tests that load Zig-packed output (via WASM) and verify the TS unpacker reads it correctly

### Errata from Phase 0 run (issues the Phase 1 agent must address)

**E-P1.1: Magic bytes are raw bytes, NOT little-endian u32s.**
The TypeScript packer writes `Buffer.from([0xde, 0xad, 0xbe, 0xef, ...])` and copies the bytes directly at offset 0. It does NOT use `setUint32(0, 0xDEADBEEF, true)`. If the Zig code writes magic as four `u32` values with `std.mem.writeIntLittle`, the byte order will be wrong (it would produce `0xef, 0xbe, 0xad, 0xde`). Write magic as a raw `[16]u8` array: `[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE, 0x13, 0x37, 0x13, 0x37, 0x42, 0x42, 0x42, 0x42 }`. Read `typeHashRegistry.ts` to confirm the exact byte sequence before writing any code.

**E-P1.2: Missing constants — on-chain binding offsets.**
`constants.json` does not yet include the on-chain binding offsets: TXID(32B@160), VOUT(4B@192), BUMP_HASH(24B@196), DERIVATION_INDEX(4B@220). These are needed for D1.1 (`getOnChainBinding`/`setOnChainBinding`). Add them to `constants.json` and re-run the generator before implementing cell.zig. Source: `FORTH:SEMOBJ-ENH` (`semantos-gift-pack/forth/semantic-objects-enhanced.fs`).

**E-P1.3: Naming ambiguity in constants.zig.**
`HEADER_SIZE_TOTAL` (value 90) is actually the byte offset of the `totalSize` field, not the total header size. The total header size is `HEADER_SIZE` (value 256). This naming will cause confusion. When reading constants.zig, verify each constant name against its meaning. The offset constants follow the pattern `HEADER_OFFSET_*` — check that `HEADER_SIZE_TOTAL` should actually be `HEADER_OFFSET_TOTAL_SIZE`.

**E-P1.4: errors.zig needs Phase 1 variants.**
Current `errors.zig` only has Phase 0 error codes. Add: `InvalidMagic`, `PayloadTooLarge`, `InvalidCellCount`, `InvalidContinuationHeader`. These are needed for `unpackCell` and `unpackMultiCell` error handling.

### Sequence

1. Read ALL 6 source files listed in the Phase 1 doc
2. Read the Phase 0 output: `constants.json`, `constants.zig`, `errors.zig` — understand what's already available
3. Fix E-P1.2 (add on-chain binding offsets to constants.json, re-run generator)
4. Fix E-P1.3 if naming is wrong (update constants.json, re-run generator)
5. Fix E-P1.4 (add error variants to errors.zig)
6. Write the test vector generator (TypeScript script that produces `.bin` files from the real TS packer)
7. Run the generator to produce test vectors — these are now your ground truth
8. Write RED Zig tests for single-cell packing (round-trip, exact offsets, magic validation, padding)
9. Implement `cell.zig` and `commerce.zig` (GREEN)
10. Write RED Zig tests for multi-cell packing (continuation header, cell ordering, round-trip)
11. Implement `multicell.zig` (GREEN)
12. Write RED cross-language tests (TypeScript) — Zig output vs TS output byte comparison
13. Wire up WASM exports in `main.zig` so the cross-language tests can call Zig via WASM
14. Run full test suite — all Zig conformance + cross-language byte identity must pass
15. Verify WASM binary size is still under 500KB with real packing logic

### What NOT to do

- Do NOT implement SHA256 or any crypto — type_hash is packed/unpacked as raw 32 bytes
- Do NOT implement 2-PDA stack operations — that's Phase 3
- Do NOT hardcode byte offsets — all offsets come from `constants.zig`
- Do NOT use GForth 8-byte cell-width offsets — use packed wire-format from `typeHashRegistry.ts`
- Do NOT fabricate test vectors — generate them from the real TypeScript packer
- Do NOT adjust tests to match wrong output — if Zig bytes don't match TS bytes, fix the Zig code
- Do NOT write magic bytes as little-endian u32 values — write them as raw bytes (see E-P1.1)

### Byte order

Little-endian for all multi-byte integer fields (linearity, version, flags, refCount, cellCount, totalSize, etc.). This matches TypeScript `DataView` with `true` (little-endian). But magic bytes are raw — NOT endian-converted. Read `typeHashRegistry.ts` line by line to confirm which fields use `setUint32(offset, value, true)` vs `Buffer.copy()`.

### Done criteria

All 8 Phase Completion Criteria from the Phase 1 doc must be true. The most important one: criterion 4 — Zig-packed bytes are bit-identical to TypeScript-packed bytes for the same inputs. If that fails, nothing else matters.
