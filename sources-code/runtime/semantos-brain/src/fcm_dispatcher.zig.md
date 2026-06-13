---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/fcm_dispatcher.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.225105+00:00
---

# runtime/semantos-brain/src/fcm_dispatcher.zig

```zig
// D-O5m.followup-9 Phase B — FCM HTTP v1 client with real RS256 JWT.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §D-O5m.followup-9
// Phase B (fcm dispatcher requirements);
// Google's "Send messages to specific devices" (FCM HTTP v1):
// https://firebase.google.com/docs/cloud-messaging/send-message
//
// Crypto choice (PINNED HERE):
//   • FCM's OAuth2 token endpoint requires an RS256-signed JWT
//     (PKCS#1 v1.5 + SHA-256 over the RSA private key from the
//     service-account JSON).
//   • Zig 0.15.2 stdlib (`std.crypto.Certificate.rsa`) provides RSA
//     **verify** but not **sign** — there's no `signPkcs1v15` API.
//     Adding a hand-rolled big-int RSA signer alongside the
//     dispatcher would be a meaningful security surface and a
//     constant-time-correctness rabbit hole.
//   • Therefore: we shell out to `openssl dgst -sha256 -sign <pem>`
//     once per JWT regeneration.  The JWT is valid for 1h, so the
//     hot path caches it; the cost is one openssl invocation per
//     hour, not per push.  The OAuth2 access_token derived from the
//     JWT is itself cached for ~55 minutes (Google issues 60-min
//     tokens; we refresh at 55 to give a buffer).
//   • If a future Zig stdlib release ships RSA signing, swapping the
//     `signRs256` helper below for the stdlib path is a one-function
//     change.  The dispatcher's interface is stable.
//
// What lives elsewhere:
//   • The HTTP transport — push_http_transport.zig.
//   • The push-notification shape — push_dispatcher.zig.
//   • The cert store — identity_certs.zig.

const std = @import("std");
const transport_mod = @import("push_http_transport");
const identity_certs = @import("identity_certs");
const audit_log_mod = @import("audit_log");

// ─── Public types ────────────────────────────────────────────────────

pub const FcmConfig = struct {
    /// GCP project id, e.g. "semantos-oddjobz".  Goes into the FCM
    /// send URL.  Owned by caller.
    project_id: []const u8,
    /// Path to Google's service-account JSON.  Read at init time.
    /// Holds `client_email` + `private_key` (PEM).  Owned by caller.
    service_account_json_path: []const u8,
};

/// One wake-only push notification to send.  Mirrors apns_dispatcher's
/// shape so the upper-level PushDispatcher can pass the same payload
/// to either transport.
///
/// Sovereign-push D.1 — FCM v1 message is data-only (no `notification`
/// field) with `priority: high` so the OS wakes the app.  No operator
/// content reaches Google.
pub const PushNotification = struct {
    /// Already-encoded JSON object literal — REQUIRED.  Each string
    /// value in the object becomes one entry in FCM's `data` map.
    /// FCM requires string→string in the data map; the helm broker
    /// produces only stringified values (`event_id`, `ts`, `kind`).
    payload_json: []const u8,
};

pub const DispatchError = error{
    service_account_read_failed,
    service_account_parse_failed,
    rsa_sign_failed,
    oauth_token_failed,
    transport_failed,
    fcm_rejected,
    no_fcm_token,
    cert_not_found,
    out_of_memory,
};

const OAUTH_ENDPOINT: []const u8 = "https://oauth2.googleapis.com/token";
const FCM_SCOPE: []const u8 = "https://www.googleapis.com/auth/firebase.messaging";
const FCM_AUDIENCE: []const u8 = "https://oauth2.googleapis.com/token";

// OAuth2 access token cache TTL — Google issues 60min tokens; we
// refresh at 55 to give a buffer.
const OAUTH_TOKEN_TTL_SECONDS: i64 = 55 * 60;

// JWT-bearer assertion shorter TTL — 60min max per Google's spec; we
// pin at 50 to match APNs' margin shape.
const JWT_TTL_SECONDS: i64 = 50 * 60;

// ─── Service-account fields (parsed from the JSON) ──────────────────

const ServiceAccount = struct {
    client_email: []u8,
    private_key_pem: []u8,
    allocator: std.mem.Allocator,

    fn deinit(self: *ServiceAccount) void {
        self.allocator.free(self.client_email);
        self.allocator.free(self.private_key_pem);
    }
};

const CachedBearer = struct {
    access_token: []u8,
    expires_at: i64,

    fn deinit(self: *CachedBearer, allocator: std.mem.Allocator) void {
        allocator.free(self.access_token);
    }
};

// ─── Dispatcher ──────────────────────────────────────────────────────

/// Sign the given preimage with RS256 using the PEM-encoded RSA
/// private key.  v0.1: shells out to `openssl dgst -sha256 -sign`.
/// Returns the raw signature bytes.  Public for tests so they can
/// substitute a stub signer.
pub const Rs256Signer = *const fn (
    allocator: std.mem.Allocator,
    pem_path: []const u8,
    preimage: []const u8,
) anyerror![]u8;

pub const FcmDispatcher = struct {
    allocator: std.mem.Allocator,
    config: FcmConfig,
    cert_store: *identity_certs.CertStore,
    audit_log: *audit_log_mod.AuditLog,
    http_transport: transport_mod.HttpTransport,
    clock_fn: *const fn () i64,
    now_iso_fn: *const fn (allocator: std.mem.Allocator) anyerror![]u8,
    /// Injectable RSA signer.  Defaults to the openssl shellout; tests
    /// override with a deterministic in-memory stub.
    rs256_sign_fn: Rs256Signer,

    service_account: ServiceAccount,
    bearer_cache: ?CachedBearer,

    pub fn init(
        allocator: std.mem.Allocator,
        config: FcmConfig,
        cert_store: *identity_certs.CertStore,
        audit_log: *audit_log_mod.AuditLog,
        http_transport: transport_mod.HttpTransport,
    ) DispatchError!FcmDispatcher {
        const sa = parseServiceAccount(allocator, config.service_account_json_path) catch |err| switch (err) {
            error.read_failed => return DispatchError.service_account_read_failed,
            else => return DispatchError.service_account_parse_failed,
        };
        return .{
            .allocator = allocator,
            .config = config,
            .cert_store = cert_store,
            .audit_log = audit_log,
            .http_transport = http_transport,
            .clock_fn = defaultClock,
            .now_iso_fn = defaultNowIso,
            .rs256_sign_fn = opensslSignRs256,
            .service_account = sa,
            .bearer_cache = null,
        };
    }

    pub fn deinit(self: *FcmDispatcher) void {
        if (self.bearer_cache) |*c| c.deinit(self.allocator);
        self.bearer_cache = null;
        self.service_account.deinit();
    }

    pub fn setClockFn(self: *FcmDispatcher, f: *const fn () i64) void {
        self.clock_fn = f;
    }

    pub fn setNowIsoFn(self: *FcmDispatcher, f: *const fn (allocator: std.mem.Allocator) anyerror![]u8) void {
        self.now_iso_fn = f;
    }

    pub fn setRs256SignFn(self: *FcmDispatcher, f: Rs256Signer) void {
        // Invalidate any cached bearer — next send() re-issues with the new signer.
        if (self.bearer_cache) |*c| c.deinit(self.allocator);
        self.bearer_cache = null;
        self.rs256_sign_fn = f;
    }

    pub fn send(
        self: *FcmDispatcher,
        cert_id: []const u8,
        notification: PushNotification,
    ) DispatchError!void {
        const rec = self.cert_store.get(cert_id) catch return DispatchError.cert_not_found;
        if (rec.push_platform != .fcm or rec.fcm_token.len == 0) {
            return DispatchError.no_fcm_token;
        }

        const bearer = self.ensureBearer() catch return DispatchError.oauth_token_failed;

        const url = std.fmt.allocPrint(
            self.allocator,
            "https://fcm.googleapis.com/v1/projects/{s}/messages:send",
            .{self.config.project_id},
        ) catch return DispatchError.out_of_memory;
        defer self.allocator.free(url);

        const auth = std.fmt.allocPrint(self.allocator, "Bearer {s}", .{bearer}) catch
            return DispatchError.out_of_memory;
        defer self.allocator.free(auth);

        const body = buildBody(self.allocator, rec.fcm_token, notification) catch
            return DispatchError.out_of_memory;
        defer self.allocator.free(body);

        var attempt: usize = 0;
        while (attempt < 3) : (attempt += 1) {
            const headers = [_]transport_mod.Header{
                .{ .name = "authorization", .value = auth },
                .{ .name = "content-type", .value = "application/json" },
            };
            var resp = self.http_transport.post(self.allocator, .{
                .url = url,
                .headers = &headers,
                .body = body,
            }) catch |err| switch (err) {
                error.transport_error => continue,
                error.out_of_memory => return DispatchError.out_of_memory,
            };
            defer resp.deinit();

            if (resp.status == 200) {
                self.recordAudit(.ok, "fcm send ok");
                return;
            }
            // Token-expiry signals: 404 with UNREGISTERED, or 400
            // with INVALID_ARGUMENT (Google returns these in the
            // body's `error.status` / `error.details[].errorCode`
            // fields).
            const status_str = extractFcmErrorStatus(self.allocator, resp.body) catch "";
            defer if (status_str.len > 0) self.allocator.free(@constCast(status_str));
            if ((resp.status == 404 and std.mem.eql(u8, status_str, "UNREGISTERED")) or
                (resp.status == 400 and std.mem.eql(u8, status_str, "INVALID_ARGUMENT")))
            {
                self.clearCertToken(cert_id) catch {};
                self.recordAudit(.ok, "fcm token expired; cleared");
                return;
            }
            if (resp.status >= 500) continue;
            self.recordAudit(.err, "fcm rejected (4xx)");
            return DispatchError.fcm_rejected;
        }
        self.recordAudit(.err, "fcm transport budget exhausted");
        return DispatchError.transport_failed;
    }

    // ── Internals ──

    fn ensureBearer(self: *FcmDispatcher) ![]const u8 {
        const now = self.clock_fn();
        if (self.bearer_cache) |c| {
            if (now < c.expires_at) return c.access_token;
            self.bearer_cache.?.deinit(self.allocator);
            self.bearer_cache = null;
        }
        // Build the JWT-bearer assertion.
        const jwt = try buildBearerJwt(
            self.allocator,
            self.service_account.client_email,
            self.service_account.private_key_pem,
            now,
            self.rs256_sign_fn,
        );
        defer self.allocator.free(jwt);

        // POST to the OAuth2 token endpoint to swap the assertion for
        // an access_token.
        const body = try std.fmt.allocPrint(
            self.allocator,
            "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion={s}",
            .{jwt},
        );
        defer self.allocator.free(body);
        const headers = [_]transport_mod.Header{
            .{ .name = "content-type", .value = "application/x-www-form-urlencoded" },
        };
        var attempt: usize = 0;
        while (attempt < 3) : (attempt += 1) {
            var resp = self.http_transport.post(self.allocator, .{
                .url = OAUTH_ENDPOINT,
                .headers = &headers,
                .body = body,
            }) catch |err| switch (err) {
                error.transport_error => continue,
                else => return err,
            };
            defer resp.deinit();
            if (resp.status != 200) continue;
            // Parse `access_token` from the response.
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, resp.body, .{}) catch
                return error.oauth_token_failed;
            defer parsed.deinit();
            if (parsed.value != .object) return error.oauth_token_failed;
            const tok_v = parsed.value.object.get("access_token") orelse return error.oauth_token_failed;
            if (tok_v != .string) return error.oauth_token_failed;
            const owned_tok = try self.allocator.dupe(u8, tok_v.string);
            self.bearer_cache = .{
                .access_token = owned_tok,
                .expires_at = now + OAUTH_TOKEN_TTL_SECONDS,
            };
            return owned_tok;
        }
        return error.oauth_token_failed;
    }

    fn clearCertToken(self: *FcmDispatcher, cert_id: []const u8) !void {
        const now_iso = try self.now_iso_fn(self.allocator);
        defer self.allocator.free(now_iso);
        try self.cert_store.updatePushToken(cert_id, .none, "", now_iso);
    }

    fn recordAudit(
        self: *FcmDispatcher,
        result: audit_log_mod.Result,
        detail: []const u8,
    ) void {
        self.audit_log.record(self.allocator, .{
            .module = "fcm-dispatcher",
            .op = "fcm_send",
            .result = result,
            .detail = detail,
        }) catch {};
    }
};

// ─── Service-account JSON parser ────────────────────────────────────

const ParseSaError = error{
    read_failed,
    bad_json,
    missing_field,
    out_of_memory,
};

pub fn parseServiceAccount(
    allocator: std.mem.Allocator,
    path: []const u8,
) ParseSaError!ServiceAccount {
    const f = std.fs.cwd().openFile(path, .{}) catch return ParseSaError.read_failed;
    defer f.close();
    const max = 64 * 1024;
    const text = f.readToEndAlloc(allocator, max) catch return ParseSaError.read_failed;
    defer allocator.free(text);

    return parseServiceAccountBytes(allocator, text);
}

pub fn parseServiceAccountBytes(
    allocator: std.mem.Allocator,
    json_bytes: []const u8,
) ParseSaError!ServiceAccount {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{}) catch
        return ParseSaError.bad_json;
    defer parsed.deinit();
    if (parsed.value != .object) return ParseSaError.bad_json;
    const obj = parsed.value.object;
    const ce = obj.get("client_email") orelse return ParseSaError.missing_field;
    if (ce != .string) return ParseSaError.missing_field;
    const pk = obj.get("private_key") orelse return ParseSaError.missing_field;
    if (pk != .string) return ParseSaError.missing_field;
    const ce_dup = allocator.dupe(u8, ce.string) catch return ParseSaError.out_of_memory;
    errdefer allocator.free(ce_dup);
    const pk_dup = allocator.dupe(u8, pk.string) catch return ParseSaError.out_of_memory;
    return .{
        .client_email = ce_dup,
        .private_key_pem = pk_dup,
        .allocator = allocator,
    };
}

// ─── JWT builder (RS256 over the service-account assertion) ─────────

/// Build the OAuth2 JWT-bearer assertion.  Caller frees the returned
/// JWT string.
///
/// JWT shape (per Google's spec):
///   header  = base64url({"alg":"RS256","typ":"JWT"})
///   claims  = base64url({"iss":<client_email>,
///                        "scope":"https://www.googleapis.com/auth/firebase.messaging",
///                        "aud":"https://oauth2.googleapis.com/token",
///                        "iat":<now>,"exp":<now+TTL>})
///   sig     = base64url(RS256(header + "." + claims))
pub fn buildBearerJwt(
    allocator: std.mem.Allocator,
    client_email: []const u8,
    private_key_pem: []const u8,
    now_unix_seconds: i64,
    sign_fn: Rs256Signer,
) ![]u8 {
    const header_json = "{\"alg\":\"RS256\",\"typ\":\"JWT\"}";
    const header_b64 = try transport_mod.base64UrlEncode(allocator, header_json);
    defer allocator.free(header_b64);

    const claims_json = try std.fmt.allocPrint(
        allocator,
        "{{\"iss\":\"{s}\",\"scope\":\"{s}\",\"aud\":\"{s}\",\"iat\":{d},\"exp\":{d}}}",
        .{
            client_email,
            FCM_SCOPE,
            FCM_AUDIENCE,
            now_unix_seconds,
            now_unix_seconds + JWT_TTL_SECONDS,
        },
    );
    defer allocator.free(claims_json);

    const claims_b64 = try transport_mod.base64UrlEncode(allocator, claims_json);
    defer allocator.free(claims_b64);

    const signing_input = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ header_b64, claims_b64 });
    defer allocator.free(signing_input);

    // Write the PEM to a temp file so openssl can read it.  In tests
    // we override sign_fn so this never actually shells out.  The
    // production-path helper writes to `<system_tmp>/brain-fcm-XXXX.pem`.
    const sig_bytes = try sign_fn(allocator, private_key_pem, signing_input);
    defer allocator.free(sig_bytes);
    const sig_b64 = try transport_mod.base64UrlEncode(allocator, sig_bytes);
    defer allocator.free(sig_b64);

    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ signing_input, sig_b64 });
}

// ─── RS256 signer — openssl shellout ────────────────────────────────

/// Production RS256 signer.  Writes the PEM private key to a temp
/// file, shells out `openssl dgst -sha256 -sign <pem> -out -`, reads
/// back the raw signature bytes, deletes the temp file.  Caller owns
/// the returned slice.
///
/// Note: the PEM is written to the operator's temp dir with mode
/// 0600 (Zig's default for std.fs.cwd().createFile is 0666 but the
/// process umask typically restricts).  Best-effort cleanup: we
/// always try to delete the temp file even if openssl errored.
fn opensslSignRs256(
    allocator: std.mem.Allocator,
    private_key_pem: []const u8,
    preimage: []const u8,
) anyerror![]u8 {
    // 1. Write the PEM to a unique temp file.
    var rand_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&rand_bytes);
    var rand_hex: [32]u8 = undefined;
    const charset = "0123456789abcdef";
    for (rand_bytes, 0..) |b, i| {
        rand_hex[i * 2] = charset[b >> 4];
        rand_hex[i * 2 + 1] = charset[b & 0x0f];
    }
    const tmp_dir = std.posix.getenv("TMPDIR") orelse "/tmp";
    const pem_path = try std.fmt.allocPrint(allocator, "{s}/brain-fcm-{s}.pem", .{ tmp_dir, rand_hex });
    defer allocator.free(pem_path);
    {
        const f = try std.fs.cwd().createFile(pem_path, .{ .mode = 0o600 });
        defer f.close();
        try f.writeAll(private_key_pem);
    }
    defer std.fs.cwd().deleteFile(pem_path) catch {};

    // 2. Shell out openssl.  We pipe the preimage in via stdin and
    //    read the raw signature out via stdout.  `openssl dgst -sha256
    //    -sign <pem>` produces PKCS#1 v1.5 signatures (NOT PSS) which
    //    is what RS256 requires.
    var child = std.process.Child.init(&.{
        "openssl",
        "dgst",
        "-sha256",
        "-sign",
        pem_path,
    }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    // Write the preimage to stdin, then close it so openssl proceeds.
    if (child.stdin) |stdin| {
        try stdin.writeAll(preimage);
        stdin.close();
        child.stdin = null;
    }

    // Read the signature bytes.
    const max_sig = 1024; // RSA-2048 → 256, RSA-4096 → 512.
    var sig_buf: std.ArrayList(u8) = .{};
    defer sig_buf.deinit(allocator);
    if (child.stdout) |stdout| {
        var read_buf: [256]u8 = undefined;
        while (true) {
            const n = try stdout.read(&read_buf);
            if (n == 0) break;
            try sig_buf.appendSlice(allocator, read_buf[0..n]);
            if (sig_buf.items.len > max_sig) return error.signature_too_large;
        }
    }
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.openssl_sign_failed,
        else => return error.openssl_sign_failed,
    }

    return try sig_buf.toOwnedSlice(allocator);
}

