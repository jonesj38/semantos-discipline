---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/tests/parity_compile.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.993908+00:00
---

# core/cell-engine/tools/sx/tests/parity_compile.zig

```zig
//! End-to-end compile parity vs bitcoinsx — measurement harness.
//!
//! Vendors his `compiler.test.ts` cases (the ones with concrete
//! `lockingAsm` / `unlockingAsm` goldens) and runs them through our
//! Lexer → Parser → Lowerer pipeline. Each case is categorised:
//!
//!   PASS    — our hex output matches his ASM-converted-to-hex exactly
//!   BLOCKED — known feature gap (repeat-unroll, call-expand, etc.)
//!             — we identify which gap, so PR-3.1 can prioritise
//!   FAIL    — unexpected mismatch (treated as a real failure)
//!
//! Goal: produce an honest map of "what's drop-in-ready today vs what
//! the next PR needs to land." NOT a hard pass/fail gate — `try
//! expectEqual(0, fails)` would block the whole test suite over an
//! intentionally-deferred feature.
//!
//! ## ASM → hex conversion
//!
//! His `lockingAsm` is space-separated mixed tokens:
//!   - OP_<NAME>  → opcode byte (uppercased shortOps lookup)
//!   - OP_<N>     → numeric opcode 0x51+N-1 for 1..16; OP_0 → 0x00
//!   - <name>     → unresolved arg slot — case is BLOCKED by PR-3.1
//!   - else       → raw hex pushdata (length-prefixed in real bytecode)
//!
//! ## Coverage state
//!
//! ~30 cases vendored from his compiler.test.ts. PR-3.2 reports
//! today's split; the number of PASS / BLOCKED-* / FAIL guides
//! PR-3.1's feature priorities.

const std = @import("std");
const sx = @import("sx");

const Block = enum {
    none,
    arg_slot, // unresolved <name> in lock half (needs PR-3.1 arg-slot model)
    repeat_unroll, // body not unrolled N times (needs PR-3.1 repeat)
    call_expand, // call site not body-inlined (needs PR-3.1 call lookup)
    push_code_data, // pushCodeData not bundling body (needs PR-3.1)
    multi_feature, // multiple of the above
    unknown, // unexpected mismatch — investigate as a real bug
};

const DeployArgPair = struct { name: []const u8, value: []const u8 };

const Case = struct {
    name: []const u8,
    source: []const u8,
    /// His lockingAsm fixture from compiler.test.ts. May contain
    /// `<argname>` slot markers; if so, the case is auto-categorised
    /// as BLOCKED(arg_slot).
    expected_locking_asm: []const u8 = "",
    /// His unlockingAsm fixture (most cases don't pin it).
    expected_unlocking_asm: []const u8 = "",
    /// Categorisation when we KNOW a feature gap blocks this case.
    /// Set when copying from his fixture — saves re-deriving each run.
    expected_block: Block = .none,
    /// Deploy-time arg resolutions, mirroring his formulator output
    /// args block. Names without leading `.`; values are raw hex
    /// strings (for slot pushes) or decimal integers (for arg-driven
    /// repeat counts).
    deploy_args: []const DeployArgPair = &[_]DeployArgPair{},
};

