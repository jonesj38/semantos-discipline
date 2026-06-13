---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/unifiedpush_dispatcher_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.186900+00:00
---

# runtime/semantos-brain/tests/unifiedpush_dispatcher_test.zig

```zig
// Sovereign-push D.3 — UnifiedPush dispatcher conformance.
//
// Asserts:
//   • POST hits the cert's stored up_endpoint URL with body =
//     payload_json verbatim and Content-Type: application/json.
//   • No Authorization header — UP is auth-free (the URL itself is
//     the capability).
//   • 2xx response → ok, no cert mutation.
//   • 410 Gone → cert.up_endpoint cleared (mirrors APNs/FCM
//     token-expiry path).
//   • 4xx (other) → unifiedpush_rejected typed error.
//   • 5xx → retry up to 3 times, then transport_failed.
//   • Transient transport_error → retry; succeeds on 3rd try.
//   • cert_not_found surfaces typed error.
//   • cert.push_platform != unifiedpush → no_up_endpoint.

const std = @import("std");
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

const Setup = struct {
    allocator: std.mem.Allocator,
    tmp: std.testing.TmpDir,
    data_dir: []u8,
    certs: identity_certs.CertStore,
    audit: audit_log_mod.AuditLog,
    audit_path: []u8,
    transport: transport_mod.MockTransport,
    cert_id: [identity_certs.CERT_ID_HEX_LEN]u8,
    dispatcher: up_mod.UnifiedPushDispatcher,

    fn init(allocator: std.mem.Allocator) !*Setup {
        const self = try allocator.create(Setup);
        self.allocator = allocator;
        self.tmp = std.testing.tmpDir(.{});
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp.dir.realpath(".", &path_buf);
        self.data_dir = try allocator.dupe(u8, real);

        self.certs = try identity_certs.CertStore.init(allocator, self.data_dir, pinnedClock);
        self.audit = audit_log_mod.AuditLog.init();
        self.audit_path = try std.fs.path.join(allocator, &.{ self.data_dir, "audit.log" });
        self.audit.open(self.audit_path) catch {};

        const root_priv = bkds.privFromSeed("up-root");
        const root_pub = try bkds.pubFromSeed("up-root");
        const root = try self.certs.issueRoot(root_pub, "operator");
        const dev = try bkds.pubFromSeed("up-device");
        const child_pub = try bkds.deriveChildPubkey(root_priv, dev, 0x13, "PinePhone");
        const child = try self.certs.issueChild(&root.id, 0x13, child_pub, &.{}, "PinePhone");
        self.cert_id = child.id;
        try self.certs.updatePushToken(&child.id, .unifiedpush, "https://ntfy.example/UPxyz", "2026-05-02T10:00:00Z");

        self.transport = transport_mod.MockTransport.init(allocator);

        self.dispatcher = up_mod.UnifiedPushDispatcher.init(
            allocator,
            &self.certs,
            &self.audit,
            self.transport.transport(),
        );
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
        self.tmp.cleanup();
        self.allocator.destroy(self);
    }
};

test "unifiedpush: 2xx success POSTs to cert.up_endpoint with raw body" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.transport.enqueueOk("");
    const payload = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}";
    try setup.dispatcher.send(&setup.cert_id, .{ .payload_json = payload });

    try std.testing.expectEqual(@as(usize, 1), setup.transport.requestCount());
    const captured = setup.transport.lastRequest().?;

    try std.testing.expectEqualStrings("POST", captured.method);
    try std.testing.expectEqualStrings("https://ntfy.example/UPxyz", captured.url);
    try std.testing.expectEqualStrings(payload, captured.body);

    // content-type header present, no authorization header.
    var saw_content_type = false;
    var saw_authorization = false;
    for (captured.headers) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "content-type")) {
            saw_content_type = true;
            try std.testing.expectEqualStrings("application/json", h.value);
        }
        if (std.ascii.eqlIgnoreCase(h.name, "authorization")) saw_authorization = true;
    }
    try std.testing.expect(saw_content_type);
    try std.testing.expect(!saw_authorization);
}

test "unifiedpush: 410 Gone clears the cert's up_endpoint" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.transport.enqueue(.{ .status = 410, .body = "Gone" });
    try setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{}" });

    // Cert still exists, but push_platform should be flipped back to
    // .none (the explicit-unregister path inside updatePushToken).
    const rec = try setup.certs.get(&setup.cert_id);
    try std.testing.expectEqual(identity_certs.PushPlatform.none, rec.push_platform);
    try std.testing.expectEqual(@as(usize, 0), rec.up_endpoint.len);
}

test "unifiedpush: 4xx (non-410) surfaces unifiedpush_rejected" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.transport.enqueue(.{ .status = 400, .body = "{\"error\":\"bad\"}" });
    try std.testing.expectError(
        up_mod.DispatchError.unifiedpush_rejected,
        setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{}" }),
    );
}

test "unifiedpush: 5xx is retried up to 3 attempts then surfaces transport_failed" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    try setup.transport.enqueue(.{ .status = 500 });
    try setup.transport.enqueue(.{ .status = 500 });
    try setup.transport.enqueue(.{ .status = 500 });
    try std.testing.expectError(
        up_mod.DispatchError.transport_failed,
        setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{}" }),
    );
    try std.testing.expectEqual(@as(usize, 3), setup.transport.requestCount());
}

test "unifiedpush: transient transport error retries, succeeds on next attempt" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    setup.transport.enqueueTransportError();
    try setup.transport.enqueueOk("");
    try setup.dispatcher.send(&setup.cert_id, .{ .payload_json = "{}" });
    // 2 captured requests — the first one returned transport_error
    // before yielding a response; the mock still records the attempt.
    try std.testing.expectEqual(@as(usize, 2), setup.transport.requestCount());
}

test "unifiedpush: cert_not_found surfaces typed error" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    const bogus = "00000000000000000000000000000000";
    try std.testing.expectError(
        up_mod.DispatchError.cert_not_found,
        setup.dispatcher.send(bogus, .{ .payload_json = "{}" }),
    );
    try std.testing.expectEqual(@as(usize, 0), setup.transport.requestCount());
}

test "unifiedpush: cert.push_platform=none surfaces no_up_endpoint" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    // Mint a second child cert, leave it unregistered.
    const root_id_arr = setup.certs.rootId().?;
    const root_id_slice: []const u8 = root_id_arr[0..];
    const root_priv = bkds.privFromSeed("up-root");
    const dev = try bkds.pubFromSeed("up-device-noreg");
    const child_pub = try bkds.deriveChildPubkey(root_priv, dev, 0x14, "Pixel");
    const child = try setup.certs.issueChild(root_id_slice, 0x14, child_pub, &.{}, "Pixel");
    try std.testing.expectError(
        up_mod.DispatchError.no_up_endpoint,
        setup.dispatcher.send(&child.id, .{ .payload_json = "{}" }),
    );
}

```
