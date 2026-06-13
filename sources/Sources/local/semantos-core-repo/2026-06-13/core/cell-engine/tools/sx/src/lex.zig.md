---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/src/lex.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.995674+00:00
---

# core/cell-engine/tools/sx/src/lex.zig

```zig
//! Tokeniser — port of bitcoinsx's `src/sx/src/tokeniser.ts`.
//!
//! State + dispatch table approach: the lexer holds (source, pos, line,
//! col) and dispatches each token-start character through a small set of
//! recognisers ordered by precedence. Mirrors his `tokenise()` loop in
//! `tokeniser.ts` lines 414+.
//!
//! ## PR-1 scope
//!
//! - Skeleton state machine
//! - Recognisers for: opcode, argument, bigint, hex (bare), string, end
//!   keyword, repeat keyword, annotation, single-line comment
//! - First parity test (see `tests/parity_tokenise.zig`) drives ~10 cases
//!   from his `tokeniseTypes.test.ts`
//!
//! ## PR-1.1 follow-on (not in this PR)
//!
//! - Multi-line `/* ... */` nested comments (he supports D-style nesting)
//! - Template literals (backtick + `${...}` interpolation)
//! - `#function ... end` block recognition (composite token)
//! - `repeat N ... end` block recognition (composite token)
//! - `import 'path.sx'` directive
//! - `0x`-prefixed hex literal variant
//! - Negative bigint sign tracking edge cases
//!
//! ## Fidelity discipline
//!
//! Per parity test, our token stream must match his test fixture EXACTLY
//! in (type, value, asm_str). Position / line / col fidelity is asserted
//! in PR-1.1 once the simple-case tokens line up.

const std = @import("std");
const node = @import("node.zig");
const err = @import("error.zig");
const short_ops = @import("short_ops.zig");

pub const TokeniseResult = struct {
    tokens: std.ArrayList(node.Node),
    /// Set when the lexer encountered a fatal error. Mirrors his
    /// `tokeniseError?: TokeniserError` field on `TokeniseResult`.
    tokenise_error: ?err.TokeniserError = null,
    file_id: []const u8,
};

