---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/opcodes_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.965408+00:00
---

# core/cell-engine/tests/opcodes_conformance.zig

```zig
const std = @import("std");
const pda_mod = @import("pda");
const standard = @import("standard");
const allocator_mod = @import("allocator");
const sighash = @import("sighash");

// Helper: execute a single opcode via standard.execute
fn execOp(p: *pda_mod.PDA, opcode: u8) !void {
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var cond_stack = [_]bool{true} ** 100;
    var cond_depth: u32 = 0;
    var executing: bool = true;
    var pc: usize = 0;
    try standard.execute(p, opcode, &[_]u8{}, &pc, &arena, null, &cond_stack, &cond_depth, &executing);
}

// ── Constants ──

test "OP_0 pushes empty (zero)" {
    var p = pda_mod.PDA.init(500000);
    try execOp(&p, standard.OP_0);
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    const top = try p.speek();
    try std.testing.expectEqual(@as(u32, 0), top.len);
}

test "OP_1 through OP_16 push correct values" {
    var p = pda_mod.PDA.init(500000);
    var i: u8 = 1;
    while (i <= 16) : (i += 1) {
        try execOp(&p, standard.OP_1 + i - 1);
    }
    try std.testing.expectEqual(@as(u32, 16), p.sdepth());
    // Pop them in reverse and verify
    i = 16;
    while (i >= 1) : (i -= 1) {
        const item = try p.spop();
        const val = pda_mod.cellToI64(item.data[0..item.len]);
        try std.testing.expectEqual(@as(i64, i), val);
    }
}

test "OP_1NEGATE pushes -1" {
    var p = pda_mod.PDA.init(500000);
    try execOp(&p, standard.OP_1NEGATE);
    const item = try p.spop();
    const val = pda_mod.cellToI64(item.data[0..item.len]);
    try std.testing.expectEqual(@as(i64, -1), val);
}

// ── Arithmetic ──

test "OP_ADD: 2 + 3 = 5" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x02});
    try p.spush(&[_]u8{0x03});
    try execOp(&p, standard.OP_ADD);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 5), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_SUB: 5 - 3 = 2" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x05});
    try p.spush(&[_]u8{0x03});
    try execOp(&p, standard.OP_SUB);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 2), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_MUL: 3 * 4 = 12" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x03});
    try p.spush(&[_]u8{0x04});
    try execOp(&p, standard.OP_MUL);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 12), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_NEGATE: -(5) = -5" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x05});
    try execOp(&p, standard.OP_NEGATE);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, -5), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_ABS: abs(-5) = 5" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x85}); // -5
    try execOp(&p, standard.OP_ABS);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 5), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_NOT: not(0) = 1, not(5) = 0" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{});
    try execOp(&p, standard.OP_NOT);
    var item = try p.spop();
    try std.testing.expectEqual(@as(i64, 1), pda_mod.cellToI64(item.data[0..item.len]));

    try p.spush(&[_]u8{0x05});
    try execOp(&p, standard.OP_NOT);
    item = try p.spop();
    try std.testing.expectEqual(@as(i64, 0), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_NUMEQUAL: 5 == 5 is true" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x05});
    try p.spush(&[_]u8{0x05});
    try execOp(&p, standard.OP_NUMEQUAL);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 1), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_LESSTHAN: 3 < 5 is true" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x03});
    try p.spush(&[_]u8{0x05});
    try execOp(&p, standard.OP_LESSTHAN);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 1), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_GREATERTHAN: 5 > 3 is true" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x05});
    try p.spush(&[_]u8{0x03});
    try execOp(&p, standard.OP_GREATERTHAN);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 1), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_MIN: min(3, 5) = 3" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x03});
    try p.spush(&[_]u8{0x05});
    try execOp(&p, standard.OP_MIN);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 3), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_MAX: max(3, 5) = 5" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x03});
    try p.spush(&[_]u8{0x05});
    try execOp(&p, standard.OP_MAX);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 5), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_WITHIN: 3 within [2, 5) is true" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x03}); // x
    try p.spush(&[_]u8{0x02}); // min
    try p.spush(&[_]u8{0x05}); // max
    try execOp(&p, standard.OP_WITHIN);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 1), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_1ADD: 1add(5) = 6" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x05});
    try execOp(&p, standard.OP_1ADD);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 6), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_1SUB: 1sub(5) = 4" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x05});
    try execOp(&p, standard.OP_1SUB);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 4), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_BOOLAND: 1 AND 1 = 1, 1 AND 0 = 0" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x01});
    try execOp(&p, standard.OP_BOOLAND);
    var item = try p.spop();
    try std.testing.expectEqual(@as(i64, 1), pda_mod.cellToI64(item.data[0..item.len]));

    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{});
    try execOp(&p, standard.OP_BOOLAND);
    item = try p.spop();
    try std.testing.expectEqual(@as(i64, 0), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_BOOLOR: 0 OR 1 = 1, 0 OR 0 = 0" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{});
    try p.spush(&[_]u8{0x01});
    try execOp(&p, standard.OP_BOOLOR);
    var item = try p.spop();
    try std.testing.expectEqual(@as(i64, 1), pda_mod.cellToI64(item.data[0..item.len]));

    try p.spush(&[_]u8{});
    try p.spush(&[_]u8{});
    try execOp(&p, standard.OP_BOOLOR);
    item = try p.spop();
    try std.testing.expectEqual(@as(i64, 0), pda_mod.cellToI64(item.data[0..item.len]));
}

// ── Equality ──

test "OP_EQUAL: equal values" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{ 0xAA, 0xBB });
    try p.spush(&[_]u8{ 0xAA, 0xBB });
    try execOp(&p, standard.OP_EQUAL);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 1), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_EQUAL: unequal values" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0xAA});
    try p.spush(&[_]u8{0xBB});
    try execOp(&p, standard.OP_EQUAL);
    const item = try p.spop();
    try std.testing.expectEqual(@as(u32, 0), item.len); // empty = false
}

test "OP_EQUALVERIFY: fails on unequal" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0xAA});
    try p.spush(&[_]u8{0xBB});
    try std.testing.expectError(error.verify_failed, execOp(&p, standard.OP_EQUALVERIFY));
}

// ── Flow control ──

test "OP_VERIFY fails on false, succeeds on true" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try execOp(&p, standard.OP_VERIFY); // should succeed
    try std.testing.expectEqual(@as(u32, 0), p.sdepth());

    try p.spush(&[_]u8{});
    try std.testing.expectError(error.verify_failed, execOp(&p, standard.OP_VERIFY));
}

test "OP_RETURN terminates with error" {
    var p = pda_mod.PDA.init(500000);
    try std.testing.expectError(error.verify_failed, execOp(&p, standard.OP_RETURN));
}

test "OP_IF true branch executes" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var cond_stack = [_]bool{true} ** 100;
    var cond_depth: u32 = 0;
    var executing: bool = true;
    var dummy_pc: usize = 0;

    try p.spush(&[_]u8{0x01}); // true
    try standard.execute(&p, standard.OP_IF, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(executing);
    try std.testing.expectEqual(@as(u32, 1), cond_depth);
}

test "OP_IF false branch skips to ELSE" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var cond_stack = [_]bool{true} ** 100;
    var cond_depth: u32 = 0;
    var executing: bool = true;
    var dummy_pc: usize = 0;

    try p.spush(&[_]u8{}); // false
    try standard.execute(&p, standard.OP_IF, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(!executing);
    try std.testing.expectEqual(@as(u32, 1), cond_depth);

    // ELSE should flip
    try standard.execute(&p, standard.OP_ELSE, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(executing);

    // ENDIF restores
    try standard.execute(&p, standard.OP_ENDIF, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(executing);
    try std.testing.expectEqual(@as(u32, 0), cond_depth);
}

test "nested IF/ELSE/ENDIF" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var cond_stack = [_]bool{true} ** 100;
    var cond_depth: u32 = 0;
    var executing: bool = true;
    var dummy_pc: usize = 0;

    // Outer IF (true)
    try p.spush(&[_]u8{0x01});
    try standard.execute(&p, standard.OP_IF, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(executing);

    // Inner IF (false)
    try p.spush(&[_]u8{});
    try standard.execute(&p, standard.OP_IF, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(!executing);

    // Inner ELSE — should flip to executing
    try standard.execute(&p, standard.OP_ELSE, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(executing);

    // Inner ENDIF
    try standard.execute(&p, standard.OP_ENDIF, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(executing);
    try std.testing.expectEqual(@as(u32, 1), cond_depth);

    // Outer ENDIF
    try standard.execute(&p, standard.OP_ENDIF, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(executing);
    try std.testing.expectEqual(@as(u32, 0), cond_depth);
}

test "nested IF inside false branch counts correctly" {
    var p = pda_mod.PDA.init(500000);
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var cond_stack = [_]bool{true} ** 100;
    var cond_depth: u32 = 0;
    var executing: bool = true;
    var dummy_pc: usize = 0;

    // Outer IF (false) — everything inside should be skipped
    try p.spush(&[_]u8{});
    try standard.execute(&p, standard.OP_IF, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(!executing);

    // Nested IF inside false branch — must track nesting but stay non-executing
    // We push nothing (we're skipping, so IF won't pop from stack)
    try standard.execute(&p, standard.OP_IF, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(!executing);
    try std.testing.expectEqual(@as(u32, 2), cond_depth);

    // Nested ENDIF
    try standard.execute(&p, standard.OP_ENDIF, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(!executing); // still in outer false branch
    try std.testing.expectEqual(@as(u32, 1), cond_depth);

    // Outer ENDIF
    try standard.execute(&p, standard.OP_ENDIF, &[_]u8{}, &dummy_pc, &arena, null, &cond_stack, &cond_depth, &executing);
    try std.testing.expect(executing);
    try std.testing.expectEqual(@as(u32, 0), cond_depth);
}

// ── Stack manipulation opcodes (via standard.execute) ──

test "OP_DUP via standard execute" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x42});
    try execOp(&p, standard.OP_DUP);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "OP_DROP via standard execute" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x42});
    try execOp(&p, standard.OP_DROP);
    try std.testing.expectEqual(@as(u32, 0), p.sdepth());
}

test "OP_DEPTH pushes stack depth" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try execOp(&p, standard.OP_DEPTH);
    const item = try p.spop();
    try std.testing.expectEqual(@as(i64, 2), pda_mod.cellToI64(item.data[0..item.len]));
}

test "OP_SIZE pushes size without popping" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{ 0x01, 0x02, 0x03 });
    try execOp(&p, standard.OP_SIZE);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth()); // original + size
    const size_item = try p.spop();
    try std.testing.expectEqual(@as(i64, 3), pda_mod.cellToI64(size_item.data[0..size_item.len]));
}

// ── String/splice ──

test "OP_CAT concatenates two items" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{ 0x01, 0x02 });
    try p.spush(&[_]u8{ 0x03, 0x04 });
    try execOp(&p, standard.OP_CAT);
    const item = try p.spop();
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x02, 0x03, 0x04 }, item.data[0..item.len]);
}

test "OP_SPLIT splits at index" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{ 0x01, 0x02, 0x03, 0x04 });
    try p.spush(&[_]u8{0x02}); // split at position 2
    try execOp(&p, standard.OP_SPLIT);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());

    const right = try p.spop();
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x03, 0x04 }, right.data[0..right.len]);
    const left = try p.spop();
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x02 }, left.data[0..left.len]);
}

// ── Crypto ──

test "OP_SHA256 hashes top of stack" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{}); // SHA256 of empty
    try execOp(&p, standard.OP_SHA256);
    const item = try p.spop();
    try std.testing.expectEqual(@as(u32, 32), item.len);
    // SHA256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    try std.testing.expectEqual(@as(u8, 0xe3), item.data[0]);
    try std.testing.expectEqual(@as(u8, 0x55), item.data[31]);
}

test "OP_HASH256 double-hashes top of stack" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{});
    try execOp(&p, standard.OP_HASH256);
    const item = try p.spop();
    try std.testing.expectEqual(@as(u32, 32), item.len);
    // Verify it's different from single SHA256
    try std.testing.expect(item.data[0] != 0xe3);
}

// ── OP_NOP ──

test "OP_NOP does nothing" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x42});
    try execOp(&p, standard.OP_NOP);
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

// ── OP_2OVER ──

test "OP_2OVER copies 3rd and 4th to top" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01}); // x1 (deepest)
    try p.spush(&[_]u8{0x02}); // x2
    try p.spush(&[_]u8{0x03}); // x3
    try p.spush(&[_]u8{0x04}); // x4 (top)
    try execOp(&p, standard.OP_2OVER);
    // Stack: 1 2 3 4 1 2
    try std.testing.expectEqual(@as(u32, 6), p.sdepth());
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), top.data[0]);
    const second = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), second.data[0]);
}

test "OP_2OVER underflow with < 4 items" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try p.spush(&[_]u8{0x03});
    try std.testing.expectError(error.stack_underflow, execOp(&p, standard.OP_2OVER));
}

// ── OP_2ROT ──

test "OP_2ROT moves 5th and 6th to top" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01}); // x1 (deepest)
    try p.spush(&[_]u8{0x02}); // x2
    try p.spush(&[_]u8{0x03}); // x3
    try p.spush(&[_]u8{0x04}); // x4
    try p.spush(&[_]u8{0x05}); // x5
    try p.spush(&[_]u8{0x06}); // x6 (top)
    try execOp(&p, standard.OP_2ROT);
    // Stack: 3 4 5 6 1 2
    try std.testing.expectEqual(@as(u32, 6), p.sdepth());
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), top.data[0]);
    const second = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), second.data[0]);
    const third = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x06), third.data[0]);
    const fourth = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x05), fourth.data[0]);
}

test "OP_2ROT underflow with < 6 items" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try p.spush(&[_]u8{0x03});
    try p.spush(&[_]u8{0x04});
    try p.spush(&[_]u8{0x05});
    try std.testing.expectError(error.stack_underflow, execOp(&p, standard.OP_2ROT));
}

```
