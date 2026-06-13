---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/voice_extract_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.220546+00:00
---

# runtime/semantos-brain/src/voice_extract_http.zig

```zig
// D-O5m.followup-3 — Multipart voice-extract endpoint.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5m followup-3
//            (the voice → STT → brain-extraction → signed cell pipeline);
//            attachments_upload_http.zig (the sibling multipart endpoint
//            we mirror for cert + signature verification);
//            cartridges/oddjobz/brain/tools/voice-extract.ts (the bun shell-out
//            CLI that wraps runtime/intent/processIntent).
//
// Wire shape (request):
//
//     POST /api/v1/voice-extract
//     Content-Type: multipart/form-data; boundary=<token>
//     Authorization: Bearer <hex64>
//     Body parts:
//       --<boundary>
//       Content-Disposition: form-data; name="audio"; filename="..."
//       Content-Type: application/octet-stream
//
//       <raw audio bytes>
//       --<boundary>
//       Content-Disposition: form-data; name="transcript"
//
//       <signed Transcript JSON>
//       --<boundary>
//       Content-Disposition: form-data; name="metadata"
//
//       {"visit_id":"...","hat_context":"...","client_correlation_id":"..."}
//       --<boundary>
//       Content-Disposition: form-data; name="sir_candidate"  (Phase 2, optional)
//
//       <Intent JSON the on-device extractor produced>
//       --<boundary>--
//
// Phase 2: when `sir_candidate` is present the brain forwards it to
// the bun CLI as a separate file; the CLI skips its L0->L1 producer
// adapter and runs L2-L4 only.  When absent the CLI runs the Phase 1
// path against the transcript text alone.
//
// Wire shape (responses):
//
//     200 → IntentResult JSON the bun shell-out produced.
//     400 → {"error":"payload_invalid_format"}
//     401 → {"error":"bearer_invalid"}
//     401 → {"error":"signature_invalid"}
//     401 → {"error":"cert_unknown"}
//     413 → {"error":"too_large"}            (audio > MAX_BLOB_BYTES)
//     422 → {"error":"pipeline_failed", ...} (bun returned non-zero)
//     503 → {"error":"bun_unavailable"}      (acceptor not configured)
//
// Phase 2 ports the L1 SIR build on-device; Phase 3 ports the
// full L2-L4 gradient on-device -- at which point the shellout
// disappears.

const std = @import("std");
const bsvz = @import("bsvz");

const attachment_blobs_fs = @import("attachment_blobs_fs");
const attachments_upload_http = @import("attachments_upload_http");
const identity_certs = @import("identity_certs");
const bearer_tokens = @import("bearer_tokens");
const bkds = @import("bkds");

pub const Error = error{
    out_of_memory,
    OutOfMemory,
    write_failed,
    payload_invalid_format,
    boundary_missing,
    blob_too_large,
};

/// 5 MiB — ~60 seconds of compressed audio at typical bitrates.  Reject
/// larger uploads with 413 to bound the bun shellout's input size.
pub const DEFAULT_MAX_AUDIO_BYTES: usize = 5 * 1024 * 1024;

/// Total request body cap.  5 MiB blob + 64 KiB framing slack.
const MAX_BODY_BYTES: usize = 5 * 1024 * 1024 + 64 * 1024;

/// Path the route is mounted at.
pub const ROUTE_PATH: []const u8 = "/api/v1/voice-extract";

/// Pluggable shell-out — production wires it to a bun subprocess that
/// runs `cartridges/oddjobz/brain/tools/voice-extract.ts`.  Tests inject a
/// stub that returns a known IntentResult JSON without forking.
///
/// On success: writes the IntentResult JSON into `out` and returns it
/// as a slice.  On pipeline rejection: returns ShellError.pipeline_failed
/// after writing the rejection JSON into `out`.  On infrastructure
/// failure (bun missing, command timed out, etc.): returns
/// ShellError.bun_unavailable.
pub const ShellResult = union(enum) {
    success: []const u8,
    pipeline_rejected: []const u8,
};

pub const ShellError = error{
    bun_unavailable,
    pipeline_failed,
    out_of_memory,
};

pub const VoiceExtractShell = struct {
    ctx: *anyopaque,
    runFn: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        transcript_json: []const u8,
        metadata_json: []const u8,
        sir_candidate_json: ?[]const u8,
    ) ShellError![]u8,

    pub fn run(
        self: VoiceExtractShell,
        allocator: std.mem.Allocator,
        transcript_json: []const u8,
        metadata_json: []const u8,
        sir_candidate_json: ?[]const u8,
    ) ShellError![]u8 {
        return self.runFn(self.ctx, allocator, transcript_json, metadata_json, sir_candidate_json);
    }
};

/// Backend pointer set the route uses.  Construct in cmdServe; attach
/// to the SiteServer alongside the attachments_upload_acceptor.
pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    blobs: ?*const attachment_blobs_fs.BlobStore = null,
    certs: *identity_certs.CertStore,
    bearer_tokens: *bearer_tokens.TokenStore,
    shell: VoiceExtractShell,
    max_audio_bytes: usize = DEFAULT_MAX_AUDIO_BYTES,
};

/// True when this request is the one this endpoint owns.
pub fn maybeHandle(
    request: *std.http.Server.Request,
    acceptor: *const Acceptor,
) Error!bool {
    const target = request.head.target;
    const method = request.head.method;
    if (!std.mem.eql(u8, target, ROUTE_PATH)) return false;
    if (method != .POST) {
        try respondJson(request, .method_not_allowed,
            "{\"error\":\"method_not_allowed\",\"hint\":\"POST required\"}");
        return true;
    }

    const bearer = bearerFromHeaders(request) orelse {
        try respondJson(request, .unauthorized, "{\"error\":\"bearer_invalid\"}");
        return true;
    };
    _ = acceptor.bearer_tokens.verifyHex(bearer) catch {
        try respondJson(request, .unauthorized, "{\"error\":\"bearer_invalid\"}");
        return true;
    };

    const ct = headerValue(request, "content-type") orelse {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing content-type\"}");
        return true;
    };
    const boundary = boundaryFromContentType(ct) orelse {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing multipart boundary\"}");
        return true;
    };

    const body_buf = acceptor.allocator.alloc(u8, MAX_BODY_BYTES) catch return Error.out_of_memory;
    defer acceptor.allocator.free(body_buf);
    const body = readBody(request, body_buf) catch {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\",\"hint\":\"failed to read body\"}");
        return true;
    };

    var parts = parseVoiceMultipart(acceptor.allocator, body, boundary) catch |err| switch (err) {
        Error.boundary_missing,
        Error.payload_invalid_format,
        => {
            try respondJson(request, .bad_request,
                "{\"error\":\"payload_invalid_format\"}");
            return true;
        },
        Error.out_of_memory => return Error.out_of_memory,
        else => return err,
    };
    defer parts.deinit(acceptor.allocator);

    const audio_bytes = parts.audio orelse {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing audio part\"}");
        return true;
    };
    const transcript_json = parts.transcript orelse {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing transcript part\"}");
        return true;
    };
    const metadata_json = parts.metadata orelse {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing metadata part\"}");
        return true;
    };

    if (audio_bytes.len > acceptor.max_audio_bytes) {
        try respondJson(request, .payload_too_large, "{\"error\":\"too_large\"}");
        return true;
    }

    // Verify the signed transcript: parse, look up cert, verify
    // signature against canonical preimage.
    var verify = verifyTranscriptSignature(acceptor.allocator, acceptor.certs, transcript_json) catch |err| switch (err) {
        VerifyError.payload_invalid_format => {
            try respondJson(request, .bad_request,
                "{\"error\":\"payload_invalid_format\",\"hint\":\"transcript JSON malformed\"}");
            return true;
        },
        VerifyError.cert_unknown => {
            try respondJson(request, .unauthorized, "{\"error\":\"cert_unknown\"}");
            return true;
        },
        VerifyError.signature_invalid => {
            try respondJson(request, .unauthorized, "{\"error\":\"signature_invalid\"}");
            return true;
        },
        VerifyError.out_of_memory => return Error.out_of_memory,
    };
    defer verify.deinit(acceptor.allocator);

    // Optionally persist the audio blob (for audit) — Phase 1 keeps
    // this opt-in; production wiring sets `blobs` so the bytes flow
    // into the same content-addressable store the camera/voice-memo
    // capture uses.
    if (acceptor.blobs) |blobs| {
        var audio_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(audio_bytes, &audio_hash, .{});
        var audio_hash_hex: [64]u8 = undefined;
        bkds.hexEncode(&audio_hash, &audio_hash_hex);
        // Best-effort write — failure here doesn't abort the request;
        // the brain still runs the pipeline against the transcript.
        blobs.write(&audio_hash_hex, audio_bytes) catch {};
    }

    // Run the pipeline shell-out.  In Phase 3 this is replaced by an
    // on-device gradient; for Phase 1 the brain hosts processIntent.
    // Phase 2: when the phone shipped a sir_candidate the bun CLI
    // skips its L0->L1 producer; otherwise it runs the full pipeline.
    const intent_result = acceptor.shell.run(
        acceptor.allocator,
        transcript_json,
        metadata_json,
        parts.sir_candidate,
    ) catch |err| switch (err) {
        ShellError.bun_unavailable => {
            try respondJson(request, .service_unavailable,
                "{\"error\":\"bun_unavailable\"}");
            return true;
        },
        ShellError.pipeline_failed => {
            try respondJson(request, .unprocessable_entity,
                "{\"error\":\"pipeline_failed\"}");
            return true;
        },
        ShellError.out_of_memory => return Error.out_of_memory,
    };
    defer acceptor.allocator.free(intent_result);

    // Pass the IntentResult JSON straight through to the client.
    try respondJson(request, .ok, intent_result);
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// Multipart parsing (audio + transcript + metadata)
// ─────────────────────────────────────────────────────────────────────

pub const VoiceMultipartParts = struct {
    audio: ?[]const u8 = null,
    transcript: ?[]const u8 = null,
    metadata: ?[]const u8 = null,
    /// Phase 2 -- on-device extracted Intent JSON.  Optional; when
    /// present the brain forwards it to the bun CLI as
    /// `--sir-candidate <tmpfile>` and the CLI skips L0->L1.
    sir_candidate: ?[]const u8 = null,

    pub fn deinit(self: *VoiceMultipartParts, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub fn parseVoiceMultipart(
    allocator: std.mem.Allocator,
    body: []const u8,
    boundary: []const u8,
) !VoiceMultipartParts {
    _ = allocator;
    if (boundary.len == 0) return Error.boundary_missing;

    var delim_buf: [256]u8 = undefined;
    if (boundary.len + 2 > delim_buf.len) return Error.payload_invalid_format;
    delim_buf[0] = '-';
    delim_buf[1] = '-';
    @memcpy(delim_buf[2 .. 2 + boundary.len], boundary);
    const delim = delim_buf[0 .. 2 + boundary.len];

    var parts = VoiceMultipartParts{};
    var idx: usize = 0;
    while (idx < body.len) {
        const next = std.mem.indexOfPos(u8, body, idx, delim) orelse break;
        var cursor: usize = next + delim.len;
        if (cursor + 2 <= body.len and body[cursor] == '-' and body[cursor + 1] == '-') {
            break;
        }
        if (cursor + 2 <= body.len and body[cursor] == '\r' and body[cursor + 1] == '\n') {
            cursor += 2;
        } else if (cursor < body.len and body[cursor] == '\n') {
            cursor += 1;
        }
        if (cursor >= body.len) break;

        const HeaderEnd = struct { at: usize, body_start: usize };
        const header_end: HeaderEnd = blk: {
            var p = cursor;
            while (p < body.len) : (p += 1) {
                if (p + 3 < body.len and
                    body[p] == '\r' and body[p + 1] == '\n' and
                    body[p + 2] == '\r' and body[p + 3] == '\n')
                {
                    break :blk .{ .at = p, .body_start = p + 4 };
                }
                if (p + 1 < body.len and body[p] == '\n' and body[p + 1] == '\n') {
                    break :blk .{ .at = p, .body_start = p + 2 };
                }
            }
            return Error.payload_invalid_format;
        };

        const headers_text = body[cursor..header_end.at];
        const part_name = parsePartName(headers_text);

        const next_delim = std.mem.indexOfPos(u8, body, header_end.body_start, delim) orelse body.len;
        var part_end = next_delim;
        if (part_end > 0 and body[part_end - 1] == '\n') part_end -= 1;
        if (part_end > 0 and body[part_end - 1] == '\r') part_end -= 1;
        const part_body = body[header_end.body_start..part_end];

        if (part_name) |name| {
            if (std.mem.eql(u8, name, "audio")) {
                parts.audio = part_body;
            } else if (std.mem.eql(u8, name, "transcript")) {
                parts.transcript = part_body;
            } else if (std.mem.eql(u8, name, "metadata")) {
                parts.metadata = part_body;
            } else if (std.mem.eql(u8, name, "sir_candidate")) {
                parts.sir_candidate = part_body;
            }
        }

        idx = next_delim;
    }
    return parts;
}

fn parsePartName(headers_text: []const u8) ?[]const u8 {
    var line_it = std.mem.splitSequence(u8, headers_text, "\r\n");
    while (line_it.next()) |line| {
        if (!std.ascii.startsWithIgnoreCase(line, "content-disposition:")) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        const name_idx = std.mem.indexOf(u8, value, "name=\"") orelse continue;
        const start = name_idx + "name=\"".len;
        const end_off = std.mem.indexOfScalarPos(u8, value, start, '"') orelse continue;
        return value[start..end_off];
    }
    return null;
}

fn boundaryFromContentType(ct: []const u8) ?[]const u8 {
    const idx = std.mem.indexOf(u8, ct, "boundary=") orelse return null;
    var start = idx + "boundary=".len;
    if (start >= ct.len) return null;
    var end: usize = start;
    if (ct[start] == '"') {
        start += 1;
        end = start;
        while (end < ct.len and ct[end] != '"') : (end += 1) {}
    } else {
        end = start;
        while (end < ct.len and ct[end] != ';' and ct[end] != ' ' and ct[end] != '\r' and ct[end] != '\n') : (end += 1) {}
    }
    if (end <= start) return null;
    return ct[start..end];
}

// ─────────────────────────────────────────────────────────────────────
// Transcript signature verification
// ─────────────────────────────────────────────────────────────────────

pub const VerifyError = error{
    payload_invalid_format,
    cert_unknown,
    signature_invalid,
    out_of_memory,
};

pub const VerifiedTranscript = struct {
    arena: std.json.Parsed(std.json.Value),
    cert_id: []const u8,
    text: []const u8,

    pub fn deinit(self: *VerifiedTranscript, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.arena.deinit();
    }
};

/// Parse the JSON-encoded signed Transcript, recompute the canonical
/// preimage, and verify the 64-byte (r||s) compact signature against
/// the speaker's cert pubkey via the recovery-byte loop.
pub fn verifyTranscriptSignature(
    allocator: std.mem.Allocator,
    certs: *identity_certs.CertStore,
    transcript_json: []const u8,
) VerifyError!VerifiedTranscript {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, transcript_json, .{}) catch
        return VerifyError.payload_invalid_format;
    errdefer parsed.deinit();
    if (parsed.value != .object) return VerifyError.payload_invalid_format;
    const obj = parsed.value.object;

    const cert_id_v = obj.get("certId") orelse return VerifyError.payload_invalid_format;
    if (cert_id_v != .string) return VerifyError.payload_invalid_format;
    const cert_id = cert_id_v.string;

    const session_id_v = obj.get("sessionId") orelse return VerifyError.payload_invalid_format;
    if (session_id_v != .string) return VerifyError.payload_invalid_format;
    const text_v = obj.get("text") orelse return VerifyError.payload_invalid_format;
    if (text_v != .string) return VerifyError.payload_invalid_format;
    const seq_v = obj.get("sequence") orelse return VerifyError.payload_invalid_format;
    const seq: i64 = switch (seq_v) {
        .integer => |n| n,
        else => return VerifyError.payload_invalid_format,
    };
    const ts_v = obj.get("timestamp") orelse return VerifyError.payload_invalid_format;
    const ts: i64 = switch (ts_v) {
        .integer => |n| n,
        else => return VerifyError.payload_invalid_format,
    };

    const sig_v = obj.get("signature") orelse return VerifyError.payload_invalid_format;
    if (sig_v != .object) return VerifyError.payload_invalid_format;
    const sig_obj = sig_v.object;
    const sig_bytes_v = sig_obj.get("bytes") orelse return VerifyError.payload_invalid_format;
    if (sig_bytes_v != .string or sig_bytes_v.string.len != 128) return VerifyError.payload_invalid_format;
    var sig: [64]u8 = undefined;
    bkds.hexDecode(sig_bytes_v.string, &sig) catch return VerifyError.payload_invalid_format;
    const key_id_v = sig_obj.get("keyId") orelse return VerifyError.payload_invalid_format;
    if (key_id_v != .string) return VerifyError.payload_invalid_format;
    if (!std.mem.eql(u8, key_id_v.string, cert_id)) {
        return VerifyError.signature_invalid;
    }

    const cert = certs.get(cert_id) catch return VerifyError.cert_unknown;

    // Rebuild the canonical preimage server-side — sorted-keys JSON
    // matching `runtime/intent/src/voice/preimage.ts`'s
    // `canonicalTranscriptPreimage`.
    const preimage = canonicalTranscriptPreimage(
        allocator,
        cert_id,
        seq,
        session_id_v.string,
        text_v.string,
        ts,
    ) catch return VerifyError.out_of_memory;
    defer allocator.free(preimage);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(preimage, &digest, .{});

    if (!attachments_upload_http.verifyCellSignatureRecoveryLoop(sig, digest, cert.pubkey)) {
        return VerifyError.signature_invalid;
    }

    return VerifiedTranscript{
        .arena = parsed,
        .cert_id = cert_id,
        .text = text_v.string,
    };
}

/// Build the deterministic JSON-with-sorted-keys canonical preimage
/// that matches `runtime/intent/src/voice/preimage.ts`'s
/// `canonicalTranscriptPreimage`.  The cross-language fixture at
/// apps/oddjobz-mobile/test/fixtures/voice-session-fixture.json
/// asserts byte-identical output across Zig / TS / Dart.
pub fn canonicalTranscriptPreimage(
    allocator: std.mem.Allocator,
    cert_id: []const u8,
    sequence: i64,
    session_id: []const u8,
    text: []const u8,
    timestamp: i64,
) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"certId\":");
    try writeJsonString(allocator, &out, cert_id);
    try out.appendSlice(allocator, ",\"sequence\":");
    try out.writer(allocator).print("{d}", .{sequence});
    try out.appendSlice(allocator, ",\"sessionId\":");
    try writeJsonString(allocator, &out, session_id);
    try out.appendSlice(allocator, ",\"text\":");
    try writeJsonString(allocator, &out, text);
    try out.appendSlice(allocator, ",\"timestamp\":");
    try out.writer(allocator).print("{d}", .{timestamp});
    try out.append(allocator, '}');
    return out.toOwnedSlice(allocator);
}

// ─────────────────────────────────────────────────────────────────────
// HTTP plumbing helpers
// ─────────────────────────────────────────────────────────────────────

fn respondJson(request: *std.http.Server.Request, status: std.http.Status, body: []const u8) Error!void {
    request.respond(body, .{
        .status = status,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "cache-control", .value = "no-store" },
        },
    }) catch return Error.write_failed;
}

fn readBody(request: *std.http.Server.Request, out: []u8) ![]const u8 {
    const reader = request.readerExpectNone(out);
    const n = try reader.readSliceShort(out);
    return out[0..n];
}

fn headerValue(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var it = request.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
    }
    return null;
}

fn bearerFromHeaders(request: *std.http.Server.Request) ?[]const u8 {
    const authz = headerValue(request, "authorization") orelse return null;
    const prefix = "Bearer ";
    if (authz.len <= prefix.len) return null;
    if (!std.ascii.eqlIgnoreCase(authz[0..prefix.len], prefix)) return null;
    const tok = std.mem.trim(u8, authz[prefix.len..], " \t");
    if (tok.len != 64) return null;
    for (tok) |c| {
        const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
        if (!ok) return null;
    }
    return tok;
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

test "boundaryFromContentType: extracts boundary token" {
    try std.testing.expectEqualStrings(
        "abc123",
        boundaryFromContentType("multipart/form-data; boundary=abc123") orelse return error.MissingBoundary,
    );
}

test "parseVoiceMultipart: extracts audio + transcript + metadata" {
    const allocator = std.testing.allocator;
    const body =
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"audio\"; filename=\"v.bin\"\r\n" ++
        "Content-Type: application/octet-stream\r\n" ++
        "\r\n" ++
        "AUDIO\x00\x01" ++
        "\r\n" ++
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"transcript\"\r\n" ++
        "\r\n" ++
        "{\"text\":\"hi\"}" ++
        "\r\n" ++
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"metadata\"\r\n" ++
        "\r\n" ++
        "{\"visit_id\":\"v\"}" ++
        "\r\n" ++
        "--xyz--\r\n";
    var parts = try parseVoiceMultipart(allocator, body, "xyz");
    defer parts.deinit(allocator);
    try std.testing.expectEqualStrings("AUDIO\x00\x01", parts.audio.?);
    try std.testing.expectEqualStrings("{\"text\":\"hi\"}", parts.transcript.?);
    try std.testing.expectEqualStrings("{\"visit_id\":\"v\"}", parts.metadata.?);
}

test "canonicalTranscriptPreimage: matches the cross-language fixture" {
    const allocator = std.testing.allocator;
    // Same fields as apps/oddjobz-mobile/test/fixtures/voice-session-fixture.json.
    const cert_id =
        "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
    const session_id =
        "3eccc3980b76409822a386b519cf6d548be5f6bcafd28a606b9b143344135e30";
    const text = "job 12345 is invoiced";
    const expected =
        "{\"certId\":\"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\"," ++
        "\"sequence\":0," ++
        "\"sessionId\":\"3eccc3980b76409822a386b519cf6d548be5f6bcafd28a606b9b143344135e30\"," ++
        "\"text\":\"job 12345 is invoiced\"," ++
        "\"timestamp\":1762000001500}";
    const got = try canonicalTranscriptPreimage(
        allocator,
        cert_id,
        0,
        session_id,
        text,
        1762000001500,
    );
    defer allocator.free(got);
    try std.testing.expectEqualStrings(expected, got);
}

test "parseVoiceMultipart: Phase 2 — extracts sir_candidate when present" {
    const allocator = std.testing.allocator;
    const body =
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"audio\"; filename=\"v.bin\"\r\n" ++
        "Content-Type: application/octet-stream\r\n" ++
        "\r\n" ++
        "AUDIO\x00\x01" ++
        "\r\n" ++
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"transcript\"\r\n" ++
        "\r\n" ++
        "{\"text\":\"hi\"}" ++
        "\r\n" ++
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"metadata\"\r\n" ++
        "\r\n" ++
        "{\"visit_id\":\"v\"}" ++
        "\r\n" ++
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"sir_candidate\"\r\n" ++
        "\r\n" ++
        "{\"id\":\"i-001\",\"action\":\"invoice\"}" ++
        "\r\n" ++
        "--xyz--\r\n";
    var parts = try parseVoiceMultipart(allocator, body, "xyz");
    defer parts.deinit(allocator);
    try std.testing.expectEqualStrings("AUDIO\x00\x01", parts.audio.?);
    try std.testing.expectEqualStrings("{\"text\":\"hi\"}", parts.transcript.?);
    try std.testing.expectEqualStrings("{\"visit_id\":\"v\"}", parts.metadata.?);
    try std.testing.expectEqualStrings(
        "{\"id\":\"i-001\",\"action\":\"invoice\"}",
        parts.sir_candidate.?,
    );
}

test "parseVoiceMultipart: Phase 2 — sir_candidate absent stays null" {
    const allocator = std.testing.allocator;
    const body =
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"audio\"; filename=\"v.bin\"\r\n" ++
        "Content-Type: application/octet-stream\r\n" ++
        "\r\n" ++
        "AUDIO" ++
        "\r\n" ++
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"transcript\"\r\n" ++
        "\r\n" ++
        "{}" ++
        "\r\n" ++
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"metadata\"\r\n" ++
        "\r\n" ++
        "{}" ++
        "\r\n" ++
        "--xyz--\r\n";
    var parts = try parseVoiceMultipart(allocator, body, "xyz");
    defer parts.deinit(allocator);
    try std.testing.expect(parts.sir_candidate == null);
}

```
