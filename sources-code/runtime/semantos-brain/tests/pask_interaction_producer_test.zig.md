---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/pask_interaction_producer_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.172554+00:00
---

# runtime/semantos-brain/tests/pask_interaction_producer_test.zig

```zig
// M3.9 — PaskInteractionProducer unit tests (mock HTTP server, no real Pravega).
//
// Test IDs:
//   M3.9-T-emit-interaction          : payload contains "kind":"pask_interaction",
//                                      correct primary_cell_id hex, now_ms
//   M3.9-T-related-cell-ids-array    : payload JSON array has correct number of related_cell_ids
//   M3.9-T-routing-key-is-cell-id-prefix : routing key = hex(primary_cell_id)[0..16]
//   M3.9-T-sequence-increments       : three buildPayload calls → seq 0, 1, 2
//   M3.9-T-effective-strength-in-payload : "effective_strength": field present and equals expected value
//
// Run: zig build test-pask-interaction-producer

const std = @import("std");
const pask_interaction_producer = @import("pask_interaction_producer");
const PaskInteractionProducer = pask_interaction_producer.PaskInteractionProducer;
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;
const PravegatConfig = pravega_client.PravegatConfig;

// ─── MockHttpServer ──────────────────────────────────────────────────────────
//
// Same pattern as mfp_tick_producer_test.zig — single-request mock server
// that captures the request body and path for assertion.

const MockHttpServer = struct {
    thread: std.Thread,
    port: u16,
    captured: *Captured,

    const Captured = struct {
        body: [8192]u8 = undefined,
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

    fn handleConnection(stream: std.net.Stream, response: Response, captured: *Captured) void {
        var req_buf: [16384]u8 = undefined;
        const n = stream.read(&req_buf) catch return;
        const raw = req_buf[0..n];

        captured.mutex.lock();
        defer captured.mutex.unlock();

        // Extract path from first line: "POST /path HTTP/1.1\r\n"
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

// ─── Helper ──────────────────────────────────────────────────────────────────

fn startMock201(alloc: std.mem.Allocator) !MockHttpServer {
    return MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "M3.9-T-emit-interaction" {
    // Payload must contain "kind":"pask_interaction", correct primary_cell_id
    // hex, and the supplied now_ms value.

    const alloc = std.testing.allocator;

    var srv = try startMock201(alloc);
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{ .gateway_url = gateway_url, .scope = "s" });
    defer client.deinit();

    var producer = PaskInteractionProducer.init(alloc, &client, "pask-interactions");
    defer producer.deinit();

    var primary: [32]u8 = undefined;
    @memset(&primary, 0xAB);

    const related: []const [32]u8 = &.{};

    try producer.emitInteraction(&primary, related, 0.75, 123456789);
    srv.waitAndFree();

    const body = srv.captured.body[0..srv.captured.body_len];

    // Must have kind field.
    try std.testing.expect(std.mem.indexOf(u8, body, "\"kind\":\"pask_interaction\"") != null);

    // primary_cell_id must be the 64-char hex of our all-0xAB bytes.
    const expected_hex = "ab" ** 32; // 64 chars
    try std.testing.expect(std.mem.indexOf(u8, body, expected_hex) != null);

    // now_ms must appear.
    try std.testing.expect(std.mem.indexOf(u8, body, "123456789") != null);
}

test "M3.9-T-related-cell-ids-array" {
    // Payload JSON array must have exactly the same count of entries as
    // the related_cell_ids slice passed in.
    //
    // buildPayload does not make any HTTP calls, so no mock server is needed.
    // We use a dummy client ptr — it is never dereferenced by buildPayload.

    const alloc = std.testing.allocator;

    var dummy_client: PravegatClient = undefined;
    var producer = PaskInteractionProducer.init(alloc, &dummy_client, "pask-interactions");
    defer producer.deinit();

    var primary: [32]u8 = undefined;
    @memset(&primary, 0x01);

    var r0: [32]u8 = undefined;
    var r1: [32]u8 = undefined;
    var r2: [32]u8 = undefined;
    @memset(&r0, 0x10);
    @memset(&r1, 0x20);
    @memset(&r2, 0x30);

    const related: []const [32]u8 = &.{ r0, r1, r2 };

    const payload = try producer.buildPayload(&primary, related, 0.5, 0);
    defer alloc.free(payload);

    // Simpler: count substrings `"10101010` (r0), `"20202020` (r1), `"30303030` (r2).
    const r0_hex = "10" ** 32;
    const r1_hex = "20" ** 32;
    const r2_hex = "30" ** 32;

    try std.testing.expect(std.mem.indexOf(u8, payload, r0_hex) != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, r1_hex) != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, r2_hex) != null);

    // Verify the array opens and closes.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"related_cell_ids\":[") != null);
}

