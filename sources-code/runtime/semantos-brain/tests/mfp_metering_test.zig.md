---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/mfp_metering_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.178786+00:00
---

# runtime/semantos-brain/tests/mfp_metering_test.zig

```zig
// M4.3 — MfpMeter metering tests (mock HTTP server, no real Pravega).
//
// Test IDs:
//   M4.3-T-charge-emits-tick            : chargeAndEmit with budget=10 succeeds and decrements to 9
//   M4.3-T-budget-exhausted-returns-error: chargeAndEmit with budget=0 returns error.BudgetExhausted
//   M4.3-T-budget-decrements-each-call  : three chargeAndEmit calls decrement budget by 3
//   M4.3-T-tick-emitted-on-success      : mock HTTP server receives exactly one POST per chargeAndEmit
//   M4.3-T-emit-failure-non-fatal       : if producer HTTP call fails (mock 500), chargeAndEmit still
//                                         succeeds (budget still decremented, fetch allowed)
//
// Run: zig build test-mfp-metering

const std = @import("std");
const mfp_metering = @import("mfp_metering");
const MfpMeter = mfp_metering.MfpMeter;
const MfpMeteringConfig = mfp_metering.MfpMeteringConfig;
const mfp_tick_producer = @import("mfp_tick_producer");
const MfpTickProducer = mfp_tick_producer.MfpTickProducer;
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;
const PravegatConfig = pravega_client.PravegatConfig;

// ─── MockHttpServer ──────────────────────────────────────────────────────────
//
// Same pattern as mfp_tick_producer_test.zig — single-request mock server
// with a shared CapturedRequest struct protected by a mutex.

const MockHttpServer = struct {
    thread: std.Thread,
    port: u16,
    captured: *CapturedRequest,

    const CapturedRequest = struct {
        body: [4096]u8 = undefined,
        body_len: usize = 0,
        path: [512]u8 = undefined,
        path_len: usize = 0,
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
        captured: *CapturedRequest,
    };

    pub fn start(alloc: std.mem.Allocator, response: Response) !MockHttpServer {
        _ = alloc;

        const addr = try std.net.Address.parseIp("127.0.0.1", 0);
        const srv = try std.heap.c_allocator.create(std.net.Server);
        srv.* = try addr.listen(.{ .reuse_address = true });
        const port: u16 = srv.listen_address.in.getPort();

        const captured = try std.heap.c_allocator.create(CapturedRequest);
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

    pub fn waitAndFree(self: *MockHttpServer) void {
        self.thread.join();
        std.heap.c_allocator.destroy(self.captured);
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

    fn handleConnection(stream: std.net.Stream, response: Response, captured: *CapturedRequest) void {
        var req_buf: [8192]u8 = undefined;
        const n = stream.read(&req_buf) catch return;
        const raw = req_buf[0..n];

        captured.mutex.lock();
        defer captured.mutex.unlock();

        if (std.mem.indexOfScalar(u8, raw, ' ')) |sp1| {
            const after_method = raw[sp1 + 1 ..];
            if (std.mem.indexOfScalar(u8, after_method, ' ')) |sp2| {
                const path_slice = after_method[0..sp2];
                const copy_len = @min(path_slice.len, captured.path.len);
                @memcpy(captured.path[0..copy_len], path_slice[0..copy_len]);
                captured.path_len = copy_len;
            }
        }

        if (std.mem.indexOf(u8, raw, "\r\n\r\n")) |header_end| {
            const body_slice = raw[header_end + 4 ..];
            const copy_len = @min(body_slice.len, captured.body.len);
            @memcpy(captured.body[0..copy_len], body_slice[0..copy_len]);
            captured.body_len = copy_len;
        }

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

// ─── Helper ──────────────────────────────────────────────────────────────────

fn makeSecret() [32]u8 {
    return [_]u8{0xAB} ** 32;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test "M4.3-T-charge-emits-tick" {
    // chargeAndEmit with budget=10 succeeds and decrements budget to 9.
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{ .gateway_url = gw, .scope = "s" });
    defer client.deinit();

    var producer = MfpTickProducer.init(alloc, &client, "mfp-ticks", "chan-meter");
    defer producer.deinit();

    var meter = MfpMeter.init(.{
        .initial_budget_sats = 10,
        .secret = makeSecret(),
        .channel_id = "chan-meter",
    }, &producer);

    try meter.chargeAndEmit(1_000);
    srv.waitAndFree();

    try std.testing.expectEqual(@as(u64, 9), meter.budget_remaining_sats);
}

test "M4.3-T-budget-exhausted-returns-error" {
    // chargeAndEmit with budget=0 returns error.BudgetExhausted without
    // touching the HTTP stack.
    const alloc = std.testing.allocator;

    // No mock server needed — the call must fail before any HTTP request.
    var client = try PravegatClient.init(alloc, .{
        .gateway_url = "http://127.0.0.1:1", // unreachable; must never be called
        .scope = "s",
    });
    defer client.deinit();

    var producer = MfpTickProducer.init(alloc, &client, "mfp-ticks", "chan-zero");
    defer producer.deinit();

    var meter = MfpMeter.init(.{
        .initial_budget_sats = 0,
        .secret = makeSecret(),
        .channel_id = "chan-zero",
    }, &producer);

    const result = meter.chargeAndEmit(1_000);
    try std.testing.expectError(error.BudgetExhausted, result);
    // Budget must still be 0.
    try std.testing.expectEqual(@as(u64, 0), meter.budget_remaining_sats);
}

test "M4.3-T-budget-decrements-each-call" {
    // Three chargeAndEmit calls decrement budget by 3 (10 → 7).
    const alloc = std.testing.allocator;

    // Need 3 separate mock servers (each handles one request).
    var srv0 = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var srv1 = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var srv2 = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });

    var url_buf0: [128]u8 = undefined;
    var url_buf1: [128]u8 = undefined;
    var url_buf2: [128]u8 = undefined;
    const gw0 = try srv0.baseUrl(&url_buf0);
    const gw1 = try srv1.baseUrl(&url_buf1);
    const gw2 = try srv2.baseUrl(&url_buf2);

    var client0 = try PravegatClient.init(alloc, .{ .gateway_url = gw0, .scope = "s" });
    defer client0.deinit();
    var client1 = try PravegatClient.init(alloc, .{ .gateway_url = gw1, .scope = "s" });
    defer client1.deinit();
    var client2 = try PravegatClient.init(alloc, .{ .gateway_url = gw2, .scope = "s" });
    defer client2.deinit();

    var producer = MfpTickProducer.init(alloc, &client0, "mfp-ticks", "chan-dec");
    defer producer.deinit();

    var meter = MfpMeter.init(.{
        .initial_budget_sats = 10,
        .secret = makeSecret(),
        .channel_id = "chan-dec",
    }, &producer);

    try meter.chargeAndEmit(1_000);
    srv0.waitAndFree();

    producer.client = &client1;
    try meter.chargeAndEmit(2_000);
    srv1.waitAndFree();

    producer.client = &client2;
    try meter.chargeAndEmit(3_000);
    srv2.waitAndFree();

    try std.testing.expectEqual(@as(u64, 7), meter.budget_remaining_sats);
}

test "M4.3-T-tick-emitted-on-success" {
    // Mock HTTP server receives exactly one POST per chargeAndEmit call.
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{ .gateway_url = gw, .scope = "s" });
    defer client.deinit();

    var producer = MfpTickProducer.init(alloc, &client, "mfp-ticks", "chan-emit");
    defer producer.deinit();

    var meter = MfpMeter.init(.{
        .initial_budget_sats = 5,
        .secret = makeSecret(),
        .channel_id = "chan-emit",
    }, &producer);

    try meter.chargeAndEmit(42_000);
    srv.waitAndFree();

    // The mock handled exactly one request (it exits after one accept()).
    // Verify the captured body is non-empty — meaning a POST was received.
    try std.testing.expect(srv.captured.body_len > 0);
    // The body should contain the channel_id field.
    const body = srv.captured.body[0..srv.captured.body_len];
    try std.testing.expect(std.mem.indexOf(u8, body, "chan-emit") != null);
}

test "M4.3-T-emit-failure-non-fatal" {
    // If the MFP producer's HTTP call fails (mock returns 500), chargeAndEmit
    // still succeeds: budget is decremented and no error is returned.
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 500, .body = "server error" });
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{ .gateway_url = gw, .scope = "s" });
    defer client.deinit();

    var producer = MfpTickProducer.init(alloc, &client, "mfp-ticks", "chan-fail");
    defer producer.deinit();

    var meter = MfpMeter.init(.{
        .initial_budget_sats = 3,
        .secret = makeSecret(),
        .channel_id = "chan-fail",
    }, &producer);

    // Must succeed despite the 500 response.
    try meter.chargeAndEmit(99_000);
    srv.waitAndFree();

    // Budget must still have been decremented.
    try std.testing.expectEqual(@as(u64, 2), meter.budget_remaining_sats);
}

```
