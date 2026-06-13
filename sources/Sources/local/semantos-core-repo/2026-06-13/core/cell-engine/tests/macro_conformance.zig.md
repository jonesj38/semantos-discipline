---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/macro_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.957871+00:00
---

# core/cell-engine/tests/macro_conformance.zig

```zig
const std = @import("std");
const pda_mod = @import("pda");
const macro = @import("macro");
const host = @import("host");

// ── XSWAP ──

test "XSWAP-2 (0xB0) swaps top with 2nd (like OP_SWAP)" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try macro.executeMacro(&p, 0xB0);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), top.data[0]);
    const second = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), second.data[0]);
}

test "XSWAP-3 (0xB1) swaps top with 3rd" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01}); // 3rd
    try p.spush(&[_]u8{0x02}); // 2nd
    try p.spush(&[_]u8{0x03}); // top
    try macro.executeMacro(&p, 0xB1);
    // After: top=0x01, 2nd=0x02, 3rd=0x03
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), top.data[0]);
    const mid = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), mid.data[0]);
    const bot = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x03), bot.data[0]);
}

test "XSWAP-4 (0xB2) swaps top with 4th" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01}); // 4th
    try p.spush(&[_]u8{0x02}); // 3rd
    try p.spush(&[_]u8{0x03}); // 2nd
    try p.spush(&[_]u8{0x04}); // top
    try macro.executeMacro(&p, 0xB2);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), top.data[0]);
}

// ── XDROP ──

test "XDROP-2 (0xB3) drops top 2 elements" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try p.spush(&[_]u8{0x03});
    try macro.executeMacro(&p, 0xB3);
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    const item = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), item.data[0]);
}

test "XDROP-3 (0xB4) drops top 3 elements" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try p.spush(&[_]u8{0x03});
    try p.spush(&[_]u8{0x04});
    try macro.executeMacro(&p, 0xB4);
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

test "XDROP-4 (0xB5) drops top 4 elements" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02});
    try p.spush(&[_]u8{0x03});
    try p.spush(&[_]u8{0x04});
    try p.spush(&[_]u8{0x05});
    try macro.executeMacro(&p, 0xB5);
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
}

// ── XROT ──

test "XROT-3 (0xB6) rotates top 3 (like OP_ROT)" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01}); // bottom of group
    try p.spush(&[_]u8{0x02});
    try p.spush(&[_]u8{0x03}); // top
    // Before: 1 2 3. After XROT-3: 2 3 1 (bottom moves to top)
    try macro.executeMacro(&p, 0xB6);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), top.data[0]);
    const mid = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x03), mid.data[0]);
    const bot = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), bot.data[0]);
}

test "XROT-4 (0xB7) rotates top 4, bringing 4th to top" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01}); // 4th (bottom of group)
    try p.spush(&[_]u8{0x02}); // 3rd
    try p.spush(&[_]u8{0x03}); // 2nd
    try p.spush(&[_]u8{0x04}); // top
    // Before: 1 2 3 4. After XROT-4: 2 3 4 1
    try macro.executeMacro(&p, 0xB7);
    const top = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x01), top.data[0]);
    const n2 = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x04), n2.data[0]);
    const n3 = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x03), n3.data[0]);
    const n4 = try p.spop();
    try std.testing.expectEqual(@as(u8, 0x02), n4.data[0]);
}

// ── HASHCAT ──

test "HASHCAT (0xB8): SHA256(a||b)" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{ 0x01, 0x02 });
    try p.spush(&[_]u8{ 0x03, 0x04 });
    try macro.executeMacro(&p, 0xB8);
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    const item = try p.spop();
    try std.testing.expectEqual(@as(u32, 32), item.len); // SHA256 = 32 bytes

    // Verify it matches SHA256([0x01, 0x02, 0x03, 0x04])
    var expected: [32]u8 = undefined;
    host.sha256(&[_]u8{ 0x01, 0x02, 0x03, 0x04 }, &expected);
    try std.testing.expectEqualSlices(u8, &expected, item.data[0..32]);
}

// ── Error cases ──

test "XSWAP-2 with insufficient stack depth returns underflow" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01}); // only 1 element
    try std.testing.expectError(error.stack_underflow, macro.executeMacro(&p, 0xB0));
}

test "XDROP-3 with insufficient stack depth returns underflow" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{0x02}); // only 2 elements
    try std.testing.expectError(error.stack_underflow, macro.executeMacro(&p, 0xB4));
}

test "unknown macro 0xBF returns unknown_macro" {
    var p = pda_mod.PDA.init(500000);
    try std.testing.expectError(error.unknown_macro, macro.executeMacro(&p, 0xBF));
}

// ── Failure atomicity tests ──

test "HASHCAT with 1 element: stack unchanged on underflow" {
    // BUG: hashcat pops b first, then fails on a. Stack is partially mutated.
    // After fix: stack must be unchanged on error.
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x42});
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    try std.testing.expectError(error.stack_underflow, macro.executeMacro(&p, 0xB8));
    // Stack must still have exactly 1 element — the original
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    const top = try p.speek();
    try std.testing.expectEqual(@as(u8, 0x42), top.data[0]);
}

test "HASHCAT with empty stack: stack unchanged on underflow" {
    var p = pda_mod.PDA.init(500000);
    try std.testing.expectEqual(@as(u32, 0), p.sdepth());
    try std.testing.expectError(error.stack_underflow, macro.executeMacro(&p, 0xB8));
    try std.testing.expectEqual(@as(u32, 0), p.sdepth());
}

// ── Buffer bounds test ──

test "HASHCAT with two max-length cells: concat fits in buffer" {
    var p = pda_mod.PDA.init(500000);
    // Push two full 1024-byte cells
    var a_data: [pda_mod.CELL_SIZE]u8 = undefined;
    @memset(&a_data, 0xAA);
    var b_data: [pda_mod.CELL_SIZE]u8 = undefined;
    @memset(&b_data, 0xBB);
    try p.spush(&a_data);
    try p.spush(&b_data);
    try macro.executeMacro(&p, 0xB8);
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    const result = try p.spop();
    try std.testing.expectEqual(@as(u32, 32), result.len); // SHA256 output

    // Verify it matches SHA256(0xAA*1024 || 0xBB*1024)
    var concat: [2048]u8 = undefined;
    @memset(concat[0..1024], 0xAA);
    @memset(concat[1024..2048], 0xBB);
    var expected: [32]u8 = undefined;
    host.sha256(&concat, &expected);
    try std.testing.expectEqualSlices(u8, &expected, result.data[0..32]);
}

// ── XDROP hygiene test ──

test "XDROP-2 zeroes lengths of dropped slots" {
    var p = pda_mod.PDA.init(500000);
    try p.spush(&[_]u8{0x01});
    try p.spush(&[_]u8{ 0x02, 0x03 }); // len=2
    try p.spush(&[_]u8{ 0x04, 0x05, 0x06 }); // len=3
    // Before drop: sp=3, lengths at [1]=2, [2]=3
    try macro.executeMacro(&p, 0xB3); // XDROP-2
    try std.testing.expectEqual(@as(u32, 1), p.sdepth());
    // After drop: slots at index 1 and 2 should have length zeroed
    try std.testing.expectEqual(@as(u32, 0), p.main_lengths[1]);
    try std.testing.expectEqual(@as(u32, 0), p.main_lengths[2]);
}

```
