---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30D-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.703578+00:00
---

# Phase 30D Execution Prompt — Anchor FFI Functions

> Paste this prompt into a fresh session to execute Phase 30D.

## Context

Phases 30A-C established the core FFI foundation: headers, adapter callbacks, capability-based access control, and linear resource consumption. Your task: expose anchor batch and verify functions through the FFI — the last core C ABI functions before platform packaging (phases 30E/F/G).

Anchoring proves that state existed at a specific time and block height on the BSV blockchain. By the end of Phase 30D, the kernel will expose both submission (batch-anchor) and verification (offline SPV) to the host via FFI.

After Phase 30D, phases 30E (Swift packaging), 30F (Dart packaging), and 30G (JavaScript packaging) can run **IN PARALLEL**.

---

## CRITICAL: READ THESE FILES FIRST

1. `docs/prd/PHASE-30D-ANCHOR-FFI.md` — Your deliverables and acceptance tests
2. `docs/prd/PHASE-30C-CAPABILITY-FFI.md` — FFI pattern, callback wiring methodology
3. `docs/prd/PHASE-30-FFI-MASTER.md` — Anchor functions table, error codes, linearity model
4. `docs/prd/PHASE-26C-ANCHOR-ADAPTER.md` — AnchorAdapter interface, BsvAnchorAdapter, StubAnchorAdapter
5. `packages/protocol-types/src/anchor.ts` — AnchorProof type definition, anchor interface
6. `docs/BRANCHING-AND-CI-POLICY.md` — Commit naming, branch rules

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

1. **NO STUBS**: Every function must have real implementation. Mock callbacks in tests are OK; fake function bodies are not.
2. **VERIFICATION IS OFFLINE**: `semantos_anchor_verify()` NEVER calls callbacks or network. It's pure local computation: SPV validation of merkle paths and block headers. If your implementation makes network calls, it's wrong.
3. **PROOF FORMAT IS CROSS-PLATFORM**: Proofs must be deserializable by Swift, Dart, and JavaScript. Use a simple, language-agnostic format (4-byte counts, 4-byte length prefixes, then bytes). JSON or CBOR serialisation of AnchorProof is safer than binary structs.
4. **BATCH IS THE PRIMARY USE CASE**: Implement batch-anchor as the main function. Single-anchor (if needed) is convenience. Don't build for single anchors and bolster them together awkwardly.
5. **NO EASY TESTS**: Don't just check "function returned 0". Verify callback invocation, check proof structure, test SPV with valid and tampered proofs, test batch count matching.
6. **NO TESTS THAT MATCH BROKEN CODE**: If you implement SPV validation wrong and your test passes, you've failed. Write tests FIRST that catch SPV bugs (e.g., if you skip merkle validation, a tampered proof should still fail).
7. **TAMPER DETECTION IS MANDATORY**: `semantos_anchor_verify()` must reject proofs with invalid merkle paths or wrong block headers. Your test suite must include valid and tampered proof cases. A "valid" proof with one byte flipped should fail.

---

## PART 0: GIT HYGIENE

**Assess current state**:
- Check `git status` — ensure working tree is clean
- Check `git log --oneline -5` — verify Phase 30C is merged
- Verify Phase 30C deliverables exist: `src/ffi/exports.zig` has capability functions, `src/ffi/tests/capability_test.zig` exists

**Discard any unrelated work**:
- If there are untracked files or unstaged changes unrelated to Phase 30D, discard them

**Verify prerequisites**:
- Phase 30C callback registration (identity callbacks) must be in place
- Phase 26C AnchorAdapter interface must exist at `src/adapters/anchor/` or similar
- `packages/protocol-types/src/anchor.ts` must define AnchorProof type

**Create and switch to branch**:
```bash
git checkout -b phase-30d-anchor-ffi
```

**Verify you're on the branch**:
```bash
git branch -v | grep phase-30d-anchor-ffi
```

---

## Steps

### Step 1: Implement D30D.1 — Anchor FFI functions

**File**: `src/ffi/exports.zig`

Add two functions:

```zig
pub export fn semantos_anchor_batch(state_hashes_json: [*]const u8, json_len: usize, out_proofs: [*]u8, out_len: [*]usize) i32 {
    // TODO: Parse JSON array of hex state hashes (e.g., ["abc123...", "def456..."])
    // TODO: For each state hash, call host_anchor_submit callback to submit to BSV
    // TODO: Collect AnchorProof results from callback
    // TODO: Serialise proof array using format defined in D30D.3 (4-byte count + length-prefixed proofs)
    // TODO: Write serialised array to out_proofs, length to out_len
    // TODO: Return: 0 on success
    //              SEMANTOS_ERR_CALLBACK_NOT_REGISTERED if host_anchor_submit not registered
    //              other error codes as appropriate (parse error, callback error, etc.)
}

pub export fn semantos_anchor_verify(proof: [*]const u8, proof_len: usize) i32 {
    // TODO: Deserialise proof bytes
    // TODO: Validate proof structure
    // TODO: Perform SPV validation: check merkle path against block header, validate block header POW
    // TODO: Return: 0 if proof is valid
    //              SEMANTOS_ERR_INVALID_PROOF=-7 if SPV fails or structure is corrupt
    //              other error codes as appropriate
    // CRITICAL: NO network calls, NO callbacks, pure computation only
}
```

