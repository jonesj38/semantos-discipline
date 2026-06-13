---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30E-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.721203+00:00
---

# Phase 30E Execution Prompt — WASM Target & Host Import Bindings

> Paste this prompt into a fresh session to execute Phase 30E.

## Context

The same Zig kernel source that produces native .a files also compiles to wasm32-wasi. The WASM module exposes the same C ABI functions as the native library. Host-provided imports supply adapter implementations. The WASM memory model: all data crosses the boundary via copy through WASM linear memory. The host allocates in WASM memory, copies data in, calls the function, copies the result out, then frees.

### The Boundary Rule

WASM linear memory is the only shared surface. The host cannot access kernel internal state. The kernel cannot access host memory. Every byte that crosses the boundary goes through explicit copy operations in WASM linear memory. This is MORE secure than native FFI because the sandbox enforces the boundary at the VM level.

---

## CRITICAL: READ THESE FILES FIRST

1. `docs/prd/PHASE-30-FFI-MASTER.md` — WASM target details, memory model, rationale
2. `docs/prd/PHASE-30D-ANCHOR-FFI.md` — Complete C ABI surface (all functions, signatures, error codes)
3. `docs/prd/PHASE-30B-ADAPTER-CALLBACKS.md` — Callback signatures (host_storage_read, host_identity_resolve, etc.)
4. `build.zig` — Current build configuration
5. `docs/BRANCHING-AND-CI-POLICY.md` — Commit naming convention

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

