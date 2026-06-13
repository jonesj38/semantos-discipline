---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/site_server/util.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.289910+00:00
---

# runtime/semantos-brain/src/site_server/util.zig

```zig
// Site-server utility helpers extracted from src/site_server.zig.
// Pure code motion: no behaviour change.
//
// Owns: setSocketTimeouts, hexDecode/hexNibble, HeaderStoreTracker,
// headerValue, clientAcceptsGzip, isSafeRelativeUrlPath,
// guessContentType.  All previously lived at the tail of
// site_server.zig as free fns / structs alongside the SiteServer
// struct definition.

const std = @import("std");
const header_store_mod = @import("header_store");
const runner_mod = @import("runner");

/// Set SO_RCVTIMEO and SO_SNDTIMEO on a socket fd.  Used by the
/// SiteServer accept loop so a stuck client can't block the worker
/// thread indefinitely in handleConnection, freeing the accept loop.
///
/// Public for conformance testing.
pub fn setSocketTimeouts(handle: std.posix.socket_t, secs: i64) !void {
    const tv = std.posix.timeval{ .sec = secs, .usec = 0 };
    const tv_bytes = std.mem.asBytes(&tv);
    try std.posix.setsockopt(handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, tv_bytes);
    try std.posix.setsockopt(handle, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, tv_bytes);
}

pub fn hexDecode(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return error.bad_length;
    for (0..out.len) |i| {
        const hi = try hexNibble(hex[i * 2]);
        const lo = try hexNibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
}

pub fn hexNibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => error.bad_hex,
    };
}

/// Adapter that exposes WH's HeaderStore as a `chain_tracker: anytype`
/// argument for `bsvz.spv.verifyBeef`. Keeps payment_verifier reusable
/// (tests can pass a mock tracker; production passes this).
pub const HeaderStoreTracker = struct {
    store: *const header_store_mod.HeaderStore,

    pub fn isValidRootForHeight(
        self: HeaderStoreTracker,
        root: anytype, // bsvz.crypto.Hash256 — taken as anytype to avoid the dep
        height: u32,
    ) !bool {
        const rec = self.store.getByHeight(height) orelse return false;
        const root_bytes: *const [32]u8 = &@field(root, "bytes");
        return std.mem.eql(u8, root_bytes, &rec.header.merkle_root);
    }
};

pub fn readBody(request: *std.http.Server.Request, out: []u8) ![]const u8 {
    // readerExpectNone returns *Io.Reader (no error union — it errors on
    // 100-continue paths via writeExpectContinue, which we skip).
    const reader = request.readerExpectNone(out);
    const n = reader.readSliceShort(out) catch |err| switch (err) {
        else => return err,
    };
    return out[0..n];
}

/// WSITE2.5 — read a (potentially large) request body for dynamic
/// dispatch.  Stack buffer first; spill to allocator if the body
/// exceeds the buffer.  Caps at `runner_mod.REQUEST_CAP` (4 MiB).
pub const DynamicBody = struct {
    bytes: []const u8,
    heap_alloc: bool,
};
pub const ReadBodyError = error{
    body_too_large,
    read_failed,
};
pub fn readDynamicBody(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    stack_buf: []u8,
) ReadBodyError!DynamicBody {
    const reader = request.readerExpectNone(stack_buf);
    const stack_n = reader.readSliceShort(stack_buf) catch return error.read_failed;
    if (stack_n < stack_buf.len) {
        return .{ .bytes = stack_buf[0..stack_n], .heap_alloc = false };
    }
    var heap = std.ArrayList(u8){};
    heap.appendSlice(allocator, stack_buf[0..stack_n]) catch return error.read_failed;
    errdefer heap.deinit(allocator);
    var chunk: [16 * 1024]u8 = undefined;
    while (heap.items.len < runner_mod.REQUEST_CAP) {
        const got = reader.readSliceShort(&chunk) catch return error.read_failed;
        if (got == 0) break;
        if (heap.items.len + got > runner_mod.REQUEST_CAP) return error.body_too_large;
        heap.appendSlice(allocator, chunk[0..got]) catch return error.read_failed;
        if (got < chunk.len) break;
    }
    return .{
        .bytes = heap.toOwnedSlice(allocator) catch return error.read_failed,
        .heap_alloc = true,
    };
}

pub fn headerValue(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var it = request.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
    }
    return null;
}

/// D-W1 Phase 3 — does the client's Accept-Encoding list include gzip?
///
/// Conservative parser: scans the comma-separated list for the literal
/// token `gzip` (case-insensitive), ignoring q-values.  A client that
/// sent `Accept-Encoding: gzip;q=0` is technically saying "I don't want
/// gzip" — we'd serve the .gz anyway in that edge case, but the only
/// real-world generator of `q=0` is a manual curl test, and the cost
/// of misreading that is "the client gets a gzipped response and has
/// to decompress" which every browser will do silently.  Worth the
/// simplicity.
pub fn clientAcceptsGzip(request: *std.http.Server.Request) bool {
    var it = request.iterateHeaders();
    while (it.next()) |h| {
        if (!std.ascii.eqlIgnoreCase(h.name, "Accept-Encoding")) continue;
        var token_it = std.mem.splitScalar(u8, h.value, ',');
        while (token_it.next()) |raw| {
            const trimmed = std.mem.trim(u8, raw, " \t");
            // Strip q-value (`gzip;q=0.5` → `gzip`).
            const semi = std.mem.indexOfScalar(u8, trimmed, ';');
            const tok = if (semi) |s| std.mem.trim(u8, trimmed[0..s], " \t") else trimmed;
            if (std.ascii.eqlIgnoreCase(tok, "gzip")) return true;
        }
    }
    return false;
}

/// True if `rest` is a safe relative URL path that cannot escape a
/// site's root via `..` traversal or NUL injection.  The check is
/// pessimistic — it rejects anything ambiguous.  Caller still joins it
/// against the route's `root`.
pub fn isSafeRelativeUrlPath(rest: []const u8) bool {
    // Leading slash → would resolve to absolute under join on POSIX.
    if (rest.len > 0 and rest[0] == '/') return false;
    // No NUL bytes, no backslashes.
    for (rest) |c| {
        if (c == 0) return false;
        if (c == '\\') return false;
    }
    // Walk slash-separated segments; reject any `..`.
    var it = std.mem.splitScalar(u8, rest, '/');
    while (it.next()) |seg| {
        if (std.mem.eql(u8, seg, "..")) return false;
    }
    return true;
}

/// Crude content-type sniff by extension. Enough for the static-page +
/// CSS + JS + image set most v0.1 sites need; richer mime detection
/// lands in WSITE2.5.
pub fn guessContentType(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (std.mem.eql(u8, ext, ".html")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, ".htm")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, ".css")) return "text/css; charset=utf-8";
    if (std.mem.eql(u8, ext, ".js")) return "application/javascript; charset=utf-8";
    if (std.mem.eql(u8, ext, ".json")) return "application/json; charset=utf-8";
    if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml";
    if (std.mem.eql(u8, ext, ".png")) return "image/png";
    if (std.mem.eql(u8, ext, ".jpg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, ".jpeg")) return "image/jpeg";
    if (std.mem.eql(u8, ext, ".gif")) return "image/gif";
    if (std.mem.eql(u8, ext, ".ico")) return "image/x-icon";
    if (std.mem.eql(u8, ext, ".txt")) return "text/plain; charset=utf-8";
    if (std.mem.eql(u8, ext, ".wasm")) return "application/wasm";
    // D-O5 — extra MIME hints for the SPA bundle Vite emits.
    if (std.mem.eql(u8, ext, ".mjs")) return "application/javascript; charset=utf-8";
    if (std.mem.eql(u8, ext, ".map")) return "application/json; charset=utf-8";
    if (std.mem.eql(u8, ext, ".webp")) return "image/webp";
    if (std.mem.eql(u8, ext, ".woff")) return "font/woff";
    if (std.mem.eql(u8, ext, ".woff2")) return "font/woff2";
    if (std.mem.eql(u8, ext, ".ttf")) return "font/ttf";
    return "application/octet-stream";
}

```
