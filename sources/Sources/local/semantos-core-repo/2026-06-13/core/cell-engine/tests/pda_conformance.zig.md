---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/pda_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.963153+00:00
---

# core/cell-engine/tests/pda_conformance.zig

```zig
const std = @import("std");
const pda_mod = @import("pda");

// ── Push/Pop round-trip ──

test "spush/spop round-trip preserves data" {
    var p = pda_mod.PDA.init(500000);
    const data = "hello world";
    try p.spush(data);
    const result = try p.spop();
    try std.testing.expectEqualSlices(u8, data, result.data[0..result.len]);
}

test "spush/spop round-trip preserves 1KB cell" {
    var p = pda_mod.PDA.init(500000);
    var data: [1024]u8 = undefined;
    for (&data, 0..) |*b, i| b.* = @truncate(i);
    try p.spush(&data);
    const result = try p.spop();
    try std.testing.expectEqualSlices(u8, &data, result.data[0..result.len]);
}

// ── Overflow/Underflow ──

test "stack overflow at MAIN_STACK_DEPTH" {
    var p = pda_mod.PDA.init(500000);
    const data = [_]u8{0x42};
    var i: u32 = 0;
    while (i < pda_mod.MAIN_STACK_DEPTH) : (i += 1) {
        try p.spush(&data);
    }
    try std.testing.expectEqual(@as(u32, 1024), p.sdepth());
    try std.testing.expectError(error.stack_overflow, p.spush(&data));
}

test "stack underflow on empty stack" {
    var p = pda_mod.PDA.init(500000);
    try std.testing.expectError(error.stack_underflow, p.spop());
}

test "aux stack overflow at AUX_STACK_DEPTH" {
    var p = pda_mod.PDA.init(500000);
    const data = [_]u8{0x01};
    var i: u32 = 0;
    while (i < pda_mod.AUX_STACK_DEPTH) : (i += 1) {
        try p.apush(&data);
    }
    try std.testing.expectEqual(@as(u32, 256), p.adepth());
    try std.testing.expectError(error.stack_overflow, p.apush(&data));
}

test "aux stack underflow on empty" {
    var p = pda_mod.PDA.init(500000);
    try std.testing.expectError(error.stack_underflow, p.apop());
}

// ── Depth ──

test "sdepth returns correct count" {
    var p = pda_mod.PDA.init(500000);
    try std.testing.expectEqual(@as(u32, 0), p.sdepth());
    try p.spush(&[_]u8{1});
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    try p.spush(&[_]u8{2});
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());
    _ = try p.spop();
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

test "sempty returns true when empty" {
    var p = pda_mod.PDA.init(500000);
    try std.testing.expect(p.sempty());
    try p.spush(&[_]u8{1});
    try std.testing.expect(!p.sempty());
}

// ── LIFO ordering ──

test "LIFO ordering: last in first out" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try p.spush(&[_]u8{0x03});

    const c = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x03), c.data[0]);
    const b = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), b.data[0]);
    const a = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), a.data[0]);
}

// ── Stack manipulation ──

test "sdup creates independent copy" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{ 0xAA, 0xBB });
    try p.sdup();
    try std.testing.expectEqual(@as(u32, 2), p.sdepth());

    const top = try p.spop();
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xAA, 0xBB }, top.data[0..top.len]);
    const orig = try p.spop();
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xAA, 0xBB }, orig.data[0..orig.len]);
}

test "sswap exchanges top two cells" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try p.sswap();

    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), top.data[0]);
    const second = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), second.data[0]);
}

test "srot rotates top three cells" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01}); // bottom
    try p.spush(&[_]u8{0x02});
    try p.spush(&[_]u8{0x03}); // top
    // Before: 1 2 3 (top=3). After ROT: 2 3 1 (top=1)
    try p.srot();

    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), top.data[0]);
    const mid = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x03), mid.data[0]);
    const bot = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), bot.data[0]);
}

test "sover copies second element to top" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try p.sover();
    try std.testing.expectEqual(@as(u32, 3), p.sdepth());

    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), top.data[0]);
}

test "spick(n) copies nth element to top" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x0A});
    try p.spush(&[_]u8{0x0B});
    try p.spush(&[_]u8{0x0C});
    try p.spick(2); // pick element at depth 2 (0x0A)

    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x0A), top.data[0]);
    try std.testing.expectEqual(@as(u32, 3), p.sdepth());
}

test "spick with n >= depth returns underflow" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try std.testing.expectError(error.stack_underflow, p.spick(1));
}

test "sroll(n) moves nth element to top" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x0A});
    try p.spush(&[_]u8{0x0B});
    try p.spush(&[_]u8{0x0C});
    try p.sroll(2); // roll element at depth 2 to top

    try std.testing.expectEqual(@as(u32, 3), p.sdepth());
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x0A), top.data[0]);
    const mid = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x0C), mid.data[0]);
    const bot = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x0B), bot.data[0]);
}

// ── Alt stack operations ──

test "toalt/fromalt transfers cell between stacks" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{ 0xDE, 0xAD });
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    try std.testing.expectEqual(@as(u32, 0), p.adepth());

    try p.toalt();
    try std.testing.expectEqual(@as(u32, 0), p.sdepth());
    try std.testing.expectEqual(@as(u32, 1), p.adepth());

    try p.fromalt();
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    try std.testing.expectEqual(@as(u32, 0), p.adepth());

    const result = try p.spop();
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xDE, 0xAD }, result.data[0..result.len]);
}

// ── NIP, TUCK ──

test "snip removes second element" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try p.snip();
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), top.data[0]);
}

test "stuck inserts top before second" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    // Before: 1 2 (top=2). After TUCK: 2 1 2 (top=2)
    try p.stuck();
    try std.testing.expectEqual(@as(u32, 3), p.sdepth());

    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), top.data[0]);
    const mid = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), mid.data[0]);
    const bot = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), bot.data[0]);
}

// ── 2DUP, 3DUP, 2DROP, 2SWAP ──

test "s2dup duplicates top two" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try p.s2dup();
    try std.testing.expectEqual(@as(u32, 4), p.sdepth());

    const d = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), d.data[0]);
    const c = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), c.data[0]);
}

test "s2drop removes top two" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try p.spush(&[_]u8{0x03});
    try p.s2drop();
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

test "s2swap swaps top two pairs" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01}); // a
    try p.spush(&[_]u8{0x02}); // b
    try p.spush(&[_]u8{0x03}); // c
    try p.spush(&[_]u8{0x04}); // d
    // Before: 1 2 3 4. After 2SWAP: 3 4 1 2
    try p.s2swap();

    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), top.data[0]);
    const n2 = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), n2.data[0]);
    const n3 = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x04), n3.data[0]);
    const n4 = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x03), n4.data[0]);
}

// ── Reset ──

test "reset clears all state" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.apush(&[_]u8{0x02});
    p.reset();
    try std.testing.expectEqual(@as(u32, 0), p.sdepth());
    try std.testing.expectEqual(@as(u32, 0), p.adepth());
    try std.testing.expectEqual(@as(u32, 0), p.opcount);
}

// ── Script number encoding ──

test "cellToI64: empty = 0" {
    const result = pda_mod.cellToI64(&[_]u8{});
    try std.testing.expectEqual(@as(i64, 0), result);
}

test "cellToI64: 0x80 alone = negative zero = 0" {
    const result = pda_mod.cellToI64(&[_]u8{0x80});
    try std.testing.expectEqual(@as(i64, 0), result);
}

test "cellToI64: 0x81 = -1" {
    const result = pda_mod.cellToI64(&[_]u8{0x81});
    try std.testing.expectEqual(@as(i64, -1), result);
}

test "cellToI64: 0x01 0x80 = -1 (two bytes)" {
    const result = pda_mod.cellToI64(&[_]u8{ 0x01, 0x80 });
    try std.testing.expectEqual(@as(i64, -1), result);
}

test "cellToI64: 0x05 = 5" {
    const result = pda_mod.cellToI64(&[_]u8{0x05});
    try std.testing.expectEqual(@as(i64, 5), result);
}

test "cellToI64: 0x85 = -5" {
    const result = pda_mod.cellToI64(&[_]u8{0x85});
    try std.testing.expectEqual(@as(i64, -5), result);
}

test "cellToI64: 0xFF 0x00 = 255" {
    const result = pda_mod.cellToI64(&[_]u8{ 0xFF, 0x00 });
    try std.testing.expectEqual(@as(i64, 255), result);
}

test "i64ToCell round-trip" {
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(42, &cell);
    const back = pda_mod.cellToI64(cell[0..len]);
    try std.testing.expectEqual(@as(i64, 42), back);
}

test "i64ToCell negative round-trip" {
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(-42, &cell);
    const back = pda_mod.cellToI64(cell[0..len]);
    try std.testing.expectEqual(@as(i64, -42), back);
}

test "i64ToCell zero returns length 0" {
    var cell: pda_mod.Cell = undefined;
    const len = pda_mod.i64ToCell(0, &cell);
    try std.testing.expectEqual(@as(u32, 0), len);
}

// ── isTruthy ──

test "isTruthy: empty is falsy" {
    var cell: pda_mod.Cell = [_]u8{0} ** 1024;
    try std.testing.expect(!pda_mod.isTruthy(&cell, 0));
}

test "isTruthy: 0x80 alone is falsy (negative zero)" {
    var cell: pda_mod.Cell = [_]u8{0} ** 1024;
    cell[0] = 0x80;
    try std.testing.expect(!pda_mod.isTruthy(&cell, 1));
}

test "isTruthy: 0x01 is truthy" {
    var cell: pda_mod.Cell = [_]u8{0} ** 1024;
    cell[0] = 0x01;
    try std.testing.expect(pda_mod.isTruthy(&cell, 1));
}

test "isTruthy: all zeros is falsy" {
    var cell: pda_mod.Cell = [_]u8{0} ** 1024;
    try std.testing.expect(!pda_mod.isTruthy(&cell, 4));
}

test "isTruthy: 0x00 0x80 is falsy (negative zero, 2 bytes)" {
    var cell: pda_mod.Cell = [_]u8{0} ** 1024;
    cell[1] = 0x80;
    try std.testing.expect(!pda_mod.isTruthy(&cell, 2));
}

```