**Commit**:
```bash
git add src/ffi/exports.zig
git commit -m "phase-30d/D30D.1: anchor FFI functions (anchor_batch, anchor_verify)"
```

---

### Step 2: Implement D30D.2 — Anchor callback wiring

**File**: `src/ffi/exports.zig` (or appropriate callback implementation file)

Verify that:
- `host_anchor_submit` callback is registered and callable from within `semantos_anchor_batch()`
- Callback properly handles state hash input and returns `AnchorProof` (or proof result)
- If callback is not registered, `semantos_anchor_batch()` returns `SEMANTOS_ERR_CALLBACK_NOT_REGISTERED`

Wire the callback invocation into `semantos_anchor_batch()`:

```zig
// Inside semantos_anchor_batch:
const callback = semantos.callback_registry.get_host_anchor_submit();
if (callback == null) return SEMANTOS_ERR_CALLBACK_NOT_REGISTERED;

for (state_hashes) |hash| {
    const proof_result = callback(hash, hash.len);
    // ... collect proof result ...
}
```

**Commit**:
```bash
git add src/ffi/exports.zig
git commit -m "phase-30d/D30D.2: wire anchor callback into batch function"
```

---

### Step 3: Implement D30D.3 — Proof serialisation

**File**: `src/ffi/exports.zig` (or new file `src/ffi/serialization.zig`)

Define the wire format and implement serialisation/deserialisation functions:

```zig
// Wire format: [4-byte count (LE)] + [for each proof: 4-byte length (LE) + proof bytes]
//
// Example: 2 proofs of 100 and 150 bytes
//   Bytes 0-3:   0x02 0x00 0x00 0x00  (count = 2)
//   Bytes 4-7:   0x64 0x00 0x00 0x00  (length of proof 1 = 100)
//   Bytes 8-107: [100 bytes of proof 1]
//   Bytes 108-111: 0x96 0x00 0x00 0x00 (length of proof 2 = 150)
//   Bytes 112-261: [150 bytes of proof 2]

pub fn serialize_anchor_proofs(allocator: std.mem.Allocator, proofs: []const AnchorProof) ![]u8 {
    // Calculate total size: 4 (count) + sum of (4 + proof_len for each)
    // Allocate buffer
    // Write count (LE)
    // For each proof: write length (LE), write bytes
    // Return buffer
}

pub fn deserialize_anchor_proofs(allocator: std.mem.Allocator, data: []const u8) ![]AnchorProof {
    // Read count (LE) from bytes 0-3
    // Allocate proofs array
    // For each proof: read length (LE), read bytes, construct AnchorProof
    // Return proofs array
}
```

Document the format with a comment block in `src/ffi/exports.zig`:

```zig
// ANCHOR PROOF SERIALISATION FORMAT
// ===================================
// Wire format for AnchorProof arrays crossing FFI boundary.
// Designed for cross-platform compatibility (Swift, Dart, JavaScript).
//
// Structure:
//   [4 bytes LE] count of proofs
//   [for each proof]:
//     [4 bytes LE] length of proof in bytes
//     [N bytes] proof bytes (JSON-encoded AnchorProof object)
//
// Example: 2 proofs, 100 and 150 bytes respectively
//   Offset 0-3:   count = 2 (0x02 0x00 0x00 0x00 in LE)
//   Offset 4-7:   length = 100 (0x64 0x00 0x00 0x00 in LE)
//   Offset 8-107: 100 bytes of proof 1 (JSON)
//   Offset 108-111: length = 150 (0x96 0x00 0x00 0x00 in LE)
//   Offset 112-261: 150 bytes of proof 2 (JSON)
//
// This format is language-agnostic and handles variable-sized proofs.
```

**Commit**:
```bash
git add src/ffi/exports.zig src/ffi/serialization.zig
git commit -m "phase-30d/D30D.3: proof serialisation (cross-platform wire format)"
```

---

### Step 4: Implement D30D.4 — Anchor FFI tests

**File**: `src/ffi/tests/anchor_test.zig` (new file)

Create a test suite with the following test cases:

