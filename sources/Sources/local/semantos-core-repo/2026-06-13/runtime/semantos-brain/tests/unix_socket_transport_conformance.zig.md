---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/unix_socket_transport_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.173416+00:00
---

# runtime/semantos-brain/tests/unix_socket_transport_conformance.zig

```zig
// Phase D-W1 / Phase 1 — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md §5.2.
//
// End-to-end conformance for the Unix socket transport.  Spins up a
// server in a tmpdir, accepts connections in a worker thread, drives
// the bearer_tokens resource through the wire codec, asserts the
// post-state matches the in-process / embedded-mode path.
//
// Coverage:
//   • Server bind + client connect + dispatch round-trips
//   • uid mismatch produces a capability_denied response envelope
//     and the dispatcher itself is never invoked
//   • Embedded fallback path produces the same on-disk bearer-token
//     log line as the socket path (proves the seam from §10's
//     deterministic-across-deployment-shapes mitigation)
//   • Wire-level malformed envelope handled gracefully
//
// The "different uid" test injects a synthetic `expected_uid` value
// (current_uid + 1) into the server.  We can't actually drop privs in
// a unit test, so we rely on the server treating expected_uid as
// authoritative — whatever the kernel returns from getpeereid is
// compared against this value.

const std = @import("std");
const dispatcher_mod = @import("dispatcher");
const audit_log = @import("audit_log");
const wire = @import("wire");
const bearer_tokens = @import("bearer_tokens");
const handler_mod = @import("bearer_tokens_handler");
const transport = @import("unix_socket");

fn pinnedClock() i64 {
    return 1_700_000_000;
}

/// macOS `sockaddr_un.sun_path` is 104 bytes.  `std.testing.tmpDir`
/// lands under `<repo>/.zig-cache/tmp/<16-hex>/`, already ~95 bytes,
/// which leaves no room for `<dir>/brain.sock`.  Allocate a short
/// `/tmp/brn-<8hex>/` path; caller cleans up via `cleanupShortDir`.
fn shortDataDir(allocator: std.mem.Allocator) ![]u8 {
    var rand_u32: u32 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&rand_u32));
    var dir_name_buf: [32]u8 = undefined;
    const path = try std.fmt.bufPrint(&dir_name_buf, "/tmp/brn-{x:0>8}", .{rand_u32});
    try std.fs.makeDirAbsolute(path);
    return allocator.dupe(u8, path);
}

fn cleanupShortDir(allocator: std.mem.Allocator, path: []const u8) void {
    std.fs.deleteTreeAbsolute(path) catch {};
    allocator.free(path);
}

const TestEnv = struct {
    allocator: std.mem.Allocator,
    data_dir: []u8,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    store: bearer_tokens.TokenStore,
    handler: handler_mod.Handler,
    disp: dispatcher_mod.Dispatcher,
    server: ?*transport.Server,
    server_thread: ?std.Thread,

    fn init(allocator: std.mem.Allocator, expected_uid: u32) !*TestEnv {
        const self = try allocator.create(TestEnv);
        errdefer allocator.destroy(self);
        const data_dir_owned = try shortDataDir(allocator);
        errdefer cleanupShortDir(allocator, data_dir_owned);
        const audit_path = try std.fs.path.join(allocator, &.{ data_dir_owned, "audit.log" });
        errdefer allocator.free(audit_path);

        self.* = .{
            .allocator = allocator,
            .data_dir = data_dir_owned,
            .audit_path = audit_path,
            .audit = audit_log.AuditLog.init(),
            .store = undefined,
            .handler = undefined,
            .disp = undefined,
            .server = null,
            .server_thread = null,
        };
        try self.audit.open(audit_path);
        self.store = try bearer_tokens.TokenStore.init(allocator, data_dir_owned, pinnedClock);
        self.handler = handler_mod.Handler.init(allocator, &self.store);
        self.disp = dispatcher_mod.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        self.server = try transport.Server.bind(allocator, data_dir_owned, expected_uid, &self.disp);
        return self;
    }

    fn startAccepting(self: *TestEnv) !void {
        self.server_thread = try std.Thread.spawn(.{}, runAccept, .{self.server.?});
    }

    fn deinit(self: *TestEnv) void {
        if (self.server) |s| {
            s.stop();
            if (self.server_thread) |t| t.join();
            s.deinit();
            self.server = null;
        }
        self.disp.deinit();
        self.store.deinit();
        self.audit.close();
        self.allocator.free(self.audit_path);
        cleanupShortDir(self.allocator, self.data_dir);
        self.allocator.destroy(self);
    }
};

fn runAccept(server: *transport.Server) void {
    server.serve();
}

// ─────────────────────────────────────────────────────────────────────
// Round-trip
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 unix_socket: server + client round-trip dispatches bearer_tokens.issue" {
    const allocator = std.testing.allocator;
    const my_uid = transport.currentUid();
    var env = try TestEnv.init(allocator, my_uid);
    defer env.deinit();
    try env.startAccepting();

    var client = try transport.Client.connect(allocator, env.data_dir);
    defer client.close();
    var resp = try client.dispatch("bearer_tokens", "issue",
        \\{"label":"socket-test"}
    , "req-001");
    defer resp.deinit();

    try std.testing.expectEqualSlices(u8, "req-001", resp.response.request_id);
    try std.testing.expectEqual(@as(?wire.ErrorBody, null), resp.response.err);
    // result_json should be the JSON object from the bearer handler.
    try std.testing.expect(std.mem.indexOf(u8, resp.response.result_json, "\"id\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.response.result_json, "\"token\":") != null);
}

// ─────────────────────────────────────────────────────────────────────
// uid mismatch — server rejects without invoking the dispatcher
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 unix_socket: peer uid mismatch returns capability_denied" {
    const allocator = std.testing.allocator;
    const my_uid = transport.currentUid();
    // Inject a different expected uid so getpeereid's result (= my_uid)
    // never matches.  The connecting test process is still the same
    // user — the server's expected_uid is the lever we flip.
    var env = try TestEnv.init(allocator, my_uid +% 1);
    defer env.deinit();
    try env.startAccepting();

    var client = try transport.Client.connect(allocator, env.data_dir);
    defer client.close();
    var resp = try client.dispatch("bearer_tokens", "issue",
        \\{"label":"should-fail"}
    , "req-002");
    defer resp.deinit();

    try std.testing.expect(resp.response.err != null);
    try std.testing.expectEqual(wire.ErrorKind.capability_denied, resp.response.err.?.kind);

    // Verify the bearer log was NOT touched — the dispatcher never ran.
    const log_path = try std.fs.path.join(allocator, &.{ env.data_dir, "bearer-tokens.log" });
    defer allocator.free(log_path);
    if (std.fs.cwd().openFile(log_path, .{})) |f| {
        defer f.close();
        const stat = try f.stat();
        try std.testing.expectEqual(@as(u64, 0), stat.size);
    } else |err| switch (err) {
        error.FileNotFound => {}, // even better — handler never opened the file
        else => return err,
    }
}

// ─────────────────────────────────────────────────────────────────────
// Wire-level malformed envelope
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 unix_socket: malformed envelope returns validation_failed" {
    const allocator = std.testing.allocator;
    const my_uid = transport.currentUid();
    var env = try TestEnv.init(allocator, my_uid);
    defer env.deinit();
    try env.startAccepting();

    // Connect manually so we can write garbage on the wire.
    const sock_path = try std.fs.path.join(allocator, &.{ env.data_dir, "brain.sock" });
    defer allocator.free(sock_path);
    var stream = try std.net.connectUnixSocket(sock_path);
    defer stream.close();

    try stream.writeAll("not json at all\n");

    var buf: [1024]u8 = undefined;
    const n = try stream.read(&buf);
    try std.testing.expect(n > 0);
    var owned = try wire.decodeResponse(allocator, std.mem.trimEnd(u8, buf[0..n], "\n"));
    defer owned.deinit();
    try std.testing.expect(owned.response.err != null);
    try std.testing.expectEqual(wire.ErrorKind.validation_failed, owned.response.err.?.kind);
}

// ─────────────────────────────────────────────────────────────────────
// Embedded fallback parity
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 unix_socket: socket-mode and embedded-mode produce identical post-state" {
    const allocator = std.testing.allocator;

    // Run the same `bearer_tokens.issue` call via the socket and via a
    // fresh embedded dispatcher; assert both leave a structurally
    // identical line in bearer-tokens.log.

    // ── Socket mode ──
    const my_uid = transport.currentUid();
    var env = try TestEnv.init(allocator, my_uid);
    defer env.deinit();
    try env.startAccepting();

    var client = try transport.Client.connect(allocator, env.data_dir);
    defer client.close();
    var resp = try client.dispatch("bearer_tokens", "issue",
        \\{"label":"parity"}
    , "req-parity-socket");
    defer resp.deinit();
    try std.testing.expect(resp.response.err == null);

    const socket_log_path = try std.fs.path.join(allocator, &.{ env.data_dir, "bearer-tokens.log" });
    defer allocator.free(socket_log_path);
    const socket_log = try readFile(allocator, socket_log_path);
    defer allocator.free(socket_log);

    // ── Embedded mode ──
    var embedded_tmp = std.testing.tmpDir(.{});
    defer embedded_tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const embedded_dir_path = try embedded_tmp.dir.realpath(".", &path_buf);
    const embedded_data_dir = try allocator.dupe(u8, embedded_dir_path);
    defer allocator.free(embedded_data_dir);

    var embedded_audit = audit_log.AuditLog.init();
    defer embedded_audit.close();
    const embedded_audit_path = try std.fs.path.join(allocator, &.{ embedded_data_dir, "audit.log" });
    defer allocator.free(embedded_audit_path);
    try embedded_audit.open(embedded_audit_path);

    var embedded_store = try bearer_tokens.TokenStore.init(allocator, embedded_data_dir, pinnedClock);
    defer embedded_store.deinit();
    var embedded_handler = handler_mod.Handler.init(allocator, &embedded_store);
    var embedded_disp = dispatcher_mod.Dispatcher.init(allocator, &embedded_audit);
    defer embedded_disp.deinit();
    try embedded_disp.register(embedded_handler.resourceHandler());

    var ctx = dispatcher_mod.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "req-parity-embedded", .transport_label = "in_process" },
    };
    var emb_result = try embedded_disp.dispatch(&ctx, "bearer_tokens", "issue",
        \\{"label":"parity"}
    );
    defer emb_result.deinit();

    const embedded_log_path = try std.fs.path.join(allocator, &.{ embedded_data_dir, "bearer-tokens.log" });
    defer allocator.free(embedded_log_path);
    const embedded_log = try readFile(allocator, embedded_log_path);
    defer allocator.free(embedded_log);

    // Both logs are JSON-lines-shaped with the same kind=issued schema.
    // The id + fingerprint differ (random per-issue), but the structural
    // shape and the operator-supplied fields must match.
    try std.testing.expect(std.mem.indexOf(u8, socket_log, "\"kind\":\"issued\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, embedded_log, "\"kind\":\"issued\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, socket_log, "\"label\":\"parity\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, embedded_log, "\"label\":\"parity\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, socket_log, "\"expires_at\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, embedded_log, "\"expires_at\"") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Stale-socket detection — second bind on the same path while the
// first server is alive must fail loud (not silently steal the
// socket from a running daemon).
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 unix_socket: bind refuses to steal a live socket" {
    const allocator = std.testing.allocator;
    const my_uid = transport.currentUid();
    var env = try TestEnv.init(allocator, my_uid);
    defer env.deinit();
    try env.startAccepting();

    // Second bind() on the same data_dir should fail because the
    // first daemon is alive and accepting.  Stand up a parallel
    // dispatcher just for the would-be second daemon.
    var audit2 = audit_log.AuditLog.init();
    defer audit2.close();
    var disp2 = dispatcher_mod.Dispatcher.init(allocator, &audit2);
    defer disp2.deinit();

    try std.testing.expectError(
        transport.TransportError.bind_failed,
        transport.Server.bind(allocator, env.data_dir, my_uid, &disp2),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Stale-socket cleanup — leftover socket file from a crashed prior
// daemon (no live accept on the other end) must be reclaimed.
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 unix_socket: bind reclaims a stale socket file from a crashed prior daemon" {
    const allocator = std.testing.allocator;
    const data_dir = try shortDataDir(allocator);
    defer cleanupShortDir(allocator, data_dir);

    // Plant a stale socket file (a regular file standing in for an
    // unlinked-but-not-cleaned-up socket inode from a crashed daemon).
    const stale_path = try std.fs.path.join(allocator, &.{ data_dir, "brain.sock" });
    defer allocator.free(stale_path);
    {
        const f = try std.fs.cwd().createFile(stale_path, .{});
        f.close();
    }

    // Bind succeeds — the stale file is reclaimed because no daemon
    // is listening on it (connect would fail with FileNotFound /
    // ConnectionRefused).
    var audit = audit_log.AuditLog.init();
    const audit_path = try std.fs.path.join(allocator, &.{ data_dir, "audit.log" });
    defer allocator.free(audit_path);
    try audit.open(audit_path);
    defer audit.close();
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();

    var srv = try transport.Server.bind(allocator, data_dir, transport.currentUid(), &disp);
    // No assertion needed — bind succeeding is the assertion.  The
    // stale file got reclaimed; the server is now listening.
    srv.deinit();
}

// ─────────────────────────────────────────────────────────────────────
// connect_failed when the socket file is absent
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 unix_socket: connect to absent socket returns connect_failed" {
    const allocator = std.testing.allocator;
    const data_dir = try shortDataDir(allocator);
    defer cleanupShortDir(allocator, data_dir);

    try std.testing.expectError(
        transport.TransportError.connect_failed,
        transport.Client.connect(allocator, data_dir),
    );
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const stat = try f.stat();
    const buf = try allocator.alloc(u8, stat.size);
    errdefer allocator.free(buf);
    const n = try f.readAll(buf);
    return buf[0..n];
}

```
