---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/federated_header_store_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.179913+00:00
---

# runtime/semantos-brain/tests/federated_header_store_test.zig

```zig
// M7.3 — FederatedSemantosHeaderStore conformance tests.
//
// TDD red phase: tests written against the interface contract before the
// implementation exists.  They fail until the green commit lands
// `federated_header_store.zig`.

const std = @import("std");
const header_store_mod = @import("header_store");
const fed_header_store_mod = @import("federated_header_store");
const rpc_log_mod = @import("rpc_log");
const slot_router_mod = @import("slot_router");
const headers_mod = @import("headers");

const HeaderStore = header_store_mod.HeaderStore;
const HeaderRecord = header_store_mod.HeaderRecord;
const LocalHeaderStore = header_store_mod.LocalHeaderStore;
const Header = header_store_mod.Header;
const FederatedSemantosHeaderStore = fed_header_store_mod.FederatedSemantosHeaderStore;
const RpcLog = rpc_log_mod.RpcLog;
const RpcEntry = rpc_log_mod.RpcEntry;
const SlotRouter = slot_router_mod.SlotRouter;

// ── Helper: produce a syntactically valid-looking Header at a given height ─

fn makeHeader(height: u32) Header {
    // prev_hash and merkle_root are all-zeros; PoW not verified by the
    // LocalHeaderStore (it trusts the caller), so this is fine for tests.
    _ = height;
    return .{
        .version = 1,
        .prev_hash = [_]u8{0} ** 32,
        .merkle_root = [_]u8{0} ** 32,
        .timestamp = 0,
        .bits = 0x1d00ffff,
        .nonce = 0,
    };
}

// Make a chain of headers, each linking to the previous, for LocalHeaderStore.
// Returns a slice; caller must free.
fn makeChain(allocator: std.mem.Allocator, n: u32) ![]Header {
    const chain = try allocator.alloc(Header, n);
    var prev_hash = [_]u8{0} ** 32;
    for (0..n) |i| {
        chain[i] = .{
            .version = 1,
            .prev_hash = prev_hash,
            .merkle_root = [_]u8{@intCast(i)} ** 32,
            .timestamp = @intCast(i),
            .bits = 0x1d00ffff,
            .nonce = 0,
        };
        prev_hash = chain[i].computeHash();
    }
    return chain;
}

// ── M7.3-T-local-put ──────────────────────────────────────────────────────
//
// height % peers.len → local peer; appendValidated delegates to local store.

test "M7.3-T-local-put" {
    const allocator = std.testing.allocator;

    // Use 3 peers so we can test round-robin slot assignment clearly.
    const peer_a = [_]u8{0xAA} ** 32;
    const peer_b = [_]u8{0xBB} ** 32;
    const peer_c = [_]u8{0xCC} ** 32;
    const peers = [_][32]u8{ peer_a, peer_b, peer_c };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalHeaderStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    // We are peer_a (index 0).  Height 0 → slot = 0 % 3 = 0 → peer_a.
    var fed = FederatedSemantosHeaderStore.init(local.store(), &router, peer_a, &rpc_log);
    const s = fed.store();

    const chain = try makeChain(allocator, 1);
    defer allocator.free(chain);

    try s.appendValidated(chain[0], 0);

    // rpc_log must be empty — this was a local write.
    try std.testing.expectEqual(@as(usize, 0), rpc_log.slice().len);

    // Local store must hold the record.
    const got = local.store().getByHeight(0);
    try std.testing.expect(got != null);
}

// ── M7.3-T-remote-put ─────────────────────────────────────────────────────
//
// height % peers.len → remote peer; rpc_log has write_header entry.

test "M7.3-T-remote-put" {
    const allocator = std.testing.allocator;

    const peer_a = [_]u8{0xAA} ** 32;
    const peer_b = [_]u8{0xBB} ** 32;
    const peer_c = [_]u8{0xCC} ** 32;
    const peers = [_][32]u8{ peer_a, peer_b, peer_c };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalHeaderStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    // We are peer_a (index 0).  Height 1 → slot = 1 % 3 = 1 → peer_b.
    var fed = FederatedSemantosHeaderStore.init(local.store(), &router, peer_a, &rpc_log);
    const s = fed.store();

    const chain = try makeChain(allocator, 2);
    defer allocator.free(chain);

    // Height 1 routes to peer_b.
    try s.appendValidated(chain[1], 1);

    const entries = rpc_log.slice();
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqual(RpcEntry.Op.write_header, entries[0].op);
    try std.testing.expectEqualSlices(u8, &peer_b, &entries[0].peer_id);

    // Local store must be empty.
    try std.testing.expect(local.store().getByHeight(1) == null);
}

// ── M7.3-T-tip ────────────────────────────────────────────────────────────
//
// tip() queries local store and returns local tip.

test "M7.3-T-tip" {
    const allocator = std.testing.allocator;

    const peer_a = [_]u8{0xAA} ** 32;
    const peer_b = [_]u8{0xBB} ** 32;
    const peer_c = [_]u8{0xCC} ** 32;
    const peers = [_][32]u8{ peer_a, peer_b, peer_c };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalHeaderStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    var fed = FederatedSemantosHeaderStore.init(local.store(), &router, peer_a, &rpc_log);
    const s = fed.store();

    // Initially no tip.
    try std.testing.expect(s.tip() == null);

    // Add height 0 locally (slot 0 % 3 = 0 → peer_a).
    const chain = try makeChain(allocator, 1);
    defer allocator.free(chain);
    try s.appendValidated(chain[0], 0);

    const tip = s.tip();
    try std.testing.expect(tip != null);
    try std.testing.expectEqual(@as(u32, 0), tip.?.height);
}

// ── M7.3-T-rollback-broadcasts ────────────────────────────────────────────
//
// rollbackFrom(height) with 3 peers; rpc_log has 3 entries (one per peer).

test "M7.3-T-rollback-broadcasts" {
    const allocator = std.testing.allocator;

    const peer_a = [_]u8{0xAA} ** 32;
    const peer_b = [_]u8{0xBB} ** 32;
    const peer_c = [_]u8{0xCC} ** 32;
    const peers = [_][32]u8{ peer_a, peer_b, peer_c };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalHeaderStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    var fed = FederatedSemantosHeaderStore.init(local.store(), &router, peer_a, &rpc_log);
    const s = fed.store();

    rpc_log.clear();

    // rollbackFrom must broadcast to ALL 3 peers.
    _ = try s.rollbackFrom(5);

    const entries = rpc_log.slice();
    try std.testing.expectEqual(@as(usize, 3), entries.len);

    // All entries must be rollback ops.
    for (entries) |e| {
        try std.testing.expectEqual(RpcEntry.Op.rollback, e.op);
    }

    // Each peer must appear exactly once.
    var saw_a = false;
    var saw_b = false;
    var saw_c = false;
    for (entries) |e| {
        if (std.mem.eql(u8, &e.peer_id, &peer_a)) saw_a = true;
        if (std.mem.eql(u8, &e.peer_id, &peer_b)) saw_b = true;
        if (std.mem.eql(u8, &e.peer_id, &peer_c)) saw_c = true;
    }
    try std.testing.expect(saw_a);
    try std.testing.expect(saw_b);
    try std.testing.expect(saw_c);
}

// ── M7.3-T-chain-length ───────────────────────────────────────────────────
//
// chainLength() returns the count of records in the local store.

test "M7.3-T-chain-length" {
    const allocator = std.testing.allocator;

    const peer_a = [_]u8{0xAA} ** 32;
    const peer_b = [_]u8{0xBB} ** 32;
    const peer_c = [_]u8{0xCC} ** 32;
    const peers = [_][32]u8{ peer_a, peer_b, peer_c };
    const router = SlotRouter.init(allocator, &peers);

    var local = LocalHeaderStore.init(allocator);
    defer local.deinit();
    var rpc_log = RpcLog.init();

    var fed = FederatedSemantosHeaderStore.init(local.store(), &router, peer_a, &rpc_log);
    const s = fed.store();

    // Initially zero — chainLength is on the concrete struct (not the vtable).
    try std.testing.expectEqual(@as(u32, 0), fed.chainLength());

    // Add height 0 locally (slot 0 % 3 = 0 → peer_a).
    const chain = try makeChain(allocator, 1);
    defer allocator.free(chain);
    try s.appendValidated(chain[0], 0);

    try std.testing.expectEqual(@as(u32, 1), fed.chainLength());
}

```
