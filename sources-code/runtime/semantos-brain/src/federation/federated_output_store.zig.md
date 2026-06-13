---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/federation/federated_output_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.282950+00:00
---

# runtime/semantos-brain/src/federation/federated_output_store.zig

```zig
// M7.2 — FederatedSemantosOutputStore vtable implementation.
//
// Routes each OutputStore operation to either the local backing store or a
// remote peer, based on the slot derived from the outpoint's txid.
//
// Slot derivation: bytes 0–3 of txid interpreted as u32 little-endian.
// This is intentionally simple — the same deterministic rule is used by the
// tests so routing is predictable and testable without network fixtures.
//
// For remote operations, the call is recorded in an RpcLog (stub transport).
// Actual network delivery is out of scope for M7.2.

const std = @import("std");
const output_store = @import("output_store");
const slot_router = @import("slot_router");
const rpc_log_mod = @import("rpc_log");

const OutputStore = output_store.OutputStore;
const OutputRecord = output_store.OutputRecord;
const Outpoint = output_store.Outpoint;
const StoreError = output_store.StoreError;
const SlotRouter = slot_router.SlotRouter;
const RpcLog = rpc_log_mod.RpcLog;
const RpcEntry = rpc_log_mod.RpcEntry;

/// Derive a slot number from an outpoint: bytes 0–3 of txid as u32 LE.
fn slotFromOutpoint(op: Outpoint) u32 {
    return std.mem.readInt(u32, op.txid[0..4], .little);
}

pub const FederatedSemantosOutputStore = struct {
    local: OutputStore,
    router: *const SlotRouter,
    local_peer_id: [32]u8,
    rpc_log: *RpcLog,

    pub fn init(
        local: OutputStore,
        router: *const SlotRouter,
        local_peer_id: [32]u8,
        rpc_log: *RpcLog,
    ) FederatedSemantosOutputStore {
        return .{
            .local = local,
            .router = router,
            .local_peer_id = local_peer_id,
            .rpc_log = rpc_log,
        };
    }

    pub fn store(self: *FederatedSemantosOutputStore) OutputStore {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    // ── Routing helpers ──────────────────────────────────────────────────

    fn isLocal(self: *const FederatedSemantosOutputStore, outpoint: Outpoint) bool {
        const slot = slotFromOutpoint(outpoint);
        const peer = self.router.slotToPeer(slot) catch return true; // single peer → local
        return std.mem.eql(u8, &peer, &self.local_peer_id);
    }

    fn remotePeer(self: *const FederatedSemantosOutputStore, outpoint: Outpoint) [32]u8 {
        const slot = slotFromOutpoint(outpoint);
        return self.router.slotToPeer(slot) catch self.local_peer_id;
    }

    // ── VTable functions ─────────────────────────────────────────────────

    fn vAddOutput(ctx: *anyopaque, record: OutputRecord) StoreError!void {
        const self: *FederatedSemantosOutputStore = @ptrCast(@alignCast(ctx));
        if (self.isLocal(record.outpoint)) {
            return self.local.addOutput(record);
        }
        const peer = self.remotePeer(record.outpoint);
        const slot = slotFromOutpoint(record.outpoint);
        self.rpc_log.append(.{ .op = .write_output, .slot = slot, .peer_id = peer });
    }

    fn vListOutputs(
        ctx: *anyopaque,
        basket_filter: ?[]const u8,
        tag_filter: ?[]const u8,
        allocator: std.mem.Allocator,
    ) StoreError![]OutputRecord {
        const self: *FederatedSemantosOutputStore = @ptrCast(@alignCast(ctx));
        // For list operations, return local results only (remote aggregation
        // is out of scope for M7.2).
        return self.local.listOutputs(basket_filter, tag_filter, allocator);
    }

    fn vGetOutput(ctx: *anyopaque, outpoint: Outpoint) ?OutputRecord {
        const self: *FederatedSemantosOutputStore = @ptrCast(@alignCast(ctx));
        if (self.isLocal(outpoint)) {
            return self.local.getOutput(outpoint);
        }
        // Remote read: log the attempt, return null (stub).
        const peer = self.remotePeer(outpoint);
        const slot = slotFromOutpoint(outpoint);
        self.rpc_log.append(.{ .op = .read_output, .slot = slot, .peer_id = peer });
        return null;
    }

    fn vMarkSpent(
        ctx: *anyopaque,
        outpoint: Outpoint,
        spending_txid: [32]u8,
    ) StoreError!void {
        const self: *FederatedSemantosOutputStore = @ptrCast(@alignCast(ctx));
        if (self.isLocal(outpoint)) {
            return self.local.markSpent(outpoint, spending_txid);
        }
        const peer = self.remotePeer(outpoint);
        const slot = slotFromOutpoint(outpoint);
        self.rpc_log.append(.{ .op = .write_output, .slot = slot, .peer_id = peer });
    }

    fn vPruneConfirmed(ctx: *anyopaque, min_confirmations: u32) StoreError!u64 {
        const self: *FederatedSemantosOutputStore = @ptrCast(@alignCast(ctx));
        return self.local.pruneConfirmed(min_confirmations);
    }

    fn vSnapshot(ctx: *anyopaque, allocator: std.mem.Allocator) StoreError![]OutputRecord {
        const self: *FederatedSemantosOutputStore = @ptrCast(@alignCast(ctx));
        return self.local.snapshot(allocator);
    }

    fn vReplay(ctx: *anyopaque, records: []const OutputRecord) StoreError!void {
        const self: *FederatedSemantosOutputStore = @ptrCast(@alignCast(ctx));
        return self.local.replay(records);
    }

    const vtable: OutputStore.VTable = .{
        .add_output = vAddOutput,
        .list_outputs = vListOutputs,
        .get_output = vGetOutput,
        .mark_spent = vMarkSpent,
        .prune_confirmed = vPruneConfirmed,
        .snapshot = vSnapshot,
        .replay = vReplay,
    };
};

```
