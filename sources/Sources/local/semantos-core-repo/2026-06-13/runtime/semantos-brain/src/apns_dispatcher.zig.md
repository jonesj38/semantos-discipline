---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/apns_dispatcher.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.260052+00:00
---

# runtime/semantos-brain/src/apns_dispatcher.zig

```zig
// D-O5m.followup-9 Phase B — APNs HTTP/2 client with real ES256 JWT.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §D-O5m.followup-9
// Phase B (apns dispatcher requirements);
// Apple's "Sending notification requests to APNs":
// https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns
//
// This module owns:
//   • Loading + parsing the .p8 key Apple issues (PKCS#8 PEM,
//     P-256 secret).
//   • Building the ES256-signed bearer JWT per Apple's spec.
//   • Caching the JWT for ~50 minutes (Apple rejects JWTs older than
//     1 hour; we regenerate at 50min to give a margin).
//   • POSTing to api.{development.}push.apple.com with the right
//     headers + JSON body.
//   • Mapping Apple's typed errors back into the broker so an
//     expired token clears the cert's push_platform.
//
// What lives elsewhere:
//   • The HTTP transport — push_http_transport.zig.  Tests use the
//     MockTransport; production uses StdHttpTransport.
//   • The push-notification shape (title/body/data) — push_dispatcher.zig.
//   • The cert store — identity_certs.zig.  We only call its
//     `updatePushToken(.none, ...)` to clear an expired token.
//
// Crypto: stdlib's std.crypto.sign.ecdsa.EcdsaP256Sha256.  Apple
// requires P-256 + SHA-256 ("ES256") — NOT secp256k1 (Bitcoin's
// curve).  Don't try to wire bsvz here.

const std = @import("std");
const transport_mod = @import("push_http_transport");
const identity_certs = @import("identity_certs");
const audit_log_mod = @import("audit_log");

// ─── Public types ────────────────────────────────────────────────────

pub const ApnsEnvironment = enum {
    development,
    production,

    pub fn endpoint(self: ApnsEnvironment) []const u8 {
        return switch (self) {
            .development => "https://api.development.push.apple.com",
            .production => "https://api.push.apple.com",
        };
    }
};

pub const ApnsConfig = struct {
    /// iOS app bundle id, e.g. "com.semantos.oddjobz".  Sent as
    /// `apns-topic`.  Owned by caller.
    bundle_id: []const u8,
    /// 10-character Apple key id.  Goes into the JWT header `kid`.
    /// Owned by caller.
    key_id: []const u8,
    /// 10-character Apple team id.  Goes into the JWT claims `iss`.
    /// Owned by caller.
    team_id: []const u8,
    /// Path to the .p8 key file Apple issued.  Read at init time.
    /// Owned by caller.
    p8_key_path: []const u8,
    environment: ApnsEnvironment = .production,
};

/// One wake-only push notification to send.  Owned by caller.
///
/// Sovereign-push D.1 — APNs payload carries `aps.content-available=1`
/// + a top-level opaque envelope.  No `alert` field.  No operator
/// content.  Apple sees nothing more than the event_id + ts the
/// `payload_json` carries; the device opens its WSS and fetches the
/// real event content via `helm.fetch_since` after waking.
pub const PushNotification = struct {
    /// Already-encoded JSON object literal — the opaque envelope
    /// merged into the top-level APNs payload alongside `aps`.
    /// REQUIRED.  Shape:
    ///   {"event_id":"<id>","ts":<unix-seconds>,"kind":"<token>"}
    payload_json: []const u8,
};

pub const DispatchError = error{
    /// The .p8 key file could not be read.
    p8_key_read_failed,
    /// The .p8 key file did not parse as a PKCS#8 P-256 secret.
    p8_key_parse_failed,
    /// JWT signing or formatting failed.
    jwt_build_failed,
    /// HTTP transport failed beyond the retry budget.
    transport_failed,
    /// Apple rejected the request with a non-success status that
    /// isn't "token expired" (e.g. bad topic, malformed body).  See
    /// audit log for the reason string.
    apns_rejected,
    /// The cert id we were asked to send to has no APNs token.
    no_apns_token,
    /// The cert id wasn't in the cert store.
    cert_not_found,
    /// allocator OOM during request build.
    out_of_memory,
};

// Headers Apple consumes — sent on every request.
//
// Sovereign-push D.1 — push-type is `background` (not `alert`) and
// priority is `5` (not `10`).  This is the only valid combination
// for content-available=1 wake-only pushes; Apple drops alert-typed
// content-available=1 pushes silently and immediate-priority is
// reserved for user-visible alerts.
const PUSH_TYPE_BACKGROUND: []const u8 = "background";
const APNS_PRIORITY_BACKGROUND: []const u8 = "5";

// JWT validity window — Apple rejects > 1h.  We cache for 50min so
// we always have a 10min buffer.
const JWT_TTL_SECONDS: i64 = 50 * 60;

// ─── Cached JWT ──────────────────────────────────────────────────────

/// One cached JWT.  Owned strings; freed on regeneration / deinit.
const CachedJwt = struct {
    token: []u8,
    issued_at: i64,
};

// ─── Dispatcher ──────────────────────────────────────────────────────

pub const ApnsDispatcher = struct {
    allocator: std.mem.Allocator,
    config: ApnsConfig,
    cert_store: *identity_certs.CertStore,
    audit_log: *audit_log_mod.AuditLog,
    http_transport: transport_mod.HttpTransport,
    /// Pinned-clock for tests; defaults to wall-clock seconds.
    clock_fn: *const fn () i64,
    /// Pinned ISO-8601 string source for tests.  Used when we clear an
    /// expired token via cert_store.updatePushToken (the store needs a
    /// human-readable timestamp for `push_registered_at`).
    now_iso_fn: *const fn (allocator: std.mem.Allocator) anyerror![]u8,

    /// Parsed P-256 secret key from the .p8 file.  Loaded at init,
    /// reused for every JWT regeneration.
    secret_key: P256.SecretKey,
    /// Most recently issued JWT (or null if never issued).
    jwt_cache: ?CachedJwt,

    pub fn init(
        allocator: std.mem.Allocator,
        config: ApnsConfig,
        cert_store: *identity_certs.CertStore,
        audit_log: *audit_log_mod.AuditLog,
        http_transport: transport_mod.HttpTransport,
    ) DispatchError!ApnsDispatcher {
        const secret_key = loadP8SecretKey(allocator, config.p8_key_path) catch |err| switch (err) {
            error.read_failed => return DispatchError.p8_key_read_failed,
            else => return DispatchError.p8_key_parse_failed,
        };
        return .{
            .allocator = allocator,
            .config = config,
            .cert_store = cert_store,
            .audit_log = audit_log,
            .http_transport = http_transport,
            .clock_fn = defaultClock,
            .now_iso_fn = defaultNowIso,
            .secret_key = secret_key,
            .jwt_cache = null,
        };
    }

    pub fn deinit(self: *ApnsDispatcher) void {
        if (self.jwt_cache) |c| self.allocator.free(c.token);
        self.jwt_cache = null;
    }

    /// Override the clock for deterministic tests.
    pub fn setClockFn(self: *ApnsDispatcher, f: *const fn () i64) void {
        self.clock_fn = f;
    }

    /// Override the ISO-clock for deterministic tests.
    pub fn setNowIsoFn(self: *ApnsDispatcher, f: *const fn (allocator: std.mem.Allocator) anyerror![]u8) void {
        self.now_iso_fn = f;
    }

    /// Send a notification to a single cert.  Best-effort: a 410-
    /// expired-token clears the cert's push_platform via
    /// CertStore.updatePushToken; other errors flow back as typed
    /// errors for the caller (push_dispatcher) to log + swallow.
    pub fn send(
        self: *ApnsDispatcher,
        cert_id: []const u8,
        notification: PushNotification,
    ) DispatchError!void {
        // Pull the cert's apns_token.
        const rec = self.cert_store.get(cert_id) catch return DispatchError.cert_not_found;
        if (rec.push_platform != .apns or rec.apns_token.len == 0) {
            return DispatchError.no_apns_token;
        }

        // Get / regenerate the JWT.
        const jwt = self.ensureJwt() catch return DispatchError.jwt_build_failed;

        // Build the URL — environment + token.
        const url = std.fmt.allocPrint(
            self.allocator,
            "{s}/3/device/{s}",
            .{ self.config.environment.endpoint(), rec.apns_token },
        ) catch return DispatchError.out_of_memory;
        defer self.allocator.free(url);

        // Build the bearer header value.
        const auth = std.fmt.allocPrint(
            self.allocator,
            "bearer {s}",
            .{jwt},
        ) catch return DispatchError.out_of_memory;
        defer self.allocator.free(auth);

        // Build the body.
        const body = buildBody(self.allocator, notification) catch return DispatchError.out_of_memory;
        defer self.allocator.free(body);

        // Try with up to 3 attempts; backoff is 1s/2s/4s but tests
        // pin the clock so the actual delay is mocked-out.  For v0.1
        // we simply retry without sleeping — std.time.sleep would
        // hold the broker mutex which is the caller's contract.  A
        // production deployment behind a real-network bursts can
        // upgrade this to a queued worker.
        var attempt: usize = 0;
        while (attempt < 3) : (attempt += 1) {
            const headers = [_]transport_mod.Header{
                .{ .name = "authorization", .value = auth },
                .{ .name = "apns-topic", .value = self.config.bundle_id },
                .{ .name = "apns-push-type", .value = PUSH_TYPE_BACKGROUND },
                .{ .name = "apns-priority", .value = APNS_PRIORITY_BACKGROUND },
                .{ .name = "content-type", .value = "application/json" },
            };
            var resp = self.http_transport.post(self.allocator, .{
                .url = url,
                .headers = &headers,
                .body = body,
            }) catch |err| switch (err) {
                error.transport_error => {
                    // Transient — retry.
                    continue;
                },
                error.out_of_memory => return DispatchError.out_of_memory,
            };
            defer resp.deinit();

            // 200 → success.  Apple returns an empty body with the
            // `apns-id` header echoed back.
            if (resp.status == 200) {
                self.recordAudit(.ok, "apns send ok", cert_id);
                return;
            }

            // 410 + (Unregistered | BadDeviceToken | DeviceTokenNotForTopic)
            //   → clear the cert's apns_token, log, return ok-from-
            //   the-caller's-POV (the device unsubscribed itself).
            // 400 + BadDeviceToken can also surface; treat that the same.
            const reason = extractReason(self.allocator, resp.body) catch "";
            defer if (reason.len > 0) self.allocator.free(@constCast(reason));
            if (resp.status == 410 or
                (resp.status == 400 and std.mem.eql(u8, reason, "BadDeviceToken")))
            {
                self.clearCertToken(cert_id) catch {};
                self.recordAudit(.ok, "apns token expired; cleared", cert_id);
                return;
            }

            // 4xx → not retryable.  5xx → retry.
            if (resp.status >= 500) continue;
            self.recordAudit(.err, "apns rejected (4xx)", cert_id);
            return DispatchError.apns_rejected;
        }
        self.recordAudit(.err, "apns transport budget exhausted", cert_id);
        return DispatchError.transport_failed;
    }

    // ── Internals ──

    fn ensureJwt(self: *ApnsDispatcher) ![]const u8 {
        const now = self.clock_fn();
        if (self.jwt_cache) |c| {
            if (now - c.issued_at < JWT_TTL_SECONDS) return c.token;
            self.allocator.free(c.token);
            self.jwt_cache = null;
        }
        const new_token = try buildJwt(self.allocator, self.config, self.secret_key, now);
        self.jwt_cache = .{ .token = new_token, .issued_at = now };
        return new_token;
    }

    fn clearCertToken(self: *ApnsDispatcher, cert_id: []const u8) !void {
        const now_iso = try self.now_iso_fn(self.allocator);
        defer self.allocator.free(now_iso);
        try self.cert_store.updatePushToken(cert_id, .none, "", now_iso);
    }

    fn recordAudit(
        self: *ApnsDispatcher,
        result: audit_log_mod.Result,
        detail: []const u8,
        cert_id: []const u8,
    ) void {
        _ = cert_id;
        self.audit_log.record(self.allocator, .{
            .module = "apns-dispatcher",
            .op = "apns_send",
            .result = result,
            .detail = detail,
        }) catch {};
    }
};

// ─── JWT builder ─────────────────────────────────────────────────────

const P256 = std.crypto.sign.ecdsa.EcdsaP256Sha256;

/// Build the APNs JWT.  Caller frees.
///
/// JWT shape (per Apple's "Establishing a Token-Based Connection"):
///   header  = base64url({"alg":"ES256","kid":"<key_id>","typ":"JWT"})
///   claims  = base64url({"iss":"<team_id>","iat":<unix_seconds>})
///   sig     = base64url(ES256(header + "." + claims))
///   token   = header + "." + claims + "." + sig
pub fn buildJwt(
    allocator: std.mem.Allocator,
    config: ApnsConfig,
    secret_key: P256.SecretKey,
    now_unix_seconds: i64,
) ![]u8 {
    // Header — JSON, then base64url.
    const header_json = try std.fmt.allocPrint(
        allocator,
        "{{\"alg\":\"ES256\",\"kid\":\"{s}\",\"typ\":\"JWT\"}}",
        .{config.key_id},
    );
    defer allocator.free(header_json);

    const header_b64 = try transport_mod.base64UrlEncode(allocator, header_json);
    defer allocator.free(header_b64);

    // Claims — JSON, then base64url.
    const claims_json = try std.fmt.allocPrint(
        allocator,
        "{{\"iss\":\"{s}\",\"iat\":{d}}}",
        .{ config.team_id, now_unix_seconds },
    );
    defer allocator.free(claims_json);

    const claims_b64 = try transport_mod.base64UrlEncode(allocator, claims_json);
    defer allocator.free(claims_b64);

    // Signing input = header_b64 + "." + claims_b64.
    const signing_input = try std.fmt.allocPrint(
        allocator,
        "{s}.{s}",
        .{ header_b64, claims_b64 },
    );
    defer allocator.free(signing_input);

    // Sign with ES256.  Deterministic — null noise.
    const kp = try P256.KeyPair.fromSecretKey(secret_key);
    const sig = try kp.sign(signing_input, null);
    const sig_bytes = sig.toBytes();
    const sig_b64 = try transport_mod.base64UrlEncode(allocator, &sig_bytes);
    defer allocator.free(sig_b64);

    // token = signing_input + "." + sig_b64.
    return try std.fmt.allocPrint(
        allocator,
        "{s}.{s}",
        .{ signing_input, sig_b64 },
    );
}

// ─── Body builder ────────────────────────────────────────────────────

/// Build the JSON body Apple expects for a sovereign-push D.1
/// wake-only notification:
///
///   {"aps":{"content-available":1},"event_id":"...","ts":...}
///
/// `payload_json` is REQUIRED and must be a well-formed JSON object
/// literal (typically `{"event_id":"<id>","ts":<int>,"kind":"<tok>"}`).
/// Its keys are merged into the top-level object alongside `aps`;
/// the device reads `event_id` to drive the subsequent
/// `helm.fetch_since` WSS call.
///
/// No alert/title/body fields are emitted — Apple sees ONLY the
/// content-available flag and the opaque event reference.
pub fn buildBody(allocator: std.mem.Allocator, notification: PushNotification) ![]u8 {
    if (notification.payload_json.len == 0) {
        // Even an empty wake still needs a valid payload envelope so
        // the device can correlate the wake-up with a fetch attempt.
        return try allocator.dupe(u8, "{\"aps\":{\"content-available\":1}}");
    }
    // Merge the payload object into the top-level by stripping its
    // surrounding braces.  Caller is responsible for valid JSON; we
    // accept anything that starts with `{` and ends with `}`.
    const trimmed = std.mem.trim(u8, notification.payload_json, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{' or trimmed[trimmed.len - 1] != '}') {
        return error.InvalidPayload;
    }
    const inner = trimmed[1 .. trimmed.len - 1];
    if (inner.len == 0) {
        return try allocator.dupe(u8, "{\"aps\":{\"content-available\":1}}");
    }
    return try std.fmt.allocPrint(
        allocator,
        "{{\"aps\":{{\"content-available\":1}},{s}}}",
        .{inner},
    );
}

// ─── .p8 / PKCS#8 PEM parser ────────────────────────────────────────

const P8ParseError = error{
    read_failed,
    bad_pem,
    bad_pkcs8,
    out_of_memory,
};

/// Read + parse Apple's .p8 file.  The file is a PEM-armoured PKCS#8
/// PrivateKeyInfo wrapping a SEC1 ECPrivateKey for prime256v1.
///
/// Apple's .p8 files have a stable byte layout — a single private key
/// scalar.  We pluck the 32-byte raw scalar out of the PKCS#8 wrapping
/// and feed it to the stdlib SecretKey.  This is a deliberately
/// minimal parser: it's robust against the exact shape Apple emits but
/// won't handle every PKCS#8 variant.  If a future format change
/// breaks this, the operator gets a typed `p8_key_parse_failed` error
/// at boot, not a silent miss-sign at request time.
fn loadP8SecretKey(allocator: std.mem.Allocator, path: []const u8) P8ParseError!P256.SecretKey {
    const f = std.fs.cwd().openFile(path, .{}) catch return P8ParseError.read_failed;
    defer f.close();
    const max = 32 * 1024;
    const text = f.readToEndAlloc(allocator, max) catch return P8ParseError.read_failed;
    defer allocator.free(text);

    return parseP8Bytes(allocator, text);
}

/// Parse a PEM-armoured P-256 PKCS#8 private key (Apple's .p8).
/// Public for testing.
pub fn parseP8Bytes(allocator: std.mem.Allocator, text: []const u8) P8ParseError!P256.SecretKey {
    // Strip the BEGIN/END PRIVATE KEY armor and base64-decode.
    const begin = "-----BEGIN PRIVATE KEY-----";
    const end = "-----END PRIVATE KEY-----";
    const start_idx = std.mem.indexOf(u8, text, begin) orelse return P8ParseError.bad_pem;
    const after_begin = start_idx + begin.len;
    const end_idx = std.mem.indexOfPos(u8, text, after_begin, end) orelse return P8ParseError.bad_pem;
    var b64_buf = std.ArrayList(u8){};
    defer b64_buf.deinit(allocator);
    for (text[after_begin..end_idx]) |c| {
        if (c == ' ' or c == '\n' or c == '\r' or c == '\t') continue;
        b64_buf.append(allocator, c) catch return P8ParseError.out_of_memory;
    }
    const Decoder = std.base64.standard.Decoder;
    const decoded_len = Decoder.calcSizeForSlice(b64_buf.items) catch return P8ParseError.bad_pem;
    const decoded = allocator.alloc(u8, decoded_len) catch return P8ParseError.out_of_memory;
    defer allocator.free(decoded);
    Decoder.decode(decoded, b64_buf.items) catch return P8ParseError.bad_pem;

    // The PKCS#8 PrivateKeyInfo wraps an ECPrivateKey (RFC 5915):
    //   ECPrivateKey ::= SEQUENCE {
    //     version INTEGER (1),
    //     privateKey OCTET STRING (32 bytes),
    //     parameters [0] OBJECT IDENTIFIER OPTIONAL,
    //     publicKey [1] BIT STRING OPTIONAL
    //   }
    //
    // Rather than write a full ASN.1 DER parser, we look for the
    // OID for prime256v1 (1.2.840.10045.3.1.7 →
    // 06 08 2a 86 48 ce 3d 03 01 07) — which marks the algorithm
    // identifier inside the SEC1 OCTET STRING — then walk back to
    // find the 32-byte private key OCTET STRING that immediately
    // follows the integer-1 version field.  This is the canonical
    // shape Apple emits.
    //
    // Find the `04 20 <32 raw bytes>` OCTET STRING that holds the
    // private scalar.  This sequence appears once in the .p8 — Apple
    // emits a single EC private key.  Our search starts after the
    // outer PKCS#8 header bytes and looks for the inner ECPrivateKey
    // octet-string of length 32.
    var i: usize = 0;
    while (i + 33 <= decoded.len) : (i += 1) {
        if (decoded[i] == 0x04 and decoded[i + 1] == 0x20) {
            // Candidate OCTET STRING of length 32.  Apple's .p8
            // contains the SEC1 ECPrivateKey wrapper whose first such
            // OCTET STRING IS the raw scalar.  We accept the FIRST
            // match.
            var sk_bytes: [32]u8 = undefined;
            @memcpy(&sk_bytes, decoded[i + 2 ..][0..32]);
            return P256.SecretKey{ .bytes = sk_bytes };
        }
    }
    return P8ParseError.bad_pkcs8;
}

// ─── Apple error-body parser ─────────────────────────────────────────

/// Apple's 4xx/5xx responses carry `{"reason":"<code>"}`.  Returns an
/// owned slice (caller frees) or an empty slice on parse failure.
fn extractReason(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    if (body.len == 0) return try allocator.dupe(u8, "");
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return try allocator.dupe(u8, "");
    defer parsed.deinit();
    if (parsed.value != .object) return try allocator.dupe(u8, "");
    const r = parsed.value.object.get("reason") orelse return try allocator.dupe(u8, "");
    if (r != .string) return try allocator.dupe(u8, "");
    return try allocator.dupe(u8, r.string);
}

// ─── Default clocks ──────────────────────────────────────────────────

fn defaultClock() i64 {
    return std.time.timestamp();
}

fn defaultNowIso(allocator: std.mem.Allocator) anyerror![]u8 {
    // Synthesise a minimal ISO-8601 timestamp from the wall-clock.
    // Phase A's push_register_http does the same by formatting a
    // YYYY-MM-DDTHH:MM:SSZ string.
    const now = std.time.timestamp();
    return try std.fmt.allocPrint(allocator, "{d}", .{now});
}

// ─── Tests ───────────────────────────────────────────────────────────

test "buildJwt produces a 3-part token, header decodes to expected JSON" {
    const allocator = std.testing.allocator;
    var seed: [P256.SecretKey.encoded_length]u8 = .{0x42} ** 32;
    seed[0] = 0x01; // ensure non-zero
    const sk = P256.SecretKey{ .bytes = seed };

    const token = try buildJwt(allocator, .{
        .bundle_id = "com.test.app",
        .key_id = "ABCDE12345",
        .team_id = "TEAM12345Z",
        .p8_key_path = "/dev/null",
    }, sk, 1_700_000_000);
    defer allocator.free(token);

    var it = std.mem.splitScalar(u8, token, '.');
    const header_b64 = it.next().?;
    const claims_b64 = it.next().?;
    const sig_b64 = it.next().?;
    try std.testing.expect(it.next() == null);

    const header = try transport_mod.base64UrlDecode(allocator, header_b64);
    defer allocator.free(header);
    try std.testing.expectEqualStrings(
        "{\"alg\":\"ES256\",\"kid\":\"ABCDE12345\",\"typ\":\"JWT\"}",
        header,
    );

    const claims = try transport_mod.base64UrlDecode(allocator, claims_b64);
    defer allocator.free(claims);
    try std.testing.expectEqualStrings(
        "{\"iss\":\"TEAM12345Z\",\"iat\":1700000000}",
        claims,
    );

    // Signature must be 64 bytes raw (r||s) → 86 base64url chars
    // (no padding).
    const sig_bytes = try transport_mod.base64UrlDecode(allocator, sig_b64);
    defer allocator.free(sig_bytes);
    try std.testing.expectEqual(@as(usize, 64), sig_bytes.len);
}

test "buildJwt sig verifies with the matching public key" {
    const allocator = std.testing.allocator;
    // Generate a real key pair so we can verify deterministically.
    const seed: [P256.KeyPair.seed_length]u8 = .{0x01} ** 32;
    const kp = try P256.KeyPair.generateDeterministic(seed);

    const token = try buildJwt(allocator, .{
        .bundle_id = "com.test.app",
        .key_id = "AAAAAAAAAA",
        .team_id = "BBBBBBBBBB",
        .p8_key_path = "/dev/null",
    }, kp.secret_key, 1_700_000_000);
    defer allocator.free(token);

    // Reconstruct the signing input + signature, verify against the pub key.
    var it = std.mem.splitScalar(u8, token, '.');
    const h_b64 = it.next().?;
    const c_b64 = it.next().?;
    const s_b64 = it.next().?;
    const signing_input = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ h_b64, c_b64 });
    defer allocator.free(signing_input);
    const sig_bytes_slice = try transport_mod.base64UrlDecode(allocator, s_b64);
    defer allocator.free(sig_bytes_slice);
    var sig_bytes_arr: [64]u8 = undefined;
    @memcpy(&sig_bytes_arr, sig_bytes_slice);
    const sig = P256.Signature.fromBytes(sig_bytes_arr);
    try sig.verify(signing_input, kp.public_key);
}

test "buildBody emits sovereign-push D.1 wake-only envelope (no alert)" {
    const allocator = std.testing.allocator;
    const body = try buildBody(allocator, .{
        .payload_json = "{\"event_id\":\"evt-001\",\"ts\":1700000000,\"kind\":\"helm.event\"}",
    });
    defer allocator.free(body);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    // aps is present and carries content-available=1 — and ONLY that.
    const aps = parsed.value.object.get("aps").?;
    try std.testing.expect(aps == .object);
    try std.testing.expectEqual(@as(i64, 1), aps.object.get("content-available").?.integer);
    // No alert / sound / badge keys leak human-readable text.
    try std.testing.expect(aps.object.get("alert") == null);
    try std.testing.expect(aps.object.get("sound") == null);
    try std.testing.expect(aps.object.get("badge") == null);
    // Event envelope is hoisted to the top level.
    try std.testing.expectEqualStrings("evt-001", parsed.value.object.get("event_id").?.string);
    try std.testing.expectEqual(@as(i64, 1700000000), parsed.value.object.get("ts").?.integer);
    try std.testing.expectEqualStrings("helm.event", parsed.value.object.get("kind").?.string);
    // No legacy operator-readable fields appear anywhere in the body.
    try std.testing.expect(std.mem.indexOf(u8, body, "title") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "body") == null);
}

test "buildBody snapshot — exact JSON shape for a typical wake" {
    const allocator = std.testing.allocator;
    const body = try buildBody(allocator, .{
        .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}",
    });
    defer allocator.free(body);
    try std.testing.expectEqualStrings(
        "{\"aps\":{\"content-available\":1},\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}",
        body,
    );
}

test "buildBody handles empty payload as bare wake" {
    const allocator = std.testing.allocator;
    const body = try buildBody(allocator, .{ .payload_json = "" });
    defer allocator.free(body);
    try std.testing.expectEqualStrings("{\"aps\":{\"content-available\":1}}", body);
}

test "parseP8Bytes pulls the raw 32-byte scalar from a synthesised PKCS#8 PEM" {
    const allocator = std.testing.allocator;

    // Build a minimal "envelope" that the byte-search parser
    // accepts: a PKCS#8 header followed by the canonical
    // ECPrivateKey OCTET STRING (04 20 <32 raw bytes>).  This
    // mirrors the shape Apple's .p8 emits.
    var raw_scalar: [32]u8 = undefined;
    for (0..32) |i| raw_scalar[i] = @intCast((i * 7 + 1) & 0xff);
    var inner_buf: [128]u8 = undefined;
    var inner_len: usize = 0;
    // Outer PKCS#8 SEQUENCE / version / algorithm OID prefix —
    // arbitrary bytes for the search-based parser.  Just need the
    // FIRST `04 20` marker + 32 bytes after to land on raw_scalar.
    const prefix = [_]u8{ 0x30, 0x81, 0x87, 0x02, 0x01, 0x00, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x04, 0x6d, 0x30, 0x6b, 0x02, 0x01, 0x01 };
    @memcpy(inner_buf[0..prefix.len], &prefix);
    inner_len += prefix.len;
    inner_buf[inner_len] = 0x04;
    inner_buf[inner_len + 1] = 0x20;
    @memcpy(inner_buf[inner_len + 2 ..][0..32], &raw_scalar);
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

    const sk = try parseP8Bytes(allocator, pem);
    try std.testing.expectEqualSlices(u8, &raw_scalar, &sk.bytes);
}

test "extractReason finds Apple's error code" {
    const allocator = std.testing.allocator;
    const r = try extractReason(allocator, "{\"reason\":\"BadDeviceToken\"}");
    defer allocator.free(r);
    try std.testing.expectEqualStrings("BadDeviceToken", r);
}

test "extractReason returns empty for empty body" {
    const allocator = std.testing.allocator;
    const r = try extractReason(allocator, "");
    defer allocator.free(r);
    try std.testing.expectEqualStrings("", r);
}

```
