---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/cognition_bounty.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.982671+00:00
---

# core/cell-engine/src/cognition_bounty.zig

```zig
// WI-D2 — Capability-token incentive UTXO (cognition bounty contract).
//
// UTXO predicate: `verified_weight_output_match`.
//
// A "training bounty" UTXO is locked to a stable-thread anchor emitted by
// kernel A.  Kernel B can unlock the UTXO by presenting a citation anchor
// that:
//   1. References kernel A's anchor Merkle root (verified_weight_output_match).
//   2. Is itself anchored (the citation's anchor record is valid and confirmed).
//
// This is the paper's "training-as-public-bounty" mechanism:
//   - Kernel A anchors a stable thread → publishes a bounty UTXO
//   - Kernel B's reducer picks up the anchor via WI-B3
//   - Kernel B's intent commits citing the anchor
//   - The citation is itself anchored
//   - B presents the citation anchor to unlock A's bounty UTXO
//
// The verification is purely data-structural — no on-chain execution context
// needed for unit tests.  The `BountyUtxo` and `CitationAnchor` types are
// the minimal encoding.  Full sCrypt encoding follows the cell-engine wire
// format (header + payload) and is the caller's responsibility.
//
// Tests (inline):
//   WI-D2-T-bounty-released-on-valid-citation
//   WI-D2-T-bounty-locked-on-wrong-root
//   WI-D2-T-bounty-locked-on-unanchored-citation
//
// See research/cognition-implementation-plan.md §WI-D2.

const std = @import("std");

pub const HASH_LEN = 32;

/// The bounty UTXO locked by kernel A.
pub const BountyUtxo = struct {
    /// SHA-256 Merkle root from kernel A's stable-thread anchor.
    anchor_merkle_root: [HASH_LEN]u8,
    /// Kernel A's identifier (opaque bytes — typically SHA-256 of its public key).
    kernel_id: [HASH_LEN]u8,
    /// Locked amount in satoshis.
    amount_sats: u64,
};

/// The citation anchor presented by kernel B to claim the bounty.
pub const CitationAnchor = struct {
    /// Kernel A's anchor Merkle root that kernel B is citing.
    cited_anchor_root: [HASH_LEN]u8,
    /// Kernel B's own anchor Merkle root (proves B's claim is itself anchored).
    own_anchor_root: [HASH_LEN]u8,
    /// Kernel B's identifier.
    citing_kernel_id: [HASH_LEN]u8,
    /// Whether B's citation is confirmed anchored on-chain.
    is_anchored: bool,
    /// On-chain timestamp of B's anchor (ms).
    anchor_timestamp_ms: u64,
};

pub const VerifyResult = enum {
    ok,
    wrong_root,
    not_anchored,
};

/// `verified_weight_output_match`: the core bounty predicate.
/// Returns `.ok` iff the citation correctly references the bounty's anchor root
/// AND the citation is itself anchored on-chain.
pub fn verifyWeightOutputMatch(
    bounty: *const BountyUtxo,
    citation: *const CitationAnchor,
) VerifyResult {
    if (!std.mem.eql(u8, &bounty.anchor_merkle_root, &citation.cited_anchor_root)) {
        return .wrong_root;
    }
    if (!citation.is_anchored) {
        return .not_anchored;
    }
    return .ok;
}

// ── Inline tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

fn makeRoot(seed: u8) [HASH_LEN]u8 {
    var r: [HASH_LEN]u8 = undefined;
    @memset(&r, seed);
    return r;
}

test "WI-D2-T-bounty-released-on-valid-citation" {
    const root_a = makeRoot(0xAA);
    const bounty = BountyUtxo{
        .anchor_merkle_root = root_a,
        .kernel_id          = makeRoot(0x01),
        .amount_sats        = 10_000,
    };
    const citation = CitationAnchor{
        .cited_anchor_root  = root_a, // correctly cites A's anchor
        .own_anchor_root    = makeRoot(0xBB),
        .citing_kernel_id   = makeRoot(0x02),
        .is_anchored        = true,
        .anchor_timestamp_ms = 9_999_999,
    };
    try testing.expectEqual(VerifyResult.ok, verifyWeightOutputMatch(&bounty, &citation));
}

test "WI-D2-T-bounty-locked-on-wrong-root" {
    const bounty = BountyUtxo{
        .anchor_merkle_root = makeRoot(0xAA),
        .kernel_id          = makeRoot(0x01),
        .amount_sats        = 10_000,
    };
    const citation = CitationAnchor{
        .cited_anchor_root  = makeRoot(0xFF), // WRONG root
        .own_anchor_root    = makeRoot(0xBB),
        .citing_kernel_id   = makeRoot(0x02),
        .is_anchored        = true,
        .anchor_timestamp_ms = 9_999_999,
    };
    try testing.expectEqual(VerifyResult.wrong_root, verifyWeightOutputMatch(&bounty, &citation));
}

test "WI-D2-T-bounty-locked-on-unanchored-citation" {
    const root_a = makeRoot(0xAA);
    const bounty = BountyUtxo{
        .anchor_merkle_root = root_a,
        .kernel_id          = makeRoot(0x01),
        .amount_sats        = 10_000,
    };
    const citation = CitationAnchor{
        .cited_anchor_root  = root_a,
        .own_anchor_root    = makeRoot(0xBB),
        .citing_kernel_id   = makeRoot(0x02),
        .is_anchored        = false, // NOT yet anchored on-chain
        .anchor_timestamp_ms = 0,
    };
    try testing.expectEqual(VerifyResult.not_anchored, verifyWeightOutputMatch(&bounty, &citation));
}

test "end-to-end: anchor → bounty → citation → release" {
    // Kernel A anchors its stable thread
    const merkle_root_a = makeRoot(0xDE);

    const bounty = BountyUtxo{
        .anchor_merkle_root = merkle_root_a,
        .kernel_id = makeRoot(0xA1),
        .amount_sats = 50_000,
    };

    // Kernel B cites A's anchor and itself anchors
    const citation = CitationAnchor{
        .cited_anchor_root = merkle_root_a,    // cites A correctly
        .own_anchor_root   = makeRoot(0xB2),   // B's own anchor root
        .citing_kernel_id  = makeRoot(0xB1),
        .is_anchored       = true,             // confirmed on-chain
        .anchor_timestamp_ms = 1_000_000,
    };

    // Full end-to-end: should release
    try testing.expectEqual(VerifyResult.ok, verifyWeightOutputMatch(&bounty, &citation));
}

```
