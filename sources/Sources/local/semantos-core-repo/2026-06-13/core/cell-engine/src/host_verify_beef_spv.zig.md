---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/host_verify_beef_spv.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.976380+00:00
---

# core/cell-engine/src/host_verify_beef_spv.zig

```zig
// PR-7a: host_verify_beef_spv — cell-engine native hostcall wrapper
// around `beef.verifyBeefSpv` per LOCKSCRIPT-CLEAVAGE.md §8.2 / PR-7
// dependency.
//
// Before PR-7a, `host_verify_beef_spv` lived only on the wasmtime side
// (runtime/semantos-brain/src/wasmtime_runner_real.zig) — handler scripts
// running in the cell-engine couldn't reach it via OP_CALLHOST. With
// the 2PDA-WASM excise (PR-1 of the recovery) the wasmtime path is
// gone for substrate handlers; the cell-engine is the runtime.
//
// This module mirrors the PR-3b / PR-4 / PR-5 / PR-5b pattern:
//   1. Brain populates a `Context` with (beef_bytes, txid, trusted_roots)
//      before script execution.
//   2. Handler script invokes OP_CALLHOST "host_verify_beef_spv".
//   3. Dispatch reads the Context, runs `beef.verifyBeefSpv`, writes
//      back (last_outcome, last_error_tag, last_valid).
//   4. Script reads outputs from Context post-callhost to populate the
//      `bsv.spv.verify.result` cell payload.
//
// The actual SPV math (BEEF parse + BUMP merkle-root computation +
// trusted-root comparison) is unchanged from `core/cell-engine/src/
// beef.zig::verifyBeefSpv`. This module is the registry plumbing.
//
// Capability: `bsv.beef.verify` — already declared in the brain's
// `host_capability_table`. The brain enforces it at script-handler
// binding time (cartridge capability surface).
//
// Embedded builds: the cell-engine `beef.zig` module is gated off in
// `embedded` profile (no bsvz). This module follows suit — when the
// caller compiles without the beef dependency, the registration is a
// no-op and `host_verify_beef_spv` is simply not in the registry.
// Handler scripts that invoke it will trap with the registry's
// `0xFFFFFFFF` unknown-name sentinel — correct behaviour for a
// substrate that doesn't support BEEF SPV.

const std = @import("std");
const host = @import("host");
const beef = @import("beef");

/// Per-invocation context. Brain populates the inputs, invokes the
/// hostcall, then reads the outputs.
pub const Context = struct {
    /// Allocator used by `beef.verifyBeefSpv` for BEEF parsing /
    /// merkle-root computation. Caller-owned; freed when ctx is.
    allocator: std.mem.Allocator,
    /// Raw BEEF bytes from the intent cell payload.
    beef_bytes: []const u8,
    /// 32-byte txid (internal byte order — matches the SPV wire format).
    txid: [32]u8,
    /// Trusted block-merkle roots from the brain's headers tracker.
    /// Each BUMP in the BEEF must terminate at one of these to count
    /// as verified.
    trusted_roots: []const [32]u8,

    /// Output — outcome enum matching `SpvVerifyOutcome` in
    /// `core/protocol-types/src/bsv/spv-verify.ts`.
    ///   0 = Invalid (BEEF parsed + txid present, but BUMP roots not trusted)
    ///   1 = Valid   (verified end-to-end against trusted roots)
    ///   2 = Error   (BEEF couldn't be parsed / txid absent / etc.)
    last_outcome: u8 = 0,
    /// Output — error_tag matching `SpvVerifyErrorTag`. 0 (None) when
    /// outcome != Error.
    last_error_tag: u8 = 0,
    /// Output — true iff last_outcome == Valid. Convenience for handler
    /// scripts that only care about the boolean.
    last_valid: bool = false,
    /// Internal — last hostcall return code, for debugging.
    last_return_code: u32 = 0,
};

// ── Outcome / error_tag values (match spv-verify.ts) ──────────────────

pub const OUTCOME_INVALID: u8 = 0;
pub const OUTCOME_VALID: u8 = 1;
pub const OUTCOME_ERROR: u8 = 2;

pub const ERROR_TAG_NONE: u8 = 0;
pub const ERROR_TAG_BEEF_PARSE_FAILED: u8 = 1;
pub const ERROR_TAG_TXID_ABSENT: u8 = 2;
pub const ERROR_TAG_ROOT_NOT_TRUSTED: u8 = 3;
pub const ERROR_TAG_BEEF_EMPTY: u8 = 4;
pub const ERROR_TAG_HOST_ERROR: u8 = 7;

// ── Return codes ──────────────────────────────────────────────────────

