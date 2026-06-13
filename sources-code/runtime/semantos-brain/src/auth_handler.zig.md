---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/auth_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.222561+00:00
---

# runtime/semantos-brain/src/auth_handler.zig

```zig
// Phase WSITE3 — HTTP 401 / identity-cert challenge protocol.
//
// Reference: docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md §3 (WSITE3) + §5.
//
// Handles the auth lifecycle for `auth = "identity_required"` routes:
//
//   1. Unauthenticated request → 401 with X-Semantos-* headers + a
//      challenge cookie carrying a freshly-generated nonce.
//   2. Browser flips to the wallet origin (out of scope here), which
//      signs the nonce and POSTs to /auth/callback.
//   3. The callback verifies the signature against the nonce we issued,
//      mints a session record, sets a Set-Cookie, redirects back to the
//      original URL via the Return-To value.
//   4. Subsequent requests carrying the session cookie pass the gate
//      until expiry.
//
// **Scope decisions for v0.1**:
//
//   • Identity verification model is "did you sign the challenge nonce
//     with this pubkey".  No BRC-52 cert parsing or trusted-issuer
//     validation yet — those land in WSITE3.5.  The pubkey + signature
//     come straight from the callback body; the gate only verifies the
//     signature is valid for that pubkey.  The downside: anyone with a
//     valid pubkey can pass, so this is "you authenticated", not "you're
//     a member of issuer X's directory".  Sites that want issuer-level
//     gating wait for WSITE3.5.
//
//   • Payment-required (402) deferred to WSITE4 alongside the BEEF
//     internalisation path.  Routes with `auth = "payment_required"`
//     return a 501 "WSITE4 deferred" response — same as the WSITE2
//     placeholder.
//
//   • Session storage: in-memory map plus an append-only log file for
//     persistence across restarts.  Backed by `<data-dir>/sites/<domain>/
//     sessions.log`.  WSITE3.5 swaps to a real lmdb-backed store when
//     multi-instance deployment matters.
//
//   • Signature verification needs bsvz secp256k1, so it's gated on
//     `build_options.enable_wasmtime`.  When wasmtime is off the
//     callback path returns 503 "auth requires the bsvz-linked binary
//     — rebuild with -Denable-wasmtime=true".  Challenge issuance,
//     cookie handling, and session lookup all work in stub mode for
//     test coverage.
//
// HMAC-signed cookies: the session cookie is `<session_id>.<hmac_hex>`
// where the HMAC is computed over `session_id ‖ pubkey ‖ expiry` under
// the site's `signing_secret`.  This prevents session-id forgery —
// even if an attacker knows a victim's session_id, they can't produce
// a valid cookie without the secret.

const std = @import("std");
const build_options = @import("build_options");
const site_config_mod = @import("site_config");

pub const AuthError = error{
    not_authenticated,
    bad_callback_body,
    signature_verification_unavailable,
    invalid_signature,
    expired,
    out_of_memory,
};

pub const Session = struct {
    /// 32-byte random session id.
    id: [32]u8,
    /// 33-byte compressed SEC1 pubkey of the authenticated user.
    pubkey: [33]u8,
    /// Unix-seconds the session expires at.
    expires_at: i64,
    /// The original URL the user was trying to reach.
    return_to: []u8,
};

pub const ChallengeRecord = struct {
    /// 16-byte random nonce, base64 encoded.
    nonce_b64: [24]u8, // 16 raw bytes → ⌈16*4/3⌉ = 22 + padding
    nonce_b64_len: u8,
    /// Where to redirect on successful callback.
    return_to: []u8,
    /// Expires after 5 minutes.
    expires_at: i64,
};

