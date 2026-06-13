---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/headers_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.447853+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/headers_http.zig

```zig
// Phase WH-Producer phase 2 — BHS-compatible HTTP endpoints over an
// FsHeaderStore.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §3 ("Default
// Source — provided by BRAIN `headers serve` (no Go service)").
//
// The browser bundle's `cartridges/wallet-headers/brain/src/header-source-adapter.ts`
// expects four endpoints:
//
//   GET /api/v1/chain/header/range?from=N&to=M
//                 → application/octet-stream, concatenated 80-byte
//                   raw headers from height N..M inclusive
//
//   GET /api/v1/chain/header/byHeight/{h}
//                 → application/octet-stream, single 80-byte raw header
//                   at height `h`
//
//   GET /api/v1/chain/header/byHeight/tip
//                 → application/json, {"height": N}
//                   (the BHS adapter follows up with a byHeight call to
//                    get the raw bytes — we keep that contract)
//
//   GET /api/v1/chain/header/byHash/{hashHex}
//                 → application/octet-stream, single 80-byte raw header
//                   matching the display-form hash
//
// All endpoints read from a borrowed `header_store.HeaderStore` —
// production passes the FsHeaderStore the tip-subscription thread is
// appending to; tests pass a LocalHeaderStore.  No mutation here; the
// HTTP surface is read-only.
//
// Single-threaded request loop (same shape as site_server.zig).
// Operators wanting concurrency front this with Caddy or run multiple
// processes behind a load balancer.

const std = @import("std");
const headers_mod = @import("headers");
const header_store_mod = @import("header_store");

pub const ServerError = error{
    listen_failed,
    out_of_memory,
};

pub const HeadersHttp = struct {
    allocator: std.mem.Allocator,
    store: *const header_store_mod.HeaderStore,
    port: u16,
    /// Optional mutex shared with the sync thread. When non-null, each
    /// request locks before reading the store and unlocks after.
    mutex: ?*std.Thread.Mutex = null,

    pub fn init(allocator: std.mem.Allocator, store: *const header_store_mod.HeaderStore, port: u16) HeadersHttp {
        return .{ .allocator = allocator, .store = store, .port = port };
    }

    /// Block-listen until error or `cancel.load(.acquire) == true`.
    pub fn serve(self: *HeadersHttp, cancel: ?*const std.atomic.Value(bool)) !void {
        const addr = try std.net.Address.parseIp4("0.0.0.0", self.port);
        var listener = try addr.listen(.{ .reuse_address = true });
        defer listener.deinit();

        while (true) {
            if (cancel) |c| {
                if (c.load(.acquire)) return;
            }
            const conn = listener.accept() catch |err| switch (err) {
                error.ProcessFdQuotaExceeded,
                error.SystemFdQuotaExceeded,
                => continue,
                else => return err,
            };
            self.handleConnection(conn) catch {
                // Per-connection failures are non-fatal.
            };
        }
    }

    fn handleConnection(self: *HeadersHttp, conn: std.net.Server.Connection) !void {
        defer conn.stream.close();

        var read_buf: [8192]u8 = undefined;
        var write_buf: [16384]u8 = undefined;
        var read_iface = conn.stream.reader(&read_buf);
        var write_iface = conn.stream.writer(&write_buf);
        var server = std.http.Server.init(read_iface.interface(), &write_iface.interface);

        while (true) {
            var request = server.receiveHead() catch |err| switch (err) {
                error.HttpConnectionClosing => return,
                else => return err,
            };
            try self.handleRequest(&request);
            if (!request.head.keep_alive) return;
        }
    }

    /// Drive a single request from a synthetic `*std.http.Server.Request`.
    /// Production calls this from the listen loop; tests call
    /// `composeResponse(method, target, store, allocator)` directly to
    /// skip the std.http surface (constructing a synthetic Request is
    /// painful + tied to internal state).
    pub fn handleRequest(self: *HeadersHttp, request: *std.http.Server.Request) !void {
        if (self.mutex) |m| m.lock();
        const resp = try composeResponse(self.allocator, self.store, request.head.method, request.head.target);
        if (self.mutex) |m| m.unlock();
        defer freeResponse(self.allocator, resp);
        const headers = [_]std.http.Header{
            .{ .name = "content-type", .value = resp.content_type },
        };
        request.respond(resp.body, .{ .status = resp.status, .extra_headers = &headers }) catch {};
    }
};

/// Synthetic response shape — what the dispatcher emits to the HTTP
/// surface.  `body` is allocator-owned; caller frees via `freeResponse`.
pub const Response = struct {
    status: std.http.Status,
    content_type: []const u8,
    body: []const u8,
    body_owned: bool,
};

pub fn freeResponse(allocator: std.mem.Allocator, resp: Response) void {
    if (resp.body_owned and resp.body.len > 0) allocator.free(resp.body);
}

/// Pure-function dispatcher — tests drive this directly.  Returns a
/// `Response` whose `body` may be either a string literal (when
/// `body_owned == false`) or allocator-owned bytes (when true).
pub fn composeResponse(
    allocator: std.mem.Allocator,
    store: *const header_store_mod.HeaderStore,
    method: std.http.Method,
    target: []const u8,
) !Response {
    if (method != .GET and method != .HEAD) {
        return literal(.method_not_allowed, "text/plain; charset=utf-8", "405 Method Not Allowed\n");
    }

    const qmark = std.mem.indexOfScalar(u8, target, '?');
    const path = if (qmark) |i| target[0..i] else target;
    const query = if (qmark) |i| target[i + 1 ..] else "";

    if (std.mem.eql(u8, path, "/api/v1/chain/header/byHeight/tip")) {
        return composeTip(allocator, store);
    }
    const by_height_prefix = "/api/v1/chain/header/byHeight/";
    if (std.mem.startsWith(u8, path, by_height_prefix)) {
        const tail = path[by_height_prefix.len..];
        const h = std.fmt.parseInt(u32, tail, 10) catch {
            return literal(.bad_request, "text/plain; charset=utf-8", "400 Bad Request — height must be u32\n");
        };
        return composeByHeight(allocator, store, h);
    }
    const by_hash_prefix = "/api/v1/chain/header/byHash/";
    if (std.mem.startsWith(u8, path, by_hash_prefix)) {
        const tail = path[by_hash_prefix.len..];
        return composeByHash(allocator, store, tail);
    }
    if (std.mem.eql(u8, path, "/api/v1/chain/header/range")) {
        return composeRange(allocator, store, query);
    }
    return literal(.not_found, "text/plain; charset=utf-8", "404 Not Found\n");
}

fn literal(status: std.http.Status, ctype: []const u8, body: []const u8) Response {
    return .{ .status = status, .content_type = ctype, .body = body, .body_owned = false };
}

fn composeTip(allocator: std.mem.Allocator, store: *const header_store_mod.HeaderStore) !Response {
    const tip = store.tip() orelse {
        // Empty store — serve a clear "not yet" instead of 404 so the
        // browser fetcher can distinguish "source down" from "source
        // has no headers yet".
        return literal(.ok, "application/json; charset=utf-8", "{\"height\":0,\"empty\":true}");
    };
    var hash_hex: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (tip.hash, 0..) |b, i| {
        const dst = 31 - i;
        hash_hex[dst * 2] = hex_chars[(b >> 4) & 0xf];
        hash_hex[dst * 2 + 1] = hex_chars[b & 0xf];
    }
    const body = try std.fmt.allocPrint(allocator, "{{\"height\":{d},\"hash\":\"{s}\"}}", .{ tip.height, hash_hex[0..] });
    return .{
        .status = .ok,
        .content_type = "application/json; charset=utf-8",
        .body = body,
        .body_owned = true,
    };
}

fn composeByHeight(allocator: std.mem.Allocator, store: *const header_store_mod.HeaderStore, h: u32) !Response {
    const rec = store.getByHeight(h) orelse {
        return literal(.not_found, "text/plain; charset=utf-8", "404 Not Found — no header at that height\n");
    };
    const buf = try allocator.alloc(u8, headers_mod.HEADER_BYTES);
    const ptr: *[80]u8 = @ptrCast(buf.ptr);
    rec.header.serialize(ptr);
    return .{
        .status = .ok,
        .content_type = "application/octet-stream",
        .body = buf,
        .body_owned = true,
    };
}

fn composeByHash(allocator: std.mem.Allocator, store: *const header_store_mod.HeaderStore, hash_hex: []const u8) !Response {
    if (hash_hex.len != 64) {
        return literal(.bad_request, "text/plain; charset=utf-8", "400 Bad Request — hash must be 64 hex chars\n");
    }
    var hash_display: [32]u8 = undefined;
    decodeHex(hash_hex, &hash_display) catch {
        return literal(.bad_request, "text/plain; charset=utf-8", "400 Bad Request — invalid hex\n");
    };
    // Wallet sends display-form (BE); internal store keys on
    // wire/internal LE.  Reverse on the way in.
    var hash_internal: [32]u8 = undefined;
    for (0..32) |i| hash_internal[i] = hash_display[31 - i];

    const rec = store.getByHash(&hash_internal) orelse {
        return literal(.not_found, "text/plain; charset=utf-8", "404 Not Found — no header with that hash\n");
    };
    const buf = try allocator.alloc(u8, headers_mod.HEADER_BYTES);
    const ptr: *[80]u8 = @ptrCast(buf.ptr);
    rec.header.serialize(ptr);
    return .{
        .status = .ok,
        .content_type = "application/octet-stream",
        .body = buf,
        .body_owned = true,
    };
}

fn composeRange(allocator: std.mem.Allocator, store: *const header_store_mod.HeaderStore, query: []const u8) !Response {
    var from_opt: ?u32 = null;
    var to_opt: ?u32 = null;
    var iter = std.mem.tokenizeScalar(u8, query, '&');
    while (iter.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        const key = pair[0..eq];
        const val = pair[eq + 1 ..];
        const v = std.fmt.parseInt(u32, val, 10) catch continue;
        if (std.mem.eql(u8, key, "from")) from_opt = v;
        if (std.mem.eql(u8, key, "to")) to_opt = v;
    }
    const from = from_opt orelse return literal(.bad_request, "text/plain; charset=utf-8", "400 Bad Request — missing `from`\n");
    const to = to_opt orelse return literal(.bad_request, "text/plain; charset=utf-8", "400 Bad Request — missing `to`\n");
    if (to < from) return literal(.bad_request, "text/plain; charset=utf-8", "400 Bad Request — to < from\n");

    const span: u32 = to - from + 1;
    if (span > 2000) return literal(.bad_request, "text/plain; charset=utf-8", "400 Bad Request — range > 2000 headers; chunk it\n");

    const total = @as(usize, span) * headers_mod.HEADER_BYTES;
    var buf = try allocator.alloc(u8, total);
    errdefer allocator.free(buf);

    var present: u32 = 0;
    for (0..span) |i| {
        const h = from + @as(u32, @intCast(i));
        const rec = store.getByHeight(h) orelse break;
        const slice_ptr: *[80]u8 = @ptrCast(buf[i * 80 ..][0..80].ptr);
        rec.header.serialize(slice_ptr);
        present += 1;
    }
    // Shrink the buffer to the actual present size — we'd otherwise
    // leak the trailing un-served bytes (and freeResponse calls
    // allocator.free on the body slice, which must own the full
    // allocation).
    const used: usize = @as(usize, present) * headers_mod.HEADER_BYTES;
    if (used < total) {
        if (allocator.resize(buf, used)) {
            buf = buf[0..used];
        } else {
            // Resize couldn't shrink in-place — reallocate.
            const small = try allocator.alloc(u8, used);
            if (used > 0) @memcpy(small, buf[0..used]);
            allocator.free(buf);
            buf = small;
        }
    }
    return .{
        .status = .ok,
        .content_type = "application/octet-stream",
        .body = buf,
        .body_owned = true,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Hex helpers
// ─────────────────────────────────────────────────────────────────────

fn decodeHex(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return error.bad_length;
    for (0..out.len) |i| {
        const hi = try nibble(hex[i * 2]);
        const lo = try nibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
}

fn nibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => error.bad_hex,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn fakeHeader(seed: u8) headers_mod.Header {
    var raw: [80]u8 = undefined;
    @memset(&raw, seed);
    // Force a recognisable bits field.
    raw[72] = 0xff;
    raw[73] = 0xff;
    raw[74] = 0x00;
    raw[75] = 0x1d;
    return headers_mod.Header.parseRaw(&raw);
}

test "WH-Headers HTTP: tip on empty store reports empty=true" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();

    const resp = try composeResponse(testing.allocator, &handle, .GET, "/api/v1/chain/header/byHeight/tip");
    defer freeResponse(testing.allocator, resp);
    try testing.expectEqual(std.http.Status.ok, resp.status);
    try testing.expect(std.mem.indexOf(u8, resp.body, "\"empty\":true") != null);
}

test "WH-Headers HTTP: tip with one header returns height + display-form hash" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();
    const h0 = fakeHeader(0xaa);
    try handle.appendValidated(h0, 0);

    const resp = try composeResponse(testing.allocator, &handle, .GET, "/api/v1/chain/header/byHeight/tip");
    defer freeResponse(testing.allocator, resp);
    try testing.expectEqual(std.http.Status.ok, resp.status);
    try testing.expect(std.mem.indexOf(u8, resp.body, "\"height\":0") != null);
    try testing.expect(std.mem.indexOf(u8, resp.body, "\"hash\":\"") != null);
}

test "WH-Headers HTTP: byHeight returns 80-byte raw header" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();
    const h0 = fakeHeader(0x11);
    try handle.appendValidated(h0, 0);

    const resp = try composeResponse(testing.allocator, &handle, .GET, "/api/v1/chain/header/byHeight/0");
    defer freeResponse(testing.allocator, resp);
    try testing.expectEqual(std.http.Status.ok, resp.status);
    try testing.expectEqual(@as(usize, 80), resp.body.len);
    try testing.expectEqualStrings("application/octet-stream", resp.content_type);
}

test "WH-Headers HTTP: byHeight 404 for missing height" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();
    const resp = try composeResponse(testing.allocator, &handle, .GET, "/api/v1/chain/header/byHeight/9999");
    defer freeResponse(testing.allocator, resp);
    try testing.expectEqual(std.http.Status.not_found, resp.status);
}

/// Build a chain of `count` headers where each's prev_hash = previous's
/// computed hash, so the store accepts the sequence.  `seed` is the
/// per-byte fill of the first header's body (above the prev_hash);
/// subsequent headers reuse the same fill bytes for sanity but with
/// the right prev_hash overlaid.
fn appendChain(handle: header_store_mod.HeaderStore, count: u32, seed_first: u8) !void {
    var prev_hash: [32]u8 = [_]u8{0} ** 32;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        var raw: [80]u8 = undefined;
        @memset(&raw, seed_first +% @as(u8, @intCast(i)));
        // Force a recognisable bits field at offset 72..76.
        raw[72] = 0xff;
        raw[73] = 0xff;
        raw[74] = 0x00;
        raw[75] = 0x1d;
        // Overlay prev_hash at offset 4..36.
        @memcpy(raw[4..36], &prev_hash);
        const hdr = headers_mod.Header.parseRaw(&raw);
        try handle.appendValidated(hdr, i);
        prev_hash = hdr.computeHash();
    }
}

test "WH-Headers HTTP: range serves concatenated 80-byte headers" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();
    try appendChain(handle, 3, 0xaa);

    const resp = try composeResponse(testing.allocator, &handle, .GET, "/api/v1/chain/header/range?from=0&to=2");
    defer freeResponse(testing.allocator, resp);
    try testing.expectEqual(std.http.Status.ok, resp.status);
    try testing.expectEqual(@as(usize, 240), resp.body.len);
    // First byte of each header is the `version` (low byte) which we
    // set to seed_first + i.  Spot-check.
    try testing.expectEqual(@as(u8, 0xaa), resp.body[0]);
    try testing.expectEqual(@as(u8, 0xab), resp.body[80]);
    try testing.expectEqual(@as(u8, 0xac), resp.body[160]);
}

test "WH-Headers HTTP: range with missing param is 400" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();
    const resp = try composeResponse(testing.allocator, &handle, .GET, "/api/v1/chain/header/range?from=0");
    defer freeResponse(testing.allocator, resp);
    try testing.expectEqual(std.http.Status.bad_request, resp.status);
}

test "WH-Headers HTTP: range > 2000 is rejected" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();
    const resp = try composeResponse(testing.allocator, &handle, .GET, "/api/v1/chain/header/range?from=0&to=2001");
    defer freeResponse(testing.allocator, resp);
    try testing.expectEqual(std.http.Status.bad_request, resp.status);
}

test "WH-Headers HTTP: range with partial coverage returns only what's present" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();
    try handle.appendValidated(fakeHeader(0x77), 0);
    // Range asks for 0..4 — store only has 0.
    const resp = try composeResponse(testing.allocator, &handle, .GET, "/api/v1/chain/header/range?from=0&to=4");
    defer freeResponse(testing.allocator, resp);
    try testing.expectEqual(std.http.Status.ok, resp.status);
    try testing.expectEqual(@as(usize, 80), resp.body.len);
}

test "WH-Headers HTTP: byHash decodes display-form + reverses to internal" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();
    const h0 = fakeHeader(0x33);
    try handle.appendValidated(h0, 0);

    const tip = handle.tip().?;
    var display_hex: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (tip.hash, 0..) |b, i| {
        const dst = 31 - i;
        display_hex[dst * 2] = hex_chars[(b >> 4) & 0xf];
        display_hex[dst * 2 + 1] = hex_chars[b & 0xf];
    }

    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "/api/v1/chain/header/byHash/{s}", .{display_hex[0..]});
    const resp = try composeResponse(testing.allocator, &handle, .GET, url);
    defer freeResponse(testing.allocator, resp);
    try testing.expectEqual(std.http.Status.ok, resp.status);
    try testing.expectEqual(@as(usize, 80), resp.body.len);
}

test "WH-Headers HTTP: unknown path is 404" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();
    const resp = try composeResponse(testing.allocator, &handle, .GET, "/foo/bar");
    defer freeResponse(testing.allocator, resp);
    try testing.expectEqual(std.http.Status.not_found, resp.status);
}

test "WH-Headers HTTP: POST is 405" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();
    const resp = try composeResponse(testing.allocator, &handle, .POST, "/api/v1/chain/header/byHeight/tip");
    defer freeResponse(testing.allocator, resp);
    try testing.expectEqual(std.http.Status.method_not_allowed, resp.status);
}

```
