---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tools/mesh-node/pask_integration.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.269860+00:00
---

# runtime/semantos-brain/tools/mesh-node/pask_integration.zig

```zig
// pask_integration.zig — D-SRS-pask-in-mesh
//
// Embeds a live Pask graph inside mesh-node. Every verified tile tick from a
// peer becomes a pask_interact_run() call:
//
//   interact(primary=peer, related=[self, ...other active peers],
//            strength=1.0, now_ms)
//
// This lets the Pask graph track *temporal co-activation patterns* across
// tile ticks: when two peers fire in the same window their edge weights
// strengthen; when one goes silent its edges decay and eventually prune.
//
// Node identity: the hex of the first 8 bytes of the 16-byte cell_id (=16
// chars, within MAX_CELL_ID_LEN=64) is used as the pask cell_id key.
// Type path: "mnca.tile.tick" for all nodes.
//
// The Store is ~6 MB and lives in module-level BSS (not the stack).
//
// Usage in mesh-node main.zig:
//   1. pask_integration.init(self_cell_id, peer_cell_ids) on startup.
//   2. pask_integration.onTileTick(peer_cell_id, tile_tick, now_ms) per RX tile.
//   3. pask_integration.logStats() periodically.

const std = @import("std");
const store_mod = @import("pask_store");
const cfg_mod = @import("pask_config");
const types = @import("pask_types");
const propagation = @import("pask_propagation");
const stability_mod = @import("pask_stability");
const pruner_mod = @import("pask_pruner");

const Store = store_mod.Store;
const Affected = propagation.Affected;
const NodeIdx = types.NodeIdx;
const NULL_IDX = types.NULL_IDX;

// ── Mesh Pask config ───────────────────────────────────────────────────────

const MESH_CONFIG: cfg_mod.Config = .{
    .prune_threshold = -0.3,
    .stability_epsilon = 0.01,
    .min_interactions = 5,
    .propagation_depth = 2,
    .learning_rate = 0.1,
    .stability_window_ms = 30_000,
    .stability_check_every = 10,
    .prune_every = 100,
};

const TYPE_PATH = "mnca.tile.tick";

// ── BSS globals (Store is ~6 MB; must not live on the stack) ──────────────

var g_store: Store = undefined;
var g_affected: Affected = undefined;
var g_tick: u64 = 0;
var g_initialized: bool = false;

// ── Node table (mesh cell_id → Pask NodeIdx) ──────────────────────────────

const MAX_MESH_NODES = 32; // enough for a 16-Pi mesh + self

const NodeEntry = struct {
    /// First 8 bytes of the 16-byte binary cell_id.
    cell_id_prefix: [16]u8,
    pask_idx: NodeIdx,
    /// Short display label (label from config.peers[i].label, if provided).
    label: [48]u8 = [_]u8{0} ** 48,
    prev_stable: bool = false,
};

var g_nodes: [MAX_MESH_NODES]NodeEntry = undefined;
var g_node_count: usize = 0;
var g_self_idx: NodeIdx = NULL_IDX;

// ── Helpers ────────────────────────────────────────────────────────────────

/// Format the first 8 bytes of a cell_id as a 16-char hex string (stack buf).
fn cellHex(cell_id: *const [32]u8, buf: *[32]u8) []const u8 {
    const hex = "0123456789abcdef";
    for (cell_id[0..8], 0..) |b, i| {
        buf[i * 2] = hex[b >> 4];
        buf[i * 2 + 1] = hex[b & 0xF];
    }
    return buf[0..16];
}

/// Upsert a Pask node for the given 16-byte cell_id. Returns its NodeIdx or
/// NULL_IDX on error (store full or cell_id already at MAX_MESH_NODES).
fn upsertMeshNode(cell_id: *const [32]u8, now_ms: u64) NodeIdx {
    // Linear scan the local table (N ≤ 32).
    for (g_nodes[0..g_node_count]) |*e| {
        if (std.mem.eql(u8, &e.cell_id_prefix, cell_id[0..16])) return e.pask_idx;
    }
    if (g_node_count >= MAX_MESH_NODES) return NULL_IDX;

    // Encode cell_id as 16-char hex for the Pask cell_id field.
    var hex_buf: [32]u8 = undefined;
    const pask_cell_id = cellHex(cell_id, &hex_buf);

    const idx = g_store.upsertNode(pask_cell_id, TYPE_PATH, now_ms) catch return NULL_IDX;

    var entry: NodeEntry = .{ .cell_id_prefix = cell_id[0..16].*, .pask_idx = idx };
    // Default label = first 8 hex chars of cell_id.
    @memcpy(entry.label[0..8], hex_buf[0..8]);
    g_nodes[g_node_count] = entry;
    g_node_count += 1;
    return idx;
}

/// Look up a NodeIdx by 16-byte cell_id prefix. Returns NULL_IDX if unknown.
fn findMeshNode(cell_id: *const [32]u8) NodeIdx {
    for (g_nodes[0..g_node_count]) |*e| {
        if (std.mem.eql(u8, &e.cell_id_prefix, cell_id[0..16])) return e.pask_idx;
    }
    return NULL_IDX;
}

// ── Public API ─────────────────────────────────────────────────────────────

/// Initialize the Pask integration.
///
/// `self_cell_id`   — this node's 16-byte binary cell_id.
/// `peer_cell_ids`  — slice of peer 16-byte cell_ids.
/// `peer_labels`    — optional slice of peer labels (parallel to peer_cell_ids).
///
/// Call once after loading the node config, before the main loop.
pub fn init(
    self_cell_id: *const [32]u8,
    peer_cell_ids: []const [32]u8,
    peer_labels: ?[]const []const u8,
) void {
    if (g_initialized) return;

    g_store.init(MESH_CONFIG);
    g_affected.init();
    g_node_count = 0;
    g_tick = 0;

    const now_ms: u64 = @intCast(std.time.milliTimestamp());

    // Register self (slot 0).
    g_self_idx = upsertMeshNode(self_cell_id, now_ms);
    if (g_self_idx != NULL_IDX) {
        std.mem.copyForwards(u8, &g_nodes[0].label, "self");
    }

    // Register peers (slots 1..N).
    for (peer_cell_ids, 0..) |*cid, i| {
        const idx = upsertMeshNode(cid, now_ms);
        if (idx != NULL_IDX and peer_labels != null) {
            const lbls = peer_labels.?;
            if (i < lbls.len) {
                const lbl = lbls[i];
                // g_nodes[g_node_count-1] was just appended by upsertMeshNode.
                // Find the entry we just created.
                for (g_nodes[0..g_node_count]) |*e| {
                    if (e.pask_idx == idx) {
                        const n = @min(lbl.len, e.label.len - 1);
                        @memcpy(e.label[0..n], lbl[0..n]);
                        break;
                    }
                }
            }
        }
    }

    g_initialized = true;
    std.log.info(
        "pask-mesh: initialized — {d} nodes (1 self + {d} peers), depth={d}",
        .{ g_node_count, peer_cell_ids.len, MESH_CONFIG.propagation_depth },
    );
}

/// Process one tile tick received from a peer.
///
/// `peer_cell_id` — 16-byte binary cell_id of the sending peer.
/// `tile_tick`    — tile tick counter (from tile header, for future use).
/// `now_ms`       — wall-clock milliseconds (std.time.milliTimestamp()).
///
/// Returns true if any node in the propagation region flipped stability state.
pub fn onTileTick(
    peer_cell_id: *const [32]u8,
    tile_tick: u64,
    now_ms: u64,
) bool {
    if (!g_initialized) return false;
    _ = tile_tick; // available for strength modulation in future slices

    const primary_idx = findMeshNode(peer_cell_id);
    if (primary_idx == NULL_IDX) return false;

    // Collect related nodes: self + all other registered peers.
    var related_buf: [cfg_mod.MAX_RELATED]NodeIdx = undefined;
    var related_count: u32 = 0;

    if (g_self_idx != NULL_IDX and g_self_idx != primary_idx) {
        related_buf[related_count] = g_self_idx;
        related_count += 1;
    }
    for (g_nodes[0..g_node_count]) |*e| {
        if (related_count >= cfg_mod.MAX_RELATED) break;
        if (e.pask_idx == primary_idx or e.pask_idx == g_self_idx) continue;
        related_buf[related_count] = e.pask_idx;
        related_count += 1;
    }

    // Core interact loop (mirrors pask_interact_run in main.zig).
    const strength: f64 = 1.0;
    g_affected.init();
    _ = g_affected.add(primary_idx) catch return false;

    for (related_buf[0..related_count]) |rel_idx| {
        const edge_idx = g_store.upsertEdge(primary_idx, rel_idx, now_ms) catch continue;
        const wd = strength * MESH_CONFIG.learning_rate;
        g_store.updateEdgeWeight(edge_idx, wd, now_ms);
        g_store.recordDelta(edge_idx, wd, now_ms);
        _ = g_affected.add(rel_idx) catch {};
    }
    g_store.updateNodeState(primary_idx, strength, now_ms);
    propagation.propagate(&g_store, &g_affected, now_ms) catch return false;

    g_tick += 1;

    // Stability check every 10 ticks.
    var any_flip = false;
    if (MESH_CONFIG.stability_check_every > 0 and
        g_tick % MESH_CONFIG.stability_check_every == 0)
    {
        var i: u32 = 0;
        while (i < g_affected.count) : (i += 1) {
            const result = stability_mod.checkNode(&g_store, g_affected.members[i], now_ms);
            if (result.transitioned_to_stable) {
                any_flip = true;
                const lbl = labelForIdx(g_affected.members[i]);
                std.log.info(
                    "pask-mesh: stability converged label={s} avg_dH={d:.4} pask_tick={d}",
                    .{ lbl, result.avg_delta_h, g_tick },
                );
            }
        }
    }

    // Prune every 100 ticks.
    if (MESH_CONFIG.prune_every > 0 and g_tick % MESH_CONFIG.prune_every == 0) {
        const prune_result = pruner_mod.pruneOnce(&g_store, now_ms);
        if (prune_result.pruned_count > 0) {
            std.log.info("pask-mesh: pruned {d} nodes at tick={d}", .{ prune_result.pruned_count, g_tick });
        }
    }

    return any_flip;
}

/// Log a summary line of the current Pask graph state.
pub fn logStats() void {
    if (!g_initialized) return;
    std.log.info(
        "pask-mesh: nodes={d} edges={d} pask_tick={d}",
        .{ g_store.node_count, g_store.edge_count, g_tick },
    );
}

fn labelForIdx(idx: NodeIdx) []const u8 {
    for (g_nodes[0..g_node_count]) |*e| {
        if (e.pask_idx == idx) {
            const s = std.mem.sliceTo(&e.label, 0);
            if (s.len > 0) return s;
        }
    }
    return "?";
}

```
