---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/spv_cap_verifier.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.239320+00:00
---

# runtime/semantos-brain/src/spv_cap_verifier.zig

```zig
//! SW2-concrete (Wave Cap-Substrate follow-on) — the concrete SPV
//! verifier backing SW2's injected `SpvVerifyFn`.
//!
//! SW2 (hat_registry.zig `SpvCapabilityProvider`) takes the SPV check
//! as an injected `*const fn(ctx, beef, txid) bool` and proved K15a/b/c
//! against a stub (the W2 pattern). This module supplies the **real**
//! verifier — `core/cell-engine/src/beef.zig` `verifyBeefSpv`
//! (indexer-less BEEF/BUMP, caller-supplied trusted roots; no
//! third-party indexer, SPV-native per PRD §0.1) — so the production
//! provider runs the genuine SPV path. This is the wiring that, once
//! exercised end-to-end, permits TS bearer-path retirement (parent PRD
//! §4 / §5.6). "Proven but unwired" would fail PRD §0.2 — the
//! conformance suite drives this concrete verifier, not a stub.
//!
//! Fail-closed contract (K15a): ANY BEEF error (parse / txid-not-found
//! / invalid proof / untrusted root) ⇒ `false` ⇒ the candidate cap
//! UTXO is excluded from the live set. Unproven is never assumed
//! unspent.

const std = @import("std");
const beef = @import("beef");

/// Context threaded to the `SpvVerifyFn`. Owns the allocator used for
/// BEEF parsing + the caller-supplied trusted Merkle roots (BUMP roots
/// the operator trusts; no indexer is consulted).
pub const Context = struct {
    allocator: std.mem.Allocator,
    /// Trusted BUMP merkle roots. A BEEF proof is accepted only if
    /// every BUMP root matches one of these (beef.verifyBeefSpv §2).
    trusted_roots: []const [32]u8,
};

/// Concrete `SpvVerifyFn` (matches hat_registry.SpvVerifyFn shape):
/// true iff `beef_bytes` SPV-proves `txid` mined under a trusted root.
/// Fail-closed: every error path ⇒ false.
pub fn verify(ctx_any: *anyopaque, beef_bytes: []const u8, txid: [32]u8) bool {
    const ctx: *Context = @ptrCast(@alignCast(ctx_any));
    return beef.verifyBeefSpv(
        ctx.allocator,
        beef_bytes,
        txid,
        ctx.trusted_roots,
    ) catch return false; // K15a: unproven ⇒ excluded (never assume unspent)
}

// ─────────────────────────────────────────────────────────────────────
// Inline smoke — empty/garbage BEEF must fail closed (no panic, false).
// Full concrete-path K15a/b conformance lives in
// tests/spv_cap_concrete_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "spv_cap_verifier: garbage BEEF fails closed (false, no panic)" {
    var ctx = Context{
        .allocator = std.testing.allocator,
        .trusted_roots = &[_][32]u8{},
    };
    const txid = [_]u8{0xAB} ** 32;
    try std.testing.expect(!verify(@ptrCast(&ctx), "not-a-beef", txid));
    try std.testing.expect(!verify(@ptrCast(&ctx), &[_]u8{}, txid));
}

```
