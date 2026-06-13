---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-5-BEEF-BUMP-CAPABILITY.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.707022+00:00
---

# Phase 5: BEEF/BUMP Host Function Integration and Capability Token Verification

**Duration**: 2 weeks (with 40% buffer: ~20 days)
**Prerequisites**: Phase 4 complete — Plexus opcodes working, linearity enforcement passing, 2-PDA fully operational.
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` (in this directory: `semantos-core/docs/prd/`)

---

## Context

This phase bridges the Zig WASM engine to BSV's transaction layer. The cell engine needs to verify that cells are genuinely anchored on the BSV blockchain (via BEEF envelopes and BUMP merkle proofs) and that capability tokens (BRC-108) are valid (by evaluating their locking scripts through the 2-PDA).

The Zig layer does NOT parse BEEF or BUMP directly — it calls host functions that delegate to `@bsv/sdk` on the TypeScript side. This keeps the BSV SDK as the single source of truth for transaction format parsing, and keeps the WASM binary small.

**Why this matters**: Without SPV verification, anyone could claim a cell is "on chain" by providing fake transaction data. BEEF/BUMP proofs make cell anchoring independently verifiable without a full node.

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `SDK:TS` | `ts-sdk/` | `src/transaction/Beef.ts` — BEEF (BRC-95) parser/builder. `src/transaction/MerklePath.ts` — BUMP (BRC-74) merkle proof verification. `src/primitives/Hash.ts` — SHA256, HASH160, HASH256. |
| `FMT:BEEF` | `bitcoin-script/formats/beef.fs` | Forth BEEF parser reference. BRC-95 format structure. |
| `FMT:BUMP` | `bitcoin-script/formats/bump.fs` | Forth BUMP reference. BRC-74 merkle proof structure. |
| `CORE:CAPABILITY` | `semantos-core/src/types/capability.ts` | CapabilityToken (extends LinearObject). 6 types: RECOVERY, PERMISSION, DATA_ACCESS, COMPUTE_DELEGATION, METERED_ACCESS, TRANSFER. CapabilityConstraints: expiresAt, geoBounds, maxInvocations, requiredDomainFlags. |
| `CORE:WASM` | `semantos-core/src/cell-engine/wasm-interface.ts` | Full PlexusKernelHostImports: host_sha256, host_hash160, host_hash256, host_checksig, host_checkmultisig, host_get_blocktime, host_get_sequence, host_log. |
| `PACKER:MAIN` | `oddjobtodd/src/lib/semantos-kernel/cellPacker.ts` | Multi-cell layout: Cell 1 = BUMP, Cell 2 = Atomic BEEF. `createBumpCells()`, `createAtomicBeefCells()`. |
| `KERNEL:MERKLE` | `oddjobtodd/src/lib/semantos-kernel/merkleEnvelope.ts` | **Reference for ENVELOPE cell content.** `buildMerkleTree()` (double-SHA256), `computeMerkleRoot()`, `generateMerkleProof()`, `verifyMerkleProof()`, `serializeMerkleEnvelope()` → `[version(1B)][leafCount(4B)][root(32B)][proofCount(4B)][proofs...]`. Cell 3 (ENVELOPE type) content is serialized merkle envelopes from this module. |
| `CASHLANES:BEEF` | `cashlanes/src/spv/BEEFPackageBuilder.ts` | Production BEEF package construction pattern. |
| `CASHLANES:SPV` | `cashlanes/src/spv/TransactionAncestryResolver.ts` | BEEF proof handling for SPV verification. |

---

## Deliverables

### D5.1 — Complete `host-functions.ts`

Implement ALL host functions from `PlexusKernelHostImports`:

```typescript
import { Hash } from '../../../ts-sdk/src/primitives/Hash';
import { Beef } from '../../../ts-sdk/src/transaction/Beef';
import { MerklePath } from '../../../ts-sdk/src/transaction/MerklePath';
import { PublicKey } from '../../../ts-sdk/src/primitives/PublicKey';
import { Signature } from '../../../ts-sdk/src/primitives/Signature';

export interface HostFunctionSet {
    host_sha256(dataPtr: number, dataLen: number, outPtr: number): void;
    host_hash160(dataPtr: number, dataLen: number, outPtr: number): void;
    host_hash256(dataPtr: number, dataLen: number, outPtr: number): void;
    host_checksig(
        pubkeyPtr: number, pubkeyLen: number,
        msgPtr: number, msgLen: number,
        sigPtr: number, sigLen: number
    ): number;  // 1 = valid, 0 = invalid
    host_checkmultisig(
        pubkeysPtr: number, pubkeysCount: number,
        sigsPtr: number, sigsCount: number,
        msgPtr: number, msgLen: number,
        threshold: number
    ): number;
    host_get_blocktime(): number;
    host_get_sequence(): number;
    host_log(msgPtr: number, msgLen: number): void;
}

