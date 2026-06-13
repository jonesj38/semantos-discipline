---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/tests/parity_tokenise.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.994536+00:00
---

# core/cell-engine/tools/sx/tests/parity_tokenise.zig

```zig
//! Parity test driver for the `.sx` lexer.
//!
//! Mirrors the shape of bitcoinsx's
//! `src/sx/tests/tokeniser/tokeniseTypes.test.ts`:
//!
//!   const testScripts = [
//!     { script: ``, tokens: [] },
//!     { script: `nop`, tokens: [{ type: nodeTypes.opcode, asm: 'OP_NOP' }] },
//!     ...
//!   ]
//!
//! Each entry here corresponds 1:1 to one of his entries. A failing case
//! in our port maps directly to "fix `lex.zig` until this case matches"
//! — no translation layer to debug.
//!
//! ## How to add a case
//!
//! 1. Find the next un-ported case in his `tokeniseTypes.test.ts`
//! 2. Copy `script:` source into `source` field below
//! 3. Translate `tokens: [...]` into our `ExpectedToken` array
//! 4. Run `zig build test`
//! 5. If it fails, fix `lex.zig` (NOT the expectation)
//!
//! ## Coverage state (kept current as cases land)
//!
//! Lines from his file: 248.
//! Test cases in his file: ~22 (counted at PR-1 start).
//! Cases ported here:    11 (PR-1).
//! Cases remaining:      ~11 (PR-1.1+).
//!
//! Cases not yet ported (PR-1.1):
//!   - `repeat .cnt nop end`             [composite repeat block]
//!   - `repeat 3n 3n repeat 2n 2n end end`  [nested repeat]
//!   - `#function`                       [function form alone]
//!   - `#test nop end test`              [function def + call]
//!   - `if nop else nop endif`           [flow-control opcode chain]
//!   - `import 'testLib.sx' testFunc`    [import + word after]
//!   - `\`templateStringValue\``         [template literal]
//!   - `@test:-123n`                     [annotation with bigint value]
//!   - `@test:-123`                      [annotation with bare-int word]

const std = @import("std");
const sx = @import("sx");

/// Expectation matching the shape of his JS test fixture entries.
/// `line` / `col` are optional — when null, fidelity is not asserted for
/// that field. Most cases leave them null; we add explicit checks for the
/// position-fidelity cases at the bottom.
const ExpectedToken = struct {
    type: sx.NodeType,
    value: ?[]const u8 = null,
    asm_str: ?[]const u8 = null,
    optional: bool = false,
    line: ?u32 = null,
    col: ?u32 = null,
};

/// Per-case expectation about a tokenise-error. `null` = no error expected.
const ExpectedError = struct {
    msg_contains: []const u8,
    line: ?u32 = null,
    col: ?u32 = null,
};

const Case = struct {
    name: []const u8,
    source: []const u8,
    expected: []const ExpectedToken,
    expected_error: ?ExpectedError = null,
};

