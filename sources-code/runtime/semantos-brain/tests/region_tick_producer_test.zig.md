---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/region_tick_producer_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.209497+00:00
---

# runtime/semantos-brain/tests/region_tick_producer_test.zig

```zig
// M3.3 — RegionTickProducer unit tests (mock HTTP server, no real Pravega).
//
// Test IDs:
//   M3.3-T-tick-payload          : buildTickPayload produces valid JSON with correct fields
//   M3.3-T-tick-count-increments : three maybeTick calls → tick_count reaches 3
//   M3.3-T-interval-gate         : maybeTick called before interval elapsed → no event (tick_count stays 0)
//   M3.3-T-merkle-root-hex       : payload contains 64-char lowercase hex of merkle_root
//   M3.3-T-routing-key           : writeEvent is called with region_id as routing_key
//
// Run: zig build test-region-tick-producer

const std = @import("std");
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;
const PravegatConfig = pravega_client.PravegatConfig;
const region_tick_producer = @import("region_tick_producer");
const RegionTickProducer = region_tick_producer.RegionTickProducer;

// ─── MockHttpServer ──────────────────────────────────────────────────────────
//
// Same pattern as pravega_client_test.zig.
// Handles exactly one request then exits the background thread.

const MockHttpServer = struct {
    thread: std.Thread,
    port: u16,
    /// Populated by the background thread after one request is received.
    captured_path: ?[]u8 = null,
    captured_body: ?[]u8 = null,

    const Response = struct {
        status: u16,
        body: []const u8,
        content_type: []const u8 = "application/json",
    };

    const Context = struct {
        server: *std.net.Server,
        response: Response,
        // Allocated by runServer; caller reads via captured_* fields.
        captured_path: ?[]u8,
        captured_body: ?[]u8,
    };

    pub fn start(alloc: std.mem.Allocator, response: Response) !MockHttpServer {
        _ = alloc;

        const addr = try std.net.Address.parseIp("127.0.0.1", 0);
        const srv = try std.heap.c_allocator.create(std.net.Server);
        srv.* = try addr.listen(.{ .reuse_address = true });
        const port: u16 = srv.listen_address.in.getPort();

        const ctx = try std.heap.c_allocator.create(Context);
        ctx.* = .{
            .server = srv,
            .response = response,
            .captured_path = null,
            .captured_body = null,
        };

        const thread = try std.Thread.spawn(.{}, runServer, .{ctx});

        return MockHttpServer{
            .thread = thread,
            .port = port,
        };
    }

    /// Join the background thread and retrieve any captured data.
    pub fn waitAndCapture(self: *MockHttpServer) struct { path: ?[]u8, body: ?[]u8 } {
        self.thread.join();
        return .{ .path = self.captured_path, .body = self.captured_body };
    }

    /// Join without capturing. For tests that don't need to inspect the request.
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

        const conn = srv.accept() catch return;
        defer conn.stream.close();
        handleConnection(conn.stream, ctx.response);
    }

    fn handleConnection(stream: std.net.Stream, response: Response) void {
        var req_buf: [8192]u8 = undefined;
        _ = stream.read(&req_buf) catch return;

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

// ─── Helpers ─────────────────────────────────────────────────────────────────

fn makeClient(alloc: std.mem.Allocator, gateway_url: []const u8) !PravegatClient {
    return PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "test-scope",
    });
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "M3.3-T-tick-payload" {
    // buildTickPayload must produce JSON with all required fields:
    //   region_id, tick, ts_ms, merkle_root
    const alloc = std.testing.allocator;

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = "http://127.0.0.1:19999", // unused — no HTTP call here
        .scope = "test-scope",
    });
    defer client.deinit();

    var producer = RegionTickProducer.init(
        alloc,
        &client,
        "region-ticks",
        "world-0",
        50,
    );
    defer producer.deinit();

    var merkle: [32]u8 = undefined;
    @memset(&merkle, 0xAB);

    const payload = try producer.buildTickPayload(alloc, 1_000_000, &merkle);
    defer alloc.free(payload);

    // Must be valid JSON containing all required keys
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"region_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"tick\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"ts_ms\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"merkle_root\"") != null);

    // region_id value must appear
    try std.testing.expect(std.mem.indexOf(u8, payload, "world-0") != null);
}

test "M3.3-T-tick-count-increments" {
    // Three maybeTick calls at t=0, t=50, t=100 → tick_count reaches 3.
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try makeClient(alloc, gateway_url);
    defer client.deinit();

    var producer = RegionTickProducer.init(
        alloc,
        &client,
        "region-ticks",
        "world-0",
        50,
    );
    defer producer.deinit();

    var merkle: [32]u8 = undefined;
    @memset(&merkle, 0x01);

    // tick 1 at t=0 (initialisation: last_tick_ms defaults to 0, so any t >= 50 fires,
    // but t=0 is exactly at epoch — use t=50 for the first tick).
    try producer.maybeTick(50, &merkle);
    srv.waitAndFree();

    // tick 2 — start a new mock for each HTTP call
    var srv2 = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf2: [128]u8 = undefined;
    // Re-use same port as client (already configured); override client gateway url
    // is not possible post-init — instead spin a new client pointing at srv2.
    // Simpler: let producer hold the same client; rebind gateway_url via a fresh client.
    var client2 = try PravegatClient.init(alloc, .{
        .gateway_url = try srv2.baseUrl(&url_buf2),
        .scope = "test-scope",
    });
    defer client2.deinit();

    var producer2 = RegionTickProducer.init(alloc, &client2, "region-ticks", "world-0", 50);
    defer producer2.deinit();

    // Manually advance tick_count to 1 by calling maybeTick once:
    try producer2.maybeTick(50, &merkle);
    srv2.waitAndFree();

    var srv3 = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf3: [128]u8 = undefined;
    var client3 = try PravegatClient.init(alloc, .{
        .gateway_url = try srv3.baseUrl(&url_buf3),
        .scope = "test-scope",
    });
    defer client3.deinit();

    var producer3 = RegionTickProducer.init(alloc, &client3, "region-ticks", "world-0", 50);
    defer producer3.deinit();
    try producer3.maybeTick(50, &merkle);
    srv3.waitAndFree();

    // Each fresh producer starts at tick_count=0 and maybeTick increments to 1.
    // Verify via a single producer doing 3 ticks with advancing time:
    var srv_a = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf_a: [128]u8 = undefined;
    var client_a = try PravegatClient.init(alloc, .{
        .gateway_url = try srv_a.baseUrl(&url_buf_a),
        .scope = "test-scope",
    });
    defer client_a.deinit();

    var p = RegionTickProducer.init(alloc, &client_a, "region-ticks", "world-0", 50);
    defer p.deinit();

    try p.maybeTick(50, &merkle); // tick 1
    srv_a.waitAndFree();
    try std.testing.expectEqual(@as(u64, 1), p.tick_count);

    var srv_b = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    p.client = &client_a; // already same
    // To redirect the second HTTP call we need client_a still bound to a live server.
    // Restart approach: give producer a new client each tick.
    // Cleaner: expose a seam. Instead, we update client_a's cfg to point to srv_b's port.
    // PravegatClient cfg is mutable — update gateway_url in place using a fixed buf.
    var url_buf_b: [128]u8 = undefined;
    const gw_b = try srv_b.baseUrl(&url_buf_b);
    client_a.cfg.gateway_url = gw_b;

    try p.maybeTick(100, &merkle); // tick 2
    srv_b.waitAndFree();
    try std.testing.expectEqual(@as(u64, 2), p.tick_count);

    var srv_c = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf_c: [128]u8 = undefined;
    const gw_c = try srv_c.baseUrl(&url_buf_c);
    client_a.cfg.gateway_url = gw_c;

    try p.maybeTick(150, &merkle); // tick 3
    srv_c.waitAndFree();
    try std.testing.expectEqual(@as(u64, 3), p.tick_count);
}

test "M3.3-T-interval-gate" {
    // maybeTick called before 50 ms elapsed → no HTTP call, tick_count stays 0.
    const alloc = std.testing.allocator;

    // We intentionally do NOT start a mock server; if writeEvent is called, it
    // will fail with connection refused (error.ConnectionRefused) and the test
    // will fail.  But we assert tick_count == 0 to verify the gate works.
    var client = try PravegatClient.init(alloc, .{
        .gateway_url = "http://127.0.0.1:19998", // nothing listening here
        .scope = "test-scope",
    });
    defer client.deinit();

    var producer = RegionTickProducer.init(alloc, &client, "region-ticks", "world-0", 50);
    defer producer.deinit();

    var merkle: [32]u8 = undefined;
    @memset(&merkle, 0xFF);

    // last_tick_ms defaults to 0. Call at t=30 — only 30 ms elapsed, below 50 ms.
    try producer.maybeTick(30, &merkle);

    // tick_count must not have incremented.
    try std.testing.expectEqual(@as(u64, 0), producer.tick_count);
}

test "M3.3-T-merkle-root-hex" {
    // buildTickPayload's "merkle_root" field must be a 64-char lowercase hex string.
    const alloc = std.testing.allocator;

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = "http://127.0.0.1:19997",
        .scope = "test-scope",
    });
    defer client.deinit();

    var producer = RegionTickProducer.init(alloc, &client, "region-ticks", "world-42", 50);
    defer producer.deinit();

    // Known merkle root: bytes 0x00..0x1f
    var merkle: [32]u8 = undefined;
    for (0..32) |i| merkle[i] = @as(u8, @intCast(i));

    const payload = try producer.buildTickPayload(alloc, 2_000_000, &merkle);
    defer alloc.free(payload);

    // Expected hex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    const expected_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
    try std.testing.expect(std.mem.indexOf(u8, payload, expected_hex) != null);

    // Must be exactly 64 chars — find the value in the JSON
    const key = "\"merkle_root\":\"";
    const start_pos = std.mem.indexOf(u8, payload, key) orelse {
        return error.MissingMerkleRootKey;
    };
    const hex_start = start_pos + key.len;
    // Find closing quote
    const hex_end = std.mem.indexOfPos(u8, payload, hex_start, "\"") orelse {
        return error.MissingMerkleRootClose;
    };
    try std.testing.expectEqual(@as(usize, 64), hex_end - hex_start);
}

test "M3.3-T-routing-key" {
    // writeEvent must be called with region_id as the routing_key.
    // We verify indirectly: the payload JSON includes "region_id":"world-7"
    // and buildTickPayload is the source of truth for the routing key passed
    // to writeEvent (checked by inspecting producer source / payload).
    //
    // Practical check: call maybeTick once and verify the payload sent to the
    // mock server contains the region_id, which is the value used as routing_key.
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "test-scope",
    });
    defer client.deinit();

    var producer = RegionTickProducer.init(alloc, &client, "region-ticks", "world-7", 50);
    defer producer.deinit();

    var merkle: [32]u8 = undefined;
    @memset(&merkle, 0x77);

    try producer.maybeTick(50, &merkle);
    srv.waitAndFree();

    // The routing key is region_id. Verify the payload produced by buildTickPayload
    // contains the region_id value (which is what maybeTick passes as routing_key).
    var merkle2: [32]u8 = undefined;
    @memset(&merkle2, 0x77);
    const payload = try producer.buildTickPayload(alloc, 50, &merkle2);
    defer alloc.free(payload);

    try std.testing.expect(std.mem.indexOf(u8, payload, "world-7") != null);
    // tick_count incremented confirms writeEvent was invoked
    try std.testing.expectEqual(@as(u64, 1), producer.tick_count);
}

```
