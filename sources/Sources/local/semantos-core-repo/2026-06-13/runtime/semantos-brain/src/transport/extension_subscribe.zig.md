---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/transport/extension_subscribe.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.291027+00:00
---

# runtime/semantos-brain/src/transport/extension_subscribe.zig

```zig
// Phase D-W2 Phase 2 — `POST /api/v1/bundle-frame` HTTP receive seam.
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §5.2
//   (Subscribing flow), §7 Phase 2.
//
// Mirrors `transport/signed_bundle.zig`'s pattern:
//   • A transport-agnostic core (`processFrame`) callable from any
//     wire transport (HTTP today; future BLE / multicast / Plexus push).
//   • An HTTP wrapper (`maybeHandle`) that the SiteServer's request
//     dispatch table consults BEFORE route lookup so an operator's
//     site config can't shadow the receive path.
//
// Distinct from D-W1 Phase 4's `/api/v1/bundle` endpoint — that
// endpoint receives `SignedBundle` envelopes (mesh dispatch).  This
// endpoint receives extension-bundle BRC-12 frames produced by the
// publisher's TS sidecar (`cartridges/oddjobz/brain/tools/subscribe-bundles
// .ts`).  Both transports plug into brain; both are opt-in per
// deployment.

const std = @import("std");
const subscriber = @import("extension_subscriber");
const tenant_manifest = @import("tenant_manifest");
const dispatcher_mod = @import("dispatcher");
const audit_log = @import("audit_log");
const nullifier_mod = @import("extension_nullifier");

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

/// Default HTTP path the receive seam binds to.  Operator can
/// override via `cmdServe`'s `--bundle-frame-endpoint` flag.
pub const DEFAULT_ENDPOINT_PATH: []const u8 = "/api/v1/bundle-frame";

/// Maximum POST body size — generous enough for a typical
/// `extension-bundle-v1` frame (the BRC-12 cap is 10 MiB on the
/// wire; we accept up to that here to match).
pub const MAX_FRAME_BYTES: usize = 10 * 1024 * 1024 + 64 * 1024;

// ─────────────────────────────────────────────────────────────────────
// Acceptor
// ─────────────────────────────────────────────────────────────────────

/// Borrowed state the receive seam needs.  Constructed once at
/// cmdServe boot when `--bundle-frame-endpoint` is supplied.
pub const FrameAcceptor = struct {
    allocator: std.mem.Allocator,
    /// Trusted-signer set, sourced from the tenant manifest at boot.
    /// Borrowed — outlives the acceptor (lives in the manifest's arena).
    manifest_signers: []const tenant_manifest.TrustedSigner,
    /// SPV client for publish-tx lookup + depth check.  Borrowed.
    spv: subscriber.SpvClient,
    /// Borrowed — the dispatcher applied frames hot-register against.
    dispatcher: ?*dispatcher_mod.Dispatcher,
    /// Borrowed — audit log every apply / rejection lands in.
    audit: ?*audit_log.AuditLog,
    /// Where to write applied bundles.  Layout:
    /// `<data_dir>/extensions/<namespace>/<version>/bundle.bin`.
    data_dir: []const u8,
    /// Verify-time options (SPV depth, etc.).
    verify_opts: subscriber.VerifyOptions = .{},

    // ── D-W2 Phase 3 — nullifier-frame state ──────────────────────
    //
    // The nullifier-frame path needs:
    //   • a recovery-authority lookup (resolves a signer's
    //     recovery_enrolment_id → on-chain pubkey of the rotation
    //     authority — typically backed by Plexus identity registry).
    //   • the manifest path (the canonical TOML on disk that the
    //     atomic revoke-and-promote rewrites).
    //   • the revoked-keys index path (per-tenant JSON-lines audit
    //     of every revoked pubkey; the spec footer (c) says
    //     `<data_dir>/extension-revoked-keys.json`).
    //
    // `init` (the Phase 2 constructor) leaves these empty so the
    // bundle-only deployments don't pay any cost.  `initFull`
    // populates them — operator boot wires both at once when the
    // tenant subscribes to nullifier frames.
    recovery_authority: nullifier_mod.RecoveryAuthorityLookup = .{
        .state = null,
        .lookup_fn = nullRecoveryLookup,
    },
    manifest_path: []const u8 = "",
    revoked_keys_index_path: []const u8 = "",

    pub fn init(
        allocator: std.mem.Allocator,
        manifest_signers: []const tenant_manifest.TrustedSigner,
        spv: subscriber.SpvClient,
        dispatcher: ?*dispatcher_mod.Dispatcher,
        audit: ?*audit_log.AuditLog,
        data_dir: []const u8,
    ) FrameAcceptor {
        return .{
            .allocator = allocator,
            .manifest_signers = manifest_signers,
            .spv = spv,
            .dispatcher = dispatcher,
            .audit = audit,
            .data_dir = data_dir,
        };
    }

    /// Construct an acceptor wired for both bundle frames AND
    /// nullifier frames.  D-W2 Phase 3.
    pub fn initFull(
        allocator: std.mem.Allocator,
        manifest_signers: []const tenant_manifest.TrustedSigner,
        spv: subscriber.SpvClient,
        dispatcher: ?*dispatcher_mod.Dispatcher,
        audit: ?*audit_log.AuditLog,
        data_dir: []const u8,
        recovery_authority: nullifier_mod.RecoveryAuthorityLookup,
        manifest_path: []const u8,
        revoked_keys_index_path: []const u8,
    ) FrameAcceptor {
        return .{
            .allocator = allocator,
            .manifest_signers = manifest_signers,
            .spv = spv,
            .dispatcher = dispatcher,
            .audit = audit,
            .data_dir = data_dir,
            .recovery_authority = recovery_authority,
            .manifest_path = manifest_path,
            .revoked_keys_index_path = revoked_keys_index_path,
        };
    }
};

