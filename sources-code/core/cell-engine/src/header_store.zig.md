---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/header_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.977245+00:00
---

# core/cell-engine/src/header_store.zig

```zig
// Phase WH2 — Trustless SPV: HeaderStore vtable + LocalHeaderStore.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH2).
//
// Pluggable storage layer for verified block headers.  Mirrors the vtable
// pattern from `derivation_state.zig` / `slot_store.zig`:
//   • LocalHeaderStore           — in-memory (v0.1, default backing for browser
//                                  IndexedDB layer + sovereign-node lmdb layer)
//   • PlexusHeaderStore          — v0.2 stub: paid mirror via Plexus operator
//   • FederatedSemantosHeaderStore — v0.3 stub: cross-node header replication
//
// **Important invariant**: `appendValidated` only accepts headers that have
// already been validated by `headers.validateHeader`. This module does NOT
// re-validate — it stores blindly and trusts that the WH3 fetcher / WH4 tip
// subscriber filter every byte through the verifier first. The append-only
// over the verified chain property is the contract; misuse is a caller bug.

const std = @import("std");
const headers = @import("headers");

pub const Header = headers.Header;

pub const HeaderRecord = struct {
    header: Header,
    height: u32,
    hash: [32]u8,
};

pub const StoreError = error{
    out_of_memory,
    not_found,
    prev_hash_mismatch,
    height_out_of_order,
    persistence_failed,
};

/// Pluggable interface for verified-header persistence.  Three planned
/// backings, all conforming to this vtable:
///   • LocalHeaderStore           — in-memory (v0.1)
///   • PlexusHeaderStore          — local + Plexus mirror (v0.2)
///   • FederatedSemantosHeaderStore — local + federated replication (v0.3)
pub const HeaderStore = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        get_by_height: *const fn (ctx: *anyopaque, height: u32) ?HeaderRecord,
        get_by_hash: *const fn (ctx: *anyopaque, hash: *const [32]u8) ?HeaderRecord,
        /// Append a validated header. Fails if the new header's prev_hash
        /// does not match the current tip's hash (or, when the store is
        /// empty, if `height` is non-zero).
        append_validated: *const fn (ctx: *anyopaque, header: Header, height: u32) StoreError!void,
        tip: *const fn (ctx: *anyopaque) ?HeaderRecord,
        snapshot: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) StoreError![]HeaderRecord,
        replay: *const fn (ctx: *anyopaque, records: []const HeaderRecord) StoreError!void,
        /// Drop every record at height >= `from_height`. Used by WH4 reorg
        /// handling. Returns count of dropped records.
        rollback_from: *const fn (ctx: *anyopaque, from_height: u32) StoreError!u32,
    };

    pub fn getByHeight(self: *const HeaderStore, height: u32) ?HeaderRecord {
        return self.vtable.get_by_height(self.ctx, height);
    }
    pub fn getByHash(self: *const HeaderStore, hash: *const [32]u8) ?HeaderRecord {
        return self.vtable.get_by_hash(self.ctx, hash);
    }
    pub fn appendValidated(self: *const HeaderStore, header: Header, height: u32) StoreError!void {
        return self.vtable.append_validated(self.ctx, header, height);
    }
    pub fn tip(self: *const HeaderStore) ?HeaderRecord {
        return self.vtable.tip(self.ctx);
    }
    pub fn snapshot(self: *const HeaderStore, allocator: std.mem.Allocator) StoreError![]HeaderRecord {
        return self.vtable.snapshot(self.ctx, allocator);
    }
    pub fn replay(self: *const HeaderStore, records: []const HeaderRecord) StoreError!void {
        return self.vtable.replay(self.ctx, records);
    }
    pub fn rollbackFrom(self: *const HeaderStore, from_height: u32) StoreError!u32 {
        return self.vtable.rollback_from(self.ctx, from_height);
    }
};

/// In-memory implementation. Suitable for native tests and as the volatile
/// inner layer for the browser IndexedDB / sovereign lmdb backings.
pub const LocalHeaderStore = struct {
    allocator: std.mem.Allocator,
    /// Heights are dense from `genesis_height` upward; we use an ArrayList
    /// keyed by (height - genesis_height).  Genesis is 0 in the canonical
    /// chain, so for v0.1 we just index from 0.
    by_height: std.ArrayList(HeaderRecord),
    by_hash: std.AutoHashMap([32]u8, u32),

    pub fn init(allocator: std.mem.Allocator) LocalHeaderStore {
        return .{
            .allocator = allocator,
            .by_height = .empty,
            .by_hash = std.AutoHashMap([32]u8, u32).init(allocator),
        };
    }

    pub fn deinit(self: *LocalHeaderStore) void {
        self.by_height.deinit(self.allocator);
        self.by_hash.deinit();
    }

    pub fn store(self: *LocalHeaderStore) HeaderStore {
        return .{ .ctx = @ptrCast(self), .vtable = &local_vtable };
    }

    fn vGetByHeight(ctx: *anyopaque, height: u32) ?HeaderRecord {
        const self: *LocalHeaderStore = @ptrCast(@alignCast(ctx));
        if (self.by_height.items.len == 0) return null;
        const first_height = self.by_height.items[0].height;
        if (height < first_height) return null;
        const idx = height - first_height;
        if (idx >= self.by_height.items.len) return null;
        return self.by_height.items[idx];
    }

    fn vGetByHash(ctx: *anyopaque, hash: *const [32]u8) ?HeaderRecord {
        const self: *LocalHeaderStore = @ptrCast(@alignCast(ctx));
        const h = self.by_hash.get(hash.*) orelse return null;
        return vGetByHeight(ctx, h);
    }

    fn vAppendValidated(ctx: *anyopaque, header: Header, height: u32) StoreError!void {
        const self: *LocalHeaderStore = @ptrCast(@alignCast(ctx));
        const new_hash = header.computeHash();

        if (self.by_height.items.len == 0) {
            // First record may be at any height — we record it as our origin.
        } else {
            const last = self.by_height.items[self.by_height.items.len - 1];
            if (height != last.height + 1) return error.height_out_of_order;
            if (!std.mem.eql(u8, &header.prev_hash, &last.hash)) {
                return error.prev_hash_mismatch;
            }
        }

        const rec: HeaderRecord = .{ .header = header, .height = height, .hash = new_hash };
        self.by_height.append(self.allocator, rec) catch return error.out_of_memory;
        self.by_hash.put(new_hash, height) catch {
            // Roll back the append on hash-index failure to keep the indexes
            // consistent.
            _ = self.by_height.pop();
            return error.out_of_memory;
        };
    }

    fn vTip(ctx: *anyopaque) ?HeaderRecord {
        const self: *LocalHeaderStore = @ptrCast(@alignCast(ctx));
        if (self.by_height.items.len == 0) return null;
        return self.by_height.items[self.by_height.items.len - 1];
    }

    fn vSnapshot(ctx: *anyopaque, allocator: std.mem.Allocator) StoreError![]HeaderRecord {
        const self: *LocalHeaderStore = @ptrCast(@alignCast(ctx));
        const out = allocator.alloc(HeaderRecord, self.by_height.items.len) catch return error.out_of_memory;
        @memcpy(out, self.by_height.items);
        return out;
    }

    fn vReplay(ctx: *anyopaque, records: []const HeaderRecord) StoreError!void {
        const self: *LocalHeaderStore = @ptrCast(@alignCast(ctx));
        self.by_height.clearRetainingCapacity();
        self.by_hash.clearRetainingCapacity();
        // Records must be in monotone height order with valid prev_hash links.
        for (records, 0..) |r, i| {
            if (i > 0) {
                const prev = records[i - 1];
                if (r.height != prev.height + 1) return error.height_out_of_order;
                if (!std.mem.eql(u8, &r.header.prev_hash, &prev.hash)) {
                    return error.prev_hash_mismatch;
                }
            }
            self.by_height.append(self.allocator, r) catch return error.out_of_memory;
            self.by_hash.put(r.hash, r.height) catch return error.out_of_memory;
        }
    }

    fn vRollbackFrom(ctx: *anyopaque, from_height: u32) StoreError!u32 {
        const self: *LocalHeaderStore = @ptrCast(@alignCast(ctx));
        if (self.by_height.items.len == 0) return 0;
        const first_height = self.by_height.items[0].height;
        if (from_height < first_height) {
            // Drop everything.
            const dropped: u32 = @intCast(self.by_height.items.len);
            for (self.by_height.items) |r| _ = self.by_hash.remove(r.hash);
            self.by_height.clearRetainingCapacity();
            return dropped;
        }
        const idx = from_height - first_height;
        if (idx >= self.by_height.items.len) return 0;
        const dropped: u32 = @intCast(self.by_height.items.len - idx);
        for (self.by_height.items[idx..]) |r| _ = self.by_hash.remove(r.hash);
        self.by_height.shrinkRetainingCapacity(idx);
        return dropped;
    }

    const local_vtable: HeaderStore.VTable = .{
        .get_by_height = vGetByHeight,
        .get_by_hash = vGetByHash,
        .append_validated = vAppendValidated,
        .tip = vTip,
        .snapshot = vSnapshot,
        .replay = vReplay,
        .rollback_from = vRollbackFrom,
    };
};

// ──────────────────────────────────────────────────────────────────────
// Stubs for v0.2 / v0.3
// ──────────────────────────────────────────────────────────────────────

pub const PlexusHeaderStore = struct {
    pub fn init() PlexusHeaderStore {
        return .{};
    }
    pub fn store(_: *PlexusHeaderStore) HeaderStore {
        return .{ .ctx = undefined, .vtable = &stub_vtable };
    }
    fn err1(_: *anyopaque, _: u32) ?HeaderRecord {
        return null;
    }
    fn err2(_: *anyopaque, _: *const [32]u8) ?HeaderRecord {
        return null;
    }
    fn err3(_: *anyopaque, _: Header, _: u32) StoreError!void {
        return error.persistence_failed;
    }
    fn err4(_: *anyopaque) ?HeaderRecord {
        return null;
    }
    fn err5(_: *anyopaque, _: std.mem.Allocator) StoreError![]HeaderRecord {
        return error.persistence_failed;
    }
    fn err6(_: *anyopaque, _: []const HeaderRecord) StoreError!void {
        return error.persistence_failed;
    }
    fn err7(_: *anyopaque, _: u32) StoreError!u32 {
        return error.persistence_failed;
    }
    const stub_vtable: HeaderStore.VTable = .{
        .get_by_height = err1,
        .get_by_hash = err2,
        .append_validated = err3,
        .tip = err4,
        .snapshot = err5,
        .replay = err6,
        .rollback_from = err7,
    };
};

pub const FederatedSemantosHeaderStore = struct {
    pub fn init() FederatedSemantosHeaderStore {
        return .{};
    }
    pub fn store(_: *FederatedSemantosHeaderStore) HeaderStore {
        return .{ .ctx = undefined, .vtable = &stub_vtable };
    }
    fn err1(_: *anyopaque, _: u32) ?HeaderRecord {
        return null;
    }
    fn err2(_: *anyopaque, _: *const [32]u8) ?HeaderRecord {
        return null;
    }
    fn err3(_: *anyopaque, _: Header, _: u32) StoreError!void {
        return error.persistence_failed;
    }
    fn err4(_: *anyopaque) ?HeaderRecord {
        return null;
    }
    fn err5(_: *anyopaque, _: std.mem.Allocator) StoreError![]HeaderRecord {
        return error.persistence_failed;
    }
    fn err6(_: *anyopaque, _: []const HeaderRecord) StoreError!void {
        return error.persistence_failed;
    }
    fn err7(_: *anyopaque, _: u32) StoreError!u32 {
        return error.persistence_failed;
    }
    const stub_vtable: HeaderStore.VTable = .{
        .get_by_height = err1,
        .get_by_hash = err2,
        .append_validated = err3,
        .tip = err4,
        .snapshot = err5,
        .replay = err6,
        .rollback_from = err7,
    };
};

```