```zig
const std = @import("std");
const semantos = @import("../../../src/main.zig");

test "T1: anchor_batch with valid state hashes returns serialised proof array" {
    // Setup: register mock anchor callback that returns valid proofs
    // Prepare JSON: ["hash1", "hash2"]
    // Call semantos_anchor_batch(json, json_len, out_proofs, out_len)
    // Assert: return value is 0
    // Assert: out_len > 0 (proofs were serialised)
    // Assert: out_proofs is non-null
}

test "T2: anchor_batch calls host_anchor_submit callback with correct state hash" {
    // Setup: register mock anchor callback that logs invocations
    // Prepare JSON: ["abc123def456"]
    // Call semantos_anchor_batch(json, json_len, out_proofs, out_len)
    // Assert: callback was invoked once with hash "abc123def456"
}

test "T3: anchor_verify with valid proof returns 0" {
    // Setup: generate a valid AnchorProof (or use test fixture)
    // Serialise proof to bytes
    // Call semantos_anchor_verify(proof_bytes, proof_len)
    // Assert: return value is 0
}

test "T4: anchor_verify with tampered proof returns SEMANTOS_ERR_INVALID_PROOF" {
    // Setup: generate a valid AnchorProof, serialise it
    // Tamper: flip one byte in the merkle path or block header
    // Call semantos_anchor_verify(tampered_bytes, len)
    // Assert: return value is SEMANTOS_ERR_INVALID_PROOF
}

test "T5: batch of N hashes produces N individual proofs in output" {
    // Setup: register mock anchor callback
    // Prepare JSON with 5 state hashes: ["h1", "h2", "h3", "h4", "h5"]
    // Call semantos_anchor_batch(json, json_len, out_proofs, out_len)
    // Deserialise output using deserialize_anchor_proofs()
    // Assert: proofs array has length 5
}

test "T6: empty batch returns success with empty proof array" {
    // Prepare empty JSON: []
    // Call semantos_anchor_batch(json, json_len, out_proofs, out_len)
    // Assert: return value is 0
    // Assert: output is valid empty array (count = 0) or out_len = 0
}

test "T7: anchor_batch with null callback registered returns error code" {
    // Setup: do NOT register host_anchor_submit callback
    // Prepare JSON: ["hash1"]
    // Call semantos_anchor_batch(json, json_len, out_proofs, out_len)
    // Assert: return value is SEMANTOS_ERR_CALLBACK_NOT_REGISTERED (or similar)
}

test "T8: proof serialisation is deserializable (round-trip)" {
    // Generate a test AnchorProof
    // Serialise it using serialize_anchor_proofs()
    // Deserialise using deserialize_anchor_proofs()
    // Re-serialise
    // Assert: first serialisation == second serialisation (byte-for-byte)
}
```

**Commit**:
```bash
git add src/ffi/tests/anchor_test.zig
git commit -m "phase-30d/D30D.4: anchor FFI test suite (8 TDD gate tests)"
```

---

## Completion Criteria

- [ ] All four deliverables (D30D.1-D30D.4) implemented
- [ ] All 8 TDD gate tests passing: `zig build test`
- [ ] Anchor callback wiring verified: tests assert callback invocation
- [ ] SPV validation tested: T3 and T4 verify both valid and tampered proofs
- [ ] Proof serialisation format documented and round-trip tested (T8)
- [ ] No stubs, no fake implementations
- [ ] Code review completed
- [ ] Branch `phase-30d-anchor-ffi` is up-to-date and ready for merge
- [ ] Commit history is clean: one commit per deliverable (4 commits total)

---

## Post-Phase: Errata Sprint

After Phase 30D is complete and merged:

1. **SPV edge cases**: What if block header is beyond the Bitcoin chain tip? Add validation.
2. **Proof expiry**: Should old proofs (e.g., 6+ months) be rejected? Add configurable expiry if needed.
3. **Batch size limits**: Are batch submissions bounded? Add max-batch-size validation.
4. **Callback retry logic**: If host_anchor_submit fails, should we retry? Track as known issue.

These are post-merge follow-ups. Don't block Phase 30D on them.

---

## NOTES FOR IMPLEMENTATION

- **Proof structure**: Consult `packages/protocol-types/src/anchor.ts` for the exact AnchorProof type. Likely contains: `blockHash`, `blockHeight`, `merkleProof`, `txHash`, `txIndex`, timestamp, etc.
- **SPV validation**: You'll need merkle path validation (each node is hash(left, right)) and block header proof-of-work validation (hash < target). Lean on existing BSV libraries if available.
- **JSON parsing**: Use Zig's JSON parser (stdlib or ziggy if available) to parse the state hash array from host. If JSON parsing fails, return error code.
- **Memory management**: Kernel allocates proofs array; host must free it. Document this in the FFI header.
