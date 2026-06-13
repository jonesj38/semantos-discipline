---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/tests/vault_round_trip.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.300593+00:00
---

# runtime/node/tests/vault_round_trip.zig

```zig
// Phase W11 — vault cell at-rest round-trip via `LmdbSlotStore`.
// Reference: docs/design/WALLET-TIER-CUSTODY.md §6.2 (Tier-N base cell, AFFINE),
// §6.2.1 (per-tx leaf, LINEAR), and docs/design/VAULT-MULTISIG-NSEQUENCE.md
// (multisig-extended Tier-3 leaf layout).
//
// What we test
// ────────────
// The W11 design adds a multisig-aware Tier-3 leaf cell layout but does NOT
// change the slot-store contract: cells are encrypted opaque blobs that the
// engine round-trips through `host_persist_cell` / `host_load_cell` at a
// given slot id. The acceptance criterion is that the v0.2 vault cell
// (extended payload — member pubkeys, threshold, nSequence, parent_txid)
// survives the AES-GCM envelope round-trip bit-for-bit.
//
// We exercise the AFFINE Tier-3 *base* key cell here (which is what lives
// at rest — the LINEAR leaf is per-tx and never persisted). The base cell
// holds the vault root for BRC-42 derivation; the multisig-specific fields
// (member pubkeys, threshold, nSequence) are derived/staged at signing time
// onto the leaf cell. Persisting the base verifies the slot-store contract
// is unchanged by W11. We separately confirm the LINEAR leaf format builds
// correctly via the cell-engine `tests/vault_conformance.zig`.

const std = @import("std");
const slot_store_mod = @import("slot_store");
const lmdb_slot = @import("lmdb_slot_store");

fn makeTmpDir(allocator: std.mem.Allocator) ![]u8 {
    const ts = std.time.nanoTimestamp();
    const tmp_root = std.posix.getenv("TMPDIR") orelse "/tmp";
    const path = try std.fmt.allocPrint(
        allocator,
        "{s}/semantos-vault-test-{d}-{d}",
        .{ tmp_root, ts, std.crypto.random.int(u32) },
    );
    try std.fs.cwd().makePath(path);
    return path;
}

// Layout constants mirroring §6.2 / VAULT-MULTISIG-NSEQUENCE.md.
const HEADER_SIZE: usize = 256;
const PAYLOAD_SIZE: usize = 768;
const CELL_SIZE: usize = HEADER_SIZE + PAYLOAD_SIZE;

const VAULT_DOMAIN_FLAG: u32 = 0x10000005;

// Plexus offsets we don't import here (test runs without the full cell-engine
// module graph) — keep them in lockstep with `core/cell-engine/src/opcodes/plexus.zig`.
const VAULT_OFFSET_THRESHOLD: usize = 63;
const VAULT_OFFSET_MEMBER_PUBKEYS_START: usize = 64;
const VAULT_OFFSET_NSEQUENCE: usize = 229;
const VAULT_OFFSET_PARENT_TXID: usize = 233;
const VAULT_MEMBER_PUBKEY_LEN: usize = 33;

const LINEARITY_AFFINE: u8 = 2;
const LINEARITY_LINEAR: u8 = 1;
const LINEARITY_RELEVANT: u8 = 3;

const MAGIC_1: u32 = 0xDEADBEEF;
const MAGIC_2: u32 = 0xCAFEBABE;
const MAGIC_3: u32 = 0x13371337;
const MAGIC_4: u32 = 0x42424242;

/// Build a 1024-byte Tier-3 vault cell with the v0.2 multisig metadata.
/// This is the same byte layout the cell-engine vault tests construct, but
/// reproduced here so the runtime/node test suite has no upstream-source
/// import (mirrors `lmdb_round_trip.zig`'s standalone style).
fn makeVaultCell(
    linearity_byte: u8,
    leaf_sk_marker: u8,
    member_count: u8,
    threshold: u8,
    nsequence: u32,
    parent_txid_marker: u8,
) [CELL_SIZE]u8 {
    var cell: [CELL_SIZE]u8 = [_]u8{0} ** CELL_SIZE;
    std.mem.writeInt(u32, cell[0..4], MAGIC_1, .little);
    std.mem.writeInt(u32, cell[4..8], MAGIC_2, .little);
    std.mem.writeInt(u32, cell[8..12], MAGIC_3, .little);
    std.mem.writeInt(u32, cell[12..16], MAGIC_4, .little);
    cell[16] = linearity_byte;
    std.mem.writeInt(u32, cell[20..24], 1, .little); // version
    std.mem.writeInt(u32, cell[24..28], VAULT_DOMAIN_FLAG, .little);

    // Pseudo-priv-key (deterministic marker for round-trip identity).
    @memset(cell[HEADER_SIZE .. HEADER_SIZE + 32], leaf_sk_marker);

    // Threshold byte
    cell[HEADER_SIZE + VAULT_OFFSET_THRESHOLD] = threshold;

    // Each pubkey slot is filled with a recognizable per-slot byte pattern.
    var i: u8 = 0;
    while (i < member_count and i < 5) : (i += 1) {
        const off = HEADER_SIZE + VAULT_OFFSET_MEMBER_PUBKEYS_START +
            @as(usize, i) * VAULT_MEMBER_PUBKEY_LEN;
        // First byte mimics a compressed-pubkey prefix (0x02 / 0x03).
        cell[off] = if (i % 2 == 0) 0x02 else 0x03;
        // Remaining 32 bytes get a recognizable marker.
        @memset(cell[off + 1 .. off + VAULT_MEMBER_PUBKEY_LEN], 0xA0 + i);
    }

    // nSequence
    std.mem.writeInt(
        u32,
        cell[HEADER_SIZE + VAULT_OFFSET_NSEQUENCE ..][0..4],
        nsequence,
        .little,
    );

    // parent_txid
    @memset(
        cell[HEADER_SIZE + VAULT_OFFSET_PARENT_TXID .. HEADER_SIZE + VAULT_OFFSET_PARENT_TXID + 32],
        parent_txid_marker,
    );

    return cell;
}

// 1) AFFINE base — round-trips bit-for-bit via the slot store.
test "Vault: AFFINE Tier-3 base cell round-trips through LmdbSlotStore" {
    const allocator = std.testing.allocator;
    const dir = try makeTmpDir(allocator);
    defer {
        std.fs.cwd().deleteTree(dir) catch {};
        allocator.free(dir);
    }

    // §6.2: base key cell is AFFINE.
    const base = makeVaultCell(
        LINEARITY_AFFINE,
        0x55, // leaf_sk_marker
        3, // 3 member pubkeys
        2, // 2-of-3 threshold
        (1 << 22) | 60, // BIP-68 time-mode, 60 * 512s
        0xDE, // parent_txid_marker
    );

    {
        var s = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
        defer s.deinit();
        const iface = s.store();
        try iface.put(0x301, &base);
    }

    // Re-open: bytes match exactly.
    var s2 = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
    defer s2.deinit();
    const got = try s2.store().get(0x301);
    try std.testing.expectEqualSlices(u8, &base, got);

    // Re-extract structural fields and confirm they survive the round trip.
    try std.testing.expectEqual(LINEARITY_AFFINE, got[16]);
    try std.testing.expectEqual(@as(u8, 2), got[HEADER_SIZE + VAULT_OFFSET_THRESHOLD]);
    try std.testing.expectEqual(
        @as(u32, (1 << 22) | 60),
        std.mem.readInt(u32, got[HEADER_SIZE + VAULT_OFFSET_NSEQUENCE ..][0..4], .little),
    );
}

// 2) LINEAR leaf — also round-trips. The leaf is normally never persisted
//    (v0.2 vault leaves are derived per spend), but the slot store has no
//    knowledge of linearity and the test confirms the contract is uniform.
test "Vault: LINEAR Tier-3 leaf cell round-trips (extended layout preserved)" {
    const allocator = std.testing.allocator;
    const dir = try makeTmpDir(allocator);
    defer {
        std.fs.cwd().deleteTree(dir) catch {};
        allocator.free(dir);
    }

    const leaf = makeVaultCell(
        LINEARITY_LINEAR,
        0x77,
        5, // up to VAULT_MAX_MEMBERS
        3, // 3-of-5
        // BIP-68 disable bit set — leaf carries no cooldown of its own; the
        // chained UTXO does. We still verify the field survives a round trip.
        (1 << 31),
        0xBE,
    );

    {
        var s = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
        defer s.deinit();
        try s.store().put(0x1EAF, &leaf);
    }

    var s2 = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
    defer s2.deinit();
    const got = try s2.store().get(0x1EAF);
    try std.testing.expectEqualSlices(u8, &leaf, got);

    // 5 distinct member-pubkey markers preserved.
    var idx: u8 = 0;
    while (idx < 5) : (idx += 1) {
        const off = HEADER_SIZE + VAULT_OFFSET_MEMBER_PUBKEYS_START +
            @as(usize, idx) * VAULT_MEMBER_PUBKEY_LEN;
        const expected_prefix: u8 = if (idx % 2 == 0) 0x02 else 0x03;
        try std.testing.expectEqual(expected_prefix, got[off]);
        try std.testing.expectEqual(@as(u8, 0xA0 + idx), got[off + 1]);
    }
    try std.testing.expectEqual(@as(u8, 3), got[HEADER_SIZE + VAULT_OFFSET_THRESHOLD]);
}

// 3) Multiple vault cells coexist at distinct slot ids — deletion of one
//    leaves the other intact. Confirms slot-store isolation under W11
//    layout (no shared per-tier global state on the vault side).
test "Vault: independent slots (delete one, others remain)" {
    const allocator = std.testing.allocator;
    const dir = try makeTmpDir(allocator);
    defer {
        std.fs.cwd().deleteTree(dir) catch {};
        allocator.free(dir);
    }

    const a = makeVaultCell(LINEARITY_AFFINE, 0x11, 3, 2, 0x10, 0x01);
    const b = makeVaultCell(LINEARITY_AFFINE, 0x22, 4, 3, 0x20, 0x02);
    const c = makeVaultCell(LINEARITY_AFFINE, 0x33, 5, 3, 0x30, 0x03);

    {
        var s = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
        defer s.deinit();
        try s.store().put(0x301, &a);
        try s.store().put(0x302, &b);
        try s.store().put(0x303, &c);
    }

    var s2 = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
    defer s2.deinit();
    try s2.store().delete(0x302);

    var s3 = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
    defer s3.deinit();
    try std.testing.expectEqualSlices(u8, &a, try s3.store().get(0x301));
    try std.testing.expectError(error.not_found, s3.store().get(0x302));
    try std.testing.expectEqualSlices(u8, &c, try s3.store().get(0x303));
}

// 4) v0.1 vault stub MUST still round-trip. The v0.1 layout is just a
//    plain Tier-3 LINEAR leaf cell with priv_key in payload[0..32] and
//    no extended multisig fields — i.e. the post-v0.2 trailing region is
//    zero. Confirms backward compatibility (Acceptance criterion 7).
test "Vault: v0.1 stub LINEAR cell still round-trips (no W11 regression)" {
    const allocator = std.testing.allocator;
    const dir = try makeTmpDir(allocator);
    defer {
        std.fs.cwd().deleteTree(dir) catch {};
        allocator.free(dir);
    }

    var stub: [CELL_SIZE]u8 = [_]u8{0} ** CELL_SIZE;
    std.mem.writeInt(u32, stub[0..4], MAGIC_1, .little);
    std.mem.writeInt(u32, stub[4..8], MAGIC_2, .little);
    std.mem.writeInt(u32, stub[8..12], MAGIC_3, .little);
    std.mem.writeInt(u32, stub[12..16], MAGIC_4, .little);
    stub[16] = LINEARITY_LINEAR;
    std.mem.writeInt(u32, stub[20..24], 1, .little); // version
    std.mem.writeInt(u32, stub[24..28], VAULT_DOMAIN_FLAG, .little);
    @memset(stub[HEADER_SIZE .. HEADER_SIZE + 32], 0x99); // priv_key marker
    // Everything after [00..32] is zero — v0.1 had no multisig fields.

    {
        var s = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
        defer s.deinit();
        try s.store().put(0x100, &stub);
    }

    var s2 = try lmdb_slot.LmdbSlotStore.init(allocator, dir);
    defer s2.deinit();
    const got = try s2.store().get(0x100);
    try std.testing.expectEqualSlices(u8, &stub, got);

    // The W11 fields are all zero — a v0.1 cell is still recognizable as
    // such by its zeroed threshold byte.
    try std.testing.expectEqual(@as(u8, 0), got[HEADER_SIZE + VAULT_OFFSET_THRESHOLD]);
}

```
