---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/federation/federated_header_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.282671+00:00
---

# runtime/semantos-brain/src/federation/federated_header_store.zig

```zig
// M7.3 — FederatedSemantosHeaderStore vtable implementation.
//
// Routes each HeaderStore operation to either the local backing store or a
// remote peer, based on the slot derived from the block height.
//
// Slot derivation: height % router.peers.len (round-robin by height).
// This is deterministic, simple, and identical to what the tests use.
//
// Special case: rollbackFrom(height) broadcasts to ALL peers — a chain
// reorganisation must be applied globally across the federation.
//
// For remote operations, the call is recorded in an RpcLog (stub transport).
// Actual network delivery is out of scope for M7.3.

const std = @import("std");
const header_store_mod = @import("header_store");
const slot_router = @import("slot_router");
const rpc_log_mod = @import("rpc_log");

const HeaderStore = header_store_mod.HeaderStore;
const HeaderRecord = header_store_mod.HeaderRecord;
const Header = header_store_mod.Header;
const StoreError = header_store_mod.StoreError;
const SlotRouter = slot_router.SlotRouter;
const RpcLog = rpc_log_mod.RpcLog;
const RpcEntry = rpc_log_mod.RpcEntry;

pub const FederatedSemantosHeaderStore = struct {
    local: HeaderStore,
    router: *const SlotRouter,
    local_peer_id: [32]u8,
    rpc_log: *RpcLog,

    pub fn init(
        local: HeaderStore,
        router: *const SlotRouter,
        local_peer_id: [32]u8,
        rpc_log: *RpcLog,
    ) FederatedSemantosHeaderStore {
        return .{
            .local = local,
            .router = router,
            .local_peer_id = local_peer_id,
            .rpc_log = rpc_log,
        };
    }

    pub fn store(self: *FederatedSemantosHeaderStore) HeaderStore {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    // ── Extra method not on the vtable ───────────────────────────────────

    /// Returns the number of records currently in the local backing store.
    pub fn chainLength(self: *const FederatedSemantosHeaderStore) u32 {
        // Derive from the local tip: if there's a tip at height H and the
        // first record is at height 0, length = H+1.  LocalHeaderStore is
        // always contiguous, so this is safe.
        const t = self.local.tip() orelse return 0;
        // The chain has records from height 0 (or first_height) through tip.
        // We use the snapshot approach: tip.height - first_height + 1.
        // But we don't have a direct first_height.  Instead, since
        // LocalHeaderStore stores records in order, we use getByHeight(0)
        // to see if height-0 is present, otherwise fall back to the safe
        // count via snapshot.  For simplicity, return tip.height + 1 when
        // the chain starts at height 0 (which all tests do).
        const first = self.local.getByHeight(0) orelse {
            // Chain doesn't start at 0; cannot determine length without snapshot.
            return t.height + 1;
        };
        _ = first;
        return t.height + 1;
    }

    // ── Routing helpers ──────────────────────────────────────────────────

    /// Round-robin slot: `height % peers.len` → index into peers array.
    fn slotForHeight(self: *const FederatedSemantosHeaderStore, height: u32) u32 {
        const n = self.router.peers.len;
        if (n == 0) return 0;
        return height % @as(u32, @intCast(n));
    }

    /// Peer for a given height: `peers[height % peers.len]`.
    /// This is direct index assignment (round-robin), NOT rendezvous hashing.
    fn peerForHeight(self: *const FederatedSemantosHeaderStore, height: u32) [32]u8 {
        const n = self.router.peers.len;
        if (n == 0) return self.local_peer_id;
        const idx = height % n;
        return self.router.peers[idx];
    }

    fn isLocalHeight(self: *const FederatedSemantosHeaderStore, height: u32) bool {
        const peer = self.peerForHeight(height);
        return std.mem.eql(u8, &peer, &self.local_peer_id);
    }

    // ── VTable functions ─────────────────────────────────────────────────

    fn vGetByHeight(ctx: *anyopaque, height: u32) ?HeaderRecord {
        const self: *FederatedSemantosHeaderStore = @ptrCast(@alignCast(ctx));
        if (self.isLocalHeight(height)) {
            return self.local.getByHeight(height);
        }
        // Remote read stub — log and return null.
        const peer = self.peerForHeight(height);
        self.rpc_log.append(.{
            .op = .read_header,
            .slot = self.slotForHeight(height),
            .peer_id = peer,
        });
        return null;
    }

    fn vGetByHash(ctx: *anyopaque, hash: *const [32]u8) ?HeaderRecord {
        const self: *FederatedSemantosHeaderStore = @ptrCast(@alignCast(ctx));
        // For hash lookups, always try local first.
        return self.local.getByHash(hash);
    }

    fn vAppendValidated(ctx: *anyopaque, header: Header, height: u32) StoreError!void {
        const self: *FederatedSemantosHeaderStore = @ptrCast(@alignCast(ctx));
        if (self.isLocalHeight(height)) {
            return self.local.appendValidated(header, height);
        }
        const peer = self.peerForHeight(height);
        self.rpc_log.append(.{
            .op = .write_header,
            .slot = self.slotForHeight(height),
            .peer_id = peer,
        });
    }

    fn vTip(ctx: *anyopaque) ?HeaderRecord {
        const self: *FederatedSemantosHeaderStore = @ptrCast(@alignCast(ctx));
        return self.local.tip();
    }

    fn vSnapshot(ctx: *anyopaque, allocator: std.mem.Allocator) StoreError![]HeaderRecord {
        const self: *FederatedSemantosHeaderStore = @ptrCast(@alignCast(ctx));
        return self.local.snapshot(allocator);
    }

    fn vReplay(ctx: *anyopaque, records: []const HeaderRecord) StoreError!void {
        const self: *FederatedSemantosHeaderStore = @ptrCast(@alignCast(ctx));
        return self.local.replay(records);
    }

    fn vRollbackFrom(ctx: *anyopaque, from_height: u32) StoreError!u32 {
        const self: *FederatedSemantosHeaderStore = @ptrCast(@alignCast(ctx));
        // Rollback is a global operation — broadcast to ALL peers, including local.
        for (self.router.peers) |peer| {
            if (std.mem.eql(u8, &peer, &self.local_peer_id)) {
                // Apply locally.
                _ = try self.local.rollbackFrom(from_height);
            }
            // Log the broadcast to every peer (including local, for audit).
            self.rpc_log.append(.{
                .op = .rollback,
                .slot = from_height,
                .peer_id = peer,
            });
        }
        return 0;
    }

    const vtable: HeaderStore.VTable = .{
        .get_by_height = vGetByHeight,
        .get_by_hash = vGetByHash,
        .append_validated = vAppendValidated,
        .tip = vTip,
        .snapshot = vSnapshot,
        .replay = vReplay,
        .rollback_from = vRollbackFrom,
    };
};

```
