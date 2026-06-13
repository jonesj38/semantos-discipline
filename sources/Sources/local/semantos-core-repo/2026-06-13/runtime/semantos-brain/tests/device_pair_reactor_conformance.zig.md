---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/device_pair_reactor_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.201091+00:00
---

# runtime/semantos-brain/tests/device_pair_reactor_conformance.zig

```zig
// brain-wedge Commit 8a — POST /api/v1/device-pair reactor dispatch conformance.
//
// Reference: brain-wedge B-pragmatic fix series; PR #411/#412 wired WSS + REPL;
// this commit ports device-pair.
//
// Before Commit 8a:  POST /api/v1/device-pair → 503 in reactor mode.
//                    A fresh install / token-expired device can't pair.
// After  Commit 8a:  POST /api/v1/device-pair → 200 with registered JSON body
//                    mirroring the blocking device_pair_http.maybeHandle path.
//
// These tests drive the full reactor path:
//   client TCP → EventLoop (site_server.serve)
//              → reactorDispatchHttp
//              → reactorHandleDevicePair
//              → device_pair_http.parseAcceptRequest (JSON body parse)
//              → device_pair_http.accept (BRC-42 derivation verify + cert store)
//              → JSON response on wire
//
// Scenarios:
//   1. POST with valid payload → 200 + {"status":"registered","cert_id":...}
//   2. POST with malformed JSON body → 400 derivation_missing_fields
//   3. GET /api/v1/device-pair → 405 method_not_allowed
//   4. POST when device_pair_acceptor is null → 503
//   5. OPTIONS preflight → 204 + CORS headers (reactor OPTIONS branch)

const std = @import("std");
const bsvz = @import("bsvz");
const bkds = @import("bkds");
const device_pair = @import("device_pair");
const device_pair_http = @import("device_pair_http");
const identity_certs = @import("identity_certs");
const bearer_tokens = @import("bearer_tokens");
const site_config = @import("site_config");
const site_server = @import("site_server");

// ─────────────────────────────────────────────────────────────────────
// Minimal site config — no routes; /api/v1/device-pair is a reserved
// prefix handled before route lookup.
// ─────────────────────────────────────────────────────────────────────

const SITE_CFG_JSON =
    \\{
    \\  "site": {
    \\    "domain": "device-pair-reactor-test.local",
    \\    "content_root": "."
    \\  },
    \\  "routes": {}
    \\}
;

// Token expiry is set relative to the real clock so the acceptor (which uses
// std.time.timestamp internally) doesn't see the payload as expired.
// 24 hours from the build-time epoch is more than enough for any test run.
const TOKEN_TTL: i64 = 86400; // 24 hours

// ─────────────────────────────────────────────────────────────────────
// Crypto fixture helpers (reused from device_pair_http_conformance)
// ─────────────────────────────────────────────────────────────────────

fn buildToken(
    allocator: std.mem.Allocator,
    privkey: [bkds.PRIVKEY_LEN]u8,
    pubkey: [bkds.PUBKEY_LEN]u8,
    cert_id: [32]u8,
    label: []const u8,
    context_tag: u8,
    nonce_byte: u8,
    expires_at: i64,
) !device_pair.SignedToken {
    var nonce: [device_pair.NONCE_LEN]u8 = undefined;
    @memset(&nonce, nonce_byte);
    const caps = [_][]const u8{ "cap.attach.photo", "cap.attach.gps" };
    const payload = device_pair.PairPayload{
        .operator_root_cert_id = cert_id,
        .operator_root_pub = pubkey,
        .context_tag = context_tag,
        .label = label,
        .capabilities = &caps,
        .expires_at = expires_at,
        .nonce = nonce,
        .brain_pair_endpoint = "https://brain.test/api/v1/device-pair",
        .brain_wss_endpoint = "wss://brain.test/api/v1/wallet",
        .brain_pin_cert_id = cert_id,
        .brain_pin_pubkey = pubkey,
    };
    return device_pair.signAndEncode(allocator, payload, privkey);
}

fn deriveDevicePair(
    operator_pub: [bkds.PUBKEY_LEN]u8,
    context_tag: u8,
    label: []const u8,
    device_seed: []const u8,
) !struct {
    device_pub: [bkds.PUBKEY_LEN]u8,
    child_pub: [bkds.PUBKEY_LEN]u8,
} {
    const dpriv = bkds.privFromSeed(device_seed);
    const priv_obj = try bsvz.primitives.ec.PrivateKey.fromBytes(dpriv);
    const dpub_obj = try priv_obj.publicKey();
    const dpub = dpub_obj.toCompressedSec1();
    const child = try bkds.deriveChildPubkeyFromDevice(dpriv, operator_pub, context_tag, label);
    return .{ .device_pub = dpub, .child_pub = child };
}

// ─────────────────────────────────────────────────────────────────────
// ServerFixture — reactor server with device-pair acceptor attached.
// ─────────────────────────────────────────────────────────────────────

const ServerFixture = struct {
    allocator: std.mem.Allocator,
    tmp: std.testing.TmpDir,
    data_dir: []u8,
    site_cfg: site_config.SiteConfig,
    server: site_server.SiteServer,
    cert_store: identity_certs.CertStore,
    acceptor: device_pair_http.Acceptor,
    token_store: bearer_tokens.TokenStore,
    privkey: [bkds.PRIVKEY_LEN]u8,
    pubkey: [bkds.PUBKEY_LEN]u8,
    cert_id: [32]u8,
    serve_thread: std.Thread,
    cancel: std.atomic.Value(bool),
    server_port: u16,

    fn init(allocator: std.mem.Allocator, operator_seed: []const u8) !*ServerFixture {
        const self = try allocator.create(ServerFixture);
        errdefer allocator.destroy(self);

        // Pre-initialise all fields to undefined so pointers into self
        // are stable before we start building components.  Pattern from
        // repl_http_reactor_conformance.zig.
        self.* = .{
            .allocator = allocator,
            .tmp = undefined,
            .data_dir = undefined,
            .site_cfg = undefined,
            .server = undefined,
            .cert_store = undefined,
            .acceptor = undefined,
            .token_store = undefined,
            .privkey = undefined,
            .pubkey = undefined,
            .cert_id = undefined,
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

        // Derive operator key material from seed.
        self.privkey = bkds.privFromSeed(operator_seed);
        self.pubkey = try bkds.pubFromSeed(operator_seed);
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&self.pubkey, &hash, .{});
        bkds.hexEncode(hash[0..16], &self.cert_id);

        // Parse site config + pick free port.
        self.site_cfg = try site_config.parseJson(allocator, SITE_CFG_JSON);
        errdefer self.site_cfg.deinit();
        const port = try findFreePort();
        self.site_cfg.listen_port = port;
        self.server_port = port;

        // Build cert store with root cert seeded into it.
        self.cert_store = try identity_certs.CertStore.init(allocator, self.data_dir, std.time.timestamp);
        errdefer self.cert_store.deinit();
        _ = try self.cert_store.issueRoot(self.pubkey, "operator");

        // Build bearer token store.
        self.token_store = try bearer_tokens.TokenStore.init(allocator, self.data_dir, std.time.timestamp);
        errdefer self.token_store.deinit();

        // Build the device-pair acceptor (cert_store pointer is now stable).
        self.acceptor = device_pair_http.Acceptor.init(allocator, &self.cert_store, self.data_dir);
        self.acceptor.setOperatorRootPriv(self.privkey);
        // Wire bearer token store into acceptor so it mints a bearer on success.
        self.acceptor.setTokenStore(&self.token_store);

        // Build the site server (site_cfg pointer is now stable).
        self.server = try site_server.SiteServer.init(allocator, &self.site_cfg, self.data_dir);
        errdefer self.server.deinit();

        // Wire acceptor into site server.
        self.server.attachDevicePairAcceptor(&self.acceptor);

        // Spawn the reactor on a background thread.
        self.serve_thread = try std.Thread.spawn(.{}, runServer, .{ &self.server, &self.cancel });
        std.Thread.sleep(50 * std.time.ns_per_ms);

        return self;
    }

    fn deinit(self: *ServerFixture) void {
        self.cancel.store(true, .release);
        wakeListener(self.server_port);
        self.serve_thread.join();

        self.server.deinit();
        self.token_store.deinit();
        self.cert_store.deinit();
        self.site_cfg.deinit();
        self.tmp.cleanup();
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }

    /// Build a valid device-pair request body JSON for this fixture's operator.
    fn buildValidBody(
        self: *ServerFixture,
        allocator: std.mem.Allocator,
        label: []const u8,
        context_tag: u8,
        nonce_byte: u8,
        device_seed: []const u8,
    ) ![]u8 {
        // Use the real clock so the acceptor (which also uses std.time.timestamp)
        // doesn't reject the payload as expired.
        const now: i64 = @intCast(std.time.timestamp());
        var tok = try buildToken(
            allocator,
            self.privkey,
            self.pubkey,
            self.cert_id,
            label,
            context_tag,
            nonce_byte,
            now + TOKEN_TTL,
        );
        defer tok.deinit(allocator);

        const dev = try deriveDevicePair(self.pubkey, context_tag, label, device_seed);

        const hex_chars = "0123456789abcdef";
        var dp_hex: [bkds.PUBKEY_LEN * 2]u8 = undefined;
        for (dev.child_pub, 0..) |b, i| {
            dp_hex[i * 2] = hex_chars[b >> 4];
            dp_hex[i * 2 + 1] = hex_chars[b & 0x0f];
        }
        var proof_hex: [bkds.PUBKEY_LEN * 2]u8 = undefined;
        for (dev.device_pub, 0..) |b, i| {
            proof_hex[i * 2] = hex_chars[b >> 4];
            proof_hex[i * 2 + 1] = hex_chars[b & 0x0f];
        }

        return std.fmt.allocPrint(
            allocator,
            "{{\"token\":\"{s}\",\"derivation_pubkey\":\"{s}\",\"derivation_proof\":\"{s}\"}}",
            .{ tok.base64url, &dp_hex, &proof_hex },
        );
    }
};

// ─────────────────────────────────────────────────────────────────────
// HTTP client helpers (shared with repl_http_reactor_conformance pattern)
// ─────────────────────────────────────────────────────────────────────

const HttpResponse = struct {
    status: u16,
    body: []u8,

    fn deinit(self: *HttpResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

fn rawRequest(
    allocator: std.mem.Allocator,
    port: u16,
    method: []const u8,
    path: []const u8,
    body: []const u8,
    extra_header: ?[]const u8,
) !HttpResponse {
    const addr = try std.net.Address.parseIp4("127.0.0.1", port);
    var stream = try std.net.tcpConnectToAddress(addr);
    defer stream.close();

    var req: [8192]u8 = undefined;
    var req_text: []const u8 = undefined;

    if (extra_header) |hdr| {
        req_text = try std.fmt.bufPrint(
            &req,
            "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\n{s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
            .{ method, path, hdr, body.len, body },
        );
    } else {
        req_text = try std.fmt.bufPrint(
            &req,
            "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
            .{ method, path, body.len, body },
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
// Test 1: POST with valid payload → 200 + registered JSON
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8a: POST /api/v1/device-pair valid payload → 200 registered" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator, "op-seed-8a-happy");
    defer fx.deinit();

    const body = try fx.buildValidBody(
        allocator,
        "iPhone-prod",
        0x10,
        0x42,
        "device-seed-8a-happy",
    );
    defer allocator.free(body);

    var resp = try rawRequest(allocator, fx.server_port, "POST", "/api/v1/device-pair", body, null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 200), resp.status);

    // Body must be valid JSON with "status":"registered" and "cert_id".
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.body, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);

    const status_v = parsed.value.object.get("status") orelse
        return std.testing.expect(false);
    try std.testing.expectEqualStrings("registered", status_v.string);

    try std.testing.expect(parsed.value.object.get("cert_id") != null);
    try std.testing.expect(parsed.value.object.get("brain_cert_id") != null);

    // Bearer token must be present (token_store is wired).
    const bearer_v = parsed.value.object.get("bearer") orelse
        return std.testing.expect(false);
    try std.testing.expectEqual(@as(usize, 64), bearer_v.string.len);
}

// ─────────────────────────────────────────────────────────────────────
// Test 2: POST with malformed JSON body → 400
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8a: POST /api/v1/device-pair malformed JSON → 400" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator, "op-seed-8a-badJson");
    defer fx.deinit();

    var resp = try rawRequest(allocator, fx.server_port, "POST", "/api/v1/device-pair",
        "not json at all", null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 400), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "error") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 3: GET /api/v1/device-pair → 405
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8a: GET /api/v1/device-pair → 405" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator, "op-seed-8a-method");
    defer fx.deinit();

    var resp = try rawRequest(allocator, fx.server_port, "GET", "/api/v1/device-pair", "", null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 405), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "method_not_allowed") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 4: POST when device_pair_acceptor is null → 503
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8a: POST /api/v1/device-pair with no acceptor → 503" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    var cfg = try site_config.parseJson(allocator, SITE_CFG_JSON);
    defer cfg.deinit();
    const port = try findFreePort();
    cfg.listen_port = port;

    var server = try site_server.SiteServer.init(allocator, &cfg, real);
    defer server.deinit();
    // NB: NOT calling attachDevicePairAcceptor — acceptor is null.

    var cancel = std.atomic.Value(bool).init(false);
    const t = try std.Thread.spawn(.{}, runServer, .{ &server, &cancel });
    defer {
        cancel.store(true, .release);
        wakeListener(port);
        t.join();
    }
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var resp = try rawRequest(
        allocator,
        port,
        "POST",
        "/api/v1/device-pair",
        "{\"token\":\"abc\",\"derivation_pubkey\":\"0000000000000000000000000000000000000000000000000000000000000000aa\",\"derivation_proof\":\"0000000000000000000000000000000000000000000000000000000000000000bb\"}",
        null,
    );
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 503), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "error") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 5: OPTIONS preflight → 204 with CORS headers
// The reactor's OPTIONS branch at the top of reactorDispatchHttp handles
// this path-independently; /api/v1/device-pair follows the same flow.
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8a: OPTIONS /api/v1/device-pair → 204" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator, "op-seed-8a-options");
    defer fx.deinit();

    // Send OPTIONS with an Origin header to trigger CORS preflight.
    var resp = try rawRequest(
        allocator,
        fx.server_port,
        "OPTIONS",
        "/api/v1/device-pair",
        "",
        "Origin: https://app.example.com",
    );
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 204), resp.status);
}

```
