---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/src/lower.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.997329+00:00
---

# core/cell-engine/tools/sx/src/lower.zig

```zig
//! Lowerer — port of bitcoinsx's `src/sx/src/compiler.ts::processOps`.
//!
//! Walks the AST produced by `parse.zig` and emits two byte streams:
//! unlockingHex (everything before the `|` section separator) and
//! lockingHex (everything after). Hex is lowercase, no spaces — matches
//! his `processOps().hex` shape.
//!
//! ## PR-3 skeleton scope
//!
//! Emit-by-type:
//!   - opcode  → byte from `short_ops.TABLE` (camelCase mnemonic lookup)
//!   - bigint  → CScriptNum push (uses `asm_str` set by lexer)
//!   - hex     → pushdata of the lowercased hex bytes
//!   - string  → pushdata of UTF-8 bytes (uses `asm_str` set by lexer)
//!   - word "|"→ section switch (unlock → lock)
//!   - comment → skipped
//!
//! Pushdata length prefix per BSV / Bitcoin Script convention:
//!   - 1..75 bytes  : single length byte (no opcode prefix)
//!   - 76..255      : OP_PUSHDATA1 (0x4c) + 1-byte length
//!   - 256..65535   : OP_PUSHDATA2 (0x4d) + 2-byte LE length
//!   - >65535       : OP_PUSHDATA4 (0x4e) + 4-byte LE length
//!
//! ## PR-3.1+ follow-ons
//!
//! - argument slot resolution (his .lockArgs / .unlockArgs + recombinants)
//! - repeat unrolling (his parseRepeat already attaches a count; lower
//!   needs to emit body N times)
//! - call expansion (look up function body in parser.functions and inline)
//! - pushCodeData node → emit children as a single pushdata bundle
//! - ASM string output (his `lockingAsm` / `unlockingAsm`)
//! - autoSlice
//! - argument typing + default-value resolution
//!
//! ## Cleavage tie-in
//!
//! The two output halves map directly onto the cleavage manifest's
//! `unlockScript` / `lockScript` sections (per
//! docs/design/LOCKSCRIPT-CLEAVAGE.md §2). When PR-3.x is feature-
//! complete, the cleavage exporter consumes these byte slices verbatim.

const std = @import("std");
const node = @import("node.zig");
const short_ops = @import("short_ops.zig");

/// Output of one lower pass.
pub const LowerResult = struct {
    /// Bytes emitted before the `|` separator (or all bytes if no
    /// separator). Hex-encode for display via `std.fmt.bytesToHex`.
    unlocking_bytes: []const u8,
    /// Bytes emitted after the `|` separator. Empty when no separator.
    locking_bytes: []const u8,
    /// Whether a `|` section split was seen.
    sectioned: bool,
    /// Names of arguments encountered that had no resolution — either
    /// no @test annotation at parse time AND no deploy_args entry.
    /// Mirrors his `lockArgs` / `unlockArgs` lists (his model splits by
    /// section; we report all together — a section-tagged version is a
    /// trivial follow-up if needed).
    unresolved_args: []const []const u8,
};

pub const LowerErr = error{
    UnknownOpcode,
    InvalidPushdata,
    UnsupportedNodeType,
    OutOfMemory,
    InvalidCharacter,
    Overflow,
    NoSpaceLeft,
};

/// Deploy-time argument resolution map — `{ arg_name → hex_value_string }`.
/// Mirrors his formulator's `args: { argName: <value> }` block (per
/// Brendan: "in the formulator you say in the output args that .variable
/// is x"). For .pubKeyHash style slots, the value is the resolved hex
/// bytes (e.g. a 20-byte hash160). For .variable repeat-count slots,
/// the value parses as a decimal integer (no `n` suffix needed).
pub const DeployArgs = std.StringHashMapUnmanaged([]const u8);

/// Lowerer state. Pass the parsed AST root to `lower()`.
pub const Lowerer = struct {
    allocator: std.mem.Allocator,
    unlock: std.ArrayList(u8) = .{},
    lock: std.ArrayList(u8) = .{},
    in_lock_section: bool = false,
    sectioned: bool = false,
    /// Caller-supplied resolutions for argument-slot tokens (lock-side
    /// .pubKeyHash etc., or argument-driven repeat counts). Null = no
    /// resolution available; unresolved args get tracked rather than
    /// emitted.
    deploy_args: ?*const DeployArgs = null,
    /// Names of arguments we couldn't resolve at lower time. Caller can
    /// check this to know what slot values the consumer needs to supply.
    unresolved_args: std.ArrayList([]const u8) = .{},

    pub fn init(allocator: std.mem.Allocator) Lowerer {
        return .{ .allocator = allocator };
    }

    pub fn initWithArgs(allocator: std.mem.Allocator, deploy_args: *const DeployArgs) Lowerer {
        return .{ .allocator = allocator, .deploy_args = deploy_args };
    }

    /// Walk the AST root's children in order, emitting bytes.
    pub fn lower(self: *Lowerer, root: node.Node) LowerErr!LowerResult {
        if (root.type != .root) return error.UnsupportedNodeType;
        for (root.children.items) |child| {
            try self.emitNode(child);
        }
        return .{
            .unlocking_bytes = self.unlock.items,
            .locking_bytes = self.lock.items,
            .sectioned = self.sectioned,
            .unresolved_args = self.unresolved_args.items,
        };
    }

    /// Emit one node. Recurses into composite nodes (function bodies,
    /// pushCodeData, repeats) where their content contributes bytes.
    fn emitNode(self: *Lowerer, n: node.Node) LowerErr!void {
        switch (n.type) {
            .opcode => try self.emitOpcode(n),
            .bigint => try self.emitNumeric(n),
            .hex => try self.emitHexPush(n),
            .string => try self.emitStringPush(n),
            .comment, .whitespace => {}, // skipped
            .word => {
                // `|` section separator → flip output target.
                if (n.value) |v| {
                    if (std.mem.eql(u8, v, "|")) {
                        self.in_lock_section = true;
                        self.sectioned = true;
                        return;
                    }
                }
                // Bare words at the top level are unusual but his
                // compiler.ts treats them as no-op (the parser usually
                // rewrites them to call/autoSlice/break). Silent skip.
            },
            .function => {
                // Function DEFINITIONS emit no bytes — the body lives in
                // the functions map for call-site inlining. His behaviour
                // (compiler.ts: function nodes are recorded, not emitted).
            },
            .pushCodeData => {
                // Lower the children into a sub-Lowerer, then push the
                // resulting bytes as a single pushdata blob. The parser
                // has already inlined the macro body as children, so
                // sub-lowering them produces the macro's compiled hex
                // (which is exactly what pushCodeData is meant to push).
                var sub_lowerer = Lowerer.init(self.allocator);
                for (n.children.items) |c| try sub_lowerer.emitNode(c);
                // pushCodeData is always single-stream (children inherit
                // its section). Use the sub-lowerer's unlocking buffer.
                try self.pushBytes(sub_lowerer.unlock.items);
            },
            .repeat => {
                // Unroll: emit body N times. Count resolution:
                //   1. arg-driven repeat (`repeat .variable ... end`) →
                //      n.label holds the variable name. Look up in
                //      deploy_args; parse as decimal int.
                //   2. bigint-driven repeat (`repeat 3n ... end`) →
                //      n.value is "<N>" set by parseRepeat.
                //
                // Per Brendan: "Then in the formulator you say in the
                // output args that .variable is x. Then you give that
                // number to the contract so that when it builds its next
                // self ... it knows how many loops in needs to insert."
                var count: u32 = 0;
                if (n.label) |var_name| {
                    if (self.deploy_args) |da| {
                        if (da.get(var_name)) |v| {
                            count = std.fmt.parseInt(u32, v, 10) catch return error.InvalidPushdata;
                        } else {
                            // Unresolved arg-driven repeat — track + skip.
                            try self.unresolved_args.append(self.allocator, var_name);
                            return;
                        }
                    } else {
                        try self.unresolved_args.append(self.allocator, var_name);
                        return;
                    }
                } else {
                    const count_str = n.value orelse return;
                    count = std.fmt.parseInt(u32, count_str, 10) catch return error.InvalidPushdata;
                }
                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    for (n.children.items) |c| try self.emitNode(c);
                }
            },
            .call => {
                // PR-3.1: full body lookup via parser.functions for
                // unresolved calls. For calls that already have children
                // populated (e.g. `break` rewrite from parser, which
                // produces call([opcode.false, opcode.verify])), emit
                // the children inline.
                for (n.children.items) |c| try self.emitNode(c);
            },
            .argument => {
                // Resolution priority (matches his behaviour):
                //   1. deploy_args[name] supplied at lower init → push value
                //   2. asm_str set by parser via @test annotation → emit as numeric
                //   3. otherwise → track as unresolved + skip emission
                //
                // (1) is the formulator-supplied path Brendan described:
                // "in the formulator you say in the output args that
                // .variable is x" — supplied by the deploy spec, baked
                // into the locking script at compile time.
                if (n.value) |arg_name| {
                    if (self.deploy_args) |da| {
                        if (da.get(arg_name)) |value_hex| {
                            try self.pushHex(value_hex);
                            return;
                        }
                    }
                }
                if (n.asm_str) |asm_str| {
                    if (!std.mem.eql(u8, asm_str, "OP_0")) {
                        // Parser resolved via @test annotation.
                        try self.emitNumeric(n);
                        return;
                    }
                }
                // Unresolved — track for caller, emit nothing. His
                // compiler tracks these in lockArgs / unlockArgs and the
                // consumer fills at witness/deploy time.
                if (n.value) |arg_name| {
                    try self.unresolved_args.append(self.allocator, arg_name);
                }
            },
            .import => {
                // Import statements are parse-time only — no bytes.
            },
            else => {
                // Unhandled node types fail loud rather than silently
                // miscompiling. Surfaces gaps in PR-3 coverage early.
                return error.UnsupportedNodeType;
            },
        }
    }

    fn out(self: *Lowerer) *std.ArrayList(u8) {
        return if (self.in_lock_section) &self.lock else &self.unlock;
    }

    fn emitOpcode(self: *Lowerer, n: node.Node) LowerErr!void {
        // Lexer already populated `num` for shortOps tokens.
        if (n.num) |b| {
            try self.out().append(self.allocator, @intCast(b));
            return;
        }
        // Fallback: lookup by mnemonic (case-insensitive).
        if (n.value) |mnem| {
            if (short_ops.lookupPrefix(mnem)) |m| {
                if (m.len == mnem.len) {
                    try self.out().append(self.allocator, m.op.int);
                    return;
                }
            }
        }
        return error.UnknownOpcode;
    }

    /// Emit a bigint as a numeric opcode (OP_0/OP_1..16/OP_1NEGATE) when
    /// the lexer set asm_str to that form, or as a CScriptNum pushdata
    /// otherwise.
    fn emitNumeric(self: *Lowerer, n: node.Node) LowerErr!void {
        const asm_str = n.asm_str orelse return error.InvalidPushdata;
        if (std.mem.eql(u8, asm_str, "OP_0")) {
            try self.out().append(self.allocator, 0x00);
            return;
        }
        if (std.mem.eql(u8, asm_str, "OP_1NEGATE")) {
            try self.out().append(self.allocator, 0x4f);
            return;
        }
        // "OP_1".."OP_16" → 0x51..0x60
        if (std.mem.startsWith(u8, asm_str, "OP_")) {
            const digits = asm_str[3..];
            const n_val = std.fmt.parseInt(u8, digits, 10) catch return error.InvalidPushdata;
            if (n_val >= 1 and n_val <= 16) {
                try self.out().append(self.allocator, 0x50 + n_val);
                return;
            }
            return error.InvalidPushdata;
        }
        // asm_str is raw hex (e.g. "fb" for -123n) → push the decoded bytes.
        try self.pushHex(asm_str);
    }

    fn emitHexPush(self: *Lowerer, n: node.Node) LowerErr!void {
        // Lexer guarantees `value` is the cleaned (no `0x`, lowercased,
        // even-length) hex string.
        const hex = n.value orelse return error.InvalidPushdata;
        try self.pushHex(hex);
    }

    fn emitStringPush(self: *Lowerer, n: node.Node) LowerErr!void {
        // String body bytes (value field is the unescaped contents) get
        // pushed verbatim. His asm_str field is utf-8 hex of body — same
        // content as value but pre-encoded.
        const body = n.value orelse return error.InvalidPushdata;
        try self.pushBytes(body);
    }

    /// Push hex-encoded bytes (caller-provided lowercase hex string)
    /// with the correct pushdata-length prefix.
    fn pushHex(self: *Lowerer, hex: []const u8) LowerErr!void {
        if (hex.len % 2 != 0) return error.InvalidPushdata;
        const byte_len = hex.len / 2;
        const buf = try self.allocator.alloc(u8, byte_len);
        defer self.allocator.free(buf);
        var i: usize = 0;
        while (i < byte_len) : (i += 1) {
            buf[i] = try std.fmt.parseInt(u8, hex[i * 2 .. i * 2 + 2], 16);
        }
        try self.pushBytes(buf);
    }

    /// Append a pushdata with the correct length prefix (BSV/Bitcoin
    /// Script convention).
    fn pushBytes(self: *Lowerer, bytes: []const u8) LowerErr!void {
        const buf_ref = self.out();
        const len = bytes.len;
        if (len == 0) {
            // Empty push = OP_0 (his behaviour for empty strings).
            try buf_ref.append(self.allocator, 0x00);
            return;
        }
        if (len <= 75) {
            try buf_ref.append(self.allocator, @intCast(len));
        } else if (len <= 0xff) {
            try buf_ref.append(self.allocator, 0x4c); // OP_PUSHDATA1
            try buf_ref.append(self.allocator, @intCast(len));
        } else if (len <= 0xffff) {
            try buf_ref.append(self.allocator, 0x4d); // OP_PUSHDATA2
            try buf_ref.append(self.allocator, @intCast(len & 0xff));
            try buf_ref.append(self.allocator, @intCast((len >> 8) & 0xff));
        } else if (len <= 0xffffffff) {
            try buf_ref.append(self.allocator, 0x4e); // OP_PUSHDATA4
            try buf_ref.append(self.allocator, @intCast(len & 0xff));
            try buf_ref.append(self.allocator, @intCast((len >> 8) & 0xff));
            try buf_ref.append(self.allocator, @intCast((len >> 16) & 0xff));
            try buf_ref.append(self.allocator, @intCast((len >> 24) & 0xff));
        } else {
            return error.InvalidPushdata;
        }
        try buf_ref.appendSlice(self.allocator, bytes);
    }
};

/// Convenience: bytes → lowercase hex string (no spaces).
pub fn bytesToHex(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var buf = try allocator.alloc(u8, bytes.len * 2);
    const digits = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        buf[i * 2] = digits[b >> 4];
        buf[i * 2 + 1] = digits[b & 0x0f];
    }
    return buf;
}

test "lowerer: single nop opcode emits 0x61" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var root = node.Node.init(.root, null, 0);
    var nop = node.Node.init(.opcode, "nop", 0);
    nop.num = 0x61;
    try root.children.append(arena.allocator(), nop);

    var lowerer = Lowerer.init(arena.allocator());
    const res = try lowerer.lower(root);
    try std.testing.expectEqual(@as(usize, 1), res.unlocking_bytes.len);
    try std.testing.expectEqual(@as(u8, 0x61), res.unlocking_bytes[0]);
    try std.testing.expectEqual(@as(usize, 0), res.locking_bytes.len);
}

test "lowerer: bare hex emits pushdata with length prefix" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var root = node.Node.init(.root, null, 0);
    const h = node.Node.init(.hex, "deadbeef", 0);
    try root.children.append(arena.allocator(), h);

    var lowerer = Lowerer.init(arena.allocator());
    const res = try lowerer.lower(root);
    // 4 bytes "deadbeef" → length prefix 0x04, then 4 bytes
    try std.testing.expectEqual(@as(usize, 5), res.unlocking_bytes.len);
    try std.testing.expectEqual(@as(u8, 0x04), res.unlocking_bytes[0]);
    try std.testing.expectEqual(@as(u8, 0xde), res.unlocking_bytes[1]);
    try std.testing.expectEqual(@as(u8, 0xef), res.unlocking_bytes[4]);
}

test "lowerer: section separator flips output target" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var root = node.Node.init(.root, null, 0);
    var n1 = node.Node.init(.opcode, "dup", 0);
    n1.num = 0x76;
    const sep = node.Node.init(.word, "|", 0);
    var n2 = node.Node.init(.opcode, "hash160", 0);
    n2.num = 0xa9;
    try root.children.append(arena.allocator(), n1);
    try root.children.append(arena.allocator(), sep);
    try root.children.append(arena.allocator(), n2);

    var lowerer = Lowerer.init(arena.allocator());
    const res = try lowerer.lower(root);
    try std.testing.expect(res.sectioned);
    try std.testing.expectEqual(@as(usize, 1), res.unlocking_bytes.len);
    try std.testing.expectEqual(@as(u8, 0x76), res.unlocking_bytes[0]);
    try std.testing.expectEqual(@as(usize, 1), res.locking_bytes.len);
    try std.testing.expectEqual(@as(u8, 0xa9), res.locking_bytes[0]);
}

test "lowerer: bigint OP_3 emits 0x53" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var root = node.Node.init(.root, null, 0);
    var b = node.Node.init(.bigint, "3n", 0);
    b.asm_str = "OP_3";
    try root.children.append(arena.allocator(), b);

    var lowerer = Lowerer.init(arena.allocator());
    const res = try lowerer.lower(root);
    try std.testing.expectEqual(@as(usize, 1), res.unlocking_bytes.len);
    try std.testing.expectEqual(@as(u8, 0x53), res.unlocking_bytes[0]);
}

test "lowerer: 76-byte hex push uses OP_PUSHDATA1 prefix" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // 76 bytes = 152 hex chars
    var hex_buf: [152]u8 = undefined;
    @memset(&hex_buf, 'a');
    var root = node.Node.init(.root, null, 0);
    const h = node.Node.init(.hex, &hex_buf, 0);
    try root.children.append(arena.allocator(), h);

    var lowerer = Lowerer.init(arena.allocator());
    const res = try lowerer.lower(root);
    // Expect: 0x4c (PUSHDATA1) + 0x4c (length=76) + 76 bytes
    try std.testing.expectEqual(@as(usize, 78), res.unlocking_bytes.len);
    try std.testing.expectEqual(@as(u8, 0x4c), res.unlocking_bytes[0]);
    try std.testing.expectEqual(@as(u8, 0x4c), res.unlocking_bytes[1]);
    try std.testing.expectEqual(@as(u8, 0xaa), res.unlocking_bytes[2]);
}

```
