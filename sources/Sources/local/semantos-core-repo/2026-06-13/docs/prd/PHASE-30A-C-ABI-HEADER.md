---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30A-C-ABI-HEADER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.684358+00:00
---

# Phase 30A — C ABI Header & Core FFI Functions
**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week
**Prerequisites**: Phase 25A–25D complete (kernel proof boundary, StorageAdapter)
**Master document**: `PHASE-30-FFI-MASTER.md`
**Branch**: `phase-30a-c-abi-header`

---

## Context
The Zig kernel needs a flat C API surface that any language can bind to. No Zig-specific types, no C++ mangling, no exceptions. Every function takes/returns C-compatible types: integers, pointers to byte buffers, status codes. This is the contract Swift, Dart, and JavaScript will bind to.

### The Boundary Rule
The C ABI header exposes ONLY flat C types. No Zig allocators, no Zig error unions, no comptime types. The kernel's internal complexity stays behind the FFI wall. Every function is `export fn` with `callconv(.C)`.

---

## Source Files / References
| Alias | Path | What to extract |
|-------|------|-----------------|
| `MASTER-FFI` | `docs/prd/PHASE-30-FFI-MASTER.md` | Architecture, C ABI surface, memory ownership model |
| `KERNEL-CELL` | `src/kernel/cell_engine.zig` | Cell engine API that FFI wraps |
| `CONSTANTS` | `packages/protocol-types/src/constants.ts` | CELL_SIZE, magic numbers for reference |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules |

---

## Deliverables

### D30A.1 — semantos.h (C header file)
**New file**: `src/ffi/semantos.h`

The complete C header declaring all FFI functions. A pure C header (compilable with `gcc -c`) that exposes the kernel's C ABI surface.

**Content**:
- SemantosResult typedef: `typedef int32_t SemantosResult;` (0=success, negative=error)
- Error code enum with these values:
  - `SEMANTOS_OK = 0`
  - `SEMANTOS_ERR_NOT_FOUND = -1`
  - `SEMANTOS_ERR_INVALID_JSON = -2`
  - `SEMANTOS_ERR_ALREADY_CONSUMED = -3`
  - `SEMANTOS_ERR_ALREADY_INIT = -4`
  - `SEMANTOS_ERR_NOT_INIT = -5`
  - `SEMANTOS_ERR_BUFFER_TOO_SMALL = -6`
  - `SEMANTOS_ERR_INVALID_PROOF = -7`
  - `SEMANTOS_ERR_DENIED = -8`
  - `SEMANTOS_ERR_EXPIRED = -9`
- Function declarations with C calling convention:
  - `SemantosResult semantos_init(const uint8_t* config_json, size_t config_len)`
  - `SemantosResult semantos_shutdown(void)`
  - `SemantosResult semantos_cell_write(const char* path, size_t path_len, const uint8_t* data, size_t data_len)`
  - `SemantosResult semantos_cell_read(const char* path, size_t path_len, uint8_t* out_data, size_t* inout_len)`
  - `SemantosResult semantos_cell_verify(const char* path, size_t path_len, const uint8_t* proof, size_t proof_len)`
  - `void semantos_free(uint8_t* ptr, size_t len)`
  - `const char* semantos_version(void)`
  - `SemantosResult semantos_last_error(char* out_buf, size_t* inout_len)`

---

### D30A.2 — Core FFI implementation (Zig)
**New file**: `src/ffi/exports.zig`

The Zig implementation of core functions with C calling convention. Each function:
- Uses `export fn` with `callconv(.C)` for C-compatible calling convention
- Bounds-checks all input pointers and length parameters; returns error for null/invalid pointers
- Copies data in/out of the kernel (never holds references to host memory across calls)
- Returns SemantosResult (0 on success, negative error code on failure)
- Uses kernel's arena allocator for any kernel-allocated return buffers
- Maintains global (thread-local) initialization state to enforce init/shutdown ordering

**Functions to implement**:
- `semantos_init`: Parse config JSON, initialize kernel subsystems, set initialized flag
- `semantos_shutdown`: Clean up, reset initialized flag
- `semantos_cell_write`: Route to kernel cell engine, verify path/data validity
- `semantos_cell_read`: Route to kernel cell engine, bounds-check output buffer
- `semantos_cell_verify`: Route to proof verification subsystem
- All functions: guard with initialized-flag check (return SEMANTOS_ERR_NOT_INIT if not ready)

---

### D30A.3 — Memory management functions
**In file**: `src/ffi/exports.zig`

Three additional functions for memory and metadata:
- `semantos_free(ptr: [*]u8, len: usize) void`: Releases kernel-allocated buffers (no-op if invalid pointer, but does not crash)
- `semantos_version() [*:0]const u8`: Returns static null-terminated string matching build version tag (e.g., "0.2.1-phase-30a")
- `semantos_last_error(out_buf: [*]u8, inout_len: [*]usize) SemantosResult`: Writes thread-local error message (with newline) into out_buf; updates inout_len to actual length written or required length if buffer too small

---

### D30A.4 — FFI integration test harness
**New file**: `src/ffi/tests/core_test.zig`

Zig test file exercising the full FFI round-trip via C calling convention. Tests invoke the exported functions as if from external C code (do not use Zig-only conveniences like error handling).

**Test structure**:
- Setup: call semantos_init with valid minimal config JSON
- Exercise: invoke each core function with valid and invalid inputs
- Verify: check return codes and output buffer contents match expectations
- Teardown: call semantos_shutdown

---

## TDD Gate Tests
### 30A Gate Tests
- Test 1: `semantos_init()` with valid JSON config returns SEMANTOS_OK (0)
- Test 2: `semantos_init()` with invalid JSON returns SEMANTOS_ERR_INVALID_JSON
- Test 3: `semantos_cell_write()` then `semantos_cell_read()` returns identical bytes
- Test 4: `semantos_cell_read()` on non-existent path returns SEMANTOS_ERR_NOT_FOUND
- Test 5: `semantos_free()` on kernel-allocated buffer does not crash and succeeds
- Test 6: `semantos_version()` returns non-null string matching build version
- Test 7: Double `semantos_init()` (without shutdown) returns SEMANTOS_ERR_ALREADY_INIT
- Test 8: Any core function called before `semantos_init()` returns SEMANTOS_ERR_NOT_INIT
- Test 9: `semantos_cell_write()` with null data pointer returns error (does not crash)
- Test 10: `semantos_cell_write()` with zero-length data returns error (validates minimum payload)

---

## Completion Criteria
- [ ] `src/ffi/semantos.h` exists, is valid C, compiles with `gcc -c`
- [ ] `src/ffi/exports.zig` implements all 8 exported functions with `export fn` and `callconv(.C)`
- [ ] All functions bounds-check inputs and return appropriate error codes
- [ ] No Zig-specific types leak into function signatures (only C primitives)
- [ ] Thread-local initialization state prevents use-before-init and double-init
- [ ] `src/ffi/tests/core_test.zig` covers all 10 gate tests, all pass
- [ ] No stubs, mocks, or hardcoded responses; functions perform real work
- [ ] Branch `phase-30a-c-abi-header` created and commits follow naming convention
- [ ] All code follows Semantos project style (indentation, naming, comments)
- [ ] Branch merged to main, tagged as `v0.30a` or similar
