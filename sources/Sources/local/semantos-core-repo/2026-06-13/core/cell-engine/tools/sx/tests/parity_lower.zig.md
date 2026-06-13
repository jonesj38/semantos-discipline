---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/tests/parity_lower.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.994843+00:00
---

# core/cell-engine/tools/sx/tests/parity_lower.zig

```zig
//! End-to-end parity test for the lexer → parser → lowerer pipeline.
//!
//! Each case takes a `.sx` source string, runs it through the full
//! pipeline, and asserts the produced unlockingHex / lockingHex matches
//! the expected lowercase hex string.
//!
//! ## How to add a case
//!
//! 1. Run his JS compiler on the same source (`yarn sx <file>` or
//!    via Jest setup) and capture the unlockingHex / lockingHex outputs
//! 2. Add an entry below with the expected hex strings
//! 3. Run `zig build test`
//! 4. If it fails: fix `lower.zig` or upstream pipeline (NOT the
//!    expectation), unless the JS compiler output is itself wrong (rare)
//!
//! ## Coverage state
//!
//! PR-3 skeleton — 9 cases hand-crafted from the BSV / Bitcoin Script
//! spec. PR-3.1+ will drive his `src/sx/contracts/*.sx` corpus directly,
//! using his compiler output as goldens checked into the repo.
//!
//! ## Out of scope for PR-3 skeleton
//!
//! Lower-side features that need iteration:
//! - argument slot replacement (.argName)
//! - repeat unrolling
//! - call expansion (look up function body, inline)
//! - pushCodeData → single pushdata bundle
//! - asm-string output

const std = @import("std");
const sx = @import("sx");

const Case = struct {
    name: []const u8,
    source: []const u8,
    expected_unlocking_hex: []const u8 = "",
    expected_locking_hex: []const u8 = "",
};

/// Hex byte references used in cases:
///   OP_NOP        = 0x61
///   OP_DUP        = 0x76
///   OP_HASH160    = 0xa9
///   OP_EQUALVERIFY= 0x88
///   OP_CHECKSIG   = 0xac
///   OP_0          = 0x00
///   OP_1NEGATE    = 0x4f
///   OP_1..OP_16   = 0x51..0x60
///   OP_PUSHDATA1  = 0x4c
///   OP_PUSHDATA2  = 0x4d
///
/// Pushdata: 1..75 bytes = single length byte + data
///           76..255     = 0x4c + 1-byte length + data
const CASES = [_]Case{
    .{
        .name = "single nop",
        .source = "nop",
        .expected_unlocking_hex = "61",
    },
    .{
        .name = "two opcodes in sequence",
        .source = "dup hash160",
        .expected_unlocking_hex = "76a9",
    },
    .{
        .name = "bare hex pushes with length-1 prefix",
        .source = "ab",
        .expected_unlocking_hex = "01ab",
    },
    .{
        .name = "4-byte hex push",
        .source = "deadbeef",
        .expected_unlocking_hex = "04deadbeef",
    },
    .{
        .name = "single-char string pushes single byte",
        .source = "'a'",
        // 'a' = 0x61, push as 1 byte → "0161"
        .expected_unlocking_hex = "0161",
    },
    .{
        .name = "OP_0 from bigint 0n",
        .source = "0n",
        .expected_unlocking_hex = "00",
    },
    .{
        .name = "OP_3 from bigint 3n",
        .source = "3n",
        .expected_unlocking_hex = "53",
    },
    .{
        .name = "OP_1NEGATE from bigint -1n",
        .source = "-1n",
        .expected_unlocking_hex = "4f",
    },
    .{
        .name = "negative-123 bigint as CScriptNum push",
        .source = "-123n",
        // -123 → CScriptNum "fb" (1 byte) → push as 0x01 0xfb
        .expected_unlocking_hex = "01fb",
    },
    .{
        .name = "section separator splits unlock/lock outputs",
        // Simulated P2PKH skeleton — only the standard opcodes, no
        // argument slots yet.
        .source = "dup | hash160 equalVerify checkSig",
        .expected_unlocking_hex = "76",
        // 0xa9 HASH160, 0x88 EQUALVERIFY, 0xac CHECKSIG
        .expected_locking_hex = "a988ac",
    },
};

fn hexBytes(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    return try sx.lower.bytesToHex(allocator, bytes);
}

fn runCase(case: Case) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var lexer = sx.Lexer.init(arena.allocator(), case.source);
    const lex_res = try lexer.tokenise();
    var parser = sx.Parser.init(arena.allocator(), lex_res.tokens.items);
    const parse_res = try parser.parse();
    const root = parse_res.ast orelse {
        std.debug.print("\n[{s}] no AST\n", .{case.name});
        return error.NoAst;
    };
    var lowerer = sx.Lowerer.init(arena.allocator());
    const low = try lowerer.lower(root);

    const got_unlocking = try hexBytes(arena.allocator(), low.unlocking_bytes);
    const got_locking = try hexBytes(arena.allocator(), low.locking_bytes);

    if (!std.mem.eql(u8, case.expected_unlocking_hex, got_unlocking)) {
        std.debug.print(
            "\n[{s}] unlocking hex mismatch:\n  expected: {s}\n  got:      {s}\n  source:   \"{s}\"\n",
            .{ case.name, case.expected_unlocking_hex, got_unlocking, case.source },
        );
        return error.UnlockingHexMismatch;
    }
    if (!std.mem.eql(u8, case.expected_locking_hex, got_locking)) {
        std.debug.print(
            "\n[{s}] locking hex mismatch:\n  expected: {s}\n  got:      {s}\n  source:   \"{s}\"\n",
            .{ case.name, case.expected_locking_hex, got_locking, case.source },
        );
        return error.LockingHexMismatch;
    }
}

test "lowerer parity vs hand-crafted hex goldens" {
    var failed: usize = 0;
    var total: usize = 0;
    for (CASES) |case| {
        total += 1;
        runCase(case) catch |e| {
            std.debug.print("  FAIL: [{s}] {s}\n", .{ case.name, @errorName(e) });
            failed += 1;
        };
    }
    std.debug.print(
        "\nlowerer parity: {}/{} cases passing ({} failing)\n",
        .{ total - failed, total, failed },
    );
    try std.testing.expectEqual(@as(usize, 0), failed);
}

```
