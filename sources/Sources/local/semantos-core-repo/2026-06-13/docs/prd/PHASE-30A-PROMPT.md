---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30A-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.683814+00:00
---

# Phase 30A Execution Prompt — C ABI Header & Core FFI Functions

> Paste this prompt into a fresh session to execute Phase 30A.

## Context
You are working in the Semantos kernel (Zig). Phase 25A–25D established the kernel proof boundary and core subsystems (StorageAdapter, IdentityAdapter, AnchorAdapter). Your task is Phase 30A: create the C ABI header and implement core FFI functions so that external languages (Swift, Dart, JavaScript, etc.) can bind to the kernel.

This phase creates the flat C surface: no Zig-specific types, no exceptions, no complex memory ownership. Every function is callable from C and returns simple types (integers, byte buffers). The kernel's internal complexity stays behind the wall.

### The Boundary Rule
The C ABI header exposes ONLY flat C types. No Zig allocators, no Zig error unions, no comptime types. Every function is `export fn` with `callconv(.C)`. This is the contract all language bindings depend on.

---

## CRITICAL: READ THESE FILES FIRST
1. **PHASE-30A-C-ABI-HEADER.md** — Phase specification with deliverables D30A.1–D30A.4 and all 10 gate tests
2. **PHASE-30-FFI-MASTER.md** — FFI architecture, memory ownership model, and the complete C ABI surface
3. **src/kernel/cell_engine.zig** (or equivalent) — The kernel cell engine API that your FFI functions will wrap
4. **packages/protocol-types/src/constants.ts** — CELL_SIZE, magic numbers, and type constants
5. **docs/BRANCHING-AND-CI-POLICY.md** — Commit naming conventions, branch rules, CI requirements

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO STUBS
Every function does real work. No `@panic` placeholders, no `return 0 // TODO`, no functions that accept input but ignore it.
- `semantos_cell_write` must actually write data to kernel storage.
- `semantos_cell_read` must actually retrieve data and copy it to the output buffer.
- `semantos_last_error` must contain real error messages, not dummy text.

### 2. NO ZIG TYPES IN C HEADER
The header file (`semantos.h`) contains ONLY C types: `int32_t`, `uint8_t`, `size_t`, `const char*`, pointers to unsigned byte arrays.
- No `!u32`, no `error!T`, no custom Zig structs.
- Function signatures are callable from C; if a C compiler cannot parse it, you failed.

### 3. BOUNDS CHECK EVERYTHING
Every pointer and length parameter is validated.
- Null pointer input → return error, do not crash.
- Zero length on write → return error (minimum payload validation).
- Output buffer length too small → return SEMANTOS_ERR_BUFFER_TOO_SMALL and set required length.
- No buffer overflows, no undefined behavior.

### 4. NO HOST REFERENCES HELD
Each FFI call is a self-contained transaction. The kernel does not hold pointers to host-provided buffers after the function returns.
- Copy all host-provided data into kernel-owned memory before the function returns.
- Any kernel-allocated buffers returned to host are owned by the host (host calls `semantos_free` to release).
- No dangling pointers, no use-after-free.

### 5. NO EASY TESTS
Tests verify actual behavior, not just "function exists" or "does not crash."
- Gate Test 3: Actually write, then read back the same bytes. Verify content.
- Gate Test 1: Parse the config JSON, verify init state changes.
- Gate Test 7: Second init without shutdown must return SEMANTOS_ERR_ALREADY_INIT, not succeed.
- Tests call the C functions as if from external code; do not use Zig-only error handling or special testing shortcuts.

### 6. NO TESTS THAT MATCH BROKEN CODE
Do not write tests that pass against buggy implementations.
- If a function always returns success, and your test expects success, the test is useless.
- If a function ignores invalid input, and your test passes invalid input, the test is useless.
- Each test must have a clear failure case: what would cause this test to fail? If the answer is "nothing," rewrite the test.

---

## PART 0: GIT HYGIENE

### 0.1 Assess
```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```
Verify that working directory is clean or contains only expected work-in-progress.

