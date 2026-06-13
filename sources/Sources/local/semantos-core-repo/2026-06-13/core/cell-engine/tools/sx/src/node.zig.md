---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/src/node.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.996646+00:00
---

# core/cell-engine/tools/sx/src/node.zig

```zig
//! AST node types — verbatim port of bitcoinsx's `node.ts` + `lib/utils.ts`
//! `nodeTypes` enum.
//!
//! Numeric values MUST match his; downstream test fixtures (his
//! `tokeniseTypes.test.ts`, `parseTypes.test.ts`) literally assert
//! `{ type: nodeTypes.argument, ... }`. Our parity harness JSON-serialises
//! node objects and compares against his — any drift here breaks every
//! parity test.

const std = @import("std");

/// Mirror of `src/sx/src/lib/utils.ts::nodeTypes`. Add new variants only
/// when upstream adds them, never reorder.
pub const NodeType = enum(u8) {
    root = 0,
    opcode = 1,
    comment = 2,
    argument = 3,
    template = 4,
    bigint = 5,
    hex = 6,
    string = 7,
    annotation = 8,
    repeat = 9,
    end = 10,
    function = 11,
    call = 12,
    import = 13,
    word = 14,
    whitespace = 15,
    section = 16,
    pushCodeData = 17,

    pub fn name(self: NodeType) []const u8 {
        return @tagName(self);
    }
};

/// Mirror of `src/sx/src/node.ts::SxNode`. Optional fields use `?T` to map
/// his JS `undefined`. The parity harness considers a missing field on his
/// side equivalent to `null` on ours.
pub const Node = struct {
    type: NodeType,
    /// His `value: string | null`. We keep as optional slice — null when his
    /// node has no `value`. Memory: caller owns the backing bytes; lexer
    /// returns slices into the source string for zero-copy.
    value: ?[]const u8 = null,
    pos: u32 = 0,
    children: std.ArrayList(Node) = .{},
    /// His `asm: string | null`. Set for opcode nodes (e.g. "OP_NOP" for "nop").
    asm_str: ?[]const u8 = null,
    /// His `num?: number`. Set for opcode/bigint nodes from `shortOps`.
    num: ?i64 = null,
    /// His `label?: string` (from `@label:foo` annotations on subsequent node).
    label: ?[]const u8 = null,
    /// His `line?: number` — 1-indexed.
    line: ?u32 = null,
    /// His `col?: number` — 1-indexed.
    col: ?u32 = null,
    /// His `fileName?: string`.
    file_name: ?[]const u8 = null,
    /// His `fileId?: string | number` — we store as string for round-trip.
    file_id: ?[]const u8 = null,
    /// His `optional?: boolean` — set by lexer when argument ends in `?`
    /// (e.g. `.optArgName?`).
    optional: bool = false,
    /// His `description?: string` — populated by `@d:`/`@desc:` annotation
    /// when target is a function node.
    description: ?[]const u8 = null,
    /// His `cs?: number` — populated by `@cs:N` annotation, parses int
    /// from word or bigint value (stripping `n` suffix on bigint).
    cs: ?i64 = null,

    pub fn init(type_: NodeType, value: ?[]const u8, pos: u32) Node {
        return .{ .type = type_, .value = value, .pos = pos };
    }

    /// Deinit children recursively. Caller passes the allocator used to back
    /// the children list (the parity harness uses a single arena, so this is
    /// effectively a no-op when called from there).
    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        for (self.children.items) |*c| c.deinit(allocator);
        self.children.deinit(allocator);
    }
};

test "NodeType numeric values match bitcoinsx nodeTypes object" {
    // Anti-regression: a careless reorder of the enum would silently break
    // every parity test. Pin the wire values explicitly.
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(NodeType.root));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(NodeType.opcode));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(NodeType.comment));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(NodeType.argument));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(NodeType.template));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(NodeType.bigint));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(NodeType.hex));
    try std.testing.expectEqual(@as(u8, 7), @intFromEnum(NodeType.string));
    try std.testing.expectEqual(@as(u8, 8), @intFromEnum(NodeType.annotation));
    try std.testing.expectEqual(@as(u8, 9), @intFromEnum(NodeType.repeat));
    try std.testing.expectEqual(@as(u8, 10), @intFromEnum(NodeType.end));
    try std.testing.expectEqual(@as(u8, 11), @intFromEnum(NodeType.function));
    try std.testing.expectEqual(@as(u8, 12), @intFromEnum(NodeType.call));
    try std.testing.expectEqual(@as(u8, 13), @intFromEnum(NodeType.import));
    try std.testing.expectEqual(@as(u8, 14), @intFromEnum(NodeType.word));
    try std.testing.expectEqual(@as(u8, 15), @intFromEnum(NodeType.whitespace));
    try std.testing.expectEqual(@as(u8, 16), @intFromEnum(NodeType.section));
    try std.testing.expectEqual(@as(u8, 17), @intFromEnum(NodeType.pushCodeData));
}

```
