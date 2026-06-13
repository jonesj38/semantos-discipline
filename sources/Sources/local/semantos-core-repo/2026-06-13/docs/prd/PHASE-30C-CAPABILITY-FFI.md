---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30C-CAPABILITY-FFI.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.698703+00:00
---

# Phase 30C — Capability & Linearity FFI Functions

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week
**Prerequisites**: Phase 30B complete (adapter callbacks registered), Phase 26B complete (LocalIdentityAdapter)
**Master document**: `PHASE-30-FFI-MASTER.md`
**Branch**: `phase-30c-capability-ffi`

---

## Context

The kernel enforces two critical invariants through the FFI: capability-based access control and linear resource consumption. These are the functions that make Semantos provably secure — a tradie can't access a PM's private notes (capability denial), and an approval token can't be consumed twice (linearity enforcement). This phase exposes these invariants through the C ABI.

**The Boundary Rule**: Capability tokens are opaque byte arrays at the FFI boundary. The host never interprets token internals — it receives bytes from `semantos_capability_present()` and passes them back via `semantos_capability_check()`. The kernel validates internally. LINEAR consumption is atomic: if the kernel crashes mid-consume, the cell is either fully consumed or untouched, never partial.

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `PHASE-30B` | `docs/prd/PHASE-30B-ADAPTER-CALLBACKS.md` | Callback registry, identity callbacks |
| `MASTER-FFI` | `docs/prd/PHASE-30-FFI-MASTER.md` | Capability functions table, linearity model |
| `IDENTITY-ADAPTER` | `packages/protocol-types/src/identity.ts` | IdentityAdapter interface |
| `CONSTANTS` | `packages/protocol-types/src/constants.ts` | Linearity constants (LINEAR, AFFINE, RELEVANT, etc.) |
| `PHASE-26B` | `docs/prd/PHASE-26B-LOCAL-IDENTITY.md` | LocalIdentityAdapter, offline capability validation |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules |

---

## Deliverables

### D30C.1 — Capability FFI functions

In `src/ffi/exports.zig`, add:

- `semantos_capability_check(cert_id, cert_len, domain_flag) → i32`
  - Returns: `0` (valid), `SEMANTOS_ERR_DENIED`, or `SEMANTOS_ERR_EXPIRED`
  - Validates that the certificate grants access to the specified domain
  - Calls through to IdentityAdapter callbacks for cert resolution

- `semantos_capability_present(cert_id, cert_len, domain_flag, out_token, out_len) → i32`
  - Generates BRC-108 capability token bytes
  - Returns: `0` on success, error code on failure
  - Kernel allocates token memory; host must free via `semantos_free()`
  - Calls through to IdentityAdapter callbacks for cert resolution

Both functions call through to IdentityAdapter callbacks for certificate resolution.

### D30C.2 — Linearity FFI function

In `src/ffi/exports.zig`, add:

- `semantos_linear_consume(path, path_len, consumer_cert, cert_len) → i32`
  - Returns: `0` (success), `SEMANTOS_ERR_ALREADY_CONSUMED=-3`, or other error
  - Enforces exactly-once semantics via kernel's linearity engine
  - Atomic: writes consumption record to StorageAdapter before returning success
  - On crash recovery: checks consumption record exists → if yes, cell is consumed

### D30C.3 — Identity callback wiring

Wire `host_identity_resolve` and `host_identity_derive` callbacks into the capability functions. When kernel needs to resolve a certificate for `capability_check`, it calls through the registered identity callback. Ensure callback registration from Phase 30B is properly linked.

### D30C.4 — Capability + linearity tests

New file: `src/ffi/tests/capability_test.zig`

Tests exercising:
- Capability check with valid and invalid domains
- Token generation and basic structure validation
- LINEAR consumption with exactly-once semantics
- Double-consume rejection
- Crash-recovery atomicity (simulated via mock storage)
- Null pointer handling

---

## TDD Gate Tests

- **T1**: `semantos_capability_check()` returns `0` for granted domain flag
- **T2**: `semantos_capability_check()` returns `SEMANTOS_ERR_DENIED` for ungranted domain flag
- **T3**: `semantos_capability_check()` returns `SEMANTOS_ERR_EXPIRED` for expired cert
- **T4**: `semantos_capability_present()` returns valid BRC-108 token bytes (non-empty, kernel-allocated)
- **T5**: Token from `semantos_capability_present()` can be verified externally (structure check)
- **T6**: `semantos_linear_consume()` returns `0` on first call
- **T7**: `semantos_linear_consume()` returns `SEMANTOS_ERR_ALREADY_CONSUMED` on second call with same path
- **T8**: LINEAR consumption is atomic: simulated crash leaves cell in clean state (consumed or untouched)
- **T9**: `semantos_capability_check()` with null `cert_id` returns error (not crash)
- **T10**: `semantos_linear_consume()` with non-LINEAR cell returns appropriate error

---

## Completion Criteria

- All four deliverables implemented and committed
- All 10 TDD gate tests passing
- Identity callback wiring verified via callback invocation logs in tests
- Linearity atomicity validated with simulated crash scenarios
- Code review completed; no stubs or placeholders remain
- Branch `phase-30c-capability-ffi` pushed and ready for merge
