---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-6-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.689583+00:00
---

# Phase 6 Errata — Issues to Fix Before Phase 7

Audit of the Phase 6 Octave Memory Scaling implementation. Each item is categorised as **BUG** (wrong behaviour), **INCONSISTENCY** (mismatches between docs/code/tests), **DEAD CODE** (stuff that exists but isn't exercised), or **TECH DEBT** (not broken but will bite you in Phase 7).

---

## BUG-1: PRD says 89-byte payload, implementation uses 90 bytes

**Location**: `docs/prd/PHASE-6-OCTAVE-MEMORY.md` line 100 vs `src/pointer.zig` line 25

The PRD's wire format section says `payloadSize: actual data bytes (fixed: 89)` and `[89-byte pointer payload]` with `[927-byte padding]`. But the actual `PointerPayload` struct adds up to 90 bytes (1+8+32+32+8+1+2+6=90), the code correctly uses `POINTER_PAYLOAD_SIZE: u16 = 90`, and the padding test checks bytes 98..1023 (which is 926 bytes of zero padding: 1024 - 8 - 90 = 926).

**The code is correct, the PRD is wrong.** Fix the PRD: `89` → `90`, `927` → `926`.

---

## BUG-2: `getOctaveAddress` packs slot+offset into `cell_address` with an undocumented encoding

**Location**: `src/pointer.zig` lines 121-128

```zig
pub fn getOctaveAddress(cell: *const [constants.CELL_SIZE]u8) UnpackError!octave_mod.OctaveAddress {
    const payload = try unpackPointerCell(cell);
    return .{
        .octave = @enumFromInt(payload.octave),
        .slot = @intCast(payload.cell_address & 0xFFFF),
        .offset = @intCast((payload.cell_address >> 16) & 0xFFFFFFFF),
    };
}
```

The `cell_address` field is a `u64`. This function interprets it as `[slot:16][offset:32][unused:16]`. But there's no corresponding `makeOctaveAddress → cell_address` packer. If someone stores `cell_address = 42` (as the round-trip test does), they get `slot=42, offset=0` — which happens to work for the simple case but is a latent trap. The encoding is never documented and there's no inverse function.

**Fix**: Either document the encoding explicitly and add a `fn octaveAddressToCellAddress(addr: OctaveAddress) u64` helper, or change `PointerPayload` to store `slot: u16` and `offset: u32` as separate fields instead of packing them into `cell_address`. The second option is cleaner because the TS side will need to match this encoding exactly in Phase 7.

---

## BUG-3: `OctaveAddress.toU64`/`fromU64` encoding differs from `getOctaveAddress` encoding

**Location**: `src/octave.zig` lines 36-49 vs `src/pointer.zig` lines 121-128

`OctaveAddress.toU64()` packs as `[octave:8][slot:16][offset:32][reserved:8]` — octave in the MSB.
`getOctaveAddress()` extracts from `cell_address` as `[slot:16][offset:32]` — no octave (it's in a separate field).

These are two different encodings of the same logical thing. The `toU64`/`fromU64` is tested in the conformance tests and works, but it's never actually used by `opDerefPointer` — the opcode uses `getOctaveAddress` which reads the separate `octave` and `cell_address` fields. So `toU64`/`fromU64` is dead code in the hot path.

**Fix**: Decide which encoding is canonical. If `PointerPayload` keeps `octave` and `cell_address` as separate fields (which makes sense for wire format), then `toU64`/`fromU64` should be documented as "transport format for host function calls" and the mismatch acknowledged. Or remove `toU64`/`fromU64` entirely if they're not needed.

---

## BUG-4: `opDerefPointer` is NOT failure-atomic

**Location**: `src/opcodes/plexus.zig` lines 174-197

The other plexus check ops (0xC3-0xC7) were carefully hardened in the opcode hardening sprint to be failure-atomic: peek first, mutate last, stack unchanged on error. But `opDerefPointer` does `spop()` on line 176 *before* validating the pointer cell. If `isPointerCell` returns false on line 180, the stack has already lost the item.

Compare to `opCheckCapability` which peeks with `speekAt()` first and only pops after all checks pass.

**Fix**: Peek at the top cell with `speek()`, validate it's a pointer cell, extract the address, call `host_fetch_cell`, and only then `spop()` + `spush()`. This is the same pattern used throughout the rest of plexus.

---

## BUG-5: `host_fetch_cell` native stub always returns `false` — makes `OP_DEREF_POINTER` untestable in Zig native tests

**Location**: `src/host.zig` lines 226-228

```zig
pub fn fetchCell(oct: u8, slot: u32, offset: u32, out: [*]u8) bool {
    if (comptime is_wasm) {
        return host_fetch_cell(oct, slot, offset, out) != 0;
    }
    _ = .{ oct, slot, offset, out };
    return false;
}
```

This means T6.09-T6.12 (OP_DEREF_POINTER tests from the PRD TDD gate) cannot be tested in the Zig native test runner. The `octave_conformance.zig` test file has no tests for the opcode at all — it only tests address math, pointer pack/unpack, and cost calculation. The actual opcode is only testable through the WASM→TS host path.

This isn't necessarily a bug (it follows the `checksig` pattern where native embedded returns false), but it means **4 of the 12 Zig TDD gate tests (T6.09-T6.12) don't exist**. The completion log says "300/300 pass" but those 4 tests were never written.

**Fix**: Either accept this as a known limitation and document it, or add a compile-time-switchable test backend to `fetchCell` that allows native tests to inject data (like a `test_octave_store: ?*const std.AutoHashMap(...)` field).

---

## INCONSISTENCY-1: PRD says `tests/octave_test.zig`, code uses `tests/octave_conformance.zig`

**Location**: `docs/prd/PHASE-6-OCTAVE-MEMORY.md` line 253 vs `packages/cell-engine/tests/octave_conformance.zig`

The PRD TDD section says "Zig Tests (in `tests/octave_test.zig`)" but the actual file is `tests/octave_conformance.zig` (following the codebase naming convention). Minor, but the PRD should be updated to match.

---

## INCONSISTENCY-2: PRD `bytesToCellsAtOctave` return type is `u16`, code returns `u64`

**Location**: `docs/prd/PHASE-6-OCTAVE-MEMORY.md` D6.2 code sample vs `src/octave.zig` line 102

PRD shows `pub fn bytesToCellsAtOctave(bytes: u64, oct: Octave) u16` but the implementation returns `u64`. The `u64` return is correct — at octave 0, 1TB of data requires ~1 billion cells, which doesn't fit in `u16`. The PRD code sample is wrong.

---

## INCONSISTENCY-3: PRD host function signature doesn't match implementation

**Location**: `docs/prd/PHASE-6-OCTAVE-MEMORY.md` D6.5 vs actual code

PRD says:
```zig
extern "host" fn host_fetch_cell(octave: u8, address_lo: u32, address_hi: u32, out_ptr: [*]u8, out_len: u32) u32;
```

Actual code:
```zig
pub extern "host" fn host_fetch_cell(octave: u8, slot: u32, offset: u32, out_ptr: [*]u8) u32;
```

The implementation is cleaner (no split address, no redundant `out_len` since it's always 1024). The PRD should be updated.

---

## INCONSISTENCY-4: TS host function doesn't validate octave bounds

**Location**: `packages/cell-engine/bindings/host-functions.ts` line 177

The Zig side has `Octave = enum(u8) { base=0, kilo=1, mega=2, giga=3 }` — values 0-3 only. The TS `host_fetch_cell` accepts any `number` for octave and just uses it as a map key. No validation that `octave <= 3`.

**Fix**: Add `if (octave > 3) return 0;` at the top.

---

## DEAD CODE-1: `std` imported but unused in `octave.zig`

**Location**: `src/octave.zig` line 13

```zig
const std = @import("std");
```

No `std` functions are called anywhere in `octave.zig`. Remove the import.

---

## DEAD CODE-2: `SlotMeta` and `SlotState` are defined but never used anywhere

**Location**: `src/octave.zig` lines 58-84

These types are declared in the module and tested (`SlotMeta.init()` test), but nothing in the codebase uses them. `opDerefPointer` doesn't check slot state. The registry doesn't exist in Zig. They're premature scaffolding for future work.

**Decision**: Keep if Phase 7 bindings will use them (they're exposed in the module graph). Document as "scaffolding for Phase 7 octave pool management" in a comment.

---

## DEAD CODE-3: `minimumOctaveForSize` tested but never called by any production code

**Location**: `src/octave.zig` line 109

Similar to above — it's useful logic that will be needed by `storeWithEscalation` in Phase 7, but it's currently dead. Just note it.

---

## DEAD CODE-4: `writeContHeader` in `pointer.zig` duplicates `writeContinuationHeader` in `multicell.zig`

**Location**: `src/pointer.zig` lines 132-138 vs `src/multicell.zig` lines 57-63

Identical logic, different names. `pointer.zig` imports `multicell` but uses its own copy of the header writer. The original in `multicell.zig` is `fn writeContinuationHeader` (private). Options: make the multicell version `pub` and use it, or keep the duplication and note it.

**Fix**: Make `multicell.writeContinuationHeader` pub and use it from `pointer.zig`. Kill the duplicate.

---

## TECH DEBT-1: `octaveCellStore` is module-level mutable state

**Location**: `packages/cell-engine/bindings/host-functions.ts` line 197

```typescript
const octaveCellStore = new Map<string, Uint8Array>();
```

This is a module-scoped `Map` that persists across all test runs and WASM instantiations. `clearOctaveCells()` exists but nothing calls it between tests. If any test seeds octave data, it leaks into subsequent tests.

**Fix**: Either call `clearOctaveCells()` in a `beforeEach`/`afterEach` in the test harness, or make the store per-WASM-instance by passing it into `createHostFunctions`.

---

## TECH DEBT-2: `PointerFlags` defined but never validated

**Location**: `src/pointer.zig` lines 28-32

`PointerFlags.IMMUTABLE`, `ENCRYPTED`, `COMPRESSED` are defined as constants but no code ever reads or validates them. `packPointerCell` writes `payload.flags` verbatim and `unpackPointerCell` reads it back — no masking, no validation. Anyone can set arbitrary bits.

**Fix for Phase 7**: When the Bun bindings expose `createPointerCell`, validate that `flags & ~0x07 == 0` (only defined bits set).

---

## TECH DEBT-3: No WASM integration test for `OP_DEREF_POINTER` through the full host path

The Zig native tests cover address math and pointer packing. The TS tests check WASM instantiation. But there's no end-to-end test that:
1. Seeds a cell into `octaveCellStore`
2. Pushes a pointer cell onto the PDA stack via script
3. Executes `0xC8`
4. Verifies the fetched cell content on the stack

This is the actual smoke test for the whole Phase 6 feature.

**Fix**: Add a test in `tests-ts/` that does the above. This is the single most important missing test.

---

## TECH DEBT-4: PRD completion checklist is stale

**Location**: `docs/prd/PHASE-6-OCTAVE-MEMORY.md` Completion Criteria section

Several checklist items don't match the actual scope decision:
- "Zig and TS pointer cell packers produce bit-identical output" — TS packer deferred to Phase 7
- "In-memory CellRegistry with CAS + location dual addressing" — deferred to Phase 7
- "`storeWithEscalation` correctly routes objects to the right octave" — deferred to Phase 7
- "All 20 TDD gate tests pass" — only 11 exist (T6.01-T6.08, T6.20, plus extras)
- "Pointer cell wire format is 1024 bytes with 89-byte payload" — should say 90

**Fix**: Update the PRD to reflect what was actually done vs deferred.

---

## Summary: Priority Order

| # | Item | Severity | Effort |
|---|------|----------|--------|
| 1 | BUG-4: opDerefPointer not failure-atomic | **High** | 10 min |
| 2 | BUG-2/BUG-3: cell_address encoding undocumented + mismatched | **High** | 30 min |
| 3 | TECH DEBT-3: No WASM integration test for 0xC8 | **High** | 1 hr |
| 4 | BUG-5: T6.09-T6.12 never written | **Medium** | 30 min |
| 5 | DEAD CODE-4: Duplicate writeContHeader | **Low** | 5 min |
| 6 | INCONSISTENCY-4: TS octave bounds check | **Low** | 2 min |
| 7 | TECH DEBT-1: Module-level mutable octaveCellStore | **Low** | 15 min |
| 8 | PRD updates (BUG-1, INCONSISTENCY-1/2/3, TECH DEBT-4) | **Low** | 20 min |
| 9 | DEAD CODE-1: Unused std import | **Trivial** | 1 min |
