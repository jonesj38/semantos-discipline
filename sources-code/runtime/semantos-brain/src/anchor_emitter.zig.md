---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/anchor_emitter.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.254295+00:00
---

# runtime/semantos-brain/src/anchor_emitter.zig

```zig
// Zig AnchorEmitter — brain-side seam for cell anchoring (§11.10 order 3a).
//
// Reference: docs/prd/UNIFICATION-ROADMAP.md §11.10 v0.12 order 3a;
//            docs/prd/D-LIFT-BSV-ANCHOR.md (cartridge carve status);
//            core/protocol-types/src/anchor.ts (AnchorAdapter interface
//            the real backend bridges into);
//            core/anchor-attestation/src/operations.ts (AnchorAttestation
//            cell schema the real backend mints);
//            cartridges/wallet-headers/brain/ (the cartridge that will
//            actually do the BSV signing + broadcast);
//            runtime/semantos-brain/src/policy_runtime.zig (sister seam
//            — same staged-backend pattern).
//
// What this is: the single entry point cartridge handlers / store layers
// call after a successful cell write to enqueue an on-chain anchoring
// transaction.  Per Todd 2026-05-25: every cell write triggers an
// anchor (simpler than filtering by linearity).
//
// What this IS NOT (today): a wired bridge to the wallet cartridge.
// The `.stub` backend synthesises a deterministic fake txid for
// traceability so call sites can light up + tests can pass.  The
// `.bsv` backend returns `failed / bsv_backend_not_wired` until the
// task #16 bridge work lands (event-bus async via helm_event_broker
// to cartridges/wallet-headers per §11.10 order 3a architecture).
//
// Recursion break:
//   AnchorAttestation cells (entity_tag = ANCHOR_ATTESTATION_ENTITY_TAG)
//   are themselves the *result* of an anchor.  Re-anchoring them would
//   spin forever — emit() short-circuits with status=.skipped.  The
//   real cartridge-side schema (@semantos/anchor-attestation) defines
//   the canonical entity_tag value; we use a sentinel 0x20 here pending
//   wire-up to that schema (TODO below).
//
// Shape mirror (relative to other brain primitives):
//   PolicyRuntime.evaluate(policy_bytes, context) → PolicyResult
//   AnchorEmitter.emit(context) → AnchorResult
// Identical pattern: pluggable backend, structured return, no exceptions
// for business-rule outcomes (failed/skipped are not thrown).

const std = @import("std");
// §11.10 order 3a step 3 (PR-3a-bridge-1) — emitBsv publishes
// "cell.created" events on the helm broker for the wallet-headers
// cartridge subscriber (PR-3a-bridge-2) to consume.  Stub mode does
// not touch the broker.  See docs/prd/ANCHOR-BACKEND-BRIDGE.md §3.
const helm_event_broker = @import("helm_event_broker");

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

/// Entity tag for AnchorAttestation cells.  Used as the recursion-break
/// sentinel — emit() returns `.skipped` when called for a cell carrying
/// this tag, preventing the anchor-of-anchor infinite loop.
///
/// TODO(§11.10 order 3a step 3): replace this sentinel with the canonical
/// value pulled from @semantos/anchor-attestation's schema (see
/// core/anchor-attestation/src/operations.ts).  0x20 is currently
/// unused across the brain (verified 2026-05-25: 0x00-0x18 are in use
/// across oddjobz / contacts / jam cartridges; 0x20+ is the free range
/// where this lands).  Cross-cartridge schema sync needs to land before
/// the real backend bridge is wired in task #16.
pub const ANCHOR_ATTESTATION_ENTITY_TAG: u32 = 0x20;

/// Stable broker event type token for cell-created anchor requests.
/// The wallet-headers cartridge subscriber (PR-3a-bridge-2) keys on
/// this string verbatim.
pub const EVENT_TYPE_CELL_CREATED: []const u8 = "cell.created";

/// Maximum bytes of JSON payload `emitBsv` formats per publish.  Sized
/// to comfortably fit the 5-field payload (cell_hash + type_hash as 64-
/// hex each = 128 + 2 quote chars × 2 fields = ~136 chars; entity_tag
/// u32 = 10 chars; cartridge_id + correlation_id bounded by call-site
/// values < 64 chars each in practice; plus JSON structural overhead).
/// Overflow surfaces as `.failed / payload_overflow` rather than
/// silently truncating.
pub const MAX_EVENT_PAYLOAD_BYTES: usize = 512;

// ─────────────────────────────────────────────────────────────────────
// Public types
// ─────────────────────────────────────────────────────────────────────

/// Which backend the AnchorEmitter dispatches to.
pub const AnchorMode = enum {
    /// Synthesises a deterministic fake txid from the cell hash; never
    /// touches the network.  Used in tests + dev where on-chain effects
    /// aren't wanted.  Until task #16 lands a real bridge, this is also
    /// the only working backend.
    stub,
    /// Bridges to the BSV anchor backend via the wallet-headers
    /// cartridge.  Returns `bsv_backend_not_wired` failure today;
    /// implementation lands under §11.10 order 3a step 3 (task #16).
    bsv,
};

/// What we're anchoring + how to route the request.
pub const AnchorContext = struct {
    /// SHA-256 of the 1024-byte cell.  Becomes the `targetCellId` on
    /// the AnchorAttestation cell minted by the cartridge backend.
    cell_hash: [32]u8,
    /// Cell's canonical typeHash (from header offset 30, per
    /// core/cell-engine/src/constants.zig HEADER_OFFSET_TYPE_HASH).
    /// The wallet-headers cartridge needs this to derive the anchor
    /// protocolHash via BRC-42 (see cartridges/wallet-headers/brain/
    /// src/cell-anchor.ts `anchorProtocolHash`).  Optional today —
    /// existing call sites land their own population over PR-3a-
    /// bridge-2; emitStub doesn't care; emitBsv rejects all-zeros
    /// with `.failed / type_hash_missing` rather than publishing a
    /// useless event that the cartridge subscriber would just drop.
    type_hash: [32]u8 = [_]u8{0} ** 32,
    /// `cellEntityTag(cell)` — used by the recursion-break check to
    /// short-circuit anchor-of-anchor calls (see ANCHOR_ATTESTATION_ENTITY_TAG
    /// above).  Also surfaces in observability so operators can filter
    /// anchor activity per cartridge / type.
    entity_tag: u32,
    /// Optional cartridge id (e.g., "oddjobz", "jambox").  Routing hint
    /// for the wallet cartridge when one backend serves multiple
    /// cartridges — null today; informational.
    cartridge_id: ?[]const u8 = null,
    /// Optional trace id propagated through audit logs and (when wired)
    /// the wallet cartridge's submit-tx path.  Null for non-traced
    /// callers; cartridges that already carry correlation_id (e.g.
    /// intent_cells) thread it through.
    correlation_id: ?[]const u8 = null,
};

/// Lifecycle status of an anchor request.  The brain doesn't block on
/// tx mining — callers see `pending` immediately, then the wallet
/// cartridge (under task #16) emits a follow-up event when the tx
/// confirms and the AnchorAttestation cell is minted.
pub const AnchorStatus = enum {
    /// Backend accepted the request; tx broadcast is in flight.  Most
    /// successful calls land here under the async architecture.
    pending,
    /// Tx is mined + AnchorAttestation cell persisted.  Synchronous
    /// backends (none today) can return this directly; async backends
    /// notify separately when the state advances from pending →
    /// confirmed.
    confirmed,
    /// Backend rejected or broadcast failed.  `error_kind` carries the
    /// short token; details live in the audit log + backend's own
    /// failure surface.
    failed,
    /// Recursion break — caller passed a cell carrying
    /// ANCHOR_ATTESTATION_ENTITY_TAG.  Anchor cells don't re-anchor.
    skipped,
};

/// Structured outcome of an `emit()` call.  Never thrown; all states
/// (including infrastructure failures) are encoded here so call sites
/// stay branchless on hot paths.
pub const AnchorResult = struct {
    /// True iff the backend accepted the request into its queue.
    /// `pending` / `confirmed` imply true; `failed` / `skipped` imply
    /// false.
    enqueued: bool,
    /// Tx id (lower-hex, 64 chars) when available.  Stub backend
    /// synthesises one for traceability; real backend populates it on
    /// successful broadcast.  Null for skipped + failed paths.
    txid: ?[64]u8 = null,
    status: AnchorStatus,
    /// Short error token when `status == .failed`.  Borrowed from a
    /// static table; lifetime is the program.  Null otherwise.
    error_kind: ?[]const u8 = null,
};

// ─────────────────────────────────────────────────────────────────────
// AnchorEmitter
// ─────────────────────────────────────────────────────────────────────

/// The single entry point cartridge handlers / store layers call after
/// a successful cell write.  Holds the backend mode + an allocator the
/// stub backend uses for synthesised txid formatting.  The real backend
/// (task #16) will hold a broker handle + per-cartridge routing config;
/// the .init signature stays stable across that migration.
pub const AnchorEmitter = struct {
    allocator: std.mem.Allocator,
    mode: AnchorMode,
    /// Borrowed broker handle for .bsv mode publishes.  Null for .stub
    /// mode; required (non-null) for .bsv (enforced at emit time, not
    /// at construction — caller may want a .bsv-mode emitter wired up
    /// before the broker boots).
    broker: ?*helm_event_broker.Broker = null,

    pub fn init(allocator: std.mem.Allocator, mode: AnchorMode) AnchorEmitter {
        return .{ .allocator = allocator, .mode = mode, .broker = null };
    }

    /// .bsv-mode constructor — takes a borrowed broker handle.  The
    /// broker lifetime is the caller's concern (typically the process-
    /// scoped Broker constructed in cli/serve.zig at boot).  Failure
    /// to supply a broker for .bsv mode surfaces at emit time as
    /// `.failed / broker_not_configured`, not at construction —
    /// matches the staged-construction pattern of cli/serve.zig where
    /// wires aren't yet plumbed in declaration order.
    pub fn initWithBroker(
        allocator: std.mem.Allocator,
        mode: AnchorMode,
        broker: *helm_event_broker.Broker,
    ) AnchorEmitter {
        return .{ .allocator = allocator, .mode = mode, .broker = broker };
    }

    /// Enqueue an anchor request for the cell described by `context`.
    /// Pure dispatch — backend-specific work lives in the per-mode
    /// helpers below.  Recursion-break check runs first so anchor cells
    /// short-circuit regardless of backend.
    pub fn emit(self: *AnchorEmitter, context: AnchorContext) AnchorResult {
        if (context.entity_tag == ANCHOR_ATTESTATION_ENTITY_TAG) {
            return .{ .enqueued = false, .status = .skipped };
        }
        return switch (self.mode) {
            .stub => emitStub(context),
            .bsv => self.emitBsv(context),
        };
    }

    /// .bsv backend — publishes a "cell.created" event on the helm
    /// broker.  Subscribers (the wallet-headers cartridge under
    /// PR-3a-bridge-2) mint the AnchorAttestation cell and broadcast
    /// the BSV tx asynchronously.  Returns `.pending` immediately
    /// without a txid — the cartridge emits a follow-up
    /// `anchor.confirmed` event with the txid once broadcast lands
    /// (PR-3a-bridge-3).
    ///
    /// Failure modes — all return `.failed` with a stable token:
    ///   • `broker_not_configured` — `self.broker` is null
    ///   • `type_hash_missing`     — context.type_hash is all-zeros
    ///                               (call site didn't populate)
    ///   • `payload_overflow`      — JSON wouldn't fit in
    ///                               MAX_EVENT_PAYLOAD_BYTES
    ///
    /// Note: broker.publish() returns void — broker-side OOM is
    /// silently dropped per its contract.  We treat publish as
    /// best-effort + return `.pending` once we hand off, because the
    /// brain doesn't block on tx mining anyway (eventual consistency
    /// per design doc §2).
    fn emitBsv(self: *AnchorEmitter, context: AnchorContext) AnchorResult {
        const broker = self.broker orelse return .{
            .enqueued = false,
            .status = .failed,
            .error_kind = "broker_not_configured",
        };

        // Reject all-zeros type_hash so the cartridge subscriber
        // doesn't get a useless event.  Real call sites populate
        // type_hash from the cell header (offset 30 per
        // core/cell-engine/src/constants.zig HEADER_OFFSET_TYPE_HASH).
        if (allZero(&context.type_hash)) {
            return .{
                .enqueued = false,
                .status = .failed,
                .error_kind = "type_hash_missing",
            };
        }

        var payload_buf: [MAX_EVENT_PAYLOAD_BYTES]u8 = undefined;
        var cell_hash_hex: [64]u8 = undefined;
        hexEncode(&context.cell_hash, &cell_hash_hex);
        var type_hash_hex: [64]u8 = undefined;
        hexEncode(&context.type_hash, &type_hash_hex);

        const payload_json = std.fmt.bufPrint(
            &payload_buf,
            "{{\"cell_hash\":\"{s}\",\"type_hash\":\"{s}\",\"entity_tag\":{d},\"cartridge_id\":\"{s}\",\"correlation_id\":\"{s}\"}}",
            .{
                cell_hash_hex,
                type_hash_hex,
                context.entity_tag,
                context.cartridge_id orelse "",
                context.correlation_id orelse "",
            },
        ) catch return .{
            .enqueued = false,
            .status = .failed,
            .error_kind = "payload_overflow",
        };

        // broker.publish never throws — it logs OOM internally + drops.
        // We hand the event off and consider that "enqueued."  The
        // confirmation feedback path (PR-3a-bridge-3) reports actual
        // broadcast outcome via the anchor.confirmed / anchor.failed
        // events the cartridge will publish back.
        broker.publish(.{
            .type = EVENT_TYPE_CELL_CREATED,
            .payload_json = payload_json,
        });

        return .{
            .enqueued = true,
            .status = .pending,
            // No txid yet — the wallet emits a follow-up event with
            // the broadcast result.  See ANCHOR-BACKEND-BRIDGE.md §5.
        };
    }
};

fn allZero(bytes: []const u8) bool {
    for (bytes) |b| {
        if (b != 0) return false;
    }
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// Backends
// ─────────────────────────────────────────────────────────────────────

/// Stub backend: synthesises a deterministic fake txid by hex-encoding
/// the cell hash.  The txid carries no on-chain meaning, but it's
/// stable per-cell so callers can join against it in audit logs + tests
/// can pin assertions against the deterministic value.
fn emitStub(context: AnchorContext) AnchorResult {
    var txid: [64]u8 = undefined;
    hexEncode(&context.cell_hash, &txid);
    return .{
        .enqueued = true,
        .txid = txid,
        .status = .pending,
    };
}

// PR-3a-bridge-1: the standalone `emitBsv` placeholder was replaced by
// the `AnchorEmitter.emitBsv` method (above) that publishes on
// `self.broker`.  Inline tests for the broker-bearing path live at
// the bottom of this file.

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

fn hexEncode(bytes: []const u8, out: []u8) void {
    const alphabet = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = alphabet[b >> 4];
        out[i * 2 + 1] = alphabet[b & 0x0f];
    }
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure-function backend behaviour + recursion break.
// Cross-handler wiring tests (cell_handler / intent_cells_handler
// calling emit on successful writes) belong in task #15 + the
// per-handler conformance suites.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn fakeHash(seed: u8) [32]u8 {
    var out: [32]u8 = undefined;
    for (&out, 0..) |*b, i| b.* = seed +% @as(u8, @intCast(i));
    return out;
}

test "emit: stub backend returns pending with deterministic txid from cell_hash" {
    var em = AnchorEmitter.init(testing.allocator, .stub);
    const ctx = AnchorContext{
        .cell_hash = fakeHash(0x42),
        .entity_tag = 0x01, // arbitrary non-anchor tag
    };
    const r = em.emit(ctx);
    try testing.expect(r.enqueued);
    try testing.expectEqual(AnchorStatus.pending, r.status);
    try testing.expect(r.txid != null);
    try testing.expect(r.error_kind == null);
    // Deterministic: synthesised txid is the hex of the cell hash.
    var expected_txid: [64]u8 = undefined;
    hexEncode(&ctx.cell_hash, &expected_txid);
    try testing.expectEqualSlices(u8, &expected_txid, &r.txid.?);
}

test "emit: same cell_hash yields same stub txid (idempotent for traceability)" {
    var em = AnchorEmitter.init(testing.allocator, .stub);
    const ctx_a = AnchorContext{ .cell_hash = fakeHash(0x10), .entity_tag = 0x01 };
    const ctx_b = AnchorContext{ .cell_hash = fakeHash(0x10), .entity_tag = 0x02 };
    const r_a = em.emit(ctx_a);
    const r_b = em.emit(ctx_b);
    try testing.expectEqualSlices(u8, &r_a.txid.?, &r_b.txid.?);
}

test "emit: anchor entity_tag → skipped (recursion break)" {
    var em = AnchorEmitter.init(testing.allocator, .stub);
    const ctx = AnchorContext{
        .cell_hash = fakeHash(0x99),
        .entity_tag = ANCHOR_ATTESTATION_ENTITY_TAG,
    };
    const r = em.emit(ctx);
    try testing.expect(!r.enqueued);
    try testing.expectEqual(AnchorStatus.skipped, r.status);
    try testing.expect(r.txid == null);
}

test "emit: skip applies to bsv backend too (recursion break is mode-agnostic)" {
    var em = AnchorEmitter.init(testing.allocator, .bsv);
    const ctx = AnchorContext{
        .cell_hash = fakeHash(0x55),
        .entity_tag = ANCHOR_ATTESTATION_ENTITY_TAG,
    };
    const r = em.emit(ctx);
    try testing.expectEqual(AnchorStatus.skipped, r.status);
}

test "emit: bsv backend without broker → failed/broker_not_configured" {
    // .bsv mode constructed via init() (no broker plumbed) — common
    // case during cli/serve.zig boot where the emitter is wired before
    // the broker exists.  emit must fail-fast with a clean token, not
    // crash.
    var em = AnchorEmitter.init(testing.allocator, .bsv);
    const ctx = AnchorContext{
        .cell_hash = fakeHash(0x33),
        .entity_tag = 0x01,
        .type_hash = fakeHash(0xAA),
    };
    const r = em.emit(ctx);
    try testing.expect(!r.enqueued);
    try testing.expectEqual(AnchorStatus.failed, r.status);
    try testing.expectEqualStrings("broker_not_configured", r.error_kind.?);
    try testing.expect(r.txid == null);
}

// ─────────────────────────────────────────────────────────────────────
// §11.10 order 3a step 3 — PR-3a-bridge-1: emitBsv publishes
// "cell.created" events on helm_event_broker.  Tests use a real
// in-memory broker + a capturing subscriber to assert publish
// happened with the expected payload shape.
// ─────────────────────────────────────────────────────────────────────

/// Test-only subscriber that snapshots every event it receives so
/// assertions can inspect what emitBsv actually published.  One slot;
/// later events overwrite earlier ones.
const TestCapture = struct {
    fired: bool = false,
    last_type: [64]u8 = [_]u8{0} ** 64,
    last_type_len: usize = 0,
    last_payload: [MAX_EVENT_PAYLOAD_BYTES]u8 = undefined,
    last_payload_len: usize = 0,

    fn callback(state: ?*anyopaque, event: helm_event_broker.Event) void {
        const self: *TestCapture = @ptrCast(@alignCast(state.?));
        self.fired = true;
        self.last_type_len = @min(event.type.len, self.last_type.len);
        @memcpy(self.last_type[0..self.last_type_len], event.type[0..self.last_type_len]);
        self.last_payload_len = @min(event.payload_json.len, self.last_payload.len);
        @memcpy(self.last_payload[0..self.last_payload_len], event.payload_json[0..self.last_payload_len]);
    }

    fn typeStr(self: *const TestCapture) []const u8 {
        return self.last_type[0..self.last_type_len];
    }
    fn payloadStr(self: *const TestCapture) []const u8 {
        return self.last_payload[0..self.last_payload_len];
    }
};

test "emit.bsv: publishes cell.created with hex cell_hash + type_hash + entity_tag" {
    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();

    var cap: TestCapture = .{};
    const sub_id = try broker.subscribe(.{
        .state = &cap,
        .callback = TestCapture.callback,
    });
    defer broker.unsubscribe(sub_id);

    var em = AnchorEmitter.initWithBroker(testing.allocator, .bsv, &broker);
    const ctx = AnchorContext{
        .cell_hash = fakeHash(0x10),
        .type_hash = fakeHash(0xC0),
        .entity_tag = 0x06,
        .cartridge_id = "oddjobz",
        .correlation_id = "trace-bridge-1",
    };
    const r = em.emit(ctx);

    try testing.expect(r.enqueued);
    try testing.expectEqual(AnchorStatus.pending, r.status);
    try testing.expect(r.error_kind == null);
    try testing.expect(r.txid == null); // confirmation lands via anchor.confirmed (PR-3a-bridge-3)

    try testing.expect(cap.fired);
    try testing.expectEqualStrings("cell.created", cap.typeStr());
    // Sanity: payload contains hex of both hashes + the entity_tag.
    const payload = cap.payloadStr();
    try testing.expect(std.mem.indexOf(u8, payload, "cell_hash") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "type_hash") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "\"entity_tag\":6") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "\"cartridge_id\":\"oddjobz\"") != null);
    try testing.expect(std.mem.indexOf(u8, payload, "\"correlation_id\":\"trace-bridge-1\"") != null);
}

test "emit.bsv: all-zeros type_hash → failed/type_hash_missing (no publish)" {
    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();

    var cap: TestCapture = .{};
    const sub_id = try broker.subscribe(.{
        .state = &cap,
        .callback = TestCapture.callback,
    });
    defer broker.unsubscribe(sub_id);

    var em = AnchorEmitter.initWithBroker(testing.allocator, .bsv, &broker);
    const ctx = AnchorContext{
        .cell_hash = fakeHash(0x10),
        // .type_hash deliberately omitted → defaults to all-zeros
        .entity_tag = 0x06,
    };
    const r = em.emit(ctx);

    try testing.expect(!r.enqueued);
    try testing.expectEqual(AnchorStatus.failed, r.status);
    try testing.expectEqualStrings("type_hash_missing", r.error_kind.?);
    // No publish should have happened — the subscriber stays silent.
    try testing.expect(!cap.fired);
}

test "emit.bsv: anchor entity_tag still short-circuits to .skipped (no publish)" {
    // Belt + suspenders: even in .bsv mode with a broker wired, anchor
    // cells shouldn't republish.  This is the recursion break we don't
    // want to lose when adding the broker path.
    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();

    var cap: TestCapture = .{};
    const sub_id = try broker.subscribe(.{
        .state = &cap,
        .callback = TestCapture.callback,
    });
    defer broker.unsubscribe(sub_id);

    var em = AnchorEmitter.initWithBroker(testing.allocator, .bsv, &broker);
    const ctx = AnchorContext{
        .cell_hash = fakeHash(0x55),
        .type_hash = fakeHash(0xC0),
        .entity_tag = ANCHOR_ATTESTATION_ENTITY_TAG,
    };
    const r = em.emit(ctx);

    try testing.expectEqual(AnchorStatus.skipped, r.status);
    try testing.expect(!cap.fired);
}

test "emit.bsv: hex-encodes cell_hash + type_hash to lowercase 64 chars" {
    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();

    var cap: TestCapture = .{};
    const sub_id = try broker.subscribe(.{
        .state = &cap,
        .callback = TestCapture.callback,
    });
    defer broker.unsubscribe(sub_id);

    var em = AnchorEmitter.initWithBroker(testing.allocator, .bsv, &broker);
    // Two distinguishable hashes so the test can spot byte-order bugs.
    var ch: [32]u8 = undefined;
    for (&ch, 0..) |*b, i| b.* = @intCast(i); // 00 01 02 ... 1F
    var th: [32]u8 = undefined;
    for (&th, 0..) |*b, i| b.* = @intCast(0x80 + i); // 80 81 82 ... 9F
    const ctx = AnchorContext{
        .cell_hash = ch,
        .type_hash = th,
        .entity_tag = 0x01,
    };
    _ = em.emit(ctx);

    try testing.expect(cap.fired);
    // Spot-check: hex of cell_hash ends with "1f" + hex of type_hash
    // ends with "9f" — exact lowercase, no separators.
    try testing.expect(std.mem.indexOf(u8, cap.payloadStr(), "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f") != null);
    try testing.expect(std.mem.indexOf(u8, cap.payloadStr(), "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f") != null);
}

test "emit.bsv: null cartridge_id + correlation_id render as empty strings (no crash)" {
    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();

    var cap: TestCapture = .{};
    const sub_id = try broker.subscribe(.{
        .state = &cap,
        .callback = TestCapture.callback,
    });
    defer broker.unsubscribe(sub_id);

    var em = AnchorEmitter.initWithBroker(testing.allocator, .bsv, &broker);
    const ctx = AnchorContext{
        .cell_hash = fakeHash(0x42),
        .type_hash = fakeHash(0xDE),
        .entity_tag = 0x07,
        // .cartridge_id + .correlation_id omitted → null → empty strings
    };
    const r = em.emit(ctx);
    try testing.expect(r.enqueued);
    try testing.expectEqual(AnchorStatus.pending, r.status);
    try testing.expect(cap.fired);
    try testing.expect(std.mem.indexOf(u8, cap.payloadStr(), "\"cartridge_id\":\"\"") != null);
    try testing.expect(std.mem.indexOf(u8, cap.payloadStr(), "\"correlation_id\":\"\"") != null);
}

test "emit: optional context fields (cartridge_id, correlation_id) compile + pass through" {
    var em = AnchorEmitter.init(testing.allocator, .stub);
    const ctx = AnchorContext{
        .cell_hash = fakeHash(0x07),
        .entity_tag = 0x06, // oddjobz.job.v2
        .cartridge_id = "oddjobz",
        .correlation_id = "trace-abc-123",
    };
    const r = em.emit(ctx);
    try testing.expect(r.enqueued);
}

test "ANCHOR_ATTESTATION_ENTITY_TAG sentinel does not collide with known cartridge tags" {
    // Documented audit 2026-05-25: 0x01-0x08 oddjobz, 0x0A-0x0B contacts,
    // 0x10-0x18 jam* / generic.  0x20 is free.
    try testing.expect(ANCHOR_ATTESTATION_ENTITY_TAG > 0x18);
}

```
