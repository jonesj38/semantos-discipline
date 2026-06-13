---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/events_stream_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.173976+00:00
---

# runtime/semantos-brain/tests/events_stream_handler_conformance.zig

```zig
// W3.2 — EventsStreamHandler conformance tests.
//
// Test IDs:
//   W3.2-T-upgrade-succeeds:
//     GET /api/v1/events?hat=0x000101 with WS headers → 101 Switching Protocols
//
//   W3.2-T-event-forwarded:
//     Emitting a job FSM event on the bus forwards the correct JSON frame
//     to a connected WebSocket client.
//
//   W3.2-T-hat-filter:
//     Events for a different hat are NOT forwarded to the connected client.
//
//   W3.2-T-resume-replay:
//     Client connecting with resume_after=<event_id> receives missed events
//     from the ring buffer before the live stream.
//
//   W3.2-T-json-shape:
//     Forwarded JSON has all required fields in the W1.4 wire shape:
//     {event_id, job_id, cell_id, from_state, to_state, ts_ms, hat_id}
//
//   W3.2-T-missing-hat-rejected:
//     GET /api/v1/events without hat param → 400 Bad Request (HTTP, not WS).
//
// Run: zig build test-events-stream-handler
//
// Pattern mirrors wss_wallet_conformance.zig:
//   - Bind a loopback listener.
//   - Run the server side in a background thread.
//   - Drive the client side (handshake + frames) from the main thread.
//   - Assert frame content.

const std = @import("std");
const wss_codec = @import("wss_codec");
const events_stream_handler = @import("events_stream_handler");
const oddjobz_event_bus = @import("oddjobz_event_bus");

const OddjobzEventBus = oddjobz_event_bus.OddjobzEventBus;

// ─── Test helpers ──────────────────────────────────────────────────────────

const Bound = struct {
    listener: std.net.Server,
    address: std.net.Address,

    fn deinit(self: *Bound) void {
        self.listener.deinit();
    }
};

fn bindLoopback() !Bound {
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    const listener = try addr.listen(.{ .reuse_address = true });
    return .{ .listener = listener, .address = listener.listen_address };
}

/// Build a raw GET-upgrade HTTP request for /api/v1/events with the given
/// query string.  Writes the request to `stream`.
fn sendUpgradeRequest(stream: std.net.Stream, path_and_query: []const u8) !void {
    var buf: [1024]u8 = undefined;
    const req = try std.fmt.bufPrint(
        &buf,
        "GET {s} HTTP/1.1\r\n" ++
            "Host: localhost\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n" ++
            "Sec-WebSocket-Version: 13\r\n" ++
            "\r\n",
        .{path_and_query},
    );
    try stream.writeAll(req);
}

/// Read the HTTP response status line from `stream`.  Returns the status
/// code as a number (e.g. 101, 400).
///
/// Reads one byte at a time until the `\r\n\r\n` end-of-headers marker.
/// This is deliberate: when the server writes 101 followed immediately by
/// WebSocket frames (e.g. the resume-replay path), the kernel can coalesce
/// the response and the frames into a single read.  A larger read would
/// pull those frame bytes into this buffer and silently drop them on the
/// floor, deadlocking the next readClientFrame.  Byte-at-a-time keeps the
/// frames on the wire for the WS reader.
fn readResponseStatus(stream: std.net.Stream) !u16 {
    var buf: [4096]u8 = undefined;
    var total: usize = 0;
    while (total < buf.len) {
        const n = try stream.read(buf[total .. total + 1]);
        if (n == 0) return error.Eof;
        total += n;
        if (total >= 4 and std.mem.eql(u8, buf[total - 4 .. total], "\r\n\r\n")) break;
    }
    const resp = buf[0..total];
    // "HTTP/1.1 <3-digit-code> "
    const sp1 = std.mem.indexOfScalar(u8, resp, ' ') orelse return error.BadResponse;
    const after = resp[sp1 + 1 ..];
    const sp2 = std.mem.indexOfScalar(u8, after, ' ') orelse return error.BadResponse;
    return std.fmt.parseInt(u16, after[0..sp2], 10) catch error.BadResponse;
}

/// Context passed to the server-side background thread.
const ServeCtx = struct {
    listener: *std.net.Server,
    allocator: std.mem.Allocator,
    bus: *OddjobzEventBus,
    hat: []const u8,
    resume_after: []const u8,
};

/// Background thread: accept one connection, parse the upgrade, serve the
/// session until the client closes.
fn serveOneThread(ctx: *ServeCtx) void {
    const conn = ctx.listener.accept() catch return;
    defer conn.stream.close();

    var read_buf: [8192]u8 = undefined;
    var write_buf: [16384]u8 = undefined;
    var read_iface = conn.stream.reader(&read_buf);
    var write_iface = conn.stream.writer(&write_buf);
    var server = std.http.Server.init(read_iface.interface(), &write_iface.interface);
    var request = server.receiveHead() catch return;

    var hat_buf: [128]u8 = undefined;
    var hat_len: usize = 0;
    var resume_buf: [16]u8 = undefined;
    var has_resume: bool = false;

    const result = events_stream_handler.tryUpgrade(
        &request,
        conn.stream,
        &hat_buf,
        &hat_len,
        &resume_buf,
        &has_resume,
    ) catch return;

    if (result != .upgraded) return;

    const hat_slice = hat_buf[0..hat_len];
    const resume_slice: []const u8 = if (has_resume) &resume_buf else "";
    events_stream_handler.serveSession(
        ctx.allocator,
        conn.stream,
        ctx.bus,
        hat_slice,
        resume_slice,
    );
}

// ─── W3.2-T-upgrade-succeeds ───────────────────────────────────────────────
//
// GET /api/v1/events?hat=0x000101 with correct WS headers → 101.

test "W3.2-T-upgrade-succeeds: WS upgrade to /api/v1/events returns 101" {
    const allocator = std.testing.allocator;
    var bus = OddjobzEventBus.init(allocator);
    defer bus.deinit();

    var bound = try bindLoopback();
    defer bound.deinit();

    // Start server thread.
    var ctx = ServeCtx{
        .listener = &bound.listener,
        .allocator = allocator,
        .bus = &bus,
        .hat = "0x000101",
        .resume_after = "",
    };
    const thr = try std.Thread.spawn(.{}, serveOneThread, .{&ctx});

    // Connect as client and send the upgrade request.
    const stream = try std.net.tcpConnectToAddress(bound.address);
    defer stream.close();

    try sendUpgradeRequest(stream, "/api/v1/events?hat=0x000101");

    // The server must respond 101.
    const status = try readResponseStatus(stream);
    try std.testing.expectEqual(@as(u16, 101), status);

    // Send a close frame so the server exits cleanly.
    try wss_codec.writeClientFrame(stream, .close, &[_]u8{ 0x03, 0xe8 });

    thr.join();
}

// ─── W3.2-T-missing-hat-rejected ──────────────────────────────────────────
//
// GET /api/v1/events (no hat param) → 400 Bad Request.

const ServeOneHttpCtx = struct {
    listener: *std.net.Server,
    allocator: std.mem.Allocator,
    bus: *OddjobzEventBus,
};

fn serveOneHttpOnly(ctx: *ServeOneHttpCtx) void {
    const conn = ctx.listener.accept() catch return;
    defer conn.stream.close();

    var read_buf: [8192]u8 = undefined;
    var write_buf: [16384]u8 = undefined;
    var read_iface = conn.stream.reader(&read_buf);
    var write_iface = conn.stream.writer(&write_buf);
    var server = std.http.Server.init(read_iface.interface(), &write_iface.interface);
    var request = server.receiveHead() catch return;

    var hat_buf: [128]u8 = undefined;
    var hat_len: usize = 0;
    var resume_buf: [16]u8 = undefined;
    var has_resume: bool = false;

    _ = events_stream_handler.tryUpgrade(
        &request,
        conn.stream,
        &hat_buf,
        &hat_len,
        &resume_buf,
        &has_resume,
    ) catch {};
}

test "W3.2-T-missing-hat-rejected: no hat param returns 400" {
    const allocator = std.testing.allocator;
    var bus = OddjobzEventBus.init(allocator);
    defer bus.deinit();

    var bound = try bindLoopback();
    defer bound.deinit();

    var ctx = ServeOneHttpCtx{
        .listener = &bound.listener,
        .allocator = allocator,
        .bus = &bus,
    };
    const thr = try std.Thread.spawn(.{}, serveOneHttpOnly, .{&ctx});

    const stream = try std.net.tcpConnectToAddress(bound.address);
    defer stream.close();

    // Request without hat param.
    try sendUpgradeRequest(stream, "/api/v1/events");

    const status = try readResponseStatus(stream);
    try std.testing.expectEqual(@as(u16, 400), status);

    thr.join();
}

// ─── W3.2-T-event-forwarded ───────────────────────────────────────────────
//
// Emitting a job FSM event on the bus forwards the correct JSON frame to the
// connected WebSocket client.

/// Background: accept one connection, serve frames, exit on close.
/// The main test thread publishes the event AFTER receiving the 101,
/// so the subscription is already registered when the event fires.
const EventFwdCtx = struct {
    listener: *std.net.Server,
    allocator: std.mem.Allocator,
    bus: *OddjobzEventBus,
    hat: []const u8,
};

fn serveOnly(ctx: *EventFwdCtx) void {
    const conn = ctx.listener.accept() catch return;
    defer conn.stream.close();

    var read_buf: [8192]u8 = undefined;
    var write_buf: [16384]u8 = undefined;
    var read_iface = conn.stream.reader(&read_buf);
    var write_iface = conn.stream.writer(&write_buf);
    var server = std.http.Server.init(read_iface.interface(), &write_iface.interface);
    var request = server.receiveHead() catch return;

    var hat_buf: [128]u8 = undefined;
    var hat_len: usize = 0;
    var resume_buf: [16]u8 = undefined;
    var has_resume: bool = false;

    const result = events_stream_handler.tryUpgrade(
        &request,
        conn.stream,
        &hat_buf,
        &hat_len,
        &resume_buf,
        &has_resume,
    ) catch return;
    if (result != .upgraded) return;

    // serveSession registers the subscription before blocking on readFrame.
    const hat_slice = hat_buf[0..hat_len];
    const resume_slice: []const u8 = if (has_resume) &resume_buf else "";
    events_stream_handler.serveSession(
        ctx.allocator,
        conn.stream,
        ctx.bus,
        hat_slice,
        resume_slice,
    );
}

test "W3.2-T-event-forwarded: published event arrives at connected client" {
    const allocator = std.testing.allocator;
    var bus = OddjobzEventBus.init(allocator);
    defer bus.deinit();

    var bound = try bindLoopback();
    defer bound.deinit();

    var ctx = EventFwdCtx{
        .listener = &bound.listener,
        .allocator = allocator,
        .bus = &bus,
        .hat = "hat-forward",
    };
    const thr = try std.Thread.spawn(.{}, serveOnly, .{&ctx});

    const stream = try std.net.tcpConnectToAddress(bound.address);
    defer stream.close();

    try sendUpgradeRequest(stream, "/api/v1/events?hat=hat-forward");
    // Drain the 101 response — server is now in serveSession, subscription registered.
    _ = try readResponseStatus(stream);

    // Small pause to ensure serveSession has entered its read loop.
    std.Thread.sleep(10 * std.time.ns_per_ms);

    // Publish from the main thread while the server is blocked in readFrame.
    bus.publish("job-fwd-1", "aabb", "lead", "quoted", 5_000_000, "hat-forward");

    // Read the forwarded event frame.
    const frame = try wss_codec.readClientFrame(allocator, stream, 64 * 1024);
    defer allocator.free(frame.payload);

    try std.testing.expectEqual(wss_codec.Opcode.text, frame.opcode);
    // Payload must contain the required JSON fields.
    try std.testing.expect(std.mem.indexOf(u8, frame.payload, "\"event_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, frame.payload, "\"job_id\":\"job-fwd-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, frame.payload, "\"from_state\":\"lead\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, frame.payload, "\"to_state\":\"quoted\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, frame.payload, "\"ts_ms\":5000000") != null);
    try std.testing.expect(std.mem.indexOf(u8, frame.payload, "\"hat_id\":\"hat-forward\"") != null);

    // Close cleanly.
    try wss_codec.writeClientFrame(stream, .close, &[_]u8{ 0x03, 0xe8 });
    thr.join();
}

// ─── W3.2-T-hat-filter ────────────────────────────────────────────────────
//
// Events for a different hat are NOT forwarded to the connected client.

test "W3.2-T-hat-filter: events for wrong hat are not forwarded" {
    const allocator = std.testing.allocator;
    var bus = OddjobzEventBus.init(allocator);
    defer bus.deinit();

    var bound = try bindLoopback();
    defer bound.deinit();

    // Reuse serveOnly — publish comes from the main thread after 101.
    var ctx = EventFwdCtx{
        .listener = &bound.listener,
        .allocator = allocator,
        .bus = &bus,
        .hat = "hat-correct",
    };
    const thr = try std.Thread.spawn(.{}, serveOnly, .{&ctx});

    const stream = try std.net.tcpConnectToAddress(bound.address);
    defer stream.close();

    try sendUpgradeRequest(stream, "/api/v1/events?hat=hat-correct");
    _ = try readResponseStatus(stream);

    // Small pause to ensure serveSession has entered its read loop.
    std.Thread.sleep(10 * std.time.ns_per_ms);

    // Publish one event for the WRONG hat → must NOT be forwarded.
    bus.publish("job-wrong", "cc", "lead", "quoted", 1_000, "hat-OTHER");
    // Publish one event for the RIGHT hat → MUST be forwarded.
    bus.publish("job-right", "dd", "lead", "quoted", 2_000, "hat-correct");

    // Read the ONE frame we expect (the correct hat event).
    const frame = try wss_codec.readClientFrame(allocator, stream, 64 * 1024);
    defer allocator.free(frame.payload);

    try std.testing.expectEqual(wss_codec.Opcode.text, frame.opcode);
    // Must be the right-hat job.
    try std.testing.expect(std.mem.indexOf(u8, frame.payload, "\"job_id\":\"job-right\"") != null);
    // Must NOT be the wrong-hat job.
    try std.testing.expect(std.mem.indexOf(u8, frame.payload, "job-wrong") == null);
    try std.testing.expect(std.mem.indexOf(u8, frame.payload, "hat-OTHER") == null);

    try wss_codec.writeClientFrame(stream, .close, &[_]u8{ 0x03, 0xe8 });
    thr.join();
}

// ─── W3.2-T-resume-replay ─────────────────────────────────────────────────
//
// Client reconnecting with resume_after=<event_id> receives missed events
// from the ring buffer.

const ResumeCtx = struct {
    listener: *std.net.Server,
    allocator: std.mem.Allocator,
    bus: *OddjobzEventBus,
    hat: []const u8,
    resume_after: [16]u8,
};

fn serveWithResume(ctx: *ResumeCtx) void {
    const conn = ctx.listener.accept() catch return;
    defer conn.stream.close();

    var read_buf: [8192]u8 = undefined;
    var write_buf: [16384]u8 = undefined;
    var read_iface = conn.stream.reader(&read_buf);
    var write_iface = conn.stream.writer(&write_buf);
    var server = std.http.Server.init(read_iface.interface(), &write_iface.interface);
    var request = server.receiveHead() catch return;

    var hat_buf: [128]u8 = undefined;
    var hat_len: usize = 0;
    var resume_buf: [16]u8 = undefined;
    var has_resume: bool = false;

    const result = events_stream_handler.tryUpgrade(
        &request,
        conn.stream,
        &hat_buf,
        &hat_len,
        &resume_buf,
        &has_resume,
    ) catch return;
    if (result != .upgraded) return;

    const hat_slice = hat_buf[0..hat_len];
    // Override resume_after with the test's pre-set value.
    const resume_slice: []const u8 = &ctx.resume_after;
    events_stream_handler.serveSession(
        ctx.allocator,
        conn.stream,
        ctx.bus,
        hat_slice,
        resume_slice,
    );
}

test "W3.2-T-resume-replay: reconnect replays missed events from ring buffer" {
    const allocator = std.testing.allocator;
    var bus = OddjobzEventBus.init(allocator);
    defer bus.deinit();

    // Pre-populate the ring with 3 events (same hat).
    bus.publish("job-r1", "aa", "lead", "quoted", 1000, "hat-replay");
    bus.publish("job-r2", "bb", "quoted", "scheduled", 2000, "hat-replay");
    bus.publish("job-r3", "cc", "scheduled", "in_progress", 3000, "hat-replay");

    // Grab the first event's event_id from the ring.
    const ring_events = try bus.fetchSince(allocator, "", 10);
    defer allocator.free(ring_events);
    try std.testing.expectEqual(@as(usize, 3), ring_events.len);

    const first_event_id = ring_events[0].event_id;

    var bound = try bindLoopback();
    defer bound.deinit();

    // Client will resume after the first event → should receive events 2 + 3.
    var ctx = ResumeCtx{
        .listener = &bound.listener,
        .allocator = allocator,
        .bus = &bus,
        .hat = "hat-replay",
        .resume_after = first_event_id,
    };
    const thr = try std.Thread.spawn(.{}, serveWithResume, .{&ctx});

    const stream = try std.net.tcpConnectToAddress(bound.address);
    defer stream.close();

    // Pass resume_after in the query string (matching the first event's id).
    var qbuf: [128]u8 = undefined;
    const path_and_query = try std.fmt.bufPrint(
        &qbuf,
        "/api/v1/events?hat=hat-replay&resume_after={s}",
        .{&first_event_id},
    );
    try sendUpgradeRequest(stream, path_and_query);
    _ = try readResponseStatus(stream);

    // Should receive 2 replayed frames (events 2 + 3).
    const frame1 = try wss_codec.readClientFrame(allocator, stream, 64 * 1024);
    defer allocator.free(frame1.payload);
    const frame2 = try wss_codec.readClientFrame(allocator, stream, 64 * 1024);
    defer allocator.free(frame2.payload);

    try std.testing.expect(std.mem.indexOf(u8, frame1.payload, "\"job_id\":\"job-r2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, frame2.payload, "\"job_id\":\"job-r3\"") != null);

    try wss_codec.writeClientFrame(stream, .close, &[_]u8{ 0x03, 0xe8 });
    thr.join();
}

// ─── W3.2-T-json-shape ────────────────────────────────────────────────────
//
// The serialized JSON has all 7 required fields.

test "W3.2-T-json-shape: serialized event has all required fields" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    const event = oddjobz_event_bus.JobEvent{
        .event_id = "0000000000000042".*,
        .job_id = "job-shape-test",
        .cell_id = "deadbeef01234567",
        .from_state = "in_progress",
        .to_state = "completed",
        .ts_ms = 9_876_543,
        .hat_id = "hat-shape",
    };
    try events_stream_handler.serializeEvent(allocator, &buf, event);

    const json = buf.items;
    // All 7 required fields from the W1.4 wire spec.
    try std.testing.expect(std.mem.indexOf(u8, json, "\"event_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"job_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cell_id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"from_state\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"to_state\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ts_ms\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hat_id\"") != null);

    // Correct values.
    try std.testing.expect(std.mem.indexOf(u8, json, "0000000000000042") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "job-shape-test") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "in_progress") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "completed") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "9876543") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "hat-shape") != null);

    // ts_ms must be a number, not a string.
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ts_ms\":9876543") != null);
}

```
