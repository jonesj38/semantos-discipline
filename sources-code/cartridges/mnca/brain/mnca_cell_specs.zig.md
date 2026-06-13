---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/mnca/brain/mnca_cell_specs.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.681117+00:00
---

# cartridges/mnca/brain/mnca_cell_specs.zig

```zig
// MNCA cell-type identity registry — Zig comptime mirror of
// `cartridges/mnca/cartridge.json` `cellTypes[]` (the canonical source).
//
// Spec:    docs/design/STRUCTURED-TYPEHASH-CANONICAL.md (§4, D6/D7)
// Tracker: docs/STRUCTURED-TYPEHASH-TRACKER.md (T3.b, Q4=Option B, Q13=A)
//
// MNCA is a substrate-level cartridge.  The 5 cell types declared here
// are the STANDALONE-MNCA shape (segment2 = "standalone").  Domain-bound
// MNCA invocations (e.g. oddjobz running MNCA over Job data) mint cells
// with segment1 = "<domain>" — they don't need separate manifest entries
// because the typeHash is computed dynamically from the triple by the
// source-cartridge code path.
//
// Mirrors the same shape as `cartridges/tessera/brain/tessera_cell_specs.zig`
// — TRIPLES table at comptime, hashes computed via the kernel's
// `buildTypeHash` (`core/cell-engine/src/type_hash.zig`).
//
// Parity contract: this file's TRIPLES MUST agree with cartridge.json's
// cellTypes[].triple values byte-for-byte.  The parity test in this
// same file asserts both produce identical hex.

const std = @import("std");
const type_hash = @import("type_hash");

/// Static info for a single MNCA cell type, comptime-known.
pub const MncaCellSpec = struct {
    name: []const u8,
    s1: []const u8,
    s2: []const u8,
    s3: []const u8,
    s4: []const u8,
    /// Pre-computed typeHash from the structured |8|8|8|8| algorithm.
    /// Comptime-evaluated; baked into the kernel binary.  Set by
    /// `withTypeHash` below.
    type_hash: [type_hash.TYPE_HASH_SIZE]u8,
};

/// Helper to build a spec with the typeHash pre-computed at comptime.
/// Caller is responsible for the @setEvalBranchQuota bump.
fn spec(
    comptime name: []const u8,
    comptime s1: []const u8,
    comptime s2: []const u8,
    comptime s3: []const u8,
    comptime s4: []const u8,
) MncaCellSpec {
    return MncaCellSpec{
        .name = name,
        .s1 = s1,
        .s2 = s2,
        .s3 = s3,
        .s4 = s4,
        .type_hash = type_hash.buildTypeHash(s1, s2, s3, s4),
    };
}

/// All MNCA cell types, in declaration order.
///
/// The first 5 are standalone-MNCA (segment2 = "standalone") sharing
/// bytes 0:16 = `09e9fe981010c9b45b565a33b80b75dc` (= sha256("mnca")[0:8]
/// ++ sha256("standalone")[0:8]). A relay can prefix-match "all
/// standalone MNCA" with a 16-byte compare. The 3 tile-* entries
/// additionally share bytes 0:24.
///
/// The 4 added in PR-8 are anchor-state-machine entries (segment2 =
/// "anchor") sharing bytes 0:16 = `09e9fe981010c9b479bfb0e2ba76b9d4`
/// — a parallel routing prefix. The 2 transition-* entries share
/// bytes 0:24 (the "transition" segment3 prefix).
pub const ALL = blk: {
    @setEvalBranchQuota(400_000);
    break :blk [_]MncaCellSpec{
        spec("mnca.snapshot",       "mnca", "standalone", "snapshot", ""),
        spec("mnca.perturb",        "mnca", "standalone", "perturb",  ""),
        spec("mnca.tile.injection", "mnca", "standalone", "tile",     "injection"),
        spec("mnca.tile.tick",      "mnca", "standalone", "tile",     "tick"),
        // Renamed from `mnca.tile.v0` under D12 (no version suffixes).
        // Q13-A resolution: base-tile shape with operations in segment4.
        spec("mnca.tile",           "mnca", "standalone", "tile",     ""),
        // PR-8 / LOCKSCRIPT-CLEAVAGE.md §7.2 — on-chain anchor state machine.
        spec("mnca.anchor.create.intent",     "mnca", "anchor", "create",     "intent"),
        spec("mnca.anchor",                   "mnca", "anchor", "",           ""),
        spec("mnca.anchor.transition.intent", "mnca", "anchor", "transition", "intent"),
        spec("mnca.anchor.transition.result", "mnca", "anchor", "transition", "result"),
    };
};

/// Look up a spec by canonical name.  Comptime-friendly for callers
/// that know the name at compile time; linear-scan at runtime is fine
/// because ALL.len = 5.
pub fn specByName(name: []const u8) ?MncaCellSpec {
    for (ALL) |s| {
        if (std.mem.eql(u8, s.name, name)) return s;
    }
    return null;
}

// ── Parity contract: manifest hex pinned here ─────────────────────────────────
//
// The expected hex values below MUST match `cartridges/mnca/cartridge.json`
// cellTypes[] after `buildTypeHash` is applied to each triple.  Any drift
// between this file and the manifest triggers a test failure.  Computed
// 2026-05-25 via Node `crypto.createHash`:
//
//   for ([s1,s2,s3,s4] of triples) {
//     for (i, seg of [s1,s2,s3,s4])
//       out.set(sha256(seg).slice(0,8), i*8)
//   }
//
// If anyone changes a triple in either file, regenerate both sides
// from this Node snippet.

const ExpectedHex = struct {
    name: []const u8,
    hex: *const [64]u8,
};

const EXPECTED: [9]ExpectedHex = .{
    .{ .name = "mnca.snapshot",       .hex = "09e9fe981010c9b45b565a33b80b75dc16a0eeb0791b6c92e3b0c44298fc1c14" },
    .{ .name = "mnca.perturb",        .hex = "09e9fe981010c9b45b565a33b80b75dc9dab0a86a717bbbbe3b0c44298fc1c14" },
    .{ .name = "mnca.tile.injection", .hex = "09e9fe981010c9b45b565a33b80b75dc8b668b8994aa8451545a70019936cf88" },
    .{ .name = "mnca.tile.tick",      .hex = "09e9fe981010c9b45b565a33b80b75dc8b668b8994aa845155a4bc5be68ea5c3" },
    .{ .name = "mnca.tile",           .hex = "09e9fe981010c9b45b565a33b80b75dc8b668b8994aa8451e3b0c44298fc1c14" },
    // PR-8 anchor entries — computed 2026-06-01 via the same Node snippet.
    .{ .name = "mnca.anchor.create.intent",     .hex = "09e9fe981010c9b479bfb0e2ba76b9d4fa8847b0c3318327282bcbc3f0a34a8a" },
    .{ .name = "mnca.anchor",                   .hex = "09e9fe981010c9b479bfb0e2ba76b9d4e3b0c44298fc1c14e3b0c44298fc1c14" },
    .{ .name = "mnca.anchor.transition.intent", .hex = "09e9fe981010c9b479bfb0e2ba76b9d470dd37c11434d9c5282bcbc3f0a34a8a" },
    .{ .name = "mnca.anchor.transition.result", .hex = "09e9fe981010c9b479bfb0e2ba76b9d470dd37c11434d9c5f6a214f7a5fcda0c" },
};

fn hexEncode(bytes: [type_hash.TYPE_HASH_SIZE]u8) [64]u8 {
    const hex_chars = "0123456789abcdef";
    var out: [64]u8 = undefined;
    for (bytes, 0..) |b, i| {
        out[i * 2] = hex_chars[(b >> 4) & 0x0f];
        out[i * 2 + 1] = hex_chars[b & 0x0f];
    }
    return out;
}

test "manifest parity — every ALL[i].type_hash matches its EXPECTED hex" {
    try std.testing.expectEqual(@as(usize, EXPECTED.len), ALL.len);
    for (ALL, EXPECTED) |s, e| {
        try std.testing.expectEqualStrings(s.name, e.name);
        const actual_hex = hexEncode(s.type_hash);
        if (!std.mem.eql(u8, &actual_hex, e.hex)) {
            std.debug.print(
                "MNCA parity drift for {s}\n  expected: {s}\n  actual:   {s}\n",
                .{ s.name, e.hex, &actual_hex },
            );
            return error.MncaParityMismatch;
        }
    }
}

test "routing-prefix property — all standalone-MNCA cells share bytes 0:16" {
    // PR-8 added 4 anchor-MNCA entries (segment2 = "anchor") that share
    // a different 16-byte prefix. This test still covers the original
    // 5 standalone entries; the per-namespace property is asserted by
    // the test below.
    const ns_prefix = ALL[0].type_hash[0..16];
    for (ALL) |s| {
        if (std.mem.eql(u8, s.s2, "standalone")) {
            try std.testing.expectEqualSlices(u8, ns_prefix, s.type_hash[0..16]);
        }
    }
}

test "routing-prefix property — all anchor-MNCA cells share bytes 0:16 (PR-8)" {
    // The 4 PR-8 anchor entries have segment2 = "anchor" so they share
    // a 16-byte prefix distinct from the standalone shape — relays can
    // subscribe to "all MNCA anchor activity" with a 16-byte compare.
    var anchor_prefix: ?[16]u8 = null;
    for (ALL) |s| {
        if (std.mem.eql(u8, s.s2, "anchor")) {
            if (anchor_prefix) |prev| {
                try std.testing.expectEqualSlices(u8, &prev, s.type_hash[0..16]);
            } else {
                var p: [16]u8 = undefined;
                @memcpy(&p, s.type_hash[0..16]);
                anchor_prefix = p;
            }
        }
    }
    try std.testing.expect(anchor_prefix != null);
}

test "routing-prefix property — anchor transition.* cells share bytes 0:24 (PR-8)" {
    // The 2 transition.* entries share segment3 = "transition" so their
    // bytes 0:24 (s1 + s2 + s3 hashes) match. Subscription pattern:
    // "all MNCA anchor transitions" with a 24-byte compare.
    var trans_prefix: ?[24]u8 = null;
    for (ALL) |s| {
        if (std.mem.eql(u8, s.s2, "anchor") and std.mem.eql(u8, s.s3, "transition")) {
            if (trans_prefix) |prev| {
                try std.testing.expectEqualSlices(u8, &prev, s.type_hash[0..24]);
            } else {
                var p: [24]u8 = undefined;
                @memcpy(&p, s.type_hash[0..24]);
                trans_prefix = p;
            }
        }
    }
    try std.testing.expect(trans_prefix != null);
}

test "routing-prefix property — all tile.* cells share bytes 0:24" {
    // Find the 3 tile-* specs: tile.injection, tile.tick, mnca.tile
    var tile_prefix: ?[24]u8 = null;
    for (ALL) |s| {
        if (std.mem.eql(u8, s.s3, "tile")) {
            if (tile_prefix) |prev| {
                try std.testing.expectEqualSlices(u8, &prev, s.type_hash[0..24]);
            } else {
                var p: [24]u8 = undefined;
                @memcpy(&p, s.type_hash[0..24]);
                tile_prefix = p;
            }
        }
    }
    try std.testing.expect(tile_prefix != null);
}

test "specByName finds each declared name" {
    for (ALL) |s| {
        const found = specByName(s.name);
        try std.testing.expect(found != null);
        try std.testing.expectEqualSlices(u8, &s.type_hash, &found.?.type_hash);
    }
}

test "specByName returns null for unknown" {
    try std.testing.expectEqual(@as(?MncaCellSpec, null), specByName("mnca.unknown"));
}

```
