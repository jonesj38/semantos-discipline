---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/uhrp_http_store_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.961145+00:00
---

# core/cell-engine/tests/uhrp_http_store_test.zig

```zig
// M4.2 — UhrpHttpStore conformance tests.
//
// TDD red phase: written before the implementation.
// These tests define the contract for fetching 1024-byte windows from
// octave-2 slots via HTTP Range requests.
//
// Test IDs:
//   M4.2-T-register-and-fetch    — register slot 1 with a test server; fetch at offset 0
//   M4.2-T-range-at-offset       — fetch at offset 4096 → bytes [4096..5119]
//   M4.2-T-slot-not-registered   — fetchWindow on unregistered slot → error.SlotNotRegistered
//   M4.2-T-end-of-stream         — server returns 206 but body < 1024 bytes → error.EndOfStream
//   M4.2-T-http-error            — server returns 200 (not 206) → error.HttpError
//
// Run: zig build test-uhrp-http-store

const std = @import("std");
const uhrp_http_store = @import("uhrp_http_store");
const UhrpHttpStore = uhrp_http_store.UhrpHttpStore;

// ── TestHttpServer ────────────────────────────────────────────────────────────
//
// In-process HTTP server that handles a single Range GET request and responds
// with 206 Partial Content from an in-memory buffer.
//
// Lifecycle:
//   1. Caller calls TestHttpServer.start(alloc, buffer, mode) → server address
//   2. The server runs in a background thread.
//   3. Caller calls server.stop() after the test.
//
// `mode` controls what the server sends:
//   .normal        — serves Range requests correctly with 206
//   .short_body    — sends 206 with only 512 bytes (less than 1024)
//   .wrong_status  — sends 200 OK instead of 206

const ServerMode = enum { normal, short_body, wrong_status };

const TestHttpServer = struct {
    server: std.net.Server,
    thread: std.Thread,
    port: u16,

    /// 2 MB cycling buffer: byte[i] = @truncate(i % 251)
    const BUFFER_SIZE = 2 * 1024 * 1024;

    const Context = struct {
        server: *std.net.Server,
        mode: ServerMode,
    };

    pub fn start(alloc: std.mem.Allocator, mode: ServerMode) !TestHttpServer {
        _ = alloc;

        const addr = try std.net.Address.parseIp("127.0.0.1", 0);
        var srv = try addr.listen(.{ .reuse_address = true });
        const port: u16 = srv.listen_address.in.getPort();

        const ctx = try std.heap.c_allocator.create(Context);
        ctx.* = .{ .server = &srv, .mode = mode };

        // We need srv to outlive the thread, but we can't take its address after
        // moving it into the struct. Work around: heap-allocate the server too.
        const srv_heap = try std.heap.c_allocator.create(std.net.Server);
        srv_heap.* = srv;
        ctx.server = srv_heap;

        const thread = try std.Thread.spawn(.{}, runServer, .{ctx});

        return TestHttpServer{
            .server = srv_heap.*,
            .thread = thread,
            .port = port,
        };
    }

    pub fn stop(self: *TestHttpServer) void {
        // Close the server socket; this will unblock accept() in the thread.
        self.server.deinit();
        self.thread.join();
    }

    fn runServer(ctx: *Context) void {
        defer std.heap.c_allocator.destroy(ctx);
        const mode = ctx.mode;
        const srv = ctx.server;
        defer std.heap.c_allocator.destroy(srv);

        // Handle one connection then exit.
        const conn = srv.accept() catch return;
        defer conn.stream.close();
        handleConnection(conn.stream, mode);
    }

    fn handleConnection(stream: std.net.Stream, mode: ServerMode) void {
        var buf: [4096]u8 = undefined;
        // Read the HTTP request (we only need the Range header).
        const n = stream.read(&buf) catch return;
        const req = buf[0..n];

        // Parse Range header: "Range: bytes=<start>-<end>"
        var range_start: usize = 0;
        var range_end: usize = 1023;

        if (std.mem.indexOf(u8, req, "Range: bytes=")) |range_idx| {
            const range_val_start = range_idx + "Range: bytes=".len;
            const range_line_end = std.mem.indexOfScalarPos(u8, req, range_val_start, '\r') orelse
                std.mem.indexOfScalarPos(u8, req, range_val_start, '\n') orelse (range_val_start + 20);
            const range_str = req[range_val_start..range_line_end];
            if (std.mem.indexOf(u8, range_str, "-")) |dash_pos| {
                range_start = std.fmt.parseInt(usize, range_str[0..dash_pos], 10) catch 0;
                range_end = std.fmt.parseInt(usize, range_str[dash_pos + 1 ..], 10) catch 1023;
            }
        }

        // Build the cycling data buffer.
        var data: [BUFFER_SIZE]u8 = undefined;
        for (&data, 0..) |*b, i| b.* = @truncate(i % 251);

        const content_start = @min(range_start, data.len);
        const content_end_normal = @min(range_end + 1, data.len);
        const normal_body = data[content_start..content_end_normal];

        switch (mode) {
            .normal => {
                const body_len = normal_body.len;
                var header_buf: [256]u8 = undefined;
                const header = std.fmt.bufPrint(
                    &header_buf,
                    "HTTP/1.1 206 Partial Content\r\nContent-Length: {d}\r\nContent-Range: bytes {d}-{d}/{d}\r\nConnection: close\r\n\r\n",
                    .{ body_len, content_start, content_end_normal - 1, data.len },
                ) catch return;
                _ = stream.writeAll(header) catch return;
                _ = stream.writeAll(normal_body) catch return;
            },
            .short_body => {
                // Return 206 but only 512 bytes.
                const short = data[content_start..@min(content_start + 512, data.len)];
                var header_buf: [256]u8 = undefined;
                const header = std.fmt.bufPrint(
                    &header_buf,
                    "HTTP/1.1 206 Partial Content\r\nContent-Length: {d}\r\nContent-Range: bytes {d}-{d}/{d}\r\nConnection: close\r\n\r\n",
                    .{ short.len, content_start, content_start + short.len - 1, data.len },
                ) catch return;
                _ = stream.writeAll(header) catch return;
                _ = stream.writeAll(short) catch return;
            },
            .wrong_status => {
                // Return 200 OK instead of 206.
                const body = normal_body;
                var header_buf: [256]u8 = undefined;
                const header = std.fmt.bufPrint(
                    &header_buf,
                    "HTTP/1.1 200 OK\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
                    .{body.len},
                ) catch return;
                _ = stream.writeAll(header) catch return;
                _ = stream.writeAll(body) catch return;
            },
        }
    }

    pub fn urlForSlot(self: *const TestHttpServer, slot: u32, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "http://127.0.0.1:{d}/slot/{d}", .{ self.port, slot });
    }
};

// ── Reference buffer ──────────────────────────────────────────────────────────

/// Build 2 MB of cycling byte pattern: byte[i] = @truncate(i % 251).
fn makeCyclingData(alloc: std.mem.Allocator, size: usize) ![]u8 {
    const buf = try alloc.alloc(u8, size);
    for (buf, 0..) |*b, i| b.* = @truncate(i % 251);
    return buf;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "M4.2-T-register-and-fetch" {
    const alloc = std.testing.allocator;

    var srv = try TestHttpServer.start(alloc, .normal);
    defer srv.stop();

    var store = UhrpHttpStore.init(alloc, "http://unused-base/");
    defer store.deinit();

    var url_buf: [128]u8 = undefined;
    const url = try srv.urlForSlot(1, &url_buf);
    try store.registerSlot(1, url);

    var out: [1024]u8 = undefined;
    try store.fetchWindow(1, 0, &out);

    // Compare against the expected cycling pattern at offset 0.
    const ref = try makeCyclingData(alloc, 2 * 1024 * 1024);
    defer alloc.free(ref);
    try std.testing.expectEqualSlices(u8, ref[0..1024], &out);
}

test "M4.2-T-range-at-offset" {
    const alloc = std.testing.allocator;

    var srv = try TestHttpServer.start(alloc, .normal);
    defer srv.stop();

    var store = UhrpHttpStore.init(alloc, "http://unused-base/");
    defer store.deinit();

    var url_buf: [128]u8 = undefined;
    const url = try srv.urlForSlot(1, &url_buf);
    try store.registerSlot(1, url);

    var out: [1024]u8 = undefined;
    try store.fetchWindow(1, 4096, &out);

    // Compare against the expected cycling pattern at offset 4096.
    const ref = try makeCyclingData(alloc, 2 * 1024 * 1024);
    defer alloc.free(ref);
    try std.testing.expectEqualSlices(u8, ref[4096..5120], &out);
}

test "M4.2-T-slot-not-registered" {
    const alloc = std.testing.allocator;

    var store = UhrpHttpStore.init(alloc, "http://unused-base/");
    defer store.deinit();

    var out: [1024]u8 = undefined;
    const result = store.fetchWindow(99, 0, &out);
    try std.testing.expectError(error.SlotNotRegistered, result);
}

test "M4.2-T-end-of-stream" {
    const alloc = std.testing.allocator;

    var srv = try TestHttpServer.start(alloc, .short_body);
    defer srv.stop();

    var store = UhrpHttpStore.init(alloc, "http://unused-base/");
    defer store.deinit();

    var url_buf: [128]u8 = undefined;
    const url = try srv.urlForSlot(2, &url_buf);
    try store.registerSlot(2, url);

    var out: [1024]u8 = undefined;
    const result = store.fetchWindow(2, 0, &out);
    try std.testing.expectError(error.EndOfStream, result);
}

test "M4.2-T-http-error" {
    const alloc = std.testing.allocator;

    var srv = try TestHttpServer.start(alloc, .wrong_status);
    defer srv.stop();

    var store = UhrpHttpStore.init(alloc, "http://unused-base/");
    defer store.deinit();

    var url_buf: [128]u8 = undefined;
    const url = try srv.urlForSlot(3, &url_buf);
    try store.registerSlot(3, url);

    var out: [1024]u8 = undefined;
    const result = store.fetchWindow(3, 0, &out);
    try std.testing.expectError(error.HttpError, result);
}

```
