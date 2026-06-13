---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/host_mnca_verify_transition.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.978945+00:00
---

# core/cell-engine/src/host_mnca_verify_transition.zig

```zig
// PR-8b-i: host_mnca_verify_transition — cell-engine native hostcall
// wrapping `mnca_tile.stepTilePayload` as the MNCA-transition
// determinism oracle per LOCKSCRIPT-CLEAVAGE.md §7.2 / §8.2.
//
// The MNCA anchor state machine's transition handler invokes this
// hostcall to confirm that a claimed next_snapshot_hash was computed
// by deterministically applying the MNCA rule to the predecessor
// snapshot. Without this oracle, the substrate would have to trust
// the operator's word — defeating the cleavage invariant that every
// byte the wallet signs commits to a hash whose origin is verifiable.
//
// Architecture mirror of PR-7a (host_verify_beef_spv): Context-style
// inputs the brain populates pre-execution, packed (verdict, error_tag)
// rc the script reads via OP_DUP + DIV/MOD by 256 (same pattern as
// PR-7d). The actual computation lives in `mnca_tile.zig::
// stepTilePayload` — fully deterministic, allocation-free, integer-
// arithmetic per the locked design (memory: mnca_design_decisions).
//
// Capability: `cap.mnca.verify` — declared in the brain's
// `host_capability_table` (PR-8b-iv wires it).
//
// Scope (PR-8b-i): single-tile transition verification. The MNCA
// snapshot is the union of all tiles in the grid; the snapshot-level
// determinism verification is the union of per-tile verifications,
// orchestrated by the handler script across multiple OP_CALLHOST
// invocations. Each invocation handles ONE tile transition — small
// per-call cost (one stepTilePayload + one SHA-256), composes
// trivially via the script's loop opcodes.

const std = @import("std");
const host = @import("host");
const mnca_tile = @import("mnca_tile");
const Sha256 = std.crypto.hash.sha2.Sha256;

// ── Verdict / error_tag values (wire-format for the MNCA transition oracle) ──

pub const VERDICT_INVALID: u8 = 0;
pub const VERDICT_VALID: u8 = 1;
pub const VERDICT_ERROR: u8 = 2;

pub const ERROR_TAG_NONE: u8 = 0;
/// Predecessor payload was not exactly mnca_tile.PAYLOAD_SIZE (768) bytes.
pub const ERROR_TAG_BAD_PAYLOAD_LEN: u8 = 1;
/// Verdict=Invalid: re-derived hash differs from the claimed hash. This is
/// the "no" verdict — the proof failed, but the hostcall ran to completion.
pub const ERROR_TAG_HASH_MISMATCH: u8 = 2;
/// Verdict=Error: internal (should never happen). Reserved.
pub const ERROR_TAG_INTERNAL: u8 = 3;

/// Per-invocation context. Brain populates inputs + the rule params,
/// invokes the hostcall, then reads `last_derived_hash` and
/// `last_verdict` to populate the result cell payload.
pub const Context = struct {
    /// Predecessor tile payload — exactly 768 bytes
    /// (mnca_tile.PAYLOAD_SIZE). Caller-owned; lifetime ≥ hostcall.
    predecessor_tile_payload: []const u8,
    /// 32-byte SHA-256 of the successor tile payload the script claims
    /// is the deterministic next-state. The hostcall re-derives the
    /// successor via stepTilePayload + hashes it + compares.
    claimed_next_hash: [32]u8,
    /// Optional rule parameters. Null means use the substrate's
    /// `DEFAULT_MNCA_RULE` — the canonical params Todd ships with
    /// the reference oracle. Caller passes explicit params when the
    /// cartridge declares a non-default rule.
    rule_params: ?mnca_tile.MncaRuleParams = null,

    /// Output: SHA-256 of the re-derived successor tile payload.
    /// Always set on success (Valid or Invalid verdict) so audit logs
    /// can record "claimed X, derived Y". Zero on the Error path.
    last_derived_hash: [32]u8 = [_]u8{0} ** 32,
    /// Output: verdict (Valid / Invalid / Error).
    last_verdict: u8 = 0,
    /// Output: error_tag discriminant (see ERROR_TAG_* constants).
    last_error_tag: u8 = 0,
    /// Internal — last hostcall return code, for debugging.
    last_return_code: u32 = 0,
};

