---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/k15a_positive_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.194351+00:00
---

# runtime/semantos-brain/tests/k15a_positive_conformance.zig

```zig
//! Phase 1 (Wave Cap-Substrate follow-on) — K15a **positive** leg,
//! discharged against the real cell-engine `beef.verifyBeefSpv` driving
//! SW2's shipped `SpvCapabilityProvider`.
//!
//! Oracle: CapabilityUtxoK15.lean K15a (UTXO unspent ⟹ authorized).
//!
//! SW2-concrete proved K15a *fail-closed* (garbage BEEF ⇒ excluded).
//! The honest gap it left open (PRD §0.2): the *positive* leg — a
//! structurally-valid BEEF whose BUMP root is trusted ⇒ the cap IS in
//! the live set. This closes it WITHOUT live funding / Metanet / real
//! headers, using the insight that `verifyBeefSpv` runs structure under
//! a GullibleChainTracker and the real gate is matching each BUMP root
//! against **caller-supplied trusted_roots**. So a deterministic,
//! structurally-valid BEEF + its own computed BUMP root (passed as the
//! trusted root) is a complete, self-contained positive vector.
//!
//! The BEEF is the canonical BRC-62 example vector (the same
//! `go_brc62_hex` bsvz pins in its own round-trip tests) — a public,
//! standard test vector. We reuse the SAME bsvz BEEF/MerklePath API the
//! verifier is built on, so the trusted root we compute is exactly the
//! root `verifyBeefSpv` will compare against.

const std = @import("std");
const bsvz = @import("bsvz");
const ce_beef = @import("beef"); // cell-engine/src/beef.zig — verifyBeefSpv
const hat_registry = @import("hat_registry");
const spvv = @import("spv_cap_verifier");

/// Canonical BRC-62 BEEF example (1 BUMP, 2 txs). Public standard
/// vector; identical to bsvz `transaction/beef.zig` `go_brc62_hex`.
const BRC62_HEX =
    "0100beef01fe636d0c0007021400fe507c0c7aa754cef1f7889d5fd395cf1f785dd7de98eed895dbedfe4e5bc70d1502ac4e164f5bc16746bb0868404292ac8318bbac3800e4aad13a014da427adce3e010b00bc4ff395efd11719b277694cface5aa50d085a0bb81f613f70313acd28cf4557010400574b2d9142b8d28b61d88e3b2c3f44d858411356b49a28a4643b6d1a6a092a5201030051a05fc84d531b5d250c23f4f886f6812f9fe3f402d61607f977b4ecd2701c19010000fd781529d58fc2523cf396a7f25440b409857e7e221766c57214b1d38c7b481f01010062f542f45ea3660f86c013ced80534cb5fd4c19d66c56e7e8c5d4bf2d40acc5e010100b121e91836fd7cd5102b654e9f72f3cf6fdbfd0b161c53a9c54b12c841126331020100000001cd4e4cac3c7b56920d1e7655e7e260d31f29d9a388d04910f1bbd72304a79029010000006b483045022100e75279a205a547c445719420aa3138bf14743e3f42618e5f86a19bde14bb95f7022064777d34776b05d816daf1699493fcdf2ef5a5ab1ad710d9c97bfb5b8f7cef3641210263e2dee22b1ddc5e11f6fab8bcd2378bdd19580d640501ea956ec0e786f93e76ffffffff013e660000000000001976a9146bfd5c7fbe21529d45803dbcf0c87dd3c71efbc288ac0000000001000100000001ac4e164f5bc16746bb0868404292ac8318bbac3800e4aad13a014da427adce3e000000006a47304402203a61a2e931612b4bda08d541cfb980885173b8dcf64a3471238ae7abcd368d6402204cbf24f04b9aa2256d8901f0ed97866603d2be8324c2bfb7a37bf8fc90edd5b441210263e2dee22b1ddc5e11f6fab8bcd2378bdd19580d640501ea956ec0e786f93e76ffffffff013c660000000000001976a9146bfd5c7fbe21529d45803dbcf0c87dd3c71efbc288ac0000000000";

const DOMAIN: u32 = 0x000101; // oddjobz page

const Vec = struct {
    raw: []u8, // BEEF bytes (caller-owned; outlives verify calls)
    txid: [32]u8, // the MINED (BUMP-covered) txid
    root: [32]u8, // its computed BUMP merkle root (the trusted root)
};

/// Decode the BRC-62 vector, find the MINED txid (the tx a BUMP
/// covers — not the unmined subject), and compute its BUMP root
/// exactly as `verifyBeefSpv` will, so the two agree by construction.
fn loadVector(alloc: std.mem.Allocator) !Vec {
    const raw = try bsvz.primitives.hex.decode(alloc, BRC62_HEX);
    errdefer alloc.free(raw);

    var beef = try bsvz.transaction.beef.newBeefFromBytes(alloc, raw);
    defer beef.deinit();

    // The mined tx = the one whose hash a BUMP path covers.
    var it = beef.transactions.keyIterator();
    const mined: bsvz.primitives.chainhash.Hash = blk: {
        while (it.next()) |k| {
            if (beef.findBumpByHash(k.*) != null) break :blk k.*;
        }
        return error.NoMinedTxInBeef;
    };
    const bump = beef.findBumpByHash(mined).?;
    const root = try bump.computeRoot(alloc, bsvz.crypto.Hash256{ .bytes = mined.bytes });

    return .{ .raw = raw, .txid = mined.bytes, .root = root.bytes };
}

test "K15a-positive: real beef.verifyBeefSpv ⇒ true for a valid BEEF under its trusted root" {
    const a = std.testing.allocator;
    const v = try loadVector(a);
    defer a.free(v.raw);

    const trusted = [_][32]u8{v.root};
    const ok = try ce_beef.verifyBeefSpv(a, v.raw, v.txid, &trusted);
    try std.testing.expect(ok); // POSITIVE leg — the gap SW2-concrete left open
}

test "K15a-negative control: same valid BEEF, WRONG trusted root ⇒ false (not error)" {
    const a = std.testing.allocator;
    const v = try loadVector(a);
    defer a.free(v.raw);

    const wrong = [_][32]u8{[_]u8{0xAB} ** 32};
    const ok = try ce_beef.verifyBeefSpv(a, v.raw, v.txid, &wrong);
    try std.testing.expect(!ok); // root mismatch ⇒ false, fail-closed
}

test "K15a-positive end-to-end: cap LANDS in SpvCapabilityProvider set via concrete verifier" {
    const a = std.testing.allocator;
    const v = try loadVector(a);
    defer a.free(v.raw);

    const Combined = struct {
        cap: [1]hat_registry.CapUtxo,
        vctx: spvv.Context,
        fn candFn(ctx: *anyopaque, domain_flag: u32) []const hat_registry.CapUtxo {
            const s: *@This() = @ptrCast(@alignCast(ctx));
            return if (domain_flag == DOMAIN) s.cap[0..] else &[_]hat_registry.CapUtxo{};
        }
        fn verFn(ctx: *anyopaque, b: []const u8, txid: [32]u8) bool {
            const s: *@This() = @ptrCast(@alignCast(ctx));
            return spvv.verify(@ptrCast(&s.vctx), b, txid);
        }
        fn neverSpent(_: *anyopaque, _: [32]u8, _: u32) bool {
            return false;
        }
    };
    var trusted = [_][32]u8{v.root};
    var combined = Combined{
        .cap = .{.{
            .txid = v.txid,
            .vout = 0,
            .cap_name = "cap.oddjobz.read_jobs",
            .beef = v.raw,
        }},
        .vctx = .{ .allocator = a, .trusted_roots = trusted[0..] },
    };
    var spvp = hat_registry.SpvCapabilityProvider{
        .user_ctx = @ptrCast(&combined),
        .candidates = Combined.candFn,
        .verify = Combined.verFn,
        .spent = Combined.neverSpent,
    };
    var reg = hat_registry.HatRegistry.initWithProvider(a, spvp.provider());
    defer reg.deinit();
    try reg.addHat(DOMAIN, "oddjobz.local");

    const caps = try reg.getCapabilities(a, DOMAIN);
    defer a.free(caps);
    // K15a POSITIVE end-to-end: unspent + SPV-proven ⇒ cap in the set.
    try std.testing.expectEqual(@as(usize, 1), caps.len);
    try std.testing.expectEqualStrings("cap.oddjobz.read_jobs", caps[0]);
}

```
