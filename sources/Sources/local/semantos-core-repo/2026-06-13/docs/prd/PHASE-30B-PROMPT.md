---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30B-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.662076+00:00
---

# Phase 30B Execution Prompt — Adapter Callback Registration & Storage Callbacks

> Paste this prompt into a fresh session to execute Phase 30B.

## Context
You are working in the Semantos kernel (Zig). Phase 30A created the C ABI header and core FFI functions (semantos_init, semantos_cell_write, semantos_cell_read, etc.). Your task is Phase 30B: implement callback registration and wire the storage callbacks so the kernel can call back into host code for I/O operations.

The kernel is pure and deterministic. It does not perform I/O directly. Instead, it invokes callbacks that the host has registered during init. When the kernel needs to read or write storage, it calls `host_storage_read` or `host_storage_write`. This phase establishes that callback mechanism.

### The Boundary Rule
Callbacks are synchronous from the kernel's perspective. The host may internally dispatch to async I/O, but the kernel blocks on the callback return. This keeps kernel execution simple and deterministic. Callback function pointers are C-compatible: no closures, no Zig error unions, no capturing. Each callback accepts only the parameters it needs and returns a status code.

---

## CRITICAL: READ THESE FILES FIRST
1. **PHASE-30B-ADAPTER-CALLBACKS.md** — Phase specification with deliverables D30B.1–D30B.4 and all 10 gate tests
2. **PHASE-30A-C-ABI-HEADER.md** — Phase 30A results; the C ABI header and core functions
3. **PHASE-30-FFI-MASTER.md** — FFI architecture, callback table with all 7 signatures, adapter directions, registration protocol
4. **packages/protocol-types/src/storage.ts** — StorageAdapter pattern, key/value semantics
5. **packages/protocol-types/src/identity.ts** — IdentityAdapter pattern (context for later phases)
6. **src/kernel/storage_adapter.zig** (or equivalent) — The kernel's storage layer that your callbacks will integrate with
7. **docs/BRANCHING-AND-CI-POLICY.md** — Commit naming conventions, branch rules, CI requirements

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO STUBS
Every callback implementation does real work. No `return 0 // TODO`, no empty functions.
- Mock callbacks in tests must actually manipulate state (e.g., store key-value pairs).
- StorageAdapter integration must actually invoke the registered callbacks, not hardcode responses.
- Null callback detection must prevent invocation, not silently succeed.

### 2. CALLBACKS ARE C-COMPATIBLE
Function pointer types use `callconv(.C)` and take only C types.
- No closures, no Zig error unions, no custom error sets that don't map to i32.
- If a function signature won't compile as a C function pointer, you failed.
- All 7 callback types are callable from C code.

### 3. SYNCHRONOUS ONLY
The kernel blocks on callback return. No async, no futures, no event dispatch.
- The host may internally use async I/O, but the callback function signature is synchronous.
- If you add `async` or `await` to a callback, you broke the boundary rule.
- Tests should verify that the kernel does not proceed until the callback returns.

### 4. NULL-SAFE
Every callback pointer is checked before invocation. Null callback → error, not crash.
- `if (callback_registry.host_storage_read == null) return SEMANTOS_ERR_DENIED;`
- Never dereference a null function pointer.
- Tests must verify null callback handling.

### 5. NO EASY TESTS
Tests verify actual behavior, not just "callback exists" or "does not crash."
- Test 2: Write data → verify host_storage_write is called with exact key and data.
- Test 3: Read data → verify host_storage_read is called, kernel returns host-provided bytes.
- Test 7: Register twice → second call must fail, not succeed.
- Each test must have a failure case.

### 6. NO TESTS THAT MATCH BROKEN CODE
Do not write tests that pass against buggy implementations.
- If storage_adapter always returns success without calling the callback, your test should fail.
- If re-registration is allowed, your test should fail.
- Each test is only valid if the corresponding code change would cause it to fail.

### 7. REGISTRY IS IMMUTABLE AFTER INIT
Once callbacks are registered, they cannot be re-registered.
- Gate Test 7 verifies this: second registration returns SEMANTOS_ERR_ALREADY_INIT.
- After semantos_shutdown, callbacks may be re-registered on next init.

---

## PART 0: GIT HYGIENE

### 0.1 Assess
```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```
Verify working directory is clean or contains only expected work-in-progress.