/// 1:1 with `tokeniseTypes.test.ts::testScripts`. Names mirror his
/// `describe`/`it` labels where present.
const CASES = [_]Case{
    .{
        .name = "empty",
        .source = "",
        .expected = &[_]ExpectedToken{},
    },
    .{
        .name = "nop opcode",
        .source = "nop",
        .expected = &[_]ExpectedToken{
            .{ .type = .opcode, .asm_str = "OP_NOP" },
        },
    },
    .{
        .name = "nop with line comment",
        .source = "nop//comment",
        .expected = &[_]ExpectedToken{
            .{ .type = .opcode, .asm_str = "OP_NOP" },
            .{ .type = .comment },
            .{ .type = .word, .value = "comment" },
        },
    },
    .{
        .name = "argument",
        .source = ".argName",
        .expected = &[_]ExpectedToken{
            .{ .type = .argument, .value = "argName" },
        },
    },
    .{
        .name = "optional argument",
        .source = ".optArgName?",
        .expected = &[_]ExpectedToken{
            .{ .type = .argument, .value = "optArgName", .optional = true },
        },
    },
    .{
        .name = "bigint positive",
        .source = "12345n",
        .expected = &[_]ExpectedToken{
            .{ .type = .bigint, .value = "12345n" },
        },
    },
    .{
        .name = "bigint negative",
        .source = "-12345n",
        .expected = &[_]ExpectedToken{
            .{ .type = .bigint, .value = "-12345n" },
        },
    },
    .{
        .name = "bare hex",
        .source = "deadbeef",
        .expected = &[_]ExpectedToken{
            .{ .type = .hex, .value = "deadbeef" },
        },
    },
    .{
        .name = "single-quoted string",
        .source = "'string'",
        .expected = &[_]ExpectedToken{
            .{ .type = .string, .value = "string" },
        },
    },
    .{
        .name = "double-quoted string",
        .source = "\"double-quote string\"",
        .expected = &[_]ExpectedToken{
            .{ .type = .string, .value = "double-quote string" },
        },
    },
    .{
        .name = "annotation with quoted string value",
        .source = "@label:'spaced string'",
        .expected = &[_]ExpectedToken{
            .{ .type = .annotation, .value = "label" },
            .{ .type = .string, .value = "spaced string" },
        },
    },
    .{
        .name = "repeat keyword alone",
        .source = "repeat",
        .expected = &[_]ExpectedToken{
            .{ .type = .repeat },
        },
    },
    .{
        .name = "end keyword alone",
        .source = "end",
        .expected = &[_]ExpectedToken{
            .{ .type = .end },
        },
    },
    // ---- PR-1.1 cases below ----
    .{
        .name = "repeat with argument and opcode",
        .source = "repeat .cnt nop end",
        .expected = &[_]ExpectedToken{
            .{ .type = .repeat },
            .{ .type = .argument, .value = "cnt" },
            .{ .type = .opcode, .value = "nop" },
            .{ .type = .end },
        },
    },
    .{
        .name = "nested repeat",
        .source = "repeat 3n 3n repeat 2n 2n end end",
        .expected = &[_]ExpectedToken{
            .{ .type = .repeat },
            .{ .type = .bigint, .value = "3n" },
            .{ .type = .bigint, .value = "3n" },
            .{ .type = .repeat },
            .{ .type = .bigint, .value = "2n" },
            .{ .type = .bigint, .value = "2n" },
            .{ .type = .end },
            .{ .type = .end },
        },
    },
    .{
        .name = "flow-control opcode chain (if/else/endif)",
        .source = "if nop else nop endif",
        .expected = &[_]ExpectedToken{
            .{ .type = .opcode },
            .{ .type = .opcode },
            .{ .type = .opcode },
            .{ .type = .opcode },
            .{ .type = .opcode },
        },
    },
    .{
        .name = "annotation with bigint value",
        .source = "@cs:1n",
        .expected = &[_]ExpectedToken{
            .{ .type = .annotation, .value = "cs" },
            .{ .type = .bigint, .value = "1n" },
        },
    },
    .{
        .name = "import directive with quoted path and word",
        .source = "import 'testLib.sx'\n      testFunc",
        .expected = &[_]ExpectedToken{
            .{ .type = .import },
            .{ .type = .string, .value = "testLib.sx" },
            .{ .type = .word, .value = "testFunc" },
        },
    },
    .{
        .name = "annotation with bigint negative",
        .source = "@test:-123n",
        .expected = &[_]ExpectedToken{
            .{ .type = .annotation, .value = "test" },
            .{ .type = .bigint, .value = "-123n" },
        },
    },
    .{
        .name = "annotation with bare int as word",
        .source = "@test:-123",
        .expected = &[_]ExpectedToken{
            .{ .type = .annotation, .value = "test" },
            .{ .type = .word, .value = "-123" },
        },
    },
    .{
        .name = "function form alone",
        .source = "#function",
        .expected = &[_]ExpectedToken{
            .{ .type = .function, .value = "function" },
        },
    },
    .{
        .name = "function definition and later call",
        .source = "#test nop end test",
        .expected = &[_]ExpectedToken{
            .{ .type = .function, .value = "test" },
            .{ .type = .opcode },
            .{ .type = .end },
            .{ .type = .call, .value = "test" },
        },
    },
    .{
        .name = "function with body returning bigint via if/else",
        .source = "#testFunc if 1n else 2n endif end\n      testFunc",
        .expected = &[_]ExpectedToken{
            .{ .type = .function, .value = "testFunc" },
            .{ .type = .opcode },
            .{ .type = .bigint, .value = "1n" },
            .{ .type = .opcode },
            .{ .type = .bigint, .value = "2n" },
            .{ .type = .opcode },
            .{ .type = .end },
            .{ .type = .call, .value = "testFunc" },
        },
    },
    .{
        .name = "function defining hex macro with separator and pushCodeData",
        .source = "#beefMacro beef end | pushCodeData beefMacro",
        .expected = &[_]ExpectedToken{
            .{ .type = .function, .value = "beefMacro" },
            .{ .type = .hex, .value = "beef" },
            .{ .type = .end },
            .{ .type = .word, .value = "|" },
            .{ .type = .pushCodeData, .value = "pushCodeData" },
            .{ .type = .call, .value = "beefMacro" },
        },
    },
    .{
        .name = "function with pushCodeDataV variant",
        .source = "#beefMacro beef end | pushCodeDataV beefMacro",
        .expected = &[_]ExpectedToken{
            .{ .type = .function, .value = "beefMacro" },
            .{ .type = .hex, .value = "beef" },
            .{ .type = .end },
            .{ .type = .word, .value = "|" },
            .{ .type = .pushCodeData, .value = "pushCodeDataV" },
            .{ .type = .call, .value = "beefMacro" },
        },
    },
    .{
        .name = "template literal with simple word body",
        .source = "`templateStringValue`",
        .expected = &[_]ExpectedToken{
            .{ .type = .template },
            .{ .type = .word, .value = "templateStringValue" },
            .{ .type = .template },
        },
    },
    // ---- PR-1.2 cases below: multi-line comments, 0x-hex, asm fields, ----
    // ---- annotation whitelist, position fidelity ----
    .{
        .name = "0x-prefixed hex normalises to lowercase",
        .source = "0xDEADBEEF",
        .expected = &[_]ExpectedToken{
            .{ .type = .hex, .value = "deadbeef", .asm_str = "deadbeef" },
        },
    },
    .{
        .name = "uppercase bare hex normalises to lowercase",
        .source = "DEADBEEF",
        .expected = &[_]ExpectedToken{
            .{ .type = .hex, .value = "deadbeef", .asm_str = "deadbeef" },
        },
    },
    .{
        .name = "string asm field is utf-8 hex of body",
        .source = "'abc'",
        .expected = &[_]ExpectedToken{
            .{ .type = .string, .value = "abc", .asm_str = "616263" },
        },
    },
    .{
        .name = "multi-line comment opens and closes",
        .source = "/* hi */",
        .expected = &[_]ExpectedToken{
            .{ .type = .comment, .value = "/*" },
            .{ .type = .word, .value = "hi" },
            .{ .type = .comment, .value = "*/" },
        },
    },
    .{
        .name = "nested multi-line comments",
        .source = "/* outer /* inner */ outer */",
        .expected = &[_]ExpectedToken{
            .{ .type = .comment, .value = "/*" },
            .{ .type = .word, .value = "outer" },
            .{ .type = .comment, .value = "/*" },
            .{ .type = .word, .value = "inner" },
            .{ .type = .comment, .value = "*/" },
            .{ .type = .word, .value = "outer" },
            .{ .type = .comment, .value = "*/" },
        },
    },
    .{
        .name = "position fidelity: opcode on second line",
        .source = "\nnop",
        .expected = &[_]ExpectedToken{
            .{ .type = .opcode, .value = "nop", .line = 2, .col = 1 },
        },
    },
    .{
        .name = "position fidelity: argument after spaces",
        .source = "  .arg",
        .expected = &[_]ExpectedToken{
            .{ .type = .argument, .value = "arg", .line = 1, .col = 3 },
        },
    },
    .{
        // In-comment opcode words shouldn't resolve as opcodes. Single-line
        // comment ends at \n; the second `nop` IS an opcode.
        .name = "opcode in single-line comment stays a word",
        .source = "// nop is just text\nnop",
        .expected = &[_]ExpectedToken{
            .{ .type = .comment, .value = "//" },
            .{ .type = .word, .value = "nop" },
            .{ .type = .word, .value = "is" },
            .{ .type = .word, .value = "just" },
            .{ .type = .word, .value = "text" },
            .{ .type = .opcode, .value = "nop", .asm_str = "OP_NOP" },
        },
    },
    .{
        // Same for multi-line.
        .name = "opcode inside multi-line comment stays a word",
        .source = "/* dup nop */",
        .expected = &[_]ExpectedToken{
            .{ .type = .comment, .value = "/*" },
            .{ .type = .word, .value = "dup" },
            .{ .type = .word, .value = "nop" },
            .{ .type = .comment, .value = "*/" },
        },
    },
};