// ─── Body builder ────────────────────────────────────────────────────

/// Build the FCM v1 message body for a sovereign-push D.1 wake-only
/// notification:
///
///   {"message":{
///     "token":"<token>",
///     "android":{"priority":"high"},
///     "apns":{"headers":{"apns-priority":"5","apns-push-type":"background"},
///             "payload":{"aps":{"content-available":1}}},
///     "data":{"event_id":"...","ts":"...","kind":"..."}
///   }}
///
/// No `notification` field — FCM treats messages without a
/// `notification` block as data-only, which means the OS wakes the
/// app instead of rendering a banner.  Google sees only the opaque
/// envelope.
///
/// FCM requires the `data` map to be string→string; non-string
/// values in `payload_json` are coerced via std.json.Value
/// stringification.
pub fn buildBody(
    allocator: std.mem.Allocator,
    fcm_token: []const u8,
    notification: PushNotification,
) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"message\":{\"token\":");
    try appendJsonString(allocator, &buf, fcm_token);
    // Per-platform overrides force a high-priority wake on both
    // Android (data-only is delayed by default) and iOS (mirrors
    // the APNs dispatcher's background+priority-5 shape).
    try buf.appendSlice(allocator, ",\"android\":{\"priority\":\"high\"}");
    try buf.appendSlice(
        allocator,
        ",\"apns\":{\"headers\":{\"apns-priority\":\"5\",\"apns-push-type\":\"background\"},\"payload\":{\"aps\":{\"content-available\":1}}}",
    );
    try buf.appendSlice(allocator, ",\"data\":");
    try appendDataMap(allocator, &buf, notification.payload_json);
    try buf.appendSlice(allocator, "}}");
    return buf.toOwnedSlice(allocator);
}

