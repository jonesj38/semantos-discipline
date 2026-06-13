---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/push_register_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.246504+00:00
---

# runtime/semantos-brain/src/push_register_http.zig

```zig
// D-O5m.followup-9 Phase A — push notification registration substrate.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §D-O5m.followup-9
// Phase A (substrate scope: this PR ships schema + register endpoint
// + event flag; no APNs/FCM dispatchers, no Flutter Firebase wiring,
// no transports — those land in Phases B and C).
//
// What this is: the brain-side endpoint a paired device hits to
// register / refresh / unregister its push token.  The endpoint
// persists the token onto the device's identity-cert record (via
// `identity_certs.updatePushToken`) and replies with a typed JSON
// envelope.  No actual APNs/FCM dispatch happens here — Phase B owns
// the brain-side dispatcher; this Phase A only shapes the
// substrate so a device can announce "I'm subscribable".
//
// ─── Wire shape ──────────────────────────────────────────────────────
//
//   POST /api/v1/push-register
//     Authorization: Bearer <hex64>      (helm session bearer)
//     Content-Type: application/json
//     Body:
//       {
//         "cert_id": "<32 hex>",         (the device's cert id; same
//                                          shape as the one issued by
//                                          POST /api/v1/device-pair)
//         "platform": "apns" | "fcm" | "unifiedpush",
//         "token": "<opaque platform token, ≤ 4 KiB>"
//                                         (Sovereign-push D.3 — when
//                                          platform=unifiedpush the
//                                          token field carries the
//                                          distributor endpoint URL,
//                                          which MUST start with
//                                          "https://" and be ≤ 4 KiB.
//                                          Reject anything else with
//                                          400 endpoint_invalid.)
//       }
//
//   Success (200):
//     {
//       "registered": true,
//       "platform": "apns",
//       "registered_at": "<ISO-8601>"
//     }
//
//   DELETE /api/v1/push-register
//     Authorization: Bearer <hex64>
//     Content-Type: application/json
//     Body:
//       { "cert_id": "<32 hex>" }
//
//   Success (200):
//     { "registered": false }
//
// ─── Errors (typed code in body) ────────────────────────────────────
//
//   401 → {"error":"unauthorised"}     // missing / bad bearer or cert
//                                          unknown
//   400 → {"error":"platform_invalid"} // platform ∉ {apns, fcm,
//                                       //              unifiedpush}
//   400 → {"error":"token_empty"}      // token length zero
//   400 → {"error":"endpoint_invalid"} // platform=unifiedpush but
//                                       // token doesn't start with
//                                       // https:// (Sovereign-push
//                                       // D.3)
//   413 → {"error":"token_too_large"}  // token > MAX_TOKEN_BYTES
//   400 → {"error":"payload_invalid_format"}
//                                       // malformed JSON / missing
//                                       // cert_id field
//
// ─── Why bearer + cert_id (instead of bearer→cert lookup) ─────────────
//
// The brain bearer-token store (bearer_tokens.zig) doesn't bind a token
// to a cert today — bearers are session credentials issued by `brain
// bearer issue` for HTTP REPL access; certs are device identities
// minted via the identity-cert chain.  So this endpoint takes the same
// shape as attachments_upload_http.zig (bearer gates the request +
// cert_id rides in the body, then the cert store validates it).
// When a future PR introduces a token→cert seam (e.g. helm sessions
// minted under the device's child cert), this endpoint can drop the
// body field; the wire shape on the success path stays the same.

const std = @import("std");
const identity_certs = @import("identity_certs");
const bearer_tokens = @import("bearer_tokens");

pub const Error = error{
    out_of_memory,
    write_failed,
};

pub const ROUTE_PATH = "/api/v1/push-register";

/// Hard ceiling on the platform token length.  APNs device tokens are
/// 64 hex chars (32 bytes) at v0.5; FCM registration tokens are
/// typically ≤ 256 chars but the spec allows arbitrary opaque strings.
/// 4 KiB gives generous headroom without inviting payload-pump abuse.
pub const MAX_TOKEN_BYTES: usize = 4 * 1024;

/// Body buffer cap.  cert_id (32) + platform name (≤4) + token
/// (≤4 KiB) + JSON envelope overhead.  8 KiB covers it with margin.
const MAX_BODY_BYTES: usize = 8 * 1024;

pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    certs: *identity_certs.CertStore,
    bearer_tokens: *bearer_tokens.TokenStore,
    /// Injected for deterministic timestamps in tests.  In production
    /// callers wire `std.time.timestamp` via a thin shim.
    now_iso_fn: *const fn (std.mem.Allocator) anyerror![]u8,
};

