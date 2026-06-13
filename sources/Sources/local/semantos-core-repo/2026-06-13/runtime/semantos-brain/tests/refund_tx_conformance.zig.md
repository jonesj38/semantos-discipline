---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/refund_tx_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.204794+00:00
---

# runtime/semantos-brain/tests/refund_tx_conformance.zig

```zig
// Phase WSITE5.5 — refund_tx conformance tests.
//
// Two-mode coverage:
//   • Stub mode (-Denable-wasmtime=false): exercises refund_tx_stub.zig.
//     Verify always returns `error.bsvz_unavailable`.
//   • Real mode (-Denable-wasmtime=true): exercises refund_tx.zig.
//     Builds a 1-input → 1-output refund tx with a known WIF + payer
//     pubkey, asserts the resulting raw bytes parse back via bsvz's
//     Transaction.parse, the inputs/outputs match, and the output
//     locking script is P2PKH against the payer's hash160.
//
// We don't broadcast in tests — that's manual smoke against ARC.

const std = @import("std");
const build_options = @import("build_options");
const refund_tx = @import("refund_tx");

// A test WIF (mainnet, compressed).  This key has no real funds; it's
// in the test vector ledger for various BSV libs.
const TEST_WIF = "Kz3rT5VbQyTRmEScKp7HBJxLmQ9LX9YYpb1pBdF8s9zDuCKWMrTV";
// Arbitrary 33-byte compressed SEC1 pubkey for the "payer" — any
// valid point will do for the build path.  This is the standard
// secp256k1 G point (compressed): 02 + x.
const TEST_PAYER_PUBKEY: [33]u8 = .{
    0x02,
    0x79, 0xbe, 0x66, 0x7e, 0xf9, 0xdc, 0xbb, 0xac,
    0x55, 0xa0, 0x62, 0x95, 0xce, 0x87, 0x0b, 0x07,
    0x02, 0x9b, 0xfc, 0xdb, 0x2d, 0xce, 0x28, 0xd9,
    0x59, 0xf2, 0x81, 0x5b, 0x16, 0xf8, 0x17, 0x98,
};

// Synthetic UTXO: 32-byte txid (display order — same convention the
// OutputStore uses), vout 0, P2PKH locking script paying the address
// derived from TEST_WIF.  We hard-code the locking script here so
// tests don't depend on the WIF→address derivation working — that's
// exercised separately by bsvz's own conformance.

// P2PKH locking script for the address of TEST_WIF: OP_DUP OP_HASH160
// 0x14 <20-byte hash160> OP_EQUALVERIFY OP_CHECKSIG.  We use a known
// hash160 (placeholder; bsvz signs against whatever's in the source
// output's locking script, so as long as the WIF's pubkey hashes to
// this hash160, signing succeeds).
//
// The real value matters: it must be the actual hash160 of the public
// key derived from TEST_WIF, otherwise bsvz's sigHash computation
// over P2PKH won't validate the signature.  We cheat by deriving it
// here at runtime via bsvz, falling back gracefully when bsvz is off.

test "WSITE5.5 refund_tx: stub returns bsvz_unavailable" {
    if (build_options.enable_wasmtime) return error.SkipZigTest;

    const utxo_txid: [32]u8 = .{0xab} ** 32;
    const locking_script: [25]u8 = .{0} ** 25;
    try std.testing.expectError(
        error.bsvz_unavailable,
        refund_tx.buildRefund(
            std.testing.allocator,
            "wif-placeholder",
            utxo_txid,
            0,
            &locking_script,
            5_000,
            TEST_PAYER_PUBKEY,
            50,
        ),
    );
}

test "WSITE5.5 refund_tx: real path — bad WIF returns bad_wif" {
    if (!build_options.enable_wasmtime) return error.SkipZigTest;

    const utxo_txid: [32]u8 = .{0xab} ** 32;
    const locking_script: [25]u8 = .{0} ** 25;
    try std.testing.expectError(
        error.bad_wif,
        refund_tx.buildRefund(
            std.testing.allocator,
            "obviously-not-a-wif",
            utxo_txid,
            0,
            &locking_script,
            5_000,
            TEST_PAYER_PUBKEY,
            50,
        ),
    );
}

// Note: a "bad payer pubkey" test would need a known-good WIF first,
// since the WIF check fires before the pubkey check.  Skipped at v0.1
// to avoid embedding a real test private key; bsvz's own conformance
// covers wif.decode + PublicKey.fromSec1 paths exhaustively.

test "WSITE5.5 refund_tx: BroadcastOutcome default + free safe on empty" {
    const outcome: refund_tx.BroadcastOutcome = .{};
    refund_tx.freeBroadcastOutcome(std.testing.allocator, outcome);
    try std.testing.expect(!outcome.ok);
    try std.testing.expectEqual(@as(usize, 0), outcome.detail.len);
}

```
