---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/payload_type_router.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.252294+00:00
---

# runtime/semantos-brain/src/payload_type_router.zig

```zig
// D-O5m.followup-6 Phase 2 — SignedBundle payload_type router.
//
// Reference: this brief.  The brain receives SignedBundles via
// `transport/signed_bundle.zig::processBundle`.  Today the bundle's
// `payload` is a wire.Request envelope and routing happens through
// `dispatcher.dispatch(ctx, resource, cmd, args_json)`.
//
// Phase 2 introduces three explicit oddjobz.* payload types that the
// mobile peer publishes through the mesh transport:
//
//   • oddjobz.attachment.create — payload is the attachment metadata
//     JSON; the brain routes this through the attachments handler's
//     create_metadata path (the multipart blob arrives via the
//     existing /api/v1/attachments/upload endpoint; the bundle is
//     metadata-only).
//
//   • oddjobz.voice-extract — payload is the {transcript, metadata}
//     envelope JSON; the brain routes this through voice_extract_http's
//     handler-level call (without re-parsing multipart, since the
//     blob arrived via the existing endpoint).
//
//   • oddjobz.cell.create — payload is the cell-write JSON; the brain
//     routes this through whichever dispatcher resource matches the
//     cell's type-hash.
//
// This module is the mapping layer: payload_type string → routing
// decision.  It does NOT do the routing itself (that's
// `transport/signed_bundle.zig`'s job).  Keeping the mapping
// stand-alone means future payload types (oddjobz.invoice.create,
// oddjobz.helm.event, …) plug in here without touching the receive
// pipeline's verify/audit code.
//
// Phase 2 ships the seam: the router recognises the three types above
// and returns typed routing decisions.  The wire-level dispatch
// remains delegated to the existing dispatcher path (the current
// `wire.Request` envelope stays the canonical inner shape; the new
// payload_types simply pre-classify the route the dispatcher will
// take).  Future phases extend this router with explicit handler
// callbacks that bypass the dispatcher when the routing is statically
// known.

const std = @import("std");

/// Payload-type tag for the wire.Request envelope (the v0.1 default).
/// Pre-existing bundles use this tag and route through the
/// dispatcher's resource+cmd path.
pub const PAYLOAD_TYPE_DISPATCH_REQUEST: []const u8 = "dispatch.request";

/// New in Phase 2 — attachment-create cells (metadata only; blob
/// rides the multipart upload endpoint).
pub const PAYLOAD_TYPE_ATTACHMENT_CREATE: []const u8 = "oddjobz.attachment.create";

/// New in Phase 2 — voice-extract cells (transcript + metadata; audio
/// blob rides the multipart endpoint).
pub const PAYLOAD_TYPE_VOICE_EXTRACT: []const u8 = "oddjobz.voice-extract";

/// New in Phase 2 — generic signed-cell creates.  Payload is the
/// cell-write JSON; the dispatcher's resource selection happens via
/// the cell's type-hash.
pub const PAYLOAD_TYPE_CELL_CREATE: []const u8 = "oddjobz.cell.create";

/// Discriminator the receive pipeline switches on.  Future payload
/// types extend this enum (oddjobz.invoice.create, helm.event, …)
/// without changing the pipeline's structure.
pub const RouteDecision = enum {
    /// Default path — payload is a wire.Request envelope; dispatcher
    /// routes by resource+cmd.
    dispatch_request,
    /// Mesh-published attachment-create.  Payload is the attachment
    /// metadata JSON; attachments handler create_metadata path.
    attachment_create,
    /// Mesh-published voice-extract.  Payload is the {transcript,
    /// metadata} envelope JSON; voice-extract handler.
    voice_extract,
    /// Mesh-published generic cell-create.  Payload is the cell-write
    /// JSON; dispatcher routes by the cell's type-hash.
    cell_create,
    /// Unknown payload_type — receive pipeline rejects with a typed
    /// `unknown_payload_type` error.
    unknown,
};

/// Map a payload_type string to a [RouteDecision].
pub fn classify(payload_type: []const u8) RouteDecision {
    if (std.mem.eql(u8, payload_type, PAYLOAD_TYPE_DISPATCH_REQUEST)) {
        return .dispatch_request;
    }
    if (std.mem.eql(u8, payload_type, PAYLOAD_TYPE_ATTACHMENT_CREATE)) {
        return .attachment_create;
    }
    if (std.mem.eql(u8, payload_type, PAYLOAD_TYPE_VOICE_EXTRACT)) {
        return .voice_extract;
    }
    if (std.mem.eql(u8, payload_type, PAYLOAD_TYPE_CELL_CREATE)) {
        return .cell_create;
    }
    return .unknown;
}

/// Wire-string for the typed-error JSON body the receive pipeline
/// emits on `unknown` classification.  Pinned so the mobile fallback
/// flow can match on this exact string.
pub const UNKNOWN_PAYLOAD_TYPE_ERR: []const u8 = "unknown_payload_type";

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

test "classify recognises the v0.1 + Phase 2 payload types" {
    try std.testing.expectEqual(RouteDecision.dispatch_request, classify("dispatch.request"));
    try std.testing.expectEqual(RouteDecision.attachment_create, classify("oddjobz.attachment.create"));
    try std.testing.expectEqual(RouteDecision.voice_extract, classify("oddjobz.voice-extract"));
    try std.testing.expectEqual(RouteDecision.cell_create, classify("oddjobz.cell.create"));
}

test "classify rejects unknown payload types" {
    try std.testing.expectEqual(RouteDecision.unknown, classify(""));
    try std.testing.expectEqual(RouteDecision.unknown, classify("oddjobz.unknown.thing"));
    try std.testing.expectEqual(RouteDecision.unknown, classify("plexus.identity.update"));
    try std.testing.expectEqual(RouteDecision.unknown, classify("attachment.create")); // no oddjobz prefix
}

```