/// State for nested multi-line and active single-line comments. Mirrors
/// his `commentState` struct in `tokeniser.ts:33`.
pub const CommentState = struct {
    in_single_line: bool = false,
    multiline_depth: u32 = 0,

    pub fn inComment(self: CommentState) bool {
        return self.in_single_line or self.multiline_depth > 0;
    }
};

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: u32 = 0,
    line: u32 = 1,
    col: u32 = 1,
    file_name: []const u8 = "test.sx",
    file_id: []const u8 = "0",
    /// Function names registered via `#name`. Subsequent bare words that
    /// match are emitted as `call(name)` instead of `word(name)`. Mirrors
    /// his `_functionNamesSet` in `tokeniser.ts`.
    function_names: std.StringHashMapUnmanaged(void) = .{},
    /// Comment depth tracker — `/*` increments, `*/` decrements; `//`
    /// flips `in_single_line` until next `\n`. While inside a comment,
    /// the lexer suppresses opcode/keyword/function-call resolution
    /// (mirrors his `tryWord` `isInComment()` branch).
    comment_state: CommentState = .{},
    /// Tokenise error set when the lexer hits a fatal-but-not-throwing
    /// condition (e.g. unrecognised annotation key). Mirrors his
    /// `tokeniseError` field on `TokeniseResult`. Copied into the result
    /// at the end of `tokenise()`.
    tokenise_error: ?err.TokeniserError = null,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        return .{ .allocator = allocator, .source = source };
    }

    /// Top-level entry. Returns owned tokens; caller deinits via the
    /// arena/allocator used to construct the Lexer.
    pub fn tokenise(self: *Lexer) !TokeniseResult {
        var tokens: std.ArrayList(node.Node) = .{};

        while (self.pos < self.source.len) {
            // Halt on first hard error (his behaviour: throwError exits
            // the loop via JS catch and returns partial tokens + error).
            if (self.tokenise_error != null) break;
            // Whitespace as a token (matches his tryWhitespace). Newline
            // also clears the single-line-comment state.
            if (isWhitespace(self.source[self.pos])) {
                try self.lexWhitespace(&tokens);
                continue;
            }

            const ch = self.source[self.pos];

            // Comment-state shortcut: while inside a comment (single-line
            // OR multi-line), opcode/keyword resolution is suppressed;
            // content runs are emitted as `word` tokens. Multi-line also
            // handles `/*` (nested open) and `*/` (close). Single-line is
            // cleared by the whitespace recogniser on `\n`.
            if (self.comment_state.inComment()) {
                if (self.comment_state.multiline_depth > 0) {
                    if (ch == '*' and self.peekAt(1) == '/') {
                        try self.lexMultilineCommentClose(&tokens);
                        continue;
                    }
                    if (ch == '/' and self.peekAt(1) == '*') {
                        try self.lexMultilineCommentOpen(&tokens);
                        continue;
                    }
                }
                try self.lexCommentContentWord(&tokens);
                continue;
            }

            // Dispatch on the next character. Order matters where prefixes
            // overlap (e.g. '.' for argument is unambiguous; bare hex must
            // be checked after opcode because some opcodes start with hex
            // chars like "abs" — handled by `\b` requirement in shortOps).
            if (ch == '/' and self.peekAt(1) == '/') {
                try self.lexLineComment(&tokens);
            } else if (ch == '/' and self.peekAt(1) == '*') {
                try self.lexMultilineCommentOpen(&tokens);
            } else if (ch == '.') {
                try self.lexArgument(&tokens);
            } else if (ch == '@') {
                try self.lexAnnotation(&tokens);
            } else if (ch == '"' or ch == '\'') {
                try self.lexString(&tokens);
            } else if (ch == '`') {
                try self.lexTemplate(&tokens);
            } else if (ch == '#') {
                try self.lexFunctionDef(&tokens);
            } else if (ch == '|') {
                // His `keywordToNodeType['|'] === nodeTypes.word`. Single
                // bar emitted as a word with value "|".
                try tokens.append(self.allocator, node.Node.init(.word, self.source[self.pos .. self.pos + 1], self.pos));
                self.pos += 1;
                self.col += 1;
            } else if (std.ascii.isAlphabetic(ch) or ch == '_') {
                // Could be opcode, keyword (end/repeat/import/pushCodeData),
                // function call, or word.
                try self.lexIdentifierLike(&tokens);
            } else if (std.ascii.isDigit(ch) or ch == '+' or ch == '-') {
                // Could be bigint, hex (bare-hex starting with [0-9]), or
                // a signed bare-int word like `-123`.
                try self.lexNumberOrHex(&tokens);
            } else if (std.ascii.isHex(ch)) {
                try self.lexBareHex(&tokens);
            } else {
                // PR-1.2: section markers, etc. Skip unknown for now.
                self.pos += 1;
                self.col += 1;
            }
        }

        return .{
            .tokens = tokens,
            .tokenise_error = self.tokenise_error,
            .file_id = self.file_id,
        };
    }

    // -------------------------------------------------------------------
    // Recognisers
    // -------------------------------------------------------------------

    fn lexWhitespace(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        while (self.pos < self.source.len and isWhitespace(self.source[self.pos])) {
            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.col = 1;
                // Newline ends any active single-line comment.
                self.comment_state.in_single_line = false;
            } else {
                self.col += 1;
            }
            self.pos += 1;
        }
        var n = node.Node.init(.whitespace, self.source[start..self.pos], start);
        n.line = start_line;
        n.col = start_col;
        try tokens.append(self.allocator, n);
    }

    fn lexLineComment(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        // Consume `//` — value of comment token is the marker itself (his
        // behaviour at tokeniser.ts:225).
        self.pos += 2;
        self.col += 2;
        self.comment_state.in_single_line = true;
        var marker = node.Node.init(.comment, self.source[start .. start + 2], start);
        marker.line = start_line;
        marker.col = start_col;
        try tokens.append(self.allocator, marker);

        // Rest of the line becomes a `word` token. His `tryWord` regex
        // `^(?:\\.|[^\n*\` \s]|(?!\*\/)\*)+` excludes whitespace; so the
        // word here is just the run until the next whitespace.
        const word_start = self.pos;
        const word_line = self.line;
        const word_col = self.col;
        while (self.pos < self.source.len and self.source[self.pos] != '\n' and !isWhitespace(self.source[self.pos])) {
            self.pos += 1;
            self.col += 1;
        }
        if (self.pos > word_start) {
            var w = node.Node.init(.word, self.source[word_start..self.pos], word_start);
            w.line = word_line;
            w.col = word_col;
            try tokens.append(self.allocator, w);
        }
    }

    fn lexMultilineCommentOpen(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        self.pos += 2;
        self.col += 2;
        self.comment_state.multiline_depth += 1;
        var n = node.Node.init(.comment, self.source[start .. start + 2], start);
        n.line = start_line;
        n.col = start_col;
        try tokens.append(self.allocator, n);
    }

    fn lexMultilineCommentClose(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        self.pos += 2;
        self.col += 2;
        if (self.comment_state.multiline_depth > 0) {
            self.comment_state.multiline_depth -= 1;
        }
        var n = node.Node.init(.comment, self.source[start .. start + 2], start);
        n.line = start_line;
        n.col = start_col;
        try tokens.append(self.allocator, n);
    }

    /// Inside a multi-line comment, content runs are emitted as `word`
    /// tokens (his `tryWord` `isInComment()` branch). We consume up to
    /// the next whitespace, `*/`, or `/*`.
    fn lexCommentContentWord(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        while (self.pos < self.source.len and !isWhitespace(self.source[self.pos])) {
            // Stop at `*/` or `/*` so the comment-state handler picks them up.
            if (self.source[self.pos] == '*' and self.peekAt(1) == '/') break;
            if (self.source[self.pos] == '/' and self.peekAt(1) == '*') break;
            self.pos += 1;
            self.col += 1;
        }
        if (self.pos > start) {
            var w = node.Node.init(.word, self.source[start..self.pos], start);
            w.line = start_line;
            w.col = start_col;
            try tokens.append(self.allocator, w);
        } else {
            // Defensive: if we're stopped on a single `*` or `/` with no
            // following `/` or `*`, consume one char so we don't loop forever.
            self.pos += 1;
            self.col += 1;
        }
    }

    fn lexArgument(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        // His regex: /^\.[a-zA-Z0-9]+\??/
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        std.debug.assert(self.source[self.pos] == '.');
        self.pos += 1;
        self.col += 1;
        const name_start = self.pos;
        while (self.pos < self.source.len and std.ascii.isAlphanumeric(self.source[self.pos])) {
            self.pos += 1;
            self.col += 1;
        }
        if (self.pos == name_start) {
            // Bare `.` is not a valid argument. Skip — PR-2.1 emits error.
            return;
        }
        var n = node.Node.init(.argument, self.source[name_start..self.pos], start);
        n.line = start_line;
        n.col = start_col;
        if (self.pos < self.source.len and self.source[self.pos] == '?') {
            n.optional = true;
            self.pos += 1;
            self.col += 1;
        }
        try tokens.append(self.allocator, n);
    }

    fn lexAnnotation(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        // His regex: /^@[a-zA-Z0-9_]+:/
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        std.debug.assert(self.source[self.pos] == '@');
        self.pos += 1;
        self.col += 1;
        const key_start = self.pos;
        while (self.pos < self.source.len and
            (std.ascii.isAlphanumeric(self.source[self.pos]) or self.source[self.pos] == '_'))
        {
            self.pos += 1;
            self.col += 1;
        }
        if (self.pos < self.source.len and self.source[self.pos] == ':') {
            const key = self.source[key_start..self.pos];
            // Validate against his whitelist. Per `tokeniser.ts:397-403`,
            // unknown key advances pos by 1 BEFORE the throw — that's
            // observable to error.pos.
            if (!err.isKnownAnnotationKey(key)) {
                self.pos += 1;
                self.col += 1;
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "{s} '{s}'",
                    .{ err.ErrorMsg.unrecognised_annotation_prefix, key },
                );
                self.tokenise_error = .{
                    .msg = msg,
                    // His `match.length - 2` = key length (subtracting `@`
                    // and `:`).
                    .pos = start + 1,
                    .len = @intCast(key.len),
                    .line = start_line,
                    .col = start_col,
                    .file_id = self.file_id,
                    .file_name = self.file_name,
                };
                return;
            }
            var n = node.Node.init(.annotation, key, start);
            n.line = start_line;
            n.col = start_col;
            try tokens.append(self.allocator, n);
            self.pos += 1;
            self.col += 1;
            // Annotation value (the token AFTER the `:`) is lexed by the
            // next outer-loop iteration. Matches his behaviour per
            // `tokeniseTypes.test.ts`:
            //   `@label:'spaced string'` → annotation('label'), string('spaced string')
        } else {
            // Bare `@key` with no colon. PR-2.1 may surface this as a
            // tokenise error; his current code silently falls through.
        }
    }

    fn lexString(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        // His regex: /^(["'])(?:\\.|[^\\])*?\1(?=\s|$)/
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        const quote = self.source[self.pos];
        self.pos += 1;
        self.col += 1;
        const body_start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != quote) {
            if (self.source[self.pos] == '\\' and self.pos + 1 < self.source.len) {
                self.pos += 2;
                self.col += 2;
            } else {
                if (self.source[self.pos] == '\n') {
                    self.line += 1;
                    self.col = 1;
                } else {
                    self.col += 1;
                }
                self.pos += 1;
            }
        }
        if (self.pos >= self.source.len) {
            // Unterminated. PR-2.1: emit TokeniserError using
            // err.ErrorMsg.unterminated_string.
            return;
        }
        const body = self.source[body_start..self.pos];
        self.pos += 1; // consume closing quote
        self.col += 1;
        var n = node.Node.init(.string, body, start);
        n.line = start_line;
        n.col = start_col;
        // His `tryString` sets `asm = Buffer.from(strVal, 'utf8').toString('hex')`.
        n.asm_str = try utf8ToHex(self.allocator, body);
        try tokens.append(self.allocator, n);
    }

    fn lexIdentifierLike(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        // Try opcode (longest-match against shortOps), then keywords (end,
        // repeat, import, pushCodeData[V]), then registered function name
        // → call, then bare-hex run, else word.
        const start_line = self.line;
        const start_col = self.col;
        const remaining = self.source[self.pos..];

        // Opcode prefix match. Require word-boundary after match.
        if (short_ops.lookupPrefix(remaining)) |m| {
            const after = self.pos + m.len;
            if (after >= self.source.len or !isWordChar(self.source[after])) {
                // Build OP_<UPPER> asm string from the SOURCE casing (his
                // `node.asm_str = OP_${opcodeMatch.toUpperCase()}` — so `nop`
                // and `NOP` and `Nop` all give "OP_NOP" but the value
                // preserves the source spelling).
                const matched_src = self.source[self.pos .. self.pos + m.len];
                const asm_str = try buildOpAsm(self.allocator, matched_src);
                var n = node.Node.init(.opcode, matched_src, self.pos);
                n.asm_str = asm_str;
                n.num = m.op.int;
                n.line = start_line;
                n.col = start_col;
                try tokens.append(self.allocator, n);
                self.pos += @intCast(m.len);
                self.col += @intCast(m.len);
                return;
            }
        }

        // Keyword check (case-insensitive end / repeat / import; case-
        // SENSITIVE pushCodeData / pushCodeDataV — his keyword map keys
        // are case-sensitive in JS).
        const word_end = scanWord(self.source, self.pos);
        const word = self.source[self.pos..word_end];
        if (std.ascii.eqlIgnoreCase(word, "end")) {
            var n = node.Node.init(.end, null, self.pos);
            n.line = start_line;
            n.col = start_col;
            try tokens.append(self.allocator, n);
        } else if (std.ascii.eqlIgnoreCase(word, "repeat")) {
            var n = node.Node.init(.repeat, null, self.pos);
            n.line = start_line;
            n.col = start_col;
            try tokens.append(self.allocator, n);
        } else if (std.ascii.eqlIgnoreCase(word, "import")) {
            var n = node.Node.init(.import, null, self.pos);
            n.line = start_line;
            n.col = start_col;
            try tokens.append(self.allocator, n);
        } else if (std.mem.eql(u8, word, "pushCodeData") or std.mem.eql(u8, word, "pushCodeDataV")) {
            // His `keywordToNodeType.pushCodeData(V) === nodeTypes.pushCodeData`.
            // Value preserves the original mnemonic so compiler.ts can branch
            // on the V (verbose) variant.
            var n = node.Node.init(.pushCodeData, word, self.pos);
            n.line = start_line;
            n.col = start_col;
            try tokens.append(self.allocator, n);
        } else if (self.function_names.contains(word)) {
            // Registered function name → call. Same mechanism as his
            // `_functionNamesSet.has(word)` check.
            var n = node.Node.init(.call, word, self.pos);
            n.line = start_line;
            n.col = start_col;
            try tokens.append(self.allocator, n);
        } else if (isBareHexCandidate(word)) {
            // His tokeniser tries bare hex even on alpha-leading runs — the
            // regex `^([a-fA-F0-9]{2})+(?=\s|$)` matches things like
            // `deadbeef`. The hex value is the lowercased word per his
            // `tryHex` normalisation.
            const cleaned = try toLowerHex(self.allocator, word);
            var n = node.Node.init(.hex, cleaned, self.pos);
            n.line = start_line;
            n.col = start_col;
            n.asm_str = cleaned;
            try tokens.append(self.allocator, n);
        } else {
            var n = node.Node.init(.word, word, self.pos);
            n.line = start_line;
            n.col = start_col;
            try tokens.append(self.allocator, n);
        }

        self.col += @intCast(word_end - self.pos);
        self.pos = word_end;
    }

    /// `#name` — registers `name` in function_names + emits function token.
    /// Per `tokeniseTypes.test.ts`, `#test` produces `{ type: function, value: 'test' }`
    /// and a subsequent bare `test` becomes `{ type: call, value: 'test' }`.
    fn lexFunctionDef(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        std.debug.assert(self.source[self.pos] == '#');
        self.pos += 1;
        self.col += 1;
        const name_start = self.pos;
        while (self.pos < self.source.len and isWordChar(self.source[self.pos])) {
            self.pos += 1;
            self.col += 1;
        }
        if (self.pos == name_start) {
            // Bare `#` with no identifier — skip. PR-2.1 emits error.
            return;
        }
        const name = self.source[name_start..self.pos];
        try self.function_names.put(self.allocator, name, {});
        var n = node.Node.init(.function, name, start);
        n.line = start_line;
        n.col = start_col;
        try tokens.append(self.allocator, n);
    }

    /// Backtick template literal. His regex emits a `template` marker at
    /// the opening backtick, then the body as a `word`, then another
    /// `template` marker at the closing backtick. `${...}` interpolation
    /// is PR-2.1 (the test fixture doesn't exercise it yet).
    fn lexTemplate(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        std.debug.assert(self.source[self.pos] == '`');
        var open = node.Node.init(.template, null, start);
        open.line = start_line;
        open.col = start_col;
        try tokens.append(self.allocator, open);
        self.pos += 1;
        self.col += 1;

        const body_start = self.pos;
        const body_line = self.line;
        const body_col = self.col;
        while (self.pos < self.source.len and self.source[self.pos] != '`') {
            // PR-2.1: handle `${` interpolation tokens.
            self.pos += 1;
            self.col += 1;
        }
        if (self.pos > body_start) {
            var w = node.Node.init(.word, self.source[body_start..self.pos], body_start);
            w.line = body_line;
            w.col = body_col;
            try tokens.append(self.allocator, w);
        }
        if (self.pos < self.source.len and self.source[self.pos] == '`') {
            var close = node.Node.init(.template, null, self.pos);
            close.line = self.line;
            close.col = self.col;
            try tokens.append(self.allocator, close);
            self.pos += 1;
            self.col += 1;
        }
    }

    fn lexNumberOrHex(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        // His bigint regex: /^([+-]?0*)(\d+)(n)/
        // His hex regex:    /^(0x)?([a-fA-F0-9]{2})+(?=\s|$)/
        // Order: bigint (more specific suffix `n`), then bare hex if even-
        // length AND all hex-chars, else word (his fallthrough behaviour).
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        var p = self.pos;
        const has_sign = p < self.source.len and (self.source[p] == '+' or self.source[p] == '-');
        if (has_sign) p += 1;
        const digits_start = p;
        while (p < self.source.len and std.ascii.isDigit(self.source[p])) p += 1;
        if (p > digits_start and p < self.source.len and self.source[p] == 'n') {
            // bigint — emit with asm_str set to CScriptNum encoding.
            p += 1;
            const value = self.source[start..p];
            var n = node.Node.init(.bigint, value, start);
            n.line = start_line;
            n.col = start_col;
            const enc = try bigintToScriptNum(self.allocator, value);
            n.asm_str = enc.asm_str;
            n.num = enc.num;
            try tokens.append(self.allocator, n);
            self.col += @intCast(p - start);
            self.pos = p;
            return;
        }

        // Signed integer without `n` suffix → his lexer emits as a word
        // (`@test:-123` → annotation(test), word(-123)).
        if (has_sign and p > digits_start) {
            const value = self.source[start..p];
            var n = node.Node.init(.word, value, start);
            n.line = start_line;
            n.col = start_col;
            try tokens.append(self.allocator, n);
            self.col += @intCast(p - start);
            self.pos = p;
            return;
        }

        // No sign + no `n` suffix. Try the `0x`-prefixed hex form first
        // (his regex `^(0x)?(...)` allows it). lexBareHex handles the
        // prefix.
        if (self.pos + 1 < self.source.len and self.source[self.pos] == '0' and
            (self.source[self.pos + 1] == 'x' or self.source[self.pos + 1] == 'X'))
        {
            try self.lexBareHex(tokens);
            return;
        }

        // Otherwise: determine bare-hex vs word by scanning the full
        // whitespace-bounded run, NOT a partial prefix. His tryHex regex
        // `^([a-fA-F0-9]{2})+(?=\s|$)` requires whitespace-or-EOF
        // immediately after; `123` doesn't qualify (odd-length when the
        // whole word is taken).
        const word_end = scanWord(self.source, self.pos);
        const word = self.source[self.pos..word_end];
        if (isBareHexCandidate(word)) {
            const cleaned = try toLowerHex(self.allocator, word);
            var n = node.Node.init(.hex, cleaned, start);
            n.line = start_line;
            n.col = start_col;
            n.asm_str = cleaned;
            try tokens.append(self.allocator, n);
            self.col += @intCast(word_end - self.pos);
            self.pos = word_end;
            return;
        }
        // Otherwise fall back to word — mirrors his tryWord fallthrough.
        var n = node.Node.init(.word, word, start);
        n.line = start_line;
        n.col = start_col;
        try tokens.append(self.allocator, n);
        self.col += @intCast(word_end - self.pos);
        self.pos = word_end;
    }

    fn lexBareHex(self: *Lexer, tokens: *std.ArrayList(node.Node)) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;
        var p = self.pos;
        // Optional `0x` prefix (his regex `^(0x)?([a-fA-F0-9]{2})+`).
        if (p + 1 < self.source.len and self.source[p] == '0' and
            (self.source[p + 1] == 'x' or self.source[p + 1] == 'X'))
        {
            p += 2;
        }
        const hex_start = p;
        while (p < self.source.len and std.ascii.isHex(self.source[p])) p += 1;
        const len = p - hex_start;
        if (len == 0 or len % 2 != 0) {
            // Not a valid hex literal — fall through. PR-2.1 emits error.
            self.pos += 1;
            self.col += 1;
            return;
        }
        // His `tryHex` strips the `0x` prefix and lowercases the value.
        const cleaned = try toLowerHex(self.allocator, self.source[hex_start..p]);
        var n = node.Node.init(.hex, cleaned, start);
        n.line = start_line;
        n.col = start_col;
        n.asm_str = cleaned; // his `node.asm_str = cleanedVal`
        try tokens.append(self.allocator, n);
        self.col += @intCast(p - start);
        self.pos = p;
    }

    // -------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------

    fn peekAt(self: *const Lexer, offset: usize) u8 {
        const idx = self.pos + offset;
        if (idx >= self.source.len) return 0;
        return self.source[idx];
    }
};

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