/// In-memory session store. Append-only persistence to a log file keeps
/// sessions across restarts — on init we replay the log to rebuild the
/// map, expired entries get garbage-collected on access.
pub const SessionStore = struct {
    allocator: std.mem.Allocator,
    sessions: std.AutoHashMap([32]u8, Session),
    challenges: std.AutoHashMap([24]u8, ChallengeRecord),
    log_path: []const u8,
    log_file: ?std.fs.File,
    /// Pinned-clock for tests.
    clock_fn: *const fn () i64,

    pub fn init(allocator: std.mem.Allocator, log_path: []const u8) !SessionStore {
        if (std.fs.path.dirname(log_path)) |parent| {
            std.fs.cwd().makePath(parent) catch {};
        }
        var self: SessionStore = .{
            .allocator = allocator,
            .sessions = std.AutoHashMap([32]u8, Session).init(allocator),
            .challenges = std.AutoHashMap([24]u8, ChallengeRecord).init(allocator),
            .log_path = try allocator.dupe(u8, log_path),
            .log_file = null,
            .clock_fn = defaultClock,
        };
        // WSITE5 — replay sessions.log so sessions survive restarts.
        // The log records two event shapes:
        //   {"id":"<hex>","pk":"<hex>","exp":N,"ret":"<path>"}      // mintSession
        //   {"id":"<hex>","op":"revoke"}                            // revokeSession
        // Replay applies them in order; expired entries are GC'd at lookup time.
        self.replayLog() catch |err| switch (err) {
            error.FileNotFound => {},
            else => {
                self.deinit();
                return err;
            },
        };
        // Re-open in append mode for future writes.
        const file = std.fs.cwd().createFile(log_path, .{ .read = false, .truncate = false }) catch null;
        if (file) |f| f.seekFromEnd(0) catch {};
        self.log_file = file;
        return self;
    }

    fn replayLog(self: *SessionStore) !void {
        const f = std.fs.cwd().openFile(self.log_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer f.close();
        const stat = try f.stat();
        if (stat.size == 0) return;

        const buf = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(buf);
        _ = try f.readAll(buf);

        var line_iter = std.mem.tokenizeScalar(u8, buf, '\n');
        while (line_iter.next()) |line| {
            self.applySessionLogLine(line) catch continue;
        }
    }

    fn applySessionLogLine(self: *SessionStore, line: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), line, .{}) catch return error.bad_event;
        if (parsed != .object) return error.bad_event;
        const obj = parsed.object;
        const id_v = obj.get("id") orelse return error.bad_event;
        if (id_v != .string or id_v.string.len != 64) return error.bad_event;
        var id: [32]u8 = undefined;
        try hexDecode(id_v.string, &id);

        if (obj.get("op")) |op_v| {
            if (op_v == .string and std.mem.eql(u8, op_v.string, "revoke")) {
                if (self.sessions.fetchRemove(id)) |kv| {
                    self.allocator.free(kv.value.return_to);
                }
                return;
            }
            return error.bad_event;
        }

        // mint event
        const pk_v = obj.get("pk") orelse return error.bad_event;
        const exp_v = obj.get("exp") orelse return error.bad_event;
        const ret_v = obj.get("ret") orelse return error.bad_event;
        if (pk_v != .string or pk_v.string.len != 66 or exp_v != .integer or ret_v != .string) return error.bad_event;
        var pubkey: [33]u8 = undefined;
        try hexDecode(pk_v.string, &pubkey);
        const ret_dup = try self.allocator.dupe(u8, ret_v.string);
        errdefer self.allocator.free(ret_dup);

        // Replay records every mint regardless of expiry — `lookupSession`
        // already gates by `clock_fn()` at access time and GC's expired
        // entries.  Filtering at replay time would race with tests that
        // pin the clock via `setClockFn` *after* init.
        const session: Session = .{
            .id = id,
            .pubkey = pubkey,
            .expires_at = exp_v.integer,
            .return_to = ret_dup,
        };
        // Last write wins — a later mint with the same id replaces.
        if (self.sessions.fetchRemove(id)) |kv| self.allocator.free(kv.value.return_to);
        self.sessions.put(id, session) catch return error.out_of_memory;
    }

    pub fn deinit(self: *SessionStore) void {
        var sit = self.sessions.iterator();
        while (sit.next()) |e| self.allocator.free(e.value_ptr.return_to);
        self.sessions.deinit();
        var cit = self.challenges.iterator();
        while (cit.next()) |e| self.allocator.free(e.value_ptr.return_to);
        self.challenges.deinit();
        if (self.log_file) |f| f.close();
        self.allocator.free(self.log_path);
    }

    pub fn setClockFn(self: *SessionStore, f: *const fn () i64) void {
        self.clock_fn = f;
    }

    /// Issue a fresh challenge: 16 random bytes, base64 encoded, stored
    /// indexed by the encoded form (which is what comes back in the
    /// cookie).  Returns the b64 slice valid until next mutation.
    pub fn issueChallenge(self: *SessionStore, return_to: []const u8) ![]u8 {
        var raw: [16]u8 = undefined;
        std.crypto.random.bytes(&raw);
        var nonce_b64: [24]u8 = undefined;
        const enc = std.base64.standard.Encoder;
        const written = enc.encode(&nonce_b64, &raw);
        const len: u8 = @intCast(written.len);

        const ret = try self.allocator.dupe(u8, return_to);
        errdefer self.allocator.free(ret);

        const expires_at = self.clock_fn() + 5 * 60; // 5 min

        const key: [24]u8 = nonce_b64;
        try self.challenges.put(key, .{
            .nonce_b64 = nonce_b64,
            .nonce_b64_len = len,
            .return_to = ret,
            .expires_at = expires_at,
        });
        // Return a stable copy by getting back the entry's nonce_b64 slice
        const e = self.challenges.getPtr(key) orelse return error.out_of_memory;
        return e.nonce_b64[0..e.nonce_b64_len];
    }

    /// Resolve a challenge nonce (as it came back in the cookie) to its
    /// stored ChallengeRecord. Returns null if missing/expired.
    pub fn lookupChallenge(self: *SessionStore, nonce_b64: []const u8) ?*const ChallengeRecord {
        if (nonce_b64.len > 24) return null;
        var key: [24]u8 = .{0} ** 24;
        @memcpy(key[0..nonce_b64.len], nonce_b64);
        const rec = self.challenges.getPtr(key) orelse return null;
        if (rec.expires_at < self.clock_fn()) {
            // GC the expired entry.
            self.allocator.free(rec.return_to);
            _ = self.challenges.remove(key);
            return null;
        }
        return rec;
    }

    pub fn consumeChallenge(self: *SessionStore, nonce_b64: []const u8) ?ChallengeRecord {
        if (nonce_b64.len > 24) return null;
        var key: [24]u8 = .{0} ** 24;
        @memcpy(key[0..nonce_b64.len], nonce_b64);
        const removed = self.challenges.fetchRemove(key) orelse return null;
        if (removed.value.expires_at < self.clock_fn()) {
            self.allocator.free(removed.value.return_to);
            return null;
        }
        return removed.value;
    }

    /// Mint a session for a verified pubkey.  Returns the session
    /// allocated; caller can format the cookie with it.
    pub fn mintSession(
        self: *SessionStore,
        pubkey: [33]u8,
        ttl_seconds: u32,
        return_to: []const u8,
    ) !Session {
        var id: [32]u8 = undefined;
        std.crypto.random.bytes(&id);
        const ret = try self.allocator.dupe(u8, return_to);
        errdefer self.allocator.free(ret);
        const session = Session{
            .id = id,
            .pubkey = pubkey,
            .expires_at = self.clock_fn() + @as(i64, @intCast(ttl_seconds)),
            .return_to = ret,
        };
        try self.sessions.put(id, session);
        // Persist (best-effort).
        if (self.log_file) |f| {
            var line_buf: [256]u8 = undefined;
            var id_hex: [64]u8 = undefined;
            var pk_hex: [66]u8 = undefined;
            hexEncode(&id, &id_hex);
            hexEncode(&pubkey, &pk_hex);
            const line = std.fmt.bufPrint(&line_buf,
                "{{\"id\":\"{s}\",\"pk\":\"{s}\",\"exp\":{d},\"ret\":\"{s}\"}}\n",
                .{ &id_hex, &pk_hex, session.expires_at, return_to }) catch return session;
            f.writeAll(line) catch {};
        }
        return session;
    }

    pub fn lookupSession(self: *SessionStore, id: [32]u8) ?*const Session {
        const s = self.sessions.getPtr(id) orelse return null;
        if (s.expires_at < self.clock_fn()) {
            self.allocator.free(s.return_to);
            _ = self.sessions.remove(id);
            return null;
        }
        return s;
    }

    pub fn revokeSession(self: *SessionStore, id: [32]u8) void {
        if (self.sessions.fetchRemove(id)) |kv| {
            self.allocator.free(kv.value.return_to);
        }
        // WSITE5 — persist the revoke event so a future restart still
        // sees the session as gone (it might still be carrying a valid
        // cookie that hasn't hit its TTL).
        if (self.log_file) |f| {
            var line_buf: [128]u8 = undefined;
            var id_hex: [64]u8 = undefined;
            hexEncode(&id, &id_hex);
            const line = std.fmt.bufPrint(&line_buf,
                "{{\"id\":\"{s}\",\"op\":\"revoke\"}}\n",
                .{&id_hex}) catch return;
            f.writeAll(line) catch {};
        }
    }

    /// WSITE5 — return a snapshot of currently-active sessions for the
    /// `brain sessions` admin command.  Caller frees the slice + each
    /// entry's `return_to` via `freeSessionList`.
    pub fn activeSessionsAlloc(self: *SessionStore, allocator: std.mem.Allocator) ![]Session {
        const now = self.clock_fn();
        var out = std.ArrayList(Session){};
        errdefer {
            for (out.items) |s| allocator.free(s.return_to);
            out.deinit(allocator);
        }
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.expires_at < now) continue;
            const dup = try allocator.dupe(u8, entry.value_ptr.return_to);
            try out.append(allocator, .{
                .id = entry.value_ptr.id,
                .pubkey = entry.value_ptr.pubkey,
                .expires_at = entry.value_ptr.expires_at,
                .return_to = dup,
            });
        }
        return out.toOwnedSlice(allocator);
    }
};

