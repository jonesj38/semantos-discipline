---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/propose_turn_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.480244+00:00
---

# cartridges/oddjobz/brain/zig/propose_turn_http.zig

```zig
// D-OJ-conv-propose-outbound — Propose-turn HTTP handler.
//
// Spawns a Bun subprocess to run the TypeScript propose-turn-script.ts
// for each request.  Wire protocol:
//
//   stdin  → { "conversationId":"...", "surface":"...", "bodyText":"...",
//               "participantRole":"...", "recipientHandle":{"kind":"phone","value":"..."},
//               "includeCustomerLink":false }
//   stdout ← { "ok":true,  "turnId":"...", "state":"proposed" }
//           | { "ok":false, "error":"db_error" }
//           | { "ok":false, "error":"missing_fields" }
//
// HTTP status mapping:
//   proposed       → 200 { "ok":true, "turnId":"...", "state":"proposed" }
//   db_error       → 500 { "error":"db_error" }
//   missing_fields → 400 { "error":"missing_fields" }
//   script_error   → 500 { "error":"script_error" }
//   unauthorised   → 401 { "error":"unauthorized" }
//
// No persistent process — one subprocess per request.  Acceptable for
// the personal-scale sovereign node.

const std = @import("std");

// ── Request parsing ───────────────────────────────────────────────────────────

pub const ProposeTurnRequest = struct {
    conversation_id: []u8,
    surface: []u8,
    body_text: []u8,
    participant_role: []u8,
    recipient_kind: []u8,
    recipient_value: []u8,
    include_customer_link: bool = false,
    /// Optional entity cell hash
    entity_cell_hash: ?[]u8 = null,
    /// Optional entity kind ("job"|"site"|"customer"|"lead")
    entity_kind: ?[]u8 = null,
    /// Optional quoted turn id
    quoted_turn_id: ?[]u8 = null,

    pub fn deinit(self: ProposeTurnRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.conversation_id);
        allocator.free(self.surface);
        allocator.free(self.body_text);
        allocator.free(self.participant_role);
        allocator.free(self.recipient_kind);
        allocator.free(self.recipient_value);
        if (self.entity_cell_hash) |v| allocator.free(v);
        if (self.entity_kind) |v| allocator.free(v);
        if (self.quoted_turn_id) |v| allocator.free(v);
    }
};

pub const ParseError = error{
    malformed,
    missing_field,
    out_of_memory,
};

/// Parse the HTTP request body JSON.  Required fields: conversationId,
/// surface, bodyText, participantRole, recipientKind, recipientValue.
/// Optional: includeCustomerLink (bool, default false), entityCellHash,
/// entityKind, quotedTurnId.
pub fn parseRequest(allocator: std.mem.Allocator, body: []const u8) ParseError!ProposeTurnRequest {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.malformed;
    defer parsed.deinit();
    if (parsed.value != .object) return error.malformed;
    const obj = parsed.value.object;

    // conversationId — required, non-empty.
    const cid_v = obj.get("conversationId") orelse return error.missing_field;
    if (cid_v != .string) return error.malformed;
    if (cid_v.string.len == 0) return error.missing_field;
    const conversation_id = allocator.dupe(u8, cid_v.string) catch return error.out_of_memory;
    errdefer allocator.free(conversation_id);

    // surface — required, non-empty.
    const surf_v = obj.get("surface") orelse return error.missing_field;
    if (surf_v != .string) return error.malformed;
    if (surf_v.string.len == 0) return error.missing_field;
    const surface = allocator.dupe(u8, surf_v.string) catch return error.out_of_memory;
    errdefer allocator.free(surface);

    // bodyText — required (may be non-empty).
    const body_v = obj.get("bodyText") orelse return error.missing_field;
    if (body_v != .string) return error.malformed;
    if (body_v.string.len == 0) return error.missing_field;
    const body_text = allocator.dupe(u8, body_v.string) catch return error.out_of_memory;
    errdefer allocator.free(body_text);

    // participantRole — required.
    const role_v = obj.get("participantRole") orelse return error.missing_field;
    if (role_v != .string) return error.malformed;
    if (role_v.string.len == 0) return error.missing_field;
    const participant_role = allocator.dupe(u8, role_v.string) catch return error.out_of_memory;
    errdefer allocator.free(participant_role);

    // recipientKind — required ("phone"|"email").
    const rk_v = obj.get("recipientKind") orelse return error.missing_field;
    if (rk_v != .string) return error.malformed;
    if (rk_v.string.len == 0) return error.missing_field;
    const recipient_kind = allocator.dupe(u8, rk_v.string) catch return error.out_of_memory;
    errdefer allocator.free(recipient_kind);

    // recipientValue — required.
    const rv_v = obj.get("recipientValue") orelse return error.missing_field;
    if (rv_v != .string) return error.malformed;
    if (rv_v.string.len == 0) return error.missing_field;
    const recipient_value = allocator.dupe(u8, rv_v.string) catch return error.out_of_memory;
    errdefer allocator.free(recipient_value);

    // includeCustomerLink — optional bool, defaults to false.
    var include_customer_link: bool = false;
    if (obj.get("includeCustomerLink")) |icl_v| {
        if (icl_v != .bool) return error.malformed;
        include_customer_link = icl_v.bool;
    }

    // entityCellHash — optional string.
    var entity_cell_hash: ?[]u8 = null;
    if (obj.get("entityCellHash")) |ech_v| {
        if (ech_v == .string and ech_v.string.len > 0) {
            entity_cell_hash = allocator.dupe(u8, ech_v.string) catch return error.out_of_memory;
        }
    }
    errdefer if (entity_cell_hash) |v| allocator.free(v);

    // entityKind — optional string.
    var entity_kind: ?[]u8 = null;
    if (obj.get("entityKind")) |ek_v| {
        if (ek_v == .string and ek_v.string.len > 0) {
            entity_kind = allocator.dupe(u8, ek_v.string) catch return error.out_of_memory;
        }
    }
    errdefer if (entity_kind) |v| allocator.free(v);

    // quotedTurnId — optional string.
    var quoted_turn_id: ?[]u8 = null;
    if (obj.get("quotedTurnId")) |qt_v| {
        if (qt_v == .string and qt_v.string.len > 0) {
            quoted_turn_id = allocator.dupe(u8, qt_v.string) catch return error.out_of_memory;
        }
    }
    errdefer if (quoted_turn_id) |v| allocator.free(v);

    return .{
        .conversation_id = conversation_id,
        .surface = surface,
        .body_text = body_text,
        .participant_role = participant_role,
        .recipient_kind = recipient_kind,
        .recipient_value = recipient_value,
        .include_customer_link = include_customer_link,
        .entity_cell_hash = entity_cell_hash,
        .entity_kind = entity_kind,
        .quoted_turn_id = quoted_turn_id,
    };
}

// ── Result types ──────────────────────────────────────────────────────────────

pub const ProposeResultKind = enum {
    /// Turn proposed successfully: 200
    proposed,
    /// Missing required fields in request: 400
    missing_fields,
    /// db_error from the TS script: 500
    db_error,
    /// Subprocess exited non-zero or produced unparseable output: 500
    script_error,
    /// Missing / invalid bearer token: 401
    unauthorised,

    pub fn httpStatus(self: ProposeResultKind) std.http.Status {
        return switch (self) {
            .proposed => .ok,
            .missing_fields => .bad_request,
            .db_error => .internal_server_error,
            .script_error => .internal_server_error,
            .unauthorised => .unauthorized,
        };
    }
};

pub const ProposeResult = struct {
    kind: ProposeResultKind,
    /// Populated for .proposed — the new turn id.
    turn_id: []u8 = &.{},

    pub fn deinit(self: *ProposeResult, allocator: std.mem.Allocator) void {
        if (self.turn_id.len > 0) allocator.free(self.turn_id);
    }
};

// ── Subprocess dispatch ───────────────────────────────────────────────────────

/// Call the Bun propose-turn subprocess and return a typed result.
///
/// Returns `.unauthorised` immediately when `bearer` is null.
///
/// The subprocess receives JSON on stdin and returns JSON on stdout.
/// Up to 64 KB of stdout is read.
pub fn callProposeScript(
    allocator: std.mem.Allocator,
    script: []const u8,
    bearer: ?[]const u8,
    req: ProposeTurnRequest,
) !ProposeResult {
    // 1. Bearer check — no token → 401.
    if (bearer == null) {
        return .{ .kind = .unauthorised };
    }

    // 2. Build stdin JSON.
    var stdin_buf: std.ArrayList(u8) = .{};
    defer stdin_buf.deinit(allocator);
    try buildProposeStdinJson(allocator, &stdin_buf, req);

    // 3. Spawn bun subprocess.
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
    return parseProposeScriptOutput(allocator, out.items);
}

/// Parse the subprocess stdout JSON into a typed ProposeResult.
fn parseProposeScriptOutput(allocator: std.mem.Allocator, output: []const u8) !ProposeResult {
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

        if (std.mem.eql(u8, err_str, "db_error")) {
            return .{ .kind = .db_error };
        }
        if (std.mem.eql(u8, err_str, "missing_fields")) {
            return .{ .kind = .missing_fields };
        }
        return .{ .kind = .script_error };
    }

    // { ok: true, turnId: "...", state: "proposed" }
    const turn_id_v = obj.get("turnId") orelse return .{ .kind = .script_error };
    if (turn_id_v != .string) return .{ .kind = .script_error };
    if (turn_id_v.string.len == 0) return .{ .kind = .script_error };
    const turn_id = try allocator.dupe(u8, turn_id_v.string);

    return .{ .kind = .proposed, .turn_id = turn_id };
}

// ── Resolve script types ──────────────────────────────────────────────────────

pub const ResolveResultKind = enum {
    /// Link found: 200
    found,
    /// Token not found: 404
    not_found,
    /// db_error from the TS script: 500
    db_error,
    /// Subprocess produced unparseable output: 500
    script_error,

    pub fn httpStatus(self: ResolveResultKind) std.http.Status {
        return switch (self) {
            .found => .ok,
            .not_found => .not_found,
            .db_error => .internal_server_error,
            .script_error => .internal_server_error,
        };
    }
};

pub const ResolveResult = struct {
    kind: ResolveResultKind,
    /// Populated for .found — the conversation id.
    conversation_id: []u8 = &.{},
    /// Populated for .found — the entity title.
    entity_title: []u8 = &.{},

    pub fn deinit(self: *ResolveResult, allocator: std.mem.Allocator) void {
        if (self.conversation_id.len > 0) allocator.free(self.conversation_id);
        if (self.entity_title.len > 0) allocator.free(self.entity_title);
    }
};

/// Call the Bun customer-link-resolve subprocess.
pub fn callResolveScript(
    allocator: std.mem.Allocator,
    script: []const u8,
    token: []const u8,
) !ResolveResult {
    // Build stdin JSON: { "token": "..." }
    var stdin_buf: std.ArrayList(u8) = .{};
    defer stdin_buf.deinit(allocator);
    try stdin_buf.appendSlice(allocator, "{\"token\":");
    try writeJsonString(allocator, &stdin_buf, token);
    try stdin_buf.append(allocator, '}');

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

    return parseResolveScriptOutput(allocator, out.items);
}

fn parseResolveScriptOutput(allocator: std.mem.Allocator, output: []const u8) !ResolveResult {
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
        if (err_v != .string) return .{ .kind = .script_error };
        if (std.mem.eql(u8, err_v.string, "not_found")) {
            return .{ .kind = .not_found };
        }
        if (std.mem.eql(u8, err_v.string, "db_error")) {
            return .{ .kind = .db_error };
        }
        return .{ .kind = .script_error };
    }

    const cid_v = obj.get("conversationId") orelse return .{ .kind = .script_error };
    if (cid_v != .string) return .{ .kind = .script_error };
    const conversation_id = try allocator.dupe(u8, cid_v.string);
    errdefer allocator.free(conversation_id);

    const et_v = obj.get("entityTitle") orelse return .{ .kind = .script_error };
    if (et_v != .string) return .{ .kind = .script_error };
    const entity_title = try allocator.dupe(u8, et_v.string);

    return .{ .kind = .found, .conversation_id = conversation_id, .entity_title = entity_title };
}

// ── JSON helpers ──────────────────────────────────────────────────────────────

fn buildProposeStdinJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    req: ProposeTurnRequest,
) !void {
    try out.appendSlice(allocator, "{\"conversationId\":");
    try writeJsonString(allocator, out, req.conversation_id);
    try out.appendSlice(allocator, ",\"surface\":");
    try writeJsonString(allocator, out, req.surface);
    try out.appendSlice(allocator, ",\"bodyText\":");
    try writeJsonString(allocator, out, req.body_text);
    try out.appendSlice(allocator, ",\"participantRole\":");
    try writeJsonString(allocator, out, req.participant_role);
    try out.appendSlice(allocator, ",\"recipientHandle\":{\"kind\":");
    try writeJsonString(allocator, out, req.recipient_kind);
    try out.appendSlice(allocator, ",\"value\":");
    try writeJsonString(allocator, out, req.recipient_value);
    try out.append(allocator, '}');
    if (req.include_customer_link) {
        try out.appendSlice(allocator, ",\"includeCustomerLink\":true");
    }
    if (req.entity_cell_hash) |ech| {
        try out.appendSlice(allocator, ",\"entityRef\":{\"kind\":");
        const kind_str = req.entity_kind orelse "job";
        try writeJsonString(allocator, out, kind_str);
        try out.appendSlice(allocator, ",\"cellHash\":");
        try writeJsonString(allocator, out, ech);
        try out.append(allocator, '}');
    }
    if (req.quoted_turn_id) |qt| {
        try out.appendSlice(allocator, ",\"quotedTurnId\":");
        try writeJsonString(allocator, out, qt);
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

test "parseRequest: happy path — all required fields" {
    const body =
        \\{"conversationId":"conv-001","surface":"sms","bodyText":"Hello there",
        \\"participantRole":"operator","recipientKind":"phone","recipientValue":"+61400000001"}
    ;
    const r = try parseRequest(std.testing.allocator, body);
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("conv-001", r.conversation_id);
    try std.testing.expectEqualStrings("sms", r.surface);
    try std.testing.expectEqualStrings("Hello there", r.body_text);
    try std.testing.expectEqualStrings("operator", r.participant_role);
    try std.testing.expectEqualStrings("phone", r.recipient_kind);
    try std.testing.expectEqualStrings("+61400000001", r.recipient_value);
    try std.testing.expect(r.include_customer_link == false);
}

test "parseRequest: missing conversationId → error.missing_field" {
    try std.testing.expectError(
        error.missing_field,
        parseRequest(
            std.testing.allocator,
            "{\"surface\":\"sms\",\"bodyText\":\"Hi\",\"participantRole\":\"operator\",\"recipientKind\":\"phone\",\"recipientValue\":\"+61400\"}",
        ),
    );
}

test "parseRequest: missing bodyText → error.missing_field" {
    try std.testing.expectError(
        error.missing_field,
        parseRequest(
            std.testing.allocator,
            "{\"conversationId\":\"c1\",\"surface\":\"sms\",\"participantRole\":\"operator\",\"recipientKind\":\"phone\",\"recipientValue\":\"+61400\"}",
        ),
    );
}

test "parseRequest: includeCustomerLink=true parsed correctly" {
    const body =
        \\{"conversationId":"c1","surface":"widget","bodyText":"Hi","participantRole":"operator",
        \\"recipientKind":"phone","recipientValue":"+61400","includeCustomerLink":true}
    ;
    const r = try parseRequest(std.testing.allocator, body);
    defer r.deinit(std.testing.allocator);
    try std.testing.expect(r.include_customer_link == true);
}

test "parseRequest: malformed JSON → error.malformed" {
    try std.testing.expectError(
        error.malformed,
        parseRequest(std.testing.allocator, "not-json"),
    );
}

test "parseProposeScriptOutput: proposed case" {
    const output =
        \\{"ok":true,"turnId":"turn-out-abc123","state":"proposed"}
    ;
    var result = try parseProposeScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .proposed);
    try std.testing.expectEqualStrings("turn-out-abc123", result.turn_id);
}

test "parseProposeScriptOutput: db_error case" {
    const output = "{\"ok\":false,\"error\":\"db_error\"}";
    var result = try parseProposeScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .db_error);
}

test "parseProposeScriptOutput: empty output → script_error" {
    var result = try parseProposeScriptOutput(std.testing.allocator, "");
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .script_error);
}

```
