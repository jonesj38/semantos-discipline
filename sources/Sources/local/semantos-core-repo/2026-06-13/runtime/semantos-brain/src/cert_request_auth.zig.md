---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cert_request_auth.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.226566+00:00
---

# runtime/semantos-brain/src/cert_request_auth.zig

```zig
// Tracker T7 — BRC-52 cert + capability request auth for the brain HTTP
// surface.
//
// Reference: docs/prd/PWA-BRAIN-WALLET-UNIFICATION.md §1 (the
//            operator/user trust model — this module is the
//            "access-isolation" half); [[brain_auth_model_intent]].
//
// ── What this replaces ───────────────────────────────────────────────
//
// Today every brain HTTP endpoint authenticates with ONE shared bearer
// token (a hex64 "helm session bearer", `bearer_tokens.TokenStore`).
// Whoever holds it has full access — there is NO operator-vs-user
// distinction at the HTTP boundary.
//
// ── The intended model ───────────────────────────────────────────────
//
// The brain pins ONE operator cert (its root cert, surfaced at
// `GET /api/v1/info` as `brain_pin_cert_id` + `brain_pin_pubkey`).  A
// caller proves control of a cert key by presenting:
//
//     X-Brain-Pubkey:   <66 hex chars>   (33-byte compressed-SEC1)
//     X-Brain-Cert-Sig: <128 hex chars>  (64-byte compact r‖s ECDSA)
//     X-Brain-Cert-Ts:  <unix-seconds>   (freshness anchor)
//
// The signature is over `challengeDigest(method, path, timestamp)` —
// SHA-256 over a domain-separated preimage that BINDS the credential to
// the specific request (method + path) and a timestamp.  This means a
// captured signature can't be replayed against a different route, and a
// stale signature (outside the skew window) is rejected.  Replay of the
// exact same (method, path, timestamp) within the skew window is the
// one residual window — a server-side nonce store would close it and is
// the noted hardening follow-on (kept out of v1 to stay stateless on
// the single-threaded reactor).
//
// Authorisation is capability-driven, reusing the brain's existing
// machinery:
//   • The cert's capabilities come from `identity_certs.CertStore`
//     (the same store the signer-cert mint path + `wss_operator_auth`
//     read).  The operator's root cert carries the admin capability
//     (granted at boot by `extensions.mintFirstBootCapabilities`); user
//     child certs do not.
//   • Capability matching reuses `dispatcher.impliesCapability` /
//     `CapabilitySet` — the canonical hierarchical dotted-namespace
//     matcher (`cap.brain.admin` implies `cap.brain.admin.*`).
//   • The signature-control check reuses the same recovery-loop ECDSA
//     scheme as `attachments_upload_http.verifyCellSignatureRecoveryLoop`
//     / `signed_bundle.zig` (the #828 signer-cert verification path).
//
// Routes are classified `admin` / `user` / `public` by `ROUTE_AUTH_
// POLICIES` (mirrors the `ROUTE_BODY_CAPS` table shape in the reactor).
// Admin routes require an admin cert; a verified non-admin cert is
// rejected (403) on them but allowed on user/public routes.
//
// ── Migration posture ────────────────────────────────────────────────
//
// This module is purely additive: it makes a DECISION from credentials,
// it does not itself replace the bearer path.  The reactor calls
// `authorizeFromHeaders` only when the cert headers are present; when
// they're absent the legacy bearer path still runs (so nothing breaks
// mid-transition).  Operators flip `BRAIN_REQUIRE_CERT_AUTH` / the
// server's `require_cert_auth` flag to retire the bearer fallback once
// every client presents a cert.

const std = @import("std");
const identity_certs = @import("identity_certs");
const dispatcher = @import("dispatcher");
const bkds = @import("bkds");
const bsvz = @import("bsvz");

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

/// The admin capability string.  Matches the REPL dispatcher surface
/// (`cells_mint_handler.capForCmd`, `cell_handler`, `modules_handler`)
/// so the HTTP boundary and the dispatcher boundary gate on the SAME
/// capability — one admin cap, two transports.
pub const ADMIN_CAPABILITY = "cap.brain.admin";

/// Header the caller presents its 33-byte compressed-SEC1 pubkey under
/// (66 lowercase hex chars).  Same header `wss_operator_auth` uses, so a
/// client speaks one identity header across HTTP + WSS.
pub const PUBKEY_HEADER = "x-brain-pubkey";
/// Header carrying the 64-byte compact r‖s signature (128 hex chars).
pub const SIG_HEADER = "x-brain-cert-sig";
/// Header carrying the client's unix-seconds timestamp (freshness anchor).
pub const TIMESTAMP_HEADER = "x-brain-cert-ts";