// ── Packed return code encoding (PR-7d) ───────────────────────────────
//
// The hostcall return code is a u32 packing (outcome, error_tag) so the
// handler script can read both values without a separate stack-push
// mechanism:
//
//     bits 0..7    : outcome     (OUTCOME_INVALID/VALID/ERROR)
//     bits 8..15   : error_tag   (ERROR_TAG_*)
//     bits 16..31  : reserved (must be 0)
//
// The script extracts via standard arithmetic:
//
//     OP_DUP                    # [rc, rc]
//     PUSH 256; OP_MOD          # [rc, outcome]
//     OP_SWAP                   # [outcome, rc]
//     PUSH 256; OP_DIV          # [outcome, error_tag]
//
// rc == 0 is unreachable in normal operation: the hostcall always sets
// outcome to a non-zero value when error_tag is None (Valid → outcome=1),
// and sets error_tag to a non-zero discriminant on the Invalid path
// (RootNotTrusted = 3). So a handler script can treat rc == 0 as a
// "registry sentinel returned without invoking us" trap (e.g. unknown
// host function 0xFFFFFFFF AFTER OP_AND-masked to fit the low bytes).
//
// PR-7d note: this REPLACES the pre-7d scalar rc {0..3} encoding.
// Handler scripts that haven't been re-assembled against the new
// encoding produce wrong verdicts. The PR ships the cell-engine
// hostcall + cartridge .cs source + manifest hex + scriptHash in
// lockstep so the brain's hash-check catches any straggler.

/// Pack `(outcome, error_tag)` into the u32 return code. Inline so the
/// callsites stay readable.
inline fn packRc(outcome: u8, error_tag: u8) u32 {
    return (@as(u32, error_tag) << 8) | @as(u32, outcome);
}

/// Registered handler. Delegates to `beef.verifyBeefSpv` and translates
/// the (bool, error-tag) result into Context output fields + packed rc.
pub fn handle(ctx_opaque: *anyopaque) callconv(.c) u32 {
    const ctx: *Context = @ptrCast(@alignCast(ctx_opaque));

    // Sanity-check inputs. Empty BEEF is a clear caller bug — handler
    // scripts should validate the wire-format length byte before
    // invoking us. Likewise an all-zero txid is invalid (sha256d of
    // anything is never identically zero).
    if (ctx.beef_bytes.len == 0) {
        ctx.last_outcome = OUTCOME_ERROR;
        ctx.last_error_tag = ERROR_TAG_BEEF_EMPTY;
        ctx.last_valid = false;
        const rc = packRc(OUTCOME_ERROR, ERROR_TAG_BEEF_EMPTY);
        ctx.last_return_code = rc;
        return rc;
    }

    const result = beef.verifyBeefSpv(
        ctx.allocator,
        ctx.beef_bytes,
        ctx.txid,
        ctx.trusted_roots,
    ) catch |err| {
        // Translate BeefError → (outcome, error_tag). The handler
        // script reads BOTH values from the packed rc.
        const error_tag: u8 = switch (err) {
            error.beef_parse_error => ERROR_TAG_BEEF_PARSE_FAILED,
            error.beef_txid_not_found => ERROR_TAG_TXID_ABSENT,
            error.beef_invalid_proof => ERROR_TAG_BEEF_PARSE_FAILED,
            error.bump_parse_error => ERROR_TAG_BEEF_PARSE_FAILED,
            error.bump_invalid_proof => ERROR_TAG_BEEF_PARSE_FAILED,
        };
        ctx.last_outcome = OUTCOME_ERROR;
        ctx.last_error_tag = error_tag;
        ctx.last_valid = false;
        const rc = packRc(OUTCOME_ERROR, error_tag);
        ctx.last_return_code = rc;
        return rc;
    };

    if (result) {
        ctx.last_outcome = OUTCOME_VALID;
        ctx.last_error_tag = ERROR_TAG_NONE;
        ctx.last_valid = true;
        const rc = packRc(OUTCOME_VALID, ERROR_TAG_NONE);
        ctx.last_return_code = rc;
        return rc;
    }

    // verifyBeefSpv returned false → BEEF was structurally valid + txid
    // was found, but none of the BUMP merkle roots matched a trusted
    // root. Outcome=Invalid (verification reached a verdict; the verdict
    // was no), error_tag=RootNotTrusted (the discriminant tells callers
    // exactly which kind of "no" this was).
    ctx.last_outcome = OUTCOME_INVALID;
    ctx.last_error_tag = ERROR_TAG_ROOT_NOT_TRUSTED;
    ctx.last_valid = false;
    const rc = packRc(OUTCOME_INVALID, ERROR_TAG_ROOT_NOT_TRUSTED);
    ctx.last_return_code = rc;
    return rc;
}

