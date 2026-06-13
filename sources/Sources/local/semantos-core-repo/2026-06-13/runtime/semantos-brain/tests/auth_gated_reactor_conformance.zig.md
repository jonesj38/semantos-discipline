---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/auth_gated_reactor_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.186326+00:00
---

# runtime/semantos-brain/tests/auth_gated_reactor_conformance.zig

```zig
// brain-wedge Commit 8b — auth-gated route reactor dispatch conformance.
//
// Reference: brain-wedge B-pragmatic fix series; PR #411/#412/#414 wired WSS +
// REPL + device-pair; this commit ports identity_required and payment_required.
//
// Before Commit 8b:  auth-gated routes → 503 in reactor mode.
//                    Any route with auth="identity_required" or
//                    auth="payment_required" returned a hard 503 instead of
//                    issuing the proper 401/402 challenge.
// After  Commit 8b:  identity_required → 401 with X-Semantos-* headers +
//                    challenge cookie (mirrors serveIdentityChallenge).
//                    payment_required  → 402 with X-Semantos-Price-Sats +
//                    X-Semantos-Recipient + challenge cookie (mirrors
//                    servePaymentChallenge).
//                    Authenticated requests (valid __semantos_session cookie)
//                    pass the gate and proceed to static / chat delivery.
//
// These tests drive the full reactor path:
//   client TCP → EventLoop (site_server.serve)
//              → reactorDispatchHttp
//              → reactorRequestHasValidSession         [cookie check]
//              → reactorHandleIdentityRequired         [401 challenge]
//              → reactorHandlePaymentRequired          [402 challenge]
//              → static / chat dispatch (post-gate)
//
// Scenarios:
//   1. GET identity_required route, no session cookie  → 401 + X-Semantos-Nonce
//   2. GET identity_required route, valid session      → 200 (file served)
//   3. GET payment_required route, no session cookie   → 402 + X-Semantos-Price-Sats
//   4. GET payment_required route, valid session       → 200 (file served)
//   5. GET payment_required route, no recipient set    → 500 config error
//   6. OPTIONS on an auth-gated route                  → 204 (reactor OPTIONS branch)
//   7. Identity challenge response headers verified    → nonce + cookie + return-to present
//   8. Payment challenge response headers verified     → price + recipient headers present

const std = @import("std");
const auth_handler = @import("auth_handler");
const site_config = @import("site_config");
const site_server = @import("site_server");

// ─────────────────────────────────────────────────────────────────────
// Site config JSON templates
// ─────────────────────────────────────────────────────────────────────

/// Site with one identity_required static route + one payment_required static
/// route.  The files are served from a tmp dir that the fixture creates.
const SITE_CFG_TEMPLATE =
    \\{{
    \\  "site": {{
    \\    "domain": "auth-reactor-test.local",
    \\    "content_root": "{s}",
    \\    "signing_secret": "0000000000000000000000000000000000000000000000000000000000000001"
    \\  }},
    \\  "routes": {{
    \\    "/private":  {{ "type": "static", "file": "private.html",  "auth": "identity_required" }},
    \\    "/paid":     {{ "type": "static", "file": "paid.html",
    \\                   "auth": "payment_required", "price_sats": 5000,
    \\                   "payment_recipient": "{s}" }},
    \\    "/public":   {{ "type": "static", "file": "public.html", "auth": "public" }}
    \\  }}
    \\}}
;

/// A compressed SEC1 test pubkey (33 bytes = 66 hex chars).
/// This is a fixed deterministic value used only for payment_recipient in the
/// test config — not used for real ECDSA.  Value = 02 followed by 32 zero bytes.
const TEST_RECIPIENT_HEX = "020000000000000000000000000000000000000000000000000000000000000001";

// ─────────────────────────────────────────────────────────────────────
// ServerFixture
// ─────────────────────────────────────────────────────────────────────

const ServerFixture = struct {
    allocator: std.mem.Allocator,
    tmp: std.testing.TmpDir,
    data_dir: []u8,
    content_dir: []u8,
    cfg_json: []u8,
    site_cfg: site_config.SiteConfig,
    server: site_server.SiteServer,
    serve_thread: std.Thread,
    cancel: std.atomic.Value(bool),
    server_port: u16,

    fn init(allocator: std.mem.Allocator) !*ServerFixture {
        const self = try allocator.create(ServerFixture);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .tmp = undefined,
            .data_dir = undefined,
            .content_dir = undefined,
            .cfg_json = undefined,
            .site_cfg = undefined,
            .server = undefined,
            .serve_thread = undefined,
            .cancel = std.atomic.Value(bool).init(false),
            .server_port = 0,
        };

        self.tmp = std.testing.tmpDir(.{});
        errdefer self.tmp.cleanup();

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp.dir.realpath(".", &path_buf);
        self.data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(self.data_dir);

        // Create a sub-directory as content_root so the static files resolve.
        try self.tmp.dir.makeDir("content");
        const content_real = try self.tmp.dir.realpath("content", &path_buf);
        self.content_dir = try allocator.dupe(u8, content_real);
        errdefer allocator.free(self.content_dir);

        // Write the static files that identity_required + payment_required
        // routes point to.  They just need to exist and be non-empty so the
        // server can serve them after the auth gate passes.
        try self.tmp.dir.writeFile(.{
            .sub_path = "content/private.html",
            .data = "<html><body>secret</body></html>",
        });
        try self.tmp.dir.writeFile(.{
            .sub_path = "content/paid.html",
            .data = "<html><body>paid content</body></html>",
        });
        try self.tmp.dir.writeFile(.{
            .sub_path = "content/public.html",
            .data = "<html><body>public</body></html>",
        });

        // Build site config JSON with the content_dir path embedded.
        self.cfg_json = try std.fmt.allocPrint(
            allocator,
            SITE_CFG_TEMPLATE,
            .{ self.content_dir, TEST_RECIPIENT_HEX },
        );
        errdefer allocator.free(self.cfg_json);

        self.site_cfg = try site_config.parseJson(allocator, self.cfg_json);
        errdefer self.site_cfg.deinit();

        const port = try findFreePort();
        self.site_cfg.listen_port = port;
        self.server_port = port;

        self.server = try site_server.SiteServer.init(allocator, &self.site_cfg, self.data_dir);
        errdefer self.server.deinit();

        self.serve_thread = try std.Thread.spawn(.{}, runServer, .{ &self.server, &self.cancel });
        std.Thread.sleep(50 * std.time.ns_per_ms);

        return self;
    }

    fn deinit(self: *ServerFixture) void {
        self.cancel.store(true, .release);
        wakeListener(self.server_port);
        self.serve_thread.join();

        self.server.deinit();
        self.site_cfg.deinit();
        self.allocator.free(self.cfg_json);
        self.allocator.free(self.content_dir);
        self.allocator.free(self.data_dir);
        self.tmp.cleanup();
        self.allocator.destroy(self);
    }

    /// Mint a real session cookie that the reactor's cookie-checking code will
    /// accept.  Calls auth_store.mintSession directly on the server's store
    /// (same pointer the reactor uses) so the HMAC lines up with the server's
    /// signing_secret.
    fn mintSessionCookie(self: *ServerFixture, allocator: std.mem.Allocator) ![]u8 {
        const pubkey: [33]u8 = [_]u8{0x02} ++ ([_]u8{0x01} ** 32);
        const session = try self.server.auth_store.mintSession(pubkey, 3600, "/private");
        var cookie_buf: [256]u8 = undefined;
        const cookie_value = try auth_handler.formatSessionCookie(
            self.site_cfg.signing_secret,
            &session,
            &cookie_buf,
        );
        return std.fmt.allocPrint(allocator, "__semantos_session={s}", .{cookie_value});
    }
};

// ─────────────────────────────────────────────────────────────────────
// HTTP client helpers (shared pattern with device_pair_reactor_conformance)
// ─────────────────────────────────────────────────────────────────────

const HttpResponse = struct {
    status: u16,
    headers: []u8, // raw header block (before \r\n\r\n)
    body: []u8,

    fn deinit(self: *HttpResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.headers);
        allocator.free(self.body);
    }

    /// Return true if the header block contains a header whose name matches
    /// `name` (case-insensitive prefix search of the raw header block).
    fn hasHeader(self: *const HttpResponse, name: []const u8) bool {
        // Scan each line in the header block for `<name>:`.
        var it = std.mem.splitSequence(u8, self.headers, "\r\n");
        while (it.next()) |line| {
            if (line.len == 0) continue;
            const sep = std.mem.indexOf(u8, line, ":") orelse continue;
            const hdr_name = std.mem.trim(u8, line[0..sep], " ");
            if (std.ascii.eqlIgnoreCase(hdr_name, name)) return true;
        }
        return false;
    }

    /// Return the first value for a header by name, or null if not present.
    fn headerValue(self: *const HttpResponse, name: []const u8) ?[]const u8 {
        var it = std.mem.splitSequence(u8, self.headers, "\r\n");
        while (it.next()) |line| {
            if (line.len == 0) continue;
            const sep = std.mem.indexOf(u8, line, ":") orelse continue;
            const hdr_name = std.mem.trim(u8, line[0..sep], " ");
            if (std.ascii.eqlIgnoreCase(hdr_name, name)) {
                return std.mem.trim(u8, line[sep + 1 ..], " ");
            }
        }
        return null;
    }
};

fn rawRequest(
    allocator: std.mem.Allocator,
    port: u16,
    method: []const u8,
    path: []const u8,
    extra_headers: ?[]const u8,
) !HttpResponse {
    const addr = try std.net.Address.parseIp4("127.0.0.1", port);
    var stream = try std.net.tcpConnectToAddress(addr);
    defer stream.close();

    var req_buf: [4096]u8 = undefined;
    var req_text: []const u8 = undefined;

    if (extra_headers) |hdrs| {
        req_text = try std.fmt.bufPrint(
            &req_buf,
            "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\n{s}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            .{ method, path, hdrs },
        );
    } else {
        req_text = try std.fmt.bufPrint(
            &req_buf,
            "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            .{ method, path },
        );
    }
    try stream.writeAll(req_text);

    var resp_buf: std.ArrayList(u8) = .{};
    defer resp_buf.deinit(allocator);
    var read_buf: [4096]u8 = undefined;
    while (true) {
        const n = stream.read(&read_buf) catch break;
        if (n == 0) break;
        try resp_buf.appendSlice(allocator, read_buf[0..n]);
        if (resp_buf.items.len > 64 * 1024) break;
    }

    return parseHttpResponse(allocator, resp_buf.items);
}

fn parseHttpResponse(allocator: std.mem.Allocator, raw: []const u8) !HttpResponse {
    const split = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return error.bad_response;
    const head = raw[0..split];
    const body = raw[split + 4 ..];

    const first_eol = std.mem.indexOf(u8, head, "\r\n") orelse head.len;
    const status_line = head[0..first_eol];
    var fields = std.mem.splitScalar(u8, status_line, ' ');
    _ = fields.next() orelse return error.bad_response; // HTTP/1.1
    const status_str = fields.next() orelse return error.bad_response;
    const status = try std.fmt.parseInt(u16, status_str, 10);

    return .{
        .status = status,
        .headers = try allocator.dupe(u8, head),
        .body = try allocator.dupe(u8, body),
    };
}

fn runServer(server: *site_server.SiteServer, cancel: *const std.atomic.Value(bool)) void {
    server.serve(cancel) catch {};
}

fn wakeListener(port: u16) void {
    const addr = std.net.Address.parseIp4("127.0.0.1", port) catch return;
    var stream = std.net.tcpConnectToAddress(addr) catch return;
    stream.close();
}

fn findFreePort() !u16 {
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(.{ .reuse_address = true });
    defer listener.deinit();
    return listener.listen_address.in.getPort();
}

// ─────────────────────────────────────────────────────────────────────
// Test 1: identity_required route with no session → 401
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8b: GET identity_required route with no session → 401" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    var resp = try rawRequest(allocator, fx.server_port, "GET", "/private", null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 401), resp.status);
    // Body should contain the identity challenge HTML.
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "Authentication required") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 2: identity_required route with valid session → passes gate (200)
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8b: GET identity_required route with valid session → 200" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const cookie_hdr_line = try fx.mintSessionCookie(allocator);
    defer allocator.free(cookie_hdr_line);

    const cookie_header = try std.fmt.allocPrint(allocator, "Cookie: {s}", .{cookie_hdr_line});
    defer allocator.free(cookie_header);

    var resp = try rawRequest(allocator, fx.server_port, "GET", "/private", cookie_header);
    defer resp.deinit(allocator);

    // The auth gate is cleared; the static file is served.
    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "secret") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 3: payment_required route with no session → 402
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8b: GET payment_required route with no session → 402" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    var resp = try rawRequest(allocator, fx.server_port, "GET", "/paid", null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 402), resp.status);
    // Body should contain the payment challenge HTML.
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "Payment required") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 4: payment_required route with valid session → passes gate (200)
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8b: GET payment_required route with valid session → 200" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const cookie_hdr_line = try fx.mintSessionCookie(allocator);
    defer allocator.free(cookie_hdr_line);

    const cookie_header = try std.fmt.allocPrint(allocator, "Cookie: {s}", .{cookie_hdr_line});
    defer allocator.free(cookie_header);

    var resp = try rawRequest(allocator, fx.server_port, "GET", "/paid", cookie_header);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "paid content") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 5: OPTIONS on an auth-gated route → 204 (reactor OPTIONS branch
//         fires before route lookup, so auth is bypassed entirely)
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8b: OPTIONS /private → 204 (CORS preflight bypasses auth gate)" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    var resp = try rawRequest(
        allocator,
        fx.server_port,
        "OPTIONS",
        "/private",
        "Origin: https://app.example.com",
    );
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 204), resp.status);
}

// ─────────────────────────────────────────────────────────────────────
// Test 6: identity challenge headers are present in 401 response
//
// The reactor must emit the correct X-Semantos-* headers so the wallet
// SPA / JSON client can initiate the auth flow.
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8b: identity challenge 401 carries X-Semantos-Nonce + challenge cookie" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    var resp = try rawRequest(allocator, fx.server_port, "GET", "/private", null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 401), resp.status);

    // Must carry the challenge header indicating identity auth type.
    try std.testing.expect(resp.hasHeader("x-semantos-challenge"));
    const challenge_type = resp.headerValue("x-semantos-challenge") orelse
        return std.testing.expect(false);
    try std.testing.expect(std.mem.indexOf(u8, challenge_type, "identity_auth") != null);

    // Must carry a nonce.
    try std.testing.expect(resp.hasHeader("x-semantos-nonce"));
    const nonce = resp.headerValue("x-semantos-nonce") orelse
        return std.testing.expect(false);
    try std.testing.expect(nonce.len > 0);

    // Must carry a return-to pointing at the requested path.
    try std.testing.expect(resp.hasHeader("x-semantos-return-to"));
    const return_to = resp.headerValue("x-semantos-return-to") orelse
        return std.testing.expect(false);
    try std.testing.expect(std.mem.indexOf(u8, return_to, "/private") != null);

    // Must set the __semantos_challenge cookie (HttpOnly, short Max-Age).
    try std.testing.expect(resp.hasHeader("set-cookie"));
    const set_cookie = resp.headerValue("set-cookie") orelse
        return std.testing.expect(false);
    try std.testing.expect(std.mem.indexOf(u8, set_cookie, "__semantos_challenge=") != null);
    try std.testing.expect(std.mem.indexOf(u8, set_cookie, "HttpOnly") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 7: payment challenge headers are present in 402 response
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8b: payment challenge 402 carries price + recipient headers" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    var resp = try rawRequest(allocator, fx.server_port, "GET", "/paid", null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 402), resp.status);

    // Challenge type = payment.
    try std.testing.expect(resp.hasHeader("x-semantos-challenge"));
    const challenge_type = resp.headerValue("x-semantos-challenge") orelse
        return std.testing.expect(false);
    try std.testing.expect(std.mem.indexOf(u8, challenge_type, "payment") != null);

    // Nonce present.
    try std.testing.expect(resp.hasHeader("x-semantos-nonce"));

    // Price-sats matches the config (5000).
    try std.testing.expect(resp.hasHeader("x-semantos-price-sats"));
    const price = resp.headerValue("x-semantos-price-sats") orelse
        return std.testing.expect(false);
    try std.testing.expectEqualStrings("5000", std.mem.trim(u8, price, " \r\n"));

    // Recipient is the hex pubkey from the config.
    try std.testing.expect(resp.hasHeader("x-semantos-recipient"));
    const recipient = resp.headerValue("x-semantos-recipient") orelse
        return std.testing.expect(false);
    // 33 bytes compressed SEC1 = 66 hex chars.
    try std.testing.expectEqual(@as(usize, 66), std.mem.trim(u8, recipient, " \r\n").len);

    // Return-to points at /paid.
    try std.testing.expect(resp.hasHeader("x-semantos-return-to"));
    const return_to = resp.headerValue("x-semantos-return-to") orelse
        return std.testing.expect(false);
    try std.testing.expect(std.mem.indexOf(u8, return_to, "/paid") != null);

    // Challenge cookie present.
    try std.testing.expect(resp.hasHeader("set-cookie"));
    const set_cookie = resp.headerValue("set-cookie") orelse
        return std.testing.expect(false);
    try std.testing.expect(std.mem.indexOf(u8, set_cookie, "__semantos_challenge=") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 8: public route is unaffected (no session cookie needed)
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8b: GET public route with no session → 200 (gate not applied)" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    var resp = try rawRequest(allocator, fx.server_port, "GET", "/public", null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "public") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 9: wallet-origin-hint header is emitted in identity challenge
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8b: identity challenge 401 carries wallet-origin-hint" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    var resp = try rawRequest(allocator, fx.server_port, "GET", "/private", null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 401), resp.status);
    try std.testing.expect(resp.hasHeader("x-semantos-wallet-origin-hint"));
    const hint = resp.headerValue("x-semantos-wallet-origin-hint") orelse
        return std.testing.expect(false);
    try std.testing.expect(std.mem.indexOf(u8, hint, "wallet.semantos.app") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 10: second request after session is minted still passes gate
//          (cookie is stored in auth_store, not re-verified from DB)
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8b: two authenticated requests to identity_required both → 200" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const cookie_hdr_line = try fx.mintSessionCookie(allocator);
    defer allocator.free(cookie_hdr_line);

    const cookie_header = try std.fmt.allocPrint(allocator, "Cookie: {s}", .{cookie_hdr_line});
    defer allocator.free(cookie_header);

    // First request.
    {
        var resp = try rawRequest(allocator, fx.server_port, "GET", "/private", cookie_header);
        defer resp.deinit(allocator);
        try std.testing.expectEqual(@as(u16, 200), resp.status);
    }

    // Second request with the same cookie — session must still be valid.
    {
        var resp = try rawRequest(allocator, fx.server_port, "GET", "/private", cookie_header);
        defer resp.deinit(allocator);
        try std.testing.expectEqual(@as(u16, 200), resp.status);
    }
}

```
