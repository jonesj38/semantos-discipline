---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/swarm/brain/swarm_manifest.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.679487+00:00
---

# cartridges/swarm/brain/swarm_manifest.zig

```zig
// swarm_manifest — Zig side of the canonical swarm manifest, kept byte-identical
// to core/protocol-types/src/swarm-manifest.ts so a manifest published by a TS
// seeder and indexed/located by the brain agree on the same 32-byte infohash.
//
// Conformance is pinned by the `*_CONFORMANCE` test vectors below, generated
// from the TS implementation. If TS changes the canonical layout, these break.
//
//   infohash         = sha256(canonical manifest payload)  (== payload region of the cell)
//   manifest typeHash = sha256("swarm.manifest")
//   receipt  typeHash = sha256("swarm.receipt")

const std = @import("std");

const HEADER_SIZE: usize = 256;
const PAYLOAD_SIZE: usize = 768;
const TYPE_HASH_OFFSET: usize = 30;
const CELL_COUNT_OFFSET: usize = 86;
const TOTAL_SIZE_OFFSET: usize = 90;

fn hexLit(comptime s: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, s) catch unreachable;
    return out;
}

/// sha256("swarm.manifest") — the cell typeHash the brain indexes manifests by.
pub const MANIFEST_TYPE_HASH: [32]u8 = hexLit("1a6fa9cb95a145f31e9d6eef1dc25e825790f0b1996a5dada63a5ed605174b33");
/// sha256("swarm.receipt") — the settlement-ledger cell typeHash.
pub const RECEIPT_TYPE_HASH: [32]u8 = hexLit("e9f97610dc417b7e30a776d0f254c7db2dcf8d520b0f3fecdf19becfc2d036ce");

fn sha256(bytes: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &out, .{});
    return out;
}

/// Read the manifest cell's typeHash region (bytes 30..62).
pub fn cellTypeHash(cell: *const [1024]u8) [32]u8 {
    var out: [32]u8 = undefined;
    @memcpy(&out, cell[TYPE_HASH_OFFSET .. TYPE_HASH_OFFSET + 32]);
    return out;
}

/// True iff `cell` carries the swarm.manifest typeHash.
pub fn isManifestCell(cell: *const [1024]u8) bool {
    return std.mem.eql(u8, cell[TYPE_HASH_OFFSET .. TYPE_HASH_OFFSET + 32], &MANIFEST_TYPE_HASH);
}

/// infohash = sha256(canonical payload). The payload is the first
/// header.totalSize bytes of the payload region — byte-identical to the TS
/// `computeInfohash`, owner/timestamp-independent (those live in the header).
pub fn infohashFromManifestCell(cell: *const [1024]u8) [32]u8 {
    const total_size = std.mem.readInt(u32, cell[TOTAL_SIZE_OFFSET .. TOTAL_SIZE_OFFSET + 4], .little);
    const len = @min(@as(usize, total_size), PAYLOAD_SIZE);
    return sha256(cell[HEADER_SIZE .. HEADER_SIZE + len]);
}

/// Magic + minimal header fields (linearity LINEAR, version 2, typeHash,
/// cellCount 1, totalSize). The rest of the header stays zero — enough for the
/// CellStore to index by typeHash and for a reader to recover the payload.
fn writeCellHeader(cell: *[1024]u8, type_hash: *const [32]u8, payload_len: u32) void {
    @memset(cell, 0);
    std.mem.writeInt(u32, cell[0..4], 0xDEADBEEF, .little);
    std.mem.writeInt(u32, cell[4..8], 0xCAFEBABE, .little);
    std.mem.writeInt(u32, cell[8..12], 0x13371337, .little);
    std.mem.writeInt(u32, cell[12..16], 0x42424242, .little);
    std.mem.writeInt(u32, cell[16..20], 1, .little); // linearity = LINEAR
    std.mem.writeInt(u32, cell[20..24], 2, .little); // version
    @memcpy(cell[TYPE_HASH_OFFSET .. TYPE_HASH_OFFSET + 32], type_hash);
    std.mem.writeInt(u32, cell[CELL_COUNT_OFFSET .. CELL_COUNT_OFFSET + 4][0..4], 1, .little);
    std.mem.writeInt(u32, cell[TOTAL_SIZE_OFFSET .. TOTAL_SIZE_OFFSET + 4][0..4], payload_len, .little);
}

/// Decode a 2048-hex-char manifest cell into 1024 bytes.
pub fn decodeManifestCellHex(hex: []const u8) error{InvalidHex}![1024]u8 {
    if (hex.len != 2048) return error.InvalidHex;
    var cell: [1024]u8 = undefined;
    _ = std.fmt.hexToBytes(&cell, hex) catch return error.InvalidHex;
    return cell;
}

/// Build a swarm.receipt ledger cell committing a settled batch:
/// payload = {"infohash":"<hex>","count":<n>}.
pub fn buildReceiptCell(allocator: std.mem.Allocator, infohash_hex: []const u8, count: u32) ![1024]u8 {
    const payload = try std.fmt.allocPrint(allocator, "{{\"infohash\":\"{s}\",\"count\":{d}}}", .{ infohash_hex, count });
    defer allocator.free(payload);
    if (payload.len > PAYLOAD_SIZE) return error.PayloadTooLarge;
    var cell: [1024]u8 = undefined;
    writeCellHeader(&cell, &RECEIPT_TYPE_HASH, @intCast(payload.len));
    @memcpy(cell[HEADER_SIZE .. HEADER_SIZE + payload.len], payload);
    return cell;
}

// ─── Conformance tests (vectors generated from swarm-manifest.ts) ──────────────

const testing = std.testing;

test "type hashes match sha256 of the canonical names" {
    try testing.expectEqualSlices(u8, &MANIFEST_TYPE_HASH, &sha256("swarm.manifest"));
    try testing.expectEqualSlices(u8, &RECEIPT_TYPE_HASH, &sha256("swarm.receipt"));
}

test "infohash conformance with TS computeInfohash" {
    // Vector: manifest {v:1,p:"demo",ts:1000,n:1,cs:1016,ch:0xab*32,mr:0xcd*32}.
    const canon = "{\"v\":1,\"p\":\"demo\",\"ts\":1000,\"n\":1,\"cs\":1016,\"ch\":\"abababababababababababababababababababababababababababababababab\",\"mr\":\"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd\"}";
    const expected = hexLit("97a1116e1fca9ea9bb0c6dd115a94d724205b0a1877424fc556966cdf328be9a");
    // Direct: sha256(canonical payload) matches TS.
    try testing.expectEqualSlices(u8, &expected, &sha256(canon));
    // Via a built manifest cell: header.totalSize-scoped payload re-derives it.
    var cell: [1024]u8 = undefined;
    writeCellHeader(&cell, &MANIFEST_TYPE_HASH, @intCast(canon.len));
    @memcpy(cell[HEADER_SIZE .. HEADER_SIZE + canon.len], canon);
    try testing.expect(isManifestCell(&cell));
    try testing.expectEqualSlices(u8, &expected, &infohashFromManifestCell(&cell));
}

test "buildReceiptCell carries the receipt typeHash + a parseable payload" {
    const cell = try buildReceiptCell(testing.allocator, "deadbeef", 7);
    try testing.expectEqualSlices(u8, &RECEIPT_TYPE_HASH, &cellTypeHash(&cell));
    const total = std.mem.readInt(u32, cell[TOTAL_SIZE_OFFSET .. TOTAL_SIZE_OFFSET + 4], .little);
    try testing.expect(std.mem.indexOf(u8, cell[HEADER_SIZE .. HEADER_SIZE + total], "\"count\":7") != null);
    try testing.expect(std.mem.indexOf(u8, cell[HEADER_SIZE .. HEADER_SIZE + total], "\"infohash\":\"deadbeef\"") != null);
}

test "decodeManifestCellHex round-trips a built cell" {
    var cell: [1024]u8 = undefined;
    writeCellHeader(&cell, &MANIFEST_TYPE_HASH, 4);
    @memcpy(cell[HEADER_SIZE .. HEADER_SIZE + 4], "test");
    var hexbuf: [2048]u8 = undefined;
    const hex = std.fmt.bytesToHex(cell, .lower);
    @memcpy(&hexbuf, &hex);
    const decoded = try decodeManifestCellHex(&hexbuf);
    try testing.expectEqualSlices(u8, &cell, &decoded);
    try testing.expectError(error.InvalidHex, decodeManifestCellHex("abcd"));
}

```
