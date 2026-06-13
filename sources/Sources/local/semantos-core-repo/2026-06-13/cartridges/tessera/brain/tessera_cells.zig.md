---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/tessera_cells.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.633728+00:00
---

# cartridges/tessera/brain/tessera_cells.zig

```zig
// tessera_cells — cell-type definitions for the tessera care-chain
// provenance cartridge, tied in lockstep to the real cell-engine kernel.
//
// Reference:
//   docs/prd/TESSERA-CARTRIDGE.md §3.3 (cell types) + §0.1 (greenfield)
//   docs/canon/commissions/wave-tessera.md §8 (D-sub axis → V0.5)
//   cartridges/tessera/cartridge.json `cellTypes` (the canonical
//     declaration this file makes machine-checkable)
//   core/cell-engine/src/linearity.zig (the kernel LinearityType +
//     checkLinearity + header readers this file is validated against)
//   core/cell-engine/src/constants.zig (canonical header offsets)
//   cartridges/chess/brain/chess_cells.zig (the pattern this follows)
//
// What this is:
//
//   The §3.3 object model as concrete cell types. Each type carries the
//   linearity class the design assigns it, and a header builder whose
//   byte layout is the SAME one the kernel's linearity.getLinearity /
//   getDomainFlag / getTypeHash readers expect — the tests below prove
//   that round-trip against the real kernel functions, not a copy.
//
//   This is the V0.5 D-sub substrate evidence: the design's linearity
//   choices are machine-checked against the kernel now. The marquee
//   test proves `tessera.tamper-event` being LINEAR means the kernel
//   itself forbids dropping or duplicating it — the tamper-loop
//   one-shot guarantee (Lean: tessera.tamper_one_shot, V5.2) is
//   enforced by the type system, not by cartridge branching. Custody
//   linearity (V5.5), scan-evidence presence (V5.6), and the
//   accumulating care-event chain all reduce to these linearity
//   classes. Greenfield (§0.1): this file lives under cartridges/
//   tessera/, never runtime/semantos-brain/src/.

const std = @import("std");
const linearity = @import("linearity");
const constants = @import("constants");

pub const Linearity = linearity.LinearityType;

pub const CellType = struct {
    /// Stable type name. The type-hash is SHA-256 of this string.
    /// Matches cartridges/tessera/cartridge.json `cellTypes[].name`.
    name: []const u8,
    /// Linearity class per TESSERA-CARTRIDGE.md §3.3.
    lin: Linearity,
};

// ── The ten tessera cell types (cartridge.json `cellTypes`) ──────────

/// AFFINE origin cell — partial consumption into barrels; remainder
/// spendable. (no DUP; DROP allowed — a lot may be left unused.)
pub const GRAPE_LOT = CellType{ .name = "tessera.grape-lot", .lin = .affine };

/// LINEAR cell consumed entirely at bottling.
pub const BARREL = CellType{ .name = "tessera.barrel", .lin = .linear };

/// LINEAR cell; one tamper-break ends its open trajectory.
pub const BOTTLE = CellType{ .name = "tessera.bottle", .lin = .linear };

/// LINEAR cell assembled from N bottles via typed SemanticRelation.
pub const CASE = CellType{ .name = "tessera.case", .lin = .linear };

/// LINEAR cell; split into cases = a new pallet cell consuming the old.
pub const PALLET = CellType{ .name = "tessera.pallet", .lin = .linear };

/// LINEAR cell; closed once destination receives.
pub const SHIPMENT = CellType{ .name = "tessera.shipment", .lin = .linear };

/// AFFINE cell; logger readings accumulate against one shipment.
/// (no DUP — a reading is not forgeable by copy; DROP allowed — a
/// shipment may legitimately carry zero care events.)
pub const CARE_EVENT = CellType{ .name = "tessera.care-event", .lin = .affine };

/// RELEVANT cell; must exist for the Care Score view to render
/// (Lean: tessera.scan_evidence_present, V5.6). DUP ok, no DROP.
pub const SCAN_EVENT = CellType{ .name = "tessera.scan-event", .lin = .relevant };

/// LINEAR cell; single irreversible transition intact → broken. This
/// is the tamper-loop one-shot mechanic (Lean: tessera.tamper_one_shot,
/// V5.2): it MUST be consumed exactly once, cannot be dropped (ignored)
/// or duplicated (seal forged).
pub const TAMPER_EVENT = CellType{ .name = "tessera.tamper-event", .lin = .linear };

/// DEBUG cell; read-only, opaque to FSMs and capability flow.
pub const TASTING_NOTE = CellType{ .name = "tessera.tasting-note", .lin = .debug };

pub const ALL = [_]CellType{
    GRAPE_LOT, BARREL,     BOTTLE,       CASE,  PALLET,
    SHIPMENT,  CARE_EVENT, SCAN_EVENT,   TAMPER_EVENT, TASTING_NOTE,
};

// ── Derivations ──────────────────────────────────────────────────────

pub fn typeHash(t: CellType) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(t.name, &out, .{});
    return out;
}

/// Per-type sovereign domain flag, mirroring chess_cells.zig:
///   0x00010000 | (h[0]<<16) | (h[1]<<8) | h[2]
/// Always lands in the sovereign tier (>= 0x10000), so each tessera
/// cell-type's anchors are cryptographically isolated.
pub fn domainFlag(t: CellType) u32 {
    const h = typeHash(t);
    return 0x00010000 | (@as(u32, h[0]) << 16) | (@as(u32, h[1]) << 8) | @as(u32, h[2]);
}

/// Build a minimal 256-byte cell header for `t` bound to `owner_id`,
/// using the EXACT offsets the kernel readers use.
pub fn buildHeader(t: CellType, owner_id: [16]u8) [constants.HEADER_SIZE]u8 {
    var hdr = [_]u8{0} ** constants.HEADER_SIZE;
    std.mem.writeInt(u32, hdr[0..4], constants.MAGIC_1, .little);
    std.mem.writeInt(u32, hdr[4..8], constants.MAGIC_2, .little);
    std.mem.writeInt(u32, hdr[8..12], constants.MAGIC_3, .little);
    std.mem.writeInt(u32, hdr[12..16], constants.MAGIC_4, .little);
    const lo = constants.HEADER_OFFSET_LINEARITY;
    std.mem.writeInt(u32, hdr[lo..][0..4], @intFromEnum(t.lin), .little);
    const fo = constants.HEADER_OFFSET_FLAGS;
    std.mem.writeInt(u32, hdr[fo..][0..4], domainFlag(t), .little);
    const to = constants.HEADER_OFFSET_TYPE_HASH;
    hdr[to..][0..32].* = typeHash(t);
    const oo = constants.HEADER_OFFSET_OWNER_ID;
    hdr[oo..][0..16].* = owner_id;
    return hdr;
}

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

test "cartridge.json §3.3 linearity assignment" {
    try testing.expectEqual(Linearity.affine, GRAPE_LOT.lin);
    try testing.expectEqual(Linearity.linear, BARREL.lin);
    try testing.expectEqual(Linearity.linear, BOTTLE.lin);
    try testing.expectEqual(Linearity.linear, CASE.lin);
    try testing.expectEqual(Linearity.linear, PALLET.lin);
    try testing.expectEqual(Linearity.linear, SHIPMENT.lin);
    try testing.expectEqual(Linearity.affine, CARE_EVENT.lin);
    try testing.expectEqual(Linearity.relevant, SCAN_EVENT.lin);
    try testing.expectEqual(Linearity.linear, TAMPER_EVENT.lin);
    try testing.expectEqual(Linearity.debug, TASTING_NOTE.lin);
}

test "MARQUEE: tamper-event LINEAR ⇒ kernel forbids DROP and DUP (the tamper-loop one-shot guarantee)" {
    // The whole "a broken seal is irreversible and unforgeable" rule
    // reduces to this: a LINEAR cell cannot be discarded or duplicated,
    // only consumed once — verified against the REAL kernel
    // checkLinearity, not a copy. Mirrors Lean tessera.tamper_one_shot.
    try testing.expectEqual(Linearity.linear, TAMPER_EVENT.lin);
    try testing.expectError(
        error.cannot_discard_linear,
        linearity.checkLinearity(TAMPER_EVENT.lin, .discard),
    );
    try testing.expectError(
        error.cannot_duplicate_linear,
        linearity.checkLinearity(TAMPER_EVENT.lin, .duplicate),
    );
    // The single intact→broken transition = exactly one consume.
    try linearity.checkLinearity(TAMPER_EVENT.lin, .consume);
}

test "custody chain LINEAR ⇒ no DUP/DROP (Lean: tessera.custody_linear)" {
    // barrel/bottle/case/pallet/shipment cannot be cloned (value
    // printed twice) or dropped (custody silently vanishes).
    for ([_]CellType{ BARREL, BOTTLE, CASE, PALLET, SHIPMENT }) |t| {
        try testing.expectError(error.cannot_duplicate_linear, linearity.checkLinearity(t.lin, .duplicate));
        try testing.expectError(error.cannot_discard_linear, linearity.checkLinearity(t.lin, .discard));
        try linearity.checkLinearity(t.lin, .consume);
    }
}

test "grape-lot & care-event AFFINE ⇒ no DUP, DROP allowed (accumulate at most once)" {
    for ([_]CellType{ GRAPE_LOT, CARE_EVENT }) |t| {
        try testing.expectError(error.cannot_duplicate_affine, linearity.checkLinearity(t.lin, .duplicate));
        // AFFINE permits discard — a lot may be left unused; a shipment
        // may carry zero care events.
        try linearity.checkLinearity(t.lin, .discard);
        try linearity.checkLinearity(t.lin, .consume);
    }
}

test "scan-event RELEVANT ⇒ DUP ok, no DROP (Lean: tessera.scan_evidence_present)" {
    // The Care Score view cannot render without the scan evidence: a
    // RELEVANT cell must be retained, may be referenced repeatedly.
    try linearity.checkLinearity(SCAN_EVENT.lin, .duplicate);
    try testing.expectError(error.cannot_discard_relevant, linearity.checkLinearity(SCAN_EVENT.lin, .discard));
}

test "tasting-note DEBUG ⇒ inert: every op allowed, opaque to FSM/cap flow" {
    try linearity.checkLinearity(TASTING_NOTE.lin, .duplicate);
    try linearity.checkLinearity(TASTING_NOTE.lin, .discard);
    try linearity.checkLinearity(TASTING_NOTE.lin, .consume);
}

test "header byte layout round-trips through the real kernel readers" {
    const owner = [_]u8{0xC3} ** 16;
    for (ALL) |t| {
        const hdr = buildHeader(t, owner);
        try testing.expectEqual(t.lin, try linearity.getLinearity(&hdr));
        try testing.expectEqual(domainFlag(t), try linearity.getDomainFlag(&hdr));
        try testing.expectEqual(typeHash(t), try linearity.getTypeHash(&hdr));
        try testing.expectEqual(owner, try linearity.getOwnerId(&hdr));
    }
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

test "all ten cartridge.json cell types are present in ALL" {
    try testing.expectEqual(@as(usize, 10), ALL.len);
}

```