/// Domain separator mixed into the challenge preimage so a brain
/// cert-auth signature can never collide with a signature produced for
/// some other purpose (cell-payload sigs, transcript sigs, etc.).
pub const CHALLENGE_DOMAIN = "brain-cert-auth-v1";

/// Default freshness window (seconds) either side of the server clock a
/// credential timestamp may fall in.  ±5 minutes tolerates modest clock
/// skew without leaving a wide replay window.
pub const DEFAULT_MAX_SKEW_SECS: i64 = 300;

const SIG_LEN = 64;
const PUBKEY_HEX_LEN = bkds.KEY_LEN * 2; // 66
const SIG_HEX_LEN = SIG_LEN * 2; // 128

// ─────────────────────────────────────────────────────────────────────
// Route policy
// ─────────────────────────────────────────────────────────────────────

/// How sensitive a route is.  `admin` requires the admin capability;
/// `user` accepts any verified cert; `public` accepts a verified cert
/// (and is reachable without one via the legacy bearer / open path).
pub const RouteClass = enum { admin, user, public };

pub const RoutePolicy = struct {
    /// Route path (or path prefix when `prefix` is true).
    path: []const u8,
    /// When true, match `std.mem.startsWith(path, entry.path)`.
    prefix: bool = false,
    class: RouteClass,
};

/// Per-route auth-class table.  Mirrors the `ROUTE_BODY_CAPS` table in
/// `site_server/reactor.zig` — one declarative row per route.  Anything
/// NOT listed defaults to `admin` (deny-by-default for a non-admin cert):
/// the brain HTTP surface is overwhelmingly an operator console, so the
/// safe default is "operator only".  Add a `user` / `public` row when a
/// route is genuinely field-app facing.
///
/// More-specific (longer) entries should precede broader prefixes so
/// `classifyRoute` returns the tightest match.
pub const ROUTE_AUTH_POLICIES = [_]RoutePolicy{
    // ── user / public surface — reachable by a non-admin field cert ──
    // Brain discovery: a paired field device fetches /info post-pairing
    // to learn the mesh config + re-assert its TOFU pin.  Read-only,
    // no admin authority — a non-operator cert is allowed here.
    .{ .path = "/api/v1/info", .class = .user },
    // Device-pairing handshake: BY DEFINITION reached before the device
    // holds any operator authority.  User-class.
    .{ .path = "/api/v1/device-pair", .class = .user },
    // Customer link resolution (public landing pages).
    .{ .path = "/api/v1/c/", .prefix = true, .class = .public },

    // ── admin surface — operator cert (admin capability) required ────
    // Generic cell mint — the canonical sovereign write path.
    .{ .path = "/api/v1/cells", .prefix = true, .class = .admin },
    .{ .path = "/api/v1/cell/", .prefix = true, .class = .admin },
    .{ .path = "/api/v1/repl", .class = .admin },
    // Operator sign-as-operator — rtc.jingle / SignedBundle signing (helm).
    .{ .path = "/api/v1/bundle/sign", .class = .admin },
    .{ .path = "/api/v1/attachments/upload", .class = .admin },
    .{ .path = "/api/v1/events", .class = .admin },
    .{ .path = "/api/v1/voice-extract", .class = .admin },
    .{ .path = "/api/v1/voice-note", .class = .admin },
    .{ .path = "/api/v1/self-sweep", .class = .admin },
    .{ .path = "/api/v1/betterment-sweep", .class = .admin },
};

/// Classify a route by path.  Returns the class of the longest matching
/// policy entry; `admin` (deny-by-default) when nothing matches.
pub fn classifyRoute(path: []const u8) RouteClass {
    var best_len: usize = 0;
    var best: RouteClass = .admin;
    for (ROUTE_AUTH_POLICIES) |p| {
        const matches = if (p.prefix)
            std.mem.startsWith(u8, path, p.path)
        else
            std.mem.eql(u8, path, p.path);
        if (matches and p.path.len >= best_len) {
            best_len = p.path.len;
            best = p.class;
        }
    }
    return best;
}

// ─────────────────────────────────────────────────────────────────────
// Credential
// ─────────────────────────────────────────────────────────────────────