fn nullRecoveryLookup(state: ?*anyopaque, recovery_enrolment_id: []const u8) ?[nullifier_mod.PUBKEY_LEN]u8 {
    _ = state;
    _ = recovery_enrolment_id;
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Outcome
// ─────────────────────────────────────────────────────────────────────

pub const Outcome = struct {
    http_status: std.http.Status,
    /// Owned JSON body the wire transport echoes back.  Caller frees
    /// via `allocator.free` on a non-empty payload.
    body: []u8,
};

// ─────────────────────────────────────────────────────────────────────
// processFrame — transport-agnostic core
// ─────────────────────────────────────────────────────────────────────

/// Decode + verify + apply.  Transport-agnostic; any inbound
/// transport (HTTP today; BLE / multicast / Plexus push future)
/// builds an `Outcome` via this call.
///
/// Error path produces a typed JSON failure body so the caller always
/// has bytes to send back.  HTTP wrapper writes them under the
/// appropriate status; a UDP / multicast transport emits them as the
/// response frame.
///
/// D-W2 Phase 3 — switches on the inner-payload tag to dispatch to
/// either the bundle-frame path (Phase 2) or the nullifier-frame path
/// (this phase).  The wire is the same; the inner tag selects.
pub fn processFrame(
    acceptor: *FrameAcceptor,
    frame_bytes: []const u8,
) !Outcome {
    const allocator = acceptor.allocator;

    const kind = subscriber.decodeFrameKind(frame_bytes) catch |err| {
        return failureOutcome(allocator, err, acceptor.audit);
    };

    switch (kind) {
        .extension_bundle => return processBundleFrame(acceptor, frame_bytes),
        .nullifier => return processNullifierFrame(acceptor, frame_bytes),
    }
}

fn processBundleFrame(acceptor: *FrameAcceptor, frame_bytes: []const u8) !Outcome {
    const allocator = acceptor.allocator;

    const vf = subscriber.verifyFrame(
        frame_bytes,
        acceptor.manifest_signers,
        acceptor.spv,
        acceptor.verify_opts,
    ) catch |err| {
        return failureOutcome(allocator, err, acceptor.audit);
    };

    var outcome = subscriber.applyVerifiedFrame(
        allocator,
        vf,
        acceptor.data_dir,
        acceptor.dispatcher,
        acceptor.audit,
    ) catch |err| {
        return failureOutcome(allocator, err, acceptor.audit);
    };
    defer outcome.deinit(allocator);

    // Build success body.  JSON shape pinned for the operator runbook
    // + the TS sidecar's logging:
    //   { "status": "ok", "namespace": "...", "version": "...",
    //     "registered": true, "already_applied": false,
    //     "bundle_hash": "<64-hex>" }
    const body = std.fmt.allocPrint(
        allocator,
        "{{\"status\":\"ok\",\"frame_type\":\"extension-bundle\",\"namespace\":\"{s}\",\"version\":\"{s}\",\"signer\":\"{s}\",\"registered\":{s},\"already_applied\":{s},\"bundle_hash\":\"{s}\"}}",
        .{
            vf.extension_name,
            vf.version,
            vf.signer_name,
            if (outcome.registered) "true" else "false",
            if (outcome.already_applied) "true" else "false",
            outcome.bundle_hash_hex,
        },
    ) catch return error.OutOfMemory;
    return .{ .http_status = .ok, .body = body };
}

fn processNullifierFrame(acceptor: *FrameAcceptor, frame_bytes: []const u8) !Outcome {
    const allocator = acceptor.allocator;

    const result = subscriber.processNullifierFrame(
        allocator,
        frame_bytes,
        acceptor.manifest_signers,
        acceptor.recovery_authority,
        acceptor.manifest_path,
        acceptor.revoked_keys_index_path,
        acceptor.audit,
    ) catch |err| {
        return failureOutcome(allocator, err, acceptor.audit);
    };

    // JSON shape pinned for the operator runbook:
    //   { "status": "ok", "frame_type": "nullifier",
    //     "signer": "...", "applied": true, "already_applied": false,
    //     "promoted_replacement": false, "platform_tier": false }
    const body = std.fmt.allocPrint(
        allocator,
        "{{\"status\":\"ok\",\"frame_type\":\"nullifier\",\"signer\":\"{s}\",\"applied\":{s},\"already_applied\":{s},\"promoted_replacement\":{s},\"platform_tier\":{s}}}",
        .{
            result.signer_name,
            if (result.applied) "true" else "false",
            if (!result.applied) "true" else "false",
            if (result.promoted_replacement) "true" else "false",
            if (result.platform_tier) "true" else "false",
        },
    ) catch return error.OutOfMemory;
    return .{ .http_status = .ok, .body = body };
}

fn failureOutcome(
    allocator: std.mem.Allocator,
    err: subscriber.VerifyError,
    audit: ?*audit_log.AuditLog,
) !Outcome {
    const kind = errName(err);
    const status: std.http.Status = httpStatusFor(err);
    const body = std.fmt.allocPrint(
        allocator,
        "{{\"status\":\"err\",\"kind\":\"{s}\"}}",
        .{kind},
    ) catch return error.OutOfMemory;

    if (audit) |a| {
        var detail_buf: [256]u8 = undefined;
        const detail = std.fmt.bufPrint(
            &detail_buf,
            "phase=reject kind={s}",
            .{kind},
        ) catch detail_buf[0..0];
        a.record(allocator, .{
            .module = "extension_subscriber",
            .op = "extension.frame_recv",
            .result = .denied,
            .detail = detail,
        }) catch {};
    }
    return .{ .http_status = status, .body = body };
}

pub fn errName(err: subscriber.VerifyError) []const u8 {
    return switch (err) {
        error.frame_too_small => "frame_too_small",
        error.frame_bad_magic => "frame_bad_magic",
        error.frame_bad_protocol => "frame_bad_protocol",
        error.frame_bad_version => "frame_bad_version",
        error.frame_payload_oversize => "frame_payload_oversize",
        error.frame_payload_truncated => "frame_payload_truncated",
        error.payload_bad_tag => "payload_bad_tag",
        error.payload_truncated => "payload_truncated",
        error.payload_bad_namespace => "payload_bad_namespace",
        error.payload_bad_version => "payload_bad_version",
        error.payload_bad_signer_pubkey => "payload_bad_signer_pubkey",
        error.spv_verify_failed => "spv_verify_failed",
        error.hash_mismatch => "hash_mismatch",
        error.signature_invalid => "signature_invalid",
        error.unknown_signer => "unknown_signer",
        error.scope_mismatch => "scope_mismatch",
        error.bad_publish_payload => "bad_publish_payload",
        // D-W2 Phase 3 — nullifier verify variants.
        error.unknown_target_signer => "unknown_target_signer",
        error.bad_rotation_authority_signature => "bad_rotation_authority_signature",
        error.missing_replacement_for_rotation => "missing_replacement_for_rotation",
        error.missing_rotation_authority => "missing_rotation_authority",
        error.nullifier_payload_bad => "nullifier_payload_bad",
        error.apply_io_failed => "apply_io_failed",
        error.apply_manifest_failed => "apply_manifest_failed",
        error.out_of_memory => "out_of_memory",
    };
}

fn httpStatusFor(err: subscriber.VerifyError) std.http.Status {
    return switch (err) {
        // 400 — frame is malformed or doesn't match the schema.
        error.frame_too_small,
        error.frame_bad_magic,
        error.frame_bad_protocol,
        error.frame_bad_version,
        error.frame_payload_oversize,
        error.frame_payload_truncated,
        error.payload_bad_tag,
        error.payload_truncated,
        error.payload_bad_namespace,
        error.payload_bad_version,
        error.payload_bad_signer_pubkey,
        error.bad_publish_payload,
        error.nullifier_payload_bad,
        error.missing_replacement_for_rotation,
        => .bad_request,

        // 401 — signature didn't validate against the publish-tx, or
        // the rotation-authority signature didn't validate.
        error.signature_invalid,
        error.bad_rotation_authority_signature,
        => .unauthorized,

        // 403 — signer not trusted (bundle path), nullifier targets
        // a pubkey not in the manifest (nullifier path), scope
        // violation, or hash mismatch (bundle bytes don't match
        // on-chain commitment).
        error.unknown_signer,
        error.unknown_target_signer,
        error.missing_rotation_authority,
        error.scope_mismatch,
        error.hash_mismatch,
        => .forbidden,

        // 410 — SPV says the publish tx isn't deep enough (or
        // doesn't exist).  Tunable: operator may relax depth.
        error.spv_verify_failed => .gone,

        // 500 — apply failed (disk I/O, OOM, manifest rewrite).
        error.apply_io_failed,
        error.apply_manifest_failed,
        error.out_of_memory,
        => .internal_server_error,
    };
}

// ─────────────────────────────────────────────────────────────────────
// HTTP wrapper — POST <endpoint_path>
// ─────────────────────────────────────────────────────────────────────

/// Plug into `site_server.handleRequest` (gated on the configured
/// endpoint path).  Returns `true` iff the request was matched +
/// handled.  Returns `false` on non-matching paths so the surrounding
/// router can try other handlers.
pub fn maybeHandle(
    request: *std.http.Server.Request,
    acceptor: *FrameAcceptor,
    endpoint_path: []const u8,
) !bool {
    const target = request.head.target;
    const method = request.head.method;
    if (!std.mem.eql(u8, target, endpoint_path)) return false;

    if (method != .POST) {
        try respondJsonStatic(request, .method_not_allowed,
            "{\"status\":\"err\",\"kind\":\"method_not_allowed\"}");
        return true;
    }

    const body_buf = acceptor.allocator.alloc(u8, MAX_FRAME_BYTES) catch {
        try respondJsonStatic(request, .internal_server_error,
            "{\"status\":\"err\",\"kind\":\"out_of_memory\"}");
        return true;
    };
    defer acceptor.allocator.free(body_buf);

    const body = readBody(request, body_buf) catch {
        try respondJsonStatic(request, .bad_request,
            "{\"status\":\"err\",\"kind\":\"body_read_failed\"}");
        return true;
    };

    const outcome = processFrame(acceptor, body) catch {
        try respondJsonStatic(request, .internal_server_error,
            "{\"status\":\"err\",\"kind\":\"internal_error\"}");
        return true;
    };
    defer acceptor.allocator.free(outcome.body);

    try respondJsonOwned(request, outcome.http_status, outcome.body);
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

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
// Tests — pure logic.  Full receive→verify→apply e2e lives in
// tests/extension_subscribe_e2e_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "errName covers every VerifyError variant" {
    // Touch every variant; if a new one is added the switch above
    // forces a compile error before this test runs.
    _ = errName(error.frame_too_small);
    _ = errName(error.frame_bad_magic);
    _ = errName(error.unknown_signer);
    _ = errName(error.scope_mismatch);
    _ = errName(error.hash_mismatch);
    _ = errName(error.signature_invalid);
    _ = errName(error.spv_verify_failed);
    _ = errName(error.bad_publish_payload);
}

test "httpStatusFor mapping" {
    try std.testing.expectEqual(std.http.Status.bad_request, httpStatusFor(error.frame_too_small));
    try std.testing.expectEqual(std.http.Status.bad_request, httpStatusFor(error.payload_bad_tag));
    try std.testing.expectEqual(std.http.Status.unauthorized, httpStatusFor(error.signature_invalid));
    try std.testing.expectEqual(std.http.Status.forbidden, httpStatusFor(error.unknown_signer));
    try std.testing.expectEqual(std.http.Status.forbidden, httpStatusFor(error.scope_mismatch));
    try std.testing.expectEqual(std.http.Status.forbidden, httpStatusFor(error.hash_mismatch));
    try std.testing.expectEqual(std.http.Status.gone, httpStatusFor(error.spv_verify_failed));
    try std.testing.expectEqual(std.http.Status.internal_server_error, httpStatusFor(error.apply_io_failed));
}

```
