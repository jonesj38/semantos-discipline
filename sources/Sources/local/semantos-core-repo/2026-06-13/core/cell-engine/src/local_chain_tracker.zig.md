---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/local_chain_tracker.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.981797+00:00
---

# core/cell-engine/src/local_chain_tracker.zig

```zig
// Phase WH5 — Trustless SPV: bsvz chain-tracker backed by the local
// HeaderStore.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH5).
//
// `bsvz.spv.MerklePath.verify` accepts an `anytype` chain_tracker with a
// single method:
//
//     pub fn isValidRootForHeight(
//         self: @This(),
//         root: bsvz.crypto.Hash256,
//         height: u32,
//     ) !bool
//
// This module ships `LocalHeaderChainTracker`, a tracker that resolves the
// claim "merkle_root R is valid at height H" by looking up the local
// PoW-validated header at H and comparing R against `header.merkle_root`.
//
// The result: a BEEF whose merkle path computes to R passes only if the
// wallet has independently verified that the block at height H actually
// contains R as its merkle root — verification grounded in code we ran, not
// in any external indexer's claim.
//
// Three modes mirror the spec's `policy.spv_mode`:
//
//   • .strict  — header at H must be in the store. Missing → reject (error).
//                Default for wallets where the user has opted in to bulk
//                sync; eliminates indexer trust completely.
//
//   • .hybrid  — header at H may be missing locally; tracker returns false
//                (rather than failing). Caller may then do a single-header
//                lazy fetch via the WH3 fetcher and re-attempt. The mobile-
//                friendly default — never blocks BEEF validation behind a
//                35MB initial sync.
//
//   • .gullible — DEBUG ONLY. Always returns true. Kept for v0.4 escape-hatch
//                 testing (parallel to bsvz.spv.GullibleChainTracker). Gated
//                 behind a build-flag in production.
//
// **The wallet's job is to filter every BEEF validation through one of
// strict or hybrid.** Gullible exists only to let test fixtures produced
// pre-WH still parse against BEEF tests that don't carry real chain data.

const std = @import("std");
const headers_mod = @import("headers");
const header_store_mod = @import("header_store");

pub const SpvMode = enum {
    strict,
    hybrid,
    gullible,
};

pub const TrackerError = error{
    header_missing,
    /// The header at the queried height *was* present in the store but its
    /// merkle_root field doesn't match the BEEF's computed root — the BEEF
    /// is bogus or the wrong (orphan) header was stored.
    merkle_root_mismatch,
};

/// Chain tracker compatible with bsvz's `verifyBeef` / `MerklePath.verify`
/// `chain_tracker: anytype` parameter.  Holds a reference to the wallet's
/// HeaderStore plus a SPV-mode flag.
///
/// Construction:
///
///     var tracker = LocalHeaderChainTracker{
///         .store = &header_store,
///         .mode = .strict,
///     };
///     const ok = try bsvz.spv.verifyBeef(
///         allocator, &beef, root_txid, tracker, null,
///     );
pub const LocalHeaderChainTracker = struct {
    store: *const header_store_mod.HeaderStore,
    mode: SpvMode = .hybrid,

    /// bsvz contract — return whether `root` is the canonical merkle root
    /// for the block at `height`. The "canonical" answer comes from the
    /// local PoW-validated chain.
    pub fn isValidRootForHeight(
        self: LocalHeaderChainTracker,
        root: anytype, // bsvz.crypto.Hash256, taken as anytype to avoid the bsvz dep here
        height: u32,
    ) !bool {
        if (self.mode == .gullible) return true;

        const rec = self.store.getByHeight(height) orelse {
            // Strict refuses; hybrid signals "unknown" to the caller via
            // `false`. Both approaches preserve the trustlessness property:
            // we never claim a root is valid based on something we haven't
            // verified locally.
            switch (self.mode) {
                .strict => return error.header_missing,
                .hybrid => return false,
                .gullible => unreachable,
            }
        };

        // Compare bsvz's Hash256.bytes against the header's merkle_root field
        // (both are 32 bytes, internal byte order).
        const root_bytes: *const [32]u8 = &@field(root, "bytes");
        return std.mem.eql(u8, root_bytes, &rec.header.merkle_root);
    }
};

// ──────────────────────────────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────────────────────────────

const FakeHash = struct { bytes: [32]u8 };

fn buildHeaderWithMerkle(merkle: [32]u8, ts: u32) headers_mod.Header {
    return .{
        .version = 1,
        .prev_hash = [_]u8{0} ** 32,
        .merkle_root = merkle,
        .timestamp = ts,
        .bits = headers_mod.REGTEST_BITS,
        .nonce = 0,
    };
}

test "WH5: strict mode returns true when local merkle matches" {
    var ls = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer ls.deinit();
    const store = ls.store();

    const merkle: [32]u8 = [_]u8{0xab} ** 32;
    var h = buildHeaderWithMerkle(merkle, 1_700_000_000);
    // Loose-mine.
    var n: u32 = 0;
    while (n < 200_000) : (n += 1) {
        h.nonce = n;
        if (h.satisfiesProofOfWork()) break;
    }
    try store.appendValidated(h, 0);

    const tracker = LocalHeaderChainTracker{ .store = &store, .mode = .strict };
    const ok = try tracker.isValidRootForHeight(FakeHash{ .bytes = merkle }, 0);
    try std.testing.expect(ok);
}

test "WH5: strict mode rejects mismatched merkle" {
    var ls = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer ls.deinit();
    const store = ls.store();

    const merkle: [32]u8 = [_]u8{0xab} ** 32;
    var h = buildHeaderWithMerkle(merkle, 1_700_000_000);
    var n: u32 = 0;
    while (n < 200_000) : (n += 1) {
        h.nonce = n;
        if (h.satisfiesProofOfWork()) break;
    }
    try store.appendValidated(h, 0);

    const tracker = LocalHeaderChainTracker{ .store = &store, .mode = .strict };
    const fake: [32]u8 = [_]u8{0xcd} ** 32;
    const ok = try tracker.isValidRootForHeight(FakeHash{ .bytes = fake }, 0);
    try std.testing.expect(!ok);
}

test "WH5: strict mode errors on missing height" {
    var ls = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer ls.deinit();
    const store = ls.store();

    const tracker = LocalHeaderChainTracker{ .store = &store, .mode = .strict };
    const dummy: [32]u8 = [_]u8{0xff} ** 32;
    try std.testing.expectError(
        error.header_missing,
        tracker.isValidRootForHeight(FakeHash{ .bytes = dummy }, 5),
    );
}

test "WH5: hybrid mode returns false on missing height (no error)" {
    var ls = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer ls.deinit();
    const store = ls.store();

    const tracker = LocalHeaderChainTracker{ .store = &store, .mode = .hybrid };
    const dummy: [32]u8 = [_]u8{0xff} ** 32;
    const ok = try tracker.isValidRootForHeight(FakeHash{ .bytes = dummy }, 5);
    try std.testing.expect(!ok);
}

test "WH5: gullible mode always returns true" {
    var ls = header_store_mod.LocalHeaderStore.init(std.testing.allocator);
    defer ls.deinit();
    const store = ls.store();

    const tracker = LocalHeaderChainTracker{ .store = &store, .mode = .gullible };
    const dummy: [32]u8 = [_]u8{0xff} ** 32;
    const ok = try tracker.isValidRootForHeight(FakeHash{ .bytes = dummy }, 5);
    try std.testing.expect(ok);
}

```
