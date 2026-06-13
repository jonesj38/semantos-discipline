---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30C-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.694684+00:00
---

# Phase 30C Execution Prompt — Capability & Linearity FFI Functions

> Paste this prompt into a fresh session to execute Phase 30C.

## Context

Phase 30A created the C ABI header skeleton. Phase 30B wired adapter callbacks into the kernel. Your task: expose capability-based access control and linear resource consumption through the FFI. These are the security invariants that make Semantos provably safe — the kernel enforces that a tradie can't read a PM's private notes, and that an approval token can't be spent twice.

By the end of Phase 30C, the core FFI surface (capability check, token generation, linear consume) will be ready. Phases 30E/F/G (platform packaging) depend on this.

---

## CRITICAL: READ THESE FILES FIRST

1. `docs/prd/PHASE-30C-CAPABILITY-FFI.md` — Your deliverables and acceptance tests
2. `docs/prd/PHASE-30B-ADAPTER-CALLBACKS.md` — Callback registry pattern, identity callbacks
3. `docs/prd/PHASE-30-FFI-MASTER.md` — Capability functions table, linearity model, error codes
4. `packages/protocol-types/src/identity.ts` — IdentityAdapter interface definition
5. `packages/protocol-types/src/constants.ts` — Linearity constants (LINEAR, AFFINE, RELEVANT)
6. `docs/prd/PHASE-26B-LOCAL-IDENTITY.md` — LocalIdentityAdapter implementation, offline capability validation
7. `docs/BRANCHING-AND-CI-POLICY.md` — Commit naming, branch rules, PR etiquette

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

1. **NO STUBS**: Every function must have a real implementation. Mock/stub callbacks are OK; fake function bodies are not.
2. **CAPABILITY TOKENS ARE OPAQUE**: The host never interprets token internals. You receive bytes from `semantos_capability_present()` and pass them back via `semantos_capability_check()`. The kernel validates. No "token = JSON string" shortcuts.
3. **LINEAR CONSUME IS ATOMIC**: No partial states. If the kernel crashes mid-consume, the cell is either fully consumed or untouched — never half-consumed. Your test must simulate crash recovery via mock storage.
4. **IDENTITY CALLBACKS MUST BE WIRED**: `semantos_capability_check()` must call through `host_identity_resolve` to validate the certificate. Test it by asserting the callback was invoked with the correct cert_id.
5. **NO EASY TESTS**: Verify actual token bytes. Test double-consume rejection. Simulate crash recovery. Don't just check "function returned 0".
6. **NO TESTS THAT MATCH BROKEN CODE**: If your implementation is buggy and your test passes, you've failed. Write tests FIRST that would catch real bugs (e.g., consuming the same path twice should fail; if your implementation doesn't reject it, the test must fail).
7. **CRASH RECOVERY IS NOT OPTIONAL**: `semantos_linear_consume()` must persist consumption state via StorageAdapter. Your test must verify that after a simulated crash (restart with existing storage), the second consume call is rejected. This is not a nice-to-have; it's the whole point of linearity.

---

## PART 0: GIT HYGIENE

**Assess current state**:
- Check `git status` — ensure working tree is clean
- Check `git log --oneline -5` — verify Phase 30B is merged (or current HEAD if still on phase-30b branch)
- Verify Phase 30B deliverables exist: `src/ffi/exports.zig` has callback functions

**Discard any unrelated work**:
- If there are untracked files or unstaged changes unrelated to Phase 30C, discard them: `git clean -fd` (after verifying with `git status`)

**Verify prerequisites**:
- Phase 30B callback registration functions must be in `src/ffi/exports.zig`
- Phase 26B LocalIdentityAdapter must exist at `src/adapters/identity/local.zig` or similar
- `packages/protocol-types/src/constants.ts` must define LINEAR, AFFINE, RELEVANT constants

**Create and switch to branch**:
```bash
git checkout -b phase-30c-capability-ffi
```

