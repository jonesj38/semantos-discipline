---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/pravega_client_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.180737+00:00
---

# runtime/semantos-brain/tests/pravega_client_test.zig

```zig
// M3.2 — PravegatClient unit tests (mock HTTP server, no real Pravega).
//
// Test IDs:
//   M3.2-T-ensure-scope-201    : mock returns 201 → no error
//   M3.2-T-ensure-scope-409    : mock returns 409 (already exists) → no error
//   M3.2-T-write-event-201     : mock returns 201 → no error
//   M3.2-T-write-event-http-error : mock returns 500 → error.HttpError
//   M3.2-T-read-event-null     : mock returns 200 empty body → readEvent null
//
// Run: zig build test-pravega-client

const std = @import("std");
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;
const PravegatConfig = pravega_client.PravegatConfig;

// ─── MockHttpServer ──────────────────────────────────────────────────────────
//
// Minimal in-process HTTP server for one request → one response.
// Uses std.net.Server + std.Thread.
//
// Lifecycle:
//   1. Caller calls MockHttpServer.start(alloc, response) → MockHttpServer
//   2. Server runs in a background thread (handles exactly one connection).
//   3. Caller calls server.waitAndFree() after the test assertion.
//
// The server socket is owned exclusively by the background thread.
// The thread closes it after handling one request. The caller must NOT
// close the socket itself — call waitAndFree() instead which just joins
// the thread.

const MockHttpServer = struct {
    thread: std.Thread,
    port: u16,

    const Response = struct {
        status: u16,
        body: []const u8,
        content_type: []const u8 = "application/json",
    };

    const Context = struct {
        // Heap-allocated server owned by the thread.
        server: *std.net.Server,
        response: Response,
    };

    pub fn start(alloc: std.mem.Allocator, response: Response) !MockHttpServer {
        _ = alloc;

        const addr = try std.net.Address.parseIp("127.0.0.1", 0);
        const srv = try std.heap.c_allocator.create(std.net.Server);
        srv.* = try addr.listen(.{ .reuse_address = true });
        const port: u16 = srv.listen_address.in.getPort();

        const ctx = try std.heap.c_allocator.create(Context);
        ctx.* = .{ .server = srv, .response = response };

        const thread = try std.Thread.spawn(.{}, runServer, .{ctx});

        return MockHttpServer{
            .thread = thread,
            .port = port,
        };
    }

    /// Join the background thread. Must be called after the HTTP interaction
    /// that causes the server to handle its one request.
    pub fn waitAndFree(self: *MockHttpServer) void {
        self.thread.join();
    }

    fn runServer(ctx: *Context) void {
        defer std.heap.c_allocator.destroy(ctx);
        const srv = ctx.server;
        defer {
            srv.deinit();
            std.heap.c_allocator.destroy(srv);
        }

        // Handle one connection then exit.
        const conn = srv.accept() catch return;
        defer conn.stream.close();
        handleConnection(conn.stream, ctx.response);
    }

    fn handleConnection(stream: std.net.Stream, response: Response) void {
        // Drain the incoming request bytes.
        var req_buf: [8192]u8 = undefined;
        _ = stream.read(&req_buf) catch return;

        // Build and send HTTP response.
        var header_buf: [512]u8 = undefined;
        const status_text = statusText(response.status);
        const header = std.fmt.bufPrint(
            &header_buf,
            "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ response.status, status_text, response.content_type, response.body.len },
        ) catch return;
        _ = stream.writeAll(header) catch return;
        _ = stream.writeAll(response.body) catch return;
    }

    fn statusText(code: u16) []const u8 {
        return switch (code) {
            200 => "OK",
            201 => "Created",
            204 => "No Content",
            409 => "Conflict",
            500 => "Internal Server Error",
            else => "Unknown",
        };
    }

    pub fn baseUrl(self: *const MockHttpServer, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "http://127.0.0.1:{d}", .{self.port});
    }
};

// ─── Tests ───────────────────────────────────────────────────────────────────

test "M3.2-T-ensure-scope-201" {
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{
        .status = 201,
        .body = "{}",
    });

    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "test-scope",
    });
    defer client.deinit();

    // 201 → no error
    try client.ensureScope();

    // Join server thread after the HTTP call completes.
    srv.waitAndFree();
}

test "M3.2-T-ensure-scope-409" {
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{
        .status = 409,
        .body = "{\"message\":\"Scope already exists\"}",
    });

    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "existing-scope",
    });
    defer client.deinit();

    // 409 (already exists) → still no error (idempotent)
    try client.ensureScope();

    srv.waitAndFree();
}

test "M3.2-T-write-event-201" {
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{
        .status = 201,
        .body = "",
    });

    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "test-scope",
    });
    defer client.deinit();

    // 201 → no error
    try client.writeEvent(
        "my-stream",
        "key-1",
        "{\"hello\":\"M3.2\"}",
    );

    srv.waitAndFree();
}

test "M3.2-T-write-event-http-error" {
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{
        .status = 500,
        .body = "{\"error\":\"internal server error\"}",
    });

    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "test-scope",
    });
    defer client.deinit();

    // 500 → error.HttpError
    const result = client.writeEvent(
        "my-stream",
        "key-1",
        "{\"hello\":\"M3.2\"}",
    );
    try std.testing.expectError(error.HttpError, result);

    srv.waitAndFree();
}

test "M3.2-T-read-event-null" {
    const alloc = std.testing.allocator;

    // Mock returns 200 with empty body → readEvent should return null.
    var srv = try MockHttpServer.start(alloc, .{
        .status = 200,
        .body = "",
    });

    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "test-scope",
    });
    defer client.deinit();

    const result = try client.readEvent("my-rg", "reader-1");
    try std.testing.expect(result == null);

    srv.waitAndFree();
}

```
