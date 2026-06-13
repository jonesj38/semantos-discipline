---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-3-ERRATA-FIX-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.716864+00:00
---

# Phase 3 Errata Fix Prompt

**Purpose**: Fix the 5 critical bugs identified in the Phase 3 post-implementation review.
**Prerequisites**: Read `docs/prd/PHASE-3-2PDA-CORE.md` errata section (E-P3.9 through E-P3.14).
**Scope**: Bug fixes and test additions only. No new features.

---

## Fix Order (dependencies flow downward)

### Fix 1: Branch skip bug — `executor.zig` (E-P3.9 + E-P3.10)

**Problem**: Direct push opcodes (0x01-0x4B) and PUSHDATA1/2/4 in false IF/ELSE branches don't advance `pc` past the data bytes. The data bytes are then misinterpreted as opcodes.

**File**: `packages/cell-engine/src/executor.zig`

**Fix for direct push (lines ~242-248)**:
```zig
// Direct push: 0x01-0x4B (push next N bytes)
if (opcode >= 0x01 and opcode <= 0x4B) {
    const n: u32 = opcode;
    if (!ctx.executing) {
        ctx.pc += n;  // skip past data bytes even in false branch
        return;
    }
    if (ctx.pc + n > ctx.currentScriptLen()) return error.invalid_pushdata;
    try ctx.pda.spush(script[ctx.pc .. ctx.pc + n]);
    ctx.pc += n;
    return;
}
```

**Fix for PUSHDATA1 (lines ~252-263)**:
```zig
if (opcode == standard.OP_PUSHDATA1) {
    if (ctx.pc >= ctx.currentScriptLen()) return error.invalid_pushdata;
    const n: u32 = script[ctx.pc];
    ctx.pc += 1;
    if (!ctx.executing) {
        ctx.pc += n;  // skip past data bytes
        return;
    }
    if (ctx.pc + n > ctx.currentScriptLen()) return error.invalid_pushdata;
    try ctx.pda.spush(script[ctx.pc .. ctx.pc + n]);
    ctx.pc += n;
    return;
}
```

**Fix for PUSHDATA2 (lines ~265-276)**:
```zig
if (opcode == standard.OP_PUSHDATA2) {
    if (ctx.pc + 2 > ctx.currentScriptLen()) return error.invalid_pushdata;
    const n: u32 = std.mem.readInt(u16, script[ctx.pc..][0..2], .little);
    ctx.pc += 2;
    if (!ctx.executing) {
        ctx.pc += n;
        return;
    }
    if (ctx.pc + n > ctx.currentScriptLen()) return error.invalid_pushdata;
    try ctx.pda.spush(script[ctx.pc .. ctx.pc + n]);
    ctx.pc += n;
    return;
}
```

**Fix for PUSHDATA4 (lines ~278-289)**:
Same pattern — read the 4-byte length, advance `pc` by 4, then if not executing advance `pc` by `n` and return.

**New tests** — add to `tests/executor_conformance.zig`:

```zig
test "direct push in false IF branch skips data bytes" {
    // Script: OP_0 OP_IF OP_PUSHBYTES_3 0xAA 0xBB 0xCC OP_ELSE OP_1 OP_ENDIF
    // Expected: false branch skips the 3-byte push, executes OP_1 from ELSE
    const script = [_]u8{
        0x00,       // OP_0 (false)
        0x63,       // OP_IF
        0x03,       // OP_PUSHBYTES_3
        0xAA, 0xBB, 0xCC,  // 3 data bytes (must be skipped)
        0x67,       // OP_ELSE
        0x51,       // OP_1
        0x68,       // OP_ENDIF
    };
    // ... execute and verify stack top == 1
}

test "PUSHDATA1 in false IF branch skips length and data bytes" {
    // Script: OP_0 OP_IF PUSHDATA1 0x02 0xDE 0xAD OP_ELSE OP_1 OP_ENDIF
    const script = [_]u8{
        0x00,       // OP_0
        0x63,       // OP_IF
        0x4C,       // PUSHDATA1
        0x02,       // length = 2
        0xDE, 0xAD, // 2 data bytes
        0x67,       // OP_ELSE
        0x51,       // OP_1
        0x68,       // OP_ENDIF
    };
    // ... execute and verify stack top == 1
}
```

**Verification**: Run `zig build test-executor`. Both new tests must pass.

---

### Fix 2: hashOutputs stack overflow — `sighash.zig` (E-P3.11)

**Problem**: `computeSigHash` allocates `MAX_OUTPUTS * 10008 = 2.56MB` on the WASM stack (256KB limit). Will crash for any transaction.

**File**: `packages/cell-engine/src/sighash.zig`

**Fix**: Replace buffer-then-hash with streaming double-SHA256. This requires adding incremental SHA256 to `host.zig`.