const CASES = [_]Case{
    // ---- Cases that should PASS today (no gated features) ----
    .{ .name = "empty source", .source = "", .expected_locking_asm = "" },
    .{ .name = "OP_1 from 1n", .source = "1n", .expected_locking_asm = "OP_1" },
    .{ .name = "OP_1 with line comment", .source = "1n // lol\n", .expected_locking_asm = "OP_1" },
    .{ .name = "raw 7b from 123n", .source = "123n", .expected_locking_asm = "7b" },
    .{ .name = "raw fb from -123n", .source = "-123n", .expected_locking_asm = "fb" },
    .{ .name = "argument with @test:bigint resolves to value", .source = ".argument @test:123n", .expected_locking_asm = "7b" },
    .{ .name = "argument with @test:hex resolves", .source = ".pubKeyHash1 @test:0100000000000000deadbeefbabecafe", .expected_locking_asm = "0100000000000000deadbeefbabecafe" },
    .{ .name = "argument with @t:hex shorthand", .source = ".pubKeyHash2 @t:0100000000000000deadbeefbabecafe", .expected_locking_asm = "0100000000000000deadbeefbabecafe" },
    .{ .name = "0x-prefixed hex", .source = "0xdeadbeef", .expected_locking_asm = "deadbeef" },
    .{ .name = "string literal then dup opcode", .source = "'deadbeef' dup", .expected_locking_asm = "6465616462656566 OP_DUP" },
    .{ .name = "if/else/endif opcode chain (top-level)", .source = "1n if true else false endif", .expected_locking_asm = "OP_1 OP_IF OP_TRUE OP_ELSE OP_FALSE OP_ENDIF" },
    .{ .name = "1n then comment then 2n", .source = "1n // comment\n        2n", .expected_locking_asm = "OP_1 OP_2" },
    .{ .name = "multi-line block comment alone", .source = "/* multi -\n              line comments. */", .expected_locking_asm = "" },
    .{ .name = "uppercased hex normalises", .source = "deadbeeF", .expected_locking_asm = "deadbeef" },
    // Skipped: ".argTest @test:'This is an esc\'d char'" — his JS test
    // source uses a backslash-escaped apostrophe that gets stripped from
    // the string body before lex time, producing "This is an escd char"
    // (without the apostrophe). Our lexer doesn't yet handle this
    // particular JS-source-level escape; tracked as PR-3.2.1 if it ever
    // matters in practice. Not a real `.sx` source pattern.

    // ---- Repeat unrolling (PR-3.1 — now PASSING) ----
    .{ .name = "repeat 3n with body", .source = "repeat 3n 3n end", .expected_locking_asm = "OP_3 OP_3 OP_3" },
    .{ .name = "nested repeats", .source = "repeat 2n\n                        2n\n                        repeat 3n\n                          1n\n                        end\n                      end", .expected_locking_asm = "OP_2 OP_1 OP_1 OP_1 OP_2 OP_1 OP_1 OP_1" },
    .{ .name = "mixed top-level + nested repeat", .source = "1n repeat 1n 2n repeat 1n deadbeef end end", .expected_locking_asm = "OP_1 OP_2 deadbeef" },

    // ---- Call expansion (PR-3.1 — now PASSING) ----
    .{ .name = "function def alone emits nothing", .source = "#outerFunc 2n end", .expected_locking_asm = "" },
    .{ .name = "function def + later call", .source = "#outerFunc 2n end outerFunc", .expected_locking_asm = "OP_2" },
    .{ .name = "function def + repeat in body + call", .source = "#outerFunc repeat 2n nop end true\n                      end\n                      false outerFunc", .expected_locking_asm = "OP_FALSE OP_NOP OP_NOP OP_TRUE" },
    .{ .name = "nested function defs + call", .source = "#outerFunc #innerFunc verify end true innerFunc end outerFunc", .expected_locking_asm = "OP_TRUE OP_VERIFY" },
    .{ .name = "function with if/else body + call", .source = "#testFunc if 1n else 2n endif end\n    testFunc", .expected_locking_asm = "OP_IF OP_1 OP_ELSE OP_2 OP_ENDIF" },
    .{ .name = "repeat unrolled around call", .source = "#functionName\n        repeat 3n\n            true\n        end\n      end\n\n      functionName", .expected_locking_asm = "OP_TRUE OP_TRUE OP_TRUE" },
    .{ .name = "import + imported call", .source = "import 'std.sxLib'\n      mod2 @l:mod2", .expected_locking_asm = "OP_2 OP_MOD" },
    .{ .name = "break keyword expands to false+verify", .source = "break", .expected_locking_asm = "OP_FALSE OP_VERIFY" },

    // ---- pushCodeData body bundling (PR-3.1 — now PASSING) ----
    .{ .name = "pushCodeData of a hex macro", .source = "#beefMacro beef end pushCodeData beefMacro", .expected_locking_asm = "02beef" },

    // ---- Lock-half arg slot resolved via deploy_args (PR-3.1.5) ----
    // The formulator-supplied resolution model Brendan described:
    // ".pubKeyHash" gets a concrete value from the deploy spec; the
    // lowerer bakes it into the locking script at compile time.
    .{
        .name = "P2PKH locking script with .pubKeyHash resolved via deploy_args",
        .source = ".sig .pubKey | dup hash160 .pubKeyHash equalVerify checksig",
        .expected_locking_asm = "OP_DUP OP_HASH160 1122334455667788990011223344556677889900 OP_EQUALVERIFY OP_CHECKSIG",
        .deploy_args = &[_]DeployArgPair{
            .{ .name = "pubKeyHash", .value = "1122334455667788990011223344556677889900" },
        },
    },
    // ---- Argument-driven repeat count via deploy_args (Brendan's
    //      `Repeat .variable <code> end` pattern) ----
    .{
        .name = "argument-driven repeat unrolls to deploy_args value",
        .source = "repeat .loops nop end",
        .expected_locking_asm = "OP_NOP OP_NOP OP_NOP OP_NOP",
        .deploy_args = &[_]DeployArgPair{
            .{ .name = "loops", .value = "4" },
        },
    },
};