pub fn freeSessionList(allocator: std.mem.Allocator, list: []Session) void {
    for (list) |s| allocator.free(s.return_to);
    allocator.free(list);
}

// ─────────────────────────────────────────────────────────────────────
// Cookie HMAC + parsing
// ─────────────────────────────────────────────────────────────────────

/// Compute HMAC-SHA256(secret, session_id ‖ pubkey ‖ expiry_le).
pub fn cookieHmac(secret: [32]u8, session: *const Session) [32]u8 {
    var hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(&secret);
    hmac.update(&session.id);
    hmac.update(&session.pubkey);
    var exp_le: [8]u8 = undefined;
    std.mem.writeInt(i64, &exp_le, session.expires_at, .little);
    hmac.update(&exp_le);
    var out: [32]u8 = undefined;
    hmac.final(&out);
    return out;
}

/// Format the session cookie as `<id_hex>.<hmac_hex>` (96 + 1 + 64 = 161 bytes).
pub fn formatSessionCookie(secret: [32]u8, session: *const Session, out: []u8) ![]u8 {
    if (out.len < 161) return error.buffer_too_small;
    var id_hex: [64]u8 = undefined;
    hexEncode(&session.id, &id_hex);
    @memcpy(out[0..64], &id_hex);
    out[64] = '.';
    const mac = cookieHmac(secret, session);
    var mac_hex: [64]u8 = undefined;
    hexEncode(&mac, &mac_hex);
    @memcpy(out[65..129], &mac_hex);
    return out[0..129];
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-2 — dual-cookie auth-callback response.
//
// The /auth/callback handler now mints a helm bearer alongside the
// session cookie and surfaces it to the SPA via a Set-Cookie header
// (instead of stitching `?bearer=...` into the redirect URL).  The
// bearer cookie is intentionally NOT HttpOnly so document.cookie can
// read it; once the SPA promotes it into localStorage the cookie is
// cleared.  The session cookie stays HttpOnly so JS can't exfiltrate
// the session id even on an XSS.
//
// Why two cookies + one redirect instead of bearer-in-URL:
//   • URL params leak into browser history, Referer headers on any
//     embedded image/script load, server logs, and any analytics
//     beacon the page fires.  Cookies don't.
//   • The redirect target is now stable: bookmarking `/helm/` after
//     auth no longer captures the bearer for replay.
//   • Backward-compat: the SPA still recognises a `?bearer=...` query
//     param (callsites with pre-followup-2 brain deploys keep working
//     during the transition window).
// ─────────────────────────────────────────────────────────────────────

/// Format the helm-bearer Set-Cookie header value.  `hex_token` is the
/// 64-hex bearer secret; `ttl_seconds` is the cookie Max-Age.  Output
/// shape: `__semantos_helm_bearer=<hex>; Path=/; SameSite=Lax; Max-Age=<ttl>`.
///
/// The cookie is deliberately NOT HttpOnly — the Svelte SPA reads it
/// via document.cookie on first load and clears it after promoting
/// the value into localStorage.  Single-use semantics; the on-wire
/// cookie window is one round-trip.
pub fn formatHelmBearerCookie(hex_token: []const u8, ttl_seconds: i64, out: []u8) ![]u8 {
    return std.fmt.bufPrint(out,
        "__semantos_helm_bearer={s}; Path=/; SameSite=Lax; Max-Age={d}",
        .{ hex_token, ttl_seconds });
}

/// Parse `<id_hex>.<hmac_hex>` from a cookie value, verify the HMAC.
/// Returns the session_id on success, error otherwise.
pub fn verifySessionCookie(
    secret: [32]u8,
    cookie_value: []const u8,
    store: *SessionStore,
) ?*const Session {
    if (cookie_value.len != 129) return null;
    if (cookie_value[64] != '.') return null;
    var id: [32]u8 = undefined;
    hexDecode(cookie_value[0..64], &id) catch return null;
    var expected_mac: [32]u8 = undefined;
    hexDecode(cookie_value[65..129], &expected_mac) catch return null;

    const session = store.lookupSession(id) orelse return null;
    const actual_mac = cookieHmac(secret, session);
    if (!std.crypto.timing_safe.eql([32]u8, expected_mac, actual_mac)) return null;
    return session;
}

// ─────────────────────────────────────────────────────────────────────
// Cookie header parser — pulls a named cookie out of `Cookie: a=b; c=d`.
// ─────────────────────────────────────────────────────────────────────

pub fn extractCookie(cookie_header: []const u8, name: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < cookie_header.len) {
        // skip whitespace + ;
        while (i < cookie_header.len and (cookie_header[i] == ' ' or cookie_header[i] == ';' or cookie_header[i] == '\t')) i += 1;
        if (i >= cookie_header.len) break;
        const start = i;
        while (i < cookie_header.len and cookie_header[i] != '=' and cookie_header[i] != ';') i += 1;
        const k = cookie_header[start..i];
        if (i >= cookie_header.len or cookie_header[i] != '=') continue;
        i += 1; // skip '='
        const v_start = i;
        while (i < cookie_header.len and cookie_header[i] != ';') i += 1;
        const v = cookie_header[v_start..i];
        if (std.mem.eql(u8, k, name)) return v;
    }
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Hex helpers
// ─────────────────────────────────────────────────────────────────────

pub fn hexEncode(bytes: []const u8, out: []u8) void {
    const charset = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        if (i * 2 + 1 >= out.len) break;
        out[i * 2 + 0] = charset[(b >> 4) & 0xf];
        out[i * 2 + 1] = charset[b & 0xf];
    }
}

