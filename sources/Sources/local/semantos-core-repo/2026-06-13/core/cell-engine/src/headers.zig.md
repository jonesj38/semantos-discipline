---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/headers.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.974389+00:00
---

# core/cell-engine/src/headers.zig

```zig
// Phase WH1 — Trustless SPV: pure-Zig BSV block-header parser + PoW verifier.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH1).
//
// Closes the wallet's last "trust an external indexer" dependency. Every
// 80-byte header the wallet ingests passes through this module and is
// validated against:
//   1. SHA256d(header) < target_from(bits)            — PoW
//   2. candidate.prev_hash == parent.computeHash()    — chain linkage
//   3. candidate.timestamp > median(prior 11 stamps)  — MTP rule
//   4. candidate.bits == ChainState.nextTarget(...)   — BSV cw-144 DAA
//
// All functions here are pure: no I/O, no allocations, no externs. Suitable
// for both the wasm32-freestanding browser bundle and native conformance
// tests. The header_store.zig vtable layers persistence on top.

const std = @import("std");

// ──────────────────────────────────────────────────────────────────────
// Constants
// ──────────────────────────────────────────────────────────────────────

/// Serialized header size (BSV consensus, identical to Bitcoin).
pub const HEADER_BYTES: usize = 80;

/// Target spacing between blocks (seconds). 10 minutes.
pub const TARGET_SPACING_SECS: u64 = 600;

/// cw-144 window size — number of blocks the DAA looks back over.
pub const DAA_WINDOW: u32 = 144;

/// cw-144 needs the "suitable block" three ancestors deep, so the
/// minimum-data window is 147 (height 0..146 inclusive).
pub const DAA_MIN_HEIGHT: u32 = 147;

/// MTP window — number of prior timestamps used to compute the
/// median-time-past gating value.
pub const MTP_WINDOW: usize = 11;

/// Genesis powLimit (mainnet): 0x1d00ffff → target = 0x00000000FFFF...0000.
pub const POW_LIMIT_BITS: u32 = 0x1d00ffff;

/// Test-only: regtest-style "easy" target — nearly the entire 256-bit space.
/// Used by conformance tests so synthetic chains can be mined in a handful of
/// nonce attempts. Real consensus rejects this on mainnet.
pub const REGTEST_BITS: u32 = 0x207fffff;

// ──────────────────────────────────────────────────────────────────────
// Errors
// ──────────────────────────────────────────────────────────────────────

pub const HeaderError = error{
    too_short,
    too_long,
    invalid_bits,
    insufficient_pow,
    prev_hash_mismatch,
    timestamp_too_early,
    timestamp_too_far_future,
    wrong_difficulty,
};

// ──────────────────────────────────────────────────────────────────────
// Header struct + serialization
// ──────────────────────────────────────────────────────────────────────

/// 80-byte BSV block header. All multi-byte fields are little-endian on the
/// wire. Hashes are stored in *internal byte order* — the same byte order
/// SHA256 produces. Display order ("hex string with leading zeros") is the
/// reverse.
pub const Header = struct {
    version: u32,
    prev_hash: [32]u8,
    merkle_root: [32]u8,
    timestamp: u32,
    bits: u32,
    nonce: u32,

    /// Decode a raw 80-byte header. Bytes are little-endian for ints.
    pub fn parseRaw(bytes: *const [HEADER_BYTES]u8) Header {
        return .{
            .version = std.mem.readInt(u32, bytes[0..4], .little),
            .prev_hash = bytes[4..36].*,
            .merkle_root = bytes[36..68].*,
            .timestamp = std.mem.readInt(u32, bytes[68..72], .little),
            .bits = std.mem.readInt(u32, bytes[72..76], .little),
            .nonce = std.mem.readInt(u32, bytes[76..80], .little),
        };
    }

    /// Decode from an arbitrary-length slice (must be exactly 80 bytes).
    pub fn parseSlice(bytes: []const u8) HeaderError!Header {
        if (bytes.len < HEADER_BYTES) return error.too_short;
        if (bytes.len > HEADER_BYTES) return error.too_long;
        return parseRaw(bytes[0..HEADER_BYTES]);
    }

    /// Encode the header into the canonical 80-byte wire form.
    pub fn serialize(self: *const Header, out: *[HEADER_BYTES]u8) void {
        std.mem.writeInt(u32, out[0..4], self.version, .little);
        @memcpy(out[4..36], &self.prev_hash);
        @memcpy(out[36..68], &self.merkle_root);
        std.mem.writeInt(u32, out[68..72], self.timestamp, .little);
        std.mem.writeInt(u32, out[72..76], self.bits, .little);
        std.mem.writeInt(u32, out[76..80], self.nonce, .little);
    }

    /// Block hash: SHA256(SHA256(serialized header)). Output is in internal
    /// byte order; reverse for display.
    pub fn computeHash(self: *const Header) [32]u8 {
        var buf: [HEADER_BYTES]u8 = undefined;
        self.serialize(&buf);
        return sha256d(&buf);
    }

    /// Decode `bits` to a 256-bit big-endian target. Reject malformed
    /// "negative" or "overflow" encodings per consensus rules.
    pub fn target(self: *const Header) HeaderError![32]u8 {
        return targetFromBits(self.bits);
    }

    /// `computeHash() < target(bits)` interpreted as a 256-bit unsigned
    /// big-endian integer. Returns false if `bits` is malformed.
    pub fn satisfiesProofOfWork(self: *const Header) bool {
        const t = self.target() catch return false;
        const h = self.computeHash();
        // Block hash is little-endian (SHA256 output) — compare against
        // big-endian target by reversing one or the other.
        var h_be: [32]u8 = undefined;
        for (0..32) |i| h_be[i] = h[31 - i];
        return cmp32(&h_be, &t) == .lt;
    }

    /// Approximate "work" = floor(2^256 / (target + 1)). Returns a u128 that
    /// is representative for cw-144 difficulty math (we cap at u128 since
    /// no real BSV chain gets close to 2^128).
    pub fn work(self: *const Header) u128 {
        const t = self.target() catch return 0;
        return targetToWork(&t);
    }
};

// ──────────────────────────────────────────────────────────────────────
// Compact "bits" encoding
// ──────────────────────────────────────────────────────────────────────

/// Decode a compact-bits field into a 256-bit big-endian target. The
/// encoding stores an exponent (1 byte) and a 24-bit mantissa.  Negative
/// (sign bit set) and overflow (mantissa shifted off the high end) are
/// rejected per BSV consensus.
pub fn targetFromBits(bits: u32) HeaderError![32]u8 {
    const exponent: u8 = @intCast((bits >> 24) & 0xff);
    const mantissa: u32 = bits & 0x007f_ffff;
    const negative: bool = (bits & 0x0080_0000) != 0;
    if (negative and mantissa != 0) return error.invalid_bits;

    var out = [_]u8{0} ** 32;

    if (mantissa == 0) {
        return out; // zero target — never satisfiable
    }

    if (exponent <= 3) {
        const shift: u5 = @intCast((3 - exponent) * 8);
        const small: u32 = mantissa >> shift;
        out[29] = @intCast((small >> 16) & 0xff);
        out[30] = @intCast((small >> 8) & 0xff);
        out[31] = @intCast(small & 0xff);
        return out;
    }

    // Place the 3-byte mantissa at offset (32 - exponent).
    if (exponent > 32) return error.invalid_bits;
    const start: usize = 32 - @as(usize, exponent);
    // overflow: any non-zero byte would be shifted past byte 0
    // (start < 0 once we account for the 3-byte mantissa width).
    if (start + 3 > 32) {
        // mantissa would overflow past byte 31 — reject.
        return error.invalid_bits;
    }
    out[start + 0] = @intCast((mantissa >> 16) & 0xff);
    out[start + 1] = @intCast((mantissa >> 8) & 0xff);
    out[start + 2] = @intCast(mantissa & 0xff);
    return out;
}

/// Encode a 256-bit big-endian target back into compact-bits form.
/// Inverse of targetFromBits modulo precision loss in the lowest bits.
pub fn bitsFromTarget(t: *const [32]u8) u32 {
    var first_nonzero: usize = 0;
    while (first_nonzero < 32 and t[first_nonzero] == 0) : (first_nonzero += 1) {}
    if (first_nonzero == 32) return 0;

    var exp: u8 = @intCast(32 - first_nonzero);
    const b0: u32 = if (first_nonzero + 0 < 32) t[first_nonzero + 0] else 0;
    const b1: u32 = if (first_nonzero + 1 < 32) t[first_nonzero + 1] else 0;
    const b2: u32 = if (first_nonzero + 2 < 32) t[first_nonzero + 2] else 0;

    var mantissa: u32 = (b0 << 16) | (b1 << 8) | b2;
    // If the high byte has the sign bit set, shift right one byte to keep
    // the encoding "unsigned".
    if ((mantissa & 0x0080_0000) != 0) {
        mantissa >>= 8;
        exp += 1;
    }
    return (@as(u32, exp) << 24) | (mantissa & 0x007f_ffff);
}

// ──────────────────────────────────────────────────────────────────────
// Hashing & big-int helpers
// ──────────────────────────────────────────────────────────────────────

/// Bitcoin's SHA256d.
pub fn sha256d(data: []const u8) [32]u8 {
    var first: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &first, .{});
    var second: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&first, &second, .{});
    return second;
}

/// 256-bit unsigned compare, both inputs big-endian.
pub fn cmp32(a: *const [32]u8, b: *const [32]u8) std.math.Order {
    for (0..32) |i| {
        if (a[i] < b[i]) return .lt;
        if (a[i] > b[i]) return .gt;
    }
    return .eq;
}

/// Approximate work = (2^128 - 1) / (target_high_64 + 1). Caps at u128
/// because real BSV targets sit well above 2^160 — capping the input avoids
/// a full bigint impl while keeping work-comparisons monotonic for cw-144.
pub fn targetToWork(t: *const [32]u8) u128 {
    // Take the top 16 bytes (most-significant 128 bits) of the target. If
    // they are all zero, the chain has more work than we can represent —
    // saturate to u128 max.
    var hi: u128 = 0;
    for (0..16) |i| {
        hi = (hi << 8) | @as(u128, t[i]);
    }
    if (hi == 0) return std.math.maxInt(u128);
    // work ≈ 2^128 / (hi + 1) using u256-emulated division through u128 std.
    const numerator: u256 = (@as(u256, 1) << 128);
    const denom: u256 = @as(u256, hi) + 1;
    const w: u256 = numerator / denom;
    return std.math.cast(u128, w) orelse std.math.maxInt(u128);
}

// ──────────────────────────────────────────────────────────────────────
// Median-time-past helper
// ──────────────────────────────────────────────────────────────────────

/// Median of up to 11 prior timestamps (BIP-113 / consensus MTP).
/// `prev_timestamps` should be the timestamps of the 11 (or fewer if early
/// in the chain) blocks immediately preceding the candidate, in any order.
pub fn medianTimePast(prev_timestamps: []const u32) u32 {
    if (prev_timestamps.len == 0) return 0;
    var buf: [MTP_WINDOW]u32 = undefined;
    const n = @min(prev_timestamps.len, MTP_WINDOW);
    @memcpy(buf[0..n], prev_timestamps[0..n]);
    std.sort.insertion(u32, buf[0..n], {}, std.sort.asc(u32));
    return buf[n / 2];
}

// ──────────────────────────────────────────────────────────────────────
// Chain validation
// ──────────────────────────────────────────────────────────────────────

/// All inputs the validator needs from prior chain context.  Caller assembles
/// these from a HeaderStore lookup.  The DAA-window slice is required only
/// when `parent_height + 1 >= DAA_MIN_HEIGHT`; before that height the network
/// runs at the genesis powLimit and the slice is ignored.
pub const ValidateInputs = struct {
    /// Direct parent of the candidate. candidate.prev_hash must equal
    /// parent.computeHash().
    parent: *const Header,

    /// Height of `parent` (so candidate height = parent_height + 1).
    parent_height: u32,

    /// Up to 11 prior timestamps for MTP calculation. Order doesn't matter.
    /// May include `parent.timestamp` itself.
    prev_timestamps: []const u32,

    /// The DAA "ring": at minimum the most recent DAA_WINDOW + 3 headers
    /// preceding the candidate (heights parent_height - 146 .. parent_height
    /// inclusive). Required only when candidate height ≥ DAA_MIN_HEIGHT.
    daa_window: []const Header = &.{},

    /// Optional clock cap (consensus rule: ≤ 2 hours into the future).
    /// Set to 0 to disable.
    now_seconds: u32 = 0,

    /// Bits value the verifier expects before the DAA kicks in. Mainnet uses
    /// POW_LIMIT_BITS; conformance tests pass REGTEST_BITS so synthetic
    /// chains are minable in microseconds. Mainnet callers leave this at the
    /// default.
    pow_limit_bits: u32 = POW_LIMIT_BITS,
};

/// Validate a candidate header against its parent and the chain state.
/// This is the single entry point that concentrates all consensus rules so
/// the lift to Lean (k14_pow_validity_preserved) has a small surface to
/// unfold over.
pub fn validateHeader(candidate: *const Header, inputs: *const ValidateInputs) HeaderError!void {
    // 1. Chain linkage: candidate.prev_hash == sha256d(parent.serialize())
    const parent_hash = inputs.parent.computeHash();
    if (!std.mem.eql(u8, &candidate.prev_hash, &parent_hash)) {
        return error.prev_hash_mismatch;
    }

    // 2. Difficulty (bits) — checked before PoW because (a) it doesn't need
    //    the SHA256d compute and (b) a mismatched-bits failure is a clearer
    //    diagnostic than a PoW failure caused by a tampered target.
    const expected_bits = nextRequiredBits(inputs.parent, inputs.parent_height, inputs.daa_window, inputs.pow_limit_bits) catch |e| return e;
    if (candidate.bits != expected_bits) return error.wrong_difficulty;

    // 3. PoW: sha256d(candidate.serialize()) < target_from(candidate.bits)
    if (!candidate.satisfiesProofOfWork()) {
        return error.insufficient_pow;
    }

    // 4. MTP: candidate.timestamp > median of last 11 timestamps.
    const mtp = medianTimePast(inputs.prev_timestamps);
    if (candidate.timestamp <= mtp) return error.timestamp_too_early;

    // 5. Optional clock cap (≤ 2 hours into future).
    if (inputs.now_seconds != 0) {
        const future_limit: u32 = inputs.now_seconds +% 2 * 60 * 60;
        if (candidate.timestamp > future_limit) {
            return error.timestamp_too_far_future;
        }
    }
}

// ──────────────────────────────────────────────────────────────────────
// BSV cw-144 difficulty adjustment (per-block)
// ──────────────────────────────────────────────────────────────────────

/// Returns the consensus `bits` field a candidate at height `parent_height + 1`
/// must carry. For early blocks (height < DAA_MIN_HEIGHT) the powLimit is
/// returned. After that, the cw-144 algorithm is applied:
///
///   first  := suitableBlock(parent_height - 144)
///   last   := suitableBlock(parent_height)
///   work   := sum_of_block_work(first..last)        // exclusive of `first`
///   work  *= TARGET_SPACING_SECS
///   span   := clamp(last.time - first.time, 72*600, 288*600)
///   target := (~work) / work                          // ≈ 2^256/work
///
/// `daa_window` must be a slice of `DAA_WINDOW + 3` consecutive headers
/// ending at `parent` (i.e. heights `parent_height - 146 .. parent_height`).
pub fn nextRequiredBits(parent: *const Header, parent_height: u32, daa_window: []const Header, pow_limit_bits: u32) HeaderError!u32 {
    if (parent_height + 1 < DAA_MIN_HEIGHT) return pow_limit_bits;

    const need: usize = DAA_WINDOW + 3;
    if (daa_window.len < need) return error.wrong_difficulty;
    // Slice should be the *last* `need` headers ending at `parent`.
    const slice = daa_window[daa_window.len - need ..];
    // Sanity check that `parent` is the last element.
    const last_header = &slice[slice.len - 1];
    const want_hash = last_header.computeHash();
    const have_hash = parent.computeHash();
    if (!std.mem.eql(u8, &want_hash, &have_hash)) return error.wrong_difficulty;

    // suitable block among (slice[0], slice[1], slice[2]) for "first"
    const first_idx = suitableIndex(slice, 0);
    // suitable block among the last three for "last"
    const last_idx = suitableIndex(slice, slice.len - 3);

    const first = &slice[first_idx];
    const last = &slice[last_idx];

    // Sum work between first (exclusive) and last (inclusive).
    var work_sum: u128 = 0;
    var i: usize = first_idx + 1;
    while (i <= last_idx) : (i += 1) {
        work_sum +|= slice[i].work();
    }
    if (work_sum == 0) return pow_limit_bits;

    // Compute timespan between first and last.
    var actual_span: i64 = @as(i64, @intCast(last.timestamp)) - @as(i64, @intCast(first.timestamp));
    const min_span: i64 = 72 * @as(i64, @intCast(TARGET_SPACING_SECS));
    const max_span: i64 = 288 * @as(i64, @intCast(TARGET_SPACING_SECS));
    if (actual_span < min_span) actual_span = min_span;
    if (actual_span > max_span) actual_span = max_span;

    const span_u: u128 = @intCast(actual_span);

    // projected_work = work_sum * 600 / actual_span
    const projected: u128 = (work_sum *| TARGET_SPACING_SECS) / span_u;
    if (projected == 0) return pow_limit_bits;

    // new_target = (2^256 - 1) / (projected + 1).
    const numerator: u256 = std.math.maxInt(u256);
    const new_t: u256 = numerator / (@as(u256, projected) + 1);

    var t_be: [32]u8 = undefined;
    var v: u256 = new_t;
    var bi: usize = 32;
    while (bi > 0) {
        bi -= 1;
        t_be[bi] = @intCast(v & 0xff);
        v >>= 8;
    }

    // Cap at powLimit.
    const limit = try targetFromBits(pow_limit_bits);
    const capped: [32]u8 = if (cmp32(&t_be, &limit) == .gt) limit else t_be;
    return bitsFromTarget(&capped);
}

/// Median-by-timestamp of slice[start..start+3]; returns the absolute index
/// (into the original slice) of that median.
fn suitableIndex(slice: []const Header, start: usize) usize {
    const a = start + 0;
    const b = start + 1;
    const c = start + 2;
    var idx = [_]usize{ a, b, c };
    if (slice[idx[0]].timestamp > slice[idx[1]].timestamp) std.mem.swap(usize, &idx[0], &idx[1]);
    if (slice[idx[0]].timestamp > slice[idx[2]].timestamp) std.mem.swap(usize, &idx[0], &idx[2]);
    if (slice[idx[1]].timestamp > slice[idx[2]].timestamp) std.mem.swap(usize, &idx[1], &idx[2]);
    return idx[1];
}

// ──────────────────────────────────────────────────────────────────────
// Inline tests
// ──────────────────────────────────────────────────────────────────────

test "parseRaw round-trips through serialize" {
    var bytes: [HEADER_BYTES]u8 = undefined;
    for (0..HEADER_BYTES) |i| bytes[i] = @intCast(i);
    const h = Header.parseRaw(&bytes);
    var back: [HEADER_BYTES]u8 = undefined;
    h.serialize(&back);
    try std.testing.expectEqualSlices(u8, &bytes, &back);
}

test "targetFromBits: powLimit (0x1d00ffff) decodes correctly" {
    const t = try targetFromBits(POW_LIMIT_BITS);
    // Expected: 0x00000000 FFFF0000 0000... (29 trailing zeros after FFFF)
    try std.testing.expectEqual(@as(u8, 0x00), t[0]);
    try std.testing.expectEqual(@as(u8, 0x00), t[1]);
    try std.testing.expectEqual(@as(u8, 0x00), t[2]);
    try std.testing.expectEqual(@as(u8, 0x00), t[3]);
    try std.testing.expectEqual(@as(u8, 0xff), t[4]);
    try std.testing.expectEqual(@as(u8, 0xff), t[5]);
    try std.testing.expectEqual(@as(u8, 0x00), t[6]);
    for (7..32) |i| try std.testing.expectEqual(@as(u8, 0x00), t[i]);
}

test "targetFromBits round-trips through bitsFromTarget" {
    const samples = [_]u32{ POW_LIMIT_BITS, 0x1c00ffff, 0x1b0404cb, 0x1900ffff };
    for (samples) |b| {
        const t = try targetFromBits(b);
        const back = bitsFromTarget(&t);
        try std.testing.expectEqual(b, back);
    }
}

test "targetFromBits: negative bit set is rejected" {
    try std.testing.expectError(error.invalid_bits, targetFromBits(0x1d80ffff));
}

test "Genesis block PoW satisfies its own bits" {
    // BSV/Bitcoin mainnet genesis header (well-known constants).
    var raw: [HEADER_BYTES]u8 = .{0} ** HEADER_BYTES;
    std.mem.writeInt(u32, raw[0..4], 1, .little);
    // prev_hash = 0
    // merkle_root: 4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b
    //   stored little-endian (internal byte order):
    const mr_be = [_]u8{
        0x4a, 0x5e, 0x1e, 0x4b, 0xaa, 0xb8, 0x9f, 0x3a,
        0x32, 0x51, 0x8a, 0x88, 0xc3, 0x1b, 0xc8, 0x7f,
        0x61, 0x8f, 0x76, 0x67, 0x3e, 0x2c, 0xc7, 0x7a,
        0xb2, 0x12, 0x7b, 0x7a, 0xfd, 0xed, 0xa3, 0x3b,
    };
    var mr_le: [32]u8 = undefined;
    for (0..32) |i| mr_le[i] = mr_be[31 - i];
    @memcpy(raw[36..68], &mr_le);
    std.mem.writeInt(u32, raw[68..72], 1231006505, .little);
    std.mem.writeInt(u32, raw[72..76], POW_LIMIT_BITS, .little);
    std.mem.writeInt(u32, raw[76..80], 2083236893, .little);

    const h = Header.parseRaw(&raw);
    try std.testing.expect(h.satisfiesProofOfWork());
}

test "validateHeader: prev-hash mismatch is rejected" {
    var parent = mkSyntheticHeader(0, 1_700_000_000, TEST_BITS);
    var child = mkSyntheticHeader(0, 1_700_000_600, TEST_BITS);
    // Deliberate corrupt prev_hash
    @memcpy(&child.prev_hash, &([_]u8{0xff} ** 32));
    minePoW(&child);

    const inputs = ValidateInputs{
        .parent = &parent,
        .parent_height = 0,
        .prev_timestamps = &.{parent.timestamp},
        .pow_limit_bits = TEST_BITS,
    };
    try std.testing.expectError(error.prev_hash_mismatch, validateHeader(&child, &inputs));
}

test "validateHeader: insufficient PoW is rejected" {
    // Parent uses POW_LIMIT_BITS so the bits-check passes for both. With
    // POW_LIMIT_BITS the probability of a random nonce satisfying PoW is
    // ~2^-32 — vanishingly unlikely for a few million attempts.
    var parent = mkSyntheticHeader(0, 1_700_000_000, POW_LIMIT_BITS);
    parent.merkle_root = [_]u8{0xab} ** 32;
    var child = mkSyntheticHeader(0, 1_700_000_600, POW_LIMIT_BITS);
    child.prev_hash = parent.computeHash();
    child.merkle_root = [_]u8{0xcd} ** 32;
    child.nonce = 0;

    const inputs = ValidateInputs{
        .parent = &parent,
        .parent_height = 0,
        .prev_timestamps = &.{parent.timestamp},
        .pow_limit_bits = POW_LIMIT_BITS,
    };
    // The probability of nonce=0 satisfying POW_LIMIT_BITS is ~2^-32 — for
    // these specific bytes we know it doesn't.
    try std.testing.expectError(error.insufficient_pow, validateHeader(&child, &inputs));
}

test "validateHeader: MTP rule rejects too-early timestamps" {
    var parent = mkSyntheticHeader(0, 1_700_000_500, TEST_BITS);
    minePoW(&parent);
    var child = mkSyntheticHeader(0, 1_700_000_400, TEST_BITS);
    child.prev_hash = parent.computeHash();
    minePoW(&child);

    // 11 timestamps all > child.timestamp → MTP > child.timestamp → reject.
    var prev_ts: [11]u32 = undefined;
    for (0..11) |i| prev_ts[i] = 1_700_000_500 + @as(u32, @intCast(i));

    const inputs = ValidateInputs{
        .parent = &parent,
        .parent_height = 0,
        .prev_timestamps = &prev_ts,
        .pow_limit_bits = TEST_BITS,
    };
    try std.testing.expectError(error.timestamp_too_early, validateHeader(&child, &inputs));
}

test "validateHeader: clock-cap rejects far-future stamps" {
    var parent = mkSyntheticHeader(0, 1_700_000_000, TEST_BITS);
    minePoW(&parent);
    var child = mkSyntheticHeader(0, 1_700_000_600 + (3 * 60 * 60), TEST_BITS);
    child.prev_hash = parent.computeHash();
    minePoW(&child);

    const inputs = ValidateInputs{
        .parent = &parent,
        .parent_height = 0,
        .prev_timestamps = &.{parent.timestamp},
        .now_seconds = 1_700_000_600,
        .pow_limit_bits = TEST_BITS,
    };
    try std.testing.expectError(error.timestamp_too_far_future, validateHeader(&child, &inputs));
}

test "medianTimePast: returns true median for 11 stamps" {
    const stamps = [_]u32{ 5, 1, 9, 2, 8, 3, 7, 4, 6, 10, 11 };
    try std.testing.expectEqual(@as(u32, 6), medianTimePast(&stamps));
}

test "medianTimePast: handles fewer than 11 stamps" {
    const stamps = [_]u32{ 100, 200, 300 };
    try std.testing.expectEqual(@as(u32, 200), medianTimePast(&stamps));
}

test "nextRequiredBits: pre-DAA height returns powLimit" {
    var parent = mkSyntheticHeader(0, 1_700_000_000, TEST_BITS);
    minePoW(&parent);
    const bits = try nextRequiredBits(&parent, 100, &.{}, POW_LIMIT_BITS);
    try std.testing.expectEqual(POW_LIMIT_BITS, bits);
}

// ── Test helpers ──

fn mkSyntheticHeader(prev_height: u32, timestamp: u32, bits: u32) Header {
    _ = prev_height;
    return .{
        .version = 1,
        .prev_hash = [_]u8{0} ** 32,
        .merkle_root = [_]u8{0} ** 32,
        .timestamp = timestamp,
        .bits = bits,
        .nonce = 0,
    };
}

const TEST_BITS: u32 = REGTEST_BITS;

/// Mine the header at the given (loose) target by sweeping the nonce.
/// Used only by tests; powLimit is so loose that nonce=0 usually works.
fn minePoW(h: *Header) void {
    var n: u32 = 0;
    while (n < 1_000_000) : (n += 1) {
        h.nonce = n;
        if (h.satisfiesProofOfWork()) return;
    }
    // If we couldn't find one, the test will see insufficient_pow — fine.
}

```