fn isWordChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn scanWord(source: []const u8, start: u32) u32 {
    var p = start;
    while (p < source.len and isWordChar(source[p])) p += 1;
    return p;
}

/// True if `word` is a valid bare-hex run per his regex
/// `^([a-fA-F0-9]{2})+(?=\s|$)`: non-empty, even length, every byte is a
/// hex digit. The `(?=\s|$)` boundary check is the scanWord stop above.
fn isBareHexCandidate(word: []const u8) bool {
    if (word.len == 0 or word.len % 2 != 0) return false;
    for (word) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}

fn buildOpAsm(allocator: std.mem.Allocator, mnemonic: []const u8) ![]const u8 {
    // "nop" → "OP_NOP", "checkSig" → "OP_CHECKSIG"
    var buf = try allocator.alloc(u8, mnemonic.len + 3);
    buf[0] = 'O';
    buf[1] = 'P';
    buf[2] = '_';
    for (mnemonic, 0..) |c, i| {
        buf[i + 3] = std.ascii.toUpper(c);
    }
    return buf;
}

fn toLowerHex(allocator: std.mem.Allocator, hex: []const u8) ![]const u8 {
    const buf = try allocator.alloc(u8, hex.len);
    for (hex, 0..) |c, i| buf[i] = std.ascii.toLower(c);
    return buf;
}