pub fn hexDecode(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return error.bad_length;
    for (0..out.len) |i| {
        const hi = try nibble(hex[i * 2]);
        const lo = try nibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
}

fn nibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => error.bad_hex,
    };
}

fn defaultClock() i64 {
    return std.time.timestamp();
}

// ─────────────────────────────────────────────────────────────────────
// Signature verification (gated on bsvz availability)
// ─────────────────────────────────────────────────────────────────────

/// Verify a DER ECDSA signature over the SHA256 of `nonce_b64` under
/// the supplied compressed-SEC1 pubkey.  Returns true on valid match.
/// When the binary is built without bsvz (`enable-wasmtime=false`),
/// returns `error.signature_verification_unavailable` so the caller
/// can surface a meaningful 503.
pub fn verifySignatureOverNonce(
    pubkey_sec1: [33]u8,
    nonce_b64: []const u8,
    signature_der: []const u8,
) AuthError!bool {
    if (!build_options.enable_wasmtime) {
        return error.signature_verification_unavailable;
    }
    // Lazy-load bsvz only in the enabled build.
    const bsvz = @import("bsvz");
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(nonce_b64, &digest, .{});
    return bsvz.crypto.verifyDigest256RelaxedSec1(&pubkey_sec1, digest, signature_der) catch
        error.invalid_signature;
}

