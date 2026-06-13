---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/src/parse.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.996953+00:00
---

# core/cell-engine/tools/sx/src/parse.zig

```zig
//! Parser — port of bitcoinsx's `src/sx/src/parser.ts`.
//!
//! Two passes:
//!
//! - **firstPass**: walks the token stream linearly, collects function
//!   definitions into `functions`, tracks `|` to flip `ctx` from
//!   scriptSig → scriptPubKey, registers imports. Doesn't emit nodes.
//! - **secondPass**: walks the tokens again, dispatches per token type
//!   (`parseNodeByType`), builds the AST tree under a root node.
//!
//! The AST root has `type = .root`; its children are the top-level nodes
//! in source order. Composite nodes (comments, repeats, functions,
//! templates) hold their content as children. Annotations attach to the
//! following node by mutating its `asm_str` (his `@t:` annotation handler
//! sets `asm` on the next token).
//!
//! ## PR-2 scope
//!
//! - Parser skeleton (state + two-pass scaffolding)
//! - Simple cases: empty, opcode, argument (default asm=OP_0), hex,
//!   string, bigint
//! - Parity test harness mirroring parseTypes.test.ts shape
//!
//! ## PR-2.1+ follow-ons
//!
//! - Comment composite (comment node owns child word tokens until close)
//! - Annotation @t: attachment to next node's asm
//! - Repeat block unrolling
//! - Function definitions + later calls
//! - Section markers (the `|` separator switching scriptSig/scriptPubKey
//!   context, producing the lockScript/unlockScript split downstream)
//! - Import resolution
//! - pushCodeData macro expansion
//! - AutoSlice / break

const std = @import("std");
const node = @import("node.zig");
const err = @import("error.zig");
const lex = @import("lex.zig");

pub const ParseError = struct {
    msg: []const u8,
    pos: u32 = 0,
    len: u32 = 0,
    line: u32 = 0,
    col: u32 = 0,
    file_name: []const u8 = "",
    function_name: ?[]const u8 = null,
};

pub const ParseResult = struct {
    /// Root AST node — type=.root, children = top-level parsed nodes.
    /// Null when a fatal error fires before the second pass starts.
    ast: ?node.Node = null,
    parse_error: ?ParseError = null,
};

/// Mirror of his `FileData` interface in `tokeniser.ts:11`. Required for
/// import resolution: `parseImport` looks up the imported filename in
/// the parent's project_files slice, tokenises + parses recursively,
/// then harvests the imported file's function defs into our functions
/// table.
pub const FileData = struct {
    id: []const u8,
    name: []const u8,
    data: []const u8,
};

/// Per `parser.ts:79`, his `ctx` starts as `"scriptSig"` and flips to
/// `"scriptPubKey"` on the `|` separator. Used downstream to split the
/// AST into unlockScript / lockScript halves.
pub const Ctx = enum { script_sig, script_pub_key };

/// Explicit error set for `parseNode` and its recursive callees
/// (parseRepeat, parseFunctionDef, parseComment). Zig needs the
/// error union resolved up-front when the call graph cycles.
pub const ParseErr = error{
    UnexpectedEnd,
    UnexpectedTokenType,
    UnmatchedEnd,
    UnsupportedTokenType,
    MalformedRepeat,
    RepeatBadCount,
    RepeatMissingEnd,
    FunctionMissingEnd,
    NothingToAnnotate,
    BadAnnotationValue,
    DescNonFunctionTarget,
    PushCodeDataNoMacro,
    PushCodeDataUnknownMacro,
    OutOfMemory,
    InvalidCharacter,
    Overflow,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    tokens: []const node.Node,
    pos: u32 = 0,
    file_name: []const u8 = "test.sx",
    /// `{ function_name → owned slice of body children }`. Body slice
    /// is allocated against `allocator` and cloned from the function
    /// node's children when parseFunctionDef finishes (also when import
    /// resolution harvests functions from a sibling file). pushCodeData
    /// inlining copies these children into its own node.
    functions: std.StringHashMapUnmanaged([]node.Node) = .{},
    /// Source files visible to import statements — corresponds to his
    /// `projectFiles` constructor param. Empty by default; populated by
    /// the test harness or downstream caller (the WASM shim will pass
    /// FileData[] received from JS).
    project_files: []const FileData = &[_]FileData{},
    ctx: Ctx = .script_sig,
    current_function_name: ?[]const u8 = null,
    parse_error: ?ParseError = null,

    pub fn init(allocator: std.mem.Allocator, tokens: []const node.Node) Parser {
        return .{ .allocator = allocator, .tokens = tokens };
    }

    pub fn initWithFiles(
        allocator: std.mem.Allocator,
        tokens: []const node.Node,
        file_name: []const u8,
        project_files: []const FileData,
    ) Parser {
        return .{
            .allocator = allocator,
            .tokens = tokens,
            .file_name = file_name,
            .project_files = project_files,
        };
    }

    pub fn parse(self: *Parser) ParseErr!ParseResult {
        if (self.tokens.len == 0) {
            return .{ .ast = node.Node.init(.root, null, 0) };
        }

        self.firstPass() catch {
            return .{ .parse_error = self.parse_error };
        };

        // secondPass walks the tokens again — reset pos.
        self.pos = 0;
        const ast = self.secondPass() catch {
            return .{ .parse_error = self.parse_error };
        };

        return .{ .ast = ast };
    }

    fn atEnd(self: *const Parser) bool {
        return self.pos >= self.tokens.len;
    }

    fn currentToken(self: *const Parser) node.Node {
        return self.tokens[self.pos];
    }

    /// Consume the current token if it matches `expected_type`, else
    /// record a parse error. Returns a COPY of the consumed token (the
    /// AST owns its nodes; we don't mutate the lexer's output).
    fn consume(self: *Parser, expected_type: node.NodeType) !node.Node {
        if (self.atEnd()) {
            self.parse_error = .{
                .msg = "Unexpected end of input",
                .file_name = self.file_name,
            };
            return error.UnexpectedEnd;
        }
        const t = self.tokens[self.pos];
        if (t.type != expected_type) {
            self.parse_error = .{
                .msg = "Unexpected token type",
                .pos = t.pos,
                .line = t.line orelse 0,
                .col = t.col orelse 0,
                .file_name = self.file_name,
            };
            return error.UnexpectedTokenType;
        }
        self.pos += 1;
        return t;
    }

    /// Skip whitespace tokens — they're emitted by the lexer but the
    /// parser usually doesn't care (his `secondPass` filters them at
    /// the addChildToNode stage). PR-2.1 will preserve them where they
    /// affect comment-end detection.
    fn skipWhitespace(self: *Parser) void {
        while (!self.atEnd() and self.currentToken().type == .whitespace) {
            self.pos += 1;
        }
    }

    fn firstPass(self: *Parser) ParseErr!void {
        // Walk tokens, register function NAMES (empty body — secondPass
        // fills the body via parseFunctionDef), flip ctx on `|`, harvest
        // imports.
        while (!self.atEnd()) {
            const t = self.currentToken();
            switch (t.type) {
                .function => {
                    if (t.value) |name| {
                        // Register with empty body; secondPass updates.
                        try self.functions.put(self.allocator, name, &[_]node.Node{});
                    }
                },
                .import => {
                    // Imports must be harvested in firstPass so their
                    // functions are visible to later call sites in this
                    // file (his compileDependency is invoked from
                    // parseImport, but his firstPass also pre-scans for
                    // the same reason). Look forward past whitespace for
                    // the filename string.
                    var look = self.pos + 1;
                    while (look < self.tokens.len and self.tokens[look].type == .whitespace) {
                        look += 1;
                    }
                    if (look < self.tokens.len and self.tokens[look].type == .string) {
                        if (self.tokens[look].value) |fname| {
                            try self.harvestImport(fname);
                        }
                    }
                },
                .word => {
                    // `|` separator → flip context (his `parser.ts:239`).
                    if (t.value) |v| {
                        if (std.mem.eql(u8, v, "|")) self.ctx = .script_pub_key;
                    }
                },
                else => {},
            }
            self.pos += 1;
        }
    }

    /// Locate `filename` in project_files, tokenise + recursively parse
    /// it, harvest its function defs into our `functions` map. Mirrors
    /// his `compileDependency` (parser.ts:534).
    fn harvestImport(self: *Parser, filename: []const u8) ParseErr!void {
        if (std.mem.eql(u8, filename, "stdlib") or std.mem.eql(u8, filename, "stdlib.sx")) {
            // His code has the stdlib branch commented out; nothing to do.
            return;
        }
        const file = blk: {
            for (self.project_files) |f| {
                if (std.mem.eql(u8, f.name, filename)) break :blk f;
            }
            // File not in project — silently ignore. PR-3.1 can promote
            // this to an error if/when consumer wants strict resolution.
            return;
        };

        // Tokenise the imported file.
        var sub_lexer = lex.Lexer.init(self.allocator, file.data);
        const sub_lex_res = sub_lexer.tokenise() catch return;
        if (sub_lex_res.tokenise_error != null) return;

        // Parse it. The sub-parser sees the SAME project_files so
        // transitive imports work. Functions map is independent.
        var sub_parser = Parser.initWithFiles(
            self.allocator,
            sub_lex_res.tokens.items,
            file.name,
            self.project_files,
        );
        const sub_res = sub_parser.parse() catch return;
        if (sub_res.parse_error != null) return;

        // Harvest function defs from sub-parser's functions map.
        var it = sub_parser.functions.iterator();
        while (it.next()) |entry| {
            // Skip if we already have this function (local defs win).
            if (self.functions.contains(entry.key_ptr.*)) continue;
            try self.functions.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    fn secondPass(self: *Parser) ParseErr!node.Node {
        var root = node.Node.init(.root, null, 0);
        while (!self.atEnd()) {
            self.skipWhitespace();
            if (self.atEnd()) break;
            const child = try self.parseNode();
            if (child) |c| {
                try root.children.append(self.allocator, c);
            }
        }
        return root;
    }

    /// Dispatch on the current token's type. Mirrors his
    /// `parseNodeByType` switch. After parsing a target node, checks for
    /// an inbound annotation and applies it (mirrors his `annotate()`
    /// post-target application).
    fn parseNode(self: *Parser) ParseErr!?node.Node {
        const t = self.currentToken();
        var parsed: ?node.Node = switch (t.type) {
            .whitespace => blk: {
                self.pos += 1;
                break :blk null;
            },
            .opcode => try self.consume(.opcode),
            .argument => try self.parseArgument(),
            .hex => try self.parseHex(),
            .string => try self.parseString(),
            .bigint => try self.parseBigint(),
            .comment => try self.parseComment(),
            .repeat => try self.parseRepeat(),
            .function => try self.parseFunctionDef(),
            .end => {
                // A bare `end` outside a function/repeat block is an
                // error (per his secondPass:312).
                self.parse_error = .{
                    .msg = "No opening func/repeat block to match end",
                    .pos = t.pos,
                    .line = t.line orelse 0,
                    .col = t.col orelse 0,
                    .file_name = self.file_name,
                };
                return error.UnmatchedEnd;
            },
            .word => try self.parseWordLike(),
            .call => blk: {
                // Lexer-promoted call (function name was already in
                // function_names before the lexer's left-to-right walk
                // reached this token). Inline the body the same way
                // parseWordLike does for parser-promoted calls.
                var c = try self.consume(.call);
                try self.inlineCallBody(&c);
                break :blk c;
            },
            .pushCodeData => try self.parsePushCodeData(),
            .import => try self.parseImport(),
            .annotation => {
                // A bare annotation with nothing preceding it is the
                // "Nothing to annotate" case from his annotate() (line
                // 641). Mirrors his error msg + offset.
                self.parse_error = .{
                    .msg = "Nothing to annotate",
                    .pos = t.pos,
                    // His error len includes `@` + key + `:` = full match.
                    .len = if (t.value) |v| @as(u32, @intCast(v.len + 2)) else 1,
                    .line = t.line orelse 0,
                    .col = t.col orelse 0,
                    .file_name = self.file_name,
                };
                return error.NothingToAnnotate;
            },
            // PR-2.3: .template, .import (need file IO + recursive parse)
            else => {
                self.parse_error = .{
                    .msg = "Unsupported token type at top level (PR-2.3)",
                    .pos = t.pos,
                    .line = t.line orelse 0,
                    .col = t.col orelse 0,
                    .file_name = self.file_name,
                };
                return error.UnsupportedTokenType;
            },
        };

        // Apply inbound annotation. Target type isn't restricted — his
        // annotate() (parser.ts:624) only errors when the target token
        // is missing entirely (`Nothing to annotate`). Call / word /
        // import targets are valid (his test fixture annotates calls
        // with @l: labels).
        if (parsed) |*p| {
            try self.maybeApplyAnnotation(p);
        }
        return parsed;
    }

    /// If the next non-whitespace tokens are `annotation` + `<value>`,
    /// consume both and apply the value to the target. Otherwise no-op.
    ///
    /// Annotation semantics (his `annotate()` at parser.ts:624):
    ///   - `t` / `test` → target.asm_str = value.asm_str (or value.value)
    ///   - `label` / `l` → target.label = value.value
    ///   - `desc` / `d` → (PR-2.2: target.description)
    ///   - `cs` → (PR-2.2: target.cs as parsed int)
    fn maybeApplyAnnotation(self: *Parser, target: *node.Node) !void {
        // Look ahead past whitespace for an annotation token.
        var look = self.pos;
        while (look < self.tokens.len and self.tokens[look].type == .whitespace) {
            look += 1;
        }
        if (look >= self.tokens.len) return;
        if (self.tokens[look].type != .annotation) return;
        const ann_key = self.tokens[look].value orelse return;

        // The value token follows (possibly with whitespace in between in
        // some grammars, but his lexer emits annotation→value directly
        // with no intervening ws: `@t:0100...` is annotation('t') then
        // hex('0100...'). We allow optional whitespace defensively.
        var val_idx = look + 1;
        while (val_idx < self.tokens.len and self.tokens[val_idx].type == .whitespace) {
            val_idx += 1;
        }
        if (val_idx >= self.tokens.len) return;
        const value_tok = self.tokens[val_idx];
        if (!isValidAnnotationValue(value_tok.type)) return;

        // Apply.
        if (std.mem.eql(u8, ann_key, "t") or std.mem.eql(u8, ann_key, "test")) {
            // His `tokens[toAnnotateIdx].asm = nextNode.asm`. Value's asm
            // is set by the lexer (hex → cleaned lowercase, string → utf8
            // hex, bigint → CScriptNum, word → null).
            if (value_tok.asm_str) |a| {
                target.asm_str = a;
            } else if (value_tok.value) |v| {
                // Word values (no asm_str) — pass the literal through.
                target.asm_str = v;
            }
        } else if (std.mem.eql(u8, ann_key, "label") or std.mem.eql(u8, ann_key, "l")) {
            target.label = value_tok.value;
        } else if (std.mem.eql(u8, ann_key, "desc") or std.mem.eql(u8, ann_key, "d")) {
            // His annotate(): `desc` is only valid on function targets;
            // otherwise throws "Expected a function to annotate with
            // description".
            if (target.type != .function) {
                self.parse_error = .{
                    .msg = "Expected a function to annotate with description",
                    .pos = target.pos,
                    .line = target.line orelse 0,
                    .col = target.col orelse 0,
                    .file_name = self.file_name,
                };
                return error.DescNonFunctionTarget;
            }
            target.description = value_tok.value;
        } else if (std.mem.eql(u8, ann_key, "cs")) {
            // His annotate(): `cs` parses int from value, stripping `n`
            // suffix if present.
            const v = value_tok.value orelse return;
            const digits = if (v.len > 0 and v[v.len - 1] == 'n') v[0 .. v.len - 1] else v;
            target.cs = try std.fmt.parseInt(i64, digits, 10);
        }

        // Advance past annotation + value (their whitespace tokens are
        // already accounted for by the skipWhitespace at loop top).
        self.pos = val_idx + 1;
    }

    fn isValidAnnotationValue(t: node.NodeType) bool {
        // His VALID_ANNOTATION_NEXT_TYPES = {word, string, hex, bigint}.
        return switch (t) {
            .word, .string, .hex, .bigint => true,
            else => false,
        };
    }

    /// `// ...` or `/* ... */` — fold following tokens until the close
    /// marker (or newline for single-line) as children of the comment
    /// node. His parseComment + parseMultilineComment.
    fn parseComment(self: *Parser) !node.Node {
        var comment = try self.consume(.comment);
        const is_multiline = if (comment.value) |v| std.mem.eql(u8, v, "/*") else false;

        if (is_multiline) {
            // Walk tokens until matching `*/` (depth-aware, mirroring his
            // parseMultilineComment).
            var depth: u32 = 1;
            while (!self.atEnd() and depth > 0) {
                const t = self.currentToken();
                if (t.type == .comment) {
                    if (t.value) |v| {
                        if (std.mem.eql(u8, v, "/*")) depth += 1;
                        if (std.mem.eql(u8, v, "*/")) depth -= 1;
                    }
                }
                try comment.children.append(self.allocator, t);
                self.pos += 1;
                if (depth == 0) break;
            }
        } else {
            // Single-line: fold until newline (his
            // currentTokenIsNotNewLine helper).
            while (!self.atEnd()) {
                const t = self.currentToken();
                if (t.type == .whitespace) {
                    if (t.value) |v| if (std.mem.indexOfScalar(u8, v, '\n') != null) break;
                }
                try comment.children.append(self.allocator, t);
                self.pos += 1;
            }
        }
        return comment;
    }

    /// `repeat N|.arg <body> end` — consume count, fold body, consume end.
    /// `value` set to the integer count (or "1" for argument-driven
    /// counts; the actual unroll happens at lower / compile time).
    fn parseRepeat(self: *Parser) ParseErr!node.Node {
        const start_pos = self.pos;
        const start_tok = self.currentToken();
        var repeat = try self.consume(.repeat);
        self.skipWhitespace();
        if (self.atEnd()) {
            self.parse_error = .{
                .msg = "Malformed repeat block",
                .pos = start_tok.pos,
                .len = 6,
                .line = start_tok.line orelse 0,
                .col = start_tok.col orelse 0,
                .file_name = self.file_name,
            };
            return error.MalformedRepeat;
        }
        const count_tok = self.currentToken();
        switch (count_tok.type) {
            .bigint => {
                _ = try self.consume(.bigint);
                // Value is the integer text (stripping `n` suffix). His
                // `repeatNode.value = String(parseInt(times.value.slice(0,-1)))`.
                if (count_tok.value) |v| {
                    if (v.len > 0 and v[v.len - 1] == 'n') {
                        repeat.value = v[0 .. v.len - 1];
                    } else repeat.value = v;
                }
            },
            .argument => {
                const arg = try self.consume(.argument);
                repeat.value = "1";
                // Argument name preserved on the repeat node's label as a
                // proxy for his `repeatArgName` field. PR-3 wires this
                // properly when the lowerer needs it.
                repeat.label = arg.value;
            },
            else => {
                self.parse_error = .{
                    .msg = "Repeat needs a BIGINT(n) or .argument to define it's count",
                    .pos = count_tok.pos,
                    .len = if (count_tok.value) |v| @as(u32, @intCast(v.len)) else 1,
                    .line = count_tok.line orelse 0,
                    .col = count_tok.col orelse 0,
                    .file_name = self.file_name,
                };
                return error.RepeatBadCount;
            },
        }

        // Body — parse children until `end`.
        while (!self.atEnd()) {
            self.skipWhitespace();
            if (self.atEnd()) break;
            if (self.currentToken().type == .end) break;
            const child = try self.parseNode();
            if (child) |c| try repeat.children.append(self.allocator, c);
        }

        if (self.atEnd() or self.currentToken().type != .end) {
            self.parse_error = .{
                .msg = "Repeat block missing 'end'",
                .pos = start_tok.pos,
                .line = start_tok.line orelse 0,
                .col = start_tok.col orelse 0,
                .file_name = self.file_name,
                .len = blk: {
                    // Span from repeat keyword start to last body byte
                    // (best-effort — his computation uses the last child's
                    // value length added to its pos).
                    if (repeat.children.items.len > 0) {
                        const last = repeat.children.items[repeat.children.items.len - 1];
                        const last_len: u32 = if (last.value) |v| @intCast(v.len) else 0;
                        break :blk last.pos + last_len - start_tok.pos;
                    }
                    break :blk 0;
                },
            };
            _ = start_pos;
            return error.RepeatMissingEnd;
        }
        _ = try self.consume(.end);
        return repeat;
    }

    /// A `word` token reaches here. His secondPass dispatch:
    ///   - `|` → consume as word (used as section separator)
    ///   - word that names a registered function → call(name)
    ///   - lowercase("autoslice") → autoSlice rewrite
    ///   - lowercase("break") → break rewrite (false + verify children)
    ///   - else: consume as word
    fn parseWordLike(self: *Parser) ParseErr!node.Node {
        const t = self.currentToken();
        const v = t.value orelse return try self.consume(.word);

        if (std.mem.eql(u8, v, "|")) {
            return try self.consume(.word);
        }
        // Function call promotion (his test corpus exercises this for
        // cases where the function was defined LATER in the source — the
        // lexer's left-to-right walk doesn't catch those). The lexer
        // handles the common forward case; this catches the rest.
        if (self.functions.contains(v)) {
            var n = try self.consume(.word);
            n.type = .call;
            try self.inlineCallBody(&n);
            return n;
        }
        // autoSlice rewrite (his parseAutoSlice).
        const lower_buf = try self.allocator.alloc(u8, v.len);
        for (v, 0..) |c, i| lower_buf[i] = std.ascii.toLower(c);
        defer self.allocator.free(lower_buf);
        if (std.mem.eql(u8, lower_buf, "autoslice")) {
            var n = try self.consume(.word);
            n.value = "autoSlice";
            return n;
        }
        // break rewrite — emit a call node with [false, verify] children.
        if (std.mem.eql(u8, lower_buf, "break")) {
            var n = try self.consume(.word);
            n.type = .call;
            var false_op = node.Node.init(.opcode, "false", n.pos);
            false_op.asm_str = "OP_FALSE";
            false_op.file_id = n.file_id;
            var verify_op = node.Node.init(.opcode, "verify", n.pos);
            verify_op.asm_str = "OP_VERIFY";
            verify_op.file_id = n.file_id;
            try n.children.append(self.allocator, false_op);
            try n.children.append(self.allocator, verify_op);
            return n;
        }
        return try self.consume(.word);
    }

    /// Look up `n.value` in the functions table and append the body as
    /// children of `n`. Mirrors his parseCall body-inline loop
    /// (parser.ts:697-708). Silent no-op when the function isn't yet
    /// registered — the lowerer will then emit nothing for the call.
    fn inlineCallBody(self: *Parser, n: *node.Node) ParseErr!void {
        const name = n.value orelse return;
        const body = self.functions.get(name) orelse return;
        for (body) |child| {
            try n.children.append(self.allocator, child);
        }
    }

    /// `pushCodeData <macroName>` — looks up the macro in the function
    /// table and inlines its body as children of the pushCodeData node.
    /// His parsePushCodeData.
    fn parsePushCodeData(self: *Parser) ParseErr!node.Node {
        const pcd = try self.consume(.pushCodeData);
        self.skipWhitespace();
        if (self.atEnd()) {
            self.parse_error = .{
                .msg = "Incomplete pushCodeData unrecognised macro name: ''",
                .pos = pcd.pos,
                .len = 0,
                .line = pcd.line orelse 0,
                .col = pcd.col orelse 0,
                .file_name = self.file_name,
                .function_name = self.current_function_name,
            };
            return error.PushCodeDataNoMacro;
        }
        const macro_tok = self.currentToken();
        // His check: only word/call types accepted as macro name.
        if (macro_tok.type != .word and macro_tok.type != .call) {
            self.parse_error = .{
                .msg = "Incomplete pushCodeData unrecognised macro name: ''",
                .pos = macro_tok.pos,
                .len = if (macro_tok.value) |v| @as(u32, @intCast(v.len)) else 0,
                .line = macro_tok.line orelse 0,
                .col = macro_tok.col orelse 0,
                .file_name = self.file_name,
                .function_name = self.current_function_name,
            };
            return error.PushCodeDataNoMacro;
        }
        _ = try self.consume(macro_tok.type);
        const macro_name = macro_tok.value orelse "";
        const body = self.functions.get(macro_name) orelse {
            // Build the error message matching his format.
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Incomplete pushCodeData unrecognised macro name: '{s}'",
                .{macro_name},
            );
            self.parse_error = .{
                .msg = msg,
                .pos = macro_tok.pos,
                .len = @as(u32, @intCast(macro_name.len)),
                .line = macro_tok.line orelse 0,
                .col = macro_tok.col orelse 0,
                .file_name = self.file_name,
                .function_name = self.current_function_name,
            };
            return error.PushCodeDataUnknownMacro;
        };
        // Inline the macro body as children of pcd (his parsePushCodeData
        // loop at line 405). Copy by value — pcd owns its children list.
        var pcd_mut = pcd;
        for (body) |child| {
            try pcd_mut.children.append(self.allocator, child);
        }
        return pcd_mut;
    }

    /// `#name <body> end` — fold body tokens as children of the function
    /// node. His parseFunction.
    fn parseFunctionDef(self: *Parser) ParseErr!node.Node {
        const start_tok = self.currentToken();
        var func = try self.consume(.function);
        self.current_function_name = func.value;
        defer self.current_function_name = null;

        while (!self.atEnd()) {
            self.skipWhitespace();
            if (self.atEnd()) break;
            if (self.currentToken().type == .end) break;
            const child = try self.parseNode();
            if (child) |c| try func.children.append(self.allocator, c);
        }
        if (self.atEnd() or self.currentToken().type != .end) {
            self.parse_error = .{
                .msg = "Macro block missing 'end'",
                .pos = start_tok.pos,
                .len = if (func.value) |v| @as(u32, @intCast(v.len + 1)) else 1,
                .line = start_tok.line orelse 0,
                .col = start_tok.col orelse 0,
                .file_name = self.file_name,
                .function_name = func.value,
            };
            return error.FunctionMissingEnd;
        }
        _ = try self.consume(.end);

        // Register the function's body so subsequent pushCodeData /
        // call-site inlining can find it. Clone the children slice into
        // a fresh allocation so its lifetime is independent of the
        // function node's children list.
        if (func.value) |name| {
            const body = try self.allocator.alloc(node.Node, func.children.items.len);
            @memcpy(body, func.children.items);
            try self.functions.put(self.allocator, name, body);
        }
        return func;
    }

    /// `import '<filename>'` — consumes import keyword + filename string.
    /// File resolution + function harvest already happened in firstPass
    /// (`harvestImport`). secondPass just emits the AST nodes.
    /// His parseImport.
    fn parseImport(self: *Parser) ParseErr!node.Node {
        var imp = try self.consume(.import);
        self.skipWhitespace();
        if (self.atEnd() or self.currentToken().type != .string) {
            self.parse_error = .{
                .msg = "Poorly formed import statement",
                .pos = imp.pos,
                .line = imp.line orelse 0,
                .col = imp.col orelse 0,
                .file_name = self.file_name,
            };
            return error.UnsupportedTokenType;
        }
        const fname = try self.consume(.string);
        try imp.children.append(self.allocator, fname);
        // His parseImport sets value to "import" — already the case since
        // we don't set value on the import node from the lexer either,
        // but his fixture asserts {type:import, value:"import"} on some
        // tests. Set explicitly to match.
        imp.value = "import";
        return imp;
    }

    /// His `parseNodeByType` for argument: emits the argument node with
    /// `asm = OP_0` when there's no inbound annotation. Annotation
    /// attachment is PR-2.1 (it modifies `asm` based on a preceding
    /// `@t:`).
    fn parseArgument(self: *Parser) !node.Node {
        var n = try self.consume(.argument);
        // Default asm — his `getDefaultArgAsm` returns "OP_0" when no
        // type hint is available. We don't have argType inference yet,
        // so this is the unconditional default for PR-2.
        n.asm_str = "OP_0";
        return n;
    }

    /// Hex token already carries `asm_str` set by the lexer (= the
    /// lowercased value). His parser just passes it through.
    fn parseHex(self: *Parser) !node.Node {
        return try self.consume(.hex);
    }

    /// String token already carries `asm_str` = utf-8 hex from the lexer.
    fn parseString(self: *Parser) !node.Node {
        return try self.consume(.string);
    }

    /// Bigint passthrough. His `parseBigint` is essentially `consume`
    /// + the lexer has already set `asm` via `convertBigIntToASM`. PR-3
    /// (lowerer) populates the asm field properly; for PR-2 we pass it
    /// through.
    fn parseBigint(self: *Parser) !node.Node {
        return try self.consume(.bigint);
    }
};