/// Typed result kind that the HTTP wrapper turns into an HTTP status +
/// JSON body.  Lifted out of the HTTP path so the conformance suite
/// can drive `accept()` directly and assert on the discriminator.
pub const AcceptResultKind = enum {
    registered,
    unregistered,
    unauthorised,
    platform_invalid,
    token_empty,
    token_too_large,
    /// Sovereign-push D.3 — platform=unifiedpush but the supplied
    /// `token` (which is the distributor endpoint URL) doesn't start
    /// with `https://`.
    endpoint_invalid,
    payload_invalid_format,
    store_error,

    pub fn httpStatus(self: AcceptResultKind) std.http.Status {
        return switch (self) {
            .registered, .unregistered => .ok,
            .unauthorised => .unauthorized,
            .platform_invalid,
            .token_empty,
            .endpoint_invalid,
            .payload_invalid_format,
            => .bad_request,
            .token_too_large => .payload_too_large,
            .store_error => .internal_server_error,
        };
    }

    pub fn wireName(self: AcceptResultKind) []const u8 {
        return switch (self) {
            .registered => "registered",
            .unregistered => "unregistered",
            .unauthorised => "unauthorised",
            .platform_invalid => "platform_invalid",
            .token_empty => "token_empty",
            .token_too_large => "token_too_large",
            .endpoint_invalid => "endpoint_invalid",
            .payload_invalid_format => "payload_invalid_format",
            .store_error => "store_error",
        };
    }
};

pub const AcceptResult = struct {
    kind: AcceptResultKind,
    /// Owned (set on `.registered`); the now-iso timestamp the cert
    /// was registered at.  Empty otherwise.
    registered_at: []u8 = &.{},
    /// Mirrors what the wire envelope returns on `.registered`.  Empty
    /// otherwise.
    platform: identity_certs.PushPlatform = .none,

    pub fn deinit(self: *AcceptResult, allocator: std.mem.Allocator) void {
        if (self.registered_at.len > 0) allocator.free(self.registered_at);
        self.registered_at = &.{};
    }
};

/// Pure-logic register path — bearer must be valid; cert_id must
/// resolve to a live cert in the store.  Persists via
/// `identity_certs.updatePushToken` and returns the result kind +
/// the timestamp the store stamped (so the HTTP wrapper can echo it
/// in the response body).
pub fn acceptPost(
    acceptor: *const Acceptor,
    bearer_hex: ?[]const u8,
    body: []const u8,
) Error!AcceptResult {
    const bearer = bearer_hex orelse return .{ .kind = .unauthorised };
    _ = acceptor.bearer_tokens.verifyHex(bearer) catch {
        return .{ .kind = .unauthorised };
    };

    var parsed = parsePostBody(acceptor.allocator, body) catch |err| {
        return switch (err) {
            error.platform_invalid => .{ .kind = .platform_invalid },
            error.token_empty => .{ .kind = .token_empty },
            error.token_too_large => .{ .kind = .token_too_large },
            error.endpoint_invalid => .{ .kind = .endpoint_invalid },
            error.cert_id_missing,
            error.payload_invalid_format,
            => .{ .kind = .payload_invalid_format },
            error.out_of_memory => Error.out_of_memory,
        };
    };
    defer parsed.deinit(acceptor.allocator);

    _ = acceptor.certs.get(parsed.cert_id) catch {
        return .{ .kind = .unauthorised };
    };

    const now_iso = acceptor.now_iso_fn(acceptor.allocator) catch return Error.out_of_memory;
    errdefer acceptor.allocator.free(now_iso);

    acceptor.certs.updatePushToken(
        parsed.cert_id,
        parsed.platform,
        parsed.token,
        now_iso,
    ) catch {
        acceptor.allocator.free(now_iso);
        return .{ .kind = .store_error };
    };

    return .{
        .kind = .registered,
        .registered_at = now_iso,
        .platform = parsed.platform,
    };
}

