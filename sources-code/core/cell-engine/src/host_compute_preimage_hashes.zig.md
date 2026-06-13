---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/host_compute_preimage_hashes.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.982940+00:00
---

# core/cell-engine/src/host_compute_preimage_hashes.zig

```zig
// PR-5: BIP-143 preimage hashing helpers — `host_compute_prevouts_hash`,
// `host_compute_sequence_hash`, `host_compute_outputs_hash` per
// LOCKSCRIPT-CLEAVAGE.md §8.2.
//
// All three hostcalls compute the same operation: double-SHA256 of an
// input byte sequence. They share an implementation but expose three
// distinct names so handler scripts can invoke OP_CALLHOST with the
// intent-naming convention from the BIP-143 preimage spec:
//
//   - prevouts:  SHA256d( concat( prev_txid || prev_vout_LE ) for each input )
//   - sequence:  SHA256d( concat( sequence_LE ) for each input )
//   - outputs:   SHA256d( concat( value_LE || varint(script_len) || script )
//                         for each output )
//
// The hostcall takes the ALREADY-concatenated bytes from the brain-set
// Context and emits a 32-byte digest. Per-input/per-output
// serialization is the dispatcher's responsibility (it has the
// transaction shape available); the hostcall is the SHA256d primitive.
//
// All three are gateless (cap == ""): they're pure CPU functions with
// no security-relevant outputs — they hash whatever the script gives
// them. The cleavage invariant only cares about what hash gets fed
// into `host_compute_sighash`, which IS capability-gated.

const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;
const host = @import("host");

/// Per-invocation context. Brain populates `input_bytes`, invokes the
/// hostcall, then reads `output_hash` on success.
pub const Context = struct {
    /// Already-concatenated bytes to hash. Caller-owned.
    input_bytes: []const u8,

    /// Output slot — handler writes 32-byte digest here on success.
    output_hash: [32]u8 = [_]u8{0} ** 32,
    output_valid: bool = false,
    last_error: u32 = 0,
};

/// Return codes.
pub const RC_OK: u32 = 0;
pub const RC_EMPTY_INPUT: u32 = 1; // SHA256d of empty is well-defined but
// disallowed to catch bugs in dispatcher setup early
pub const RC_INTERNAL_ERROR: u32 = 2;

/// Shared computation: double-SHA256 of `ctx.input_bytes` written to
/// `ctx.output_hash`. All three named hostcalls dispatch to this.
fn computeDoubleSha256(ctx_opaque: *anyopaque) callconv(.c) u32 {
    const ctx: *Context = @ptrCast(@alignCast(ctx_opaque));

    if (ctx.input_bytes.len == 0) {
        ctx.output_valid = false;
        ctx.last_error = RC_EMPTY_INPUT;
        return RC_EMPTY_INPUT;
    }

    var first: [32]u8 = undefined;
    Sha256.hash(ctx.input_bytes, &first, .{});
    Sha256.hash(&first, &ctx.output_hash, .{});
    ctx.output_valid = true;
    ctx.last_error = RC_OK;
    return RC_OK;
}

/// Register all three named hostcalls. Brain calls this once at boot.
/// The three names share the same handler function — the distinction
/// is purely intentional (intent at the call site).
pub fn register() !void {
    try host.registerHostCall("host_compute_prevouts_hash", computeDoubleSha256);
    try host.registerHostCall("host_compute_sequence_hash", computeDoubleSha256);
    try host.registerHostCall("host_compute_outputs_hash", computeDoubleSha256);
}

// ── Inline tests ──────────────────────────────────────────────────────

const testing = std.testing;

test "register: idempotent failure on duplicate" {
    host.resetRegistryForTest();
    try register();
    try testing.expectError(error.duplicate_registration, register());
    // 3 names registered on the first call.
    try testing.expectEqual(@as(usize, 3), host.registryCountForTest());
}

test "register: all 3 named hostcalls present after boot" {
    host.resetRegistryForTest();
    try register();
    try testing.expectEqual(@as(usize, 3), host.registryCountForTest());
}

test "computeDoubleSha256: produces deterministic 32-byte digest" {
    host.resetRegistryForTest();
    try register();

    var ctx: Context = .{
        .input_bytes = &[_]u8{ 0xAA, 0xBB, 0xCC },
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_compute_prevouts_hash");
    try testing.expectEqual(RC_OK, rc);
    try testing.expect(ctx.output_valid);

    // Re-run — must produce identical output.
    const digest_1 = ctx.output_hash;
    ctx.output_valid = false;
    _ = host.callByName("host_compute_prevouts_hash");
    try testing.expectEqualSlices(u8, &digest_1, &ctx.output_hash);
}

test "computeDoubleSha256: empty input → RC_EMPTY_INPUT" {
    host.resetRegistryForTest();
    try register();

    var ctx: Context = .{ .input_bytes = &[_]u8{} };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_compute_prevouts_hash");
    try testing.expectEqual(RC_EMPTY_INPUT, rc);
    try testing.expect(!ctx.output_valid);
}

test "all three named hostcalls produce identical output for identical input" {
    // Confirms the three names share the same impl. If we ever split
    // them (e.g., a future PR adds per-name validation), this test
    // surfaces the divergence.
    host.resetRegistryForTest();
    try register();

    var ctx: Context = .{
        .input_bytes = &[_]u8{ 1, 2, 3, 4, 5 },
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    _ = host.callByName("host_compute_prevouts_hash");
    const d_prevouts = ctx.output_hash;

    ctx.output_valid = false;
    _ = host.callByName("host_compute_sequence_hash");
    const d_sequence = ctx.output_hash;

    ctx.output_valid = false;
    _ = host.callByName("host_compute_outputs_hash");
    const d_outputs = ctx.output_hash;

    try testing.expectEqualSlices(u8, &d_prevouts, &d_sequence);
    try testing.expectEqualSlices(u8, &d_sequence, &d_outputs);
}

test "computeDoubleSha256 matches manually-computed SHA256d" {
    // Sanity-check against std.crypto directly — catches any drift in
    // the handler's hashing logic.
    host.resetRegistryForTest();
    try register();

    const input = "the quick brown fox";
    var ctx: Context = .{ .input_bytes = input };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    _ = host.callByName("host_compute_prevouts_hash");
    try testing.expect(ctx.output_valid);

    // Compute SHA256d manually.
    var first: [32]u8 = undefined;
    Sha256.hash(input, &first, .{});
    var expected: [32]u8 = undefined;
    Sha256.hash(&first, &expected, .{});

    try testing.expectEqualSlices(u8, &expected, &ctx.output_hash);
}

```
