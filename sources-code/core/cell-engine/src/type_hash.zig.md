---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/type_hash.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.973543+00:00
---

# core/cell-engine/src/type_hash.zig

```zig
// Canonical typeHash construction — kernel primitive.
//
// Owns the single function every cell-type identity in the system flows
// through: `buildTypeHash(s1, s2, s3, s4)`.  Type identities themselves
// live in cartridge manifests (cartridge.json `cellTypes[].triple`),
// not in this binary.  This module just provides the HOW; cartridges
// declare the WHAT at load time.
//
// Spec: docs/design/STRUCTURED-TYPEHASH-CANONICAL.md
// Tracker: docs/STRUCTURED-TYPEHASH-TRACKER.md
//
// Algorithm: structured |8|8|8|8| construction (T5.a, 2026-05-25)
//   typeHash[ 0: 8] = sha256(s1)[0:8]    namespace
//   typeHash[ 8:16] = sha256(s2)[0:8]    domain
//   typeHash[16:24] = sha256(s3)[0:8]    sub-type
//   typeHash[24:32] = sha256(s4)[0:8]    qualifier / version
//
// The 32 bytes ARE the four truncated inner hashes concatenated
// directly — NO outer hash wrapper (that would collapse the structure
// back to opaque and defeat the whole purpose).
//
// Routing wins enabled:
//   - Relays peek bytes 30:38 of a cell to filter by namespace prefix
//     in O(1) without resolving a path string (decision record §7.2).
//   - LMDB cellsByType becomes range-scannable by prefix (§7.1).
//   - SQL projection layers gain 4 indexed segment columns (§7.3).
//   - Raw 0x00 × 8 prefix is reserved as wildcard sentinel for
//     promiscuous fan-out compute (§2.2 / §7.4).
//
// Pre-T5.a history: the algorithm was flat
//   SHA256(s1 ++ ":" ++ s2 ++ ":" ++ s3 ++ ":" ++ s4)
// during T1-T4 migration.  The function signature stayed identical
// across the flip; callers don't move.  Wire-breaking change is
// isolated to T5.a by this design.
//
// TS mirror: core/protocol-types/src/type-hash.ts (parity-tested).

const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

/// Size of a canonical typeHash, in bytes.
pub const TYPE_HASH_SIZE: usize = 32;

/// Number of canonical segments in a typeHash construction.
pub const TYPE_HASH_SEGMENT_COUNT: usize = 4;

/// Width of a single segment's contribution under the structured (T5.a)
/// algorithm.  Unused in the flat phase but exported now so consumers
/// designing prefix-match logic can begin building against the final
/// constant.
pub const TYPE_HASH_SEGMENT_BYTES: usize = TYPE_HASH_SIZE / TYPE_HASH_SEGMENT_COUNT;

/// Reserved wildcard prefix sentinel.
///
/// A typeHash whose `bytes[0..8]` equal this constant signals
/// "no namespace owner — promiscuous routing, any subscriber may pick
/// this up."  Distinct from `sha256("")[0..8]` (which is a specific
/// deterministic constant produced by the empty-segment-1 case).
///
/// Wildcard mints are reserved for substrate cartridges by default; see
/// decision record §2.2 and Q5 in the tracker.
pub const WILDCARD_NAMESPACE_PREFIX: [TYPE_HASH_SEGMENT_BYTES]u8 =
    [_]u8{0x00} ** TYPE_HASH_SEGMENT_BYTES;

/// Compute the canonical typeHash for a 4-segment identity tuple
/// under the structured |8|8|8|8| construction (T5.a).
///
/// No allocator required — each segment is independently SHA-256'd and
/// the first 8 bytes of each digest are concatenated into the 32-byte
/// result.  Works at comptime and runtime with the same call (comptime
/// callers must bump `@setEvalBranchQuota` due to SHA-256's branch cost).
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

/// Extract the namespace prefix (bytes 0:8) — the routing-layer peek
/// window.  Relays compare this 8-byte slice to a subscribed namespace
/// hash to decide whether to forward a cell, without resolving the
/// full triple or reading the payload.
pub fn namespacePrefix(type_hash: [TYPE_HASH_SIZE]u8) [TYPE_HASH_SEGMENT_BYTES]u8 {
    var out: [TYPE_HASH_SEGMENT_BYTES]u8 = undefined;
    @memcpy(&out, type_hash[0..TYPE_HASH_SEGMENT_BYTES]);
    return out;
}

/// Return true when the first 8 bytes of `type_hash` equal the reserved
/// wildcard sentinel.  Trivial helper, but documents the routing-layer
/// peek pattern: relays compare these 8 bytes to decide promiscuous
/// fan-out membership without further inspection of the cell.
pub fn isWildcard(type_hash: [TYPE_HASH_SIZE]u8) bool {
    return std.mem.eql(u8, type_hash[0..TYPE_HASH_SEGMENT_BYTES], &WILDCARD_NAMESPACE_PREFIX);
}

// ── Parity vectors ────────────────────────────────────────────────────────────
//
// The same table is replicated byte-identically in
// `core/protocol-types/__tests__/type-hash-parity.test.ts`.
// If you change one, change the other; CI runs both to catch drift.
//
// Each row is `(segment1, segment2, segment3, segment4) → expected_hex_64`.
// Hashes are SHA-256 of `s1:s2:s3:s4`, generated by:
//
//   node -e 'const c = require("crypto");
//            console.log(c.createHash("sha256")
//                         .update(`${s1}:${s2}:${s3}:${s4}`, "utf-8")
//                         .digest("hex"))'

const ParityVector = struct {
    s1: []const u8,
    s2: []const u8,
    s3: []const u8,
    s4: []const u8,
    expected_hex: *const [64]u8,
};

const PARITY_VECTORS = [_]ParityVector{
    .{ .s1 = "", .s2 = "", .s3 = "", .s4 = "", .expected_hex = "e3b0c44298fc1c14e3b0c44298fc1c14e3b0c44298fc1c14e3b0c44298fc1c14" },
    .{ .s1 = "mnca", .s2 = "", .s3 = "", .s4 = "", .expected_hex = "09e9fe981010c9b4e3b0c44298fc1c14e3b0c44298fc1c14e3b0c44298fc1c14" },
    .{ .s1 = "mnca", .s2 = "snapshot", .s3 = "", .s4 = "", .expected_hex = "09e9fe981010c9b416a0eeb0791b6c92e3b0c44298fc1c14e3b0c44298fc1c14" },
    .{ .s1 = "mnca", .s2 = "tile", .s3 = "injection", .s4 = "", .expected_hex = "09e9fe981010c9b48b668b8994aa8451545a70019936cf88e3b0c44298fc1c14" },
    .{ .s1 = "mnca", .s2 = "tile", .s3 = "tick", .s4 = "", .expected_hex = "09e9fe981010c9b48b668b8994aa845155a4bc5be68ea5c3e3b0c44298fc1c14" },
    .{ .s1 = "mnca", .s2 = "tile", .s3 = "", .s4 = "v0", .expected_hex = "09e9fe981010c9b48b668b8994aa8451e3b0c44298fc1c140270da4daac514f3" },
    .{ .s1 = "mnca", .s2 = "standalone", .s3 = "tile", .s4 = "tick", .expected_hex = "09e9fe981010c9b45b565a33b80b75dc8b668b8994aa845155a4bc5be68ea5c3" },
    .{ .s1 = "oddjobz", .s2 = "job", .s3 = "worktrack", .s4 = "v1", .expected_hex = "c4cf2fd44009863e5e8c9902207afaeb822965fc3debc30d3bfc269594ef6492" },
    .{ .s1 = "oddjobz", .s2 = "job", .s3 = "worktrack", .s4 = "v2", .expected_hex = "c4cf2fd44009863e5e8c9902207afaeb822965fc3debc30dfb04dcb6970e4c3d" },
    .{ .s1 = "oddjobz", .s2 = "customer", .s3 = "identify", .s4 = "v2", .expected_hex = "c4cf2fd44009863eb6c45863875e34480f780b5c735e7025fb04dcb6970e4c3d" },
    .{ .s1 = "oddjobz", .s2 = "site", .s3 = "locate", .s4 = "v2", .expected_hex = "c4cf2fd44009863efbae041b02c41ed0c61d02ef654ab458fb04dcb6970e4c3d" },
    .{ .s1 = "oddjobz", .s2 = "attachment", .s3 = "capture", .s4 = "v2", .expected_hex = "c4cf2fd44009863e602a5e69c3021bdb460ee6aa3a803591fb04dcb6970e4c3d" },
    .{ .s1 = "oddjobz", .s2 = "mnca", .s3 = "tile", .s4 = "tick", .expected_hex = "c4cf2fd44009863e09e9fe981010c9b48b668b8994aa845155a4bc5be68ea5c3" },
    .{ .s1 = "nonprofit-os", .s2 = "fund", .s3 = "earmarked_balance", .s4 = "v1", .expected_hex = "52b2931aa02bb055639f78fb7729d09d187a3cbda417c6b43bfc269594ef6492" },
    .{ .s1 = "nonprofit-os", .s2 = "mnca", .s3 = "snapshot", .s4 = "v1", .expected_hex = "52b2931aa02bb05509e9fe981010c9b416a0eeb0791b6c923bfc269594ef6492" },
    .{ .s1 = "tessera", .s2 = "batch", .s3 = "mint", .s4 = "v1", .expected_hex = "2f1e83d30fff12f14bb24efc9641afc5dc6f17bbec824fff3bfc269594ef6492" },
    .{ .s1 = "chess", .s2 = "stake", .s3 = "", .s4 = "v1", .expected_hex = "ac739dccd121f712f4caf4ff95731a23e3b0c44298fc1c143bfc269594ef6492" },
    .{ .s1 = "semantos", .s2 = "test", .s3 = "linear-cell", .s4 = "", .expected_hex = "af70498e94f58c419f86d081884c7d6503f44d22268104d9e3b0c44298fc1c14" },
    .{ .s1 = "a", .s2 = "b", .s3 = "c", .s4 = "d", .expected_hex = "ca978112ca1bbdca3e23e8160039594a2e7d2c03a9507ae218ac3e7343f01689" },
    .{ .s1 = "café", .s2 = "naïve", .s3 = "日本", .s4 = "🦀", .expected_hex = "850f7dc43910ff89f86fd89de87a848acf2abf0c5be326cb7224c588fa988754" },
};

fn hexEncode(bytes: [TYPE_HASH_SIZE]u8) [64]u8 {
    const hex_chars = "0123456789abcdef";
    var out: [64]u8 = undefined;
    for (bytes, 0..) |b, i| {
        out[i * 2] = hex_chars[(b >> 4) & 0x0f];
        out[i * 2 + 1] = hex_chars[b & 0x0f];
    }
    return out;
}

test "parity vectors — flat SHA256 of joined segments" {
    for (PARITY_VECTORS) |v| {
        const actual = buildTypeHash(v.s1, v.s2, v.s3, v.s4);
        const actual_hex = hexEncode(actual);
        if (!std.mem.eql(u8, &actual_hex, v.expected_hex)) {
            std.debug.print(
                "parity mismatch for ({s},{s},{s},{s})\n  expected: {s}\n  actual:   {s}\n",
                .{ v.s1, v.s2, v.s3, v.s4, v.expected_hex, &actual_hex },
            );
            return error.ParityMismatch;
        }
    }
}

test "wildcard sentinel is 8 raw zero bytes" {
    try std.testing.expectEqual(@as(usize, 8), WILDCARD_NAMESPACE_PREFIX.len);
    for (WILDCARD_NAMESPACE_PREFIX) |b| {
        try std.testing.expectEqual(@as(u8, 0x00), b);
    }
}

test "wildcard sentinel is distinct from sha256(\"\")[0..8]" {
    // sha256("") = e3b0c44298fc1c14...
    // sha256("")[0..8] = e3 b0 c4 42 98 fc 1c 14
    // Wildcard       = 00 00 00 00 00 00 00 00
    var empty_hash: [32]u8 = undefined;
    Sha256.hash("", &empty_hash, .{});
    try std.testing.expect(!std.mem.eql(
        u8,
        empty_hash[0..TYPE_HASH_SEGMENT_BYTES],
        &WILDCARD_NAMESPACE_PREFIX,
    ));
}

test "isWildcard matches the sentinel prefix only" {
    var hash: [TYPE_HASH_SIZE]u8 = undefined;
    @memset(&hash, 0xAA);
    try std.testing.expect(!isWildcard(hash));

    @memset(hash[0..TYPE_HASH_SEGMENT_BYTES], 0x00);
    try std.testing.expect(isWildcard(hash));
}

test "buildTypeHash works at comptime" {
    // SHA-256 at comptime exceeds the default branch quota; bump it
    // for the duration of this comptime block.  Callers wanting to
    // bake a typeHash into kernel-side constants must do the same:
    //
    //   const MY_HASH = blk: {
    //       @setEvalBranchQuota(20_000);
    //       break :blk type_hash.buildTypeHash("a", "b", "c", "d");
    //   };
    @setEvalBranchQuota(20_000);
    const ct_hash = comptime buildTypeHash("oddjobz", "job", "worktrack", "v2");
    const rt_hash = buildTypeHash("oddjobz", "job", "worktrack", "v2");
    try std.testing.expectEqualSlices(u8, &ct_hash, &rt_hash);
}

test "TYPE_HASH_SEGMENT_BYTES matches T5.a design (32 / 4 = 8)" {
    try std.testing.expectEqual(@as(usize, 8), TYPE_HASH_SEGMENT_BYTES);
}

```
