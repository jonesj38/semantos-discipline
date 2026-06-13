---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/tests/propagation_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.929757+00:00
---

# core/pask/tests/propagation_conformance.zig

```zig
// Propagation conformance — locks the constraint-effect math against
// hand-computed expected values, plus the EMA trend update.

const std = @import("std");
const testing = std.testing;
const config = @import("config");
const types = @import("types");
const store_mod = @import("store");
const propagation = @import("propagation");

const Store = store_mod.Store;
const Affected = propagation.Affected;

fn allocStore(allocator: std.mem.Allocator, cfg: config.Config) !*Store {
    const s = try allocator.create(Store);
    s.init(cfg);
    return s;
}

test "Affected: add returns true for new, false for existing" {
    var a: Affected = undefined;
    a.init();
    try testing.expectEqual(true, try a.add(0));
    try testing.expectEqual(false, try a.add(0));
    try testing.expectEqual(@as(u32, 1), a.count);
    try testing.expectEqual(true, try a.add(7));
    try testing.expectEqual(@as(u32, 2), a.count);
}

test "Affected: bitset survives sparse indices" {
    var a: Affected = undefined;
    a.init();
    _ = try a.add(0);
    _ = try a.add(1000);
    _ = try a.add(5000);
    try testing.expect(a.contains(0));
    try testing.expect(a.contains(1000));
    try testing.expect(a.contains(5000));
    try testing.expect(!a.contains(1));
    try testing.expect(!a.contains(999));
}

test "localUpdate: applies sum of constraint effects to source" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    // Setup: A → B, A → C.  hA = 0, hB = 1.0, hC = 0.5.
    // edge weights: A→B = 0.5, A→C = 0.2.
    // lr = 0.1 (default).
    // effect(A→B) = (1.0 - 0.0) * 0.5 * 0.1 = 0.05
    // effect(A→C) = (0.5 - 0.0) * 0.2 * 0.1 = 0.01
    // total = 0.06. Apply once to A → A.h becomes 0.06.
    const a = try s.upsertNode("A", "k", 0);
    const b = try s.upsertNode("B", "k", 0);
    const c = try s.upsertNode("C", "k", 0);
    const e_ab = try s.upsertEdge(a, b, 0);
    const e_ac = try s.upsertEdge(a, c, 0);

    s.updateNodeState(b, 1.0, 0);
    s.updateNodeState(c, 0.5, 0);
    s.updateEdgeWeight(e_ab, 0.5, 0);
    s.updateEdgeWeight(e_ac, 0.2, 0);

    propagation.localUpdate(s, a, 1000);

    try testing.expectApproxEqAbs(@as(f64, 0.06), s.nodes[a].h_state, 1e-12);

    // Edge trend EMA: trend = 0.9 * 0 + 0.1 * effect.
    try testing.expectApproxEqAbs(@as(f64, 0.005), s.edges[e_ab].delta_trend, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 0.001), s.edges[e_ac].delta_trend, 1e-12);
}

test "localUpdate: no outgoing edges → no-op" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    const a = try s.upsertNode("A", "k", 0);
    s.updateNodeState(a, 0.5, 0);
    propagation.localUpdate(s, a, 100);
    try testing.expectApproxEqAbs(@as(f64, 0.5), s.nodes[a].h_state, 1e-12);
}

test "expandRegion: adds both endpoints of touching edges" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    // Graph: A → B → C, plus D → B (D inbound to B).
    // After expandRegion starting from {A}: should hit A, B (via A→B),
    // and after second pass, D (via D→B inbound).
    const a = try s.upsertNode("A", "k", 0);
    const b = try s.upsertNode("B", "k", 0);
    const c = try s.upsertNode("C", "k", 0);
    const d = try s.upsertNode("D", "k", 0);
    _ = try s.upsertEdge(a, b, 0);
    _ = try s.upsertEdge(b, c, 0);
    _ = try s.upsertEdge(d, b, 0);

    var region: Affected = undefined;
    region.init();
    _ = try region.add(a);

    // 1 hop: A's edges are (A→B). Adds A and B.
    try propagation.expandRegion(s, &region);
    try testing.expect(region.contains(a));
    try testing.expect(region.contains(b));
    try testing.expect(!region.contains(c));
    try testing.expect(!region.contains(d));

    // 2 hops: B's edges are (A→B, B→C, D→B). Adds A, B, C, D.
    try propagation.expandRegion(s, &region);
    try testing.expect(region.contains(c));
    try testing.expect(region.contains(d));
}

test "propagate: 3 hops over a chain reaches all nodes" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    // Linear chain A → B → C → D. Starting from {A} with depth=3.
    const a = try s.upsertNode("A", "k", 0);
    const b = try s.upsertNode("B", "k", 0);
    const c = try s.upsertNode("C", "k", 0);
    const d = try s.upsertNode("D", "k", 0);
    _ = try s.upsertEdge(a, b, 0);
    _ = try s.upsertEdge(b, c, 0);
    _ = try s.upsertEdge(c, d, 0);

    var region: Affected = undefined;
    region.init();
    _ = try region.add(a);

    try propagation.propagate(s, &region, 0);

    try testing.expect(region.contains(a));
    try testing.expect(region.contains(b));
    try testing.expect(region.contains(c));
    try testing.expect(region.contains(d));
}

```
