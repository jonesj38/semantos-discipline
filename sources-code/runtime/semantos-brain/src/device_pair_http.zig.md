---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/device_pair_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.237892+00:00
---

# runtime/semantos-brain/src/device_pair_http.zig

```zig
// Phase D-O5p — Production HTTP acceptor for child-cert pairing.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §3 phase O5p-c
// (Acceptor side runs in the brain: receives child cert
// registration, verifies BRC-42 derivation against the operator's
// root, records in the identity DAG, mints capability delegations
// under the requested allowlist); §11 (operator perspective).
//
// What this is:
//
//   POST /api/v1/device-pair
//   Content-Type: application/json
//
//   Request body:
//     {
//       "token": "<base64url-pairing-payload>",      // operator-signed
//       "derivation_pubkey": "<66 hex>",             // BRC-42 child pubkey
//                                                    // device computed
//       "derivation_proof":  "<66 hex>"              // device's
//                                                    // counterparty pubkey
//     }
//
//   Success response (200):
//     {
//       "status": "registered",
//       "cert_id": "<32 hex>",                       // newly issued child cert id
//       "brain_cert_id": "<32 hex>"                  // operator-root cert id
//                                                    // (echoed for client logs)
//     }
//
//   Error responses (4xx/5xx) — body shape `{"error": "<typed code>"}`:
//     400 payload_invalid_format       — base64url/JSON parse failure
//     400 payload_unknown_version      — wire-version mismatch
//     400 payload_label_too_long       — label > MAX_LABEL_LEN
//     400 payload_invalid_capability   — cap allowlist syntactic failure
//     400 derivation_missing_fields    — derivation_pubkey or
//                                        derivation_proof absent /
//                                        wrong shape
//     401 payload_invalid_signature    — operator signature didn't
//                                        verify under embedded pub
//     409 payload_consumed             — single-use nonce was already
//                                        burned
//     410 payload_expired              — payload past expires_at
//     422 derivation_proof_mismatch    — recomputed child pubkey
//                                        differed from device-submitted
//                                        derivation_pubkey
//     422 cap_allowlist_invalid        — cap on the cert chain didn't
//                                        survive validation
//     500 cap_minting_failed           — internal failure during cert
//                                        store mutation
//     500 internal_error               — unanticipated path
//
// ─── How this differs from `brain device claim` (lab fixture) ─────────
//
// The lab `claim` verb runs both halves of the handshake in one
// process: it fabricates a device priv inside the CLI, computes the
// expected child pubkey via the device-side BRC-42 path, posts to
// `identity_certs.issue_child` against the same dispatcher.
//
// This acceptor is the BRAIN-SIDE half only.  The device side runs
// elsewhere (Flutter app, post-D-O5m; or the TS test fixture in
// `cartridges/oddjobz/brain/tests/device-pair-roundtrip.test.ts`).  The
// device computes its own derivation_pubkey + submits its
// counterparty pub as derivation_proof; we verify them against the
// operator priv we hold in-memory.
//
// ─── Capability minting note ─────────────────────────────────────────
//
// The §3 O5p-c acceptance language is "mints capability delegations
// under the requested allowlist".  This PR records the cap names
// onto the child cert record (the `capabilities` slice in the
// CertRecord) — which is what the cert store + dispatcher cap-gate
// already consult.  Minting fresh capability UTXOs (separate cap-
// token PR #279 territory) is deferred to D-O5m: that's where the
// cap-token spend mechanism gets exercised on the mobile side.
// Today the operator-root caps are sufficient because the device's
// child cert participates in the audit log + the dispatcher checks
// the cert's cap list directly.  Future fork: D-O5m may want fresh
// per-child UTXO mints to enforce K2 spend-uniqueness across
// multiple devices.
//
// ─── CORS note (brain issue #273 follow-up) ──────────────────────────
//
// This endpoint is the first brain-served public POST that takes
// external (cross-origin) input.  v0.5 ships same-origin only — the
// browser-based device-pair app is intended to live at the same
// brain-domain (e.g. `https://oddjobtodd.info/pair-app/`) so CORS
// preflight isn't required.  When D-O5m's Flutter shell goes live
// it talks via dart:ffi or via a same-origin pseudo-shell, also
// CORS-free.  Ship a CORS allowlist at the SiteServer layer when
// either of these change.
//
// The matching client side lives in the TS test fixture
// (`cartridges/oddjobz/brain/tests/device-pair-roundtrip.test.ts`).

