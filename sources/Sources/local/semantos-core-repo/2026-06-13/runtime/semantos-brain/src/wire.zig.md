---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/wire.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.250215+00:00
---

# runtime/semantos-brain/src/wire.zig

```zig
// Phase D-W1 / Phase 0 — brain wire envelope codec.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §6, §9.
//
// Hand-rolled JSON codec for the four envelope shapes the dispatcher's
// non-in-process transports speak:
//
//   • Request  — operator-side dispatch invocation.
//   • Response — synchronous success or typed failure.
//   • Chunk    — one piece of a streaming response (multi-frame
//                replies, e.g. headers byHeight range queries).
//   • Complete — terminator for a stream (with optional final result).
//
// Same envelope shape on every non-in-process transport — Unix socket,
// HTTP, WSS, SignedBundle mesh.  In-process transports skip
// serialisation entirely (they call dispatcher.dispatch directly with
// typed args).
//
// Phase 0 scope (this PR): codec only.  No transport actually wired
// onto the wire format yet.  The Unix socket transport is Phase 1.
//
// Design notes:
//
//   • The envelope's `args`/`result`/`details` payloads are kept as
//     raw `[]u8` JSON byte slices on both the encode and decode paths
//     so the dispatcher and the resource handlers don't have to know
//     about std.json.Value trees.  The wire codec re-stringifies the
//     JSON sub-tree on decode for canonical round-trip.
//
//   • Unknown top-level fields are silently ignored on decode (forward-
//     compat with future schema additions).
//
//   • Missing optional fields decode to defaults (`request_id = ""`,
//     `args = "null"`, etc.) — strict parsers are easier to break
//     across language ecosystems.
//
//   • Keep this module pure-Zig + std.  Hand-rolled construction via
//     std.fmt.allocPrint + std.json.Stringify for string escaping
//     (same pattern as llm_http_adapter.zig).

const std = @import("std");

/// Schema version.  Bumped only when the wire shape itself changes
/// incompatibly; field additions are forward-compat at v1.
pub const ENVELOPE_VERSION: u8 = 1;

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

pub const WireError = error{
    /// JSON parse failed (malformed input).
    invalid_json,
    /// Top-level value isn't a JSON object.
    not_an_object,
    /// A required field is missing.
    missing_field,
    /// A field has the wrong JSON type.
    wrong_type,
    /// `v` is not the expected ENVELOPE_VERSION.
    unsupported_version,
    /// `kind` field on an error envelope didn't match a known kind.
    unknown_error_kind,
    /// Stream envelope's `type` field is neither "chunk" nor "complete".
    unknown_stream_envelope_type,
    /// Allocation failed during codec.
    out_of_memory,
};

// ─────────────────────────────────────────────────────────────────────
// Error envelope kinds
// ─────────────────────────────────────────────────────────────────────

/// Typed error categories per BRAIN-DISPATCHER-UNIFICATION.md §6.  The
/// human-readable `message` field is for operator UX; `kind` is the
/// parseable contract — clients dispatch on this enum, not the message.
pub const ErrorKind = enum {
    unknown_resource,
    unknown_command,
    capability_denied,
    validation_failed,
    not_implemented,

    pub fn toString(self: ErrorKind) []const u8 {
        return switch (self) {
            .unknown_resource => "unknown_resource",
            .unknown_command => "unknown_command",
            .capability_denied => "capability_denied",
            .validation_failed => "validation_failed",
            .not_implemented => "not_implemented",
        };
    }

    pub fn fromString(s: []const u8) ?ErrorKind {
        if (std.mem.eql(u8, s, "unknown_resource")) return .unknown_resource;
        if (std.mem.eql(u8, s, "unknown_command")) return .unknown_command;
        if (std.mem.eql(u8, s, "capability_denied")) return .capability_denied;
        if (std.mem.eql(u8, s, "validation_failed")) return .validation_failed;
        if (std.mem.eql(u8, s, "not_implemented")) return .not_implemented;
        return null;
    }
};

// ─────────────────────────────────────────────────────────────────────
// Envelope shapes
// ─────────────────────────────────────────────────────────────────────

/// One operator-initiated dispatch call.  All slices are borrowed; the
/// caller (encoder) owns the memory and the decoder returns slices
/// owned by the OwnedRequest result.
pub const Request = struct {
    v: u8 = ENVELOPE_VERSION,
    request_id: []const u8 = "",
    resource: []const u8,
    cmd: []const u8,
    /// Raw JSON for the `args` field.  Empty/`""` decodes-encodes as
    /// `"null"`; any well-formed JSON value is accepted.
    args_json: []const u8 = "null",
};

/// Synchronous response.  Either `result_json` is set (success) OR
/// `err` is set (failure); never both at once on a well-formed envelope.
pub const Response = struct {
    v: u8 = ENVELOPE_VERSION,
    request_id: []const u8 = "",
    /// Raw JSON of the success result.  `"null"` is a valid empty result.
    result_json: []const u8 = "null",
    err: ?ErrorBody = null,
};

pub const ErrorBody = struct {
    kind: ErrorKind,
    message: []const u8 = "",
    /// Raw JSON for the optional `details` field.  Defaults to `"null"`.
    details_json: []const u8 = "null",
};

/// One chunk of a streaming response.  Sequence numbers start at 0 and
/// monotonically increase per request.  The final frame is a `Complete`
/// envelope (NOT a chunk with seq=last).
pub const Chunk = struct {
    v: u8 = ENVELOPE_VERSION,
    request_id: []const u8 = "",
    seq: u32,
    /// Raw JSON for this chunk's body.
    body_json: []const u8 = "null",
};

/// Terminator for a stream.  May carry an optional final result OR an
/// error (e.g. partial success then validation_failed).
pub const Complete = struct {
    v: u8 = ENVELOPE_VERSION,
    request_id: []const u8 = "",
    result_json: []const u8 = "null",
    err: ?ErrorBody = null,
};

/// Discriminated stream-envelope union — the wire format peeks at
/// `type` to decide which shape to decode.
pub const StreamEnvelope = union(enum) {
    chunk: Chunk,
    complete: Complete,
};

// ─────────────────────────────────────────────────────────────────────
// Owned-decode wrappers — every decoded envelope owns its slices via
// the supplied allocator.  Caller must call `deinit`.
//
// Implementation note: each string/raw-JSON field that needs to outlive
// the parser is allocator.dupe'd individually and tracked in `bufs`
// for batch-free.  A single growing backing buffer would invalidate
// earlier slices on realloc; per-field dupe is the safe shape.
// ─────────────────────────────────────────────────────────────────────

const OwnedBufs = struct {
    list: std.ArrayList([]u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) OwnedBufs {
        return .{ .list = .{}, .allocator = allocator };
    }

    fn track(self: *OwnedBufs, buf: []u8) WireError![]u8 {
        self.list.append(self.allocator, buf) catch return WireError.out_of_memory;
        return buf;
    }

    fn deinit(self: *OwnedBufs) void {
        for (self.list.items) |b| self.allocator.free(b);
        self.list.deinit(self.allocator);
    }
};

pub const OwnedRequest = struct {
    request: Request,
    allocator: std.mem.Allocator,
    bufs: OwnedBufs,

    pub fn deinit(self: *OwnedRequest) void {
        self.bufs.deinit();
    }
};

pub const OwnedResponse = struct {
    response: Response,
    allocator: std.mem.Allocator,
    bufs: OwnedBufs,

    pub fn deinit(self: *OwnedResponse) void {
        self.bufs.deinit();
    }
};

pub const OwnedChunk = struct {
    chunk: Chunk,
    allocator: std.mem.Allocator,
    bufs: OwnedBufs,

    pub fn deinit(self: *OwnedChunk) void {
        self.bufs.deinit();
    }
};

pub const OwnedComplete = struct {
    complete: Complete,
    allocator: std.mem.Allocator,
    bufs: OwnedBufs,

    pub fn deinit(self: *OwnedComplete) void {
        self.bufs.deinit();
    }
};

pub const OwnedStreamEnvelope = struct {
    envelope: StreamEnvelope,
    allocator: std.mem.Allocator,
    bufs: OwnedBufs,

    pub fn deinit(self: *OwnedStreamEnvelope) void {
        self.bufs.deinit();
    }
};

// ─────────────────────────────────────────────────────────────────────
// Encoder — hand-built JSON via allocPrint + Stringify for string escape.
// ─────────────────────────────────────────────────────────────────────

pub fn encodeRequest(allocator: std.mem.Allocator, req: Request) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"v\":");
    try writeU8(allocator, &out, req.v);
    try out.appendSlice(allocator, ",\"request_id\":");
    try writeJsonString(allocator, &out, req.request_id);
    try out.appendSlice(allocator, ",\"resource\":");
    try writeJsonString(allocator, &out, req.resource);
    try out.appendSlice(allocator, ",\"cmd\":");
    try writeJsonString(allocator, &out, req.cmd);
    try out.appendSlice(allocator, ",\"args\":");
    try writeRawJson(allocator, &out, req.args_json);
    try out.append(allocator, '}');
    return out.toOwnedSlice(allocator);
}

pub fn encodeResponse(allocator: std.mem.Allocator, resp: Response) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"v\":");
    try writeU8(allocator, &out, resp.v);
    try out.appendSlice(allocator, ",\"request_id\":");
    try writeJsonString(allocator, &out, resp.request_id);
    if (resp.err) |e| {
        try out.appendSlice(allocator, ",\"error\":");
        try writeErrorBody(allocator, &out, e);
    } else {
        try out.appendSlice(allocator, ",\"result\":");
        try writeRawJson(allocator, &out, resp.result_json);
    }
    try out.append(allocator, '}');
    return out.toOwnedSlice(allocator);
}

pub fn encodeChunk(allocator: std.mem.Allocator, c: Chunk) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"v\":");
    try writeU8(allocator, &out, c.v);
    try out.appendSlice(allocator, ",\"type\":\"chunk\",\"request_id\":");
    try writeJsonString(allocator, &out, c.request_id);
    try out.appendSlice(allocator, ",\"seq\":");
    var seq_buf: [16]u8 = undefined;
    const seq = try std.fmt.bufPrint(&seq_buf, "{d}", .{c.seq});
    try out.appendSlice(allocator, seq);
    try out.appendSlice(allocator, ",\"body\":");
    try writeRawJson(allocator, &out, c.body_json);
    try out.append(allocator, '}');
    return out.toOwnedSlice(allocator);
}

pub fn encodeComplete(allocator: std.mem.Allocator, c: Complete) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    defer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"v\":");
    try writeU8(allocator, &out, c.v);
    try out.appendSlice(allocator, ",\"type\":\"complete\",\"request_id\":");
    try writeJsonString(allocator, &out, c.request_id);
    if (c.err) |e| {
        try out.appendSlice(allocator, ",\"error\":");
        try writeErrorBody(allocator, &out, e);
    } else {
        try out.appendSlice(allocator, ",\"result\":");
        try writeRawJson(allocator, &out, c.result_json);
    }
    try out.append(allocator, '}');
    return out.toOwnedSlice(allocator);
}

fn writeU8(allocator: std.mem.Allocator, out: *std.ArrayList(u8), n: u8) !void {
    var buf: [4]u8 = undefined;
    const slice = try std.fmt.bufPrint(&buf, "{d}", .{n});
    try out.appendSlice(allocator, slice);
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

/// Append a raw JSON value (object, array, scalar, "null") verbatim.
/// If `s` is empty, defaults to `"null"` so the resulting envelope is
/// always valid JSON.  No validation here — that's the caller's job
/// (or the round-trip decoder will reject malformed input later).
fn writeRawJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    if (s.len == 0) {
        try out.appendSlice(allocator, "null");
    } else {
        try out.appendSlice(allocator, s);
    }
}

fn writeErrorBody(allocator: std.mem.Allocator, out: *std.ArrayList(u8), e: ErrorBody) !void {
    try out.appendSlice(allocator, "{\"kind\":");
    try writeJsonString(allocator, out, e.kind.toString());
    try out.appendSlice(allocator, ",\"message\":");
    try writeJsonString(allocator, out, e.message);
    try out.appendSlice(allocator, ",\"details\":");
    try writeRawJson(allocator, out, e.details_json);
    try out.append(allocator, '}');
}

// ─────────────────────────────────────────────────────────────────────
// Decoder — std.json.parseFromSlice → std.json.Value walk.
// ─────────────────────────────────────────────────────────────────────

pub fn decodeRequest(allocator: std.mem.Allocator, json: []const u8) WireError!OwnedRequest {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch
        return WireError.invalid_json;
    defer parsed.deinit();
    if (parsed.value != .object) return WireError.not_an_object;
    const obj = parsed.value.object;

    try checkVersion(obj);

    var bufs = OwnedBufs.init(allocator);
    errdefer bufs.deinit();

    const request_id = try dupString(&bufs, getStringField(obj, "request_id") orelse "");
    const resource = try dupString(&bufs, getStringField(obj, "resource") orelse return WireError.missing_field);
    const cmd = try dupString(&bufs, getStringField(obj, "cmd") orelse return WireError.missing_field);
    const args = try dupRawJson(&bufs, allocator, obj.get("args"));

    return .{
        .request = .{
            .v = ENVELOPE_VERSION,
            .request_id = request_id,
            .resource = resource,
            .cmd = cmd,
            .args_json = args,
        },
        .allocator = allocator,
        .bufs = bufs,
    };
}

pub fn decodeResponse(allocator: std.mem.Allocator, json: []const u8) WireError!OwnedResponse {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch
        return WireError.invalid_json;
    defer parsed.deinit();
    if (parsed.value != .object) return WireError.not_an_object;
    const obj = parsed.value.object;

    try checkVersion(obj);

    var bufs = OwnedBufs.init(allocator);
    errdefer bufs.deinit();

    const request_id = try dupString(&bufs, getStringField(obj, "request_id") orelse "");

    var err_body: ?ErrorBody = null;
    if (obj.get("error")) |err_v| {
        if (err_v != .null) {
            err_body = try decodeErrorBody(&bufs, allocator, err_v);
        }
    }

    var result_json: []const u8 = "null";
    if (err_body == null) {
        result_json = try dupRawJson(&bufs, allocator, obj.get("result"));
    }

    return .{
        .response = .{
            .v = ENVELOPE_VERSION,
            .request_id = request_id,
            .result_json = result_json,
            .err = err_body,
        },
        .allocator = allocator,
        .bufs = bufs,
    };
}

pub fn decodeChunk(allocator: std.mem.Allocator, json: []const u8) WireError!OwnedChunk {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch
        return WireError.invalid_json;
    defer parsed.deinit();
    if (parsed.value != .object) return WireError.not_an_object;
    const obj = parsed.value.object;

    try checkVersion(obj);
    if (getStringField(obj, "type")) |t| {
        if (!std.mem.eql(u8, t, "chunk")) return WireError.unknown_stream_envelope_type;
    }

    var bufs = OwnedBufs.init(allocator);
    errdefer bufs.deinit();

    const request_id = try dupString(&bufs, getStringField(obj, "request_id") orelse "");
    const seq_v = obj.get("seq") orelse return WireError.missing_field;
    if (seq_v != .integer) return WireError.wrong_type;
    if (seq_v.integer < 0) return WireError.wrong_type;
    const seq: u32 = @intCast(seq_v.integer);
    const body = try dupRawJson(&bufs, allocator, obj.get("body"));

    return .{
        .chunk = .{
            .v = ENVELOPE_VERSION,
            .request_id = request_id,
            .seq = seq,
            .body_json = body,
        },
        .allocator = allocator,
        .bufs = bufs,
    };
}

pub fn decodeComplete(allocator: std.mem.Allocator, json: []const u8) WireError!OwnedComplete {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch
        return WireError.invalid_json;
    defer parsed.deinit();
    if (parsed.value != .object) return WireError.not_an_object;
    const obj = parsed.value.object;

    try checkVersion(obj);
    if (getStringField(obj, "type")) |t| {
        if (!std.mem.eql(u8, t, "complete")) return WireError.unknown_stream_envelope_type;
    }

    var bufs = OwnedBufs.init(allocator);
    errdefer bufs.deinit();

    const request_id = try dupString(&bufs, getStringField(obj, "request_id") orelse "");

    var err_body: ?ErrorBody = null;
    if (obj.get("error")) |err_v| {
        if (err_v != .null) {
            err_body = try decodeErrorBody(&bufs, allocator, err_v);
        }
    }

    var result_json: []const u8 = "null";
    if (err_body == null) {
        result_json = try dupRawJson(&bufs, allocator, obj.get("result"));
    }

    return .{
        .complete = .{
            .v = ENVELOPE_VERSION,
            .request_id = request_id,
            .result_json = result_json,
            .err = err_body,
        },
        .allocator = allocator,
        .bufs = bufs,
    };
}

/// Decode a stream envelope by peeking at `type`.  Caller deinits the
/// returned wrapper.
pub fn decodeStreamEnvelope(allocator: std.mem.Allocator, json: []const u8) WireError!OwnedStreamEnvelope {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch
        return WireError.invalid_json;
    defer parsed.deinit();
    if (parsed.value != .object) return WireError.not_an_object;
    const obj = parsed.value.object;

    const t = getStringField(obj, "type") orelse return WireError.unknown_stream_envelope_type;
    if (std.mem.eql(u8, t, "chunk")) {
        var owned = try decodeChunk(allocator, json);
        // Move ownership of the bufs list into the union wrapper; clear
        // the inner so its deinit becomes a no-op.
        const bufs = owned.bufs;
        owned.bufs = OwnedBufs.init(allocator);
        return .{
            .envelope = .{ .chunk = owned.chunk },
            .allocator = owned.allocator,
            .bufs = bufs,
        };
    }
    if (std.mem.eql(u8, t, "complete")) {
        var owned = try decodeComplete(allocator, json);
        const bufs = owned.bufs;
        owned.bufs = OwnedBufs.init(allocator);
        return .{
            .envelope = .{ .complete = owned.complete },
            .allocator = owned.allocator,
            .bufs = bufs,
        };
    }
    return WireError.unknown_stream_envelope_type;
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

fn checkVersion(obj: std.json.ObjectMap) WireError!void {
    const v_val = obj.get("v") orelse return WireError.missing_field;
    if (v_val != .integer) return WireError.wrong_type;
    if (v_val.integer != ENVELOPE_VERSION) return WireError.unsupported_version;
}

fn getStringField(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    if (v != .string) return null;
    return v.string;
}

fn decodeErrorBody(bufs: *OwnedBufs, allocator: std.mem.Allocator, v: std.json.Value) WireError!ErrorBody {
    if (v != .object) return WireError.wrong_type;
    const eobj = v.object;
    const kind_str = getStringField(eobj, "kind") orelse return WireError.missing_field;
    const kind = ErrorKind.fromString(kind_str) orelse return WireError.unknown_error_kind;
    const message = try dupString(bufs, getStringField(eobj, "message") orelse "");
    const details = try dupRawJson(bufs, allocator, eobj.get("details"));
    return .{
        .kind = kind,
        .message = message,
        .details_json = details,
    };
}

/// Allocate a tracked copy of `s`.  Lifetime is the OwnedBufs's deinit.
fn dupString(bufs: *OwnedBufs, s: []const u8) WireError![]const u8 {
    const buf = bufs.allocator.dupe(u8, s) catch return WireError.out_of_memory;
    return try bufs.track(buf);
}

/// Canonicalise a JSON sub-value (or `null` if absent) into a tracked
/// raw-JSON byte slice.  Re-stringification through std.json yields a
/// byte-stable canonical form, so subsequent re-encodes are reproducible.
fn dupRawJson(bufs: *OwnedBufs, allocator: std.mem.Allocator, v: ?std.json.Value) WireError![]const u8 {
    const val = v orelse return try dupString(bufs, "null");
    const stringified = std.json.Stringify.valueAlloc(allocator, val, .{}) catch
        return WireError.out_of_memory;
    return try bufs.track(stringified);
}

// ─────────────────────────────────────────────────────────────────────
// Tests — pure logic.  Full conformance lives in
// tests/wire_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "ErrorKind round-trips through string" {
    const all = [_]ErrorKind{
        .unknown_resource, .unknown_command, .capability_denied,
        .validation_failed, .not_implemented,
    };
    for (all) |k| {
        const s = k.toString();
        try std.testing.expectEqual(@as(?ErrorKind, k), ErrorKind.fromString(s));
    }
    try std.testing.expectEqual(@as(?ErrorKind, null), ErrorKind.fromString("nope"));
}

```