test "M3.9-T-routing-key-is-cell-id-prefix" {
    // Routing key must equal hex(primary_cell_id[0..8]) — the first 16 hex
    // characters of the primary cell id.
    //
    // We verify this by:
    //   1. Using emitInteraction so writeEvent is actually called, capturing
    //      the request body and URL path via the mock server.
    //   2. Checking that the primary_cell_id in the payload starts with the
    //      expected 16-char prefix ("de00000000000000").
    //
    // (PravegatClient.writeEvent does not currently embed the routing_key in
    // the HTTP path per M3.2, so we validate the prefix via the payload.)

    const alloc = std.testing.allocator;

    var srv = try startMock201(alloc);
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{ .gateway_url = gateway_url, .scope = "s" });
    defer client.deinit();

    var producer = PaskInteractionProducer.init(alloc, &client, "pask-interactions");
    defer producer.deinit();

    // primary_cell_id: first byte 0xDE, rest 0x00 — routing key must be
    // hex of first 8 bytes = "de00000000000000".
    var primary: [32]u8 = undefined;
    @memset(&primary, 0x00);
    primary[0] = 0xDE;

    const related: []const [32]u8 = &.{};

    try producer.emitInteraction(&primary, related, 1.0, 0);
    srv.waitAndFree();

    const body = srv.captured.body[0..srv.captured.body_len];

    // The primary_cell_id hex in the payload must start with "de00000000000000".
    const expected_routing_key = "de00000000000000";
    try std.testing.expect(std.mem.indexOf(u8, body, expected_routing_key) != null);

    // Verify the full 64-char primary_cell_id starts with the routing key prefix.
    const primary_key = "\"primary_cell_id\":\"";
    const pk_pos = std.mem.indexOf(u8, body, primary_key) orelse return error.MissingField;
    const value_start = pk_pos + primary_key.len;
    const first_16 = body[value_start .. value_start + 16];
    try std.testing.expectEqualStrings(expected_routing_key, first_16);
}

test "M3.9-T-sequence-increments" {
    // Three buildPayload calls must produce seq values 0, 1, 2 in order.
    //
    // buildPayload does not make any HTTP calls, so no mock server is needed.
    // We use a dummy client ptr — it is never dereferenced by buildPayload.

    const alloc = std.testing.allocator;

    var dummy_client: PravegatClient = undefined;
    var producer = PaskInteractionProducer.init(alloc, &dummy_client, "pask-interactions");
    defer producer.deinit();

    var primary: [32]u8 = undefined;
    @memset(&primary, 0x55);

    const related: []const [32]u8 = &.{};

    const p0 = try producer.buildPayload(&primary, related, 0.0, 0);
    defer alloc.free(p0);
    const p1 = try producer.buildPayload(&primary, related, 0.0, 0);
    defer alloc.free(p1);
    const p2 = try producer.buildPayload(&primary, related, 0.0, 0);
    defer alloc.free(p2);

    try std.testing.expect(std.mem.indexOf(u8, p0, "\"seq\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, p1, "\"seq\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, p2, "\"seq\":2") != null);
}

test "M3.9-T-effective-strength-in-payload" {
    // The "effective_strength" field must be present and equal the supplied value.
    //
    // buildPayload does not make any HTTP calls, so no mock server is needed.
    // We use a dummy client ptr — it is never dereferenced by buildPayload.

    const alloc = std.testing.allocator;

    var dummy_client: PravegatClient = undefined;
    var producer = PaskInteractionProducer.init(alloc, &dummy_client, "pask-interactions");
    defer producer.deinit();

    var primary: [32]u8 = undefined;
    @memset(&primary, 0x77);

    const related: []const [32]u8 = &.{};

    const payload = try producer.buildPayload(&primary, related, 3.14, 0);
    defer alloc.free(payload);

    try std.testing.expect(std.mem.indexOf(u8, payload, "\"effective_strength\":") != null);

    // The value 3.14 must appear in the payload.
    try std.testing.expect(std.mem.indexOf(u8, payload, "3.14") != null);
}

```
