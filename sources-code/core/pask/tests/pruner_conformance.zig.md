---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/tests/pruner_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.928930+00:00
---

# core/pask/tests/pruner_conformance.zig

```zig
// Pruner conformance — verifies that nodes whose inbound edge trend
// has dropped below threshold get marked is_pruned, and that nodes
// without inbound edges are exempt (mirrors the SQL JOIN).

const std = @import("std");
const testing = std.testing;
const config = @import("config");
const types = @import("types");
const store_mod = @import("store");
const pruner = @import("pruner");

const Store = store_mod.Store;

fn allocStore(allocator: std.mem.Allocator, cfg: config.Config) !*Store {
    const s = try allocator.create(Store);
    s.init(cfg);
    return s;
}

test "prunes node with avg inbound trend below threshold" {
    var cfg = config.DEFAULT;
    cfg.prune_threshold = -0.3;
    const s = try allocStore(testing.allocator, cfg);
    defer testing.allocator.destroy(s);

    const target = try s.upsertNode("target", "k", 0);
    const src1 = try s.upsertNode("s1", "k", 0);
    const src2 = try s.upsertNode("s2", "k", 0);

    const e1 = try s.upsertEdge(src1, target, 0);
    const e2 = try s.upsertEdge(src2, target, 0);
    s.updateEdgeTrend(e1, -0.4);
    s.updateEdgeTrend(e2, -0.5);
    // avg = -0.45 < -0.3 → prune.

    const r = pruner.pruneOnce(s, 0);
    try testing.expectEqual(@as(u32, 1), r.pruned_count);
    try testing.expectEqual(@as(u8, 1), s.nodes[target].is_pruned);
}

test "spares node with avg inbound trend above threshold" {
    var cfg = config.DEFAULT;
    cfg.prune_threshold = -0.3;
    const s = try allocStore(testing.allocator, cfg);
    defer testing.allocator.destroy(s);

    const target = try s.upsertNode("target", "k", 0);
    const src = try s.upsertNode("s", "k", 0);
    const e = try s.upsertEdge(src, target, 0);
    s.updateEdgeTrend(e, -0.2);

    const r = pruner.pruneOnce(s, 0);
    try testing.expectEqual(@as(u32, 0), r.pruned_count);
    try testing.expectEqual(@as(u8, 0), s.nodes[target].is_pruned);
}

test "spares orphan node with no inbound edges (mirrors SQL JOIN)" {
    var cfg = config.DEFAULT;
    cfg.prune_threshold = 999.0; // would prune anything visible to the join
    const s = try allocStore(testing.allocator, cfg);
    defer testing.allocator.destroy(s);

    // Solo orphan: no edges anywhere. JOIN drops it; stays untouched.
    const orphan = try s.upsertNode("orphan", "k", 0);
    const r = pruner.pruneOnce(s, 0);
    try testing.expectEqual(@as(u32, 0), r.pruned_count);
    try testing.expectEqual(@as(u8, 0), s.nodes[orphan].is_pruned);
}

test "node with only outbound edges is not pruned (JOIN on inbound only)" {
    var cfg = config.DEFAULT;
    cfg.prune_threshold = 999.0;
    const s = try allocStore(testing.allocator, cfg);
    defer testing.allocator.destroy(s);

    const a = try s.upsertNode("A", "k", 0);
    const b = try s.upsertNode("B", "k", 0);
    const e = try s.upsertEdge(a, b, 0); // outbound from A, inbound to B
    s.updateEdgeTrend(e, -10.0);

    _ = pruner.pruneOnce(s, 0);
    // A has only outbound edges → JOIN excludes → not pruned.
    try testing.expectEqual(@as(u8, 0), s.nodes[a].is_pruned);
    // B has the inbound edge with bad trend → IS pruned.
    try testing.expectEqual(@as(u8, 1), s.nodes[b].is_pruned);
}

test "already-pruned nodes are not re-pruned" {
    var cfg = config.DEFAULT;
    cfg.prune_threshold = -0.3;
    const s = try allocStore(testing.allocator, cfg);
    defer testing.allocator.destroy(s);

    const target = try s.upsertNode("target", "k", 0);
    const src = try s.upsertNode("s", "k", 0);
    const e = try s.upsertEdge(src, target, 0);
    s.updateEdgeTrend(e, -0.5);

    _ = pruner.pruneOnce(s, 0); // first sweep prunes
    const r2 = pruner.pruneOnce(s, 0); // second sweep should be a no-op
    try testing.expectEqual(@as(u32, 0), r2.pruned_count);
}

```
