---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-2-BCA-DERIVATION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.679662+00:00
---

# Phase 2: BCA Derivation and Verification

**Duration**: 2 weeks (with 40% buffer: ~20 days)
**Prerequisites**: Phase 1 complete — cell packing produces bit-identical output, cross-language tests pass.
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` (in this directory: `semantos-core/docs/prd/`)

---

## Context

Bitcoin-Certified Addresses (BCAs) are IPv6 addresses cryptographically derived from BSV public keys. They allow any network node to verify that an IPv6 address belongs to a specific public key holder — in exactly 2 hash evaluations. This is the addressing layer that binds Semantos semantic objects to network-routable identities.

The BCA algorithm comes from the nChain paper "IPv6 Bitcoin-Certified Addresses" (Ducroux, 2023). This phase implements the algorithm in Zig, introduces the first WASM host function (`host_sha256`), and validates against independently computed test vectors.

**Why this matters for Semantos**: Every semantic object has an `ownerId` (16 bytes in the cell header). For network-addressed objects, this ownerId IS the BCA-derived IPv6 address. The derivation must be deterministic — same public key + same parameters → same address, every time, on every platform.

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `DOC:BCA-PAPER` | `(uploaded) 2311.15842v1.pdf` | **Primary reference.** Section IV: BCA Generation Algorithm. Table II: BCA Parameters (modifier 16B, public key 33B, subnet prefix 8B, collision count 1B). Section V: Verification (always 2 hash evaluations). Figure 3: BCA structure within IPv6 address. Key equations for Hash1 and interfaceIdentifier construction. |
| `CORE:WASM` | `semantos-core/src/cell-engine/wasm-interface.ts` | `PlexusKernelHostImports` interface — `host_sha256(dataPtr, dataLen, outPtr)`. This is the import contract the Zig WASM module uses. |
| `SDK:TS` | `ts-sdk/` | `@bsv/sdk` v1.6.12. `src/primitives/Hash.ts` — SHA256 implementation. `src/primitives/PublicKey.ts` — compressed public key handling (33 bytes). These are used to implement the host function on the TypeScript side. |

---

## BCA Algorithm Summary (from DOC:BCA-PAPER)

### Generation

```
Input:
  pubkey       — 33 bytes (compressed secp256k1 public key)
  subnetPrefix — 8 bytes (network-assigned IPv6 /64 prefix)
  modifier     — 16 bytes (application-specific modifier)
  sec          — security parameter (0, 1, or 2; default 0)

Steps:
  1. Concatenate: data = modifier || subnetPrefix || 0x00 || pubkey
     (collision count starts at 0x00)
  2. Hash1 = SHA256(data)
  3. interfaceIdentifier = Hash1[0..8]  (first 8 bytes)
  4. Set u-bit and g-bit in interfaceIdentifier per RFC 4291
  5. Encode sec parameter in reserved bits
  6. BCA = subnetPrefix || interfaceIdentifier  (16 bytes = 128 bits)

If collision detected (same BCA for different keys):
  Increment collision count (max 2), rehash from step 1
```

### Verification

```
Input:
  bca          — 16 bytes (the IPv6 address to verify)
  pubkey       — 33 bytes
  subnetPrefix — 8 bytes
  modifier     — 16 bytes

Steps:
  1. Extract interfaceIdentifier from bca[8..16]
  2. For collisionCount in [0, 1, 2]:
       data = modifier || subnetPrefix || collisionCount || pubkey
       Hash1 = SHA256(data)
       candidate = Hash1[0..8] with u/g bits set
       if candidate == interfaceIdentifier: return true
  3. return false

Always exactly 1-3 hash evaluations (worst case 3 with collision retry).
```

---

## Deliverables

### D2.1 — `bca.zig`

```zig
pub const BCAInput = struct {
    pubkey: [33]u8,          // Compressed secp256k1 public key
    subnet_prefix: [8]u8,    // IPv6 /64 prefix
    modifier: [16]u8,        // Application-specific modifier
    sec: u8,                 // Security parameter (0, 1, or 2)
};