// ── Packed return code (PR-7d-style) ──────────────────────────────────
//
// u32 packing so the script reads both values without a separate
// stack-push mechanism:
//
//     bits 0..7   : verdict     (VERDICT_INVALID/VALID/ERROR)
//     bits 8..15  : error_tag   (ERROR_TAG_*)
//     bits 16..31 : reserved (zero — future expansion)
//
// Script extraction:
//
//     OP_DUP                    # [rc, rc]
//     PUSH 256; OP_MOD          # [rc, verdict]
//     OP_SWAP                   # [verdict, rc]
//     PUSH 256; OP_DIV          # [verdict, error_tag]

inline fn packRc(verdict: u8, error_tag: u8) u32 {
    return (@as(u32, error_tag) << 8) | @as(u32, verdict);
}

pub inline fn verdictOf(rc: u32) u8 {
    return @intCast(rc & 0xFF);
}

pub inline fn errorTagOf(rc: u32) u8 {
    return @intCast((rc >> 8) & 0xFF);
}

// Named rc constants for the canonical outcomes — supersede ad-hoc
// `packRc` calls at the test-assertion site. rc == 0 is unreachable
// (every branch sets at least one non-zero field) so scripts can
// treat rc == 0 as a "registry-sentinel-returned-without-invoking-us"
// trap.

pub const RC_VALID: u32 = (@as(u32, ERROR_TAG_NONE) << 8) | VERDICT_VALID;
pub const RC_INVALID_HASH_MISMATCH: u32 =
    (@as(u32, ERROR_TAG_HASH_MISMATCH) << 8) | VERDICT_INVALID;
pub const RC_ERROR_BAD_PAYLOAD_LEN: u32 =
    (@as(u32, ERROR_TAG_BAD_PAYLOAD_LEN) << 8) | VERDICT_ERROR;

/// Registered handler. Re-derives the successor tile via
/// `mnca_tile.stepTilePayload`, hashes it, compares to the claimed
/// hash, returns a packed rc.
pub fn handle(ctx_opaque: *anyopaque) callconv(.c) u32 {
    const ctx: *Context = @ptrCast(@alignCast(ctx_opaque));

    // Wire-shape sanity. Predecessor payload MUST be a full tile.
    if (ctx.predecessor_tile_payload.len != mnca_tile.PAYLOAD_SIZE) {
        ctx.last_verdict = VERDICT_ERROR;
        ctx.last_error_tag = ERROR_TAG_BAD_PAYLOAD_LEN;
        ctx.last_return_code = RC_ERROR_BAD_PAYLOAD_LEN;
        return RC_ERROR_BAD_PAYLOAD_LEN;
    }

    // Re-derive the successor tile. Allocation-free — output buffer
    // sits on the stack (768 bytes is fine; brain stacks are 1 MB+).
    var derived: [mnca_tile.PAYLOAD_SIZE]u8 = undefined;
    const params = ctx.rule_params orelse mnca_tile.DEFAULT_MNCA_RULE;
    // Cast slice ptr → fixed-array ptr. Safe — we just checked the
    // length above.
    const in_ptr: *const [mnca_tile.PAYLOAD_SIZE]u8 = @ptrCast(ctx.predecessor_tile_payload.ptr);
    mnca_tile.stepTilePayload(in_ptr, &derived, params);

    // Hash + compare.
    Sha256.hash(&derived, &ctx.last_derived_hash, .{});

    if (std.mem.eql(u8, &ctx.last_derived_hash, &ctx.claimed_next_hash)) {
        ctx.last_verdict = VERDICT_VALID;
        ctx.last_error_tag = ERROR_TAG_NONE;
        ctx.last_return_code = RC_VALID;
        return RC_VALID;
    }

    // Hashes differ — verification reached a verdict, the verdict was
    // "no". This is INVALID, not ERROR: the proof was malformed, not
    // the inputs.
    ctx.last_verdict = VERDICT_INVALID;
    ctx.last_error_tag = ERROR_TAG_HASH_MISMATCH;
    ctx.last_return_code = RC_INVALID_HASH_MISMATCH;
    return RC_INVALID_HASH_MISMATCH;
}