### 0.2 Commit or discard uncommitted work
If there are changes not related to Phase 30B, commit them explicitly by name or discard them.
```bash
git add <specific_files>
git commit -m "phase-xx/DXX.y: description"
```
Never use `git add -A`.

### 0.3 Verify prerequisites are complete
Phase 30A must be complete and merged to main. Check:
```bash
git log --oneline main | head -5  # Should show Phase 30A merge commit
ls -la src/ffi/semantos.h
ls -la src/ffi/exports.zig
ls -la src/ffi/tests/core_test.zig
zig build test  # Phase 30A tests should pass
```

### 0.4 Create Phase 30B branch
```bash
git checkout main
git pull origin main
git checkout -b phase-30b-adapter-callbacks
```

---

## Step 1: D30B.1 — Define callback type definitions (callbacks.zig)

**Objective**: Define all 7 C-compatible callback function pointer types.

**Instructions**:
1. Create file `src/ffi/callbacks.zig`.
2. Define the `CallbackRegistry` struct with fields for all 7 callback pointers:
   ```zig
   pub const CallbackRegistry = struct {
       host_storage_read: ?*const fn (
           key: [*:0]const u8,
           key_len: usize,
           out_buf: [*]u8,
           inout_len: [*]usize,
       ) callconv(.C) i32 = null,

       host_storage_write: ?*const fn (
           key: [*:0]const u8,
           key_len: usize,
           data: [*:0]const u8,
           data_len: usize,
       ) callconv(.C) i32 = null,

       host_identity_resolve: ?*const fn (
           cert_id: [*]const u8,
           cert_len: usize,
           out_json: [*]u8,
           inout_len: [*]usize,
       ) callconv(.C) i32 = null,

       host_identity_derive: ?*const fn (
           parent_cert: [*:0]const u8,
           cert_len: usize,
           resource_id: [*:0]const u8,
           rid_len: usize,
           domain_flag: u32,
           out_json: [*]u8,
           inout_len: [*]usize,
       ) callconv(.C) i32 = null,

       host_anchor_submit: ?*const fn (
           state_hash: [*]const u8,
           hash_len: usize,
           metadata_json: [*:0]const u8,
           meta_len: usize,
           out_proof: [*]u8,
           inout_len: [*]usize,
       ) callconv(.C) i32 = null,

       host_network_publish: ?*const fn (
           object_json: [*:0]const u8,
           json_len: usize,
       ) callconv(.C) i32 = null,

       host_network_resolve: ?*const fn (
           query_json: [*:0]const u8,
           json_len: usize,
           out_results: [*]u8,
           inout_len: [*]usize,
       ) callconv(.C) i32 = null,
   };
   ```
3. Define thread-local registry and registration state:
   ```zig
   threadlocal var callback_registry: CallbackRegistry = .{};
   threadlocal var callbacks_registered: bool = false;
   ```
4. Add documentation comments for each callback explaining its purpose.

**Commit**:
```bash
git add src/ffi/callbacks.zig
git commit -m "phase-30b/D30B.1: Callback type definitions for all 7 adapter interfaces"
```

---

## Step 2: D30B.2 — Implement callback registry and registration function

**Objective**: Create the callback registration mechanism.

**Instructions**:
1. In `src/ffi/callbacks.zig`, add the `semantos_register_callbacks` function:
   ```zig
   pub export fn semantos_register_callbacks(
       storage_read: ?*const fn (...) callconv(.C) i32,
       storage_write: ?*const fn (...) callconv(.C) i32,
       identity_resolve: ?*const fn (...) callconv(.C) i32,
       identity_derive: ?*const fn (...) callconv(.C) i32,
       anchor_submit: ?*const fn (...) callconv(.C) i32,
       network_publish: ?*const fn (...) callconv(.C) i32,
       network_resolve: ?*const fn (...) callconv(.C) i32,
   ) i32
   ```
2. Implementation:
   - If `callbacks_registered == true`, return SEMANTOS_ERR_ALREADY_INIT
   - Store all 7 pointers in `callback_registry`
   - Set `callbacks_registered = true`
   - Return SEMANTOS_OK
3. Add helper function to reset registry on shutdown (called from semantos_shutdown in exports.zig):
   ```zig
   pub fn reset_callbacks() void {
       callback_registry = .{};
       callbacks_registered = false;
   }
   ```
4. Add getter function for internal kernel use:
   ```zig
   pub fn get_registry() *const CallbackRegistry {
       return &callback_registry;
   }
   ```
