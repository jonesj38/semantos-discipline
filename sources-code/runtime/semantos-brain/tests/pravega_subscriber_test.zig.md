---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/pravega_subscriber_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.181824+00:00
---

# runtime/semantos-brain/tests/pravega_subscriber_test.zig

```zig
// M3.7 — PravegatSubscriber conformance tests (mock HTTP server, no real Pravega).
//
// Test IDs:
//   M3.7-T-subscribe-creates-rg-and-reader : subscribe() calls createReaderGroup then
//       createReader; handle holds both names
//   M3.7-T-readnext-returns-event-json     : readNext() returns event JSON from mock 200
//   M3.7-T-readnext-returns-null-on-empty  : readNext() returns null when mock returns 200
//       with empty body
//   M3.7-T-handle-deinit-frees             : handle.deinit() runs without crash (test alloc)
//   M3.7-T-multi-stream-subscribe          : subscribe called twice; each handle has distinct
//       rg_name
//
// Run: zig build test-pravega-subscriber

const std = @import("std");
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;
const PravegatConfig = pravega_client.PravegatConfig;
const pravega_subscriber = @import("pravega_subscriber");
const PravegatSubscriber = pravega_subscriber.PravegatSubscriber;

// ─── Response type ───────────────────────────────────────────────────────────

const MockResponse = struct {
    status: u16,
    body: []const u8,
    content_type: []const u8 = "application/json",
};

// ─── Connection handler ──────────────────────────────────────────────────────

fn handleOne(stream: std.net.Stream, response: MockResponse) void {
    var req_buf: [8192]u8 = undefined;
    _ = stream.read(&req_buf) catch return;

    var header_buf: [512]u8 = undefined;
    const status_text: []const u8 = switch (response.status) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        409 => "Conflict",
        500 => "Internal Server Error",
        else => "Unknown",
    };
    const header = std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ response.status, status_text, response.content_type, response.body.len },
    ) catch return;
    _ = stream.writeAll(header) catch return;
    _ = stream.writeAll(response.body) catch return;
}

// ─── MultiShotServer ─────────────────────────────────────────────────────────
//
// A reusable mock HTTP server that can serve a fixed number of sequential
// connections (one response per connection), each with its own canned response.
//
// Up to 8 responses can be registered. The server background thread handles
// them in order then exits.

const MAX_RESPONSES = 8;

const MultiShotServer = struct {
    thread: std.Thread,
    port: u16,

    const Context = struct {
        server: *std.net.Server,
        responses: [MAX_RESPONSES]MockResponse,
        count: usize,
    };

    pub fn start(responses: []const MockResponse) !MultiShotServer {
        std.debug.assert(responses.len <= MAX_RESPONSES);

        const addr = try std.net.Address.parseIp("127.0.0.1", 0);
        const srv = try std.heap.c_allocator.create(std.net.Server);
        srv.* = try addr.listen(.{ .reuse_address = true });
        const port: u16 = srv.listen_address.in.getPort();

        const ctx = try std.heap.c_allocator.create(Context);
        ctx.server = srv;
        ctx.count = responses.len;
        for (responses, 0..) |r, i| ctx.responses[i] = r;

        const thread = try std.Thread.spawn(.{}, runServer, .{ctx});
        return MultiShotServer{ .thread = thread, .port = port };
    }

    fn runServer(ctx: *Context) void {
        defer std.heap.c_allocator.destroy(ctx);
        const srv = ctx.server;
        defer {
            srv.deinit();
            std.heap.c_allocator.destroy(srv);
        }
        for (0..ctx.count) |i| {
            const conn = srv.accept() catch return;
            defer conn.stream.close();
            handleOne(conn.stream, ctx.responses[i]);
        }
    }

    pub fn waitAndFree(self: *MultiShotServer) void {
        self.thread.join();
    }

    pub fn baseUrl(self: *const MultiShotServer, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "http://127.0.0.1:{d}", .{self.port});
    }
};

// ─── Tests ───────────────────────────────────────────────────────────────────

test "M3.7-T-subscribe-creates-rg-and-reader" {
    // subscribe() must:
    //   1. POST /readergroups → receive rg_name (201)
    //   2. POST /readers      → receive reader_id (201)
    //   3. Return a SubscriptionHandle with non-empty rg_name, reader_id, and
    //      a copy of the stream name.
    const alloc = std.testing.allocator;

    // Two-shot server: first connection = createReaderGroup, second = createReader.
    var srv = try MultiShotServer.start(&.{
        .{ .status = 201, .body = "" }, // createReaderGroup
        .{ .status = 201, .body = "" }, // createReader
    });
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gw,
        .scope = "test-scope",
    });
    defer client.deinit();

    var sub = PravegatSubscriber.init(alloc, &client);
    defer sub.deinit();

    var handle = try sub.subscribe("tick-stream");
    defer handle.deinit();

    srv.waitAndFree();

    // Handle must carry the stream name.
    try std.testing.expectEqualStrings("tick-stream", handle.stream);
    // rg_name and reader_id must be non-empty (generated by PravegatClient).
    try std.testing.expect(handle.rg_name.len > 0);
    try std.testing.expect(handle.reader_id.len > 0);
}

test "M3.7-T-readnext-returns-event-json" {
    // readNext() must return the event body when the mock returns 200 with content.
    const alloc = std.testing.allocator;

    const event_body = "{\"kind\":\"region_tick\",\"tick\":42}";

    // Three-shot: createReaderGroup, createReader, readEvent.
    var srv = try MultiShotServer.start(&.{
        .{ .status = 201, .body = "" },         // createReaderGroup
        .{ .status = 201, .body = "" },         // createReader
        .{ .status = 200, .body = event_body }, // readEvent
    });
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gw,
        .scope = "test-scope",
    });
    defer client.deinit();

    var sub = PravegatSubscriber.init(alloc, &client);
    defer sub.deinit();

    var handle = try sub.subscribe("tick-stream");
    defer handle.deinit();

    const event = try sub.readNext(&handle);
    defer if (event) |e| alloc.free(e);

    srv.waitAndFree();

    try std.testing.expect(event != null);
    try std.testing.expectEqualStrings(event_body, event.?);
}

test "M3.7-T-readnext-returns-null-on-empty" {
    // readNext() must return null when mock returns 200 with empty body.
    const alloc = std.testing.allocator;

    // Three-shot: createReaderGroup, createReader, readEvent (empty → null).
    var srv = try MultiShotServer.start(&.{
        .{ .status = 201, .body = "" }, // createReaderGroup
        .{ .status = 201, .body = "" }, // createReader
        .{ .status = 200, .body = "" }, // readEvent → empty → null
    });
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gw,
        .scope = "test-scope",
    });
    defer client.deinit();

    var sub = PravegatSubscriber.init(alloc, &client);
    defer sub.deinit();

    var handle = try sub.subscribe("utxo-stream");
    defer handle.deinit();

    const result = try sub.readNext(&handle);

    srv.waitAndFree();

    try std.testing.expect(result == null);
}

test "M3.7-T-handle-deinit-frees" {
    // handle.deinit() must free stream, rg_name, and reader_id without crashing.
    // Verified by std.testing.allocator which reports leaks at test end.
    const alloc = std.testing.allocator;

    var srv = try MultiShotServer.start(&.{
        .{ .status = 201, .body = "" }, // createReaderGroup
        .{ .status = 201, .body = "" }, // createReader
    });
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gw,
        .scope = "test-scope",
    });
    defer client.deinit();

    var sub = PravegatSubscriber.init(alloc, &client);
    defer sub.deinit();

    var handle = try sub.subscribe("identity-stream");
    srv.waitAndFree();

    // deinit must free all three owned slices — no crash, no leak.
    handle.deinit();
}

test "M3.7-T-multi-stream-subscribe" {
    // subscribe() called twice for two different streams; each handle must have
    // a distinct rg_name (the generated name embeds a nanosecond timestamp).
    const alloc = std.testing.allocator;

    // Four POSTs: rg1, reader1, rg2, reader2.
    var srv = try MultiShotServer.start(&.{
        .{ .status = 201, .body = "" }, // createReaderGroup for stream-a
        .{ .status = 201, .body = "" }, // createReader for stream-a
        .{ .status = 201, .body = "" }, // createReaderGroup for stream-b
        .{ .status = 201, .body = "" }, // createReader for stream-b
    });
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gw,
        .scope = "test-scope",
    });
    defer client.deinit();

    var sub = PravegatSubscriber.init(alloc, &client);
    defer sub.deinit();

    var handle_a = try sub.subscribe("stream-a");
    defer handle_a.deinit();

    // 1 µs pause so the nanosecond timestamp in the generated rg_name differs.
    std.Thread.sleep(1_000);

    var handle_b = try sub.subscribe("stream-b");
    defer handle_b.deinit();

    srv.waitAndFree();

    // Each handle must be bound to its own stream.
    try std.testing.expectEqualStrings("stream-a", handle_a.stream);
    try std.testing.expectEqualStrings("stream-b", handle_b.stream);

    // rg_names must differ (timestamps in the generated names make them unique).
    try std.testing.expect(!std.mem.eql(u8, handle_a.rg_name, handle_b.rg_name));
}

```
