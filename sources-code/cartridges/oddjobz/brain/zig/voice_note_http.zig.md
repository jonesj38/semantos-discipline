---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/voice_note_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.482120+00:00
---

# cartridges/oddjobz/brain/zig/voice_note_http.zig

```zig
// D-OJ-conv-voice-intake — voice note HTTP handler.
//
// Phase 5 of OJT-UNIFIED-QUOTE-INVOICE-PLAN: operators record voice notes
// while viewing a job; the transcript is stored as a ConversationTurn
// anchored to that job's entityRef so it appears in the Thread tab and
// feeds future AI quote/invoice extraction.
//
// Wire shape (POST /api/v1/voice-note):
//
//   Request:
//     Authorization: Bearer <hex64>
//     Content-Type: application/json
//     Body: {
//       "transcript":       string,          // required
//       "entity_id":        string,          // required — 64-hex job cellId
//       "entity_kind":      "job"|"site"|"customer", // required
//       "captured_at":      string,          // required — ISO-8601
//       "duration_seconds": number,          // optional
//       "recording_id":     string           // optional — dedup anchor
//     }
//
//   Response 201: { "turn_id": "..." }
//   Response 400: { "error": "invalid_payload", "hint": "..." }
//   Response 401: { "error": "bearer_invalid" }
//   Response 503: { "error": "script_unavailable" }
//   Response 500: { "error": "script_failed", "detail": "..." }
//
// Architecture: bearer-gated, shells out to
// `cartridges/oddjobz/brain/tools/voice-note-intake.ts` via stdin/stdout.
// The bun child writes the turn directly to Postgres — no HTTP self-call.

const std = @import("std");
const bearer_tokens = @import("bearer_tokens");

// ── Request validation ────────────────────────────────────────────────────────

pub const VoiceNoteRequest = struct {
    transcript: []u8,
    entity_id: []u8,
    entity_kind: []u8,
    captured_at: []u8,
    duration_seconds: ?f64 = null,
    recording_id: ?[]u8 = null,

    pub fn deinit(self: VoiceNoteRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.transcript);
        allocator.free(self.entity_id);
        allocator.free(self.entity_kind);
        allocator.free(self.captured_at);
        if (self.recording_id) |r| allocator.free(r);
    }
};

pub const ParseError = error{
    malformed,
    missing_transcript,
    missing_entity_id,
    missing_entity_kind,
    missing_captured_at,
    invalid_entity_kind,
    out_of_memory,
};

pub fn parseVoiceNoteRequest(
    allocator: std.mem.Allocator,
    body: []const u8,
) ParseError!VoiceNoteRequest {
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        body,
        .{},
    ) catch return error.malformed;
    defer parsed.deinit();

    if (parsed.value != .object) return error.malformed;
    const obj = parsed.value.object;

    // transcript
    const tr_v = obj.get("transcript") orelse return error.missing_transcript;
    if (tr_v != .string or tr_v.string.len == 0) return error.missing_transcript;
    const transcript = allocator.dupe(u8, tr_v.string) catch return error.out_of_memory;
    errdefer allocator.free(transcript);

    // entity_id
    const ei_v = obj.get("entity_id") orelse return error.missing_entity_id;
    if (ei_v != .string or ei_v.string.len == 0) return error.missing_entity_id;
    const entity_id = allocator.dupe(u8, ei_v.string) catch return error.out_of_memory;
    errdefer allocator.free(entity_id);

    // entity_kind
    const ek_v = obj.get("entity_kind") orelse return error.missing_entity_kind;
    if (ek_v != .string) return error.missing_entity_kind;
    const ek = ek_v.string;
    if (!std.mem.eql(u8, ek, "job") and
        !std.mem.eql(u8, ek, "site") and
        !std.mem.eql(u8, ek, "customer"))
    {
        return error.invalid_entity_kind;
    }
    const entity_kind = allocator.dupe(u8, ek) catch return error.out_of_memory;
    errdefer allocator.free(entity_kind);

    // captured_at
    const ca_v = obj.get("captured_at") orelse return error.missing_captured_at;
    if (ca_v != .string or ca_v.string.len == 0) return error.missing_captured_at;
    const captured_at = allocator.dupe(u8, ca_v.string) catch return error.out_of_memory;
    errdefer allocator.free(captured_at);

    // duration_seconds (optional)
    var duration_seconds: ?f64 = null;
    if (obj.get("duration_seconds")) |ds_v| {
        if (ds_v == .float) duration_seconds = ds_v.float;
        if (ds_v == .integer) duration_seconds = @as(f64, @floatFromInt(ds_v.integer));
    }

    // recording_id (optional)
    var recording_id: ?[]u8 = null;
    if (obj.get("recording_id")) |ri_v| {
        if (ri_v == .string and ri_v.string.len > 0) {
            recording_id = allocator.dupe(u8, ri_v.string) catch return error.out_of_memory;
        }
    }

    return .{
        .transcript = transcript,
        .entity_id = entity_id,
        .entity_kind = entity_kind,
        .captured_at = captured_at,
        .duration_seconds = duration_seconds,
        .recording_id = recording_id,
    };
}

// ── Result types ──────────────────────────────────────────────────────────────

pub const VoiceNoteResultKind = enum {
    created,
    invalid_payload,
    unauthorised,
    script_unavailable,
    script_failed,

    pub fn httpStatus(self: VoiceNoteResultKind) std.http.Status {
        return switch (self) {
            .created => .created,
            .invalid_payload => .bad_request,
            .unauthorised => .unauthorized,
            .script_unavailable => .service_unavailable,
            .script_failed => .internal_server_error,
        };
    }
};

pub const VoiceNoteResult = struct {
    kind: VoiceNoteResultKind,
    turn_id: []u8 = &.{},
    detail: []u8 = &.{},

    pub fn deinit(self: *VoiceNoteResult, allocator: std.mem.Allocator) void {
        if (self.turn_id.len > 0) allocator.free(self.turn_id);
        if (self.detail.len > 0) allocator.free(self.detail);
    }
};

// ── Subprocess dispatch ───────────────────────────────────────────────────────

/// Call the voice-note-intake bun CLI via stdin/stdout.
///
/// The acceptor carries the script path, bearer store, and the brain's
/// data_dir.  Returns `.unauthorised` when bearer is null.
/// Returns `.script_unavailable` when script path is empty.
pub fn callVoiceNoteScript(
    allocator: std.mem.Allocator,
    script: []const u8,
    bearer: ?[]const u8,
    req: VoiceNoteRequest,
    data_dir: []const u8,
) !VoiceNoteResult {
    if (bearer == null) {
        return .{ .kind = .unauthorised };
    }
    if (script.len == 0) {
        return .{ .kind = .script_unavailable };
    }

    // Build stdin JSON.
    var stdin_buf: std.ArrayList(u8) = .{};
    defer stdin_buf.deinit(allocator);
    try buildStdinJson(allocator, &stdin_buf, req, data_dir);

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

    // Read stdout (up to 64 KB).
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

    return parseScriptOutput(allocator, out.items);
}

/// Parse the subprocess stdout JSON.
fn parseScriptOutput(
    allocator: std.mem.Allocator,
    output: []const u8,
) !VoiceNoteResult {
    if (output.len == 0) {
        return .{ .kind = .script_failed };
    }
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        output,
        .{},
    ) catch return .{ .kind = .script_failed };
    defer parsed.deinit();

    if (parsed.value != .object) return .{ .kind = .script_failed };
    const obj = parsed.value.object;

    const ok_v = obj.get("ok") orelse return .{ .kind = .script_failed };
    if (ok_v != .bool) return .{ .kind = .script_failed };

    if (!ok_v.bool) {
        var detail: []u8 = &.{};
        if (obj.get("error")) |ev| {
            if (ev == .string and ev.string.len > 0) {
                detail = try allocator.dupe(u8, ev.string);
            }
        }
        return .{ .kind = .script_failed, .detail = detail };
    }

    // { ok: true, turn_id: "..." }
    var turn_id: []u8 = &.{};
    if (obj.get("turn_id")) |tv| {
        if (tv == .string and tv.string.len > 0) {
            turn_id = try allocator.dupe(u8, tv.string);
        }
    }
    return .{ .kind = .created, .turn_id = turn_id };
}

// ── JSON helpers ──────────────────────────────────────────────────────────────

fn buildStdinJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    req: VoiceNoteRequest,
    data_dir: []const u8,
) !void {
    const writer = out.writer(allocator);
    try writer.writeByte('{');
    try writeJsonString(allocator, out, "transcript");
    try writer.writeByte(':');
    try writeJsonString(allocator, out, req.transcript);
    try writer.writeByte(',');
    try writeJsonString(allocator, out, "entity_id");
    try writer.writeByte(':');
    try writeJsonString(allocator, out, req.entity_id);
    try writer.writeByte(',');
    try writeJsonString(allocator, out, "entity_kind");
    try writer.writeByte(':');
    try writeJsonString(allocator, out, req.entity_kind);
    try writer.writeByte(',');
    try writeJsonString(allocator, out, "captured_at");
    try writer.writeByte(':');
    try writeJsonString(allocator, out, req.captured_at);
    try writer.writeByte(',');
    try writeJsonString(allocator, out, "data_dir");
    try writer.writeByte(':');
    try writeJsonString(allocator, out, data_dir);
    if (req.duration_seconds) |ds| {
        try writer.writeByte(',');
        try writeJsonString(allocator, out, "duration_seconds");
        try writer.print(":{d}", .{ds});
    }
    if (req.recording_id) |rid| {
        try writer.writeByte(',');
        try writeJsonString(allocator, out, "recording_id");
        try writer.writeByte(':');
        try writeJsonString(allocator, out, rid);
    }
    try writer.writeByte('}');
}

fn writeJsonString(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    s: []const u8,
) !void {
    const writer = out.writer(allocator);
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "parseVoiceNoteRequest: valid full payload" {
    const allocator = std.testing.allocator;
    const body =
        \\{"transcript":"replace the tap washer","entity_id":"abc123","entity_kind":"job","captured_at":"2026-05-24T10:00:00Z","duration_seconds":8.5,"recording_id":"rec-001"}
    ;
    var req = try parseVoiceNoteRequest(allocator, body);
    defer req.deinit(allocator);
    try std.testing.expectEqualStrings("replace the tap washer", req.transcript);
    try std.testing.expectEqualStrings("abc123", req.entity_id);
    try std.testing.expectEqualStrings("job", req.entity_kind);
    try std.testing.expectEqualStrings("2026-05-24T10:00:00Z", req.captured_at);
    try std.testing.expectApproxEqAbs(8.5, req.duration_seconds.?, 0.001);
    try std.testing.expectEqualStrings("rec-001", req.recording_id.?);
}

test "parseVoiceNoteRequest: minimal required fields" {
    const allocator = std.testing.allocator;
    const body =
        \\{"transcript":"fix the gutters","entity_id":"deadbeef","entity_kind":"job","captured_at":"2026-05-24T10:00:00Z"}
    ;
    var req = try parseVoiceNoteRequest(allocator, body);
    defer req.deinit(allocator);
    try std.testing.expectEqualStrings("fix the gutters", req.transcript);
    try std.testing.expect(req.duration_seconds == null);
    try std.testing.expect(req.recording_id == null);
}

test "parseVoiceNoteRequest: entity_kind site and customer" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{ "site", "customer" }) |kind| {
        const body = try std.fmt.allocPrint(
            allocator,
            "{{\"transcript\":\"x\",\"entity_id\":\"id\",\"entity_kind\":\"{s}\",\"captured_at\":\"2026-05-24T10:00:00Z\"}}",
            .{kind},
        );
        defer allocator.free(body);
        var req = try parseVoiceNoteRequest(allocator, body);
        defer req.deinit(allocator);
        try std.testing.expectEqualStrings(kind, req.entity_kind);
    }
}

test "parseVoiceNoteRequest: missing transcript → error" {
    const allocator = std.testing.allocator;
    const body =
        \\{"entity_id":"abc","entity_kind":"job","captured_at":"2026-05-24T10:00:00Z"}
    ;
    const result = parseVoiceNoteRequest(allocator, body);
    try std.testing.expectError(error.missing_transcript, result);
}

test "parseVoiceNoteRequest: invalid entity_kind → error" {
    const allocator = std.testing.allocator;
    const body =
        \\{"transcript":"x","entity_id":"abc","entity_kind":"unknown","captured_at":"2026-05-24T10:00:00Z"}
    ;
    const result = parseVoiceNoteRequest(allocator, body);
    try std.testing.expectError(error.invalid_entity_kind, result);
}

test "parseVoiceNoteRequest: malformed JSON → error" {
    const allocator = std.testing.allocator;
    const result = parseVoiceNoteRequest(allocator, "not json");
    try std.testing.expectError(error.malformed, result);
}

test "parseScriptOutput: ok=true with turn_id" {
    const allocator = std.testing.allocator;
    const output = "{\"ok\":true,\"turn_id\":\"uuid-123\"}";
    var result = try parseScriptOutput(allocator, output);
    defer result.deinit(allocator);
    try std.testing.expectEqual(VoiceNoteResultKind.created, result.kind);
    try std.testing.expectEqualStrings("uuid-123", result.turn_id);
}

test "parseScriptOutput: ok=false returns script_failed" {
    const allocator = std.testing.allocator;
    const output = "{\"ok\":false,\"error\":\"db_unavailable\"}";
    var result = try parseScriptOutput(allocator, output);
    defer result.deinit(allocator);
    try std.testing.expectEqual(VoiceNoteResultKind.script_failed, result.kind);
    try std.testing.expectEqualStrings("db_unavailable", result.detail);
}

test "parseScriptOutput: empty output returns script_failed" {
    const allocator = std.testing.allocator;
    var result = try parseScriptOutput(allocator, "");
    defer result.deinit(allocator);
    try std.testing.expectEqual(VoiceNoteResultKind.script_failed, result.kind);
}

```