pub const BCAOutput = struct {
    address: [16]u8,         // Full 128-bit IPv6 address
    collision_count: u8,     // How many collision retries were needed
};

pub fn deriveBCA(input: *const BCAInput) BCAError!BCAOutput;
pub fn verifyBCA(address: *const [16]u8, input: *const BCAInput) bool;
```

**Critical constraints**:
- SHA256 is performed via `host_sha256` (WASM import) — the Zig code does NOT include a SHA256 implementation for the WASM target. For native test builds, a Zig-native SHA256 from std lib is acceptable.
- Collision count maxes at `sec` parameter value (0=no retry, 1=one retry, 2=two retries)
- The u-bit (universal/local) and g-bit (individual/group) must be set correctly per RFC 4291 Section 2.5.1

### D2.2 — `host.zig` (first host function)

```zig
// WASM imports — provided by TypeScript host
extern "host" fn host_sha256(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;

// Zig-side wrapper with safety checks
pub fn sha256(data: []const u8, out: *[32]u8) void {
    host_sha256(data.ptr, @intCast(data.len), out);
}
```

For native test builds, provide a compile-time switch:
```zig
const sha256_impl = if (builtin.target.cpu_arch == .wasm32)
    host_sha256_wasm
else
    std.crypto.hash.sha2.Sha256.hash;
```

### D2.3 — `host-functions.ts` (TypeScript host implementation)

```typescript
import { Hash } from '../../../ts-sdk/src/primitives/Hash';

export function host_sha256(dataPtr: number, dataLen: number, outPtr: number, memory: WebAssembly.Memory): void {
    const data = new Uint8Array(memory.buffer, dataPtr, dataLen);
    const hash = Hash.sha256(Array.from(data));
    const out = new Uint8Array(memory.buffer, outPtr, 32);
    out.set(new Uint8Array(hash));
}
```

### D2.4 — Independent test vectors

Compute BCA test vectors using a SEPARATE implementation (e.g., Python + hashlib, or directly from @bsv/sdk Hash). Do NOT derive test vectors from your own Zig code.

```
tests/vectors/
├── bca_basic.json           # Known pubkey → known IPv6
├── bca_collision.json       # Inputs that trigger collision retry
├── bca_all_sec_params.json  # sec=0, sec=1, sec=2
└── bca_verify_false.json    # Wrong pubkey → verification fails
```

---

## TDD Gate — Tests That Must Pass

### Test 1: BCA derivation (Zig native)
```zig
// bca_conformance.zig
test "deriveBCA produces correct IPv6 for known pubkey" {
    // Use pre-computed test vector
    // deriveBCA(input) == expected_address
}

test "deriveBCA with collision retry produces correct result" { ... }
test "deriveBCA sec=0 never retries" { ... }
test "deriveBCA sec=2 retries up to 2 times" { ... }
test "u-bit and g-bit set correctly per RFC 4291" { ... }
test "deriveBCA is deterministic — same input always same output" { ... }
```

### Test 2: BCA verification (Zig native)
```zig
test "verifyBCA returns true for correctly derived address" { ... }
test "verifyBCA returns false for wrong public key" { ... }
test "verifyBCA returns false for wrong modifier" { ... }
test "verifyBCA returns false for wrong subnet prefix" { ... }
test "verifyBCA handles collision count correctly" { ... }
```

### Test 3: Host function integration (TypeScript)
```typescript
// bca_compat.test.ts
test("host_sha256 produces correct hash via @bsv/sdk", () => {
    // Known input → known SHA256 output
});

test("BCA derivation through WASM matches TypeScript derivation", () => {
    // Same pubkey+params → Zig WASM and TS produce identical IPv6
});

test("BCA round-trip: derive in Zig, verify in TS; derive in TS, verify in Zig", () => { ... });
```

### Test 4: Performance
```zig
test "BCA derivation completes in under 1ms" {
    // Time 1000 derivations, assert average < 1ms
}
```

---

## Phase Completion Criteria

You are **done with Phase 2** when ALL of the following are true:

1. `zig build test` passes all bca_conformance tests using native SHA256
2. WASM binary exports `deriveBCA` and `verifyBCA` functions
3. TypeScript `host_sha256` implementation works with @bsv/sdk Hash module
4. `bun test tests-ts/bca_compat.test.ts` passes — WASM BCA matches TS BCA
5. Test vectors were computed independently (not from the Zig implementation)
6. `verifyBCA` always completes in at most 3 hash evaluations
7. BCA derivation is deterministic across native and WASM targets
8. `host.zig` compiles for both native (std lib SHA256) and WASM (extern import) targets

## What NOT To Do

- Do not implement a full SHA256 in Zig for the WASM target — use host_sha256. A native SHA256 for test builds is fine.
- Do not implement ECDSA or signature operations — that's Phase 3+ (for OP_CHECKSIG)
- Do not implement BEEF/BUMP parsing — that's Phase 5
- Do not assume specific endianness without checking the BCA paper's byte order
- Do not skip the RFC 4291 u-bit/g-bit requirements — network stacks depend on these bits

---

## Errata (Post-Implementation)

### E-P2.1: deriveBCA always returns collision_count=0
The collision retry loop in `deriveBCA` exists structurally (`while cc <= input.sec`) but returns immediately on the first iteration (line 52) because there is no collision oracle. This means the `collision_count` output is always 0 regardless of sec. The sec parameter only affects the bit encoding in the interface identifier, not actual collision avoidance. **Impact**: None for the simplified algorithm. **Future work**: If on-chain collision detection is needed (full paper algorithm, Phase 5+), add an optional collision oracle callback to `deriveBCA`.

### E-P2.2: "collision" test vectors don't test collision retry
`bca_collision.json` contains 3 vectors with sec=2 and different modifiers, but all have `expectedCollisionCount: 0`. They test that different modifiers produce different addresses (useful for verify coverage), but they don't exercise the collision retry path because no actual collisions occur. The file name is misleading. **Impact**: Low — `verifyBCA` still loops through cc=0,1,2 which provides coverage of the verification loop.

### E-P2.3: build.zig module name "host.zig" includes file extension
The host module is registered as `"host.zig"` (with extension) in build.zig, while all other modules use bare names (`"constants"`, `"errors"`, `"cell"`, etc.). This works because `bca.zig` uses `@import("host.zig")` to match, and `main.zig` also uses `@import("host.zig")`. Internally consistent but inconsistent with the convention used by all other modules. **Fix (optional, Phase 3)**: Rename the module to `"host"` and update imports in bca.zig and main.zig to `@import("host")`.

### E-P2.4: verifyBCA ignores input.sec — extracts sec from the address
`verifyBCA` extracts the sec parameter from the address's interface identifier (3 MSBs of byte 8) rather than using `input.sec`. This is correct behavior — the verifier doesn't need to know what sec was used, it reads it from the address. But it means `BCAInput.sec` is unused during verification. The WASM export `bca_verify` in main.zig hardcodes `sec: 0` (line 295) which is fine but the comment should note that sec is ignored. **Impact**: None — functionally correct.

### E-P2.5: host.zig extern declarations compiled for all targets (RESOLVED)
All `extern "host"` declarations (lines 12-19) are at file scope, meaning they're compiled for both WASM and native targets. This works because the `sha256` wrapper uses a comptime-known `is_wasm` branch, and Zig eliminates the dead branch (including the extern call) at compile time. The linker never tries to resolve the externs for native builds. **Status**: Working correctly — no fix needed. Noted for awareness in case future code references externs directly outside the `sha256` wrapper.

---

## Open Questions for This Phase

| # | Question | Default |
|---|----------|---------|
| Q3 | Do we store BCA merkle proofs in continuation cells or rely on BEEF envelopes? | Default: BEEF envelopes (Phase 5). BCA cells only store the 16-byte address. |

---

## Next Phase

Phase 2 output feeds into **Phase 3: 2-PDA Core**, which implements the dual-stack pushdown automaton and standard Bitcoin Script opcodes.
