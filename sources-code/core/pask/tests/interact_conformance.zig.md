---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/tests/interact_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.929210+00:00
---

# core/pask/tests/interact_conformance.zig

```zig
// End-to-end interact() conformance.
//
// The kernel's interact pipeline is in main.zig — but we don't link main
// here (it has WASM-only externs). We re-implement the same compose
// against the modules directly. If this stays in lockstep with main.zig,
// the tests double as documentation of the loop.

const std = @import("std");
const testing = std.testing;
const config = @import("config");
const types = @import("types");
const store_mod = @import("store");
const propagation = @import("propagation");
const stability_mod = @import("stability");
const pruner_mod = @import("pruner");

const Store = store_mod.Store;
const Affected = propagation.Affected;
const NodeIdx = types.NodeIdx;

const Engine = struct {
    store: Store,
    affected: Affected,
    tick: u64,

    fn init(self: *Engine, cfg: config.Config) void {
        self.store.init(cfg);
        self.affected.init();
        self.tick = 0;
    }

    fn interact(
        self: *Engine,
        primary_idx: NodeIdx,
        effective_strength: f64,
        related: []const NodeIdx,
        now_ms: u64,
    ) !void {
        self.affected.init();
        _ = try self.affected.add(primary_idx);
        for (related) |r| {
            const e = try self.store.upsertEdge(primary_idx, r, now_ms);
            const w_delta = effective_strength * self.store.cfg.learning_rate;
            self.store.updateEdgeWeight(e, w_delta, now_ms);
            self.store.recordDelta(e, w_delta, now_ms);
            _ = try self.affected.add(r);
        }
        self.store.updateNodeState(primary_idx, effective_strength, now_ms);

        try propagation.propagate(&self.store, &self.affected, now_ms);
        self.tick += 1;

        if (self.store.cfg.stability_check_every > 0 and
            self.tick % self.store.cfg.stability_check_every == 0)
        {
            var i: u32 = 0;
            while (i < self.affected.count) : (i += 1) {
                _ = stability_mod.checkNode(&self.store, self.affected.members[i], now_ms);
            }
        }
        if (self.store.cfg.prune_every > 0 and
            self.tick % self.store.cfg.prune_every == 0)
        {
            _ = pruner_mod.pruneOnce(&self.store, now_ms);
        }
    }
};

fn allocEngine(allocator: std.mem.Allocator, cfg: config.Config) !*Engine {
    const e = try allocator.create(Engine);
    e.init(cfg);
    return e;
}

fn upsert(eng: *Engine, name: []const u8, now: u64) !NodeIdx {
    return eng.store.upsertNode(name, "test", now);
}

test "single interact: primary h_state += effective_strength" {
    var cfg = config.DEFAULT;
    cfg.stability_check_every = 0;
    cfg.prune_every = 0;
    cfg.propagation_depth = 0; // isolate the direct update
    const eng = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng);

    const a = try upsert(eng, "A", 0);
    const b = try upsert(eng, "B", 0);
    const related = [_]NodeIdx{b};
    try eng.interact(a, 1.0, related[0..], 100);

    try testing.expectEqual(@as(f64, 1.0), eng.store.nodes[a].h_state);
    try testing.expectEqual(@as(u32, 1), eng.store.nodes[a].interaction_count);
    // A→B edge exists with weight = 1.0 * 0.1 = 0.1.
    const e = eng.store.findEdge(a, b);
    try testing.expect(e != types.NULL_IDX);
    try testing.expectApproxEqAbs(@as(f64, 0.1), eng.store.edges[e].constraint_weight, 1e-12);
}

test "high-traffic edges accumulate weight; rare edges stay weak" {
    // Synthetic mini-rig: opening 1 played 30×, opening 2 played once.
    // We assert structural learning — high-traffic edges have higher
    // constraint_weight + interaction_count than rare ones. Stability
    // proper is the chess conformance test's job, since it requires
    // the window-expiration dynamics that only emerge at scale.
    var cfg = config.DEFAULT;
    cfg.stability_check_every = 0;
    cfg.prune_every = 0;
    cfg.propagation_depth = 0; // isolate direct edge updates
    const eng = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng);

    const root = try upsert(eng, "root", 0);
    const a1 = try upsert(eng, "A1", 0);
    const b1 = try upsert(eng, "B1", 0);

    var clock: u64 = 0;
    var i: u32 = 0;
    while (i < 30) : (i += 1) {
        clock += 1;
        try eng.interact(root, 1.0, &[_]NodeIdx{a1}, clock);
        clock += 1;
        try eng.interact(a1, 1.0, &[_]NodeIdx{b1}, clock);
    }

    // Rare opening: root → a2 played once.
    const a2 = try upsert(eng, "A2", 0);
    clock += 1;
    try eng.interact(root, 1.0, &[_]NodeIdx{a2}, clock);

    // Edge weights: each interact adds strength * lr = 0.1.
    const e_root_a1 = eng.store.findEdge(root, a1);
    const e_a1_b1 = eng.store.findEdge(a1, b1);
    const e_root_a2 = eng.store.findEdge(root, a2);
    try testing.expect(e_root_a1 != types.NULL_IDX);
    try testing.expect(e_a1_b1 != types.NULL_IDX);
    try testing.expect(e_root_a2 != types.NULL_IDX);

    // root→a1 and a1→b1 should both have weight = 30 * 0.1 = 3.0.
    try testing.expectApproxEqAbs(@as(f64, 3.0), eng.store.edges[e_root_a1].constraint_weight, 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 3.0), eng.store.edges[e_a1_b1].constraint_weight, 1e-9);
    // root→a2 should have weight = 1 * 0.1 = 0.1.
    try testing.expectApproxEqAbs(@as(f64, 0.1), eng.store.edges[e_root_a2].constraint_weight, 1e-9);

    // High-traffic edges should have far more interactions than rare ones.
    try testing.expect(eng.store.edges[e_root_a1].interaction_count >= 30);
    try testing.expectEqual(@as(u32, 1), eng.store.edges[e_root_a2].interaction_count);
}

test "snapshot/restore round-trips graph state" {
    var cfg = config.DEFAULT;
    cfg.stability_check_every = 0;
    cfg.prune_every = 0;
    const eng = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng);

    const a = try upsert(eng, "A", 0);
    const b = try upsert(eng, "B", 0);
    try eng.interact(a, 0.5, &[_]NodeIdx{b}, 100);

    // Capture state by raw memcpy of the Store struct (mirrors what
    // pask_snapshot_state does in main.zig).
    var snap: Store = undefined;
    @memcpy(std.mem.asBytes(&snap), std.mem.asBytes(&eng.store));

    // Mutate.
    try eng.interact(a, 0.5, &[_]NodeIdx{b}, 200);
    try testing.expect(eng.store.nodes[a].h_state != snap.nodes[a].h_state);

    // Restore and verify.
    @memcpy(std.mem.asBytes(&eng.store), std.mem.asBytes(&snap));
    try testing.expectApproxEqAbs(snap.nodes[a].h_state, eng.store.nodes[a].h_state, 1e-12);
    try testing.expectEqual(snap.node_count, eng.store.node_count);
    try testing.expectEqual(snap.edge_count, eng.store.edge_count);
}

```