const std_lib_stub = sx.parse.FileData{
    .id = "1",
    .name = "std.sxLib",
    .data = "#mod2 2n mod end",
};

const Result = struct {
    pass: usize = 0,
    blocked_arg_slot: usize = 0,
    blocked_repeat: usize = 0,
    blocked_call: usize = 0,
    blocked_pcd: usize = 0,
    blocked_multi: usize = 0,
    unexpected_fail: usize = 0,
    total: usize = 0,
};

fn opcodeByte(mnemonic: []const u8) ?u8 {
    // OP_0 .. OP_16 numeric forms (case-sensitive).
    if (std.mem.eql(u8, mnemonic, "OP_0") or std.mem.eql(u8, mnemonic, "OP_FALSE")) return 0x00;
    if (std.mem.eql(u8, mnemonic, "OP_1NEGATE")) return 0x4f;
    if (std.mem.eql(u8, mnemonic, "OP_TRUE")) return 0x51;
    if (std.mem.startsWith(u8, mnemonic, "OP_")) {
        const tail = mnemonic[3..];
        // OP_<n> where n is 1..16
        if (tail.len <= 2 and tail.len >= 1) {
            const n = std.fmt.parseInt(u8, tail, 10) catch {
                // fall through to mnemonic lookup
                return opcodeByMnemonic(tail);
            };
            if (n >= 1 and n <= 16) return 0x50 + n;
            if (n == 0) return 0x00;
        }
        return opcodeByMnemonic(tail);
    }
    return null;
}

fn opcodeByMnemonic(upper_mnemonic: []const u8) ?u8 {
    // shortOps stores camelCase; lookup case-insensitively.
    for (sx.short_ops.TABLE) |op| {
        if (std.ascii.eqlIgnoreCase(upper_mnemonic, op.value)) return op.int;
    }
    return null;
}

/// Convert his lockingAsm string to expected hex bytes.
/// Returns null when the string contains an unresolved arg slot (e.g.
/// `<pubKeyHash>`) — caller categorises as BLOCKED(arg_slot).
fn asmToHex(allocator: std.mem.Allocator, asm_str: []const u8) !?[]const u8 {
    if (asm_str.len == 0) return try allocator.alloc(u8, 0);

    var out: std.ArrayList(u8) = .{};
    var it = std.mem.tokenizeScalar(u8, asm_str, ' ');
    while (it.next()) |tok| {
        if (tok.len == 0) continue;
        if (tok[0] == '<') {
            // Unresolved arg slot — can't compute byte form yet.
            out.deinit(allocator);
            return null;
        }
        if (std.mem.startsWith(u8, tok, "OP_")) {
            const b = opcodeByte(tok) orelse {
                out.deinit(allocator);
                return error.UnknownOpcode;
            };
            try out.append(allocator, b);
            continue;
        }
        // Raw hex token — push as pushdata with length prefix.
        if (tok.len % 2 != 0) {
            out.deinit(allocator);
            return error.InvalidHex;
        }
        const byte_len = tok.len / 2;
        const data = try allocator.alloc(u8, byte_len);
        defer allocator.free(data);
        var i: usize = 0;
        while (i < byte_len) : (i += 1) {
            data[i] = std.fmt.parseInt(u8, tok[i * 2 .. i * 2 + 2], 16) catch {
                out.deinit(allocator);
                return error.InvalidHex;
            };
        }
        // Length-prefix.
        if (byte_len == 0) {
            try out.append(allocator, 0x00);
        } else if (byte_len <= 75) {
            try out.append(allocator, @intCast(byte_len));
        } else if (byte_len <= 0xff) {
            try out.append(allocator, 0x4c);
            try out.append(allocator, @intCast(byte_len));
        } else if (byte_len <= 0xffff) {
            try out.append(allocator, 0x4d);
            try out.append(allocator, @intCast(byte_len & 0xff));
            try out.append(allocator, @intCast((byte_len >> 8) & 0xff));
        } else {
            out.deinit(allocator);
            return error.PushdataTooLarge;
        }
        try out.appendSlice(allocator, data);
    }
    return try out.toOwnedSlice(allocator);
}

fn ourCompile(allocator: std.mem.Allocator, source: []const u8, deploy_args: []const DeployArgPair) !sx.LowerResult {
    var lexer = sx.Lexer.init(allocator, source);
    const lex_res = try lexer.tokenise();
    var parser = sx.Parser.initWithFiles(
        allocator,
        lex_res.tokens.items,
        "test.sx",
        &[_]sx.parse.FileData{std_lib_stub},
    );
    const parse_res = try parser.parse();
    const root = parse_res.ast orelse return error.NoAst;

    var deploy_args_map: sx.DeployArgs = .{};
    for (deploy_args) |pair| {
        try deploy_args_map.put(allocator, pair.name, pair.value);
    }

    var lowerer = if (deploy_args.len > 0)
        sx.Lowerer.initWithArgs(allocator, &deploy_args_map)
    else
        sx.Lowerer.init(allocator);
    return try lowerer.lower(root);
}