/// Register `host_mnca_verify_transition` with the cell-engine host
/// registry. Brain calls this once at boot.
pub fn register() !void {
    try host.registerHostCall("host_mnca_verify_transition", handle);
}

// ── Inline tests ──────────────────────────────────────────────────────

const testing = std.testing;

/// Synthesize a deterministic predecessor tile payload + compute its
/// deterministic successor (post-stepTilePayload) + return both. Used
/// across multiple tests to exercise the Valid / Invalid / Error
/// paths without bespoke fixtures.
fn synthTransition() struct {
    predecessor: [mnca_tile.PAYLOAD_SIZE]u8,
    successor: [mnca_tile.PAYLOAD_SIZE]u8,
    successor_hash: [32]u8,
} {
    var pred: [mnca_tile.PAYLOAD_SIZE]u8 = [_]u8{0} ** mnca_tile.PAYLOAD_SIZE;
    // Write a small valid tile header: 8×8 grid, halo=1 (interior 6×6).
    mnca_tile.writeHeader(&pred, 5, 7, 100, 8, 8, 1, 0);
    // Seed the interior with a glider-like pattern. The state byte
    // values are arbitrary; we just need stepTilePayload to produce
    // a stable next-generation we can pin to a hash.
    pred[mnca_tile.OFF_STATE + 8 * 1 + 1] = 200;
    pred[mnca_tile.OFF_STATE + 8 * 1 + 2] = 200;
    pred[mnca_tile.OFF_STATE + 8 * 2 + 2] = 200;
    pred[mnca_tile.OFF_STATE + 8 * 2 + 1] = 200;

    var succ: [mnca_tile.PAYLOAD_SIZE]u8 = undefined;
    mnca_tile.stepTilePayload(&pred, &succ, mnca_tile.DEFAULT_MNCA_RULE);

    var hash: [32]u8 = undefined;
    Sha256.hash(&succ, &hash, .{});

    return .{ .predecessor = pred, .successor = succ, .successor_hash = hash };
}

test "register: idempotent failure on duplicate" {
    host.resetRegistryForTest();
    try register();
    try testing.expectError(error.duplicate_registration, register());
    try testing.expectEqual(@as(usize, 1), host.registryCountForTest());
}

