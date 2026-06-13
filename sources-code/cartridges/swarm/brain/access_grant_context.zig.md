---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/swarm/brain/access_grant_context.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.678009+00:00
---

# cartridges/swarm/brain/access_grant_context.zig

```zig
// DAM-1 — the access-grant ScriptContextBuilder.
//
// Engine-checked data access (LOCKSCRIPT-CLEAVAGE §3.5): the `.handler`
// for `access.grant.verify.intent` runs on the real 2-PDA and must see a
// pre-built execution Context. This builder (mirrors
// cells_mint_spv_context.zig) gates on the verify-intent typeHash, loads
// the LINEAR `access.grant` cell by hash from the cell store, computes the
// challenge digest, and hands the cell-engine a `host_verify_partial_sig`
// Context so the handler's `OP_CALLHOST "host_verify_partial_sig"` verifies
// the grantee's challenge signature.
//
// Reuse, not new host calls: the verification IS the existing
// host_verify_partial_sig (pubkey, digest, signature). Expiry + domain/type
// scope are checked in the handler against the grant cell, which the
// dispatcher pushes onto the stack via `extra_cells_fn`.
//
// Lifecycle (per cells_mint_handler.ScriptContextBuilder):
//   build : BEFORE script exec — typeHash gate → load grant → digest →
//           host_verify_partial_sig.Context (returns the inner ctx ptr).
//   extra : push the access.grant cell so the handler reads expiry/domain.
//   destroy: AFTER exec — free the owned grant copy + digest + wrapper.

const std = @import("std");
const cells_mint_handler = @import("cells_mint_handler");
const host_verify_partial_sig = @import("host_verify_partial_sig");
const sighash = @import("sighash");
const cell_store_mod = @import("cell_store");
const cell_engine_constants = @import("constants");

const CELL_SIZE = cell_engine_constants.CELL_SIZE;
const HEADER_SIZE = cell_engine_constants.HEADER_SIZE; // 256

// ── Cell-type hashes (sha256 of the canonical type string) ──────────────
//   Matches the swarm convention (sha256("swarm.manifest")).
pub const VERIFY_INTENT_TYPE_HASH: [32]u8 = sha256OfStr("access.grant.verify.intent");
pub const GRANT_TYPE_HASH: [32]u8 = sha256OfStr("access.grant");

fn sha256OfStr(comptime s: []const u8) [32]u8 {
    @setEvalBranchQuota(10000);
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(s, &out, .{});
    return out;
}

// ── Cell layout (header offsets per core/cell-engine/src/constants.zig) ──
const HDR_DOMAIN_FLAG_OFF = 24; // u32 LE
const HDR_TYPE_HASH_OFF = 30; // 32 bytes

// access.grant payload (bytes 256..):
//   [0]      capability_type (2 = DATA_ACCESS)
//   [1..34]  grantee_pubkey (33, compressed — the contact's edge-derived key)
//   [34..66] content_hash (32)
//   [66..74] expiry_ts (u64 LE, unix seconds)
const GRANT_CAP_OFF = 0;
const GRANT_PUBKEY_OFF = 1;
const GRANT_PUBKEY_LEN = 33;
const GRANT_CONTENT_HASH_OFF = 34;
const GRANT_EXPIRY_OFF = 66;
const CAP_DATA_ACCESS: u8 = 2;

// access.grant.verify.intent payload (bytes 256..):
//   [0..32]  grant_cell_hash
//   [32..34] sig_len (u16 LE)
//   [34..]   signature (DER + trailing sighash flag byte)
const VI_GRANT_HASH_OFF = 0;
const VI_SIG_LEN_OFF = 32;
const VI_SIG_OFF = 34;

/// The canonical access-challenge digest — the BIP-143 sighash ("ctx preimage",
/// LOCKSCRIPT-CLEAVAGE §4c) of a synthetic 1-in/1-out access tx that spends the
/// grant cell (input.prev_txid = grant_hash) under a P2PK scriptCode to the
/// grantee, SIGHASH_ALL|FORKID. Deterministic from (grant_hash, grantee_pubkey)
/// so the brain and the grantee derive the IDENTICAL digest. Uses the SAME
/// `sighash.computeSigHashDispatch` path host_compute_sighash uses.
pub fn accessChallengeDigest(grant_hash: [32]u8, grantee_pubkey: [33]u8) ![32]u8 {
    var subscript: [35]u8 = undefined;
    subscript[0] = 0x21; // PUSH 33
    @memcpy(subscript[1..34], &grantee_pubkey);
    subscript[34] = 0xAC; // OP_CHECKSIG

    var tx = sighash.TxContext.init();
    tx.version = 2;
    tx.locktime = 0;
    tx.input_count = 1;
    tx.current_input_index = 0;
    tx.input_value = 1;
    @memcpy(&tx.inputs[0].prev_txid, &grant_hash);
    tx.inputs[0].prev_vout = 0;
    tx.inputs[0].script_len = 0;
    tx.inputs[0].sequence = 0xFFFFFFFF;
    tx.output_count = 1;
    tx.outputs[0].value = 0;
    tx.outputs[0].script_len = 0;

    return sighash.computeSigHashDispatch(&tx, &subscript, sighash.SIGHASH_ALL | sighash.SIGHASH_FORKID);
}

/// Owns the heap allocations the host_verify_partial_sig.Context borrows.
/// `sig_ctx` is what the cell-engine sees; `@fieldParentPtr` recovers this
/// wrapper in destroy so the owned buffers are freed.
const Wrapper = struct {
    sig_ctx: host_verify_partial_sig.Context,
    grant_cell: *[CELL_SIZE]u8, // pubkey slice borrows from here
    digest: *[32]u8,
};

/// Caller-owned state. Holds the cell store the builder loads grants from +
/// a unix-seconds clock for the expiry gate.
pub const State = struct {
    cell_store: *const cell_store_mod.CellStore,
    /// Current unix seconds. host_get_blocktime is a WASM extern (not a named
    /// hostcall), so expiry can't be checked in-script — the builder gates it:
    /// an expired grant gets NO Context, and the handler's host_verify_partial_sig
    /// then fails → OP_VERIFY traps → reject. Brain wires the real clock; tests
    /// inject a fixed time.
    now_fn: *const fn () i64,
};

pub fn toBuilder(state: *State) cells_mint_handler.ScriptContextBuilder {
    return .{
        .state = @ptrCast(state),
        .build_fn = build,
        .destroy_fn = destroy,
        .extra_cells_fn = extraCells,
        .extra_cells_destroy_fn = extraCellsDestroy,
    };
}

fn build(
    state_any: *anyopaque,
    input_cell: *const [CELL_SIZE]u8,
    allocator: std.mem.Allocator,
) ?*anyopaque {
    const state: *State = @ptrCast(@alignCast(state_any));

    // Gate on typeHash — only verify-intent cells get a Context.
    const input_th: *const [32]u8 = input_cell[HDR_TYPE_HASH_OFF .. HDR_TYPE_HASH_OFF + 32][0..32];
    if (!std.mem.eql(u8, input_th, &VERIFY_INTENT_TYPE_HASH)) return null;

    const payload: *const [CELL_SIZE - HEADER_SIZE]u8 = input_cell[HEADER_SIZE..CELL_SIZE];

    // Decode the verify-intent: grant hash + signature (borrows input_cell).
    var grant_hash: [32]u8 = undefined;
    @memcpy(&grant_hash, payload[VI_GRANT_HASH_OFF .. VI_GRANT_HASH_OFF + 32]);
    const sig_len: usize = @as(usize, payload[VI_SIG_LEN_OFF]) | (@as(usize, payload[VI_SIG_LEN_OFF + 1]) << 8);
    if (sig_len < 2 or VI_SIG_OFF + sig_len > payload.len) return null;
    const sig: []const u8 = payload[VI_SIG_OFF .. VI_SIG_OFF + sig_len];

    // Load the referenced LINEAR access.grant cell from the store.
    const grant_opt = state.cell_store.getCell(&grant_hash) catch return null;
    const grant_val = grant_opt orelse return null;

    // Heap-copy the grant cell so the pubkey slice survives execution.
    const grant_cell = allocator.create([CELL_SIZE]u8) catch return null;
    grant_cell.* = grant_val;
    errdefer allocator.destroy(grant_cell);

    // The grant must be an access.grant carrying a DATA_ACCESS capability.
    if (!std.mem.eql(u8, grant_cell[HDR_TYPE_HASH_OFF .. HDR_TYPE_HASH_OFF + 32], &GRANT_TYPE_HASH)) {
        allocator.destroy(grant_cell);
        return null;
    }
    if (grant_cell[HEADER_SIZE + GRANT_CAP_OFF] != CAP_DATA_ACCESS) {
        allocator.destroy(grant_cell);
        return null;
    }

    // Expiry gate (see State.now_fn) — expired grant → no Context → reject.
    const expiry = std.mem.readInt(u64, grant_cell[HEADER_SIZE + GRANT_EXPIRY_OFF .. HEADER_SIZE + GRANT_EXPIRY_OFF + 8][0..8], .little);
    const now = state.now_fn();
    if (now >= 0 and @as(u64, @intCast(now)) > expiry) {
        allocator.destroy(grant_cell);
        return null;
    }

    const gp = grant_cell[HEADER_SIZE + GRANT_PUBKEY_OFF .. HEADER_SIZE + GRANT_PUBKEY_OFF + GRANT_PUBKEY_LEN];

    // The challenge digest is the canonical BIP-143 sighash — the "ctx
    // preimage" (LOCKSCRIPT-CLEAVAGE §4c), computed by the SAME path
    // host_compute_sighash uses — bound to THIS grant: a synthetic access tx
    // spending the grant (input.prev_txid = grant_hash) under a P2PK
    // scriptCode to the grantee, SIGHASH_ALL|FORKID. grant_hash
    // content-addresses the grant, so the digest transitively commits to its
    // domain/content/expiry/grantee. The grantee proves access by signing
    // this exact digest with their edge-derived key (NOT an ad-hoc hash).
    const digest = allocator.create([32]u8) catch {
        allocator.destroy(grant_cell);
        return null;
    };
    digest.* = accessChallengeDigest(grant_hash, gp.*) catch {
        allocator.destroy(digest);
        allocator.destroy(grant_cell);
        return null;
    };

    const wrapper = allocator.create(Wrapper) catch {
        allocator.destroy(grant_cell);
        allocator.destroy(digest);
        return null;
    };
    wrapper.* = .{
        .sig_ctx = .{
            .pubkey = grant_cell[HEADER_SIZE + GRANT_PUBKEY_OFF .. HEADER_SIZE + GRANT_PUBKEY_OFF + GRANT_PUBKEY_LEN],
            .digest = digest,
            .signature = sig,
        },
        .grant_cell = grant_cell,
        .digest = digest,
    };

    // The cell-engine sees the inner sig_ctx; destroy recovers the wrapper.
    return @ptrCast(&wrapper.sig_ctx);
}

fn destroy(state_any: *anyopaque, ctx_any: *anyopaque, allocator: std.mem.Allocator) void {
    _ = state_any;
    const sig_ctx: *host_verify_partial_sig.Context = @ptrCast(@alignCast(ctx_any));
    const wrapper: *Wrapper = @fieldParentPtr("sig_ctx", sig_ctx);
    allocator.destroy(wrapper.grant_cell);
    allocator.destroy(wrapper.digest);
    allocator.destroy(wrapper);
}

/// Push the access.grant cell onto the PDA stack (slot 1) so the handler
/// reads expiry (host_get_blocktime + payload) + scope (OP_CHECKDOMAINFLAG /
/// OP_CHECKCAPABILITY) directly off the cell.
fn extraCells(
    state_any: *anyopaque,
    ctx_any: *anyopaque,
    allocator: std.mem.Allocator,
) ?[]const [CELL_SIZE]u8 {
    _ = state_any;
    const sig_ctx: *host_verify_partial_sig.Context = @ptrCast(@alignCast(ctx_any));
    const wrapper: *Wrapper = @fieldParentPtr("sig_ctx", sig_ctx);
    const out = allocator.alloc([CELL_SIZE]u8, 1) catch return null;
    out[0] = wrapper.grant_cell.*;
    return out;
}

fn extraCellsDestroy(state_any: *anyopaque, extra: []const [CELL_SIZE]u8, allocator: std.mem.Allocator) void {
    _ = state_any;
    allocator.free(extra);
}

// ── Inline tests ──────────────────────────────────────────────────────

const testing = std.testing;

fn testClock() i64 {
    return 1_000_000; // < the 9_999_999_999 expiry the test grants carry
}

/// A minimal in-memory CellStore stub: getCell returns the single grant
/// cell the test seeds; everything else errors/empties.
const StubStore = struct {
    grant: ?[CELL_SIZE]u8 = null,

    fn getCellFn(ctx: *anyopaque, hash: *const [32]u8) cell_store_mod.StoreError!?[CELL_SIZE]u8 {
        _ = hash;
        const self: *StubStore = @ptrCast(@alignCast(ctx));
        return self.grant;
    }
};

fn makeGrantCell(grantee_pub: [33]u8, content_hash: [32]u8, domain_flag: u32, expiry: u64) [CELL_SIZE]u8 {
    var c: [CELL_SIZE]u8 = [_]u8{0} ** CELL_SIZE;
    @memcpy(c[HDR_TYPE_HASH_OFF .. HDR_TYPE_HASH_OFF + 32], &GRANT_TYPE_HASH);
    std.mem.writeInt(u32, c[HDR_DOMAIN_FLAG_OFF .. HDR_DOMAIN_FLAG_OFF + 4][0..4], domain_flag, .little);
    c[HEADER_SIZE + GRANT_CAP_OFF] = CAP_DATA_ACCESS;
    @memcpy(c[HEADER_SIZE + GRANT_PUBKEY_OFF .. HEADER_SIZE + GRANT_PUBKEY_OFF + 33], &grantee_pub);
    @memcpy(c[HEADER_SIZE + GRANT_CONTENT_HASH_OFF .. HEADER_SIZE + GRANT_CONTENT_HASH_OFF + 32], &content_hash);
    std.mem.writeInt(u64, c[HEADER_SIZE + GRANT_EXPIRY_OFF .. HEADER_SIZE + GRANT_EXPIRY_OFF + 8][0..8], expiry, .little);
    return c;
}

fn makeVerifyIntentCell(grant_hash: [32]u8, sig: []const u8) [CELL_SIZE]u8 {
    var c: [CELL_SIZE]u8 = [_]u8{0} ** CELL_SIZE;
    @memcpy(c[HDR_TYPE_HASH_OFF .. HDR_TYPE_HASH_OFF + 32], &VERIFY_INTENT_TYPE_HASH);
    @memcpy(c[HEADER_SIZE + VI_GRANT_HASH_OFF .. HEADER_SIZE + VI_GRANT_HASH_OFF + 32], &grant_hash);
    c[HEADER_SIZE + VI_SIG_LEN_OFF] = @intCast(sig.len & 0xff);
    c[HEADER_SIZE + VI_SIG_LEN_OFF + 1] = @intCast((sig.len >> 8) & 0xff);
    @memcpy(c[HEADER_SIZE + VI_SIG_OFF .. HEADER_SIZE + VI_SIG_OFF + sig.len], sig);
    return c;
}

fn stubCellStore(stub: *StubStore) cell_store_mod.CellStore {
    return .{ .ctx = @ptrCast(stub), .vtable = &stub_vtable };
}

const stub_vtable: cell_store_mod.CellStore.VTable = blk: {
    var vt: cell_store_mod.CellStore.VTable = undefined;
    vt.get_cell = StubStore.getCellFn;
    break :blk vt;
};

test "build: non-verify-intent typeHash returns null" {
    var cell: [CELL_SIZE]u8 = [_]u8{0} ** CELL_SIZE;
    @memcpy(cell[HDR_TYPE_HASH_OFF .. HDR_TYPE_HASH_OFF + 32], &[_]u8{0xAA} ** 32);
    var stub = StubStore{};
    var store = stubCellStore(&stub);
    var state = State{ .cell_store = &store, .now_fn = testClock };
    try testing.expect(build(@ptrCast(&state), &cell, testing.allocator) == null);
}

test "build: verify-intent with a DATA_ACCESS grant produces a sig Context" {
    const grantee_pub = [_]u8{0x02} ** 33;
    const content_hash = [_]u8{0xCC} ** 32;
    const grant = makeGrantCell(grantee_pub, content_hash, 0x00010042, 9_999_999_999);
    var stub = StubStore{ .grant = grant };
    var store = stubCellStore(&stub);
    var state = State{ .cell_store = &store, .now_fn = testClock };

    const sig = [_]u8{0x30} ** 70;
    var vi = makeVerifyIntentCell([_]u8{0x11} ** 32, &sig);

    const ptr = build(@ptrCast(&state), &vi, testing.allocator) orelse return error.unexpected_null;
    const sig_ctx: *host_verify_partial_sig.Context = @ptrCast(@alignCast(ptr));
    try testing.expectEqual(@as(usize, 33), sig_ctx.pubkey.len);
    try testing.expectEqualSlices(u8, &grantee_pub, sig_ctx.pubkey);
    try testing.expectEqual(@as(usize, 32), sig_ctx.digest.len);
    try testing.expectEqualSlices(u8, &sig, sig_ctx.signature);

    // Challenge digest matches the canonical access-challenge ctx preimage
    // (BIP-143 sighash bound to the grant hash + grantee pubkey).
    const expect = try accessChallengeDigest([_]u8{0x11} ** 32, grantee_pub);
    try testing.expectEqualSlices(u8, &expect, sig_ctx.digest);

    destroy(@ptrCast(&state), ptr, testing.allocator);
}

test "build: missing grant cell returns null" {
    var stub = StubStore{ .grant = null };
    var store = stubCellStore(&stub);
    var state = State{ .cell_store = &store, .now_fn = testClock };
    const sig = [_]u8{0x30} ** 70;
    var vi = makeVerifyIntentCell([_]u8{0x11} ** 32, &sig);
    try testing.expect(build(@ptrCast(&state), &vi, testing.allocator) == null);
}

test "build: expired grant returns null (no Context → handler rejects)" {
    const grant = makeGrantCell([_]u8{0x02} ** 33, [_]u8{0xCC} ** 32, 1, 500_000); // expiry < testClock
    var stub = StubStore{ .grant = grant };
    var store = stubCellStore(&stub);
    var state = State{ .cell_store = &store, .now_fn = testClock };
    const sig = [_]u8{0x30} ** 70;
    var vi = makeVerifyIntentCell([_]u8{0x11} ** 32, &sig);
    try testing.expect(build(@ptrCast(&state), &vi, testing.allocator) == null);
}

test "build: grant without DATA_ACCESS capability returns null" {
    var grant = makeGrantCell([_]u8{0x02} ** 33, [_]u8{0xCC} ** 32, 1, 9_999_999_999);
    grant[HEADER_SIZE + GRANT_CAP_OFF] = 5; // TRANSFER, not DATA_ACCESS
    var stub = StubStore{ .grant = grant };
    var store = stubCellStore(&stub);
    var state = State{ .cell_store = &store, .now_fn = testClock };
    const sig = [_]u8{0x30} ** 70;
    var vi = makeVerifyIntentCell([_]u8{0x11} ** 32, &sig);
    try testing.expect(build(@ptrCast(&state), &vi, testing.allocator) == null);
}

test "accessChallengeDigest — cross-impl conformance vector (TS port, DAM-3)" {
    // Pinned byte-for-byte with the TS port in
    // core/protocol-types/src/bsv/access-grant.ts (same hex on both sides). If
    // the synthetic-tx preimage ever changes on either side, both must change
    // together — else a TS grantee's signature never verifies on the 2-PDA.
    const d = try accessChallengeDigest([_]u8{0x11} ** 32, [_]u8{0x02} ** 33);
    var expect: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expect, "ac9b3eb15ec0447f21bb2058c591776555a5eacb187b51c47a32bdb6b1f3d4ae");
    try testing.expectEqualSlices(u8, &expect, &d);
}

test "toBuilder wires build/destroy" {
    var stub = StubStore{};
    var store = stubCellStore(&stub);
    var state = State{ .cell_store = &store, .now_fn = testClock };
    const b = toBuilder(&state);
    try testing.expect(b.build_fn == build);
    try testing.expect(b.destroy_fn == destroy);
    try testing.expect(b.extra_cells_fn != null);
}

```