/// UTF-8 bytes → hex string. Mirrors his
/// `Buffer.from(strVal, 'utf8').toString('hex')` for `tryString.asm`.
fn utf8ToHex(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var buf = try allocator.alloc(u8, bytes.len * 2);
    const digits = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        buf[i * 2] = digits[b >> 4];
        buf[i * 2 + 1] = digits[b & 0x0f];
    }
    return buf;
}

/// Encoded bigint result — matches his `convertBigIntToASM` return shape:
/// `{ asm: string, num: number }`. Special cases: 0 → "OP_0",
/// 1..16 → "OP_1".."OP_16", -1 → "OP_1NEGATE", else CScriptNum hex.
const BigintEncoded = struct {
    asm_str: []const u8,
    num: i64,
};

/// His `convertBigIntToASM` — pulls the digit body out of a bigint
/// literal like "-123n" or "12345n", parses the int, returns the BSV
/// CScriptNum-encoded asm form. PR-3 will exercise the full corpus
/// against his goldens; this covers the cases the parser tests reach.
fn bigintToScriptNum(allocator: std.mem.Allocator, literal: []const u8) !BigintEncoded {
    // Strip trailing 'n'.
    std.debug.assert(literal.len > 0 and literal[literal.len - 1] == 'n');
    const digits = literal[0 .. literal.len - 1];
    const n = try std.fmt.parseInt(i64, digits, 10);

    // Special cases.
    if (n == 0) return .{ .asm_str = "OP_0", .num = 0 };
    if (n == -1) return .{ .asm_str = "OP_1NEGATE", .num = -1 };
    if (n >= 1 and n <= 16) {
        // OP_1 = 0x51 = 81, OP_16 = 0x60 = 96. asm form "OP_<n>".
        const op_asm = try std.fmt.allocPrint(allocator, "OP_{d}", .{n});
        return .{ .asm_str = op_asm, .num = n };
    }

    // CScriptNum: little-endian, with sign-bit in the high byte of the
    // last byte. If the high bit of the absolute-value MSB is set, append
    // an extra byte for the sign.
    const negative = n < 0;
    var abs_val: u64 = if (negative) @intCast(-n) else @intCast(n);

    var bytes: [10]u8 = undefined;
    var len: usize = 0;
    while (abs_val > 0) : (abs_val >>= 8) {
        bytes[len] = @intCast(abs_val & 0xff);
        len += 1;
    }
    // Apply sign bit. If high bit of the MSB is already set, we need an
    // extra byte (Bitcoin Script's "minimal encoding" rule).
    if ((bytes[len - 1] & 0x80) != 0) {
        bytes[len] = if (negative) 0x80 else 0x00;
        len += 1;
    } else if (negative) {
        bytes[len - 1] |= 0x80;
    }

    // Hex-encode.
    const hex_digits = "0123456789abcdef";
    var hex = try allocator.alloc(u8, len * 2);
    for (bytes[0..len], 0..) |b, i| {
        hex[i * 2] = hex_digits[b >> 4];
        hex[i * 2 + 1] = hex_digits[b & 0x0f];
    }
    return .{ .asm_str = hex, .num = n };
}

