---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/swarm/brain/swarm_tracker.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.679765+00:00
---

# cartridges/swarm/brain/swarm_tracker.zig

```zig
// swarm_tracker — in-memory tracker state for the swarm cartridge.
//
// The brain is the cold-path control plane for the paid swarm (data-plane
// engine lives in runtime/session-protocol/src/swarm). This tracker holds, per
// infohash: the published manifest cell, the set of seeders that have announced
// (address + coarse HAVE-bitfield summary), and a running settled-receipt
// count. M5 keeps it purely in memory; M6 rebuilds it from the CellStore at
// boot and persists manifests + receipts as cells.
//
// Keys + owned string fields are duped on insert and freed on deinit.

const std = @import("std");

pub const SeederEntry = struct {
    address: []const u8,
    bitfield_hex: []const u8,
    last_seen: i64,
};

pub const ManifestEntry = struct {
    manifest_cell_hex: []const u8,
    semantic_path: []const u8,
    seeders: std.ArrayListUnmanaged(SeederEntry) = .{},
    receipts_count: u32 = 0,
    /// 32-byte CellStore hash of the persisted manifest cell (M7 — used to
    /// read its on-chain anchor status). Null until the cell is persisted.
    manifest_cell_hash: ?[32]u8 = null,
};

pub const Tracker = struct {
    allocator: std.mem.Allocator,
    by_infohash: std.StringHashMapUnmanaged(ManifestEntry) = .{},

    pub fn init(allocator: std.mem.Allocator) Tracker {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Tracker) void {
        var it = self.by_infohash.iterator();
        while (it.next()) |kv| {
            const e = kv.value_ptr;
            self.allocator.free(e.manifest_cell_hex);
            self.allocator.free(e.semantic_path);
            for (e.seeders.items) |s| {
                self.allocator.free(s.address);
                self.allocator.free(s.bitfield_hex);
            }
            e.seeders.deinit(self.allocator);
            self.allocator.free(kv.key_ptr.*);
        }
        self.by_infohash.deinit(self.allocator);
    }

    /// Upsert a published manifest. Idempotent on infohash; later publishes
    /// refresh the stored cell + path.
    pub fn publish(
        self: *Tracker,
        infohash_hex: []const u8,
        manifest_cell_hex: []const u8,
        semantic_path: []const u8,
    ) !void {
        if (self.by_infohash.getPtr(infohash_hex)) |e| {
            const new_cell = try self.allocator.dupe(u8, manifest_cell_hex);
            const new_path = try self.allocator.dupe(u8, semantic_path);
            self.allocator.free(e.manifest_cell_hex);
            self.allocator.free(e.semantic_path);
            e.manifest_cell_hex = new_cell;
            e.semantic_path = new_path;
            return;
        }
        const key = try self.allocator.dupe(u8, infohash_hex);
        errdefer self.allocator.free(key);
        const entry = ManifestEntry{
            .manifest_cell_hex = try self.allocator.dupe(u8, manifest_cell_hex),
            .semantic_path = try self.allocator.dupe(u8, semantic_path),
        };
        try self.by_infohash.put(self.allocator, key, entry);
    }

    pub fn locate(self: *Tracker, infohash_hex: []const u8) ?*ManifestEntry {
        return self.by_infohash.getPtr(infohash_hex);
    }

    /// Record the CellStore hash of a persisted manifest (M7 anchor lookups).
    pub fn setManifestHash(self: *Tracker, infohash_hex: []const u8, hash: [32]u8) void {
        if (self.by_infohash.getPtr(infohash_hex)) |e| e.manifest_cell_hash = hash;
    }

    /// Upsert a seeder's coarse HAVE summary. No-op if the manifest is unknown
    /// (a seeder must publish/locate before announcing).
    pub fn announce(
        self: *Tracker,
        infohash_hex: []const u8,
        address: []const u8,
        bitfield_hex: []const u8,
        ts: i64,
    ) !void {
        const e = self.by_infohash.getPtr(infohash_hex) orelse return;
        for (e.seeders.items) |*s| {
            if (std.mem.eql(u8, s.address, address)) {
                const new_bf = try self.allocator.dupe(u8, bitfield_hex);
                self.allocator.free(s.bitfield_hex);
                s.bitfield_hex = new_bf;
                s.last_seen = ts;
                return;
            }
        }
        try e.seeders.append(self.allocator, .{
            .address = try self.allocator.dupe(u8, address),
            .bitfield_hex = try self.allocator.dupe(u8, bitfield_hex),
            .last_seen = ts,
        });
    }

    /// Record `n` settled receipts for an infohash. Returns the number recorded
    /// (0 if the manifest is unknown).
    pub fn recordReceipts(self: *Tracker, infohash_hex: []const u8, n: u32) u32 {
        const e = self.by_infohash.getPtr(infohash_hex) orelse return 0;
        e.receipts_count += n;
        return n;
    }
};

// ─── Tests ───────────────────────────────────────────────────────────────────

const testing = std.testing;

test "publish + locate round-trips the manifest" {
    var t = Tracker.init(testing.allocator);
    defer t.deinit();
    try t.publish("aa", "deadbeef", "media/clip");
    const e = t.locate("aa").?;
    try testing.expectEqualStrings("deadbeef", e.manifest_cell_hex);
    try testing.expectEqualStrings("media/clip", e.semantic_path);
    try testing.expect(t.locate("bb") == null);
}

test "publish is idempotent + refreshes the stored cell" {
    var t = Tracker.init(testing.allocator);
    defer t.deinit();
    try t.publish("aa", "1111", "p1");
    try t.publish("aa", "2222", "p2");
    try testing.expectEqual(@as(u32, 1), t.by_infohash.count());
    try testing.expectEqualStrings("2222", t.locate("aa").?.manifest_cell_hex);
}

test "announce upserts a seeder by address" {
    var t = Tracker.init(testing.allocator);
    defer t.deinit();
    try t.publish("aa", "00", "p");
    try t.announce("aa", "node-A", "ff", 100);
    try t.announce("aa", "node-B", "0f", 101);
    try t.announce("aa", "node-A", "ee", 102); // update, not append
    const e = t.locate("aa").?;
    try testing.expectEqual(@as(usize, 2), e.seeders.items.len);
    for (e.seeders.items) |s| {
        if (std.mem.eql(u8, s.address, "node-A")) {
            try testing.expectEqualStrings("ee", s.bitfield_hex);
            try testing.expectEqual(@as(i64, 102), s.last_seen);
        }
    }
    // announce against an unknown infohash is a no-op.
    try t.announce("zz", "node-A", "ff", 1);
    try testing.expect(t.locate("zz") == null);
}

test "recordReceipts accumulates" {
    var t = Tracker.init(testing.allocator);
    defer t.deinit();
    try t.publish("aa", "00", "p");
    try testing.expectEqual(@as(u32, 3), t.recordReceipts("aa", 3));
    try testing.expectEqual(@as(u32, 2), t.recordReceipts("aa", 2));
    try testing.expectEqual(@as(u32, 5), t.locate("aa").?.receipts_count);
    try testing.expectEqual(@as(u32, 0), t.recordReceipts("zz", 9));
}

```