const std = @import("std");
const device_pair = @import("device_pair");
const identity_certs = @import("identity_certs");
const bkds = @import("bkds");
const bsvz = @import("bsvz");
const bearer_tokens = @import("bearer_tokens");

pub const Error = error{
    out_of_memory,
    write_failed,
};

/// Status code → typed error name mapping the HTTP layer emits.
/// Every variant carries a short kebab-case name the client side
/// asserts on.
pub const AcceptResultKind = enum {
    registered,
    payload_invalid_format,
    payload_unknown_version,
    payload_label_too_long,
    payload_invalid_capability,
    payload_invalid_signature,
    payload_expired,
    payload_consumed,
    derivation_missing_fields,
    derivation_proof_mismatch,
    cap_allowlist_invalid,
    cap_minting_failed,
    internal_error,

    pub fn httpStatus(self: AcceptResultKind) std.http.Status {
        return switch (self) {
            .registered => .ok,
            .payload_invalid_format,
            .payload_unknown_version,
            .payload_label_too_long,
            .payload_invalid_capability,
            .derivation_missing_fields,
            => .bad_request,
            .payload_invalid_signature => .unauthorized,
            .payload_consumed => .conflict,
            .payload_expired => .gone,
            .derivation_proof_mismatch,
            .cap_allowlist_invalid,
            => .unprocessable_entity,
            .cap_minting_failed,
            .internal_error,
            => .internal_server_error,
        };
    }

    pub fn wireName(self: AcceptResultKind) []const u8 {
        return switch (self) {
            .registered => "registered",
            .payload_invalid_format => "payload_invalid_format",
            .payload_unknown_version => "payload_unknown_version",
            .payload_label_too_long => "payload_label_too_long",
            .payload_invalid_capability => "payload_invalid_capability",
            .payload_invalid_signature => "payload_invalid_signature",
            .payload_expired => "payload_expired",
            .payload_consumed => "payload_consumed",
            .derivation_missing_fields => "derivation_missing_fields",
            .derivation_proof_mismatch => "derivation_proof_mismatch",
            .cap_allowlist_invalid => "cap_allowlist_invalid",
            .cap_minting_failed => "cap_minting_failed",
            .internal_error => "internal_error",
        };
    }
};

/// State the acceptor needs for a single request.  Borrowed from
/// the SiteServer; lifetimes are managed there.  We do NOT take a
/// dispatcher here — we dial directly into the cert store + nonce
/// ledger.  The dispatcher's `identity_certs.issue_child` does the
/// same thing internally, but we already have the verified parsed
/// payload + the operator priv at this seam, so an extra hop adds
/// a JSON-encode + JSON-decode trip with no benefit.
pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    cert_store: *identity_certs.CertStore,
    /// secp256k1 scalar matching the cert chain's root pubkey.  Same
    /// shape as identity_certs_handler.zig's operator_root_priv.
    /// When null, every accept call returns
    /// `derivation_proof_mismatch` (we can't recompute the expected
    /// child without the priv half).
    operator_root_priv: ?[bkds.PRIVKEY_LEN]u8,
    /// Data dir, used to open the nonce ledger.  Borrowed.
    data_dir: []const u8,
    /// When set, a bearer token is minted on successful registration
    /// + returned in the response body so the device can immediately
    /// hit /api/v1/repl etc. without a separate bearer-mint roundtrip.
    /// When null, the response omits the `bearer` field (legacy shape).
    token_store: ?*bearer_tokens.TokenStore = null,

    pub fn init(
        allocator: std.mem.Allocator,
        cert_store: *identity_certs.CertStore,
        data_dir: []const u8,
    ) Acceptor {
        return .{
            .allocator = allocator,
            .cert_store = cert_store,
            .operator_root_priv = null,
            .data_dir = data_dir,
            .token_store = null,
        };
    }

    pub fn setOperatorRootPriv(self: *Acceptor, priv: [bkds.PRIVKEY_LEN]u8) void {
        self.operator_root_priv = priv;
    }

    pub fn setTokenStore(self: *Acceptor, ts: *bearer_tokens.TokenStore) void {
        self.token_store = ts;
    }
};

/// Result of an accept call.  `cert_id` is owned by the caller on
/// success; the deinit function frees it.
pub const AcceptResult = struct {
    kind: AcceptResultKind,
    cert_id: ?[32]u8 = null,
    brain_cert_id: ?[32]u8 = null,

    pub fn deinit(self: *AcceptResult, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // No owned bytes today; `cert_id` is a stack array.  Kept
        // as a method for symmetry with the rest of the codebase.
    }
};