**Verify you're on the branch**:
```bash
git branch -v | grep phase-30c-capability-ffi
```

---

## Steps

### Step 1: Implement D30C.1 — Capability FFI functions

**File**: `src/ffi/exports.zig`

Add two functions:

```zig
pub export fn semantos_capability_check(cert_id: [*]const u8, cert_len: usize, domain_flag: u32) i32 {
    // TODO: Call host_identity_resolve callback to fetch certificate
    // Validate certificate is not expired
    // Check that certificate grants the requested domain_flag
    // Return: 0 on success
    //         SEMANTOS_ERR_DENIED if domain not granted
    //         SEMANTOS_ERR_EXPIRED if cert is expired
    //         other error codes as appropriate
}

pub export fn semantos_capability_present(cert_id: [*]const u8, cert_len: usize, domain_flag: u32, out_token: [*]u8, out_len: [*]usize) i32 {
    // TODO: Call host_identity_resolve callback to fetch certificate
    // Generate BRC-108 capability token bytes for this (cert, domain_flag) pair
    // Kernel allocates memory for token; write pointer to out_token, length to out_len
    // Return: 0 on success
    //         error code on failure (invalid cert, expired, etc.)
}
```

**Commit**:
```bash
git add src/ffi/exports.zig
git commit -m "phase-30c/D30C.1: capability FFI functions (capability_check, capability_present)"
```

---

### Step 2: Implement D30C.2 — Linearity FFI function

**File**: `src/ffi/exports.zig`

Add:

```zig
pub export fn semantos_linear_consume(path: [*]const u8, path_len: usize, consumer_cert: [*]const u8, cert_len: usize) i32 {
    // TODO: Look up the cell at (path) in kernel storage
    // Verify the cell is marked LINEAR (check constant from CONSTANTS)
    // Check StorageAdapter: has this (path, consumer_cert) pair been consumed before?
    // If yes: return SEMANTOS_ERR_ALREADY_CONSUMED
    // If no: write consumption record to StorageAdapter, then return 0
    // The write MUST complete before returning (atomicity guarantee)
}
```

**Key invariant**: If the kernel crashes after writing the consumption record but before returning, the next call to `semantos_linear_consume()` with the same path must check storage and reject it. This is the crash-recovery guarantee.

**Commit**:
```bash
git add src/ffi/exports.zig
git commit -m "phase-30c/D30C.2: linearity FFI function (linear_consume with atomicity)"
```

---

### Step 3: Implement D30C.3 — Identity callback wiring

**File**: `src/ffi/exports.zig` (or appropriate callback implementation file)

Verify that:
- `host_identity_resolve` callback is registered and callable from within `semantos_capability_check()`
- `host_identity_derive` callback is registered and callable from within `semantos_capability_present()`
- Both callbacks properly unmarshal the certificate from host memory

Wire the callback invocation into your capability functions:

```zig
// Inside semantos_capability_check:
const resolved_cert = semantos.callback_registry.host_identity_resolve(cert_id, cert_len);
if (resolved_cert == null) return SEMANTOS_ERR_CERT_NOT_FOUND;
// ... validate capability ...
```

**Commit**:
```bash
git add src/ffi/exports.zig
git commit -m "phase-30c/D30C.3: wire identity callbacks into capability functions"
```

---

### Step 4: Implement D30C.4 — Capability + linearity tests

**File**: `src/ffi/tests/capability_test.zig` (new file)

Create a test suite with the following test cases. Use mock callbacks where needed:

