---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/zig/betterment_cell_specs.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.565306+00:00
---

# cartridges/betterment/brain/zig/betterment_cell_specs.zig

```zig
// betterment cell-type identity registry — Zig comptime mirror of
// `cartridges/betterment/cartridge.json` `cellTypes[]` (the canonical
// source).
//
// Spec:    docs/design/EXTENSIONS-REFACTOR-CANDIDATES.md (T6, the `self` proposal — historical name)
// Tracker: docs/STRUCTURED-TYPEHASH-TRACKER.md (T6)
//
// RENAME (2026-05-29): cartridge was `self` with cell-type prefix `self.*`
// and namespace bytes `06c604b332b386b6`. Renamed to `betterment` with
// prefix `betterment.*` and namespace bytes `06d0a049e88a982b` so the
// word "self" is free for the shell-level identity primitive. All 23
// type hashes recomputed; v0.1.0 was test data only (no on-chain
// migration required).
//
// The `betterment` cartridge consolidates Todd's personal practice +
// Paskian narrative substrate for self-development. Pask stays kernel-
// side (core/pask/); this cartridge declares the cell SHAPES pask
// reads (practice + accountability inputs) and emits (paskian.graph +
// story outputs) when reducing over personal data.
//
// Mirrors `cartridges/mnca/brain/mnca_cell_specs.zig` pattern (SQ4 —
// Zig comptime spec with parity test against manifest). Identity
// comptime; pask hot-path kernel-side.
//
// Parity contract: this file's TRIPLES MUST agree with cartridge.json's
// cellTypes[].triple values byte-for-byte. The parity test asserts
// both produce identical hex.

const std = @import("std");
const type_hash = @import("type_hash");

pub const BettermentCellSpec = struct {
    name: []const u8,
    s1: []const u8,
    s2: []const u8,
    s3: []const u8,
    s4: []const u8,
    type_hash: [type_hash.TYPE_HASH_SIZE]u8,
};

fn spec(
    comptime name: []const u8,
    comptime s1: []const u8,
    comptime s2: []const u8,
    comptime s3: []const u8,
    comptime s4: []const u8,
) BettermentCellSpec {
    return BettermentCellSpec{
        .name = name,
        .s1 = s1,
        .s2 = s2,
        .s3 = s3,
        .s4 = s4,
        .type_hash = type_hash.buildTypeHash(s1, s2, s3, s4),
    };
}

/// All 23 cellTypes for the `betterment` cartridge.
/// Bytes 0:8 of every type_hash here are `06d0a049e88a982b` =
/// sha256("betterment")[0:8]. A PWA subscriber to "everything from
/// the personal-development substrate" does an 8-byte memcmp on
/// bytes 30:38 of any inbound cell.
///
/// Sub-namespace prefixes (bytes 8:16):
///   paskian       = 23a58f8728c6cf6f
///   story         = c478361e6869af25
///   practice      = ada750e3f8464e9e
///   accountability= 03939fbeaa4a9d85
///   state         = 4ba69735ca53765e
pub const ALL = blk: {
    @setEvalBranchQuota(500_000);
    break :blk [_]BettermentCellSpec{
        // Paskian substrate (4) — pask kernel emits these; PWA renders.
        spec("betterment.paskian.graph.node",       "betterment", "paskian",        "graph",      "node"),
        spec("betterment.paskian.graph.edge",       "betterment", "paskian",        "graph",      "edge"),
        spec("betterment.paskian.graph.stabilised", "betterment", "paskian",        "graph",      "stabilised"),
        spec("betterment.paskian.graph.pruned",     "betterment", "paskian",        "graph",      "pruned"),

        // Narrative arcs (5) — story-shaped reads over the Paskian substrate.
        spec("betterment.story.thread",             "betterment", "story",          "thread",     ""),
        spec("betterment.story.artifact",           "betterment", "story",          "artifact",   ""),
        spec("betterment.story.entity",             "betterment", "story",          "entity",     ""),
        spec("betterment.story.relation",           "betterment", "story",          "relation",   ""),
        spec("betterment.story.moment",             "betterment", "story",          "moment",     ""),

        // Personal practice (8) — release/integrate/seal cycle. PWA primary surface (SQ3).
        spec("betterment.practice.release",         "betterment", "practice",       "release",    ""),
        spec("betterment.practice.session",         "betterment", "practice",       "session",    ""),
        spec("betterment.practice.intention",       "betterment", "practice",       "intention",  ""),
        spec("betterment.practice.insight",         "betterment", "practice",       "insight",    ""),
        spec("betterment.practice.pattern",         "betterment", "practice",       "pattern",    ""),
        spec("betterment.practice.connection",      "betterment", "practice",       "connection", ""),
        spec("betterment.practice.vacuum",          "betterment", "practice",       "vacuum",     ""),
        spec("betterment.practice.seal",            "betterment", "practice",       "seal",       ""),

        // Daily-cadence accountability (4) — morning/review/pulse/streak loop.
        spec("betterment.accountability.morning",   "betterment", "accountability", "morning",    ""),
        spec("betterment.accountability.review",    "betterment", "accountability", "review",     ""),
        spec("betterment.accountability.pulse",     "betterment", "accountability", "pulse",      ""),
        spec("betterment.accountability.streak",    "betterment", "accountability", "streak",     ""),

        // Derived state (2) — rolling current-state cells.
        spec("betterment.state.dimension",          "betterment", "state",          "dimension",  ""),
        spec("betterment.state.elevation",          "betterment", "state",          "elevation",  ""),
    };
};

pub fn specByName(name: []const u8) ?BettermentCellSpec {
    for (ALL) |s| {
        if (std.mem.eql(u8, s.name, name)) return s;
    }
    return null;
}

// ── Parity contract: manifest hex pinned here ─────────────────────────────────
//
// MUST match `cartridges/betterment/cartridge.json` cellTypes[] after
// `buildTypeHash` is applied. Recomputed 2026-05-29 via Node sha256
// for the betterment rename (segment1 changed `self` → `betterment`,
// so bytes 0:8 changed; segments 2/3/4 unchanged so bytes 8:32 match
// the historical values).
// If you change a triple in either file, regenerate both sides.

const ExpectedHex = struct {
    name: []const u8,
    hex: *const [64]u8,
};

const EXPECTED: [23]ExpectedHex = .{
    .{ .name = "betterment.paskian.graph.node",       .hex = "06d0a049e88a982b23a58f8728c6cf6feef93e1d14482804545ea538461003ef" },
    .{ .name = "betterment.paskian.graph.edge",       .hex = "06d0a049e88a982b23a58f8728c6cf6feef93e1d14482804a1cb100f57e971ca" },
    .{ .name = "betterment.paskian.graph.stabilised", .hex = "06d0a049e88a982b23a58f8728c6cf6feef93e1d14482804b4532fa0c29ca555" },
    .{ .name = "betterment.paskian.graph.pruned",     .hex = "06d0a049e88a982b23a58f8728c6cf6feef93e1d144828040fedead8d392392e" },
    .{ .name = "betterment.story.thread",             .hex = "06d0a049e88a982bc478361e6869af2539200d1e8a8dbbb6e3b0c44298fc1c14" },
    .{ .name = "betterment.story.artifact",           .hex = "06d0a049e88a982bc478361e6869af25c7c5c1d70c5dec44e3b0c44298fc1c14" },
    .{ .name = "betterment.story.entity",             .hex = "06d0a049e88a982bc478361e6869af25bca3685fea8acd4ee3b0c44298fc1c14" },
    .{ .name = "betterment.story.relation",           .hex = "06d0a049e88a982bc478361e6869af25fc8fbb48a3a16bfde3b0c44298fc1c14" },
    .{ .name = "betterment.story.moment",             .hex = "06d0a049e88a982bc478361e6869af2572110207b6499adbe3b0c44298fc1c14" },
    .{ .name = "betterment.practice.release",         .hex = "06d0a049e88a982bada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14" },
    .{ .name = "betterment.practice.session",         .hex = "06d0a049e88a982bada750e3f8464e9e3f3af1ecebbd1410e3b0c44298fc1c14" },
    .{ .name = "betterment.practice.intention",       .hex = "06d0a049e88a982bada750e3f8464e9e74a11fdc7152e492e3b0c44298fc1c14" },
    .{ .name = "betterment.practice.insight",         .hex = "06d0a049e88a982bada750e3f8464e9ee43ba08557cbb4f1e3b0c44298fc1c14" },
    .{ .name = "betterment.practice.pattern",         .hex = "06d0a049e88a982bada750e3f8464e9e1fd38d5cbd2a997be3b0c44298fc1c14" },
    .{ .name = "betterment.practice.connection",      .hex = "06d0a049e88a982bada750e3f8464e9eb38d9d168c3aedf1e3b0c44298fc1c14" },
    .{ .name = "betterment.practice.vacuum",          .hex = "06d0a049e88a982bada750e3f8464e9e657fdc2b228b14a6e3b0c44298fc1c14" },
    .{ .name = "betterment.practice.seal",            .hex = "06d0a049e88a982bada750e3f8464e9ef0f668bf610e5cf9e3b0c44298fc1c14" },
    .{ .name = "betterment.accountability.morning",   .hex = "06d0a049e88a982b03939fbeaa4a9d85c23b31a0179b550fe3b0c44298fc1c14" },
    .{ .name = "betterment.accountability.review",    .hex = "06d0a049e88a982b03939fbeaa4a9d85c97ace4c8fef2ceee3b0c44298fc1c14" },
    .{ .name = "betterment.accountability.pulse",     .hex = "06d0a049e88a982b03939fbeaa4a9d8541b589ea15f2d94ae3b0c44298fc1c14" },
    .{ .name = "betterment.accountability.streak",    .hex = "06d0a049e88a982b03939fbeaa4a9d853fbf0de21a976c03e3b0c44298fc1c14" },
    .{ .name = "betterment.state.dimension",          .hex = "06d0a049e88a982b4ba69735ca53765e48eb632fe16ae195e3b0c44298fc1c14" },
    .{ .name = "betterment.state.elevation",          .hex = "06d0a049e88a982b4ba69735ca53765ebcaee9d9573aa21ae3b0c44298fc1c14" },
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
                "betterment parity drift for {s}\n  expected: {s}\n  actual:   {s}\n",
                .{ s.name, e.hex, &actual_hex },
            );
            return error.BettermentParityMismatch;
        }
    }
}

test "namespace prefix — all betterment.* cells share bytes 0:8" {
    const betterment_prefix = ALL[0].type_hash[0..8];
    for (ALL) |s| {
        try std.testing.expectEqualSlices(u8, betterment_prefix, s.type_hash[0..8]);
    }
}

test "sub-namespace prefix — all paskian.graph.* share bytes 0:24" {
    var graph_prefix: ?[24]u8 = null;
    for (ALL) |s| {
        if (std.mem.eql(u8, s.s2, "paskian") and std.mem.eql(u8, s.s3, "graph")) {
            if (graph_prefix) |prev| {
                try std.testing.expectEqualSlices(u8, &prev, s.type_hash[0..24]);
            } else {
                var p: [24]u8 = undefined;
                @memcpy(&p, s.type_hash[0..24]);
                graph_prefix = p;
            }
        }
    }
    try std.testing.expect(graph_prefix != null);
}

test "sub-namespace prefix — all practice.* share bytes 0:16" {
    var practice_prefix: ?[16]u8 = null;
    var count: usize = 0;
    for (ALL) |s| {
        if (std.mem.eql(u8, s.s2, "practice")) {
            count += 1;
            if (practice_prefix) |prev| {
                try std.testing.expectEqualSlices(u8, &prev, s.type_hash[0..16]);
            } else {
                var p: [16]u8 = undefined;
                @memcpy(&p, s.type_hash[0..16]);
                practice_prefix = p;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 8), count);
}

test "specByName finds each declared name" {
    for (ALL) |s| {
        const found = specByName(s.name);
        try std.testing.expect(found != null);
        try std.testing.expectEqualSlices(u8, &s.type_hash, &found.?.type_hash);
    }
}

test "specByName returns null for unknown" {
    try std.testing.expectEqual(@as(?BettermentCellSpec, null), specByName("betterment.unknown"));
}

test "23 cellTypes total" {
    try std.testing.expectEqual(@as(usize, 23), ALL.len);
}

```