/// The pure acceptor logic — lifted out of HTTP shape so the TS
/// test fixture can drive it directly via dispatcher, AND so the
/// HTTP wrapper can focus on transport + body parsing.
///
/// Steps:
///   1. parseAndVerify the operator-signed token (sig, expiry,
///      version, syntactic cap validity).
///   2. Check the one-shot nonce ledger.
///   3. Verify the device-supplied (derivation_pubkey,
///      derivation_proof) against the operator priv via BRC-42.
///   4. Persist the child cert in the store.
///   5. Mark nonce consumed.
pub fn accept(
    self: *Acceptor,
    now_unix: i64,
    token: []const u8,
    derivation_pubkey: [bkds.KEY_LEN]u8,
    derivation_proof: [bkds.PROOF_LEN]u8,
) Error!AcceptResult {
    const allocator = self.allocator;

    // 1. Verify operator-signed payload.
    var parsed = device_pair.parseAndVerify(allocator, token, now_unix) catch |err| switch (err) {
        device_pair.Error.pairing_payload_invalid_format => return .{ .kind = .payload_invalid_format },
        device_pair.Error.pairing_payload_unknown_version => return .{ .kind = .payload_unknown_version },
        device_pair.Error.pairing_payload_label_too_long => return .{ .kind = .payload_label_too_long },
        device_pair.Error.pairing_payload_invalid_capability => return .{ .kind = .payload_invalid_capability },
        device_pair.Error.pairing_payload_invalid_signature => return .{ .kind = .payload_invalid_signature },
        device_pair.Error.pairing_payload_expired => return .{ .kind = .payload_expired },
        device_pair.Error.out_of_memory => return Error.out_of_memory,
        else => return .{ .kind = .internal_error },
    };
    defer parsed.deinit(allocator);

    // 2. One-shot nonce check.  If consumed, return a separate
    // typed error so the device can tell "I already paired" apart
    // from "operator's payload was bad".
    var ledger = device_pair.NonceLedger.init(allocator, self.data_dir) catch |err| switch (err) {
        device_pair.Error.out_of_memory => return Error.out_of_memory,
        else => return .{ .kind = .internal_error },
    };
    defer ledger.deinit();
    if (ledger.isConsumed(parsed.nonce)) {
        return .{ .kind = .payload_consumed };
    }

    // 3. BRC-42 derivation check — the structural argument.  The
    // operator priv recomputes the expected child pubkey from
    // (derivation_proof, context_tag, label); a constant-time
    // compare against the device-submitted derivation_pubkey is
    // the gate that keeps a forged device pubkey out of the cert
    // chain.  Mirrors identity_certs_handler.zig handleIssueChild.
    const root_priv = self.operator_root_priv orelse return .{ .kind = .derivation_proof_mismatch };
    bkds.verifyDerivationProof(
        root_priv,
        derivation_proof,
        parsed.context_tag,
        parsed.label,
        derivation_pubkey,
    ) catch return .{ .kind = .derivation_proof_mismatch };

    // 4. Persist the child cert.  The store call validates caps
    // again (defence in depth) — anything malformed surfaces as
    // cap_allowlist_invalid.  parent_not_found is treated as
    // internal_error since the parent cert id rode in the
    // operator-signed payload (we already verified the operator
    // signed it).
    const rec = self.cert_store.issueChild(
        &parsed.operator_root_cert_id,
        parsed.context_tag,
        derivation_pubkey,
        parsed.capabilities,
        parsed.label,
    ) catch |err| switch (err) {
        identity_certs.CertError.parent_not_found => return .{ .kind = .internal_error },
        identity_certs.CertError.parent_revoked => return .{ .kind = .internal_error },
        identity_certs.CertError.capability_invalid => return .{ .kind = .cap_allowlist_invalid },
        identity_certs.CertError.out_of_memory => return Error.out_of_memory,
        else => return .{ .kind = .cap_minting_failed },
    };

    // 5. Burn the nonce.  Done after the store mutation succeeds
    // so a transient store failure leaves the nonce reusable for a
    // retry.  If the nonce mark fails (file I/O), we still return
    // success — the device side has its cert; a stale nonce is
    // visible at next claim attempt.
    ledger.markConsumed(parsed.nonce) catch {};

    return .{
        .kind = .registered,
        .cert_id = rec.id,
        .brain_cert_id = parsed.operator_root_cert_id,
    };
}

// ─────────────────────────────────────────────────────────────────────
// HTTP wrapper — POST /api/v1/device-pair
// ─────────────────────────────────────────────────────────────────────

