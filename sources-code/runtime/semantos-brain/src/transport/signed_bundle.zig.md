---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/transport/signed_bundle.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.291340+00:00
---

# runtime/semantos-brain/src/transport/signed_bundle.zig

```zig
// Phase D-W1 / Phase 4 — SignedBundle mesh receive seam.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §5.4 (SignedBundle
//            mesh transport: mobile Flutter peer + federated tenant
//            nodes wrap a dispatch Request envelope inside a SignedBundle
//            and post it; the receiving brain decodes the envelope,
//            verifies the cert chain, constructs a DispatchContext with
//            auth.cert = <peer's cert>, calls the dispatcher).  §8
//            Phase 4.  Closes the original D-W1 transport-unification
//            scope.
//
// This module owns the transport-agnostic shape:
//
//   processBundle(allocator, ctx_state, bytes) -> []u8
//
// Any I/O mechanism (HTTP today; BLE / multicast / Plexus push in
// future deployments) calls processBundle with the inbound bytes; the
// returned bytes are the wire.Response JSON the caller writes back to
// its peer.  The HTTP wrapper at the bottom of this file is the v0.1
// production seam.
//
// Pipeline per inbound bundle:
//
//   1. signed_bundle.decode(bytes)
//   2. enforce recipient_cert_id == brain's root_cert_id (addressed-
//      bundle posture; broadcast bundles rejected on receive).
//   3. timestamp freshness check (sender's stamp within
//      `freshness_window_seconds`).
//   4. nonce LRU check (replay protection; configurable bound).
//   5. signed_bundle.verifyCertChain(store) → VerifiedSender (resolves
//      caps + leaf cert id).
//   6. signed_bundle.verifySignature(VerifiedSender.leaf_pubkey).
//   7. wire.decodeRequest(bundle.payload) → inner dispatch Request.
//   8. construct DispatchContext{ auth = .cert, capabilities = caps,
//      meta = { request_id = nonce_hex, transport_label =
//      "signed_bundle" } }.
//   9. dispatcher.dispatch(ctx, resource, cmd, args_json).
//  10. wire.encodeResponse(result) → output bytes.
//
// Every failure branch produces a typed wire.Response error envelope so
// the operator surface (audit log + the HTTP status) speaks the same
// vocabulary as every other transport.

const std = @import("std");
const dispatcher_mod = @import("dispatcher");
const wire = @import("wire");
const signed_bundle = @import("signed_bundle");
const identity_certs = @import("identity_certs");
const bkds = @import("bkds");
// D-O5m.followup-6 Phase 2 — payload_type discriminator for the
// new oddjobz.* mesh-published types.  See `payload_type_router.zig`.
const payload_router = @import("payload_type_router");

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

/// Default freshness window — bundles whose timestamp_unix differs
/// from the brain's clock by more than this are rejected.  5 minutes
/// is comfortable for clock-skew across mobile/desktop without being
/// permissive enough to enable a useful replay window.  Operator can
/// override via `BundleAcceptor.freshness_window_seconds`.
pub const DEFAULT_FRESHNESS_WINDOW_SECONDS: i64 = 5 * 60;

/// Default nonce-LRU bound.  Each entry is 64 chars (hex).  At 1024
/// entries that's ~64 KiB of memory — comfortable for the brain.
pub const DEFAULT_NONCE_LRU_CAPACITY: usize = 1024;

/// HTTP path the receive seam binds to by default.  Operator can
/// override via the cmdServe `--signed-bundle-endpoint` flag.
pub const DEFAULT_BUNDLE_ENDPOINT_PATH: []const u8 = "/api/v1/bundle";

// ─────────────────────────────────────────────────────────────────────
// Replay-protection LRU
// ─────────────────────────────────────────────────────────────────────

/// Bounded LRU of recently-seen nonces.  v0.1 — flat circular buffer +
/// linear scan.  At DEFAULT_NONCE_LRU_CAPACITY = 1024 the worst-case
/// scan is bounded; sustained high-volume traffic on the bundle
/// endpoint warrants a hashset-based replacement, but the brain's
/// expected mesh traffic is human-paced (mobile shells posting jobs,
/// federated tenant nodes posting per-event syncs).
pub const NonceLru = struct {
    allocator: std.mem.Allocator,
    /// Owned 64-byte hex slices.  `len` ≤ capacity.  Insertion order;
    /// the oldest entry sits at index 0 and gets evicted first.
    entries: std.ArrayList([]u8),
    capacity: usize,
    mu: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator, capacity: usize) NonceLru {
        return .{
            .allocator = allocator,
            .entries = .{},
            .capacity = capacity,
        };
    }

    pub fn deinit(self: *NonceLru) void {
        for (self.entries.items) |e| self.allocator.free(e);
        self.entries.deinit(self.allocator);
    }

    /// True if `nonce_hex` is already in the cache.
    pub fn contains(self: *NonceLru, nonce_hex: []const u8) bool {
        self.mu.lock();
        defer self.mu.unlock();
        for (self.entries.items) |e| {
            if (std.mem.eql(u8, e, nonce_hex)) return true;
        }
        return false;
    }

    /// Add `nonce_hex` to the cache.  Evicts the oldest entry if full.
    /// Caller must NOT call `contains` and `add` separately under
    /// concurrency — the BundleAcceptor uses `addIfFresh` which holds
    /// the mutex across both operations.
    pub fn addIfFresh(self: *NonceLru, nonce_hex: []const u8) !bool {
        self.mu.lock();
        defer self.mu.unlock();
        for (self.entries.items) |e| {
            if (std.mem.eql(u8, e, nonce_hex)) return false;
        }
        const owned = try self.allocator.dupe(u8, nonce_hex);
        errdefer self.allocator.free(owned);
        if (self.entries.items.len >= self.capacity) {
            // Evict oldest.
            const evicted = self.entries.orderedRemove(0);
            self.allocator.free(evicted);
        }
        try self.entries.append(self.allocator, owned);
        return true;
    }
};

// ─────────────────────────────────────────────────────────────────────
// Acceptor
// ─────────────────────────────────────────────────────────────────────

/// Borrowed state the receive seam needs.  Constructed once at
/// cmdServe boot, attached to the SiteServer when --signed-bundle-
/// endpoint is set.
pub const BundleAcceptor = struct {
    allocator: std.mem.Allocator,
    /// Borrowed — outlives the acceptor, dispatched by the daemon.
    dispatcher: *dispatcher_mod.Dispatcher,
    /// Borrowed — the cert store the chain verification reads from.
    cert_store: *identity_certs.CertStore,
    /// The brain's own root cert id.  Recipients must address the
    /// bundle to this id; broadcast bundles are rejected.
    /// v0.1 derives this from the operator root cert at boot; future
    /// fork allows per-tenant or per-extension recipient addresses
    /// for finer mesh routing.
    expected_recipient: ?[signed_bundle.CERT_ID_HEX_LEN]u8,
    /// Replay protection — see `NonceLru`.
    nonces: NonceLru,
    /// Timestamp freshness window in seconds.
    freshness_window_seconds: i64,
    /// Pinned-clock for tests.
    clock_fn: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        dispatcher: *dispatcher_mod.Dispatcher,
        cert_store: *identity_certs.CertStore,
        clock_fn: *const fn () i64,
    ) BundleAcceptor {
        return .{
            .allocator = allocator,
            .dispatcher = dispatcher,
            .cert_store = cert_store,
            .expected_recipient = null,
            .nonces = NonceLru.init(allocator, DEFAULT_NONCE_LRU_CAPACITY),
            .freshness_window_seconds = DEFAULT_FRESHNESS_WINDOW_SECONDS,
            .clock_fn = clock_fn,
        };
    }

    pub fn deinit(self: *BundleAcceptor) void {
        self.nonces.deinit();
    }

    /// Set the brain's own recipient address.  Mesh peers MUST address
    /// bundles to this cert id; mismatch → recipient_mismatch.
    pub fn setExpectedRecipient(self: *BundleAcceptor, cert_id: [signed_bundle.CERT_ID_HEX_LEN]u8) void {
        self.expected_recipient = cert_id;
    }
};

// ─────────────────────────────────────────────────────────────────────
// Outcome
// ─────────────────────────────────────────────────────────────────────

/// What `processBundle` returns to its transport caller.  `body` is the
/// wire.Response JSON the transport echoes back; `http_status` carries
/// the HTTP status code the HTTP wrapper should emit (transport-
/// agnostic transports may ignore it).  Caller frees `body` with
/// `allocator.free` on a non-empty payload.
pub const Outcome = struct {
    /// 200 / 400 / 401 / 403 / 409 / 500 — see the per-error branches
    /// in `processBundle`.
    http_status: std.http.Status,
    /// Owned wire.Response JSON.  Caller frees.
    body: []u8,
};

// ─────────────────────────────────────────────────────────────────────
// Pure entry point
// ─────────────────────────────────────────────────────────────────────

/// Decode + verify + dispatch + encode-response.  Transport-agnostic;
/// any inbound transport (HTTP today, BLE / multicast / Plexus push
/// future) builds an `Outcome` via this call.
///
/// The error path always produces a wire.Response failure envelope so
/// the caller always has bytes to send back — the HTTP wrapper writes
/// them under the appropriate status; a UDP/multicast transport just
/// emits them as the response frame.
pub fn processBundle(
    acceptor: *BundleAcceptor,
    bytes: []const u8,
) !Outcome {
    const allocator = acceptor.allocator;

    // 1. Decode.
    var owned = signed_bundle.decode(allocator, bytes) catch |err| {
        return failureOutcome(allocator, .bad_request, "", .validation_failed, codecErrName(err));
    };
    defer owned.deinit();
    const bundle = owned.bundle;

    // 2. Recipient address check.
    const expected = acceptor.expected_recipient orelse {
        // Brain hasn't been initialised yet (no operator root cert).
        // Fail closed with internal_server_error — operator surface
        // recovers via `brain device init`.
        return failureOutcome(allocator, .service_unavailable, "", .not_implemented, "recipient_unavailable");
    };
    const recipient = bundle.recipient_cert_id orelse {
        return failureOutcome(allocator, .forbidden, "", .capability_denied, "recipient_missing");
    };
    if (!std.mem.eql(u8, recipient[0..], expected[0..])) {
        return failureOutcome(allocator, .forbidden, "", .capability_denied, "recipient_mismatch");
    }

    // 3. Freshness window.
    const now = acceptor.clock_fn();
    const skew = absDiff(now, bundle.signature_metadata.timestamp_unix);
    if (skew > acceptor.freshness_window_seconds) {
        return failureOutcome(allocator, .gone, "", .validation_failed, "stale_or_future_timestamp");
    }

    // 4. Nonce LRU — adds + checks atomically.
    const fresh = acceptor.nonces.addIfFresh(bundle.signature_metadata.nonce_hex[0..]) catch {
        return failureOutcome(allocator, .internal_server_error, "", .validation_failed, "nonce_track_failed");
    };
    if (!fresh) {
        return failureOutcome(allocator, .conflict, "", .validation_failed, "nonce_replay");
    }

    // 5. Cert chain verification.
    var verified = signed_bundle.verifyCertChain(allocator, bundle, acceptor.cert_store) catch |err| {
        const msg = certChainErrName(err);
        const status: std.http.Status = switch (err) {
            signed_bundle.Error.leaf_cert_unknown,
            signed_bundle.Error.chain_intermediate_unknown,
            => .unauthorized,
            signed_bundle.Error.chain_parent_mismatch => .unauthorized,
            signed_bundle.Error.chain_empty => .bad_request,
            else => .internal_server_error,
        };
        return failureOutcome(allocator, status, "", .capability_denied, msg);
    };
    defer verified.deinit();

    // 6. Signature verification.
    signed_bundle.verifySignature(allocator, bundle, verified.leaf_pubkey) catch |err| {
        const msg = sigErrName(err);
        return failureOutcome(allocator, .unauthorized, "", .capability_denied, msg);
    };

    // 6.5. D-O5m.followup-6 Phase 2 — payload_type pre-classification.
    //
    // The current Phase 2 wire still wraps the inner content as a
    // wire.Request envelope (the dispatch.request shape), so the v0.1
    // dispatch path stays unchanged.  We additionally pre-classify
    // the payload_type so genuinely-unknown types fail closed with a
    // typed error instead of producing a confusing
    // payload_invalid_json downstream.
    //
    // Future phases extend the router with explicit handler
    // callbacks (oddjobz.attachment.create → attachments_handler.create_metadata,
    // oddjobz.voice-extract → voice_extract_http handler-level call,
    // oddjobz.cell.create → dispatcher-by-type-hash).  Today, all
    // recognised payload_types continue through the existing
    // dispatcher path; unknown types are rejected here.
    const route = payload_router.classify(bundle.payload_type);
    if (route == .unknown) {
        return failureOutcome(
            allocator,
            .bad_request,
            "",
            .validation_failed,
            payload_router.UNKNOWN_PAYLOAD_TYPE_ERR,
        );
    }

    // 7. Decode the inner dispatch Request envelope.
    var inner = wire.decodeRequest(allocator, bundle.payload) catch |err| {
        const msg = wireErrName(err);
        return failureOutcome(allocator, .bad_request, "", .validation_failed, msg);
    };
    defer inner.deinit();

    // 8. Build the DispatchContext.
    //
    // Use the bundle's nonce as the request_id so audit pairs are
    // greppable per-bundle.  transport_label = "signed_bundle" — the
    // only place this string lands; downstream audit consumers
    // (operator runbooks, helm panels) filter on it.
    const ctx = dispatcher_mod.DispatchContext{
        .auth = .{ .cert = .{ .placeholder = 0 } },
        .capabilities = dispatcher_mod.CapabilitySet.fromList(verified.capabilities),
        .meta = .{
            .request_id = bundle.signature_metadata.nonce_hex[0..],
            .timestamp_unix = bundle.signature_metadata.timestamp_unix,
            .transport_label = "signed_bundle",
        },
    };

    // 9. Dispatch.
    var result = acceptor.dispatcher.dispatch(
        &ctx,
        inner.request.resource,
        inner.request.cmd,
        inner.request.args_json,
    ) catch |err| {
        const kind: wire.ErrorKind = switch (err) {
            dispatcher_mod.DispatchError.unknown_resource => .unknown_resource,
            dispatcher_mod.DispatchError.unknown_command => .unknown_command,
            dispatcher_mod.DispatchError.capability_denied,
            dispatcher_mod.DispatchError.capability_not_declared,
            => .capability_denied,
            else => .validation_failed,
        };
        const status: std.http.Status = switch (kind) {
            .unknown_resource, .unknown_command => .not_found,
            .capability_denied => .forbidden,
            else => .bad_request,
        };
        return failureOutcome(allocator, status, inner.request.request_id, kind, @errorName(err));
    };
    defer result.deinit();

    // 10. Encode the success response.
    const resp = wire.Response{
        .request_id = inner.request.request_id,
        .result_json = if (result.payload.len > 0) result.payload else "null",
        .err = null,
    };
    const body = wire.encodeResponse(allocator, resp) catch |err| {
        return failureOutcome(allocator, .internal_server_error, inner.request.request_id, .validation_failed, @errorName(err));
    };
    return .{ .http_status = .ok, .body = body };
}

// ─────────────────────────────────────────────────────────────────────
// HTTP wrapper — POST <bundle_endpoint_path>
// ─────────────────────────────────────────────────────────────────────

/// Plug into `site_server.handleRequest` (gated on the configured
/// endpoint path).  Returns true iff the request was matched +
/// handled (caller skips the rest of routing).  Returns false on
/// non-matching paths so the surrounding router can try other handlers.
pub fn maybeHandle(
    request: *std.http.Server.Request,
    acceptor: *BundleAcceptor,
    endpoint_path: []const u8,
) !bool {
    const target = request.head.target;
    const method = request.head.method;
    if (!std.mem.eql(u8, target, endpoint_path)) return false;

    if (method != .POST) {
        try respondJsonStatic(request, .method_not_allowed,
            "{\"error\":\"method_not_allowed\",\"hint\":\"POST required\"}");
        return true;
    }

    // 1MB request-body cap — well above the 64KB envelope the cell-
    // engine's typical bundle uses, generous for future heavier
    // payloads, but bounded so a hostile peer can't OOM the brain.
    const max_body = signed_bundle.MAX_PAYLOAD_LEN + 64 * 1024;
    const body_buf = acceptor.allocator.alloc(u8, max_body) catch {
        try respondJsonStatic(request, .internal_server_error, "{\"error\":\"out_of_memory\"}");
        return true;
    };
    defer acceptor.allocator.free(body_buf);

    const body = readBody(request, body_buf) catch {
        try respondJsonStatic(request, .bad_request, "{\"error\":\"body_read_failed\"}");
        return true;
    };

    const outcome = processBundle(acceptor, body) catch {
        // processBundle never throws on a logical error — it produces
        // a typed Outcome.  Reaching here means an OOM during the
        // failure-envelope encode itself; we have nothing better to
        // emit than a static internal_error.
        try respondJsonStatic(request, .internal_server_error, "{\"error\":\"internal_error\"}");
        return true;
    };
    defer acceptor.allocator.free(outcome.body);

    try respondJsonOwned(request, outcome.http_status, outcome.body);
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

fn failureOutcome(
    allocator: std.mem.Allocator,
    status: std.http.Status,
    request_id: []const u8,
    kind: wire.ErrorKind,
    message: []const u8,
) !Outcome {
    const resp = wire.Response{
        .request_id = request_id,
        .result_json = "null",
        .err = wire.ErrorBody{ .kind = kind, .message = message, .details_json = "null" },
    };
    const body = try wire.encodeResponse(allocator, resp);
    return .{ .http_status = status, .body = body };
}

fn absDiff(a: i64, b: i64) i64 {
    const d = a - b;
    return if (d < 0) -d else d;
}

fn codecErrName(err: signed_bundle.Error) []const u8 {
    return switch (err) {
        signed_bundle.Error.invalid_json => "invalid_json",
        signed_bundle.Error.not_an_object => "not_an_object",
        signed_bundle.Error.missing_field => "missing_field",
        signed_bundle.Error.wrong_type => "wrong_type",
        signed_bundle.Error.unsupported_version => "unsupported_version",
        signed_bundle.Error.chain_too_long => "chain_too_long",
        signed_bundle.Error.chain_empty => "chain_empty",
        signed_bundle.Error.payload_too_long => "payload_too_long",
        signed_bundle.Error.bad_hex => "bad_hex",
        signed_bundle.Error.bad_signature_length => "bad_signature_length",
        signed_bundle.Error.bad_pubkey_length => "bad_pubkey_length",
        signed_bundle.Error.bad_cert_id_length => "bad_cert_id_length",
        signed_bundle.Error.bad_nonce_length => "bad_nonce_length",
        signed_bundle.Error.out_of_memory => "out_of_memory",
        else => "decode_failed",
    };
}

fn certChainErrName(err: anyerror) []const u8 {
    return switch (err) {
        signed_bundle.Error.leaf_cert_unknown => "leaf_cert_unknown",
        signed_bundle.Error.chain_intermediate_unknown => "chain_intermediate_unknown",
        signed_bundle.Error.chain_parent_mismatch => "chain_parent_mismatch",
        signed_bundle.Error.chain_empty => "chain_empty",
        else => "chain_verify_failed",
    };
}

fn sigErrName(err: anyerror) []const u8 {
    return switch (err) {
        signed_bundle.Error.signature_mismatch => "signature_mismatch",
        signed_bundle.Error.unknown_algorithm => "unknown_algorithm",
        else => "signature_verify_failed",
    };
}

fn wireErrName(err: anyerror) []const u8 {
    return switch (err) {
        wire.WireError.invalid_json => "payload_invalid_json",
        wire.WireError.not_an_object => "payload_not_an_object",
        wire.WireError.missing_field => "payload_missing_field",
        wire.WireError.wrong_type => "payload_wrong_type",
        wire.WireError.unsupported_version => "payload_unsupported_version",
        else => "payload_decode_failed",
    };
}

fn respondJsonStatic(request: *std.http.Server.Request, status: std.http.Status, body: []const u8) !void {
    request.respond(body, .{
        .status = status,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "cache-control", .value = "no-store" },
        },
    }) catch return error.write_failed;
}

fn respondJsonOwned(request: *std.http.Server.Request, status: std.http.Status, body: []const u8) !void {
    request.respond(body, .{
        .status = status,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "cache-control", .value = "no-store" },
        },
    }) catch return error.write_failed;
}

fn readBody(request: *std.http.Server.Request, out: []u8) ![]const u8 {
    const reader = request.readerExpectNone(out);
    const n = try reader.readSliceShort(out);
    return out[0..n];
}

// ─────────────────────────────────────────────────────────────────────
// Tests — pure logic.  Full verify→dispatch e2e lives in
// tests/signed_bundle_e2e_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "NonceLru: addIfFresh detects replay" {
    const allocator = std.testing.allocator;
    var lru = NonceLru.init(allocator, 4);
    defer lru.deinit();
    try std.testing.expect(try lru.addIfFresh("aaaa"));
    try std.testing.expect(!try lru.addIfFresh("aaaa"));
    try std.testing.expect(try lru.addIfFresh("bbbb"));
}

test "NonceLru: capacity-bounded eviction" {
    const allocator = std.testing.allocator;
    var lru = NonceLru.init(allocator, 2);
    defer lru.deinit();
    // [a]
    try std.testing.expect(try lru.addIfFresh("a"));
    // [a, b]
    try std.testing.expect(try lru.addIfFresh("b"));
    // capacity = 2, insert c → evicts a, state [b, c]
    try std.testing.expect(try lru.addIfFresh("c"));
    // a was evicted, insert it again → evicts b, state [c, a]
    try std.testing.expect(try lru.addIfFresh("a"));
    // c is still in the cache
    try std.testing.expect(!try lru.addIfFresh("c"));
    // b WAS evicted in the previous step → re-adding it succeeds
    try std.testing.expect(try lru.addIfFresh("b"));
}

test "absDiff" {
    try std.testing.expectEqual(@as(i64, 5), absDiff(10, 5));
    try std.testing.expectEqual(@as(i64, 5), absDiff(5, 10));
    try std.testing.expectEqual(@as(i64, 0), absDiff(7, 7));
}

```
