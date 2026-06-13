---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/identity_merge_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.480542+00:00
---

# cartridges/oddjobz/brain/zig/identity_merge_http.zig

```zig
// D-OJ-conv-identity-merge-endpoint — Identity-merge HTTP handler.
//
// Spawns a Bun subprocess to run the TypeScript processIdentityMerge
// function for each request.  Wire protocol:
//
//   stdin  → { "sourceParticipantId": "...", "targetParticipantId": "...",
//               "challengeQuestion": "...", "challengeAnswer": "...",
//               "operatorConfirmed": true }
//   stdout ← { "ok": true,  "mergeId": "...", "chain": ["id1", "id2"] }
//           | { "ok": false, "error": "not_confirmed" }
//           | { "ok": false, "error": "same_identity" }
//           | { "ok": false, "error": "already_merged" }
//           | { "ok": false, "error": "db_error" }
//
// HTTP status mapping:
//   merged       → 200 { "ok":true, "mergeId":"...", "chain":[...] }
//   same_identity → 400 { "error":"same_identity" }
//   not_confirmed → 422 { "error":"not_confirmed" }
//   already_merged → 200 (idempotent) { "ok":true, "mergeId":"...", "chain":[...] }
//   db_error      → 500 { "error":"db_error" }
//   script_error  → 500 { "error":"script_error" }
//   unauthorised  → 401 { "error":"unauthorized" }
//
// No persistent process — one subprocess per request.  Acceptable for
// the personal-scale sovereign node; a long-lived sidecar with a Unix
// socket can replace this later without changing the route config shape.

const std = @import("std");

// ── Request parsing ───────────────────────────────────────────────────────────

pub const MergeRequest = struct {
    source_participant_id: []u8,
    target_participant_id: []u8,
    challenge_question: []u8,
    challenge_answer: []u8,
    operator_confirmed: bool,

    pub fn deinit(self: MergeRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.source_participant_id);
        allocator.free(self.target_participant_id);
        allocator.free(self.challenge_question);
        allocator.free(self.challenge_answer);
    }
};

pub const ParseError = error{
    malformed,
    missing_field,
    out_of_memory,
};

/// Parse the HTTP request body JSON.  All fields are required except
/// `operatorConfirmed`, which defaults to `false` when absent.
pub fn parseRequest(allocator: std.mem.Allocator, body: []const u8) ParseError!MergeRequest {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.malformed;
    defer parsed.deinit();
    if (parsed.value != .object) return error.malformed;
    const obj = parsed.value.object;

    // sourceParticipantId — required, non-empty.
    const src_v = obj.get("sourceParticipantId") orelse return error.missing_field;
    if (src_v != .string) return error.malformed;
    if (src_v.string.len == 0) return error.missing_field;
    const source_participant_id = allocator.dupe(u8, src_v.string) catch return error.out_of_memory;
    errdefer allocator.free(source_participant_id);

    // targetParticipantId — required, non-empty.
    const tgt_v = obj.get("targetParticipantId") orelse return error.missing_field;
    if (tgt_v != .string) return error.malformed;
    if (tgt_v.string.len == 0) return error.missing_field;
    const target_participant_id = allocator.dupe(u8, tgt_v.string) catch return error.out_of_memory;
    errdefer allocator.free(target_participant_id);

    // challengeQuestion — required (may be empty string — operator supplies it).
    const cq_v = obj.get("challengeQuestion") orelse return error.missing_field;
    if (cq_v != .string) return error.malformed;
    const challenge_question = allocator.dupe(u8, cq_v.string) catch return error.out_of_memory;
    errdefer allocator.free(challenge_question);

    // challengeAnswer — required (may be empty string).
    const ca_v = obj.get("challengeAnswer") orelse return error.missing_field;
    if (ca_v != .string) return error.malformed;
    const challenge_answer = allocator.dupe(u8, ca_v.string) catch return error.out_of_memory;
    errdefer allocator.free(challenge_answer);

    // operatorConfirmed — optional boolean, defaults to false.
    var operator_confirmed: bool = false;
    if (obj.get("operatorConfirmed")) |oc_v| {
        if (oc_v != .bool) return error.malformed;
        operator_confirmed = oc_v.bool;
    }

    return .{
        .source_participant_id = source_participant_id,
        .target_participant_id = target_participant_id,
        .challenge_question = challenge_question,
        .challenge_answer = challenge_answer,
        .operator_confirmed = operator_confirmed,
    };
}

// ── Result types ──────────────────────────────────────────────────────────────

pub const MergeResultKind = enum {
    /// Merge succeeded (new or idempotent): 200
    merged,
    /// Same source and target ids: 400
    same_identity,
    /// operatorConfirmed was false: 422
    not_confirmed,
    /// db_error from the TS script: 500
    db_error,
    /// Subprocess exited non-zero or produced unparseable output: 500
    script_error,
    /// Missing / invalid bearer token: 401
    unauthorised,

    pub fn httpStatus(self: MergeResultKind) std.http.Status {
        return switch (self) {
            .merged => .ok,
            .same_identity => .bad_request,
            .not_confirmed => .unprocessable_entity,
            .db_error => .internal_server_error,
            .script_error => .internal_server_error,
            .unauthorised => .unauthorized,
        };
    }
};

pub const MergeResult = struct {
    kind: MergeResultKind,
    /// Populated for .merged — the relation id of the MERGES edge.
    merge_id: []u8 = &.{},
    /// Populated for .merged — the BFS chain of participant ids.
    chain_json: []u8 = &.{},

    pub fn deinit(self: *MergeResult, allocator: std.mem.Allocator) void {
        if (self.merge_id.len > 0) allocator.free(self.merge_id);
        if (self.chain_json.len > 0) allocator.free(self.chain_json);
    }
};

// ── Subprocess dispatch ───────────────────────────────────────────────────────

/// Call the Bun identity-merge subprocess and return a typed result.
///
/// Returns `.unauthorised` immediately when `bearer` is null.
///
/// The subprocess receives JSON on stdin and returns JSON on stdout.
/// Up to 64 KB of stdout is read.
pub fn callMergeScript(
    allocator: std.mem.Allocator,
    script: []const u8,
    bearer: ?[]const u8,
    req: MergeRequest,
) !MergeResult {
    // 1. Bearer check — no token → 401.
    if (bearer == null) {
        return .{ .kind = .unauthorised };
    }

    // 2. Build stdin JSON.
    var stdin_buf: std.ArrayList(u8) = .{};
    defer stdin_buf.deinit(allocator);
    try buildMergeStdinJson(allocator, &stdin_buf, req);

    // 3. Spawn bun subprocess.
    var child = std.process.Child.init(&.{ "bun", "run", script }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    // Inherit stderr so diagnostic logs land in the brain's stderr /
    // systemd journal (same rationale as conversation_approve_http.zig).
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
    return parseMergeScriptOutput(allocator, out.items);
}

/// Parse the subprocess stdout JSON into a typed MergeResult.
fn parseMergeScriptOutput(allocator: std.mem.Allocator, output: []const u8) !MergeResult {
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

        if (std.mem.eql(u8, err_str, "same_identity")) {
            return .{ .kind = .same_identity };
        }
        if (std.mem.eql(u8, err_str, "not_confirmed")) {
            return .{ .kind = .not_confirmed };
        }
        if (std.mem.eql(u8, err_str, "db_error")) {
            return .{ .kind = .db_error };
        }
        // Unknown error string → script_error
        return .{ .kind = .script_error };
    }

    // { ok: true, mergeId: "...", chain: [...] }
    const merge_id_v = obj.get("mergeId") orelse return .{ .kind = .script_error };
    if (merge_id_v != .string) return .{ .kind = .script_error };
    if (merge_id_v.string.len == 0) return .{ .kind = .script_error };
    const merge_id = try allocator.dupe(u8, merge_id_v.string);
    errdefer allocator.free(merge_id);

    // chain is a JSON array of strings — re-serialise it for the HTTP response.
    const chain_v = obj.get("chain") orelse {
        // Missing chain — return merged with just mergeId.
        const chain_json = try allocator.dupe(u8, "[]");
        return .{ .kind = .merged, .merge_id = merge_id, .chain_json = chain_json };
    };
    if (chain_v != .array) {
        allocator.free(merge_id);
        return .{ .kind = .script_error };
    }

    // Serialise the chain array back to a JSON string for embedding in
    // the response.  Simple: each element must be a string.
    var chain_buf: std.ArrayList(u8) = .{};
    errdefer chain_buf.deinit(allocator);
    try chain_buf.append(allocator, '[');
    for (chain_v.array.items, 0..) |elem, idx| {
        if (elem != .string) {
            allocator.free(merge_id);
            chain_buf.deinit(allocator);
            return .{ .kind = .script_error };
        }
        if (idx > 0) try chain_buf.append(allocator, ',');
        try chain_buf.append(allocator, '"');
        // Escape the string value.
        for (elem.string) |c| switch (c) {
            '"' => try chain_buf.appendSlice(allocator, "\\\""),
            '\\' => try chain_buf.appendSlice(allocator, "\\\\"),
            '\n' => try chain_buf.appendSlice(allocator, "\\n"),
            '\r' => try chain_buf.appendSlice(allocator, "\\r"),
            '\t' => try chain_buf.appendSlice(allocator, "\\t"),
            else => try chain_buf.append(allocator, c),
        };
        try chain_buf.append(allocator, '"');
    }
    try chain_buf.append(allocator, ']');

    return .{ .kind = .merged, .merge_id = merge_id, .chain_json = try chain_buf.toOwnedSlice(allocator) };
}

// ── JSON helpers ──────────────────────────────────────────────────────────────

fn buildMergeStdinJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    req: MergeRequest,
) !void {
    try out.appendSlice(allocator, "{\"sourceParticipantId\":");
    try writeJsonString(allocator, out, req.source_participant_id);
    try out.appendSlice(allocator, ",\"targetParticipantId\":");
    try writeJsonString(allocator, out, req.target_participant_id);
    try out.appendSlice(allocator, ",\"challengeQuestion\":");
    try writeJsonString(allocator, out, req.challenge_question);
    try out.appendSlice(allocator, ",\"challengeAnswer\":");
    try writeJsonString(allocator, out, req.challenge_answer);
    if (req.operator_confirmed) {
        try out.appendSlice(allocator, ",\"operatorConfirmed\":true}");
    } else {
        try out.appendSlice(allocator, ",\"operatorConfirmed\":false}");
    }
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

test "parseRequest: happy path — all fields present" {
    const body =
        \\{"sourceParticipantId":"src-001","targetParticipantId":"tgt-002",
        \\"challengeQuestion":"What was the address?","challengeAnswer":"42 Acacia Ave",
        \\"operatorConfirmed":true}
    ;
    const r = try parseRequest(std.testing.allocator, body);
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("src-001", r.source_participant_id);
    try std.testing.expectEqualStrings("tgt-002", r.target_participant_id);
    try std.testing.expectEqualStrings("What was the address?", r.challenge_question);
    try std.testing.expectEqualStrings("42 Acacia Ave", r.challenge_answer);
    try std.testing.expect(r.operator_confirmed == true);
}

test "parseRequest: missing sourceParticipantId → error.missing_field" {
    try std.testing.expectError(
        error.missing_field,
        parseRequest(
            std.testing.allocator,
            "{\"targetParticipantId\":\"tgt-002\",\"challengeQuestion\":\"Q\",\"challengeAnswer\":\"A\"}",
        ),
    );
}

test "parseRequest: operatorConfirmed absent → defaults to false" {
    const body =
        \\{"sourceParticipantId":"src-001","targetParticipantId":"tgt-002",
        \\"challengeQuestion":"Q","challengeAnswer":"A"}
    ;
    const r = try parseRequest(std.testing.allocator, body);
    defer r.deinit(std.testing.allocator);
    try std.testing.expect(r.operator_confirmed == false);
}

test "parseRequest: malformed JSON → error.malformed" {
    try std.testing.expectError(
        error.malformed,
        parseRequest(std.testing.allocator, "not-json"),
    );
}

test "parseMergeScriptOutput: merged case" {
    const output =
        \\{"ok":true,"mergeId":"rel-abc","chain":["src-001","tgt-002"]}
    ;
    var result = try parseMergeScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .merged);
    try std.testing.expectEqualStrings("rel-abc", result.merge_id);
    try std.testing.expectEqualStrings("[\"src-001\",\"tgt-002\"]", result.chain_json);
}

test "parseMergeScriptOutput: same_identity case" {
    const output = "{\"ok\":false,\"error\":\"same_identity\"}";
    var result = try parseMergeScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .same_identity);
}

test "parseMergeScriptOutput: not_confirmed case" {
    const output = "{\"ok\":false,\"error\":\"not_confirmed\"}";
    var result = try parseMergeScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .not_confirmed);
}

test "parseMergeScriptOutput: already_merged returns script_error (unknown to zig)" {
    // already_merged is handled at the TS layer and re-mapped to ok:true
    // by identity-merge-script.ts (idempotent); but if it ever leaks as
    // ok:false we map it to script_error to be safe.
    const output = "{\"ok\":false,\"error\":\"already_merged\"}";
    var result = try parseMergeScriptOutput(std.testing.allocator, output);
    defer result.deinit(std.testing.allocator);
    // already_merged is not in our error string list → script_error
    try std.testing.expect(result.kind == .script_error);
}

test "parseMergeScriptOutput: empty output → script_error" {
    var result = try parseMergeScriptOutput(std.testing.allocator, "");
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.kind == .script_error);
}

```