pub const Credential = struct {
    /// 33-byte compressed-SEC1 pubkey the caller claims.
    pubkey: [bkds.KEY_LEN]u8,
    /// cert id derived from `pubkey` (sha256(pubkey)[0..16] hex).  Used
    /// to select the stored cert record; control is then verified
    /// against that record's pubkey, never the presented one alone.
    cert_id: [identity_certs.CERT_ID_HEX_LEN]u8,
    /// 64-byte compact r‖s ECDSA signature over the challenge digest.
    signature: [SIG_LEN]u8,
    /// Client's unix-seconds timestamp (the freshness anchor mixed into
    /// the challenge preimage).
    timestamp: i64,
};

pub const ParseError = error{
    missing_pubkey,
    bad_pubkey,
    missing_sig,
    bad_sig,
    missing_timestamp,
    bad_timestamp,
};

/// Parse the three cert-auth headers into a `Credential`.  Any of the
/// header values may be null (header absent) — the caller passes through
/// `req.header(name)`.  Pure: derives `cert_id` from `pubkey`, does NOT
/// touch any store or clock.
pub fn parseCredential(
    pubkey_hex: ?[]const u8,
    sig_hex: ?[]const u8,
    timestamp_str: ?[]const u8,
) ParseError!Credential {
    const pk_hex = pubkey_hex orelse return ParseError.missing_pubkey;
    const s_hex = sig_hex orelse return ParseError.missing_sig;
    const ts_str = timestamp_str orelse return ParseError.missing_timestamp;

    if (pk_hex.len != PUBKEY_HEX_LEN) return ParseError.bad_pubkey;
    var pubkey: [bkds.KEY_LEN]u8 = undefined;
    bkds.hexDecode(pk_hex, &pubkey) catch return ParseError.bad_pubkey;

    if (s_hex.len != SIG_HEX_LEN) return ParseError.bad_sig;
    var signature: [SIG_LEN]u8 = undefined;
    bkds.hexDecode(s_hex, &signature) catch return ParseError.bad_sig;

    const timestamp = std.fmt.parseInt(i64, ts_str, 10) catch return ParseError.bad_timestamp;

    return .{
        .pubkey = pubkey,
        .cert_id = identity_certs.certIdFromPubkey(pubkey),
        .signature = signature,
        .timestamp = timestamp,
    };
}

/// Whether the cert-auth headers are present at all.  When false the
/// reactor falls back to the legacy bearer path.
pub fn hasCertHeaders(
    pubkey_hex: ?[]const u8,
    sig_hex: ?[]const u8,
    timestamp_str: ?[]const u8,
) bool {
    return pubkey_hex != null and sig_hex != null and timestamp_str != null;
}

// ─────────────────────────────────────────────────────────────────────
// Challenge + control-signature verification
// ─────────────────────────────────────────────────────────────────────

/// The digest the caller must sign to prove key control.  Domain-
/// separated + bound to (method, path, timestamp) so a captured
/// signature is useless on any other route / past its freshness window.
pub fn challengeDigest(method: []const u8, path: []const u8, timestamp: i64) [32]u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(CHALLENGE_DOMAIN);
    h.update("\n");
    h.update(method);
    h.update("\n");
    h.update(path);
    h.update("\n");
    var ts_buf: [24]u8 = undefined;
    const ts_slice = std.fmt.bufPrint(&ts_buf, "{d}", .{timestamp}) catch unreachable;
    h.update(ts_slice);
    var out: [32]u8 = undefined;
    h.final(&out);
    return out;
}

/// Recovery-loop ECDSA verify: does `signature` over `digest` recover to
/// `expected_pubkey`?  Mirrors `attachments_upload_http.
/// verifyCellSignatureRecoveryLoop` / `signed_bundle.zig` exactly (same
/// scheme used across the brain's signer-cert paths) — kept local so
/// this security-policy core doesn't pull a large HTTP module into its
/// dependency graph.
fn recoverMatches(
    signature: [SIG_LEN]u8,
    digest: [32]u8,
    expected_pubkey: [bkds.KEY_LEN]u8,
) bool {
    var candidate: [65]u8 = undefined;
    @memcpy(candidate[1..65], &signature);
    var rec: u8 = 31;
    while (rec <= 34) : (rec += 1) {
        candidate[0] = rec;
        const recovered = bsvz.crypto.compact.recoverCompactDigest256(candidate, digest) catch continue;
        const recovered_sec1 = recovered.pubkey.toCompressedSec1();
        if (std.crypto.timing_safe.eql([bkds.KEY_LEN]u8, recovered_sec1, expected_pubkey)) return true;
    }
    return false;
}