```zig
const std = @import("std");
const semantos = @import("../../../src/main.zig");

test "T1: capability_check returns 0 for granted domain flag" {
    // Setup: register mock identity callback that returns a valid cert with domain_flag granted
    // Call semantos_capability_check with cert_id, domain_flag
    // Assert: return value is 0
}

test "T2: capability_check returns SEMANTOS_ERR_DENIED for ungranted domain flag" {
    // Setup: register mock identity callback that returns a valid cert WITHOUT domain_flag
    // Call semantos_capability_check with cert_id, domain_flag
    // Assert: return value is SEMANTOS_ERR_DENIED
}

test "T3: capability_check returns SEMANTOS_ERR_EXPIRED for expired cert" {
    // Setup: register mock identity callback that returns an expired cert
    // Call semantos_capability_check with cert_id, domain_flag
    // Assert: return value is SEMANTOS_ERR_EXPIRED
}

test "T4: capability_present returns valid BRC-108 token bytes" {
    // Setup: register mock identity callback that returns a valid cert
    // Call semantos_capability_present with cert_id, domain_flag, out_token, out_len
    // Assert: return value is 0, out_len > 0, out_token is non-null and contains bytes
}

test "T5: token from capability_present can be verified externally" {
    // Call semantos_capability_present to get token bytes
    // Manually verify token structure: BRC-108 format check (e.g., magic bytes, length field, signature)
    // Assert: token has expected structure
}

test "T6: linear_consume returns 0 on first call" {
    // Setup: mock storage adapter
    // Call semantos_linear_consume(path, consumer_cert)
    // Assert: return value is 0
    // Assert: storage adapter recorded the consumption
}

test "T7: linear_consume returns SEMANTOS_ERR_ALREADY_CONSUMED on second call with same path" {
    // Setup: mock storage adapter with a pre-recorded consumption
    // Call semantos_linear_consume(path, consumer_cert) twice with same path
    // Assert: first call returns 0
    // Assert: second call returns SEMANTOS_ERR_ALREADY_CONSUMED
}

test "T8: linear consumption is atomic (simulated crash recovery)" {
    // Setup: mock storage adapter that persists consumption records
    // Call semantos_linear_consume(path, consumer_cert)
    // Simulate crash: destroy kernel instance, restore from storage
    // Call semantos_linear_consume(path, consumer_cert) again on restored instance
    // Assert: second call returns SEMANTOS_ERR_ALREADY_CONSUMED (proof of atomicity)
}

test "T9: capability_check with null cert_id returns error" {
    // Call semantos_capability_check(null, 0, domain_flag)
    // Assert: return value is an error code (not crash, not 0)
}

test "T10: linear_consume with non-LINEAR cell returns appropriate error" {
    // Setup: create a cell marked as AFFINE (not LINEAR)
    // Call semantos_linear_consume(path, consumer_cert)
    // Assert: return value is an error code (e.g., SEMANTOS_ERR_WRONG_LINEARITY)
}
```

**Commit**:
```bash
git add src/ffi/tests/capability_test.zig
git commit -m "phase-30c/D30C.4: capability + linearity test suite (10 TDD gate tests)"
```

---

## Completion Criteria

- [ ] All four deliverables (D30C.1-D30C.4) implemented
- [ ] All 10 TDD gate tests passing: `zig build test`
- [ ] Identity callback wiring verified: tests assert callback invocation
- [ ] Linearity atomicity validated: T8 simulates crash recovery and confirms double-consume is rejected
- [ ] Code review: no stubs, no fake implementations, no shortcuts
- [ ] Branch `phase-30c-capability-ffi` is up-to-date and ready for merge
- [ ] Commit history is clean: one commit per deliverable (4 commits total)

---

## Post-Phase: Errata Sprint

After Phase 30C is complete and merged:

1. **Review callback errors**: If identity callbacks return errors, do capability functions propagate them correctly? Add error handling if needed.
2. **Linearity edge cases**: What happens if StorageAdapter fails to persist? Add fallback/retry logic.
3. **Token size limits**: Are generated tokens bounded? Add max-size validation.
4. **Memory leaks**: Ensure kernel-allocated memory in capability_present is properly tracked for host-side deallocation.

These are post-merge follow-ups. Don't block Phase 30C on them, but track them as known issues.
