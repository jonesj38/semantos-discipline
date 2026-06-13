---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/tests/parity_parse.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.994228+00:00
---

# core/cell-engine/tools/sx/tests/parity_parse.zig

```zig
//! Parity test driver for the `.sx` parser.
//!
//! Mirrors the shape of bitcoinsx's
//! `src/sx/tests/parser/parseTypes.test.ts`. His test runner builds a
//! tokeniser → parser pipeline and asserts on the AST children of the
//! returned root node.
//!
//! ## How to add a case
//!
//! 1. Find the next un-ported case in his `parseTypes.test.ts`
//! 2. Copy `script:` source into `source` field below
//! 3. Translate `expected: [...]` into our `ExpectedNode` array; nested
//!    children become `children: &[_]ExpectedNode{...}`.
//! 4. Run `zig build test`
//! 5. If it fails, fix `parse.zig` (NOT the expectation)
//!
//! ## Coverage state (kept current as cases land)
//!
//! His parseTypes.test.ts: 396 LOC. ~22 cases (some commented out).
//! Cases ported here:  6  (PR-2 skeleton — empty / opcode / argument /
//!                          hex / string / bigint)
//! Cases remaining:   ~16 (PR-2.1+ — comments, annotations, repeats,
//!                          functions, if/else, sections, imports,
//!                          pushCodeData, templates)

const std = @import("std");
const sx = @import("sx");

const ExpectedNode = struct {
    type: sx.NodeType,
    value: ?[]const u8 = null,
    asm_str: ?[]const u8 = null,
    label: ?[]const u8 = null,
    cs: ?i64 = null,
    children: []const ExpectedNode = &[_]ExpectedNode{},
};

const ExpectedError = struct {
    msg_contains: []const u8,
    line: ?u32 = null,
    col: ?u32 = null,
};

const Case = struct {
    name: []const u8,
    source: []const u8,
    expected: []const ExpectedNode,
    expected_error: ?ExpectedError = null,
    /// Imported files visible to the parser via `initWithFiles`. Mirrors
    /// his test runner passing `[{...self}, stdFile]` as projectFiles
    /// — except we pin a minimal stub per case so each test is
    /// self-contained.
    project_files: []const sx.parse.FileData = &[_]sx.parse.FileData{},
};

const CASES = [_]Case{
    .{
        .name = "empty source yields empty root",
        .source = "",
        .expected = &[_]ExpectedNode{},
    },
    .{
        .name = "single opcode",
        .source = "nop",
        .expected = &[_]ExpectedNode{
            .{ .type = .opcode, .asm_str = "OP_NOP" },
        },
    },
    .{
        .name = "argument with default asm OP_0",
        .source = ".argName",
        .expected = &[_]ExpectedNode{
            .{ .type = .argument, .value = "argName", .asm_str = "OP_0" },
        },
    },
    .{
        .name = "bare hex passes through",
        .source = "deadbeef",
        .expected = &[_]ExpectedNode{
            .{ .type = .hex, .asm_str = "deadbeef" },
        },
    },
    .{
        .name = "single-quoted string carries utf-8 hex asm",
        .source = "'string'",
        .expected = &[_]ExpectedNode{
            .{ .type = .string, .asm_str = "737472696e67" },
        },
    },
    .{
        .name = "bigint passes through",
        .source = "12345n",
        .expected = &[_]ExpectedNode{
            .{ .type = .bigint, .value = "12345n" },
        },
    },
    // ---- PR-2.1 cases: annotations, comments, repeats, functions ----
    .{
        .name = "label annotation sets target label, asm stays OP_0",
        .source = ".pKH @label:123",
        .expected = &[_]ExpectedNode{
            .{ .type = .argument, .value = "pKH", .asm_str = "OP_0" },
        },
    },
    .{
        .name = "test annotation with hex value sets target asm",
        .source = ".bobPubKeyHash @test:deadbeef",
        .expected = &[_]ExpectedNode{
            .{ .type = .argument, .value = "bobPubKeyHash", .asm_str = "deadbeef" },
        },
    },
    .{
        .name = "t-short annotation with long hex sets target asm",
        .source = ".charliePubKeyHash @t:0100000000000000deadbeefbabecafe",
        .expected = &[_]ExpectedNode{
            .{ .type = .argument, .value = "charliePubKeyHash", .asm_str = "0100000000000000deadbeefbabecafe" },
        },
    },
    .{
        .name = "label-short annotation with spaced string",
        .source = ".pubKeyHash @l:'spaced string'",
        .expected = &[_]ExpectedNode{
            .{ .type = .argument, .value = "pubKeyHash", .asm_str = "OP_0" },
        },
    },
    .{
        .name = "test annotation with negative bigint encodes via CScriptNum",
        .source = ".sumting @test:-123n",
        .expected = &[_]ExpectedNode{
            .{ .type = .argument, .value = "sumting", .asm_str = "fb" },
        },
    },
    .{
        .name = "repeat with bigint count",
        .source = "repeat 3n 3n end",
        .expected = &[_]ExpectedNode{
            .{
                .type = .repeat,
                .value = "3",
                .children = &[_]ExpectedNode{
                    .{ .type = .bigint, .value = "3n", .asm_str = "OP_3" },
                },
            },
        },
    },
    .{
        .name = "repeat with argument count and opcode body",
        .source = "repeat .cnt nop end",
        .expected = &[_]ExpectedNode{
            .{
                .type = .repeat,
                .value = "1",
                .children = &[_]ExpectedNode{
                    .{ .type = .opcode, .value = "nop", .asm_str = "OP_NOP" },
                },
            },
        },
    },
    .{
        .name = "nested repeat",
        .source = "repeat 3n 3n repeat 2n 2n end end",
        .expected = &[_]ExpectedNode{
            .{
                .type = .repeat,
                .value = "3",
                .children = &[_]ExpectedNode{
                    .{ .type = .bigint, .value = "3n", .asm_str = "OP_3" },
                    .{
                        .type = .repeat,
                        .value = "2",
                        .children = &[_]ExpectedNode{
                            .{ .type = .bigint, .value = "2n", .asm_str = "OP_2" },
                        },
                    },
                },
            },
        },
    },
    .{
        .name = "function definition body",
        .source = "#function 3n 'string' end",
        .expected = &[_]ExpectedNode{
            .{
                .type = .function,
                .value = "function",
                .children = &[_]ExpectedNode{
                    .{ .type = .bigint, .value = "3n", .asm_str = "OP_3" },
                    .{ .type = .string, .value = "string", .asm_str = "737472696e67" },
                },
            },
        },
    },
    .{
        .name = "single-line comment with following words",
        .source = "nop//comment",
        .expected = &[_]ExpectedNode{
            .{ .type = .opcode, .value = "nop", .asm_str = "OP_NOP" },
            .{
                .type = .comment,
                .value = "//",
                .children = &[_]ExpectedNode{
                    .{ .type = .word, .value = "comment" },
                },
            },
        },
    },
    // ---- PR-2.2 cases ----
    .{
        .name = "function def + later call",
        .source = "#function 3n 'string' end function",
        .expected = &[_]ExpectedNode{
            .{
                .type = .function,
                .value = "function",
                .children = &[_]ExpectedNode{
                    .{ .type = .bigint, .value = "3n", .asm_str = "OP_3" },
                    .{ .type = .string, .value = "string", .asm_str = "737472696e67" },
                },
            },
            .{ .type = .call, .value = "function" },
        },
    },
    .{
        .name = "nested function definitions with calls",
        .source = "#function 3n 'string' #innerFunc 2n end innerFunc end function",
        .expected = &[_]ExpectedNode{
            .{
                .type = .function,
                .value = "function",
                .children = &[_]ExpectedNode{
                    .{ .type = .bigint, .value = "3n", .asm_str = "OP_3" },
                    .{ .type = .string, .value = "string", .asm_str = "737472696e67" },
                    .{
                        .type = .function,
                        .value = "innerFunc",
                        .children = &[_]ExpectedNode{
                            .{ .type = .bigint, .value = "2n", .asm_str = "OP_2" },
                        },
                    },
                    .{ .type = .call, .value = "innerFunc" },
                },
            },
            .{ .type = .call, .value = "function" },
        },
    },
    .{
        .name = "flow-control opcode chain",
        .source = "if nop else drop endif",
        .expected = &[_]ExpectedNode{
            .{ .type = .opcode, .value = "if", .asm_str = "OP_IF" },
            .{ .type = .opcode, .asm_str = "OP_NOP" },
            .{ .type = .opcode, .asm_str = "OP_ELSE" },
            .{ .type = .opcode, .asm_str = "OP_DROP" },
            .{ .type = .opcode, .asm_str = "OP_ENDIF" },
        },
    },
    .{
        .name = "@cs annotation with bigint sets cs field",
        .source = ".ctx @cs:2n | nop",
        .expected = &[_]ExpectedNode{
            .{ .type = .argument, .value = "ctx", .cs = 2 },
            .{ .type = .word, .value = "|" },
            .{ .type = .opcode, .value = "nop" },
        },
    },
    .{
        .name = "section separator + codeSeparator after annotated arg",
        .source = ".ctxSingleACP @cs:1n | codeSeparator nop",
        .expected = &[_]ExpectedNode{
            .{ .type = .argument, .value = "ctxSingleACP", .cs = 1 },
            .{ .type = .word, .value = "|" },
            .{ .type = .opcode, .value = "codeSeparator" },
            .{ .type = .opcode, .value = "nop" },
        },
    },
    .{
        .name = "pushCodeData with registered macro",
        .source = "#beefMacro beef end | pushCodeData beefMacro",
        .expected = &[_]ExpectedNode{
            .{ .type = .function, .value = "beefMacro" },
            .{ .type = .word, .value = "|" },
            .{ .type = .pushCodeData, .value = "pushCodeData" },
        },
    },
    .{
        .name = "label annotation explicit fixture",
        .source = ".alicePubKeyHash @label:123",
        .expected = &[_]ExpectedNode{
            .{ .type = .argument, .value = "alicePubKeyHash", .asm_str = "OP_0", .label = "123" },
        },
    },
    // ---- PR-2.3 cases: pushCodeData body inlining + import resolution ----
    .{
        .name = "pushCodeData inlines macro body",
        .source = "#beefMacro beef end pushCodeData beefMacro",
        .expected = &[_]ExpectedNode{
            .{
                .type = .function,
                .value = "beefMacro",
                .children = &[_]ExpectedNode{
                    .{ .type = .hex, .value = "beef" },
                },
            },
            .{
                .type = .pushCodeData,
                .value = "pushCodeData",
                .children = &[_]ExpectedNode{
                    // Inlined from beefMacro's body.
                    .{ .type = .hex, .value = "beef" },
                },
            },
        },
    },
    .{
        .name = "pushCodeDataV variant inlines macro body",
        .source = "#beefMacro beef end pushCodeDataV beefMacro",
        .expected = &[_]ExpectedNode{
            .{
                .type = .function,
                .value = "beefMacro",
                .children = &[_]ExpectedNode{
                    .{ .type = .hex, .value = "beef" },
                },
            },
            .{
                .type = .pushCodeData,
                .value = "pushCodeDataV",
                .children = &[_]ExpectedNode{
                    .{ .type = .hex, .value = "beef" },
                },
            },
        },
    },
    .{
        .name = "import resolves and call site promotes word→call",
        .source = "import 'tiny.sx'\n      foo",
        .expected = &[_]ExpectedNode{
            .{ .type = .import, .value = "import" },
            .{ .type = .call, .value = "foo" },
        },
        .project_files = &[_]sx.parse.FileData{
            .{ .id = "1", .name = "tiny.sx", .data = "#foo nop end" },
        },
    },
    .{
        .name = "import with multiple defined functions",
        .source = "import 'stub.sx'\n      mod2 @l:mod2",
        .expected = &[_]ExpectedNode{
            .{ .type = .import, .value = "import" },
            .{ .type = .call, .value = "mod2", .label = "mod2" },
        },
        .project_files = &[_]sx.parse.FileData{
            .{ .id = "1", .name = "stub.sx", .data = "#mod2 2n mod end\n#p2pkh dup hash160 .pubKeyHash equalVerify checkSig end" },
        },
    },
    .{
        .name = "import + two call sites of the same imported function",
        .source = "import 'stub.sx'\n      mod2 @l:mod2\n      mod2",
        .expected = &[_]ExpectedNode{
            .{ .type = .import, .value = "import" },
            .{ .type = .call, .value = "mod2", .label = "mod2" },
            .{ .type = .call, .value = "mod2" },
        },
        .project_files = &[_]sx.parse.FileData{
            .{ .id = "1", .name = "stub.sx", .data = "#mod2 2n mod end" },
        },
    },
};

/// Parser error cases — driven by his parseTypes.test.ts expectedError
/// fixtures. Separate table so the main loop stays simple.
const ERROR_CASES = [_]Case{
    .{
        .name = "annotation with no preceding target",
        .source = "@test:123",
        .expected = &[_]ExpectedNode{},
        .expected_error = .{ .msg_contains = "Nothing to annotate", .line = 1, .col = 1 },
    },
    .{
        .name = "bare repeat is malformed",
        .source = "repeat",
        .expected = &[_]ExpectedNode{},
        .expected_error = .{ .msg_contains = "Malformed repeat block", .line = 1, .col = 1 },
    },
    .{
        .name = "repeat with int but no n suffix rejects count",
        .source = "repeat 1 nop end",
        .expected = &[_]ExpectedNode{},
        .expected_error = .{
            .msg_contains = "Repeat needs a BIGINT(n) or .argument to define it's count",
            .line = 1,
            .col = 8,
        },
    },
    .{
        .name = "repeat body without closing end",
        .source = "repeat 3n 'string'",
        .expected = &[_]ExpectedNode{},
        .expected_error = .{ .msg_contains = "Repeat block missing 'end'", .line = 1, .col = 1 },
    },
    .{
        .name = "function block without closing end",
        .source = "#function 3n 'string'",
        .expected = &[_]ExpectedNode{},
        .expected_error = .{ .msg_contains = "Macro block missing 'end'", .line = 1, .col = 1 },
    },
    .{
        .name = "pushCodeData with unregistered macro",
        .source = "pushCodeData beefMacro2",
        .expected = &[_]ExpectedNode{},
        .expected_error = .{
            .msg_contains = "Incomplete pushCodeData unrecognised macro name: 'beefMacro2'",
            .line = 1,
            .col = 14,
        },
    },
};

fn runCase(case: Case) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var lexer = sx.Lexer.init(arena.allocator(), case.source);
    const lex_res = try lexer.tokenise();
    var parser = sx.Parser.initWithFiles(
        arena.allocator(),
        lex_res.tokens.items,
        "test.sx",
        case.project_files,
    );
    const parse_res = try parser.parse();

    // Error cases: assert error fired with the right shape.
    if (case.expected_error) |exp_err| {
        const got = parse_res.parse_error orelse {
            std.debug.print(
                "\n[{s}] expected parse error containing \"{s}\", got none\n",
                .{ case.name, exp_err.msg_contains },
            );
            return error.ExpectedParseError;
        };
        if (std.mem.indexOf(u8, got.msg, exp_err.msg_contains) == null) {
            std.debug.print(
                "\n[{s}] parse-error msg mismatch: expected to contain \"{s}\", got \"{s}\"\n",
                .{ case.name, exp_err.msg_contains, got.msg },
            );
            return error.ParseErrorMsgMismatch;
        }
        if (exp_err.line) |l| if (got.line != l) {
            std.debug.print(
                "\n[{s}] parse-error line mismatch: expected {}, got {}\n",
                .{ case.name, l, got.line },
            );
            return error.ParseErrorLineMismatch;
        };
        if (exp_err.col) |c| if (got.col != c) {
            std.debug.print(
                "\n[{s}] parse-error col mismatch: expected {}, got {}\n",
                .{ case.name, c, got.col },
            );
            return error.ParseErrorColMismatch;
        };
        return;
    }

    if (parse_res.parse_error) |e| {
        std.debug.print(
            "\n[{s}] unexpected parse error: \"{s}\" at line={d} col={d}\n" ++
                "  source: \"{s}\"\n",
            .{ case.name, e.msg, e.line, e.col, case.source },
        );
        return error.UnexpectedParseError;
    }

    const root = parse_res.ast orelse {
        std.debug.print("\n[{s}] no AST produced\n", .{case.name});
        return error.NoAst;
    };
    if (root.type != .root) {
        std.debug.print("\n[{s}] AST root type {s}, expected root\n", .{ case.name, root.type.name() });
        return error.NonRootAst;
    }
    if (root.children.items.len != case.expected.len) {
        std.debug.print(
            "\n[{s}] root child count mismatch: expected {}, got {}\n" ++
                "  source: \"{s}\"\n",
            .{ case.name, case.expected.len, root.children.items.len, case.source },
        );
        return error.ChildCountMismatch;
    }
    for (case.expected, root.children.items, 0..) |exp, got, i| {
        try checkNode(case.name, i, exp, got);
    }
}

fn checkNode(case_name: []const u8, idx: usize, exp: ExpectedNode, got: sx.Node) !void {
    if (exp.type != got.type) {
        std.debug.print(
            "\n[{s}] child[{}] type mismatch: expected {s}, got {s}\n",
            .{ case_name, idx, exp.type.name(), got.type.name() },
        );
        return error.TypeMismatch;
    }
    if (exp.value) |v| {
        if (got.value == null or !std.mem.eql(u8, v, got.value.?)) {
            std.debug.print(
                "\n[{s}] child[{}] value mismatch: expected \"{s}\", got {?s}\n",
                .{ case_name, idx, v, got.value },
            );
            return error.ValueMismatch;
        }
    }
    if (exp.asm_str) |asm_str| {
        if (got.asm_str == null or !std.mem.eql(u8, asm_str, got.asm_str.?)) {
            std.debug.print(
                "\n[{s}] child[{}] asm_str mismatch: expected \"{s}\", got {?s}\n",
                .{ case_name, idx, asm_str, got.asm_str },
            );
            return error.AsmMismatch;
        }
    }
    if (exp.label) |l| {
        if (got.label == null or !std.mem.eql(u8, l, got.label.?)) {
            std.debug.print(
                "\n[{s}] child[{}] label mismatch: expected \"{s}\", got {?s}\n",
                .{ case_name, idx, l, got.label },
            );
            return error.LabelMismatch;
        }
    }
    if (exp.cs) |c| {
        if (got.cs == null or got.cs.? != c) {
            std.debug.print(
                "\n[{s}] child[{}] cs mismatch: expected {}, got {?}\n",
                .{ case_name, idx, c, got.cs },
            );
            return error.CsMismatch;
        }
    }
    // Recursive grandchild check for composite nodes (comment / repeat /
    // function). Expectation with empty `children` slice doesn't pin
    // grandchild count, matching his validateNode's loose check.
    if (exp.children.len > 0) {
        if (got.children.items.len != exp.children.len) {
            std.debug.print(
                "\n[{s}] child[{}] grandchild count mismatch: expected {}, got {}\n",
                .{ case_name, idx, exp.children.len, got.children.items.len },
            );
            return error.GrandchildCountMismatch;
        }
        for (exp.children, got.children.items, 0..) |sub_exp, sub_got, sub_i| {
            try checkNode(case_name, sub_i, sub_exp, sub_got);
        }
    }
}

test "parser parity vs bitcoinsx" {
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
        "\nparser parity: {}/{} cases passing ({} failing)\n",
        .{ total - failed, total, failed },
    );
    try std.testing.expectEqual(@as(usize, 0), failed);
}

```
