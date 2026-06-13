---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/bsv_restored_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.970344+00:00
---

# core/cell-engine/tests/bsv_restored_conformance.zig

```zig
// BSV-restored opcodes conformance tests
// Reference: CORE:EXECUTOR (script-executor.fs), PHASE-3-BSV-RESTORE.md
//
// Tests the 19 BSV-restored opcodes:
// - Reserved: OP_RESERVED, OP_VER, OP_VERIF, OP_VERNOTIF, OP_RESERVED1, OP_RESERVED2
// - Arithmetic: OP_DIV, OP_MOD, OP_2MUL, OP_2DIV
// - Bitwise: OP_INVERT, OP_AND, OP_OR, OP_XOR
// - Shifts: OP_LSHIFT, OP_RSHIFT
// - Crypto: OP_SHA1, OP_RIPEMD160
// - Other: OP_CODESEPARATOR

const std = @import("std");
const pda_mod = @import("pda");
const standard = @import("standard");
const allocator_mod = @import("allocator");
const sighash = @import("sighash");

// ── Helper: execute a single opcode via standard.execute ──

fn execOp(p: *pda_mod.PDA, opcode: u8) !void {
    var arena_buf: [4096]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var cond_stack = [_]bool{true} ** 100;
    var cond_depth: u32 = 0;
    var executing: bool = true;
    var pc: usize = 0;
    try standard.execute(p, opcode, &[_]u8{}, &pc, &arena, null, &cond_stack, &cond_depth, &executing);
}

// ── Reserved opcodes (always fail) ──

test "OP_RESERVED always fails" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    const result = execOp(&p, standard.OP_RESERVED);
    try std.testing.expectError(error.verify_failed, result);
}

test "OP_VER always fails" {
    var p = pda_mod.PDA.init(500000);
    const result = execOp(&p, standard.OP_VER);
    try std.testing.expectError(error.verify_failed, result);
}

test "OP_VERIF always fails" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    const result = execOp(&p, standard.OP_VERIF);
    try std.testing.expectError(error.verify_failed, result);
}

test "OP_VERNOTIF always fails" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    const result = execOp(&p, standard.OP_VERNOTIF);
    try std.testing.expectError(error.verify_failed, result);
}

test "OP_RESERVED1 always fails" {
    var p = pda_mod.PDA.init(500000);
    const result = execOp(&p, standard.OP_RESERVED1);
    try std.testing.expectError(error.verify_failed, result);
}

test "OP_RESERVED2 always fails" {
    var p = pda_mod.PDA.init(500000);
    const result = execOp(&p, standard.OP_RESERVED2);
    try std.testing.expectError(error.verify_failed, result);
}

// ── Arithmetic: OP_DIV ──

test "OP_DIV: 6 / 3 = 2" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    var len = pda_mod.i64ToCell(6, &cell);
    try p.spush(cell[0..len]);
    len = pda_mod.i64ToCell(3, &cell);
    try p.spush(cell[0..len]);
    try execOp(&p, standard.OP_DIV);
    const top = try p.spop();
    try std.testing.expectEqual(@as(i64, 2), pda_mod.cellToI64(top.data[0..top.len]));
}

test "OP_DIV: -6 / 3 = -2" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    var len = pda_mod.i64ToCell(-6, &cell);
    try p.spush(cell[0..len]);
    len = pda_mod.i64ToCell(3, &cell);
    try p.spush(cell[0..len]);
    try execOp(&p, standard.OP_DIV);
    const top = try p.spop();
    try std.testing.expectEqual(@as(i64, -2), pda_mod.cellToI64(top.data[0..top.len]));
}

test "OP_DIV: division by zero fails" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    var len = pda_mod.i64ToCell(6, &cell);
    try p.spush(cell[0..len]);
    len = pda_mod.i64ToCell(0, &cell);
    try p.spush(cell[0..len]);
    const result = execOp(&p, standard.OP_DIV);
    try std.testing.expectError(error.verify_failed, result);
}

// ── Arithmetic: OP_MOD ──

test "OP_MOD: 7 % 3 = 1" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    var len = pda_mod.i64ToCell(7, &cell);
    try p.spush(cell[0..len]);
    len = pda_mod.i64ToCell(3, &cell);
    try p.spush(cell[0..len]);
    try execOp(&p, standard.OP_MOD);
    const top = try p.spop();
    try std.testing.expectEqual(@as(i64, 1), pda_mod.cellToI64(top.data[0..top.len]));
}

test "OP_MOD: -7 % 3 = -1" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    var len = pda_mod.i64ToCell(-7, &cell);
    try p.spush(cell[0..len]);
    len = pda_mod.i64ToCell(3, &cell);
    try p.spush(cell[0..len]);
    try execOp(&p, standard.OP_MOD);
    const top = try p.spop();
    try std.testing.expectEqual(@as(i64, -1), pda_mod.cellToI64(top.data[0..top.len]));
}

test "OP_MOD: modulo by zero fails" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    var len = pda_mod.i64ToCell(7, &cell);
    try p.spush(cell[0..len]);
    len = pda_mod.i64ToCell(0, &cell);
    try p.spush(cell[0..len]);
    const result = execOp(&p, standard.OP_MOD);
    try std.testing.expectError(error.verify_failed, result);
}

// ── Arithmetic: OP_2MUL ──

test "OP_2MUL: 5 * 2 = 10" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(5, &cell);
    try p.spush(cell[0..len]);
    try execOp(&p, standard.OP_2MUL);
    const top = try p.spop();
    try std.testing.expectEqual(@as(i64, 10), pda_mod.cellToI64(top.data[0..top.len]));
}

test "OP_2MUL: -3 * 2 = -6" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(-3, &cell);
    try p.spush(cell[0..len]);
    try execOp(&p, standard.OP_2MUL);
    const top = try p.spop();
    try std.testing.expectEqual(@as(i64, -6), pda_mod.cellToI64(top.data[0..top.len]));
}

// ── Arithmetic: OP_2DIV ──

test "OP_2DIV: 10 / 2 = 5" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(10, &cell);
    try p.spush(cell[0..len]);
    try execOp(&p, standard.OP_2DIV);
    const top = try p.spop();
    try std.testing.expectEqual(@as(i64, 5), pda_mod.cellToI64(top.data[0..top.len]));
}

test "OP_2DIV: -10 / 2 = -5" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(-10, &cell);
    try p.spush(cell[0..len]);
    try execOp(&p, standard.OP_2DIV);
    const top = try p.spop();
    try std.testing.expectEqual(@as(i64, -5), pda_mod.cellToI64(top.data[0..top.len]));
}

// ── Shifts: OP_LSHIFT ──

test "OP_LSHIFT: 1 << 3 = 8" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    var len = pda_mod.i64ToCell(1, &cell);
    try p.spush(cell[0..len]);
    len = pda_mod.i64ToCell(3, &cell);
    try p.spush(cell[0..len]);
    try execOp(&p, standard.OP_LSHIFT);
    const top = try p.spop();
    try std.testing.expectEqual(@as(i64, 8), pda_mod.cellToI64(top.data[0..top.len]));
}

test "OP_LSHIFT: 7 << 2 = 28" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    var len = pda_mod.i64ToCell(7, &cell);
    try p.spush(cell[0..len]);
    len = pda_mod.i64ToCell(2, &cell);
    try p.spush(cell[0..len]);
    try execOp(&p, standard.OP_LSHIFT);
    const top = try p.spop();
    try std.testing.expectEqual(@as(i64, 28), pda_mod.cellToI64(top.data[0..top.len]));
}

// ── Shifts: OP_RSHIFT ──

test "OP_RSHIFT: 8 >> 3 = 1" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    var len = pda_mod.i64ToCell(8, &cell);
    try p.spush(cell[0..len]);
    len = pda_mod.i64ToCell(3, &cell);
    try p.spush(cell[0..len]);
    try execOp(&p, standard.OP_RSHIFT);
    const top = try p.spop();
    try std.testing.expectEqual(@as(i64, 1), pda_mod.cellToI64(top.data[0..top.len]));
}

test "OP_RSHIFT: 28 >> 2 = 7" {
    var p = pda_mod.PDA.init(500000);
    var cell: pda_mod.Cell = undefined;
    var len = pda_mod.i64ToCell(28, &cell);
    try p.spush(cell[0..len]);
    len = pda_mod.i64ToCell(2, &cell);
    try p.spush(cell[0..len]);
    try execOp(&p, standard.OP_RSHIFT);
    const top = try p.spop();
    try std.testing.expectEqual(@as(i64, 7), pda_mod.cellToI64(top.data[0..top.len]));
}

// ── Bitwise: OP_INVERT ──

test "OP_INVERT: bitwise NOT of 0x00 = 0xFF" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x00});
    try execOp(&p, standard.OP_INVERT);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u32, 1), top.len);
    try std.testing.expectEqual(@as(u8, 0xFF), top.data[0]);
}

test "OP_INVERT: bitwise NOT of 0xFF = 0x00" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0xFF});
    try execOp(&p, standard.OP_INVERT);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u32, 1), top.len);
    try std.testing.expectEqual(@as(u8, 0x00), top.data[0]);
}

// ── Bitwise: OP_AND ──

test "OP_AND: 0xFF AND 0x0F = 0x0F" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0xFF});
    try p.spush(&[_]u8{0x0F});
    try execOp(&p, standard.OP_AND);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x0F), top.data[0]);
}

test "OP_AND: 0xF0 AND 0x0F = 0x00" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0xF0});
    try p.spush(&[_]u8{0x0F});
    try execOp(&p, standard.OP_AND);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x00), top.data[0]);
}

// ── Bitwise: OP_OR ──

test "OP_OR: 0xF0 OR 0x0F = 0xFF" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0xF0});
    try p.spush(&[_]u8{0x0F});
    try execOp(&p, standard.OP_OR);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0xFF), top.data[0]);
}

test "OP_OR: 0xF0 OR 0xF0 = 0xF0" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0xF0});
    try p.spush(&[_]u8{0xF0});
    try execOp(&p, standard.OP_OR);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0xF0), top.data[0]);
}

// ── Bitwise: OP_XOR ──

test "OP_XOR: 0xFF XOR 0xFF = 0x00" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0xFF});
    try p.spush(&[_]u8{0xFF});
    try execOp(&p, standard.OP_XOR);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x00), top.data[0]);
}

test "OP_XOR: 0xFF XOR 0x0F = 0xF0" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0xFF});
    try p.spush(&[_]u8{0x0F});
    try execOp(&p, standard.OP_XOR);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0xF0), top.data[0]);
}

// ── Crypto: OP_SHA1 ──

test "OP_SHA1: hash of 'abc'" {
    var p = pda_mod.PDA.init(500000);
    try p.spush("abc");
    try execOp(&p, standard.OP_SHA1);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u32, 20), top.len);
    // SHA1("abc") = a9993e364706816aba3e25717850c26c9cd0d89d
    const expected = [_]u8{ 0xa9, 0x99, 0x3e, 0x36, 0x47, 0x06, 0x81, 0x6a, 0xba, 0x3e, 0x25, 0x71, 0x78, 0x50, 0xc2, 0x6c, 0x9c, 0xd0, 0xd8, 0x9d };
    try std.testing.expectEqualSlices(u8, &expected, top.data[0..20]);
}

// ── Crypto: OP_RIPEMD160 ──

test "OP_RIPEMD160: hash of empty string" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{});
    try execOp(&p, standard.OP_RIPEMD160);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u32, 20), top.len);
    // RIPEMD160("") = 9c1185a5c5e9fc54612808977ee8f548b2258d31
    const expected = [_]u8{ 0x9c, 0x11, 0x85, 0xa5, 0xc5, 0xe9, 0xfc, 0x54, 0x61, 0x28, 0x08, 0x97, 0x7e, 0xe8, 0xf5, 0x48, 0xb2, 0x25, 0x8d, 0x31 };
    try std.testing.expectEqualSlices(u8, &expected, top.data[0..20]);
}

// ── Other: OP_CODESEPARATOR ──

test "OP_CODESEPARATOR: no stack change" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x42});
    const depth_before = p.sdepth();
    try execOp(&p, standard.OP_CODESEPARATOR);
    const depth_after = p.sdepth();
    try std.testing.expectEqual(depth_before, depth_after);
}

test "OP_CODESEPARATOR: does not consume stack items" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0xAA});
    try p.spush(&[_]u8{0xBB});
    try p.spush(&[_]u8{0xCC});
    try execOp(&p, standard.OP_CODESEPARATOR);
    const top = try p.speek();
    try std.testing.expectEqual(@as(u8, 0xCC), top.data[0]);
}

```
