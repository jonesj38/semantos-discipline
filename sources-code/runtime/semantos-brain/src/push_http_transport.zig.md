---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/push_http_transport.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.218503+00:00
---

# runtime/semantos-brain/src/push_http_transport.zig

```zig
// D-O5m.followup-9 Phase B — HTTP transport seam shared by the APNs +
// FCM dispatchers.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §D-O5m.followup-9
// Phase B (apns + fcm dispatcher requirements).
//
// The dispatchers need an HTTP client that:
//   1. POSTs JSON to a URL with arbitrary headers.
//   2. Returns the response status + headers + body so the dispatcher
//      can read the expiry hints (`apns-id`, `apns-unique-id`, `error`
//      in the body, etc.).
//   3. Is INJECTABLE — tests must run without hitting Apple / Google.
//
// `std.http.Client` does (1) + (2) but isn't easy to swap out for a
// fake.  This module wraps it in a tiny vtable so the production path
// uses `std.http.Client` and tests use a script-driven mock that
// captures the request shape and replays a queued response.
//
// Trust-boundary note: the .p8 / service-account JSON paths are in
// the dispatcher config, not on the wire.  This module is plain
// transport — never sees the signing material.

const std = @import("std");

pub const TransportError = error{
    transport_error,
    out_of_memory,
};

/// One header — name + value, both borrowed for the duration of the
/// `post` call.
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// A response captured from the transport.  `headers` is an alloc-
/// owned slice of (name, value) pairs (both alloc-owned strings).
/// `body` is alloc-owned.  Caller frees via `Response.deinit`.
pub const Response = struct {
    status: u16,
    headers: []HeaderPair,
    body: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Response) void {
        for (self.headers) |h| {
            self.allocator.free(h.name);
            self.allocator.free(h.value);
        }
        if (self.headers.len > 0) self.allocator.free(self.headers);
        if (self.body.len > 0) self.allocator.free(self.body);
        self.headers = &.{};
        self.body = &.{};
    }

    pub fn headerValue(self: *const Response, name: []const u8) ?[]const u8 {
        for (self.headers) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
        }
        return null;
    }
};

pub const HeaderPair = struct {
    name: []u8,
    value: []u8,
};

pub const Request = struct {
    /// "POST" — both APNs + FCM are POST only at v0.1.
    method: []const u8 = "POST",
    url: []const u8,
    headers: []const Header,
    body: []const u8,
};

/// A vtable-based HTTP transport.  The dispatcher calls
/// `transport.post(allocator, req)`; the implementation does the
/// rest.  `state` is the implementation's opaque context pointer.
pub const HttpTransport = struct {
    state: ?*anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        post: *const fn (
            state: ?*anyopaque,
            allocator: std.mem.Allocator,
            req: Request,
        ) TransportError!Response,
    };

    pub fn post(
        self: HttpTransport,
        allocator: std.mem.Allocator,
        req: Request,
    ) TransportError!Response {
        return self.vtable.post(self.state, allocator, req);
    }
};

// ─── Production transport — std.http.Client adapter ─────────────────

/// Production transport backed by `std.http.Client`.  Single-shot per
/// post (we don't reuse connections across calls — the volumes are
/// low enough that connection setup is not the bottleneck).
pub const StdHttpTransport = struct {
    pub fn transport(self: *StdHttpTransport) HttpTransport {
        return .{ .state = self, .vtable = &std_http_vtable };
    }

    const std_http_vtable: HttpTransport.VTable = .{ .post = stdPost };

    fn stdPost(
        state: ?*anyopaque,
        allocator: std.mem.Allocator,
        req: Request,
    ) TransportError!Response {
        _ = state;

        // Translate Header[] → std.http.Header[].
        var hdrs = std.ArrayList(std.http.Header){};
        defer hdrs.deinit(allocator);
        for (req.headers) |h| {
            hdrs.append(allocator, .{ .name = h.name, .value = h.value }) catch
                return TransportError.out_of_memory;
        }

        var resp_writer = std.io.Writer.Allocating.init(allocator);
        defer resp_writer.deinit();

        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        const result = client.fetch(.{
            .location = .{ .url = req.url },
            .method = .POST,
            .payload = req.body,
            .extra_headers = hdrs.items,
            .response_writer = &resp_writer.writer,
        }) catch return TransportError.transport_error;

        const body_bytes = resp_writer.written();
        const owned_body: []u8 = if (body_bytes.len > 0)
            allocator.dupe(u8, body_bytes) catch return TransportError.out_of_memory
        else
            &.{};

        // std.http.Client.fetch in 0.15.x doesn't surface response
        // headers — the fetch API only returns status.  For the v0.1
        // dispatchers this is fine: the body carries the actionable
        // information (Apple's `reason` field; Google's `error.status`).
        return .{
            .status = @intFromEnum(result.status),
            .headers = &.{},
            .body = owned_body,
            .allocator = allocator,
        };
    }
};

// ─── Mock transport for tests ───────────────────────────────────────

/// One queued response the mock will return on the next post() call.
pub const MockResponse = struct {
    status: u16,
    headers: []const HeaderPair = &.{},
    body: []const u8 = "",
};

/// One captured request.  Owned strings for the assertion path so the
/// test doesn't have to keep the original Request alive.
pub const CapturedRequest = struct {
    method: []u8,
    url: []u8,
    headers: []HeaderPair,
    body: []u8,

    pub fn deinit(self: *CapturedRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.method);
        allocator.free(self.url);
        for (self.headers) |h| {
            allocator.free(h.name);
            allocator.free(h.value);
        }
        if (self.headers.len > 0) allocator.free(self.headers);
        allocator.free(self.body);
    }
};

/// A scripted mock that captures every request and replays queued
/// responses in order.  When the queue is empty, returns
/// `transport_error` (the test set up wrong).
pub const MockTransport = struct {
    allocator: std.mem.Allocator,
    /// FIFO queue of pre-baked responses.  Owned by the mock.
    responses: std.ArrayList(MockResponse),
    /// Captured requests in arrival order.  Owned by the mock; freed
    /// in `deinit`.
    captured: std.ArrayList(CapturedRequest),
    /// When true, the next post() returns transport_error instead of
    /// popping a response.  Used to exercise the dispatcher's retry
    /// loop without burning queued responses.
    inject_transport_errors: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) MockTransport {
        return .{
            .allocator = allocator,
            .responses = .{},
            .captured = .{},
        };
    }

    pub fn deinit(self: *MockTransport) void {
        for (self.responses.items) |*r| {
            // We do NOT own r.headers or r.body — the test queued them
            // as borrowed slices.  Just drop the queue.
            _ = r;
        }
        self.responses.deinit(self.allocator);
        for (self.captured.items) |*c| c.deinit(self.allocator);
        self.captured.deinit(self.allocator);
    }

    pub fn enqueueOk(self: *MockTransport, body: []const u8) !void {
        try self.responses.append(self.allocator, .{
            .status = 200,
            .headers = &.{},
            .body = body,
        });
    }

    pub fn enqueue(self: *MockTransport, resp: MockResponse) !void {
        try self.responses.append(self.allocator, resp);
    }

    pub fn enqueueTransportError(self: *MockTransport) void {
        self.inject_transport_errors += 1;
    }

    pub fn transport(self: *MockTransport) HttpTransport {
        return .{ .state = self, .vtable = &mock_vtable };
    }

    pub fn requestCount(self: *const MockTransport) usize {
        return self.captured.items.len;
    }

    pub fn lastRequest(self: *const MockTransport) ?*const CapturedRequest {
        if (self.captured.items.len == 0) return null;
        return &self.captured.items[self.captured.items.len - 1];
    }

    const mock_vtable: HttpTransport.VTable = .{ .post = mockPost };

    fn mockPost(
        state: ?*anyopaque,
        allocator: std.mem.Allocator,
        req: Request,
    ) TransportError!Response {
        const self: *MockTransport = @ptrCast(@alignCast(state.?));

        // Build a CapturedRequest, then move ownership into self.captured.
        // A single ownership-flag drives the error-cleanup so once the
        // list has the strings, subsequent error returns in this fn (e.g.
        // queued transport_error, empty queue) MUST NOT free them again.
        var captured: CapturedRequest = .{
            .method = &.{},
            .url = &.{},
            .headers = &.{},
            .body = &.{},
        };
        var captured_handed_off: bool = false;
        var headers_filled: usize = 0;
        errdefer if (!captured_handed_off) {
            // Free in built order.  The header alloc may be live with
            // only `headers_filled` entries populated.
            if (captured.method.len > 0) self.allocator.free(captured.method);
            if (captured.url.len > 0) self.allocator.free(captured.url);
            if (captured.body.len > 0) self.allocator.free(captured.body);
            if (captured.headers.len > 0) {
                var hi: usize = 0;
                while (hi < headers_filled) : (hi += 1) {
                    self.allocator.free(captured.headers[hi].name);
                    self.allocator.free(captured.headers[hi].value);
                }
                self.allocator.free(captured.headers);
            }
        };

        captured.method = self.allocator.dupe(u8, req.method) catch return TransportError.out_of_memory;
        captured.url = self.allocator.dupe(u8, req.url) catch return TransportError.out_of_memory;
        captured.body = self.allocator.dupe(u8, req.body) catch return TransportError.out_of_memory;

        if (req.headers.len > 0) {
            const hs = self.allocator.alloc(HeaderPair, req.headers.len) catch
                return TransportError.out_of_memory;
            captured.headers = hs;
            var n: usize = 0;
            while (n < req.headers.len) : (n += 1) {
                hs[n] = .{
                    .name = self.allocator.dupe(u8, req.headers[n].name) catch
                        return TransportError.out_of_memory,
                    .value = undefined,
                };
                hs[n].value = self.allocator.dupe(u8, req.headers[n].value) catch {
                    // The name was already duped; fold it into the
                    // headers_filled count so the errdefer frees it.
                    self.allocator.free(hs[n].name);
                    return TransportError.out_of_memory;
                };
                headers_filled = n + 1;
            }
        }
        self.captured.append(self.allocator, captured) catch return TransportError.out_of_memory;
        captured_handed_off = true;

        // Honour any queued transport error.
        if (self.inject_transport_errors > 0) {
            self.inject_transport_errors -= 1;
            return TransportError.transport_error;
        }

        // Pop the next response.
        if (self.responses.items.len == 0) return TransportError.transport_error;
        const resp = self.responses.orderedRemove(0);

        // Dupe the body + headers into the caller's allocator so the
        // Response's deinit hits the same allocator that owns the
        // duplicated data.  (The Response deinit frees with whatever
        // allocator we hand back.)
        const body_dup: []u8 = if (resp.body.len > 0)
            allocator.dupe(u8, resp.body) catch return TransportError.out_of_memory
        else
            &.{};

        const headers_dup: []HeaderPair = if (resp.headers.len > 0) blk: {
            const hs = allocator.alloc(HeaderPair, resp.headers.len) catch
                return TransportError.out_of_memory;
            for (resp.headers, 0..) |h, i| {
                hs[i] = .{
                    .name = allocator.dupe(u8, h.name) catch return TransportError.out_of_memory,
                    .value = allocator.dupe(u8, h.value) catch return TransportError.out_of_memory,
                };
            }
            break :blk hs;
        } else &.{};

        return .{
            .status = resp.status,
            .headers = headers_dup,
            .body = body_dup,
            .allocator = allocator,
        };
    }
};

// ─── base64url helpers — used by both APNs + FCM JWT builders ────────

/// Encode bytes as base64url WITHOUT padding (per RFC 7515 §2).
/// Caller-owned slice; caller frees.
pub fn base64UrlEncode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const Base64 = std.base64.url_safe_no_pad.Encoder;
    const out_len = Base64.calcSize(data.len);
    const out = try allocator.alloc(u8, out_len);
    _ = Base64.encode(out, data);
    return out;
}

/// Decode base64url-no-padding bytes.  Caller frees the returned slice.
pub fn base64UrlDecode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const Base64 = std.base64.url_safe_no_pad.Decoder;
    const out_len = try Base64.calcSizeForSlice(encoded);
    const out = try allocator.alloc(u8, out_len);
    errdefer allocator.free(out);
    try Base64.decode(out, encoded);
    return out;
}

// ─── Tests ───────────────────────────────────────────────────────────

test "MockTransport: enqueue + post round-trip captures the request" {
    const allocator = std.testing.allocator;
    var mock = MockTransport.init(allocator);
    defer mock.deinit();

    try mock.enqueueOk("{\"ok\":true}");
    const t = mock.transport();
    var resp = try t.post(allocator, .{
        .url = "https://example.test/path",
        .headers = &.{
            .{ .name = "authorization", .value = "Bearer ABC" },
            .{ .name = "content-type", .value = "application/json" },
        },
        .body = "{\"hello\":1}",
    });
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings("{\"ok\":true}", resp.body);
    try std.testing.expectEqual(@as(usize, 1), mock.requestCount());
    const captured = mock.lastRequest().?;
    try std.testing.expectEqualStrings("POST", captured.method);
    try std.testing.expectEqualStrings("https://example.test/path", captured.url);
    try std.testing.expectEqualStrings("{\"hello\":1}", captured.body);
    try std.testing.expectEqual(@as(usize, 2), captured.headers.len);
    try std.testing.expectEqualStrings("authorization", captured.headers[0].name);
    try std.testing.expectEqualStrings("Bearer ABC", captured.headers[0].value);
}

test "MockTransport: empty queue returns transport_error" {
    const allocator = std.testing.allocator;
    var mock = MockTransport.init(allocator);
    defer mock.deinit();

    const t = mock.transport();
    try std.testing.expectError(TransportError.transport_error, t.post(allocator, .{
        .url = "https://example.test/",
        .headers = &.{},
        .body = "",
    }));
}

test "MockTransport: enqueueTransportError fires before queued responses" {
    const allocator = std.testing.allocator;
    var mock = MockTransport.init(allocator);
    defer mock.deinit();

    mock.enqueueTransportError();
    try mock.enqueueOk("{\"ok\":true}");

    const t = mock.transport();
    try std.testing.expectError(TransportError.transport_error, t.post(allocator, .{
        .url = "https://example.test/",
        .headers = &.{},
        .body = "",
    }));
    var resp = try t.post(allocator, .{
        .url = "https://example.test/",
        .headers = &.{},
        .body = "",
    });
    defer resp.deinit();
    try std.testing.expectEqual(@as(u16, 200), resp.status);
}

test "base64UrlEncode RFC 7515 fixture" {
    const allocator = std.testing.allocator;
    // RFC 7515 Appendix A.3.1 — JOSE header
    // {"alg":"ES256"} → "eyJhbGciOiJFUzI1NiJ9"
    const encoded = try base64UrlEncode(allocator, "{\"alg\":\"ES256\"}");
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("eyJhbGciOiJFUzI1NiJ9", encoded);
}

test "base64UrlEncode/Decode round-trips arbitrary bytes" {
    const allocator = std.testing.allocator;
    const original = [_]u8{ 0x00, 0xff, 0x10, 0x42, 0x7e, 0x80, 0xa5, 0x3c, 0xff };
    const encoded = try base64UrlEncode(allocator, &original);
    defer allocator.free(encoded);
    // No padding characters.
    try std.testing.expect(std.mem.indexOf(u8, encoded, "=") == null);
    const decoded = try base64UrlDecode(allocator, encoded);
    defer allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, &original, decoded);
}

test "Response.headerValue is case-insensitive" {
    const allocator = std.testing.allocator;
    var headers = try allocator.alloc(HeaderPair, 1);
    headers[0] = .{
        .name = try allocator.dupe(u8, "Apns-Id"),
        .value = try allocator.dupe(u8, "abc-123"),
    };
    var resp: Response = .{
        .status = 200,
        .headers = headers,
        .body = &.{},
        .allocator = allocator,
    };
    defer resp.deinit();
    try std.testing.expectEqualStrings("abc-123", resp.headerValue("apns-id").?);
    try std.testing.expectEqualStrings("abc-123", resp.headerValue("APNS-ID").?);
    try std.testing.expect(resp.headerValue("missing") == null);
}

```