/// Format `payload_json` as an FCM-compatible `data` map.  Every
/// non-string value is stringified (FCM rejects non-string data
/// values).  Empty / null payloads emit `{}`.
fn appendDataMap(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    payload_json: []const u8,
) !void {
    if (payload_json.len == 0) {
        try out.appendSlice(allocator, "{}");
        return;
    }
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, payload_json, .{}) catch {
        try out.appendSlice(allocator, "{}");
        return;
    };
    defer parsed.deinit();
    if (parsed.value != .object) {
        try out.appendSlice(allocator, "{}");
        return;
    }
    try out.append(allocator, '{');
    var it = parsed.value.object.iterator();
    var first = true;
    while (it.next()) |entry| {
        if (!first) try out.append(allocator, ',');
        first = false;
        try appendJsonString(allocator, out, entry.key_ptr.*);
        try out.append(allocator, ':');
        // Coerce every value to a JSON string.
        switch (entry.value_ptr.*) {
            .string => |s| try appendJsonString(allocator, out, s),
            .integer => |n| {
                const s = try std.fmt.allocPrint(allocator, "{d}", .{n});
                defer allocator.free(s);
                try appendJsonString(allocator, out, s);
            },
            .float => |f| {
                const s = try std.fmt.allocPrint(allocator, "{d}", .{f});
                defer allocator.free(s);
                try appendJsonString(allocator, out, s);
            },
            .bool => |b| try appendJsonString(allocator, out, if (b) "true" else "false"),
            .null => try appendJsonString(allocator, out, ""),
            else => {
                // Nested objects / arrays — re-serialise the value
                // as JSON, then store as a string.
                const s = try std.json.Stringify.valueAlloc(allocator, entry.value_ptr.*, .{});
                defer allocator.free(s);
                try appendJsonString(allocator, out, s);
            },
        }
    }
    try out.append(allocator, '}');
}

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

