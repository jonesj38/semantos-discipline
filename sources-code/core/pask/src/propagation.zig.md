---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/src/propagation.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.932267+00:00
---

# core/pask/src/propagation.zig

```zig
// Propagation — Zig port of the paper's main loop (adapter.ts:82-161).
//
// The TS impl uses a Set<string> for the affected region and grows it
// by traversing edges out of every member. We use a fixed-capacity
// affected-set with a small bitset for membership checking.
//
// Critical fidelity points (must match TS bit-for-bit):
//   1. constraintEffect = (target.h - source.h) * edge.constraintWeight * lr
//   2. Edge trend update: trend = trend*0.9 + effect*0.1
//   3. Total effect accumulates ALL outgoing edges then applies once to source.
//   4. expandRegion adds BOTH from_idx and to_idx of every touching edge
//      (not just outgoing). This is what gives 3-hop propagation actual reach.

const std = @import("std");
const config = @import("config");
const types = @import("types");
const store_mod = @import("store");

const Store = store_mod.Store;
const Edge = types.Edge;
const NodeIdx = types.NodeIdx;
const EdgeIdx = types.EdgeIdx;
const NULL_IDX = types.NULL_IDX;

const TREND_OLD_WEIGHT: f64 = 0.9;
const TREND_NEW_WEIGHT: f64 = 0.1;

/// Bitset-backed affected-set. Membership in O(1), iteration via the
/// `members` array. Capped at config.MAX_AFFECTED.
pub const Affected = struct {
    /// bitset[node_idx >> 6] has bit (node_idx & 63) set iff present.
    /// Sized to cover all possible node indices.
    bitset: [(config.MAX_NODES + 63) / 64]u64,
    members: [config.MAX_AFFECTED]NodeIdx,
    count: u32,

    pub fn init(self: *Affected) void {
        @memset(self.bitset[0..self.bitset.len], 0);
        self.count = 0;
    }

    pub fn contains(self: *const Affected, idx: NodeIdx) bool {
        if (idx >= config.MAX_NODES) return false;
        const word = idx >> 6;
        const bit = @as(u6, @intCast(idx & 63));
        return (self.bitset[word] & (@as(u64, 1) << bit)) != 0;
    }

    /// Add idx; returns true if it was newly inserted.
    pub fn add(self: *Affected, idx: NodeIdx) types.PaskError!bool {
        if (idx >= config.MAX_NODES) return error.invalid_index;
        const word = idx >> 6;
        const bit = @as(u6, @intCast(idx & 63));
        const mask = @as(u64, 1) << bit;
        if ((self.bitset[word] & mask) != 0) return false;
        if (self.count >= config.MAX_AFFECTED) return error.affected_overflow;
        self.bitset[word] |= mask;
        self.members[self.count] = idx;
        self.count += 1;
        return true;
    }
};

/// Apply one edge's constraint pull to the source node.
/// Mirrors adapter.ts:215-224 constraintEffect().
fn constraintEffect(
    store: *const Store,
    source_idx: NodeIdx,
    edge: *const Edge,
    learning_rate: f64,
) f64 {
    const source = store.getNode(source_idx) orelse return 0;
    const target = store.getNode(edge.to_idx) orelse return 0;
    const state_diff = target.h_state - source.h_state;
    return state_diff * edge.constraint_weight * learning_rate;
}

/// localUpdate: walk outgoing edges, sum constraint effects, apply once.
/// Mirrors adapter.ts:182-204.
pub fn localUpdate(
    store: *Store,
    cell_idx: NodeIdx,
    now_ms: u64,
) void {
    // Pass 1: collect edge indices for this node — we can't mutate the
    // store while iterating its arrays via the forEachOutgoing closure
    // pattern (Zig doesn't have closures). Inline-loop instead.
    var total_effect: f64 = 0;
    var i: u32 = 0;
    var any: bool = false;
    while (i < store.edge_count) : (i += 1) {
        const e_const = store.getEdge(i).?;
        if (e_const.from_idx != cell_idx) continue;
        any = true;

        const effect = constraintEffect(store, cell_idx, e_const, store.cfg.learning_rate);
        total_effect += effect;

        store.recordDelta(i, effect, now_ms);

        // Edge trend EMA: 0.9 * old + 0.1 * effect.
        const new_trend = e_const.delta_trend * TREND_OLD_WEIGHT +
            effect * TREND_NEW_WEIGHT;
        store.updateEdgeTrend(i, new_trend);
    }

    if (!any) return;
    if (total_effect != 0) {
        store.updateNodeState(cell_idx, total_effect, now_ms);
    }
}

/// expandRegion: grow the affected set by one hop.
/// Mirrors adapter.ts:232-247 — adds BOTH endpoints of every touching edge.
///
/// Iterating `current` while we mutate `current` would skew the snapshot
/// the TS Set iterator gives. We snapshot the prior count and only walk
/// up to that boundary, exactly matching the TS `for (const cellId of current)`.
pub fn expandRegion(store: *const Store, region: *Affected) types.PaskError!void {
    const snapshot_count = region.count;
    var m: u32 = 0;
    while (m < snapshot_count) : (m += 1) {
        const node = region.members[m];
        var i: u32 = 0;
        while (i < store.edge_count) : (i += 1) {
            const e = store.getEdge(i).?;
            if (e.from_idx == node or e.to_idx == node) {
                _ = try region.add(e.from_idx);
                _ = try region.add(e.to_idx);
            }
        }
    }
}

/// Run propagation_depth iterations of (foreach localUpdate, expand).
/// Mirrors adapter.ts:124-134.
pub fn propagate(
    store: *Store,
    region: *Affected,
    now_ms: u64,
) types.PaskError!void {
    const depth = store.cfg.propagation_depth;
    var k: u32 = 0;
    while (k < depth) : (k += 1) {
        // Walk all current members of the region — but only the snapshot
        // at the start of this iteration. Newly added members from
        // expansion are processed in the NEXT k.
        const snapshot_count = region.count;
        var m: u32 = 0;
        while (m < snapshot_count) : (m += 1) {
            localUpdate(store, region.members[m], now_ms);
        }
        try expandRegion(store, region);
    }
}

```
