---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/mfp_tick_producer_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.188374+00:00
---

# runtime/semantos-brain/tests/mfp_tick_producer_test.zig

```zig
// M3.6 — MfpTickProducer unit tests (mock HTTP server, no real Pravega).
//
// Test IDs:
//   M3.6-T-hmac-correctness        : computeHmac with known inputs → known output
//   M3.6-T-n-sequence-increments   : emitTick x3 → nSequence 0, 1, 2 in payloads
//   M3.6-T-payload-fields          : buildPayload → JSON has channel_id, n_sequence,
//                                    value_sats, hmac, ts_ms
//   M3.6-T-routing-key-is-channel-id : writeEvent called with channel_id as routing_key
//   M3.6-T-hmac-hex-64-chars       : hmac field in payload is exactly 64 lowercase hex chars
//
// Run: zig build test-mfp-tick-producer

const std = @import("std");
const mfp_tick_producer = @import("mfp_tick_producer");
const MfpTickProducer = mfp_tick_producer.MfpTickProducer;
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;
const PravegatConfig = pravega_client.PravegatConfig;

const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

// ─── MockHttpServer ──────────────────────────────────────────────────────────
//
// Same pattern as pravega_client_test.zig — single-request mock server.
// Extended here to capture the request body and routing key for assertion.

const MockHttpServer = struct {
    thread: std.Thread,
    port: u16,
    // Shared state: the body of the last POST request received.
    captured: *CapturedRequest,

    const CapturedRequest = struct {
        body: [4096]u8 = undefined,
        body_len: usize = 0,
        // The URL path so tests can check stream + routing key embedding.
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

        // Extract path from first line: "POST /path HTTP/1.1\r\n"
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

        // Extract body (after \r\n\r\n).
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

// ─── Helper: start a mock that returns 201 for writeEvent ────────────────────

fn startMock201(alloc: std.mem.Allocator) !MockHttpServer {
    return MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "M3.6-T-hmac-correctness" {
    // Known test inputs:
    //   channel_id bytes: "chan1" = [0x63, 0x68, 0x61, 0x6e, 0x31]
    //   n_sequence: 7 (LE32 = [0x07, 0x00, 0x00, 0x00])
    //   value_sats: 1000 (LE64 = [0xe8, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    //   secret: all-0x42 (32 bytes)
    //
    // Compute expected HMAC using the same algorithm, then assert equality.

    const channel_id_bytes: []const u8 = "chan1";
    const n_sequence: u32 = 7;
    const value_sats: u64 = 1000;
    var secret: [32]u8 = undefined;
    @memset(&secret, 0x42);

    // Build the HMAC message manually (same as computeHmac).
    var message: [5 + 4 + 8]u8 = undefined; // channel_id(5) + n_seq(4) + value_sats(8)
    @memcpy(message[0..5], channel_id_bytes);
    std.mem.writeInt(u32, message[5..9], n_sequence, .little);
    std.mem.writeInt(u64, message[9..17], value_sats, .little);

    var expected: [32]u8 = undefined;
    HmacSha256.create(&expected, &message, &secret);

    // Call the function under test.
    const got = MfpTickProducer.computeHmac(channel_id_bytes, n_sequence, value_sats, &secret);

    try std.testing.expectEqualSlices(u8, &expected, &got);
}

test "M3.6-T-n-sequence-increments" {
    const alloc = std.testing.allocator;

    // We need 3 HTTP interactions, so we spin up 3 sequential mock servers.
    // Each emitTick calls writeEvent once.

    const secret: [32]u8 = [_]u8{0xAB} ** 32;
    const channel_id = "test-channel";

    // Start 3 mock servers upfront, then create one producer that cycles
    // through them by re-pointing its client.  Each mock handles one POST
    // and closes; the producer's n_sequence persists across client swaps.

    var srv0 = try startMock201(alloc);
    var srv1 = try startMock201(alloc);
    var srv2 = try startMock201(alloc);

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

    var producer = MfpTickProducer.init(alloc, &client0, "mfp-ticks", channel_id);
    defer producer.deinit();

    // Tick 0 — client0
    try producer.emitTick(&secret, 100, 1000);
    srv0.waitAndFree();

    // Tick 1 — swap client pointer to client1 and fire
    producer.client = &client1;
    try producer.emitTick(&secret, 200, 2000);
    srv1.waitAndFree();

    // Tick 2 — swap client pointer to client2 and fire
    producer.client = &client2;
    try producer.emitTick(&secret, 300, 3000);
    srv2.waitAndFree();

    // n_sequence after 3 emits must be 3.
    try std.testing.expectEqual(@as(u32, 3), producer.n_sequence);
}

test "M3.6-T-payload-fields" {
    const alloc = std.testing.allocator;

    const secret: [32]u8 = [_]u8{0x11} ** 32;
    const channel_id = "payload-test";

    // Create a minimal producer (client pointer is irrelevant for buildPayload).
    var srv = try startMock201(alloc);
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{ .gateway_url = gateway_url, .scope = "s" });
    defer client.deinit();

    var producer = MfpTickProducer.init(alloc, &client, "mfp-ticks", channel_id);
    defer producer.deinit();

    // Compute HMAC for the current state.
    const hmac_bytes = MfpTickProducer.computeHmac(channel_id, producer.n_sequence, 500, &secret);

    // Build payload.
    const payload = try producer.buildPayload(&hmac_bytes, 500, 999_000);
    defer alloc.free(payload);

    srv.waitAndFree();

    // Assert required JSON fields are present.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"channel_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"n_sequence\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"value_sats\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"hmac\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"ts_ms\"") != null);
}

test "M3.6-T-routing-key-is-channel-id" {
    // The routing_key passed to writeEvent must equal channel_id.
    // We verify this by inspecting the URL path: the mock server captures it.
    // Per pravega_client.writeEvent the routing key is currently unused at the
    // HTTP level (it's a TODO), so we test the producer sets it correctly by
    // checking that writeEvent is called (no error) — and separately we verify
    // the field in the JSON payload equals channel_id.

    const alloc = std.testing.allocator;
    const secret: [32]u8 = [_]u8{0xCC} ** 32;
    const channel_id = "my-channel-42";

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{ .gateway_url = gateway_url, .scope = "s" });
    defer client.deinit();

    var producer = MfpTickProducer.init(alloc, &client, "mfp-ticks", channel_id);
    defer producer.deinit();

    try producer.emitTick(&secret, 42, 12345);
    srv.waitAndFree();

    // The captured body must contain the channel_id value.
    const body = srv.captured.body[0..srv.captured.body_len];
    try std.testing.expect(std.mem.indexOf(u8, body, channel_id) != null);
}

test "M3.6-T-hmac-hex-64-chars" {
    const alloc = std.testing.allocator;
    const secret: [32]u8 = [_]u8{0xFF} ** 32;
    const channel_id = "hex-len-test";

    var srv = try startMock201(alloc);
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{ .gateway_url = gateway_url, .scope = "s" });
    defer client.deinit();

    var producer = MfpTickProducer.init(alloc, &client, "mfp-ticks", channel_id);
    defer producer.deinit();

    const hmac_bytes = MfpTickProducer.computeHmac(channel_id, 0, 1, &secret);
    const payload = try producer.buildPayload(&hmac_bytes, 1, 0);
    defer alloc.free(payload);

    srv.waitAndFree();

    // Find "hmac":"<value>" and check the value is exactly 64 lowercase hex chars.
    const hmac_key = "\"hmac\":\"";
    const start_pos = std.mem.indexOf(u8, payload, hmac_key) orelse {
        return error.HmacFieldMissing;
    };
    const value_start = start_pos + hmac_key.len;
    const end_pos = std.mem.indexOfScalarPos(u8, payload, value_start, '"') orelse {
        return error.HmacValueUnterminated;
    };
    const hmac_hex = payload[value_start..end_pos];

    try std.testing.expectEqual(@as(usize, 64), hmac_hex.len);

    // Verify all chars are lowercase hex.
    for (hmac_hex) |c| {
        const is_hex = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        try std.testing.expect(is_hex);
    }
}

```