test "bigintToScriptNum: special cases" {
    const a = try bigintToScriptNum(std.testing.allocator, "0n");
    try std.testing.expectEqualStrings("OP_0", a.asm_str);
    try std.testing.expectEqual(@as(i64, 0), a.num);

    const b = try bigintToScriptNum(std.testing.allocator, "3n");
    defer std.testing.allocator.free(b.asm_str);
    try std.testing.expectEqualStrings("OP_3", b.asm_str);

    const c = try bigintToScriptNum(std.testing.allocator, "-1n");
    try std.testing.expectEqualStrings("OP_1NEGATE", c.asm_str);
}

test "bigintToScriptNum: -123 encodes as fb" {
    // His test fixture: `.sumting @test:-123n` → asm "fb". -123 in
    // CScriptNum: abs=123 (0x7b), high bit clear, so apply sign-bit
    // directly: 0x7b | 0x80 = 0xfb.
    const enc = try bigintToScriptNum(std.testing.allocator, "-123n");
    defer std.testing.allocator.free(enc.asm_str);
    try std.testing.expectEqualStrings("fb", enc.asm_str);
    try std.testing.expectEqual(@as(i64, -123), enc.num);
}

test "bigintToScriptNum: 128 needs sign-padding byte" {
    // 128 = 0x80, high bit set → append 0x00 → "8000"
    const enc = try bigintToScriptNum(std.testing.allocator, "128n");
    defer std.testing.allocator.free(enc.asm_str);
    try std.testing.expectEqualStrings("8000", enc.asm_str);
}