/// Plug into `site_server.handleRequest`.  Returns true iff the
/// request was matched + handled (caller skips the rest of routing).
/// Returns false for non-/api/v1/device-pair paths.
///
/// CORS: same-origin only at v0.5.  When the device-side surface
/// moves off-origin, add an OPTIONS preflight handler here +
/// allowlist headers under SiteServer.config.
pub fn maybeHandle(
    request: *std.http.Server.Request,
    acceptor: *Acceptor,
    now_unix: i64,
) Error!bool {
    const target = request.head.target;
    const method = request.head.method;
    if (!std.mem.eql(u8, target, "/api/v1/device-pair")) return false;

    if (method != .POST) {
        try respondJson(request, .method_not_allowed,
            "{\"error\":\"method_not_allowed\",\"hint\":\"POST required\"}");
        return true;
    }

    var body_buf: [16384]u8 = undefined;
    const body = readBody(request, &body_buf) catch {
        try respondJson(request, .bad_request,
            "{\"error\":\"payload_invalid_format\",\"hint\":\"failed to read request body\"}");
        return true;
    };

    var req = parseAcceptRequest(acceptor.allocator, body) catch |err| {
        const msg = switch (err) {
            error.derivation_missing_fields,
            => "{\"error\":\"derivation_missing_fields\"}",
            else => "{\"error\":\"payload_invalid_format\"}",
        };
        try respondJson(request, .bad_request, msg);
        return true;
    };
    defer req.deinit(acceptor.allocator);

    var result = accept(acceptor, now_unix, req.token, req.derivation_pubkey, req.derivation_proof) catch |err| switch (err) {
        Error.out_of_memory => {
            try respondJson(request, .internal_server_error,
                "{\"error\":\"internal_error\",\"hint\":\"out_of_memory\"}");
            return true;
        },
        else => {
            try respondJson(request, .internal_server_error,
                "{\"error\":\"internal_error\"}");
            return true;
        },
    };
    defer result.deinit(acceptor.allocator);

    const status = result.kind.httpStatus();
    if (result.kind == .registered) {
        var resp_buf: std.ArrayList(u8) = .{};
        defer resp_buf.deinit(acceptor.allocator);
        const cert_id = result.cert_id orelse {
            try respondJson(request, .internal_server_error,
                "{\"error\":\"internal_error\",\"hint\":\"registered with no cert_id\"}");
            return true;
        };
        const brain_id = result.brain_cert_id orelse {
            try respondJson(request, .internal_server_error,
                "{\"error\":\"internal_error\",\"hint\":\"registered with no brain_cert_id\"}");
            return true;
        };
        // Mint a bearer for the newly-paired device when the token
        // store is wired.  Without this the mobile shell has a child
        // cert but no auth token + can't reach /api/v1/repl.
        var bearer_hex: [64]u8 = undefined;
        var bearer_set = false;
        if (acceptor.token_store) |ts| {
            const issued = ts.issue("device-pair", 60 * 60 * 24 * 30) catch null;
            if (issued) |minted| {
                const hex_chars = "0123456789abcdef";
                for (minted.token, 0..) |b, i| {
                    bearer_hex[i * 2] = hex_chars[b >> 4];
                    bearer_hex[i * 2 + 1] = hex_chars[b & 0x0f];
                }
                bearer_set = true;
            }
        }
        if (bearer_set) {
            resp_buf.print(acceptor.allocator,
                "{{\"status\":\"registered\",\"cert_id\":\"{s}\",\"brain_cert_id\":\"{s}\",\"bearer\":\"{s}\"}}",
                .{ &cert_id, &brain_id, &bearer_hex }) catch return Error.out_of_memory;
        } else {
            resp_buf.print(acceptor.allocator,
                "{{\"status\":\"registered\",\"cert_id\":\"{s}\",\"brain_cert_id\":\"{s}\"}}",
                .{ &cert_id, &brain_id }) catch return Error.out_of_memory;
        }
        try respondJson(request, status, resp_buf.items);
    } else {
        var err_buf: std.ArrayList(u8) = .{};
        defer err_buf.deinit(acceptor.allocator);
        err_buf.print(acceptor.allocator,
            "{{\"error\":\"{s}\"}}",
            .{result.kind.wireName()}) catch return Error.out_of_memory;
        try respondJson(request, status, err_buf.items);
    }
    return true;
}

const AcceptHttpRequest = struct {
    /// Owned base64url token slice.
    token: []u8,
    derivation_pubkey: [bkds.KEY_LEN]u8,
    derivation_proof: [bkds.PROOF_LEN]u8,

    fn deinit(self: AcceptHttpRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.token);
    }
};