/// Pure-logic unregister path — DELETE /api/v1/push-register.  Same
/// bearer + cert lookup as `acceptPost`; clears both push tokens +
/// the registered_at timestamp on the cert record.
pub fn acceptDelete(
    acceptor: *const Acceptor,
    bearer_hex: ?[]const u8,
    body: []const u8,
) Error!AcceptResult {
    const bearer = bearer_hex orelse return .{ .kind = .unauthorised };
    _ = acceptor.bearer_tokens.verifyHex(bearer) catch {
        return .{ .kind = .unauthorised };
    };

    var parsed = parseDeleteBody(acceptor.allocator, body) catch |err| {
        return switch (err) {
            error.cert_id_missing,
            error.payload_invalid_format,
            => .{ .kind = .payload_invalid_format },
            error.out_of_memory => Error.out_of_memory,
            else => .{ .kind = .payload_invalid_format },
        };
    };
    defer parsed.deinit(acceptor.allocator);

    _ = acceptor.certs.get(parsed.cert_id) catch {
        return .{ .kind = .unauthorised };
    };

    acceptor.certs.updatePushToken(parsed.cert_id, .none, "", "") catch {
        return .{ .kind = .store_error };
    };

    return .{ .kind = .unregistered };
}

/// Plug into `site_server.handleRequest`.  Returns true iff the request
/// was matched + handled (caller skips the rest of routing).  Returns
/// false for any non-/api/v1/push-register path.
pub fn maybeHandle(
    request: *std.http.Server.Request,
    acceptor: *const Acceptor,
) Error!bool {
    const target = request.head.target;
    const method = request.head.method;
    if (!std.mem.eql(u8, target, ROUTE_PATH)) return false;

    if (method != .POST and method != .DELETE) {
        try respondJson(request, .method_not_allowed,
            "{\"error\":\"method_not_allowed\",\"hint\":\"POST or DELETE required\"}");
        return true;
    }

    // Bearer is parsed here + threaded into the pure-logic path.  The
    // pure path re-runs verifyHex so a bad/missing bearer surfaces the
    // same `unauthorised` typed error regardless of which entry point
    // (HTTP vs the conformance test fixture) drove the call.
    const bearer = bearerFromHeaders(request);

    var body_buf: [MAX_BODY_BYTES]u8 = undefined;
    const body = readBody(request, &body_buf) catch {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\",\"hint\":\"failed to read body\"}");
        return true;
    };

    if (method == .DELETE) {
        return try handleDelete(request, acceptor, body, bearer);
    }
    return try handlePost(request, acceptor, body, bearer);
}

fn handlePost(
    request: *std.http.Server.Request,
    acceptor: *const Acceptor,
    body: []const u8,
    bearer: ?[]const u8,
) Error!bool {
    const allocator = acceptor.allocator;
    var result = try acceptPost(acceptor, bearer, body);
    defer result.deinit(allocator);

    if (result.kind == .registered) {
        var resp_buf: std.ArrayList(u8) = .{};
        defer resp_buf.deinit(allocator);
        resp_buf.print(
            allocator,
            "{{\"registered\":true,\"platform\":\"{s}\",\"registered_at\":\"{s}\"}}",
            .{ result.platform.wireName(), result.registered_at },
        ) catch return Error.out_of_memory;
        try respondJson(request, .ok, resp_buf.items);
        return true;
    }

    var err_buf: std.ArrayList(u8) = .{};
    defer err_buf.deinit(allocator);
    err_buf.print(allocator, "{{\"error\":\"{s}\"}}", .{result.kind.wireName()}) catch return Error.out_of_memory;
    try respondJson(request, result.kind.httpStatus(), err_buf.items);
    return true;
}

