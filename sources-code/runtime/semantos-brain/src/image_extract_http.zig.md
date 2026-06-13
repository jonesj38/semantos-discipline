---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/image_extract_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.213641+00:00
---

# runtime/semantos-brain/src/image_extract_http.zig

```zig
// Betterment OCR — multipart image-extract endpoint types + parser.
//
// Mirror of voice_extract_http.zig, simplified: bearer-only (NO cert /
// signature verification — release photos are not device-signed this pass),
// and the multipart body carries one or more `image` parts (+ optional
// `metadata`) instead of audio + signed transcript.
//
// The live request path is the reactor: see
// runtime/semantos-brain/src/site_server/reactor.zig `reactorHandleImageExtract`.
// This module provides the shared types (Acceptor, ImageExtractShell,
// ShellError, ImageInput) and the multipart parser the reactor calls.  There is
// no std.http `maybeHandle` (voice's is dead code — nothing calls it).
//
// Wire shape (request):
//
//     POST /api/v1/image-extract
//     Content-Type: multipart/form-data; boundary=<token>
//     Authorization: Bearer <hex64>
//     Body parts (1..MAX_PAGES `image` parts, optional `metadata`):
//       --<boundary>
//       Content-Disposition: form-data; name="image"; filename="page1.jpg"
//       Content-Type: image/jpeg
//
//       <raw image bytes>
//       --<boundary>
//       Content-Disposition: form-data; name="metadata"
//
//       {"day":"2026-06-10","client_correlation_id":"..."}
//       --<boundary>--
//
// Wire shape (responses):
//     200 → ExtractResult JSON the bun shell-out produced (turns + rawText).
//     400 → {"error":"payload_invalid_format"}
//     401 → {"error":"bearer_invalid"}
//     413 → {"error":"too_large"}            (an image > max_image_bytes, or > MAX_PAGES)
//     422 → {"error":"pipeline_failed"}      (bun returned non-zero — incl. missing API key)
//     503 → {"error":"bun_unavailable"}      (acceptor wired but bun missing)

const std = @import("std");
const bearer_tokens = @import("bearer_tokens");

pub const Error = error{
    out_of_memory,
    OutOfMemory,
    payload_invalid_format,
    boundary_missing,
};

/// 4 MiB per image — the Flutter client downscales so a page stays well under
/// this; larger uploads are rejected with 413.
pub const DEFAULT_MAX_IMAGE_BYTES: usize = 4 * 1024 * 1024;

/// Max number of `image` parts accepted in one request (multi-page release).
pub const MAX_PAGES: usize = 4;

pub const ROUTE_PATH: []const u8 = "/api/v1/image-extract";

/// One decoded image part: raw bytes + its declared MIME type.
pub const ImageInput = struct {
    bytes: []const u8,
    media_type: []const u8,
};

pub const ShellError = error{
    bun_unavailable,
    pipeline_failed,
    out_of_memory,
};

/// Pluggable shell-out — production wires it to a bun subprocess running
/// cartridges/betterment/brain/tools/image-extract.ts.  Tests inject a stub.
pub const ImageExtractShell = struct {
    ctx: *anyopaque,
    runFn: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        images: []const ImageInput,
        metadata_json: ?[]const u8,
        // BYOK overrides (per-request, never persisted). When api_key is non-null
        // the subprocess runs with ANTHROPIC_API_KEY set to it; otherwise it
        // inherits the brain's own env. model selects the vision model.
        api_key: ?[]const u8,
        model: ?[]const u8,
    ) ShellError![]u8,

    pub fn run(
        self: ImageExtractShell,
        allocator: std.mem.Allocator,
        images: []const ImageInput,
        metadata_json: ?[]const u8,
        api_key: ?[]const u8,
        model: ?[]const u8,
    ) ShellError![]u8 {
        return self.runFn(self.ctx, allocator, images, metadata_json, api_key, model);
    }
};

/// Backend pointer set the route uses.  Construct in cmdServe; attach to the
/// SiteServer.  Bearer-only — no cert store (unlike voice-extract).
pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    bearer_tokens: *bearer_tokens.TokenStore,
    shell: ImageExtractShell,
    max_image_bytes: usize = DEFAULT_MAX_IMAGE_BYTES,
    max_pages: usize = MAX_PAGES,
};

// ─────────────────────────────────────────────────────────────────────
// Multipart parsing (1..N image parts + optional metadata)
// ─────────────────────────────────────────────────────────────────────

pub const ImageMultipartParts = struct {
    images: std.ArrayList(ImageInput) = .{},
    metadata: ?[]const u8 = null,
    /// BYOK overrides (optional multipart fields). Secrets — never logged/persisted.
    api_key: ?[]const u8 = null,
    model: ?[]const u8 = null,

    pub fn deinit(self: *ImageMultipartParts, allocator: std.mem.Allocator) void {
        self.images.deinit(allocator);
    }
};

pub fn parseImageMultipart(
    allocator: std.mem.Allocator,
    body: []const u8,
    boundary: []const u8,
) Error!ImageMultipartParts {
    if (boundary.len == 0) return Error.boundary_missing;

    var delim_buf: [256]u8 = undefined;
    if (boundary.len + 2 > delim_buf.len) return Error.payload_invalid_format;
    delim_buf[0] = '-';
    delim_buf[1] = '-';
    @memcpy(delim_buf[2 .. 2 + boundary.len], boundary);
    const delim = delim_buf[0 .. 2 + boundary.len];

    var parts = ImageMultipartParts{};
    errdefer parts.images.deinit(allocator);

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
            if (std.mem.eql(u8, name, "image")) {
                const media_type = parsePartContentType(headers_text) orelse "image/jpeg";
                parts.images.append(allocator, .{ .bytes = part_body, .media_type = media_type }) catch
                    return Error.out_of_memory;
            } else if (std.mem.eql(u8, name, "metadata")) {
                parts.metadata = part_body;
            } else if (std.mem.eql(u8, name, "api_key")) {
                if (part_body.len > 0) parts.api_key = part_body;
            } else if (std.mem.eql(u8, name, "model")) {
                if (part_body.len > 0) parts.model = part_body;
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

fn parsePartContentType(headers_text: []const u8) ?[]const u8 {
    var line_it = std.mem.splitSequence(u8, headers_text, "\r\n");
    while (line_it.next()) |line| {
        if (!std.ascii.startsWithIgnoreCase(line, "content-type:")) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        return std.mem.trim(u8, line[colon + 1 ..], " \t");
    }
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

test "parseImageMultipart: single image + metadata" {
    const allocator = std.testing.allocator;
    const body =
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"image\"; filename=\"p1.jpg\"\r\n" ++
        "Content-Type: image/jpeg\r\n" ++
        "\r\n" ++
        "IMG\x00\x01" ++
        "\r\n" ++
        "--xyz\r\n" ++
        "Content-Disposition: form-data; name=\"metadata\"\r\n" ++
        "\r\n" ++
        "{\"day\":\"2026-06-10\"}" ++
        "\r\n" ++
        "--xyz--\r\n";
    var parts = try parseImageMultipart(allocator, body, "xyz");
    defer parts.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), parts.images.items.len);
    try std.testing.expectEqualStrings("IMG\x00\x01", parts.images.items[0].bytes);
    try std.testing.expectEqualStrings("image/jpeg", parts.images.items[0].media_type);
    try std.testing.expectEqualStrings("{\"day\":\"2026-06-10\"}", parts.metadata.?);
}

test "parseImageMultipart: multiple image parts collected in order" {
    const allocator = std.testing.allocator;
    const body =
        "--b\r\n" ++
        "Content-Disposition: form-data; name=\"image\"; filename=\"1.png\"\r\n" ++
        "Content-Type: image/png\r\n" ++
        "\r\n" ++
        "PAGE1" ++
        "\r\n" ++
        "--b\r\n" ++
        "Content-Disposition: form-data; name=\"image\"; filename=\"2.webp\"\r\n" ++
        "Content-Type: image/webp\r\n" ++
        "\r\n" ++
        "PAGE2" ++
        "\r\n" ++
        "--b--\r\n";
    var parts = try parseImageMultipart(allocator, body, "b");
    defer parts.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), parts.images.items.len);
    try std.testing.expectEqualStrings("PAGE1", parts.images.items[0].bytes);
    try std.testing.expectEqualStrings("image/png", parts.images.items[0].media_type);
    try std.testing.expectEqualStrings("PAGE2", parts.images.items[1].bytes);
    try std.testing.expectEqualStrings("image/webp", parts.images.items[1].media_type);
    try std.testing.expect(parts.metadata == null);
}

test "parseImageMultipart: extracts optional api_key + model fields" {
    const allocator = std.testing.allocator;
    const body =
        "--b\r\n" ++
        "Content-Disposition: form-data; name=\"image\"; filename=\"1.jpg\"\r\n" ++
        "Content-Type: image/jpeg\r\n" ++
        "\r\n" ++
        "IMG" ++
        "\r\n" ++
        "--b\r\n" ++
        "Content-Disposition: form-data; name=\"api_key\"\r\n" ++
        "\r\n" ++
        "sk-byok-xyz" ++
        "\r\n" ++
        "--b\r\n" ++
        "Content-Disposition: form-data; name=\"model\"\r\n" ++
        "\r\n" ++
        "claude-haiku-4-5" ++
        "\r\n" ++
        "--b--\r\n";
    var parts = try parseImageMultipart(allocator, body, "b");
    defer parts.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), parts.images.items.len);
    try std.testing.expectEqualStrings("sk-byok-xyz", parts.api_key.?);
    try std.testing.expectEqualStrings("claude-haiku-4-5", parts.model.?);
}

test "parseImageMultipart: api_key + model absent stay null" {
    const allocator = std.testing.allocator;
    const body =
        "--b\r\n" ++
        "Content-Disposition: form-data; name=\"image\"; filename=\"1.jpg\"\r\n" ++
        "\r\n" ++
        "IMG" ++
        "\r\n" ++
        "--b--\r\n";
    var parts = try parseImageMultipart(allocator, body, "b");
    defer parts.deinit(allocator);
    try std.testing.expect(parts.api_key == null);
    try std.testing.expect(parts.model == null);
}

test "parseImageMultipart: missing content-type defaults to jpeg" {
    const allocator = std.testing.allocator;
    const body =
        "--b\r\n" ++
        "Content-Disposition: form-data; name=\"image\"; filename=\"x\"\r\n" ++
        "\r\n" ++
        "RAW" ++
        "\r\n" ++
        "--b--\r\n";
    var parts = try parseImageMultipart(allocator, body, "b");
    defer parts.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), parts.images.items.len);
    try std.testing.expectEqualStrings("image/jpeg", parts.images.items[0].media_type);
}

```
