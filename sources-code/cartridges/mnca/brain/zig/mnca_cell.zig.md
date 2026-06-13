---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/mnca/brain/zig/mnca_cell.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.681499+00:00
---

# cartridges/mnca/brain/zig/mnca_cell.zig

```zig
// mnca_cell.zig — D-SRS-typed-cell
//
// Wraps an MNCA tile payload (768 bytes) in the Semantos 1024-byte cell
// wire format, giving it a proper type identity via typeHash.
//
// Cell layout (matches core/protocol-types/src/constants.ts + cell-header.ts):
//
//   [0..256)   256-byte header (packed LE):
//     [ 0..16)   magic: DEADBEEF CAFEBABE 13371337 42424242 (LE u32×4)
//     [16..20)   linearity: u32 LE = 3 (Linearity.RELEVANT)
//     [20..24)   version: u32 LE = 2
//     [24..28)   flags: u32 LE = 0
//     [28..30)   refCount: u16 LE = 1
//     [30..62)   typeHash: 32 B = SHA-256("mnca.tile.tick")
//     [62..78)   ownerId: 16 B = 0 (mesh node — no operator identity yet)
//     [78..86)   timestamp: u64 LE (now_ms from caller)
//     [86..90)   cellCount: u32 LE = 1
//     [90..94)   totalSize: u32 LE = PAYLOAD_SIZE (768)
//     [94..96)   reserved: u16 LE = 0
//     [96..128)  parentHash: 32 B = 0 (no chain yet)
//     [128..160) prevStateHash: 32 B = 0 (stateless for tile ticks)
//     [160..224) reserved (was onChainBinding, retired RM-042)
//     [224..256) domainPayloadRoot: SHA-256(tile_payload[0..768])
//   [256..1024) 768-byte tile payload (tileX, tileY, tick, state…)
//
// The typed cell is emitted alongside the existing plain cell_sync (768 B)
// so mesh-bridge can serve both old (768-byte payload) and new (1024-byte
// payload) consumers. The bridge distinguishes by payload length.
//
// typeHash = SHA-256("mnca.tile.tick")
//          = d2182b60a63e3646a75f9b4b2a1cd771d52e0ab913566a6dd84b78af7edbf519
//   (Verify: `node -e "const{createHash}=require('crypto');
//              console.log(createHash('sha256').update('mnca.tile.tick').digest('hex'))"`)

const std = @import("std");

// ── Constants (matching constants.ts) ─────────────────────────────────────────

pub const CELL_SIZE: usize = 1024;
pub const HEADER_SIZE: usize = 256;
pub const PAYLOAD_SIZE: usize = 768;

const VERSION: u32 = 2;
const LINEARITY_RELEVANT: u32 = 3;

// Header field offsets (matching HeaderOffsets in constants.ts).
const OFF_MAGIC: usize = 0;
const OFF_LINEARITY: usize = 16;
const OFF_VERSION: usize = 20;
const OFF_FLAGS: usize = 24;
const OFF_REF_COUNT: usize = 28;
const OFF_TYPE_HASH: usize = 30;
const OFF_OWNER_ID: usize = 62;
const OFF_TIMESTAMP: usize = 78;
const OFF_CELL_COUNT: usize = 86;
const OFF_TOTAL_SIZE: usize = 90;
const OFF_PARENT_HASH: usize = 96;
const OFF_PREV_STATE_HASH: usize = 128;
const OFF_DOMAIN_PAYLOAD_ROOT: usize = 224;
pub const OFF_PAYLOAD: usize = HEADER_SIZE;

// Magic bytes: [DEADBEEF, CAFEBABE, 13371337, 42424242] in LE.
const MAGIC_BYTES: [16]u8 = blk: {
    var m: [16]u8 = undefined;
    std.mem.writeInt(u32, m[0..4],   0xDEADBEEF, .little);
    std.mem.writeInt(u32, m[4..8],   0xCAFEBABE, .little);
    std.mem.writeInt(u32, m[8..12],  0x13371337, .little);
    std.mem.writeInt(u32, m[12..16], 0x42424242, .little);
    break :blk m;
};

// ── typeHash for "mnca.tile.tick" (SHA-256, hex above) ────────────────────────

pub const MNCA_TILE_TICK_TYPE_HASH: [32]u8 = .{
    0xd2, 0x18, 0x2b, 0x60, 0xa6, 0x3e, 0x36, 0x46,
    0xa7, 0x5f, 0x9b, 0x4b, 0x2a, 0x1c, 0xd7, 0x71,
    0xd5, 0x2e, 0x0a, 0xb9, 0x13, 0x56, 0x6a, 0x6d,
    0xd8, 0x4b, 0x78, 0xaf, 0x7e, 0xdb, 0xf5, 0x19,
};

