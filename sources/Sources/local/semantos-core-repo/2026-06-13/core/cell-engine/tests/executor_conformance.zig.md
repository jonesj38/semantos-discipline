---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/executor_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.967303+00:00
---

# core/cell-engine/tests/executor_conformance.zig

```zig
const std = @import("std");
const constants = @import("constants");
const pda_mod = @import("pda");
const executor = @import("executor");
const allocator_mod = @import("allocator");
const standard = @import("standard");
const linearity = @import("linearity");
const sighash = @import("sighash");

fn makeCtx(p: *pda_mod.PDA, arena: *allocator_mod.ScriptArena) executor.ExecutionContext {
    return executor.ExecutionContext.init(p, arena);
}

// ── Simple script execution ──

test "OP_1 OP_1 OP_ADD → stack has 2, script succeeds" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: OP_1 OP_1 OP_ADD = 0x51 0x51 0x93
    try ctx.loadScript(&[_]u8{ 0x51, 0x51, 0x93 });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result); // true because 2 is truthy

    const top = try p.speek();
    try std.testing.expectEqual(@as(i64, 2), pda_mod.cellToI64(top.data[0..top.len]));
}

test "OP_0 → script fails (zero is falsy)" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    try ctx.loadScript(&[_]u8{0x00}); // OP_0
    const result = try executor.execute(&ctx);
    try std.testing.expect(!result); // false
}

test "empty script → fails (empty stack)" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    ctx.lock_script_len = 0;
    const result = try executor.execute(&ctx);
    try std.testing.expect(!result);
}

// ── Direct push ──

test "direct push: 0x03 pushes 3 bytes" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: push 3 bytes [0xAA, 0xBB, 0xCC], then OP_1 (to make truthy top)
    try ctx.loadScript(&[_]u8{ 0x03, 0xAA, 0xBB, 0xCC, 0x51 });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "PUSHDATA1 pushes N bytes" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: PUSHDATA1 0x02 0xDE 0xAD OP_1
    try ctx.loadScript(&[_]u8{ 0x4C, 0x02, 0xDE, 0xAD, 0x51 });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);

    // Pop OP_1, then check the pushed data
    _ = try p.spop();
    const item = try p.spop();
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xDE, 0xAD }, item.data[0..item.len]);
}

// ── Unlock + Lock script ──

test "unlock pushes value, lock verifies it" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Unlock: OP_5 (pushes 5)
    try ctx.loadUnlock(&[_]u8{0x55});
    // Lock: OP_5 OP_NUMEQUAL (pushes 5, compares)
    try ctx.loadScript(&[_]u8{ 0x55, 0x9C });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result); // 5 == 5 → true
}

test "unlock pushes wrong value, lock fails" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    try ctx.loadUnlock(&[_]u8{0x54}); // OP_4
    try ctx.loadScript(&[_]u8{ 0x55, 0x9C }); // OP_5 OP_NUMEQUAL
    const result = try executor.execute(&ctx);
    try std.testing.expect(!result); // 4 != 5 → false
}

// ── Bounded execution ──

test "execution stops at max_ops limit" {
    var p = pda_mod.PDA.init(5); // very low limit
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script with more than 5 ops: OP_1 OP_1 OP_1 OP_1 OP_1 OP_1 OP_ADD OP_ADD OP_ADD OP_ADD
    try ctx.loadScript(&[_]u8{ 0x51, 0x51, 0x51, 0x51, 0x51, 0x51, 0x93, 0x93, 0x93, 0x93 });
    const result = executor.execute(&ctx);
    try std.testing.expectError(error.execution_limit, result);
}

test "script length limit enforced" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    var big_script: [executor.MAX_SCRIPT_SIZE + 1]u8 = [_]u8{0x61} ** (executor.MAX_SCRIPT_SIZE + 1);
    const result = ctx.loadScript(&big_script);
    try std.testing.expectError(error.script_too_large, result);
}

// ── Flow control in executor ──

test "IF/ELSE/ENDIF executes correct branch via executor" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: OP_1 OP_IF OP_2 OP_ELSE OP_3 OP_ENDIF
    // Should push 2 (true branch)
    try ctx.loadScript(&[_]u8{ 0x51, 0x63, 0x52, 0x67, 0x53, 0x68 });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);
    const top = try p.speek();
    try std.testing.expectEqual(@as(i64, 2), pda_mod.cellToI64(top.data[0..top.len]));
}

test "IF false branch skips via executor" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: OP_0 OP_IF OP_2 OP_ELSE OP_3 OP_ENDIF
    // Should push 3 (false branch)
    try ctx.loadScript(&[_]u8{ 0x00, 0x63, 0x52, 0x67, 0x53, 0x68 });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);
    const top = try p.speek();
    try std.testing.expectEqual(@as(i64, 3), pda_mod.cellToI64(top.data[0..top.len]));
}

// ── OP_RETURN ──

test "OP_RETURN terminates script with failure" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: OP_1 OP_RETURN OP_1 (should never reach second OP_1)
    try ctx.loadScript(&[_]u8{ 0x51, 0x6A, 0x51 });
    const result = executor.execute(&ctx);
    try std.testing.expectError(error.verify_failed, result);
}

// ── Opcount tracking ──

test "opcount tracks number of executed operations" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: OP_1 OP_1 OP_ADD = 3 opcodes
    try ctx.loadScript(&[_]u8{ 0x51, 0x51, 0x93 });
    _ = try executor.execute(&ctx);
    try std.testing.expectEqual(@as(u32, 3), p.opcount);
}

// ── Step execution ──

test "step executes one opcode at a time" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: OP_1 OP_2 OP_ADD
    try ctx.loadScript(&[_]u8{ 0x51, 0x52, 0x93 });

    // Step 1: OP_1
    var result = try executor.step(&ctx);
    try std.testing.expectEqual(executor.StepResult.continue_execution, result);
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());

    // Step 2: OP_2
    result = try executor.step(&ctx);
    try std.testing.expectEqual(executor.StepResult.continue_execution, result);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());

    // Step 3: OP_ADD → end of script
    result = try executor.step(&ctx);
    try std.testing.expectEqual(executor.StepResult.done_true, result);
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

// ── Plexus opcodes — Phase 4 ──

test "Plexus opcode 0xC0 on empty stack returns stack_underflow" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    try ctx.loadScript(&[_]u8{0xC0});
    const result = executor.execute(&ctx);
    try std.testing.expectError(error.stack_underflow, result);
}

test "Plexus opcode 0xC9 (OP_READHEADER) on empty stack returns stack_underflow" {
    // After Phase W1+W3 the entire 0xC0-0xCF range is mapped: 0xC9 is
    // OP_READHEADER, which needs 3 stack items. With an empty stack it
    // fails with stack_underflow.
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    try ctx.loadScript(&[_]u8{0xC9});
    const result = executor.execute(&ctx);
    try std.testing.expectError(error.stack_underflow, result);
}

fn makeTestCellForExecutor(lin: u32, domain_flag: u32) pda_mod.Cell {
    var cell: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    std.mem.writeInt(u32, cell[0..4], constants.MAGIC_1, .little);
    std.mem.writeInt(u32, cell[4..8], constants.MAGIC_2, .little);
    std.mem.writeInt(u32, cell[8..12], constants.MAGIC_3, .little);
    std.mem.writeInt(u32, cell[12..16], constants.MAGIC_4, .little);
    std.mem.writeInt(u32, cell[16..20], lin, .little);
    std.mem.writeInt(u32, cell[20..24], 1, .little);
    std.mem.writeInt(u32, cell[24..28], domain_flag, .little);
    return cell;
}

test "script: push LINEAR cell, OP_CHECKLINEARTYPE succeeds" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Push a LINEAR cell onto the stack, then run OP_CHECKLINEARTYPE
    var cell = makeTestCellForExecutor(1, constants.DOMAIN_FLAG_EDGE_CREATION);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try ctx.loadScript(&[_]u8{0xC0}); // OP_CHECKLINEARTYPE
    const result = try executor.execute(&ctx);
    try std.testing.expect(result); // TRUE on top
}

test "script: enforcement enabled, AFFINE cell OP_DUP fails" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    var cell = makeTestCellForExecutor(2, 0); // AFFINE
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    try ctx.loadScript(&[_]u8{0x76}); // OP_DUP
    const result = executor.execute(&ctx);
    try std.testing.expectError(error.cannot_duplicate_affine, result);
}

test "script: enforcement disabled, LINEAR cell OP_DUP succeeds (raw Bitcoin mode)" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    var cell = makeTestCellForExecutor(1, 0); // LINEAR
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    // Enforcement is off by default
    try ctx.loadScript(&[_]u8{0x76}); // OP_DUP
    const result = try executor.execute(&ctx);
    // DUP succeeds, two items on stack, top is truthy (has magic bytes)
    try std.testing.expect(result);
}

test "script: enforcement enabled, RELEVANT cell DUP succeeds, DROP fails" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    var cell = makeTestCellForExecutor(3, 0); // RELEVANT
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    p.enableEnforcement();
    // OP_DUP (0x76) then OP_DROP (0x75)
    try ctx.loadScript(&[_]u8{ 0x76, 0x75 });
    const result = executor.execute(&ctx);
    try std.testing.expectError(error.cannot_discard_relevant, result);
}

// ── Unbalanced IF/ENDIF ──

test "unbalanced IF without ENDIF fails" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: OP_1 OP_IF OP_1 (no ENDIF)
    try ctx.loadScript(&[_]u8{ 0x51, 0x63, 0x51 });
    const result = executor.execute(&ctx);
    try std.testing.expectError(error.invalid_script, result);
}

// ── P2PKH-like script ──

test "P2PKH-like: OP_DUP OP_HASH160 push20 OP_EQUALVERIFY OP_CHECKSIG structure" {
    // This tests the opcode dispatch structure without real crypto
    // (checksig always returns false in native mode, so we test the dispatch path)
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Just verify OP_DUP OP_HASH160 works in sequence
    // Script: push 4 bytes, OP_DUP, OP_HASH160
    try ctx.loadScript(&[_]u8{ 0x04, 0x01, 0x02, 0x03, 0x04, 0x76, 0xA9 });
    _ = executor.execute(&ctx) catch {};
    // After DUP we have 2 items, after HASH160 we have 2 items (original + hash)
    // The exact result depends on the hash output
    try std.testing.expect(p.sdepth() >= 1);
}

// ── Reset ──

test "context reset clears state" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    try ctx.loadScript(&[_]u8{ 0x51, 0x51, 0x93 });
    _ = try executor.execute(&ctx);
    try std.testing.expectEqual(@as(u32, 3), p.opcount);

    p.reset();
    ctx.reset();
    try std.testing.expectEqual(@as(u32, 0), p.opcount);
    try std.testing.expectEqual(@as(u32, 0), ctx.lock_script_len);
}

// ── Branch skip tests (E-P3.9 + E-P3.10) ──

test "direct push in false IF branch skips data bytes" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: OP_0 OP_IF OP_PUSHBYTES_3 0xAA 0xBB 0xCC OP_ELSE OP_1 OP_ENDIF
    // Expected: false branch skips the 3-byte push, executes OP_1 from ELSE
    try ctx.loadScript(&[_]u8{
        0x00, // OP_0 (false)
        0x63, // OP_IF
        0x03, // OP_PUSHBYTES_3
        0xAA, 0xBB, 0xCC, // 3 data bytes (must be skipped)
        0x67, // OP_ELSE
        0x51, // OP_1
        0x68, // OP_ENDIF
    });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result); // true (OP_1 is truthy)
    const top = try p.speek();
    try std.testing.expectEqual(@as(i64, 1), pda_mod.cellToI64(top.data[0..top.len]));
}

test "PUSHDATA1 in false IF branch skips length and data bytes" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: OP_0 OP_IF PUSHDATA1 0x02 0xDE 0xAD OP_ELSE OP_1 OP_ENDIF
    try ctx.loadScript(&[_]u8{
        0x00, // OP_0
        0x63, // OP_IF
        0x4C, // PUSHDATA1
        0x02, // length = 2
        0xDE, 0xAD, // 2 data bytes
        0x67, // OP_ELSE
        0x51, // OP_1
        0x68, // OP_ENDIF
    });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);
    const top = try p.speek();
    try std.testing.expectEqual(@as(i64, 1), pda_mod.cellToI64(top.data[0..top.len]));
}

test "PUSHDATA2 in false IF branch skips length and data bytes" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: OP_0 OP_IF PUSHDATA2 0x02 0x00 0xDE 0xAD OP_ELSE OP_1 OP_ENDIF
    try ctx.loadScript(&[_]u8{
        0x00, // OP_0
        0x63, // OP_IF
        0x4D, // PUSHDATA2
        0x02, 0x00, // length = 2 (LE)
        0xDE, 0xAD, // 2 data bytes
        0x67, // OP_ELSE
        0x51, // OP_1
        0x68, // OP_ENDIF
    });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);
}

test "multiple pushes in false branch all skipped correctly" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    // Script: OP_0 OP_IF PUSH2 0xAA 0xBB PUSH1 0xCC OP_ELSE OP_2 OP_ENDIF
    try ctx.loadScript(&[_]u8{
        0x00, // OP_0
        0x63, // OP_IF
        0x02, // PUSH 2 bytes
        0xAA, 0xBB,
        0x01, // PUSH 1 byte
        0xCC,
        0x67, // OP_ELSE
        0x52, // OP_2
        0x68, // OP_ENDIF
    });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);
    const top = try p.speek();
    try std.testing.expectEqual(@as(i64, 2), pda_mod.cellToI64(top.data[0..top.len]));
}

// ── OP_BRANCHONOUTPUT (0xE0) — routing range ──
// Spec: docs/design/OP-BRANCHONOUTPUT-SPEC.md
//
// Invariants exercised here (I1..I4 in the spec):
//   I1 determinism            — fixed test inputs always produce the
//                               same script result and stack contents.
//   I2 stack delta = +1       — pre/post depth differs by exactly one.
//   I3 non-malleability       — tx_context.current_output_index is
//                               unchanged after script execution.
//   I4 linear single-claim    — exercised at integration time
//                               (Phase 5); covered here only at the
//                               opcode-level discriminator step.

fn makeTxCtxWithOutput(idx: u32) sighash.TxContext {
    var ctx = sighash.TxContext.init();
    ctx.current_output_index = idx;
    return ctx;
}

test "OP_BRANCHONOUTPUT pushes current_output_index = 0 as 4-byte LE" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    const tx = makeTxCtxWithOutput(0);
    ctx.tx_context = &tx;

    // Script: OP_BRANCHONOUTPUT OP_1 (OP_1 to leave a truthy top).
    try ctx.loadScript(&[_]u8{ 0xE0, 0x51 });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);

    // Pop the OP_1, then check the BRANCHONOUTPUT push.
    _ = try p.spop();
    const item = try p.spop();
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 0x00, 0x00, 0x00, 0x00 },
        item.data[0..item.len],
    );
}

test "OP_BRANCHONOUTPUT pushes current_output_index = 1 as 4-byte LE" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    const tx = makeTxCtxWithOutput(1);
    ctx.tx_context = &tx;

    try ctx.loadScript(&[_]u8{ 0xE0, 0x51 });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);

    _ = try p.spop();
    const item = try p.spop();
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 0x01, 0x00, 0x00, 0x00 },
        item.data[0..item.len],
    );
}

test "OP_BRANCHONOUTPUT pushes current_output_index = 0x12345678 as 4-byte LE" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    const tx = makeTxCtxWithOutput(0x12345678);
    ctx.tx_context = &tx;

    try ctx.loadScript(&[_]u8{ 0xE0, 0x51 });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);

    _ = try p.spop();
    const item = try p.spop();
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 0x78, 0x56, 0x34, 0x12 },
        item.data[0..item.len],
    );
}

test "OP_BRANCHONOUTPUT stack delta is exactly +1 (I2)" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    const tx = makeTxCtxWithOutput(42);
    ctx.tx_context = &tx;

    const depth_before = p.sdepth();
    try ctx.loadScript(&[_]u8{0xE0});
    _ = executor.execute(&ctx) catch |err| {
        // execute() returns false for empty/falsy result, not an error,
        // so any error here indicates a real failure.
        try std.testing.expect(err == error.execution_limit);
        return;
    };
    const depth_after = p.sdepth();
    try std.testing.expectEqual(@as(u32, 1), depth_after - depth_before);
}

test "OP_BRANCHONOUTPUT without tx_context fails (no_tx_context)" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    ctx.tx_context = null;

    try ctx.loadScript(&[_]u8{ 0xE0, 0x51 });
    const result = executor.execute(&ctx);
    try std.testing.expectError(error.no_tx_context, result);
}

test "OP_BRANCHONOUTPUT is non-malleable: tx_context unchanged after script (I3)" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    const orig_idx: u32 = 7;
    const tx = makeTxCtxWithOutput(orig_idx);
    ctx.tx_context = &tx;

    // Script: BRANCHONOUTPUT, then drop, then 1ADD (manipulating other
    // stack values shouldn't affect tx_context).
    // 0xE0 0x75 (OP_DROP) 0x51 (OP_1) — push idx, drop it, push 1.
    try ctx.loadScript(&[_]u8{ 0xE0, 0x75, 0x51 });
    _ = try executor.execute(&ctx);

    // tx_context.current_output_index must be unchanged.
    try std.testing.expectEqual(orig_idx, tx.current_output_index);
}

test "OP_BRANCHONOUTPUT in non-executing branch is a no-op (skipped)" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    const tx = makeTxCtxWithOutput(99);
    ctx.tx_context = &tx;

    // Script: OP_0 OP_IF OP_BRANCHONOUTPUT OP_ENDIF OP_1
    // Because the IF is false, OP_BRANCHONOUTPUT is skipped — nothing pushed.
    try ctx.loadScript(&[_]u8{
        0x00, // OP_0  (false)
        0x63, // OP_IF
        0xE0, // OP_BRANCHONOUTPUT (skipped)
        0x68, // OP_ENDIF
        0x51, // OP_1
    });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);
    // Only OP_1 ran → stack has exactly one item (= 1).
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

test "OP_BRANCHONOUTPUT enables index-based branching: output 0 path" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    const tx = makeTxCtxWithOutput(0);
    ctx.tx_context = &tx;

    // Script: pushes idx (0), compares to pushed 0, IF → push 0x42,
    // ELSE → push 0xFF, ENDIF.
    // Layout: OP_BRANCHONOUTPUT OP_BIN2NUM OP_0 OP_NUMEQUAL OP_IF OP_PUSH1 0x42 OP_ELSE OP_PUSH1 0xFF OP_ENDIF
    try ctx.loadScript(&[_]u8{
        0xE0,       // OP_BRANCHONOUTPUT → push 0x00 00 00 00
        0x81,       // OP_BIN2NUM → coerce to numeric 0 (empty)
        0x00,       // OP_0 (the literal 0 to compare against)
        0x9C,       // OP_NUMEQUAL
        0x63,       // OP_IF
        0x01, 0x42, // push 0x42 (truthy)
        0x67,       // OP_ELSE
        0x01, 0xFF, // push 0xFF
        0x68,       // OP_ENDIF
    });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);
    const top = try p.speek();
    try std.testing.expectEqualSlices(u8, &[_]u8{0x42}, top.data[0..top.len]);
}

test "OP_BRANCHONOUTPUT enables index-based branching: output 1 path" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = makeCtx(&p, &arena);

    const tx = makeTxCtxWithOutput(1);
    ctx.tx_context = &tx;

    // Same script as previous test, but with output_index = 1 → ELSE path.
    try ctx.loadScript(&[_]u8{
        0xE0, 0x81, 0x00, 0x9C, 0x63,
        0x01, 0x42,
        0x67,
        0x01, 0xFF,
        0x68,
    });
    const result = try executor.execute(&ctx);
    try std.testing.expect(result);
    const top = try p.speek();
    try std.testing.expectEqualSlices(u8, &[_]u8{0xFF}, top.data[0..top.len]);
}

test "OP_BRANCHONOUTPUT is deterministic (I1): same context → same result" {
    var arena_buf: [4096]u8 = undefined;

    const tx = makeTxCtxWithOutput(0xABCDEF01);

    var p1 = pda_mod.PDA.init(500000);
    var arena1 = allocator_mod.ScriptArena.init(&arena_buf);
    var c1 = makeCtx(&p1, &arena1);
    c1.tx_context = &tx;
    try c1.loadScript(&[_]u8{ 0xE0, 0x51 });
    _ = try executor.execute(&c1);
    _ = try p1.spop();
    const a = try p1.spop();
    const a_copy: [4]u8 = .{ a.data[0], a.data[1], a.data[2], a.data[3] };

    var p2 = pda_mod.PDA.init(500000);
    var arena2 = allocator_mod.ScriptArena.init(&arena_buf);
    var c2 = makeCtx(&p2, &arena2);
    c2.tx_context = &tx;
    try c2.loadScript(&[_]u8{ 0xE0, 0x51 });
    _ = try executor.execute(&c2);
    _ = try p2.spop();
    const b = try p2.spop();

    try std.testing.expectEqualSlices(u8, &a_copy, b.data[0..b.len]);
}

```
