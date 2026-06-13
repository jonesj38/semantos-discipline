---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/repl_http_reactor_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.195260+00:00
---

# runtime/semantos-brain/tests/repl_http_reactor_conformance.zig

```zig
// brain-wedge Commit 7 — POST /api/v1/repl reactor dispatch conformance.
//
// Reference: Bridget's diagnosis; brain-wedge B-pragmatic fix series.
//
// Before Commit 7:  POST /api/v1/repl → 503 in reactor mode.
//                   Phone's oddjobz.poll_attention_signals / helm.fetch_since
//                   time out waiting for a REPL response.
// After  Commit 7:  POST /api/v1/repl → 200 with {"result":"...","exit":"..."}
//                   mirroring the blocking repl_http.maybeHandle path.
//
// These tests drive the full reactor path:
//   client TCP → EventLoop (site_server.serve)
//              → reactorDispatchHttp
//              → reactorHandleRepl
//              → bearer_tokens.verifyHex
//              → repl_http.parseCmdField
//              → repl.handleLine (help / exit commands only — no disk I/O)
//              → JSON response on wire
//
// Bearer-token scenarios exercised:
//   • POST with valid bearer + valid body  → 200
//   • POST missing Authorization header   → 401
//   • POST with bad bearer (not 64 hex)   → 401
//   • POST with unknown valid-format hex  → 401
//   • GET /api/v1/repl                    → 405
//   • POST with malformed JSON body       → 400
//   • POST with no repl_session wired     → 503

const std = @import("std");
const build_options = @import("build_options");
const config_mod = @import("config");
const audit_log_mod = @import("audit_log");
const broker_mod = @import("broker");
const instance_manager_mod = @import("instance_manager");
const module_loader_mod = @import("module_loader");
const runner_mod = @import("runner");
const repl_mod = @import("repl");
const slot_store_mod = @import("slot_store");
const derivation_state_mod = @import("derivation_state");
const header_store_mod = @import("header_store");
const wasmtime_backend = @import("wasmtime_backend");
const dispatcher_mod = @import("dispatcher");
const bearer_tokens = @import("bearer_tokens");
const site_config = @import("site_config");
const site_server = @import("site_server");

// ─────────────────────────────────────────────────────────────────────
// Minimal config JSON — no routes; /api/v1/repl is a reserved prefix
// that site_server handles before route lookup.
// ─────────────────────────────────────────────────────────────────────

const TEST_REPL_CONFIG_JSON =
    \\{
    \\  "shell": { "data_dir": "/tmp/brain-repl-reactor-test", "modules_dir": "/tmp/brain-repl-reactor-test/wasm" },
    \\  "modules": {}
    \\}
;

const SITE_CFG_JSON =
    \\{
    \\  "site": {
    \\    "domain": "repl-reactor-test.local",
    \\    "content_root": "."
    \\  },
    \\  "routes": {}
    \\}
;

// ─────────────────────────────────────────────────────────────────────
// Repl session fixture (mirrors Fixture from repl_conformance.zig)
// ─────────────────────────────────────────────────────────────────────

const ReplFixture = struct {
    allocator: std.mem.Allocator,
    cfg: config_mod.Config,
    audit_path: []u8,
    audit: audit_log_mod.AuditLog,
    slot_local: slot_store_mod.LocalSlotStore,
    state_local: derivation_state_mod.LocalStateStore,
    header_local: header_store_mod.LocalHeaderStore,
    broker: broker_mod.Broker,
    manager: instance_manager_mod.InstanceManager,
    runner: runner_mod.Runner,
    instances: std.ArrayList(repl_mod.NamedInstance),
    header_store_handle: header_store_mod.HeaderStore,

    fn init(allocator: std.mem.Allocator) !ReplFixture {
        var cfg = try config_mod.parseJson(allocator, TEST_REPL_CONFIG_JSON);
        errdefer cfg.deinit();

        const ap = try tempPath("repl-reactor-audit.log", allocator);
        var audit = audit_log_mod.AuditLog.init();
        try audit.open(ap);

        return .{
            .allocator = allocator,
            .cfg = cfg,
            .audit_path = ap,
            .audit = audit,
            .slot_local = slot_store_mod.LocalSlotStore.init(allocator),
            .state_local = derivation_state_mod.LocalStateStore.init(allocator),
            .header_local = header_store_mod.LocalHeaderStore.init(allocator),
            .broker = undefined,
            .manager = instance_manager_mod.InstanceManager.init(allocator),
            .runner = undefined,
            .instances = .empty,
            .header_store_handle = undefined,
        };
    }

    fn bind(self: *ReplFixture) void {
        self.broker = broker_mod.Broker.init(
            self.allocator,
            self.slot_local.store(),
            self.state_local.store(),
            self.header_local.store(),
            &self.audit,
        );
        self.runner = runner_mod.Runner.init(self.allocator, &self.broker);
        self.header_store_handle = self.header_local.store();
    }

    fn session(self: *ReplFixture) repl_mod.Session {
        return .{
            .allocator = self.allocator,
            .cfg = &self.cfg,
            .audit_path = self.audit_path,
            .audit = &self.audit,
            .broker = &self.broker,
            .manager = &self.manager,
            .runner = &self.runner,
            .instances = self.instances.items,
            .header_store = &self.header_store_handle,
        };
    }

    fn deinit(self: *ReplFixture) void {
        for (self.instances.items) |*ni| {
            var inst = ni.instance;
            inst.deinit();
        }
        self.instances.deinit(self.allocator);
        self.runner.deinit();
        self.audit.close();
        std.fs.cwd().deleteFile(self.audit_path) catch {};
        self.allocator.free(self.audit_path);
        self.slot_local.deinit();
        self.state_local.deinit();
        self.header_local.deinit();
        self.manager.deinit();
        self.cfg.deinit();
    }
};

// ─────────────────────────────────────────────────────────────────────
// Server fixture
// ─────────────────────────────────────────────────────────────────────

const ServerFixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    site_cfg: site_config.SiteConfig,
    server: site_server.SiteServer,
    token_store: bearer_tokens.TokenStore,
    repl_fx: ReplFixture,
    repl_session: repl_mod.Session,
    serve_thread: std.Thread,
    cancel: std.atomic.Value(bool),
    server_port: u16,

    /// Initialise the full reactor server fixture.
    /// After init, server.serve() is running in a background thread.
    fn init(allocator: std.mem.Allocator) !*ServerFixture {
        const self = try allocator.create(ServerFixture);
        errdefer allocator.destroy(self);

        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(data_dir);

        self.* = .{
            .allocator = allocator,
            .tmp_dir = tmp,
            .data_dir = data_dir,
            .site_cfg = undefined,
            .server = undefined,
            .token_store = undefined,
            .repl_fx = undefined,
            .repl_session = undefined,
            .serve_thread = undefined,
            .cancel = std.atomic.Value(bool).init(false),
            .server_port = 0,
        };

        // Parse site config and bind a free port.
        self.site_cfg = try site_config.parseJson(allocator, SITE_CFG_JSON);
        errdefer self.site_cfg.deinit();
        const port = try findFreePort();
        self.site_cfg.listen_port = port;
        self.server_port = port;

        // Build bearer-token store in the tmp dir.
        self.token_store = try bearer_tokens.TokenStore.init(allocator, data_dir, std.time.timestamp);
        errdefer self.token_store.deinit();

        // Build the repl session.
        self.repl_fx = try ReplFixture.init(allocator);
        errdefer self.repl_fx.deinit();
        self.repl_fx.bind();
        self.repl_session = self.repl_fx.session();

        // Build the site server.
        self.server = try site_server.SiteServer.init(allocator, &self.site_cfg, data_dir);
        errdefer self.server.deinit();

        // Wire up the REPL backend (bearer tokens + session).
        self.server.attachReplBackend(&self.token_store, &self.repl_session);

        // Spawn serve() on a background thread; the reactor runs there.
        self.serve_thread = try std.Thread.spawn(.{}, runServer, .{ &self.server, &self.cancel });

        // Brief grace to let the reactor's listen socket bind.
        std.Thread.sleep(50 * std.time.ns_per_ms);

        return self;
    }

    fn deinit(self: *ServerFixture) void {
        self.cancel.store(true, .release);
        wakeListener(self.server_port);
        self.serve_thread.join();

        self.server.deinit();
        self.token_store.deinit();
        self.repl_fx.deinit();
        self.site_cfg.deinit();
        self.tmp_dir.cleanup();
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }

    /// Issue a request to POST /api/v1/repl with the supplied body and
    /// optional Authorization header.  Caller frees the response body.
    fn postRepl(
        self: *ServerFixture,
        body_json: []const u8,
        auth_header: ?[]const u8,
    ) !HttpResponse {
        return rawRequest(self.allocator, self.server_port, "POST", "/api/v1/repl", body_json, auth_header);
    }

    /// Issue a request with the given method (e.g. GET) to /api/v1/repl.
    fn methodRepl(
        self: *ServerFixture,
        method: []const u8,
        body_json: []const u8,
        auth_header: ?[]const u8,
    ) !HttpResponse {
        return rawRequest(self.allocator, self.server_port, method, "/api/v1/repl", body_json, auth_header);
    }
};

// ─────────────────────────────────────────────────────────────────────
// HTTP client helpers
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
    auth_header: ?[]const u8,
) !HttpResponse {
    const addr = try std.net.Address.parseIp4("127.0.0.1", port);
    var stream = try std.net.tcpConnectToAddress(addr);
    defer stream.close();

    var req: [8192]u8 = undefined;
    var req_text: []const u8 = undefined;

    if (auth_header) |auth| {
        req_text = try std.fmt.bufPrint(
            &req,
            "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
            .{ method, path, auth, body.len, body },
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

fn tempPath(name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return std.fs.path.join(allocator, &.{ real, name });
}

// ─────────────────────────────────────────────────────────────────────
// Helper: issue a token and format the Authorization header.
// ─────────────────────────────────────────────────────────────────────

fn issueToken(store: *bearer_tokens.TokenStore, allocator: std.mem.Allocator) ![]u8 {
    const issued = try store.issue("test-token", 3600);
    var hex_buf: [64]u8 = undefined;
    bearer_tokens.hexEncode(&issued.token, &hex_buf);
    return std.fmt.allocPrint(allocator, "Bearer {s}", .{&hex_buf});
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

// Commit 7 core: POST /api/v1/repl with valid bearer + JSON body dispatches
// into repl.handleLine and returns 200 with {"result":"...","exit":"..."}.
test "brain-wedge Commit 7: POST /api/v1/repl with valid bearer + valid body returns 200" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const auth = try issueToken(&fx.token_store, allocator);
    defer allocator.free(auth);

    var resp = try fx.postRepl(
        \\{"cmd":"help"}
    , auth);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 200), resp.status);

    // Body must be valid JSON with "result" and "exit" fields.
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.body, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expect(parsed.value.object.get("result") != null);
    try std.testing.expect(parsed.value.object.get("exit") != null);
    // "help" is a non-exit command — exit must be "continue".
    try std.testing.expectEqualStrings("continue", parsed.value.object.get("exit").?.string);
}

// Commit 7: POST /api/v1/repl with valid bearer + "exit" command returns
// 200 with {"exit":"quit"} — the reactor surfaces quit vs continue.
test "brain-wedge Commit 7: POST /api/v1/repl with 'exit' cmd returns exit=quit" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const auth = try issueToken(&fx.token_store, allocator);
    defer allocator.free(auth);

    var resp = try fx.postRepl(
        \\{"cmd":"exit"}
    , auth);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.body, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expectEqualStrings("quit", parsed.value.object.get("exit").?.string);
}

// Commit 7: missing Authorization header → 401 with error message.
test "brain-wedge Commit 7: POST /api/v1/repl missing bearer → 401" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    var resp = try fx.postRepl(
        \\{"cmd":"help"}
    , null); // no Authorization header
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 401), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "missing bearer token") != null);
}

// Commit 7: malformed Authorization header (not Bearer <hex64>) → 401.
test "brain-wedge Commit 7: POST /api/v1/repl malformed bearer → 401" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    var resp = try fx.postRepl(
        \\{"cmd":"help"}
    , "Bearer notvalid");
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 401), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "error") != null);
}

// Commit 7: well-formed hex64 bearer token that is not in the store → 401.
test "brain-wedge Commit 7: POST /api/v1/repl unknown bearer → 401" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    // Valid 64-char hex that was never issued.
    var resp = try fx.postRepl(
        \\{"cmd":"help"}
    , "Bearer 0000000000000000000000000000000000000000000000000000000000000000");
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 401), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "error") != null);
}

// Commit 7: GET /api/v1/repl → 405 (POST-only endpoint).
test "brain-wedge Commit 7: GET /api/v1/repl → 405" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const auth = try issueToken(&fx.token_store, allocator);
    defer allocator.free(auth);

    var resp = try fx.methodRepl("GET", "", auth);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 405), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "POST required") != null);
}

// Commit 7: POST with malformed JSON body (not {"cmd":"..."}) → 400.
test "brain-wedge Commit 7: POST /api/v1/repl malformed JSON body → 400" {
    const allocator = std.testing.allocator;

    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const auth = try issueToken(&fx.token_store, allocator);
    defer allocator.free(auth);

    var resp = try fx.postRepl("not json at all", auth);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 400), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "error") != null);
}

// Commit 7: POST when repl_session is not wired → 503.
// Exercises the backend-gate branch in reactorHandleRepl.
test "brain-wedge Commit 7: POST /api/v1/repl when repl_backend not attached → 503" {
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
    // NB: NOT calling attachReplBackend — backend is nil.

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
        "/api/v1/repl",
        \\{"cmd":"help"}
    ,
        "Bearer 0000000000000000000000000000000000000000000000000000000000000000",
    );
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 503), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "error") != null);
}

```