// ── Convenience accessors for callers that want named rc values ──────
//
// Tests + audit log readers can decode a packed rc back into (outcome,
// error_tag) without re-implementing the bit math.

pub inline fn outcomeOf(rc: u32) u8 {
    return @intCast(rc & 0xFF);
}

pub inline fn errorTagOf(rc: u32) u8 {
    return @intCast((rc >> 8) & 0xFF);
}

// Compile-time named-rc constants for the four canonical outcomes.
// These supersede the pre-7d RC_OK/RC_INVALID/RC_ERROR/RC_INVALID_INPUT
// scalars; callers that compared against those values should switch to
// these (or to outcomeOf/errorTagOf accessors).

pub const RC_VALID: u32 = (@as(u32, ERROR_TAG_NONE) << 8) | OUTCOME_VALID;
pub const RC_INVALID_ROOT_NOT_TRUSTED: u32 =
    (@as(u32, ERROR_TAG_ROOT_NOT_TRUSTED) << 8) | OUTCOME_INVALID;
pub const RC_ERROR_BEEF_EMPTY: u32 =
    (@as(u32, ERROR_TAG_BEEF_EMPTY) << 8) | OUTCOME_ERROR;
pub const RC_ERROR_BEEF_PARSE_FAILED: u32 =
    (@as(u32, ERROR_TAG_BEEF_PARSE_FAILED) << 8) | OUTCOME_ERROR;
pub const RC_ERROR_TXID_ABSENT: u32 =
    (@as(u32, ERROR_TAG_TXID_ABSENT) << 8) | OUTCOME_ERROR;

/// Register `host_verify_beef_spv` with the cell-engine host registry.
/// Brain calls this once at boot.
pub fn register() !void {
    try host.registerHostCall("host_verify_beef_spv", handle);
}

// ── Inline tests ──────────────────────────────────────────────────────

const testing = std.testing;

test "register: idempotent failure on duplicate" {
    host.resetRegistryForTest();
    try register();
    try testing.expectError(error.duplicate_registration, register());
    try testing.expectEqual(@as(usize, 1), host.registryCountForTest());
}

test "handle: empty beef → packed rc carries (Error, BeefEmpty)" {
    host.resetRegistryForTest();
    try register();

    var ctx: Context = .{
        .allocator = testing.allocator,
        .beef_bytes = &[_]u8{},
        .txid = [_]u8{0xAA} ** 32,
        .trusted_roots = &[_][32]u8{},
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_verify_beef_spv");
    try testing.expectEqual(RC_ERROR_BEEF_EMPTY, rc);
    // The packed accessor decode matches the Context output fields —
    // both paths are valid for callers (Zig-side uses Context; script-
    // side uses the packed rc).
    try testing.expectEqual(OUTCOME_ERROR, outcomeOf(rc));
    try testing.expectEqual(ERROR_TAG_BEEF_EMPTY, errorTagOf(rc));
    try testing.expectEqual(OUTCOME_ERROR, ctx.last_outcome);
    try testing.expectEqual(ERROR_TAG_BEEF_EMPTY, ctx.last_error_tag);
    try testing.expect(!ctx.last_valid);
}

test "handle: malformed BEEF → packed rc carries (Error, BeefParseFailed)" {
    host.resetRegistryForTest();
    try register();

    // 8 random bytes — definitely not a valid BEEF envelope.
    var ctx: Context = .{
        .allocator = testing.allocator,
        .beef_bytes = &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE },
        .txid = [_]u8{0x11} ** 32,
        .trusted_roots = &[_][32]u8{},
    };
    host.setExecutionContext(@ptrCast(&ctx));
    defer host.setExecutionContext(null);

    const rc = host.callByName("host_verify_beef_spv");
    try testing.expectEqual(RC_ERROR_BEEF_PARSE_FAILED, rc);
    try testing.expectEqual(OUTCOME_ERROR, outcomeOf(rc));
    try testing.expectEqual(ERROR_TAG_BEEF_PARSE_FAILED, errorTagOf(rc));
    try testing.expectEqual(OUTCOME_ERROR, ctx.last_outcome);
    try testing.expectEqual(ERROR_TAG_BEEF_PARSE_FAILED, ctx.last_error_tag);
    try testing.expect(!ctx.last_valid);
}

test "handle: unknown name → 0xFFFFFFFF sentinel (negative test)" {
    host.resetRegistryForTest();
    try register();

    const rc = host.callByName("host_definitely_not_registered");
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), rc);
}

