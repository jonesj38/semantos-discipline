---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/host_verify_partial_sig.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.977819+00:00
---

# core/cell-engine/src/host_verify_partial_sig.zig

```zig
// PR-5: host_verify_partial_sig — verify a partial-tx contribution's
// ECDSA signature against a known sighash digest + pubkey, per
// LOCKSCRIPT-CLEAVAGE.md §8.2.
//
// Contribution handler use:
//
//   1. The handler receives a partial-tx contribution cell carrying
//      (counterparty pubkey, signed digest, signature bytes including
//      the trailing sighash flag byte per BSV convention).
//   2. The handler script extracts those three values into a
//      `Context` (populated by the brain before script execution).
//   3. Script invokes OP_CALLHOST "host_verify_partial_sig".
//   4. Handler delegates to `host.checksig` (which already handles
//      BSVZ-backed secp256k1 verification + sighash-byte stripping).
//   5. Returns 0 if the signature verifies, 1 if not.
//
// Why a distinct hostcall name (vs reusing OP_CHECKSIG): script-side
// OP_CHECKSIG pops its operands from the PDA main stack, which limits
// each operand to 1024 bytes — fine for typical signatures but
// awkward for the contribution-handler pattern where the values
// arrive in cell payloads. The hostcall reads from a pre-set Context,
// so the brain can wire any inputs the cartridge needs without
// per-opcode stack juggling. Capability gating also lets the broker
// audit partial-sig verification specifically (cap.tx.sign) vs other
// CHECKSIG uses.

const std = @import("std");
const host = @import("host");

/// Per-invocation context. Brain populates fields, invokes the
/// hostcall, then reads `last_valid` to know whether the signature
/// verified.
pub const Context = struct {
    /// Counterparty's compressed-secp256k1 public key (33 bytes typical).
    pubkey: []const u8,
    /// 32-byte sighash digest the partial signature is supposed to cover.
    digest: []const u8,
    /// DER-encoded signature with the trailing sighash flag byte
    /// appended per BSV convention. `host.checksig` strips that byte
    /// before DER decode.
    signature: []const u8,

    /// Handler writes the verification outcome here. True iff the
    /// signature passes ECDSA verification.
    last_valid: bool = false,
    last_error: u32 = 0,
};

/// Return codes the handler emits.
pub const RC_OK: u32 = 0; // signature verified
pub const RC_REJECTED: u32 = 1; // signature did NOT verify
pub const RC_INVALID_INPUT: u32 = 2; // digest != 32 bytes, or pubkey/sig empty

/// Registered handler. Delegates to `host.checksig`.
pub fn handle(ctx_opaque: *anyopaque) callconv(.c) u32 {
    const ctx: *Context = @ptrCast(@alignCast(ctx_opaque));

    if (ctx.digest.len != 32 or ctx.pubkey.len == 0 or ctx.signature.len < 2) {
        ctx.last_valid = false;
        ctx.last_error = RC_INVALID_INPUT;
        return RC_INVALID_INPUT;
    }

    if (host.checksig(ctx.pubkey, ctx.digest, ctx.signature)) {
        ctx.last_valid = true;
        ctx.last_error = RC_OK;
        return RC_OK;
    }
    ctx.last_valid = false;
    ctx.last_error = RC_REJECTED;
    return RC_REJECTED;
}

/// Register `host_verify_partial_sig` with the cell-engine host
/// registry. Brain calls this once at boot.
pub fn register() !void {
    try host.registerHostCall("host_verify_partial_sig", handle);
}

// ── Inline tests ──────────────────────────────────────────────────────

const testing = std.testing;

test "register: idempotent failure on duplicate" {
    host.resetRegistryForTest();
    try register();
    try testing.expectError(error.duplicate_registration, register());
    try testing.expectEqual(@as(usize, 1), host.registryCountForTest());
}

test "handle: invalid digest length → RC_INVALID_INPUT" {
    host.resetRegistryForTest();
    try register();

    var pubkey: [33]u8 = [_]u8{0x02} ** 33;
    var digest: [16]u8 = [_]u8{0xAA} ** 16; // wrong length
    var sig: [72]u8 = [_]u8{0x30} ** 72;
    var ctx: Context = .{
        .pubkey = &pubkey,
        .digest = &digest,
        .signature = &sig,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_verify_partial_sig");
    try testing.expectEqual(RC_INVALID_INPUT, rc);
    try testing.expect(!ctx.last_valid);
}

test "handle: empty pubkey → RC_INVALID_INPUT" {
    host.resetRegistryForTest();
    try register();

    var digest: [32]u8 = [_]u8{0xAA} ** 32;
    var sig: [72]u8 = [_]u8{0x30} ** 72;
    var ctx: Context = .{
        .pubkey = &[_]u8{},
        .digest = &digest,
        .signature = &sig,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_verify_partial_sig");
    try testing.expectEqual(RC_INVALID_INPUT, rc);
}

test "handle: tampered signature → RC_REJECTED" {
    host.resetRegistryForTest();
    try register();

    // Use a syntactically-valid but cryptographically-bogus triple.
    // host.checksig will return false (no matching pubkey).
    var pubkey: [33]u8 = [_]u8{0x02} ** 33;
    var digest: [32]u8 = [_]u8{0xAA} ** 32;
    var sig: [72]u8 = [_]u8{0x30} ** 72;
    var ctx: Context = .{
        .pubkey = &pubkey,
        .digest = &digest,
        .signature = &sig,
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_verify_partial_sig");
    try testing.expectEqual(RC_REJECTED, rc);
    try testing.expect(!ctx.last_valid);
}

```
