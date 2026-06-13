---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/conv_turns_query_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.481183+00:00
---

# cartridges/oddjobz/brain/zig/conv_turns_query_http.zig

```zig
// D-OJ-conv-turns-query — Conversation turns query HTTP handler.
//
// Spawns a Bun subprocess to run conversation-turns-query-script.ts.
//
//   GET  /api/v1/conversation/turns?entityRef=<hex>&limit=50&before=<ms>
//   GET  /api/v1/conversation/turns?conversationId=<id>&direction=inbound
//
// Query params (all optional):
//   entityRef      — cellHash of the entity (job/site/customer)
//   conversationId — narrow to a single thread
//   limit          — max rows, default 50, capped at 200
//   before         — ms-epoch cursor for pagination
//   direction      — 'inbound' | 'outbound'
//   outboundState  — 'proposed' | 'approved' | 'sent' | ...
//
// stdin  → { entityRef?, conversationId?, limit?, before?, direction?, outboundState? }
// stdout ← { ok: true,  turns: [...] }
//         | { ok: false, error: 'db_error' }
//
// HTTP status mapping:
//   ok        → 200 { ok: true, turns: [...] }
//   db_error  → 500 { error: 'db_error' }
//   script_error → 500 { error: 'script_error' }
//   unauthorised → 401 { error: 'unauthorized' }
//
// Bearer-gated; no persistent process.

const std = @import("std");

// ── Result types ──────────────────────────────────────────────────────────────

pub const QueryResultKind = enum {
    ok,
    db_error,
    script_error,
    unauthorised,

    pub fn httpStatus(self: QueryResultKind) std.http.Status {
        return switch (self) {
            .ok => .ok,
            .db_error => .internal_server_error,
            .script_error => .internal_server_error,
            .unauthorised => .unauthorized,
        };
    }
};

pub const QueryResult = struct {
    kind: QueryResultKind,
    /// Raw JSON turns array string (populated for .ok).
    turns_json: []u8 = &.{},

    pub fn deinit(self: *QueryResult, allocator: std.mem.Allocator) void {
        if (self.turns_json.len > 0) allocator.free(self.turns_json);
    }
};

// ── Subprocess dispatch ───────────────────────────────────────────────────────

/// Call the Bun turns-query subprocess and return a typed result.
/// bearer == null → .unauthorised immediately.
pub fn callQueryScript(
    allocator: std.mem.Allocator,
    script: []const u8,
    bearer: ?[]const u8,
    entity_ref: ?[]const u8,
    conversation_id: ?[]const u8,
    limit: ?u32,
    before: ?u64,
    direction: ?[]const u8,
    outbound_state: ?[]const u8,
) !QueryResult {
    if (bearer == null) return .{ .kind = .unauthorised };

    // Build stdin JSON.
    var stdin_buf: std.ArrayList(u8) = .{};
    defer stdin_buf.deinit(allocator);
    try buildStdinJson(allocator, &stdin_buf, entity_ref, conversation_id, limit, before, direction, outbound_state);

    // Spawn bun subprocess.
    var child = std.process.Child.init(&.{ "bun", "run", script }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    try child.spawn();

    if (child.stdin) |stdin| {
        try stdin.writeAll(stdin_buf.items);
        stdin.close();
        child.stdin = null;
    }

    // Read stdout (up to 1 MB — turns can be many rows).
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(allocator);
    if (child.stdout) |stdout| {
        const buf = try allocator.alloc(u8, 1024 * 1024);
        defer allocator.free(buf);
        var total: usize = 0;
        while (true) {
            const n = stdout.read(buf[total..]) catch break;
            if (n == 0) break;
            total += n;
            if (total >= buf.len) break;
        }
        try out.appendSlice(allocator, buf[0..total]);
    }
    _ = child.wait() catch {};

    return parseScriptOutput(allocator, out.items);
}

fn parseScriptOutput(allocator: std.mem.Allocator, output: []const u8) !QueryResult {
    if (output.len == 0) return .{ .kind = .script_error };

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, output, .{}) catch
        return .{ .kind = .script_error };
    defer parsed.deinit();

    if (parsed.value != .object) return .{ .kind = .script_error };
    const obj = parsed.value.object;

    const ok_v = obj.get("ok") orelse return .{ .kind = .script_error };
    if (ok_v != .bool) return .{ .kind = .script_error };

    if (!ok_v.bool) {
        const err_v = obj.get("error") orelse return .{ .kind = .script_error };
        if (err_v == .string and std.mem.eql(u8, err_v.string, "db_error"))
            return .{ .kind = .db_error };
        return .{ .kind = .script_error };
    }

    // Extract the raw "turns" array JSON to pass through to the HTTP response.
    const turns_v = obj.get("turns") orelse return .{ .kind = .script_error };
    const turns_json = std.json.Stringify.valueAlloc(allocator, turns_v, .{}) catch
        return .{ .kind = .script_error };
    return .{ .kind = .ok, .turns_json = turns_json };
}

// ── JSON builder ──────────────────────────────────────────────────────────────

fn buildStdinJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    entity_ref: ?[]const u8,
    conversation_id: ?[]const u8,
    limit: ?u32,
    before: ?u64,
    direction: ?[]const u8,
    outbound_state: ?[]const u8,
) !void {
    try out.append(allocator, '{');
    var first = true;

    if (entity_ref) |v| {
        try out.appendSlice(allocator, "\"entityRef\":");
        try writeJsonString(allocator, out, v);
        first = false;
    }
    if (conversation_id) |v| {
        if (!first) try out.append(allocator, ',');
        try out.appendSlice(allocator, "\"conversationId\":");
        try writeJsonString(allocator, out, v);
        first = false;
    }
    if (limit) |v| {
        if (!first) try out.append(allocator, ',');
        var num_buf: [16]u8 = undefined;
        const num_str = try std.fmt.bufPrint(&num_buf, "{d}", .{v});
        try out.appendSlice(allocator, "\"limit\":");
        try out.appendSlice(allocator, num_str);
        first = false;
    }
    if (before) |v| {
        if (!first) try out.append(allocator, ',');
        var num_buf: [24]u8 = undefined;
        const num_str = try std.fmt.bufPrint(&num_buf, "{d}", .{v});
        try out.appendSlice(allocator, "\"before\":");
        try out.appendSlice(allocator, num_str);
        first = false;
    }
    if (direction) |v| {
        if (!first) try out.append(allocator, ',');
        try out.appendSlice(allocator, "\"direction\":");
        try writeJsonString(allocator, out, v);
        first = false;
    }
    if (outbound_state) |v| {
        if (!first) try out.append(allocator, ',');
        try out.appendSlice(allocator, "\"outboundState\":");
        try writeJsonString(allocator, out, v);
    }
    try out.append(allocator, '}');
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    try out.append(allocator, '"');
    for (s) |c| switch (c) {
        '"' => try out.appendSlice(allocator, "\\\""),
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\r' => try out.appendSlice(allocator, "\\r"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        0x08 => try out.appendSlice(allocator, "\\b"),
        0x0c => try out.appendSlice(allocator, "\\f"),
        0...0x07, 0x0b, 0x0e...0x1f => {
            var buf: [8]u8 = undefined;
            const slice = try std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c});
            try out.appendSlice(allocator, slice);
        },
        else => try out.append(allocator, c),
    };
    try out.append(allocator, '"');
}

// ── Inline tests ──────────────────────────────────────────────────────────────

test "parseScriptOutput: ok with turns array" {
    const output =
        \\{"ok":true,"turns":[{"turnId":"t1","direction":"inbound"}]}
    ;
    var result = try parseScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .ok);
    try std.testing.expect(result.turns_json.len > 0);
}

test "parseScriptOutput: db_error" {
    var result = try parseScriptOutput(std.testing.allocator, "{\"ok\":false,\"error\":\"db_error\"}");
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .db_error);
}

test "parseScriptOutput: empty output → script_error" {
    var result = try parseScriptOutput(std.testing.allocator, "");
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .script_error);
}

test "buildStdinJson: entityRef only" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    try buildStdinJson(std.testing.allocator, &buf, "abc123", null, null, null, null, null);
    try std.testing.expectEqualStrings("{\"entityRef\":\"abc123\"}", buf.items);
}

test "buildStdinJson: empty" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    try buildStdinJson(std.testing.allocator, &buf, null, null, null, null, null, null);
    try std.testing.expectEqualStrings("{}", buf.items);
}

test "buildStdinJson: limit and direction" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    try buildStdinJson(std.testing.allocator, &buf, null, null, 25, null, "inbound", null);
    try std.testing.expectEqualStrings("{\"limit\":25,\"direction\":\"inbound\"}", buf.items);
}

```