// ─── Google error-status parser ─────────────────────────────────────

/// Google's FCM v1 error responses:
///   {"error":{"code":404,"status":"UNREGISTERED","message":"..."}}
fn extractFcmErrorStatus(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    if (body.len == 0) return try allocator.dupe(u8, "");
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch
        return try allocator.dupe(u8, "");
    defer parsed.deinit();
    if (parsed.value != .object) return try allocator.dupe(u8, "");
    const err = parsed.value.object.get("error") orelse return try allocator.dupe(u8, "");
    if (err != .object) return try allocator.dupe(u8, "");
    const status = err.object.get("status") orelse return try allocator.dupe(u8, "");
    if (status != .string) return try allocator.dupe(u8, "");
    return try allocator.dupe(u8, status.string);
}

// ─── Default clocks ──────────────────────────────────────────────────

fn defaultClock() i64 {
    return std.time.timestamp();
}

fn defaultNowIso(allocator: std.mem.Allocator) anyerror![]u8 {
    const now = std.time.timestamp();
    return try std.fmt.allocPrint(allocator, "{d}", .{now});
}

// ─── Test helpers ────────────────────────────────────────────────────

/// Deterministic in-memory RS256 signer for tests.  Returns a
/// fixed 256-byte slab so tests can assert the signing path was hit
/// without spawning openssl.  NOT cryptographically valid — tests
/// MUST NOT rely on the bytes being a real signature.
pub fn testStubSigner(
    allocator: std.mem.Allocator,
    pem_path: []const u8,
    preimage: []const u8,
) anyerror![]u8 {
    _ = pem_path;
    _ = preimage;
    const sig = try allocator.alloc(u8, 256);
    @memset(sig, 0xab);
    return sig;
}

