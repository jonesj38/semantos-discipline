---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/dynamic_reactor_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.206771+00:00
---

# runtime/semantos-brain/tests/dynamic_reactor_conformance.zig

```zig
// brain-wedge Commit 8c — dynamic WASM handler reactor dispatch conformance.
//
// Reference: brain-wedge B-pragmatic fix series; PRs #411/#412/#414/#419 wired
// WSS + REPL + device-pair + auth-gated routes through the reactor.  Commit 8c
// closes the LAST TODO-REACTOR-COMPLETE stub: dynamic WASM handler routes.
//
// Before Commit 8c:  dynamic routes → 501 in reactor mode.
//                    Any route with type="dynamic" returned a hard 501
//                    instead of dispatching to the WASM handler.
// After  Commit 8c:  runner null     → 503 "rebuild with wasmtime"
//                    slot missing   → 503 "handler not loaded"
//                    dispatch error → 500 with @errorName in JSON body
//                    success        → handler status + body (wasmtime only)
//                    auth gates     → 401/402 fire BEFORE reaching dynamic
//                                    dispatch (Commit 8b's gate is upstream)
//
// These tests drive the full reactor path:
//   client TCP → EventLoop (site_server.serve)
//              → reactorDispatchHttp
//              → [Commit 8b auth gate if auth ≠ public]
//              → reactorHandleDynamic   ← NEW in Commit 8c
//              → runner_mod.callHandlerHandle
//
// Scenarios covered:
//   1. Dynamic route, runner null          → 503 "rebuild with wasmtime"
//   2. Dynamic route, runner set, slot absent → 503 "handler not loaded"
//   3. Dynamic route, slot injected, dispatch error → 500 + error name JSON
//   4. Dynamic route, dispatch succeeds → 200 (wasmtime build only — skipped)
//   5. Dynamic route + identity_required, no session → 401 (8b gate fires)
//   6. Dynamic route + payment_required,  no session → 402 (8b gate fires)
//   7. Dynamic + identity_required, valid session → 503 (gate cleared, reaches dynamic dispatch)
//   8. OPTIONS on dynamic route → 204 (CORS preflight, before route lookup)
//
// Tests 5-7 are particularly important: they verify that Commit 8b's auth
// gate composition with Commit 8c's dynamic dispatch is correct.

const std = @import("std");
const build_options = @import("build_options");
const runner_mod = @import("runner");
const broker_mod = @import("broker");
const audit_log_mod = @import("audit_log");
const slot_store_mod = @import("slot_store");
const derivation_state_mod = @import("derivation_state");
const header_store_mod = @import("header_store");
const site_config = @import("site_config");
const site_server = @import("site_server");
const auth_handler = @import("auth_handler");
const module_loader = @import("module_loader");

// ─────────────────────────────────────────────────────────────────────
// Site config JSON templates
// ─────────────────────────────────────────────────────────────────────

/// Site with:
///   /api/handler  — dynamic, public auth
///   /api/private  — dynamic, identity_required
///   /api/paid     — dynamic, payment_required
/// (all reference dummy handler + zero sha256 to pass JSON parse)
const SITE_CFG_TEMPLATE =
    \\{{
    \\  "site": {{
    \\    "domain": "dynamic-reactor-test.local",
    \\    "content_root": "{s}",
    \\    "signing_secret": "0000000000000000000000000000000000000000000000000000000000000001"
    \\  }},
    \\  "routes": {{
    \\    "/api/handler": {{
    \\      "type": "dynamic",
    \\      "handler": "handler.wasm",
    \\      "handler_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    \\      "auth": "public"
    \\    }},
    \\    "/api/private": {{
    \\      "type": "dynamic",
    \\      "handler": "handler.wasm",
    \\      "handler_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    \\      "auth": "identity_required"
    \\    }},
    \\    "/api/paid": {{
    \\      "type": "dynamic",
    \\      "handler": "handler.wasm",
    \\      "handler_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    \\      "auth": "payment_required",
    \\      "price_sats": 1000,
    \\      "payment_recipient": "{s}"
    \\    }}
    \\  }}
    \\}}
;

/// Compressed SEC1 test pubkey for payment_recipient in the config.
const TEST_RECIPIENT_HEX = "020000000000000000000000000000000000000000000000000000000000000001";

// ─────────────────────────────────────────────────────────────────────
// RunnerFixture — minimal broker + runner for tests that need
// server.runner != null without loading real WASM modules.
//
// Mirrors the pattern from repl_conformance.zig: build a Broker from
// in-memory store implementations, then pass it to Runner.init.
// In stub mode Runner.init stores the broker but never calls it.
// ─────────────────────────────────────────────────────────────────────

const RunnerFixture = struct {
    audit_path: []u8,
    audit: audit_log_mod.AuditLog,
    slot_local: slot_store_mod.LocalSlotStore,
    state_local: derivation_state_mod.LocalStateStore,
    header_local: header_store_mod.LocalHeaderStore,
    broker: broker_mod.Broker,
    runner: runner_mod.Runner,

    fn init(allocator: std.mem.Allocator) !RunnerFixture {
        const audit_path = try makeAuditPath(allocator);
        var audit = audit_log_mod.AuditLog.init();
        try audit.open(audit_path);
        errdefer {
            audit.close();
            std.fs.cwd().deleteFile(audit_path) catch {};
            allocator.free(audit_path);
        }

        const slot_local = slot_store_mod.LocalSlotStore.init(allocator);
        const state_local = derivation_state_mod.LocalStateStore.init(allocator);
        const header_local = header_store_mod.LocalHeaderStore.init(allocator);

        var self = RunnerFixture{
            .audit_path = audit_path,
            .audit = audit,
            .slot_local = slot_local,
            .state_local = state_local,
            .header_local = header_local,
            .broker = undefined,
            .runner = undefined,
        };
        self.broker = broker_mod.Broker.init(
            allocator,
            self.slot_local.store(),
            self.state_local.store(),
            self.header_local.store(),
            &self.audit,
        );
        self.runner = runner_mod.Runner.init(allocator, &self.broker);
        return self;
    }

    fn deinit(self: *RunnerFixture, allocator: std.mem.Allocator) void {
        self.runner.deinit();
        self.audit.close();
        std.fs.cwd().deleteFile(self.audit_path) catch {};
        allocator.free(self.audit_path);
        self.slot_local.deinit();
        self.state_local.deinit();
        self.header_local.deinit();
    }

    fn makeAuditPath(allocator: std.mem.Allocator) ![]u8 {
        const tmp = std.testing.tmpDir(.{});
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &buf);
        return std.fs.path.join(allocator, &.{ real, "dynamic-reactor-audit.log" });
    }
};

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

        // Create a sub-directory as content_root.
        try self.tmp.dir.makeDir("content");
        const content_real = try self.tmp.dir.realpath("content", &path_buf);
        self.content_dir = try allocator.dupe(u8, content_real);
        errdefer allocator.free(self.content_dir);

        // Build site config JSON.
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

    /// Inject a fake HandlerSlot directly into server.handler_instances so
    /// the slot lookup in reactorHandleDynamic finds a slot without needing a
    /// real WASM binary on disk.
    ///
    /// The injected slot holds a zero-initialised Instance (stub: _stub=0)
    /// which is valid — stub callHandlerHandle() ignores it.  The loaded
    /// module holds minimal heap slices that deinit() will free.
    fn injectHandlerSlot(self: *ServerFixture, route_path: []const u8) !void {
        // Locate the route by path so findHandlerSlot matches by pointer.
        var target_route: ?*const site_config.Route = null;
        for (self.site_cfg.routes) |*r| {
            if (std.mem.eql(u8, r.path, route_path)) {
                target_route = r;
                break;
            }
        }
        const route = target_route orelse return error.route_not_found;

        // Minimal LoadedModule — bytes/name/path owned by allocator; deinit
        // will free them.  sha256 is zeros (matches the config stub value).
        const dummy_bytes = try self.allocator.dupe(u8, &[_]u8{0});
        errdefer self.allocator.free(dummy_bytes);
        const dummy_name = try self.allocator.dupe(u8, "handler.wasm");
        errdefer self.allocator.free(dummy_name);
        const dummy_path = try self.allocator.dupe(u8, "/dev/null");
        errdefer self.allocator.free(dummy_path);

        const loaded = module_loader.LoadedModule{
            .name = dummy_name,
            .path = dummy_path,
            .bytes = dummy_bytes,
            .sha256 = [_]u8{0} ** 32,
            .allocator = self.allocator,
        };

        // Stub Instance has a single u8 field (_stub); zero-init is fine.
        const instance = runner_mod.Instance{ ._stub = 0 };

        try self.server.handler_instances.append(self.allocator, .{
            .route = route,
            .loaded = loaded,
            .instance = instance,
        });
    }

    /// Mint a valid __semantos_session cookie accepted by the reactor's
    /// cookie-checking code (auth signed with the server's signing_secret).
    fn mintSessionCookie(self: *ServerFixture, allocator: std.mem.Allocator) ![]u8 {
        const pubkey: [33]u8 = [_]u8{0x02} ++ ([_]u8{0x01} ** 32);
        const session = try self.server.auth_store.mintSession(pubkey, 3600, "/api/private");
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
// HTTP client helpers (mirrors auth_gated_reactor_conformance pattern)
// ─────────────────────────────────────────────────────────────────────

const HttpResponse = struct {
    status: u16,
    headers: []u8,
    body: []u8,

    fn deinit(self: *HttpResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.headers);
        allocator.free(self.body);
    }

    fn hasHeader(self: *const HttpResponse, name: []const u8) bool {
        var it = std.mem.splitSequence(u8, self.headers, "\r\n");
        while (it.next()) |line| {
            if (line.len == 0) continue;
            const sep = std.mem.indexOf(u8, line, ":") orelse continue;
            const hdr_name = std.mem.trim(u8, line[0..sep], " ");
            if (std.ascii.eqlIgnoreCase(hdr_name, name)) return true;
        }
        return false;
    }

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
    body_opt: ?[]const u8,
) !HttpResponse {
    const addr = try std.net.Address.parseIp4("127.0.0.1", port);
    var stream = try std.net.tcpConnectToAddress(addr);
    defer stream.close();

    var req_buf: std.ArrayList(u8) = .empty;
    defer req_buf.deinit(allocator);

    const body_len = if (body_opt) |b| b.len else 0;
    const w = req_buf.writer(allocator);

    if (extra_headers) |hdrs| {
        try w.print(
            "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\n{s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ method, path, hdrs, body_len },
        );
    } else {
        try w.print(
            "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ method, path, body_len },
        );
    }
    if (body_opt) |b| try req_buf.appendSlice(allocator, b);

    try stream.writeAll(req_buf.items);

    var resp_buf: std.ArrayList(u8) = .empty;
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
// Test 1: dynamic route, runner null → 503 "rebuild with wasmtime"
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8c: dynamic route, runner null → 503 rebuild-with-wasmtime" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    // No attachRunner — server.runner stays null.
    var resp = try rawRequest(allocator, fx.server_port, "POST", "/api/handler",
        "Content-Type: application/json", "{\"x\":1}");
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 503), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "wasmtime") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "rebuild") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 2: dynamic route, runner attached, handler slot absent → 503
//
// attachRunner sets server.runner and tries to loadHandlerSlot for all
// dynamic routes.  Since handler.wasm doesn't exist on disk, all slot
// loads fail → handler_instances is empty → findHandlerSlot returns null
// → 503 "handler not loaded".
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8c: dynamic route, runner set, slot absent → 503 handler-not-loaded" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    // Build a real runner (broker + stores in memory; no WASM capability needed).
    var rfx = try RunnerFixture.init(allocator);
    defer rfx.deinit(allocator);

    // attachRunner sets server.runner but loadHandlerSlot fails (no handler.wasm
    // on disk) → handler_instances stays empty.
    _ = fx.server.attachRunner(&rfx.runner) catch {};

    var resp = try rawRequest(allocator, fx.server_port, "GET", "/api/handler", null, null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 503), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "handler not loaded") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 3: dynamic route, slot injected, dispatch error → 500 + error name
//
// In stub mode callHandlerHandle always returns error.wasmtime_not_enabled.
// The reactor maps any HandlerError → 500 with {"error":"<errorName>"}.
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8c: dynamic route, slot injected, dispatch error → 500 with error name" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    var rfx = try RunnerFixture.init(allocator);
    defer rfx.deinit(allocator);

    // Set runner without loading real slots.
    _ = fx.server.attachRunner(&rfx.runner) catch {};

    // Inject a fake slot so findHandlerSlot succeeds.
    try fx.injectHandlerSlot("/api/handler");

    var resp = try rawRequest(allocator, fx.server_port, "POST", "/api/handler",
        "Content-Type: application/json", "{\"hello\":\"world\"}");
    defer resp.deinit(allocator);

    // Stub callHandlerHandle returns error.wasmtime_not_enabled → 500.
    try std.testing.expectEqual(@as(u16, 500), resp.status);
    // Error name must appear in JSON body.
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "error") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 4: dynamic route, dispatch succeeds → 200 + handler body
//
// Only meaningful with a real wasmtime build + a compiled handler.wasm.
// Skipped in stub mode (the stub always returns an error, never 200).
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8c: dynamic route, dispatch succeeds → 200 (wasmtime only)" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;

    // With real wasmtime a properly compiled handler.wasm is required.
    // This is a placeholder for real-wasmtime CI; stub CI skips it.
    // Full integration: compile WAT via wasmtime_wat2wasm → attachRunner
    // → loadHandlerSlot → POST → assert 200 + body from handler.
    return error.SkipZigTest;
}

// ─────────────────────────────────────────────────────────────────────
// Test 5: dynamic route + identity_required, no session → 401
//
// Commit 8b's auth gate fires BEFORE reactorHandleDynamic.  Even without
// any runner, an unauthenticated request to an identity_required dynamic
// route must get 401, not 501/503.
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8c: dynamic + identity_required, no session → 401" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    // No session cookie, no runner — auth gate must fire before dynamic dispatch.
    var resp = try rawRequest(allocator, fx.server_port, "GET", "/api/private", null, null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 401), resp.status);
    // Commit 8b challenge headers must be present.
    try std.testing.expect(resp.hasHeader("x-semantos-challenge"));
    try std.testing.expect(resp.hasHeader("x-semantos-nonce"));
}

// ─────────────────────────────────────────────────────────────────────
// Test 6: dynamic route + payment_required, no session → 402
//
// Same gate-composition check as Test 5 but for payment_required.
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8c: dynamic + payment_required, no session → 402" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    var resp = try rawRequest(allocator, fx.server_port, "GET", "/api/paid", null, null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 402), resp.status);
    try std.testing.expect(resp.hasHeader("x-semantos-challenge"));
    try std.testing.expect(resp.hasHeader("x-semantos-price-sats"));
    try std.testing.expect(resp.hasHeader("x-semantos-recipient"));
}

// ─────────────────────────────────────────────────────────────────────
// Test 7: dynamic + identity_required, valid session → auth gate cleared,
//         reaches dynamic dispatch (runner null → 503, not 401)
//
// A valid session clears the Commit 8b gate.  The request then hits
// reactorHandleDynamic which — with no runner — returns 503, not 401.
// This proves the two commits compose correctly: 8b gate + 8c dispatch.
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8c: dynamic + identity_required, valid session → auth cleared, dynamic dispatch fires (503 no runner)" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const cookie_hdr_line = try fx.mintSessionCookie(allocator);
    defer allocator.free(cookie_hdr_line);

    const cookie_header = try std.fmt.allocPrint(allocator, "Cookie: {s}", .{cookie_hdr_line});
    defer allocator.free(cookie_header);

    // No runner — auth gate is cleared, dynamic dispatch fires and returns 503.
    // If 401 were returned the auth gate would not have been cleared correctly.
    var resp = try rawRequest(allocator, fx.server_port, "GET", "/api/private", cookie_header, null);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 503), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "wasmtime") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Test 8: OPTIONS on a dynamic route → 204 (reactor OPTIONS branch fires
//         before route lookup, so auth + dynamic dispatch are bypassed)
// ─────────────────────────────────────────────────────────────────────

test "brain-wedge Commit 8c: OPTIONS /api/handler → 204 (CORS preflight)" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    var resp = try rawRequest(
        allocator,
        fx.server_port,
        "OPTIONS",
        "/api/handler",
        "Origin: https://app.example.com",
        null,
    );
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 204), resp.status);
}

```
