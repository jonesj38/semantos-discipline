---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/output_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.976670+00:00
---

# core/cell-engine/src/output_store.zig

```zig
// WA2 — OutputStore: tracks UTXOs the wallet owns + their BEEF proofs.
//
// Reference: docs/design/WALLET-ACTIVE-USE-ROADMAP.md §2 / WA2 deliverable 1.
//
// When a peer sends the user a payment via BRC-100 `internalizeAction`, the
// wallet validates the BEEF, derives the leaf key per BRC-29, and persists
// the resulting UTXO + BEEF locally. Spending later resolves the BEEF, builds
// a tx, signs with the same derived key, and broadcasts.
//
// This module defines the interface (`OutputStore`) and ships a pure
// in-memory implementation (`LocalOutputStore`). The browser bundle and
// sovereign-node target install backing implementations under the same
// vtable:
//   • LocalOutputStore           — in-memory / IndexedDB / lmdb (v0.1, ships)
//   • PlexusOutputStore          — local + async mirror to Plexus (v0.2 stub)
//   • FederatedSemantosOutputStore — replicated across sovereign nodes (v0.3 stub)
//
// The vtable parallels `derivation_state.zig` so wiring is consistent across
// the wallet's pluggable storage layer.

const std = @import("std");

// ──────────────────────────────────────────────────────────────────────
// Outpoint / OutputStatus / OutputRecord
// ──────────────────────────────────────────────────────────────────────

/// 32-byte txid + 4-byte vout. Order matches the BSV wire format (big-endian
/// txid as displayed; little-endian internally — the wallet stores the
/// display form so JSON envelopes round-trip cleanly).
pub const Outpoint = struct {
    txid: [32]u8,
    vout: u32,

    pub fn eql(a: Outpoint, b: Outpoint) bool {
        if (a.vout != b.vout) return false;
        return std.mem.eql(u8, &a.txid, &b.txid);
    }
};

pub const OutputStatus = enum(u8) {
    /// UTXO is unspent and available for the wallet to spend.
    unspent = 0,
    /// UTXO has been spent — `spending_txid` is set on the record.
    spent = 1,
    /// UTXO was reorganized out (parent tx no longer in the longest chain)
    /// and should be hidden from listOutputs but kept until pruning.
    reorged = 2,
};

/// One UTXO the wallet owns. Mirrors the design schema in WALLET-ACTIVE-USE-
/// ROADMAP.md §2 / WA2 deliverable 1:
///   {outpoint, satoshis, locking_script, derived_key_hash,
///    derivation_context, beef, basket, tags, custom_instructions,
///    confirmations, status}
///
/// Variable-length fields (locking_script, beef, tags, custom_instructions,
/// basket) are stored as caller-allocated slices. The OutputStore impls take
/// ownership on `add_output` and free on `mark_spent`/`prune_confirmed`.
pub const OutputRecord = struct {
    outpoint: Outpoint,
    satoshis: u64,
    locking_script: []const u8,
    /// SHA-256 of the BRC-42 derived public key at this UTXO. Used as an
    /// index — listOutputs by derivation context can join via this hash
    /// without re-deriving every key.
    derived_key_hash: [32]u8,
    /// 16-byte protocol_hash || 33-byte counterparty pubkey, mirroring
    /// `derivation_state.Record.{protocol_hash, counterparty}` so the same
    /// (protocol_hash, counterparty) tuple resolves in both stores.
    derivation_protocol_hash: [16]u8,
    derivation_counterparty: [33]u8,
    /// BRC-42 monotonic index this output was derived at.
    derivation_index: u64,
    /// BEEF blob (BRC-62) covering the parent tx + its merkle proof, kept
    /// until `prune_confirmed` removes it after `min_confirmations >= 100`.
    /// Empty slice once pruned.
    beef: []const u8,
    /// Optional basket (BRC-46 inventory). Empty string = "default".
    basket: []const u8,
    /// Application tags (BRC-46). Stored as packed length-prefixed bytes:
    /// for each tag: u16_le tag_len || tag_bytes.
    tags: []const u8,
    /// Application-defined hints (BRC-100 customInstructions).
    custom_instructions: []const u8,
    /// Number of confirmations at last update. Drives pruning policy.
    confirmations: u32,
    status: OutputStatus,
    /// If status == .spent, the txid that consumed this output.
    spending_txid: [32]u8,
};

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    duplicate_outpoint,
    unknown_outpoint,
};

// ──────────────────────────────────────────────────────────────────────
// VTable
// ──────────────────────────────────────────────────────────────────────

pub const OutputStore = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Insert a fresh OutputRecord. Returns `duplicate_outpoint` if the
        /// outpoint already exists — internalizeAction is idempotent at the
        /// caller layer; the store enforces uniqueness for safety.
        add_output: *const fn (
            ctx: *anyopaque,
            record: OutputRecord,
        ) StoreError!void,

        /// List outputs filtered by basket (null = any) and tag-set
        /// (null = any). Caller owns the returned slice.
        list_outputs: *const fn (
            ctx: *anyopaque,
            basket_filter: ?[]const u8,
            tag_filter: ?[]const u8,
            allocator: std.mem.Allocator,
        ) StoreError![]OutputRecord,

        /// Look up by outpoint. Returns null if unknown.
        get_output: *const fn (
            ctx: *anyopaque,
            outpoint: Outpoint,
        ) ?OutputRecord,

        /// Mark an output spent — sets status=.spent, records spending_txid.
        /// Returns `unknown_outpoint` if the outpoint isn't tracked.
        mark_spent: *const fn (
            ctx: *anyopaque,
            outpoint: Outpoint,
            spending_txid: [32]u8,
        ) StoreError!void,

        /// Drop the BEEF blob from records with confirmations >= min_confirmations,
        /// and fully delete records with status == .spent and confirmations >=
        /// 1000. Returns the count of records pruned (BEEFs dropped or rows
        /// deleted). v0.1 ships the policy hard-coded in the impl; v0.2 wires
        /// thresholds to the policy cell.
        prune_confirmed: *const fn (
            ctx: *anyopaque,
            min_confirmations: u32,
        ) StoreError!u64,

        /// Dump every record. Used by recovery sync and federated mirroring.
        snapshot: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
        ) StoreError![]OutputRecord,

        /// Replace the store with a snapshot. Mirror of derivation_state's
        /// replay — does not merge.
        replay: *const fn (
            ctx: *anyopaque,
            records: []const OutputRecord,
        ) StoreError!void,
    };

    pub fn addOutput(self: *const OutputStore, record: OutputRecord) StoreError!void {
        return self.vtable.add_output(self.ctx, record);
    }

    pub fn listOutputs(
        self: *const OutputStore,
        basket_filter: ?[]const u8,
        tag_filter: ?[]const u8,
        allocator: std.mem.Allocator,
    ) StoreError![]OutputRecord {
        return self.vtable.list_outputs(self.ctx, basket_filter, tag_filter, allocator);
    }

    pub fn getOutput(self: *const OutputStore, outpoint: Outpoint) ?OutputRecord {
        return self.vtable.get_output(self.ctx, outpoint);
    }

    pub fn markSpent(
        self: *const OutputStore,
        outpoint: Outpoint,
        spending_txid: [32]u8,
    ) StoreError!void {
        return self.vtable.mark_spent(self.ctx, outpoint, spending_txid);
    }

    pub fn pruneConfirmed(
        self: *const OutputStore,
        min_confirmations: u32,
    ) StoreError!u64 {
        return self.vtable.prune_confirmed(self.ctx, min_confirmations);
    }

    pub fn snapshot(
        self: *const OutputStore,
        allocator: std.mem.Allocator,
    ) StoreError![]OutputRecord {
        return self.vtable.snapshot(self.ctx, allocator);
    }

    pub fn replay(
        self: *const OutputStore,
        records: []const OutputRecord,
    ) StoreError!void {
        return self.vtable.replay(self.ctx, records);
    }
};

// ──────────────────────────────────────────────────────────────────────
// LocalOutputStore — in-memory (native tests) / IndexedDB (browser).
//
// Native impl is keyed by Outpoint via 36-byte composite key. Browser impl
// lives in cartridges/wallet-headers/brain/src/output-store.ts and follows the same
// schema; the two share record layout via JSON wire format.
// ──────────────────────────────────────────────────────────────────────

pub const LocalOutputStore = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap(Key, OutputRecord),

    /// 36 bytes: txid(32) || vout_le_4. AutoHashMap is happy with fixed arrays.
    const Key = [36]u8;

    pub fn init(allocator: std.mem.Allocator) LocalOutputStore {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(Key, OutputRecord).init(allocator),
        };
    }

    pub fn deinit(self: *LocalOutputStore) void {
        // Free the variable-length slices on each record.
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.freeRecord(entry.value_ptr);
        }
        self.map.deinit();
    }

    pub fn store(self: *LocalOutputStore) OutputStore {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &local_vtable,
        };
    }

    fn keyFor(outpoint: Outpoint) Key {
        var k: Key = undefined;
        @memcpy(k[0..32], &outpoint.txid);
        std.mem.writeInt(u32, k[32..36], outpoint.vout, .little);
        return k;
    }

    fn freeRecord(self: *LocalOutputStore, r: *OutputRecord) void {
        self.allocator.free(r.locking_script);
        self.allocator.free(r.beef);
        self.allocator.free(r.basket);
        self.allocator.free(r.tags);
        self.allocator.free(r.custom_instructions);
    }

    fn copySlice(self: *LocalOutputStore, src: []const u8) StoreError![]const u8 {
        const dst = self.allocator.alloc(u8, src.len) catch return error.out_of_memory;
        @memcpy(dst, src);
        return dst;
    }

    fn cloneRecord(self: *LocalOutputStore, src: OutputRecord) StoreError!OutputRecord {
        return .{
            .outpoint = src.outpoint,
            .satoshis = src.satoshis,
            .locking_script = try self.copySlice(src.locking_script),
            .derived_key_hash = src.derived_key_hash,
            .derivation_protocol_hash = src.derivation_protocol_hash,
            .derivation_counterparty = src.derivation_counterparty,
            .derivation_index = src.derivation_index,
            .beef = try self.copySlice(src.beef),
            .basket = try self.copySlice(src.basket),
            .tags = try self.copySlice(src.tags),
            .custom_instructions = try self.copySlice(src.custom_instructions),
            .confirmations = src.confirmations,
            .status = src.status,
            .spending_txid = src.spending_txid,
        };
    }

    fn vAdd(ctx: *anyopaque, record: OutputRecord) StoreError!void {
        const self: *LocalOutputStore = @ptrCast(@alignCast(ctx));
        const k = keyFor(record.outpoint);
        if (self.map.contains(k)) return error.duplicate_outpoint;
        const owned = try self.cloneRecord(record);
        self.map.put(k, owned) catch return error.out_of_memory;
    }

    fn vList(
        ctx: *anyopaque,
        basket_filter: ?[]const u8,
        tag_filter: ?[]const u8,
        allocator: std.mem.Allocator,
    ) StoreError![]OutputRecord {
        const self: *LocalOutputStore = @ptrCast(@alignCast(ctx));
        var matching: std.ArrayList(OutputRecord) = .empty;
        defer matching.deinit(allocator);

        var it = self.map.valueIterator();
        while (it.next()) |entry| {
            if (entry.status != .unspent) continue;
            if (basket_filter) |b| {
                if (!std.mem.eql(u8, entry.basket, b)) continue;
            }
            if (tag_filter) |t| {
                // tags are length-prefixed packed bytes; t must appear as a
                // sub-slice that respects the length prefix.
                if (!hasTag(entry.tags, t)) continue;
            }
            matching.append(allocator, entry.*) catch return error.out_of_memory;
        }
        return matching.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    fn hasTag(packed_tags: []const u8, want: []const u8) bool {
        var i: usize = 0;
        while (i + 2 <= packed_tags.len) {
            const tag_len = std.mem.readInt(u16, packed_tags[i..][0..2], .little);
            i += 2;
            if (i + tag_len > packed_tags.len) return false;
            if (std.mem.eql(u8, packed_tags[i .. i + tag_len], want)) return true;
            i += tag_len;
        }
        return false;
    }

    fn vGet(ctx: *anyopaque, outpoint: Outpoint) ?OutputRecord {
        const self: *LocalOutputStore = @ptrCast(@alignCast(ctx));
        return self.map.get(keyFor(outpoint));
    }

    fn vMarkSpent(
        ctx: *anyopaque,
        outpoint: Outpoint,
        spending_txid: [32]u8,
    ) StoreError!void {
        const self: *LocalOutputStore = @ptrCast(@alignCast(ctx));
        const k = keyFor(outpoint);
        const entry = self.map.getPtr(k) orelse return error.unknown_outpoint;
        entry.status = .spent;
        entry.spending_txid = spending_txid;
    }

    fn vPrune(ctx: *anyopaque, min_confirmations: u32) StoreError!u64 {
        const self: *LocalOutputStore = @ptrCast(@alignCast(ctx));
        var pruned: u64 = 0;
        // Two-pass: first drop BEEFs, then delete fully-pruned spent rows.
        var it = self.map.valueIterator();
        while (it.next()) |entry| {
            if (entry.confirmations >= min_confirmations and entry.beef.len > 0) {
                self.allocator.free(entry.beef);
                entry.beef = &[_]u8{};
                pruned += 1;
            }
        }

        // Delete spent + heavily confirmed.
        var to_delete: std.ArrayList(Key) = .empty;
        defer to_delete.deinit(self.allocator);
        var it2 = self.map.iterator();
        while (it2.next()) |entry| {
            if (entry.value_ptr.status == .spent and entry.value_ptr.confirmations >= 1000) {
                to_delete.append(self.allocator, entry.key_ptr.*) catch return error.out_of_memory;
            }
        }
        for (to_delete.items) |k| {
            if (self.map.getPtr(k)) |r| self.freeRecord(r);
            _ = self.map.remove(k);
            pruned += 1;
        }
        return pruned;
    }

    fn vSnapshot(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
    ) StoreError![]OutputRecord {
        const self: *LocalOutputStore = @ptrCast(@alignCast(ctx));
        var out = allocator.alloc(OutputRecord, self.map.count()) catch return error.out_of_memory;
        var it = self.map.valueIterator();
        var i: usize = 0;
        while (it.next()) |entry| : (i += 1) out[i] = entry.*;
        return out;
    }

    fn vReplay(ctx: *anyopaque, records: []const OutputRecord) StoreError!void {
        const self: *LocalOutputStore = @ptrCast(@alignCast(ctx));
        // Free existing.
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.freeRecord(entry.value_ptr);
        }
        self.map.clearRetainingCapacity();
        for (records) |r| {
            const owned = try self.cloneRecord(r);
            self.map.put(keyFor(r.outpoint), owned) catch return error.out_of_memory;
        }
    }

    const local_vtable: OutputStore.VTable = .{
        .add_output = vAdd,
        .list_outputs = vList,
        .get_output = vGet,
        .mark_spent = vMarkSpent,
        .prune_confirmed = vPrune,
        .snapshot = vSnapshot,
        .replay = vReplay,
    };
};

// ──────────────────────────────────────────────────────────────────────
// Stubs for v0.2 / v0.3 — same vtable, mirror DerivationState pattern.
// ──────────────────────────────────────────────────────────────────────

/// v0.2 stub: PlexusOutputStore — local + paid mirror to a Plexus operator.
pub const PlexusOutputStore = struct {
    pub fn init() PlexusOutputStore {
        return .{};
    }
    pub fn store(_: *PlexusOutputStore) OutputStore {
        return .{ .ctx = undefined, .vtable = &stub_vtable };
    }
    fn errAdd(_: *anyopaque, _: OutputRecord) StoreError!void {
        return error.persistence_failed;
    }
    fn errList(
        _: *anyopaque,
        _: ?[]const u8,
        _: ?[]const u8,
        _: std.mem.Allocator,
    ) StoreError![]OutputRecord {
        return error.persistence_failed;
    }
    fn errGet(_: *anyopaque, _: Outpoint) ?OutputRecord {
        return null;
    }
    fn errMark(_: *anyopaque, _: Outpoint, _: [32]u8) StoreError!void {
        return error.persistence_failed;
    }
    fn errPrune(_: *anyopaque, _: u32) StoreError!u64 {
        return error.persistence_failed;
    }
    fn errSnapshot(_: *anyopaque, _: std.mem.Allocator) StoreError![]OutputRecord {
        return error.persistence_failed;
    }
    fn errReplay(_: *anyopaque, _: []const OutputRecord) StoreError!void {
        return error.persistence_failed;
    }
    const stub_vtable: OutputStore.VTable = .{
        .add_output = errAdd,
        .list_outputs = errList,
        .get_output = errGet,
        .mark_spent = errMark,
        .prune_confirmed = errPrune,
        .snapshot = errSnapshot,
        .replay = errReplay,
    };
};

/// v0.3 stub: FederatedSemantosOutputStore — replicated across the user's
/// own sovereign nodes. Same shape as PlexusOutputStore.
pub const FederatedSemantosOutputStore = struct {
    pub fn init() FederatedSemantosOutputStore {
        return .{};
    }
    pub fn store(_: *FederatedSemantosOutputStore) OutputStore {
        return .{ .ctx = undefined, .vtable = &stub_vtable };
    }
    fn errAdd(_: *anyopaque, _: OutputRecord) StoreError!void {
        return error.persistence_failed;
    }
    fn errList(
        _: *anyopaque,
        _: ?[]const u8,
        _: ?[]const u8,
        _: std.mem.Allocator,
    ) StoreError![]OutputRecord {
        return error.persistence_failed;
    }
    fn errGet(_: *anyopaque, _: Outpoint) ?OutputRecord {
        return null;
    }
    fn errMark(_: *anyopaque, _: Outpoint, _: [32]u8) StoreError!void {
        return error.persistence_failed;
    }
    fn errPrune(_: *anyopaque, _: u32) StoreError!u64 {
        return error.persistence_failed;
    }
    fn errSnapshot(_: *anyopaque, _: std.mem.Allocator) StoreError![]OutputRecord {
        return error.persistence_failed;
    }
    fn errReplay(_: *anyopaque, _: []const OutputRecord) StoreError!void {
        return error.persistence_failed;
    }
    const stub_vtable: OutputStore.VTable = .{
        .add_output = errAdd,
        .list_outputs = errList,
        .get_output = errGet,
        .mark_spent = errMark,
        .prune_confirmed = errPrune,
        .snapshot = errSnapshot,
        .replay = errReplay,
    };
};

// ──────────────────────────────────────────────────────────────────────
// Round-trip tests
// ──────────────────────────────────────────────────────────────────────

test "LocalOutputStore: add → get → mark spent → list filters" {
    const allocator = std.testing.allocator;
    var local = LocalOutputStore.init(allocator);
    defer local.deinit();
    const s = local.store();

    const op1 = Outpoint{
        .txid = [_]u8{1} ** 32,
        .vout = 0,
    };
    const rec1 = OutputRecord{
        .outpoint = op1,
        .satoshis = 50_000,
        .locking_script = &[_]u8{ 0x76, 0xa9, 0x14 },
        .derived_key_hash = [_]u8{2} ** 32,
        .derivation_protocol_hash = [_]u8{3} ** 16,
        .derivation_counterparty = [_]u8{4} ** 33,
        .derivation_index = 0,
        .beef = &[_]u8{ 0xef, 0xbe, 0x00, 0x01 },
        .basket = "default",
        .tags = &[_]u8{},
        .custom_instructions = &[_]u8{},
        .confirmations = 0,
        .status = .unspent,
        .spending_txid = [_]u8{0} ** 32,
    };

    try s.addOutput(rec1);

    // Duplicate insert is rejected.
    try std.testing.expectError(error.duplicate_outpoint, s.addOutput(rec1));

    // Get returns the record.
    const got = s.getOutput(op1);
    try std.testing.expect(got != null);
    try std.testing.expectEqual(@as(u64, 50_000), got.?.satoshis);

    // listOutputs returns the record (basket filter matches).
    const list1 = try s.listOutputs("default", null, allocator);
    defer allocator.free(list1);
    try std.testing.expectEqual(@as(usize, 1), list1.len);

    // Wrong basket → empty.
    const list2 = try s.listOutputs("incoming", null, allocator);
    defer allocator.free(list2);
    try std.testing.expectEqual(@as(usize, 0), list2.len);

    // Mark spent → list excludes.
    try s.markSpent(op1, [_]u8{0xaa} ** 32);
    const list3 = try s.listOutputs(null, null, allocator);
    defer allocator.free(list3);
    try std.testing.expectEqual(@as(usize, 0), list3.len);

    // Mark unknown → error.
    const op_unknown = Outpoint{ .txid = [_]u8{9} ** 32, .vout = 0 };
    try std.testing.expectError(error.unknown_outpoint, s.markSpent(op_unknown, [_]u8{0} ** 32));
}

test "LocalOutputStore: prune_confirmed drops BEEF over threshold" {
    const allocator = std.testing.allocator;
    var local = LocalOutputStore.init(allocator);
    defer local.deinit();
    const s = local.store();

    const rec_low = OutputRecord{
        .outpoint = .{ .txid = [_]u8{1} ** 32, .vout = 0 },
        .satoshis = 1000,
        .locking_script = &[_]u8{},
        .derived_key_hash = [_]u8{0} ** 32,
        .derivation_protocol_hash = [_]u8{0} ** 16,
        .derivation_counterparty = [_]u8{0} ** 33,
        .derivation_index = 0,
        .beef = &[_]u8{ 0x01, 0x02, 0x03, 0x04 },
        .basket = "default",
        .tags = &[_]u8{},
        .custom_instructions = &[_]u8{},
        .confirmations = 50,
        .status = .unspent,
        .spending_txid = [_]u8{0} ** 32,
    };
    var rec_high = rec_low;
    rec_high.outpoint.vout = 1;
    rec_high.confirmations = 100;

    try s.addOutput(rec_low);
    try s.addOutput(rec_high);

    const pruned = try s.pruneConfirmed(100);
    try std.testing.expectEqual(@as(u64, 1), pruned);

    const high_after = s.getOutput(rec_high.outpoint).?;
    try std.testing.expectEqual(@as(usize, 0), high_after.beef.len);

    const low_after = s.getOutput(rec_low.outpoint).?;
    try std.testing.expect(low_after.beef.len > 0);
}

test "LocalOutputStore: snapshot → replay round-trip" {
    const allocator = std.testing.allocator;
    var src = LocalOutputStore.init(allocator);
    defer src.deinit();
    const s_src = src.store();

    var i: u8 = 0;
    while (i < 3) : (i += 1) {
        const rec = OutputRecord{
            .outpoint = .{ .txid = [_]u8{i} ** 32, .vout = i },
            .satoshis = @as(u64, i) * 1000,
            .locking_script = &[_]u8{i},
            .derived_key_hash = [_]u8{i} ** 32,
            .derivation_protocol_hash = [_]u8{i} ** 16,
            .derivation_counterparty = [_]u8{i} ** 33,
            .derivation_index = i,
            .beef = &[_]u8{i},
            .basket = "default",
            .tags = &[_]u8{},
            .custom_instructions = &[_]u8{},
            .confirmations = 1,
            .status = .unspent,
            .spending_txid = [_]u8{0} ** 32,
        };
        try s_src.addOutput(rec);
    }

    const snap = try s_src.snapshot(allocator);
    defer allocator.free(snap);
    try std.testing.expectEqual(@as(usize, 3), snap.len);

    var dst = LocalOutputStore.init(allocator);
    defer dst.deinit();
    const s_dst = dst.store();
    try s_dst.replay(snap);

    const dst_snap = try s_dst.snapshot(allocator);
    defer allocator.free(dst_snap);
    try std.testing.expectEqual(@as(usize, 3), dst_snap.len);
}

```