// ─────────────────────────────────────────────────────────────────────
// Callback body parser
// ─────────────────────────────────────────────────────────────────────

pub const CallbackBody = struct {
    pubkey: [33]u8,
    signature: []u8, // DER, allocator-owned
    nonce: []u8, // base64, allocator-owned
    return_to: []u8, // allocator-owned

    /// WSITE4 — present iff the callback claims a payment for a
    /// payment_required route.  When set, the nonce digest is over
    /// `(challenge_nonce ‖ txid_bytes ‖ satoshis_le_8)` instead of just
    /// the nonce, so the signature commits to the specific payment
    /// claim.  The auth handler records (txid_hex, satoshis) into the
    /// PaymentLedger after verifying the signature.
    payment: ?PaymentClaim = null,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *CallbackBody) void {
        self.allocator.free(self.signature);
        self.allocator.free(self.nonce);
        self.allocator.free(self.return_to);
        if (self.payment) |p| {
            if (p.beef_bytes) |b| self.allocator.free(b);
        }
    }
};

pub const PaymentClaim = struct {
    /// 32-byte txid (hex form).
    txid_hex: [64]u8,
    satoshis: u64,
    /// WSITE4.5 — optional raw BEEF the payer supplied alongside the
    /// signed claim.  When present, the site server stores it under
    /// <data-dir>/sites/<domain>/beefs/<txid>.beef and runs the WSITE4.5
    /// verifier inline.  Allocator-owned bytes; non-null means the
    /// CallbackBody owns them.
    beef_bytes: ?[]u8 = null,
};

