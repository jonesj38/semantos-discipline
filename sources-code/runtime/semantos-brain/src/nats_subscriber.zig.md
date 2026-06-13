---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/nats_subscriber.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.245924+00:00
---

# runtime/semantos-brain/src/nats_subscriber.zig

```zig
// NATS push-subscription client.
//
// Owns its own TCP connection (separate from NatsClient's connection used
// for PUB / request).  A background reader thread reads MSG frames in a
// loop and dispatches them to a single callback.  Each subscription has
// one subject pattern + one SID.
//
// Why a second connection?
//   The existing NatsClient.request() and publish() share one TCP stream
//   under a single mutex.  Multiplexing a long-running reader on the same
//   stream would require a protocol-level demultiplexer (route MSG frames
//   to async waiters vs subscribe callbacks).  Two connections sidesteps
//   that — each side owns its stream.
//
// V1 semantics:
//   • One subscriber = one subject pattern + one callback.
//   • Wildcards supported (NATS-native: `op.*.>`).
//   • Reader thread runs until stop() is called or the socket closes.
//   • No reconnect logic — caller restarts brain to reconnect.
//
// Wire protocol:
//   CONNECT + PING/PONG (mirror of NatsClient.init).
//   SUB <subject> <sid>\r\n
//   MSG <subject> <sid> [<reply>] <len>\r\n<payload>\r\n
//   PING\r\n → PONG\r\n (server sends PING; we reply PONG)

const std = @import("std");

const CRLF = "\r\n";

pub const SubscriberConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 4222,
};

pub const Message = struct {
    subject: []const u8, // owned by callback's allocator
    reply: []const u8, // empty if no reply subject; owned
    payload: []const u8, // owned

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        allocator.free(self.subject);
        allocator.free(self.reply);
        allocator.free(self.payload);
    }
};

pub const Callback = struct {
    ctx: *anyopaque,
    /// Called from the reader thread, NOT the reactor thread.
    /// The Message is allocator-owned; callback takes ownership and is
    /// responsible for deinit.  Don't block on the reactor here — push
    /// to a mutex-protected queue.
    onMessage: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, msg: Message) void,
};

pub const Subscriber = struct {
    allocator: std.mem.Allocator,
    cfg: SubscriberConfig,
    stream: ?std.net.Stream = null,
    thread: ?std.Thread = null,
    callback: Callback,
    /// Owned subject + sid string.
    subject: []u8 = &.{},
    sid: u64 = 1,
    /// Set to true from any thread to ask the reader to exit.
    stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    /// Construct (does NOT connect — call subscribe() to start).
    pub fn init(
        allocator: std.mem.Allocator,
        cfg: SubscriberConfig,
        callback: Callback,
    ) Subscriber {
        return .{
            .allocator = allocator,
            .cfg = cfg,
            .callback = callback,
        };
    }

    /// Connect, send CONNECT + PING, send SUB, spawn reader thread.
    /// Returns once the subscription is registered (PONG received).
    pub fn subscribe(self: *Subscriber, subject: []const u8) !void {
        const tcp = try std.net.tcpConnectToHost(self.allocator, self.cfg.host, self.cfg.port);
        errdefer tcp.close();

        // Drain INFO.
        var line_buf: [4096]u8 = undefined;
        _ = try readLine(tcp, &line_buf);

        // CONNECT.
        try tcp.writeAll("CONNECT {\"verbose\":false,\"pedantic\":false}" ++ CRLF);
        try tcp.writeAll("PING" ++ CRLF);
        _ = try readLine(tcp, &line_buf); // expect PONG

        // SUB.
        var sub_buf: [256]u8 = undefined;
        const sub_line = try std.fmt.bufPrint(
            &sub_buf,
            "SUB {s} {d}" ++ CRLF,
            .{ subject, self.sid },
        );
        try tcp.writeAll(sub_line);

        self.subject = try self.allocator.dupe(u8, subject);
        self.stream = tcp;

        // Spawn reader.
        self.thread = try std.Thread.spawn(.{}, readerLoop, .{self});
    }

    /// Signal the reader thread to stop; close the stream; join the thread.
    pub fn deinit(self: *Subscriber) void {
        self.stop_flag.store(true, .release);
        if (self.stream) |s| s.close();
        if (self.thread) |t| t.join();
        if (self.subject.len > 0) self.allocator.free(self.subject);
    }

    /// Reader thread body.  Reads MSG / PING frames in a loop, dispatches
    /// payloads to the callback.  Exits cleanly on stop_flag or EOF.
    fn readerLoop(self: *Subscriber) void {
        const tcp = self.stream orelse return;
        var line_buf: [4096]u8 = undefined;
        while (!self.stop_flag.load(.acquire)) {
            const line = readLine(tcp, &line_buf) catch return;
            if (std.mem.startsWith(u8, line, "MSG ")) {
                const msg = readMsg(self.allocator, tcp, line) catch continue;
                self.callback.onMessage(self.callback.ctx, self.allocator, msg);
            } else if (std.mem.startsWith(u8, line, "PING")) {
                tcp.writeAll("PONG" ++ CRLF) catch return;
            }
            // +OK, -ERR, PONG, INFO: ignore.
        }
    }
};

/// Read one CRLF-terminated NATS protocol line.  No mutex — caller owns
/// the stream's read side (single reader assumption).
fn readLine(stream: std.net.Stream, buf: []u8) ![]const u8 {
    var pos: usize = 0;
    while (pos < buf.len) {
        const n = try stream.read(buf[pos .. pos + 1]);
        if (n == 0) return error.ConnectionClosed;
        pos += 1;
        if (pos >= 2 and buf[pos - 2] == '\r' and buf[pos - 1] == '\n') {
            return buf[0 .. pos - 2];
        }
    }
    return error.LineTooLong;
}

/// Parse an MSG line header + read the payload from the stream.
/// MSG format:  `MSG <subject> <sid> [<reply>] <len>`
///
/// Returns an allocator-owned Message — caller (callback) must deinit.
pub fn readMsg(
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    msg_line: []const u8,
) !Message {
    const parsed = try parseMsgHeader(msg_line);

    // Read payload + trailing \r\n.
    const total = parsed.payload_len + 2;
    const raw = try allocator.alloc(u8, total);
    defer allocator.free(raw);
    var read: usize = 0;
    while (read < total) {
        const n = try stream.read(raw[read..]);
        if (n == 0) return error.ConnectionClosed;
        read += n;
    }

    const subject = try allocator.dupe(u8, parsed.subject);
    errdefer allocator.free(subject);
    const reply = try allocator.dupe(u8, parsed.reply);
    errdefer allocator.free(reply);
    const payload = try allocator.dupe(u8, raw[0..parsed.payload_len]);

    return .{
        .subject = subject,
        .reply = reply,
        .payload = payload,
    };
}

const ParsedMsg = struct {
    subject: []const u8,
    sid: []const u8,
    reply: []const u8, // empty if no reply subject
    payload_len: usize,
};

/// Pure-function MSG-header parser.  Splits the line by space, validates,
/// returns the four fields.  No I/O, no allocation — slices borrow from
/// `msg_line`.
///
/// Wire shape: `MSG <subject> <sid> [<reply>] <len>`
///   4 tokens (no reply) or 5 tokens (with reply, the optional 4th).
pub fn parseMsgHeader(msg_line: []const u8) !ParsedMsg {
    if (!std.mem.startsWith(u8, msg_line, "MSG ")) return error.NotMsgFrame;
    const rest = std.mem.trim(u8, msg_line[4..], " \t\r\n");

    // Split tokens.  We expect 3 or 4 fields after "MSG ".
    var tokens: [4][]const u8 = undefined;
    var n: usize = 0;
    var it = std.mem.tokenizeAny(u8, rest, " \t");
    while (it.next()) |tok| : (n += 1) {
        if (n >= tokens.len) return error.MalformedMsgLine;
        tokens[n] = tok;
    }
    if (n < 3) return error.MalformedMsgLine;

    const subject = tokens[0];
    const sid = tokens[1];
    var reply: []const u8 = "";
    var len_tok: []const u8 = tokens[2];
    if (n == 4) {
        reply = tokens[2];
        len_tok = tokens[3];
    }
    const payload_len = try std.fmt.parseInt(usize, len_tok, 10);
    return .{
        .subject = subject,
        .sid = sid,
        .reply = reply,
        .payload_len = payload_len,
    };
}

// ── Inline tests — pure protocol parsing ────────────────────────────────

const testing = std.testing;

test "nats_subscriber: parseMsgHeader — 3 fields (no reply)" {
    const parsed = try parseMsgHeader("MSG op.foo.bar.fsm_transition 7 142");
    try testing.expectEqualStrings("op.foo.bar.fsm_transition", parsed.subject);
    try testing.expectEqualStrings("7", parsed.sid);
    try testing.expectEqualStrings("", parsed.reply);
    try testing.expectEqual(@as(usize, 142), parsed.payload_len);
}

test "nats_subscriber: parseMsgHeader — 4 fields (with reply)" {
    const parsed = try parseMsgHeader("MSG _INBOX.brain.42 1 $JS.ACK.op_x.cons.1.5.5.0.0 99");
    try testing.expectEqualStrings("_INBOX.brain.42", parsed.subject);
    try testing.expectEqualStrings("1", parsed.sid);
    try testing.expectEqualStrings("$JS.ACK.op_x.cons.1.5.5.0.0", parsed.reply);
    try testing.expectEqual(@as(usize, 99), parsed.payload_len);
}

test "nats_subscriber: parseMsgHeader — rejects non-MSG" {
    try testing.expectError(error.NotMsgFrame, parseMsgHeader("PUB op.foo 5"));
    try testing.expectError(error.NotMsgFrame, parseMsgHeader("PING"));
}

test "nats_subscriber: parseMsgHeader — rejects malformed (too few tokens)" {
    try testing.expectError(error.MalformedMsgLine, parseMsgHeader("MSG op.foo"));
    // "MSG" without trailing space doesn't satisfy startsWith("MSG ").
    try testing.expectError(error.NotMsgFrame, parseMsgHeader("MSG"));
}

test "nats_subscriber: parseMsgHeader — rejects too-many tokens" {
    try testing.expectError(error.MalformedMsgLine, parseMsgHeader("MSG a b c d e 5"));
}

test "nats_subscriber: parseMsgHeader — rejects non-numeric len" {
    try testing.expectError(
        error.InvalidCharacter,
        parseMsgHeader("MSG op.foo 1 not_a_number"),
    );
}

test "nats_subscriber: readMsg round-trip on a socketpair" {
    // Spin up a socketpair, write a full MSG frame on one side, read it
    // from the other via readMsg.  Confirms the line-then-payload chain.
    var sv: [2]std.posix.fd_t = undefined;
    const rc = std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, @ptrCast(&sv));
    if (rc != 0) return error.SocketPairFailed;
    defer std.posix.close(sv[0]);

    const writer_stream = std.net.Stream{ .handle = sv[0] };
    const reader_stream = std.net.Stream{ .handle = sv[1] };

    const wire =
        "MSG op.demo.hat.fsm_transition 1 12" ++ CRLF ++
        "hello-world!\r\n";
    try writer_stream.writeAll(wire);

    // Read the header line, then readMsg the body.
    var line_buf: [256]u8 = undefined;
    const line = try readLine(reader_stream, &line_buf);
    try testing.expect(std.mem.startsWith(u8, line, "MSG "));

    var msg = try readMsg(testing.allocator, reader_stream, line);
    defer msg.deinit(testing.allocator);
    try testing.expectEqualStrings("op.demo.hat.fsm_transition", msg.subject);
    try testing.expectEqualStrings("", msg.reply);
    try testing.expectEqualStrings("hello-world!", msg.payload);

    std.posix.close(sv[1]);
}

test "nats_subscriber: readMsg with reply subject roundtrips" {
    var sv: [2]std.posix.fd_t = undefined;
    const rc = std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, @ptrCast(&sv));
    if (rc != 0) return error.SocketPairFailed;
    defer std.posix.close(sv[0]);

    const writer_stream = std.net.Stream{ .handle = sv[0] };
    const reader_stream = std.net.Stream{ .handle = sv[1] };

    const wire =
        "MSG op.x 5 $JS.ACK.op_x.cons.1.5.5.0.0 4" ++ CRLF ++
        "data\r\n";
    try writer_stream.writeAll(wire);

    var line_buf: [256]u8 = undefined;
    const line = try readLine(reader_stream, &line_buf);
    var msg = try readMsg(testing.allocator, reader_stream, line);
    defer msg.deinit(testing.allocator);

    try testing.expectEqualStrings("op.x", msg.subject);
    try testing.expectEqualStrings("$JS.ACK.op_x.cons.1.5.5.0.0", msg.reply);
    try testing.expectEqualStrings("data", msg.payload);

    std.posix.close(sv[1]);
}

```
