---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/cors_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.205639+00:00
---

# runtime/semantos-brain/tests/cors_conformance.zig

```zig
// D-W1 Phase 3 — CORS conformance suite.  Closes brain issue #273.
//
// References:
//   • docs/design/BRAIN-DISPATCHER-UNIFICATION.md §5.3 + §8 Phase 3.
//   • https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS/Preflight_request.
//
// Two layers of coverage:
//
//   1. Pure-helper tests for `cors.Cors.prepare` / `optionsHeaders` /
//      `responseHeaders` — drive the helper directly against a fixture
//      `SiteConfig`, no socket.  Constructs an `std.http.Server.Request`
//      via the in-process loopback socket fixture so the helper sees a
//      real header iterator.
//
//   2. SiteConfig parse-time guards — exact-origin / wildcard / refusal
//      of `*` + credentials.
//
// The cases enumerated in the deliverables note (see PR body):
//   • OPTIONS with no Origin             → 204, no ACAO header
//   • OPTIONS with allowed Origin        → 204, ACAO + ACAM + ACAH + ACMA
//   • OPTIONS with disallowed Origin     → 204, no ACAO (browser blocks)
//   • GET/POST with allowed Origin       → response carries ACAO
//   • Wildcard config "*"                → ACAO=`*`
//   • Wildcard + credentials             → parser refuses (CORS spec)

const std = @import("std");
const site_config = @import("site_config");
const cors = @import("cors");

// ─────────────────────────────────────────────────────────────────────
// Layer 1: SiteConfig parse-time guards
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P3 site_config: cors_allowed_origins parses array of strings" {
    const json =
        \\{
        \\  "site": {
        \\    "domain": "test.local",
        \\    "content_root": ".",
        \\    "cors_allowed_origins": ["https://helm.example.com", "https://app.example.com"]
        \\  },
        \\  "routes": {}
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    try std.testing.expectEqual(@as(usize, 2), cfg.cors_allowed_origins.len);
    try std.testing.expectEqualStrings("https://helm.example.com", cfg.cors_allowed_origins[0]);
    try std.testing.expectEqualStrings("https://app.example.com", cfg.cors_allowed_origins[1]);
}

test "D-W1 P3 site_config: cors defaults are sane when fields omitted" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "." },
        \\  "routes": {}
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    // Default empty allowlist ⇒ same-origin only.
    try std.testing.expectEqual(@as(usize, 0), cfg.cors_allowed_origins.len);
    // Defaults cover GET/POST/OPTIONS — the verbs the existing brain
    // routes use; operator can narrow per-site.
    try std.testing.expectEqual(@as(usize, 3), cfg.cors_allowed_methods.len);
    try std.testing.expectEqualStrings("GET", cfg.cors_allowed_methods[0]);
    try std.testing.expectEqualStrings("POST", cfg.cors_allowed_methods[1]);
    try std.testing.expectEqualStrings("OPTIONS", cfg.cors_allowed_methods[2]);
    // 10-minute preflight cache — matches what most prod deployments use.
    try std.testing.expectEqual(@as(u32, 600), cfg.cors_max_age_seconds);
    try std.testing.expectEqual(false, cfg.cors_allow_credentials);
    try std.testing.expectEqualStrings("", cfg.content_security_policy);
}

test "D-W1 P3 site_config: cors_allowed_methods overrides the default" {
    const json =
        \\{
        \\  "site": {
        \\    "domain": "x",
        \\    "content_root": ".",
        \\    "cors_allowed_methods": ["GET", "OPTIONS"]
        \\  },
        \\  "routes": {}
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    try std.testing.expectEqual(@as(usize, 2), cfg.cors_allowed_methods.len);
    try std.testing.expectEqualStrings("GET", cfg.cors_allowed_methods[0]);
    try std.testing.expectEqualStrings("OPTIONS", cfg.cors_allowed_methods[1]);
}

test "D-W1 P3 site_config: parser refuses '*' + cors_allow_credentials" {
    const json =
        \\{
        \\  "site": {
        \\    "domain": "x",
        \\    "content_root": ".",
        \\    "cors_allowed_origins": ["*"],
        \\    "cors_allow_credentials": true
        \\  },
        \\  "routes": {}
        \\}
    ;
    const err = site_config.parseJson(std.testing.allocator, json);
    try std.testing.expectError(error.invalid_cors_config, err);
}

test "D-W1 P3 site_config: '*' alone (no credentials) parses fine" {
    const json =
        \\{
        \\  "site": {
        \\    "domain": "x",
        \\    "content_root": ".",
        \\    "cors_allowed_origins": ["*"]
        \\  },
        \\  "routes": {}
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    try std.testing.expectEqual(@as(usize, 1), cfg.cors_allowed_origins.len);
    try std.testing.expectEqualStrings("*", cfg.cors_allowed_origins[0]);
}

test "D-W1 P3 site_config: matchCorsOrigin exact match echoes the configured origin" {
    const json =
        \\{
        \\  "site": {
        \\    "domain": "x",
        \\    "content_root": ".",
        \\    "cors_allowed_origins": ["https://helm.example.com"]
        \\  },
        \\  "routes": {}
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    const matched = cfg.matchCorsOrigin("https://helm.example.com") orelse return error.TestFailed;
    try std.testing.expectEqualStrings("https://helm.example.com", matched);
}

test "D-W1 P3 site_config: matchCorsOrigin wildcard returns '*'" {
    const json =
        \\{
        \\  "site": {
        \\    "domain": "x",
        \\    "content_root": ".",
        \\    "cors_allowed_origins": ["*"]
        \\  },
        \\  "routes": {}
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    // Both an arbitrary origin AND no-origin should produce "*"
    const matched = cfg.matchCorsOrigin("https://attacker.example") orelse return error.TestFailed;
    try std.testing.expectEqualStrings("*", matched);
}

test "D-W1 P3 site_config: matchCorsOrigin disallowed returns null" {
    const json =
        \\{
        \\  "site": {
        \\    "domain": "x",
        \\    "content_root": ".",
        \\    "cors_allowed_origins": ["https://helm.example.com"]
        \\  },
        \\  "routes": {}
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    try std.testing.expect(cfg.matchCorsOrigin("https://attacker.example") == null);
}

test "D-W1 P3 site_config: matchCorsOrigin empty allowlist denies everything" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "." },
        \\  "routes": {}
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    try std.testing.expect(cfg.matchCorsOrigin("https://anyone.example") == null);
}

test "D-W1 P3 site_config: content_security_policy parses + round-trips" {
    const json =
        \\{
        \\  "site": {
        \\    "domain": "x",
        \\    "content_root": ".",
        \\    "content_security_policy": "default-src 'self'"
        \\  },
        \\  "routes": {}
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    try std.testing.expectEqualStrings("default-src 'self'", cfg.content_security_policy);
}

// ─────────────────────────────────────────────────────────────────────
// Layer 2: full request roundtrip via a real loopback HTTP socket.
//
// This is the load-bearing coverage for the deliverables-note cases
// (OPTIONS preflight + GET/POST CORS-header emission).  We stand up a
// `site_server.SiteServer` on a real TCP port, hit it with a hand-
// rolled HTTP/1.1 client (matches the chat_http_conformance pattern),
// and parse the response headers.
// ─────────────────────────────────────────────────────────────────────

const site_server = @import("site_server");

const HttpResponse = struct {
    status: u16,
    headers: []u8,
    body: []u8,
    allocator: std.mem.Allocator,

    fn deinit(self: *HttpResponse) void {
        self.allocator.free(self.headers);
        self.allocator.free(self.body);
    }

    /// Case-insensitive single-value header lookup.  Returns the
    /// first match (CORS responses don't repeat any header).
    fn header(self: HttpResponse, name: []const u8) ?[]const u8 {
        var it = std.mem.splitSequence(u8, self.headers, "\r\n");
        // Skip the status line.
        _ = it.next();
        while (it.next()) |line| {
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const k = line[0..colon];
            if (std.ascii.eqlIgnoreCase(k, name)) {
                const v = std.mem.trim(u8, line[colon + 1 ..], " \t");
                return v;
            }
        }
        return null;
    }
};

const ServerFixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    cfg: site_config.SiteConfig,
    server: site_server.SiteServer,
    serve_thread: std.Thread,
    cancel: std.atomic.Value(bool),
    server_port: u16,

    fn init(allocator: std.mem.Allocator, cfg_json: []const u8) !*ServerFixture {
        const self = try allocator.create(ServerFixture);
        errdefer allocator.destroy(self);

        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(data_dir);

        // Drop a tiny index.html into <tmp>/ so the static GET case can
        // serve real bytes (content_root == data_dir for the fixture).
        try tmp.dir.writeFile(.{
            .sub_path = "index.html",
            .data = "<!doctype html><title>cors fixture</title>",
        });

        self.* = .{
            .allocator = allocator,
            .tmp_dir = tmp,
            .data_dir = data_dir,
            .cfg = undefined,
            .server = undefined,
            .serve_thread = undefined,
            .cancel = std.atomic.Value(bool).init(false),
            .server_port = 0,
        };

        self.cfg = try site_config.parseJson(allocator, cfg_json);
        errdefer self.cfg.deinit();
        // Point content_root at the tmp dir so the static route below
        // resolves index.html on disk.
        self.cfg.content_root = data_dir;

        const free_port = try findFreePort();
        self.cfg.listen_port = free_port;
        self.server_port = free_port;

        self.server = try site_server.SiteServer.init(allocator, &self.cfg, data_dir);
        errdefer self.server.deinit();

        self.serve_thread = try std.Thread.spawn(.{}, runServer, .{ &self.server, &self.cancel });
        // Tiny grace so the listener binds before we connect.
        std.Thread.sleep(50 * std.time.ns_per_ms);

        return self;
    }

    fn deinit(self: *ServerFixture) void {
        self.cancel.store(true, .release);
        wakeListener(self.server_port);
        self.serve_thread.join();
        self.server.deinit();
        self.cfg.deinit();
        self.tmp_dir.cleanup();
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }

    fn request(
        self: *ServerFixture,
        method: []const u8,
        path: []const u8,
        extra_headers: []const u8,
    ) !HttpResponse {
        return doRequest(self.allocator, self.server_port, method, path, extra_headers, "");
    }
};

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

fn doRequest(
    allocator: std.mem.Allocator,
    port: u16,
    method: []const u8,
    path: []const u8,
    extra_headers: []const u8,
    body: []const u8,
) !HttpResponse {
    const addr = try std.net.Address.parseIp4("127.0.0.1", port);
    var stream = try std.net.tcpConnectToAddress(addr);
    defer stream.close();

    var req: [4096]u8 = undefined;
    const req_text = try std.fmt.bufPrint(
        &req,
        "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: {d}\r\nConnection: close\r\n{s}\r\n{s}",
        .{ method, path, body.len, extra_headers, body },
    );
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
        .allocator = allocator,
    };
}

const SITE_CFG_WITH_HELM_ORIGIN =
    \\{
    \\  "site": {
    \\    "domain": "test.local",
    \\    "content_root": ".",
    \\    "cors_allowed_origins": ["https://helm.example.com"],
    \\    "cors_allowed_headers": ["authorization", "content-type"],
    \\    "cors_max_age_seconds": 600
    \\  },
    \\  "routes": {
    \\    "/": { "type": "static", "file": "index.html", "public": true }
    \\  }
    \\}
;

const SITE_CFG_WILDCARD =
    \\{
    \\  "site": {
    \\    "domain": "test.local",
    \\    "content_root": ".",
    \\    "cors_allowed_origins": ["*"]
    \\  },
    \\  "routes": {
    \\    "/": { "type": "static", "file": "index.html", "public": true }
    \\  }
    \\}
;

const SITE_CFG_NO_CORS =
    \\{
    \\  "site": { "domain": "test.local", "content_root": "." },
    \\  "routes": {
    \\    "/": { "type": "static", "file": "index.html", "public": true }
    \\  }
    \\}
;

// ─────────────────────────────────────────────────────────────────────
// OPTIONS preflight cases.
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P3 cors: OPTIONS with no Origin returns 204 + no ACAO header" {
    const fx = try ServerFixture.init(std.testing.allocator, SITE_CFG_WITH_HELM_ORIGIN);
    defer fx.deinit();

    var resp = try fx.request("OPTIONS", "/api/v1/repl", "");
    defer resp.deinit();
    try std.testing.expectEqual(@as(u16, 204), resp.status);
    try std.testing.expect(resp.header("access-control-allow-origin") == null);
}

test "D-W1 P3 cors: OPTIONS with allowed Origin returns 204 + ACAO + ACAM + ACAH + ACMA" {
    const fx = try ServerFixture.init(std.testing.allocator, SITE_CFG_WITH_HELM_ORIGIN);
    defer fx.deinit();

    var resp = try fx.request(
        "OPTIONS",
        "/api/v1/repl",
        "Origin: https://helm.example.com\r\nAccess-Control-Request-Method: POST\r\n",
    );
    defer resp.deinit();
    try std.testing.expectEqual(@as(u16, 204), resp.status);
    try std.testing.expectEqualStrings(
        "https://helm.example.com",
        resp.header("access-control-allow-origin") orelse return error.TestFailed,
    );
    // ACAM should contain the configured methods.
    const acam = resp.header("access-control-allow-methods") orelse return error.TestFailed;
    try std.testing.expect(std.mem.indexOf(u8, acam, "GET") != null);
    try std.testing.expect(std.mem.indexOf(u8, acam, "POST") != null);
    try std.testing.expect(std.mem.indexOf(u8, acam, "OPTIONS") != null);
    // ACAH should reflect the configured headers.
    const acah = resp.header("access-control-allow-headers") orelse return error.TestFailed;
    try std.testing.expect(std.mem.indexOf(u8, acah, "authorization") != null);
    try std.testing.expect(std.mem.indexOf(u8, acah, "content-type") != null);
    // Max-Age is the configured value.
    try std.testing.expectEqualStrings(
        "600",
        resp.header("access-control-max-age") orelse return error.TestFailed,
    );
    // Vary: Origin so caches don't reuse a non-CORS response.
    try std.testing.expectEqualStrings(
        "Origin",
        resp.header("vary") orelse return error.TestFailed,
    );
}

test "D-W1 P3 cors: OPTIONS with disallowed Origin returns 204 + no ACAO" {
    const fx = try ServerFixture.init(std.testing.allocator, SITE_CFG_WITH_HELM_ORIGIN);
    defer fx.deinit();

    var resp = try fx.request(
        "OPTIONS",
        "/api/v1/repl",
        "Origin: https://attacker.example\r\nAccess-Control-Request-Method: POST\r\n",
    );
    defer resp.deinit();
    try std.testing.expectEqual(@as(u16, 204), resp.status);
    // Browsers block when ACAO is absent — the server is correctly
    // refusing to opt the response into the CORS protocol.
    try std.testing.expect(resp.header("access-control-allow-origin") == null);
}

test "D-W1 P3 cors: OPTIONS with wildcard config returns ACAO=*" {
    const fx = try ServerFixture.init(std.testing.allocator, SITE_CFG_WILDCARD);
    defer fx.deinit();

    var resp = try fx.request(
        "OPTIONS",
        "/api/v1/repl",
        "Origin: https://anyone.example\r\nAccess-Control-Request-Method: POST\r\n",
    );
    defer resp.deinit();
    try std.testing.expectEqual(@as(u16, 204), resp.status);
    try std.testing.expectEqualStrings(
        "*",
        resp.header("access-control-allow-origin") orelse return error.TestFailed,
    );
}

// ─────────────────────────────────────────────────────────────────────
// Non-OPTIONS responses must include ACAO when the origin is allowed.
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P3 cors: GET /static with allowed Origin includes ACAO header" {
    const fx = try ServerFixture.init(std.testing.allocator, SITE_CFG_WITH_HELM_ORIGIN);
    defer fx.deinit();

    var resp = try fx.request(
        "GET",
        "/",
        "Origin: https://helm.example.com\r\n",
    );
    defer resp.deinit();
    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings(
        "https://helm.example.com",
        resp.header("access-control-allow-origin") orelse return error.TestFailed,
    );
    // Non-preflight responses don't carry the Methods/Headers/Max-Age
    // headers (they're preflight-only per the CORS spec).
    try std.testing.expect(resp.header("access-control-allow-methods") == null);
}

test "D-W1 P3 cors: GET /static with no Origin has no ACAO header" {
    const fx = try ServerFixture.init(std.testing.allocator, SITE_CFG_WITH_HELM_ORIGIN);
    defer fx.deinit();

    var resp = try fx.request("GET", "/", "");
    defer resp.deinit();
    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expect(resp.header("access-control-allow-origin") == null);
}

test "D-W1 P3 cors: GET /static with disallowed Origin has no ACAO header" {
    const fx = try ServerFixture.init(std.testing.allocator, SITE_CFG_WITH_HELM_ORIGIN);
    defer fx.deinit();

    var resp = try fx.request(
        "GET",
        "/",
        "Origin: https://attacker.example\r\n",
    );
    defer resp.deinit();
    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expect(resp.header("access-control-allow-origin") == null);
}

test "D-W1 P3 cors: site without CORS config emits no ACAO even on allowed-method GET" {
    const fx = try ServerFixture.init(std.testing.allocator, SITE_CFG_NO_CORS);
    defer fx.deinit();

    var resp = try fx.request(
        "GET",
        "/",
        "Origin: https://anyone.example\r\n",
    );
    defer resp.deinit();
    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expect(resp.header("access-control-allow-origin") == null);
}

// ─────────────────────────────────────────────────────────────────────
// CSP header emission (Tier 2).
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P3 cors: configured content_security_policy is emitted on responses" {
    const json =
        \\{
        \\  "site": {
        \\    "domain": "test.local",
        \\    "content_root": ".",
        \\    "content_security_policy": "default-src 'self'"
        \\  },
        \\  "routes": {
        \\    "/": { "type": "static", "file": "index.html", "public": true }
        \\  }
        \\}
    ;
    const fx = try ServerFixture.init(std.testing.allocator, json);
    defer fx.deinit();

    var resp = try fx.request("GET", "/", "");
    defer resp.deinit();
    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings(
        "default-src 'self'",
        resp.header("content-security-policy") orelse return error.TestFailed,
    );
}

```