// ── Cell builder ───────────────────────────────────────────────────────────────

/// Fill a 1024-byte output buffer with the typed cell wrapping `tile_payload`.
///
/// `out`           — must be exactly CELL_SIZE (1024) bytes.
/// `tile_payload`  — the 768-byte tile payload to embed.
/// `now_ms`        — wall-clock timestamp in milliseconds (u64, LE in header).
pub fn wrapTile(
    out: *[CELL_SIZE]u8,
    tile_payload: *const [PAYLOAD_SIZE]u8,
    now_ms: u64,
) void {
    @memset(out, 0);

    // ── Header ───────────────────────────────────────────────────────────────

    // Magic (16 B).
    @memcpy(out[OFF_MAGIC..][0..16], &MAGIC_BYTES);

    // Linearity: RELEVANT = 3.
    std.mem.writeInt(u32, out[OFF_LINEARITY..][0..4], LINEARITY_RELEVANT, .little);

    // Version: 2.
    std.mem.writeInt(u32, out[OFF_VERSION..][0..4], VERSION, .little);

    // flags: 0 (no special flags for tile ticks).
    std.mem.writeInt(u32, out[OFF_FLAGS..][0..4], 0, .little);

    // refCount: 1.
    std.mem.writeInt(u16, out[OFF_REF_COUNT..][0..2], 1, .little);

    // typeHash: SHA-256("mnca.tile.tick").
    @memcpy(out[OFF_TYPE_HASH..][0..32], &MNCA_TILE_TICK_TYPE_HASH);

    // ownerId: zeros (mesh node has no operator ID in v1).
    @memset(out[OFF_OWNER_ID..][0..16], 0);

    // timestamp: now_ms (u64 LE).
    std.mem.writeInt(u64, out[OFF_TIMESTAMP..][0..8], now_ms, .little);

    // cellCount: 1.
    std.mem.writeInt(u32, out[OFF_CELL_COUNT..][0..4], 1, .little);

    // totalSize: 768 (the payload byte count).
    std.mem.writeInt(u32, out[OFF_TOTAL_SIZE..][0..4], @intCast(PAYLOAD_SIZE), .little);

    // parentHash, prevStateHash: zeros (no chain linkage for tile ticks).
    @memset(out[OFF_PARENT_HASH..][0..32], 0);
    @memset(out[OFF_PREV_STATE_HASH..][0..32], 0);

    // bytes [160..224): reserved / zero.
    @memset(out[160..224], 0);

    // domainPayloadRoot: SHA-256(tile_payload).
    var dpr: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(tile_payload, &dpr, .{});
    @memcpy(out[OFF_DOMAIN_PAYLOAD_ROOT..][0..32], &dpr);

    // ── Payload ───────────────────────────────────────────────────────────────
    @memcpy(out[OFF_PAYLOAD..][0..PAYLOAD_SIZE], tile_payload);
}

/// Return the tile payload slice from a typed cell buffer (without copying).
pub fn tilePayload(cell: *const [CELL_SIZE]u8) *const [PAYLOAD_SIZE]u8 {
    return cell[OFF_PAYLOAD..][0..PAYLOAD_SIZE];
}

/// Quick validation: check magic bytes and typeHash match the tile-tick spec.
pub fn isValidMncaCell(cell: []const u8) bool {
    if (cell.len < CELL_SIZE) return false;
    if (!std.mem.eql(u8, cell[OFF_MAGIC..][0..16], &MAGIC_BYTES)) return false;
    if (!std.mem.eql(u8, cell[OFF_TYPE_HASH..][0..32], &MNCA_TILE_TICK_TYPE_HASH)) return false;
    return true;
}

// ── Inline tests ───────────────────────────────────────────────────────────────

const testing = std.testing;

test "wrapTile: output is CELL_SIZE" {
    var out: [CELL_SIZE]u8 = undefined;
    var tile: [PAYLOAD_SIZE]u8 = undefined;
    @memset(&tile, 0xAB);
    wrapTile(&out, &tile, 1_000_000);
    try testing.expect(out.len == CELL_SIZE);
}

test "wrapTile: magic bytes correct" {
    var out: [CELL_SIZE]u8 = undefined;
    var tile: [PAYLOAD_SIZE]u8 = undefined;
    @memset(&tile, 0);
    wrapTile(&out, &tile, 0);
    try testing.expect(std.mem.eql(u8, out[OFF_MAGIC..][0..16], &MAGIC_BYTES));
}