**Step 2a — Add streaming SHA256 to `host.zig`**:

For native builds, wrap `std.crypto.hash.sha2.Sha256`. For WASM builds, you have two options:
- Option A (simpler): Use a fixed-size temp buffer (e.g., 4KB) and hash outputs one at a time, accumulating into a single incremental hasher. This works because the Zig std SHA256 is available in freestanding WASM (it's pure Zig, no libc needed).
- Option B: Add new host extern functions for incremental hashing.

**Recommendation**: Option A. The Zig std `Sha256` works on freestanding WASM — it's already used by `host.sha256()` in the native path and only needs `@import("std")`. Use it directly:

```zig
// In sighash.zig — replace the hashOutputs block:
const Sha256 = @import("std").crypto.hash.sha2.Sha256;

// hashOutputs — SIGHASH_ALL: hash all outputs using streaming hasher
if (base_type == SIGHASH_ALL) {
    var hasher = Sha256.init(.{});
    var i: u32 = 0;
    while (i < tx.output_count) : (i += 1) {
        var val_buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &val_buf, tx.outputs[i].value, .little);
        hasher.update(&val_buf);
        var vi_buf: [9]u8 = undefined;
        const vi_len = writeVarInt(&vi_buf, tx.outputs[i].script_len);
        hasher.update(vi_buf[0..vi_len]);
        hasher.update(tx.outputs[i].script[0..tx.outputs[i].script_len]);
    }
    var first_hash: [32]u8 = undefined;
    hasher.final(&first_hash);
    // Double SHA256
    var second_hasher = Sha256.init(.{});
    second_hasher.update(&first_hash);
    second_hasher.final(preimage[pos..][0..32]);
}
```

**Also fix hashPrevouts and hashSequence** if they use large stack buffers. Check `MAX_INPUTS * 36` and `MAX_INPUTS * 4` — at 256 inputs these are 9KB and 1KB respectively, which fit in 256KB stack. But convert to streaming anyway for safety.

**Verification**: `zig build test-executor` still passes. Then run the new WASM integration test (Fix 4).

---

### Fix 3: OP_2OVER and OP_2ROT dispatch — `standard.zig` + `pda.zig` (E-P3.13)

**Problem**: OP_2OVER (0x70) and OP_2ROT (0x71) are declared as constants but not in the switch dispatch.

**File**: `packages/cell-engine/src/opcodes/standard.zig`, `packages/cell-engine/src/pda.zig`

**Step 3a — Add PDA methods**:

```zig
// In pda.zig:

/// OP_2OVER: copy 3rd and 4th items to top
/// Stack: x1 x2 x3 x4 → x1 x2 x3 x4 x1 x2
pub fn s2over(self: *PDA) !void {
    if (self.main_sp < 4) return error.stack_underflow;
    // 3rd from top = sp-3, 4th from top = sp-4
    const a = self.main_stack[self.main_sp - 4]; // x1 (deepest of the 4)
    const b = self.main_stack[self.main_sp - 3]; // x2
    try self.spush(a.data[0..a.len]);
    try self.spush(b.data[0..b.len]);
}

/// OP_2ROT: move 5th and 6th items to top
/// Stack: x1 x2 x3 x4 x5 x6 → x3 x4 x5 x6 x1 x2
pub fn s2rot(self: *PDA) !void {
    if (self.main_sp < 6) return error.stack_underflow;
    // Save x1 and x2 (deepest pair)
    const x1 = self.main_stack[self.main_sp - 6];
    const x2 = self.main_stack[self.main_sp - 5];
    // Shift x3,x4,x5,x6 down by 2
    self.main_stack[self.main_sp - 6] = self.main_stack[self.main_sp - 4]; // x3
    self.main_stack[self.main_sp - 5] = self.main_stack[self.main_sp - 3]; // x4
    self.main_stack[self.main_sp - 4] = self.main_stack[self.main_sp - 2]; // x5
    self.main_stack[self.main_sp - 3] = self.main_stack[self.main_sp - 1]; // x6
    // Place x1, x2 on top
    self.main_stack[self.main_sp - 2] = x1;
    self.main_stack[self.main_sp - 1] = x2;
}
```

**NOTE on aliasing**: `s2over` pushes copies (via `spush` which does `@memcpy`), so it's safe. `s2rot` only moves `StackEntry` structs within the same array — the `.data` field is a length + inline array, not a pointer, so this is also safe. Verify the `StackEntry` struct before implementing.

**Step 3b — Add dispatch**:

```zig
// In standard.zig, in the stack manipulation switch:
OP_2OVER => return p.s2over(),
OP_2ROT => return p.s2rot(),
```

**Step 3c — Add tests** to `tests/opcodes_conformance.zig`:

```zig
test "OP_2OVER copies 3rd and 4th to top" {
    // Push 1,2,3,4 → OP_2OVER → expect 1,2,3,4,1,2
}

test "OP_2ROT moves 5th and 6th to top" {
    // Push 1,2,3,4,5,6 → OP_2ROT → expect 3,4,5,6,1,2
}

test "OP_2OVER underflow with < 4 items" {
    // Push 1,2,3 → OP_2OVER → expect stack_underflow error
}

test "OP_2ROT underflow with < 6 items" {
    // Push 1,2,3,4,5 → OP_2ROT → expect stack_underflow error
}
```

**Verification**: `zig build test-opcodes` passes.

---

### Fix 4: SIGHASH WASM integration test (E-P3.12)

**Problem**: No test exercises `kernel_load_tx_context` + `OP_CHECKSIG` through the WASM binary.

**File**: `packages/cell-engine/tests-ts/kernel_compat.test.ts`

**Prerequisite**: Fix 2 (hashOutputs) must be applied first, or this test will crash.

**Test outline**:

```typescript
test("kernel_load_tx_context + OP_CHECKSIG smoke test", async () => {
    // 1. Construct a minimal BSV transaction with 1 input, 1 output
    // 2. Create a P2PKH locking script: OP_DUP OP_HASH160 <pubkeyhash> OP_EQUALVERIFY OP_CHECKSIG
    // 3. Create an unlock script: <sig> <pubkey>
    // 4. Serialize the transaction to bytes
    // 5. Call kernel_load_tx_context(tx_bytes, tx_len, 0, input_value)
    // 6. Call kernel_load_script(locking_script)
    // 7. Call kernel_load_unlock(unlock_script)
    // 8. Call kernel_execute()
    // 9. Verify return value
    //
    // NOTE: Since the TS host provides real secp256k1 verification via host_checksig,
    // you need a REAL valid signature. Use the @bsv/sdk or similar to generate one.
    // Alternatively, for a smoke test: verify that kernel_load_tx_context returns 0
    // and that the CHECKSIG opcode is reached without stack overflow.
});
```

**Minimum viable test** (if generating a real signature is too complex for this fix pass): Verify that `kernel_load_tx_context` succeeds and that running a script with `OP_CHECKSIG` doesn't crash (even if the signature verification fails, the pipeline must not stack overflow).

---

### Fix 5: Test offset hardening (E-P3.8)

**File**: `packages/cell-engine/tests-ts/kernel_compat.test.ts`

Change all script write offsets from `1024` to `0x100000` (1MB) to match the Phase 1 tests. This puts test data safely above the WASM stack zone.

```typescript
// Before:
const SCRIPT_OFFSET = 1024;
// After:
const SCRIPT_OFFSET = 0x100000;  // 1MB — above WASM stack zone
```

---

### Fix 6: OP_CHECKSIGVERIFY / OP_CHECKMULTISIGVERIFY audit (E-P3.14)

**File**: `packages/cell-engine/src/opcodes/standard.zig`

Verify that opcodes 0xAD (CHECKSIGVERIFY) and 0xAF (CHECKMULTISIGVERIFY) are handled in the crypto dispatch. If missing, add:

```zig
OP_CHECKSIGVERIFY => {
    try opChecksig(p, script, pc, tx_ctx);
    const result = try p.spop();
    if (!pda_mod.isTruthy(result.data, result.len)) return error.verify_failed;
},
OP_CHECKMULTISIGVERIFY => {
    try opCheckmultisig(p, script, pc, tx_ctx);
    const result = try p.spop();
    if (!pda_mod.isTruthy(result.data, result.len)) return error.verify_failed;
},
```

---

## Verification Sequence

1. Apply Fix 1 (branch skip) → `zig build test-executor` → all pass including new tests
2. Apply Fix 2 (streaming hash) → `zig build test-executor` → still passes
3. Apply Fix 3 (OP_2OVER/2ROT) → `zig build test-opcodes` → new tests pass
4. Apply Fix 6 (CHECKSIGVERIFY audit) → `zig build test-opcodes` → passes
5. Build WASM: `zig build` → verify binary exists and is <50KB
6. Apply Fix 5 (test offsets) → `bun test tests-ts/kernel_compat.test.ts` → all pass
7. Apply Fix 4 (SIGHASH WASM test) → `bun test tests-ts/kernel_compat.test.ts` → new test passes
8. Full regression: `zig build test` (all targets) + `bun test`

## What NOT To Do

- Do not refactor PDA struct layout — that's working
- Do not change WASM memory size or stack size — 256KB stack + 8MB memory is correct
- Do not add new opcodes beyond the missing OP_2OVER/OP_2ROT
- Do not modify the host function interface
- Do not touch Phase 1/2 code (cell packing, BCA)
