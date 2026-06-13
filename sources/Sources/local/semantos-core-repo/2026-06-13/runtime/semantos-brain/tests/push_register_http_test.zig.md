---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/push_register_http_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.185193+00:00
---

# runtime/semantos-brain/tests/push_register_http_test.zig

```zig
// D-O5m.followup-9 Phase A — push-register endpoint conformance.
//
// Drives the pure-logic accept paths (acceptPost / acceptDelete)
// against a real CertStore + TokenStore so the bearer gate, cert
// lookup, body parser, and store update all run end-to-end.  The
// HTTP wrapper around these is mechanical (status code + JSON body
// format) and is exercised by the inline tests in
// src/push_register_http.zig.
//
// Reference: src/push_register_http.zig (the endpoint under test);
// docs/design/ODDJOBZ-EXTENSION-PLAN.md §D-O5m.followup-9 Phase A.

const std = @import("std");
const bsvz = @import("bsvz");
const bkds = @import("bkds");
const identity_certs = @import("identity_certs");
const bearer_tokens = @import("bearer_tokens");
const push_register_http = @import("push_register_http");

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
    tokens: bearer_tokens.TokenStore,
    bearer_hex: [64]u8,
    cert_id: [identity_certs.CERT_ID_HEX_LEN]u8,
    acceptor: push_register_http.Acceptor,

    fn init(allocator: std.mem.Allocator, seed: []const u8) !*Setup {
        const self = try allocator.create(Setup);
        self.allocator = allocator;
        self.tmp = std.testing.tmpDir(.{});
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp.dir.realpath(".", &path_buf);
        self.data_dir = try allocator.dupe(u8, real);

        self.certs = try identity_certs.CertStore.init(allocator, self.data_dir, pinnedClock);
        self.tokens = try bearer_tokens.TokenStore.init(allocator, self.data_dir, pinnedClock);

        // Mint operator root + a child cert so we have a real cert id
        // to register a token against.
        const root_priv = bkds.privFromSeed(seed);
        const root_pub = try bkds.pubFromSeed(seed);
        const device_pub = try bkds.pubFromSeed("device-push-test");
        const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x10, "phone");
        const root = try self.certs.issueRoot(root_pub, "operator");
        const child = try self.certs.issueChild(&root.id, 0x10, child_pub, &.{}, "phone");
        self.cert_id = child.id;

        // Issue a bearer token for the helm session that's about to
        // call /api/v1/push-register.
        const issued = try self.tokens.issue("test-bearer", 0);
        var bh: [64]u8 = undefined;
        bearer_tokens.hexEncode(&issued.token, &bh);
        self.bearer_hex = bh;

        self.acceptor = .{
            .allocator = allocator,
            .certs = &self.certs,
            .bearer_tokens = &self.tokens,
            .now_iso_fn = pinnedNowIso,
        };
        return self;
    }

    fn deinit(self: *Setup) void {
        self.tokens.deinit();
        self.certs.deinit();
        self.allocator.free(self.data_dir);
        self.tmp.cleanup();
        self.allocator.destroy(self);
    }
};

test "POST /api/v1/push-register: apns happy path persists token + returns timestamp" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "op-root-apns-pr");
    defer setup.deinit();

    var body_buf: std.ArrayList(u8) = .{};
    defer body_buf.deinit(allocator);
    try body_buf.print(allocator,
        "{{\"cert_id\":\"{s}\",\"platform\":\"apns\",\"token\":\"apns-tok-001\"}}",
        .{setup.cert_id});

    var result = try push_register_http.acceptPost(&setup.acceptor, setup.bearer_hex[0..], body_buf.items);
    defer result.deinit(allocator);
    try std.testing.expectEqual(push_register_http.AcceptResultKind.registered, result.kind);
    try std.testing.expectEqual(identity_certs.PushPlatform.apns, result.platform);
    try std.testing.expectEqualStrings("2026-05-02T10:00:00Z", result.registered_at);

    // Assert the cert store actually persisted the token.
    const reloaded = try setup.certs.get(&setup.cert_id);
    try std.testing.expectEqualStrings("apns-tok-001", reloaded.apns_token);
    try std.testing.expectEqual(identity_certs.PushPlatform.apns, reloaded.push_platform);
}

test "POST /api/v1/push-register: fcm happy path persists token + returns timestamp" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "op-root-fcm-pr");
    defer setup.deinit();

    var body_buf: std.ArrayList(u8) = .{};
    defer body_buf.deinit(allocator);
    try body_buf.print(allocator,
        "{{\"cert_id\":\"{s}\",\"platform\":\"fcm\",\"token\":\"fcm-reg-token-001\"}}",
        .{setup.cert_id});

    var result = try push_register_http.acceptPost(&setup.acceptor, setup.bearer_hex[0..], body_buf.items);
    defer result.deinit(allocator);
    try std.testing.expectEqual(push_register_http.AcceptResultKind.registered, result.kind);
    try std.testing.expectEqual(identity_certs.PushPlatform.fcm, result.platform);

    const reloaded = try setup.certs.get(&setup.cert_id);
    try std.testing.expectEqualStrings("fcm-reg-token-001", reloaded.fcm_token);
}

test "POST /api/v1/push-register: missing bearer surfaces unauthorised (401)" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "op-root-no-bearer-pr");
    defer setup.deinit();

    var body_buf: std.ArrayList(u8) = .{};
    defer body_buf.deinit(allocator);
    try body_buf.print(allocator,
        "{{\"cert_id\":\"{s}\",\"platform\":\"apns\",\"token\":\"tok\"}}",
        .{setup.cert_id});

    var result = try push_register_http.acceptPost(&setup.acceptor, null, body_buf.items);
    defer result.deinit(allocator);
    try std.testing.expectEqual(push_register_http.AcceptResultKind.unauthorised, result.kind);
    try std.testing.expectEqual(std.http.Status.unauthorized, result.kind.httpStatus());
}

test "POST /api/v1/push-register: invalid bearer surfaces unauthorised" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "op-root-bad-bearer-pr");
    defer setup.deinit();

    var body_buf: std.ArrayList(u8) = .{};
    defer body_buf.deinit(allocator);
    try body_buf.print(allocator,
        "{{\"cert_id\":\"{s}\",\"platform\":\"apns\",\"token\":\"tok\"}}",
        .{setup.cert_id});

    // 64 hex chars but not in the token store.
    const bad_bearer = "0000000000000000000000000000000000000000000000000000000000000000";
    var result = try push_register_http.acceptPost(&setup.acceptor, bad_bearer, body_buf.items);
    defer result.deinit(allocator);
    try std.testing.expectEqual(push_register_http.AcceptResultKind.unauthorised, result.kind);
}

test "POST /api/v1/push-register: unknown platform surfaces platform_invalid (400)" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "op-root-bad-platform-pr");
    defer setup.deinit();

    var body_buf: std.ArrayList(u8) = .{};
    defer body_buf.deinit(allocator);
    try body_buf.print(allocator,
        "{{\"cert_id\":\"{s}\",\"platform\":\"oops\",\"token\":\"tok\"}}",
        .{setup.cert_id});

    var result = try push_register_http.acceptPost(&setup.acceptor, setup.bearer_hex[0..], body_buf.items);
    defer result.deinit(allocator);
    try std.testing.expectEqual(push_register_http.AcceptResultKind.platform_invalid, result.kind);
    try std.testing.expectEqual(std.http.Status.bad_request, result.kind.httpStatus());
}

test "POST /api/v1/push-register: empty token surfaces token_empty (400)" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "op-root-empty-tok-pr");
    defer setup.deinit();

    var body_buf: std.ArrayList(u8) = .{};
    defer body_buf.deinit(allocator);
    try body_buf.print(allocator,
        "{{\"cert_id\":\"{s}\",\"platform\":\"apns\",\"token\":\"\"}}",
        .{setup.cert_id});

    var result = try push_register_http.acceptPost(&setup.acceptor, setup.bearer_hex[0..], body_buf.items);
    defer result.deinit(allocator);
    try std.testing.expectEqual(push_register_http.AcceptResultKind.token_empty, result.kind);
}

test "POST /api/v1/push-register: oversized token surfaces token_too_large (413)" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "op-root-big-tok-pr");
    defer setup.deinit();

    // Build a 5 KiB token (well over the 4 KiB ceiling).
    const huge = try allocator.alloc(u8, 5 * 1024);
    defer allocator.free(huge);
    @memset(huge, 'A');

    var body_buf: std.ArrayList(u8) = .{};
    defer body_buf.deinit(allocator);
    try body_buf.print(allocator, "{{\"cert_id\":\"{s}\",\"platform\":\"apns\",\"token\":\"", .{setup.cert_id});
    try body_buf.appendSlice(allocator, huge);
    try body_buf.appendSlice(allocator, "\"}");

    var result = try push_register_http.acceptPost(&setup.acceptor, setup.bearer_hex[0..], body_buf.items);
    defer result.deinit(allocator);
    try std.testing.expectEqual(push_register_http.AcceptResultKind.token_too_large, result.kind);
    try std.testing.expectEqual(std.http.Status.payload_too_large, result.kind.httpStatus());
}

test "POST /api/v1/push-register: unknown cert_id surfaces unauthorised" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "op-root-bad-cert-pr");
    defer setup.deinit();

    const body =
        \\{"cert_id":"00000000000000000000000000000000","platform":"apns","token":"tok"}
    ;
    var result = try push_register_http.acceptPost(&setup.acceptor, setup.bearer_hex[0..], body);
    defer result.deinit(allocator);
    try std.testing.expectEqual(push_register_http.AcceptResultKind.unauthorised, result.kind);
}

test "DELETE /api/v1/push-register: clears tokens + flips push_platform back to none" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator, "op-root-delete-pr");
    defer setup.deinit();

    // Pre-populate a registration so DELETE has something to clear.
    var post_body: std.ArrayList(u8) = .{};
    defer post_body.deinit(allocator);
    try post_body.print(allocator,
        "{{\"cert_id\":\"{s}\",\"platform\":\"apns\",\"token\":\"tok-to-clear\"}}",
        .{setup.cert_id});
    var post_res = try push_register_http.acceptPost(&setup.acceptor, setup.bearer_hex[0..], post_body.items);
    post_res.deinit(allocator);

    var del_body: std.ArrayList(u8) = .{};
    defer del_body.deinit(allocator);
    try del_body.print(allocator, "{{\"cert_id\":\"{s}\"}}", .{setup.cert_id});

    var result = try push_register_http.acceptDelete(&setup.acceptor, setup.bearer_hex[0..], del_body.items);
    defer result.deinit(allocator);
    try std.testing.expectEqual(push_register_http.AcceptResultKind.unregistered, result.kind);

    const reloaded = try setup.certs.get(&setup.cert_id);
    try std.testing.expectEqual(identity_certs.PushPlatform.none, reloaded.push_platform);
    try std.testing.expectEqualStrings("", reloaded.apns_token);
    try std.testing.expectEqualStrings("", reloaded.push_registered_at);
}

// Touch bsvz to force its inclusion on the unit-test target — needed
// transitively via bkds.deriveChildPubkey.
comptime {
    _ = bsvz;
}

```
