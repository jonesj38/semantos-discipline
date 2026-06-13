---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30D-ANCHOR-FFI.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.655880+00:00
---

# Phase 30D — Anchor FFI Functions

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 3-4 days
**Prerequisites**: Phase 30C complete (capability + linearity FFI), Phase 26C complete (AnchorAdapter)
**Master document**: `PHASE-30-FFI-MASTER.md`
**Branch**: `phase-30d-anchor-ffi`

---

## Context

Anchoring is how Semantos proves that state existed at a specific time and block height. The FFI surface exposes two anchor functions: batch-anchor (submit multiple state hashes in one operation) and verify (SPV-check an anchor proof offline). This is the last piece of the core C ABI before the platform-specific packaging phases (30E/F/G) can begin.

**The Boundary Rule**: Anchor proofs cross the FFI boundary as serialised byte arrays. The host provides state hashes as JSON, receives serialised `AnchorProof` arrays back. The kernel calls through to the `host_anchor_submit` callback for the actual BSV transaction submission. Verification is purely local — no network, no callbacks — using SPV proof validation.

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `PHASE-30C` | `docs/prd/PHASE-30C-CAPABILITY-FFI.md` | FFI pattern, callback wiring |
| `MASTER-FFI` | `docs/prd/PHASE-30-FFI-MASTER.md` | Anchor functions table, error codes |
| `PHASE-26C` | `docs/prd/PHASE-26C-ANCHOR-ADAPTER.md` | AnchorAdapter interface, BsvAnchorAdapter, StubAnchorAdapter |
| `ANCHOR-TS` | `packages/protocol-types/src/anchor.ts` | AnchorProof type, anchor interface |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules |

---

## Deliverables

### D30D.1 — Anchor FFI functions

In `src/ffi/exports.zig`, add:

- `semantos_anchor_batch(state_hashes_json, json_len, out_proofs, out_len) → i32`
  - Parses JSON array of hex state hashes (e.g., `["abc123...", "def456..."]`)
  - Calls `host_anchor_submit` callback for each state hash (or batched if callback supports it)
  - Returns serialised `AnchorProof` array (kernel-allocated)
  - Returns: `0` on success, error code on failure
  - On error: `out_proofs` and `out_len` are set to null/0

- `semantos_anchor_verify(proof, proof_len) → i32`
  - Offline SPV verification of an anchor proof
  - Deserialises the proof bytes from FFI boundary
  - Validates proof structure, merkle path, and block header SPV
  - Returns: `0` (valid), `SEMANTOS_ERR_INVALID_PROOF=-7`, or other error
  - **CRITICAL**: No callbacks, no network — pure computation

### D30D.2 — Anchor callback wiring

Wire `host_anchor_submit` callback into `semantos_anchor_batch`. The kernel constructs the anchor request (state hash, optional metadata), calls the registered callback to submit to BSV blockchain, and packages the result (proof) into the output array.

Ensure callback registration from Phase 30B/C is accessible. If callback is not registered, return error code (e.g., `SEMANTOS_ERR_CALLBACK_NOT_REGISTERED`).

### D30D.3 — Proof serialisation

Define the wire format for `AnchorProof` arrays crossing the FFI boundary. Must be deserializable by Swift, Dart, and JavaScript.

Recommended format:
- 4-byte count (little-endian): number of proofs in array
- For each proof:
  - 4-byte length prefix (little-endian): bytes for this proof
  - Proof bytes: JSON (recommended) or CBOR-encoded AnchorProof object

Example: N proofs = 4 bytes (N) + [4 bytes (len_1) + proof_1_bytes] + [4 bytes (len_2) + proof_2_bytes] + ...

Document this format in a comment block in `src/ffi/exports.zig`.

### D30D.4 — Anchor FFI tests

New file: `src/ffi/tests/anchor_test.zig`

Tests:
- Batch anchor with stub callback
- Verify valid proof (SPV passes)
- Reject tampered proof (SPV fails)
- Verify batch of N hashes produces N individual proofs
- Empty batch handling (zero hashes → empty proof array)
- Null callback registration error
- Proof serialisation round-trip (deserialise, re-serialise, compare)

---

## TDD Gate Tests

- **T1**: `semantos_anchor_batch()` with valid state hashes returns serialised proof array (out_len > 0)
- **T2**: `semantos_anchor_batch()` calls `host_anchor_submit` callback with correct state hash (verified via mock)
- **T3**: `semantos_anchor_verify()` with valid proof returns `0`
- **T4**: `semantos_anchor_verify()` with tampered proof returns `SEMANTOS_ERR_INVALID_PROOF`
- **T5**: Batch of N hashes produces N individual proofs in output array
- **T6**: Empty batch (zero hashes) returns success with empty proof array (out_len = 0 or valid empty structure)
- **T7**: `semantos_anchor_batch()` with null callback registered returns error code
- **T8**: Proof serialisation is deserializable and round-trip (serialise → deserialise → serialise yields same bytes)

---

## Completion Criteria

- All four deliverables implemented and committed
- All 8 TDD gate tests passing
- Anchor callback wiring verified via callback invocation logs in tests
- SPV validation tested with both valid and tampered proofs
- Proof serialisation format documented and round-trip tested
- No stubs or placeholders remain
- Code review completed
- Branch `phase-30d-anchor-ffi` pushed and ready for merge