// ─── Tests ───────────────────────────────────────────────────────────

test "parseServiceAccountBytes pulls client_email + private_key" {
    const allocator = std.testing.allocator;
    const json =
        \\{
        \\  "type":"service_account",
        \\  "client_email":"abc@test.iam.gserviceaccount.com",
        \\  "private_key":"-----BEGIN PRIVATE KEY-----\nXXXX\n-----END PRIVATE KEY-----\n"
        \\}
    ;
    var sa = try parseServiceAccountBytes(allocator, json);
    defer sa.deinit();
    try std.testing.expectEqualStrings("abc@test.iam.gserviceaccount.com", sa.client_email);
    try std.testing.expect(std.mem.startsWith(u8, sa.private_key_pem, "-----BEGIN PRIVATE KEY-----"));
}

test "buildBearerJwt produces 3-part token, header decodes RS256" {
    const allocator = std.testing.allocator;
    const token = try buildBearerJwt(
        allocator,
        "abc@test.iam.gserviceaccount.com",
        "-----BEGIN PRIVATE KEY-----\nXXXX\n-----END PRIVATE KEY-----\n",
        1_700_000_000,
        testStubSigner,
    );
    defer allocator.free(token);

    var it = std.mem.splitScalar(u8, token, '.');
    const header_b64 = it.next().?;
    const claims_b64 = it.next().?;
    const sig_b64 = it.next().?;
    try std.testing.expect(it.next() == null);

    const header = try transport_mod.base64UrlDecode(allocator, header_b64);
    defer allocator.free(header);
    try std.testing.expectEqualStrings("{\"alg\":\"RS256\",\"typ\":\"JWT\"}", header);

    const claims = try transport_mod.base64UrlDecode(allocator, claims_b64);
    defer allocator.free(claims);
    // Should contain iss, scope, aud, iat, exp.
    try std.testing.expect(std.mem.indexOf(u8, claims, "\"iss\":\"abc@test.iam.gserviceaccount.com\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, claims, "\"scope\":\"https://www.googleapis.com/auth/firebase.messaging\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, claims, "\"aud\":\"https://oauth2.googleapis.com/token\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, claims, "\"iat\":1700000000") != null);
    try std.testing.expect(std.mem.indexOf(u8, claims, "\"exp\":1700003000") != null);

    // Signature is the stub's 256 0xab bytes → 342 chars base64url
    // (no padding).  Just sanity-check it's the expected length.
    const sig = try transport_mod.base64UrlDecode(allocator, sig_b64);
    defer allocator.free(sig);
    try std.testing.expectEqual(@as(usize, 256), sig.len);
}