test "lexer: empty input yields no tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), "");
    const res = try lexer.tokenise();
    try std.testing.expectEqual(@as(usize, 0), res.tokens.items.len);
}

test "lexer: single nop opcode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), "nop");
    const res = try lexer.tokenise();
    try std.testing.expectEqual(@as(usize, 1), res.tokens.items.len);
    const t = res.tokens.items[0];
    try std.testing.expectEqual(node.NodeType.opcode, t.type);
    try std.testing.expectEqualStrings("OP_NOP", t.asm_str.?);
    try std.testing.expectEqual(@as(i64, 97), t.num.?);
}

test "lexer: argument with optional flag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), ".optArgName?");
    const res = try lexer.tokenise();
    try std.testing.expectEqual(@as(usize, 1), res.tokens.items.len);
    const t = res.tokens.items[0];
    try std.testing.expectEqual(node.NodeType.argument, t.type);
    try std.testing.expectEqualStrings("optArgName", t.value.?);
    try std.testing.expect(t.optional);
}

test "lexer: bigint negative" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), "-12345n");
    const res = try lexer.tokenise();
    try std.testing.expectEqual(@as(usize, 1), res.tokens.items.len);
    try std.testing.expectEqual(node.NodeType.bigint, res.tokens.items[0].type);
    try std.testing.expectEqualStrings("-12345n", res.tokens.items[0].value.?);
}

