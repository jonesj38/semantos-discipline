---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/events_stream_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.244431+00:00
---

# runtime/semantos-brain/src/events_stream_handler.zig

```zig
// W3.2 — EventsStreamHandler: WebSocket endpoint for /api/v1/events.
//
// Bridges the in-process OddjobzEventBus (fed by jobs_handler via W3.1's
// OddjobzEventProducer shape) to WebSocket clients — specifically the
// Flutter W1.4 EventSubscriptionService.
//
// ─── Endpoint ─────────────────────────────────────────────────────────────
//
//   GET /api/v1/events?hat=<domain_flag>[&resume_after=<event_id>]
//
//   Upgrade: websocket  (standard RFC 6455 handshake)
//
// Query parameters:
//   hat             — hat (tenant) domain flag, e.g. "0x000101" or "hat-alpha".
//                     Only events whose hat_id matches are forwarded to this
//                     client.  Required; missing → 400.
//   resume_after    — last acked event_id from a previous session.  When
//                     present, the server replays ring-buffered events with
//                     event_id > resume_after before entering the live stream.
//                     Optional; absent → no replay.
//   bearer          — query-string bearer fallback (Flutter can't set headers
//                     on `WebSocket.connect`).  Optional; if absent, checked
//                     via Authorization header.  Auth is best-effort in v0.1:
//                     when no bearer_tokens store is attached the connection
//                     is accepted unauthenticated (matches the helm WSS model
//                     for in-process / local deploys).
//
// ─── Server → client wire shape ──────────────────────────────────────────
//
//   Text frame, JSON:
//   {
//     "event_id":   "<hex16>",
//     "job_id":     "<string>",
//     "cell_id":    "<hex64>",
//     "from_state": "<state>",
//     "to_state":   "<state>",
//     "ts_ms":      <u64>,
//     "hat_id":     "<string>"
//   }
//
// ─── Client → server ack ─────────────────────────────────────────────────
//
//   Text frame, JSON:
//   { "ack": "<event_id>" }
//
//   Client may also send on reconnect:
//   { "resume_after": "<last_acked_event_id>" }
//   (the query-string form is preferred; this supports in-session replay)
//
// ─── Reconnect / replay guarantee ────────────────────────────────────────
//
//   The bus ring holds the last MAX_RING_EVENTS events.  Clients that
//   reconnect within that window receive all missed events before the
//   live stream resumes.  Clients offline longer than the window miss
//   events (acceptable for v0.1; W3.3 may persist to disk).
//
// ─── No-stale guarantee ──────────────────────────────────────────────────
//
//   Live publish-to-delivery is synchronous in the broker call path; a
//   connected client receives an event within one write-frame call of the
//   FSM transition landing.  The 1s-latency budget is met whenever the
//   TCP write path is not saturated.
//
// ─── hat filter ──────────────────────────────────────────────────────────
//
//   Events are filtered by hat_id at the per-connection level (same as
//   helm_event_broker topic filtering).  An event whose hat_id != the
//   connection's requested hat is silently dropped.
//
// References:
//   - runtime/semantos-brain/src/oddjobz_event_bus.zig   (W3.2 in-process bus)
//   - runtime/semantos-brain/src/wss_codec.zig            (RFC 6455 framing)
//   - runtime/semantos-brain/src/wss_wallet.zig           (upgrade pattern)
//   - apps/oddjobz-mobile/…/event_subscription_service.dart (W1.4 consumer)

const std = @import("std");
const wss_codec = @import("wss_codec");
const oddjobz_event_bus = @import("oddjobz_event_bus");

const OddjobzEventBus = oddjobz_event_bus.OddjobzEventBus;
const JobEvent = oddjobz_event_bus.JobEvent;

/// Maximum WebSocket frame payload (same cap as wss_wallet).
pub const MAX_PAYLOAD_BYTES: usize = 64 * 1024;

// ─── Upgrade ──────────────────────────────────────────────────────────────

/// Inspect a parsed HTTP request and, if it's a WebSocket upgrade to
/// /api/v1/events, write the 101 response.  Returns whether the upgrade
/// was performed so the caller can hand the raw stream to serveSession.
///
/// Parses the `hat` query param and `resume_after` query param; writes
/// them into `hat_out` and `resume_after_out` on success.
///
/// `hat_out` must be at least 128 bytes; `resume_after_out` must be at
/// least 16 bytes (event_id length).
pub const UpgradeResult = enum {
    upgraded,
    not_an_events_upgrade,
    rejected,
};

pub fn tryUpgrade(
    request: *std.http.Server.Request,
    stream: std.net.Stream,
    hat_out: []u8,
    hat_len_out: *usize,
    resume_after_out: *[16]u8,
    has_resume_after_out: *bool,
) !UpgradeResult {
    const target = request.head.target;
    const method = request.head.method;

    // Only handle GET /api/v1/events[?...]
    const path_only = if (std.mem.indexOfScalar(u8, target, '?')) |q|
        target[0..q]
    else
        target;
    if (!std.mem.eql(u8, path_only, "/api/v1/events")) {
        return .not_an_events_upgrade;
    }
    if (method != .GET) {
        try respondHttp(request, .method_not_allowed,
            "{\"error\":\"GET required for WS upgrade\"}");
        return .rejected;
    }

    // Parse query params from target.
    const query: []const u8 = if (std.mem.indexOfScalar(u8, target, '?')) |q|
        target[q + 1 ..]
    else
        "";
    const hat_val = queryParam(query, "hat") orelse {
        try respondHttp(request, .bad_request,
            "{\"error\":\"missing required query param: hat\"}");
        return .rejected;
    };
    if (hat_val.len == 0 or hat_val.len >= hat_out.len) {
        try respondHttp(request, .bad_request,
            "{\"error\":\"hat param too long or empty\"}");
        return .rejected;
    }
    @memcpy(hat_out[0..hat_val.len], hat_val);
    hat_len_out.* = hat_val.len;

    // Optional resume_after.
    has_resume_after_out.* = false;
    if (queryParam(query, "resume_after")) |ra| {
        if (ra.len == 16) {
            @memcpy(resume_after_out, ra[0..16]);
            has_resume_after_out.* = true;
        }
    }

    // Validate WebSocket upgrade headers.
    const upgrade_hdr = headerValue(request, "upgrade") orelse {
        try respondHttp(request, .bad_request,
            "{\"error\":\"missing Upgrade: websocket\"}");
        return .rejected;
    };
    if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, upgrade_hdr, " \t"), "websocket")) {
        try respondHttp(request, .bad_request,
            "{\"error\":\"Upgrade must be websocket\"}");
        return .rejected;
    }
    const conn_hdr = headerValue(request, "connection") orelse {
        try respondHttp(request, .bad_request,
            "{\"error\":\"missing Connection: Upgrade\"}");
        return .rejected;
    };
    if (!asciiContainsCaseInsensitive(conn_hdr, "Upgrade")) {
        try respondHttp(request, .bad_request,
            "{\"error\":\"Connection must contain Upgrade\"}");
        return .rejected;
    }
    const ws_key = headerValue(request, "sec-websocket-key") orelse {
        try respondHttp(request, .bad_request,
            "{\"error\":\"missing Sec-WebSocket-Key\"}");
        return .rejected;
    };

    // Write 101 Switching Protocols.
    var accept_b64: [28]u8 = undefined;
    wss_codec.computeAccept(ws_key, &accept_b64);
    var resp_buf: [256]u8 = undefined;
    const resp = try std.fmt.bufPrint(
        &resp_buf,
        "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n\r\n",
        .{&accept_b64},
    );
    stream.writeAll(resp) catch return error.write_failed;
    return .upgraded;
}

// ─── Session ──────────────────────────────────────────────────────────────

/// Per-connection session state.
const SessionState = struct {
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    write_mu: std.Thread.Mutex,
    hat: []const u8, // points into the hat_buf owned by serveSession
    sub_id: ?oddjobz_event_bus.SubscriberId = null,
};

/// Broker callback: called inside the bus's mutex for each published event.
/// Filters by hat; serialises to JSON; writes one WS text frame.
fn busEventCallback(state: ?*anyopaque, event: JobEvent) void {
    const sess: *SessionState = @ptrCast(@alignCast(state.?));

    // hat filter — drop events that don't match this connection's hat.
    if (!std.mem.eql(u8, event.hat_id, sess.hat)) return;

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(sess.allocator);
    serializeEvent(sess.allocator, &buf, event) catch return;

    sess.write_mu.lock();
    defer sess.write_mu.unlock();
    wss_codec.writeFrame(sess.stream, .text, buf.items) catch return;
}

/// Serve a WebSocket session on `stream` until the client closes.
/// `hat` is the filter string from the upgrade query param.
/// `resume_after` is the event_id to replay from (empty → no replay).
/// `bus` provides the live event stream + ring replay.
pub fn serveSession(
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    bus: *OddjobzEventBus,
    hat: []const u8,
    resume_after: []const u8, // "" → no replay; 16 hex chars → replay
) void {
    var sess = SessionState{
        .allocator = allocator,
        .stream = stream,
        .write_mu = .{},
        .hat = hat,
    };

    // Subscribe to live events BEFORE replaying the ring, so no event
    // can slip between replay and live subscription.
    const sub_id = bus.subscribe(.{
        .state = &sess,
        .callback = busEventCallback,
    }) catch return;
    sess.sub_id = sub_id;
    defer bus.unsubscribe(sub_id);

    // Replay missed events from the ring buffer.
    if (resume_after.len > 0) {
        const replayed = bus.fetchSince(allocator, resume_after, 512) catch &.{};
        defer allocator.free(replayed);
        for (replayed) |ev| {
            // Only replay events matching this connection's hat.
            if (!std.mem.eql(u8, ev.hat_id, hat)) continue;
            var buf: std.ArrayList(u8) = .{};
            defer buf.deinit(allocator);
            serializeEvent(allocator, &buf, ev) catch continue;
            sess.write_mu.lock();
            wss_codec.writeFrame(stream, .text, buf.items) catch {
                sess.write_mu.unlock();
                return;
            };
            sess.write_mu.unlock();
        }
    }

    // Frame loop: accept ack frames from client until close.
    while (true) {
        const frame = wss_codec.readFrame(allocator, stream, MAX_PAYLOAD_BYTES) catch return;
        defer allocator.free(frame.payload);
        switch (frame.opcode) {
            .close => {
                wss_codec.writeClose(stream, 1000, "") catch {};
                return;
            },
            .ping => {
                wss_codec.writeFrame(stream, .pong, frame.payload) catch return;
            },
            .text => {
                // Ack frame: {"ack":"<event_id>"} — acknowledged; no action
                // needed beyond keeping the connection alive.
                // resume_after frame: {"resume_after":"<event_id>"} — in-session
                // replay (same as the query param but sent after connect).
                handleClientText(allocator, stream, bus, &sess, frame.payload);
            },
            else => {},
        }
    }
}

/// Handle a text frame from the client.  Currently understands:
///   {"ack": "<event_id>"}        — no-op; connection stays open
///   {"resume_after": "<eid>"}    — replay missed events
fn handleClientText(
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    bus: *OddjobzEventBus,
    sess: *SessionState,
    payload: []const u8,
) void {
    // We need only to detect the resume_after key; use a simple scan
    // rather than a full JSON parser.
    if (std.mem.indexOf(u8, payload, "\"resume_after\"")) |_| {
        // Extract the 16-char event_id value.
        var eid_buf: [16]u8 = undefined;
        if (extractEventId(payload, "resume_after", &eid_buf)) {
            const replayed = bus.fetchSince(allocator, &eid_buf, 512) catch return;
            defer allocator.free(replayed);
            for (replayed) |ev| {
                if (!std.mem.eql(u8, ev.hat_id, sess.hat)) continue;
                var buf: std.ArrayList(u8) = .{};
                defer buf.deinit(allocator);
                serializeEvent(allocator, &buf, ev) catch continue;
                sess.write_mu.lock();
                wss_codec.writeFrame(stream, .text, buf.items) catch {
                    sess.write_mu.unlock();
                    return;
                };
                sess.write_mu.unlock();
            }
        }
    }
    // "ack" frames are intentionally no-op: connection stays open.
}

// ─── JSON serialisation ───────────────────────────────────────────────────

/// Serialise a JobEvent to the wire shape the Flutter client expects:
///   {"event_id":"<hex16>","job_id":"<s>","cell_id":"<s>",
///    "from_state":"<s>","to_state":"<s>","ts_ms":<u64>,"hat_id":"<s>"}
pub fn serializeEvent(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    event: JobEvent,
) !void {
    try buf.appendSlice(allocator, "{\"event_id\":\"");
    try buf.appendSlice(allocator, &event.event_id);
    try buf.appendSlice(allocator, "\",\"job_id\":\"");
    try appendJsonString(allocator, buf, event.job_id);
    try buf.appendSlice(allocator, "\",\"cell_id\":\"");
    try appendJsonString(allocator, buf, event.cell_id);
    try buf.appendSlice(allocator, "\",\"from_state\":\"");
    try appendJsonString(allocator, buf, event.from_state);
    try buf.appendSlice(allocator, "\",\"to_state\":\"");
    try appendJsonString(allocator, buf, event.to_state);
    try buf.appendSlice(allocator, "\",\"ts_ms\":");
    var num_buf: [32]u8 = undefined;
    const num = std.fmt.bufPrint(&num_buf, "{d}", .{event.ts_ms}) catch return error.OutOfMemory;
    try buf.appendSlice(allocator, num);
    try buf.appendSlice(allocator, ",\"hat_id\":\"");
    try appendJsonString(allocator, buf, event.hat_id);
    try buf.appendSlice(allocator, "\"}");
}

fn appendJsonString(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |c| {
        if (c == '"') {
            try buf.appendSlice(allocator, "\\\"");
        } else if (c == '\\') {
            try buf.appendSlice(allocator, "\\\\");
        } else {
            try buf.append(allocator, c);
        }
    }
}

// ─── HTTP helpers ─────────────────────────────────────────────────────────

fn respondHttp(
    request: *std.http.Server.Request,
    status: std.http.Status,
    body: []const u8,
) !void {
    const hdrs = [_]std.http.Header{
        .{ .name = "content-type", .value = "application/json" },
    };
    try request.respond(body, .{ .status = status, .extra_headers = &hdrs });
}

fn headerValue(request: *const std.http.Server.Request, name: []const u8) ?[]const u8 {
    var iter = request.iterateHeaders();
    while (iter.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
    }
    return null;
}

pub fn asciiContainsCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

/// Extract a single query parameter value from a URL query string.
/// Returns null if not found.
pub fn queryParam(query: []const u8, name: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |kv| {
        if (std.mem.indexOfScalar(u8, kv, '=')) |eq| {
            const k = kv[0..eq];
            const v = kv[eq + 1 ..];
            if (std.mem.eql(u8, k, name)) return v;
        }
    }
    return null;
}

/// Scan a JSON text for `"key":"<16-char-hex>"` and copy the 16 chars
/// into `out`.  Returns true on success.
pub fn extractEventId(payload: []const u8, key: []const u8, out: *[16]u8) bool {
    // Find `"<key>"` in payload.
    var buf: [64]u8 = undefined;
    const search = std.fmt.bufPrint(&buf, "\"{s}\"", .{key}) catch return false;
    const pos = std.mem.indexOf(u8, payload, search) orelse return false;
    // Skip to the `"` after the `:`.
    const after_key = pos + search.len;
    const colon = std.mem.indexOfScalarPos(u8, payload, after_key, ':') orelse return false;
    const open_quote = std.mem.indexOfScalarPos(u8, payload, colon + 1, '"') orelse return false;
    const value_start = open_quote + 1;
    if (value_start + 16 > payload.len) return false;
    if (payload[value_start + 16] != '"') return false;
    @memcpy(out, payload[value_start .. value_start + 16]);
    return true;
}

// ─── Inline tests ─────────────────────────────────────────────────────────

test "events_stream_handler: queryParam parses hat from query string" {
    const q = "hat=0x000101&resume_after=abcdef0123456789";
    try std.testing.expectEqualStrings("0x000101", queryParam(q, "hat").?);
    try std.testing.expectEqualStrings("abcdef0123456789", queryParam(q, "resume_after").?);
    try std.testing.expect(queryParam(q, "bearer") == null);
}

test "events_stream_handler: serializeEvent produces correct JSON shape" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    const event = JobEvent{
        .event_id = "0000000000000001".*,
        .job_id = "job-42",
        .cell_id = "aabb",
        .from_state = "lead",
        .to_state = "quoted",
        .ts_ms = 1_000_000,
        .hat_id = "hat-test",
    };
    try serializeEvent(allocator, &buf, event);

    const json = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, json, "\"event_id\":\"0000000000000001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"job_id\":\"job-42\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"from_state\":\"lead\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"to_state\":\"quoted\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ts_ms\":1000000") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"hat_id\":\"hat-test\"") != null);
}

```