test "handle: bad payload length → RC_ERROR_BAD_PAYLOAD_LEN" {
    host.resetRegistryForTest();
    try register();

    var ctx: Context = .{
        .predecessor_tile_payload = &[_]u8{0xAA} ** 100, // wrong length
        .claimed_next_hash = [_]u8{0} ** 32,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_mnca_verify_transition");
    try testing.expectEqual(RC_ERROR_BAD_PAYLOAD_LEN, rc);
    try testing.expectEqual(VERDICT_ERROR, verdictOf(rc));
    try testing.expectEqual(ERROR_TAG_BAD_PAYLOAD_LEN, errorTagOf(rc));
    try testing.expectEqual(VERDICT_ERROR, ctx.last_verdict);
}

test "handle: deterministic re-derivation matches claimed hash → RC_VALID" {
    host.resetRegistryForTest();
    try register();

    const s = synthTransition();
    var ctx: Context = .{
        .predecessor_tile_payload = &s.predecessor,
        .claimed_next_hash = s.successor_hash,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_mnca_verify_transition");
    try testing.expectEqual(RC_VALID, rc);
    try testing.expectEqual(VERDICT_VALID, ctx.last_verdict);
    try testing.expectEqual(ERROR_TAG_NONE, ctx.last_error_tag);
    // last_derived_hash should equal the claimed hash on Valid.
    try testing.expectEqualSlices(u8, &s.successor_hash, &ctx.last_derived_hash);
}

test "handle: claimed hash mismatch → RC_INVALID_HASH_MISMATCH" {
    host.resetRegistryForTest();
    try register();

    const s = synthTransition();
    // Tamper the claimed hash so the comparison fails.
    var tampered = s.successor_hash;
    tampered[0] ^= 0xFF;
    var ctx: Context = .{
        .predecessor_tile_payload = &s.predecessor,
        .claimed_next_hash = tampered,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_mnca_verify_transition");
    try testing.expectEqual(RC_INVALID_HASH_MISMATCH, rc);
    try testing.expectEqual(VERDICT_INVALID, ctx.last_verdict);
    try testing.expectEqual(ERROR_TAG_HASH_MISMATCH, ctx.last_error_tag);
    // last_derived_hash carries the ACTUAL hash so audit logs can see
    // what the predecessor would have stepped to.
    try testing.expectEqualSlices(u8, &s.successor_hash, &ctx.last_derived_hash);
}

test "handle: re-running with same inputs is byte-identical (determinism oracle)" {
    host.resetRegistryForTest();
    try register();

    const s = synthTransition();
    var ctx: Context = .{
        .predecessor_tile_payload = &s.predecessor,
        .claimed_next_hash = s.successor_hash,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc1 = host.callByName("host_mnca_verify_transition");
    const derived1 = ctx.last_derived_hash;

    // Reset Context outputs and re-invoke.
    ctx.last_derived_hash = [_]u8{0} ** 32;
    ctx.last_verdict = 0;
    const rc2 = host.callByName("host_mnca_verify_transition");

    try testing.expectEqual(rc1, rc2);
    try testing.expectEqualSlices(u8, &derived1, &ctx.last_derived_hash);
}

test "packed rc: outcomeOf/errorTagOf round-trip every named constant" {
    try testing.expectEqual(VERDICT_VALID, verdictOf(RC_VALID));
    try testing.expectEqual(ERROR_TAG_NONE, errorTagOf(RC_VALID));

    try testing.expectEqual(VERDICT_INVALID, verdictOf(RC_INVALID_HASH_MISMATCH));
    try testing.expectEqual(ERROR_TAG_HASH_MISMATCH, errorTagOf(RC_INVALID_HASH_MISMATCH));

    try testing.expectEqual(VERDICT_ERROR, verdictOf(RC_ERROR_BAD_PAYLOAD_LEN));
    try testing.expectEqual(ERROR_TAG_BAD_PAYLOAD_LEN, errorTagOf(RC_ERROR_BAD_PAYLOAD_LEN));
}

test "packed rc: rc == 0 is unreachable in normal hostcall output" {
    // Every named constant is non-zero — scripts treating rc==0 as a
    // "registry sentinel returned without invoking us" trap don't
    // false-trigger.
    try testing.expect(RC_VALID != 0);
    try testing.expect(RC_INVALID_HASH_MISMATCH != 0);
    try testing.expect(RC_ERROR_BAD_PAYLOAD_LEN != 0);
}

test "packed rc: reserved high bits are zero" {
    try testing.expectEqual(@as(u32, 0), RC_VALID & 0xFFFF0000);
    try testing.expectEqual(@as(u32, 0), RC_INVALID_HASH_MISMATCH & 0xFFFF0000);
    try testing.expectEqual(@as(u32, 0), RC_ERROR_BAD_PAYLOAD_LEN & 0xFFFF0000);
}

```
