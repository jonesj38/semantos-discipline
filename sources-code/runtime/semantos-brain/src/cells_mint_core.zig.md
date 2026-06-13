---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cells_mint_core.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.246216+00:00
---

# runtime/semantos-brain/src/cells_mint_core.zig

```zig
//! BRAIN-GENERIC-MINT-VERB — transport-agnostic mint core (M1.7).
//!
//! `mintCellCore` is the single source of truth for the generic cell-mint
//! pipeline's BODY: structural schema validation → operator-signature verify →
//! linearity map → encode → cell-script dispatch hook → persist → auto-anchor →
//! broker publish. It takes an already-parsed `MintRequest` + resolved
//! `CellTypeEntry` and returns a structured `MintOutcome` — it touches NO
//! transport (no HTTP status writes, no RPC frames).
//!
//! Two callers share it verbatim so their behaviour can't drift:
//!   - `site_server/reactor.zig::reactorHandleCellsMint` — the `POST /api/v1/cells`
//!     HTTP path (does acceptor/method/auth/parse/lookup, then calls this).
//!   - `wss_rpc_methods.zig::cellsMint` — the `cells.mint` method on the unified
//!     `/api/v1/rpc` WSS channel (auth bound at upgrade, then parse/lookup/this).
//!
//! This is a LEAF over the heavy deps (substrate_entity / anchor_emitter /
//! attachments_upload_http / cells_mint_validator) + cells_mint_http (Acceptor +
//! MintRequest). None of those import this module, so adding it introduces no
//! dependency cycle — the trap the M1.7 blocker flagged. Resolved by extracting
//! a NEW leaf rather than growing cells_mint_http's import surface.

const std = @import("std");

const cells_mint_http = @import("cells_mint_http");
const cells_mint_validator = @import("cells_mint_validator");
const cartridge_cell_registry = @import("cartridge_cell_registry");
const substrate_entity = @import("substrate_entity");
const attachments_upload_http = @import("attachments_upload_http");
const anchor_emitter_mod = @import("anchor_emitter");

pub const Acceptor = cells_mint_http.Acceptor;
pub const MintRequest = cells_mint_http.MintRequest;
pub const CellTypeEntry = cartridge_cell_registry.CellTypeEntry;

/// Structured result of the mint body. Carries everything BOTH transports need
/// to render their own wire shape: `created` → 201 / `res` frame; `failed` →
/// the HTTP status + `error` body the reactor wrote inline before this
/// extraction, OR the WSS `err` frame code+message.
pub const MintOutcome = union(enum) {
    created: Created,
    failed: Failure,

    pub const Created = struct {
        /// Lower-hex sha256 of the persisted 1024-byte cell.
        cell_hash_hex: [64]u8,
        /// Borrowed from the registry entry (module-scope, process-lifetime).
        cartridge_id: []const u8,
        /// Borrowed from the registry entry (module-scope, process-lifetime).
        cell_type_name: []const u8,
        persisted_at: i64,
    };

    pub const Failure = struct {
        /// The status the HTTP path returned for this failure pre-extraction.
        http_status: u16,
        /// The `"error"` tag string in the HTTP JSON body (a static literal).
        error_tag: []const u8,
        /// Optional structured detail. Any borrowed slice here is duped into
        /// the allocator passed to `mintCellCore`, so it outlives any internal
        /// arena (e.g. the validator's parse arena).
        detail: ?Detail = null,

        pub const Detail = union(enum) {
            /// `,"field":"<f>","expectedType":"<t>"` — schema validation.
            field_type: struct { field: []const u8, expected_type: []const u8 },
            /// `,"reason":"<r>"` — handler script rejected the mint.
            reason: []const u8,
            /// `,"hint":"<h>"` — supplementary operator hint.
            hint: []const u8,
        };

        /// Map the HTTP status to the WSS RPC error-code vocabulary
        /// (unauthorized | forbidden | bad_request | not_found | internal).
        pub fn rpcCode(self: Failure) []const u8 {
            return switch (self.http_status) {
                400, 413 => "bad_request",
                401 => "unauthorized",
                403 => "forbidden",
                404 => "not_found",
                else => "internal",
            };
        }
    };

    /// Convenience constructor for a detail-less failure with a literal tag.
    fn fail(status: u16, tag: []const u8) MintOutcome {
        return .{ .failed = .{ .http_status = status, .error_tag = tag } };
    }
};

/// Run the mint body (steps 5b–9 of the legacy reactor handler) over an
/// already-parsed request + resolved cellType. The caller has already done
/// acceptor presence, method/auth gating, body parse, and registry lookup.
///
/// `alloc` is the per-request allocator; any owned detail in the returned
/// `MintOutcome.Failure` is allocated from it. The success path allocates
/// nothing on `alloc` (the caller formats the response body).
pub fn mintCellCore(
    acceptor: *const Acceptor,
    mint_req: *const MintRequest,
    entry: CellTypeEntry,
    alloc: std.mem.Allocator,
) MintOutcome {
    // 5b. Structural payload validation against the cellType's payloadSchema.
    //     Skipped when the cellType declares no schema. On failure, the
    //     validator's failure fields point INTO a local parse arena, so we
    //     dupe them onto `alloc` before the arena deinits.
    if (entry.payload_schema_raw) |schema_raw| {
        var validate_arena = std.heap.ArenaAllocator.init(alloc);
        defer validate_arena.deinit();
        var failure: ?cells_mint_validator.ValidationFailure = null;
        cells_mint_validator.validate(
            validate_arena.allocator(),
            schema_raw,
            mint_req.payload_json,
            &failure,
        ) catch |err| switch (err) {
            cells_mint_validator.ValidationError.missing_required_field,
            cells_mint_validator.ValidationError.wrong_field_type,
            => {
                const tag = if (err == cells_mint_validator.ValidationError.missing_required_field)
                    "missing_required_field"
                else
                    "wrong_field_type";
                const f = failure orelse cells_mint_validator.ValidationFailure{
                    .field_name = "?",
                    .expected_type = "any",
                };
                // Dupe out of the arena; on OOM degrade to a detail-less tag
                // (still the same error_tag → identical 400 class).
                const field_owned = alloc.dupe(u8, f.field_name) catch
                    return MintOutcome.fail(400, tag);
                const type_owned = alloc.dupe(u8, f.expected_type) catch {
                    alloc.free(field_owned);
                    return MintOutcome.fail(400, tag);
                };
                return .{ .failed = .{
                    .http_status = 400,
                    .error_tag = tag,
                    .detail = .{ .field_type = .{ .field = field_owned, .expected_type = type_owned } },
                } };
            },
            else => {
                // invalid_schema / invalid_payload / out_of_memory
                return MintOutcome.fail(500, "schema_validation_failed");
            },
        };
    }

    // 5c. Operator-signature gate (sovereign mint). When the mint carries an
    //     operator signature, verify it against the signer cert's pubkey over
    //     sha256(canonicaliseCellPayload(payload)) BEFORE assembling. Absent
    //     signature = bearer-only path, unchanged.
    if (mint_req.signature) |sig| {
        const certs = acceptor.certs orelse
            return .{ .failed = .{
                .http_status = 401,
                .error_tag = "signature_unverifiable",
                .detail = .{ .hint = "no cert store wired" },
            } };
        const cert = certs.get(mint_req.signer_cert_id_hex.?) catch
            return MintOutcome.fail(401, "cert_unknown");
        if (!attachments_upload_http.verifyPayloadSignature(alloc, mint_req.payload_json, sig, cert.pubkey)) {
            return MintOutcome.fail(401, "signature_invalid");
        }
    }

    // 6. Map registry Linearity → substrate_entity.LinearityClass.
    //    PERSISTENT + EPHEMERAL have no kernel slot; both map to relevant.
    const linearity_class: substrate_entity.LinearityClass = switch (entry.linearity) {
        .LINEAR => .linear,
        .AFFINE => .affine,
        .RELEVANT, .PERSISTENT, .EPHEMERAL => .relevant,
        .DEBUG => .debug,
    };

    // 7. Encode the cell. Owner id zero-filled — v0.1.0 has no cert→owner
    //    derivation (lands with Phase-1b BCA work).
    const cell = substrate_entity.encodeFromTypeHash(.{
        .type_hash = mint_req.type_hash,
        .linearity = linearity_class,
        .owner_id = [_]u8{0} ** 16,
        .payload_json = mint_req.payload_json,
    }) catch |err| switch (err) {
        substrate_entity.EncodeError.payload_too_large => return .{ .failed = .{
            .http_status = 413,
            .error_tag = "payload_too_large",
            .detail = .{ .hint = "payload exceeds 768-byte inline budget; octave-1 escalation pending" },
        } },
    };

    // 7b. Cell-script handler dispatch. When wired, runs the same step-4.5
    //     pipeline the REPL `cells mint` verb runs (lookup script-handler
    //     registry, build per-script Context, execute bytecode, persist
    //     emitted cells) BEFORE the input cell is persisted at step 8.
    //     `.skipped` = no handler for this typeHash (preserves the plain
    //     substrate-cell path). Reason/hint strings come from the dispatch
    //     callback; dupe them onto `alloc` so they outlive its scratch.
    if (acceptor.dispatch_input_cell_fn) |dispatch_fn| {
        if (acceptor.dispatch_ctx) |dispatch_ctx| {
            const outcome = dispatch_fn(dispatch_ctx, alloc, &mint_req.type_hash, entry.cartridge_id, &cell);
            switch (outcome) {
                .skipped, .success => {},
                .rejection => |reason| {
                    const reason_owned = alloc.dupe(u8, reason) catch
                        return MintOutcome.fail(400, "handler_rejected");
                    return .{ .failed = .{
                        .http_status = 400,
                        .error_tag = "handler_rejected",
                        .detail = .{ .reason = reason_owned },
                    } };
                },
                .internal_error => |msg| {
                    const msg_owned = alloc.dupe(u8, msg) catch
                        return MintOutcome.fail(500, "handler_internal_error");
                    return .{ .failed = .{
                        .http_status = 500,
                        .error_tag = "handler_internal_error",
                        .detail = .{ .hint = msg_owned },
                    } };
                },
            }
        }
    }

    // 8. Persist.
    const cell_hash = acceptor.cell_store.put(&cell) catch
        return MintOutcome.fail(500, "persist_failed");

    // 8.5. Auto-anchor every persisted cell when the operator opts in. The
    //      emit is fire-and-forget (.bsv backend returns .pending; mining is
    //      out of band). The AnchorAttestation recursion break is enforced
    //      inside AnchorEmitter.emit() — we pass the generic substrate-cell
    //      entity_tag (0x10); anchor-sentinel cells (0x20) short-circuit.
    if (acceptor.auto_anchor_on_mint) {
        var anchor_emitter = anchor_emitter_mod.AnchorEmitter.initWithBroker(
            alloc,
            .bsv,
            acceptor.broker,
        );
        _ = anchor_emitter.emit(.{
            .cell_hash = cell_hash,
            .type_hash = mint_req.type_hash,
            .entity_tag = 0x10,
            .cartridge_id = entry.cartridge_id,
        });
    }

    // 9. Broker publish. Subject: cells.<cartridge-id>.minted. Best-effort —
    //    a broker failure does NOT fail the mint (cell already persisted).
    var cell_hash_hex: [64]u8 = undefined;
    bytesToHex(&cell_hash, &cell_hash_hex);
    var subject_buf: [128]u8 = undefined;
    const subject = std.fmt.bufPrint(&subject_buf, "cells.{s}.minted", .{entry.cartridge_id}) catch
        "cells.minted";
    var event_payload_buf: [512]u8 = undefined;
    const event_payload = std.fmt.bufPrint(
        &event_payload_buf,
        "{{\"cellId\":\"{s}\",\"cartridgeId\":\"{s}\",\"cellType\":\"{s}\"}}",
        .{ cell_hash_hex[0..64], entry.cartridge_id, entry.cell_type_name },
    ) catch event_payload_buf[0..0];
    acceptor.broker.publish(.{
        .type = subject,
        .payload_json = event_payload,
    });

    return .{ .created = .{
        .cell_hash_hex = cell_hash_hex,
        .cartridge_id = entry.cartridge_id,
        .cell_type_name = entry.cell_type_name,
        .persisted_at = std.time.milliTimestamp(),
    } };
}

/// Lower-hex encode `bytes` into `out` (out.len must be 2*bytes.len). Local
/// mirror of the reactor's helper so this module stays a leaf.
fn bytesToHex(bytes: []const u8, out: []u8) void {
    const hex = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = hex[b >> 4];
        out[i * 2 + 1] = hex[b & 0x0f];
    }
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests. The live mint pipeline (store + registry + dispatch) is
// exercised by the reactor + cells_mint_handler suites; here we lock the
// pure pieces the M1.7 extraction introduced: the HTTP-status → WSS-RPC
// error-code mapping and the hex helper.
// ─────────────────────────────────────────────────────────────────────
const testing = std.testing;

test "Failure.rpcCode maps HTTP status to the WSS RPC code vocabulary" {
    const F = MintOutcome.Failure;
    try testing.expectEqualStrings("bad_request", (F{ .http_status = 400, .error_tag = "x" }).rpcCode());
    try testing.expectEqualStrings("bad_request", (F{ .http_status = 413, .error_tag = "x" }).rpcCode());
    try testing.expectEqualStrings("unauthorized", (F{ .http_status = 401, .error_tag = "x" }).rpcCode());
    try testing.expectEqualStrings("forbidden", (F{ .http_status = 403, .error_tag = "x" }).rpcCode());
    try testing.expectEqualStrings("not_found", (F{ .http_status = 404, .error_tag = "x" }).rpcCode());
    try testing.expectEqualStrings("internal", (F{ .http_status = 500, .error_tag = "x" }).rpcCode());
}

test "bytesToHex — lower-hex round-trip" {
    var out: [8]u8 = undefined;
    bytesToHex(&[_]u8{ 0x00, 0xde, 0xad, 0xff }, &out);
    try testing.expectEqualStrings("00deadff", &out);
}

```
