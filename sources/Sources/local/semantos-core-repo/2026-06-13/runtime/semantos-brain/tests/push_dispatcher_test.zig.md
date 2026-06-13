---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/push_dispatcher_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.208249+00:00
---

# runtime/semantos-brain/tests/push_dispatcher_test.zig

```zig
// D-O5m.followup-9 Phase B / Sovereign-push D.3 — PushDispatcher
// routing conformance.
//
// Asserts:
//   • Routes to APNs when cert.push_platform == apns.
//   • Routes to FCM when cert.push_platform == fcm.
//   • Routes to UnifiedPush when cert.push_platform == unifiedpush.
//   • Skips with audit when cert.push_platform == none.
//   • Skips with audit when the relevant dispatcher isn't configured.
//   • sendToCerts fans out to multiple cert ids across all backends.

const std = @import("std");
const push_mod = @import("push_dispatcher");
const apns_mod = @import("apns_dispatcher");
const fcm_mod = @import("fcm_dispatcher");
const up_mod = @import("unifiedpush_dispatcher");
const transport_mod = @import("push_http_transport");
const identity_certs = @import("identity_certs");
const audit_log_mod = @import("audit_log");
const bkds = @import("bkds");

fn pinnedClock() i64 {
    return 1_700_000_000;
}

fn pinnedNowIso(allocator: std.mem.Allocator) anyerror![]u8 {
    return try allocator.dupe(u8, "2026-05-02T10:00:00Z");
}

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

fn writeServiceAccountJson(allocator: std.mem.Allocator, dir: std.fs.Dir, name: []const u8) ![]u8 {
    {
        const f = try dir.createFile(name, .{});
        defer f.close();
        try f.writeAll(
            \\{
            \\  "type":"service_account",
            \\  "client_email":"abc@test.iam.gserviceaccount.com",
            \\  "private_key":"-----BEGIN PRIVATE KEY-----\nNOTKEY\n-----END PRIVATE KEY-----\n"
            \\}
        );
    }
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    return try allocator.dupe(u8, try dir.realpath(name, &path_buf));
}

const Setup = struct {
    allocator: std.mem.Allocator,
    tmp: std.testing.TmpDir,
    data_dir: []u8,
    p8_path: []u8,
    sa_path: []u8,
    certs: identity_certs.CertStore,
    audit: audit_log_mod.AuditLog,
    audit_path: []u8,
    cert_apns_id: [identity_certs.CERT_ID_HEX_LEN]u8,
    cert_fcm_id: [identity_certs.CERT_ID_HEX_LEN]u8,
    cert_up_id: [identity_certs.CERT_ID_HEX_LEN]u8,
    cert_none_id: [identity_certs.CERT_ID_HEX_LEN]u8,
    apns_transport: transport_mod.MockTransport,
    fcm_transport: transport_mod.MockTransport,
    up_transport: transport_mod.MockTransport,
    apns: apns_mod.ApnsDispatcher,
    fcm: fcm_mod.FcmDispatcher,
    up: up_mod.UnifiedPushDispatcher,
    push: push_mod.PushDispatcher,

    fn init(allocator: std.mem.Allocator) !*Setup {
        const self = try allocator.create(Setup);
        self.allocator = allocator;
        self.tmp = std.testing.tmpDir(.{});
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp.dir.realpath(".", &path_buf);
        self.data_dir = try allocator.dupe(u8, real);

        const scalar: [32]u8 = .{0x42} ** 32;
        self.p8_path = try writeFakeP8(allocator, self.tmp.dir, "AuthKey.p8", scalar);
        self.sa_path = try writeServiceAccountJson(allocator, self.tmp.dir, "sa.json");

        self.certs = try identity_certs.CertStore.init(allocator, self.data_dir, pinnedClock);
        self.audit = audit_log_mod.AuditLog.init();
        self.audit_path = try std.fs.path.join(allocator, &.{ self.data_dir, "audit.log" });
        self.audit.open(self.audit_path) catch {};

        // 3 child certs: one with apns, one with fcm, one with none.
        const root_priv = bkds.privFromSeed("push-root");
        const root_pub = try bkds.pubFromSeed("push-root");
        const root = try self.certs.issueRoot(root_pub, "operator");

        const apns_dev = try bkds.pubFromSeed("apns-dev");
        const apns_child_pub = try bkds.deriveChildPubkey(root_priv, apns_dev, 0x10, "iPhone");
        const apns_child = try self.certs.issueChild(&root.id, 0x10, apns_child_pub, &.{}, "iPhone");
        self.cert_apns_id = apns_child.id;
        try self.certs.updatePushToken(&apns_child.id, .apns, "apns-tok-1", "2026-05-02T10:00:00Z");

        const fcm_dev = try bkds.pubFromSeed("fcm-dev");
        const fcm_child_pub = try bkds.deriveChildPubkey(root_priv, fcm_dev, 0x11, "Pixel");
        const fcm_child = try self.certs.issueChild(&root.id, 0x11, fcm_child_pub, &.{}, "Pixel");
        self.cert_fcm_id = fcm_child.id;
        try self.certs.updatePushToken(&fcm_child.id, .fcm, "fcm-tok-1", "2026-05-02T10:00:00Z");

        // Sovereign-push D.3 — a fourth child cert registered via
        // UnifiedPush.  The token field carries an https:// distributor
        // endpoint URL; the dispatcher will POST the wake envelope
        // there with no auth headers.
        const up_dev = try bkds.pubFromSeed("up-dev");
        const up_child_pub = try bkds.deriveChildPubkey(root_priv, up_dev, 0x13, "PinePhone");
        const up_child = try self.certs.issueChild(&root.id, 0x13, up_child_pub, &.{}, "PinePhone");
        self.cert_up_id = up_child.id;
        try self.certs.updatePushToken(&up_child.id, .unifiedpush, "https://ntfy.example/UPxyz", "2026-05-02T10:00:00Z");

        const none_dev = try bkds.pubFromSeed("none-dev");
        const none_child_pub = try bkds.deriveChildPubkey(root_priv, none_dev, 0x12, "WebOnly");
        const none_child = try self.certs.issueChild(&root.id, 0x12, none_child_pub, &.{}, "WebOnly");
        self.cert_none_id = none_child.id;

        self.apns_transport = transport_mod.MockTransport.init(allocator);
        self.fcm_transport = transport_mod.MockTransport.init(allocator);
        self.up_transport = transport_mod.MockTransport.init(allocator);

        self.apns = try apns_mod.ApnsDispatcher.init(
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
            self.apns_transport.transport(),
        );
        self.apns.setClockFn(pinnedClock);
        self.apns.setNowIsoFn(pinnedNowIso);

        self.fcm = try fcm_mod.FcmDispatcher.init(
            allocator,
            .{
                .project_id = "test-proj",
                .service_account_json_path = self.sa_path,
            },
            &self.certs,
            &self.audit,
            self.fcm_transport.transport(),
        );
        self.fcm.setClockFn(pinnedClock);
        self.fcm.setNowIsoFn(pinnedNowIso);
        self.fcm.setRs256SignFn(fcm_mod.testStubSigner);

        self.up = up_mod.UnifiedPushDispatcher.init(
            allocator,
            &self.certs,
            &self.audit,
            self.up_transport.transport(),
        );
        self.up.setNowIsoFn(pinnedNowIso);

        self.push = push_mod.PushDispatcher.init(
            allocator,
            &self.apns,
            &self.fcm,
            &self.up,
            &self.certs,
            &self.audit,
        );
        return self;
    }

    fn deinit(self: *Setup) void {
        self.up.deinit();
        self.fcm.deinit();
        self.apns.deinit();
        self.up_transport.deinit();
        self.fcm_transport.deinit();
        self.apns_transport.deinit();
        self.audit.close();
        self.certs.deinit();
        self.allocator.free(self.audit_path);
        self.allocator.free(self.data_dir);
        self.allocator.free(self.p8_path);
        self.allocator.free(self.sa_path);
        self.tmp.cleanup();
        self.allocator.destroy(self);
    }
};

test "push: routes to APNs when cert.push_platform=apns" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.apns_transport.enqueueOk("");
    try setup.push.sendToCert(&setup.cert_apns_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });

    try std.testing.expectEqual(@as(usize, 1), setup.apns_transport.requestCount());
    try std.testing.expectEqual(@as(usize, 0), setup.fcm_transport.requestCount());
}

test "push: routes to FCM when cert.push_platform=fcm" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.fcm_transport.enqueueOk("{\"access_token\":\"x\",\"expires_in\":3600,\"token_type\":\"Bearer\"}");
    try setup.fcm_transport.enqueueOk("{\"name\":\"y\"}");
    try setup.push.sendToCert(&setup.cert_fcm_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });

    try std.testing.expectEqual(@as(usize, 0), setup.apns_transport.requestCount());
    try std.testing.expectEqual(@as(usize, 2), setup.fcm_transport.requestCount());
}

test "push: skips when cert.push_platform=none" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.push.sendToCert(&setup.cert_none_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });
    // No transport calls — skipped via audit only.
    try std.testing.expectEqual(@as(usize, 0), setup.apns_transport.requestCount());
    try std.testing.expectEqual(@as(usize, 0), setup.fcm_transport.requestCount());
}

test "push: skips APNs when apns dispatcher null" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    var pd_no_apns = push_mod.PushDispatcher.init(
        allocator,
        null,
        &setup.fcm,
        &setup.up,
        &setup.certs,
        &setup.audit,
    );
    try pd_no_apns.sendToCert(&setup.cert_apns_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });
    try std.testing.expectEqual(@as(usize, 0), setup.apns_transport.requestCount());
    try std.testing.expectEqual(@as(usize, 0), setup.fcm_transport.requestCount());
    try std.testing.expectEqual(@as(usize, 0), setup.up_transport.requestCount());
}

test "push: routes to UnifiedPush when cert.push_platform=unifiedpush" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.up_transport.enqueueOk("");
    try setup.push.sendToCert(&setup.cert_up_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });

    try std.testing.expectEqual(@as(usize, 0), setup.apns_transport.requestCount());
    try std.testing.expectEqual(@as(usize, 0), setup.fcm_transport.requestCount());
    try std.testing.expectEqual(@as(usize, 1), setup.up_transport.requestCount());

    // Body should be the raw payload_json byte-for-byte.
    const captured = setup.up_transport.lastRequest().?;
    try std.testing.expectEqualStrings(
        "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}",
        captured.body,
    );
    try std.testing.expectEqualStrings("https://ntfy.example/UPxyz", captured.url);
}

test "push: skips UnifiedPush when up dispatcher null" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    var pd_no_up = push_mod.PushDispatcher.init(
        allocator,
        &setup.apns,
        &setup.fcm,
        null,
        &setup.certs,
        &setup.audit,
    );
    try pd_no_up.sendToCert(&setup.cert_up_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });
    try std.testing.expectEqual(@as(usize, 0), setup.up_transport.requestCount());
}

test "push: sendToCerts fans out to multiple certs across all backends" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    // 1 APNs send + (1 FCM oauth + 1 FCM send) + 1 UP send = 4 calls
    // across the three transports.  cert_none_id never reaches a
    // transport (push_platform == none).
    try setup.apns_transport.enqueueOk("");
    try setup.fcm_transport.enqueueOk("{\"access_token\":\"x\",\"expires_in\":3600,\"token_type\":\"Bearer\"}");
    try setup.fcm_transport.enqueueOk("{\"name\":\"y\"}");
    try setup.up_transport.enqueueOk("");

    var ids_buf: [4][identity_certs.CERT_ID_HEX_LEN]u8 = .{
        setup.cert_apns_id,
        setup.cert_fcm_id,
        setup.cert_up_id,
        setup.cert_none_id,
    };
    var ids = [4][]const u8{ &ids_buf[0], &ids_buf[1], &ids_buf[2], &ids_buf[3] };
    setup.push.sendToCerts(&ids, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });

    try std.testing.expectEqual(@as(usize, 1), setup.apns_transport.requestCount());
    try std.testing.expectEqual(@as(usize, 2), setup.fcm_transport.requestCount());
    try std.testing.expectEqual(@as(usize, 1), setup.up_transport.requestCount());
}

test "push: cert_not_found surfaces typed error" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    const bogus_id = "00000000000000000000000000000000";
    try std.testing.expectError(
        push_mod.DispatchError.cert_not_found,
        setup.push.sendToCert(bogus_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" }),
    );
}

```