/// Cases that must emit a tokenise-error rather than a clean token stream.
/// Kept in a separate table so the main `runCase` loop stays simple.
const ERROR_CASES = [_]Case{
    .{
        .name = "unknown annotation key emits Unrecognised annotation error",
        .source = "@note:123",
        .expected = &[_]ExpectedToken{},
        .expected_error = .{
            .msg_contains = "Unrecognised annotation type:",
            .line = 1,
            .col = 1,
        },
    },
    .{
        .name = "line/col populated on annotation error",
        .source = "@invalidAnnotation: dup",
        .expected = &[_]ExpectedToken{},
        .expected_error = .{
            .msg_contains = "Unrecognised annotation",
            .line = 1,
            .col = 1,
        },
    },
};

/// Mirrors his test runner: `noWhitespaceTokens = res.tokens.filter(t =>
/// t.type !== nodeTypes.whitespace)`. The lexer DOES emit whitespace
/// tokens now (PR-1.2); the harness strips them before comparing against
/// his fixture expectations.
fn filterWhitespace(allocator: std.mem.Allocator, tokens: []const sx.Node) ![]sx.Node {
    var list: std.ArrayList(sx.Node) = .{};
    for (tokens) |t| {
        if (t.type == .whitespace) continue;
        try list.append(allocator, t);
    }
    return try list.toOwnedSlice(allocator);
}