5. Add checks in semantos_shutdown (in exports.zig) to reset callbacks:
   ```zig
   pub export fn semantos_shutdown() i32 {
       // ... existing shutdown code ...
       callbacks.reset_callbacks();
       return SEMANTOS_OK;
   }
   ```

**Commit**:
```bash
git add src/ffi/callbacks.zig src/ffi/exports.zig
git commit -m "phase-30b/D30B.2: Callback registry and semantos_register_callbacks export"
```

---

## Step 3: D30B.3 — Wire storage callbacks into kernel storage adapter

**Objective**: Connect the registered callbacks to the kernel's storage operations.

**Instructions**:
1. Modify `src/kernel/storage_adapter.zig` (or equivalent storage layer):
   - Import callbacks module: `const callbacks = @import("../ffi/callbacks.zig");`
2. For the storage read operation:
   ```zig
   pub fn read(allocator: std.mem.Allocator, key: []const u8) ![]u8 {
       const registry = callbacks.get_registry();
       if (registry.host_storage_read == null) {
           return error.StorageCallbackNotRegistered;  // Maps to SEMANTOS_ERR_DENIED
       }

       // Allocate output buffer (kernel-owned)
       var out_buf = try allocator.alloc(u8, MAX_CELL_SIZE);
       var out_len = out_buf.len;

       // Call host callback
       const result = registry.host_storage_read.?(
           key.ptr, key.len,
           out_buf.ptr, &out_len
       );

       if (result != 0) {
           allocator.free(out_buf);
           return error.HostCallbackFailed;  // Maps to callback error code
       }

       // Kernel now owns the buffer; return the slice
       return out_buf[0..out_len];
   }
   ```
3. For the storage write operation:
   ```zig
   pub fn write(key: []const u8, data: []const u8) !void {
       const registry = callbacks.get_registry();
       if (registry.host_storage_write == null) {
           return error.StorageCallbackNotRegistered;
       }

       const result = registry.host_storage_write.?(
           key.ptr, key.len,
           data.ptr, data.len
       );

       if (result != 0) {
           return error.HostCallbackFailed;
       }
   }
   ```
4. Ensure that semantos_cell_write and semantos_cell_read route through these functions.
5. Map Zig errors back to FFI error codes:
   - `error.StorageCallbackNotRegistered` → SEMANTOS_ERR_DENIED
   - `error.HostCallbackFailed` → propagate callback's error code

**Commit**:
```bash
git add src/kernel/storage_adapter.zig
git commit -m "phase-30b/D30B.3: Storage adapter integration with host callbacks"
```

---

## Step 4: D30B.4 — Implement callback round-trip tests

**Objective**: Test the full round-trip with mock callbacks.

**Instructions**:
1. Create file `src/ffi/tests/callback_test.zig`.
2. Define mock C callbacks in Zig:
   ```zig
   var mock_storage_data: std.StringHashMap([]u8) = undefined;
   var mock_callback_invoked: bool = false;

   fn mock_storage_write(
       key: [*:0]const u8,
       key_len: usize,
       data: [*:0]const u8,
       data_len: usize,
   ) callconv(.C) i32 {
       mock_callback_invoked = true;
       // Store key-value pair in mock_storage_data
       const key_slice = key[0..key_len];
       const data_slice = data[0..data_len];
       mock_storage_data.put(key_slice, data_slice) catch return -1;
       return 0;  // Success
   }

   fn mock_storage_read(
       key: [*:0]const u8,
       key_len: usize,
       out_buf: [*]u8,
       inout_len: [*]usize,
   ) callconv(.C) i32 {
       mock_callback_invoked = true;
       const key_slice = key[0..key_len];
       const stored = mock_storage_data.get(key_slice) orelse return -1;  // Not found
       if (stored.len > inout_len.*) {
           inout_len.* = stored.len;
           return -6;  // SEMANTOS_ERR_BUFFER_TOO_SMALL
       }
       std.mem.copy(u8, out_buf[0..stored.len], stored);
       inout_len.* = stored.len;
       return 0;
   }
   ```
