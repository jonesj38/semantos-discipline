---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/derivation_state.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.982074+00:00
---

# core/cell-engine/src/derivation_state.zig

```zig
// Phase W3.5 — DerivationStateStore: tracks which BRC-42 indices have been used
// per (protocol, counterparty) context.
//
// Reference: docs/design/SEMANTOS-WALLET-TIERED-CUSTODY.md §3.5.2, §6.4.
//
// The wallet uses BRC-42 (BKDS) derivation to produce a fresh private key for
// every transaction. To avoid re-using indices (which would re-issue the same
// public key — privacy + security failure), it must persist a monotonic
// counter per (protocol, counterparty) context.
//
// This module defines the interface (`DerivationStateStore`) and ships a
// pure in-memory implementation (`LocalStateStore`). The browser bundle and
// sovereign-node target install backing implementations (IndexedDB / lmdb /
// federated mesh sync) under the same vtable in W4 / W6 / future phases.

const std = @import("std");

/// A single (protocol, counterparty) → index record. Matches §6.4 layout:
/// 16 bytes protocol_hash || 33 bytes counterparty || 8 bytes index = 57 bytes.
pub const Record = struct {
    protocol_hash: [16]u8,
    counterparty: [33]u8,
    current_index: u64,
};

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
};

/// Interface for the BRC-42 derivation state. Three planned backings, all
/// conforming to this vtable:
///   • LocalStateStore           — in-memory / IndexedDB (v0.1, ships)
///   • PlexusStateStore          — local + async mirror to Plexus servers
///   • FederatedSemantosStateStore — local + replication across sovereign nodes
pub const DerivationStateStore = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Look up the current index for a (protocol, counterparty) context.
        /// Returns null if the context has never been used.
        get_index: *const fn (
            ctx: *anyopaque,
            protocol_hash: *const [16]u8,
            counterparty: *const [33]u8,
        ) ?u64,

        /// Atomically allocate and persist the next index. The returned
        /// value is guaranteed never to be returned again for the same
        /// context. Persistence failure must surface as `persistence_failed`
        /// — the caller must NOT use the returned index in that case.
        next_index: *const fn (
            ctx: *anyopaque,
            protocol_hash: *const [16]u8,
            counterparty: *const [33]u8,
        ) StoreError!u64,

        /// Snapshot all (context, index) records. Used by the dispatch
        /// envelope builder (§8.2) and recovery sync.
        snapshot: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
        ) StoreError![]Record,

        /// Replay a snapshot from an external source (recovery, federated sync).
        /// Replaces the existing state — does not merge.
        replay: *const fn (
            ctx: *anyopaque,
            records: []const Record,
        ) StoreError!void,
    };

    pub fn getIndex(
        self: *const DerivationStateStore,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) ?u64 {
        return self.vtable.get_index(self.ctx, protocol_hash, counterparty);
    }

    pub fn nextIndex(
        self: *const DerivationStateStore,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) StoreError!u64 {
        return self.vtable.next_index(self.ctx, protocol_hash, counterparty);
    }

    pub fn snapshot(
        self: *const DerivationStateStore,
        allocator: std.mem.Allocator,
    ) StoreError![]Record {
        return self.vtable.snapshot(self.ctx, allocator);
    }

    pub fn replay(
        self: *const DerivationStateStore,
        records: []const Record,
    ) StoreError!void {
        return self.vtable.replay(self.ctx, records);
    }
};

/// In-memory implementation. Suitable for native tests and as the default
/// backing layer of the browser/node wallets (each wraps it in storage I/O).
pub const LocalStateStore = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap(Key, u64),

    const Key = [16 + 33]u8;

    pub fn init(allocator: std.mem.Allocator) LocalStateStore {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(Key, u64).init(allocator),
        };
    }

    pub fn deinit(self: *LocalStateStore) void {
        self.map.deinit();
    }

    pub fn store(self: *LocalStateStore) DerivationStateStore {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &local_vtable,
        };
    }

    fn keyFor(protocol_hash: *const [16]u8, counterparty: *const [33]u8) Key {
        var k: Key = undefined;
        @memcpy(k[0..16], protocol_hash);
        @memcpy(k[16..49], counterparty);
        return k;
    }

    fn vGetIndex(
        ctx: *anyopaque,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) ?u64 {
        const self: *LocalStateStore = @ptrCast(@alignCast(ctx));
        return self.map.get(keyFor(protocol_hash, counterparty));
    }

    fn vNextIndex(
        ctx: *anyopaque,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) StoreError!u64 {
        const self: *LocalStateStore = @ptrCast(@alignCast(ctx));
        const k = keyFor(protocol_hash, counterparty);
        const next = if (self.map.get(k)) |cur| cur + 1 else @as(u64, 0);
        self.map.put(k, next) catch return error.out_of_memory;
        return next;
    }

    fn vSnapshot(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
    ) StoreError![]Record {
        const self: *LocalStateStore = @ptrCast(@alignCast(ctx));
        var records = allocator.alloc(Record, self.map.count()) catch return error.out_of_memory;
        var it = self.map.iterator();
        var i: usize = 0;
        while (it.next()) |entry| : (i += 1) {
            var r: Record = undefined;
            @memcpy(&r.protocol_hash, entry.key_ptr.*[0..16]);
            @memcpy(&r.counterparty, entry.key_ptr.*[16..49]);
            r.current_index = entry.value_ptr.*;
            records[i] = r;
        }
        return records;
    }

    fn vReplay(
        ctx: *anyopaque,
        records: []const Record,
    ) StoreError!void {
        const self: *LocalStateStore = @ptrCast(@alignCast(ctx));
        self.map.clearRetainingCapacity();
        for (records) |r| {
            self.map.put(keyFor(&r.protocol_hash, &r.counterparty), r.current_index) catch return error.out_of_memory;
        }
    }

    const local_vtable: DerivationStateStore.VTable = .{
        .get_index = vGetIndex,
        .next_index = vNextIndex,
        .snapshot = vSnapshot,
        .replay = vReplay,
    };
};

// ──────────────────────────────────────────────────────────────────────
// DerivationState cell layout (§6.4)
//
// Header: linearity=RELEVANT, domain_flag=0x10000020 (DERIVATION_STATE)
// Payload:
//   [00..04]   record_count (u32 LE)
//   [04..08]   format_version (u32 LE) = 1
//   [08..16]   reserved (u64)
//   [16..]     records: protocol_hash(16) || counterparty(33) || index_le_8
//                = 57 bytes per record
//                ~13 records per 768-byte payload (continuation cells handle more)
// ──────────────────────────────────────────────────────────────────────

pub const DERIVATION_STATE_FORMAT_VERSION: u32 = 1;
pub const DERIVATION_STATE_RECORD_BYTES: u32 = 16 + 33 + 8;
pub const DERIVATION_STATE_PAYLOAD_HEADER_BYTES: u32 = 16; // record_count + format_version + reserved
pub const DERIVATION_STATE_DOMAIN_FLAG: u32 = 0x10000020;

/// Serialize a list of records into a payload buffer (size-bounded — caller
/// supplies). Returns the number of bytes written. Returns
/// `out_of_memory` if `records` would exceed `payload_buf.len`.
pub fn packPayload(records: []const Record, payload_buf: []u8) StoreError!usize {
    const required = DERIVATION_STATE_PAYLOAD_HEADER_BYTES +
        DERIVATION_STATE_RECORD_BYTES * @as(u32, @intCast(records.len));
    if (required > payload_buf.len) return error.out_of_memory;

    std.mem.writeInt(u32, payload_buf[0..4], @intCast(records.len), .little);
    std.mem.writeInt(u32, payload_buf[4..8], DERIVATION_STATE_FORMAT_VERSION, .little);
    std.mem.writeInt(u64, payload_buf[8..16], 0, .little); // reserved

    var off: usize = DERIVATION_STATE_PAYLOAD_HEADER_BYTES;
    for (records) |r| {
        @memcpy(payload_buf[off .. off + 16], &r.protocol_hash);
        off += 16;
        @memcpy(payload_buf[off .. off + 33], &r.counterparty);
        off += 33;
        std.mem.writeInt(u64, payload_buf[off..][0..8], r.current_index, .little);
        off += 8;
    }
    return required;
}

/// Deserialize a payload buffer back into a slice of records.
/// The caller owns the returned slice (must free via `allocator`).
pub fn unpackPayload(payload: []const u8, allocator: std.mem.Allocator) StoreError![]Record {
    if (payload.len < DERIVATION_STATE_PAYLOAD_HEADER_BYTES) return error.persistence_failed;
    const count = std.mem.readInt(u32, payload[0..4], .little);
    const version = std.mem.readInt(u32, payload[4..8], .little);
    if (version != DERIVATION_STATE_FORMAT_VERSION) return error.persistence_failed;

    const required = DERIVATION_STATE_PAYLOAD_HEADER_BYTES +
        DERIVATION_STATE_RECORD_BYTES * count;
    if (required > payload.len) return error.persistence_failed;

    var records = allocator.alloc(Record, count) catch return error.out_of_memory;
    var off: usize = DERIVATION_STATE_PAYLOAD_HEADER_BYTES;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var r: Record = undefined;
        @memcpy(&r.protocol_hash, payload[off .. off + 16]);
        off += 16;
        @memcpy(&r.counterparty, payload[off .. off + 33]);
        off += 33;
        r.current_index = std.mem.readInt(u64, payload[off..][0..8], .little);
        off += 8;
        records[i] = r;
    }
    return records;
}

// ──────────────────────────────────────────────────────────────────────
// Stubs for v0.2 / v0.3 — the same vtable, no-op until backing impls
// land in their respective phases. Placed here so that the integration
// points are pinned in source from day one (per design §3.5.2).
// ──────────────────────────────────────────────────────────────────────

/// v0.2 stub: PlexusStateStore — local persistence + async mirror to
/// `plexus-keys.com/state/checkpoint` after each increment, with fall-through
/// to local on network failure. v0.1 stub returns `persistence_failed` for
/// every operation so misuse is loud.
pub const PlexusStateStore = struct {
    pub fn init() PlexusStateStore {
        return .{};
    }
    pub fn store(_: *PlexusStateStore) DerivationStateStore {
        return .{
            .ctx = undefined,
            .vtable = &stub_vtable,
        };
    }
    fn err1(_: *anyopaque, _: *const [16]u8, _: *const [33]u8) ?u64 {
        return null;
    }
    fn err2(_: *anyopaque, _: *const [16]u8, _: *const [33]u8) StoreError!u64 {
        return error.persistence_failed;
    }
    fn err3(_: *anyopaque, _: std.mem.Allocator) StoreError![]Record {
        return error.persistence_failed;
    }
    fn err4(_: *anyopaque, _: []const Record) StoreError!void {
        return error.persistence_failed;
    }
    const stub_vtable: DerivationStateStore.VTable = .{
        .get_index = err1,
        .next_index = err2,
        .snapshot = err3,
        .replay = err4,
    };
};

/// v0.3 stub: FederatedSemantosStateStore — local persistence + replication
/// across the user's own sovereign nodes via the federated mesh. Same shape
/// as PlexusStateStore but no third-party involved.
pub const FederatedSemantosStateStore = struct {
    pub fn init() FederatedSemantosStateStore {
        return .{};
    }
    pub fn store(_: *FederatedSemantosStateStore) DerivationStateStore {
        return .{
            .ctx = undefined,
            .vtable = &stub_vtable,
        };
    }
    fn err1(_: *anyopaque, _: *const [16]u8, _: *const [33]u8) ?u64 {
        return null;
    }
    fn err2(_: *anyopaque, _: *const [16]u8, _: *const [33]u8) StoreError!u64 {
        return error.persistence_failed;
    }
    fn err3(_: *anyopaque, _: std.mem.Allocator) StoreError![]Record {
        return error.persistence_failed;
    }
    fn err4(_: *anyopaque, _: []const Record) StoreError!void {
        return error.persistence_failed;
    }
    const stub_vtable: DerivationStateStore.VTable = .{
        .get_index = err1,
        .next_index = err2,
        .snapshot = err3,
        .replay = err4,
    };
};

```
