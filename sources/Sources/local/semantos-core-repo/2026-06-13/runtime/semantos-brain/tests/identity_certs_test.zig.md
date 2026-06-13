---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/identity_certs_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.203652+00:00
---

# runtime/semantos-brain/tests/identity_certs_test.zig

```zig
// D-O5m.followup-9 Phase A — push-token substrate tests for the
// identity-cert store.  Validates the four new fields + updatePushToken
// + log replay + backward-compat parsing of legacy records that
// pre-date the schema bump.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §D-O5m.followup-9
// Phase A (substrate scope: schema + register endpoint + event flag,
// no transports).

const std = @import("std");
const bkds = @import("bkds");
const identity_certs = @import("identity_certs");

fn pinnedClock() i64 {
    return 1_700_000_000;
}

test "push schema: round-trip apns_token through log replay" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    const root_priv = bkds.privFromSeed("op-root-apns-roundtrip");
    const root_pub = try bkds.pubFromSeed("op-root-apns-roundtrip");
    const device_pub = try bkds.pubFromSeed("device-apns");
    const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x10, "phone");

    {
        var store = try identity_certs.CertStore.init(allocator, real, pinnedClock);
        defer store.deinit();
        const root = try store.issueRoot(root_pub, "operator");
        const child = try store.issueChild(&root.id, 0x10, child_pub, &.{}, "phone");
        try store.updatePushToken(
            &child.id,
            .apns,
            "apns-device-token-deadbeef",
            "2026-05-02T10:00:00Z",
        );
    }

    var store2 = try identity_certs.CertStore.init(allocator, real, pinnedClock);
    defer store2.deinit();
    const child_id = identity_certs.certIdFromPubkey(child_pub);
    const reloaded = try store2.get(&child_id);
    try std.testing.expectEqual(identity_certs.PushPlatform.apns, reloaded.push_platform);
    try std.testing.expectEqualStrings("apns-device-token-deadbeef", reloaded.apns_token);
    try std.testing.expectEqualStrings("", reloaded.fcm_token);
    try std.testing.expectEqualStrings("2026-05-02T10:00:00Z", reloaded.push_registered_at);
}

test "push schema: round-trip fcm_token through log replay" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    const root_priv = bkds.privFromSeed("op-root-fcm-roundtrip");
    const root_pub = try bkds.pubFromSeed("op-root-fcm-roundtrip");
    const device_pub = try bkds.pubFromSeed("device-fcm");
    const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x11, "android");

    {
        var store = try identity_certs.CertStore.init(allocator, real, pinnedClock);
        defer store.deinit();
        const root = try store.issueRoot(root_pub, "operator");
        const child = try store.issueChild(&root.id, 0x11, child_pub, &.{}, "android");
        try store.updatePushToken(
            &child.id,
            .fcm,
            "fcm-registration-token-cafebabe",
            "2026-05-02T11:00:00Z",
        );
    }

    var store2 = try identity_certs.CertStore.init(allocator, real, pinnedClock);
    defer store2.deinit();
    const child_id = identity_certs.certIdFromPubkey(child_pub);
    const reloaded = try store2.get(&child_id);
    try std.testing.expectEqual(identity_certs.PushPlatform.fcm, reloaded.push_platform);
    try std.testing.expectEqualStrings("", reloaded.apns_token);
    try std.testing.expectEqualStrings("fcm-registration-token-cafebabe", reloaded.fcm_token);
    try std.testing.expectEqualStrings("2026-05-02T11:00:00Z", reloaded.push_registered_at);
}

test "push schema: backward-compat — legacy record without push fields parses cleanly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    // Stamp out a legacy log file by hand — exact shape that pre-
    // followup-9 brain would have written (no push_token line, no push
    // fields anywhere on the issue lines).
    const log_path = try std.fs.path.join(allocator, &.{ real, "identity-certs.log" });
    defer allocator.free(log_path);
    const root_pub_hex = "02000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000a";
    // 33-byte compressed pubkey hex: 66 chars total.  Build a synthetic
    // legacy line with the cert id derived from the pubkey above so it
    // matches what certIdFromPubkey would produce.
    var pub_bytes: [bkds.KEY_LEN]u8 = undefined;
    try bkds.hexDecode(root_pub_hex[0 .. bkds.KEY_LEN * 2], &pub_bytes);
    const legacy_id = identity_certs.certIdFromPubkey(pub_bytes);

    const file = try std.fs.cwd().createFile(log_path, .{});
    var pub_hex_short: [bkds.KEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&pub_bytes, &pub_hex_short);
    var line_buf: [512]u8 = undefined;
    const line = try std.fmt.bufPrint(
        &line_buf,
        "{{\"ts\":1700000000,\"kind\":\"root\",\"cert_id\":\"{s}\",\"pubkey\":\"{s}\",\"label\":\"legacy-operator\",\"issued_at\":1700000000}}\n",
        .{ legacy_id, pub_hex_short },
    );
    try file.writeAll(line);
    file.close();

    var store = try identity_certs.CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();
    try std.testing.expectEqual(@as(usize, 1), store.count());
    const rec = try store.get(&legacy_id);
    try std.testing.expectEqual(identity_certs.PushPlatform.none, rec.push_platform);
    try std.testing.expectEqualStrings("", rec.apns_token);
    try std.testing.expectEqualStrings("", rec.fcm_token);
    try std.testing.expectEqualStrings("", rec.up_endpoint);
    try std.testing.expectEqualStrings("", rec.push_registered_at);
    try std.testing.expectEqualStrings("legacy-operator", rec.label);
}

test "updatePushToken: happy path on existing cert" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    var store = try identity_certs.CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();
    const root_priv = bkds.privFromSeed("op-root-update");
    const root_pub = try bkds.pubFromSeed("op-root-update");
    const device_pub = try bkds.pubFromSeed("device-update");
    const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x10, "phone");

    const root = try store.issueRoot(root_pub, "operator");
    const child = try store.issueChild(&root.id, 0x10, child_pub, &.{}, "phone");
    try store.updatePushToken(&child.id, .apns, "first-token", "2026-05-02T10:00:00Z");

    const after = try store.get(&child.id);
    try std.testing.expectEqual(identity_certs.PushPlatform.apns, after.push_platform);
    try std.testing.expectEqualStrings("first-token", after.apns_token);

    // A second call replaces the token without leaking the old one.
    try store.updatePushToken(&child.id, .apns, "second-token", "2026-05-02T11:00:00Z");
    const after2 = try store.get(&child.id);
    try std.testing.expectEqualStrings("second-token", after2.apns_token);
    try std.testing.expectEqualStrings("2026-05-02T11:00:00Z", after2.push_registered_at);

    // Switching platform clears the old token.
    try store.updatePushToken(&child.id, .fcm, "fcm-token", "2026-05-02T12:00:00Z");
    const after3 = try store.get(&child.id);
    try std.testing.expectEqual(identity_certs.PushPlatform.fcm, after3.push_platform);
    try std.testing.expectEqualStrings("", after3.apns_token);
    try std.testing.expectEqualStrings("fcm-token", after3.fcm_token);

    // Unregister via platform=.none clears both tokens + the timestamp.
    try store.updatePushToken(&child.id, .none, "", "");
    const after4 = try store.get(&child.id);
    try std.testing.expectEqual(identity_certs.PushPlatform.none, after4.push_platform);
    try std.testing.expectEqualStrings("", after4.apns_token);
    try std.testing.expectEqualStrings("", after4.fcm_token);
    try std.testing.expectEqualStrings("", after4.push_registered_at);
}

test "updatePushToken: unknown cert_id surfaces typed cert_not_found" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    var store = try identity_certs.CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();

    try std.testing.expectError(
        identity_certs.CertError.cert_not_found,
        store.updatePushToken("00000000000000000000000000000000", .apns, "tok", "2026-05-02T10:00:00Z"),
    );
    // Wrong cert_id length.
    try std.testing.expectError(
        identity_certs.CertError.cert_not_found,
        store.updatePushToken("short", .apns, "tok", "2026-05-02T10:00:00Z"),
    );
}

test "PushPlatform: wireName + fromWireName round-trip" {
    try std.testing.expectEqualStrings("none", identity_certs.PushPlatform.none.wireName());
    try std.testing.expectEqualStrings("apns", identity_certs.PushPlatform.apns.wireName());
    try std.testing.expectEqualStrings("fcm", identity_certs.PushPlatform.fcm.wireName());
    try std.testing.expectEqualStrings("unifiedpush", identity_certs.PushPlatform.unifiedpush.wireName());
    try std.testing.expectEqual(@as(?identity_certs.PushPlatform, .apns), identity_certs.PushPlatform.fromWireName("apns"));
    try std.testing.expectEqual(@as(?identity_certs.PushPlatform, .fcm), identity_certs.PushPlatform.fromWireName("fcm"));
    try std.testing.expectEqual(@as(?identity_certs.PushPlatform, .unifiedpush), identity_certs.PushPlatform.fromWireName("unifiedpush"));
    try std.testing.expectEqual(@as(?identity_certs.PushPlatform, .none), identity_certs.PushPlatform.fromWireName("none"));
    try std.testing.expectEqual(@as(?identity_certs.PushPlatform, null), identity_certs.PushPlatform.fromWireName("oops"));
}

// Sovereign-push D.3 — round-trip a unifiedpush registration through
// the log replay.  The `token` parameter on updatePushToken is
// re-purposed as the distributor endpoint URL when platform =
// .unifiedpush; the store persists it onto `up_endpoint` (not
// fcm_token / apns_token) and replay rebuilds the same shape.
test "push schema: round-trip up_endpoint through log replay" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    const root_priv = bkds.privFromSeed("op-root-up-roundtrip");
    const root_pub = try bkds.pubFromSeed("op-root-up-roundtrip");
    const device_pub = try bkds.pubFromSeed("device-up");
    const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x13, "phone");
    const endpoint = "https://ntfy.example.org/UPxyzABC123";

    {
        var store = try identity_certs.CertStore.init(allocator, real, pinnedClock);
        defer store.deinit();
        const root = try store.issueRoot(root_pub, "operator");
        const child = try store.issueChild(&root.id, 0x13, child_pub, &.{}, "phone");
        try store.updatePushToken(&child.id, .unifiedpush, endpoint, "2026-05-02T13:00:00Z");
    }

    var store2 = try identity_certs.CertStore.init(allocator, real, pinnedClock);
    defer store2.deinit();
    const child_id = identity_certs.certIdFromPubkey(child_pub);
    const reloaded = try store2.get(&child_id);
    try std.testing.expectEqual(identity_certs.PushPlatform.unifiedpush, reloaded.push_platform);
    try std.testing.expectEqualStrings("", reloaded.apns_token);
    try std.testing.expectEqualStrings("", reloaded.fcm_token);
    try std.testing.expectEqualStrings(endpoint, reloaded.up_endpoint);
    try std.testing.expectEqualStrings("2026-05-02T13:00:00Z", reloaded.push_registered_at);
}

// Sovereign-push D.3 — switching platform from unifiedpush back to
// fcm clears the up_endpoint, and unregister wipes everything.
test "updatePushToken: switching from unifiedpush to fcm clears up_endpoint" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    var store = try identity_certs.CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();
    const root_priv = bkds.privFromSeed("op-root-up-switch");
    const root_pub = try bkds.pubFromSeed("op-root-up-switch");
    const device_pub = try bkds.pubFromSeed("device-up-switch");
    const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x13, "phone");

    const root = try store.issueRoot(root_pub, "operator");
    const child = try store.issueChild(&root.id, 0x13, child_pub, &.{}, "phone");

    try store.updatePushToken(&child.id, .unifiedpush, "https://ntfy.example/UP-A", "2026-05-02T10:00:00Z");
    const after_up = try store.get(&child.id);
    try std.testing.expectEqual(identity_certs.PushPlatform.unifiedpush, after_up.push_platform);
    try std.testing.expectEqualStrings("https://ntfy.example/UP-A", after_up.up_endpoint);

    try store.updatePushToken(&child.id, .fcm, "fcm-tok", "2026-05-02T11:00:00Z");
    const after_fcm = try store.get(&child.id);
    try std.testing.expectEqual(identity_certs.PushPlatform.fcm, after_fcm.push_platform);
    try std.testing.expectEqualStrings("", after_fcm.up_endpoint);
    try std.testing.expectEqualStrings("fcm-tok", after_fcm.fcm_token);

    try store.updatePushToken(&child.id, .none, "", "");
    const after_none = try store.get(&child.id);
    try std.testing.expectEqual(identity_certs.PushPlatform.none, after_none.push_platform);
    try std.testing.expectEqualStrings("", after_none.up_endpoint);
    try std.testing.expectEqualStrings("", after_none.fcm_token);
    try std.testing.expectEqualStrings("", after_none.apns_token);
}

```