test "lexer: bare hex" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), "deadbeef");
    const res = try lexer.tokenise();
    try std.testing.expectEqual(@as(usize, 1), res.tokens.items.len);
    try std.testing.expectEqual(node.NodeType.hex, res.tokens.items[0].type);
    try std.testing.expectEqualStrings("deadbeef", res.tokens.items[0].value.?);
}

test "lexer: single-quoted string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), "'string'");
    const res = try lexer.tokenise();
    try std.testing.expectEqual(@as(usize, 1), res.tokens.items.len);
    try std.testing.expectEqual(node.NodeType.string, res.tokens.items[0].type);
    try std.testing.expectEqualStrings("string", res.tokens.items[0].value.?);
}

test "lexer: annotation then string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), "@label:'spaced string'");
    const res = try lexer.tokenise();
    try std.testing.expectEqual(@as(usize, 2), res.tokens.items.len);
    try std.testing.expectEqual(node.NodeType.annotation, res.tokens.items[0].type);
    try std.testing.expectEqualStrings("label", res.tokens.items[0].value.?);
    try std.testing.expectEqual(node.NodeType.string, res.tokens.items[1].type);
    try std.testing.expectEqualStrings("spaced string", res.tokens.items[1].value.?);
}

test "lexer: end keyword alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), "end");
    const res = try lexer.tokenise();
    try std.testing.expectEqual(@as(usize, 1), res.tokens.items.len);
    try std.testing.expectEqual(node.NodeType.end, res.tokens.items[0].type);
}

test "lexer: repeat keyword alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), "repeat");
    const res = try lexer.tokenise();
    try std.testing.expectEqual(@as(usize, 1), res.tokens.items.len);
    try std.testing.expectEqual(node.NodeType.repeat, res.tokens.items[0].type);
}

test "lexer: nop with line comment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), "nop//comment");
    const res = try lexer.tokenise();
    try std.testing.expectEqual(@as(usize, 3), res.tokens.items.len);
    try std.testing.expectEqual(node.NodeType.opcode, res.tokens.items[0].type);
    try std.testing.expectEqual(node.NodeType.comment, res.tokens.items[1].type);
    try std.testing.expectEqual(node.NodeType.word, res.tokens.items[2].type);
    try std.testing.expectEqualStrings("comment", res.tokens.items[2].value.?);
}

```