fn runCase(case: Case) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var lexer = sx.Lexer.init(arena.allocator(), case.source);
    const result = try lexer.tokenise();
    const all_tokens = result.tokens.items;
    const filtered = try filterWhitespace(arena.allocator(), all_tokens);

    // Error cases: assert the error fired with the right shape, ignore tokens.
    if (case.expected_error) |exp_err| {
        const got = result.tokenise_error orelse {
            std.debug.print(
                "\n[{s}] expected tokenise-error containing \"{s}\", got none\n",
                .{ case.name, exp_err.msg_contains },
            );
            return error.ExpectedTokeniseError;
        };
        if (std.mem.indexOf(u8, got.msg, exp_err.msg_contains) == null) {
            std.debug.print(
                "\n[{s}] tokenise-error msg mismatch: expected to contain \"{s}\", got \"{s}\"\n",
                .{ case.name, exp_err.msg_contains, got.msg },
            );
            return error.TokeniseErrorMsgMismatch;
        }
        if (exp_err.line) |l| if (got.line != l) {
            std.debug.print(
                "\n[{s}] tokenise-error line mismatch: expected {}, got {}\n",
                .{ case.name, l, got.line },
            );
            return error.TokeniseErrorLineMismatch;
        };
        if (exp_err.col) |c| if (got.col != c) {
            std.debug.print(
                "\n[{s}] tokenise-error col mismatch: expected {}, got {}\n",
                .{ case.name, c, got.col },
            );
            return error.TokeniseErrorColMismatch;
        };
        return;
    }

    // Normal cases: compare filtered (whitespace-stripped) tokens.
    if (filtered.len != case.expected.len) {
        std.debug.print(
            "\n[{s}] token count mismatch: expected {}, got {}\n" ++
                "  source: \"{s}\"\n" ++
                "  got:    {f}\n",
            .{ case.name, case.expected.len, filtered.len, case.source, fmtTokens(filtered) },
        );
        return error.TokenCountMismatch;
    }

    for (case.expected, filtered, 0..) |exp, got, i| {
        if (exp.type != got.type) {
            std.debug.print(
                "\n[{s}] token[{}] type mismatch: expected {s}, got {s}\n" ++
                    "  source: \"{s}\"\n",
                .{ case.name, i, exp.type.name(), got.type.name(), case.source },
            );
            return error.TokenTypeMismatch;
        }
        if (exp.value) |v| {
            if (got.value == null or !std.mem.eql(u8, v, got.value.?)) {
                std.debug.print(
                    "\n[{s}] token[{}] value mismatch: expected \"{s}\", got {?s}\n",
                    .{ case.name, i, v, got.value },
                );
                return error.TokenValueMismatch;
            }
        }
        if (exp.asm_str) |asm_str| {
            if (got.asm_str == null or !std.mem.eql(u8, asm_str, got.asm_str.?)) {
                std.debug.print(
                    "\n[{s}] token[{}] asm_str mismatch: expected \"{s}\", got {?s}\n",
                    .{ case.name, i, asm_str, got.asm_str },
                );
                return error.TokenAsmMismatch;
            }
        }
        if (exp.optional and !got.optional) {
            std.debug.print(
                "\n[{s}] token[{}] expected optional=true, got false\n",
                .{ case.name, i },
            );
            return error.TokenOptionalMismatch;
        }
        if (exp.line) |l| if (got.line == null or got.line.? != l) {
            std.debug.print(
                "\n[{s}] token[{}] line mismatch: expected {}, got {?}\n",
                .{ case.name, i, l, got.line },
            );
            return error.TokenLineMismatch;
        };
        if (exp.col) |c| if (got.col == null or got.col.? != c) {
            std.debug.print(
                "\n[{s}] token[{}] col mismatch: expected {}, got {?}\n",
                .{ case.name, i, c, got.col },
            );
            return error.TokenColMismatch;
        };
    }
}

/// Debug formatter for failed cases — lists token (type, value) pairs.
fn fmtTokens(tokens: []const sx.Node) FmtTokens {
    return .{ .tokens = tokens };
}

const FmtTokens = struct {
    tokens: []const sx.Node,

    pub fn format(self: FmtTokens, writer: anytype) !void {
        try writer.writeAll("[");
        for (self.tokens, 0..) |t, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("({s}, {?s})", .{ t.type.name(), t.value });
        }
        try writer.writeAll("]");
    }
};

test "tokeniser parity vs bitcoinsx" {
    var failed: usize = 0;
    var total: usize = 0;
    for (CASES) |case| {
        total += 1;
        runCase(case) catch |e| {
            std.debug.print("  FAIL: [{s}] {s}\n", .{ case.name, @errorName(e) });
            failed += 1;
        };
    }
    for (ERROR_CASES) |case| {
        total += 1;
        runCase(case) catch |e| {
            std.debug.print("  FAIL: [{s}] {s}\n", .{ case.name, @errorName(e) });
            failed += 1;
        };
    }
    std.debug.print(
        "\nparity: {}/{} cases passing ({} failing)\n",
        .{ total - failed, total, failed },
    );
    try std.testing.expectEqual(@as(usize, 0), failed);
}

```
