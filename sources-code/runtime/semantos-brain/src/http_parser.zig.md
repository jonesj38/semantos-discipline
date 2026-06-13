---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/http_parser.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.258815+00:00
---

# runtime/semantos-brain/src/http_parser.zig

```zig
// http_parser.zig — Minimal resumable HTTP/1.1 request parser
//
// WHY THIS FILE EXISTS
// --------------------
// The reactor (event_loop.zig) uses non-blocking sockets: every read()
// may return fewer bytes than needed for a complete request. std.http.Server
// performs blocking reads through its reader interface and cannot be used in
// a non-blocking context. This module provides a byte-driven state machine
// that accepts arbitrary chunks and signals "not yet" until a complete
// request has been assembled.
//
// ARCHITECTURAL MODEL
// -------------------
// This is a pure parser — no I/O, no allocation side effects. The caller
// (connection_state.zig) feeds bytes via `feed()` and checks the returned
// ParseResult. The parser accumulates state across calls until either:
//   - A complete request is available (ParseResult.complete)
//   - An error is detected (ParseResult.err)
//   - More bytes are needed (ParseResult.incomplete)
//
// Parsed output is placed into an HttpRequest struct allocated by the
// caller's arena. The parser itself only borrows slices into the input
// buffer passed by the caller — nothing is heap-allocated by the parser.
//
// SCOPE (v1)
// ----------
//   • Request line: METHOD /path HTTP/1.1
//   • Headers until \r\n\r\n (max MAX_HEADERS headers)
//   • Body accumulation when Content-Length is present
//   • Chunked transfer encoding: NOT supported (brain sends, not receives, large bodies)
//     Documented as TODO; add when a Semantos Brain endpoint needs to receive chunked input.
//
// HOW TO REVERT
// -------------
// This file is new. To revert the entire reactor change, delete:
//   http_parser.zig, wss_frame_parser.zig, event_loop.zig, connection_state.zig
// and restore site_server.zig + wss_wallet.zig to the pre-reactor shape
// via `git revert <commit-sha>` per the RIP-OUT markers in those files.
//
// RIP-OUT-MARKER (brain-wedge B-pragmatic, 2026-05-07):
//   This file is part of the reactor wedge fix. It was not present before
//   that fix. Deleting it (along with the other reactor files) reverts the
//   fix. See docs/prd/BRAIN-WEDGE-STEP0-AUDIT.md for the full file list.

const std = @import("std");

/// Maximum number of request headers accepted per request.
/// 64 covers every real HTTP/1.1 scenario brain encounters (browser + curl
/// clients); large enough to avoid practical rejection, small enough to
/// bound per-request stack use.
pub const MAX_HEADERS: usize = 64;

/// Maximum size of the request line (METHOD /path HTTP/1.1\r\n).
/// 8 KiB is the same limit std.http.Server uses and covers any sane path.
pub const MAX_REQUEST_LINE: usize = 8192;

/// Maximum cumulative header block size (\r\n\r\n included).
/// 16 KiB covers even pathological header sets; matches common reverse
/// proxy limits.
pub const MAX_HEADER_BLOCK: usize = 16384;

/// Default body cap when no per-route policy applies.  Conservative —
/// the policy callback can raise it per-route (e.g. attachment uploads
/// declare a 12 MB cap).
pub const DEFAULT_BODY_CAP: usize = 256 * 1024; // 256 KiB

/// Absolute upper limit on body size, regardless of per-route policy.
/// Sanity cap so a misconfigured policy can't request a multi-GB
/// allocation per connection.
pub const MAX_BODY_BYTES_ABS: usize = 64 * 1024 * 1024; // 64 MiB

/// Body-handling policy for a parsed request.  Returned by the
/// policy callback after headers parse so the parser knows how to
/// handle the body.
pub const BodyPolicy = union(enum) {
    /// Heap-buffer the body up to `cap` bytes.  Reject (BodyTooLarge)
    /// if `Content-Length > cap`.  This is the only mode currently
    /// implemented; covers every V1 endpoint.
    buffer: usize,
    /// Reserved: stream body bytes to the handler as they arrive.
    /// Not yet implemented — returns error.StreamNotImplemented.  Add
    /// only when a route genuinely needs sub-Content-Length progress
    /// (e.g. multi-GB upload with progress events).
    stream: void,
};

/// Policy lookup callback.  Called by the parser once headers are
/// parsed, before any body bytes are buffered.  The callback inspects
/// the partial HttpRequest (method, path, headers) and returns the
/// BodyPolicy for this request.
pub const PolicyFn = *const fn (req: *const HttpRequest, ctx: *anyopaque) BodyPolicy;

/// A single HTTP header name+value pair. Both slices borrow from the
/// caller's buffer; the caller owns the storage.
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// A parsed HTTP/1.1 request. All slices borrow from the caller's
/// read buffer — valid only while the buffer is alive.
pub const HttpRequest = struct {
    method: []const u8,
    path: []const u8,
    /// Query string portion of the path (empty slice if no '?').
    query: []const u8,
    /// HTTP version string, e.g. "HTTP/1.1".
    version: []const u8,
    /// Parsed headers; populated up to `header_count`.
    headers: [MAX_HEADERS]Header,
    header_count: usize,
    /// Body bytes (may be empty). Borrowed from read buffer.
    body: []const u8,
    /// True if the Connection: keep-alive header was present (or the
    /// default for HTTP/1.1). False if Connection: close was set or this
    /// is HTTP/1.0.
    keep_alive: bool,

    /// Find the first header whose name matches `name` (case-insensitive).
    /// Returns null if not found.
    pub fn header(self: *const HttpRequest, name: []const u8) ?[]const u8 {
        for (self.headers[0..self.header_count]) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
        }
        return null;
    }

    /// Return the Content-Length value, or null if the header is absent
    /// or malformed.
    pub fn contentLength(self: *const HttpRequest) ?usize {
        const v = self.header("content-length") orelse return null;
        return std.fmt.parseUnsigned(usize, std.mem.trim(u8, v, " \t"), 10) catch null;
    }
};

/// Result of one call to `Parser.feed()`.
pub const ParseResult = union(enum) {
    /// Need more bytes — feed more data and call again.
    incomplete,
    /// A complete request is ready. `bytes_consumed` is the number of
    /// bytes from the input slice that were consumed (so the caller can
    /// advance its read-buffer pointer). The parsed request borrows from
    /// the bytes already accumulated in the parser's internal buffer.
    complete: struct { bytes_consumed: usize },
    /// Unrecoverable parse error. Close the connection.
    err: ParseError,
};

pub const ParseError = error{
    RequestLineTooLong,
    HeaderBlockTooLong,
    BodyTooLarge,
    MalformedRequestLine,
    MalformedHeader,
    TooManyHeaders,
    OutOfMemory,
    StreamNotImplemented,
};

/// Per-connection HTTP parser state.
///
/// Memory shape (post-T0):
///   • `header_buf` is a fixed-size stack/embedded buffer (16 KiB).  All
///     connections pay this even when idle.
///   • `body_buf` is heap-allocated *only* after headers parse, sized to
///     min(Content-Length, route_cap).  Freed on `reset()` so a keep-alive
///     connection doesn't retain the previous request's body memory.
///
/// At MAX_CONNECTIONS = 1024 this drops idle per-connection memory from
/// ~272 KB (header + body region) to ~16 KB (header only).  Peak memory
/// scales with active in-flight bodies × route cap.
pub const Parser = struct {
    /// Header bytes only.  Body lives in `body_buf` once allocated.
    header_buf: [MAX_HEADER_BLOCK]u8,
    /// Number of bytes written into `header_buf`.
    header_len: usize,
    /// Set to true once \r\n\r\n is found and headers are parsed.
    headers_complete: bool,
    /// Offset within `header_buf` where the headers end (\r\n\r\n + 4).
    /// Always == header_len after `feed` returns (we trim leftover body
    /// bytes out of header_buf into body_buf on the same call).
    body_start_in_header: usize,
    /// Expected body length from Content-Length, or 0 if none.
    expected_body: usize,

    /// Heap-allocated body buffer.  Null until headers parsed and policy
    /// resolved (or stays null if expected_body == 0).
    body_buf: ?[]u8,
    body_buf_filled: usize,

    /// Allocator used for body_buf.  Same allocator the ConnectionState
    /// owns.
    allocator: std.mem.Allocator,
    /// Policy callback invoked once headers are parsed.
    policy_fn: PolicyFn,
    /// Opaque context passed to `policy_fn`.
    policy_ctx: *anyopaque,

    /// Construct a parser.  `allocator` is used for body_buf allocations;
    /// `policy_fn` is invoked once per request after headers parse to
    /// determine the body-handling policy.
    pub fn init(allocator: std.mem.Allocator, policy_fn: PolicyFn, policy_ctx: *anyopaque) Parser {
        return .{
            .header_buf = undefined,
            .header_len = 0,
            .headers_complete = false,
            .body_start_in_header = 0,
            .expected_body = 0,
            .body_buf = null,
            .body_buf_filled = 0,
            .allocator = allocator,
            .policy_fn = policy_fn,
            .policy_ctx = policy_ctx,
        };
    }

    /// Construct a parser with a "default" policy (always `.buffer{cap: DEFAULT_BODY_CAP}`).
    /// Used by tests + any caller that doesn't need per-route caps.
    pub fn initDefault(allocator: std.mem.Allocator) Parser {
        return init(allocator, defaultPolicyFn, undefined);
    }

    /// Reset for the next request on the same connection (keep-alive).
    /// Frees the heap body buffer; header buffer is reused in place.
    pub fn reset(self: *Parser) void {
        if (self.body_buf) |b| {
            self.allocator.free(b);
            self.body_buf = null;
        }
        self.header_len = 0;
        self.headers_complete = false;
        self.body_start_in_header = 0;
        self.expected_body = 0;
        self.body_buf_filled = 0;
    }

    /// Same as reset.  Provided for parity with structs that distinguish
    /// the two (deinit = final teardown).
    pub fn deinit(self: *Parser) void {
        self.reset();
    }

    /// Feed a chunk of bytes to the parser.  Returns the result of this
    /// partial parse.  On `complete`, the parsed request is placed into
    /// `out` and the caller must call `reset()` before the next request.
    /// `out.body` borrows from `self.body_buf` — valid until `reset()`.
    ///
    /// Flow:
    ///   Phase A (headers): copy bytes into `header_buf` until \r\n\r\n.
    ///     - Parse headers, consult policy callback, allocate `body_buf`
    ///       if expected_body > 0.
    ///     - Copy any body bytes that arrived in the same chunk into
    ///       `body_buf` (they landed in `header_buf` past the
    ///       \r\n\r\n boundary).
    ///     - Fall through to Phase B logic to consume remaining
    ///       `new_bytes` as body.
    ///   Phase B (body): copy bytes into `body_buf` until filled.
    ///
    /// `bytes_consumed` counts bytes from `new_bytes` consumed by this
    /// call.  Pipelined leftover bytes (the start of the next request)
    /// are NOT consumed and must be re-fed by the caller.
    pub fn feed(self: *Parser, new_bytes: []const u8, out: *HttpRequest) ParseResult {
        var input = new_bytes;
        var consumed_from_input: usize = 0;

        if (!self.headers_complete) {
            // ── Phase A: accumulate header bytes ──────────────────────
            const take = @min(input.len, MAX_HEADER_BLOCK - self.header_len);
            if (take == 0) {
                // header_buf is full and we still haven't seen \r\n\r\n.
                return .{ .err = error.HeaderBlockTooLong };
            }
            @memcpy(self.header_buf[self.header_len..][0..take], input[0..take]);
            self.header_len += take;
            consumed_from_input += take;
            input = input[take..];

            // Search for end of headers.
            const sep = std.mem.indexOf(u8, self.header_buf[0..self.header_len], "\r\n\r\n") orelse {
                // Not yet found.  If header_buf is now full, signal
                // overflow (subsequent feed calls would error).
                if (self.header_len >= MAX_HEADER_BLOCK and input.len > 0) {
                    return .{ .err = error.HeaderBlockTooLong };
                }
                return .incomplete;
            };
            self.headers_complete = true;
            self.body_start_in_header = sep + 4;

            // Parse the header block.
            parseHeaderBlock(self.header_buf[0..self.body_start_in_header], out) catch |e| {
                return .{ .err = e };
            };
            self.expected_body = out.contentLength() orelse 0;

            // Bytes after the \r\n\r\n that landed in header_buf are body bytes.
            const body_bytes_in_header = self.header_len - self.body_start_in_header;

            if (self.expected_body == 0) {
                out.body = &.{};
                // No body expected.  Anything past \r\n\r\n is leftover
                // (pipelined next request) — un-consume it from this call.
                const consumed_total = consumed_from_input;
                return .{ .complete = .{ .bytes_consumed = consumed_total - body_bytes_in_header } };
            }

            // Consult per-route policy.
            const policy = self.policy_fn(out, self.policy_ctx);
            const cap = switch (policy) {
                .buffer => |c| c,
                .stream => return .{ .err = error.StreamNotImplemented },
            };
            if (self.expected_body > cap or self.expected_body > MAX_BODY_BYTES_ABS) {
                return .{ .err = error.BodyTooLarge };
            }

            // Allocate the body buffer.
            self.body_buf = self.allocator.alloc(u8, self.expected_body) catch {
                return .{ .err = error.OutOfMemory };
            };
            self.body_buf_filled = 0;

            // Copy body bytes that already landed in header_buf.
            if (body_bytes_in_header > 0) {
                const copy_n = @min(body_bytes_in_header, self.expected_body);
                @memcpy(self.body_buf.?[0..copy_n], self.header_buf[self.body_start_in_header..][0..copy_n]);
                self.body_buf_filled = copy_n;
                // Trim header_buf back to "headers only" so subsequent
                // resets don't think there are still body bytes here.
                self.header_len = self.body_start_in_header;
                // If body bytes overran expected_body, those are pipelined
                // leftover.  Un-consume them from this call.
                if (body_bytes_in_header > self.expected_body) {
                    const overshoot = body_bytes_in_header - self.expected_body;
                    consumed_from_input -= overshoot;
                }
            }

            // Fall through to Phase B logic to absorb remaining `input`.
        }

        // ── Phase B: accumulate body bytes ────────────────────────────
        if (self.body_buf == null) {
            // expected_body == 0 path already returned complete above.
            // This branch only reachable if headers_complete is true AND
            // we already returned complete previously — caller forgot to reset.
            return .incomplete;
        }
        const body = self.body_buf.?;
        if (self.body_buf_filled >= self.expected_body) {
            // Already complete (filled from header_buf overflow on same call).
            out.body = body[0..self.expected_body];
            return .{ .complete = .{ .bytes_consumed = consumed_from_input } };
        }
        const need = self.expected_body - self.body_buf_filled;
        const take_body = @min(input.len, need);
        @memcpy(body[self.body_buf_filled..][0..take_body], input[0..take_body]);
        self.body_buf_filled += take_body;
        consumed_from_input += take_body;

        if (self.body_buf_filled >= self.expected_body) {
            out.body = body[0..self.expected_body];
            return .{ .complete = .{ .bytes_consumed = consumed_from_input } };
        }
        return .incomplete;
    }

    /// Simpler entry point: feed a complete byte slice and return the
    /// parsed request, or an error.  Useful for tests.
    pub fn feedAll(self: *Parser, bytes: []const u8, out: *HttpRequest) !void {
        var remaining = bytes;
        while (remaining.len > 0) {
            const result = self.feed(remaining, out);
            switch (result) {
                .incomplete => return error.Incomplete,
                .complete => |c| {
                    remaining = remaining[c.bytes_consumed..];
                    if (remaining.len == 0) return;
                    // Pipelined: reset and continue (only relevant for callers
                    // that loop). For now just return after one request.
                    return;
                },
                .err => |e| return e,
            }
        }
    }
};

/// Default policy used by `Parser.initDefault`: always returns
/// `.buffer{cap: DEFAULT_BODY_CAP}`.  Mirrors the pre-T0 behaviour.
fn defaultPolicyFn(_: *const HttpRequest, _: *anyopaque) BodyPolicy {
    return .{ .buffer = DEFAULT_BODY_CAP };
}

/// Parse the header block (everything up to and including \r\n\r\n).
/// Writes parsed fields into `out`. Returns an error if the block is
/// structurally invalid.
fn parseHeaderBlock(block: []const u8, out: *HttpRequest) !void {
    // The block ends with \r\n\r\n; split on \r\n.
    var it = std.mem.splitSequence(u8, block, "\r\n");
    const request_line = it.next() orelse return error.MalformedRequestLine;
    if (request_line.len == 0) return error.MalformedRequestLine;

    // Parse "METHOD /path HTTP/version".
    try parseRequestLine(request_line, out);

    out.header_count = 0;
    out.keep_alive = std.mem.eql(u8, out.version, "HTTP/1.1"); // default for 1.1

    while (it.next()) |line| {
        if (line.len == 0) break; // empty line = end of headers
        if (out.header_count >= MAX_HEADERS) return error.TooManyHeaders;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.MalformedHeader;
        const name = std.mem.trimRight(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        out.headers[out.header_count] = .{ .name = name, .value = value };
        out.header_count += 1;

        // Detect Connection: close / keep-alive.
        if (std.ascii.eqlIgnoreCase(name, "connection")) {
            if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, value, " \t"), "close")) {
                out.keep_alive = false;
            } else if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, value, " \t"), "keep-alive")) {
                out.keep_alive = true;
            }
        }
    }
}

/// Parse "METHOD /path?query HTTP/version" into the corresponding fields.
fn parseRequestLine(line: []const u8, out: *HttpRequest) !void {
    // First space separates method.
    const sp1 = std.mem.indexOfScalar(u8, line, ' ') orelse return error.MalformedRequestLine;
    out.method = line[0..sp1];

    // Second space separates path from version.
    const rest = line[sp1 + 1 ..];
    const sp2 = std.mem.lastIndexOfScalar(u8, rest, ' ') orelse return error.MalformedRequestLine;
    const target = rest[0..sp2];
    out.version = rest[sp2 + 1 ..];

    if (out.method.len == 0) return error.MalformedRequestLine;
    if (out.version.len == 0) return error.MalformedRequestLine;

    // Split target into path and query.
    if (std.mem.indexOfScalar(u8, target, '?')) |q| {
        out.path = target[0..q];
        out.query = target[q + 1 ..];
    } else {
        out.path = target;
        out.query = target[target.len..]; // empty slice at end
    }
}

// ─── Tests ───────────────────────────────────────────────────────────

test "http_parser: simple GET" {
    const input = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: HttpRequest = undefined;
    const r = parser.feed(input, &req);
    try std.testing.expect(r == .complete);
    try std.testing.expectEqualStrings("GET", req.method);
    try std.testing.expectEqualStrings("/hello", req.path);
    try std.testing.expectEqualStrings("HTTP/1.1", req.version);
    try std.testing.expectEqual(@as(usize, 1), req.header_count);
    try std.testing.expectEqualStrings("Host", req.headers[0].name);
    try std.testing.expectEqualStrings("localhost", req.headers[0].value);
    try std.testing.expectEqual(@as(usize, 0), req.body.len);
    try std.testing.expect(req.keep_alive); // default for HTTP/1.1
}

test "http_parser: POST with body" {
    const body = "{\"x\":1}";
    const input = "POST /api/v1/repl HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 7\r\n\r\n" ++ body;
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: HttpRequest = undefined;
    const r = parser.feed(input, &req);
    try std.testing.expect(r == .complete);
    try std.testing.expectEqualStrings("POST", req.method);
    try std.testing.expectEqualStrings("/api/v1/repl", req.path);
    try std.testing.expectEqualStrings(body, req.body);
    try std.testing.expectEqual(@as(usize, 2), req.header_count);
}

test "http_parser: path with query string" {
    const input = "GET /api/v1/wallet?bearer=abcd HTTP/1.1\r\n\r\n";
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: HttpRequest = undefined;
    _ = parser.feed(input, &req);
    try std.testing.expectEqualStrings("/api/v1/wallet", req.path);
    try std.testing.expectEqualStrings("bearer=abcd", req.query);
}

test "http_parser: partial input — bytes arrive one at a time" {
    const input = "GET /slow HTTP/1.1\r\nHost: x\r\n\r\n";
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: HttpRequest = undefined;
    var complete = false;
    for (input, 0..) |_, i| {
        const chunk = input[i .. i + 1];
        const r = parser.feed(chunk, &req);
        switch (r) {
            .incomplete => {},
            .complete => { complete = true; break; },
            .err => try std.testing.expect(false),
        }
    }
    try std.testing.expect(complete);
    try std.testing.expectEqualStrings("GET", req.method);
    try std.testing.expectEqualStrings("/slow", req.path);
}

test "http_parser: header lookup case-insensitive" {
    const input = "GET / HTTP/1.1\r\nAuthorization: Bearer abc123\r\n\r\n";
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: HttpRequest = undefined;
    _ = parser.feed(input, &req);
    const auth = req.header("authorization");
    try std.testing.expect(auth != null);
    try std.testing.expectEqualStrings("Bearer abc123", auth.?);
}

test "http_parser: Connection: close → keep_alive=false" {
    const input = "GET / HTTP/1.1\r\nConnection: close\r\n\r\n";
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: HttpRequest = undefined;
    _ = parser.feed(input, &req);
    try std.testing.expect(!req.keep_alive);
}

test "http_parser: HTTP/1.0 → keep_alive=false by default" {
    const input = "GET / HTTP/1.0\r\n\r\n";
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: HttpRequest = undefined;
    _ = parser.feed(input, &req);
    try std.testing.expect(!req.keep_alive);
}

test "http_parser: Content-Length: 0 → body empty" {
    const input = "POST /x HTTP/1.1\r\nContent-Length: 0\r\n\r\n";
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: HttpRequest = undefined;
    const r = parser.feed(input, &req);
    try std.testing.expect(r == .complete);
    try std.testing.expectEqual(@as(usize, 0), req.body.len);
}

test "http_parser: malformed — missing second space in request line" {
    const input = "GET HTTP/1.1\r\n\r\n";
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: HttpRequest = undefined;
    const r = parser.feed(input, &req);
    try std.testing.expect(r == .err);
}

test "http_parser: Upgrade websocket request parses correctly" {
    const input =
        "GET /api/v1/wallet HTTP/1.1\r\n" ++
        "Host: localhost:8080\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "Authorization: Bearer " ++ ("a" ** 64) ++ "\r\n" ++
        "\r\n";
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: HttpRequest = undefined;
    const r = parser.feed(input, &req);
    try std.testing.expect(r == .complete);
    try std.testing.expectEqualStrings("/api/v1/wallet", req.path);
    const upgrade = req.header("upgrade");
    try std.testing.expect(upgrade != null);
    try std.testing.expectEqualStrings("websocket", upgrade.?);
}

test "http_parser: partial body delivery" {
    const body = "hello";
    const header_part = "POST /api/v1/repl HTTP/1.1\r\nContent-Length: 5\r\n\r\n";
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    var req: HttpRequest = undefined;

    // Feed headers only — should be incomplete.
    const r1 = parser.feed(header_part, &req);
    try std.testing.expect(r1 == .incomplete);

    // Feed body — should complete.
    const r2 = parser.feed(body, &req);
    switch (r2) {
        .complete => {},
        else => try std.testing.expect(false),
    }
    try std.testing.expectEqualStrings("hello", req.body);
}

// T0 — body policy tests.

/// Custom policy used by the T0 tests below: looks up a per-path cap
/// from a global map.  Production wiring lives in
/// `src/site_server/reactor.zig` (reactorBodyPolicy / ROUTE_BODY_POLICIES).
var test_caps: ?std.StringHashMap(usize) = null;

fn testPolicyFn(req: *const HttpRequest, _: *anyopaque) BodyPolicy {
    if (test_caps) |*m| {
        if (m.get(req.path)) |cap| return .{ .buffer = cap };
    }
    return .{ .buffer = DEFAULT_BODY_CAP };
}

fn streamPolicyFn(_: *const HttpRequest, _: *anyopaque) BodyPolicy {
    return .stream;
}

test "http_parser: per-route body cap accepts body within cap" {
    test_caps = std.StringHashMap(usize).init(std.testing.allocator);
    defer {
        test_caps.?.deinit();
        test_caps = null;
    }
    try test_caps.?.put("/big", 1024 * 1024); // 1 MB

    var dummy: u8 = 0;
    var parser = Parser.init(std.testing.allocator, &testPolicyFn, @ptrCast(&dummy));
    defer parser.deinit();

    // Build a 600 KB body — comfortably above the default 256 KB cap but
    // within the per-route 1 MB cap.
    const body_size = 600 * 1024;
    const body = try std.testing.allocator.alloc(u8, body_size);
    defer std.testing.allocator.free(body);
    @memset(body, 'x');

    const head = try std.fmt.allocPrint(std.testing.allocator,
        "POST /big HTTP/1.1\r\nContent-Length: {d}\r\n\r\n",
        .{body_size});
    defer std.testing.allocator.free(head);

    var req: HttpRequest = undefined;
    const r1 = parser.feed(head, &req);
    try std.testing.expect(r1 == .incomplete);
    const r2 = parser.feed(body, &req);
    try std.testing.expect(r2 == .complete);
    try std.testing.expectEqual(@as(usize, body_size), req.body.len);
}

test "http_parser: per-route body cap rejects body over cap" {
    test_caps = std.StringHashMap(usize).init(std.testing.allocator);
    defer {
        test_caps.?.deinit();
        test_caps = null;
    }
    try test_caps.?.put("/small", 1024); // 1 KB

    var dummy: u8 = 0;
    var parser = Parser.init(std.testing.allocator, &testPolicyFn, @ptrCast(&dummy));
    defer parser.deinit();

    // Content-Length: 2048 — over the 1 KB cap.
    const head = "POST /small HTTP/1.1\r\nContent-Length: 2048\r\n\r\n";
    var req: HttpRequest = undefined;
    const r = parser.feed(head, &req);
    try std.testing.expect(r == .err);
    if (r == .err) try std.testing.expectEqual(ParseError.BodyTooLarge, r.err);
}

test "http_parser: default policy still rejects > 256 KB" {
    // Backward-compat: a parser constructed with initDefault rejects
    // bodies over the DEFAULT_BODY_CAP, same as pre-T0 behaviour.
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();
    const head = "POST /x HTTP/1.1\r\nContent-Length: 300000\r\n\r\n";
    var req: HttpRequest = undefined;
    const r = parser.feed(head, &req);
    try std.testing.expect(r == .err);
    if (r == .err) try std.testing.expectEqual(ParseError.BodyTooLarge, r.err);
}

test "http_parser: stream policy returns StreamNotImplemented" {
    var dummy: u8 = 0;
    var parser = Parser.init(std.testing.allocator, &streamPolicyFn, @ptrCast(&dummy));
    defer parser.deinit();
    const head = "POST /stream HTTP/1.1\r\nContent-Length: 1\r\n\r\n";
    var req: HttpRequest = undefined;
    const r = parser.feed(head, &req);
    try std.testing.expect(r == .err);
    if (r == .err) try std.testing.expectEqual(ParseError.StreamNotImplemented, r.err);
}

test "http_parser: reset frees body_buf, parser ready for next request" {
    var parser = Parser.initDefault(std.testing.allocator);
    defer parser.deinit();

    const input1 = "POST /a HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc";
    var req1: HttpRequest = undefined;
    const r1 = parser.feed(input1, &req1);
    try std.testing.expect(r1 == .complete);
    try std.testing.expectEqualStrings("abc", req1.body);

    parser.reset();

    const input2 = "POST /b HTTP/1.1\r\nContent-Length: 2\r\n\r\nyz";
    var req2: HttpRequest = undefined;
    const r2 = parser.feed(input2, &req2);
    try std.testing.expect(r2 == .complete);
    try std.testing.expectEqualStrings("yz", req2.body);
}

```