test "wrapTile: typeHash = SHA-256('mnca.tile.tick')" {
    var out: [CELL_SIZE]u8 = undefined;
    var tile: [PAYLOAD_SIZE]u8 = undefined;
    @memset(&tile, 0);
    wrapTile(&out, &tile, 0);
    const got = out[OFF_TYPE_HASH..][0..32];
    try testing.expect(std.mem.eql(u8, got, &MNCA_TILE_TICK_TYPE_HASH));
}

test "wrapTile: linearity = RELEVANT (3)" {
    var out: [CELL_SIZE]u8 = undefined;
    var tile: [PAYLOAD_SIZE]u8 = undefined;
    @memset(&tile, 0);
    wrapTile(&out, &tile, 0);
    const lin = std.mem.readInt(u32, out[OFF_LINEARITY..][0..4], .little);
    try testing.expectEqual(@as(u32, LINEARITY_RELEVANT), lin);
}

test "wrapTile: version = 2" {
    var out: [CELL_SIZE]u8 = undefined;
    var tile: [PAYLOAD_SIZE]u8 = undefined;
    @memset(&tile, 0);
    wrapTile(&out, &tile, 0);
    const ver = std.mem.readInt(u32, out[OFF_VERSION..][0..4], .little);
    try testing.expectEqual(@as(u32, 2), ver);
}

test "wrapTile: payload at OFF_PAYLOAD, bytes match" {
    var out: [CELL_SIZE]u8 = undefined;
    var tile: [PAYLOAD_SIZE]u8 = undefined;
    for (&tile, 0..) |*b, i| b.* = @intCast(i & 0xFF);
    wrapTile(&out, &tile, 42);
    const embedded = out[OFF_PAYLOAD..][0..PAYLOAD_SIZE];
    try testing.expect(std.mem.eql(u8, embedded, &tile));
}

test "wrapTile: timestamp in header" {
    var out: [CELL_SIZE]u8 = undefined;
    var tile: [PAYLOAD_SIZE]u8 = undefined;
    @memset(&tile, 0);
    const ts: u64 = 0xDEAD_BEEF_0000_1234;
    wrapTile(&out, &tile, ts);
    const got_ts = std.mem.readInt(u64, out[OFF_TIMESTAMP..][0..8], .little);
    try testing.expectEqual(ts, got_ts);
}

test "wrapTile: domainPayloadRoot = SHA-256(tile)" {
    var out: [CELL_SIZE]u8 = undefined;
    var tile: [PAYLOAD_SIZE]u8 = undefined;
    for (&tile, 0..) |*b, i| b.* = @intCast(i % 251);
    wrapTile(&out, &tile, 0);
    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&tile, &expected, .{});
    const got = out[OFF_DOMAIN_PAYLOAD_ROOT..][0..32];
    try testing.expect(std.mem.eql(u8, got, &expected));
}

test "isValidMncaCell: recognises correct cell" {
    var out: [CELL_SIZE]u8 = undefined;
    var tile: [PAYLOAD_SIZE]u8 = undefined;
    @memset(&tile, 0);
    wrapTile(&out, &tile, 0);
    try testing.expect(isValidMncaCell(&out));
}

test "isValidMncaCell: rejects wrong typeHash" {
    var out: [CELL_SIZE]u8 = undefined;
    var tile: [PAYLOAD_SIZE]u8 = undefined;
    @memset(&tile, 0);
    wrapTile(&out, &tile, 0);
    out[OFF_TYPE_HASH] ^= 0xFF; // corrupt typeHash
    try testing.expect(!isValidMncaCell(&out));
}

test "tilePayload: returns pointer into embedded payload" {
    var out: [CELL_SIZE]u8 = undefined;
    var tile: [PAYLOAD_SIZE]u8 = undefined;
    for (&tile, 0..) |*b, i| b.* = @intCast((i * 7) & 0xFF);
    wrapTile(&out, &tile, 0);
    const got = tilePayload(&out);
    try testing.expect(std.mem.eql(u8, got, &tile));
}

test "typeHash correctness: verify against runtime SHA-256" {
    // Double-check the hardcoded constant matches runtime SHA-256("mnca.tile.tick").
    var computed: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("mnca.tile.tick", &computed, .{});
    try testing.expect(std.mem.eql(u8, &computed, &MNCA_TILE_TICK_TYPE_HASH));
}

```