/// Parse a JSON callback body of shape:
///   { "pubkey": "<hex 33-byte>", "signature": "<hex DER>",
///     "nonce": "<base64>", "return_to": "/path" }
pub fn parseCallback(allocator: std.mem.Allocator, body: []const u8) !CallbackBody {
    // Use an arena for the JSON tree itself; dupe out only the
    // fields the CallbackBody surface needs into the caller's
    // allocator before the arena is freed.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), body, .{});
    if (parsed != .object) return error.bad_callback_body;
    const obj = parsed.object;
    const pk_v = obj.get("pubkey") orelse return error.bad_callback_body;
    const sig_v = obj.get("signature") orelse return error.bad_callback_body;
    const nonce_v = obj.get("nonce") orelse return error.bad_callback_body;
    const ret_v = obj.get("return_to") orelse return error.bad_callback_body;
    if (pk_v != .string or sig_v != .string or nonce_v != .string or ret_v != .string)
        return error.bad_callback_body;

    var pubkey: [33]u8 = undefined;
    if (pk_v.string.len != 66) return error.bad_callback_body;
    hexDecode(pk_v.string, &pubkey) catch return error.bad_callback_body;

    if (sig_v.string.len % 2 != 0 or sig_v.string.len > 144) return error.bad_callback_body;
    const sig_bytes = try allocator.alloc(u8, sig_v.string.len / 2);
    errdefer allocator.free(sig_bytes);
    hexDecode(sig_v.string, sig_bytes) catch return error.bad_callback_body;

    const nonce_dup = try allocator.dupe(u8, nonce_v.string);
    errdefer allocator.free(nonce_dup);
    const ret_dup = try allocator.dupe(u8, ret_v.string);
    errdefer allocator.free(ret_dup);

    // Optional payment claim block: { "payment": { "txid": "<hex>",
    //                                              "satoshis": N,
    //                                              "beef": "<optional hex>" } }
    var payment_claim: ?PaymentClaim = null;
    if (obj.get("payment")) |p_v| {
        if (p_v != .object) return error.bad_callback_body;
        const p_obj = p_v.object;
        const txid_v = p_obj.get("txid") orelse return error.bad_callback_body;
        const sats_v = p_obj.get("satoshis") orelse return error.bad_callback_body;
        if (txid_v != .string or sats_v != .integer) return error.bad_callback_body;
        if (txid_v.string.len != 64) return error.bad_callback_body;
        if (sats_v.integer < 0) return error.bad_callback_body;

        var txid_hex: [64]u8 = undefined;
        @memcpy(&txid_hex, txid_v.string[0..64]);
        // Validate it's hex.
        var dummy: [32]u8 = undefined;
        hexDecode(&txid_hex, &dummy) catch return error.bad_callback_body;

        var beef_bytes: ?[]u8 = null;
        if (p_obj.get("beef")) |b_v| {
            if (b_v != .string) return error.bad_callback_body;
            if (b_v.string.len % 2 != 0) return error.bad_callback_body;
            // Cap at 16MB raw == 32MB hex; protects against pathological
            // payloads.
            if (b_v.string.len > 32 * 1024 * 1024) return error.bad_callback_body;
            const bytes = try allocator.alloc(u8, b_v.string.len / 2);
            errdefer allocator.free(bytes);
            hexDecode(b_v.string, bytes) catch return error.bad_callback_body;
            beef_bytes = bytes;
        }

        payment_claim = .{
            .txid_hex = txid_hex,
            .satoshis = @intCast(sats_v.integer),
            .beef_bytes = beef_bytes,
        };
    }

    return .{
        .pubkey = pubkey,
        .signature = sig_bytes,
        .nonce = nonce_dup,
        .return_to = ret_dup,
        .payment = payment_claim,
        .allocator = allocator,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Payment-aware signature verification
// ─────────────────────────────────────────────────────────────────────

/// For payment_required routes, the message digested for signing is
/// `(nonce_b64 ‖ txid_raw ‖ satoshis_le_8)` so the signature commits
/// to the specific payment claim — replaying the same signature for a
/// different txid won't pass.
pub fn verifyPaymentSignature(
    pubkey_sec1: [33]u8,
    nonce_b64: []const u8,
    txid_hex: [64]u8,
    satoshis: u64,
    signature_der: []const u8,
) AuthError!bool {
    if (!build_options.enable_wasmtime) {
        return error.signature_verification_unavailable;
    }
    const bsvz = @import("bsvz");

    var txid_raw: [32]u8 = undefined;
    hexDecode(&txid_hex, &txid_raw) catch return error.bad_callback_body;
    var sats_le: [8]u8 = undefined;
    std.mem.writeInt(u64, &sats_le, satoshis, .little);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(nonce_b64);
    hasher.update(&txid_raw);
    hasher.update(&sats_le);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    return bsvz.crypto.verifyDigest256RelaxedSec1(&pubkey_sec1, digest, signature_der) catch
        error.invalid_signature;
}

```
