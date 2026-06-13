---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/tests/stability_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.930024+00:00
---

# core/pask/tests/stability_conformance.zig

```zig
// Stability conformance — verifies the avg-|ΔH| < ε rule and the
// transition event semantics from adapter.ts:checkStability.

const std = @import("std");
const testing = std.testing;
const config = @import("config");
const types = @import("types");
const store_mod = @import("store");
const stability = @import("stability");

const Store = store_mod.Store;

fn allocStore(allocator: std.mem.Allocator, cfg: config.Config) !*Store {
    const s = try allocator.create(Store);
    s.init(cfg);
    return s;
}

test "skip when interaction_count below min_interactions" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    const a = try s.upsertNode("A", "k", 0);
    const b = try s.upsertNode("B", "k", 0);
    const e = try s.upsertEdge(a, b, 0);
    s.updateNodeState(a, 0.1, 0);
    s.updateNodeState(a, 0.1, 0); // 2 interactions, default min=5
    s.recordDelta(e, 0.001, 100);

    const r = stability.checkNode(s, a, 200);
    try testing.expect(r.skipped);
    try testing.expect(!r.transitioned_to_stable);
}

test "skip when no edges touch the node" {
    var cfg = config.DEFAULT;
    cfg.min_interactions = 1;
    const s = try allocStore(testing.allocator, cfg);
    defer testing.allocator.destroy(s);

    const a = try s.upsertNode("A", "k", 0);
    s.updateNodeState(a, 0.1, 0);

    const r = stability.checkNode(s, a, 100);
    try testing.expect(r.skipped);
}

test "marks stable when avg|ΔH| < epsilon" {
    var cfg = config.DEFAULT;
    cfg.min_interactions = 1;
    cfg.stability_epsilon = 0.01;
    cfg.stability_window_ms = 10_000;
    const s = try allocStore(testing.allocator, cfg);
    defer testing.allocator.destroy(s);

    const a = try s.upsertNode("A", "k", 0);
    const b = try s.upsertNode("B", "k", 0);
    const e = try s.upsertEdge(a, b, 0);
    s.updateNodeState(a, 0.1, 0);
    // Three small deltas — avg |delta| = 0.005 < 0.01 → stable.
    s.recordDelta(e, 0.001, 100);
    s.recordDelta(e, -0.005, 200);
    s.recordDelta(e, 0.009, 300);

    const r = stability.checkNode(s, a, 1000);
    try testing.expect(!r.skipped);
    try testing.expect(r.is_stable);
    try testing.expect(r.transitioned_to_stable);
    try testing.expectEqual(@as(u8, 1), s.nodes[a].is_stable);
}

test "no transition flag on second consecutive stable check" {
    var cfg = config.DEFAULT;
    cfg.min_interactions = 1;
    const s = try allocStore(testing.allocator, cfg);
    defer testing.allocator.destroy(s);

    const a = try s.upsertNode("A", "k", 0);
    const b = try s.upsertNode("B", "k", 0);
    const e = try s.upsertEdge(a, b, 0);
    s.updateNodeState(a, 0.1, 0);
    s.recordDelta(e, 0.001, 100);

    const r1 = stability.checkNode(s, a, 1000);
    try testing.expect(r1.transitioned_to_stable);
    const r2 = stability.checkNode(s, a, 2000);
    try testing.expect(r2.is_stable);
    try testing.expect(!r2.transitioned_to_stable);
}

test "high-volatility node stays unstable" {
    var cfg = config.DEFAULT;
    cfg.min_interactions = 1;
    cfg.stability_epsilon = 0.01;
    const s = try allocStore(testing.allocator, cfg);
    defer testing.allocator.destroy(s);

    const a = try s.upsertNode("A", "k", 0);
    const b = try s.upsertNode("B", "k", 0);
    const e = try s.upsertEdge(a, b, 0);
    s.updateNodeState(a, 0.1, 0);
    // Big swings → avg|delta| well above ε.
    s.recordDelta(e, 0.5, 100);
    s.recordDelta(e, -0.4, 200);
    s.recordDelta(e, 0.6, 300);

    const r = stability.checkNode(s, a, 1000);
    try testing.expect(!r.is_stable);
    try testing.expect(!r.transitioned_to_stable);
}

```
