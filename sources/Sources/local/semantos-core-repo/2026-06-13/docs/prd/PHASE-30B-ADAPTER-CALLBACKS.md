---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30B-ADAPTER-CALLBACKS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.674736+00:00
---

# Phase 30B — Adapter Callback Registration & Storage Callbacks
**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week
**Prerequisites**: Phase 30A complete (C ABI header + core functions), Phase 26A complete (IdentityAdapter extraction)
**Master document**: `PHASE-30-FFI-MASTER.md`
**Branch**: `phase-30b-adapter-callbacks`

---

## Context
The kernel calls back into host code for adapter operations. On init, the host registers function pointers for each adapter interface. The kernel invokes these when it needs I/O (storage, identity resolution, anchor submission, network queries, etc.). This phase implements the callback registration mechanism and the first callback pair: host_storage_read/host_storage_write.

Callbacks enable the kernel to remain pure (no I/O, no async, no side effects) while delegating I/O to the host runtime. The host can implement these callbacks synchronously (in-process) or asynchronously (dispatch to event loop, then block on result). From the kernel's perspective, callbacks are synchronous: the kernel blocks on return.

### The Boundary Rule
Callbacks are synchronous from the kernel's perspective. The host may internally dispatch to async I/O, but the kernel blocks on the callback return. This keeps kernel execution simple and deterministic — critical for formal proofs. Callback function pointers are C-compatible: no closures, no Zig error unions, no capturing. Each callback accepts a subset of parameters relevant to that operation and returns a status code.

---

## Source Files / References
| Alias | Path | What to extract |
|-------|------|-----------------|
| `PHASE-30A` | `docs/prd/PHASE-30A-C-ABI-HEADER.md` | C ABI surface, error codes, initialization flow |
| `MASTER-FFI` | `docs/prd/PHASE-30-FFI-MASTER.md` | Callback table, all 7 callback signatures, adapter directions, registration protocol |
| `STORAGE-ADAPTER` | `packages/protocol-types/src/storage.ts` | StorageAdapter pattern, key/value semantics |
| `IDENTITY-ADAPTER` | `packages/protocol-types/src/identity.ts` | IdentityAdapter pattern, cert resolution and derivation |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules |

---

## Deliverables

### D30B.1 — Callback type definitions
**New file**: `src/ffi/callbacks.zig`

Defines all C-compatible function pointer types for adapter callbacks. These types match the signatures that the host will implement.

**Content**:
Callback function pointer types (all with `callconv(.C)`):
- `host_storage_read`: `fn (key: [*:0]const u8, key_len: usize, out_buf: [*]u8, inout_len: [*]usize) callconv(.C) i32`
  - Host provides data for a key; kernel-provided buffer is filled with value bytes; returns status
- `host_storage_write`: `fn (key: [*:0]const u8, key_len: usize, data: [*:0]const u8, data_len: usize) callconv(.C) i32`
  - Kernel asks host to persist a key-value pair; returns status
- `host_identity_resolve`: `fn (cert_id: [*]const u8, cert_len: usize, out_json: [*]u8, inout_len: [*]usize) callconv(.C) i32`
  - Given certificate ID, host returns certificate JSON; kernel-provided buffer filled; returns status
- `host_identity_derive`: `fn (parent_cert: [*:0]const u8, cert_len: usize, resource_id: [*:0]const u8, rid_len: usize, domain_flag: u32, out_json: [*]u8, inout_len: [*]usize) callconv(.C) i32`
  - Kernel asks host to derive a new certificate from parent; returns derived cert JSON; returns status
- `host_anchor_submit`: `fn (state_hash: [*]const u8, hash_len: usize, metadata_json: [*:0]const u8, meta_len: usize, out_proof: [*]u8, inout_len: [*]usize) callconv(.C) i32`
  - Kernel submits state for anchoring; host returns proof; returns status
- `host_network_publish`: `fn (object_json: [*:0]const u8, json_len: usize) callconv(.C) i32`
  - Kernel publishes object to network; host handles distribution; returns status
- `host_network_resolve`: `fn (query_json: [*:0]const u8, json_len: usize, out_results: [*]u8, inout_len: [*]usize) callconv(.C) i32`
  - Kernel queries network; host returns matching objects; returns status

Each function returns `i32` (0 = success, negative = error code).

---

### D30B.2 — Callback registry
**In file**: `src/ffi/callbacks.zig`

Global (thread-local) registry that stores registered function pointers. The registry is:
- Initialized on first `semantos_init` call
- Immutable after init (re-registration is an error)
- Thread-local (each thread has its own set of callbacks)

