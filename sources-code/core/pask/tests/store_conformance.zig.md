---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/tests/store_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.930300+00:00
---

# core/pask/tests/store_conformance.zig

```zig
// Store conformance — fixed-pool, hash-table, delta ring.
// Mirrors expectations from store.ts: upsert idempotence, NaN-guarded
// state updates, edge keying, windowed avgDelta.

const std = @import("std");
const testing = std.testing;
const config = @import("config");
const types = @import("types");
const store_mod = @import("store");

const Store = store_mod.Store;
const NULL_IDX = types.NULL_IDX;

// Heap-allocate the Store in tests — its size is too large for the
// default 1 MB test stack.
fn allocStore(allocator: std.mem.Allocator, cfg: config.Config) !*Store {
    const s = try allocator.create(Store);
    s.init(cfg);
    return s;
}

test "upsertNode creates then resolves" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    const idx = try s.upsertNode("pos:e4", "chess.move.transition", 1);
    try testing.expectEqual(@as(u32, 0), idx);
    try testing.expectEqual(@as(u32, 1), s.node_count);

    const idx2 = try s.upsertNode("pos:e4", "chess.move.transition", 5);
    try testing.expectEqual(idx, idx2);
    try testing.expectEqual(@as(u32, 1), s.node_count);
    try testing.expectEqual(@as(u64, 5), s.nodes[idx].updated_at);
    try testing.expectEqual(@as(u64, 1), s.nodes[idx].created_at);
}

test "findNode misses on absent cell_id" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    _ = try s.upsertNode("pos:e4", "k", 0);
    try testing.expectEqual(NULL_IDX, s.findNode("pos:d4"));
}

test "upsertNode rejects oversized cell_id" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    var huge: [128]u8 = undefined;
    @memset(huge[0..], 'x');
    try testing.expectError(error.cell_id_too_long, s.upsertNode(huge[0..], "k", 0));
}

test "updateNodeState drops NaN/Inf" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    const idx = try s.upsertNode("a", "k", 0);
    s.updateNodeState(idx, 1.5, 100);
    try testing.expectEqual(@as(f64, 1.5), s.nodes[idx].h_state);

    s.updateNodeState(idx, std.math.nan(f64), 200);
    try testing.expectEqual(@as(f64, 1.5), s.nodes[idx].h_state);

    s.updateNodeState(idx, std.math.inf(f64), 300);
    try testing.expectEqual(@as(f64, 1.5), s.nodes[idx].h_state);
}

test "upsertEdge is idempotent on (from,to)" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    const a = try s.upsertNode("a", "k", 0);
    const b = try s.upsertNode("b", "k", 0);
    const e1 = try s.upsertEdge(a, b, 1);
    const e2 = try s.upsertEdge(a, b, 2);
    try testing.expectEqual(e1, e2);
    try testing.expectEqual(@as(u32, 1), s.edge_count);
}

test "directionality: edge (a,b) and (b,a) are distinct" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    const a = try s.upsertNode("a", "k", 0);
    const b = try s.upsertNode("b", "k", 0);
    const e_ab = try s.upsertEdge(a, b, 0);
    const e_ba = try s.upsertEdge(b, a, 0);
    try testing.expect(e_ab != e_ba);
    try testing.expectEqual(@as(u32, 2), s.edge_count);
}

test "avgDelta returns 0 when no samples in window" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    const a = try s.upsertNode("a", "k", 0);
    const b = try s.upsertNode("b", "k", 0);
    const e = try s.upsertEdge(a, b, 0);
    try testing.expectEqual(@as(f64, 0), s.avgDelta(e, 1000, 5000));
}

test "avgDelta averages |delta| across samples within window" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    const a = try s.upsertNode("a", "k", 0);
    const b = try s.upsertNode("b", "k", 0);
    const e = try s.upsertEdge(a, b, 0);

    s.recordDelta(e, 0.4, 100);
    s.recordDelta(e, -0.2, 200);
    s.recordDelta(e, 0.6, 300);

    // Window includes all three: avg(|0.4|, |-0.2|, |0.6|) = 0.4
    const avg = s.avgDelta(e, 1000, 1000);
    try testing.expectApproxEqAbs(@as(f64, 0.4), avg, 1e-12);
}

test "avgDelta excludes samples older than window" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    const a = try s.upsertNode("a", "k", 0);
    const b = try s.upsertNode("b", "k", 0);
    const e = try s.upsertEdge(a, b, 0);

    s.recordDelta(e, 1.0, 100);   // out of window
    s.recordDelta(e, 0.2, 9000);  // in window
    s.recordDelta(e, 0.4, 9500);  // in window

    // Window 1000 ms ending at 10_000 → since=9000 → samples 0.2 and 0.4.
    const avg = s.avgDelta(e, 1000, 10_000);
    try testing.expectApproxEqAbs(@as(f64, 0.3), avg, 1e-12);
}

test "inboundTrend averages delta_trend across inbound edges" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    const target = try s.upsertNode("target", "k", 0);
    const src1 = try s.upsertNode("s1", "k", 0);
    const src2 = try s.upsertNode("s2", "k", 0);
    const src3 = try s.upsertNode("s3", "k", 0);

    const e1 = try s.upsertEdge(src1, target, 0);
    const e2 = try s.upsertEdge(src2, target, 0);
    const e3 = try s.upsertEdge(src3, target, 0);

    s.updateEdgeTrend(e1, 0.3);
    s.updateEdgeTrend(e2, -0.1);
    s.updateEdgeTrend(e3, 0.4);
    // Outbound edge (target → src1) — must NOT contribute.
    const outbound = try s.upsertEdge(target, src1, 0);
    s.updateEdgeTrend(outbound, 99.0);

    const avg = s.inboundTrend(target);
    try testing.expectApproxEqAbs(@as(f64, 0.2), avg, 1e-12);
}

test "totalInboundWeight sums constraint_weight on inbound edges" {
    const s = try allocStore(testing.allocator, config.DEFAULT);
    defer testing.allocator.destroy(s);

    const target = try s.upsertNode("target", "k", 0);
    const src1 = try s.upsertNode("s1", "k", 0);
    const src2 = try s.upsertNode("s2", "k", 0);

    const e1 = try s.upsertEdge(src1, target, 0);
    const e2 = try s.upsertEdge(src2, target, 0);
    s.updateEdgeWeight(e1, 0.5, 1);
    s.updateEdgeWeight(e2, 0.7, 1);
    // Outbound from target — should not contribute.
    const e3 = try s.upsertEdge(target, src1, 0);
    s.updateEdgeWeight(e3, 99.0, 1);

    try testing.expectApproxEqAbs(@as(f64, 1.2), s.totalInboundWeight(target), 1e-12);
}

```
