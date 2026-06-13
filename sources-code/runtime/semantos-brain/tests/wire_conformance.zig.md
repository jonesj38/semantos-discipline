---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/wire_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.182933+00:00
---

# runtime/semantos-brain/tests/wire_conformance.zig

```zig
// Phase D-W1 / Phase 0 — wire envelope codec conformance tests.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §6, §9.
//
// Coverage:
//   • Round-trip every envelope shape (Request, Response success,
//     Response failure, Chunk, Complete) — encode → decode → fields
//     match.
//   • Optional-fields-missing / unknown-fields-ignored on decode
//     (forward-compat).
//   • Large bodies + empty bodies don't break the codec.
//   • Streaming: a `chunk + chunk + complete` sequence decodes in
//     order; chunks have monotonically increasing seq; the complete
//     envelope terminates the stream.
//   • Malformed JSON returns `error.invalid_json`.
//   • Unknown error `kind` returns `error.unknown_error_kind`.
//   • Unsupported `v` returns `error.unsupported_version`.
//   • Stream envelope with unknown `type` returns
//     `error.unknown_stream_envelope_type`.
//
// The tests treat `*_json` payload fields as opaque JSON byte slices
// — std.json's canonical re-stringification means `{"a":1}` and
// `{ "a": 1 }` round-trip to the same bytes after decode.

const std = @import("std");
const wire = @import("wire");

// ─────────────────────────────────────────────────────────────────────
// Request round-trip
// ─────────────────────────────────────────────────────────────────────

test "wire: Request round-trip preserves all fields" {
    const allocator = std.testing.allocator;
    const original = wire.Request{
        .request_id = "req-9f8a-1",
        .resource = "bearer_tokens",
        .cmd = "issue",
        .args_json = "{\"label\":\"helm-dev\",\"ttl_seconds\":86400}",
    };
    const encoded = try wire.encodeRequest(allocator, original);
    defer allocator.free(encoded);

    var decoded = try wire.decodeRequest(allocator, encoded);
    defer decoded.deinit();
    try std.testing.expectEqual(wire.ENVELOPE_VERSION, decoded.request.v);
    try std.testing.expectEqualStrings("req-9f8a-1", decoded.request.request_id);
    try std.testing.expectEqualStrings("bearer_tokens", decoded.request.resource);
    try std.testing.expectEqualStrings("issue", decoded.request.cmd);
    // Args is canonicalised on decode — expect the same JSON value, not
    // necessarily identical bytes.  std.json's canonical formatter is
    // deterministic, so the second encode is byte-stable.
    const re_encoded = try wire.encodeRequest(allocator, decoded.request);
    defer allocator.free(re_encoded);
    var re_decoded = try wire.decodeRequest(allocator, re_encoded);
    defer re_decoded.deinit();
    try std.testing.expectEqualStrings(decoded.request.args_json, re_decoded.request.args_json);
}

test "wire: Request decodes with empty optional request_id" {
    const allocator = std.testing.allocator;
    const json =
        \\{"v":1,"resource":"x","cmd":"y","args":null}
    ;
    var decoded = try wire.decodeRequest(allocator, json);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("", decoded.request.request_id);
    try std.testing.expectEqualStrings("x", decoded.request.resource);
    try std.testing.expectEqualStrings("y", decoded.request.cmd);
}

test "wire: Request unknown top-level fields are ignored" {
    const allocator = std.testing.allocator;
    const json =
        \\{"v":1,"resource":"x","cmd":"y","args":null,"future_field":"ignored","another":[1,2,3]}
    ;
    var decoded = try wire.decodeRequest(allocator, json);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("x", decoded.request.resource);
}

test "wire: Request missing required field returns missing_field" {
    const allocator = std.testing.allocator;
    const json =
        \\{"v":1,"resource":"x"}
    ;
    try std.testing.expectError(
        wire.WireError.missing_field,
        wire.decodeRequest(allocator, json),
    );
}

test "wire: Request with empty args_json encodes as null" {
    const allocator = std.testing.allocator;
    const original = wire.Request{
        .resource = "x",
        .cmd = "y",
        .args_json = "",
    };
    const encoded = try wire.encodeRequest(allocator, original);
    defer allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\"args\":null") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Response success round-trip
// ─────────────────────────────────────────────────────────────────────

test "wire: Response success round-trip" {
    const allocator = std.testing.allocator;
    const original = wire.Response{
        .request_id = "req-1",
        .result_json = "{\"id\":\"4e51d201bf42\",\"token\":\"85f36690a3fa\",\"expires_at\":1778148499}",
    };
    const encoded = try wire.encodeResponse(allocator, original);
    defer allocator.free(encoded);

    var decoded = try wire.decodeResponse(allocator, encoded);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("req-1", decoded.response.request_id);
    try std.testing.expect(decoded.response.err == null);
    try std.testing.expect(decoded.response.result_json.len > 0);
    // Field-level semantic equality
    try std.testing.expect(std.mem.indexOf(u8, decoded.response.result_json, "85f36690a3fa") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Response failure round-trip — every typed kind
// ─────────────────────────────────────────────────────────────────────

test "wire: Response error round-trip for every kind" {
    const allocator = std.testing.allocator;
    const all = [_]wire.ErrorKind{
        .unknown_resource, .unknown_command, .capability_denied,
        .validation_failed, .not_implemented,
    };
    for (all) |kind| {
        const original = wire.Response{
            .request_id = "req-err",
            .err = .{
                .kind = kind,
                .message = "human readable",
                .details_json = "{\"hint\":\"check the cap\"}",
            },
        };
        const encoded = try wire.encodeResponse(allocator, original);
        defer allocator.free(encoded);
        var decoded = try wire.decodeResponse(allocator, encoded);
        defer decoded.deinit();
        try std.testing.expect(decoded.response.err != null);
        try std.testing.expectEqual(kind, decoded.response.err.?.kind);
        try std.testing.expectEqualStrings("human readable", decoded.response.err.?.message);
        try std.testing.expect(std.mem.indexOf(u8, decoded.response.err.?.details_json, "check the cap") != null);
    }
}

test "wire: Response error with null details defaults to literal null" {
    const allocator = std.testing.allocator;
    const json =
        \\{"v":1,"request_id":"r","error":{"kind":"capability_denied","message":"nope","details":null}}
    ;
    var decoded = try wire.decodeResponse(allocator, json);
    defer decoded.deinit();
    try std.testing.expect(decoded.response.err != null);
    try std.testing.expectEqualStrings("null", decoded.response.err.?.details_json);
}

test "wire: Response with unknown error kind returns typed error" {
    const allocator = std.testing.allocator;
    const json =
        \\{"v":1,"request_id":"r","error":{"kind":"made_up","message":"x","details":null}}
    ;
    try std.testing.expectError(
        wire.WireError.unknown_error_kind,
        wire.decodeResponse(allocator, json),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Chunk + Complete (streaming)
// ─────────────────────────────────────────────────────────────────────

test "wire: Chunk round-trip" {
    const allocator = std.testing.allocator;
    const original = wire.Chunk{
        .request_id = "stream-1",
        .seq = 5,
        .body_json = "{\"line\":\"abc\"}",
    };
    const encoded = try wire.encodeChunk(allocator, original);
    defer allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\"type\":\"chunk\"") != null);

    var decoded = try wire.decodeChunk(allocator, encoded);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(u32, 5), decoded.chunk.seq);
    try std.testing.expect(std.mem.indexOf(u8, decoded.chunk.body_json, "abc") != null);
}

test "wire: Complete with success result round-trip" {
    const allocator = std.testing.allocator;
    const original = wire.Complete{
        .request_id = "stream-1",
        .result_json = "{\"total\":10}",
    };
    const encoded = try wire.encodeComplete(allocator, original);
    defer allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\"type\":\"complete\"") != null);

    var decoded = try wire.decodeComplete(allocator, encoded);
    defer decoded.deinit();
    try std.testing.expect(decoded.complete.err == null);
    try std.testing.expect(std.mem.indexOf(u8, decoded.complete.result_json, "10") != null);
}

test "wire: Complete with error round-trip" {
    const allocator = std.testing.allocator;
    const original = wire.Complete{
        .request_id = "stream-1",
        .err = .{
            .kind = .validation_failed,
            .message = "partial",
        },
    };
    const encoded = try wire.encodeComplete(allocator, original);
    defer allocator.free(encoded);
    var decoded = try wire.decodeComplete(allocator, encoded);
    defer decoded.deinit();
    try std.testing.expect(decoded.complete.err != null);
    try std.testing.expectEqual(wire.ErrorKind.validation_failed, decoded.complete.err.?.kind);
}

test "wire: streaming sequence — chunks in order, complete terminates" {
    const allocator = std.testing.allocator;

    // Synthetic stream: three chunks then a complete.
    const tokens = [_][]const u8{ "alpha", "beta", "gamma" };
    var encoded_frames: [4][]u8 = undefined;
    for (tokens, 0..) |tok, i| {
        var body_buf: [64]u8 = undefined;
        const body = try std.fmt.bufPrint(&body_buf, "{{\"tok\":\"{s}\"}}", .{tok});
        encoded_frames[i] = try wire.encodeChunk(allocator, .{
            .request_id = "stream-x",
            .seq = @intCast(i),
            .body_json = body,
        });
    }
    encoded_frames[3] = try wire.encodeComplete(allocator, .{
        .request_id = "stream-x",
        .result_json = "{\"final_count\":3}",
    });
    defer for (encoded_frames) |f| allocator.free(f);

    // Decode each in order via the union decoder.  Chunks must arrive
    // with monotonically increasing seq; the complete envelope must
    // terminate the loop.
    var seen_complete = false;
    var last_seq: i64 = -1;
    for (encoded_frames) |frame| {
        var owned = try wire.decodeStreamEnvelope(allocator, frame);
        defer owned.deinit();
        switch (owned.envelope) {
            .chunk => |c| {
                try std.testing.expect(@as(i64, c.seq) > last_seq);
                last_seq = c.seq;
                try std.testing.expect(!seen_complete);
            },
            .complete => |_| {
                seen_complete = true;
            },
        }
    }
    try std.testing.expect(seen_complete);
    try std.testing.expectEqual(@as(i64, 2), last_seq);
}

test "wire: malformed JSON in chunk returns invalid_json" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        wire.WireError.invalid_json,
        wire.decodeChunk(allocator, "{not even json"),
    );
}

test "wire: stream envelope with unknown type returns typed error" {
    const allocator = std.testing.allocator;
    const json =
        \\{"v":1,"type":"nope","request_id":"x"}
    ;
    try std.testing.expectError(
        wire.WireError.unknown_stream_envelope_type,
        wire.decodeStreamEnvelope(allocator, json),
    );
}

test "wire: chunk envelope decoded as complete returns typed error" {
    const allocator = std.testing.allocator;
    const original = wire.Chunk{ .request_id = "x", .seq = 0, .body_json = "null" };
    const encoded = try wire.encodeChunk(allocator, original);
    defer allocator.free(encoded);
    try std.testing.expectError(
        wire.WireError.unknown_stream_envelope_type,
        wire.decodeComplete(allocator, encoded),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Edge cases
// ─────────────────────────────────────────────────────────────────────

test "wire: large body bodies round-trip" {
    const allocator = std.testing.allocator;
    // Build a 4KB args object: {"k0":"v0", ...}
    var args: std.ArrayList(u8) = .{};
    defer args.deinit(allocator);
    try args.append(allocator, '{');
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        if (i > 0) try args.append(allocator, ',');
        var pair_buf: [64]u8 = undefined;
        const pair = try std.fmt.bufPrint(&pair_buf, "\"k{d}\":\"v{d}\"", .{ i, i });
        try args.appendSlice(allocator, pair);
    }
    try args.append(allocator, '}');

    const original = wire.Request{
        .request_id = "big",
        .resource = "files",
        .cmd = "write",
        .args_json = args.items,
    };
    const encoded = try wire.encodeRequest(allocator, original);
    defer allocator.free(encoded);
    var decoded = try wire.decodeRequest(allocator, encoded);
    defer decoded.deinit();
    try std.testing.expect(std.mem.indexOf(u8, decoded.request.args_json, "k0") != null);
    try std.testing.expect(std.mem.indexOf(u8, decoded.request.args_json, "k99") != null);
}

test "wire: empty body chunks round-trip" {
    const allocator = std.testing.allocator;
    const original = wire.Chunk{ .request_id = "empty", .seq = 0, .body_json = "{}" };
    const encoded = try wire.encodeChunk(allocator, original);
    defer allocator.free(encoded);
    var decoded = try wire.decodeChunk(allocator, encoded);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("{}", decoded.chunk.body_json);
}

test "wire: unsupported version returns typed error" {
    const allocator = std.testing.allocator;
    const json =
        \\{"v":2,"resource":"x","cmd":"y","args":null}
    ;
    try std.testing.expectError(
        wire.WireError.unsupported_version,
        wire.decodeRequest(allocator, json),
    );
}

test "wire: top-level non-object returns typed error" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        wire.WireError.not_an_object,
        wire.decodeRequest(allocator, "[1,2,3]"),
    );
}

```
