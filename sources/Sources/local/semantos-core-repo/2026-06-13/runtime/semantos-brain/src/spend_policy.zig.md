---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/spend_policy.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.213079+00:00
---

# runtime/semantos-brain/src/spend_policy.zig

```zig
// PR-9 — SpendPolicy foundation (recipe-template dispatch was a
// misnomer; see the rename note below).
//
// A SpendPolicy is the declarative contract between the brain's
// Context builder and a wallet/assembler: it pins (a) the on-chain
// lock-script shape the brain commits to via BIP-143, (b) the
// sighash flag combination the wallet must use when signing, (c)
// the structural predicate the brain grinds the sighash to satisfy
// before emitting the sign.request, and (d) which preimage fields
// the brain may nudge during that grind.
//
// The seam this PR ships replaces the per-cartridge-hardcoded
// sighash_flags + predicate constants the PR-8b series put on the
// MNCA Context builder's State struct with a single
// `policy: *const SpendPolicy` field. Cartridges (or future
// `bsv.tx.lock.policy` substrate cells — name TBD) declare which
// policy a transition uses; the brain dispatches accordingly.
// Adding a new on-chain enforcement contract (Brendan Lee's
// 110-byte OP_PUSH_TX, the 82-byte PUSHTX_BIT_SHIFT, etc.) becomes
// a 1-policy-entry change in this file rather than a per-cartridge
// kernel diff.
//
// Reference: LOCKSCRIPT-CLEAVAGE.md §3.5 (the Context construction
// seam is a dispatcher concern) + 2026-06-02 Brendan Lee
// conversation (architectural shift to brain-as-constraint-
// satisfier, captured in PR-8b-xi's grind loop + this PR's policy
// dispatcher).
//
// ── Rename note (PR-9 v2) ─────────────────────────────────────────────
//
// The initial PR-9 commit called this `SpendRecipe` and put
// `SHA256(name)` into the bsv.tx.sign.request payload's `recipe_id`
// field at offset 33. That conflated two distinct concepts:
//
//   1. **Recipe** (the one in `core/protocol-types/`): a BRC-42 /
//      BRC-43 derivation schema — `(protocolID, keyID, counterparty)`
//      — content-addressable, load-bearing for recovery + e2e p2p
//      key-material interop. The reserved sign.request `recipe_id`
//      slot is for THIS concept (per PR-8b-vi-3's planned semantics).
//      A separate `bsv.tx.derivation.recipe` substrate cellType is
//      scheduled for PR-9c.
//
//   2. **SpendPolicy** (what this file is): the brain's on-chain
//      enforcement dispatch contract. Sighash flag, structural
//      predicate, grind surface. Brain-side only — the wallet sees
//      the effects (sighash flag byte at offset 69) but doesn't
//      need a policy id in the wire format.
//
// Renaming SpendRecipe → SpendPolicy + reverting the recipe_id
// wire-format write fixes the conflation. The dispatch architecture
// is unchanged.
//
// Future PR-9b: ship per-policy on-chain lock-script template bytes
// (OP_PUSH_TX variants; Brendan-110b once bytes are validated) +
// the wider grind surface (`nlocktime_plus_lock_nonce` — pushes a
// policy-local grind nonce into the successor PushDrop).
//
// Future PR-9c: define the real `bsv.tx.derivation.recipe`
// substrate cellType + wire format for the BRC-42 derivation
// schema. That recipe — the one with key-material implications —
// is what the sign.request's reserved `recipe_id` slot is for.

const std = @import("std");

// ── BIP-143 sighash flag combinations ─────────────────────────────────
//
// `SIGHASH_ALL_FORKID` (0x41) — the v1 mainnet policy. Commits to
// ALL inputs (via `hashPrevouts` + `hashSequence`) AND all outputs
// (via `hashOutputs`). Strongest commitment; rules out fee-input
// extension because `hashPrevouts` changes the moment a second
// input lands.
//
// `SIGHASH_SINGLE_ANYONECANPAY_FORKID` (0xC3) — the fee-composable
// v1 default (PR-8b-xii-b). With SIGHASH_SINGLE + ANYONECANPAY:
//   - hashPrevouts = 0 (this input doesn't commit to other
//     inputs; a wallet can add fee inputs without invalidating)
//   - hashSequence = 0
//   - hashOutputs = SHA256d(output[input_index]) (commits to the
//     successor PushDrop at output 0 only; change outputs the
//     wallet adds after output 0 don't invalidate)
// The cleavage commitment in output 0 (cell-hash in the PushDrop)
// is what matters for the cell-graph; extra outputs are operator-
// side state the apparatus doesn't care about.
//
// `SIGHASH_NONE_ANYONECANPAY_FORKID` (0xC2) — the flag the
// FEE-PAYING secondary input uses (operator-side wallet
// composition). NONE means the fee input commits to no outputs
// at all; ANYONECANPAY means it doesn't commit to other inputs.
// Maximally permissive — appropriate for "pay whatever fee is
// needed, don't constrain the rest of the tx" semantics. Not
// used by the brain directly (the wallet builds + signs this
// input), but documented here so the constant ecosystem stays
// in one place.

pub const SIGHASH_ALL_FORKID: u8 = 0x41;
pub const SIGHASH_SINGLE_ANYONECANPAY_FORKID: u8 = 0xC3;
pub const SIGHASH_NONE_ANYONECANPAY_FORKID: u8 = 0xC2;

// ── SighashPredicate seam ──────────────────────────────────────────────
//
// Signature of a sighash structural predicate (moved here from
// PR-8b-xi's `cells_mint_mnca_context.zig` so multiple cartridges
// can share policies without circular imports).
//
// `digest` is the 32-byte BIP-143 (or OTDA) sighash output. Returns
// true if the digest satisfies the policy's on-chain validity
// constraint, false to keep grinding. Stateless + side-effect-free
// so the grind loop's invariants are obvious.

pub const SighashPredicate = *const fn (digest: *const [32]u8) bool;

/// Permissive predicate — accepts every 32-byte input.
/// Used by policies whose on-chain script (e.g. a plain
/// PushDrop + OP_CHECKSIG) imposes no structural constraint on
/// the sighash; the wallet signature is the only required
/// validity proof. The grind loop terminates on attempt 0.
pub fn sighashPredicatePermissive(digest: *const [32]u8) bool {
    _ = digest;
    return true;
}

/// Brendan Lee 136-byte OP_PUSH_TX construction predicate
/// (preliminary; verify with Brendan before relying on for
/// mainnet). Rejects when the sighash's tail 4 bytes equal
/// 0xFFFFFFFF — a 1-in-2^32 grind retry rate. The construction's
/// in-script endianness manipulation collapses on this exact value;
/// grinding nLockTime (or another surface) past the collision is
/// trivial.
///
/// Concrete on-chain lock-script bytes ship with PR-9b once
/// Brendan's bytes are validated. The predicate is published now
/// so the grind seam is exercised by tests + so cartridge authors
/// can reference the policy by name.
pub fn sighashPredicateBrendan136(digest: *const [32]u8) bool {
    return !(digest[28] == 0xFF and digest[29] == 0xFF and
        digest[30] == 0xFF and digest[31] == 0xFF);
}

// ── Grind surface taxonomy ─────────────────────────────────────────────
//
// Which preimage-committed fields the brain may freely nudge during
// the grind loop. Matches the runbook's grind-surface taxonomy
// (PR-8b-x update from 2026-06-02 Brendan conversation):
//
//   - `nlocktime`: brain nudges `tx.locktime` (32 bits, default
//     surface, what PR-8b-xi's grind loop currently uses)
//   - `nlocktime_plus_lock_nonce`: brain ALSO injects a policy-
//     local `PUSH <nonce> OP_DROP` prefix into the successor
//     PushDrop lock script — changes `hashOutputs` without
//     disturbing the cell-graph semantic commitment. Cleaner for
//     cartridges where nLockTime carries semantic meaning. Wired
//     in PR-9b alongside the OP_PUSH_TX policy bytes.

pub const GrindSurface = enum {
    nlocktime,
    nlocktime_plus_lock_nonce,
};

// ── SpendPolicy struct ─────────────────────────────────────────────────

/// Declarative contract for a single on-chain enforcement shape.
/// Cartridges (or future policy-substrate cells) reference a
/// SpendPolicy to declare how the brain should construct the
/// BIP-143 sighash + what predicate to grind to + what flag the
/// wallet should use.
pub const SpendPolicy = struct {
    /// Stable name for cartridge authors + ops. Used by
    /// `lookupByName` for in-Zig dispatch. Distinct from the BRC-42
    /// derivation recipe id that lives in
    /// `core/protocol-types/`-land; SpendPolicy is purely a
    /// brain-side dispatch artifact and does NOT participate in
    /// key derivation.
    name: []const u8,

    /// BSV sighash flag byte (BIP-143 SIGHASH_* | FORKID). Threaded
    /// through to (a) the BIP-143 digest computation in the brain's
    /// Context builder and (b) the sign.request payload's flag
    /// byte at offset 69 (the byte the wallet appends to the DER
    /// signature).
    sighash_flags: u8,

    /// Structural predicate the brain grinds to satisfy. The grind
    /// loop nudges the declared `grind_surface` fields until this
    /// predicate accepts.
    predicate: SighashPredicate,

    /// Which preimage-committed fields the brain may freely nudge.
    /// PR-9 supports `nlocktime` (the only surface PR-8b-xi's
    /// grind loop currently exercises); PR-9b widens to also push
    /// a policy-local grind nonce into the successor PushDrop.
    grind_surface: GrindSurface = .nlocktime,
};

// ── Policy registry ────────────────────────────────────────────────────

/// V1 PushDrop + OP_CHECKSIG policy — the mainnet-proven shape the
/// PR-8b-x runbook documents. Used by every MNCA anchor transition
/// from PR-8b-vi-2 through today. SIGHASH_ALL means the wallet can
/// NOT compose with fee inputs; this policy is for the zero-fee
/// broadcast path (WhatsOnChain) the runbook walk produced
/// [transition txid 5d592c2647…d0b8589a](https://whatsonchain.com/tx/5d592c2647fc96cbeddb37aff43daa9406efb43e1879b4ece3a4aa61d0b8589a)
/// against.
pub const POLICY_V1_PUSHDROP = SpendPolicy{
    .name = "policy.mnca.anchor.v1.pushdrop",
    .sighash_flags = SIGHASH_ALL_FORKID,
    .predicate = sighashPredicatePermissive,
    .grind_surface = .nlocktime,
};

/// V1 PushDrop fee-composable variant — same lock-script shape,
/// different sighash flag. SIGHASH_SINGLE+ANYONECANPAY lets a
/// wallet add a fee-paying secondary input (signed with
/// SIGHASH_NONE+ANYONECANPAY) without invalidating this primary
/// signature. PR-8b-xii-b's TS composer will use this policy to
/// unblock ARC/Taal broadcast. The on-chain lock is identical to
/// V1_PUSHDROP so existing PushDrop-aware wallets don't need any
/// lock-template change — only the sighash flag they sign over.
pub const POLICY_V1_FEE_COMPOSABLE = SpendPolicy{
    .name = "policy.mnca.anchor.v1.pushdrop.fee-composable",
    .sighash_flags = SIGHASH_SINGLE_ANYONECANPAY_FORKID,
    .predicate = sighashPredicatePermissive,
    .grind_surface = .nlocktime,
};

/// Brendan Lee 136-byte OP_PUSH_TX policy — placeholder for the
/// validated construction (bytes pending verification). The
/// predicate matches the cost profile in the PR-8b-x runbook's
/// grind-surface taxonomy (1-in-2^32 retry rate; mean 1 attempt).
/// Lock-template bytes + assembler integration land in PR-9b once
/// Brendan's bytes are validated. Until then this policy exercises
/// the grind seam in tests + documents the shape.
pub const POLICY_PUSHTX_136B = SpendPolicy{
    .name = "policy.pushtx.brendan.136b",
    .sighash_flags = SIGHASH_ALL_FORKID,
    .predicate = sighashPredicateBrendan136,
    .grind_surface = .nlocktime,
};

/// Canonical registry. PR-9b will eventually move policies into
/// substrate cells (cellType name TBD; NOT
/// `bsv.tx.lock.recipe` because "recipe" is reserved for the
/// BRC-42 derivation concept) + bootstrap from this in-Zig set;
/// new policies added to cartridges by cell-mint rather than
/// kernel rebuild.
pub const REGISTRY = [_]*const SpendPolicy{
    &POLICY_V1_PUSHDROP,
    &POLICY_V1_FEE_COMPOSABLE,
    &POLICY_PUSHTX_136B,
};

// ── Lookup helpers ─────────────────────────────────────────────────────

/// Resolve a policy by its stable name. Linear scan — the registry
/// is small (3 entries today, single-digit growth expected). Returns
/// null when no policy matches.
pub fn lookupByName(name: []const u8) ?*const SpendPolicy {
    for (REGISTRY) |p| {
        if (std.mem.eql(u8, p.name, name)) return p;
    }
    return null;
}

// ── Inline tests ───────────────────────────────────────────────────────

const testing = std.testing;

test "PR-9 SIGHASH constants match BIP-143 wire-format values" {
    try testing.expectEqual(@as(u8, 0x41), SIGHASH_ALL_FORKID);
    try testing.expectEqual(@as(u8, 0xC3), SIGHASH_SINGLE_ANYONECANPAY_FORKID);
    try testing.expectEqual(@as(u8, 0xC2), SIGHASH_NONE_ANYONECANPAY_FORKID);
}

test "PR-9 sighashPredicatePermissive accepts every digest" {
    // The v1 PushDrop + OP_CHECKSIG policy imposes no structural
    // constraint on the sighash, so the predicate accepts every
    // 32-byte input. This is the contract the v1 mainnet-proven
    // policy relies on (PR-8b-x runbook).
    try testing.expect(sighashPredicatePermissive(&[_]u8{0} ** 32));
    try testing.expect(sighashPredicatePermissive(&[_]u8{0xFF} ** 32));
    var random_digest: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) random_digest[i] = @intCast(i * 7 ^ 0xA5);
    try testing.expect(sighashPredicatePermissive(&random_digest));
}

test "PR-9 sighashPredicateBrendan136 rejects the ffffffff tail collision" {
    var digest = [_]u8{0xAB} ** 32;
    try testing.expect(sighashPredicateBrendan136(&digest));

    // Flip the tail to the collision value.
    digest[28] = 0xFF;
    digest[29] = 0xFF;
    digest[30] = 0xFF;
    digest[31] = 0xFF;
    try testing.expect(!sighashPredicateBrendan136(&digest));

    // 3-of-4 ff isn't enough; predicate must accept.
    digest[28] = 0xFE;
    try testing.expect(sighashPredicateBrendan136(&digest));
}

test "PR-9 lookupByName resolves shipped policies" {
    try testing.expect(lookupByName("policy.mnca.anchor.v1.pushdrop") == &POLICY_V1_PUSHDROP);
    try testing.expect(lookupByName("policy.mnca.anchor.v1.pushdrop.fee-composable") == &POLICY_V1_FEE_COMPOSABLE);
    try testing.expect(lookupByName("policy.pushtx.brendan.136b") == &POLICY_PUSHTX_136B);
    try testing.expect(lookupByName("nope") == null);
}

test "PR-9 POLICY_V1_PUSHDROP matches the mainnet-proven shape" {
    // Pin the v1 policy's fields so a careless future change is
    // caught by tests. The mainnet txid 5d592c2647…d0b8589a was
    // produced with exactly this shape.
    try testing.expectEqualStrings("policy.mnca.anchor.v1.pushdrop", POLICY_V1_PUSHDROP.name);
    try testing.expectEqual(SIGHASH_ALL_FORKID, POLICY_V1_PUSHDROP.sighash_flags);
    try testing.expect(POLICY_V1_PUSHDROP.predicate == sighashPredicatePermissive);
    try testing.expectEqual(GrindSurface.nlocktime, POLICY_V1_PUSHDROP.grind_surface);
}

test "PR-9 POLICY_V1_FEE_COMPOSABLE differs from V1_PUSHDROP only in sighash_flags" {
    // The fee-composable variant shares the same on-chain lock
    // shape + permissive predicate as the base v1 PushDrop policy;
    // the only difference is the sighash flag byte (which is what
    // unlocks the wallet-side fee composition path).
    try testing.expectEqual(SIGHASH_SINGLE_ANYONECANPAY_FORKID, POLICY_V1_FEE_COMPOSABLE.sighash_flags);
    try testing.expect(POLICY_V1_FEE_COMPOSABLE.predicate == POLICY_V1_PUSHDROP.predicate);
    try testing.expectEqual(POLICY_V1_PUSHDROP.grind_surface, POLICY_V1_FEE_COMPOSABLE.grind_surface);
}

```