test "parser: empty token stream yields empty root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var p = Parser.init(arena.allocator(), &[_]node.Node{});
    const res = try p.parse();
    try std.testing.expect(res.ast != null);
    try std.testing.expectEqual(node.NodeType.root, res.ast.?.type);
    try std.testing.expectEqual(@as(usize, 0), res.ast.?.children.items.len);
}

test "parser: single opcode passes through" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = lex.Lexer.init(arena.allocator(), "nop");
    const lex_res = try lexer.tokenise();
    var p = Parser.init(arena.allocator(), lex_res.tokens.items);
    const res = try p.parse();
    try std.testing.expect(res.ast != null);
    try std.testing.expectEqual(@as(usize, 1), res.ast.?.children.items.len);
    const c = res.ast.?.children.items[0];
    try std.testing.expectEqual(node.NodeType.opcode, c.type);
    try std.testing.expectEqualStrings("OP_NOP", c.asm_str.?);
}

test "parser: argument default asm is OP_0" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = lex.Lexer.init(arena.allocator(), ".argName");
    const lex_res = try lexer.tokenise();
    var p = Parser.init(arena.allocator(), lex_res.tokens.items);
    const res = try p.parse();
    try std.testing.expectEqual(@as(usize, 1), res.ast.?.children.items.len);
    const c = res.ast.?.children.items[0];
    try std.testing.expectEqual(node.NodeType.argument, c.type);
    try std.testing.expectEqualStrings("argName", c.value.?);
    try std.testing.expectEqualStrings("OP_0", c.asm_str.?);
}

```