fn runCase(allocator: std.mem.Allocator, case: Case, result: *Result) !void {
    result.total += 1;

    // Categorise by expected_block first — these are known gaps, not
    // failures.
    switch (case.expected_block) {
        .arg_slot => {
            result.blocked_arg_slot += 1;
            return;
        },
        .repeat_unroll => {
            result.blocked_repeat += 1;
            return;
        },
        .call_expand => {
            result.blocked_call += 1;
            return;
        },
        .push_code_data => {
            result.blocked_pcd += 1;
            return;
        },
        .multi_feature => {
            result.blocked_multi += 1;
            return;
        },
        else => {},
    }

    // Run our pipeline.
    const low = ourCompile(allocator, case.source, case.deploy_args) catch {
        std.debug.print("  UNEXPECTED FAIL [{s}]: our pipeline errored\n", .{case.name});
        result.unexpected_fail += 1;
        return;
    };

    // Convert his ASM to expected BYTES, then hex-encode for comparison.
    const expected_bytes = asmToHex(allocator, case.expected_locking_asm) catch {
        std.debug.print("  UNEXPECTED FAIL [{s}]: couldn't convert his ASM\n", .{case.name});
        result.unexpected_fail += 1;
        return;
    } orelse {
        // ASM had an unresolved slot — should have been marked arg_slot.
        std.debug.print("  UNEXPECTED FAIL [{s}]: ASM has slot but case not marked arg_slot\n", .{case.name});
        result.unexpected_fail += 1;
        return;
    };
    const expected_lock_hex = try sx.lower.bytesToHex(allocator, expected_bytes);

    // Our hex.
    const our_lock_hex = try sx.lower.bytesToHex(allocator, low.locking_bytes);
    // Some cases output to unlocking half (no | separator); compare
    // against unlocking when his locking is empty AND our locking is
    // empty AND we have unlocking bytes.
    const our_hex = if (!low.sectioned and low.unlocking_bytes.len > 0)
        try sx.lower.bytesToHex(allocator, low.unlocking_bytes)
    else
        our_lock_hex;

    if (std.mem.eql(u8, expected_lock_hex, our_hex)) {
        result.pass += 1;
        return;
    }

    std.debug.print(
        "  UNEXPECTED FAIL [{s}]:\n    source:   \"{s}\"\n    expected: {s}\n    got:      {s}\n",
        .{ case.name, case.source, expected_lock_hex, our_hex },
    );
    result.unexpected_fail += 1;
}

test "compile parity vs bitcoinsx — coverage report" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var result: Result = .{};
    for (CASES) |case| {
        runCase(arena.allocator(), case, &result) catch |e| {
            std.debug.print("  UNEXPECTED FAIL [{s}]: {s}\n", .{ case.name, @errorName(e) });
            result.unexpected_fail += 1;
        };
    }

    const expected_blocked = result.blocked_arg_slot + result.blocked_repeat +
        result.blocked_call + result.blocked_pcd + result.blocked_multi;

    std.debug.print(
        \\
        \\========================================================================
        \\compile parity coverage (PR-3 today)
        \\========================================================================
        \\  PASS                : {} / {}
        \\  BLOCKED — arg slot  : {}  (PR-3.1: lock-half .argName resolution)
        \\  BLOCKED — repeat    : {}  (PR-3.1: repeat-body unrolling at lower)
        \\  BLOCKED — call      : {}  (PR-3.1: call-site body inlining)
        \\  BLOCKED — pushCData : {}  (PR-3.1: bundle children as 1 pushdata)
        \\  BLOCKED — multi     : {}  (combinations of the above)
        \\  UNEXPECTED FAILS    : {}
        \\
        \\  Total blocked       : {}
        \\  Total accounted for : {} / {}
        \\========================================================================
        \\
        \\
    , .{
        result.pass, result.total,
        result.blocked_arg_slot,
        result.blocked_repeat,
        result.blocked_call,
        result.blocked_pcd,
        result.blocked_multi,
        result.unexpected_fail,
        expected_blocked,
        result.pass + expected_blocked + result.unexpected_fail,
        result.total,
    });

    // Only fail on UNEXPECTED fails — known-blocked cases are
    // intentionally deferred to PR-3.1 and shouldn't gate this test.
    try std.testing.expectEqual(@as(usize, 0), result.unexpected_fail);
}

```
