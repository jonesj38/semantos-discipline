---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/audio_extract_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.260351+00:00
---

# runtime/semantos-brain/src/audio_extract_http.zig

```zig
// Betterment voice — multipart audio-extract endpoint types + parser.
//
// Sibling of image_extract_http.zig: the betterment cartridge runs on the
// Flutter PWA (no on-device inference), so a recorded voice note bounces to the
// brain, which transcribes it SERVER-SIDE via whisper.cpp and returns the text
// as chronological ReleaseTurns — the voice equivalent of OCR.
//
// Bearer-only, no API key (whisper runs locally on the brain host). The live
// request path is the reactor: see reactorHandleAudioExtract.
//
// Wire shape (request):
//     POST /api/v1/audio-extract
//     Content-Type: multipart/form-data; boundary=<token>
//     Authorization: Bearer <hex64>
//     Body parts: one `audio` part (16kHz mono WAV) + optional `metadata`.
//
// Wire shape (responses):
//     200 → ExtractResult JSON (turns + rawText) from the bun shell-out.
//     400 → {"error":"payload_invalid_format"}
//     401 → {"error":"bearer_invalid"}
//     413 → {"error":"too_large"}            (audio > max_audio_bytes)
//     422 → {"error":"pipeline_failed"}      (whisper failed / non-zero exit)
//     503 → {"error":"bun_unavailable"}      (acceptor wired but bun missing)

const std = @import("std");
const bearer_tokens = @import("bearer_tokens");

pub const Error = error{
    out_of_memory,
    OutOfMemory,
    payload_invalid_format,
    boundary_missing,
};

/// 16 MiB — a few minutes of 16kHz mono 16-bit WAV (~1.9 MiB/min).
pub const DEFAULT_MAX_AUDIO_BYTES: usize = 16 * 1024 * 1024;

pub const ROUTE_PATH: []const u8 = "/api/v1/audio-extract";

pub const ShellError = error{
    bun_unavailable,
    pipeline_failed,
    out_of_memory,
};

/// Pluggable shell-out — production wires it to a bun subprocess running
/// cartridges/betterment/brain/tools/audio-extract.ts (→ whisper.cpp).
pub const AudioExtractShell = struct {
    ctx: *anyopaque,
    runFn: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        audio_bytes: []const u8,
        metadata_json: ?[]const u8,
    ) ShellError![]u8,

    pub fn run(
        self: AudioExtractShell,
        allocator: std.mem.Allocator,
        audio_bytes: []const u8,
        metadata_json: ?[]const u8,
    ) ShellError![]u8 {
        return self.runFn(self.ctx, allocator, audio_bytes, metadata_json);
    }
};

pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    bearer_tokens: *bearer_tokens.TokenStore,
    shell: AudioExtractShell,
    max_audio_bytes: usize = DEFAULT_MAX_AUDIO_BYTES,
};

// ─────────────────────────────────────────────────────────────────────
// Multipart parsing (single audio part + optional metadata)
// ─────────────────────────────────────────────────────────────────────

pub const AudioMultipartParts = struct {
    audio: ?[]const u8 = null,
    metadata: ?[]const u8 = null,

    pub fn deinit(self: *AudioMultipartParts, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub fn parseAudioMultipart(
    allocator: std.mem.Allocator,
    body: []const u8,
    boundary: []const u8,
) Error!AudioMultipartParts {
    _ = allocator;
    if (boundary.len == 0) return Error.boundary_missing;

    var delim_buf: [256]u8 = undefined;
    if (boundary.len + 2 > delim_buf.len) return Error.payload_invalid_format;
    delim_buf[0] = '-';
    delim_buf[1] = '-';
    @memcpy(delim_buf[2 .. 2 + boundary.len], boundary);
    const delim = delim_buf[0 .. 2 + boundary.len];

    var parts = AudioMultipartParts{};
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
            } else if (std.mem.eql(u8, name, "metadata")) {
                parts.metadata = part_body;
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

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

test "parseAudioMultipart: extracts audio + metadata" {
    const allocator = std.testing.allocator;
    const body =
        "--b\r\n" ++
        "Content-Disposition: form-data; name=\"audio\"; filename=\"v.wav\"\r\n" ++
        "Content-Type: audio/wav\r\n" ++
        "\r\n" ++
        "RIFF\x00\x01" ++
        "\r\n" ++
        "--b\r\n" ++
        "Content-Disposition: form-data; name=\"metadata\"\r\n" ++
        "\r\n" ++
        "{\"day\":\"2026-06-11\"}" ++
        "\r\n" ++
        "--b--\r\n";
    var parts = try parseAudioMultipart(allocator, body, "b");
    defer parts.deinit(allocator);
    try std.testing.expectEqualStrings("RIFF\x00\x01", parts.audio.?);
    try std.testing.expectEqualStrings("{\"day\":\"2026-06-11\"}", parts.metadata.?);
}

test "parseAudioMultipart: audio only, metadata stays null" {
    const allocator = std.testing.allocator;
    const body =
        "--b\r\n" ++
        "Content-Disposition: form-data; name=\"audio\"; filename=\"v.wav\"\r\n" ++
        "\r\n" ++
        "WAVDATA" ++
        "\r\n" ++
        "--b--\r\n";
    var parts = try parseAudioMultipart(allocator, body, "b");
    defer parts.deinit(allocator);
    try std.testing.expectEqualStrings("WAVDATA", parts.audio.?);
    try std.testing.expect(parts.metadata == null);
}

```