/// Verify the credential's signature proves control of `expected_pubkey`
/// for this (method, path).  `expected_pubkey` is the TRUSTED stored
/// cert pubkey — the presented `cred.pubkey` only selects the cert.
pub fn verifyControl(
    cred: Credential,
    method: []const u8,
    path: []const u8,
    expected_pubkey: [bkds.KEY_LEN]u8,
) bool {
    const digest = challengeDigest(method, path, cred.timestamp);
    return recoverMatches(cred.signature, digest, expected_pubkey);
}

// ─────────────────────────────────────────────────────────────────────
// Decision
// ─────────────────────────────────────────────────────────────────────

pub const Decision = enum {
    /// Verified cert carrying the admin capability — full access.
    allow_admin,
    /// Verified non-admin cert on a user/public route — allowed.
    allow_user,
    /// No verifiable cert: missing/unknown cert, bad signature, or
    /// stale timestamp.  Maps to HTTP 401.
    deny_unauthenticated,
    /// Verified cert, but it lacks the capability this route requires
    /// (a field user hitting an admin route).  Maps to HTTP 403.
    deny_forbidden,

    pub fn isAllow(self: Decision) bool {
        return self == .allow_admin or self == .allow_user;
    }
};

/// Is this cert an admin?  True when it is the operator root cert (the
/// brain's pinned operator identity) OR it explicitly carries the admin
/// capability (a delegated admin child).  Capability matching uses the
/// canonical `dispatcher.impliesCapability` semantics.
pub fn isAdminCert(record: identity_certs.CertRecord) bool {
    if (record.kind == .root) return true;
    const set = dispatcher.CapabilitySet.fromList(record.capabilities);
    return set.contains(ADMIN_CAPABILITY);
}

/// Core decision.  Given a parsed credential + the request line + the
/// server clock, decide access.  Pure w.r.t. the clock (injected as
/// `now`) so it's deterministically testable.
///
/// Order matters: freshness → control signature (against the stored
/// cert's pubkey) → route-class capability.  An attacker who can't
/// produce a fresh, valid signature never reaches the capability stage.
pub fn authorize(
    store: *identity_certs.CertStore,
    cred: Credential,
    method: []const u8,
    path: []const u8,
    now: i64,
    max_skew_secs: i64,
) Decision {
    // 1. Freshness — reject timestamps outside the skew window.
    const delta = now - cred.timestamp;
    const abs_delta = if (delta < 0) -delta else delta;
    if (abs_delta > max_skew_secs) return .deny_unauthenticated;

    // 2. Resolve the stored cert by the id derived from the presented
    //    pubkey.  Unknown / revoked / malformed id → unauthenticated.
    const record = store.get(&cred.cert_id) catch return .deny_unauthenticated;

    // 3. Control: the signature must verify against the STORED cert's
    //    pubkey (not merely the presented one — defends against a forged
    //    credential whose cert_id collides but whose key differs).
    if (!verifyControl(cred, method, path, record.pubkey)) {
        return .deny_unauthenticated;
    }

    // 4. Capability gate by route class.
    return switch (classifyRoute(path)) {
        .admin => if (isAdminCert(record)) .allow_admin else .deny_forbidden,
        .user, .public => if (isAdminCert(record)) .allow_admin else .allow_user,
    };
}