**Registry structure**:
```zig
threadlocal var callback_registry: CallbackRegistry = undefined;
threadlocal var callbacks_registered: bool = false;

pub const CallbackRegistry = struct {
    host_storage_read: ?*const fn (...) callconv(.C) i32 = null,
    host_storage_write: ?*const fn (...) callconv(.C) i32 = null,
    host_identity_resolve: ?*const fn (...) callconv(.C) i32 = null,
    host_identity_derive: ?*const fn (...) callconv(.C) i32 = null,
    host_anchor_submit: ?*const fn (...) callconv(.C) i32 = null,
    host_network_publish: ?*const fn (...) callconv(.C) i32 = null,
    host_network_resolve: ?*const fn (...) callconv(.C) i32 = null,
};
```

**Registration function**:
`semantos_register_callbacks(storage_read: ?*..., storage_write: ?*..., identity_resolve: ?*..., identity_derive: ?*..., anchor_submit: ?*..., network_publish: ?*..., network_resolve: ?*...) SemantosResult`
- If already registered, return SEMANTOS_ERR_ALREADY_INIT
- Store all 7 function pointers (null allowed for unused callbacks)
- Set callbacks_registered = true
- Return SEMANTOS_OK

**Export function (C ABI)**:
Make semantos_register_callbacks available as an export so hosts can call it.

---

### D30B.3 — Storage callback integration
**Modify file**: `src/kernel/storage_adapter.zig` (or equivalent kernel storage layer)

Wire host_storage_read and host_storage_write into the kernel's StorageAdapter pathway.

**When kernel calls StorageAdapter.read(key)**:
1. Guard: if host_storage_read callback is null, return SEMANTOS_ERR_DENIED
2. Allocate output buffer (kernel-owned arena)
3. Call `callback_registry.host_storage_read(key.ptr, key.len, out_buf, &out_len)`
4. If callback returns error, propagate
5. If callback succeeds, return buffer to kernel
6. Kernel owns the buffer; caller must free via semantos_free

**When kernel calls StorageAdapter.write(key, value)**:
1. Guard: if host_storage_write callback is null, return SEMANTOS_ERR_DENIED
2. Call `callback_registry.host_storage_write(key.ptr, key.len, value.ptr, value.len)`
3. If callback returns error, propagate
4. If callback succeeds, return success
5. No buffer allocation; host is responsible for persistence

---

### D30B.4 — Callback round-trip tests
**New file**: `src/ffi/tests/callback_test.zig`

Zig test file with mock C callbacks that verify the full round-trip: host registers callback → kernel calls through function pointer → host callback receives correct args → host returns data → kernel processes result.

**Test structure**:
- Define mock callback functions (in Zig, but with `callconv(.C)`)
- Create a test harness that registers these mocks
- Invoke kernel operations and verify callbacks were triggered with correct parameters
- Verify data flows correctly in and out

**Tests to implement**:
- Test 1: Register callbacks successfully, query registry
- Test 2: Kernel cell_write triggers host_storage_write with correct key/data
- Test 3: Kernel cell_read triggers host_storage_read, returns host-provided data
- Test 4: Null callback for storage → error on read/write (not crash)
- Test 5: Callback returning error code propagates through FFI
- Test 6: All 7 callback types can be registered independently
- Test 7: Re-registration after init returns error

---

## TDD Gate Tests
### 30B Gate Tests
- Test 1: `semantos_register_callbacks()` with valid pointers stores them in registry; subsequent query returns same pointers
- Test 2: `semantos_cell_write()` after init and callback registration triggers `host_storage_write` callback with correct key and data
- Test 3: `semantos_cell_read()` after init and callback registration triggers `host_storage_read` callback; kernel returns host-provided data
- Test 4: `semantos_cell_write()` when host_storage_write callback is null returns error (does not crash)
- Test 5: `semantos_cell_read()` when host_storage_read callback is null returns error (does not crash)
- Test 6: `host_storage_write` callback returning error code causes `semantos_cell_write()` to return that error
- Test 7: `semantos_register_callbacks()` called twice (without shutdown) returns SEMANTOS_ERR_ALREADY_INIT
- Test 8: All 7 callback types can be registered; each can be individually null while others are set
- Test 9: Callback receiving null key pointer or zero key_len returns error (not crash)
- Test 10: Host callback that returns SEMANTOS_ERR_DENIED causes kernel operation to return that error

---

## Completion Criteria
- [ ] `src/ffi/callbacks.zig` exists with all 7 callback type definitions
- [ ] `semantos_register_callbacks()` is exported and callable from C
- [ ] Registry is thread-local and immutable after first registration
- [ ] `src/kernel/storage_adapter.zig` (or equivalent) calls registered callbacks on read/write
- [ ] `src/ffi/tests/callback_test.zig` defines mock C callbacks and tests all 10 gate tests
- [ ] All 10 gate tests pass
- [ ] Null callback pointers are handled gracefully (error, not crash)
- [ ] Callback return codes propagate through FFI
- [ ] No stubs, no hardcoded responses
- [ ] Branch `phase-30b-adapter-callbacks` created, commits follow naming convention
- [ ] All code follows Semantos project style
- [ ] Branch merged to main, tagged as `v0.30b`