fn handleDelete(
    request: *std.http.Server.Request,
    acceptor: *const Acceptor,
    body: []const u8,
    bearer: ?[]const u8,
) Error!bool {
    const allocator = acceptor.allocator;
    var result = try acceptDelete(acceptor, bearer, body);
    defer result.deinit(allocator);

    if (result.kind == .unregistered) {
        try respondJson(request, .ok, "{\"registered\":false}");
        return true;
    }

    var err_buf: std.ArrayList(u8) = .{};
    defer err_buf.deinit(allocator);
    err_buf.print(allocator, "{{\"error\":\"{s}\"}}", .{result.kind.wireName()}) catch return Error.out_of_memory;
    try respondJson(request, result.kind.httpStatus(), err_buf.items);
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// Body parsing
// ─────────────────────────────────────────────────────────────────────

const ParseError = error{
    payload_invalid_format,
    cert_id_missing,
    platform_invalid,
    token_empty,
    token_too_large,
    endpoint_invalid,
    out_of_memory,
};

const PostBody = struct {
    cert_id: []u8,
    platform: identity_certs.PushPlatform,
    token: []u8,

    fn deinit(self: PostBody, allocator: std.mem.Allocator) void {
        allocator.free(self.cert_id);
        allocator.free(self.token);
    }
};

const DeleteBody = struct {
    cert_id: []u8,

    fn deinit(self: DeleteBody, allocator: std.mem.Allocator) void {
        allocator.free(self.cert_id);
    }
};

pub fn parsePostBody(allocator: std.mem.Allocator, body: []const u8) ParseError!PostBody {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch |err| {
        return switch (err) {
            error.OutOfMemory => ParseError.out_of_memory,
            else => ParseError.payload_invalid_format,
        };
    };
    defer parsed.deinit();
    if (parsed.value != .object) return ParseError.payload_invalid_format;
    const obj = parsed.value.object;

    const cert_v = obj.get("cert_id") orelse return ParseError.cert_id_missing;
    if (cert_v != .string or cert_v.string.len != identity_certs.CERT_ID_HEX_LEN) {
        return ParseError.cert_id_missing;
    }
    const cert_id = allocator.dupe(u8, cert_v.string) catch return ParseError.out_of_memory;
    errdefer allocator.free(cert_id);

    const platform_v = obj.get("platform") orelse return ParseError.platform_invalid;
    if (platform_v != .string) return ParseError.platform_invalid;
    const platform = identity_certs.PushPlatform.fromWireName(platform_v.string) orelse return ParseError.platform_invalid;
    // `none` over the wire is reserved for DELETE — POST must specify
    // one of the live platforms.
    if (platform == .none) return ParseError.platform_invalid;

    const token_v = obj.get("token") orelse return ParseError.token_empty;
    if (token_v != .string) return ParseError.payload_invalid_format;
    if (token_v.string.len == 0) return ParseError.token_empty;
    if (token_v.string.len > MAX_TOKEN_BYTES) return ParseError.token_too_large;
    // Sovereign-push D.3 — when platform=unifiedpush, the `token` field
    // carries the distributor endpoint URL.  Enforce https:// so the
    // brain doesn't POST wake envelopes into plaintext channels (a UP
    // distributor running on plain http would silently leak the
    // event_id over the operator's network).
    if (platform == .unifiedpush and !std.mem.startsWith(u8, token_v.string, "https://")) {
        return ParseError.endpoint_invalid;
    }
    const token = allocator.dupe(u8, token_v.string) catch return ParseError.out_of_memory;
    errdefer allocator.free(token);

    return .{
        .cert_id = cert_id,
        .platform = platform,
        .token = token,
    };
}

pub fn parseDeleteBody(allocator: std.mem.Allocator, body: []const u8) ParseError!DeleteBody {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch |err| {
        return switch (err) {
            error.OutOfMemory => ParseError.out_of_memory,
            else => ParseError.payload_invalid_format,
        };
    };
    defer parsed.deinit();
    if (parsed.value != .object) return ParseError.payload_invalid_format;
    const obj = parsed.value.object;

    const cert_v = obj.get("cert_id") orelse return ParseError.cert_id_missing;
    if (cert_v != .string or cert_v.string.len != identity_certs.CERT_ID_HEX_LEN) {
        return ParseError.cert_id_missing;
    }
    const cert_id = allocator.dupe(u8, cert_v.string) catch return ParseError.out_of_memory;
    return .{ .cert_id = cert_id };
}

// ─────────────────────────────────────────────────────────────────────
// HTTP helpers
// ─────────────────────────────────────────────────────────────────────

fn bearerFromHeaders(request: *std.http.Server.Request) ?[]const u8 {
    const auth = headerValue(request, "authorization") orelse return null;
    const prefix = "Bearer ";
    const lower_prefix = "bearer ";
    if (std.mem.startsWith(u8, auth, prefix)) return auth[prefix.len..];
    if (std.mem.startsWith(u8, auth, lower_prefix)) return auth[lower_prefix.len..];
    return null;
}

fn headerValue(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var it = request.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
    }
    return null;
}

fn respondJson(request: *std.http.Server.Request, status: std.http.Status, body: []const u8) Error!void {
    request.respond(body, .{
        .status = status,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "cache-control", .value = "no-store" },
        },
    }) catch return Error.write_failed;
}

fn readBody(request: *std.http.Server.Request, out: []u8) ![]const u8 {
    const reader = request.readerExpectNone(out);
    const n = try reader.readSliceShort(out);
    return out[0..n];
}

// ─────────────────────────────────────────────────────────────────────
// Inline parser tests — pure body-shape coverage (the full HTTP /
// store round-trip lives in tests/push_register_http_test.zig).
// ─────────────────────────────────────────────────────────────────────