### 0.2 Commit or discard uncommitted work
If there are staged or unstaged changes not related to Phase 30A, commit them explicitly by name or discard them.
```bash
git add <specific_files>
git commit -m "phase-xx/DXX.y: description"
```
Never use `git add -A` — be explicit about what you commit.

### 0.3 Verify prerequisites are complete
Phase 25A–25D must be complete. Check that these files exist:
```bash
ls -la src/kernel/cell_engine.zig
ls -la src/kernel/identity_adapter.zig
ls -la src/kernel/storage_adapter.zig
ls -la src/kernel/anchor_adapter.zig
ls -la packages/protocol-types/src/constants.ts
```
All files must exist and contain real implementations (not stubs). If anything is missing, STOP and complete prerequisites.

### 0.4 Create Phase 30A branch
```bash
git checkout -b phase-30a-c-abi-header
```

---

## Step 1: D30A.1 — Create semantos.h (C header)

**Objective**: Define the complete C API surface.

**Instructions**:
1. Create file `src/ffi/semantos.h`.
2. Include standard C headers (stdint.h, stddef.h, stdint.h for size_t).
3. Define `SemantosResult` as `typedef int32_t SemantosResult;`.
4. Define error codes enum with all 10 error constants (SEMANTOS_OK through SEMANTOS_ERR_EXPIRED).
5. Declare all 8 functions:
   - `semantos_init(const uint8_t* config_json, size_t config_len)`
   - `semantos_shutdown(void)`
   - `semantos_cell_write(const char* path, size_t path_len, const uint8_t* data, size_t data_len)`
   - `semantos_cell_read(const char* path, size_t path_len, uint8_t* out_data, size_t* inout_len)`
   - `semantos_cell_verify(const char* path, size_t path_len, const uint8_t* proof, size_t proof_len)`
   - `semantos_free(uint8_t* ptr, size_t len)`
   - `semantos_version(void)` returns `const char*`
   - `semantos_last_error(char* out_buf, size_t* inout_len)`
6. Add include guards and comments.
7. Verify the header compiles:
   ```bash
   gcc -c src/ffi/semantos.h -o /dev/null
   ```

**Commit**:
```bash
git add src/ffi/semantos.h
git commit -m "phase-30a/D30A.1: C ABI header with error codes and core function declarations"
```

---

## Step 2: D30A.2 & D30A.3 — Implement exports.zig (core FFI functions)

**Objective**: Implement the 8 FFI functions in Zig with C calling convention.

**Instructions**:
1. Create file `src/ffi/exports.zig`.
2. Import kernel subsystems (cell_engine, adapters, config parsing, error handling).
3. Declare thread-local state:
   ```zig
   threadlocal var is_initialized: bool = false;
   threadlocal var last_error_msg: [256]u8 = undefined;
   ```
