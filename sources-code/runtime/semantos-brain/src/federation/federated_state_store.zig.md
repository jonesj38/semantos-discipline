---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/federation/federated_state_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.282112+00:00
---

# runtime/semantos-brain/src/federation/federated_state_store.zig

```zig
// M7.4 — FederatedSemantosStateStore vtable implementation.
//
// Routes each DerivationStateStore operation to either the local backing
// store or a remote peer, based on the slot derived from the protocol_hash.
//
// Slot derivation: bytes 0–3 of protocol_hash interpreted as u32 little-endian.
// This is intentionally simple — the same deterministic rule is used by the
// tests so routing is predictable and testable without network fixtures.
//
// For remote operations, the call is recorded in an RpcLog (stub transport).
// Actual network delivery is out of scope for M7.4.

const std = @import("std");
const derivation_state_mod = @import("derivation_state");
const slot_router = @import("slot_router");
const rpc_log_mod = @import("rpc_log");

const DerivationStateStore = derivation_state_mod.DerivationStateStore;
const Record = derivation_state_mod.Record;
const StoreError = derivation_state_mod.StoreError;
const SlotRouter = slot_router.SlotRouter;
const RpcLog = rpc_log_mod.RpcLog;
const RpcEntry = rpc_log_mod.RpcEntry;

/// Derive a slot number from a protocol_hash: bytes 0–3 as u32 LE.
fn slotFromProtocolHash(protocol_hash: *const [16]u8) u32 {
    return std.mem.readInt(u32, protocol_hash[0..4], .little);
}

pub const FederatedSemantosStateStore = struct {
    local: DerivationStateStore,
    router: *const SlotRouter,
    local_peer_id: [32]u8,
    rpc_log: *RpcLog,

    pub fn init(
        local: DerivationStateStore,
        router: *const SlotRouter,
        local_peer_id: [32]u8,
        rpc_log: *RpcLog,
    ) FederatedSemantosStateStore {
        return .{
            .local = local,
            .router = router,
            .local_peer_id = local_peer_id,
            .rpc_log = rpc_log,
        };
    }

    pub fn store(self: *FederatedSemantosStateStore) DerivationStateStore {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    // ── Routing helpers ──────────────────────────────────────────────────

    fn isLocal(self: *const FederatedSemantosStateStore, protocol_hash: *const [16]u8) bool {
        const slot = slotFromProtocolHash(protocol_hash);
        const peer = self.router.slotToPeer(slot) catch return true; // single peer → local
        return std.mem.eql(u8, &peer, &self.local_peer_id);
    }

    fn remotePeer(self: *const FederatedSemantosStateStore, protocol_hash: *const [16]u8) [32]u8 {
        const slot = slotFromProtocolHash(protocol_hash);
        return self.router.slotToPeer(slot) catch self.local_peer_id;
    }

    // ── VTable functions ─────────────────────────────────────────────────

    /// get_index: local → delegate; remote → log read_state, return null.
    fn vGetIndex(
        ctx: *anyopaque,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) ?u64 {
        const self: *FederatedSemantosStateStore = @ptrCast(@alignCast(ctx));
        if (self.isLocal(protocol_hash)) {
            return self.local.getIndex(protocol_hash, counterparty);
        }
        const peer = self.remotePeer(protocol_hash);
        const slot = slotFromProtocolHash(protocol_hash);
        self.rpc_log.append(.{ .op = .read_state, .slot = slot, .peer_id = peer });
        return null;
    }

    /// next_index: local → delegate; remote → log write_state, return 0 stub.
    fn vNextIndex(
        ctx: *anyopaque,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) StoreError!u64 {
        const self: *FederatedSemantosStateStore = @ptrCast(@alignCast(ctx));
        if (self.isLocal(protocol_hash)) {
            return self.local.nextIndex(protocol_hash, counterparty);
        }
        const peer = self.remotePeer(protocol_hash);
        const slot = slotFromProtocolHash(protocol_hash);
        self.rpc_log.append(.{ .op = .write_state, .slot = slot, .peer_id = peer });
        return 0; // stub — actual index assigned by remote
    }

    /// snapshot: always delegates to local backing store.
    fn vSnapshot(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
    ) StoreError![]Record {
        const self: *FederatedSemantosStateStore = @ptrCast(@alignCast(ctx));
        return self.local.snapshot(allocator);
    }

    /// replay: always delegates to local backing store.
    fn vReplay(
        ctx: *anyopaque,
        records: []const Record,
    ) StoreError!void {
        const self: *FederatedSemantosStateStore = @ptrCast(@alignCast(ctx));
        return self.local.replay(records);
    }

    const vtable: DerivationStateStore.VTable = .{
        .get_index = vGetIndex,
        .next_index = vNextIndex,
        .snapshot = vSnapshot,
        .replay = vReplay,
    };
};

```
