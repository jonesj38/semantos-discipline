---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/payment_verifier.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.445736+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/payment_verifier.zig

```zig
// Phase WSITE4.5 — Payment claim verifier.
//
// Reference: docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md §3 (WSITE4 + 4.5).
//
// Closes the v0.1 trust gap: WSITE4 records the payer's signed *claim*
// `(txid, satoshis)` but doesn't check the chain.  WSITE4.5 takes the
// caller-supplied BEEF, validates it via WH's PoW-verified header store,
// and confirms the cited tx actually pays >= the claimed amount to the
// configured `payment_recipient`.
//
// The `chain_tracker: anytype` parameter — same shape as
// `bsvz.spv.verifyBeef` — keeps this module testable without a real
// HeaderStore: tests pass a mock tracker that returns true for any
// (root, height) it's pre-loaded with.  Production callers wrap a
// `HeaderStore` (file-backed) with a thin `HeaderStoreTracker` that
// looks up `merkle_root` by `height` and compares.
//
// What the verifier does NOT do at v0.1:
//   • Internalize the UTXO into the admin's OutputStore (deferred to
//     WSITE4.6 when the broker exposes `internalizeAction`).
//   • Verify the source-output ancestry — bsvz.spv.verifyBeef walks
//     that for us, but the only thing this WSITE-level verifier asks
//     about is "did the tx reach the chain + does it pay me?".
//   • Track double-spends across multiple payment claims (the same
//     txid could in principle be replayed across two routes; v0.1
//     sweep_dedupes on txid in the ledger reader).

const std = @import("std");
const bsvz = @import("bsvz");

pub const VerifyError = error{
    parse_failed,
    txid_not_found,
    spv_invalid,
    no_matching_output,
    out_of_memory,
    /// Mirrors the stub's error tag.  Never returned by the real
    /// verifier, but listed here so call sites can write a single
    /// switch that compiles in both build modes.
    bsvz_unavailable,
};

/// Outcome of a verification attempt.  Distinguishes "BEEF/SPV check
/// passed but no output matched the expected recipient/amount" from
/// "the BEEF itself was bogus" so the operator can diagnose mis-pays
/// vs forged claims.
pub const VerifyResult = struct {
    /// The cited tx exists in the BEEF and its merkle path verifies
    /// against a trusted root from `chain_tracker`.
    spv_ok: bool = false,
    /// At least one output in the cited tx pays >= `expected_satoshis`
    /// to the expected recipient (P2PKH or P2PK against the supplied
    /// compressed-SEC1 pubkey).
    output_ok: bool = false,
    /// Combined pass: spv_ok && output_ok.
    verified: bool = false,
    /// Total satoshis matched across all matching outputs (informational —
    /// useful for over-payment detection in WSITE5).
    matched_satoshis: u64 = 0,
    /// WSITE4.6 — vout of the *first* output that matched the
    /// recipient + amount predicate.  Sites typically pay one output;
    /// the first-match policy avoids double-counting when the payer
    /// sends multiple outputs to the same recipient.  Only meaningful
    /// when `output_ok` is true.
    matched_vout: u32 = 0,
    /// WSITE4.6 — the matched output's locking script, duped via the
    /// `out_locking_script_allocator` argument to `verify` (when one is
    /// provided).  Empty otherwise.  Caller frees with the same
    /// allocator when done.  Only meaningful when `output_ok` is true.
    matched_locking_script: []u8 = &.{},
    /// WSITE4.6 — sats paid by the matched output specifically (not the
    /// total `matched_satoshis` summed across all matches).
    matched_output_satoshis: u64 = 0,
};

/// Verify a payment claim against the supplied BEEF.
///
///   allocator:                       working memory for BEEF parse + SPV walk
///   beef_bytes:                      raw BEEF v1 / v2 / atomic
///   txid_hex:                        64-char hex of the cited txid (display order)
///   recipient_sec1:                  33-byte compressed pubkey of the expected recipient
///   expected_satoshis:               minimum sats the matching output must pay
///   chain_tracker:                   anytype with `isValidRootForHeight(root, height) !bool`
///   out_locking_script_allocator:    if non-null, the matched output's
///                                    locking script is duped into this
///                                    allocator and surfaced via
///                                    `result.matched_locking_script` so
///                                    callers can hand the bytes to an
///                                    `OutputStore` (WSITE4.6).  Caller
///                                    frees on the same allocator.
pub fn verify(
    allocator: std.mem.Allocator,
    beef_bytes: []const u8,
    txid_hex: []const u8,
    recipient_sec1: [33]u8,
    expected_satoshis: u64,
    chain_tracker: anytype,
    out_locking_script_allocator: ?std.mem.Allocator,
) VerifyError!VerifyResult {
    var result = VerifyResult{};

    if (txid_hex.len != 64) return error.parse_failed;
    var txid_bytes: [32]u8 = undefined;
    hexDecode(txid_hex, &txid_bytes) catch return error.parse_failed;
    // BEEF txids are stored display-LE (the chainhash convention) — but
    // the user's `txid_hex` from a block explorer is also display-LE,
    // so byte-for-byte comparison works.  bsvz's chainhash.Hash stores
    // bytes in display order.
    const txid_chain = bsvz.primitives.chainhash.Hash{ .bytes = txid_bytes };

    var beef = bsvz.transaction.beef.newBeefFromBytes(allocator, beef_bytes) catch
        return error.parse_failed;
    defer beef.deinit();

    // First: does the BEEF's merkle path verify the cited tx?  bsvz's
    // verifyBeef walks every tx in the envelope and checks each merkle
    // path against the chain_tracker.  If the tracker returns false for
    // any included path, verifyBeef returns InvalidMerklePath.
    const ok = bsvz.spv.verifyBeef(allocator, &beef, txid_chain, chain_tracker, null) catch |err| switch (err) {
        error.MissingTransaction => return error.txid_not_found,
        else => {
            return result; // result.verified == false; spv_ok stays false
        },
    };
    if (!ok) return result;
    result.spv_ok = true;

    // Find the cited tx and walk its outputs looking for one that pays
    // expected_satoshis to the recipient.  Two script shapes accepted at
    // v0.1: P2PKH (`OP_DUP OP_HASH160 <hash160> OP_EQUALVERIFY OP_CHECKSIG`)
    // and bare P2PK (`<pubkey> OP_CHECKSIG`).  Wallets ship one or the
    // other; supporting both covers the common case.
    const tx = beef.findTransaction(txid_chain) orelse return error.txid_not_found;

    var hash160_recipient: [20]u8 = undefined;
    {
        var sha: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&recipient_sec1, &sha, .{});
        // RIPEMD160 of the SHA256 — pure-Zig from cell-engine.  We import
        // it via the Semantos Brain build dep.
        const ripemd160 = @import("ripemd160");
        ripemd160.hash(&sha, &hash160_recipient);
    }

    for (tx.outputs, 0..) |out, vout_usize| {
        const sats: u64 = @intCast(@max(out.satoshis, 0));
        if (sats < expected_satoshis) continue;
        const script = out.locking_script.bytes;
        if (matchesP2PKH(script, &hash160_recipient) or matchesP2PK(script, &recipient_sec1)) {
            result.matched_satoshis +|= sats;
            // First match wins for the WSITE4.6 internalize step — even
            // if the payer paid multiple matching outputs, we record one
            // canonical UTXO per claim.
            if (!result.output_ok) {
                result.matched_vout = @intCast(vout_usize);
                result.matched_output_satoshis = sats;
                if (out_locking_script_allocator) |a| {
                    const dup = a.alloc(u8, script.len) catch return error.out_of_memory;
                    @memcpy(dup, script);
                    result.matched_locking_script = dup;
                }
            }
            result.output_ok = true;
        }
    }

    result.verified = result.spv_ok and result.output_ok;
    return result;
}

// ─────────────────────────────────────────────────────────────────────
// Script shape matchers
// ─────────────────────────────────────────────────────────────────────

/// `OP_DUP OP_HASH160 0x14 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG` (25 bytes).
fn matchesP2PKH(script: []const u8, expected_hash160: *const [20]u8) bool {
    if (script.len != 25) return false;
    if (script[0] != 0x76) return false; // OP_DUP
    if (script[1] != 0xa9) return false; // OP_HASH160
    if (script[2] != 0x14) return false; // 20-byte push
    if (!std.mem.eql(u8, script[3..23], expected_hash160)) return false;
    if (script[23] != 0x88) return false; // OP_EQUALVERIFY
    if (script[24] != 0xac) return false; // OP_CHECKSIG
    return true;
}

/// `0x21 <33 bytes compressed pubkey> OP_CHECKSIG` (35 bytes).
fn matchesP2PK(script: []const u8, expected_sec1: *const [33]u8) bool {
    if (script.len != 35) return false;
    if (script[0] != 0x21) return false; // 33-byte push
    if (!std.mem.eql(u8, script[1..34], expected_sec1)) return false;
    if (script[34] != 0xac) return false; // OP_CHECKSIG
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// Hex helpers (duped from auth_handler to avoid the import cycle —
// payment_verifier needs to stay above the auth_handler ↔ site_server
// circle).
// ─────────────────────────────────────────────────────────────────────

fn hexDecode(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return error.bad_length;
    for (0..out.len) |i| {
        const hi = try nibble(hex[i * 2]);
        const lo = try nibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
}

fn nibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => error.bad_hex,
    };
}

```