4. Implement each function:
   - **`semantos_init`**:
     - Guard: if already initialized, return SEMANTOS_ERR_ALREADY_INIT.
     - Parse config_json as UTF-8 string; if invalid, return SEMANTOS_ERR_INVALID_JSON.
     - Initialize kernel subsystems (cell engine, adapters).
     - Set `is_initialized = true`.
     - Return SEMANTOS_OK or error code.
   - **`semantos_shutdown`**:
     - Guard: if not initialized, return SEMANTOS_ERR_NOT_INIT.
     - Clean up kernel subsystems.
     - Set `is_initialized = false`.
     - Return SEMANTOS_OK.
   - **`semantos_cell_write`**:
     - Guard: if not initialized, return SEMANTOS_ERR_NOT_INIT.
     - Bounds check: null path, null data → return error.
     - Bounds check: zero-length data → return error.
     - Copy path and data into kernel-owned buffers (do not hold host pointers).
     - Call kernel cell engine to write.
     - Return result code.
   - **`semantos_cell_read`**:
     - Guard: if not initialized, return SEMANTOS_ERR_NOT_INIT.
     - Bounds check: null path, null out_data, null inout_len → return error.
     - Call kernel cell engine to read by path.
     - If path not found, return SEMANTOS_ERR_NOT_FOUND.
     - If output buffer (*inout_len) is too small, set *inout_len to required length, return SEMANTOS_ERR_BUFFER_TOO_SMALL.
     - Copy read data into out_data, update *inout_len, return SEMANTOS_OK.
   - **`semantos_cell_verify`**:
     - Guard: if not initialized, return SEMANTOS_ERR_NOT_INIT.
     - Bounds check: null path, null proof → return error.
     - Copy proof into kernel-owned buffer.
     - Call proof verification subsystem.
     - Return result (SEMANTOS_OK or SEMANTOS_ERR_INVALID_PROOF, SEMANTOS_ERR_DENIED, etc.).
   - **`semantos_free`**:
     - Bounds check: null ptr → return (no-op).
     - Release kernel-allocated buffer (using kernel arena or free list).
     - No crash if ptr is invalid; if necessary, log and return.
   - **`semantos_version`**:
     - Return static null-terminated string matching build version.
     - Example: `"0.2.1-phase-30a\0"`.
   - **`semantos_last_error`**:
     - Bounds check: null out_buf, null inout_len → return error.
     - Copy thread-local error message into out_buf (up to *inout_len bytes).
     - If buffer too small, set *inout_len to required length, return SEMANTOS_ERR_BUFFER_TOO_SMALL.
     - Update *inout_len to actual bytes written.
     - Return SEMANTOS_OK.
5. Mark all functions with `export fn` and `callconv(.C)`.
6. Set `last_error_msg` on every error path so semantos_last_error has context.

**Commit**:
```bash
git add src/ffi/exports.zig
git commit -m "phase-30a/D30A.2-D30A.3: Core FFI functions with memory management and error handling"
```

---

## Step 3: D30A.4 — Implement test harness (core_test.zig)

**Objective**: Test all 10 gate tests. Do not use Zig error handling; call the C functions directly.

**Instructions**:
1. Create file `src/ffi/tests/core_test.zig`.
2. Define a minimal C test harness that calls the exported functions (as if from C).
3. Implement tests for all 10 gate tests:

   **Test 1: semantos_init with valid JSON returns SEMANTOS_OK**
   ```zig
   const config = "{\"version\":\"0.2.1\"}";
   const result = semantos_init(config.ptr, config.len);
   try std.testing.expectEqual(result, 0); // SEMANTOS_OK
   _ = semantos_shutdown();
   ```

   **Test 2: semantos_init with invalid JSON returns SEMANTOS_ERR_INVALID_JSON**
   ```zig
   const invalid = "{invalid json";
   const result = semantos_init(invalid.ptr, invalid.len);
   try std.testing.expectEqual(result, -2); // SEMANTOS_ERR_INVALID_JSON
   ```

   **Test 3: semantos_cell_write then semantos_cell_read returns identical bytes**
   ```zig
   const config = "{\"version\":\"0.2.1\"}";
   _ = semantos_init(config.ptr, config.len);

   const path = "/test/key";
   const data = "hello, world!";
   const wr = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);
   try std.testing.expectEqual(wr, 0);

   var buf: [64]u8 = undefined;
   var len: usize = buf.len;
   const rd = semantos_cell_read(path.ptr, path.len, &buf, &len);
   try std.testing.expectEqual(rd, 0);
   try std.testing.expectEqual(len, data.len);
   try std.testing.expectEqualSlices(u8, buf[0..len], data);

   _ = semantos_shutdown();
   ```

   **Test 4: semantos_cell_read on non-existent path returns SEMANTOS_ERR_NOT_FOUND**
   ```zig
   const config = "{\"version\":\"0.2.1\"}";
   _ = semantos_init(config.ptr, config.len);

   const path = "/nonexistent/path";
   var buf: [64]u8 = undefined;
   var len: usize = buf.len;
   const result = semantos_cell_read(path.ptr, path.len, &buf, &len);
   try std.testing.expectEqual(result, -1); // SEMANTOS_ERR_NOT_FOUND

   _ = semantos_shutdown();
   ```

   **Test 5: semantos_free does not crash**
   ```zig
   const config = "{\"version\":\"0.2.1\"}";
   _ = semantos_init(config.ptr, config.len);

   var buf: [64]u8 = undefined;
   semantos_free(&buf, 64);
   // If we reach here, no crash
   try std.testing.expect(true);

   _ = semantos_shutdown();
   ```

   **Test 6: semantos_version returns non-null string matching build version**
   ```zig
   const version = semantos_version();
   try std.testing.expect(version != null);
   const ver_str = std.mem.span(version.?);
   try std.testing.expect(ver_str.len > 0);
   try std.testing.expect(std.mem.startsWith(u8, ver_str, "0."));
   ```

   **Test 7: Double semantos_init returns SEMANTOS_ERR_ALREADY_INIT**
   ```zig
   const config = "{\"version\":\"0.2.1\"}";
   const r1 = semantos_init(config.ptr, config.len);
   try std.testing.expectEqual(r1, 0);

   const r2 = semantos_init(config.ptr, config.len);
   try std.testing.expectEqual(r2, -4); // SEMANTOS_ERR_ALREADY_INIT

   _ = semantos_shutdown();
   ```

   **Test 8: Any function before semantos_init returns SEMANTOS_ERR_NOT_INIT**
   ```zig
   // Do not call semantos_init
   const path = "/test";
   const data = "test";
   const result = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);
   try std.testing.expectEqual(result, -5); // SEMANTOS_ERR_NOT_INIT
   ```

   **Test 9: semantos_cell_write with null pointer returns error**
   ```zig
   const config = "{\"version\":\"0.2.1\"}";
   _ = semantos_init(config.ptr, config.len);

   const path = "/test";
   const result = semantos_cell_write(path.ptr, path.len, null, 10);
   try std.testing.expect(result != 0); // Some error code

   _ = semantos_shutdown();
   ```

   **Test 10: semantos_cell_write with zero-length data returns error**
   ```zig
   const config = "{\"version\":\"0.2.1\"}";
   _ = semantos_init(config.ptr, config.len);

   const path = "/test";
   const data = "something";
   const result = semantos_cell_write(path.ptr, path.len, data.ptr, 0);
   try std.testing.expect(result != 0); // Some error code

   _ = semantos_shutdown();
   ```

