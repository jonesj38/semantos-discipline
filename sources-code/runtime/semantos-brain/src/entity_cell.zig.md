---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/entity_cell.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.257124+00:00
---

# runtime/semantos-brain/src/entity_cell.zig

```zig
// W0.2 — Entity cell encoding/decoding for the five oddjobz entity stores.
//
// Each domain entity is packed into a 1024-byte cell for storage in
// LmdbCellStore.  The cell layout is a simple framing:
//
//   [0..3]   entity_tag (u32 LE) — identifies the entity type
//   [4..7]   version    (u32 LE) — always 1 for W0.2 cells
//   [8..11]  payload_len (u32 LE) — length of the JSON payload
//   [12..15] padding (zeroed)
//   [16..16+payload_len-1] JSON payload (UTF-8, NOT null-terminated)
//   [16+payload_len..1023] zeroed padding
//
// Entity tags:
//   0x01 — customer
//   0x02 — visit
//   0x03 — quote
//   0x04 — invoice
//   0x05 — attachment
//   0x06 — job      (W0.1)
//   0x07 — site     (W6.2)
//   0x08 — retired  (was lead, W6.3; removed C4 PR-J6/J7 — lead = job.v2 state)
//
// The JSON payload is the canonical JSONL line that was previously written
// to disk — same format, same fields.  This keeps the encode/decode logic
// minimal and the cell content human-readable.
//
// K4 atomicity: callers MUST call encode first, then cell_store.put().
// If put() returns an error, the caller must NOT update any in-memory state.

const std = @import("std");
const cell_store_mod = @import("cell_store");

pub const CELL_BYTES = cell_store_mod.CELL_BYTES; // 1024
pub const ENTITY_TAG_CUSTOMER: u32 = 0x01;
pub const ENTITY_TAG_VISIT: u32 = 0x02;
pub const ENTITY_TAG_QUOTE: u32 = 0x03;
pub const ENTITY_TAG_INVOICE: u32 = 0x04;
pub const ENTITY_TAG_ATTACHMENT: u32 = 0x05;
pub const ENTITY_TAG_JOB: u32 = 0x06; // W0.1
pub const ENTITY_TAG_SITE: u32 = 0x07; // W6.2
// 0x08 retired — was ENTITY_TAG_LEAD (W6.3); removed C4 PR-J6/J7. Reserved.
pub const ENTITY_TAG_ESTIMATE: u32 = 0x09; // ODDJOBZ-ESTIMATE-ROM-INGRESS Slice 2
pub const ENTITY_TAG_CONTACT: u32 = 0x0A; // D-brain-contacts-api
pub const ENTITY_TAG_EDGE: u32 = 0x0B; // D-brain-contacts-api (contact edge records)

/// Header is 16 bytes: tag(4) + version(4) + payload_len(4) + pad(4).
pub const HEADER_BYTES: usize = 16;
/// Maximum payload that fits in one cell.
pub const MAX_PAYLOAD_BYTES: usize = CELL_BYTES - HEADER_BYTES; // 1008

pub const EncodeError = error{
    payload_too_large,
};

/// Encode a JSON payload (the JSONL line, without trailing newline) into a
/// 1024-byte cell with the given entity tag.  Returns the cell bytes.
///
/// If payload.len > MAX_PAYLOAD_BYTES (1008), returns error.payload_too_large.
pub fn encodeCell(entity_tag: u32, payload: []const u8) EncodeError![CELL_BYTES]u8 {
    if (payload.len > MAX_PAYLOAD_BYTES) return EncodeError.payload_too_large;
    var cell: [CELL_BYTES]u8 = [_]u8{0} ** CELL_BYTES;
    std.mem.writeInt(u32, cell[0..4], entity_tag, .little);
    std.mem.writeInt(u32, cell[4..8], 1, .little); // version = 1
    std.mem.writeInt(u32, cell[8..12], @intCast(payload.len), .little);
    // cell[12..16] = 0 (padding)
    @memcpy(cell[HEADER_BYTES .. HEADER_BYTES + payload.len], payload);
    return cell;
}

/// Read the entity_tag from a raw cell (the first 4 bytes, LE u32).
pub fn cellEntityTag(cell: *const [CELL_BYTES]u8) u32 {
    return std.mem.readInt(u32, cell[0..4], .little);
}

/// Extract the JSON payload slice from a raw cell.  The returned slice
/// points into the cell bytes — valid for as long as `cell` is valid.
pub fn cellPayload(cell: *const [CELL_BYTES]u8) []const u8 {
    const payload_len = std.mem.readInt(u32, cell[8..12], .little);
    const safe_len: usize = @min(payload_len, MAX_PAYLOAD_BYTES);
    return cell[HEADER_BYTES .. HEADER_BYTES + safe_len];
}

test "encodeCell round-trips a small payload" {
    const tag = ENTITY_TAG_CUSTOMER;
    const payload = "{\"id\":\"abc\"}";
    const cell = try encodeCell(tag, payload);
    try std.testing.expectEqual(tag, cellEntityTag(&cell));
    const back = cellPayload(&cell);
    try std.testing.expectEqualStrings(payload, back);
}

test "encodeCell rejects oversized payloads" {
    var big: [MAX_PAYLOAD_BYTES + 1]u8 = undefined;
    @memset(&big, 'x');
    try std.testing.expectError(EncodeError.payload_too_large, encodeCell(ENTITY_TAG_VISIT, &big));
}

```