1. **NO STUBS**: Every function exported from the WASM module must be functional and testable. No placeholder implementations.
2. **SAME SOURCE**: Zero conditional compilation for WASM. The kernel source files that produce .a also produce .wasm without modification.
3. **COPY IN / COPY OUT**: Every byte that crosses the WASM boundary goes through explicit copy in WASM linear memory. This is the contract.
4. **JS HOST IS REAL**: The js-host.js is not a mock. It must instantiate the WASM module, provide all imports, and exercise all functions end-to-end.
5. **NO EASY TESTS**: Tests must verify behavior, not just that code compiles. Cell write → read must return identical bytes. Callbacks must receive correct arguments.
6. **MODULE SIZE MATTERS**: Track and report WASM module size. It must be under 2MB (ReleaseSafe). If it exceeds this, investigate and document why.
7. **WASI PREVIEW VERSION IS A DECISION**: Document which WASI preview version (e.g., wasi_snapshot_preview1) is used and why. This affects compatibility.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
git status
git log --oneline -10
git branch -a
```

What is the current state? Are you on a clean branch? Any uncommitted changes?

### 0.2 Commit or discard

If there are uncommitted changes:
- If they're relevant to Phase 30E, commit them to a feature branch first
- If they're not relevant, discard them: `git checkout -- .` (or reset)

### 0.3 Verify prerequisites

- Phase 30D must be merged and complete
- All C ABI functions from PHASE-30D must be in `src/` and `src/ffi/`
- `build.zig` must be stable and buildable with `zig build`
- Run `zig build` to verify the baseline compiles

### 0.4 Create branch

```bash
git checkout -b phase-30e-wasm-target
```

Verify you're on the new branch: `git branch`

---

## Step 1: WASM Build Target Configuration (D30E.1)

Commit: `phase-30e/D30E.1: add wasm32-wasi build target with ReleaseSafe`

### What to do

1. Open `build.zig`
2. Add a new target configuration for `wasm32-wasi`:
   - Optimize: `ReleaseSafe` (bounds checking enabled, assertions on)
   - Output: `.wasm` file in build output directory
   - Use the SAME source files as native build (no #ifdef, no conditional compilation)
3. Verify the build runs: `zig build -Dtarget=wasm32-wasi`
4. Check the output: `ls -lh zig-cache/` or wherever .wasm lands (should be under 2MB)
5. Validate the .wasm file: `wasm-objdump` or `wasmtime` (if available)

### Acceptance

- `zig build -Dtarget=wasm32-wasi` succeeds
- Output .wasm file exists and is valid
- No conditional compilation in kernel source
- Module size reported and documented

### Commit

```bash
git add build.zig
git commit -m "phase-30e/D30E.1: add wasm32-wasi build target with ReleaseSafe"
```

---

## Step 2: WASM Host Import Declarations (D30E.2)

Commit: `phase-30e/D30E.2: declare WASM host imports (env.*)`

### What to do

1. Create `src/ffi/wasm_imports.zig`
2. Declare all 7 host imports as `extern` functions:
   - `env.host_storage_read(path_ptr: *u8, path_len: usize, ...) -> i32`
   - `env.host_storage_write(path_ptr: *u8, path_len: usize, ...) -> i32`
   - `env.host_identity_resolve(cert_id_ptr: *u8, ...) -> i32`
   - `env.host_identity_derive(domain_flag: u32, ...) -> i32`
   - `env.host_anchor_submit(state_hash_ptr: *u8, ...) -> i32`
   - `env.host_network_publish(topic_ptr: *u8, ...) -> i32`
   - `env.host_network_resolve(query_ptr: *u8, ...) -> i32`
3. Signatures must match PHASE-30B callback definitions exactly
4. Use Zig's `extern` keyword for WASM import linkage
5. Link this module into the WASM build

### Acceptance

- `zig build -Dtarget=wasm32-wasi` includes wasm_imports.zig without error
- WASM module import table lists all 7 env.* functions (verify with wasm-objdump)
- Signatures match PHASE-30B callbacks

### Commit

```bash
git add src/ffi/wasm_imports.zig
git commit -m "phase-30e/D30E.2: declare WASM host imports (env.*)"
```

---

## Step 3: WASM Memory Helpers (D30E.3)

Commit: `phase-30e/D30E.3: export semantos_alloc and semantos_dealloc`

### What to do

1. Create `src/ffi/wasm_memory.zig`
2. Implement two exported functions:
   - `pub export fn semantos_alloc(size: usize) callconv(.C) ?*u8` — allocate `size` bytes in WASM linear memory, return pointer or null
   - `pub export fn semantos_dealloc(ptr: ?*u8, size: usize) callconv(.C) void` — free the allocation
3. Use Zig's standard allocator or a simple bump allocator suitable for WASM
4. Both functions callable from host via WASM exports
5. Test: host calls alloc(1024) → writes 1024 bytes → calls dealloc(ptr, 1024) → success

### Acceptance

- Both functions exported and in WASM export table
- `semantos_alloc(1024)` returns a non-null pointer
- Host can write data to the allocated buffer
- `semantos_dealloc(ptr, 1024)` succeeds without crash
- 100 cycles of alloc → write → dealloc show no memory leaks

### Commit

```bash
git add src/ffi/wasm_memory.zig
git commit -m "phase-30e/D30E.3: export semantos_alloc and semantos_dealloc"
```

---

## Step 4: JavaScript Host Bindings (D30E.4)

Commit: `phase-30e/D30E.4: implement reference JS host with all imports`

### What to do

1. Create `src/ffi/host/js-host.js` (or `.ts` if using TypeScript)
2. Implement a complete WASM host that:
   - Uses `WebAssembly.instantiate()` or `WebAssembly.instantiateStreaming()`
   - Loads the compiled `semantos.wasm` file
   - Provides all 7 import functions:
     - `host_storage_read`: In-memory Map storage, copy data to WASM buffer
     - `host_storage_write`: In-memory Map storage, copy data from WASM buffer
     - `host_identity_resolve`: Mock identity provider, return success
     - `host_identity_derive`: Mock key derivation, return derived material to WASM buffer
     - `host_anchor_submit`: Mock anchor submission, queue state hash
     - `host_network_publish`: Mock network publish, log event
     - `host_network_resolve`: Mock network query, return empty result or mock data
   - Exports a convenience function: `kernelVersion()` → calls `semantos_version()`, returns string
   - Exports convenience functions for write/read/capability checks
3. Document the copy-in/copy-out pattern in comments
4. Add example usage at end of file showing how to use the host

### Acceptance

- JS host loads and instantiates WASM module without error
- `kernelVersion()` returns version string (e.g., "0.1.0")
- Cell write → read round-trip works
- Storage adapter persists data across calls
- Callback functions are called with correct arguments

### Commit

```bash
git add src/ffi/host/js-host.js
git commit -m "phase-30e/D30E.4: implement reference JS host with all imports"
```

---

## Step 5: WASM Integration Tests (D30E.5)

Commit: `phase-30e/D30E.5: add WASM integration tests (Zig + JS)`

### What to do

1. Create `src/ffi/tests/wasm_test.zig`
   - Test: WASM build succeeds
   - Test: All C ABI exports present
   - Test: semantos_alloc/dealloc work
   - Test: Module size is under 2MB
   - Link against WASM build, not native

2. Create `src/ffi/tests/wasm_host_test.js`
   - Test: Load WASM module
   - Test: Call semantos_version() → receive version string
   - Test: Cell write/read round-trip
   - Test: Capability check through import callbacks
   - Test: Memory alloc/dealloc correctness
   - Test: Host cannot access kernel internals (only exported functions)
   - Use Node.js test framework (node --test, Jest, or similar)

3. Update `build.zig` test step to include wasm_test.zig
4. Add npm test script or makefile target for wasm_host_test.js

### Acceptance

- `zig build test` runs and passes wasm_test.zig
- `node src/ffi/tests/wasm_host_test.js` (or npm test) passes all JS tests
- All 9 TDD Gate Tests pass

### Commit

```bash
git add src/ffi/tests/wasm_test.zig src/ffi/tests/wasm_host_test.js
git commit -m "phase-30e/D30E.5: add WASM integration tests (Zig + JS)"
```

---

## Completion Criteria

1. All 5 deliverables (D30E.1–D30E.5) complete and committed
2. All 9 TDD Gate Tests pass
3. `zig build test` succeeds for all WASM tests
4. JS test suite passes without failure
5. WASM module size under 2MB (track in docs or build output)
6. WASI preview version documented (in build.zig or README)
7. Zero conditional compilation in kernel source
8. CI/CD validates WASM build on every commit

---

## Post-Phase: Errata Sprint

After Phase 30E merges to main:

1. **Code review**: Verify memory safety (no UAF, no buffer overflow in copy operations)
2. **Performance**: Profile WASM module startup and function call overhead
3. **Documentation**: Add WASM build instructions to README and tutorials
4. **Compatibility**: Test with multiple JavaScript runtimes (Node.js, browsers, deno, bun)
5. **Size optimization**: If module exceeds 2MB, investigate and optimize (strip debug info, use LTO)
6. **Security audit**: Confirm host cannot call unexported functions or access internal memory

---

## Notes

- WASM and native builds can coexist in the repo with no source changes
- The JS host is a reference implementation; production hosts (browsers, runtimes) will provide their own
- Memory management discipline is critical: every alloc must be freed
- Callback behavior must match native callbacks exactly (same return values, same side effects)
