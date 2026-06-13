---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/spv_cap_concrete_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.174929+00:00
---

# runtime/semantos-brain/tests/spv_cap_concrete_conformance.zig

```zig
//! SW2-concrete (Wave Cap-Substrate follow-on) — K15a/K15b discharged
//! against the CONCRETE SPV verifier driving the shipped
//! SpvCapabilityProvider.
//!
//! Oracle: CapabilityUtxoK15.lean K15a (UTXO unspent ⟹ authorized,
//! fail-closed when unproven) + K15b (spent ⟹ excluded).
//!
//! Distinction from SW2's existing suite: SW2 proved the set logic
//! against a *stub* verify fn (the W2 pattern). Here every call routes
//! through `spv_cap_verifier.verify` → the REAL
//! `core/cell-engine/src/beef.zig` `verifyBeefSpv` (indexer-less
//! BEEF/BUMP, trusted roots). This is the wiring PRD §4/§5.6 require
//! before TS bearer-path retirement.
//!
//! HONEST BOUNDARY (PRD §0.2 — stated, not hidden): the **K15a
//! fail-closed** leg (unproven/garbage BEEF ⟹ cap excluded) and
//! **K15b** (spent ⟹ excluded) are discharged here against the real
//! verifier. The **K15a positive** leg (a structurally-valid BEEF whose
//! BUMP root is trusted ⟹ cap IN the set) needs a real on-chain-shaped
//! BEEF fixture, which does not exist in-repo; it is NOT asserted here
//! and NOT claimed proven. Bearer retirement stays gated on that
//! positive proof (see the SW2-concrete commit/status).

const std = @import("std");
const hat_registry = @import("hat_registry");
const spvv = @import("spv_cap_verifier");

const DOMAIN: u32 = 0x000101; // oddjobz page

fn mkTxid(b: u8) [32]u8 {
    return [_]u8{b} ** 32;
}

/// Candidate source: two cap UTXOs on DOMAIN, each carrying a
/// (deliberately invalid) BEEF envelope so the REAL verifier exercises
/// its parse/error path and fails closed.
const Cands = struct {
    items: [2]hat_registry.CapUtxo,

    fn init() Cands {
        return .{ .items = .{
            .{ .txid = mkTxid(0x11), .vout = 0, .cap_name = "cap.oddjobz.read_jobs", .beef = "garbage-beef-bytes" },
            .{ .txid = mkTxid(0x22), .vout = 1, .cap_name = "cap.oddjobz.write_jobs", .beef = &[_]u8{} },
        } };
    }
    fn candidatesFn(ctx: *anyopaque, domain_flag: u32) []const hat_registry.CapUtxo {
        const self: *Cands = @ptrCast(@alignCast(ctx));
        return if (domain_flag == DOMAIN) self.items[0..] else &[_]hat_registry.CapUtxo{};
    }
};

fn neverSpent(_: *anyopaque, _: [32]u8, _: u32) bool {
    return false;
}
fn alwaysSpent(_: *anyopaque, _: [32]u8, _: u32) bool {
    return true;
}

test "SW2-concrete K15a fail-closed: real beef.verifyBeefSpv on garbage ⇒ false" {
    const cands = Cands.init();
    var vctx = spvv.Context{
        .allocator = std.testing.allocator,
        .trusted_roots = &[_][32]u8{},
    };
    // Drive the concrete verifier exactly as SW2's provider does: the
    // REAL beef.verifyBeefSpv runs its parse/error path and must fail
    // closed (K15a: unproven ⇒ excluded, never assume unspent).
    for (cands.items) |c| {
        try std.testing.expect(!spvv.verify(@ptrCast(&vctx), c.beef, c.txid));
    }
}

test "SW2-concrete: SpvCapabilityProvider with concrete verifier ⇒ empty set (fail-closed)" {
    const Combined = struct {
        cands: Cands,
        vctx: spvv.Context,
        fn candFn(ctx: *anyopaque, domain_flag: u32) []const hat_registry.CapUtxo {
            const s: *@This() = @ptrCast(@alignCast(ctx));
            return if (domain_flag == DOMAIN) s.cands.items[0..] else &[_]hat_registry.CapUtxo{};
        }
        fn verFn(ctx: *anyopaque, b: []const u8, txid: [32]u8) bool {
            const s: *@This() = @ptrCast(@alignCast(ctx));
            // Route the provider's single user_ctx into the concrete
            // verifier's Context (real beef.verifyBeefSpv).
            return spvv.verify(@ptrCast(&s.vctx), b, txid);
        }
    };
    var combined = Combined{
        .cands = Cands.init(),
        .vctx = .{ .allocator = std.testing.allocator, .trusted_roots = &[_][32]u8{} },
    };
    var spvp = hat_registry.SpvCapabilityProvider{
        .user_ctx = @ptrCast(&combined),
        .candidates = Combined.candFn,
        .verify = Combined.verFn,
        .spent = neverSpent,
    };
    var reg = hat_registry.HatRegistry.initWithProvider(std.testing.allocator, spvp.provider());
    defer reg.deinit();
    try reg.addHat(DOMAIN, "oddjobz.local");

    const caps = try reg.getCapabilities(std.testing.allocator, DOMAIN);
    defer std.testing.allocator.free(caps);
    // K15a fail-closed: both candidates have unprovable BEEF ⇒ real
    // verifier excludes both ⇒ empty live set.
    try std.testing.expectEqual(@as(usize, 0), caps.len);
}

test "SW2-concrete K15b: spent ⇒ excluded even before SPV (monotone, real verifier present)" {
    const Combined = struct {
        cands: Cands,
        vctx: spvv.Context,
        fn candFn(ctx: *anyopaque, domain_flag: u32) []const hat_registry.CapUtxo {
            const s: *@This() = @ptrCast(@alignCast(ctx));
            return if (domain_flag == DOMAIN) s.cands.items[0..] else &[_]hat_registry.CapUtxo{};
        }
        fn verFn(ctx: *anyopaque, b: []const u8, txid: [32]u8) bool {
            const s: *@This() = @ptrCast(@alignCast(ctx));
            return spvv.verify(@ptrCast(&s.vctx), b, txid);
        }
    };
    var combined = Combined{
        .cands = Cands.init(),
        .vctx = .{ .allocator = std.testing.allocator, .trusted_roots = &[_][32]u8{} },
    };
    var spvp = hat_registry.SpvCapabilityProvider{
        .user_ctx = @ptrCast(&combined),
        .candidates = Combined.candFn,
        .verify = Combined.verFn,
        .spent = alwaysSpent, // K15b
    };
    var reg = hat_registry.HatRegistry.initWithProvider(std.testing.allocator, spvp.provider());
    defer reg.deinit();
    try reg.addHat(DOMAIN, "oddjobz.local");
    const caps = try reg.getCapabilities(std.testing.allocator, DOMAIN);
    defer std.testing.allocator.free(caps);
    try std.testing.expectEqual(@as(usize, 0), caps.len); // spent ⇒ excluded
}

```