/// Convenience: parse the three headers + authorize in one call.  Any
/// parse failure (missing/malformed header) maps to
/// `deny_unauthenticated` — the reactor only calls this when the cert
/// headers are present (see `hasCertHeaders`), so a parse failure here
/// means a malformed cert credential, which is a rejected request.
pub fn authorizeFromHeaders(
    store: *identity_certs.CertStore,
    pubkey_hex: ?[]const u8,
    sig_hex: ?[]const u8,
    timestamp_str: ?[]const u8,
    method: []const u8,
    path: []const u8,
    now: i64,
    max_skew_secs: i64,
) Decision {
    const cred = parseCredential(pubkey_hex, sig_hex, timestamp_str) catch
        return .deny_unauthenticated;
    return authorize(store, cred, method, path, now, max_skew_secs);
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn pinnedClock() i64 {
    return 1_700_000_000;
}

/// Build a keypair from a fixed 32-byte scalar via bsvz (so the pubkey
/// provably matches the signing key — independent of the bkds seed
/// derivation path).
const TestKey = struct {
    priv: bsvz.primitives.ec.PrivateKey,
    pubkey: [bkds.KEY_LEN]u8,

    fn fromScalar(scalar: [32]u8) !TestKey {
        const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(scalar);
        const pubkey = (try priv.publicKey()).toCompressedSec1();
        return .{ .priv = priv, .pubkey = pubkey };
    }

    /// Sign the cert-auth challenge for (method, path, timestamp),
    /// returning the 64-byte compact r‖s the client would present.
    fn signChallenge(self: TestKey, method: []const u8, path: []const u8, timestamp: i64) ![SIG_LEN]u8 {
        const digest = challengeDigest(method, path, timestamp);
        const compact = try self.priv.signCompact(digest, true);
        var sig: [SIG_LEN]u8 = undefined;
        @memcpy(&sig, compact[1..65]);
        return sig;
    }
};

fn makeStore(dir: []const u8) !identity_certs.CertStore {
    return identity_certs.CertStore.init(testing.allocator, dir, pinnedClock);
}

// ── route classification ──────────────────────────────────────────────

test "classifyRoute: admin routes" {
    try testing.expectEqual(RouteClass.admin, classifyRoute("/api/v1/cells"));
    try testing.expectEqual(RouteClass.admin, classifyRoute("/api/v1/repl"));
    try testing.expectEqual(RouteClass.admin, classifyRoute("/api/v1/cell/abcd"));
}

test "classifyRoute: user + public routes" {
    try testing.expectEqual(RouteClass.user, classifyRoute("/api/v1/info"));
    try testing.expectEqual(RouteClass.user, classifyRoute("/api/v1/device-pair"));
    try testing.expectEqual(RouteClass.public, classifyRoute("/api/v1/c/some-link"));
}

test "classifyRoute: unknown route defaults to admin (deny-by-default)" {
    try testing.expectEqual(RouteClass.admin, classifyRoute("/api/v1/totally-unknown"));
    try testing.expectEqual(RouteClass.admin, classifyRoute("/"));
}

// ── parsing ───────────────────────────────────────────────────────────

test "parseCredential: round-trips a well-formed credential" {
    const key = try TestKey.fromScalar([_]u8{0x11} ** 32);
    var pk_hex: [PUBKEY_HEX_LEN]u8 = undefined;
    bkds.hexEncode(&key.pubkey, &pk_hex);
    const sig = try key.signChallenge("POST", "/api/v1/cells", 1_700_000_000);
    var sig_hex: [SIG_HEX_LEN]u8 = undefined;
    bkds.hexEncode(&sig, &sig_hex);

    const cred = try parseCredential(&pk_hex, &sig_hex, "1700000000");
    try testing.expectEqualSlices(u8, &key.pubkey, &cred.pubkey);
    try testing.expectEqual(@as(i64, 1_700_000_000), cred.timestamp);
    try testing.expectEqualSlices(u8, &identity_certs.certIdFromPubkey(key.pubkey), &cred.cert_id);
}

test "parseCredential: missing headers" {
    try testing.expectError(ParseError.missing_pubkey, parseCredential(null, "a", "1"));
    try testing.expectError(ParseError.missing_sig, parseCredential("a" ** PUBKEY_HEX_LEN, null, "1"));
    try testing.expectError(ParseError.missing_timestamp, parseCredential("a" ** PUBKEY_HEX_LEN, "b" ** SIG_HEX_LEN, null));
}

test "parseCredential: malformed values" {
    try testing.expectError(ParseError.bad_pubkey, parseCredential("short", "b" ** SIG_HEX_LEN, "1"));
    try testing.expectError(ParseError.bad_sig, parseCredential("a" ** PUBKEY_HEX_LEN, "short", "1"));
    try testing.expectError(ParseError.bad_timestamp, parseCredential("a" ** PUBKEY_HEX_LEN, "b" ** SIG_HEX_LEN, "not-a-number"));
}

test "hasCertHeaders: all three required" {
    try testing.expect(hasCertHeaders("a", "b", "c"));
    try testing.expect(!hasCertHeaders(null, "b", "c"));
    try testing.expect(!hasCertHeaders("a", null, "c"));
    try testing.expect(!hasCertHeaders("a", "b", null));
}

// ── the core VERIFY requirement ───────────────────────────────────────

test "authorize: operator (root, admin) cert hits an admin route" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try makeStore(real);
    defer store.deinit();

    const op = try TestKey.fromScalar([_]u8{0x42} ** 32);
    _ = try store.issueRoot(op.pubkey, "operator");

    const method = "POST";
    const route = "/api/v1/cells";
    const sig = try op.signChallenge(method, route, pinnedClock());
    const cred = Credential{
        .pubkey = op.pubkey,
        .cert_id = identity_certs.certIdFromPubkey(op.pubkey),
        .signature = sig,
        .timestamp = pinnedClock(),
    };

    const decision = authorize(&store, cred, method, route, pinnedClock(), DEFAULT_MAX_SKEW_SECS);
    try testing.expectEqual(Decision.allow_admin, decision);
    try testing.expect(decision.isAllow());
}