test "parsePostBody: well-formed apns body parses cleanly" {
    const allocator = std.testing.allocator;
    const body =
        \\{"cert_id":"abcdef0123456789abcdef0123456789","platform":"apns","token":"apns-tok-001"}
    ;
    var p = try parsePostBody(allocator, body);
    defer p.deinit(allocator);
    try std.testing.expectEqualStrings("abcdef0123456789abcdef0123456789", p.cert_id);
    try std.testing.expectEqual(identity_certs.PushPlatform.apns, p.platform);
    try std.testing.expectEqualStrings("apns-tok-001", p.token);
}

test "parsePostBody: well-formed fcm body parses cleanly" {
    const allocator = std.testing.allocator;
    const body =
        \\{"cert_id":"abcdef0123456789abcdef0123456789","platform":"fcm","token":"fcm-tok-001"}
    ;
    var p = try parsePostBody(allocator, body);
    defer p.deinit(allocator);
    try std.testing.expectEqual(identity_certs.PushPlatform.fcm, p.platform);
}

test "parsePostBody: well-formed unifiedpush body parses cleanly" {
    const allocator = std.testing.allocator;
    const body =
        \\{"cert_id":"abcdef0123456789abcdef0123456789","platform":"unifiedpush","token":"https://ntfy.example/UPxyz"}
    ;
    var p = try parsePostBody(allocator, body);
    defer p.deinit(allocator);
    try std.testing.expectEqual(identity_certs.PushPlatform.unifiedpush, p.platform);
    try std.testing.expectEqualStrings("https://ntfy.example/UPxyz", p.token);
}

test "parsePostBody: unifiedpush with non-https endpoint rejected" {
    const allocator = std.testing.allocator;
    const body =
        \\{"cert_id":"abcdef0123456789abcdef0123456789","platform":"unifiedpush","token":"http://insecure.example/UPxyz"}
    ;
    try std.testing.expectError(ParseError.endpoint_invalid, parsePostBody(allocator, body));
}

test "parsePostBody: unifiedpush with bare-string non-URL endpoint rejected" {
    const allocator = std.testing.allocator;
    const body =
        \\{"cert_id":"abcdef0123456789abcdef0123456789","platform":"unifiedpush","token":"not-a-url"}
    ;
    try std.testing.expectError(ParseError.endpoint_invalid, parsePostBody(allocator, body));
}

test "parsePostBody: unknown platform rejected" {
    const allocator = std.testing.allocator;
    const body =
        \\{"cert_id":"abcdef0123456789abcdef0123456789","platform":"oops","token":"tok"}
    ;
    try std.testing.expectError(ParseError.platform_invalid, parsePostBody(allocator, body));
}

test "parsePostBody: platform=none rejected on POST (reserved for DELETE)" {
    const allocator = std.testing.allocator;
    const body =
        \\{"cert_id":"abcdef0123456789abcdef0123456789","platform":"none","token":"tok"}
    ;
    try std.testing.expectError(ParseError.platform_invalid, parsePostBody(allocator, body));
}

test "parsePostBody: empty token rejected" {
    const allocator = std.testing.allocator;
    const body =
        \\{"cert_id":"abcdef0123456789abcdef0123456789","platform":"apns","token":""}
    ;
    try std.testing.expectError(ParseError.token_empty, parsePostBody(allocator, body));
}

test "parsePostBody: oversized token rejected" {
    const allocator = std.testing.allocator;
    const huge = try allocator.alloc(u8, MAX_TOKEN_BYTES + 1);
    defer allocator.free(huge);
    @memset(huge, 'A');
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"cert_id\":\"abcdef0123456789abcdef0123456789\",\"platform\":\"apns\",\"token\":\"");
    try buf.appendSlice(allocator, huge);
    try buf.appendSlice(allocator, "\"}");
    try std.testing.expectError(ParseError.token_too_large, parsePostBody(allocator, buf.items));
}

test "parsePostBody: missing cert_id rejected" {
    const allocator = std.testing.allocator;
    const body =
        \\{"platform":"apns","token":"tok"}
    ;
    try std.testing.expectError(ParseError.cert_id_missing, parsePostBody(allocator, body));
}

test "parseDeleteBody: well-formed body parses cleanly" {
    const allocator = std.testing.allocator;
    const body =
        \\{"cert_id":"abcdef0123456789abcdef0123456789"}
    ;
    var p = try parseDeleteBody(allocator, body);
    defer p.deinit(allocator);
    try std.testing.expectEqualStrings("abcdef0123456789abcdef0123456789", p.cert_id);
}

test "parseDeleteBody: missing cert_id rejected" {
    const allocator = std.testing.allocator;
    const body = "{}";
    try std.testing.expectError(ParseError.cert_id_missing, parseDeleteBody(allocator, body));
}

```
