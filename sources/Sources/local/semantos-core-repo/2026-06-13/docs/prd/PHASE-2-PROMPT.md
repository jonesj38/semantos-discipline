---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-2-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.716349+00:00
---

# Phase 2 Prompt

Copy everything below the line into a fresh Claude Code session.

---

## Prompt Start

Read these two documents in full before producing any output:

1. `/Users/toddprice/projects/semantos-core/docs/prd/README.md`
2. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-2-BCA-DERIVATION.md`

Also read the Phase 1 errata (end of PHASE-1-CELL-PACKING.md) — E-P1.5 and E-P1.6 are informational for you (multi-cell WASM exports not yet wired).

### What already exists (Phase 0 + Phase 1 output)

Phases 0 and 1 are complete and verified. Everything lives at `/Users/toddprice/projects/semantos-core/`:

```
semantos-core/
├── package.json                   # @semantos/core v0.3.0
├── src/
│   └── kernel/
│       ├── typeHashRegistry.ts    # Canonical wire-format header builder
│       ├── cellPacker.ts          # Multi-cell packer (TS reference)
│       ├── merkleEnvelope.ts      # Merkle envelope serialization
│       ├── wasm-interface.ts      # PlexusKernelHostImports — host function contract
│       └── index.ts               # Barrel exports
├── docs/prd/                      # PRD and phase docs
└── packages/
    ├── constants/
    │   ├── constants.json         # Single source of truth
    │   └── generate.ts            # Produces constants.zig + constants.ts
    ├── protocol-types/
    │   ├── package.json
    │   └── src/index.ts           # Re-exports + CellHeader, BCA types
    ├── __tests__/
    │   └── phase0-gate.test.ts    # Phase 0 gate tests
    └── cell-engine/
        ├── build.zig              # 3 targets: freestanding, wasi, native test
        ├── zig-out/bin/
        │   ├── cell-engine.wasm   # 1.3KB — real cell packing logic
        │   └── cell-engine-wasi.wasm
        ├── src/
        │   ├── main.zig           # WASM exports: cell_pack, cell_unpack, cell_validate_magic + Phase 0 stubs
        │   ├── constants.zig      # Generated — all offsets, ranges, linearity, phases
        │   ├── cell.zig           # DONE — packCell, unpackCell, magic validation, commerce/binding
        │   ├── commerce.zig       # DONE — CommerceExtension + OnChainBinding read/write
        │   ├── multicell.zig      # DONE — packMultiCell, unpackMultiCell, continuation headers
        │   ├── errors.zig         # KernelError enum with Phase 0 + Phase 1 codes (0-13, 255)
        │   ├── bca.zig            # STUB — you are implementing this
        │   ├── host.zig           # extern "host" declarations (sha256, hash160, hash256, checksig, etc.)
        │   ├── pda.zig            # Stub (Phase 3)
        │   ├── linearity.zig      # Stub (Phase 3)
        │   └── opcodes/           # Stubs (Phase 3-4)
        ├── tests/
        │   ├── smoke_test.zig             # Phase 0 constants
        │   ├── cell_conformance.zig       # Phase 1 — pack/unpack + byte-identity
        │   ├── commerce_conformance.zig   # Phase 1 — extension + binding
        │   ├── multicell_conformance.zig  # Phase 1 — multi-cell validation
        │   ├── generate-vectors.ts        # Deterministic vector generator
        │   └── vectors/                   # .bin files + vectors.json
        ├── tests-ts/
        │   └── compat.test.ts             # Cross-language byte-identity tests
        ├── __tests__/
        │   └── wasm-build.test.ts         # Build + size + export validation
        └── bindings/
            ├── index.ts           # Stub loader
            └── host-functions.ts  # Stub — host_sha256 throws NOT_IMPLEMENTED
