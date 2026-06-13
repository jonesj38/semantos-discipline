---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/macro_legacy_equivalence.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.967588+00:00
---

# core/cell-engine/tests/macro_legacy_equivalence.zig

```zig
// macro_legacy_equivalence — proves the TS unroller's LEGACY lowering of each
// native Craig macro (cartridges/wallet-headers/brain/src/script-macro.ts) is
// faithful: running the legacy-opcode bytecode through the executor must leave
// the SAME PDA stack as executing the native single-byte macro opcode.
//
// macro.zig (0xB0–0xB8) is the oracle. The byte expansions below are the exact
// strings the TS macros emit; if they drift, this test fails. This is the
// "both layers" guarantee: native macro for our SPV-on-spend engine, legacy
// lowering for public miners — provably the same transition.

const std = @import("std");
const pda_mod = @import("pda");
const macro = @import("macro");
const executor = @import("executor");
const allocator_mod = @import("allocator");

/// Run a legacy-opcode script against a PDA seeded with `inputs` (bottom→top).
fn runLegacy(p: *pda_mod.PDA, inputs: []const []const u8, script: []const u8) !void {
    for (inputs) |item| try p.spush(item);
    var arena_buf: [8192]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);
    var ctx = executor.ExecutionContext.init(p, &arena);
    try ctx.loadScript(script);
    _ = try executor.execute(&ctx);
}

/// Run a native macro opcode against a PDA seeded with `inputs` (bottom→top).
fn runNative(p: *pda_mod.PDA, inputs: []const []const u8, opcode: u8) !void {
    for (inputs) |item| try p.spush(item);
    try macro.executeMacro(p, opcode);
}

/// Assert two PDAs hold identical main stacks (depth + each slot's bytes).
fn expectSameStack(a: *pda_mod.PDA, b: *pda_mod.PDA) !void {
    try std.testing.expectEqual(a.sdepth(), b.sdepth());
    var i: u32 = 0;
    while (i < a.sdepth()) : (i += 1) {
        const la = a.main_lengths[i];
        const lb = b.main_lengths[i];
        try std.testing.expectEqual(la, lb);
        try std.testing.expectEqualSlices(u8, a.main_stack[i][0..la], b.main_stack[i][0..lb]);
    }
}

/// Drive native(opcode) vs legacy(script) on identical inputs; assert equal.
fn expectEquivalent(inputs: []const []const u8, opcode: u8, script: []const u8) !void {
    var native = pda_mod.PDA.init(500000);
    var legacy = pda_mod.PDA.init(500000);
    try runNative(&native, inputs, opcode);
    try runLegacy(&legacy, inputs, script);
    try expectSameStack(&native, &legacy);
}

const a1 = [_]u8{0x01};
const a2 = [_]u8{0x02};
const a3 = [_]u8{0x03};
const a4 = [_]u8{0x04};
const a5 = [_]u8{0x05};

// ── XSWAP: native 0xB0/B1/B2 vs TS xSwap(2|3|4) ──

test "XSWAP-2: native 0xB0 == OP_SWAP" {
    try expectEquivalent(&.{ &a1, &a2 }, 0xB0, &[_]u8{0x7c});
}

test "XSWAP-3: native 0xB1 == OP_SWAP OP_ROT" {
    try expectEquivalent(&.{ &a1, &a2, &a3 }, 0xB1, &[_]u8{ 0x7c, 0x7b });
}

test "XSWAP-4: native 0xB2 == <3> OP_ROLL OP_TOALTSTACK <2> OP_ROLL <2> OP_ROLL OP_FROMALTSTACK" {
    try expectEquivalent(
        &.{ &a1, &a2, &a3, &a4 },
        0xB2,
        &[_]u8{ 0x53, 0x7a, 0x6b, 0x52, 0x7a, 0x52, 0x7a, 0x6c },
    );
}

// ── XDROP: native 0xB3/B4/B5 vs TS xDrop(2|3|4) == N × OP_DROP ──

test "XDROP-2: native 0xB3 == OP_DROP OP_DROP" {
    try expectEquivalent(&.{ &a1, &a2, &a3 }, 0xB3, &[_]u8{ 0x75, 0x75 });
}

test "XDROP-3: native 0xB4 == OP_DROP x3" {
    try expectEquivalent(&.{ &a1, &a2, &a3, &a4 }, 0xB4, &[_]u8{ 0x75, 0x75, 0x75 });
}

test "XDROP-4: native 0xB5 == OP_DROP x4" {
    try expectEquivalent(&.{ &a1, &a2, &a3, &a4, &a5 }, 0xB5, &[_]u8{ 0x75, 0x75, 0x75, 0x75 });
}

// ── XROT: native 0xB6/B7 vs TS xRot(3|4) == <n-1> OP_ROLL ──

test "XROT-3: native 0xB6 == OP_2 OP_ROLL (OP_ROT)" {
    try expectEquivalent(&.{ &a1, &a2, &a3 }, 0xB6, &[_]u8{ 0x52, 0x7a });
}

test "XROT-4: native 0xB7 == OP_3 OP_ROLL" {
    try expectEquivalent(&.{ &a1, &a2, &a3, &a4 }, 0xB7, &[_]u8{ 0x53, 0x7a });
}

// ── HASHCAT: native 0xB8 vs TS hashCat() == OP_CAT OP_SHA256 ──

test "HASHCAT: native 0xB8 == OP_CAT OP_SHA256" {
    const ab = [_]u8{ 0x01, 0x02 };
    const cd = [_]u8{ 0x03, 0x04 };
    try expectEquivalent(&.{ &ab, &cd }, 0xB8, &[_]u8{ 0x7e, 0xa8 });
}

```