export function createHostFunctions(memory: WebAssembly.Memory, context: ScriptContext): HostFunctionSet;
```

**Critical**: All functions read from / write to WASM linear memory via pointer arithmetic. Bounds checking is mandatory — a bad pointer from Zig must not crash the TypeScript host.

### D5.2 — Complete `host.zig`

Full host function extern declarations matching all `PlexusKernelHostImports`:

```zig
extern "host" fn host_sha256(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;
extern "host" fn host_hash160(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;
extern "host" fn host_hash256(data_ptr: [*]const u8, data_len: u32, out_ptr: [*]u8) void;
extern "host" fn host_checksig(
    pubkey_ptr: [*]const u8, pubkey_len: u32,
    msg_ptr: [*]const u8, msg_len: u32,
    sig_ptr: [*]const u8, sig_len: u32,
) i32;
extern "host" fn host_checkmultisig(
    pubkeys_ptr: [*]const u8, pubkeys_count: u32,
    sigs_ptr: [*]const u8, sigs_count: u32,
    msg_ptr: [*]const u8, msg_len: u32,
    threshold: u32,
) i32;
extern "host" fn host_get_blocktime() i32;
extern "host" fn host_get_sequence() i32;
extern "host" fn host_log(msg_ptr: [*]const u8, msg_len: u32) void;
```

### D5.3 — BEEF/BUMP verification via host functions

Add WASM exports for SPV verification:

```zig
/// Verify a BEEF envelope contains valid merkle proof for a transaction
export fn verifyBEEF(beef_ptr: [*]const u8, beef_len: u32, txid_ptr: [*]const u8) callconv(.C) i32;

/// Verify a BUMP merkle proof for a specific txid against a block header
export fn verifyBUMP(proof_ptr: [*]const u8, proof_len: u32, txid_ptr: [*]const u8) callconv(.C) i32;
```

These delegate to new host function imports:
```zig
extern "host" fn host_parseBEEF(raw_ptr: [*]const u8, raw_len: u32) i32;   // returns struct ptr or -1
extern "host" fn host_verifyBUMP(proof_ptr: [*]const u8, proof_len: u32, header_ptr: [*]const u8, header_len: u32) i32;  // 1=valid, 0=invalid
```

### D5.4 — Capability token verification

```zig
/// Evaluate a BRC-108 capability token's locking script
/// Returns: 0 = valid, negative = specific error code
pub fn verifyCapabilityToken(
    locking_script: []const u8,
    owner_pubkey: [33]u8,
    domain_flags: u32,
    current_time: i32,
) CapabilityError!bool {
    var pda = PDA.init(constants.MAX_CAPABILITY_OPS);

    // Push context onto stack
    // ... push pubkey, domain flags, timestamp

    // Execute the locking script through the 2-PDA
    const result = try executor.execute(&pda, locking_script);

    return result;
}
```

---

## TDD Gate — Tests That Must Pass

### Test 1: Host function correctness (TypeScript)
```typescript
// host_functions.test.ts
test("host_sha256 matches @bsv/sdk Hash.sha256", () => { ... });
test("host_hash160 matches SHA256 + RIPEMD160", () => { ... });
test("host_hash256 matches double SHA256", () => { ... });
test("host_checksig validates known good signature", () => { ... });
test("host_checksig rejects known bad signature", () => { ... });
test("host_checkmultisig with 2-of-3 threshold", () => { ... });
test("host_get_blocktime returns injected context value", () => { ... });
test("host_log writes to console without crashing", () => { ... });
```

### Test 2: WASM boundary safety (TypeScript)
```typescript
test("invalid pointer to host_sha256 does not crash host", () => { ... });
test("zero-length data to host_sha256 produces valid hash", () => { ... });
test("oversized pointer is bounds-checked", () => { ... });
```

### Test 3: BEEF/BUMP verification (TypeScript integration)
```typescript
// spv_integration.test.ts
test("verifyBEEF with real BSV testnet BEEF envelope", () => {
    // Use a pre-captured BEEF envelope from a real testnet transaction
    // NOT a mock — a real envelope stored as a test fixture
});

test("verifyBUMP with real merkle proof", () => { ... });
test("verifyBEEF rejects tampered envelope", () => { ... });
test("verifyBUMP rejects wrong txid", () => { ... });
```

### Test 4: Capability token verification (Zig + TypeScript)
```zig
// capability_conformance.zig
test "simple P2PKH capability token verifies" { ... }
test "expired capability token fails" { ... }
test "wrong domain flag fails OP_CHECKDOMAINFLAG" { ... }
test "capability with maxInvocations=0 fails" { ... }
```

```typescript
// capability_compat.test.ts
test("capability token verification matches semantos-core validator", () => {
    // Same token, same context → Zig and semantos-core agree
});
```

### Test 5: Full SPV pipeline (TypeScript integration)
```typescript
test("pack cell → anchor tx → BEEF envelope → verify via WASM", () => {
    // End-to-end: create cell, embed in BSV transaction,
    // get BEEF proof, verify through Zig WASM engine
    // Skip if BSV_TESTNET_KEY not set (with clear message, not faked)
});
```

---

## Phase Completion Criteria

You are **done with Phase 5** when ALL of the following are true:

1. All `PlexusKernelHostImports` functions implemented in `host-functions.ts`
2. All host function externs declared in `host.zig`
3. `bun test tests-ts/host_functions.test.ts` passes — every host function produces correct output
4. WASM boundary is safe — bad pointers from Zig don't crash TypeScript
5. BEEF/BUMP verification works with real BSV testnet fixtures (not mocked)
6. Capability token locking scripts evaluate through the 2-PDA with Plexus opcodes
7. SPV pipeline test passes end-to-end (if testnet key available)
8. All Phase 3 and Phase 4 tests still pass (no regressions)

## What NOT To Do

- Do not implement BEEF parsing in Zig — delegate to @bsv/sdk via host functions
- Do not implement RIPEMD160 in Zig — host_hash160 handles it
- Do not implement ECDSA in Zig — host_checksig handles it
- Do not use mock BEEF envelopes — use real ones captured from BSV testnet
- Do not skip bounds checking on WASM memory pointers in host functions
- Do not make testnet tests fail silently if key is missing — print a clear skip message

---

## Next Phase

Phase 5 output feeds into **Phase 6: TypeScript Bindings and Bun Integration**, which wraps the WASM binary in a typed TypeScript API.
