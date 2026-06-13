---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/host_compute_sighash.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.980943+00:00
---

# core/cell-engine/src/host_compute_sighash.zig

```zig
// PR-3b: host_compute_sighash — the cell-engine-facing handler for
// the dual-algorithm sighash computation.
//
// Scripts invoke this hostcall via OP_CALLHOST "host_compute_sighash"
// (per LOCKSCRIPT-CLEAVAGE.md §3.5 / §4 / §8). The handler reads
// (tx, subscript, sighash_type) from the execution context the brain
// has populated, dispatches via sighash.computeSigHashDispatch (which
// branches on the CHRONICLE bit 0x20 to select BIP-143 vs OTDA), and
// writes the 32-byte digest into the context.
//
// Why a separate file: keeps host.zig focused on the registry mechanism
// + crypto wrappers; lets a future PR add sibling hostcall handlers
// (host_compute_prevouts_hash, host_verify_partial_sig, etc.) without
// host.zig growing into a dispatch monolith.
//
// Lifecycle:
//
//   1. Brain boot calls `register(allocator)` once (allocator unused
//      today but present for future hostcalls that need workspace).
//   2. Per script invocation, brain constructs a `Context` carrying the
//      tx pointer + subscript bytes + sighash_type byte, then calls
//      `host.setExecutionContext(&ctx)` before running the script.
//   3. Script invokes OP_CALLHOST "host_compute_sighash"; the registry
//      dispatches to `handle` below.
//   4. `handle` casts the opaque pointer back to *Context, computes
//      the digest, stores it in `ctx.last_digest`, sets
//      `ctx.last_digest_valid = true`, returns 0.
//   5. On dispatch error (invalid_sighash, sighash_single_bug, etc.)
//      the handler returns a non-zero error code; script reads the
//      pushed return value via the next opcode (typically OP_VERIFY).

const std = @import("std");
const host = @import("host");
const sighash = @import("sighash");

/// Context shape the brain populates per script invocation. Cast back
/// from `*anyopaque` inside `handle`.
pub const Context = struct {
    /// Inputs (populated by the brain before script execution)
    tx: *const sighash.TxContext,
    subscript: []const u8,
    sighash_type: u8,

    /// Output slot (handler writes here on success)
    last_digest: [32]u8 = [_]u8{0} ** 32,
    last_digest_valid: bool = false,

    /// Error code from the last call (mirrors the handler's return
    /// value; useful for debugging when the script just sees the
    /// integer pushed by OP_CALLHOST).
    last_error: u32 = 0,
};

/// Return codes the handler emits via OP_CALLHOST. These must fit in
/// u32 because that's the return type of host.callByName.
pub const RC_OK: u32 = 0;
pub const RC_INVALID_SIGHASH: u32 = 1;
pub const RC_SIGHASH_SINGLE_BUG: u32 = 2;
pub const RC_INTERNAL_ERROR: u32 = 3;

/// Registered handler. Reads the context, computes the digest via
/// `sighash.computeSigHashDispatch`, stores it on success, returns
/// a status code matching `RC_*` above.
pub fn handle(ctx_opaque: *anyopaque) callconv(.c) u32 {
    const ctx: *Context = @ptrCast(@alignCast(ctx_opaque));
    const digest = sighash.computeSigHashDispatch(ctx.tx, ctx.subscript, ctx.sighash_type) catch |err| {
        ctx.last_digest_valid = false;
        ctx.last_error = switch (err) {
            error.invalid_sighash => RC_INVALID_SIGHASH,
            error.sighash_single_bug => RC_SIGHASH_SINGLE_BUG,
            error.no_tx_context, error.invalid_script => RC_INTERNAL_ERROR,
        };
        return ctx.last_error;
    };
    @memcpy(&ctx.last_digest, &digest);
    ctx.last_digest_valid = true;
    ctx.last_error = RC_OK;
    return RC_OK;
}

/// Register `host_compute_sighash` with the cell-engine host registry.
/// Brain calls this once at boot.
pub fn register() !void {
    try host.registerHostCall("host_compute_sighash", handle);
}

// ── Inline tests ──────────────────────────────────────────────────────

const testing = std.testing;

fn fixtureTxContext() sighash.TxContext {
    var ctx = sighash.TxContext.init();
    ctx.version = 2;
    ctx.locktime = 0;
    ctx.current_input_index = 0;
    ctx.input_value = 50_000;
    ctx.input_count = 1;
    ctx.output_count = 1;
    @memset(&ctx.inputs[0].prev_txid, 0xAB);
    ctx.inputs[0].prev_vout = 0;
    ctx.inputs[0].script_len = 0;
    ctx.inputs[0].sequence = 0xFFFFFFFF;
    ctx.outputs[0].value = 49_500;
    ctx.outputs[0].script_len = 2;
    ctx.outputs[0].script[0] = 0x51;
    ctx.outputs[0].script[1] = 0x69;
    return ctx;
}

test "register: idempotent failure on duplicate" {
    host.resetRegistryForTest();
    try register();
    try testing.expectError(error.duplicate_registration, register());
    try testing.expectEqual(@as(usize, 1), host.registryCountForTest());
}

test "handle: BIP-143 path produces digest matching computeSigHashDispatch" {
    host.resetRegistryForTest();
    try register();

    var tx_ctx = fixtureTxContext();
    var hc_ctx: Context = .{
        .tx = &tx_ctx,
        .subscript = &[_]u8{ 0x51, 0x51, 0x69 },
        .sighash_type = sighash.SIGHASH_ALL | sighash.SIGHASH_FORKID,
    };
    host.setExecutionContext(@ptrCast(&hc_ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_compute_sighash");
    try testing.expectEqual(RC_OK, rc);
    try testing.expect(hc_ctx.last_digest_valid);

    const direct = try sighash.computeSigHashDispatch(
        &tx_ctx,
        &[_]u8{ 0x51, 0x51, 0x69 },
        sighash.SIGHASH_ALL | sighash.SIGHASH_FORKID,
    );
    try testing.expectEqualSlices(u8, &direct, &hc_ctx.last_digest);
}

test "handle: OTDA path (CHRONICLE bit) produces digest matching direct call" {
    host.resetRegistryForTest();
    try register();

    var tx_ctx = fixtureTxContext();
    var hc_ctx: Context = .{
        .tx = &tx_ctx,
        .subscript = &[_]u8{ 0x51, 0x51, 0x69 },
        .sighash_type = sighash.SIGHASH_ALL | sighash.SIGHASH_CHRONICLE,
    };
    host.setExecutionContext(@ptrCast(&hc_ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_compute_sighash");
    try testing.expectEqual(RC_OK, rc);
    try testing.expect(hc_ctx.last_digest_valid);

    const direct = try sighash.computeSigHashDispatch(
        &tx_ctx,
        &[_]u8{ 0x51, 0x51, 0x69 },
        sighash.SIGHASH_ALL | sighash.SIGHASH_CHRONICLE,
    );
    try testing.expectEqualSlices(u8, &direct, &hc_ctx.last_digest);
}

test "handle: invalid_sighash surfaces RC_INVALID_SIGHASH" {
    host.resetRegistryForTest();
    try register();

    var tx_ctx = fixtureTxContext();
    var hc_ctx: Context = .{
        .tx = &tx_ctx,
        .subscript = &[_]u8{ 0x51, 0x51, 0x69 },
        // Neither CHRONICLE nor FORKID — BIP-143 rejects.
        .sighash_type = sighash.SIGHASH_ALL,
    };
    host.setExecutionContext(@ptrCast(&hc_ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_compute_sighash");
    try testing.expectEqual(RC_INVALID_SIGHASH, rc);
    try testing.expect(!hc_ctx.last_digest_valid);
    try testing.expectEqual(RC_INVALID_SIGHASH, hc_ctx.last_error);
}

test "handle: sighash_single_bug surfaces RC_SIGHASH_SINGLE_BUG" {
    host.resetRegistryForTest();
    try register();

    var tx_ctx = fixtureTxContext();
    // Push current_input_index past output_count to trigger the bug.
    tx_ctx.current_input_index = 1;
    tx_ctx.input_count = 2;
    @memset(&tx_ctx.inputs[1].prev_txid, 0xCD);
    tx_ctx.inputs[1].prev_vout = 1;
    tx_ctx.inputs[1].script_len = 0;
    tx_ctx.inputs[1].sequence = 0xFFFFFFFF;

    var hc_ctx: Context = .{
        .tx = &tx_ctx,
        .subscript = &[_]u8{ 0x51, 0x51, 0x69 },
        .sighash_type = sighash.SIGHASH_SINGLE | sighash.SIGHASH_CHRONICLE,
    };
    host.setExecutionContext(@ptrCast(&hc_ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_compute_sighash");
    try testing.expectEqual(RC_SIGHASH_SINGLE_BUG, rc);
    try testing.expect(!hc_ctx.last_digest_valid);
}

test "callByName: unknown function returns 0xFFFFFFFF" {
    host.resetRegistryForTest();
    try register();

    var tx_ctx = fixtureTxContext();
    var hc_ctx: Context = .{
        .tx = &tx_ctx,
        .subscript = &[_]u8{ 0x51, 0x51, 0x69 },
        .sighash_type = sighash.SIGHASH_ALL | sighash.SIGHASH_FORKID,
    };
    host.setExecutionContext(@ptrCast(&hc_ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_definitely_not_registered");
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), rc);
}

test "callByName: no execution context returns 0xFFFFFFFE" {
    host.resetRegistryForTest();
    try register();
    // Note: NOT calling setExecutionContext — leave it null.

    const rc = host.callByName("host_compute_sighash");
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), rc);
}

```
