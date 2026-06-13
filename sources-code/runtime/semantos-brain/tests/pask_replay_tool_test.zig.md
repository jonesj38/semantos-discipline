---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/pask_replay_tool_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.212054+00:00
---

# runtime/semantos-brain/tests/pask_replay_tool_test.zig

```zig
// M3.10 — PaskReplayTool conformance tests (mock HTTP server, no real Pravega).
//
// Test IDs:
//   M3.10-T-empty-stream   : 0 events → events_processed == 0, snapshot has PASK magic
//   M3.10-T-single-event   : 1 event  → events_processed == 1, snapshot has PASK magic
//   M3.10-T-determinism    : replay same 3 events twice → both snapshots byte-identical
//   M3.10-T-seq-monotonic  : events with seq 0,1,2 → no crash, events_processed == 3
//
// Run: zig build test-pask-replay-tool

const std = @import("std");
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;
const PravegatConfig = pravega_client.PravegatConfig;
const pravega_subscriber = @import("pravega_subscriber");
const PravegatSubscriber = pravega_subscriber.PravegatSubscriber;
const pask_replay_tool = @import("pask_replay_tool");
const PaskReplayTool = pask_replay_tool.PaskReplayTool;

// ── Snapshot magic constant (matches pask/src/main.zig) ──────────────────────
const SNAPSHOT_MAGIC: u32 = 0x4B534150;

// ── Mock HTTP helpers ─────────────────────────────────────────────────────────

const MockResponse = struct {
    status: u16,
    body: []const u8,
    content_type: []const u8 = "application/json",
};

fn handleOne(stream: std.net.Stream, response: MockResponse) void {
    var req_buf: [8192]u8 = undefined;
    _ = stream.read(&req_buf) catch return;

    var header_buf: [512]u8 = undefined;
    const status_text: []const u8 = switch (response.status) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
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

// ── MultiShotServer ───────────────────────────────────────────────────────────
//
// Serves up to MAX_RESPONSES sequential connections, one canned response each.
// Adapted from the existing test pattern in pravega_subscriber_test.zig.

const MAX_RESPONSES = 16;

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

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Build the server-response list needed to drive one replayFromGenesis call:
///   - 201 for createReaderGroup
///   - 201 for createReader
///   - one 200+body per event
///   - one 200+empty to signal end-of-stream (readNext returns null)
///
/// `responses` must be large enough: 2 + events.len + 1
fn fillResponses(
    out: []MockResponse,
    events: []const []const u8,
) void {
    var i: usize = 0;
    out[i] = .{ .status = 201, .body = "" }; // createReaderGroup
    i += 1;
    out[i] = .{ .status = 201, .body = "" }; // createReader
    i += 1;
    for (events) |ev| {
        out[i] = .{ .status = 200, .body = ev };
        i += 1;
    }
    out[i] = .{ .status = 200, .body = "" }; // end-of-stream
}

/// Sample event JSON payloads. All use distinct but fixed 64-hex cell IDs.
const EVT_A =
    \\{"kind":"pask_interaction","primary_cell_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","related_cell_ids":["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],"effective_strength":0.5,"now_ms":1000,"seq":0}
;
const EVT_B =
    \\{"kind":"pask_interaction","primary_cell_id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","related_cell_ids":["cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"],"effective_strength":0.3,"now_ms":2000,"seq":1}
;
const EVT_C =
    \\{"kind":"pask_interaction","primary_cell_id":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","related_cell_ids":[],"effective_strength":0.8,"now_ms":3000,"seq":2}
;

// ── Tests ─────────────────────────────────────────────────────────────────────

test "M3.10-T-empty-stream" {
    // Stream with 0 events: events_processed == 0, snapshot has PASK magic header.
    const alloc = std.testing.allocator;

    var responses: [3]MockResponse = undefined;
    fillResponses(&responses, &.{});

    var srv = try MultiShotServer.start(&responses);
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gw,
        .scope = "test-scope",
    });
    defer client.deinit();

    var sub = PravegatSubscriber.init(alloc, &client);
    defer sub.deinit();

    var tool = PaskReplayTool.init(alloc, &sub);
    defer tool.deinit();

    const result = try tool.replayFromGenesis("pask-interactions");
    defer alloc.free(result.snapshot);

    srv.waitAndFree();

    try std.testing.expectEqual(@as(u64, 0), result.events_processed);
    // Snapshot must be non-empty and start with PASK magic.
    try std.testing.expect(result.snapshot.len >= 12);
    const magic = std.mem.readInt(u32, result.snapshot[0..4], .little);
    try std.testing.expectEqual(SNAPSHOT_MAGIC, magic);
}

test "M3.10-T-single-event" {
    // Stream with 1 event: events_processed == 1, snapshot has PASK magic.
    const alloc = std.testing.allocator;

    var responses: [4]MockResponse = undefined;
    fillResponses(&responses, &.{EVT_A});

    var srv = try MultiShotServer.start(&responses);
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gw,
        .scope = "test-scope",
    });
    defer client.deinit();

    var sub = PravegatSubscriber.init(alloc, &client);
    defer sub.deinit();

    var tool = PaskReplayTool.init(alloc, &sub);
    defer tool.deinit();

    const result = try tool.replayFromGenesis("pask-interactions");
    defer alloc.free(result.snapshot);

    srv.waitAndFree();

    try std.testing.expectEqual(@as(u64, 1), result.events_processed);
    try std.testing.expect(result.snapshot.len >= 12);
    const magic = std.mem.readInt(u32, result.snapshot[0..4], .little);
    try std.testing.expectEqual(SNAPSHOT_MAGIC, magic);
}

test "M3.10-T-determinism" {
    // Replay the same 3 events twice — both snapshots must be byte-identical.
    const alloc = std.testing.allocator;
    const events: []const []const u8 = &.{ EVT_A, EVT_B, EVT_C };

    // First replay.
    var responses1: [6]MockResponse = undefined;
    fillResponses(&responses1, events);
    var srv1 = try MultiShotServer.start(&responses1);
    var url_buf1: [128]u8 = undefined;
    const gw1 = try srv1.baseUrl(&url_buf1);

    var client1 = try PravegatClient.init(alloc, .{
        .gateway_url = gw1,
        .scope = "test-scope",
    });
    defer client1.deinit();
    var sub1 = PravegatSubscriber.init(alloc, &client1);
    defer sub1.deinit();
    var tool1 = PaskReplayTool.init(alloc, &sub1);
    defer tool1.deinit();

    const result1 = try tool1.replayFromGenesis("pask-interactions");
    defer alloc.free(result1.snapshot);
    srv1.waitAndFree();

    // Second replay (fresh server, fresh client).
    var responses2: [6]MockResponse = undefined;
    fillResponses(&responses2, events);
    var srv2 = try MultiShotServer.start(&responses2);
    var url_buf2: [128]u8 = undefined;
    const gw2 = try srv2.baseUrl(&url_buf2);

    var client2 = try PravegatClient.init(alloc, .{
        .gateway_url = gw2,
        .scope = "test-scope",
    });
    defer client2.deinit();
    var sub2 = PravegatSubscriber.init(alloc, &client2);
    defer sub2.deinit();
    var tool2 = PaskReplayTool.init(alloc, &sub2);
    defer tool2.deinit();

    const result2 = try tool2.replayFromGenesis("pask-interactions");
    defer alloc.free(result2.snapshot);
    srv2.waitAndFree();

    // Both replays processed the same number of events.
    try std.testing.expectEqual(result1.events_processed, result2.events_processed);

    // Snapshots must be byte-identical (determinism property).
    try std.testing.expectEqual(result1.snapshot.len, result2.snapshot.len);
    try std.testing.expectEqualSlices(u8, result1.snapshot, result2.snapshot);
}

test "M3.10-T-seq-monotonic" {
    // Events with seq 0,1,2 processed without error.
    // We do not verify the seq in the snapshot — just that the tool doesn't crash.
    const alloc = std.testing.allocator;
    const events: []const []const u8 = &.{ EVT_A, EVT_B, EVT_C };

    var responses: [6]MockResponse = undefined;
    fillResponses(&responses, events);

    var srv = try MultiShotServer.start(&responses);
    var url_buf: [128]u8 = undefined;
    const gw = try srv.baseUrl(&url_buf);

    var client = try PravegatClient.init(alloc, .{
        .gateway_url = gw,
        .scope = "test-scope",
    });
    defer client.deinit();

    var sub = PravegatSubscriber.init(alloc, &client);
    defer sub.deinit();

    var tool = PaskReplayTool.init(alloc, &sub);
    defer tool.deinit();

    const result = try tool.replayFromGenesis("pask-interactions");
    defer alloc.free(result.snapshot);

    srv.waitAndFree();

    try std.testing.expectEqual(@as(u64, 3), result.events_processed);
    // Snapshot is valid.
    try std.testing.expect(result.snapshot.len >= 12);
    const magic = std.mem.readInt(u32, result.snapshot[0..4], .little);
    try std.testing.expectEqual(SNAPSHOT_MAGIC, magic);
}

```
