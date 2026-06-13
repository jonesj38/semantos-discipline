---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/slot_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.978670+00:00
---

# core/cell-engine/src/slot_store.zig

```zig
// Phase W4 — SlotStore: at-rest persistence for tier-key cells.
//
// Reference: docs/design/WALLET-TIER-CUSTODY.md §5.3, §6.1, §6.2, §7.2-7.4.
//
// The wallet's tier cells (HOT budget, Tier-1/2/3 base keys) live across
// process restarts. They are AES-GCM encrypted under a per-tier KEK and
// written to a slot indexed by `slot_id` (a u32 keyed off tier + version).
//
// This module defines the interface (`SlotStore`) and ships a pure
// in-memory implementation (`LocalSlotStore`) — the same vtable surface that
// the browser bundle (IndexedDB) and sovereign node (lmdb) install in v0.2 /
// v0.3. The on-disk byte format (nonce || ciphertext || tag) is owned by
// `host.zig`; this layer only stores opaque blobs.

const std = @import("std");

/// Persisted ciphertext envelope. Allocator-owned bytes — `LocalSlotStore`
/// dupes on `put` and frees on `delete` / `deinit`.
pub const Blob = []u8;

pub const StoreError = error{
    out_of_memory,
    not_found,
    persistence_failed,
};

/// Interface for slot-keyed at-rest storage. Three planned backings, all
/// conforming to this vtable:
///   • LocalSlotStore     — in-memory (v0.1 native tests + browser memory cache)
///   • IndexedDBSlotStore — browser-side persistent storage (v0.2)
///   • LmdbSlotStore      — sovereign-node persistent storage (v0.3)
pub const SlotStore = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Read a blob by slot id. Returns `not_found` if the slot is empty.
        /// On success the returned slice is owned by the store — the caller
        /// must NOT free it; it is invalidated by the next `put`/`delete`/
        /// `deinit` for that slot.
        get: *const fn (
            ctx: *anyopaque,
            slot_id: u32,
        ) StoreError![]const u8,

        /// Write a blob to a slot, replacing any prior value. The store
        /// dupes the bytes — the caller's `bytes` is consumed by reference
        /// only for the duration of the call.
        put: *const fn (
            ctx: *anyopaque,
            slot_id: u32,
            bytes: []const u8,
        ) StoreError!void,

        /// Remove a slot. Returns `not_found` if the slot was never written.
        delete: *const fn (
            ctx: *anyopaque,
            slot_id: u32,
        ) StoreError!void,
    };

    pub fn get(self: *const SlotStore, slot_id: u32) StoreError![]const u8 {
        return self.vtable.get(self.ctx, slot_id);
    }

    pub fn put(self: *const SlotStore, slot_id: u32, bytes: []const u8) StoreError!void {
        return self.vtable.put(self.ctx, slot_id, bytes);
    }

    pub fn delete(self: *const SlotStore, slot_id: u32) StoreError!void {
        return self.vtable.delete(self.ctx, slot_id);
    }
};

/// In-memory implementation. Suitable for native tests and as the volatile
/// inner layer of the browser/node wallets (each wraps it in storage I/O).
/// The store owns every blob it holds — writes dupe, deletes free, deinit
/// frees all.
pub const LocalSlotStore = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap(u32, Blob),

    pub fn init(allocator: std.mem.Allocator) LocalSlotStore {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(u32, Blob).init(allocator),
        };
    }

    pub fn deinit(self: *LocalSlotStore) void {
        // Free any owned blobs before tearing down the map.
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }

    pub fn store(self: *LocalSlotStore) SlotStore {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &local_vtable,
        };
    }

    fn vGet(ctx: *anyopaque, slot_id: u32) StoreError![]const u8 {
        const self: *LocalSlotStore = @ptrCast(@alignCast(ctx));
        const blob = self.map.get(slot_id) orelse return error.not_found;
        return blob;
    }

    fn vPut(ctx: *anyopaque, slot_id: u32, bytes: []const u8) StoreError!void {
        const self: *LocalSlotStore = @ptrCast(@alignCast(ctx));
        // Peek-then-mutate: if a prior blob exists, free it before overwriting.
        if (self.map.get(slot_id)) |prior| {
            self.allocator.free(prior);
        }
        const dup = self.allocator.dupe(u8, bytes) catch return error.out_of_memory;
        self.map.put(slot_id, dup) catch {
            self.allocator.free(dup);
            return error.out_of_memory;
        };
    }

    fn vDelete(ctx: *anyopaque, slot_id: u32) StoreError!void {
        const self: *LocalSlotStore = @ptrCast(@alignCast(ctx));
        if (self.map.fetchRemove(slot_id)) |kv| {
            self.allocator.free(kv.value);
            return;
        }
        return error.not_found;
    }

    const local_vtable: SlotStore.VTable = .{
        .get = vGet,
        .put = vPut,
        .delete = vDelete,
    };
};

// ──────────────────────────────────────────────────────────────────────
// Slot envelope layout (§5.3 / §6.1 / §6.2)
//
// Each blob written through SlotStore is laid out by host.zig as:
//   [00..04]   format_version (u32 LE) = 1
//   [04..08]   tier (u32 LE) — 0=HOT, 1..3=base keys (used as KEK selector)
//   [08..20]   nonce (12 bytes, AES-GCM standard)
//   [20..36]   tag   (16 bytes, AES-GCM auth tag)
//   [36..]     ciphertext (cell payload, same length as plaintext)
//
// The (format_version || tier || nonce) prefix is bound to the ciphertext
// via the AAD — tampering with any of those bytes fails authentication.
// ──────────────────────────────────────────────────────────────────────

pub const SLOT_FORMAT_VERSION: u32 = 1;
pub const SLOT_NONCE_BYTES: usize = 12;
pub const SLOT_TAG_BYTES: usize = 16;
pub const SLOT_HEADER_BYTES: usize = 4 + 4 + SLOT_NONCE_BYTES + SLOT_TAG_BYTES; // = 36

// ──────────────────────────────────────────────────────────────────────
// Stubs for v0.2 / v0.3 — the same vtable, no-op until backing impls
// land in their respective phases. Placed here so that the integration
// points are pinned in source from day one (per design §10.1 / §10.2).
// ──────────────────────────────────────────────────────────────────────

/// v0.2 stub: IndexedDBSlotStore — browser-side persistent storage layered
/// over IndexedDB via the host.js bridge. v0.1 stub returns
/// `persistence_failed` for every operation so misuse is loud.
pub const IndexedDBSlotStore = struct {
    pub fn init() IndexedDBSlotStore {
        return .{};
    }
    pub fn store(_: *IndexedDBSlotStore) SlotStore {
        return .{
            .ctx = undefined,
            .vtable = &stub_vtable,
        };
    }
    fn err1(_: *anyopaque, _: u32) StoreError![]const u8 {
        return error.persistence_failed;
    }
    fn err2(_: *anyopaque, _: u32, _: []const u8) StoreError!void {
        return error.persistence_failed;
    }
    fn err3(_: *anyopaque, _: u32) StoreError!void {
        return error.persistence_failed;
    }
    const stub_vtable: SlotStore.VTable = .{
        .get = err1,
        .put = err2,
        .delete = err3,
    };
};

/// v0.3 stub: LmdbSlotStore — sovereign-node persistent storage using
/// memory-mapped lmdb. Same shape as IndexedDBSlotStore but backed by a
/// local on-disk database file.
pub const LmdbSlotStore = struct {
    pub fn init() LmdbSlotStore {
        return .{};
    }
    pub fn store(_: *LmdbSlotStore) SlotStore {
        return .{
            .ctx = undefined,
            .vtable = &stub_vtable,
        };
    }
    fn err1(_: *anyopaque, _: u32) StoreError![]const u8 {
        return error.persistence_failed;
    }
    fn err2(_: *anyopaque, _: u32, _: []const u8) StoreError!void {
        return error.persistence_failed;
    }
    fn err3(_: *anyopaque, _: u32) StoreError!void {
        return error.persistence_failed;
    }
    const stub_vtable: SlotStore.VTable = .{
        .get = err1,
        .put = err2,
        .delete = err3,
    };
};

```
