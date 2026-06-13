---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/auth_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.171368+00:00
---

# runtime/semantos-brain/tests/auth_handler_conformance.zig

```zig
// Phase WSITE3 — auth handler conformance tests.

const std = @import("std");
const build_options = @import("build_options");
const auth_handler = @import("auth_handler");
const site_config = @import("site_config");

fn tempPath(name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return std.fs.path.join(allocator, &.{ real, name });
}

var pinned_clock: i64 = 1_700_000_000;
fn fixedClock() i64 {
    return pinned_clock;
}

// ─────────────────────────────────────────────────────────────────────
// Cookie + helpers
// ─────────────────────────────────────────────────────────────────────

test "WSITE3 cookies: extractCookie pulls a named cookie" {
    const v = auth_handler.extractCookie("a=1; __semantos_session=abc; b=2", "__semantos_session");
    try std.testing.expect(v != null);
    try std.testing.expectEqualStrings("abc", v.?);
}

test "WSITE3 cookies: extractCookie returns null for missing name" {
    try std.testing.expect(auth_handler.extractCookie("a=1; b=2", "missing") == null);
}

test "WSITE3 hex: hex round-trip" {
    const original: [4]u8 = .{ 0xab, 0x01, 0xff, 0x10 };
    var hex_buf: [8]u8 = undefined;
    auth_handler.hexEncode(&original, &hex_buf);
    try std.testing.expectEqualStrings("ab01ff10", &hex_buf);
    var back: [4]u8 = undefined;
    try auth_handler.hexDecode(&hex_buf, &back);
    try std.testing.expectEqualSlices(u8, &original, &back);
}

// ─────────────────────────────────────────────────────────────────────
// SessionStore
// ─────────────────────────────────────────────────────────────────────

test "WSITE3 store: issueChallenge persists, lookup finds it" {
    const path = try tempPath("ss-test.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
    defer store.deinit();
    store.setClockFn(fixedClock);

    const nonce = try store.issueChallenge("/play");
    try std.testing.expect(nonce.len > 0);
    const found = store.lookupChallenge(nonce);
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("/play", found.?.return_to);
}

test "WSITE3 store: expired challenges are GC'd" {
    const path = try tempPath("ss-exp.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
    defer store.deinit();
    store.setClockFn(fixedClock);

    const nonce_owned = try std.testing.allocator.dupe(u8, try store.issueChallenge("/play"));
    defer std.testing.allocator.free(nonce_owned);
    pinned_clock += 5 * 60 + 1;
    try std.testing.expect(store.lookupChallenge(nonce_owned) == null);
    pinned_clock = 1_700_000_000;
}

test "WSITE3 store: mintSession + lookupSession round-trip" {
    const path = try tempPath("ss-mint.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
    defer store.deinit();
    store.setClockFn(fixedClock);

    const pk: [33]u8 = .{0xab} ** 33;
    const session = try store.mintSession(pk, 3600, "/play");
    const found = store.lookupSession(session.id) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, &pk, &found.pubkey);
    try std.testing.expectEqualStrings("/play", found.return_to);
    try std.testing.expectEqual(@as(i64, 1_700_000_000 + 3600), found.expires_at);
}

test "WSITE3 store: revokeSession removes the entry" {
    const path = try tempPath("ss-rev.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
    defer store.deinit();
    store.setClockFn(fixedClock);

    const pk: [33]u8 = .{0xab} ** 33;
    const session = try store.mintSession(pk, 3600, "/play");
    store.revokeSession(session.id);
    try std.testing.expect(store.lookupSession(session.id) == null);
}

// ─────────────────────────────────────────────────────────────────────
// WSITE5 — session log replay + revoke persistence
// ─────────────────────────────────────────────────────────────────────

test "WSITE5 store: sessions survive a reopen via log replay" {
    const path = try tempPath("ss-replay.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    pinned_clock = 1_700_000_000;
    const pk: [33]u8 = .{0xee} ** 33;
    var session_id: [32]u8 = undefined;

    {
        var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
        defer store.deinit();
        store.setClockFn(fixedClock);
        const session = try store.mintSession(pk, 3600, "/replay");
        session_id = session.id;
    }
    {
        var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
        defer store.deinit();
        store.setClockFn(fixedClock);
        const found = store.lookupSession(session_id) orelse return error.TestFailed;
        try std.testing.expectEqualStrings("/replay", found.return_to);
        try std.testing.expectEqualSlices(u8, &pk, &found.pubkey);
    }
}

test "WSITE5 store: revokes are persisted across reopens" {
    const path = try tempPath("ss-revoke-persist.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    pinned_clock = 1_700_000_000;
    const pk: [33]u8 = .{0xab} ** 33;
    var session_id: [32]u8 = undefined;
    {
        var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
        defer store.deinit();
        store.setClockFn(fixedClock);
        const session = try store.mintSession(pk, 3600, "/x");
        session_id = session.id;
        store.revokeSession(session.id);
    }
    {
        var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
        defer store.deinit();
        store.setClockFn(fixedClock);
        try std.testing.expect(store.lookupSession(session_id) == null);
    }
}

test "WSITE5 store: replay drops sessions past their expiry" {
    const path = try tempPath("ss-expired-replay.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    pinned_clock = 1_700_000_000;
    var session_id: [32]u8 = undefined;
    {
        var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
        defer store.deinit();
        store.setClockFn(fixedClock);
        const pk: [33]u8 = .{0xab} ** 33;
        const session = try store.mintSession(pk, 60, "/x");
        session_id = session.id;
    }
    // Jump 2h forward — session was 60s TTL.
    pinned_clock = 1_700_000_000 + 2 * 60 * 60;
    var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
    defer store.deinit();
    store.setClockFn(fixedClock);
    try std.testing.expect(store.lookupSession(session_id) == null);
    pinned_clock = 1_700_000_000;
}

test "WSITE5 store: activeSessionsAlloc returns only unexpired" {
    const path = try tempPath("ss-active.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    pinned_clock = 1_700_000_000;
    var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
    defer store.deinit();
    store.setClockFn(fixedClock);

    const pk: [33]u8 = .{0xaa} ** 33;
    _ = try store.mintSession(pk, 3600, "/active");
    _ = try store.mintSession(pk, 3600, "/another");

    const list = try store.activeSessionsAlloc(std.testing.allocator);
    defer auth_handler.freeSessionList(std.testing.allocator, list);
    try std.testing.expectEqual(@as(usize, 2), list.len);
}

// ─────────────────────────────────────────────────────────────────────
// Cookie HMAC
// ─────────────────────────────────────────────────────────────────────

test "WSITE3 cookie: HMAC round-trips through formatSessionCookie + verifySessionCookie" {
    const path = try tempPath("ss-cookie.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
    defer store.deinit();
    store.setClockFn(fixedClock);

    const secret: [32]u8 = .{0xcd} ** 32;
    const pk: [33]u8 = .{0xab} ** 33;
    const session = try store.mintSession(pk, 3600, "/play");

    var buf: [256]u8 = undefined;
    const cookie = try auth_handler.formatSessionCookie(secret, &session, &buf);
    try std.testing.expectEqual(@as(usize, 129), cookie.len);

    const verified = auth_handler.verifySessionCookie(secret, cookie, &store) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, &session.id, &verified.id);
}

test "WSITE3 cookie: tampered MAC is rejected" {
    const path = try tempPath("ss-tamp.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var store = try auth_handler.SessionStore.init(std.testing.allocator, path);
    defer store.deinit();
    store.setClockFn(fixedClock);

    const secret: [32]u8 = .{0xcd} ** 32;
    const pk: [33]u8 = .{0xab} ** 33;
    const session = try store.mintSession(pk, 3600, "/play");

    var buf: [256]u8 = undefined;
    const cookie = try auth_handler.formatSessionCookie(secret, &session, &buf);
    var tampered: [129]u8 = undefined;
    @memcpy(&tampered, cookie);
    tampered[100] ^= 0xff;
    try std.testing.expect(auth_handler.verifySessionCookie(secret, &tampered, &store) == null);
}

// ─────────────────────────────────────────────────────────────────────
// Callback parser
// ─────────────────────────────────────────────────────────────────────

test "WSITE3 callback: parses well-formed body" {
    const body =
        \\{
        \\  "pubkey":    "020202020202020202020202020202020202020202020202020202020202020202",
        \\  "signature": "abcd",
        \\  "nonce":     "n0ncE",
        \\  "return_to": "/play"
        \\}
    ;
    var cb = try auth_handler.parseCallback(std.testing.allocator, body);
    defer cb.deinit();
    try std.testing.expectEqualStrings("n0ncE", cb.nonce);
    try std.testing.expectEqualStrings("/play", cb.return_to);
    try std.testing.expectEqual(@as(u8, 0x02), cb.pubkey[0]);
    try std.testing.expectEqual(@as(usize, 2), cb.signature.len);
}

test "WSITE3 callback: rejects malformed JSON" {
    try std.testing.expectError(
        error.SyntaxError,
        auth_handler.parseCallback(std.testing.allocator, "{ bad"),
    );
}

test "WSITE3 callback: rejects bad pubkey length" {
    const body =
        \\{ "pubkey": "0202", "signature": "abcd", "nonce": "n", "return_to": "/" }
    ;
    try std.testing.expectError(
        error.bad_callback_body,
        auth_handler.parseCallback(std.testing.allocator, body),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Signature verification (gated on bsvz)
// ─────────────────────────────────────────────────────────────────────

test "WSITE3 verify: stub mode returns signature_verification_unavailable" {
    if (build_options.enable_wasmtime) return error.SkipZigTest;
    const pk: [33]u8 = .{0x02} ** 33;
    const sig = [_]u8{0xab} ** 8;
    try std.testing.expectError(
        error.signature_verification_unavailable,
        auth_handler.verifySignatureOverNonce(pk, "nonce", &sig),
    );
}

test "WSITE3 verify: real path — signed nonce verifies under matching pubkey" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const bsvz = @import("bsvz");
    const sk: [32]u8 = .{0x01} ** 32;
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(sk);
    const pub_key = try priv.publicKey();
    const compressed = pub_key.inner.toCompressedSec1();

    const nonce = "test-nonce-123";
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(nonce, &digest, .{});
    const der_sig = try priv.signDigest(digest);
    const der_bytes = der_sig.bytes[0..der_sig.len];

    const ok = try auth_handler.verifySignatureOverNonce(compressed, nonce, der_bytes);
    try std.testing.expect(ok);
}

test "WSITE3 verify: real path — wrong pubkey rejects" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const bsvz = @import("bsvz");
    const sk: [32]u8 = .{0x01} ** 32;
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(sk);

    const nonce = "test-nonce-123";
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(nonce, &digest, .{});
    const der_sig = try priv.signDigest(digest);

    const wrong_sk: [32]u8 = .{0x02} ** 32;
    const wrong_priv = try bsvz.primitives.ec.PrivateKey.fromBytes(wrong_sk);
    const wrong_pk = try wrong_priv.publicKey();

    const ok = try auth_handler.verifySignatureOverNonce(
        wrong_pk.inner.toCompressedSec1(),
        nonce,
        der_sig.bytes[0..der_sig.len],
    );
    try std.testing.expect(!ok);
}

// ─────────────────────────────────────────────────────────────────────
// WSITE4 — payment claim parsing + signature
// ─────────────────────────────────────────────────────────────────────

test "WSITE4 callback: parses optional payment claim" {
    const body =
        \\{
        \\  "pubkey":    "020202020202020202020202020202020202020202020202020202020202020202",
        \\  "signature": "abcd",
        \\  "nonce":     "n0ncE",
        \\  "return_to": "/premium",
        \\  "payment":   { "txid": "abababababababababababababababababababababababababababababababab",
        \\                  "satoshis": 5000 }
        \\}
    ;
    var cb = try auth_handler.parseCallback(std.testing.allocator, body);
    defer cb.deinit();
    try std.testing.expect(cb.payment != null);
    try std.testing.expectEqual(@as(u64, 5000), cb.payment.?.satoshis);
    try std.testing.expectEqualStrings(
        "abababababababababababababababababababababababababababababababab",
        &cb.payment.?.txid_hex,
    );
}

test "WSITE4 callback: rejects bad txid length" {
    const body =
        \\{
        \\  "pubkey":    "020202020202020202020202020202020202020202020202020202020202020202",
        \\  "signature": "abcd",
        \\  "nonce":     "n",
        \\  "return_to": "/p",
        \\  "payment":   { "txid": "ab", "satoshis": 100 }
        \\}
    ;
    try std.testing.expectError(
        error.bad_callback_body,
        auth_handler.parseCallback(std.testing.allocator, body),
    );
}

test "WSITE4 verify: payment signature commits to (nonce, txid, sats)" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const bsvz = @import("bsvz");
    const sk: [32]u8 = .{0x01} ** 32;
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(sk);
    const pub_key = try priv.publicKey();
    const compressed = pub_key.inner.toCompressedSec1();

    const nonce = "test-nonce";
    var txid_hex: [64]u8 = undefined;
    @memset(&txid_hex, 'a');
    const sats: u64 = 5000;

    var txid_raw: [32]u8 = undefined;
    try auth_handler.hexDecode(&txid_hex, &txid_raw);
    var sats_le: [8]u8 = undefined;
    std.mem.writeInt(u64, &sats_le, sats, .little);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(nonce);
    hasher.update(&txid_raw);
    hasher.update(&sats_le);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const der_sig = try priv.signDigest(digest);

    const ok = try auth_handler.verifyPaymentSignature(
        compressed, nonce, txid_hex, sats, der_sig.bytes[0..der_sig.len],
    );
    try std.testing.expect(ok);
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-2 — helm-bearer cookie shape
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-2 helm-bearer cookie: emits __semantos_helm_bearer with non-HttpOnly attrs" {
    var buf: [256]u8 = undefined;
    const hex_token = "deadbeef" ** 8; // 64-hex bearer
    const hdr = try auth_handler.formatHelmBearerCookie(hex_token, 3600, &buf);

    // Cookie name + value + Path=/ + SameSite=Lax + Max-Age must all be present.
    try std.testing.expect(std.mem.startsWith(u8, hdr, "__semantos_helm_bearer="));
    try std.testing.expect(std.mem.indexOf(u8, hdr, hex_token) != null);
    try std.testing.expect(std.mem.indexOf(u8, hdr, "Path=/") != null);
    try std.testing.expect(std.mem.indexOf(u8, hdr, "SameSite=Lax") != null);
    try std.testing.expect(std.mem.indexOf(u8, hdr, "Max-Age=3600") != null);
    // CRITICAL: the helm bearer cookie MUST NOT be HttpOnly — the
    // Svelte SPA reads it via document.cookie.  The session cookie
    // remains HttpOnly; that's a separate Set-Cookie line.
    try std.testing.expect(std.mem.indexOf(u8, hdr, "HttpOnly") == null);
}

test "D-O5.followup-2 helm-bearer cookie: ttl is honoured verbatim" {
    var buf: [256]u8 = undefined;
    const hex_token = "ab" ** 32; // 64-hex
    const hdr = try auth_handler.formatHelmBearerCookie(hex_token, 86_400, &buf);
    try std.testing.expect(std.mem.indexOf(u8, hdr, "Max-Age=86400") != null);
}

test "D-O5.followup-2 helm-bearer cookie: errors when buffer too small" {
    var buf: [16]u8 = undefined; // way too small for `__semantos_helm_bearer=` + token
    const hex_token = "ab" ** 32;
    try std.testing.expectError(
        error.NoSpaceLeft,
        auth_handler.formatHelmBearerCookie(hex_token, 3600, &buf),
    );
}

test "WSITE4 verify: tampered satoshis rejects payment signature" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;
    const bsvz = @import("bsvz");
    const sk: [32]u8 = .{0x01} ** 32;
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(sk);
    const pub_key = try priv.publicKey();

    const nonce = "test-nonce";
    var txid_hex: [64]u8 = undefined;
    @memset(&txid_hex, 'a');
    const sats: u64 = 5000;

    // Sign with sats=5000 but verify with sats=1.
    var txid_raw: [32]u8 = undefined;
    try auth_handler.hexDecode(&txid_hex, &txid_raw);
    var sats_le: [8]u8 = undefined;
    std.mem.writeInt(u64, &sats_le, sats, .little);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(nonce);
    hasher.update(&txid_raw);
    hasher.update(&sats_le);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const der_sig = try priv.signDigest(digest);

    const ok = try auth_handler.verifyPaymentSignature(
        pub_key.inner.toCompressedSec1(),
        nonce,
        txid_hex,
        1, // tampered
        der_sig.bytes[0..der_sig.len],
    );
    try std.testing.expect(!ok);
}

```
