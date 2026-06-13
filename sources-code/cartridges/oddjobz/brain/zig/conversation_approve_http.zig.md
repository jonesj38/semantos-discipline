---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/conversation_approve_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.482420+00:00
---

# cartridges/oddjobz/brain/zig/conversation_approve_http.zig

```zig
// D-OJ-conv-approve — Conversation-turn approval HTTP handler.
//
// Spawns a Bun subprocess to run the TypeScript approveOutboundTurn
// pipeline for each request.  Wire protocol:
//
//   stdin  → { "turn_id": "...", "operator_cert_id": "...", "data_dir": "..." }
//   stdout ← { "ok": true,  "state": "sent", "surface_message_id"?: "..." }
//           | { "ok": true,  "state": "failed", "error"?: "..." }
//           | { "ok": false, "error": "turn_not_found" }
//           | { "ok": false, "error": "not_proposed", "current_state": "..." }
//           | { "ok": false, "error": "db_unavailable" }
//
// No persistent process — one subprocess per request.  Acceptable for
// the personal-scale sovereign node; a long-lived sidecar with a Unix
// socket can replace this later without changing the route config shape.

const std = @import("std");

// ── Request parsing ───────────────────────────────────────────────────────────

pub const ApproveRequest = struct {
    turn_id: []u8,
    operator_cert_id: []u8,

    pub fn deinit(self: ApproveRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.turn_id);
        allocator.free(self.operator_cert_id);
    }
};

pub const ParseError = error{
    malformed,
    missing_turn_id,
    out_of_memory,
};

/// Parse the HTTP request body JSON.  `operator_cert_id` defaults to
/// "operator" when absent from the body.
pub fn parseApproveRequest(allocator: std.mem.Allocator, body: []const u8) ParseError!ApproveRequest {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.malformed;
    defer parsed.deinit();
    if (parsed.value != .object) return error.malformed;
    const obj = parsed.value.object;

    const tid_v = obj.get("turn_id") orelse return error.missing_turn_id;
    if (tid_v != .string) return error.malformed;
    if (tid_v.string.len == 0) return error.missing_turn_id;
    const turn_id = allocator.dupe(u8, tid_v.string) catch return error.out_of_memory;
    errdefer allocator.free(turn_id);

    // operator_cert_id is optional; default to "operator".
    var operator_cert_id: []u8 = allocator.dupe(u8, "operator") catch return error.out_of_memory;
    if (obj.get("operator_cert_id")) |ocv| {
        if (ocv != .string) return error.malformed;
        if (ocv.string.len > 0) {
            allocator.free(operator_cert_id);
            operator_cert_id = allocator.dupe(u8, ocv.string) catch return error.out_of_memory;
        }
    }

    return .{ .turn_id = turn_id, .operator_cert_id = operator_cert_id };
}

// ── Result types ──────────────────────────────────────────────────────────────

pub const ApproveResultKind = enum {
    /// Turn sent (or sent-but-delivery-pending): 200
    sent,
    /// Surface adapter rejected the send: 200 (structured failure)
    failed,
    /// Turn not found in DB: 404
    not_found,
    /// Turn not in 'proposed' state: 409
    not_proposed,
    /// Subprocess exited non-zero or produced unparseable output: 500
    script_error,
    /// Missing / invalid bearer token: 401
    unauthorised,

    pub fn httpStatus(self: ApproveResultKind) std.http.Status {
        return switch (self) {
            .sent => .ok,
            .failed => .ok,
            .not_found => .not_found,
            .not_proposed => .conflict,
            .script_error => .internal_server_error,
            .unauthorised => .unauthorized,
        };
    }
};

pub const ApproveResult = struct {
    kind: ApproveResultKind,
    surface_message_id: []u8 = &.{},
    error_msg: []u8 = &.{},
    current_state: []u8 = &.{},

    pub fn deinit(self: *ApproveResult, allocator: std.mem.Allocator) void {
        if (self.surface_message_id.len > 0) allocator.free(self.surface_message_id);
        if (self.error_msg.len > 0) allocator.free(self.error_msg);
        if (self.current_state.len > 0) allocator.free(self.current_state);
    }
};

// ── Subprocess dispatch ───────────────────────────────────────────────────────

/// Call the Bun approval subprocess and return a typed result.
///
/// Returns `.unauthorised` immediately when `bearer` is null (no token
/// store check needed — no valid token ⇒ no access).
///
/// The subprocess receives JSON on stdin and returns JSON on stdout.
/// Up to 64 KB of stdout is read (more than enough for any approval
/// response).
pub fn callApproveScript(
    allocator: std.mem.Allocator,
    script: []const u8,
    bearer: ?[]const u8,
    turn_id: []const u8,
    operator_cert_id: []const u8,
    data_dir: []const u8,
) !ApproveResult {
    // 1. Bearer check — no token → 401.
    if (bearer == null) {
        return .{ .kind = .unauthorised };
    }

    // 2. Build stdin JSON.
    var stdin_buf: std.ArrayList(u8) = .{};
    defer stdin_buf.deinit(allocator);
    try buildApproveStdinJson(allocator, &stdin_buf, turn_id, operator_cert_id, data_dir);

    // 3. Spawn bun subprocess.
    var child = std.process.Child.init(&.{ "bun", "run", script }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    // Inherit stderr so diagnostic logs land in the brain's stderr /
    // systemd journal (same rationale as intake_http.callScript).
    child.stderr_behavior = .Inherit;

    try child.spawn();

    if (child.stdin) |stdin| {
        try stdin.writeAll(stdin_buf.items);
        stdin.close();
        child.stdin = null;
    }

    // 4. Read stdout (up to 64 KB).
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(allocator);

    if (child.stdout) |stdout| {
        const buf = try allocator.alloc(u8, 64 * 1024);
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

    // 5. Parse stdout JSON.
    return parseApproveScriptOutput(allocator, out.items);
}

/// Parse the subprocess stdout JSON into a typed ApproveResult.
fn parseApproveScriptOutput(allocator: std.mem.Allocator, output: []const u8) !ApproveResult {
    if (output.len == 0) return .{ .kind = .script_error };

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, output, .{}) catch
        return .{ .kind = .script_error };
    defer parsed.deinit();

    if (parsed.value != .object) return .{ .kind = .script_error };
    const obj = parsed.value.object;

    const ok_v = obj.get("ok") orelse return .{ .kind = .script_error };
    if (ok_v != .bool) return .{ .kind = .script_error };

    if (!ok_v.bool) {
        // { ok: false, error: "..." }
        const err_v = obj.get("error") orelse return .{ .kind = .script_error };
        if (err_v != .string) return .{ .kind = .script_error };
        const err_str = err_v.string;

        if (std.mem.eql(u8, err_str, "turn_not_found")) {
            return .{ .kind = .not_found };
        }
        if (std.mem.eql(u8, err_str, "not_proposed")) {
            var result: ApproveResult = .{ .kind = .not_proposed };
            if (obj.get("current_state")) |cs_v| {
                if (cs_v == .string and cs_v.string.len > 0) {
                    result.current_state = try allocator.dupe(u8, cs_v.string);
                }
            }
            return result;
        }
        // db_unavailable or other errors → 500
        return .{ .kind = .script_error };
    }

    // { ok: true, state: "sent" | "failed", ... }
    const state_v = obj.get("state") orelse return .{ .kind = .script_error };
    if (state_v != .string) return .{ .kind = .script_error };

    if (std.mem.eql(u8, state_v.string, "sent")) {
        var result: ApproveResult = .{ .kind = .sent };
        if (obj.get("surface_message_id")) |sid_v| {
            if (sid_v == .string and sid_v.string.len > 0) {
                result.surface_message_id = try allocator.dupe(u8, sid_v.string);
            }
        }
        return result;
    }

    if (std.mem.eql(u8, state_v.string, "failed")) {
        var result: ApproveResult = .{ .kind = .failed };
        if (obj.get("error")) |ev| {
            if (ev == .string and ev.string.len > 0) {
                result.error_msg = try allocator.dupe(u8, ev.string);
            }
        }
        return result;
    }

    return .{ .kind = .script_error };
}

// ── JSON helpers ──────────────────────────────────────────────────────────────

fn buildApproveStdinJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    turn_id: []const u8,
    operator_cert_id: []const u8,
    data_dir: []const u8,
) !void {
    try out.appendSlice(allocator, "{\"turn_id\":");
    try writeJsonString(allocator, out, turn_id);
    try out.appendSlice(allocator, ",\"operator_cert_id\":");
    try writeJsonString(allocator, out, operator_cert_id);
    try out.appendSlice(allocator, ",\"data_dir\":");
    try writeJsonString(allocator, out, data_dir);
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

test "parseApproveRequest: happy path with both fields" {
    const r = try parseApproveRequest(
        std.testing.allocator,
        "{\"turn_id\":\"turn-abc123\",\"operator_cert_id\":\"cert-xyz\"}",
    );
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("turn-abc123", r.turn_id);
    try std.testing.expectEqualStrings("cert-xyz", r.operator_cert_id);
}

test "parseApproveRequest: defaults operator_cert_id to 'operator' when absent" {
    const r = try parseApproveRequest(
        std.testing.allocator,
        "{\"turn_id\":\"turn-abc123\"}",
    );
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("turn-abc123", r.turn_id);
    try std.testing.expectEqualStrings("operator", r.operator_cert_id);
}

test "parseApproveRequest: malformed JSON → error.malformed" {
    try std.testing.expectError(
        error.malformed,
        parseApproveRequest(std.testing.allocator, "not-json"),
    );
}

test "parseApproveRequest: missing turn_id → error.missing_turn_id" {
    try std.testing.expectError(
        error.missing_turn_id,
        parseApproveRequest(std.testing.allocator, "{\"operator_cert_id\":\"cert-xyz\"}"),
    );
}

test "parseApproveRequest: empty turn_id → error.missing_turn_id" {
    try std.testing.expectError(
        error.missing_turn_id,
        parseApproveRequest(std.testing.allocator, "{\"turn_id\":\"\"}"),
    );
}

```
