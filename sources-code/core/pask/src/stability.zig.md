---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/src/stability.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.931736+00:00
---

# core/pask/src/stability.zig

```zig
// Stability detector — Zig port of adapter.ts:checkStability (lines 256-292).
//
// Logic:
//   - skip if interaction_count < min_interactions
//   - sum avgDelta(edge, window) for every edge touching the node
//   - divide by edge count → avg_delta_h
//   - is_stable iff avg_delta_h < stability_epsilon
//   - on transition false → true, fire stable-event (caller-side)

const std = @import("std");
const config = @import("config");
const types = @import("types");
const store_mod = @import("store");

const Store = store_mod.Store;
const NodeIdx = types.NodeIdx;
const Edge = types.Edge;

pub const StabilityResult = struct {
    /// True if the node is currently considered stable.
    is_stable: bool,
    /// True if this call flipped the node from non-stable to stable.
    transitioned_to_stable: bool,
    /// Computed average |ΔH|.
    avg_delta_h: f64,
    /// True if no decision could be made (skipped: pruned / not enough
    /// interactions / no edges).
    skipped: bool,
};

pub fn checkNode(
    store: *Store,
    node_idx: NodeIdx,
    now_ms: u64,
) StabilityResult {
    const node = store.getNode(node_idx) orelse return .{
        .is_stable = false,
        .transitioned_to_stable = false,
        .avg_delta_h = 0,
        .skipped = true,
    };
    if (node.is_pruned == 1) return .{
        .is_stable = node.is_stable == 1,
        .transitioned_to_stable = false,
        .avg_delta_h = 0,
        .skipped = true,
    };
    if (node.interaction_count < store.cfg.min_interactions) return .{
        .is_stable = node.is_stable == 1,
        .transitioned_to_stable = false,
        .avg_delta_h = 0,
        .skipped = true,
    };

    // Walk every edge touching this node, sum avgDelta over the window.
    var total: f64 = 0;
    var edge_count: u32 = 0;
    var i: u32 = 0;
    while (i < store.edge_count) : (i += 1) {
        const e = store.getEdge(i).?;
        if (e.from_idx == node_idx or e.to_idx == node_idx) {
            total += store.avgDelta(i, store.cfg.stability_window_ms, now_ms);
            edge_count += 1;
        }
    }
    if (edge_count == 0) return .{
        .is_stable = node.is_stable == 1,
        .transitioned_to_stable = false,
        .avg_delta_h = 0,
        .skipped = true,
    };

    const avg = total / @as(f64, @floatFromInt(edge_count));
    const is_stable = avg < store.cfg.stability_epsilon;
    const was_stable = node.is_stable == 1;

    store.markStable(node_idx, is_stable);
    // Mirrors store.ts:stability column update on the node row.
    store.getNodeMut(node_idx).?.stability = avg;

    return .{
        .is_stable = is_stable,
        .transitioned_to_stable = is_stable and !was_stable,
        .avg_delta_h = avg,
        .skipped = false,
    };
}

```
