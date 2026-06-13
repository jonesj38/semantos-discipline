---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/intake_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.263179+00:00
---

# runtime/semantos-brain/src/intake_http.zig

```zig
// D-O7 — Intake route HTTP handler.
//
// Spawns a Bun subprocess to run the TypeScript handleConversationTurn
// pipeline for each request.  Wire protocol:
//
//   stdin  → { "message": "...", "session_id": "...", "data_dir": "...",
//              "entity_cell_hash"?: "..." }
//   stdout ← { "reply": "...", "action": {...}, "done": false }
//
// P1b — the caller may pass an optional `entity_cell_hash` (a 64-hex
// job cell ID sourced from the `?j=<cellId>` query param).  When present
// the intake-handler TypeScript sets entityRef on the written
// ConversationTurn so the widget chat is anchored to the correct job.
//
// No persistent process — one subprocess per request.  Acceptable for
// the personal-scale sovereign node; a long-lived sidecar with a Unix
// socket can replace this later without changing the route config shape.

const std = @import("std");

pub const DEFAULT_MAX_MESSAGE_CHARS: u32 = 4000;

pub const IntakeRequest = struct {
    message: []u8,
    session_id: []u8,
    /// Optional job cell hash sourced from `?j=<cellId>`.  Empty when absent.
    entity_cell_hash: []u8,

    pub fn deinit(self: IntakeRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        allocator.free(self.session_id);
        allocator.free(self.entity_cell_hash);
    }
};

pub const ParseError = error{
    malformed,
    missing_message,
    out_of_memory,
};

pub fn parseIntakeRequest(allocator: std.mem.Allocator, body: []const u8) ParseError!IntakeRequest {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.malformed;
    defer parsed.deinit();
    if (parsed.value != .object) return error.malformed;
    const obj = parsed.value.object;

    const msg_v = obj.get("message") orelse return error.missing_message;
    if (msg_v != .string) return error.malformed;
    if (msg_v.string.len == 0) return error.missing_message;
    const message = allocator.dupe(u8, msg_v.string) catch return error.out_of_memory;
    errdefer allocator.free(message);

    var session_id: []u8 = allocator.dupe(u8, "") catch return error.out_of_memory;
    errdefer allocator.free(session_id);
    if (obj.get("session_id")) |sv| {
        if (sv != .string) return error.malformed;
        if (sv.string.len > 256) return error.malformed;
        allocator.free(session_id);
        session_id = allocator.dupe(u8, sv.string) catch return error.out_of_memory;
    }

    // P1b: optional entity_cell_hash forwarded from the ?j= query param.
    var entity_cell_hash: []u8 = allocator.dupe(u8, "") catch return error.out_of_memory;
    if (obj.get("entity_cell_hash")) |ev| {
        if (ev == .string and ev.string.len > 0 and ev.string.len <= 128) {
            allocator.free(entity_cell_hash);
            entity_cell_hash = allocator.dupe(u8, ev.string) catch return error.out_of_memory;
        }
    }

    return .{ .message = message, .session_id = session_id, .entity_cell_hash = entity_cell_hash };
}

/// Invoke the Bun subprocess and return the response JSON body (caller frees).
/// Returns an alloced slice on success; returns error on OOM or subprocess failure.
/// `entity_cell_hash` — optional 64-hex job cell ID from `?j=` query param.
/// When non-null it is forwarded in the stdin JSON so the intake-handler
/// can anchor the written ConversationTurn to the correct job entity.
pub fn callScript(
    allocator: std.mem.Allocator,
    script: []const u8,
    req: IntakeRequest,
    data_dir: []const u8,
    entity_cell_hash: ?[]const u8,
) ![]u8 {
    // Build the stdin JSON: { "message": "...", "session_id": "...", "data_dir": "...",
    //                         "entity_cell_hash"?: "..." }
    var stdin_buf: std.ArrayList(u8) = .{};
    defer stdin_buf.deinit(allocator);
    try buildStdinJson(allocator, &stdin_buf, req, data_dir, entity_cell_hash);

    var child = std.process.Child.init(&.{ "bun", "run", script }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    // stdout is the wire protocol (JSON {reply,action,done}); stderr is purely
    // diagnostic (the handler returns user-facing errors as stdout JSON). Inherit
    // stderr so the handler's best-effort logs — submitLeadCell diagnostics,
    // recordIntakeTurn/persistLead errors — land in the brain's stderr and thus
    // the systemd journal. .Inherit (vs .Pipe) needs no draining, so it can't
    // deadlock against the bounded 128 KB stdout read loop below.
    child.stderr_behavior = .Inherit;

    try child.spawn();

    if (child.stdin) |stdin| {
        try stdin.writeAll(stdin_buf.items);
        stdin.close();
        child.stdin = null;
    }

    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);

    if (child.stdout) |stdout| {
        // Read up to 128 KB — more than enough for a chat reply.
        const buf = try allocator.alloc(u8, 128 * 1024);
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
    return out.toOwnedSlice(allocator);
}

fn buildStdinJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    req: IntakeRequest,
    data_dir: []const u8,
    entity_cell_hash: ?[]const u8,
) !void {
    try out.appendSlice(allocator, "{\"message\":");
    try writeJsonString(allocator, out, req.message);
    try out.appendSlice(allocator, ",\"session_id\":");
    try writeJsonString(allocator, out, req.session_id);
    try out.appendSlice(allocator, ",\"data_dir\":");
    try writeJsonString(allocator, out, data_dir);
    // P1b: forward job cell hash when present so the intake-handler can
    // anchor the ConversationTurn to the correct entity.
    if (entity_cell_hash) |h| {
        if (h.len > 0) {
            try out.appendSlice(allocator, ",\"entity_cell_hash\":");
            try writeJsonString(allocator, out, h);
        }
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

test "parseIntakeRequest: extracts message" {
    const r = try parseIntakeRequest(std.testing.allocator, "{\"message\":\"hi\"}");
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("hi", r.message);
    try std.testing.expectEqualStrings("", r.session_id);
    try std.testing.expectEqualStrings("", r.entity_cell_hash);
}

test "parseIntakeRequest: rejects empty message" {
    try std.testing.expectError(
        error.missing_message,
        parseIntakeRequest(std.testing.allocator, "{\"message\":\"\"}"),
    );
}

test "parseIntakeRequest: accepts entity_cell_hash" {
    const r = try parseIntakeRequest(std.testing.allocator,
        \\{"message":"hi","entity_cell_hash":"abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"}
    );
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("hi", r.message);
    try std.testing.expectEqualStrings(
        "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        r.entity_cell_hash,
    );
}

test "buildStdinJson: includes entity_cell_hash when present" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    const req = IntakeRequest{
        .message = @constCast("hi"),
        .session_id = @constCast("s1"),
        .entity_cell_hash = @constCast(""),
    };
    try buildStdinJson(std.testing.allocator, &buf, req, "/tmp", "abc123");
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, buf.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("abc123", parsed.value.object.get("entity_cell_hash").?.string);
}

test "buildStdinJson: omits entity_cell_hash when null" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    const req = IntakeRequest{
        .message = @constCast("hi"),
        .session_id = @constCast(""),
        .entity_cell_hash = @constCast(""),
    };
    try buildStdinJson(std.testing.allocator, &buf, req, "/tmp", null);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, buf.items, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("entity_cell_hash") == null);
}

```