3. Implement all 10 gate tests:

   **Test 1: Register callbacks successfully**
   ```zig
   test "30B gate test 1: register callbacks stores them" {
       const config = "{\"version\":\"0.2.1\"}";
       _ = semantos_init(config.ptr, config.len);

       const result = semantos_register_callbacks(
           @ptrCast(&mock_storage_read),
           @ptrCast(&mock_storage_write),
           null, null, null, null, null
       );
       try std.testing.expectEqual(result, 0);

       _ = semantos_shutdown();
   }
   ```

   **Test 2: storage_write callback is triggered**
   ```zig
   test "30B gate test 2: semantos_cell_write triggers callback" {
       mock_storage_data = std.StringHashMap([]u8).init(std.testing.allocator);
       defer mock_storage_data.deinit();

       const config = "{\"version\":\"0.2.1\"}";
       _ = semantos_init(config.ptr, config.len);

       _ = semantos_register_callbacks(
           @ptrCast(&mock_storage_read),
           @ptrCast(&mock_storage_write),
           null, null, null, null, null
       );

       mock_callback_invoked = false;
       const path = "/test/key";
       const data = "hello, world!";
       const result = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);

       try std.testing.expectEqual(result, 0);
       try std.testing.expect(mock_callback_invoked);

       _ = semantos_shutdown();
   }
   ```

   **Test 3: storage_read returns host-provided data**
   ```zig
   test "30B gate test 3: semantos_cell_read calls callback and returns data" {
       mock_storage_data = std.StringHashMap([]u8).init(std.testing.allocator);
       defer mock_storage_data.deinit();

       const config = "{\"version\":\"0.2.1\"}";
       _ = semantos_init(config.ptr, config.len);

       _ = semantos_register_callbacks(
           @ptrCast(&mock_storage_read),
           @ptrCast(&mock_storage_write),
           null, null, null, null, null
       );

       // Write first to populate mock storage
       const path = "/test/key";
       const data = "hello, world!";
       _ = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);

       // Now read it back
       var buf: [64]u8 = undefined;
       var len: usize = buf.len;
       const result = semantos_cell_read(path.ptr, path.len, &buf, &len);

       try std.testing.expectEqual(result, 0);
       try std.testing.expectEqual(len, data.len);
       try std.testing.expectEqualSlices(u8, buf[0..len], data);

       _ = semantos_shutdown();
   }
   ```

   **Test 4: Null storage_write callback returns error**
   ```zig
   test "30B gate test 4: null storage_write callback returns error" {
       const config = "{\"version\":\"0.2.1\"}";
       _ = semantos_init(config.ptr, config.len);

       _ = semantos_register_callbacks(null, null, null, null, null, null, null);

       const path = "/test";
       const data = "test";
       const result = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);

       try std.testing.expect(result != 0);  // Should be error

       _ = semantos_shutdown();
   }
   ```

   **Test 5: Null storage_read callback returns error**
   ```zig
   test "30B gate test 5: null storage_read callback returns error" {
       const config = "{\"version\":\"0.2.1\"}";
       _ = semantos_init(config.ptr, config.len);

       _ = semantos_register_callbacks(null, null, null, null, null, null, null);

       const path = "/test";
       var buf: [64]u8 = undefined;
       var len: usize = buf.len;
       const result = semantos_cell_read(path.ptr, path.len, &buf, &len);

       try std.testing.expect(result != 0);  // Should be error

       _ = semantos_shutdown();
   }
   ```

   **Test 6: All 7 callback types can be registered independently**
   ```zig
   test "30B gate test 6: all callback types can be registered" {
       const config = "{\"version\":\"0.2.1\"}";
       _ = semantos_init(config.ptr, config.len);

       const result = semantos_register_callbacks(
           @ptrCast(&mock_storage_read),
           @ptrCast(&mock_storage_write),
           @ptrCast(&mock_storage_read),  // reuse for test
           @ptrCast(&mock_storage_write),
           @ptrCast(&mock_storage_read),
           @ptrCast(&mock_storage_write),
           @ptrCast(&mock_storage_read)
       );
       try std.testing.expectEqual(result, 0);

       _ = semantos_shutdown();
   }
   ```

   **Test 7: Re-registration returns error**
   ```zig
   test "30B gate test 7: re-registration returns error" {
       const config = "{\"version\":\"0.2.1\"}";
       _ = semantos_init(config.ptr, config.len);

       _ = semantos_register_callbacks(
           @ptrCast(&mock_storage_read),
           @ptrCast(&mock_storage_write),
           null, null, null, null, null
       );

       const result = semantos_register_callbacks(
           @ptrCast(&mock_storage_read),
           @ptrCast(&mock_storage_write),
           null, null, null, null, null
       );
       try std.testing.expectEqual(result, -4);  // SEMANTOS_ERR_ALREADY_INIT

       _ = semantos_shutdown();
   }
   ```

   **Test 8: Callback returning error code propagates**
   ```zig
   fn mock_storage_write_fail(...) callconv(.C) i32 {
       return -8;  // SEMANTOS_ERR_DENIED
   }

   test "30B gate test 8: callback error propagates" {
       const config = "{\"version\":\"0.2.1\"}";
       _ = semantos_init(config.ptr, config.len);

       _ = semantos_register_callbacks(
           null,
           @ptrCast(&mock_storage_write_fail),
           null, null, null, null, null
       );

       const path = "/test";
       const data = "test";
       const result = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);

       try std.testing.expectEqual(result, -8);

       _ = semantos_shutdown();
   }
   ```

   **Test 9: Callback with null key pointer returns error**
   ```zig
   test "30B gate test 9: callback null-safety" {
       const config = "{\"version\":\"0.2.1\"}";
       _ = semantos_init(config.ptr, config.len);

       _ = semantos_register_callbacks(
           @ptrCast(&mock_storage_read),
           @ptrCast(&mock_storage_write),
           null, null, null, null, null
       );

       // This should be prevented by bounds checking in exports.zig
       const result = semantos_cell_write(null, 5, "test".ptr, 4);
       try std.testing.expect(result != 0);

       _ = semantos_shutdown();
   }
   ```

   **Test 10: Callback after shutdown can re-register**
   ```zig
   test "30B gate test 10: callbacks reset after shutdown" {
       const config = "{\"version\":\"0.2.1\"}";
       _ = semantos_init(config.ptr, config.len);

       _ = semantos_register_callbacks(
           @ptrCast(&mock_storage_read),
           @ptrCast(&mock_storage_write),
           null, null, null, null, null
       );

       _ = semantos_shutdown();

       // Re-init and re-register should succeed
       _ = semantos_init(config.ptr, config.len);
       const result = semantos_register_callbacks(
           @ptrCast(&mock_storage_read),
           @ptrCast(&mock_storage_write),
           null, null, null, null, null
       );
       try std.testing.expectEqual(result, 0);

       _ = semantos_shutdown();
   }
   ```