4. Group tests with clear names: `test "30A gate test 1: ..."`, etc.
5. Run tests:
   ```bash
   zig build test
   ```
   All 10 tests must pass.

**Commit**:
```bash
git add src/ffi/tests/core_test.zig
git commit -m "phase-30a/D30A.4: FFI integration test harness covering all 10 gate tests"
```

---

## Post-Step: Verify Completion Criteria
Before merging, verify each criterion:

- [ ] `src/ffi/semantos.h` exists and compiles with `gcc -c`
- [ ] `src/ffi/exports.zig` has 8 exported functions with `export fn` and `callconv(.C)`
- [ ] All functions bounds-check inputs
- [ ] No Zig-specific types in semantos.h
- [ ] Thread-local is_initialized and last_error_msg are maintained
- [ ] `src/ffi/tests/core_test.zig` has 10 named tests, all passing
- [ ] `zig build test` runs successfully with no failures
- [ ] All 3 commits created with proper naming

---

## Merge & Tag

```bash
git log --oneline -3  # Verify commits
git checkout main
git merge --no-ff phase-30a-c-abi-header -m "Merge phase-30a: C ABI header and core FFI functions"
git tag v0.30a
git push origin main v0.30a
```

---

## Post-Phase: Errata Sprint

In a fresh session, adversarially review the implementation:
1. Can you call semantos_cell_write with path_len=0? Does it handle it?
2. Can you call semantos_cell_read with a buffer that is legitimately too small? Does it set the required length?
3. Can you call semantos_shutdown() twice without init? Does it error?
4. Does semantos_last_error actually contain useful error messages, or is it always empty?
5. If you write, then read the same cell twice, do you get the same data both times?
6. What happens if config_json is not null-terminated? Is it handled by length parameter alone?

File any bugs as separate commits on main (or revert and re-fix on the branch, then re-merge).
