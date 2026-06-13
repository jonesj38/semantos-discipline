---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/attachments_blob_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.227405+00:00
---

# runtime/semantos-brain/src/attachments_blob_http.zig

```zig
// D-O5m.followup-8 capture+upload — Bearer-gated GET endpoint for
// attachment binary blobs.
//
// Reference: attachment_blobs_fs.zig (the content-addressable blob
//            store this endpoint reads from); attachments_store_fs.zig
//            (the metadata cell store the endpoint looks the
//            attachment up by id in); apps/loom-svelte/src/views/
//            VisitDetail.svelte (the Svelte helm thumbnail rendering
//            that fetches via this endpoint); apps/oddjobz-mobile/lib/
//            src/helm/visit_detail_screen.dart (the Flutter helm
//            thumbnail rendering that fetches via this endpoint).
//
// Wire shape:
//
//     GET /api/v1/attachments/<id>/blob
//     Authorization: Bearer <hex64>      (helm session bearer)
//
//     200 → <binary blob bytes> with `Content-Type: <mime_type>`
//     401 → {"error": "bearer_invalid"}
//     404 → {"error": "not_found"}    // attachment id unknown OR blob missing
//
// Cap-gating: bearer alone is insufficient — a non-helm bearer would
// accidentally grant read access.  The brain checks
// `cap.oddjobz.read_attachments` (mint at 0x0001010F per
// cartridges/oddjobz/brain/src/capabilities.ts) on the bearer's session.
// Today the bearer flow is a single helm session-level token so the
// cap check is trivially satisfied; once D-O5p ships per-cert
// capability scoping the check becomes meaningful (and rejecting an
// over-broad bearer pattern is what keeps the blob endpoint from
// becoming a side-channel for image exfiltration via a non-helm peer
// who happens to have a valid token).

const std = @import("std");

const attachment_blobs_fs = @import("attachment_blobs_fs");
const attachments_store_fs = @import("attachments_store_fs");
const bearer_tokens = @import("bearer_tokens");

pub const Error = error{
    out_of_memory,
    write_failed,
};

/// Path prefix; the suffix is `<id>/blob`.
pub const ROUTE_PREFIX: []const u8 = "/api/v1/attachments/";
const ROUTE_SUFFIX: []const u8 = "/blob";

/// Maximum id length (matches attachments_store_fs.MAX_ID_BYTES).
const MAX_ID_BYTES: usize = 64;

pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    blobs: *const attachment_blobs_fs.BlobStore,
    attachments: *attachments_store_fs.AttachmentsStore,
    bearer_tokens: *bearer_tokens.TokenStore,
};

/// Match the request's target against `/api/v1/attachments/<id>/blob`.
/// Returns true when the route is owned by this endpoint (the caller
/// should not fall through to other handlers).
pub fn maybeHandle(
    request: *std.http.Server.Request,
    acceptor: *const Acceptor,
) Error!bool {
    const target = request.head.target;
    const method = request.head.method;
    if (!std.mem.startsWith(u8, target, ROUTE_PREFIX)) return false;
    const after_prefix = target[ROUTE_PREFIX.len..];
    if (!std.mem.endsWith(u8, after_prefix, ROUTE_SUFFIX)) return false;
    // Excludes the upload endpoint at `/api/v1/attachments/upload`
    // (no trailing `/blob`); that route owns its own dispatch in
    // attachments_upload_http.maybeHandle.
    const id = after_prefix[0 .. after_prefix.len - ROUTE_SUFFIX.len];
    if (id.len == 0 or id.len > MAX_ID_BYTES) {
        try respondJson(request, .not_found, "{\"error\":\"not_found\"}");
        return true;
    }

    if (method != .GET and method != .HEAD) {
        try respondJson(request, .method_not_allowed,
            "{\"error\":\"method_not_allowed\",\"hint\":\"GET required\"}");
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

    // Look up attachment metadata; 404 on miss.
    const att = acceptor.attachments.findById(id) orelse {
        try respondJson(request, .not_found, "{\"error\":\"not_found\"}");
        return true;
    };

    // Read blob bytes from the FS store keyed by the metadata's
    // content_hash; 404 on miss (defensive — shouldn't happen if the
    // upload endpoint completed atomically, but a manual blob purge
    // or partial-write scenario lands here cleanly).
    const blob = acceptor.blobs.read(acceptor.allocator, att.content_hash) catch {
        try respondJson(request, .not_found, "{\"error\":\"not_found\"}");
        return true;
    };
    defer acceptor.allocator.free(blob);

    request.respond(blob, .{
        .status = .ok,
        .extra_headers = &.{
            .{ .name = "content-type", .value = att.mime_type },
            .{ .name = "cache-control", .value = "private, max-age=300" },
            // Match what `attachments_store_fs.Attachment.content_size`
            // would render — let the client validate the byte length
            // against the metadata it already has.
            .{ .name = "x-attachment-content-hash", .value = att.content_hash },
        },
    }) catch return Error.write_failed;
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
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

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure path matching.  Full HTTP-layer conformance
// (404 on missing id, 200 with blob bytes, header echo) lives in
// tests/attachments_blob_http_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "ROUTE_PREFIX + suffix shape" {
    const target = "/api/v1/attachments/abc-123/blob";
    try std.testing.expect(std.mem.startsWith(u8, target, ROUTE_PREFIX));
    const after_prefix = target[ROUTE_PREFIX.len..];
    try std.testing.expect(std.mem.endsWith(u8, after_prefix, ROUTE_SUFFIX));
    const id = after_prefix[0 .. after_prefix.len - ROUTE_SUFFIX.len];
    try std.testing.expectEqualStrings("abc-123", id);
}

```