4. Run tests:
   ```bash
   zig build test
   ```
   All 10 tests must pass.

**Commit**:
```bash
git add src/ffi/tests/callback_test.zig
git commit -m "phase-30b/D30B.4: Callback round-trip tests with mock C callbacks"
```

---

## Post-Step: Verify Completion Criteria
Before merging, verify each criterion:

- [ ] `src/ffi/callbacks.zig` has all 7 callback type definitions with `callconv(.C)`
- [ ] `semantos_register_callbacks()` is exported and callable from C
- [ ] Registry is thread-local and immutable after registration
- [ ] `semantos_shutdown()` calls `callbacks.reset_callbacks()`
- [ ] `src/kernel/storage_adapter.zig` calls registered callbacks on read/write
- [ ] Null callback pointers are checked before invocation
- [ ] `src/ffi/tests/callback_test.zig` has 10 named tests, all passing
- [ ] `zig build test` runs successfully with no failures
- [ ] All 4 commits created with proper naming
- [ ] No stubs, no hardcoded responses

---

## Merge & Tag

```bash
git log --oneline -5  # Verify commits
git checkout main
git merge --no-ff phase-30b-adapter-callbacks -m "Merge phase-30b: Adapter callback registration and storage integration"
git tag v0.30b
git push origin main v0.30b
```

---

## Post-Phase: Errata Sprint

In a fresh session, adversarially review the implementation:
1. Can you register a callback that is actually a null pointer cast to a function pointer? Does it crash?
2. If a callback modifies the callback registry during invocation, what happens? (Should not be possible, but test it.)
3. If host_storage_write callback returns SEMANTOS_ERR_NOT_FOUND, does the kernel propagate it?
4. Can you call semantos_register_callbacks directly before semantos_init? Should it fail? (Test it.)
5. Does the mock storage in tests persist across multiple calls, or does it reset?
6. If you write to /path/key and then read from /path/key2, does the mock storage distinguish them?
7. What if a callback returns a very large error code (e.g., i32::MAX)? Is it propagated correctly?

File any bugs as separate commits on main (or revert and re-fix on the branch, then re-merge).
