---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/attachments_upload_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.257989+00:00
---

# runtime/semantos-brain/src/attachments_upload_http.zig

```zig
// D-O5m.followup-8 capture+upload — Multipart upload endpoint for
// signed `oddjobz.attachment.v1` cells + their binary blobs.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5m (mobile sensor
//            adapters); apps/oddjobz-mobile/lib/src/attachments/
//            attachment_builder.dart (the producer side); apps/
//            oddjobz-mobile/lib/src/identity/cell_signer.dart (the
//            ECDSA signer the brain verifies); attachment_blobs_fs.zig
//            (the content-addressable blob store the verified blob
//            lands in); resources/attachments_handler.zig (the
//            metadata-cell store the verified payload lands in).
//
// Wire shape (request):
//
//     POST /api/v1/attachments/upload
//     Content-Type: multipart/form-data; boundary=<token>
//     Authorization: Bearer <hex64>      (helm session bearer)
//     Body:
//       --<boundary>
//       Content-Disposition: form-data; name="metadata"
//       Content-Type: application/json
//
//       {
//         "cell_payload": { ... oddjobz.attachment.v1 unsigned shape ... },
//         "signature_hex": "<128 hex>",
//         "captured_by_cert_id": "<32 hex>"
//       }
//       --<boundary>
//       Content-Disposition: form-data; name="blob"; filename="..."
//       Content-Type: application/octet-stream
//
//       <binary blob bytes>
//       --<boundary>--
//
// Wire shape (responses):
//
//     200 → {"id": "<uuid>", "status": "created" | "already_exists"}
//     400 → {"error": "hash_mismatch"}      // SHA256(blob) != cell.contentHash
//     400 → {"error": "payload_invalid_format"}
//     401 → {"error": "cert_unknown"}        // captured_by_cert_id not in CertStore
//     401 → {"error": "signature_invalid"}   // signature didn't recover the cert pubkey
//     401 → {"error": "bearer_invalid"}      // missing/bad bearer
//     404 → {"error": "visit_not_found", "visit_id": "..."}  // forwarded from handler
//     413 → {"error": "too_large"}           // blob > MAX_BLOB_BYTES
//     503 → {"error": "upload_backend_not_enabled"}
//
// Flow:
//   1. Validate bearer + extract.
//   2. Parse multipart body → {metadata_json, blob_bytes}.
//   3. Reject blob > MAX_BLOB_BYTES.
//   4. Parse metadata_json → {cell_payload, signature, captured_by_cert_id}.
//   5. Compute SHA256(blob_bytes) and assert it equals
//      cell_payload.contentHash; else 400.
//   6. Look up captured_by_cert_id in CertStore; else 401.
//   7. Re-canonicalise cell_payload (lexicographic-key JSON, no whitespace)
//      and verify signature recovers the cert's pubkey via the same
//      recovery-byte loop signed_bundle.zig::verifySignature uses.
//   8. Write blob via attachment_blobs_fs.write(contentHash, blob_bytes).
//   9. Stamp createdAt and call attachments_handler.handleCreateMetadata
//      via JSON args; return {id, status}.

const std = @import("std");
const bsvz = @import("bsvz");

const attachment_blobs_fs = @import("attachment_blobs_fs");
const attachments_store_fs = @import("attachments_store_fs");
const attachments_handler = @import("attachments_handler");
const visits_store_fs = @import("visits_store_fs");
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

/// Maximum blob size — 10 MiB.  Matches the operator-altitude SLO for
/// site photos (a HEIC photo from a flagship phone runs 2–5 MiB
/// typically; voice memos rarely exceed 1 MiB; the 10 MiB cap covers
/// the heavy-tail without inviting OOM attacks via a manually-crafted
/// upload).  Configurable via `Acceptor.max_blob_bytes` for tests.
pub const DEFAULT_MAX_BLOB_BYTES: usize = 10 * 1024 * 1024;

/// Maximum total request body size.  10 MiB blob + 16 KB metadata +
/// multipart framing overhead ≤ 10 MiB + 64 KB.  Cap at 10.1 MiB.
const MAX_BODY_BYTES: usize = 10 * 1024 * 1024 + 64 * 1024;

/// Path the route is mounted at.
pub const ROUTE_PATH: []const u8 = "/api/v1/attachments/upload";

/// Backend pointer set the route needs to discharge an upload.  The
/// daemon constructs this once at boot and attaches it to the
/// SiteServer; absence of any pointer disables the route (returns 503
/// per the wire shape).
pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    blobs: *const attachment_blobs_fs.BlobStore,
    attachments: *attachments_store_fs.AttachmentsStore,
    visits: ?*visits_store_fs.VisitsStore,
    certs: *identity_certs.CertStore,
    bearer_tokens: *bearer_tokens.TokenStore,
    /// Configurable per-request blob size cap.  Tests can lower this
    /// to exercise the 413 path without actually crafting 10 MiB
    /// payloads.  Production callers use DEFAULT_MAX_BLOB_BYTES.
    max_blob_bytes: usize = DEFAULT_MAX_BLOB_BYTES,
};

/// True when this request is the one the upload endpoint owns.  Same
/// shape as `device_pair_http.maybeHandle` — the dispatching seam is
/// in `site_server.zig`'s handleRequest.
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

    // Bearer check — same shape as repl_http.zig.
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

    // Read full body up to MAX_BODY_BYTES.
    const body_buf = acceptor.allocator.alloc(u8, MAX_BODY_BYTES) catch return Error.out_of_memory;
    defer acceptor.allocator.free(body_buf);
    const body = readBody(request, body_buf) catch {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\",\"hint\":\"failed to read body\"}");
        return true;
    };

    // Parse multipart parts.
    var parts = parseMultipart(acceptor.allocator, body, boundary) catch |err| switch (err) {
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

    const metadata_json = parts.metadata orelse {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing metadata part\"}");
        return true;
    };
    const blob_bytes = parts.blob orelse {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing blob part\"}");
        return true;
    };

    if (blob_bytes.len > acceptor.max_blob_bytes) {
        try respondJson(request, .payload_too_large, "{\"error\":\"too_large\"}");
        return true;
    }

    // Parse the metadata JSON into a typed struct.
    var meta = parseMetadata(acceptor.allocator, metadata_json) catch {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\"}");
        return true;
    };
    defer meta.deinit(acceptor.allocator);

    // 1. Hash check: SHA256(blob) must equal cell_payload.contentHash.
    var blob_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(blob_bytes, &blob_hash, .{});
    var blob_hash_hex: [64]u8 = undefined;
    bkds.hexEncode(&blob_hash, &blob_hash_hex);
    if (!std.mem.eql(u8, meta.content_hash, &blob_hash_hex)) {
        try respondJson(request, .bad_request, "{\"error\":\"hash_mismatch\"}");
        return true;
    }

    // 2. Cert lookup.
    const cert = acceptor.certs.get(meta.captured_by_cert_id) catch {
        try respondJson(request, .unauthorized, "{\"error\":\"cert_unknown\"}");
        return true;
    };

    // 3. Re-canonicalise the payload + verify signature.  We rebuild
    // the canonical bytes from the parsed JSON so a malicious sender
    // can't sneak extra whitespace into the preimage.  The brain's
    // canonicalisation rules match
    // cartridges/oddjobz/brain/src/cell-types/canonical-json.ts.
    const canonical_bytes = canonicaliseCellPayload(acceptor.allocator, meta.cell_payload_root) catch {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\",\"hint\":\"failed to canonicalise cell_payload\"}");
        return true;
    };
    defer acceptor.allocator.free(canonical_bytes);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(canonical_bytes, &digest, .{});

    if (!verifyCellSignatureRecoveryLoop(meta.signature, digest, cert.pubkey)) {
        try respondJson(request, .unauthorized, "{\"error\":\"signature_invalid\"}");
        return true;
    }

    // 4. Write the blob.  Idempotent on repeat — atomic rename.
    acceptor.blobs.write(&blob_hash_hex, blob_bytes) catch {
        try respondJson(request, .internal_server_error,
            "{\"error\":\"blob_write_failed\"}");
        return true;
    };

    // 5. Stamp createdAt + persist the metadata cell via the existing
    // `attachments.create_metadata` REPL-shape JSON args.  We
    // construct the args body inline (server-stamped createdAt is set
    // here so the canonical bytes the device signed don't include
    // it).
    const created_at = renderIsoTimestamp(acceptor.allocator, std.time.timestamp()) catch return Error.out_of_memory;
    defer acceptor.allocator.free(created_at);

    // Wire-shape note: we'd dispatch via the dispatcher seam to keep
    // the handler decoupled, but the typed `attachments.create_metadata`
    // entry point is reached via the handler's mutex-serialised
    // surface.  Construct a minimal call inline using the public
    // store + visits FK semantics that handleCreateMetadata uses.
    const create_result = createMetadataInline(acceptor, meta, created_at) catch |err| switch (err) {
        error.visit_not_found => {
            // Forward the typed payload — same shape attachments_handler
            // emits for the same condition.
            var resp_buf: std.ArrayList(u8) = .{};
            defer resp_buf.deinit(acceptor.allocator);
            try resp_buf.appendSlice(acceptor.allocator, "{\"error\":\"visit_not_found\",\"visit_id\":");
            try writeJsonString(acceptor.allocator, &resp_buf, meta.visit_id);
            try resp_buf.append(acceptor.allocator, '}');
            try respondJson(request, .not_found, resp_buf.items);
            return true;
        },
        error.attachment_id_in_use_with_different_contents => {
            try respondJson(request, .conflict,
                "{\"error\":\"attachment_id_in_use_with_different_contents\"}");
            return true;
        },
        else => {
            try respondJson(request, .internal_server_error,
                "{\"error\":\"store_error\"}");
            return true;
        },
    };

    var resp_buf: std.ArrayList(u8) = .{};
    defer resp_buf.deinit(acceptor.allocator);
    try resp_buf.appendSlice(acceptor.allocator, "{\"id\":");
    try writeJsonString(acceptor.allocator, &resp_buf, meta.attachment_id);
    try resp_buf.appendSlice(acceptor.allocator, ",\"status\":\"");
    try resp_buf.appendSlice(acceptor.allocator, switch (create_result) {
        .created => "created",
        .already_exists => "already_exists",
    });
    try resp_buf.appendSlice(acceptor.allocator, "\"}");
    try respondJson(request, .ok, resp_buf.items);
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// Multipart parsing
// ─────────────────────────────────────────────────────────────────────

const MultipartParts = struct {
    metadata: ?[]const u8 = null,
    blob: ?[]const u8 = null,

    pub fn deinit(self: *MultipartParts, allocator: std.mem.Allocator) void {
        // Slices borrow from the body buffer — no per-part free.
        _ = self;
        _ = allocator;
    }
};

/// Parse an HTTP multipart/form-data body.  Returns slices into the
/// input `body` (no allocations beyond bookkeeping).  Two parts are
/// recognised by their `name=` Content-Disposition value: `metadata`
/// (JSON) and `blob` (binary); other parts are ignored.  Tolerant
/// against trailing CRLF, missing terminator (some clients omit
/// `--<boundary>--`), and any header order.
pub fn parseMultipart(
    allocator: std.mem.Allocator,
    body: []const u8,
    boundary: []const u8,
) !MultipartParts {
    _ = allocator; // future-compat hook
    if (boundary.len == 0) return Error.boundary_missing;

    // Build the delimiter line: "--<boundary>".
    var delim_buf: [256]u8 = undefined;
    if (boundary.len + 2 > delim_buf.len) return Error.payload_invalid_format;
    delim_buf[0] = '-';
    delim_buf[1] = '-';
    @memcpy(delim_buf[2 .. 2 + boundary.len], boundary);
    const delim = delim_buf[0 .. 2 + boundary.len];

    var parts = MultipartParts{};
    // Find each occurrence of delim, walk the body part-by-part.
    var idx: usize = 0;
    while (idx < body.len) {
        const next = std.mem.indexOfPos(u8, body, idx, delim) orelse break;
        // Skip the delim line + its trailing CRLF.
        var cursor: usize = next + delim.len;
        // Tolerate `--<boundary>--` (terminator).
        if (cursor + 2 <= body.len and body[cursor] == '-' and body[cursor + 1] == '-') {
            break;
        }
        if (cursor + 2 <= body.len and body[cursor] == '\r' and body[cursor + 1] == '\n') {
            cursor += 2;
        } else if (cursor < body.len and body[cursor] == '\n') {
            cursor += 1;
        }
        if (cursor >= body.len) break;

        // Parse part headers — keep going until we see a blank line.
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

        // Extract `name="..."` from the Content-Disposition header.
        const headers_text = body[cursor..header_end.at];
        const part_name = parsePartName(headers_text);

        // Find the end of this part — next delim (preceded by CRLF).
        const next_delim = std.mem.indexOfPos(u8, body, header_end.body_start, delim) orelse body.len;
        // Strip trailing CRLF before the delim.
        var part_end = next_delim;
        if (part_end > 0 and body[part_end - 1] == '\n') part_end -= 1;
        if (part_end > 0 and body[part_end - 1] == '\r') part_end -= 1;
        const part_body = body[header_end.body_start..part_end];

        if (part_name) |name| {
            if (std.mem.eql(u8, name, "metadata")) {
                parts.metadata = part_body;
            } else if (std.mem.eql(u8, name, "blob")) {
                parts.blob = part_body;
            }
        }

        idx = next_delim;
    }

    return parts;
}

/// Pull the `name="..."` value out of part headers.  Returns null on
/// any malformed input.
fn parsePartName(headers_text: []const u8) ?[]const u8 {
    var line_it = std.mem.splitSequence(u8, headers_text, "\r\n");
    while (line_it.next()) |line| {
        if (!std.ascii.startsWithIgnoreCase(line, "content-disposition:")) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        // Look for `name="..."`.
        const name_idx = std.mem.indexOf(u8, value, "name=\"") orelse continue;
        const start = name_idx + "name=\"".len;
        const end_off = std.mem.indexOfScalarPos(u8, value, start, '"') orelse continue;
        return value[start..end_off];
    }
    return null;
}

/// Pull the `boundary=...` value out of a Content-Type header.
pub fn boundaryFromContentType(ct: []const u8) ?[]const u8 {
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
// Metadata parsing + canonicalisation
// ─────────────────────────────────────────────────────────────────────

/// Parsed metadata (slices into the underlying parsed-JSON arena —
/// freed on Metadata.deinit).
pub const Metadata = struct {
    arena: std.json.Parsed(std.json.Value),
    /// `cell_payload` sub-object — borrowed from `arena`.
    cell_payload_root: std.json.Value,
    attachment_id: []const u8,
    visit_id: []const u8,
    kind: []const u8,
    content_hash: []const u8,
    content_size: i64,
    mime_type: []const u8,
    captured_at: []const u8,
    captured_by_cert_id: []const u8,
    caption: []const u8,
    /// 64-byte (r||s) compact signature.
    signature: [64]u8,

    pub fn deinit(self: *Metadata, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.arena.deinit();
    }
};

pub fn parseMetadata(allocator: std.mem.Allocator, metadata_json: []const u8) !Metadata {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, metadata_json, .{});
    errdefer parsed.deinit();
    if (parsed.value != .object) return Error.payload_invalid_format;
    const obj = parsed.value.object;

    const sig_v = obj.get("signature_hex") orelse return Error.payload_invalid_format;
    if (sig_v != .string or sig_v.string.len != 128) return Error.payload_invalid_format;
    var sig: [64]u8 = undefined;
    bkds.hexDecode(sig_v.string, &sig) catch return Error.payload_invalid_format;

    const cci_v = obj.get("captured_by_cert_id") orelse return Error.payload_invalid_format;
    if (cci_v != .string or cci_v.string.len != 32) return Error.payload_invalid_format;
    if (!attachments_store_fs.isValidHex(cci_v.string, 32)) return Error.payload_invalid_format;

    const cp_v = obj.get("cell_payload") orelse return Error.payload_invalid_format;
    if (cp_v != .object) return Error.payload_invalid_format;
    const cp = cp_v.object;

    const aid_v = cp.get("attachmentId") orelse return Error.payload_invalid_format;
    if (aid_v != .string) return Error.payload_invalid_format;
    const vi_v = cp.get("visitId") orelse return Error.payload_invalid_format;
    if (vi_v != .string) return Error.payload_invalid_format;
    const k_v = cp.get("kind") orelse return Error.payload_invalid_format;
    if (k_v != .string) return Error.payload_invalid_format;
    const ch_v = cp.get("contentHash") orelse return Error.payload_invalid_format;
    if (ch_v != .string or ch_v.string.len != 64) return Error.payload_invalid_format;
    const cs_v = cp.get("contentSize") orelse return Error.payload_invalid_format;
    const cs: i64 = switch (cs_v) {
        .integer => |n| n,
        .float => |f| @intFromFloat(f),
        else => return Error.payload_invalid_format,
    };
    const mt_v = cp.get("mimeType") orelse return Error.payload_invalid_format;
    if (mt_v != .string) return Error.payload_invalid_format;
    const ca_v = cp.get("capturedAt") orelse return Error.payload_invalid_format;
    if (ca_v != .string) return Error.payload_invalid_format;
    const cci_inner = cp.get("capturedByCertId") orelse return Error.payload_invalid_format;
    if (cci_inner != .string) return Error.payload_invalid_format;
    if (!std.mem.eql(u8, cci_inner.string, cci_v.string)) {
        // The wrapper-level cert id MUST agree with the cell's cert
        // id; otherwise the brain might verify against a different
        // pubkey than the one the device claims signed.
        return Error.payload_invalid_format;
    }
    const caption: []const u8 = if (cp.get("caption")) |c| (if (c == .string) c.string else "") else "";

    return .{
        .arena = parsed,
        .cell_payload_root = cp_v,
        .attachment_id = aid_v.string,
        .visit_id = vi_v.string,
        .kind = k_v.string,
        .content_hash = ch_v.string,
        .content_size = cs,
        .mime_type = mt_v.string,
        .captured_at = ca_v.string,
        .captured_by_cert_id = cci_v.string,
        .caption = caption,
        .signature = sig,
    };
}

/// Re-canonicalise a parsed JSON value into the lexicographic-key,
/// no-whitespace UTF-8 form that the Dart attachment_builder produced.
/// Matches `cartridges/oddjobz/brain/src/cell-types/canonical-json.ts`
/// rules: sorted keys, no whitespace, standard JSON string escapes.
pub fn canonicaliseCellPayload(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    try writeCanonical(allocator, &out, value);
    return out.toOwnedSlice(allocator);
}

fn writeCanonical(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: std.json.Value) !void {
    switch (value) {
        .null => try out.appendSlice(allocator, "null"),
        .bool => |b| try out.appendSlice(allocator, if (b) "true" else "false"),
        .integer => |n| try out.print(allocator, "{d}", .{n}),
        .float => |f| try out.print(allocator, "{d}", .{f}),
        .number_string => |s| try out.appendSlice(allocator, s),
        .string => |s| try writeJsonString(allocator, out, s),
        .array => |arr| {
            try out.append(allocator, '[');
            for (arr.items, 0..) |item, i| {
                if (i != 0) try out.append(allocator, ',');
                try writeCanonical(allocator, out, item);
            }
            try out.append(allocator, ']');
        },
        .object => |obj| {
            // Sort keys lexicographically.
            var keys = try std.ArrayList([]const u8).initCapacity(allocator, obj.count());
            defer keys.deinit(allocator);
            var it = obj.iterator();
            while (it.next()) |entry| keys.appendAssumeCapacity(entry.key_ptr.*);
            std.mem.sort([]const u8, keys.items, {}, struct {
                fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.lessThan(u8, a, b);
                }
            }.lessThan);
            try out.append(allocator, '{');
            for (keys.items, 0..) |k, i| {
                if (i != 0) try out.append(allocator, ',');
                try writeJsonString(allocator, out, k);
                try out.append(allocator, ':');
                try writeCanonical(allocator, out, obj.get(k).?);
            }
            try out.append(allocator, '}');
        },
    }
}

// ─────────────────────────────────────────────────────────────────────
// Signature verification
// ─────────────────────────────────────────────────────────────────────

/// Recovery-loop ECDSA verifier.  Same scheme as
/// `signed_bundle.zig::verifySignature` minus the `SIG_DOMAIN` preimage
/// prefix — for cell-payload signatures the digest is just
/// SHA-256(canonical_bytes).
pub fn verifyCellSignatureRecoveryLoop(
    sig: [64]u8,
    digest: [32]u8,
    expected_pubkey: [bkds.KEY_LEN]u8,
) bool {
    var candidate: [65]u8 = undefined;
    @memcpy(candidate[1..65], &sig);
    var rec: u8 = 31;
    while (rec <= 34) : (rec += 1) {
        candidate[0] = rec;
        const recovered = bsvz.crypto.compact.recoverCompactDigest256(candidate, digest) catch continue;
        const recovered_sec1 = recovered.pubkey.toCompressedSec1();
        if (std.crypto.timing_safe.eql([bkds.KEY_LEN]u8, recovered_sec1, expected_pubkey)) return true;
    }
    return false;
}

/// C7-B Option A — verify an operator signature over a mint payload.
/// The signed preimage is `SHA-256(canonicaliseCellPayload(parse(payload_json)))`
/// — sorted-key canonical JSON, NO domain prefix (matches the PWA
/// `cell_signer.dart` scheme). `payload_json` is the brain's re-stringified
/// payload (the same bytes persisted in the cell); canonicalisation is
/// key-order-independent, so this agrees with the PWA's
/// canonicalise(payload) regardless of inbound key order. Returns false on
/// ANY parse/canonicalise failure — an unverifiable mint is a rejected mint.
pub fn verifyPayloadSignature(
    allocator: std.mem.Allocator,
    payload_json: []const u8,
    sig: [64]u8,
    expected_pubkey: [bkds.KEY_LEN]u8,
) bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const value = std.json.parseFromSliceLeaky(std.json.Value, a, payload_json, .{}) catch return false;
    const canonical = canonicaliseCellPayload(a, value) catch return false;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(canonical, &digest, .{});
    return verifyCellSignatureRecoveryLoop(sig, digest, expected_pubkey);
}

test "verifyPayloadSignature — round-trips a known operator signature" {
    const allocator = std.testing.allocator;
    const payload_json = "{\"rawText\":\"letting go\"}";

    // Compute the digest exactly as the verifier will.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const value = try std.json.parseFromSliceLeaky(std.json.Value, a, payload_json, .{});
    const canonical = try canonicaliseCellPayload(a, value);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(canonical, &digest, .{});

    // Known priv → sign → 64-byte r‖s (strip the recovery byte).
    const priv_bytes = [_]u8{0x11} ** 32;
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(priv_bytes);
    const pubkey = (try priv.publicKey()).toCompressedSec1();
    const compact = try priv.signCompact(digest, true);
    var sig: [64]u8 = undefined;
    @memcpy(&sig, compact[1..65]);

    try std.testing.expect(verifyPayloadSignature(allocator, payload_json, sig, pubkey));

    // Tamper with the signature → reject.
    var bad = sig;
    bad[0] ^= 0xff;
    try std.testing.expect(!verifyPayloadSignature(allocator, payload_json, bad, pubkey));

    // Wrong key → reject.
    const other_priv = try bsvz.primitives.ec.PrivateKey.fromBytes([_]u8{0x22} ** 32);
    const other_pub = (try other_priv.publicKey()).toCompressedSec1();
    try std.testing.expect(!verifyPayloadSignature(allocator, payload_json, sig, other_pub));
}

// ─────────────────────────────────────────────────────────────────────
// Attachment store insertion
// ─────────────────────────────────────────────────────────────────────

pub const InsertError = error{
    visit_not_found,
    attachment_id_in_use_with_different_contents,
    invalid_args,
    store_error,
    out_of_memory,
};

pub fn createMetadataInline(
    acceptor: *const Acceptor,
    meta: Metadata,
    created_at: []const u8,
) InsertError!attachments_store_fs.AttachmentsStore.AppendOutcome {
    // FK: visit_id must exist in visits store (when the handler was
    // wired with one).
    if (acceptor.visits) |vs| {
        if (vs.findById(meta.visit_id) == null) return InsertError.visit_not_found;
    }

    // Idempotent re-create posture mirrors attachments_handler.
    if (acceptor.attachments.findById(meta.attachment_id)) |existing| {
        const matches =
            std.mem.eql(u8, existing.visit_id, meta.visit_id) and
            std.mem.eql(u8, existing.kind, meta.kind) and
            std.mem.eql(u8, existing.content_hash, meta.content_hash) and
            existing.content_size == meta.content_size and
            std.mem.eql(u8, existing.mime_type, meta.mime_type) and
            std.mem.eql(u8, existing.captured_at, meta.captured_at) and
            std.mem.eql(u8, existing.captured_by_cert_id, meta.captured_by_cert_id) and
            std.mem.eql(u8, existing.caption, meta.caption);
        if (!matches) return InsertError.attachment_id_in_use_with_different_contents;
    }

    const att = attachments_store_fs.Attachment{
        .id = meta.attachment_id,
        .visit_id = meta.visit_id,
        .kind = meta.kind,
        .content_hash = meta.content_hash,
        .content_size = meta.content_size,
        .mime_type = meta.mime_type,
        .captured_at = meta.captured_at,
        .captured_by_cert_id = meta.captured_by_cert_id,
        .caption = meta.caption,
        .created_at = created_at,
    };
    const outcome = acceptor.attachments.append(att) catch return InsertError.store_error;
    return outcome;
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

pub fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

pub fn renderIsoTimestamp(allocator: std.mem.Allocator, unix_seconds: i64) ![]u8 {
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(unix_seconds) };
    const epoch_day = epoch_secs.getEpochDay();
    const day_secs = epoch_secs.getDaySeconds();
    const ymd = epoch_day.calculateYearDay();
    const month_day = ymd.calculateMonthDay();
    const year: u32 = ymd.year;
    const month: u8 = month_day.month.numeric();
    const day: u8 = month_day.day_index + 1;
    const hour: u8 = day_secs.getHoursIntoDay();
    const minute: u8 = day_secs.getMinutesIntoHour();
    const second: u8 = day_secs.getSecondsIntoMinute();
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{ year, month, day, hour, minute, second },
    );
}

// The createMetadataInline path bypasses the dispatcher and writes
// directly to the AttachmentsStore — buildHandlerArgs would shape the
// JSON args for a dispatcher dispatch instead.  Touch
// attachments_handler so the build graph keeps the dependency edge
// (we may migrate to a dispatcher dispatch in a future revision once
// the audit-log seam is wired in).
comptime {
    _ = attachments_handler.RESOURCE_NAME;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — multipart parser + canonicaliser + signature verifier.
// Full HTTP-layer conformance lives in
// tests/attachments_upload_http_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "boundaryFromContentType: extracts boundary token" {
    try std.testing.expectEqualStrings(
        "abc123",
        boundaryFromContentType("multipart/form-data; boundary=abc123") orelse return error.MissingBoundary,
    );
    try std.testing.expectEqualStrings(
        "abc",
        boundaryFromContentType("multipart/form-data; boundary=\"abc\"") orelse return error.MissingBoundary,
    );
    try std.testing.expect(boundaryFromContentType("multipart/form-data") == null);
}

test "parseMultipart: extracts metadata + blob parts" {
    const allocator = std.testing.allocator;
    const body =
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"metadata\"\r\n" ++
        "Content-Type: application/json\r\n" ++
        "\r\n" ++
        "{\"foo\":\"bar\"}\r\n" ++
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"blob\"; filename=\"x.bin\"\r\n" ++
        "Content-Type: application/octet-stream\r\n" ++
        "\r\n" ++
        "RAW\x00\x01BYTES\r\n" ++
        "--xyz--\r\n";
    var parts = try parseMultipart(allocator, body, "xyz");
    defer parts.deinit(allocator);
    try std.testing.expectEqualStrings("{\"foo\":\"bar\"}", parts.metadata.?);
    try std.testing.expectEqualStrings("RAW\x00\x01BYTES", parts.blob.?);
}

test "canonicaliseCellPayload: lexicographic keys, no whitespace" {
    const allocator = std.testing.allocator;
    const input =
        \\{"zebra":1,"alpha":"hi","mango":[1,2]}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    defer parsed.deinit();
    const out = try canonicaliseCellPayload(allocator, parsed.value);
    defer allocator.free(out);
    try std.testing.expectEqualStrings("{\"alpha\":\"hi\",\"mango\":[1,2],\"zebra\":1}", out);
}

test "verifyCellSignatureRecoveryLoop: rejects all-zero sig" {
    var sig: [64]u8 = [_]u8{0} ** 64;
    var digest: [32]u8 = [_]u8{0} ** 32;
    var pubkey: [bkds.KEY_LEN]u8 = [_]u8{0} ** bkds.KEY_LEN;
    pubkey[0] = 0x02;
    try std.testing.expect(!verifyCellSignatureRecoveryLoop(sig, digest, pubkey));
    _ = &sig;
    _ = &digest;
}

```