test "authorize: non-operator (user child) cert is REJECTED on an admin route" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try makeStore(real);
    defer store.deinit();

    // Operator root.
    const op = try TestKey.fromScalar([_]u8{0x42} ** 32);
    const root = try store.issueRoot(op.pubkey, "operator");

    // A field-user child cert WITHOUT the admin capability.
    const user = try TestKey.fromScalar([_]u8{0x07} ** 32);
    _ = try store.issueChild(&root.id, 0x10, user.pubkey, &.{"cap.oddjobz.write_customer"}, "field-phone");

    const method = "POST";
    const route = "/api/v1/cells";
    const sig = try user.signChallenge(method, route, pinnedClock());
    const cred = Credential{
        .pubkey = user.pubkey,
        .cert_id = identity_certs.certIdFromPubkey(user.pubkey),
        .signature = sig,
        .timestamp = pinnedClock(),
    };

    const decision = authorize(&store, cred, method, route, pinnedClock(), DEFAULT_MAX_SKEW_SECS);
    try testing.expectEqual(Decision.deny_forbidden, decision);
    try testing.expect(!decision.isAllow());
}

test "authorize: non-operator (user child) cert is ALLOWED on a user route" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try makeStore(real);
    defer store.deinit();

    const op = try TestKey.fromScalar([_]u8{0x42} ** 32);
    const root = try store.issueRoot(op.pubkey, "operator");
    const user = try TestKey.fromScalar([_]u8{0x07} ** 32);
    _ = try store.issueChild(&root.id, 0x10, user.pubkey, &.{"cap.oddjobz.write_customer"}, "field-phone");

    const method = "GET";
    const route = "/api/v1/info";
    const sig = try user.signChallenge(method, route, pinnedClock());
    const cred = Credential{
        .pubkey = user.pubkey,
        .cert_id = identity_certs.certIdFromPubkey(user.pubkey),
        .signature = sig,
        .timestamp = pinnedClock(),
    };

    const decision = authorize(&store, cred, method, route, pinnedClock(), DEFAULT_MAX_SKEW_SECS);
    try testing.expectEqual(Decision.allow_user, decision);
    try testing.expect(decision.isAllow());
}

test "authorize: a delegated admin child (carries cap.brain.admin) hits admin routes" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try makeStore(real);
    defer store.deinit();

    const op = try TestKey.fromScalar([_]u8{0x42} ** 32);
    const root = try store.issueRoot(op.pubkey, "operator");
    const admin_child = try TestKey.fromScalar([_]u8{0x09} ** 32);
    _ = try store.issueChild(&root.id, 0x10, admin_child.pubkey, &.{ADMIN_CAPABILITY}, "admin-laptop");

    const method = "POST";
    const route = "/api/v1/cells";
    const sig = try admin_child.signChallenge(method, route, pinnedClock());
    const cred = Credential{
        .pubkey = admin_child.pubkey,
        .cert_id = identity_certs.certIdFromPubkey(admin_child.pubkey),
        .signature = sig,
        .timestamp = pinnedClock(),
    };

    try testing.expectEqual(
        Decision.allow_admin,
        authorize(&store, cred, method, route, pinnedClock(), DEFAULT_MAX_SKEW_SECS),
    );
}

// ── control-signature failure modes ───────────────────────────────────

