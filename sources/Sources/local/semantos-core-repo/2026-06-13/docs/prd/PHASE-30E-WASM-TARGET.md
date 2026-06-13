---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30E-WASM-TARGET.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.714160+00:00
---

# Phase 30E — WASM Target & Host Import Bindings

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week
**Prerequisites**: Phase 30D complete (all core C ABI functions)
**Master document**: `PHASE-30-FFI-MASTER.md`
**Branch**: `phase-30e-wasm-target`

---

## Context

The same Zig kernel source that produces native .a files also compiles to wasm32-wasi. The WASM module exposes the same C ABI functions as the native library. Host-provided imports supply adapter implementations. The WASM memory model adds a layer: all data crosses the boundary via copy through WASM linear memory. The host allocates in WASM memory, copies data in, calls the function, copies the result out, then frees.

### The Boundary Rule

WASM linear memory is the only shared surface. The host cannot access kernel internal state. The kernel cannot access host memory. Every byte that crosses the boundary goes through explicit copy operations in WASM linear memory. This is actually MORE secure than native FFI because the sandbox enforces the boundary at the VM level.

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `MASTER-FFI` | `docs/prd/PHASE-30-FFI-MASTER.md` | WASM target details, memory model |
| `PHASE-30D` | `docs/prd/PHASE-30D-ANCHOR-FFI.md` | Complete C ABI surface |
| `BUILD-ZIG` | `build.zig` | Existing build configuration |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming |

---

## Deliverables

### D30E.1 — WASM build target configuration

In `build.zig`: add wasm32-wasi target with ReleaseSafe optimisation. Output: `semantos.wasm`. Verify the same source files compile without modification.

**Acceptance criteria**:
- `zig build -Dtarget=wasm32-wasi` completes without errors
- `zig-cache/semantos.wasm` (or output path per build.zig) is a valid WASM module
- No conditional compilation needed in kernel source for WASM
- Same source files compile to both native .a and .wasm

### D30E.2 — WASM host import declarations

New file: `src/ffi/wasm_imports.zig`

Declares imported host functions matching the callback signatures. For WASM, callbacks are declared as extern imports (not function pointers). The WASM module's import table lists:
- `env.host_storage_read`, `env.host_storage_write`
- `env.host_identity_resolve`, `env.host_identity_derive`
- `env.host_anchor_submit`
- `env.host_network_publish`, `env.host_network_resolve`

**Acceptance criteria**:
- Module declares all 7 host imports with correct parameter/return types
- Import signatures match callback signatures from PHASE-30B
- WASM module imports table is validated (wasm-objdump or wasmtime)

### D30E.3 — WASM memory helpers

New file: `src/ffi/wasm_memory.zig`

Export functions for host-side memory management:
- `semantos_alloc(size)` → pointer — allocate in WASM linear memory
- `semantos_dealloc(ptr, size)` — free WASM memory

These let the host allocate buffers in WASM memory space before calling kernel functions.

**Acceptance criteria**:
- Both functions exported and callable from WASM host
- `semantos_alloc(1024)` returns a valid pointer within WASM linear memory bounds
- Round-trip: alloc → write data → read data → dealloc succeeds
- No memory leaks detected after repeated alloc/dealloc cycles

### D30E.4 — JavaScript host bindings (reference implementation)

New file: `src/ffi/host/js-host.js` (or `.ts`)

Reference JavaScript host that:
- Loads `semantos.wasm`
- Provides import implementations (using in-memory storage for testing)
- Demonstrates the copy-in/copy-out pattern
- Exercises all FFI functions through WASM

**Acceptance criteria**:
- JS host instantiates WASM module successfully
- All import functions implemented and callable
- Can call `semantos_version()` and receive result
- Storage adapter stores/retrieves data in JS Map
- All examples in docs/tutorials reference this implementation

### D30E.5 — WASM integration tests

New files:
- `src/ffi/tests/wasm_test.zig` (Zig-side)
- `src/ffi/tests/wasm_host_test.js` (host-side)

Tests:
- WASM module loads
- All exports present
- Memory alloc/dealloc round-trip
- Cell write/read through WASM
- Capability check through WASM imports

**Acceptance criteria**:
- Zig test suite compiles and runs with `zig build test`
- JS tests run with `node` or test runner (Jest, etc.)
- All 9 TDD Gate Tests pass

---

## TDD Gate Tests

- **T1**: `zig build -Dtarget=wasm32-wasi` produces valid .wasm file
- **T2**: WASM module exports all C ABI functions (semantos_init through semantos_last_error)
- **T3**: WASM module exports semantos_alloc and semantos_dealloc
- **T4**: WASM module declares all 7 host imports (env.host_*)
- **T5**: JS host can instantiate WASM module and call semantos_version()
- **T6**: Cell write/read round-trip works through WASM (data crosses linear memory correctly)
- **T7**: Capability check works through WASM host imports
- **T8**: WASM module size is under 2MB (ReleaseSafe)
- **T9**: Host cannot access kernel internal memory (only exported functions)

---

## Completion Criteria

1. All 5 deliverables (D30E.1–D30E.5) complete and merged to `phase-30e-wasm-target`
2. All 9 TDD Gate Tests pass
3. `zig build test` passes all WASM-related tests
4. JS test suite passes (no failures)
5. Documentation: WASM build instructions in README or docs/BUILDING.md
6. No conditional compilation flags in kernel source for WASM support
7. Module size tracked and under 2MB threshold
8. CI/CD pipeline validates WASM build on every commit to phase-30e-wasm-target
