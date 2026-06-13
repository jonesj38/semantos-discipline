---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/tests/determinism_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.930574+00:00
---

# core/pask/tests/determinism_conformance.zig

```zig
// Determinism conformance — proves the kernel is fully deterministic
// when the caller supplies its clock. Two independent runs over the
// same inputs must produce byte-identical snapshot blobs.
//
// This is the load-bearing claim for offchain use: replays from the
// same input stream are bit-identical, no host clock or entropy
// sneaking in. If this test ever fails, the kernel has acquired
// undeclared non-determinism — something to find and remove, not
// to compensate for.

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
        primary: NodeIdx,
        related: []const NodeIdx,
        strength: f64,
        now_ms: u64,
    ) !void {
        self.affected.init();
        _ = try self.affected.add(primary);
        for (related) |r| {
            const e = try self.store.upsertEdge(primary, r, now_ms);
            const w = strength * self.store.cfg.learning_rate;
            self.store.updateEdgeWeight(e, w, now_ms);
            self.store.recordDelta(e, w, now_ms);
            _ = try self.affected.add(r);
        }
        self.store.updateNodeState(primary, strength, now_ms);
        try propagation.propagate(&self.store, &self.affected, now_ms);
        self.tick += 1;
        if (self.store.cfg.stability_check_every > 0 and
            self.tick % self.store.cfg.stability_check_every == 0)
        {
            var i: u32 = 0;
            while (i < self.affected.count) : (i += 1) {
                _ = stability_mod.checkNode(
                    &self.store,
                    self.affected.members[i],
                    now_ms,
                );
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

fn driveSyntheticGraph(eng: *Engine) !void {
    const root = try eng.store.upsertNode("root", "k", 0);
    const a = try eng.store.upsertNode("a", "k", 0);
    const b = try eng.store.upsertNode("b", "k", 0);
    const c = try eng.store.upsertNode("c", "k", 0);
    const d = try eng.store.upsertNode("d", "k", 0);

    var clock: u64 = 0;
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        clock += 1;
        try eng.interact(root, &[_]NodeIdx{ a, b }, 1.0, clock);
        clock += 1;
        try eng.interact(a, &[_]NodeIdx{ b, c }, 0.7, clock);
        clock += 1;
        try eng.interact(b, &[_]NodeIdx{c}, 0.4, clock);
        clock += 1;
        try eng.interact(c, &[_]NodeIdx{ d, a }, -0.3, clock);
    }
}

test "two independent runs over the same input produce byte-identical state" {
    var cfg = config.DEFAULT;
    cfg.stability_check_every = 1;
    cfg.prune_every = 7;
    cfg.min_interactions = 3;

    const e1 = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(e1);
    const e2 = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(e2);

    try driveSyntheticGraph(e1);
    try driveSyntheticGraph(e2);

    // Hash and compare the entire Store struct. Padding bytes are zeroed
    // by initInPlace + extern struct rules so this is exact.
    const e1_bytes = std.mem.asBytes(&e1.store);
    const e2_bytes = std.mem.asBytes(&e2.store);
    try testing.expect(std.mem.eql(u8, e1_bytes, e2_bytes));
}

test "snapshot of run-1 restored into engine 2 byte-matches a fresh run-2" {
    // The snapshot ABI also has to be deterministic — the byte layout
    // must not depend on allocation order or padding leakage.
    var cfg = config.DEFAULT;
    cfg.stability_check_every = 1;
    cfg.prune_every = 0;
    cfg.min_interactions = 3;

    const e1 = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(e1);
    const e2 = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(e2);

    try driveSyntheticGraph(e1);
    try driveSyntheticGraph(e2);

    // Take the run-2 store image and overwrite e1's store with it.
    @memcpy(std.mem.asBytes(&e1.store), std.mem.asBytes(&e2.store));

    // Compare every field of every node.
    try testing.expectEqual(e1.store.node_count, e2.store.node_count);
    try testing.expectEqual(e1.store.edge_count, e2.store.edge_count);
    var i: u32 = 0;
    while (i < e1.store.node_count) : (i += 1) {
        try testing.expectEqual(e1.store.nodes[i].h_state, e2.store.nodes[i].h_state);
        try testing.expectEqual(e1.store.nodes[i].interaction_count, e2.store.nodes[i].interaction_count);
        try testing.expectEqual(e1.store.nodes[i].is_stable, e2.store.nodes[i].is_stable);
    }
}

```