test "authorize: bad signature is rejected (unauthenticated)" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try makeStore(real);
    defer store.deinit();

    const op = try TestKey.fromScalar([_]u8{0x42} ** 32);
    _ = try store.issueRoot(op.pubkey, "operator");

    // Signature is all-zero garbage — recovery loop never matches.
    const cred = Credential{
        .pubkey = op.pubkey,
        .cert_id = identity_certs.certIdFromPubkey(op.pubkey),
        .signature = [_]u8{0} ** SIG_LEN,
        .timestamp = pinnedClock(),
    };

    try testing.expectEqual(
        Decision.deny_unauthenticated,
        authorize(&store, cred, "POST", "/api/v1/cells", pinnedClock(), DEFAULT_MAX_SKEW_SECS),
    );
}

test "authorize: a signature for a DIFFERENT route does not transfer" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try makeStore(real);
    defer store.deinit();

    const op = try TestKey.fromScalar([_]u8{0x42} ** 32);
    _ = try store.issueRoot(op.pubkey, "operator");

    // Operator signs the challenge for /info, then tries to reuse it on
    // the admin /cells route — the digest binding makes it invalid.
    const sig = try op.signChallenge("GET", "/api/v1/info", pinnedClock());
    const cred = Credential{
        .pubkey = op.pubkey,
        .cert_id = identity_certs.certIdFromPubkey(op.pubkey),
        .signature = sig,
        .timestamp = pinnedClock(),
    };

    try testing.expectEqual(
        Decision.deny_unauthenticated,
        authorize(&store, cred, "POST", "/api/v1/cells", pinnedClock(), DEFAULT_MAX_SKEW_SECS),
    );
}

test "authorize: a stale timestamp is rejected" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try makeStore(real);
    defer store.deinit();

    const op = try TestKey.fromScalar([_]u8{0x42} ** 32);
    _ = try store.issueRoot(op.pubkey, "operator");

    const stale_ts = pinnedClock() - 10_000; // well outside ±300s
    const sig = try op.signChallenge("POST", "/api/v1/cells", stale_ts);
    const cred = Credential{
        .pubkey = op.pubkey,
        .cert_id = identity_certs.certIdFromPubkey(op.pubkey),
        .signature = sig,
        .timestamp = stale_ts,
    };

    try testing.expectEqual(
        Decision.deny_unauthenticated,
        authorize(&store, cred, "POST", "/api/v1/cells", pinnedClock(), DEFAULT_MAX_SKEW_SECS),
    );
}

test "authorize: an unknown cert (not in store) is rejected" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try makeStore(real);
    defer store.deinit();

    // Store has an operator, but the credential is for a cert never issued.
    const op = try TestKey.fromScalar([_]u8{0x42} ** 32);
    _ = try store.issueRoot(op.pubkey, "operator");

    const stranger = try TestKey.fromScalar([_]u8{0x55} ** 32);
    const sig = try stranger.signChallenge("POST", "/api/v1/cells", pinnedClock());
    const cred = Credential{
        .pubkey = stranger.pubkey,
        .cert_id = identity_certs.certIdFromPubkey(stranger.pubkey),
        .signature = sig,
        .timestamp = pinnedClock(),
    };

    try testing.expectEqual(
        Decision.deny_unauthenticated,
        authorize(&store, cred, "POST", "/api/v1/cells", pinnedClock(), DEFAULT_MAX_SKEW_SECS),
    );
}

test "authorizeFromHeaders: end-to-end header path for the operator" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try makeStore(real);
    defer store.deinit();

    const op = try TestKey.fromScalar([_]u8{0x42} ** 32);
    _ = try store.issueRoot(op.pubkey, "operator");

    var pk_hex: [PUBKEY_HEX_LEN]u8 = undefined;
    bkds.hexEncode(&op.pubkey, &pk_hex);
    const sig = try op.signChallenge("POST", "/api/v1/cells", pinnedClock());
    var sig_hex: [SIG_HEX_LEN]u8 = undefined;
    bkds.hexEncode(&sig, &sig_hex);

    const decision = authorizeFromHeaders(
        &store,
        &pk_hex,
        &sig_hex,
        "1700000000",
        "POST",
        "/api/v1/cells",
        pinnedClock(),
        DEFAULT_MAX_SKEW_SECS,
    );
    try testing.expectEqual(Decision.allow_admin, decision);
}

test "authorizeFromHeaders: malformed headers deny" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try makeStore(real);
    defer store.deinit();

    try testing.expectEqual(
        Decision.deny_unauthenticated,
        authorizeFromHeaders(&store, null, null, null, "POST", "/api/v1/cells", pinnedClock(), DEFAULT_MAX_SKEW_SECS),
    );
}

```
