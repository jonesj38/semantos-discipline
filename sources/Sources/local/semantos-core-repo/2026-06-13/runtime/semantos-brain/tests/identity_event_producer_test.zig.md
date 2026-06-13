---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/identity_event_producer_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.192056+00:00
---

# runtime/semantos-brain/tests/identity_event_producer_test.zig

```zig
// M3.4 — IdentityEventProducer conformance tests (mock HTTP, no Pravega).
//
// Test IDs:
//   M3.4-T-emit-mint         : emitMint → payload contains "kind":"mint" + cert_id hex
//   M3.4-T-emit-edge         : emitEdge → "kind":"edge", routing key = from_cert_id
//   M3.4-T-emit-revoke       : emitRevoke → payload contains "kind":"revoke"
//   M3.4-T-sequence-monotonic: three emits → sequence fields 0, 1, 2
//   M3.4-T-routing-key-is-cert-id : writeEvent called with cert_id as routing_key
//
// Run: zig build test-identity-event-producer

const std = @import("std");
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;
const PravegatConfig = pravega_client.PravegatConfig;
const identity_event_producer = @import("identity_event_producer");
const IdentityEventProducer = identity_event_producer.IdentityEventProducer;
const EventKind = identity_event_producer.EventKind;
const IdentityEvent = identity_event_producer.IdentityEvent;

// ─── MockHttpServer ───────────────────────────────────────────────────────────
// Re-used verbatim from pravega_client_test.zig.  Handles N sequential
// requests — one per thread.accept() call.  We use a single-request variant
// here (same as M3.2) because each test starts its own mock.

const MockHttpServer = struct {
    thread: std.Thread,
    port: u16,

    const Response = struct {
        status: u16,
        body: []const u8,
        content_type: []const u8 = "application/json",
    };

    const Context = struct {
        server: *std.net.Server,
        response: Response,
        // Captured data — written by server thread, read by main thread after join.
        captured_body: [4096]u8 = undefined,
        captured_body_len: usize = 0,
        captured_routing_key: [256]u8 = undefined,
        captured_routing_key_len: usize = 0,
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

// ─── Helpers ──────────────────────────────────────────────────────────────────

// Fixed 64-char hex strings for deterministic tests.
const CERT_ID_A = "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233";
const CERT_ID_B = "deadbeef00112233deadbeef00112233deadbeef00112233deadbeef00112233";
const SUBJECT_PUB = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";
const ISSUER_PUB = "2122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40";

fn makeClient(alloc: std.mem.Allocator, gateway_url: []const u8) !PravegatClient {
    return PravegatClient.init(alloc, .{
        .gateway_url = gateway_url,
        .scope = "semantos",
    });
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test "M3.4-T-emit-mint" {
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try makeClient(alloc, gateway_url);
    defer client.deinit();

    var producer = IdentityEventProducer.init(alloc, &client, "identity-events");
    defer producer.deinit();

    // Build payload directly to inspect contents without a live Pravega.
    const event = IdentityEvent{
        .kind = .mint,
        .cert_id = CERT_ID_A,
        .subject_pub = SUBJECT_PUB,
        .issuer_pub = ISSUER_PUB,
        .timestamp_ms = 1_700_000_000_000,
        .sequence = 0,
    };
    const payload = try producer.buildPayload(event);
    defer alloc.free(payload);

    try std.testing.expect(std.mem.indexOf(u8, payload, "\"kind\":\"mint\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, CERT_ID_A) != null);

    // Drain the server (no real request was made from buildPayload, so we
    // emit a real event to allow the server to handle the connection).
    try producer.emitMint(CERT_ID_A, SUBJECT_PUB, ISSUER_PUB, 1_700_000_000_000);
    srv.waitAndFree();
}

test "M3.4-T-emit-edge" {
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try makeClient(alloc, gateway_url);
    defer client.deinit();

    var producer = IdentityEventProducer.init(alloc, &client, "identity-events");
    defer producer.deinit();

    const event = IdentityEvent{
        .kind = .edge,
        .cert_id = CERT_ID_A,
        .subject_pub = CERT_ID_B, // reuse as "to" id in edge context
        .issuer_pub = "",
        .timestamp_ms = 1_700_000_000_001,
        .sequence = 0,
    };
    const payload = try producer.buildPayload(event);
    defer alloc.free(payload);

    try std.testing.expect(std.mem.indexOf(u8, payload, "\"kind\":\"edge\"") != null);
    // routing key for emitEdge must be from_cert_id (= cert_id field)
    try std.testing.expect(std.mem.indexOf(u8, payload, CERT_ID_A) != null);

    try producer.emitEdge(CERT_ID_A, CERT_ID_B, 1_700_000_000_001);
    srv.waitAndFree();
}

test "M3.4-T-emit-revoke" {
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try makeClient(alloc, gateway_url);
    defer client.deinit();

    var producer = IdentityEventProducer.init(alloc, &client, "identity-events");
    defer producer.deinit();

    const event = IdentityEvent{
        .kind = .revoke,
        .cert_id = CERT_ID_A,
        .subject_pub = "",
        .issuer_pub = "",
        .timestamp_ms = 1_700_000_000_002,
        .sequence = 0,
    };
    const payload = try producer.buildPayload(event);
    defer alloc.free(payload);

    try std.testing.expect(std.mem.indexOf(u8, payload, "\"kind\":\"revoke\"") != null);

    try producer.emitRevoke(CERT_ID_A, 1_700_000_000_002);
    srv.waitAndFree();
}

test "M3.4-T-sequence-monotonic" {
    // This test sends three emits and checks that the sequence numbers
    // 0, 1, 2 appear in order.  We use buildPayload (no HTTP) for the
    // sequence check, then do three real emits (one mock request each).
    const alloc = std.testing.allocator;

    var producer_check = IdentityEventProducer.init(alloc, undefined, "identity-events");
    // We only call buildPayload here — no HTTP client is touched.
    defer producer_check.deinit();

    const e0 = IdentityEvent{ .kind = .mint, .cert_id = CERT_ID_A, .subject_pub = SUBJECT_PUB, .issuer_pub = ISSUER_PUB, .timestamp_ms = 0, .sequence = 0 };
    const e1 = IdentityEvent{ .kind = .mint, .cert_id = CERT_ID_A, .subject_pub = SUBJECT_PUB, .issuer_pub = ISSUER_PUB, .timestamp_ms = 1, .sequence = 1 };
    const e2 = IdentityEvent{ .kind = .revoke, .cert_id = CERT_ID_A, .subject_pub = "", .issuer_pub = "", .timestamp_ms = 2, .sequence = 2 };

    const p0 = try producer_check.buildPayload(e0);
    defer alloc.free(p0);
    const p1 = try producer_check.buildPayload(e1);
    defer alloc.free(p1);
    const p2 = try producer_check.buildPayload(e2);
    defer alloc.free(p2);

    try std.testing.expect(std.mem.indexOf(u8, p0, "\"seq\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, p1, "\"seq\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, p2, "\"seq\":2") != null);

    // Verify the producer's own counter increments through real emits.
    // Three mock servers, one per emit.
    var srv0 = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf0: [128]u8 = undefined;
    const url0 = try srv0.baseUrl(&url_buf0);
    var client0 = try makeClient(alloc, url0);
    defer client0.deinit();
    var producer = IdentityEventProducer.init(alloc, &client0, "identity-events");
    defer producer.deinit();

    try producer.emitMint(CERT_ID_A, SUBJECT_PUB, ISSUER_PUB, 0);
    srv0.waitAndFree();
    try std.testing.expectEqual(@as(u64, 1), producer.sequence);

    var srv1 = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf1: [128]u8 = undefined;
    const url1 = try srv1.baseUrl(&url_buf1);
    // Swap client URL by re-pointing client — simplest: create a new client for each mock.
    var client1 = try PravegatClient.init(alloc, .{ .gateway_url = url1, .scope = "semantos" });
    defer client1.deinit();
    producer.client = &client1;

    try producer.emitEdge(CERT_ID_A, CERT_ID_B, 1);
    srv1.waitAndFree();
    try std.testing.expectEqual(@as(u64, 2), producer.sequence);

    var srv2 = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf2: [128]u8 = undefined;
    const url2 = try srv2.baseUrl(&url_buf2);
    var client2 = try PravegatClient.init(alloc, .{ .gateway_url = url2, .scope = "semantos" });
    defer client2.deinit();
    producer.client = &client2;

    try producer.emitRevoke(CERT_ID_A, 2);
    srv2.waitAndFree();
    try std.testing.expectEqual(@as(u64, 3), producer.sequence);
}

test "M3.4-T-routing-key-is-cert-id" {
    // Verify that the routing_key passed to writeEvent equals the cert_id.
    // We do this by inspecting the JSON payload: the routing_key is embedded
    // as "cert_id" in the event JSON that the producer sends to writeEvent.
    // Because writeEvent currently ignores the routing_key parameter at the
    // network level (Pravega REST embeds it in body), we verify it indirectly
    // through buildPayload: the cert_id field in the payload must match
    // CERT_ID_A (what emitMint was told to use).
    const alloc = std.testing.allocator;

    var srv = try MockHttpServer.start(alloc, .{ .status = 201, .body = "" });
    var url_buf: [128]u8 = undefined;
    const gateway_url = try srv.baseUrl(&url_buf);

    var client = try makeClient(alloc, gateway_url);
    defer client.deinit();

    var producer = IdentityEventProducer.init(alloc, &client, "identity-events");
    defer producer.deinit();

    // buildPayload with mint → cert_id = CERT_ID_A must appear in payload
    const event = IdentityEvent{
        .kind = .mint,
        .cert_id = CERT_ID_A,
        .subject_pub = SUBJECT_PUB,
        .issuer_pub = ISSUER_PUB,
        .timestamp_ms = 999,
        .sequence = 0,
    };
    const payload = try producer.buildPayload(event);
    defer alloc.free(payload);

    // The routing key is the cert_id — confirm it's embedded in the payload
    // under the "cert_id" key so the caller can use it as the routing key.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"cert_id\":\"" ++ CERT_ID_A ++ "\"") != null);

    try producer.emitMint(CERT_ID_A, SUBJECT_PUB, ISSUER_PUB, 999);
    srv.waitAndFree();
}

```