```

WASM binary is 1.3KB with real cell packing. All Phase 1 conformance tests and cross-language byte-identity tests pass.

### What you are building

Phase 2 introduces the first real host function (`host_sha256`) and implements Bitcoin-Certified Address (BCA) derivation. Four deliverables:

- D2.1: `bca.zig` — `deriveBCA`, `verifyBCA` implementing the nChain BCA algorithm (IPv6 from BSV pubkey)
- D2.2: `host.zig` update — compile-time switch: WASM uses `extern "host" host_sha256`, native tests use `std.crypto.hash.sha2.Sha256`
- D2.3: `host-functions.ts` update — real `host_sha256` implementation using `@bsv/sdk` Hash module
- D2.4: Independent test vectors — computed from a separate implementation (NOT from your Zig code)

### The BCA algorithm (from the nChain paper)

The BCA paper is at `/Users/toddprice/uploads/2311.15842v1 (1).pdf`. READ IT before writing any code. The core algorithm:

**Generation:**
1. Concatenate: `data = modifier(16B) || subnetPrefix(8B) || collisionCount(1B) || pubkey(33B)`
2. `Hash1 = SHA256(data)` — 58 bytes in, 32 bytes out
3. `interfaceIdentifier = Hash1[0..8]` — first 8 bytes
4. Set u-bit (bit 6 of byte 0) and g-bit (bit 7 of byte 0) per RFC 4291
5. Encode `sec` parameter in reserved bits
6. `BCA = subnetPrefix || interfaceIdentifier` — 16 bytes (128-bit IPv6)

**Verification (always ≤3 hash evaluations):**
1. For `collisionCount` in [0, 1, 2]: recompute and compare interfaceIdentifier
2. If any match: verified. Otherwise: reject.

### Critical constraint: host function architecture

The Zig WASM binary must NOT contain a SHA256 implementation. SHA256 is provided by the TypeScript host via `host_sha256(dataPtr, dataLen, outPtr)`. This keeps the WASM binary small and uses @bsv/sdk as the single source of truth for crypto.

For native Zig test builds (not WASM), use `std.crypto.hash.sha2.Sha256` from the Zig standard library. The compile-time switch:

```zig
const builtin = @import("builtin");
const is_wasm = builtin.cpu_arch == .wasm32;

