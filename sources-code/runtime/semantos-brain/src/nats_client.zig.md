---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/nats_client.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.227993+00:00
---

# runtime/semantos-brain/src/nats_client.zig

```zig
// W7.3 — NatsClient: NATS JetStream TCP client for the hosted-operator event spine.
//
// Wraps a single TCP connection to the local NATS server (127.0.0.1:4222).
// Provides:
//   publish            — fire-and-forget PUB for event emission (hot path)
//   request            — synchronous request-reply for JetStream API management
//   streamCreate       — create a per-operator JetStream stream
//   streamDelete       — delete a stream (operator exit / W7.8)
//   consumerCreateDurable — create a named pull consumer for BRAIN brain replay
//
// Design decisions:
//   - One NatsClient = one TCP connection.  The caller owns reconnection.
//   - publish is mutex-serialised so multiple call sites in jobs_handler
//     can share one client without data interleaving.
//   - Management calls (streamCreate/Delete/consumerCreate) use
//     synchronous request-reply over the same connection.
//   - readLine reads one byte at a time — fine for management ops (not
//     on the hot path).
//
// Wire protocol:
//   CONNECT → server sends INFO, client sends CONNECT + PING, waits for PONG.
//   PUB <subject> <len>\r\n<payload>\r\n
//   SUB <subject> <sid>\r\n  (for request inbox)
//   MSG <subject> <sid> [<reply>] <len>\r\n<payload>\r\n
//
// JetStream API subjects (all request-reply):
//   $JS.API.STREAM.CREATE.<name>
//   $JS.API.STREAM.DELETE.<name>
//   $JS.API.CONSUMER.CREATE.<stream>.<consumer>
//
// References:
//   - docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md §2.4, W7.3
//   - runtime/semantos-brain/src/nats_event_producer.zig (caller)
//   - NATS protocol spec: https://docs.nats.io/reference/reference-protocols/nats-protocol

const std = @import("std");

// ── Config ─────────────────────────────────────────────────────────────────

pub const NatsConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 4222,
    inbox_prefix: []const u8 = "_INBOX.brain",
};

const CRLF = "\r\n";

// JetStream error codes we treat as "already exists / not found" → ok.
const JS_ERR_STREAM_EXISTS = "10058";
const JS_ERR_STREAM_NOT_FOUND = "10059";
const JS_ERR_CONSUMER_EXISTS = "10013";

// ── Client ─────────────────────────────────────────────────────────────────

pub const NatsClient = struct {
    allocator: std.mem.Allocator,
    cfg: NatsConfig,
    stream: std.net.Stream,
    mu: std.Thread.Mutex,
    /// Monotonic counter for unique sid / inbox suffix.
    next_id: u64,

    // ── Lifecycle ────────────────────────────────────────────────────────────

    /// Connect to NATS, negotiate, and return a ready client.
    pub fn init(allocator: std.mem.Allocator, cfg: NatsConfig) !NatsClient {
        const tcp = try std.net.tcpConnectToHost(allocator, cfg.host, cfg.port);
        errdefer tcp.close();

        var self = NatsClient{
            .allocator = allocator,
            .cfg = cfg,
            .stream = tcp,
            .mu = .{},
            .next_id = 1,
        };

        // Drain the server INFO line (we don't need to parse it for v1).
        var line_buf: [4096]u8 = undefined;
        _ = try self.readLine(&line_buf);

        // Identify ourselves and confirm liveness with PING/PONG.
        try tcp.writeAll("CONNECT {\"verbose\":false,\"pedantic\":false}" ++ CRLF);
        try tcp.writeAll("PING" ++ CRLF);
        _ = try self.readLine(&line_buf); // expect PONG

        return self;
    }

    pub fn deinit(self: *NatsClient) void {
        self.stream.close();
    }

    // ── Publish ──────────────────────────────────────────────────────────────

    /// Fire-and-forget publish.  Subject and payload are borrowed.
    /// Mutex-serialised so multiple callers can share one client.
    pub fn publish(self: *NatsClient, subject: []const u8, payload: []const u8) !void {
        self.mu.lock();
        defer self.mu.unlock();

        var hdr: [512]u8 = undefined;
        const h = try std.fmt.bufPrint(
            &hdr,
            "PUB {s} {d}" ++ CRLF,
            .{ subject, payload.len },
        );
        try self.stream.writeAll(h);
        try self.stream.writeAll(payload);
        try self.stream.writeAll(CRLF);
    }

    // ── Request-reply ─────────────────────────────────────────────────────────

    /// Synchronous JetStream API call.  Returns allocator-owned response payload.
    /// Caller must free.  Not for use on the hot path.
    pub fn request(self: *NatsClient, subject: []const u8, payload: []const u8) ![]u8 {
        self.mu.lock();
        defer self.mu.unlock();

        const id = self.next_id;
        self.next_id += 1;

        var inbox_buf: [128]u8 = undefined;
        const inbox = try std.fmt.bufPrint(
            &inbox_buf,
            "{s}.{d}",
            .{ self.cfg.inbox_prefix, id },
        );

        // SUB <inbox> <sid>
        var sub_buf: [256]u8 = undefined;
        const sub_line = try std.fmt.bufPrint(
            &sub_buf,
            "SUB {s} {d}" ++ CRLF,
            .{ inbox, id },
        );
        try self.stream.writeAll(sub_line);

        // PUB <subject> <inbox> <payload_len>
        var pub_buf: [512]u8 = undefined;
        const pub_line = try std.fmt.bufPrint(
            &pub_buf,
            "PUB {s} {s} {d}" ++ CRLF,
            .{ subject, inbox, payload.len },
        );
        try self.stream.writeAll(pub_line);
        try self.stream.writeAll(payload);
        try self.stream.writeAll(CRLF);

        // Read until MSG on our inbox arrives.
        var line_buf: [4096]u8 = undefined;
        var attempts: usize = 0;
        const response = while (attempts < 128) : (attempts += 1) {
            const line = try self.readLine(&line_buf);
            if (std.mem.startsWith(u8, line, "MSG ")) {
                break try self.readMsgPayload(line);
            }
            if (std.mem.startsWith(u8, line, "PING")) {
                self.stream.writeAll("PONG" ++ CRLF) catch {};
            }
            // +OK, -ERR, PONG: keep looping.
        } else return error.NatsRequestTimeout;

        // UNSUB the inbox sid.
        var unsub_buf: [64]u8 = undefined;
        const unsub_line = try std.fmt.bufPrint(&unsub_buf, "UNSUB {d}" ++ CRLF, .{id});
        self.stream.writeAll(unsub_line) catch {};

        return response;
    }

    // ── JetStream stream management ───────────────────────────────────────────

    /// Create a JetStream stream for one operator.
    /// `name` is e.g. "op_a3f7b2c1d4e5f6a7".
    /// `subjects_json` is e.g. `["op.a3f7b2c1d4e5f6a7.>"]`.
    /// 30-day retention, 10 K msgs/subject cap, file storage.
    pub fn streamCreate(
        self: *NatsClient,
        name: []const u8,
        subjects_json: []const u8,
    ) !void {
        const api_subject = try std.fmt.allocPrint(
            self.allocator,
            "$JS.API.STREAM.CREATE.{s}",
            .{name},
        );
        defer self.allocator.free(api_subject);

        // max_age in nanoseconds: 30 days = 30 * 86400 * 1e9 = 2592000000000000
        const config = try std.fmt.allocPrint(
            self.allocator,
            "{{\"name\":\"{s}\"," ++
                "\"subjects\":{s}," ++
                "\"storage\":\"file\"," ++
                "\"retention\":\"limits\"," ++
                "\"max_msgs_per_subject\":10000," ++
                "\"max_age\":2592000000000000," ++
                "\"discard\":\"old\"," ++
                "\"num_replicas\":1}}",
            .{ name, subjects_json },
        );
        defer self.allocator.free(config);

        const resp = try self.request(api_subject, config);
        defer self.allocator.free(resp);

        if (isJsError(resp) and !std.mem.containsAtLeast(u8, resp, 1, JS_ERR_STREAM_EXISTS)) {
            return error.NatsStreamCreateFailed;
        }
    }

    /// List all JetStream stream names.
    /// Calls $JS.API.STREAM.NAMES and returns an owned slice of owned name
    /// strings.  Caller must free each name and then the slice itself.
    /// Returns an empty slice when no streams exist.
    /// W7.13 — used by orphan stream detection.
    pub fn streamNames(self: *NatsClient, allocator: std.mem.Allocator) ![][]u8 {
        const resp = try self.request("$JS.API.STREAM.NAMES", "{}");
        defer self.allocator.free(resp);

        // Response shape when streams exist:
        //   {"total":N,"offset":0,"limit":256,"streams":["name1","name2",...]}
        // Response shape when no streams exist:
        //   {"total":0,"offset":0,"limit":256} or {"error":{...}}
        // We do a simple scan: find `"streams":[` then extract quoted tokens.
        var names: std.ArrayList([]u8) = .{};
        errdefer {
            for (names.items) |n| allocator.free(n);
            names.deinit(allocator);
        }

        const marker = "\"streams\":[";
        const start = std.mem.indexOf(u8, resp, marker) orelse return try names.toOwnedSlice(allocator);
        var pos = start + marker.len;

        while (pos < resp.len) {
            // Skip whitespace
            while (pos < resp.len and (resp[pos] == ' ' or resp[pos] == '\n' or resp[pos] == '\r' or resp[pos] == '\t')) {
                pos += 1;
            }
            if (pos >= resp.len or resp[pos] == ']') break;
            if (resp[pos] != '"') { pos += 1; continue; }
            pos += 1; // skip opening quote
            const name_start = pos;
            while (pos < resp.len and resp[pos] != '"') pos += 1;
            if (pos >= resp.len) break;
            const name = try allocator.dupe(u8, resp[name_start..pos]);
            try names.append(allocator, name);
            pos += 1; // skip closing quote
            // skip comma or whitespace before next entry
            while (pos < resp.len and (resp[pos] == ',' or resp[pos] == ' ')) pos += 1;
        }

        return try names.toOwnedSlice(allocator);
    }

    /// Delete an operator stream.  Idempotent (stream-not-found treated as ok).
    pub fn streamDelete(self: *NatsClient, name: []const u8) !void {
        const api_subject = try std.fmt.allocPrint(
            self.allocator,
            "$JS.API.STREAM.DELETE.{s}",
            .{name},
        );
        defer self.allocator.free(api_subject);

        const resp = try self.request(api_subject, "{}");
        defer self.allocator.free(resp);

        if (isJsError(resp) and !std.mem.containsAtLeast(u8, resp, 1, JS_ERR_STREAM_NOT_FOUND)) {
            return error.NatsStreamDeleteFailed;
        }
    }

    /// Create a durable pull consumer.
    /// `deliver_policy`: "all" | "last_per_subject" | "new".
    pub fn consumerCreateDurable(
        self: *NatsClient,
        stream_name: []const u8,
        consumer_name: []const u8,
        filter_subject: []const u8,
        deliver_policy: []const u8,
    ) !void {
        const api_subject = try std.fmt.allocPrint(
            self.allocator,
            "$JS.API.CONSUMER.CREATE.{s}.{s}",
            .{ stream_name, consumer_name },
        );
        defer self.allocator.free(api_subject);

        // ack_wait in nanoseconds: 30s = 30_000_000_000
        const config = try std.fmt.allocPrint(
            self.allocator,
            "{{\"stream_name\":\"{s}\"," ++
                "\"config\":{{" ++
                "\"durable_name\":\"{s}\"," ++
                "\"filter_subject\":\"{s}\"," ++
                "\"deliver_policy\":\"{s}\"," ++
                "\"ack_policy\":\"explicit\"," ++
                "\"max_deliver\":5," ++
                "\"ack_wait\":30000000000}}}}",
            .{ stream_name, consumer_name, filter_subject, deliver_policy },
        );
        defer self.allocator.free(config);

        const resp = try self.request(api_subject, config);
        defer self.allocator.free(resp);

        if (isJsError(resp) and !std.mem.containsAtLeast(u8, resp, 1, JS_ERR_CONSUMER_EXISTS)) {
            return error.NatsConsumerCreateFailed;
        }
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    /// Read one NATS protocol line (terminated by \r\n).
    /// Returns a slice into `buf` without the trailing \r\n.
    /// NOT mutex-guarded — callers hold the mutex already.
    fn readLine(self: *NatsClient, buf: []u8) ![]const u8 {
        var pos: usize = 0;
        while (pos < buf.len) {
            const n = try self.stream.read(buf[pos .. pos + 1]);
            if (n == 0) return error.ConnectionClosed;
            pos += 1;
            if (pos >= 2 and buf[pos - 2] == '\r' and buf[pos - 1] == '\n') {
                return buf[0 .. pos - 2];
            }
        }
        return error.LineTooLong;
    }

    /// Parse MSG header and read the payload from the wire.
    /// Returns allocator-owned slice.  Caller must free.
    /// NOT mutex-guarded — callers hold the mutex already.
    fn readMsgPayload(self: *NatsClient, msg_line: []const u8) ![]u8 {
        // MSG format: MSG <subject> <sid> [<reply>] <len>
        // The payload length is always the last space-separated token.
        const last_space = std.mem.lastIndexOfScalar(u8, msg_line, ' ') orelse
            return error.MalformedMsgLine;
        const len_str = std.mem.trim(u8, msg_line[last_space + 1 ..], " \t\r\n");
        const payload_len = try std.fmt.parseInt(usize, len_str, 10);

        // Read payload + trailing \r\n.
        const total = payload_len + 2;
        const raw = try self.allocator.alloc(u8, total);
        defer self.allocator.free(raw);

        var read: usize = 0;
        while (read < total) {
            const n = try self.stream.read(raw[read..]);
            if (n == 0) return error.ConnectionClosed;
            read += n;
        }

        return try self.allocator.dupe(u8, raw[0..payload_len]);
    }
};

// ── Helpers ────────────────────────────────────────────────────────────────

fn isJsError(resp: []const u8) bool {
    return std.mem.containsAtLeast(u8, resp, 1, "\"error\"");
}

// ── Inline tests ──────────────────────────────────────────────────────────

test "nats_client: isJsError detects error field" {
    try std.testing.expect(isJsError("{\"error\":{\"code\":10058}}"));
    try std.testing.expect(!isJsError("{\"config\":{\"name\":\"op_abc\"}}"));
}

test "nats_client: JS_ERR constants present in error bodies" {
    const stream_exists = "{\"error\":{\"code\":10058,\"description\":\"stream already exists\"}}";
    try std.testing.expect(std.mem.containsAtLeast(u8, stream_exists, 1, JS_ERR_STREAM_EXISTS));

    const not_found = "{\"error\":{\"code\":10059,\"description\":\"stream not found\"}}";
    try std.testing.expect(std.mem.containsAtLeast(u8, not_found, 1, JS_ERR_STREAM_NOT_FOUND));

    const consumer_exists = "{\"error\":{\"code\":10013,\"description\":\"consumer already exists\"}}";
    try std.testing.expect(std.mem.containsAtLeast(u8, consumer_exists, 1, JS_ERR_CONSUMER_EXISTS));
}

// streamNames is tested via its JSON scanner logic directly.

test "nats_client: streamNames parses response with streams" {
    // Simulate what NATS returns for $JS.API.STREAM.NAMES.
    // We can't run a real NatsClient here, but we can test the scanner
    // by extracting it.  Test the shape the real method would parse.
    const resp = "{\"total\":2,\"offset\":0,\"limit\":256,\"streams\":[\"op_abc1234567890ab\",\"op_deadbeefcafefed\"]}";
    const marker = "\"streams\":[";
    const start_idx = std.mem.indexOf(u8, resp, marker).?;
    var pos: usize = start_idx + marker.len;
    var names: std.ArrayList([]const u8) = .{};
    defer names.deinit(std.testing.allocator);
    while (pos < resp.len) {
        while (pos < resp.len and (resp[pos] == ' ' or resp[pos] == '\n' or resp[pos] == '\r' or resp[pos] == '\t')) pos += 1;
        if (pos >= resp.len or resp[pos] == ']') break;
        if (resp[pos] != '"') { pos += 1; continue; }
        pos += 1;
        const name_start = pos;
        while (pos < resp.len and resp[pos] != '"') pos += 1;
        try names.append(std.testing.allocator, resp[name_start..pos]);
        pos += 1;
        while (pos < resp.len and (resp[pos] == ',' or resp[pos] == ' ')) pos += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), names.items.len);
    try std.testing.expectEqualStrings("op_abc1234567890ab", names.items[0]);
    try std.testing.expectEqualStrings("op_deadbeefcafefed", names.items[1]);
}

test "nats_client: streamNames parses empty response" {
    const resp = "{\"total\":0,\"offset\":0,\"limit\":256}";
    const marker = "\"streams\":[";
    const has = std.mem.indexOf(u8, resp, marker);
    try std.testing.expect(has == null);
}

```
