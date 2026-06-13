---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/vault_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.961699+00:00
---

# core/cell-engine/tests/vault_conformance.zig

```zig
// Phase W11: Vault tier multisig + nSequence-cooldown conformance.
// Reference: docs/design/WALLET-TIER-CUSTODY.md §4.3 (vault stub vs multisig),
// §4.4 (cooldown — host clock v0.1, nSequence v0.2), §6.2.1 (per-tx leaf cell),
// docs/design/VAULT-MULTISIG-NSEQUENCE.md (full v0.2 layout + script form).
//
// v0.2 introduces NO new opcodes. The vault unlock flow reuses the existing
// `host.checkmultisig` (added during the BSV-restored phase) — these tests
// verify that:
//   1. A vault cell built with the §6.2.1+W11 layout round-trips threshold
//      multisig satisfaction via host.checkmultisig.
//   2. The cell's own LINEARITY/domain-flag invariants hold (Tier-3 vault keys
//      are LINEAR per-tx leaves; RELEVANT/AFFINE vault cells are rejected by
//      OP_SIGN per K11).
//   3. The nSequence field is readable from the documented payload offset.
//
// Tests run only in the FULL profile (BSVZ linked) — multisig verifies real
// ECDSA signatures.

const std = @import("std");
const constants = @import("constants");
const linearity = @import("linearity");
const pda_mod = @import("pda");
const plexus = @import("plexus");
const host = @import("host");
const bsvz = @import("bsvz");

// ── Vault cell layout constants (from plexus.zig) ─────────────────────

const VAULT_DOMAIN_FLAG: u32 = 0x10000005; // §6.2 Tier-3
const HEADER_SIZE: u32 = constants.HEADER_SIZE;

// ── Helpers ───────────────────────────────────────────────────────────

/// Deterministic 32-byte test scalar derived from a small index. Avoids
/// crypto.random in a unit test so failures are reproducible.
fn makeSk(idx: u8) [32]u8 {
    var k: [32]u8 = [_]u8{0} ** 32;
    // Fill with idx to keep it deterministic & well-distributed.
    for (&k, 0..) |*b, i| b.* = idx +% @as(u8, @intCast(i & 0xFF));
    // Avoid the tiny risk of a degenerate (zero / >= n) scalar by clamping
    // bit 7 of byte 0 high — keeps it well below the secp256k1 group order.
    k[0] = 0x40 | idx;
    return k;
}

/// Compressed sec1 pubkey for a given test scalar.
fn pubKeyOf(sk: [32]u8) ![33]u8 {
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(sk);
    const pk = try priv.publicKey();
    return pk.toCompressedSec1();
}

/// Build a Tier-3 vault leaf cell per §6.2.1+W11.
/// `lin` lets a test override the linearity for negative-path coverage.
fn makeVaultCell(
    lin: u32,
    leaf_sk: [32]u8,
    member_pks: []const [33]u8,
    threshold: u8,
    nsequence: u32,
    parent_txid: [32]u8,
) pda_mod.Cell {
    var cell: pda_mod.Cell = [_]u8{0} ** pda_mod.CELL_SIZE;
    std.mem.writeInt(u32, cell[0..4], constants.MAGIC_1, .little);
    std.mem.writeInt(u32, cell[4..8], constants.MAGIC_2, .little);
    std.mem.writeInt(u32, cell[8..12], constants.MAGIC_3, .little);
    std.mem.writeInt(u32, cell[12..16], constants.MAGIC_4, .little);
    std.mem.writeInt(u32, cell[16..20], lin, .little);
    std.mem.writeInt(u32, cell[20..24], 1, .little); // version
    std.mem.writeInt(u32, cell[24..28], VAULT_DOMAIN_FLAG, .little);

    // Payload offsets are relative to constants.HEADER_SIZE.
    @memcpy(cell[HEADER_SIZE .. HEADER_SIZE + 32], &leaf_sk);

    // Threshold byte at +63
    cell[HEADER_SIZE + plexus.VAULT_OFFSET_THRESHOLD] = threshold;

    // Member pubkey table at +64..+229 (5 * 33 = 165 bytes)
    const pk_base = HEADER_SIZE + plexus.VAULT_OFFSET_MEMBER_PUBKEYS_START;
    var i: u32 = 0;
    while (i < member_pks.len and i < plexus.VAULT_MAX_MEMBERS) : (i += 1) {
        const off = pk_base + i * plexus.VAULT_MEMBER_PUBKEY_LEN;
        @memcpy(cell[off .. off + plexus.VAULT_MEMBER_PUBKEY_LEN], &member_pks[i]);
    }

    // nSequence at +229..+233
    std.mem.writeInt(
        u32,
        cell[HEADER_SIZE + plexus.VAULT_OFFSET_NSEQUENCE ..][0..4],
        nsequence,
        .little,
    );

    // parent_txid at +233..+265
    @memcpy(
        cell[HEADER_SIZE + plexus.VAULT_OFFSET_PARENT_TXID .. HEADER_SIZE + plexus.VAULT_OFFSET_PARENT_TXID + 32],
        &parent_txid,
    );

    return cell;
}

/// Read the `nsequence` field from a vault cell.
fn readNSequence(cell: *const pda_mod.Cell) u32 {
    return std.mem.readInt(
        u32,
        cell[HEADER_SIZE + plexus.VAULT_OFFSET_NSEQUENCE ..][0..4],
        .little,
    );
}

/// Read the threshold field from a vault cell.
fn readThreshold(cell: *const pda_mod.Cell) u8 {
    return cell[HEADER_SIZE + plexus.VAULT_OFFSET_THRESHOLD];
}

/// Build a packed [pk_count * 33] buffer from the vault cell's member table.
fn extractMemberPubkeys(cell: *const pda_mod.Cell, n: u32, out: []u8) void {
    const pk_base = HEADER_SIZE + plexus.VAULT_OFFSET_MEMBER_PUBKEYS_START;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const off = pk_base + i * plexus.VAULT_MEMBER_PUBKEY_LEN;
        @memcpy(
            out[i * plexus.VAULT_MEMBER_PUBKEY_LEN .. (i + 1) * plexus.VAULT_MEMBER_PUBKEY_LEN],
            cell[off .. off + plexus.VAULT_MEMBER_PUBKEY_LEN],
        );
    }
}

/// Encode a list of member sigs into the [len][sig_bytes]... format
/// expected by host.checkmultisig (mirrors the BSV consensus calling
/// convention; see core/cell-engine/src/host.zig:407–438). Returns the
/// total number of bytes written.
fn packSigs(sigs: []const []const u8, out: []u8) u32 {
    var off: u32 = 0;
    for (sigs) |s| {
        out[off] = @intCast(s.len);
        off += 1;
        @memcpy(out[off .. off + s.len], s);
        off += @intCast(s.len);
    }
    return off;
}

/// Sign `digest` with each provided member secret key and return the
/// length-prefixed encoding `host.checkmultisig` expects. The trailing
/// sighash byte (0x41 = SIGHASH_ALL | FORKID) is appended per BSV convention.
fn signByMembers(
    member_sks: []const [32]u8,
    digest: [32]u8,
    out_sigs_buf: []u8,
) !u32 {
    var sig_blobs: [plexus.VAULT_MAX_MEMBERS][73]u8 = undefined;
    var sig_views: [plexus.VAULT_MAX_MEMBERS][]const u8 = undefined;
    if (member_sks.len > plexus.VAULT_MAX_MEMBERS) return error.too_many_members;

    for (member_sks, 0..) |sk, i| {
        const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(sk);
        const der = try priv.signDigest(digest);
        const der_bytes = der.bytes[0..der.len];
        if (der_bytes.len + 1 > sig_blobs[i].len) return error.sig_too_long;
        @memcpy(sig_blobs[i][0..der_bytes.len], der_bytes);
        sig_blobs[i][der_bytes.len] = 0x41; // SIGHASH_ALL | FORKID
        sig_views[i] = sig_blobs[i][0 .. der_bytes.len + 1];
    }
    return packSigs(sig_views[0..member_sks.len], out_sigs_buf);
}

// ── Tests ─────────────────────────────────────────────────────────────

// K14 differential — 2-of-3 multisig satisfies host.checkmultisig.
test "vault: 2-of-3 multisig spend verifies via host.checkmultisig" {
    // Three distinct member keys (phone enclave, laptop enclave, YubiKey).
    const sk_a = makeSk(0x11);
    const sk_b = makeSk(0x22);
    const sk_c = makeSk(0x33);
    const pk_a = try pubKeyOf(sk_a);
    const pk_b = try pubKeyOf(sk_b);
    const pk_c = try pubKeyOf(sk_c);

    // Build the vault cell. The leaf priv key is unused for the multisig path
    // (signing is by the *member* keys, not the leaf) — but every Tier-3
    // leaf cell still carries one for §6.2.1 layout consistency.
    const leaf_sk = makeSk(0x99);
    const parent_txid: [32]u8 = [_]u8{0xAB} ** 32;
    const cell = makeVaultCell(
        constants.LINEARITY_LINEAR,
        leaf_sk,
        &[_][33]u8{ pk_a, pk_b, pk_c },
        2, // 2-of-3
        plexus.VAULT_NSEQUENCE_TYPE_FLAG | (60 / 8 * 16 + 4), // ~60s, time-mode
        parent_txid,
    );

    // Spec: verify multisig is satisfied by 2 of the 3 members signing the
    // same transaction preimage digest. BSV consensus iterates pubkeys in
    // order, so we sign with members A and B (matching the cell's stored
    // order pk_a, pk_b, pk_c).
    const tx_preimage_digest: [32]u8 = blk: {
        var d: [32]u8 = undefined;
        for (&d, 0..) |*b, i| b.* = @as(u8, @intCast((i * 7 + 1) & 0xFF));
        break :blk d;
    };

    var pks_buf: [plexus.VAULT_MAX_MEMBERS * plexus.VAULT_MEMBER_PUBKEY_LEN]u8 = undefined;
    extractMemberPubkeys(&cell, 3, pks_buf[0 .. 3 * 33]);

    var sigs_buf: [plexus.VAULT_MAX_MEMBERS * 74]u8 = undefined;
    const sig_bytes = try signByMembers(
        &[_][32]u8{ sk_a, sk_b },
        tx_preimage_digest,
        &sigs_buf,
    );

    const ok = host.checkmultisig(
        pks_buf[0 .. 3 * 33],
        3,
        sigs_buf[0..sig_bytes],
        2,
        &tx_preimage_digest,
        readThreshold(&cell),
    );
    try std.testing.expect(ok);
}

// K14b — below-threshold (1-of-3) is rejected.
test "vault: 1-of-3 below threshold rejected" {
    const sk_a = makeSk(0x44);
    const sk_b = makeSk(0x55);
    const sk_c = makeSk(0x66);
    const pk_a = try pubKeyOf(sk_a);
    const pk_b = try pubKeyOf(sk_b);
    const pk_c = try pubKeyOf(sk_c);

    const leaf_sk = makeSk(0x77);
    const parent_txid: [32]u8 = [_]u8{0xCD} ** 32;
    const cell = makeVaultCell(
        constants.LINEARITY_LINEAR,
        leaf_sk,
        &[_][33]u8{ pk_a, pk_b, pk_c },
        2,
        plexus.VAULT_NSEQUENCE_TYPE_FLAG | 7, // ~7 * 512s
        parent_txid,
    );

    const digest: [32]u8 = [_]u8{0x42} ** 32;

    var pks_buf: [plexus.VAULT_MAX_MEMBERS * plexus.VAULT_MEMBER_PUBKEY_LEN]u8 = undefined;
    extractMemberPubkeys(&cell, 3, pks_buf[0 .. 3 * 33]);

    var sigs_buf: [plexus.VAULT_MAX_MEMBERS * 74]u8 = undefined;
    const sig_bytes = try signByMembers(&[_][32]u8{sk_a}, digest, &sigs_buf);

    // sig_count = 1, threshold = 2 → host.checkmultisig must reject.
    const ok = host.checkmultisig(
        pks_buf[0 .. 3 * 33],
        3,
        sigs_buf[0..sig_bytes],
        1,
        &digest,
        readThreshold(&cell),
    );
    try std.testing.expect(!ok);
}

// K14a — above threshold (3-of-3) succeeds.
test "vault: 3-of-3 (above threshold) succeeds" {
    const sk_a = makeSk(0x88);
    const sk_b = makeSk(0x99);
    const sk_c = makeSk(0xAA);
    const pk_a = try pubKeyOf(sk_a);
    const pk_b = try pubKeyOf(sk_b);
    const pk_c = try pubKeyOf(sk_c);

    const leaf_sk = makeSk(0xBB);
    const parent_txid: [32]u8 = [_]u8{0xEF} ** 32;
    const cell = makeVaultCell(
        constants.LINEARITY_LINEAR,
        leaf_sk,
        &[_][33]u8{ pk_a, pk_b, pk_c },
        2, // threshold is still 2; 3-of-3 just over-satisfies it
        plexus.VAULT_NSEQUENCE_TYPE_FLAG | 1,
        parent_txid,
    );

    const digest: [32]u8 = [_]u8{0x55} ** 32;

    var pks_buf: [plexus.VAULT_MAX_MEMBERS * plexus.VAULT_MEMBER_PUBKEY_LEN]u8 = undefined;
    extractMemberPubkeys(&cell, 3, pks_buf[0 .. 3 * 33]);

    var sigs_buf: [plexus.VAULT_MAX_MEMBERS * 74]u8 = undefined;
    const sig_bytes = try signByMembers(
        &[_][32]u8{ sk_a, sk_b, sk_c },
        digest,
        &sigs_buf,
    );

    const ok = host.checkmultisig(
        pks_buf[0 .. 3 * 33],
        3,
        sigs_buf[0..sig_bytes],
        3,
        &digest,
        readThreshold(&cell),
    );
    try std.testing.expect(ok);
}

// Vault cell rejected if linearity != LINEAR — vault keys must not be
// RELEVANT or AFFINE-class. Verified by attempting OP_SIGN on the leaf
// inside a RELEVANT vault cell (per K11/K12 invariants).
test "vault: cell rejected when linearity != LINEAR via OP_SIGN" {
    const sk_a = makeSk(0xCC);
    const pk_a = try pubKeyOf(sk_a);

    const leaf_sk = makeSk(0xDD);
    const parent_txid: [32]u8 = [_]u8{0x77} ** 32;

    // RELEVANT vault leaf — must be rejected by OP_SIGN's linearity gate.
    const cell_rel = makeVaultCell(
        constants.LINEARITY_RELEVANT,
        leaf_sk,
        &[_][33]u8{pk_a},
        1,
        0, // nSequence disabled is fine for this negative path
        parent_txid,
    );

    var p = pda_mod.PDA.init(500_000);
    const digest: [32]u8 = [_]u8{0x33} ** 32;
    try p.spushCell(&cell_rel, pda_mod.CELL_SIZE);
    try p.spush(&digest);
    try p.spush(&[_]u8{0x41});

    try std.testing.expectError(
        error.linearity_check_failed,
        plexus.executePlexus(&p, 0xCD),
    );
    // Failure-atomic: stack unchanged.
    try std.testing.expectEqual(@as(u32, 3), p.sdepth());
}

// nSequence field is readable from the documented vault cell offset, and
// round-trips through the layout helpers without bit-level loss.
test "vault: nSequence field readable from cell at VAULT_OFFSET_NSEQUENCE" {
    const sk_a = makeSk(0x01);
    const pk_a = try pubKeyOf(sk_a);
    const leaf_sk = makeSk(0x02);
    const parent_txid: [32]u8 = [_]u8{0x10} ** 32;

    // 60-second cooldown encoded BIP-68: type-flag bit | (60 / 512 ≈ 0, so 1 unit = 512s)
    // — for finer granularity we instead encode a known value and verify it
    // round-trips bitwise.
    const test_nseq: u32 = plexus.VAULT_NSEQUENCE_TYPE_FLAG | 0x000000FF;

    const cell = makeVaultCell(
        constants.LINEARITY_LINEAR,
        leaf_sk,
        &[_][33]u8{pk_a},
        1,
        test_nseq,
        parent_txid,
    );

    try std.testing.expectEqual(test_nseq, readNSequence(&cell));

    // Sanity-check BIP-68 helpers exposed alongside the offset constants.
    try std.testing.expect((test_nseq & plexus.VAULT_NSEQUENCE_TYPE_FLAG) != 0);
    try std.testing.expect((test_nseq & plexus.VAULT_NSEQUENCE_DISABLE_FLAG) == 0);
    try std.testing.expectEqual(
        @as(u32, 0xFF),
        test_nseq & plexus.VAULT_NSEQUENCE_VALUE_MASK,
    );
}

// Differential against the existing checkmultisig path: an unrelated
// adversarial signer cannot satisfy the threshold even with a structurally
// well-formed sig.
test "vault: forged sig from non-member rejected" {
    const sk_a = makeSk(0xA1);
    const sk_b = makeSk(0xB1);
    const sk_c = makeSk(0xC1);
    const pk_a = try pubKeyOf(sk_a);
    const pk_b = try pubKeyOf(sk_b);
    const pk_c = try pubKeyOf(sk_c);

    // The attacker's key is not in the member set.
    const sk_attacker = makeSk(0xFE);

    const leaf_sk = makeSk(0xFF);
    const parent_txid: [32]u8 = [_]u8{0xBA} ** 32;
    const cell = makeVaultCell(
        constants.LINEARITY_LINEAR,
        leaf_sk,
        &[_][33]u8{ pk_a, pk_b, pk_c },
        2,
        plexus.VAULT_NSEQUENCE_TYPE_FLAG | 1,
        parent_txid,
    );

    const digest: [32]u8 = [_]u8{0x66} ** 32;

    var pks_buf: [plexus.VAULT_MAX_MEMBERS * plexus.VAULT_MEMBER_PUBKEY_LEN]u8 = undefined;
    extractMemberPubkeys(&cell, 3, pks_buf[0 .. 3 * 33]);

    // Sign with member A and the attacker → only 1 sig will verify, falling
    // short of the 2-of-3 threshold.
    var sigs_buf: [plexus.VAULT_MAX_MEMBERS * 74]u8 = undefined;
    const sig_bytes = try signByMembers(
        &[_][32]u8{ sk_a, sk_attacker },
        digest,
        &sigs_buf,
    );

    const ok = host.checkmultisig(
        pks_buf[0 .. 3 * 33],
        3,
        sigs_buf[0..sig_bytes],
        2,
        &digest,
        readThreshold(&cell),
    );
    try std.testing.expect(!ok);
}

```
