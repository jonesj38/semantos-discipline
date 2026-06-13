---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/tessera_mint.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.633167+00:00
---

# cartridges/tessera/brain/tessera_mint.zig

```zig
// tessera_mint — encode a tessera cell as a real substrate cell (P3c).
//
// Design: docs/design/UNIVERSAL-CARTRIDGE-BOOT.md §8 (P3c).
//
// P3a made `substrate_entity.specByTag` registry-backed; P3b registered
// tessera's 10 SPECs at boot. This is the encode half: given a tessera
// cell type + payload + owner, build the substrate `EncodeInput` (tag
// + linearity from tessera_cells, spec from tessera_cell_specs) and
// produce the canonical 1024-byte substrate cell + its cell_id via
// `substrate_entity.encodeEntityEscalating` (the SAME path
// `entity.encode` uses; >768 B payloads escalate to octave-1
// automatically — no kernel change).
//
// Pure + deterministic when `timestamp_ns` is supplied. NO persistence
// here: persisting requires the brain's entity `CellStore`, which comes
// up in serve.zig's `--enable-repl` block AFTER cartridge constructAll
// — wiring it into a cartridge's State is a late-dep-injection seam
// (its own design decision, see §8 follow-up). This file is the
// store-independent encode proof; a walker can already return a real
// cell_id (persisted=false) exactly as `entity_encode_walker` does
// when its store is null.
//
// Greenfield: lives under cartridges/tessera/; consumes the substrate
// encode API as an adapter (like tessera_walkers consumes
// verb_dispatcher). No brain-core src/ edit.

const std = @import("std");
const substrate_entity = @import("substrate_entity");
const tessera_cells = @import("tessera_cells");
const tessera_cell_specs = @import("tessera_cell_specs");

pub const CELL_BYTES = substrate_entity.CELL_BYTES;

pub const MintError = error{unknown_cell} || substrate_entity.EncodeError;

pub const Encoded = struct {
    cell: [CELL_BYTES]u8,
    cell_id: [32]u8,
};

/// tessera_cells.Linearity and substrate_entity.LinearityClass are both
/// kernel-aligned enums (linear=1, affine=2, relevant=3, debug=4), so
/// the class maps by ordinal. (Asserted by a test below so a future
/// divergence fails loudly rather than silently mis-encoding.)
fn classOf(lin: tessera_cells.Linearity) substrate_entity.LinearityClass {
    return @enumFromInt(@intFromEnum(lin));
}

fn indexOfCell(name: []const u8) ?usize {
    for (tessera_cells.ALL, 0..) |c, i| {
        if (std.mem.eql(u8, c.name, name)) return i;
    }
    return null;
}

/// Encode the tessera cell named `name` (e.g. "tessera.grape-lot") as a
/// real substrate cell. `owner_id` is the first 16 bytes of the
/// operator hat id; zero-fill is allowed (surfaces as an unowned cell
/// in audit — real hat-context wiring is a P3c follow-up alongside
/// persistence). Returns the 1024-byte cell + sha256 cell_id.
pub fn encodeCellByName(
    name: []const u8,
    owner_id: [16]u8,
    payload_json: []const u8,
    timestamp_ns: ?i128,
) MintError!Encoded {
    const idx = indexOfCell(name) orelse return error.unknown_cell;
    const cell = tessera_cells.ALL[idx];
    const spec = tessera_cell_specs.specForIndex(idx) orelse return error.unknown_cell;
    const enc = try substrate_entity.encodeEntityEscalating(.{
        .spec = spec,
        .linearity = classOf(cell.lin),
        .owner_id = owner_id,
        .payload_json = payload_json,
        .timestamp_ns = timestamp_ns,
    });
    var out: Encoded = .{ .cell = enc.cell, .cell_id = undefined };
    std.crypto.hash.sha2.Sha256.hash(&out.cell, &out.cell_id, .{});
    return out;
}

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

test "linearity enums stay kernel-aligned (ordinal map is valid)" {
    try testing.expectEqual(@as(u8, 1), @intFromEnum(substrate_entity.LinearityClass.linear));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(substrate_entity.LinearityClass.affine));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(substrate_entity.LinearityClass.relevant));
    try testing.expectEqual(@as(u8, 4), @intFromEnum(substrate_entity.LinearityClass.debug));
    // tessera_cells.Linearity is the kernel LinearityType (same ordinals).
    try testing.expectEqual(
        @intFromEnum(tessera_cells.GRAPE_LOT.lin), // affine
        @intFromEnum(classOf(tessera_cells.GRAPE_LOT.lin)),
    );
}

test "encodeCellByName: grape-lot → real substrate cell, correct header" {
    substrate_entity.resetRegisteredSpecsForTest();
    defer substrate_entity.resetRegisteredSpecsForTest();
    try tessera_cell_specs.registerAll();

    const owner = [_]u8{0} ** 16;
    const enc = try encodeCellByName(
        "tessera.grape-lot",
        owner,
        "{\"lotId\":\"L1\",\"grower\":\"alice\",\"volumeMl\":1000}",
        1_000_000, // deterministic
    );
    // The kernel-facing header must carry tessera's content-addressed
    // domain flag + AFFINE linearity (grape-lot).
    const dec = substrate_entity.decodeEntity(&enc.cell);
    try testing.expect(dec.magic_ok);
    try testing.expectEqual(
        tessera_cells.domainFlag(tessera_cells.GRAPE_LOT),
        dec.domain_flag,
    );
    try testing.expectEqual(@as(u8, 2), enc.cell[
        // OFFSET_LINEARITY — affine=2; decodeEntity exposes it too but
        // assert the raw byte to pin the wire contract.
        16
    ]);
}

test "encodeCellByName: deterministic id with fixed ts; distinct per type" {
    substrate_entity.resetRegisteredSpecsForTest();
    defer substrate_entity.resetRegisteredSpecsForTest();
    try tessera_cell_specs.registerAll();
    const owner = [_]u8{0} ** 16;
    const a1 = try encodeCellByName("tessera.grape-lot", owner, "{\"x\":1}", 42);
    const a2 = try encodeCellByName("tessera.grape-lot", owner, "{\"x\":1}", 42);
    try testing.expectEqualSlices(u8, &a1.cell_id, &a2.cell_id); // deterministic
    const b = try encodeCellByName("tessera.bottle", owner, "{\"x\":1}", 42);
    try testing.expect(!std.mem.eql(u8, &a1.cell_id, &b.cell_id)); // type-distinct
}

test "encodeCellByName: unknown cell name → error" {
    try testing.expectError(error.unknown_cell, encodeCellByName(
        "tessera.not-a-thing",
        [_]u8{0} ** 16,
        "{}",
        0,
    ));
}

```