/// Parse the JSON body into a typed request struct.  Used by the
/// HTTP wrapper, the test fixture, and the round-trip conformance.
pub fn parseAcceptRequest(allocator: std.mem.Allocator, body: []const u8) !AcceptHttpRequest {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.derivation_missing_fields;
    const obj = parsed.value.object;

    const tok_v = obj.get("token") orelse return error.derivation_missing_fields;
    if (tok_v != .string or tok_v.string.len == 0) return error.derivation_missing_fields;
    const token = try allocator.dupe(u8, tok_v.string);
    errdefer allocator.free(token);

    const dp_v = obj.get("derivation_pubkey") orelse return error.derivation_missing_fields;
    if (dp_v != .string or dp_v.string.len != bkds.KEY_LEN * 2) return error.derivation_missing_fields;
    var derivation_pubkey: [bkds.KEY_LEN]u8 = undefined;
    bkds.hexDecode(dp_v.string, &derivation_pubkey) catch return error.derivation_missing_fields;

    const proof_v = obj.get("derivation_proof") orelse return error.derivation_missing_fields;
    if (proof_v != .string or proof_v.string.len != bkds.PROOF_LEN * 2) return error.derivation_missing_fields;
    var derivation_proof: [bkds.PROOF_LEN]u8 = undefined;
    bkds.hexDecode(proof_v.string, &derivation_proof) catch return error.derivation_missing_fields;

    return .{
        .token = token,
        .derivation_pubkey = derivation_pubkey,
        .derivation_proof = derivation_proof,
    };
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

// Touch bsvz to force its inclusion on the unit-test target — the
// pure-logic accept path doesn't reach into bsvz directly, but its
// transitive use through bkds.verifyDerivationProof needs the dep
// graph wiring to compile.
comptime {
    _ = bsvz;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — purely the parseAcceptRequest path.  The full
// accept() round-trip is exercised in the conformance suite (which
// has access to a CertStore + a real operator priv).
// ─────────────────────────────────────────────────────────────────────

test "parseAcceptRequest: well-formed body produces typed request" {
    const allocator = std.testing.allocator;
    const body =
        \\{"token":"abc","derivation_pubkey":"02000000000000000000000000000000000000000000000000000000000000000a","derivation_proof":"02000000000000000000000000000000000000000000000000000000000000000b"}
    ;
    var req = try parseAcceptRequest(allocator, body);
    defer req.deinit(allocator);
    try std.testing.expectEqualStrings("abc", req.token);
    try std.testing.expectEqual(@as(u8, 0x0a), req.derivation_pubkey[bkds.KEY_LEN - 1]);
    try std.testing.expectEqual(@as(u8, 0x0b), req.derivation_proof[bkds.PROOF_LEN - 1]);
}

test "parseAcceptRequest: missing fields rejected" {
    const allocator = std.testing.allocator;
    const body = "{\"token\":\"abc\"}";
    try std.testing.expectError(error.derivation_missing_fields, parseAcceptRequest(allocator, body));
}

test "parseAcceptRequest: bad pubkey hex length rejected" {
    const allocator = std.testing.allocator;
    const body =
        \\{"token":"abc","derivation_pubkey":"0202","derivation_proof":"02000000000000000000000000000000000000000000000000000000000000000b"}
    ;
    try std.testing.expectError(error.derivation_missing_fields, parseAcceptRequest(allocator, body));
}

test "AcceptResultKind httpStatus + wireName mappings" {
    try std.testing.expectEqual(std.http.Status.ok, AcceptResultKind.registered.httpStatus());
    try std.testing.expectEqual(std.http.Status.bad_request, AcceptResultKind.payload_invalid_format.httpStatus());
    try std.testing.expectEqual(std.http.Status.unauthorized, AcceptResultKind.payload_invalid_signature.httpStatus());
    try std.testing.expectEqual(std.http.Status.gone, AcceptResultKind.payload_expired.httpStatus());
    try std.testing.expectEqual(std.http.Status.conflict, AcceptResultKind.payload_consumed.httpStatus());
    try std.testing.expectEqual(std.http.Status.unprocessable_entity, AcceptResultKind.derivation_proof_mismatch.httpStatus());
    try std.testing.expectEqualStrings("registered", AcceptResultKind.registered.wireName());
    try std.testing.expectEqualStrings("payload_consumed", AcceptResultKind.payload_consumed.wireName());
    try std.testing.expectEqualStrings("derivation_proof_mismatch", AcceptResultKind.derivation_proof_mismatch.wireName());
}

```