test "buildBody emits sovereign-push D.1 wake-only data-only message" {
    const allocator = std.testing.allocator;
    const body = try buildBody(allocator, "fcm-tok-001", .{
        .payload_json = "{\"event_id\":\"evt-001\",\"ts\":1700000000,\"kind\":\"helm.event\"}",
    });
    defer allocator.free(body);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const message = parsed.value.object.get("message").?;
    try std.testing.expectEqualStrings("fcm-tok-001", message.object.get("token").?.string);
    // No `notification` field — that's the data-only contract.
    try std.testing.expect(message.object.get("notification") == null);
    // Android override forces high priority so the OS wakes the app.
    const android = message.object.get("android").?;
    try std.testing.expectEqualStrings("high", android.object.get("priority").?.string);
    // APNs override mirrors the wake-only headers from apns_dispatcher.
    const apns = message.object.get("apns").?;
    const headers = apns.object.get("headers").?;
    try std.testing.expectEqualStrings("5", headers.object.get("apns-priority").?.string);
    try std.testing.expectEqualStrings("background", headers.object.get("apns-push-type").?.string);
    const apns_payload = apns.object.get("payload").?;
    try std.testing.expectEqual(@as(i64, 1), apns_payload.object.get("aps").?.object.get("content-available").?.integer);
    // Data is string→string; ts has been stringified.
    const data = message.object.get("data").?;
    try std.testing.expectEqualStrings("evt-001", data.object.get("event_id").?.string);
    try std.testing.expectEqualStrings("1700000000", data.object.get("ts").?.string);
    try std.testing.expectEqualStrings("helm.event", data.object.get("kind").?.string);
    // No legacy operator-readable fields appear anywhere in the body.
    try std.testing.expect(std.mem.indexOf(u8, body, "\"title\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"notification\"") == null);
}