test "handle: no execution context → 0xFFFFFFFE sentinel" {
    host.resetRegistryForTest();
    try register();
    // No setExecutionContext call before invocation.
    const rc = host.callByName("host_verify_beef_spv");
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), rc);
}

test "PR-7d packed rc: outcomeOf + errorTagOf round-trip every named constant" {
    // Each named RC_* constant decodes back to the (outcome, error_tag)
    // pair it was constructed from. Catches any drift in the packing
    // helper or the accessor functions.
    try testing.expectEqual(OUTCOME_VALID, outcomeOf(RC_VALID));
    try testing.expectEqual(ERROR_TAG_NONE, errorTagOf(RC_VALID));

    try testing.expectEqual(OUTCOME_INVALID, outcomeOf(RC_INVALID_ROOT_NOT_TRUSTED));
    try testing.expectEqual(ERROR_TAG_ROOT_NOT_TRUSTED, errorTagOf(RC_INVALID_ROOT_NOT_TRUSTED));

    try testing.expectEqual(OUTCOME_ERROR, outcomeOf(RC_ERROR_BEEF_EMPTY));
    try testing.expectEqual(ERROR_TAG_BEEF_EMPTY, errorTagOf(RC_ERROR_BEEF_EMPTY));

    try testing.expectEqual(OUTCOME_ERROR, outcomeOf(RC_ERROR_BEEF_PARSE_FAILED));
    try testing.expectEqual(ERROR_TAG_BEEF_PARSE_FAILED, errorTagOf(RC_ERROR_BEEF_PARSE_FAILED));

    try testing.expectEqual(OUTCOME_ERROR, outcomeOf(RC_ERROR_TXID_ABSENT));
    try testing.expectEqual(ERROR_TAG_TXID_ABSENT, errorTagOf(RC_ERROR_TXID_ABSENT));
}

test "PR-7d packed rc: zero is unreachable in normal hostcall output" {
    // RC_VALID = 0x0001 (outcome=Valid=1, tag=None=0): lowest non-zero
    // rc. Every other branch sets either outcome>=1 or tag>=1 explicitly,
    // so the packed result is always non-zero. Scripts treating rc==0
    // as a "registry sentinel" trap don't false-trigger.
    try testing.expect(RC_VALID != 0);
    try testing.expect(RC_INVALID_ROOT_NOT_TRUSTED != 0);
    try testing.expect(RC_ERROR_BEEF_EMPTY != 0);
    try testing.expect(RC_ERROR_BEEF_PARSE_FAILED != 0);
    try testing.expect(RC_ERROR_TXID_ABSENT != 0);
}

test "PR-7d packed rc: reserved high bits are zero" {
    // High 16 bits MUST be zero — leaves room for future expansion
    // (e.g., a "verifier version" byte) without breaking the script-
    // side DIV/MOD extraction.
    try testing.expectEqual(@as(u32, 0), RC_VALID & 0xFFFF0000);
    try testing.expectEqual(@as(u32, 0), RC_INVALID_ROOT_NOT_TRUSTED & 0xFFFF0000);
    try testing.expectEqual(@as(u32, 0), RC_ERROR_BEEF_EMPTY & 0xFFFF0000);
    try testing.expectEqual(@as(u32, 0), RC_ERROR_BEEF_PARSE_FAILED & 0xFFFF0000);
    try testing.expectEqual(@as(u32, 0), RC_ERROR_TXID_ABSENT & 0xFFFF0000);
}

test "outcome / error_tag constants match SpvVerifyOutcome+ErrorTag wire values" {
    // The Context output fields are intended for the handler script to
    // copy directly into the SpvVerifyResult payload bytes. If these
    // constants drift from the wire enum in
    // `core/protocol-types/src/bsv/spv-verify.ts`, the result cell will
    // be silently misencoded.
    try testing.expectEqual(@as(u8, 0), OUTCOME_INVALID);
    try testing.expectEqual(@as(u8, 1), OUTCOME_VALID);
    try testing.expectEqual(@as(u8, 2), OUTCOME_ERROR);
    try testing.expectEqual(@as(u8, 0), ERROR_TAG_NONE);
    try testing.expectEqual(@as(u8, 1), ERROR_TAG_BEEF_PARSE_FAILED);
    try testing.expectEqual(@as(u8, 2), ERROR_TAG_TXID_ABSENT);
    try testing.expectEqual(@as(u8, 3), ERROR_TAG_ROOT_NOT_TRUSTED);
    try testing.expectEqual(@as(u8, 4), ERROR_TAG_BEEF_EMPTY);
    try testing.expectEqual(@as(u8, 7), ERROR_TAG_HOST_ERROR);
}

```
