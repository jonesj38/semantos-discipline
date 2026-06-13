---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/fcm_dispatcher_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.181005+00:00
---

# runtime/semantos-brain/tests/fcm_dispatcher_test.zig

```zig
// D-O5m.followup-9 Phase B — FCM dispatcher behaviour conformance.
//
// Asserts:
//   • Happy path: dispatcher swaps the JWT-bearer assertion for an
//     OAuth2 access_token, then POSTs to the FCM v1 endpoint with
//     correct shape.
//   • Bearer caching: subsequent sends within TTL reuse the same
//     access_token without re-hitting oauth2.googleapis.com.
//   • A 404 UNREGISTERED clears the cert's fcm_token.
//   • Transient transport errors on the OAuth endpoint are retried.
//   • Misconfigured (missing service-account JSON) surfaces a typed
//     error at init.
//
// The RS256 signer is overridden with a deterministic stub so the
// tests don't shell out to openssl.

const std = @import("std");
const fcm_mod = @import("fcm_dispatcher");
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

fn writeServiceAccountJson(dir: std.fs.Dir, name: []const u8) !void {
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

const Setup = struct {
    allocator: std.mem.Allocator,
    tmp: std.testing.TmpDir,
    data_dir: []u8,
    sa_path: []u8,
    certs: identity_certs.CertStore,
    audit: audit_log_mod.AuditLog,
    audit_path: []u8,
    cert_id: [identity_certs.CERT_ID_HEX_LEN]u8,
    transport: transport_mod.MockTransport,
    dispatcher: fcm_mod.FcmDispatcher,

    fn init(allocator: std.mem.Allocator) !*Setup {
        const self = try allocator.create(Setup);
        self.allocator = allocator;
        self.tmp = std.testing.tmpDir(.{});
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp.dir.realpath(".", &path_buf);
        self.data_dir = try allocator.dupe(u8, real);

        try writeServiceAccountJson(self.tmp.dir, "sa.json");
        var sa_buf: [std.fs.max_path_bytes]u8 = undefined;
        self.sa_path = try allocator.dupe(u8, try self.tmp.dir.realpath("sa.json", &sa_buf));

        self.certs = try identity_certs.CertStore.init(allocator, self.data_dir, pinnedClock);
        self.audit = audit_log_mod.AuditLog.init();
        self.audit_path = try std.fs.path.join(allocator, &.{ self.data_dir, "audit.log" });
        self.audit.open(self.audit_path) catch {};

        const root_priv = bkds.privFromSeed("fcm-root");
        const root_pub = try bkds.pubFromSeed("fcm-root");
        const device_pub = try bkds.pubFromSeed("fcm-device");
        const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x10, "Pixel");
        const root = try self.certs.issueRoot(root_pub, "operator");
        const child = try self.certs.issueChild(&root.id, 0x10, child_pub, &.{}, "Pixel");
        self.cert_id = child.id;
        try self.certs.updatePushToken(&child.id, .fcm, "fcm-tok-001", "2026-05-02T10:00:00Z");

        self.transport = transport_mod.MockTransport.init(allocator);
        self.dispatcher = try fcm_mod.FcmDispatcher.init(
            allocator,
            .{
                .project_id = "test-proj",
                .service_account_json_path = self.sa_path,
            },
            &self.certs,
            &self.audit,
            self.transport.transport(),
        );
        self.dispatcher.setClockFn(pinnedClock);
        self.dispatcher.setNowIsoFn(pinnedNowIso);
        self.dispatcher.setRs256SignFn(fcm_mod.testStubSigner);
        return self;
    }

    fn deinit(self: *Setup) void {
        self.dispatcher.deinit();
        self.transport.deinit();
        self.audit.close();
        self.certs.deinit();
        self.allocator.free(self.audit_path);
        self.allocator.free(self.data_dir);
        self.allocator.free(self.sa_path);
        self.tmp.cleanup();
        self.allocator.destroy(self);
    }
};

test "fcm: happy path swaps JWT for access_token, posts wake-only data-only message" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    // 1st response = oauth2 token swap.
    try setup.transport.enqueueOk("{\"access_token\":\"oauth-tok-AAA\",\"expires_in\":3600,\"token_type\":\"Bearer\"}");
    // 2nd response = FCM send success.
    try setup.transport.enqueueOk("{\"name\":\"projects/test-proj/messages/abc\"}");

    try setup.dispatcher.send(&setup.cert_id, .{
        .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}",
    });

    try std.testing.expectEqual(@as(usize, 2), setup.transport.requestCount());
    // First request = oauth.
    const oauth_req = setup.transport.captured.items[0];
    try std.testing.expectEqualStrings("https://oauth2.googleapis.com/token", oauth_req.url);
    try std.testing.expect(std.mem.indexOf(u8, oauth_req.body, "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer") != null);
    // Second request = FCM send.
    const fcm_req = setup.transport.captured.items[1];
    try std.testing.expectEqualStrings("https://fcm.googleapis.com/v1/projects/test-proj/messages:send", fcm_req.url);
    var have_auth = false;
    for (fcm_req.headers) |h| if (std.ascii.eqlIgnoreCase(h.name, "authorization")) {
        try std.testing.expectEqualStrings("Bearer oauth-tok-AAA", h.value);
        have_auth = true;
    };
    try std.testing.expect(have_auth);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, fcm_req.body, .{});
    defer parsed.deinit();
    const message = parsed.value.object.get("message").?;
    try std.testing.expectEqualStrings("fcm-tok-001", message.object.get("token").?.string);
    // Sovereign-push D.1 — no `notification` field.
    try std.testing.expect(message.object.get("notification") == null);
    // Data is string→string with the opaque envelope fields.
    const data = message.object.get("data").?;
    try std.testing.expectEqualStrings("E1", data.object.get("event_id").?.string);
    try std.testing.expectEqualStrings("1700000000", data.object.get("ts").?.string);
    try std.testing.expectEqualStrings("helm.event", data.object.get("kind").?.string);
}

test "fcm: bearer caching reuses access_token across sends" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.transport.enqueueOk("{\"access_token\":\"oauth-tok-AAA\",\"expires_in\":3600,\"token_type\":\"Bearer\"}");
    try setup.transport.enqueueOk("{\"name\":\"x\"}");
    try setup.transport.enqueueOk("{\"name\":\"y\"}");

    try setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });
    try setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });

    // Total = 1 oauth + 2 fcm sends = 3 (NOT 4 — the second send
    // reuses the cached bearer).
    try std.testing.expectEqual(@as(usize, 3), setup.transport.requestCount());
}

test "fcm: 404 UNREGISTERED clears the cert's fcm_token" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.transport.enqueueOk("{\"access_token\":\"x\",\"expires_in\":3600,\"token_type\":\"Bearer\"}");
    try setup.transport.enqueue(.{
        .status = 404,
        .body = "{\"error\":{\"code\":404,\"status\":\"UNREGISTERED\",\"message\":\"...\"}}",
    });
    try setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });

    const rec = try setup.certs.get(&setup.cert_id);
    try std.testing.expectEqual(identity_certs.PushPlatform.none, rec.push_platform);
    try std.testing.expectEqual(@as(usize, 0), rec.fcm_token.len);
}

test "fcm: transient transport error on OAuth retried" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    setup.transport.enqueueTransportError();
    try setup.transport.enqueueOk("{\"access_token\":\"x\",\"expires_in\":3600,\"token_type\":\"Bearer\"}");
    try setup.transport.enqueueOk("{\"name\":\"x\"}");

    try setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}" });
    // 1 transport error + 1 oauth ok + 1 fcm ok = 3.
    try std.testing.expectEqual(@as(usize, 3), setup.transport.requestCount());
}

test "fcm: missing service-account JSON surfaces service_account_read_failed" {
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
        fcm_mod.DispatchError.service_account_read_failed,
        fcm_mod.FcmDispatcher.init(allocator, .{
            .project_id = "x",
            .service_account_json_path = "/nonexistent/sa.json",
        }, &certs, &audit, transport.transport()),
    );
}

test "fcm: malformed service-account JSON surfaces service_account_parse_failed" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        const f = try tmp.dir.createFile("bad.json", .{});
        defer f.close();
        try f.writeAll("{}");
    }
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try allocator.dupe(u8, try tmp.dir.realpath(".", &path_buf));
    defer allocator.free(data_dir);
    const sa_path = try std.fs.path.join(allocator, &.{ data_dir, "bad.json" });
    defer allocator.free(sa_path);

    var certs = try identity_certs.CertStore.init(allocator, data_dir, pinnedClock);
    defer certs.deinit();
    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    var transport = transport_mod.MockTransport.init(allocator);
    defer transport.deinit();

    try std.testing.expectError(
        fcm_mod.DispatchError.service_account_parse_failed,
        fcm_mod.FcmDispatcher.init(allocator, .{
            .project_id = "x",
            .service_account_json_path = sa_path,
        }, &certs, &audit, transport.transport()),
    );
}

```