test "buildBody snapshot — exact JSON shape for a typical wake" {
    const allocator = std.testing.allocator;
    const body = try buildBody(allocator, "fcm-tok-001", .{
        .payload_json = "{\"event_id\":\"E1\",\"ts\":1700000000,\"kind\":\"helm.event\"}",
    });
    defer allocator.free(body);
    try std.testing.expectEqualStrings(
        "{\"message\":{\"token\":\"fcm-tok-001\",\"android\":{\"priority\":\"high\"}," ++
            "\"apns\":{\"headers\":{\"apns-priority\":\"5\",\"apns-push-type\":\"background\"},\"payload\":{\"aps\":{\"content-available\":1}}}," ++
            "\"data\":{\"event_id\":\"E1\",\"ts\":\"1700000000\",\"kind\":\"helm.event\"}}}",
        body,
    );
}

test "extractFcmErrorStatus pulls UNREGISTERED" {
    const allocator = std.testing.allocator;
    const r = try extractFcmErrorStatus(
        allocator,
        "{\"error\":{\"code\":404,\"status\":\"UNREGISTERED\",\"message\":\"...\"}}",
    );
    defer allocator.free(r);
    try std.testing.expectEqualStrings("UNREGISTERED", r);
}

test "extractFcmErrorStatus returns empty for non-error body" {
    const allocator = std.testing.allocator;
    const r = try extractFcmErrorStatus(allocator, "{\"name\":\"projects/x/messages/y\"}");
    defer allocator.free(r);
    try std.testing.expectEqualStrings("", r);
}

```
