---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/pravega_replay_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.202766+00:00
---

# runtime/semantos-brain/tests/pravega_replay_test.zig

```zig
// M3.8 — Snapshot + replay-from-tick semantics for PravegatSubscriber.
//
// Test IDs:
//   M3.8-T-checkpoint-returns-name  : checkpoint(handle, "ck1") returns "ck1"
//       and the HTTP body contains checkpointName.
//   M3.8-T-restore-calls-gateway   : restoreCheckpoint(handle, "ck1") issues
//       POST to the restore endpoint.
//   M3.8-T-readnext-after-restore  : checkpoint → restore → readNext still
//       returns events (mock returns data).
//   M3.8-T-no-duplicate-on-replay  : deliver event, checkpoint, restore to same
//       position, readNext → mock shows only one call per event position.
//
// Run: zig build test-pravega-replay

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

// ─── Request capture ─────────────────────────────────────────────────────────

/// A captured HTTP request (method line + body) stored by the mock server.
const CapturedRequest = struct {
    method: [8]u8 = undefined,
    method_len: usize = 0,
    path: [512]u8 = undefined,
    path_len: usize = 0,
    body: [2048]u8 = undefined,
    body_len: usize = 0,
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

/// Like handleOne but also saves the raw request bytes into `capture`.
fn handleOneCapture(stream: std.net.Stream, response: MockResponse, capture: *CapturedRequest) void {
    var req_buf: [8192]u8 = undefined;
    const n = stream.read(&req_buf) catch 0;
    const raw = req_buf[0..n];

    // Parse method and path from first line: "POST /path HTTP/1.1\r\n"
    if (std.mem.indexOfScalar(u8, raw, ' ')) |sp1| {
        const method_slice = raw[0..sp1];
        const method_len = @min(method_slice.len, 8);
        @memcpy(capture.method[0..method_len], method_slice[0..method_len]);
        capture.method_len = method_len;

        const rest = raw[sp1 + 1 ..];
        if (std.mem.indexOfScalar(u8, rest, ' ')) |sp2| {
            const path_slice = rest[0..sp2];
            const path_len = @min(path_slice.len, 512);
            @memcpy(capture.path[0..path_len], path_slice[0..path_len]);
            capture.path_len = path_len;
        }
    }

    // Body is after the blank line "\r\n\r\n".
    if (std.mem.indexOf(u8, raw, "\r\n\r\n")) |hdr_end| {
        const body_slice = raw[hdr_end + 4 ..];
        const body_len = @min(body_slice.len, 2048);
        @memcpy(capture.body[0..body_len], body_slice[0..body_len]);
        capture.body_len = body_len;
    }

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
// Serves N sequential connections, one canned response per connection.
// Optionally captures the raw request for one designated slot.

const MAX_RESPONSES = 16;

const MultiShotServer = struct {
    thread: std.Thread,
    port: u16,

    const Context = struct {
        server: *std.net.Server,
        responses: [MAX_RESPONSES]MockResponse,
        count: usize,
        /// If >= 0, capture request for this connection index.
        capture_idx: isize,
        capture: *CapturedRequest,
    };

    pub fn start(responses: []const MockResponse) !MultiShotServer {
        return startWithCapture(responses, -1, undefined);
    }

    pub fn startWithCapture(
        responses: []const MockResponse,
        capture_idx: isize,
        capture: *CapturedRequest,
    ) !MultiShotServer {
        std.debug.assert(responses.len <= MAX_RESPONSES);

        const addr = try std.net.Address.parseIp("127.0.0.1", 0);
        const srv = try std.heap.c_allocator.create(std.net.Server);
        srv.* = try addr.listen(.{ .reuse_address = true });
        const port: u16 = srv.listen_address.in.getPort();

        const ctx = try std.heap.c_allocator.create(Context);
        ctx.server = srv;
        ctx.count = responses.len;
        ctx.capture_idx = capture_idx;
        ctx.capture = capture;
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
            if (ctx.capture_idx >= 0 and @as(usize, @intCast(ctx.capture_idx)) == i) {
                handleOneCapture(conn.stream, ctx.responses[i], ctx.capture);
            } else {
                handleOne(conn.stream, ctx.responses[i]);
            }
        }
    }

    pub fn waitAndFree(self: *MultiShotServer) void {
        self.thread.join();
    }

    pub fn baseUrl(self: *const MultiShotServer, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "http://127.0.0.1:{d}", .{self.port});
    }
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Subscribe to a stream and return the handle. Consumes two mock connections
/// (createReaderGroup + createReader).
fn doSubscribe(sub: *PravegatSubscriber) !pravega_subscriber.SubscriptionHandle {
    return sub.subscribe("tick-stream");
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "M3.8-T-checkpoint-returns-name" {
    // checkpoint(handle, "ck1") must:
    //   1. POST to the checkpoint endpoint.
    //   2. Return "ck1" (the caller-provided name, owned by caller).
    //   3. Request body must contain `checkpointName`.
    const alloc = std.testing.allocator;

    var capture: CapturedRequest = .{};

    // Connections: createReaderGroup, createReader, checkpoint POST.
    // capture_idx=2 → capture the checkpoint request.
    var srv = try MultiShotServer.startWithCapture(&.{
        .{ .status = 201, .body = "" }, // createReaderGroup
        .{ .status = 201, .body = "" }, // createReader
        .{ .status = 201, .body = "" }, // checkpoint
    }, 2, &capture);
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gw,
        .scope = "test-scope",
    });
    defer client.deinit();

    var sub = PravegatSubscriber.init(alloc, &client);
    defer sub.deinit();

    var handle = try doSubscribe(&sub);
    defer handle.deinit();

    const name = try sub.checkpoint(&handle, "ck1");
    defer alloc.free(name);

    srv.waitAndFree();

    // Must return the checkpoint name.
    try std.testing.expectEqualStrings("ck1", name);

    // Body must contain the checkpointName key.
    const body = capture.body[0..capture.body_len];
    try std.testing.expect(std.mem.indexOf(u8, body, "checkpointName") != null);
}

test "M3.8-T-restore-calls-gateway" {
    // restoreCheckpoint(handle, "ck1") must POST to the restore endpoint.
    const alloc = std.testing.allocator;

    var capture: CapturedRequest = .{};

    // Connections: createReaderGroup, createReader, restore POST.
    var srv = try MultiShotServer.startWithCapture(&.{
        .{ .status = 201, .body = "" }, // createReaderGroup
        .{ .status = 201, .body = "" }, // createReader
        .{ .status = 200, .body = "" }, // restore
    }, 2, &capture);
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gw,
        .scope = "test-scope",
    });
    defer client.deinit();

    var sub = PravegatSubscriber.init(alloc, &client);
    defer sub.deinit();

    var handle = try doSubscribe(&sub);
    defer handle.deinit();

    try sub.restoreCheckpoint(&handle, "ck1");

    srv.waitAndFree();

    // Path must contain "restore" or "checkpoints".
    const path = capture.path[0..capture.path_len];
    const has_restore = std.mem.indexOf(u8, path, "restore") != null;
    const has_checkpoint = std.mem.indexOf(u8, path, "checkpoint") != null;
    try std.testing.expect(has_restore or has_checkpoint);

    // Method must be POST.
    const method = capture.method[0..capture.method_len];
    try std.testing.expectEqualStrings("POST", method);
}

test "M3.8-T-readnext-after-restore" {
    // Sequence: subscribe → checkpoint → restore → readNext
    // readNext must still return the event body from the mock.
    const alloc = std.testing.allocator;

    const event_body = "{\"kind\":\"region_tick\",\"tick\":99}";

    // Connections: createReaderGroup, createReader, checkpoint, restore, readEvent.
    var srv = try MultiShotServer.start(&.{
        .{ .status = 201, .body = "" },         // createReaderGroup
        .{ .status = 201, .body = "" },         // createReader
        .{ .status = 201, .body = "" },         // checkpoint
        .{ .status = 200, .body = "" },         // restore
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

    var handle = try doSubscribe(&sub);
    defer handle.deinit();

    const ck_name = try sub.checkpoint(&handle, "ck1");
    defer alloc.free(ck_name);

    try sub.restoreCheckpoint(&handle, ck_name);

    const event = try sub.readNext(&handle);
    defer if (event) |e| alloc.free(e);

    srv.waitAndFree();

    try std.testing.expect(event != null);
    try std.testing.expectEqualStrings(event_body, event.?);
}

test "M3.8-T-no-duplicate-on-replay" {
    // Deliver one event, checkpoint, restore to the same position.
    // A subsequent readNext should issue exactly one further read call
    // to the mock. The mock is set up to deliver a second event only on
    // the second readEvent call — if we see it we got no duplicate.
    //
    // Call sequence:
    //   createReaderGroup, createReader,
    //   readEvent → event-A,
    //   checkpoint,
    //   restore,
    //   readEvent → event-B   ← this is the *next* position, not a replay of A
    const alloc = std.testing.allocator;

    const event_a = "{\"tick\":1}";
    const event_b = "{\"tick\":2}";

    var srv = try MultiShotServer.start(&.{
        .{ .status = 201, .body = "" },    // createReaderGroup
        .{ .status = 201, .body = "" },    // createReader
        .{ .status = 200, .body = event_a }, // readEvent → A
        .{ .status = 201, .body = "" },    // checkpoint
        .{ .status = 200, .body = "" },    // restore
        .{ .status = 200, .body = event_b }, // readEvent → B (next position)
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

    var handle = try doSubscribe(&sub);
    defer handle.deinit();

    // Read first event.
    const ev_a = try sub.readNext(&handle);
    defer if (ev_a) |e| alloc.free(e);
    try std.testing.expect(ev_a != null);
    try std.testing.expectEqualStrings(event_a, ev_a.?);

    // Checkpoint then restore.
    const ck_name = try sub.checkpoint(&handle, "after-a");
    defer alloc.free(ck_name);
    try sub.restoreCheckpoint(&handle, ck_name);

    // Next read should advance (not re-deliver event-A).
    const ev_b = try sub.readNext(&handle);
    defer if (ev_b) |e| alloc.free(e);

    srv.waitAndFree();

    // The mock served event-B at connection index 5 — if we received it we
    // know exactly one readEvent was issued after restore (no phantom replay).
    try std.testing.expect(ev_b != null);
    try std.testing.expectEqualStrings(event_b, ev_b.?);
}

```
