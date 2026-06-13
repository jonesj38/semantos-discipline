---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/brain/chess_cells.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.424708+00:00
---

# cartridges/chess/brain/chess_cells.zig

```zig
// chess_cells — cell-type definitions for the chess doubling-cube
// cartridge, tied in lockstep to the real cell-engine kernel.
//
// Reference:
//   docs/design/CHESS-DOUBLING-CUBE.md §3 (object model)
//   docs/CHESS-DOUBLING-CUBE-TRACKING.md §1 Phase 1
//   core/cell-engine/src/linearity.zig (the kernel LinearityType +
//     checkLinearity + header readers this file is validated against)
//   core/cell-engine/src/constants.zig (canonical header offsets)
//   cartridges/wallet-headers/brain/src/cell-anchor.ts (the per-type
//     sovereign domain-flag derivation this mirrors)
//
// What this is:
//
//   The §3 object model as concrete cell types. Each type carries the
//   linearity class the design assigns it, and a header builder whose
//   byte layout is the SAME one the kernel's linearity.getLinearity /
//   getDomainFlag / getTypeHash readers expect — the tests below prove
//   that round-trip against the real kernel functions, not a copy.
//
//   Phase 1 mints no cells (no money). This file exists so the design's
//   linearity choices are machine-checked now: the marquee test proves
//   that `chess.pending_double.v1` being LINEAR means the kernel itself
//   forbids dropping it — i.e. "don't accept ⇒ you forfeit" is enforced
//   by the type system, not by cartridge branching. Phase 2's
//   anchor/consume wiring builds on exactly these headers.

const std = @import("std");
const linearity = @import("linearity");
const constants = @import("constants");

pub const Linearity = linearity.LinearityType;

pub const CellType = struct {
    /// Stable type name. The type-hash is SHA-256 of this string.
    name: []const u8,
    /// Linearity class per design §3.
    lin: Linearity,
};

// ── The six chess cell types (design §3 table) ───────────────────────

/// The game record: players, clock config, FEN pointer, status.
/// RELEVANT — retained, freely referenced, never an authority token.
pub const GAME = CellType{ .name = "chess.game.v1", .lin = .relevant };

/// One ply. DAG-linked (parent = prior position hash). RELEVANT — the
/// immutable move history chessgammon never had.
pub const MOVE = CellType{ .name = "chess.move.v1", .lin = .relevant };

/// A player's base escrow. LINEAR — consumed exactly once into payout
/// or refund; cannot be duplicated (pot paid twice) or dropped (stake
/// vanishes).
pub const STAKE = CellType{ .name = "chess.stake.v1", .lin = .linear };

/// Incremental cover posted when a double is accepted (or an all-in
/// marker). LINEAR — pot integrity across escalations.
pub const STAKE_AUGMENT = CellType{ .name = "chess.stake_augment.v1", .lin = .linear };

/// The doubling cube. LINEAR — exactly one in existence; bound to its
/// owner via the header owner-id.
pub const CUBE = CellType{ .name = "chess.cube.v1", .lin = .linear };

/// The unanswered-offer obligation, directed at the responder. LINEAR
/// — this is the forfeit mechanic: it MUST be consumed exactly once,
/// and the only game-continuing consumption is accept; decline/timeout
/// consume it into the offerer-wins resolution. It cannot be dropped
/// (ignored) or duplicated (game forked).
pub const PENDING_DOUBLE = CellType{ .name = "chess.pending_double.v1", .lin = .linear };

pub const ALL = [_]CellType{ GAME, MOVE, STAKE, STAKE_AUGMENT, CUBE, PENDING_DOUBLE };

// ── Derivations ──────────────────────────────────────────────────────

pub fn typeHash(t: CellType) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(t.name, &out, .{});
    return out;
}

/// Per-type sovereign domain flag, mirroring cell-anchor.ts:
///   0x00010000 | (h[0]<<16) | (h[1]<<8) | h[2]
/// Always lands in the sovereign tier (>= 0x10000), so each chess
/// cell-type's anchors are cryptographically isolated.
pub fn domainFlag(t: CellType) u32 {
    const h = typeHash(t);
    return 0x00010000 | (@as(u32, h[0]) << 16) | (@as(u32, h[1]) << 8) | @as(u32, h[2]);
}

/// Build a minimal 256-byte cell header for `t` bound to `owner_id`,
/// using the EXACT offsets the kernel readers use. (Payload is the
/// caller's concern; Phase 1 builds headers only.)
pub fn buildHeader(t: CellType, owner_id: [16]u8) [constants.HEADER_SIZE]u8 {
    var hdr = [_]u8{0} ** constants.HEADER_SIZE;
    // Magic (offset 0, 16 bytes = 4 × u32 LE).
    std.mem.writeInt(u32, hdr[0..4], constants.MAGIC_1, .little);
    std.mem.writeInt(u32, hdr[4..8], constants.MAGIC_2, .little);
    std.mem.writeInt(u32, hdr[8..12], constants.MAGIC_3, .little);
    std.mem.writeInt(u32, hdr[12..16], constants.MAGIC_4, .little);
    // Linearity (offset 16, u32 LE).
    const lo = constants.HEADER_OFFSET_LINEARITY;
    std.mem.writeInt(u32, hdr[lo..][0..4], @intFromEnum(t.lin), .little);
    // Domain flag (offset 24, u32 LE).
    const fo = constants.HEADER_OFFSET_FLAGS;
    std.mem.writeInt(u32, hdr[fo..][0..4], domainFlag(t), .little);
    // Type hash (offset 30, 32 bytes).
    const to = constants.HEADER_OFFSET_TYPE_HASH;
    hdr[to..][0..32].* = typeHash(t);
    // Owner id (offset 62, 16 bytes).
    const oo = constants.HEADER_OFFSET_OWNER_ID;
    hdr[oo..][0..16].* = owner_id;
    return hdr;
}

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

test "design §3 linearity assignment" {
    try testing.expectEqual(Linearity.relevant, GAME.lin);
    try testing.expectEqual(Linearity.relevant, MOVE.lin);
    try testing.expectEqual(Linearity.linear, STAKE.lin);
    try testing.expectEqual(Linearity.linear, STAKE_AUGMENT.lin);
    try testing.expectEqual(Linearity.linear, CUBE.lin);
    try testing.expectEqual(Linearity.linear, PENDING_DOUBLE.lin);
}

test "MARQUEE: pending-double LINEAR ⇒ kernel forbids DROP and DUP (the forfeit guarantee)" {
    // The whole "don't accept ⇒ you forfeit" rule reduces to this: a
    // LINEAR cell cannot be discarded or duplicated, only consumed once
    // — verified against the REAL kernel checkLinearity, not a copy.
    try testing.expectEqual(Linearity.linear, PENDING_DOUBLE.lin);
    try testing.expectError(
        error.cannot_discard_linear,
        linearity.checkLinearity(PENDING_DOUBLE.lin, .discard),
    );
    try testing.expectError(
        error.cannot_duplicate_linear,
        linearity.checkLinearity(PENDING_DOUBLE.lin, .duplicate),
    );
    // accept / decline / timeout = exactly one consume — allowed.
    try linearity.checkLinearity(PENDING_DOUBLE.lin, .consume);
}

test "stake & cube LINEAR ⇒ no DUP/DROP; move/game RELEVANT ⇒ DUP ok, no DROP" {
    for ([_]CellType{ STAKE, STAKE_AUGMENT, CUBE }) |t| {
        try testing.expectError(error.cannot_duplicate_linear, linearity.checkLinearity(t.lin, .duplicate));
        try testing.expectError(error.cannot_discard_linear, linearity.checkLinearity(t.lin, .discard));
    }
    // RELEVANT history: may be referenced repeatedly, must be retained.
    try linearity.checkLinearity(MOVE.lin, .duplicate);
    try testing.expectError(error.cannot_discard_relevant, linearity.checkLinearity(MOVE.lin, .discard));
    try linearity.checkLinearity(GAME.lin, .duplicate);
    try testing.expectError(error.cannot_discard_relevant, linearity.checkLinearity(GAME.lin, .discard));
}

test "header byte layout round-trips through the real kernel readers" {
    const owner = [_]u8{0xAB} ** 16;
    const hdr = buildHeader(PENDING_DOUBLE, owner);
    // The kernel's own readers must agree with our writer.
    try testing.expectEqual(Linearity.linear, try linearity.getLinearity(&hdr));
    try testing.expectEqual(domainFlag(PENDING_DOUBLE), try linearity.getDomainFlag(&hdr));
    try testing.expectEqual(typeHash(PENDING_DOUBLE), try linearity.getTypeHash(&hdr));
    try testing.expectEqual(owner, try linearity.getOwnerId(&hdr));
}

test "domain flags are sovereign-tier and distinct per type" {
    var seen: [ALL.len]u32 = undefined;
    for (ALL, 0..) |t, i| {
        const f = domainFlag(t);
        try testing.expectEqual(linearity.FlagTier.sovereign, linearity.classifyFlag(f));
        for (seen[0..i]) |prev| try testing.expect(prev != f);
        seen[i] = f;
    }
}

```
