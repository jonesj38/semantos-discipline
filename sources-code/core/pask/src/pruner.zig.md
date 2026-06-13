---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/src/pruner.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.932531+00:00
---

# core/pask/src/pruner.zig

```zig
// Pruner — Zig port of adapter.ts:prune (lines 302-334) and the
// pruningCandidates SQL query in store.ts:386-396.
//
// TS query:
//   SELECT n.* FROM paskian_nodes n
//   JOIN paskian_edges e ON e.to_cell = n.cell_id
//   WHERE n.is_pruned = 0
//   GROUP BY n.cell_id
//   HAVING AVG(e.delta_trend) < threshold
//
// We replicate by sweeping the node array and computing inboundTrend
// per node. Nodes with NO inbound edges are NOT candidates (the JOIN
// drops them in TS too).

const std = @import("std");
const config = @import("config");
const types = @import("types");
const store_mod = @import("store");

const Store = store_mod.Store;
const NodeIdx = types.NodeIdx;

pub const PruneResult = struct {
    pruned_count: u32,
};

/// Single prune pass. Mutates the store: marks any node whose inbound
/// trend is below the configured threshold as is_pruned=1.
///
/// Returns the count of nodes pruned this pass.
pub fn pruneOnce(store: *Store, _: u64) PruneResult {
    var pruned: u32 = 0;
    var node_idx: NodeIdx = 0;
    while (node_idx < store.node_count) : (node_idx += 1) {
        const n = store.getNode(node_idx).?;
        if (n.is_pruned == 1) continue;

        // Mirror the TS JOIN: only nodes with at least one inbound edge
        // are pruning-eligible.
        var has_inbound: bool = false;
        var sum: f64 = 0;
        var count: u32 = 0;
        var i: u32 = 0;
        while (i < store.edge_count) : (i += 1) {
            const e = store.getEdge(i).?;
            if (e.to_idx == node_idx) {
                has_inbound = true;
                sum += e.delta_trend;
                count += 1;
            }
        }
        if (!has_inbound) continue;
        const avg_trend = sum / @as(f64, @floatFromInt(count));

        if (avg_trend < store.cfg.prune_threshold) {
            store.markPruned(node_idx);
            pruned += 1;
        }
    }
    return .{ .pruned_count = pruned };
}

```
