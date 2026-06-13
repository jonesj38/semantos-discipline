---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/re_anchor_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.481759+00:00
---

# cartridges/oddjobz/brain/zig/re_anchor_http.zig

```zig
// D-OJ-conv-re-anchor — Re-anchor HTTP handler.
//
// Spawns a Bun subprocess to run the TypeScript reAnchorTurn function
// for each request.  Wire protocol:
//
//   stdin  → { "turnId": "...", "newEntityCellHash": "...",
//               "newEntityKind": "...", "operatorCertId": "..." (optional) }
//   stdout ← { "ok": true,  "newRelationId": "...", "supersededRelationId": "..." }
//           | { "ok": false, "error": "turn_not_found" }
//           | { "ok": false, "error": "entity_not_found" }
//           | { "ok": false, "error": "no_existing_anchor" }
//           | { "ok": false, "error": "already_anchored" }
//           | { "ok": false, "error": "db_error" }
//
// HTTP status mapping:
//   reanchored              → 200 { "ok":true, "newRelationId":"...", "supersededRelationId":"..." }
//   already_anchored        → 200 { "ok":true, "alreadyAnchored":true }  (idempotent)
//   turn_not_found          → 404 { "error":"turn_not_found" }
//   entity_not_found        → 404 { "error":"entity_not_found" }
//   no_existing_anchor      → 409 { "error":"no_existing_anchor" }
//   db_error                → 500 { "error":"db_error" }
//   script_error            → 500 { "error":"script_error" }
//   unauthorised            → 401 { "error":"unauthorized" }
//
// Request body JSON: { newEntityCellHash, newEntityKind, operatorCertId? }
// The turnId is extracted from the URL path by the reactor and passed
// separately into callReAnchorScript — it is NOT required in the body.
//
// No persistent process — one subprocess per request.  Acceptable for
// the personal-scale sovereign node; a long-lived sidecar with a Unix
// socket can replace this later without changing the route config shape.

const std = @import("std");

// ── Request structs ───────────────────────────────────────────────────────────

/// Parsed from the HTTP request body JSON (newEntityCellHash + newEntityKind
/// + optional operatorCertId).  turnId is supplied separately from the URL path.
pub const BodyRequest = struct {
    new_entity_cell_hash: []u8,
    new_entity_kind: []u8,
    operator_cert_id: ?[]u8 = null,

    pub fn deinit(self: BodyRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.new_entity_cell_hash);
        allocator.free(self.new_entity_kind);
        if (self.operator_cert_id) |s| allocator.free(s);
    }
};

/// Full re-anchor request as sent to the bun subprocess on stdin.
/// `turn_id` is a borrowed slice (from the URL path); the other fields
/// are owned by `BodyRequest` — caller must keep `BodyRequest` alive.
pub const ReAnchorRequest = struct {
    turn_id: []const u8,
    new_entity_cell_hash: []const u8,
    new_entity_kind: []const u8,
    operator_cert_id: ?[]const u8 = null,
};

pub const ParseError = error{
    malformed,
    missing_field,
    out_of_memory,
};

/// Parse the HTTP request body JSON.  newEntityCellHash and newEntityKind are
/// required.  operatorCertId is optional.  turnId is NOT in the body —
/// it comes from the URL path.
pub fn parseBodyRequest(allocator: std.mem.Allocator, body: []const u8) ParseError!BodyRequest {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.malformed;
    defer parsed.deinit();
    if (parsed.value != .object) return error.malformed;
    const obj = parsed.value.object;

    // newEntityCellHash — required, non-empty.
    const nech_v = obj.get("newEntityCellHash") orelse return error.missing_field;
    if (nech_v != .string) return error.malformed;
    if (nech_v.string.len == 0) return error.missing_field;
    const new_entity_cell_hash = allocator.dupe(u8, nech_v.string) catch return error.out_of_memory;
    errdefer allocator.free(new_entity_cell_hash);

    // newEntityKind — required, non-empty.
    const nek_v = obj.get("newEntityKind") orelse return error.missing_field;
    if (nek_v != .string) return error.malformed;
    if (nek_v.string.len == 0) return error.missing_field;
    const new_entity_kind = allocator.dupe(u8, nek_v.string) catch return error.out_of_memory;
    errdefer allocator.free(new_entity_kind);

    // operatorCertId — optional string.
    var operator_cert_id: ?[]u8 = null;
    if (obj.get("operatorCertId")) |ocid_v| {
        if (ocid_v == .string and ocid_v.string.len > 0) {
            operator_cert_id = allocator.dupe(u8, ocid_v.string) catch return error.out_of_memory;
        }
    }

    return .{
        .new_entity_cell_hash = new_entity_cell_hash,
        .new_entity_kind = new_entity_kind,
        .operator_cert_id = operator_cert_id,
    };
}

// ── Result types ──────────────────────────────────────────────────────────────

pub const ReAnchorResultKind = enum {
    /// Re-anchor succeeded (new relation + supersedes): 200
    reanchored,
    /// Turn already anchored to the same entity (idempotent): 200
    already_anchored,
    /// Turn not found: 404
    turn_not_found,
    /// New entity not found: 404
    entity_not_found,
    /// No existing anchor to supersede: 409
    no_existing_anchor,
    /// db_error from the TS script: 500
    db_error,
    /// Subprocess exited non-zero or produced unparseable output: 500
    script_error,
    /// Missing / invalid bearer token: 401
    unauthorised,

    pub fn httpStatus(self: ReAnchorResultKind) std.http.Status {
        return switch (self) {
            .reanchored => .ok,
            .already_anchored => .ok,
            .turn_not_found => .not_found,
            .entity_not_found => .not_found,
            .no_existing_anchor => .conflict,
            .db_error => .internal_server_error,
            .script_error => .internal_server_error,
            .unauthorised => .unauthorized,
        };
    }
};

pub const ReAnchorResult = struct {
    kind: ReAnchorResultKind,
    /// Populated for .reanchored — the new BELONGS_TO_ENTITY relation id.
    new_relation_id: []u8 = &.{},
    /// Populated for .reanchored — the superseded relation id.
    superseded_relation_id: []u8 = &.{},

    pub fn deinit(self: *ReAnchorResult, allocator: std.mem.Allocator) void {
        if (self.new_relation_id.len > 0) allocator.free(self.new_relation_id);
        if (self.superseded_relation_id.len > 0) allocator.free(self.superseded_relation_id);
    }
};

// ── Subprocess dispatch ───────────────────────────────────────────────────────

/// Call the Bun re-anchor subprocess and return a typed result.
///
/// Returns `.unauthorised` immediately when `bearer` is null.
///
/// The subprocess receives JSON on stdin and returns JSON on stdout.
/// Up to 64 KB of stdout is read.
pub fn callReAnchorScript(
    allocator: std.mem.Allocator,
    script: []const u8,
    bearer: ?[]const u8,
    req: ReAnchorRequest,
) !ReAnchorResult {
    // 1. Bearer check — no token → 401.
    if (bearer == null) {
        return .{ .kind = .unauthorised };
    }

    // 2. Build stdin JSON.
    var stdin_buf: std.ArrayList(u8) = .{};
    defer stdin_buf.deinit(allocator);
    try buildReAnchorStdinJson(allocator, &stdin_buf, req);

    // 3. Spawn bun subprocess.
    var child = std.process.Child.init(&.{ "bun", "run", script }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    // Inherit stderr so diagnostic logs land in the brain's stderr /
    // systemd journal (same rationale as identity_merge_http.zig).
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
    return parseReAnchorScriptOutput(allocator, out.items);
}

/// Parse the subprocess stdout JSON into a typed ReAnchorResult.
fn parseReAnchorScriptOutput(allocator: std.mem.Allocator, output: []const u8) !ReAnchorResult {
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
            return .{ .kind = .turn_not_found };
        }
        if (std.mem.eql(u8, err_str, "entity_not_found")) {
            return .{ .kind = .entity_not_found };
        }
        if (std.mem.eql(u8, err_str, "no_existing_anchor")) {
            return .{ .kind = .no_existing_anchor };
        }
        if (std.mem.eql(u8, err_str, "already_anchored")) {
            return .{ .kind = .already_anchored };
        }
        if (std.mem.eql(u8, err_str, "db_error")) {
            return .{ .kind = .db_error };
        }
        // Unknown error string → script_error
        return .{ .kind = .script_error };
    }

    // { ok: true, newRelationId: "...", supersededRelationId: "..." }
    const nrid_v = obj.get("newRelationId") orelse return .{ .kind = .script_error };
    if (nrid_v != .string) return .{ .kind = .script_error };
    if (nrid_v.string.len == 0) return .{ .kind = .script_error };
    const new_relation_id = try allocator.dupe(u8, nrid_v.string);
    errdefer allocator.free(new_relation_id);

    const srid_v = obj.get("supersededRelationId") orelse return .{ .kind = .script_error };
    if (srid_v != .string) return .{ .kind = .script_error };
    if (srid_v.string.len == 0) return .{ .kind = .script_error };
    const superseded_relation_id = try allocator.dupe(u8, srid_v.string);

    return .{
        .kind = .reanchored,
        .new_relation_id = new_relation_id,
        .superseded_relation_id = superseded_relation_id,
    };
}

// ── JSON helpers ──────────────────────────────────────────────────────────────

fn buildReAnchorStdinJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    req: ReAnchorRequest,
) !void {
    try out.appendSlice(allocator, "{\"turnId\":");
    try writeJsonString(allocator, out, req.turn_id);
    try out.appendSlice(allocator, ",\"newEntityCellHash\":");
    try writeJsonString(allocator, out, req.new_entity_cell_hash);
    try out.appendSlice(allocator, ",\"newEntityKind\":");
    try writeJsonString(allocator, out, req.new_entity_kind);
    if (req.operator_cert_id) |ocid| {
        try out.appendSlice(allocator, ",\"operatorCertId\":");
        try writeJsonString(allocator, out, ocid);
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

test "parseBodyRequest: happy path — all required fields" {
    const body =
        \\{"newEntityCellHash":"entity-abc","newEntityKind":"job"}
    ;
    const r = try parseBodyRequest(std.testing.allocator, body);
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("entity-abc", r.new_entity_cell_hash);
    try std.testing.expectEqualStrings("job", r.new_entity_kind);
    try std.testing.expect(r.operator_cert_id == null);
}

test "parseBodyRequest: with optional operatorCertId" {
    const body =
        \\{"newEntityCellHash":"entity-def","newEntityKind":"site","operatorCertId":"cert-xyz"}
    ;
    const r = try parseBodyRequest(std.testing.allocator, body);
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("entity-def", r.new_entity_cell_hash);
    try std.testing.expectEqualStrings("site", r.new_entity_kind);
    try std.testing.expectEqualStrings("cert-xyz", r.operator_cert_id.?);
}

test "parseBodyRequest: missing newEntityCellHash → error.missing_field" {
    try std.testing.expectError(
        error.missing_field,
        parseBodyRequest(
            std.testing.allocator,
            "{\"newEntityKind\":\"job\"}",
        ),
    );
}

test "parseBodyRequest: missing newEntityKind → error.missing_field" {
    try std.testing.expectError(
        error.missing_field,
        parseBodyRequest(
            std.testing.allocator,
            "{\"newEntityCellHash\":\"entity-abc\"}",
        ),
    );
}

test "parseBodyRequest: malformed JSON → error.malformed" {
    try std.testing.expectError(
        error.malformed,
        parseBodyRequest(std.testing.allocator, "not-json"),
    );
}

test "parseReAnchorScriptOutput: reanchored case" {
    const output =
        \\{"ok":true,"newRelationId":"rel-new-123","supersededRelationId":"rel-old-456"}
    ;
    var result = try parseReAnchorScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .reanchored);
    try std.testing.expectEqualStrings("rel-new-123", result.new_relation_id);
    try std.testing.expectEqualStrings("rel-old-456", result.superseded_relation_id);
}

test "parseReAnchorScriptOutput: turn_not_found case" {
    const output = "{\"ok\":false,\"error\":\"turn_not_found\"}";
    var result = try parseReAnchorScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .turn_not_found);
}

test "parseReAnchorScriptOutput: no_existing_anchor case" {
    const output = "{\"ok\":false,\"error\":\"no_existing_anchor\"}";
    var result = try parseReAnchorScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .no_existing_anchor);
}

test "parseReAnchorScriptOutput: already_anchored case" {
    const output = "{\"ok\":false,\"error\":\"already_anchored\"}";
    var result = try parseReAnchorScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .already_anchored);
}

test "parseReAnchorScriptOutput: entity_not_found case" {
    const output = "{\"ok\":false,\"error\":\"entity_not_found\"}";
    var result = try parseReAnchorScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .entity_not_found);
}

test "parseReAnchorScriptOutput: db_error case" {
    const output = "{\"ok\":false,\"error\":\"db_error\"}";
    var result = try parseReAnchorScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .db_error);
}

test "parseReAnchorScriptOutput: empty output → script_error" {
    var result = try parseReAnchorScriptOutput(std.testing.allocator, "");
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .script_error);
}

```
