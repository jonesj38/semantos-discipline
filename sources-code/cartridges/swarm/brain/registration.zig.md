---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/swarm/brain/registration.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.678620+00:00
---

# cartridges/swarm/brain/registration.zig

```zig
// DAM-4 — swarm cartridge brain registration (cartridge_seam entry-point).
//
// Wires the Engine-Checked Data Access (DAM) cell-type family into the running
// brain so the generic mint/dispatch pipeline (cells_mint_handler) evaluates an
// `access.grant.verify.intent` on the real 2-PDA:
//
//   1. cell types        → cartridge_cell_registry (access.grant LINEAR,
//                          access.grant.verify.intent + .verify.result EPHEMERAL)
//   2. the verify handler → cell_script_handler_registry, bound to the
//                          verify.intent typeHash, with emits=[verify.result]
//   3. the ScriptContextBuilder → deps.mint_context_registry (DAM-1's
//                          access_grant_context, which the Handler runs BEFORE
//                          the handler script)
//
// IN-CODE registration (not cartridge.json): the DAM type hashes are
// sha256(dotted-name) — the swarm cartridge's own convention (cf.
// sha256("swarm.manifest")) and what DAM-1/2/3 already agree on. The
// cartridge.json `triple` path would instead produce buildTypeHash(seg1..4)
// (the |8|8|8|8| construction), which is a DIFFERENT hash — so it cannot carry
// these constants. Registering directly with the sha256 constants keeps the TS
// grantee, the builder, the handler, and the registry all on the same hash.

const std = @import("std");
const dispatcher = @import("dispatcher");
const cartridge_seam = @import("cartridge_seam");
const access_grant_context = @import("access_grant_context");
const access_grant_handler = @import("access_grant_handler");
const cartridge_cell_registry = @import("cartridge_cell_registry");
const cell_script_handler_registry = @import("cell_script_handler_registry");

const CARTRIDGE_ID = "swarm";
const RESULT_TYPE_NAME = "access.grant.verify.result";

/// Brain wall-clock for the builder's expiry gate (unix seconds).
fn realClock() i64 {
    return std.time.timestamp();
}

/// Register the 3 DAM cell types + the verify handler into the global
/// registries. Idempotent (lookup-guarded), so a second boot / a test re-run is
/// a no-op rather than a typeHash_collision. Pure registry work — no deps — so
/// the e2e test can call it directly.
pub fn registerCellTypesAndHandler() !void {
    try registerCellType(access_grant_context.GRANT_TYPE_HASH, "access.grant", .LINEAR);
    try registerCellType(access_grant_context.VERIFY_INTENT_TYPE_HASH, "access.grant.verify.intent", .EPHEMERAL);
    try registerCellType(access_grant_handler.RESULT_TYPE_HASH, RESULT_TYPE_NAME, .EPHEMERAL);

    // Bind the verify handler to the verify-intent typeHash. emits[] gates the
    // result cell through the dispatcher's emit-allowlist walker.
    if (cell_script_handler_registry.lookup(&access_grant_context.VERIFY_INTENT_TYPE_HASH) == null) {
        var script_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(access_grant_handler.VERIFY_INTENT_HANDLER, &script_hash, .{});
        try cell_script_handler_registry.register(access_grant_context.VERIFY_INTENT_TYPE_HASH, .{
            .script_bytes = access_grant_handler.VERIFY_INTENT_HANDLER,
            .script_hash = script_hash,
            .capabilities = &.{},
            .opcount_budget = 500_000,
            .emits = &.{RESULT_TYPE_NAME},
        });
    }
}

fn registerCellType(type_hash: [32]u8, name: []const u8, lin: cartridge_cell_registry.Linearity) !void {
    if (cartridge_cell_registry.lookup(&type_hash) != null) return;
    try cartridge_cell_registry.register(.{
        .type_hash = type_hash,
        .cartridge_id = CARTRIDGE_ID,
        .cell_type_name = name,
        .linearity = lin,
        .capability_name = "", // no cartridge-cell capability gate; access is gated by the handler
        .payload_schema_raw = null,
    });
}

/// cartridge_seam registerInto contract (BRAIN-EXTENSION-LOADER §3). Called once
/// at brain boot. Registers the DAM cell types + handler always; attaches the
/// ScriptContextBuilder only when the mint Handler is up (static-only sites
/// leave mint_context_registry null — mints aren't served there anyway).
pub fn registerInto(
    disp: *dispatcher.Dispatcher,
    allocator: std.mem.Allocator,
    deps: *const cartridge_seam.CartridgeDeps,
) anyerror!void {
    _ = disp; // swarm DAM contributes cell types + handler + a mint-context builder, not a dispatcher resource

    try registerCellTypesAndHandler();

    const registry = deps.mint_context_registry orelse {
        std.log.info(
            "swarm.registerInto: no mint_context_registry (mint Handler not up) — access-grant cell types + handler registered, builder skipped",
            .{},
        );
        return;
    };

    // Heap-allocate the builder State (brain-lifetime; the registry holds a
    // pointer to it via ScriptContextBuilder.state). cell_store comes from the
    // DI bag; the clock is the brain wall-clock for the expiry gate.
    const state = try allocator.create(access_grant_context.State);
    errdefer allocator.destroy(state);
    state.* = .{ .cell_store = deps.cell_store, .now_fn = realClock };

    registry.add(access_grant_context.toBuilder(state));

    std.log.info(
        "swarm.registerInto: access-grant DAM family registered (mint-context builders now {d})",
        .{registry.count()},
    );
}

// ── module-importability smoke test (matches the mnca_registration posture) ──

const testing = std.testing;

test "swarm registration module imports + registerInto is referenceable" {
    try testing.expect(@TypeOf(registerInto) == fn (
        *dispatcher.Dispatcher,
        std.mem.Allocator,
        *const cartridge_seam.CartridgeDeps,
    ) anyerror!void);
}

test "registerCellTypesAndHandler registers the 3 types + handler (idempotent)" {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_registry.resetRegistryForTest();

    try registerCellTypesAndHandler();
    try registerCellTypesAndHandler(); // second call is a no-op, not a collision

    try testing.expect(cartridge_cell_registry.lookupByName(CARTRIDGE_ID, "access.grant") != null);
    try testing.expect(cartridge_cell_registry.lookupByName(CARTRIDGE_ID, "access.grant.verify.intent") != null);
    try testing.expect(cartridge_cell_registry.lookupByName(CARTRIDGE_ID, RESULT_TYPE_NAME) != null);
    const hentry = cell_script_handler_registry.lookup(&access_grant_context.VERIFY_INTENT_TYPE_HASH) orelse
        return error.handler_not_registered;
    try testing.expectEqual(@as(usize, 1), hentry.emits.len);
    try testing.expectEqualStrings(RESULT_TYPE_NAME, hentry.emits[0]);
}

// ── End-to-end composite dispatch on the REAL 2-PDA ───────────────────────────
//
// Drives the FULL pipeline through cells_mint_handler.dispatchInputCellThunk:
// the registered ScriptContextBuilder builds the Context (loads the grant,
// computes the canonical challenge digest, sets the host_verify_partial_sig
// Context + pushes the grant cell), the registered verify handler runs on the
// real 2-PDA, host.checksig (BSVZ native, full profile) verifies the grantee's
// edge-key signature, and the emit-walker persists the verify.result — gated by
// the emits[] allowlist. The valid signature is a deterministic vector
// generated from the TS DAM-3 signer (see DAM4_* constants below).

const cells_mint_handler = @import("cells_mint_handler");
const cell_store_mod = @import("cell_store");
const constants = @import("constants");
const helm_event_broker = @import("helm_event_broker");

const CELL_SIZE = constants.CELL_SIZE;
const HEADER_SIZE = constants.HEADER_SIZE; // 256
const HDR_LINEARITY_OFF = 16;
const HDR_TYPE_HASH_OFF = 30;
const GRANT_CAP_OFF = 0;
const GRANT_PUBKEY_OFF = 1;
const GRANT_EXPIRY_OFF = 66;
const VI_GRANT_HASH_OFF = 0;
const VI_SIG_LEN_OFF = 32;
const VI_SIG_OFF = 34;
const CAP_DATA_ACCESS: u8 = 2;
const LINEARITY_LINEAR: u32 = 1;

// Deterministic vector from the DAM-3 TS signer (RFC6979), over
// accessChallengeDigest(grant_hash = 0x11×32, GRANTEE_PUB):
//   granteeSk      = scalar 7
//   GRANTEE_PUB    = secp.getPublicKey(7, compressed)
//   SIG            = DER(sign(digest, 7)) ‖ 0x41  (SIGHASH_ALL|FORKID)
// Regenerate: bun run a script that imports accessChallengeDigest from
// core/protocol-types/src/bsv/access-grant.ts and signs with @noble (see the
// DAM-4 PR description). The Zig builder recomputes the IDENTICAL digest
// (proven byte-exact by the DAM-3 cross-impl conformance vector), so this sig
// verifies on the 2-PDA.
const GRANTEE_PUB_HEX = "025cbdf0646e5db4eaa398f365f2ea7a0e3d419b7e0330e39ce92bddedcac4f9bc";
const SIG_HEX = "3044022078dac4d973f12a74f21f9349277ae62e7efa451bdcaff3bf6abca53ec8f7e87d02202726cfc47a5c56fe42cb4adcbb56a1bea08bfb3e2449b160316e1534befcd44841";
const GRANT_HASH = [_]u8{0x11} ** 32;

fn fixedClock() i64 {
    return 1_000_000; // < the valid grants' 9_999_999_999 expiry, > the expired grant's
}

fn makeGrantCell(cap: u8, expiry: u64, grantee_pub: [33]u8) [CELL_SIZE]u8 {
    var c: [CELL_SIZE]u8 = [_]u8{0} ** CELL_SIZE;
    std.mem.writeInt(u32, c[HDR_LINEARITY_OFF .. HDR_LINEARITY_OFF + 4][0..4], LINEARITY_LINEAR, .little);
    @memcpy(c[HDR_TYPE_HASH_OFF .. HDR_TYPE_HASH_OFF + 32], &access_grant_context.GRANT_TYPE_HASH);
    c[HEADER_SIZE + GRANT_CAP_OFF] = cap;
    @memcpy(c[HEADER_SIZE + GRANT_PUBKEY_OFF .. HEADER_SIZE + GRANT_PUBKEY_OFF + 33], &grantee_pub);
    std.mem.writeInt(u64, c[HEADER_SIZE + GRANT_EXPIRY_OFF .. HEADER_SIZE + GRANT_EXPIRY_OFF + 8][0..8], expiry, .little);
    return c;
}

fn makeIntentCell(sig: []const u8) [CELL_SIZE]u8 {
    var c: [CELL_SIZE]u8 = [_]u8{0} ** CELL_SIZE;
    @memcpy(c[HDR_TYPE_HASH_OFF .. HDR_TYPE_HASH_OFF + 32], &access_grant_context.VERIFY_INTENT_TYPE_HASH);
    @memcpy(c[HEADER_SIZE + VI_GRANT_HASH_OFF .. HEADER_SIZE + VI_GRANT_HASH_OFF + 32], &GRANT_HASH);
    c[HEADER_SIZE + VI_SIG_LEN_OFF] = @intCast(sig.len & 0xff);
    c[HEADER_SIZE + VI_SIG_LEN_OFF + 1] = @intCast((sig.len >> 8) & 0xff);
    @memcpy(c[HEADER_SIZE + VI_SIG_OFF .. HEADER_SIZE + VI_SIG_OFF + sig.len], sig);
    return c;
}

// Minimal CellStore stub: getCell returns the single seeded grant for ANY hash
// (the builder loads by the intent's grant_hash; we decouple it from the cell's
// own sha256 so GRANT_HASH can stay the fixed value the sig was signed against),
// and put records emitted cells so the test can assert the verify.result.
const StubStore = struct {
    var grant: ?[CELL_SIZE]u8 = null;
    var emitted: [4][CELL_SIZE]u8 = undefined;
    var emitted_count: usize = 0;

    fn reset() void {
        grant = null;
        emitted_count = 0;
    }
};

fn stubGetCell(_: *anyopaque, _: *const [32]u8) cell_store_mod.StoreError!?[CELL_SIZE]u8 {
    return StubStore.grant;
}
fn stubPut(_: *anyopaque, cell: *const [CELL_SIZE]u8) cell_store_mod.StoreError![32]u8 {
    if (StubStore.emitted_count < StubStore.emitted.len) {
        StubStore.emitted[StubStore.emitted_count] = cell.*;
        StubStore.emitted_count += 1;
    }
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(cell, &hash, .{});
    return hash;
}
fn stubExists(_: *anyopaque, _: *const [32]u8) bool {
    return false;
}
fn stubCursorOpen(_: *anyopaque) cell_store_mod.StoreError!cell_store_mod.CellCursorHandle {
    return error.persistence_failed;
}
fn stubCursorPull(_: *anyopaque, _: cell_store_mod.CellCursorHandle) cell_store_mod.StoreError!?*const [CELL_SIZE]u8 {
    return null;
}
fn stubCursorClose(_: *anyopaque, _: cell_store_mod.CellCursorHandle) void {}
fn stubCount(_: *anyopaque) cell_store_mod.StoreError!u64 {
    return 0;
}
fn stubSpend(_: *anyopaque, _: *const [32]u8) cell_store_mod.StoreError!bool {
    return false;
}
fn stubIsSpent(_: *anyopaque, _: *const [32]u8) bool {
    return false;
}
fn stubCellsByOwner(_: *anyopaque, _: std.mem.Allocator, _: *const [16]u8) cell_store_mod.StoreError![][32]u8 {
    return error.persistence_failed;
}
fn stubCellsByType(_: *anyopaque, _: std.mem.Allocator, _: *const [32]u8) cell_store_mod.StoreError![][32]u8 {
    return error.persistence_failed;
}
fn stubCellsByTypePrefix(_: *anyopaque, _: std.mem.Allocator, _: []const u8) cell_store_mod.StoreError![][32]u8 {
    return error.persistence_failed;
}
fn stubCellsByPrevState(_: *anyopaque, _: std.mem.Allocator, _: *const [32]u8) cell_store_mod.StoreError![][32]u8 {
    return error.persistence_failed;
}
fn stubCellsByAnchorTxid(_: *anyopaque, _: std.mem.Allocator, _: *const [32]u8) cell_store_mod.StoreError![][32]u8 {
    return error.persistence_failed;
}
fn stubSetAnchorStatus(_: *anyopaque, _: *const [32]u8, _: cell_store_mod.AnchorStatus) cell_store_mod.StoreError!void {
    return error.persistence_failed;
}
fn stubGetAnchorStatus(_: *anyopaque, _: *const [32]u8) ?cell_store_mod.AnchorStatus {
    return null;
}
fn stubClearAnchorStatus(_: *anyopaque, _: *const [32]u8) cell_store_mod.StoreError!void {
    return error.persistence_failed;
}
fn stubSweepPendingAnchors(_: *anyopaque, _: *const [32]u8) cell_store_mod.StoreError!cell_store_mod.SweepResult {
    return error.persistence_failed;
}
fn stubCellsByAnchorHeightRange(_: *anyopaque, _: std.mem.Allocator, _: u64, _: u64) cell_store_mod.StoreError![]cell_store_mod.AnchorHeightEntry {
    return error.persistence_failed;
}
fn stubSweepReorgedFromHeight(_: *anyopaque, _: u64) cell_store_mod.StoreError!cell_store_mod.SweepResult {
    return error.persistence_failed;
}
fn stubCellsByPrevStateRange(
    _: *anyopaque,
    _: std.mem.Allocator,
    _: *const [32]u8,
    _: ?*const [32]u8,
    _: usize,
) cell_store_mod.StoreError!cell_store_mod.PrevStateRangeResult {
    return error.persistence_failed;
}

const stub_vtable: cell_store_mod.CellStore.VTable = .{
    .put = stubPut,
    .exists = stubExists,
    .cursor_open = stubCursorOpen,
    .cursor_pull = stubCursorPull,
    .cursor_close = stubCursorClose,
    .count = stubCount,
    .spend = stubSpend,
    .is_spent = stubIsSpent,
    .get_cell = stubGetCell,
    .cells_by_owner = stubCellsByOwner,
    .cells_by_type = stubCellsByType,
    .cells_by_type_prefix = stubCellsByTypePrefix,
    .cells_by_prev_state = stubCellsByPrevState,
    .cells_by_anchor_txid = stubCellsByAnchorTxid,
    .set_anchor_status = stubSetAnchorStatus,
    .get_anchor_status = stubGetAnchorStatus,
    .clear_anchor_status = stubClearAnchorStatus,
    .sweep_pending_anchors = stubSweepPendingAnchors,
    .cells_by_anchor_height_range = stubCellsByAnchorHeightRange,
    .sweep_reorged_from_height = stubSweepReorgedFromHeight,
    .cells_by_prev_state_range = stubCellsByPrevStateRange,
};

fn stubCellStore() cell_store_mod.CellStore {
    return .{ .ctx = @ptrCast(&StubStore.grant), .vtable = &stub_vtable };
}

const E2EOutcome = enum { success_emitted, rejected, internal_error };

/// Build the full pipeline (registries + builder + Handler) and dispatch the
/// given intent against the seeded grant. Returns the dispatch outcome class.
fn runDispatch(grant: [CELL_SIZE]u8, intent: [CELL_SIZE]u8, out_emitted: *usize) E2EOutcome {
    cartridge_cell_registry.resetForTest();
    cell_script_handler_registry.resetRegistryForTest();
    registerCellTypesAndHandler() catch return .internal_error;

    StubStore.reset();
    StubStore.grant = grant;
    var store = stubCellStore();

    // Builder with a fixed clock so expiry is deterministic in-test.
    var state = access_grant_context.State{ .cell_store = &store, .now_fn = fixedClock };
    var registry = cells_mint_handler.MintContextRegistry{};
    registry.add(access_grant_context.toBuilder(&state));

    var broker: helm_event_broker.Broker = undefined; // dispatchInputCellThunk path never touches the broker (Step-6 publish is handleMint-only)
    var handler = cells_mint_handler.Handler.init(testing.allocator, &store, &broker);
    handler.setContextBuilder(registry.toBuilder());

    var input = intent;
    const outcome = cells_mint_handler.dispatchInputCellThunk(
        @ptrCast(&handler),
        testing.allocator,
        &access_grant_context.VERIFY_INTENT_TYPE_HASH,
        CARTRIDGE_ID,
        &input,
    );
    return switch (outcome) {
        .success => |s| blk: {
            out_emitted.* = s.emitted_count;
            break :blk .success_emitted;
        },
        .rejection => .rejected,
        // .skipped = no handler registered for the typeHash → a test setup bug
        // (we register it in registerCellTypesAndHandler); surface it loudly.
        .skipped, .internal_error => .internal_error,
    };
}

fn hexBytes(comptime hex: []const u8) [hex.len / 2]u8 {
    var out: [hex.len / 2]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, hex) catch unreachable;
    return out;
}

test "DAM-4 e2e: valid grant + signature → verify.result emitted on the 2-PDA" {
    const grantee_pub = hexBytes(GRANTEE_PUB_HEX);
    const sig = hexBytes(SIG_HEX);
    const grant = makeGrantCell(CAP_DATA_ACCESS, 9_999_999_999, grantee_pub);
    const intent = makeIntentCell(&sig);

    var emitted: usize = 0;
    const outcome = runDispatch(grant, intent, &emitted);
    try testing.expectEqual(E2EOutcome.success_emitted, outcome);
    try testing.expectEqual(@as(usize, 1), emitted);

    // The emitted cell is an access.grant.verify.result.
    try testing.expectEqual(@as(usize, 1), StubStore.emitted_count);
    const emitted_th = StubStore.emitted[0][HDR_TYPE_HASH_OFF .. HDR_TYPE_HASH_OFF + 32];
    try testing.expectEqualSlices(u8, &access_grant_handler.RESULT_TYPE_HASH, emitted_th);
    // payload[0] == 1 (ok)
    try testing.expectEqual(@as(u8, 1), StubStore.emitted[0][HEADER_SIZE]);
}

test "DAM-4 e2e: tampered signature → rejected (no result emitted)" {
    const grantee_pub = hexBytes(GRANTEE_PUB_HEX);
    var sig = hexBytes(SIG_HEX);
    sig[10] ^= 0xff; // corrupt the signature
    const grant = makeGrantCell(CAP_DATA_ACCESS, 9_999_999_999, grantee_pub);
    const intent = makeIntentCell(&sig);

    var emitted: usize = 0;
    try testing.expectEqual(E2EOutcome.rejected, runDispatch(grant, intent, &emitted));
    try testing.expectEqual(@as(usize, 0), StubStore.emitted_count);
}

test "DAM-4 e2e: expired grant → rejected (builder yields no Context)" {
    const grantee_pub = hexBytes(GRANTEE_PUB_HEX);
    const sig = hexBytes(SIG_HEX);
    const grant = makeGrantCell(CAP_DATA_ACCESS, 500_000, grantee_pub); // expiry < fixedClock
    const intent = makeIntentCell(&sig);

    var emitted: usize = 0;
    try testing.expectEqual(E2EOutcome.rejected, runDispatch(grant, intent, &emitted));
    try testing.expectEqual(@as(usize, 0), StubStore.emitted_count);
}

test "DAM-4 e2e: wrong capability → rejected (builder yields no Context)" {
    const grantee_pub = hexBytes(GRANTEE_PUB_HEX);
    const sig = hexBytes(SIG_HEX);
    const grant = makeGrantCell(5, 9_999_999_999, grantee_pub); // TRANSFER(5), not DATA_ACCESS
    const intent = makeIntentCell(&sig);

    var emitted: usize = 0;
    try testing.expectEqual(E2EOutcome.rejected, runDispatch(grant, intent, &emitted));
    try testing.expectEqual(@as(usize, 0), StubStore.emitted_count);
}

```
