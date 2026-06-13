---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/registry_change_producer_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.175603+00:00
---

# runtime/semantos-brain/tests/registry_change_producer_test.zig

```zig
// M6.3 — RegistryChangeProducer conformance tests.
//
// Test IDs:
//   M6.3-T-emit-insert            : emitChange(.insert, ...) → body has "kind":"insert", "cell_id", "domain_flag", "new_state", "octave_level", "seq":0
//   M6.3-T-emit-state-change      : emitChange(.state_change, ...) → body has "kind":"state_change"
//   M6.3-T-routing-key-is-cell-prefix : routing key == first 4 hex chars of cell_id
//   M6.3-T-seq-increments         : three buildPayload calls → seq 0, 1, 2
//   M6.3-T-domain-flag-in-payload : domain_flag 0x0042 → "domain_flag":66 in JSON
//
// Run: zig build test-registry-change-producer

const std = @import("std");
const registry_change_producer = @import("registry_change_producer");
const RegistryChangeProducer = registry_change_producer.RegistryChangeProducer;
const ChangeKind = registry_change_producer.ChangeKind;
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;
const PravegatConfig = pravega_client.PravegatConfig;

// ─── MockHttpServer ──────────────────────────────────────────────────────────
//
// One-shot HTTP server that handles exactly one request and records body and
// routing key. Uses a shared heap-allocated Captured struct so the background
// thread's writes are visible after thread.join().

const MockHttpServer = struct {
    thread: std.Thread,
    port: u16,
    captured: *Captured,

    const Captured = struct {
        body: [16384]u8 = undefined,
        body_len: usize = 0,
        routing_key: [512]u8 = undefined,
        routing_key_len: usize = 0,
        mutex: std.Thread.Mutex = .{},
    };

    const Response = struct {
        status: u16,
        body: []const u8,
        content_type: []const u8 = "application/json",
    };

    const Context = struct {
        server: *std.net.Server,
        response: Response,
        captured: *Captured,
    };

    pub fn start(alloc: std.mem.Allocator, response: Response) !MockHttpServer {
        _ = alloc;

        const addr = try std.net.Address.parseIp("127.0.0.1", 0);
        const srv = try std.heap.c_allocator.create(std.net.Server);
        srv.* = try addr.listen(.{ .reuse_address = true });
        const port: u16 = srv.listen_address.in.getPort();

        const captured = try std.heap.c_allocator.create(Captured);
        captured.* = .{};

        const ctx = try std.heap.c_allocator.create(Context);
        ctx.* = .{ .server = srv, .response = response, .captured = captured };

        const thread = try std.Thread.spawn(.{}, runServer, .{ctx});

        return MockHttpServer{
            .thread = thread,
            .port = port,
            .captured = captured,
        };
    }

    /// Join the background thread (must be called exactly once).
    /// After this returns, self.captured holds the recorded data.
    pub fn join(self: *MockHttpServer) void {
        self.thread.join();
    }

    /// Free the shared captured buffer. Call after join() and after all
    /// reads from captured are done.
    pub fn freeCapture(self: *MockHttpServer) void {
        std.heap.c_allocator.destroy(self.captured);
    }

    pub fn body(self: *const MockHttpServer) []const u8 {
        return self.captured.body[0..self.captured.body_len];
    }

    pub fn routingKey(self: *const MockHttpServer) []const u8 {
        return self.captured.routing_key[0..self.captured.routing_key_len];
    }

    fn runServer(ctx: *Context) void {
        defer std.heap.c_allocator.destroy(ctx);
        const srv = ctx.server;
        defer {
            srv.deinit();
            std.heap.c_allocator.destroy(srv);
        }

        const conn = srv.accept() catch return;
        defer conn.stream.close();
        handleConnection(conn.stream, ctx.response, ctx.captured);
    }

    fn handleConnection(stream: std.net.Stream, response: Response, captured: *Captured) void {
        var req_buf: [16384]u8 = undefined;
        const n = stream.read(&req_buf) catch return;
        const raw = req_buf[0..n];

        captured.mutex.lock();
        defer captured.mutex.unlock();

        // Extract routing key from first-line URL: ?routingKey=<value><space>
        if (std.mem.indexOf(u8, raw, "?routingKey=")) |rk_start| {
            const val_start = rk_start + "?routingKey=".len;
            const val_end = std.mem.indexOfScalarPos(u8, raw, val_start, ' ') orelse val_start;
            const rk = raw[val_start..val_end];
            const copy_len = @min(rk.len, captured.routing_key.len);
            @memcpy(captured.routing_key[0..copy_len], rk[0..copy_len]);
            captured.routing_key_len = copy_len;
        }

        // Extract JSON body (after \r\n\r\n).
        if (std.mem.indexOf(u8, raw, "\r\n\r\n")) |header_end| {
            const b = raw[header_end + 4 ..];
            const copy_len = @min(b.len, captured.body.len);
            @memcpy(captured.body[0..copy_len], b[0..copy_len]);
            captured.body_len = copy_len;
        }

        // Send response.
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

test "M6.3-T-emit-insert" {
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "test-scope",
    });
    defer client.deinit();

    var producer = RegistryChangeProducer.init(alloc, &client, "registry-changes");
    defer producer.deinit();

    try producer.emitChange(
        .insert,
        "ab12cd34ef560000000000000000000000000000000000000000000000001234",
        0x0001,
        "unspent",
        1,
        1_700_000_000_000,
    );

    srv.join();
    defer srv.freeCapture();

    try std.testing.expect(std.mem.indexOf(u8, srv.body(), "\"kind\":\"insert\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, srv.body(), "ab12cd34ef560000000000000000000000000000000000000000000000001234") != null);
    try std.testing.expect(std.mem.indexOf(u8, srv.body(), "\"domain_flag\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, srv.body(), "\"new_state\":\"unspent\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, srv.body(), "\"octave_level\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, srv.body(), "\"seq\":0") != null);
}

test "M6.3-T-emit-state-change" {
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "test-scope",
    });
    defer client.deinit();

    var producer = RegistryChangeProducer.init(alloc, &client, "registry-changes");
    defer producer.deinit();

    try producer.emitChange(
        .state_change,
        "deadbeef00000000000000000000000000000000000000000000000000009999",
        0x0002,
        "spent",
        0,
        1_700_000_001_000,
    );

    srv.join();
    defer srv.freeCapture();

    try std.testing.expect(std.mem.indexOf(u8, srv.body(), "\"kind\":\"state_change\"") != null);
}

test "M6.3-T-routing-key-is-cell-prefix" {
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "test-scope",
    });
    defer client.deinit();

    var producer = RegistryChangeProducer.init(alloc, &client, "registry-changes");
    defer producer.deinit();

    // cell_id starts with "ab12" — routing key must be "ab12"
    try producer.emitChange(
        .insert,
        "ab120000000000000000000000000000000000000000000000000000000000ff",
        0x0001,
        "unspent",
        2,
        1_700_000_002_000,
    );

    srv.join();
    defer srv.freeCapture();

    try std.testing.expectEqualStrings("ab12", srv.routingKey());
}

test "M6.3-T-seq-increments" {
    const alloc = std.testing.allocator;

    // Use buildPayload directly to verify seq increments without HTTP.
    const gateway_url = "http://127.0.0.1:1"; // dummy — no real call
    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "test-scope",
    });
    defer client.deinit();

    var producer = RegistryChangeProducer.init(alloc, &client, "registry-changes");
    defer producer.deinit();

    const p0 = try producer.buildPayload(.insert, "aaaa", 0x0001, "unspent", 0, 1_000_000);
    defer alloc.free(p0);
    const p1 = try producer.buildPayload(.update, "bbbb", 0x0001, "locked", 1, 1_000_001);
    defer alloc.free(p1);
    const p2 = try producer.buildPayload(.state_change, "cccc", 0x0001, "spent", 2, 1_000_002);
    defer alloc.free(p2);

    try std.testing.expect(std.mem.indexOf(u8, p0, "\"seq\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, p1, "\"seq\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, p2, "\"seq\":2") != null);
}

test "M6.3-T-domain-flag-in-payload" {
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "test-scope",
    });
    defer client.deinit();

    var producer = RegistryChangeProducer.init(alloc, &client, "registry-changes");
    defer producer.deinit();

    // domain_flag = 0x0042 = 66 decimal
    try producer.emitChange(
        .insert,
        "ff001122334455667788990000000000000000000000000000000000000000aa",
        0x0042,
        "unspent",
        0,
        1_700_000_003_000,
    );

    srv.join();
    defer srv.freeCapture();

    try std.testing.expect(std.mem.indexOf(u8, srv.body(), "\"domain_flag\":66") != null);
}

```
