---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/lmdb/derivation_state_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.449945+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/lmdb/derivation_state_store_lmdb.zig

```zig
// M1.4 — LmdbDerivationStateStore: DerivationStateStore vtable backed by LMDB.
//
// Storage layout (one named database "derivation_state"):
//   key:   protocol_hash(16) || counterparty(33) = 49 bytes
//   value: current_index (u64 LE) = 8 bytes
//
// Ceiling enforcement: `next_index` checks (current + 1) < ceiling before
// committing. LMDB's single-writer model guarantees this is atomic —
// only one write txn can be open at a time, so no concurrent write can
// sneak past the ceiling check between the read and the commit.
//
// Snapshot/replay use a caller-owned []Record slice (each Record is 57 bytes,
// all fixed-size, so no arena gymnastics needed).

const std = @import("std");
const lmdb = @import("lmdb");
const derivation_state_mod = @import("derivation_state");

pub const Record = derivation_state_mod.Record;
pub const StoreError = derivation_state_mod.StoreError;

/// 49-byte composite key: protocol_hash(16) || counterparty(33).
fn makeKey(protocol_hash: *const [16]u8, counterparty: *const [33]u8) [49]u8 {
    var k: [49]u8 = undefined;
    @memcpy(k[0..16], protocol_hash);
    @memcpy(k[16..49], counterparty);
    return k;
}

pub const LmdbDerivationStateStore = struct {
    env: *lmdb.Env,
    allocator: std.mem.Allocator,
    dbi: lmdb.Dbi,
    /// Optional ceiling: next_index will fail with `persistence_failed` if
    /// the resulting index would equal or exceed this value. 0 = no ceiling.
    ceiling: u64,

    pub fn init(env: *lmdb.Env, allocator: std.mem.Allocator) StoreError!LmdbDerivationStateStore {
        return initWithCeiling(env, allocator, 0);
    }

    pub fn initWithCeiling(
        env: *lmdb.Env,
        allocator: std.mem.Allocator,
        ceiling: u64,
    ) StoreError!LmdbDerivationStateStore {
        var txn = env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();
        const dbi = txn.openDb("derivation_state", .{ .create = true }) catch
            return error.persistence_failed;
        txn.commit() catch return error.persistence_failed;
        return .{
            .env = env,
            .allocator = allocator,
            .dbi = dbi,
            .ceiling = ceiling,
        };
    }

    pub fn deinit(_: *LmdbDerivationStateStore) void {}

    pub fn store(self: *LmdbDerivationStateStore) derivation_state_mod.DerivationStateStore {
        return .{ .ctx = @ptrCast(self), .vtable = &vtable };
    }

    // ── internal helpers ──────────────────────────────────────────────

    fn doGetIndex(
        self: *LmdbDerivationStateStore,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) ?u64 {
        var txn = self.env.beginTxn(.read_only) catch return null;
        defer txn.abort();
        const k = makeKey(protocol_hash, counterparty);
        const raw = txn.get(self.dbi, &k) catch return null;
        if (raw.len < 8) return null;
        return std.mem.readInt(u64, raw[0..8], .little);
    }

    fn doNextIndex(
        self: *LmdbDerivationStateStore,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) StoreError!u64 {
        const k = makeKey(protocol_hash, counterparty);
        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;

        // Read current value inside the write txn (provides snapshot isolation).
        const current_opt: ?u64 = blk: {
            const raw = txn.get(self.dbi, &k) catch |e| {
                if (e == error.not_found) break :blk null;
                txn.abort();
                return error.persistence_failed;
            };
            if (raw.len < 8) {
                txn.abort();
                return error.persistence_failed;
            }
            break :blk std.mem.readInt(u64, raw[0..8], .little);
        };

        const next: u64 = if (current_opt) |cur| cur + 1 else 0;

        // Ceiling enforcement.
        if (self.ceiling > 0 and next >= self.ceiling) {
            txn.abort();
            return error.persistence_failed;
        }

        var val: [8]u8 = undefined;
        std.mem.writeInt(u64, &val, next, .little);
        txn.put(self.dbi, &k, &val, .{}) catch {
            txn.abort();
            return error.persistence_failed;
        };
        txn.commit() catch return error.persistence_failed;
        return next;
    }

    fn doSnapshot(
        self: *LmdbDerivationStateStore,
        allocator: std.mem.Allocator,
    ) StoreError![]Record {
        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();
        var cur = txn.openCursor(self.dbi) catch return error.persistence_failed;
        defer cur.close();

        var list: std.ArrayList(Record) = .empty;
        errdefer list.deinit(allocator);

        while (cur.next() catch return error.persistence_failed) |entry| {
            if (entry.key.len < 49 or entry.val.len < 8) continue;
            var r: Record = undefined;
            @memcpy(&r.protocol_hash, entry.key[0..16]);
            @memcpy(&r.counterparty, entry.key[16..49]);
            r.current_index = std.mem.readInt(u64, entry.val[0..8], .little);
            list.append(allocator, r) catch return error.out_of_memory;
        }
        return list.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    fn doReplay(
        self: *LmdbDerivationStateStore,
        records: []const Record,
    ) StoreError!void {
        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();
        txn.clear(self.dbi) catch {
            txn.abort();
            return error.persistence_failed;
        };
        for (records) |r| {
            const k = makeKey(&r.protocol_hash, &r.counterparty);
            var val: [8]u8 = undefined;
            std.mem.writeInt(u64, &val, r.current_index, .little);
            txn.put(self.dbi, &k, &val, .{}) catch {
                txn.abort();
                return error.persistence_failed;
            };
        }
        txn.commit() catch return error.persistence_failed;
    }

    // ── vtable shims ──────────────────────────────────────────────────

    fn vGetIndex(
        ctx: *anyopaque,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) ?u64 {
        const self: *LmdbDerivationStateStore = @ptrCast(@alignCast(ctx));
        return self.doGetIndex(protocol_hash, counterparty);
    }

    fn vNextIndex(
        ctx: *anyopaque,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) StoreError!u64 {
        const self: *LmdbDerivationStateStore = @ptrCast(@alignCast(ctx));
        return self.doNextIndex(protocol_hash, counterparty);
    }

    fn vSnapshot(ctx: *anyopaque, allocator: std.mem.Allocator) StoreError![]Record {
        const self: *LmdbDerivationStateStore = @ptrCast(@alignCast(ctx));
        return self.doSnapshot(allocator);
    }

    fn vReplay(ctx: *anyopaque, records: []const Record) StoreError!void {
        const self: *LmdbDerivationStateStore = @ptrCast(@alignCast(ctx));
        return self.doReplay(records);
    }

    const vtable = derivation_state_mod.DerivationStateStore.VTable{
        .get_index = vGetIndex,
        .next_index = vNextIndex,
        .snapshot = vSnapshot,
        .replay = vReplay,
    };
};

```
