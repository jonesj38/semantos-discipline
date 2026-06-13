---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/spend_recipe.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.233830+00:00
---

# runtime/semantos-brain/src/spend_recipe.zig

```zig
// PR-9 — `bsv.tx.lock.recipe` substrate cell-type foundation.
//
// A SpendRecipe is the declarative contract between the brain's
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
// `recipe: *const SpendRecipe` field. Cartridges (or future
// recipe-substrate cells) declare which recipe a transition uses;
// the brain dispatches accordingly. Adding a new on-chain
// enforcement contract (Brendan Lee's 110-byte OP_PUSH_TX, the
// 82-byte PUSHTX_BIT_SHIFT, etc.) becomes a 1-recipe-entry change
// in this file rather than a per-cartridge kernel diff.
//
// Reference: LOCKSCRIPT-CLEAVAGE.md §3.5 (the Context construction
// seam is a dispatcher concern) + 2026-06-02 Brendan Lee
// conversation (architectural shift to brain-as-constraint-
// satisfier, captured in PR-8b-xi's grind loop + this PR's recipe
// dispatcher).
//
// Future PR-9b: introduce a `bsv.tx.lock.recipe` substrate cell
// type that wraps a SpendRecipe in a 1024-byte cell. Cartridges
// then reference recipes by cell-hash rather than by name; the
// recipe set becomes mint-time discoverable + versionable. The
// in-Zig REGISTRY this PR ships becomes the bootstrap set for
// canonical recipes; new recipes are minted as cells and shipped
// alongside cartridges.

const std = @import("std");

// ── BIP-143 sighash flag combinations ─────────────────────────────────
//
// `SIGHASH_ALL_FORKID` (0x41) — the v1 mainnet recipe. Commits to
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
// can share recipe definitions without circular imports).
//
// `digest` is the 32-byte BIP-143 (or OTDA) sighash output. Returns
// true if the digest satisfies the recipe's on-chain validity
// constraint, false to keep grinding. Stateless + side-effect-free
// so the grind loop's invariants are obvious.

pub const SighashPredicate = *const fn (digest: *const [32]u8) bool;

/// Permissive predicate — accepts every 32-byte input.
/// Used by recipes whose on-chain script (e.g. a plain
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
/// can reference the recipe by name.
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
//   - `nlocktime_plus_lock_nonce`: brain ALSO injects a recipe-
//     local `PUSH <nonce> OP_DROP` prefix into the successor
//     PushDrop lock script — changes `hashOutputs` without
//     disturbing the cell-graph semantic commitment. Cleaner for
//     cartridges where nLockTime carries semantic meaning. Wired
//     in PR-9b alongside the OP_PUSH_TX recipe bytes.

pub const GrindSurface = enum {
    nlocktime,
    nlocktime_plus_lock_nonce,
};

// ── SpendRecipe struct ─────────────────────────────────────────────────

/// Declarative contract for a single on-chain enforcement shape.
/// Cartridges (or future recipe-substrate cells) reference a recipe
/// to declare how the brain should construct the BIP-143 sighash +
/// what predicate to grind to + what flag the wallet should use.
pub const SpendRecipe = struct {
    /// Stable name for cartridge authors + ops. Used as the input
    /// to recipe_id derivation: recipe_id = SHA256(name) — written
    /// into the bsv.tx.sign.request cell's recipe_id field at
    /// offset 33 so the wallet/assembler can resolve the unlock
    /// template without round-tripping back to the brain.
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
    /// a recipe-local grind nonce into the successor PushDrop.
    grind_surface: GrindSurface = .nlocktime,
};

// ── Recipe registry ────────────────────────────────────────────────────

/// V1 PushDrop + OP_CHECKSIG recipe — the mainnet-proven shape the
/// PR-8b-x runbook documents. Used by every MNCA anchor transition
/// from PR-8b-vi-2 through today. SIGHASH_ALL means the wallet can
/// NOT compose with fee inputs; this recipe is for the zero-fee
/// broadcast path (WhatsOnChain) the runbook walk produced
/// [transition txid 5d592c2647…d0b8589a](https://whatsonchain.com/tx/5d592c2647fc96cbeddb37aff43daa9406efb43e1879b4ece3a4aa61d0b8589a)
/// against.
pub const RECIPE_V1_PUSHDROP = SpendRecipe{
    .name = "recipe.mnca.anchor.v1.pushdrop",
    .sighash_flags = SIGHASH_ALL_FORKID,
    .predicate = sighashPredicatePermissive,
    .grind_surface = .nlocktime,
};

/// V1 PushDrop fee-composable variant — same lock-script shape,
/// different sighash flag. SIGHASH_SINGLE+ANYONECANPAY lets a
/// wallet add a fee-paying secondary input (signed with
/// SIGHASH_NONE+ANYONECANPAY) without invalidating this primary
/// signature. PR-8b-xii-b's TS composer will use this recipe to
/// unblock ARC/Taal broadcast. The on-chain lock is identical to
/// V1_PUSHDROP so existing PushDrop-aware wallets don't need any
/// lock-template change — only the sighash flag they sign over.
pub const RECIPE_V1_FEE_COMPOSABLE = SpendRecipe{
    .name = "recipe.mnca.anchor.v1.pushdrop.fee-composable",
    .sighash_flags = SIGHASH_SINGLE_ANYONECANPAY_FORKID,
    .predicate = sighashPredicatePermissive,
    .grind_surface = .nlocktime,
};

/// Brendan Lee 136-byte OP_PUSH_TX recipe — placeholder for the
/// validated construction (bytes pending verification). The
/// predicate matches the cost profile in the PR-8b-x runbook's
/// grind-surface taxonomy (1-in-2^32 retry rate; mean 1 attempt).
/// Lock-template bytes + assembler integration land in PR-9b once
/// Brendan's bytes are validated. Until then this recipe exercises
/// the grind seam in tests + documents the shape.
pub const RECIPE_PUSHTX_136B = SpendRecipe{
    .name = "recipe.pushtx.brendan.136b",
    .sighash_flags = SIGHASH_ALL_FORKID,
    .predicate = sighashPredicateBrendan136,
    .grind_surface = .nlocktime,
};

/// Canonical registry. PR-9b will move recipes into substrate
/// cells (`bsv.tx.lock.recipe` cellType) + bootstrap from this
/// in-Zig set; new recipes added to cartridges by cell-mint
/// rather than kernel rebuild.
pub const REGISTRY = [_]*const SpendRecipe{
    &RECIPE_V1_PUSHDROP,
    &RECIPE_V1_FEE_COMPOSABLE,
    &RECIPE_PUSHTX_136B,
};

// ── Lookup helpers ─────────────────────────────────────────────────────

/// Resolve a recipe by its stable name. Linear scan — the registry
/// is small (3 entries today, single-digit growth expected). Returns
/// null when no recipe matches.
pub fn lookupByName(name: []const u8) ?*const SpendRecipe {
    for (REGISTRY) |r| {
        if (std.mem.eql(u8, r.name, name)) return r;
    }
    return null;
}

/// Resolve a recipe by its 32-byte id (= SHA256(name)). Used by
/// the wallet/assembler when reading the recipe_id field out of a
/// bsv.tx.sign.request cell's payload. Linear scan.
pub fn lookupById(id: [32]u8) ?*const SpendRecipe {
    for (REGISTRY) |r| {
        if (std.mem.eql(u8, &recipeIdFromName(r.name), &id)) return r;
    }
    return null;
}

/// Derive a recipe's 32-byte id from its name. recipe_id =
/// SHA256(name) — content-addressable, collision-resistant for
/// distinct names. The brain's Context builder writes this into
/// the bsv.tx.sign.request payload at offset 33 so downstream
/// consumers (wallet, assembler, broker) can resolve the recipe
/// without round-tripping back to the brain.
pub fn recipeIdFromName(name: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(name, &out, .{});
    return out;
}

// ── Inline tests ───────────────────────────────────────────────────────

const testing = std.testing;

test "PR-9 SIGHASH constants match BIP-143 wire-format values" {
    try testing.expectEqual(@as(u8, 0x41), SIGHASH_ALL_FORKID);
    try testing.expectEqual(@as(u8, 0xC3), SIGHASH_SINGLE_ANYONECANPAY_FORKID);
    try testing.expectEqual(@as(u8, 0xC2), SIGHASH_NONE_ANYONECANPAY_FORKID);
}

test "PR-9 sighashPredicatePermissive accepts every digest" {
    // The v1 PushDrop + OP_CHECKSIG recipe imposes no structural
    // constraint on the sighash, so the predicate accepts every
    // 32-byte input. This is the contract the v1 mainnet-proven
    // recipe relies on (PR-8b-x runbook).
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

test "PR-9 lookupByName resolves shipped recipes" {
    try testing.expect(lookupByName("recipe.mnca.anchor.v1.pushdrop") == &RECIPE_V1_PUSHDROP);
    try testing.expect(lookupByName("recipe.mnca.anchor.v1.pushdrop.fee-composable") == &RECIPE_V1_FEE_COMPOSABLE);
    try testing.expect(lookupByName("recipe.pushtx.brendan.136b") == &RECIPE_PUSHTX_136B);
    try testing.expect(lookupByName("nope") == null);
}

test "PR-9 recipeIdFromName is deterministic + unique per name" {
    const id_a = recipeIdFromName("recipe.mnca.anchor.v1.pushdrop");
    const id_b = recipeIdFromName("recipe.mnca.anchor.v1.pushdrop");
    const id_c = recipeIdFromName("recipe.mnca.anchor.v1.pushdrop.fee-composable");

    // Deterministic.
    try testing.expectEqualSlices(u8, &id_a, &id_b);

    // Unique per name.
    try testing.expect(!std.mem.eql(u8, &id_a, &id_c));

    // 32 bytes (sha256 output size).
    try testing.expectEqual(@as(usize, 32), id_a.len);
}

test "PR-9 lookupById round-trips through recipeIdFromName" {
    const id = recipeIdFromName(RECIPE_V1_PUSHDROP.name);
    try testing.expect(lookupById(id) == &RECIPE_V1_PUSHDROP);

    const id_c = recipeIdFromName(RECIPE_V1_FEE_COMPOSABLE.name);
    try testing.expect(lookupById(id_c) == &RECIPE_V1_FEE_COMPOSABLE);

    // Unknown id → null.
    try testing.expect(lookupById([_]u8{0xDE} ** 32) == null);
}

test "PR-9 RECIPE_V1_PUSHDROP matches the mainnet-proven shape" {
    // Pin the v1 recipe's fields so a careless future change is
    // caught by tests. The mainnet txid 5d592c2647…d0b8589a was
    // produced with exactly this shape.
    try testing.expectEqualStrings("recipe.mnca.anchor.v1.pushdrop", RECIPE_V1_PUSHDROP.name);
    try testing.expectEqual(SIGHASH_ALL_FORKID, RECIPE_V1_PUSHDROP.sighash_flags);
    try testing.expect(RECIPE_V1_PUSHDROP.predicate == sighashPredicatePermissive);
    try testing.expectEqual(GrindSurface.nlocktime, RECIPE_V1_PUSHDROP.grind_surface);
}

test "PR-9 RECIPE_V1_FEE_COMPOSABLE differs from V1_PUSHDROP only in sighash_flags" {
    // The fee-composable variant shares the same on-chain lock
    // shape + permissive predicate as the base v1 PushDrop recipe;
    // the only difference is the sighash flag byte (which is what
    // unlocks the wallet-side fee composition path).
    try testing.expectEqual(SIGHASH_SINGLE_ANYONECANPAY_FORKID, RECIPE_V1_FEE_COMPOSABLE.sighash_flags);
    try testing.expect(RECIPE_V1_FEE_COMPOSABLE.predicate == RECIPE_V1_PUSHDROP.predicate);
    try testing.expectEqual(RECIPE_V1_PUSHDROP.grind_surface, RECIPE_V1_FEE_COMPOSABLE.grind_surface);
}

```