pub fn sha256(data: []const u8, out: *[32]u8) void {
    if (is_wasm) {
        // WASM: call host import
        host_sha256(data.ptr, @intCast(data.len), out);
    } else {
        // Native: use std lib
        std.crypto.hash.sha2.Sha256.hash(data, out, .{});
    }
}
```

### What already exists in host.zig

`host.zig` already declares:
```zig
pub extern "host" fn host_sha256(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;
```

This matches `PlexusKernelHostImports` in `wasm-interface.ts`. Do NOT change the extern signature.

### What already exists in host-functions.ts

`bindings/host-functions.ts` currently throws `NOT_IMPLEMENTED` for all functions. You need to implement `host_sha256` using `@bsv/sdk`:

```typescript
import { Hash } from '@bsv/sdk';

export function createHostFunctions(memory: WebAssembly.Memory): WebAssembly.Imports {
  return {
    host: {
      host_sha256: (dataPtr: number, dataLen: number, outPtr: number) => {
        const data = new Uint8Array(memory.buffer, dataPtr, dataLen);
        const hash = Hash.sha256(Array.from(data));
        new Uint8Array(memory.buffer, outPtr, 32).set(new Uint8Array(hash));
      },
      // ... other stubs remain NOT_IMPLEMENTED
    }
  };
}
```

Check what `@bsv/sdk` exports for Hash — the import path and API may differ. Read the sdk to confirm.

### Test vector generation

Generate BCA test vectors INDEPENDENTLY — do NOT derive them from your Zig code. Two approaches:

1. **Python + hashlib**: Write a small Python script that implements the BCA algorithm using hashlib.sha256 and produces known pubkey → IPv6 mappings
2. **TypeScript + @bsv/sdk**: Use Hash.sha256 directly in a standalone script

Store vectors in `tests/vectors/`:
```
tests/vectors/
├── bca_basic.json             # Known pubkey → known IPv6 (sec=0)
├── bca_collision.json         # Inputs that trigger collision retry
├── bca_all_sec_params.json    # sec=0, sec=1, sec=2 with same pubkey
└── bca_verify_false.json      # Wrong pubkey → verification fails
```

Each vector entry should include: pubkey (hex), subnetPrefix (hex), modifier (hex), sec, expectedAddress (hex), expectedCollisionCount.

### Errata from Phase 1 (informational)

**E-P1.5: Multi-cell WASM exports not wired.** `multicell.zig` exists but `main.zig` doesn't export multi-cell functions. Not your problem for Phase 2, but be aware when wiring BCA exports that the pattern for WASM export → linear memory pointer interfaces is established in `main.zig` (see `cell_pack` and `cell_unpack`).

**E-P1.6: Cross-language multi-cell byte-identity test incomplete.** Also not your problem, but the cross-language test pattern in `tests-ts/compat.test.ts` is the template for your BCA cross-language tests.

### Sequence

1. Read the BCA paper (`/Users/toddprice/uploads/2311.15842v1 (1).pdf`) — extract the exact algorithm from Section IV
2. Read `host.zig` — understand the existing extern declarations
3. Read `wasm-interface.ts` — confirm the host import contract
4. Read `main.zig` — understand the WASM export pattern (callconv(.c), linear memory pointers)
5. Read `@bsv/sdk` Hash module — find the correct import path and API for SHA256
6. Write the independent test vector generator (Python or standalone TS) — produce `.json` vectors
7. Run the generator — these vectors are now your ground truth
8. Update `host.zig` with the compile-time SHA256 switch (WASM vs native)
9. Write RED Zig tests for BCA derivation (`bca_conformance.zig`) using embedded test vectors
10. Implement `bca.zig` — `deriveBCA` and `verifyBCA` (GREEN)
11. Wire WASM exports in `main.zig`: `bca_derive(pubkey_ptr, prefix_ptr, modifier_ptr, sec, out_ptr) → i32` and `bca_verify(addr_ptr, pubkey_ptr, prefix_ptr, modifier_ptr) → i32`
12. Update `host-functions.ts` — implement real `host_sha256` with `@bsv/sdk`
13. Write RED cross-language tests (`bca_compat.test.ts`) — WASM BCA output matches independently-generated vectors
14. Run full test suite — all Phase 0 + Phase 1 + Phase 2 tests must pass
15. Verify WASM binary size is still under 20KB

### What NOT to do

- Do NOT implement a SHA256 in Zig for the WASM target — use host_sha256
- Do NOT implement ECDSA, signature operations, or OP_CHECKSIG — that's Phase 3
- Do NOT implement BEEF/BUMP parsing — that's Phase 5
- Do NOT skip the RFC 4291 u-bit/g-bit requirements — network stacks need these bits correct
- Do NOT derive test vectors from your own Zig code — use an independent implementation
- Do NOT adjust tests to match wrong output — fix the code
- Do NOT break Phase 1 tests — cell packing must still work after your changes
- Do NOT change the extern declarations in host.zig — they match the WASM import contract

### RFC 4291 bit requirements

The interfaceIdentifier (8 bytes) derived from SHA256 needs two bits set per RFC 4291 Section 2.5.1:
- **u-bit** (bit 6 of first byte, counting from LSB): set to 0 for universal scope
- **g-bit** (bit 7 of first byte, counting from LSB): set to 0 for individual address

Read the BCA paper for the exact bit manipulation. The paper may override standard RFC 4291 conventions for BCA-specific purposes — the paper is authoritative.

### WASM export signatures

Follow the pattern established by `cell_pack`/`cell_unpack` in `main.zig`:

```zig
// BCA exports
export fn bca_derive(
    pubkey_ptr: [*]const u8,    // 33 bytes
    prefix_ptr: [*]const u8,    // 8 bytes
    modifier_ptr: [*]const u8,  // 16 bytes
    sec: u8,
    out_ptr: [*]u8,             // 16 bytes output
) callconv(.c) i32;            // returns collision_count or negative error

export fn bca_verify(
    addr_ptr: [*]const u8,      // 16 bytes
    pubkey_ptr: [*]const u8,    // 33 bytes
    prefix_ptr: [*]const u8,    // 8 bytes
    modifier_ptr: [*]const u8,  // 16 bytes
) callconv(.c) i32;            // returns 1 (verified) or 0 (rejected)
```

### Done criteria

All 8 Phase Completion Criteria from the Phase 2 doc must be true. The most important ones:
- Criterion 4: WASM BCA output matches TypeScript BCA output (independently computed)
- Criterion 7: BCA derivation is deterministic across native and WASM targets
- Criterion 8: `host.zig` compiles for both native and WASM without code changes
