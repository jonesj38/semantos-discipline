---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/pask_stable_observer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.261484+00:00
---

# runtime/semantos-brain/src/pask_stable_observer.zig

```zig
// WI-A3 — PaskStableObserver: host-side detection of false→true stability flips.
//
// Wraps the Pask Store interaction loop to observe which nodes transition
// from unstable → stable after each interact call. The observer is a pure
// data-transformation module: it records the pre-interact stability snapshot,
// then computes a list of `StableFlip` records after the interact. The caller
// is responsible for emitting the flip records to NATS via
// `NatsEventProducer.emitStableTransition`.
//
// This split (observe vs. emit) means the observer is testable without a live
// NATS server or a real NatsClient. The integration of observe + emit lives
// in the host's pask_interact_run call site (not in this module).
//
// Usage:
//   var observer = PaskStableObserver.init(&store);
//   observer.snapshotPre();          // capture before interact
//   _ = pask_interact_run(...);      // run the kernel step
//   var flips_buf: [MAX_FLIPS]StableFlip = undefined;
//   const n = observer.collectFlips(&flips_buf);
//   for (flips_buf[0..n]) |flip| {
//       try producer.emitStableTransition(
//           flip.node_idx, flip.cellId(), flip.h_state,
//           flip.total_constraint_strength, flip.interaction_count, ts_ms,
//       );
//   }
//
// See research/cognition-implementation-plan.md §WI-A3.

const std = @import("std");
const pask_config = @import("pask_config");
const pask_store_mod = @import("pask_store");

const Store = pask_store_mod.Store;

// ── Public types ───────────────────────────────────────────────────────────

/// A node that flipped from unstable → stable in the most recent interact.
pub const StableFlip = struct {
    node_idx: u32,
    h_state: f64,
    total_constraint_strength: f64,
    interaction_count: u32,
    /// Raw cell_id bytes (same encoding as stored in the Node).
    cell_id_buf: [pask_config.MAX_CELL_ID_LEN]u8,
    cell_id_len: u32,

    /// Slice view of the cell_id bytes for passing to emitStableTransition.
    pub fn cellId(self: *const StableFlip) []const u8 {
        return self.cell_id_buf[0..self.cell_id_len];
    }
};

/// Maximum flips that can be collected in a single `collectFlips` call.
/// Bounded by MAX_NODES; in practice far fewer nodes flip per tick.
pub const MAX_FLIPS: u32 = pask_config.MAX_NODES;

// ── Observer ───────────────────────────────────────────────────────────────

pub const PaskStableObserver = struct {
    store: *const Store,
    /// is_stable snapshot taken by snapshotPre(). Index = node_idx.
    pre_stable: [pask_config.MAX_NODES]u8,
    /// store.node_count at the time of snapshotPre().
    pre_node_count: u32,

    pub fn init(store: *const Store) PaskStableObserver {
        return .{
            .store = store,
            .pre_stable = [_]u8{0} ** pask_config.MAX_NODES,
            .pre_node_count = 0,
        };
    }

    /// Snapshot the stability state of all current nodes.
    /// Call immediately BEFORE pask_interact_run (or equivalent).
    pub fn snapshotPre(self: *PaskStableObserver) void {
        self.pre_node_count = self.store.node_count;
        var i: u32 = 0;
        while (i < self.pre_node_count) : (i += 1) {
            const node = self.store.getNode(i) orelse {
                self.pre_stable[i] = 0;
                continue;
            };
            self.pre_stable[i] = node.is_stable;
        }
    }

    /// Collect all nodes that flipped from unstable → stable since the last
    /// snapshotPre() call. Writes into `out[0..n]` and returns n.
    ///
    /// Nodes that were already stable before snapshotPre() are excluded.
    /// Caller must pre-allocate at least `out.len` entries; in practice
    /// `var buf: [MAX_FLIPS]StableFlip = undefined` is always safe.
    pub fn collectFlips(
        self: *const PaskStableObserver,
        out: []StableFlip,
    ) u32 {
        var n: u32 = 0;
        const now_count = self.store.node_count;
        var i: u32 = 0;
        while (i < now_count and n < out.len) : (i += 1) {
            const node = self.store.getNode(i) orelse continue;
            if (node.is_stable != 1) continue; // not stable now
            const was_stable: u8 = if (i < self.pre_node_count) self.pre_stable[i] else 0;
            if (was_stable == 1) continue; // was already stable — not a flip

            // Record the flip.
            out[n] = .{
                .node_idx = i,
                .h_state = node.h_state,
                .total_constraint_strength = self.store.totalInboundWeight(i),
                .interaction_count = node.interaction_count,
                .cell_id_buf = node.cell_id,
                .cell_id_len = node.cell_id_len,
            };
            n += 1;
        }
        return n;
    }
};

// ── Inline tests ───────────────────────────────────────────────────────────

test "WI-A3-T-no-emit-on-skip: no flips when all nodes already stable" {
    var store: Store = undefined;
    store.init(pask_config.DEFAULT);

    // Upsert a node and mark it stable manually.
    _ = try store.upsertNode("cell-a", "", 1000);
    store.nodes[0].is_stable = 1;

    var observer = PaskStableObserver.init(&store);
    observer.snapshotPre(); // snapshot: node 0 already stable

    // No new stability flip — node was already stable before snapshot.
    var flips: [MAX_FLIPS]StableFlip = undefined;
    const n = observer.collectFlips(&flips);
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "WI-A3-T-no-emit-on-skip: no flips when transitioned_to_stable is false" {
    var store: Store = undefined;
    store.init(pask_config.DEFAULT);

    _ = try store.upsertNode("cell-b", "", 1000);
    // Node stays unstable — no flip should be reported.

    var observer = PaskStableObserver.init(&store);
    observer.snapshotPre();

    // Node is still unstable post-interact (is_stable = 0).
    var flips: [MAX_FLIPS]StableFlip = undefined;
    const n = observer.collectFlips(&flips);
    try std.testing.expectEqual(@as(u32, 0), n);
}

test "WI-A3-T-no-emit-on-skip: exactly one flip when one node newly stable" {
    var store: Store = undefined;
    store.init(pask_config.DEFAULT);

    _ = try store.upsertNode("cell-c", "", 1000);
    store.nodes[0].is_stable = 0;
    store.nodes[0].h_state = 0.85;
    store.nodes[0].interaction_count = 10;

    var observer = PaskStableObserver.init(&store);
    observer.snapshotPre(); // snapshot: node 0 unstable

    // Simulate stability flip (would happen after pask_interact_run in prod).
    store.nodes[0].is_stable = 1;

    var flips: [MAX_FLIPS]StableFlip = undefined;
    const n = observer.collectFlips(&flips);
    try std.testing.expectEqual(@as(u32, 1), n);
    try std.testing.expectEqual(@as(u32, 0), flips[0].node_idx);
    try std.testing.expectApproxEqAbs(@as(f64, 0.85), flips[0].h_state, 1e-9);
    try std.testing.expectEqual(@as(u32, 10), flips[0].interaction_count);
}

test "WI-A3-T-no-emit-on-skip: cell_id forwarded correctly" {
    var store: Store = undefined;
    store.init(pask_config.DEFAULT);

    _ = try store.upsertNode("cell-d-xyz", "", 1000);
    store.nodes[0].is_stable = 0;

    var observer = PaskStableObserver.init(&store);
    observer.snapshotPre();

    store.nodes[0].is_stable = 1;

    var flips: [MAX_FLIPS]StableFlip = undefined;
    const n = observer.collectFlips(&flips);
    try std.testing.expectEqual(@as(u32, 1), n);
    try std.testing.expectEqualStrings("cell-d-xyz", flips[0].cellId());
}

test "WI-A3-T-no-emit-on-skip: multiple flips collected in one pass" {
    var store: Store = undefined;
    store.init(pask_config.DEFAULT);

    _ = try store.upsertNode("cell-e1", "", 1000);
    _ = try store.upsertNode("cell-e2", "", 1000);
    _ = try store.upsertNode("cell-e3", "", 1000);
    store.nodes[0].is_stable = 0;
    store.nodes[1].is_stable = 1; // already stable
    store.nodes[2].is_stable = 0;

    var observer = PaskStableObserver.init(&store);
    observer.snapshotPre();

    // Nodes 0 and 2 flip; node 1 was already stable.
    store.nodes[0].is_stable = 1;
    store.nodes[2].is_stable = 1;

    var flips: [MAX_FLIPS]StableFlip = undefined;
    const n = observer.collectFlips(&flips);
    try std.testing.expectEqual(@as(u32, 2), n);
    // Order matches node index order.
    try std.testing.expectEqual(@as(u32, 0), flips[0].node_idx);
    try std.testing.expectEqual(@as(u32, 2), flips[1].node_idx);
}

```
