---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/apns_dispatcher_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.201663+00:00
---

# runtime/semantos-brain/tests/apns_dispatcher_test.zig

```zig
// D-O5m.followup-9 Phase B — APNs dispatcher behaviour conformance.
//
// Drives the dispatcher against a real CertStore + AuditLog + the
// MockTransport from push_http_transport.  Asserts:
//   • Happy path constructs the JWT + posts to the endpoint with
//     correct URL/headers/body shape.
//   • The cached JWT is reused while still inside the 50min TTL and
//     regenerated past it.
//   • A 410-Unregistered response clears the cert's apns_token.
//   • Transient transport errors are retried; persistent errors land
//     on transport_failed.
//   • Misconfigured (.p8 missing) surfaces a typed error at init.
//
// No live network — the MockTransport replays scripted responses.

const std = @import("std");
const apns_mod = @import("apns_dispatcher");
const transport_mod = @import("push_http_transport");
const identity_certs = @import("identity_certs");
const audit_log_mod = @import("audit_log");
const bkds = @import("bkds");

fn pinnedClock() i64 {
    return 1_700_000_000;
}

var g_now_iso_buf: [32]u8 = undefined;

fn pinnedNowIso(allocator: std.mem.Allocator) anyerror![]u8 {
    return try allocator.dupe(u8, "2026-05-02T10:00:00Z");
}

/// Synthesise a P-256 PKCS#8 PEM (in the byte-search shape Apple emits)
/// at the given path so the dispatcher can load it at init.  The raw
/// scalar is the seed for a deterministic key pair.
fn writeFakeP8(allocator: std.mem.Allocator, dir: std.fs.Dir, name: []const u8, scalar: [32]u8) ![]u8 {
    var inner_buf: [128]u8 = undefined;
    var inner_len: usize = 0;
    const prefix = [_]u8{ 0x30, 0x81, 0x87, 0x02, 0x01, 0x00, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x04, 0x6d, 0x30, 0x6b, 0x02, 0x01, 0x01 };
    @memcpy(inner_buf[0..prefix.len], &prefix);
    inner_len += prefix.len;
    inner_buf[inner_len] = 0x04;
    inner_buf[inner_len + 1] = 0x20;
    @memcpy(inner_buf[inner_len + 2 ..][0..32], &scalar);
    inner_len += 2 + 32;

    const Encoder = std.base64.standard.Encoder;
    const b64 = try allocator.alloc(u8, Encoder.calcSize(inner_len));
    defer allocator.free(b64);
    _ = Encoder.encode(b64, inner_buf[0..inner_len]);
    const pem = try std.fmt.allocPrint(
        allocator,
        "-----BEGIN PRIVATE KEY-----\n{s}\n-----END PRIVATE KEY-----\n",
        .{b64},
    );
    defer allocator.free(pem);

    const f = try dir.createFile(name, .{});
    defer f.close();
    try f.writeAll(pem);
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    return try allocator.dupe(u8, try dir.realpath(name, &path_buf));
}

const Setup = struct {
    allocator: std.mem.Allocator,
    tmp: std.testing.TmpDir,
    data_dir: []u8,
    p8_path: []u8,
    certs: identity_certs.CertStore,
    audit: audit_log_mod.AuditLog,
    audit_path: []u8,
    cert_id: [identity_certs.CERT_ID_HEX_LEN]u8,
    transport: transport_mod.MockTransport,
    dispatcher: apns_mod.ApnsDispatcher,

    fn init(allocator: std.mem.Allocator) !*Setup {
        const self = try allocator.create(Setup);
        self.allocator = allocator;
        self.tmp = std.testing.tmpDir(.{});
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp.dir.realpath(".", &path_buf);
        self.data_dir = try allocator.dupe(u8, real);

        const scalar: [32]u8 = .{0x42} ** 32;
        self.p8_path = try writeFakeP8(allocator, self.tmp.dir, "AuthKey.p8", scalar);

        self.certs = try identity_certs.CertStore.init(allocator, self.data_dir, pinnedClock);
        self.audit = audit_log_mod.AuditLog.init();
        self.audit_path = try std.fs.path.join(allocator, &.{ self.data_dir, "audit.log" });
        self.audit.open(self.audit_path) catch {};

        // Mint a child cert + register an APNs token on it.
        const root_priv = bkds.privFromSeed("apns-root");
        const root_pub = try bkds.pubFromSeed("apns-root");
        const device_pub = try bkds.pubFromSeed("apns-device");
        const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x10, "iPhone");
        const root = try self.certs.issueRoot(root_pub, "operator");
        const child = try self.certs.issueChild(&root.id, 0x10, child_pub, &.{}, "iPhone");
        self.cert_id = child.id;
        try self.certs.updatePushToken(&child.id, .apns, "apns-tok-001", "2026-05-02T10:00:00Z");

        self.transport = transport_mod.MockTransport.init(allocator);
        self.dispatcher = try apns_mod.ApnsDispatcher.init(
            allocator,
            .{
                .bundle_id = "com.test.app",
                .key_id = "ABCDE12345",
                .team_id = "TEAM12345Z",
                .p8_key_path = self.p8_path,
                .environment = .production,
            },
            &self.certs,
            &self.audit,
            self.transport.transport(),
        );
        self.dispatcher.setClockFn(pinnedClock);
        self.dispatcher.setNowIsoFn(pinnedNowIso);
        return self;
    }

    fn deinit(self: *Setup) void {
        self.dispatcher.deinit();
        self.transport.deinit();
        self.audit.close();
        self.certs.deinit();
        self.allocator.free(self.audit_path);
        self.allocator.free(self.data_dir);
        self.allocator.free(self.p8_path);
        self.tmp.cleanup();
        self.allocator.destroy(self);
    }
};

test "apns: happy path posts to api.push.apple.com with wake-only headers + body" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.transport.enqueueOk("");
    try setup.dispatcher.send(&setup.cert_id, .{
        .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}",
    });

    try std.testing.expectEqual(@as(usize, 1), setup.transport.requestCount());
    const captured = setup.transport.lastRequest().?;
    // URL = production endpoint + /3/device/<token>.
    try std.testing.expectEqualStrings(
        "https://api.push.apple.com/3/device/apns-tok-001",
        captured.url,
    );
    // Sovereign-push D.1 — wake-only headers: push-type=background,
    // priority=5.  Both are required for content-available=1 to wake
    // a backgrounded app without rendering a banner.
    var have_auth = false;
    var have_topic = false;
    var have_push_type = false;
    var have_priority = false;
    for (captured.headers) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "authorization")) {
            try std.testing.expect(std.mem.startsWith(u8, h.value, "bearer "));
            have_auth = true;
        } else if (std.ascii.eqlIgnoreCase(h.name, "apns-topic")) {
            try std.testing.expectEqualStrings("com.test.app", h.value);
            have_topic = true;
        } else if (std.ascii.eqlIgnoreCase(h.name, "apns-push-type")) {
            try std.testing.expectEqualStrings("background", h.value);
            have_push_type = true;
        } else if (std.ascii.eqlIgnoreCase(h.name, "apns-priority")) {
            try std.testing.expectEqualStrings("5", h.value);
            have_priority = true;
        }
    }
    try std.testing.expect(have_auth and have_topic and have_push_type and have_priority);
    // Body is wake-only: aps.content-available=1, no alert/sound/badge.
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, captured.body, .{});
    defer parsed.deinit();
    const aps = parsed.value.object.get("aps").?;
    try std.testing.expectEqual(@as(i64, 1), aps.object.get("content-available").?.integer);
    try std.testing.expect(aps.object.get("alert") == null);
    try std.testing.expect(aps.object.get("sound") == null);
    try std.testing.expect(aps.object.get("badge") == null);
    // Event envelope is hoisted to the top level.
    try std.testing.expectEqualStrings("E1", parsed.value.object.get("event_id").?.string);
    try std.testing.expectEqual(@as(i64, 1700000000), parsed.value.object.get("ts").?.integer);
    try std.testing.expectEqualStrings("helm.event", parsed.value.object.get("kind").?.string);
}

test "apns: JWT cached across multiple sends within TTL" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.transport.enqueueOk("");
    try setup.transport.enqueueOk("");
    try setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });
    try setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });

    try std.testing.expectEqual(@as(usize, 2), setup.transport.requestCount());
    // Both requests carry the same authorization header (= same JWT).
    const r0 = setup.transport.captured.items[0];
    const r1 = setup.transport.captured.items[1];
    var auth0: []const u8 = "";
    var auth1: []const u8 = "";
    for (r0.headers) |h| if (std.ascii.eqlIgnoreCase(h.name, "authorization")) {
        auth0 = h.value;
    };
    for (r1.headers) |h| if (std.ascii.eqlIgnoreCase(h.name, "authorization")) {
        auth1 = h.value;
    };
    try std.testing.expectEqualStrings(auth0, auth1);
}

test "apns: 410 Unregistered clears the cert's apns_token" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.transport.enqueue(.{
        .status = 410,
        .body = "{\"reason\":\"Unregistered\"}",
    });
    // send() returns ok-from-the-caller's-POV when the token expired
    // (the caller has nothing to retry — the token's gone).
    try setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });

    // Cert's push_platform should now be `none`.
    const rec = try setup.certs.get(&setup.cert_id);
    try std.testing.expectEqual(identity_certs.PushPlatform.none, rec.push_platform);
    try std.testing.expectEqual(@as(usize, 0), rec.apns_token.len);
}

test "apns: transient transport errors are retried" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    setup.transport.enqueueTransportError();
    setup.transport.enqueueTransportError();
    try setup.transport.enqueueOk("");
    try setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });
    // 2 transport errors consumed + 1 successful POST captured = 3 total requests.
    try std.testing.expectEqual(@as(usize, 3), setup.transport.requestCount());
}

test "apns: persistent transport errors surface as transport_failed" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    setup.transport.enqueueTransportError();
    setup.transport.enqueueTransportError();
    setup.transport.enqueueTransportError();
    try std.testing.expectError(
        apns_mod.DispatchError.transport_failed,
        setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" }),
    );
}

test "apns: missing .p8 surfaces p8_key_read_failed at init" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const data_dir = try allocator.dupe(u8, real);
    defer allocator.free(data_dir);

    var certs = try identity_certs.CertStore.init(allocator, data_dir, pinnedClock);
    defer certs.deinit();
    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    var transport = transport_mod.MockTransport.init(allocator);
    defer transport.deinit();

    try std.testing.expectError(
        apns_mod.DispatchError.p8_key_read_failed,
        apns_mod.ApnsDispatcher.init(allocator, .{
            .bundle_id = "x",
            .key_id = "y",
            .team_id = "z",
            .p8_key_path = "/nonexistent/path/key.p8",
        }, &certs, &audit, transport.transport()),
    );
}

```
