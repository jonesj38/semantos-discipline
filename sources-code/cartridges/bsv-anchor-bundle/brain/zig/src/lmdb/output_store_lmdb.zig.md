---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/lmdb/output_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.450281+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/lmdb/output_store_lmdb.zig

```zig
// M1.3 — LmdbOutputStore: OutputStore vtable backed by LMDB.
//
// Storage layout (one named database "outputs"):
//   key:   txid(32) || vout_le(4) = 36 bytes (matches LocalOutputStore.Key)
//   value: serialized OutputRecord (variable length)
//
// Serialization format (little-endian unless noted):
//   [00..08]  satoshis        (u64 LE)
//   [08..40]  derived_key_hash (32 bytes)
//   [40..56]  derivation_protocol_hash (16 bytes)
//   [56..89]  derivation_counterparty  (33 bytes)
//   [89..97]  derivation_index  (u64 LE)
//   [97..101] confirmations     (u32 LE)
//   [101]     status            (u8: 0=unspent, 1=spent, 2=reorged)
//   [102..134]spending_txid     (32 bytes)
//   [134..138]locking_script_len(u32 LE)
//   [138+N]   locking_script    (N bytes)
//   then:  u32 beef_len + beef
//          u32 basket_len + basket
//          u32 tags_len + tags
//          u32 custom_instructions_len + custom_instructions
//
// Atomicity: mark_spent reads the existing record, verifies it exists,
// mutates status + spending_txid, then commits a single write txn.
// If the outpoint is unknown the txn is aborted and no state changes.

const std = @import("std");
const lmdb = @import("lmdb");
const output_store_mod = @import("output_store");

pub const Outpoint = output_store_mod.Outpoint;
pub const OutputRecord = output_store_mod.OutputRecord;
pub const OutputStatus = output_store_mod.OutputStatus;
pub const StoreError = output_store_mod.StoreError;

const FIXED_HEADER = 8 + 32 + 16 + 33 + 8 + 4 + 1 + 32; // 134 bytes

fn outpointKey(op: Outpoint) [36]u8 {
    var k: [36]u8 = undefined;
    @memcpy(k[0..32], &op.txid);
    std.mem.writeInt(u32, k[32..36], op.vout, .little);
    return k;
}

/// Estimate serialized size for a record.
fn serializedLen(r: OutputRecord) usize {
    return FIXED_HEADER +
        4 + r.locking_script.len +
        4 + r.beef.len +
        4 + r.basket.len +
        4 + r.tags.len +
        4 + r.custom_instructions.len;
}

/// Serialize an OutputRecord into a caller-supplied buffer.
/// Buffer must be >= serializedLen(r) bytes.
fn serializeRecord(r: OutputRecord, buf: []u8) void {
    var off: usize = 0;
    std.mem.writeInt(u64, buf[off..][0..8], r.satoshis, .little);
    off += 8;
    @memcpy(buf[off .. off + 32], &r.derived_key_hash);
    off += 32;
    @memcpy(buf[off .. off + 16], &r.derivation_protocol_hash);
    off += 16;
    @memcpy(buf[off .. off + 33], &r.derivation_counterparty);
    off += 33;
    std.mem.writeInt(u64, buf[off..][0..8], r.derivation_index, .little);
    off += 8;
    std.mem.writeInt(u32, buf[off..][0..4], r.confirmations, .little);
    off += 4;
    buf[off] = @intFromEnum(r.status);
    off += 1;
    @memcpy(buf[off .. off + 32], &r.spending_txid);
    off += 32;
    // Variable-length fields.
    inline for ([_][]const u8{
        r.locking_script,
        r.beef,
        r.basket,
        r.tags,
        r.custom_instructions,
    }) |slice| {
        std.mem.writeInt(u32, buf[off..][0..4], @intCast(slice.len), .little);
        off += 4;
        @memcpy(buf[off .. off + slice.len], slice);
        off += slice.len;
    }
}

fn readSlice(buf: []const u8, off: *usize) ?[]const u8 {
    if (off.* + 4 > buf.len) return null;
    const len = std.mem.readInt(u32, buf[off.*..][0..4], .little);
    off.* += 4;
    if (off.* + len > buf.len) return null;
    const s = buf[off.* .. off.* + len];
    off.* += len;
    return s;
}

/// Deserialize a raw value slice into an OutputRecord. The returned record
/// borrows slices from `raw` — it is valid only as long as the enclosing
/// transaction is open (LMDB-managed memory). Callers that need to persist
/// the record past the txn must copy the variable-length fields.
fn deserializeRecord(outpoint: Outpoint, raw: []const u8) StoreError!OutputRecord {
    if (raw.len < FIXED_HEADER) return error.persistence_failed;
    var off: usize = 0;
    const satoshis = std.mem.readInt(u64, raw[off..][0..8], .little);
    off += 8;
    var derived_key_hash: [32]u8 = undefined;
    @memcpy(&derived_key_hash, raw[off .. off + 32]);
    off += 32;
    var derivation_protocol_hash: [16]u8 = undefined;
    @memcpy(&derivation_protocol_hash, raw[off .. off + 16]);
    off += 16;
    var derivation_counterparty: [33]u8 = undefined;
    @memcpy(&derivation_counterparty, raw[off .. off + 33]);
    off += 33;
    const derivation_index = std.mem.readInt(u64, raw[off..][0..8], .little);
    off += 8;
    const confirmations = std.mem.readInt(u32, raw[off..][0..4], .little);
    off += 4;
    const status: OutputStatus = @enumFromInt(raw[off]);
    off += 1;
    var spending_txid: [32]u8 = undefined;
    @memcpy(&spending_txid, raw[off .. off + 32]);
    off += 32;

    const locking_script = readSlice(raw, &off) orelse return error.persistence_failed;
    const beef = readSlice(raw, &off) orelse return error.persistence_failed;
    const basket = readSlice(raw, &off) orelse return error.persistence_failed;
    const tags = readSlice(raw, &off) orelse return error.persistence_failed;
    const custom_instructions = readSlice(raw, &off) orelse return error.persistence_failed;

    return .{
        .outpoint = outpoint,
        .satoshis = satoshis,
        .locking_script = locking_script,
        .derived_key_hash = derived_key_hash,
        .derivation_protocol_hash = derivation_protocol_hash,
        .derivation_counterparty = derivation_counterparty,
        .derivation_index = derivation_index,
        .beef = beef,
        .basket = basket,
        .tags = tags,
        .custom_instructions = custom_instructions,
        .confirmations = confirmations,
        .status = status,
        .spending_txid = spending_txid,
    };
}

/// Deserialize and deep-copy variable-length fields into `allocator`.
/// The returned OutputRecord owns all its slices.
fn deserializeRecordOwned(
    outpoint: Outpoint,
    raw: []const u8,
    allocator: std.mem.Allocator,
) StoreError!OutputRecord {
    const borrowed = try deserializeRecord(outpoint, raw);
    const ls = allocator.dupe(u8, borrowed.locking_script) catch return error.out_of_memory;
    errdefer allocator.free(ls);
    const bf = allocator.dupe(u8, borrowed.beef) catch return error.out_of_memory;
    errdefer allocator.free(bf);
    const bk = allocator.dupe(u8, borrowed.basket) catch return error.out_of_memory;
    errdefer allocator.free(bk);
    const tg = allocator.dupe(u8, borrowed.tags) catch return error.out_of_memory;
    errdefer allocator.free(tg);
    const ci = allocator.dupe(u8, borrowed.custom_instructions) catch return error.out_of_memory;
    errdefer allocator.free(ci);
    return .{
        .outpoint = borrowed.outpoint,
        .satoshis = borrowed.satoshis,
        .locking_script = ls,
        .derived_key_hash = borrowed.derived_key_hash,
        .derivation_protocol_hash = borrowed.derivation_protocol_hash,
        .derivation_counterparty = borrowed.derivation_counterparty,
        .derivation_index = borrowed.derivation_index,
        .beef = bf,
        .basket = bk,
        .tags = tg,
        .custom_instructions = ci,
        .confirmations = borrowed.confirmations,
        .status = borrowed.status,
        .spending_txid = borrowed.spending_txid,
    };
}

fn freeRecord(allocator: std.mem.Allocator, r: *OutputRecord) void {
    allocator.free(r.locking_script);
    allocator.free(r.beef);
    allocator.free(r.basket);
    allocator.free(r.tags);
    allocator.free(r.custom_instructions);
}

pub const LmdbOutputStore = struct {
    env: *lmdb.Env,
    allocator: std.mem.Allocator,
    dbi: lmdb.Dbi,
    /// Arena for getOutput results. Reset on each getOutput call so the returned
    /// record's variable-length slices stay valid until the next getOutput.
    get_arena: std.heap.ArenaAllocator,
    /// Arena for listOutputs results. Reset on each listOutputs call.
    list_arena: std.heap.ArenaAllocator,
    /// Arena for snapshot results. Reset on each snapshot call.
    snapshot_arena: std.heap.ArenaAllocator,

    pub fn init(env: *lmdb.Env, allocator: std.mem.Allocator) StoreError!LmdbOutputStore {
        var txn = env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();
        const dbi = txn.openDb("outputs", .{ .create = true }) catch
            return error.persistence_failed;
        txn.commit() catch return error.persistence_failed;
        return .{
            .env = env,
            .allocator = allocator,
            .dbi = dbi,
            .get_arena = std.heap.ArenaAllocator.init(allocator),
            .list_arena = std.heap.ArenaAllocator.init(allocator),
            .snapshot_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *LmdbOutputStore) void {
        self.get_arena.deinit();
        self.list_arena.deinit();
        self.snapshot_arena.deinit();
    }

    pub fn store(self: *LmdbOutputStore) output_store_mod.OutputStore {
        return .{ .ctx = @ptrCast(self), .vtable = &vtable };
    }

    // ── internal helpers ──────────────────────────────────────────────

    fn writeRecord(self: *LmdbOutputStore, txn: lmdb.Txn, r: OutputRecord) StoreError!void {
        const key = outpointKey(r.outpoint);
        const sz = serializedLen(r);
        const buf = self.allocator.alloc(u8, sz) catch return error.out_of_memory;
        defer self.allocator.free(buf);
        serializeRecord(r, buf);
        txn.put(self.dbi, &key, buf, .{}) catch return error.persistence_failed;
    }

    fn doAdd(self: *LmdbOutputStore, record: OutputRecord) StoreError!void {
        const key = outpointKey(record.outpoint);
        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        // Check uniqueness — abort the txn in all non-commit paths.
        const exists = blk: {
            _ = txn.get(self.dbi, &key) catch |e| {
                if (e == error.not_found) break :blk false;
                txn.abort();
                return error.persistence_failed;
            };
            break :blk true;
        };
        if (exists) {
            txn.abort();
            return error.duplicate_outpoint;
        }
        // Write the new record.
        self.writeRecord(txn, record) catch |e| {
            txn.abort();
            return e;
        };
        txn.commit() catch {
            return error.persistence_failed;
        };
    }

    fn doGet(self: *LmdbOutputStore, outpoint: Outpoint) ?OutputRecord {
        var txn = self.env.beginTxn(.read_only) catch return null;
        defer txn.abort();
        const key = outpointKey(outpoint);
        const raw = txn.get(self.dbi, &key) catch return null;
        // Reset the get_arena so callers don't accumulate allocations.
        // The returned slices are valid until the next doGet call.
        _ = self.get_arena.reset(.retain_capacity);
        return deserializeRecordOwned(outpoint, raw, self.get_arena.allocator()) catch null;
    }

    fn doList(
        self: *LmdbOutputStore,
        basket_filter: ?[]const u8,
        tag_filter: ?[]const u8,
        allocator: std.mem.Allocator,
    ) StoreError![]OutputRecord {
        // Reset list_arena so previous list results are no longer valid.
        // Record slices are placed into list_arena; the outer []OutputRecord
        // slice is placed into `allocator` (caller frees it; list_arena owns
        // the per-record variable-length bytes until the next listOutputs call).
        _ = self.list_arena.reset(.retain_capacity);
        const rec_alloc = self.list_arena.allocator();

        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();

        var cur = txn.openCursor(self.dbi) catch return error.persistence_failed;
        defer cur.close();

        var list: std.ArrayList(OutputRecord) = .empty;
        errdefer list.deinit(allocator);

        while (cur.next() catch return error.persistence_failed) |entry| {
            if (entry.key.len < 36) continue;
            const op = Outpoint{
                .txid = entry.key[0..32].*,
                .vout = std.mem.readInt(u32, entry.key[32..36], .little),
            };
            const borrowed = deserializeRecord(op, entry.val) catch continue;
            if (borrowed.status != .unspent) continue;
            if (basket_filter) |b| {
                if (!std.mem.eql(u8, borrowed.basket, b)) continue;
            }
            if (tag_filter) |t| {
                if (!hasTag(borrowed.tags, t)) continue;
            }
            // Allocate slices into list_arena (stable until next listOutputs).
            const owned = deserializeRecordOwned(op, entry.val, rec_alloc) catch
                return error.out_of_memory;
            list.append(allocator, owned) catch return error.out_of_memory;
        }
        return list.toOwnedSlice(allocator) catch return error.out_of_memory;
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

    fn doMarkSpent(
        self: *LmdbOutputStore,
        outpoint: Outpoint,
        spending_txid: [32]u8,
    ) StoreError!void {
        const key = outpointKey(outpoint);
        // Atomic read-verify-write in a single write txn.
        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;

        const raw = txn.get(self.dbi, &key) catch |e| {
            txn.abort();
            if (e == error.not_found) return error.unknown_outpoint;
            return error.persistence_failed;
        };

        // Parse, mutate, re-serialize inside the open txn window.
        var rec = deserializeRecord(outpoint, raw) catch {
            txn.abort();
            return error.persistence_failed;
        };
        rec.status = .spent;
        rec.spending_txid = spending_txid;

        const sz = serializedLen(rec);
        const buf = self.allocator.alloc(u8, sz) catch {
            txn.abort();
            return error.out_of_memory;
        };
        defer self.allocator.free(buf);
        serializeRecord(rec, buf);

        txn.put(self.dbi, &key, buf, .{}) catch {
            txn.abort();
            return error.persistence_failed;
        };
        txn.commit() catch return error.persistence_failed;
    }

    fn doPrune(self: *LmdbOutputStore, min_confirmations: u32) StoreError!u64 {
        // Two-pass: scan for prunable records, then write-back or delete.
        // Pass 1: collect keys needing update.
        const PruneAction = enum { clear_beef, delete };
        const PruneItem = struct {
            key: [36]u8,
            action: PruneAction,
        };
        var items: std.ArrayList(PruneItem) = .empty;
        defer items.deinit(self.allocator);

        {
            var txn_r = self.env.beginTxn(.read_only) catch return error.persistence_failed;
            defer txn_r.abort();
            var cur = txn_r.openCursor(self.dbi) catch return error.persistence_failed;
            defer cur.close();
            while (cur.next() catch return error.persistence_failed) |entry| {
                if (entry.key.len < 36) continue;
                const op = Outpoint{
                    .txid = entry.key[0..32].*,
                    .vout = std.mem.readInt(u32, entry.key[32..36], .little),
                };
                const rec = deserializeRecord(op, entry.val) catch continue;
                var k: [36]u8 = undefined;
                @memcpy(&k, entry.key[0..36]);
                if (rec.status == .spent and rec.confirmations >= 1000) {
                    items.append(self.allocator, .{ .key = k, .action = .delete }) catch
                        return error.out_of_memory;
                } else if (rec.confirmations >= min_confirmations and rec.beef.len > 0) {
                    items.append(self.allocator, .{ .key = k, .action = .clear_beef }) catch
                        return error.out_of_memory;
                }
            }
        }

        var pruned: u64 = 0;
        if (items.items.len == 0) return 0;

        var txn_w = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn_w.abort();

        for (items.items) |item| {
            switch (item.action) {
                .delete => {
                    txn_w.del(self.dbi, &item.key, null) catch {};
                    pruned += 1;
                },
                .clear_beef => {
                    // Re-read and re-write with empty beef.
                    const raw = txn_w.get(self.dbi, &item.key) catch continue;
                    const op = Outpoint{
                        .txid = item.key[0..32].*,
                        .vout = std.mem.readInt(u32, item.key[32..36], .little),
                    };
                    var rec = deserializeRecord(op, raw) catch continue;
                    const empty: []const u8 = &[_]u8{};
                    rec.beef = empty;
                    const sz = serializedLen(rec);
                    const buf = self.allocator.alloc(u8, sz) catch return error.out_of_memory;
                    defer self.allocator.free(buf);
                    serializeRecord(rec, buf);
                    txn_w.put(self.dbi, &item.key, buf, .{}) catch continue;
                    pruned += 1;
                },
            }
        }
        txn_w.commit() catch return error.persistence_failed;
        return pruned;
    }

    fn doSnapshot(self: *LmdbOutputStore, allocator: std.mem.Allocator) StoreError![]OutputRecord {
        // Reset snapshot_arena; record slices live in it. The outer slice lives
        // in `allocator`. Callers must not free individual record slices —
        // they remain valid until the next snapshot() call on this store.
        _ = self.snapshot_arena.reset(.retain_capacity);
        const rec_alloc = self.snapshot_arena.allocator();

        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();
        var cur = txn.openCursor(self.dbi) catch return error.persistence_failed;
        defer cur.close();

        var list: std.ArrayList(OutputRecord) = .empty;
        errdefer list.deinit(allocator);

        while (cur.next() catch return error.persistence_failed) |entry| {
            if (entry.key.len < 36) continue;
            const op = Outpoint{
                .txid = entry.key[0..32].*,
                .vout = std.mem.readInt(u32, entry.key[32..36], .little),
            };
            const owned = deserializeRecordOwned(op, entry.val, rec_alloc) catch
                return error.persistence_failed;
            list.append(allocator, owned) catch return error.out_of_memory;
        }
        return list.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    fn doReplay(self: *LmdbOutputStore, records: []const OutputRecord) StoreError!void {
        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();
        txn.clear(self.dbi) catch return error.persistence_failed;
        for (records) |r| {
            try self.writeRecord(txn, r);
        }
        txn.commit() catch return error.persistence_failed;
    }

    // ── vtable shims ──────────────────────────────────────────────────

    fn vAdd(ctx: *anyopaque, record: OutputRecord) StoreError!void {
        const self: *LmdbOutputStore = @ptrCast(@alignCast(ctx));
        return self.doAdd(record);
    }
    fn vList(
        ctx: *anyopaque,
        basket_filter: ?[]const u8,
        tag_filter: ?[]const u8,
        allocator: std.mem.Allocator,
    ) StoreError![]OutputRecord {
        const self: *LmdbOutputStore = @ptrCast(@alignCast(ctx));
        return self.doList(basket_filter, tag_filter, allocator);
    }
    fn vGet(ctx: *anyopaque, outpoint: Outpoint) ?OutputRecord {
        const self: *LmdbOutputStore = @ptrCast(@alignCast(ctx));
        return self.doGet(outpoint);
    }
    fn vMarkSpent(
        ctx: *anyopaque,
        outpoint: Outpoint,
        spending_txid: [32]u8,
    ) StoreError!void {
        const self: *LmdbOutputStore = @ptrCast(@alignCast(ctx));
        return self.doMarkSpent(outpoint, spending_txid);
    }
    fn vPrune(ctx: *anyopaque, min_confirmations: u32) StoreError!u64 {
        const self: *LmdbOutputStore = @ptrCast(@alignCast(ctx));
        return self.doPrune(min_confirmations);
    }
    fn vSnapshot(ctx: *anyopaque, allocator: std.mem.Allocator) StoreError![]OutputRecord {
        const self: *LmdbOutputStore = @ptrCast(@alignCast(ctx));
        return self.doSnapshot(allocator);
    }
    fn vReplay(ctx: *anyopaque, records: []const OutputRecord) StoreError!void {
        const self: *LmdbOutputStore = @ptrCast(@alignCast(ctx));
        return self.doReplay(records);
    }

    const vtable = output_store_mod.OutputStore.VTable{
        .add_output = vAdd,
        .list_outputs = vList,
        .get_output = vGet,
        .mark_spent = vMarkSpent,
        .prune_confirmed = vPrune,
        .snapshot = vSnapshot,
        .replay = vReplay,
    };
};

```
