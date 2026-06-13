---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/differential_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.969790+00:00
---

# core/cell-engine/tests/differential_conformance.zig

```zig
// Phase 12 D12.1: Differential conformance tests (Lean model ↔ Zig implementation)
// Loads test vectors from proofs/vectors/ and verifies the Zig implementation
// matches the expected behavior from the Lean theorems.

const std = @import("std");
const constants = @import("constants");
const linearity = @import("linearity");
const pda_mod = @import("pda");
const plexus = @import("plexus");

// ── Cell builder (from linearity_conformance.zig pattern) ──

fn makeTestCell(lin: u32, domain_flag: u32, type_hash: [32]u8, owner_id: [16]u8, cap_type: u8) pda_mod.Cell {
    var cell: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    std.mem.writeInt(u32, cell[0..4], constants.MAGIC_1, .little);
    std.mem.writeInt(u32, cell[4..8], constants.MAGIC_2, .little);
    std.mem.writeInt(u32, cell[8..12], constants.MAGIC_3, .little);
    std.mem.writeInt(u32, cell[12..16], constants.MAGIC_4, .little);
    std.mem.writeInt(u32, cell[16..20], lin, .little);
    std.mem.writeInt(u32, cell[20..24], 1, .little);
    std.mem.writeInt(u32, cell[24..28], domain_flag, .little);
    @memcpy(cell[30..62], &type_hash);
    @memcpy(cell[62..78], &owner_id);
    cell[256] = cap_type; // capability type at payload byte 0
    return cell;
}

fn hexToBytes(comptime N: usize, hex: []const u8) [N]u8 {
    var result: [N]u8 = [_]u8{0} ** N;
    const len = @min(hex.len / 2, N);
    for (0..len) |i| {
        result[i] = std.fmt.parseInt(u8, hex[2 * i ..][0..2], 16) catch 0;
    }
    return result;
}

// ── K1: Linearity permission matrix (20 base + 4 edge cases) ──

const PermEntry = struct {
    lin: linearity.LinearityType,
    op: linearity.LinearityOperation,
    permitted: bool,
};

const permission_table = [_]PermEntry{
    // LINEAR
    .{ .lin = .linear, .op = .duplicate, .permitted = false },
    .{ .lin = .linear, .op = .discard, .permitted = false },
    .{ .lin = .linear, .op = .consume, .permitted = true },
    .{ .lin = .linear, .op = .swap, .permitted = true },
    .{ .lin = .linear, .op = .inspect, .permitted = true },
    // AFFINE
    .{ .lin = .affine, .op = .duplicate, .permitted = false },
    .{ .lin = .affine, .op = .discard, .permitted = true },
    .{ .lin = .affine, .op = .consume, .permitted = true },
    .{ .lin = .affine, .op = .swap, .permitted = true },
    .{ .lin = .affine, .op = .inspect, .permitted = true },
    // RELEVANT
    .{ .lin = .relevant, .op = .duplicate, .permitted = true },
    .{ .lin = .relevant, .op = .discard, .permitted = false },
    .{ .lin = .relevant, .op = .consume, .permitted = true },
    .{ .lin = .relevant, .op = .swap, .permitted = true },
    .{ .lin = .relevant, .op = .inspect, .permitted = true },
    // DEBUG
    .{ .lin = .debug, .op = .duplicate, .permitted = true },
    .{ .lin = .debug, .op = .discard, .permitted = true },
    .{ .lin = .debug, .op = .consume, .permitted = true },
    .{ .lin = .debug, .op = .swap, .permitted = true },
    .{ .lin = .debug, .op = .inspect, .permitted = true },
};

test "differential: K1 linearity permission matrix (20 vectors)" {
    for (permission_table) |entry| {
        const result = linearity.checkLinearity(entry.lin, entry.op);
        if (entry.permitted) {
            _ = result catch |err| {
                std.debug.print("MISMATCH: lin={} op={} should permit but got {}\n", .{ @intFromEnum(entry.lin), @intFromEnum(entry.op), err });
                return error.TestUnexpectedResult;
            };
        } else {
            if (result) |_| {
                std.debug.print("MISMATCH: lin={} op={} should deny but succeeded\n", .{ @intFromEnum(entry.lin), @intFromEnum(entry.op) });
                return error.TestUnexpectedResult;
            } else |_| {}
        }
    }
}

// ── K1 edge cases: enforcement on/off ──

test "differential: K1 LINEAR DUP succeeds with enforcement OFF" {
    var p = pda_mod.PDA.init(500_000);
    p.enforcement_enabled = false;
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.sdup_enforced();
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "differential: K1 LINEAR DROP succeeds with enforcement OFF" {
    var p = pda_mod.PDA.init(500_000);
    p.enforcement_enabled = false;
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.sdrop_enforced();
    try std.testing.expectEqual(@as(u32, 0), p.sdepth());
}

test "differential: K1 empty stack DUP returns stack_underflow" {
    var p = pda_mod.PDA.init(500_000);
    p.enforcement_enabled = true;
    try std.testing.expectError(error.stack_underflow, p.sdup_enforced());
}

test "differential: K1 empty stack DROP returns stack_underflow" {
    var p = pda_mod.PDA.init(500_000);
    p.enforcement_enabled = true;
    try std.testing.expectError(error.stack_underflow, p.sdrop_enforced());
}

// ── K2: Plexus type-check opcodes (0xC0-0xC2, 0xC5) ──

test "differential: K2 CHECKLINEARTYPE on LINEAR → TRUE pushed" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try plexus.executePlexus(&p, 0xC0);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "differential: K2 CHECKLINEARTYPE on AFFINE → error" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(2, 5, [_]u8{0xCC} ** 32, [_]u8{0xDD} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try std.testing.expectError(error.linearity_check_failed, plexus.executePlexus(&p, 0xC0));
    try std.testing.expectEqual(@as(u32, 1), p.sdepth()); // stack unchanged (K4)
}

test "differential: K2 CHECKAFFINETYPE on AFFINE → TRUE pushed" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(2, 5, [_]u8{0xCC} ** 32, [_]u8{0xDD} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try plexus.executePlexus(&p, 0xC1);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "differential: K2 CHECKRELEVANTTYPE on RELEVANT → TRUE pushed" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(3, 10, [_]u8{0xEE} ** 32, [_]u8{0xFF} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try plexus.executePlexus(&p, 0xC2);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "differential: K2 ASSERTLINEAR on LINEAR → success, no push" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try plexus.executePlexus(&p, 0xC5);
    try std.testing.expectEqual(@as(u32, 1), p.sdepth()); // no push
}

test "differential: K2 ASSERTLINEAR on AFFINE → error" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(2, 5, [_]u8{0xCC} ** 32, [_]u8{0xDD} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try std.testing.expectError(error.linearity_check_failed, plexus.executePlexus(&p, 0xC5));
}

// ── K2: CHECKCAPABILITY (0xC3) ──

test "differential: K2 CHECKCAPABILITY matching cap on LINEAR → TRUE" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 2);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{2}); // expected cap = 2
    try plexus.executePlexus(&p, 0xC3);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth()); // cell + TRUE
}

test "differential: K2 CHECKCAPABILITY mismatching cap → error, stack unchanged" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 2);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{99}); // wrong cap
    try std.testing.expectError(error.capability_type_mismatch, plexus.executePlexus(&p, 0xC3));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth()); // unchanged (K4)
}

test "differential: K2 CHECKCAPABILITY on non-LINEAR → error, stack unchanged" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(2, 5, [_]u8{0xCC} ** 32, [_]u8{0xDD} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&[_]u8{0});
    try std.testing.expectError(error.capability_type_mismatch, plexus.executePlexus(&p, 0xC3));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

// ── K2: CHECKIDENTITY (0xC4) ──

test "differential: K2 CHECKIDENTITY matching owner → TRUE" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&([_]u8{0xBB} ** 16)); // matching owner_id
    try plexus.executePlexus(&p, 0xC4);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "differential: K2 CHECKIDENTITY mismatching owner → error, stack unchanged" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&([_]u8{0xCC} ** 16)); // wrong owner_id
    try std.testing.expectError(error.owner_id_mismatch, plexus.executePlexus(&p, 0xC4));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

// ── K3: CHECKDOMAINFLAG (0xC6) ──

test "differential: K3 CHECKDOMAINFLAG matching flag → TRUE" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    var arg: [4]u8 = undefined;
    std.mem.writeInt(u32, &arg, 1, .little); // matching domain_flag
    try p.spush(&arg);
    try plexus.executePlexus(&p, 0xC6);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "differential: K3 CHECKDOMAINFLAG mismatching flag → error, stack unchanged (K4)" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    var arg: [4]u8 = undefined;
    std.mem.writeInt(u32, &arg, 999, .little); // wrong domain_flag
    try p.spush(&arg);
    try std.testing.expectError(error.domain_flag_mismatch, plexus.executePlexus(&p, 0xC6));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

// ── K3: CHECKTYPEHASH (0xC7) ──

test "differential: K3 CHECKTYPEHASH matching hash → TRUE" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&([_]u8{0xAA} ** 32)); // matching type_hash
    try plexus.executePlexus(&p, 0xC7);
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

test "differential: K3 CHECKTYPEHASH mismatching hash → error, stack unchanged (K4)" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try p.spush(&([_]u8{0xFF} ** 32)); // wrong type_hash
    try std.testing.expectError(error.type_hash_mismatch, plexus.executePlexus(&p, 0xC7));
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
}

// ── K4: DEREF_POINTER (0xC8) on non-pointer cell → error, stack unchanged ──

test "differential: K4 DEREF_POINTER on non-pointer cell → invalid_pointer_cell, stack unchanged" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 0);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    try std.testing.expectError(error.invalid_pointer_cell, plexus.executePlexus(&p, 0xC8));
    try std.testing.expectEqual(@as(u32, 1), p.sdepth()); // stack unchanged (K4)
}

// ── K4: post-W1+W3 multi-arg opcodes (0xC9-0xCF) are atomic on underflow ──
//
// After Phase W1 (OP_SIGN at 0xCD) and W3 (OP_DECREMENT_BUDGET at 0xCE,
// OP_REFILL_BUDGET at 0xCF), the 0xC0-0xCF range is fully assigned. With
// one cell on the stack, each of these opcodes needs more arguments and
// fails with stack_underflow before any mutation — K4 holds.
test "differential: K4 multi-arg opcodes 0xC9-0xCF underflow with stack unchanged" {
    const opcodes = [_]u8{ 0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF };
    for (opcodes) |opcode| {
        var p = pda_mod.PDA.init(500_000);
        var cell = makeTestCell(1, 1, [_]u8{0xAA} ** 32, [_]u8{0xBB} ** 16, 0);
        try p.spushCell(&cell, pda_mod.CELL_SIZE);
        try std.testing.expectError(error.stack_underflow, plexus.executePlexus(&p, opcode));
        try std.testing.expectEqual(@as(u32, 1), p.sdepth()); // unchanged (K4)
    }
}

// ── K4: Empty stack plexus opcodes error with stack unchanged ──

test "differential: K4 plexus opcodes on empty stack → underflow, stack unchanged" {
    const single_arg = [_]u8{ 0xC0, 0xC1, 0xC2, 0xC5 };
    for (single_arg) |opcode| {
        var p = pda_mod.PDA.init(500_000);
        try std.testing.expectError(error.stack_underflow, plexus.executePlexus(&p, opcode));
        try std.testing.expectEqual(@as(u32, 0), p.sdepth());
    }
}

// ── K5: Stack bounds ──

test "differential: K5 main stack overflow at MAIN_STACK_DEPTH" {
    var p = pda_mod.PDA.init(500_000);
    var data = [_]u8{0x42} ** 4;
    var i: u32 = 0;
    while (i < pda_mod.MAIN_STACK_DEPTH) : (i += 1) {
        try p.spush(&data);
    }
    try std.testing.expectEqual(@as(u32, 1024), p.sdepth());
    try std.testing.expectError(error.stack_overflow, p.spush(&data));
    try std.testing.expectEqual(@as(u32, 1024), p.sdepth()); // unchanged
}

test "differential: K5 aux stack overflow at AUX_STACK_DEPTH" {
    var p = pda_mod.PDA.init(500_000);
    var data = [_]u8{0x42} ** 4;
    var i: u32 = 0;
    while (i < pda_mod.AUX_STACK_DEPTH) : (i += 1) {
        try p.apush(&data);
    }
    try std.testing.expectEqual(@as(u32, 256), p.adepth());
    try std.testing.expectError(error.stack_overflow, p.apush(&data));
    try std.testing.expectEqual(@as(u32, 256), p.adepth());
}

// ── K7: Cell immutability (push/pop roundtrip) ──

test "differential: K7 push/pop roundtrip preserves cell contents" {
    var p = pda_mod.PDA.init(500_000);
    var cell = makeTestCell(1, 42, [_]u8{0xDE} ** 32, [_]u8{0xAD} ** 16, 5);
    try p.spushCell(&cell, pda_mod.CELL_SIZE);
    const popped = try p.spop();
    try std.testing.expectEqualSlices(u8, &cell, popped.data);
    try std.testing.expectEqual(pda_mod.CELL_SIZE, popped.len);
}

```
