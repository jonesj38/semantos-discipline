---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/tests/parity_contracts.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.995281+00:00
---

# core/cell-engine/tools/sx/tests/parity_contracts.zig

```zig
//! Real-corpus parity test — drives bitcoinsx's actual
//! src/sx/contracts/*.sx files through our pipeline.
//!
//! Without access to his `@elas_co/ts` package (private registry), we
//! can't run his JS compiler to capture goldens automatically. Two
//! tactics here:
//!
//! 1. SMALL CONTRACTS — sources where the expected bytecode is
//!    unambiguous (p2pkh, helloWorld, p2pb): hand-derive the expected
//!    hex from the BSV opcode spec + deploy_args resolution and assert
//!    byte-identical.
//!
//! 2. LARGER CONTRACTS — sources too complex to hand-derive (p2fb with
//!    a 134-byte @test annotation, refactorBeginnings* with imports of
//!    `stdlib` not yet supported, etc.): run our pipeline as a clean-
//!    compile sanity test, report byte counts, flag what's known-blocked.
//!
//! Per Brendan (conversation 2026-06-03): "you can build them in SX
//! language ... in the formulator you say in the output args that
//! .variable is x." Our deploy_args map IS his formulator output args.
//!
//! ## When his goldens become available
//!
//! Replace the hand-derived `expected_locking_hex` with the captured
//! output from a `node` script that imports SxCompiler and dumps
//! lockHex/unlockHex per fixture. The harness shape doesn't change.

const std = @import("std");
const sx = @import("sx");

const DeployArg = struct { name: []const u8, value: []const u8 };

const Status = enum {
    /// Hand-derived hex matches our pipeline output exactly.
    pass,
    /// Pipeline ran cleanly + produced bytes; no golden to compare.
    clean_no_golden,
    /// Pipeline ran cleanly but produced unexpected output vs derived golden.
    output_mismatch,
    /// Known blocker (e.g. `import 'stdlib'` — his commented-out
    /// special case we haven't implemented).
    known_blocker,
    /// Unexpected error from our pipeline.
    pipeline_error,
};

const Contract = struct {
    name: []const u8,
    source: []const u8,
    deploy_args: []const DeployArg = &[_]DeployArg{},
    expected_locking_hex: ?[]const u8 = null,
    expected_unlocking_hex: ?[]const u8 = null,
    /// Known-blocker tag — skip our derivation, record as blocker.
    known_blocker: ?[]const u8 = null,
};

// 20-byte sample pubkey hash used across the P2PKH-shaped contracts.
const SAMPLE_PKH = "1122334455667788990011223344556677889900";

// Contracts vendored verbatim from bitcoinsx/src/sx/contracts/.
const CONTRACTS = [_]Contract{
    .{
        .name = "p2pkh.sx",
        .source = ".sig .pubKey | dup hash160 .pubKeyHash equalVerify checkSig",
        .deploy_args = &[_]DeployArg{
            .{ .name = "pubKeyHash", .value = SAMPLE_PKH },
        },
        // OP_DUP(76) OP_HASH160(a9) push20(14) <pkh:20> OP_EQUALVERIFY(88) OP_CHECKSIG(ac)
        .expected_locking_hex = "76a914" ++ SAMPLE_PKH ++ "88ac",
        .expected_unlocking_hex = "",
    },
    .{
        .name = "helloWorld.sx",
        .source = "// helloWorld.sx\n.sig .pubKey | dup hash160 .pubKeyHash equalVerify checkSig 'Hello World!' drop",
        .deploy_args = &[_]DeployArg{
            .{ .name = "pubKeyHash", .value = SAMPLE_PKH },
        },
        // P2PKH skeleton + push12 "Hello World!" + OP_DROP(75)
        // 'Hello World!' = 12 bytes = 48656c6c6f20576f726c6421
        .expected_locking_hex = "76a914" ++ SAMPLE_PKH ++ "88ac" ++ "0c" ++ "48656c6c6f20576f726c6421" ++ "75",
        .expected_unlocking_hex = "",
    },
    .{
        .name = "p2pb.sx",
        .source = "// p2pb.sx\n.sig .pubKey .boltUnlock @t:b017 | .boltLock @t:b017 equalVerify dup hash160 .pubKeyHash equalVerify checkSig",
        .deploy_args = &[_]DeployArg{
            .{ .name = "pubKeyHash", .value = SAMPLE_PKH },
        },
        // Lock: push2 b017 (from .boltLock @t:b017) + OP_EQUALVERIFY(88)
        //      + OP_DUP(76) OP_HASH160(a9) push20 <pkh> OP_EQUALVERIFY(88) OP_CHECKSIG(ac)
        .expected_locking_hex = "02b01788" ++ "76a914" ++ SAMPLE_PKH ++ "88ac",
        // Unlock: .sig .pubKey unresolved; .boltUnlock @t:b017 → push2 b017
        .expected_unlocking_hex = "02b017",
    },
    // p2fb.sx — Brendan's "bolt-funded" contract. Large @test annotation
    // (a full pre-signed parent tx ~135 bytes), function def, repeats
    // with sighash ECDSA reconstruction math. Sanity-test only — too
    // complex to hand-derive cleanly without his JS compiler output.
    .{
        .name = "p2fb.sx",
        .source = @embedFile("p2fb.sx"),
    },
    // refactorBeginnings.sx variants — all import 'stdlib' (his
    // commented-out branch). We don't yet handle that special case.
    .{
        .name = "refactorBeginnings.sx",
        .source = "",
        .known_blocker = "import 'stdlib' is in his commented-out special-case branch",
    },
    .{
        .name = "verCtxTest.sx",
        .source = "// verCtxTest.sx\nimport 'std.sxLib'\n// scriptSig\n.ctx | // Script separator\n// scriptPubKey\n41 checkCtx",
        .known_blocker = "checkCtx call site needs std.sxLib content available — vendored stub doesn't include checkCtx body",
    },
};

const Report = struct {
    pass: usize = 0,
    clean_no_golden: usize = 0,
    output_mismatch: usize = 0,
    known_blocker: usize = 0,
    pipeline_error: usize = 0,
    total: usize = 0,
};

fn runContract(allocator: std.mem.Allocator, c: Contract, report: *Report) !void {
    report.total += 1;
    if (c.known_blocker) |reason| {
        report.known_blocker += 1;
        std.debug.print("  BLOCKER  [{s:<26}] {s}\n", .{ c.name, reason });
        return;
    }

    // Build deploy_args map.
    var args_map: sx.DeployArgs = .{};
    for (c.deploy_args) |a| try args_map.put(allocator, a.name, a.value);

    // Pipeline.
    var lexer = sx.Lexer.init(allocator, c.source);
    const lex_res = lexer.tokenise() catch {
        report.pipeline_error += 1;
        std.debug.print("  ERROR    [{s:<26}] tokenise crashed\n", .{c.name});
        return;
    };
    var parser = sx.Parser.init(allocator, lex_res.tokens.items);
    const parse_res = parser.parse() catch {
        report.pipeline_error += 1;
        std.debug.print("  ERROR    [{s:<26}] parse crashed\n", .{c.name});
        return;
    };
    if (parse_res.parse_error) |e| {
        report.pipeline_error += 1;
        std.debug.print("  ERROR    [{s:<26}] parse error: {s}\n", .{ c.name, e.msg });
        return;
    }
    const root = parse_res.ast orelse {
        report.pipeline_error += 1;
        std.debug.print("  ERROR    [{s:<26}] no AST\n", .{c.name});
        return;
    };

    var lowerer = if (c.deploy_args.len > 0)
        sx.Lowerer.initWithArgs(allocator, &args_map)
    else
        sx.Lowerer.init(allocator);
    const low = lowerer.lower(root) catch |err| {
        report.pipeline_error += 1;
        std.debug.print("  ERROR    [{s:<26}] lower crashed: {s}\n", .{ c.name, @errorName(err) });
        return;
    };

    const unl_hex = try sx.lower.bytesToHex(allocator, low.unlocking_bytes);
    const loc_hex = try sx.lower.bytesToHex(allocator, low.locking_bytes);

    if (c.expected_locking_hex == null and c.expected_unlocking_hex == null) {
        report.clean_no_golden += 1;
        std.debug.print(
            "  CLEAN    [{s:<26}] u={d}B l={d}B unresolved={d}\n",
            .{ c.name, low.unlocking_bytes.len, low.locking_bytes.len, low.unresolved_args.len },
        );
        return;
    }

    var ok = true;
    if (c.expected_locking_hex) |exp| {
        if (!std.mem.eql(u8, exp, loc_hex)) {
            ok = false;
            std.debug.print(
                "  MISMATCH [{s:<26}] lock:\n    exp: {s}\n    got: {s}\n",
                .{ c.name, exp, loc_hex },
            );
        }
    }
    if (c.expected_unlocking_hex) |exp| {
        if (!std.mem.eql(u8, exp, unl_hex)) {
            ok = false;
            std.debug.print(
                "  MISMATCH [{s:<26}] unlock:\n    exp: {s}\n    got: {s}\n",
                .{ c.name, exp, unl_hex },
            );
        }
    }
    if (ok) {
        report.pass += 1;
        std.debug.print(
            "  PASS     [{s:<26}] u={d}B l={d}B\n",
            .{ c.name, low.unlocking_bytes.len, low.locking_bytes.len },
        );
    } else {
        report.output_mismatch += 1;
    }
}

test "real-contract parity vs bitcoinsx src/sx/contracts/" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    std.debug.print(
        \\
        \\========================================================================
        \\real-contract parity (bitcoinsx/src/sx/contracts/*.sx)
        \\========================================================================
        \\
    , .{});

    var report: Report = .{};
    for (CONTRACTS) |c| {
        runContract(arena.allocator(), c, &report) catch |e| {
            report.pipeline_error += 1;
            std.debug.print("  ERROR [{s}] harness: {s}\n", .{ c.name, @errorName(e) });
        };
    }

    std.debug.print(
        \\
        \\------------------------------------------------------------------------
        \\  PASS (byte-identical to derived golden) : {}
        \\  CLEAN (compiled, no golden to compare)  : {}
        \\  MISMATCH (output ≠ derived golden)      : {}
        \\  BLOCKER (known feature gap)             : {}
        \\  ERROR (pipeline crashed)                : {}
        \\  TOTAL                                   : {}
        \\========================================================================
        \\
        \\
    , .{ report.pass, report.clean_no_golden, report.output_mismatch, report.known_blocker, report.pipeline_error, report.total });

    // Only MISMATCH and ERROR are real failures. BLOCKER + CLEAN are
    // expected states given today's tooling.
    try std.testing.expectEqual(@as(usize, 0), report.output_mismatch);
    try std.testing.expectEqual(@as(usize, 0), report.pipeline_error);
}

```
