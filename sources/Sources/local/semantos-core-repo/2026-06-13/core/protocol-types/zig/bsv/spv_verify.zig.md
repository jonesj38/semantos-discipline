---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/zig/bsv/spv_verify.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.926839+00:00
---

# core/protocol-types/zig/bsv/spv_verify.zig

```zig
// C11 PR-C11-7e-2f — Zig mirror of
// `core/protocol-types/src/bsv/spv-verify.ts`.
//
// Wire format for `bsv.spv.verify.intent` and `bsv.spv.verify.result`
// cell payloads. Used by:
//
//   - The follow-on script-handler dispatcher (cell-engine bytecode
//     handler keyed by typeHash) — reads invocation intent, encodes
//     emitted result.
//
//   - Conformance tests + Zig-side consumers (audit tooling,
//     brain inspection) that need to read/write the same wire form
//     the TS encoder/decoder produces.
//
// Byte-identical with the TS implementation. Any drift between the
// two is a wire-protocol bug.
//
// Spec: `docs/design/LINEAR-CELL-SPV-STATE.md` §3.2 (host call ABI),
//       §2.2 (operation intent / result types).
//
// Build-time concerns:
//   - Compiles for both host-native (audit tooling, tests) and
//     wasm32-freestanding (the script-handler embed). No std.os,
//     no allocator-required paths.
//   - `RESULT_TYPE_HASH` is computed at comptime via the same
//     buildTypeHash construction the cartridge registry uses.

const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

// ─────────────────────────────────────────────────────────────────────
// Wire constants — byte-identical with the TS file.
// ─────────────────────────────────────────────────────────────────────

/// Wire-format version for both intent and result.
pub const SPV_VERIFY_WIRE_VERSION: u8 = 1;

/// Length of an intent's fixed-layout prefix, in bytes.
pub const SPV_VERIFY_INTENT_PREFIX_BYTES: usize = 36;

/// Length of the result payload, in bytes (fixed).
pub const SPV_VERIFY_RESULT_BYTES: usize = 35;

/// Upper bound on inline-BEEF size for `encodeSpvVerifyIntent`. See
/// the TS file's commentary for the derivation of 920 from the 1024-
/// byte cell budget + 62-byte CellHeader + 36-byte intent prefix.
pub const INLINE_BEEF_MAX_BYTES: u16 = 920;

/// FLAGS bit positions in the intent payload.
pub const SpvVerifyIntentFlag = struct {
    /// bit 0 — when set, the BEEF is inline in the payload after the prefix.
    pub const inline_beef: u8 = 1 << 0;
};

/// Result OUTCOME byte values.
pub const SpvVerifyOutcome = enum(u8) {
    invalid = 0,
    valid = 1,
    err = 2,
};

/// Result error_tag values. Coarse-grained on the wire; detailed
/// diagnostics live in the cell-engine + broker audit log.
pub const SpvVerifyErrorTag = enum(u8) {
    /// No error (OUTCOME != error).
    none = 0,
    /// BEEF bytes were not parseable.
    beef_parse_failed = 1,
    /// BEEF parsed but `txid` was not present in any of its transactions.
    txid_absent = 2,
    /// BUMP merkle path resolved to a root that is not in the trusted set.
    root_not_trusted = 3,
    /// Empty BEEF buffer.
    beef_empty = 4,
    /// Inline BEEF length exceeded `INLINE_BEEF_MAX_BYTES`.
    beef_too_large = 5,
    /// Reserved for the carriage-chain reference case (PR-C11-7e-3).
    carriage_ref_unsupported = 6,
    /// Catch-all for broker / host failures.
    host_error = 7,
};

// ─────────────────────────────────────────────────────────────────────
// typeHash construction — comptime-friendly mirror of
// `core/cell-engine/src/type_hash.zig::buildTypeHash`.
//
// Copied (not imported) so the codec module compiles for wasm32-
// freestanding targets without dragging in the cell-engine's host-
// only dependencies. Any change to the upstream construction MUST
// land here in lockstep — the comptime RESULT_TYPE_HASH value is
// load-bearing for substrate type-matching.
// ─────────────────────────────────────────────────────────────────────

pub const TYPE_HASH_SIZE: usize = 32;
pub const TYPE_HASH_SEGMENT_BYTES: usize = 8;

/// Compute the canonical typeHash for a 4-segment identity tuple.
/// First 8 bytes of SHA-256(segment_i) concatenated into a 32-byte
/// result. Same construction the brain's cartridge_cell_registry
/// uses at boot to key cellType entries.
pub fn buildTypeHash(
    s1: []const u8,
    s2: []const u8,
    s3: []const u8,
    s4: []const u8,
) [TYPE_HASH_SIZE]u8 {
    var out: [TYPE_HASH_SIZE]u8 = undefined;
    var tmp: [TYPE_HASH_SIZE]u8 = undefined;

    Sha256.hash(s1, &tmp, .{});
    @memcpy(out[0..TYPE_HASH_SEGMENT_BYTES], tmp[0..TYPE_HASH_SEGMENT_BYTES]);
    Sha256.hash(s2, &tmp, .{});
    @memcpy(
        out[TYPE_HASH_SEGMENT_BYTES .. 2 * TYPE_HASH_SEGMENT_BYTES],
        tmp[0..TYPE_HASH_SEGMENT_BYTES],
    );
    Sha256.hash(s3, &tmp, .{});
    @memcpy(
        out[2 * TYPE_HASH_SEGMENT_BYTES .. 3 * TYPE_HASH_SEGMENT_BYTES],
        tmp[0..TYPE_HASH_SEGMENT_BYTES],
    );
    Sha256.hash(s4, &tmp, .{});
    @memcpy(
        out[3 * TYPE_HASH_SEGMENT_BYTES .. 4 * TYPE_HASH_SEGMENT_BYTES],
        tmp[0..TYPE_HASH_SEGMENT_BYTES],
    );
    return out;
}

/// typeHash of `bsv.spv.verify.intent` — what the cartridge registry
/// keys the intent cellType under. The handler reads invocation cells
/// of this type.
pub const INTENT_TYPE_HASH: [TYPE_HASH_SIZE]u8 = blk: {
    @setEvalBranchQuota(20000);
    break :blk buildTypeHash("bsv", "spv", "verify", "intent");
};

/// typeHash of `bsv.spv.verify.result` — what the handler stamps
/// into every emitted result cell.
pub const RESULT_TYPE_HASH: [TYPE_HASH_SIZE]u8 = blk: {
    @setEvalBranchQuota(20000);
    break :blk buildTypeHash("bsv", "spv", "verify", "result");
};

// ─────────────────────────────────────────────────────────────────────
// Decoded shapes.
// ─────────────────────────────────────────────────────────────────────

pub const SpvVerifyIntent = struct {
    /// 32-byte txid (internal byte order).
    txid: [32]u8,
    /// Inline BEEF bytes (borrows from caller's buffer — same lifetime).
    beef: []const u8,
};

pub const SpvVerifyResult = struct {
    outcome: SpvVerifyOutcome,
    /// Echoed txid from the intent — for correlation.
    txid: [32]u8,
    /// `none` when `outcome != err`.
    error_tag: SpvVerifyErrorTag,
};

// ─────────────────────────────────────────────────────────────────────
// Errors.
// ─────────────────────────────────────────────────────────────────────

pub const CodecError = error{
    /// Intent payload too short for the 36-byte prefix.
    intent_truncated,
    /// Intent VERSION byte didn't match SPV_VERIFY_WIRE_VERSION.
    intent_bad_version,
    /// Intent FLAGS didn't have inline_beef bit set. Only the inline
    /// form is supported in 7e-2f; carriage-chain lands in 7e-3.
    intent_carriage_ref_unsupported,
    /// Intent declared a beef_len > INLINE_BEEF_MAX_BYTES.
    intent_beef_too_large,
    /// Intent payload truncated — declared beef_len longer than
    /// remaining buffer.
    intent_beef_truncated,
    /// Caller passed a result-encode buffer of the wrong size.
    bad_result_buffer_size,
    /// Caller passed an intent-encode buffer of the wrong size for
    /// the declared beef length.
    bad_intent_buffer_size,
    /// Result payload too short for the 35-byte layout.
    result_truncated,
    /// Result VERSION byte didn't match.
    result_bad_version,
    /// Result OUTCOME byte not in the SpvVerifyOutcome range.
    result_bad_outcome,
    /// Result error_tag byte not in the SpvVerifyErrorTag range.
    result_bad_error_tag,
};

// ─────────────────────────────────────────────────────────────────────
// Encoders.
// ─────────────────────────────────────────────────────────────────────

/// Encode an SPV verify intent payload into the caller-provided
/// `out` buffer. `out.len` MUST equal
/// `SPV_VERIFY_INTENT_PREFIX_BYTES + beef.len`. Caller-provided
/// buffer avoids any allocator dependency — required for wasm-
/// freestanding script-handler targets.
pub fn encodeIntent(
    out: []u8,
    txid: [32]u8,
    beef: []const u8,
) CodecError!void {
    if (beef.len > INLINE_BEEF_MAX_BYTES) return error.intent_beef_too_large;
    const expected = SPV_VERIFY_INTENT_PREFIX_BYTES + beef.len;
    if (out.len != expected) return error.bad_intent_buffer_size;

    out[0] = SPV_VERIFY_WIRE_VERSION;
    @memcpy(out[1..33], &txid);
    out[33] = SpvVerifyIntentFlag.inline_beef;
    // beef_len as u16 LE
    const beef_len_u16: u16 = @intCast(beef.len);
    out[34] = @intCast(beef_len_u16 & 0xff);
    out[35] = @intCast((beef_len_u16 >> 8) & 0xff);
    if (beef.len > 0) {
        @memcpy(out[SPV_VERIFY_INTENT_PREFIX_BYTES..expected], beef);
    }
}

/// Encode an SPV verify result payload into the caller-provided
/// `out` buffer. `out.len` MUST equal `SPV_VERIFY_RESULT_BYTES`.
pub fn encodeResult(out: []u8, result: SpvVerifyResult) CodecError!void {
    if (out.len != SPV_VERIFY_RESULT_BYTES) return error.bad_result_buffer_size;
    out[0] = SPV_VERIFY_WIRE_VERSION;
    out[1] = @intFromEnum(result.outcome);
    @memcpy(out[2..34], &result.txid);
    out[34] = @intFromEnum(result.error_tag);
}

// ─────────────────────────────────────────────────────────────────────
// Decoders.
// ─────────────────────────────────────────────────────────────────────

/// Decode an SPV verify intent payload. The returned `beef` borrows
/// from `payload` — same lifetime constraint as the TS slice-copy
/// pattern (modulo the explicit copy).
pub fn decodeIntent(payload: []const u8) CodecError!SpvVerifyIntent {
    if (payload.len < SPV_VERIFY_INTENT_PREFIX_BYTES) return error.intent_truncated;
    if (payload[0] != SPV_VERIFY_WIRE_VERSION) return error.intent_bad_version;

    const flags = payload[33];
    if ((flags & SpvVerifyIntentFlag.inline_beef) == 0) {
        return error.intent_carriage_ref_unsupported;
    }

    const beef_len: u16 = @as(u16, payload[34]) | (@as(u16, payload[35]) << 8);
    if (beef_len > INLINE_BEEF_MAX_BYTES) return error.intent_beef_too_large;

    const expected_len = SPV_VERIFY_INTENT_PREFIX_BYTES + @as(usize, beef_len);
    if (payload.len < expected_len) return error.intent_beef_truncated;

    var out: SpvVerifyIntent = .{
        .txid = undefined,
        .beef = payload[SPV_VERIFY_INTENT_PREFIX_BYTES..expected_len],
    };
    @memcpy(&out.txid, payload[1..33]);
    return out;
}

/// Decode an SPV verify result payload (35 bytes).
pub fn decodeResult(payload: []const u8) CodecError!SpvVerifyResult {
    if (payload.len < SPV_VERIFY_RESULT_BYTES) return error.result_truncated;
    if (payload[0] != SPV_VERIFY_WIRE_VERSION) return error.result_bad_version;

    const outcome_byte = payload[1];
    const outcome: SpvVerifyOutcome = switch (outcome_byte) {
        0 => .invalid,
        1 => .valid,
        2 => .err,
        else => return error.result_bad_outcome,
    };

    const tag_byte = payload[34];
    const error_tag: SpvVerifyErrorTag = switch (tag_byte) {
        0 => .none,
        1 => .beef_parse_failed,
        2 => .txid_absent,
        3 => .root_not_trusted,
        4 => .beef_empty,
        5 => .beef_too_large,
        6 => .carriage_ref_unsupported,
        7 => .host_error,
        else => return error.result_bad_error_tag,
    };

    var out: SpvVerifyResult = .{
        .outcome = outcome,
        .txid = undefined,
        .error_tag = error_tag,
    };
    @memcpy(&out.txid, payload[2..34]);
    return out;
}

// ─────────────────────────────────────────────────────────────────────
// Tests.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "encodeIntent + decodeIntent round-trip (empty BEEF)" {
    var txid: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) txid[i] = @intCast(i);

    var buf: [SPV_VERIFY_INTENT_PREFIX_BYTES]u8 = undefined;
    try encodeIntent(&buf, txid, &.{});

    const decoded = try decodeIntent(&buf);
    try testing.expectEqualSlices(u8, &txid, &decoded.txid);
    try testing.expectEqual(@as(usize, 0), decoded.beef.len);
}

test "encodeIntent + decodeIntent round-trip (small BEEF)" {
    var txid: [32]u8 = undefined;
    @memset(&txid, 0xaa);
    const beef = [_]u8{ 0xde, 0xad, 0xbe, 0xef, 0x12, 0x34 };

    var buf: [SPV_VERIFY_INTENT_PREFIX_BYTES + 6]u8 = undefined;
    try encodeIntent(&buf, txid, &beef);

    const decoded = try decodeIntent(&buf);
    try testing.expectEqualSlices(u8, &txid, &decoded.txid);
    try testing.expectEqualSlices(u8, &beef, decoded.beef);
}

test "encodeIntent refuses BEEF > INLINE_BEEF_MAX_BYTES" {
    var txid: [32]u8 = undefined;
    @memset(&txid, 0);
    const big = [_]u8{0} ** (INLINE_BEEF_MAX_BYTES + 1);

    var buf: [SPV_VERIFY_INTENT_PREFIX_BYTES + INLINE_BEEF_MAX_BYTES + 1]u8 = undefined;
    try testing.expectError(error.intent_beef_too_large, encodeIntent(&buf, txid, &big));
}

test "decodeIntent rejects bad version" {
    var buf: [SPV_VERIFY_INTENT_PREFIX_BYTES]u8 = [_]u8{0} ** SPV_VERIFY_INTENT_PREFIX_BYTES;
    buf[0] = 99; // wrong version
    buf[33] = SpvVerifyIntentFlag.inline_beef;
    try testing.expectError(error.intent_bad_version, decodeIntent(&buf));
}

test "decodeIntent rejects carriage-ref form (FLAGS bit 0 not set)" {
    var buf: [SPV_VERIFY_INTENT_PREFIX_BYTES]u8 = [_]u8{0} ** SPV_VERIFY_INTENT_PREFIX_BYTES;
    buf[0] = SPV_VERIFY_WIRE_VERSION;
    buf[33] = 0; // inline_beef bit absent
    try testing.expectError(error.intent_carriage_ref_unsupported, decodeIntent(&buf));
}

test "decodeIntent rejects beef_len truncation" {
    var buf: [SPV_VERIFY_INTENT_PREFIX_BYTES]u8 = [_]u8{0} ** SPV_VERIFY_INTENT_PREFIX_BYTES;
    buf[0] = SPV_VERIFY_WIRE_VERSION;
    buf[33] = SpvVerifyIntentFlag.inline_beef;
    buf[34] = 100; // declared beef_len = 100 but buffer only has 0 BEEF bytes
    buf[35] = 0;
    try testing.expectError(error.intent_beef_truncated, decodeIntent(&buf));
}

test "encodeResult + decodeResult round-trip (valid outcome)" {
    var txid: [32]u8 = undefined;
    @memset(&txid, 0x77);
    const orig: SpvVerifyResult = .{
        .outcome = .valid,
        .txid = txid,
        .error_tag = .none,
    };
    var buf: [SPV_VERIFY_RESULT_BYTES]u8 = undefined;
    try encodeResult(&buf, orig);

    const decoded = try decodeResult(&buf);
    try testing.expectEqual(SpvVerifyOutcome.valid, decoded.outcome);
    try testing.expectEqualSlices(u8, &txid, &decoded.txid);
    try testing.expectEqual(SpvVerifyErrorTag.none, decoded.error_tag);
}

test "encodeResult + decodeResult round-trip (error outcome)" {
    var txid: [32]u8 = undefined;
    @memset(&txid, 0x33);
    const orig: SpvVerifyResult = .{
        .outcome = .err,
        .txid = txid,
        .error_tag = .beef_parse_failed,
    };
    var buf: [SPV_VERIFY_RESULT_BYTES]u8 = undefined;
    try encodeResult(&buf, orig);

    const decoded = try decodeResult(&buf);
    try testing.expectEqual(SpvVerifyOutcome.err, decoded.outcome);
    try testing.expectEqual(SpvVerifyErrorTag.beef_parse_failed, decoded.error_tag);
}

test "decodeResult rejects unknown outcome byte" {
    var buf: [SPV_VERIFY_RESULT_BYTES]u8 = [_]u8{0} ** SPV_VERIFY_RESULT_BYTES;
    buf[0] = SPV_VERIFY_WIRE_VERSION;
    buf[1] = 99; // unknown outcome
    try testing.expectError(error.result_bad_outcome, decodeResult(&buf));
}

test "decodeResult rejects unknown error_tag byte" {
    var buf: [SPV_VERIFY_RESULT_BYTES]u8 = [_]u8{0} ** SPV_VERIFY_RESULT_BYTES;
    buf[0] = SPV_VERIFY_WIRE_VERSION;
    buf[1] = 1; // valid outcome
    buf[34] = 99; // unknown error_tag
    try testing.expectError(error.result_bad_error_tag, decodeResult(&buf));
}

test "RESULT_TYPE_HASH matches runtime buildTypeHash" {
    const runtime = buildTypeHash("bsv", "spv", "verify", "result");
    try testing.expectEqualSlices(u8, &runtime, &RESULT_TYPE_HASH);
}

test "INTENT_TYPE_HASH matches runtime buildTypeHash" {
    const runtime = buildTypeHash("bsv", "spv", "verify", "intent");
    try testing.expectEqualSlices(u8, &runtime, &INTENT_TYPE_HASH);
}

```
