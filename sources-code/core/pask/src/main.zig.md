---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/src/main.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.931455+00:00
---

# core/pask/src/main.zig

```zig
// Pask WASM entry point. Exports a flat C-callable surface mirroring
// PaskianAdapter (friend-semantos/packages/paskian/src/adapter.ts).
//
// Snapshot ABI matches the cell-engine's kernel_snapshot_state /
// kernel_restore_state pattern (core/cell-engine/src/main.zig:178-230)
// so persistence/migration looks the same to callers.
//
// All clock inputs are caller-supplied (now_ms argument). The kernel
// never reads a host clock — determinism wins, replays are bit-identical.

const std = @import("std");
const config = @import("config");
const types = @import("types");
const store_mod = @import("store");
const propagation = @import("propagation");
const stability_mod = @import("stability");
const pruner = @import("pruner");

const Store = store_mod.Store;
const Affected = propagation.Affected;
const NodeIdx = types.NodeIdx;
const NULL_IDX = types.NULL_IDX;

// ── Global state ────────────────────────────────────────────────────────
//
// The whole graph + delta ring lives in `g_store`. `initInPlace`-style
// to avoid blowing the WASM stack with a large struct construction.

var g_store: Store = undefined;
var g_initialized: bool = false;
var g_interaction_tick: u64 = 0;
/// Scratch affected-set, reused across interact() calls (zeroed at top).
var g_affected: Affected = undefined;
/// Last error code from a fallible export. 0 = success.
var g_last_error: i32 = 0;

// Snapshot buffer header layout (mirrors cell-engine's CESN format):
//   [u32 magic   = "PASK"  = 0x4B534150 little-endian]
//   [u32 version = 1]
//   [u32 length  = sizeof(Store)]
//   [length bytes Store image]
const SNAPSHOT_MAGIC: u32 = 0x4B534150;
const SNAPSHOT_VERSION: u32 = 1;
const SNAPSHOT_HEADER_SIZE: usize = 12;
const SNAPSHOT_BUF_SIZE: usize = @sizeOf(Store) + SNAPSHOT_HEADER_SIZE;

var g_snapshot_buffer: [SNAPSHOT_BUF_SIZE]u8 align(8) = undefined;

// ── Error code surface ──────────────────────────────────────────────────

fn errToCode(err: types.PaskError) i32 {
    return switch (err) {
        error.not_initialized => -1,
        error.nodes_full => -2,
        error.edges_full => -3,
        error.delta_ring_full => -4,
        error.cell_id_too_long => -5,
        error.type_path_too_long => -6,
        error.too_many_related => -7,
        error.affected_overflow => -8,
        error.invalid_index => -9,
        error.invalid_strength => -10,
    };
}

// ── Lifecycle exports ───────────────────────────────────────────────────

export fn pask_init() callconv(.c) i32 {
    g_store.init(config.DEFAULT);
    g_affected.init();
    g_initialized = true;
    g_interaction_tick = 0;
    g_last_error = 0;
    return 0;
}

/// Override config. Caller writes a Config struct (see config.zig) into
/// WASM memory and passes the pointer.
export fn pask_set_config(cfg_ptr: [*]const u8) callconv(.c) i32 {
    if (!g_initialized) return -1;
    const cfg: *const config.Config = @ptrCast(@alignCast(cfg_ptr));
    g_store.cfg = cfg.*;
    return 0;
}

export fn pask_reset() callconv(.c) i32 {
    g_store.init(g_store.cfg);
    g_affected.init();
    g_interaction_tick = 0;
    return 0;
}

export fn pask_last_error() callconv(.c) i32 {
    return g_last_error;
}

// ── Interaction primitives ──────────────────────────────────────────────
//
// Two-phase API: caller stages the cell_id / type / related list, then
// calls pask_interact_run. We split this way to avoid passing a packed
// related-cells blob across the wasm boundary, which is awkward from JS.

/// Stage the primary cell. Returns its node index on success, negative on error.
export fn pask_upsert_node(
    cell_id_ptr: [*]const u8,
    cell_id_len: u32,
    type_path_ptr: [*]const u8,
    type_path_len: u32,
    now_ms: u64,
) callconv(.c) i32 {
    if (!g_initialized) return -1;
    const idx = g_store.upsertNode(
        cell_id_ptr[0..cell_id_len],
        type_path_ptr[0..type_path_len],
        now_ms,
    ) catch |err| {
        g_last_error = errToCode(err);
        return g_last_error;
    };
    return @intCast(idx);
}

/// Look up a node by cell_id. Returns its index, or NULL_IDX (-1) if absent.
export fn pask_find_node(
    cell_id_ptr: [*]const u8,
    cell_id_len: u32,
) callconv(.c) i32 {
    if (!g_initialized) return -1;
    const idx = g_store.findNode(cell_id_ptr[0..cell_id_len]);
    if (idx == NULL_IDX) return -1;
    return @intCast(idx);
}

/// One full interact() pass. Mirrors adapter.ts:82-161.
///
/// related_idx_ptr is a packed array of u32 node indices (already upserted
/// by the caller via pask_upsert_node). Length `related_count`.
///
/// effective_strength is `strength * contextWeight` already applied by the
/// caller (matching the TS effectiveStrength). The kernel does not know
/// about contextWeight as a separate concept.
export fn pask_interact_run(
    primary_idx: u32,
    kind_ptr: [*]const u8,
    kind_len: u32,
    effective_strength: f64,
    related_idx_ptr: [*]const u32,
    related_count: u32,
    now_ms: u64,
) callconv(.c) i32 {
    if (!g_initialized) return -1;
    if (primary_idx >= g_store.node_count) {
        g_last_error = errToCode(error.invalid_index);
        return g_last_error;
    }
    if (!std.math.isFinite(effective_strength)) {
        g_last_error = errToCode(error.invalid_strength);
        return g_last_error;
    }
    if (related_count > config.MAX_RELATED) {
        g_last_error = errToCode(error.too_many_related);
        return g_last_error;
    }
    _ = kind_ptr;
    _ = kind_len;

    g_affected.init();
    _ = g_affected.add(primary_idx) catch |err| {
        g_last_error = errToCode(err);
        return g_last_error;
    };

    // Step 1 + 3: ensure edges, update primary node, weight + delta-log
    // each related edge. Mirrors adapter.ts:88-121.
    var r: u32 = 0;
    while (r < related_count) : (r += 1) {
        const related_idx = related_idx_ptr[r];
        if (related_idx >= g_store.node_count) {
            g_last_error = errToCode(error.invalid_index);
            return g_last_error;
        }
        const edge_idx = g_store.upsertEdge(primary_idx, related_idx, now_ms) catch |err| {
            g_last_error = errToCode(err);
            return g_last_error;
        };
        const weight_delta = effective_strength * g_store.cfg.learning_rate;
        g_store.updateEdgeWeight(edge_idx, weight_delta, now_ms);
        g_store.recordDelta(edge_idx, weight_delta, now_ms);
        _ = g_affected.add(related_idx) catch |err| {
            g_last_error = errToCode(err);
            return g_last_error;
        };
    }

    g_store.updateNodeState(primary_idx, effective_strength, now_ms);

    // Step 4: propagation (k iterations of localUpdate + expandRegion).
    propagation.propagate(&g_store, &g_affected, now_ms) catch |err| {
        g_last_error = errToCode(err);
        return g_last_error;
    };

    g_interaction_tick += 1;

    // Step 5: stability check (every Nth tick).
    if (g_store.cfg.stability_check_every > 0 and
        g_interaction_tick % g_store.cfg.stability_check_every == 0)
    {
        var i: u32 = 0;
        while (i < g_affected.count) : (i += 1) {
            _ = stability_mod.checkNode(&g_store, g_affected.members[i], now_ms);
        }
    }

    // Step 6: prune (every Nth tick).
    if (g_store.cfg.prune_every > 0 and
        g_interaction_tick % g_store.cfg.prune_every == 0)
    {
        _ = pruner.pruneOnce(&g_store, now_ms);
    }

    g_last_error = 0;
    return @intCast(g_affected.count);
}

/// Force a stability sweep over every active node, then prune.
/// Use after a batched interact() loop where stability_check_every / prune_every
/// were set to 0.
export fn pask_finalize(now_ms: u64) callconv(.c) i32 {
    if (!g_initialized) return -1;
    var i: u32 = 0;
    while (i < g_store.node_count) : (i += 1) {
        const n = g_store.getNode(i).?;
        if (n.is_pruned == 0) {
            _ = stability_mod.checkNode(&g_store, i, now_ms);
        }
    }
    _ = pruner.pruneOnce(&g_store, now_ms);
    return 0;
}

// ── Read-side exports ──────────────────────────────────────────────────

export fn pask_node_count() callconv(.c) u32 {
    if (!g_initialized) return 0;
    return g_store.node_count;
}

export fn pask_edge_count() callconv(.c) u32 {
    if (!g_initialized) return 0;
    return g_store.edge_count;
}

/// Get a pointer into the global node array. Caller reads sizeof(Node) bytes.
/// Returns 0 if idx is out of range.
export fn pask_node_ptr(idx: u32) callconv(.c) u32 {
    if (!g_initialized) return 0;
    if (idx >= g_store.node_count) return 0;
    return @intCast(@intFromPtr(&g_store.nodes[idx]));
}

export fn pask_edge_ptr(idx: u32) callconv(.c) u32 {
    if (!g_initialized) return 0;
    if (idx >= g_store.edge_count) return 0;
    return @intCast(@intFromPtr(&g_store.edges[idx]));
}

/// Pointer to a Node's cell_id bytes (read cell_id_len bytes after).
/// Returned as the offset to the cell_id field directly.
export fn pask_node_cell_id_ptr(idx: u32) callconv(.c) u32 {
    if (!g_initialized) return 0;
    if (idx >= g_store.node_count) return 0;
    return @intCast(@intFromPtr(&g_store.nodes[idx].cell_id));
}

/// h_state of node, or 0 if invalid.
export fn pask_node_h_state(idx: u32) callconv(.c) f64 {
    if (!g_initialized) return 0;
    if (idx >= g_store.node_count) return 0;
    return g_store.nodes[idx].h_state;
}

/// 1 if stable, 0 if not, -1 if invalid.
export fn pask_node_is_stable(idx: u32) callconv(.c) i32 {
    if (!g_initialized) return -1;
    if (idx >= g_store.node_count) return -1;
    return g_store.nodes[idx].is_stable;
}

/// 1 if pruned, 0 if not, -1 if invalid.
export fn pask_node_is_pruned(idx: u32) callconv(.c) i32 {
    if (!g_initialized) return -1;
    if (idx >= g_store.node_count) return -1;
    return g_store.nodes[idx].is_pruned;
}

/// Number of stable, non-pruned nodes (for sizing `pask_stable_threads_into`).
export fn pask_stable_count() callconv(.c) u32 {
    if (!g_initialized) return 0;
    var n: u32 = 0;
    var i: u32 = 0;
    while (i < g_store.node_count) : (i += 1) {
        const node = g_store.getNode(i).?;
        if (node.is_stable == 1 and node.is_pruned == 0) n += 1;
    }
    return n;
}

/// Write up to `max` StableThread records into out_ptr. Returns the number
/// written. Caller-allocated buffer must be max * sizeof(StableThread) bytes.
/// Order: descending h_state (matches stableThreads SQL ORDER BY).
export fn pask_stable_threads_into(
    out_ptr: [*]u8,
    max: u32,
) callconv(.c) u32 {
    if (!g_initialized) return 0;

    // Pass 1 — collect indices of stable, non-pruned nodes.
    var pool: [config.MAX_NODES]NodeIdx = undefined;
    var pool_count: u32 = 0;
    var i: u32 = 0;
    while (i < g_store.node_count) : (i += 1) {
        const node = g_store.getNode(i).?;
        if (node.is_stable == 1 and node.is_pruned == 0) {
            pool[pool_count] = i;
            pool_count += 1;
        }
    }

    // Pass 2 — selection sort to pick the top `max` by h_state desc.
    // For pool sizes up to a few thousand this is fine; for bigger graphs
    // a partial heap-sort would be the next move.
    const out_threads: [*]types.StableThread = @ptrCast(@alignCast(out_ptr));
    const want = @min(max, pool_count);
    var written: u32 = 0;
    while (written < want) : (written += 1) {
        var best: u32 = written;
        var j: u32 = written + 1;
        const w_node = g_store.getNode(pool[written]).?;
        var best_h = w_node.h_state;
        while (j < pool_count) : (j += 1) {
            const cand = g_store.getNode(pool[j]).?;
            if (cand.h_state > best_h) {
                best = j;
                best_h = cand.h_state;
            }
        }
        if (best != written) {
            const tmp = pool[written];
            pool[written] = pool[best];
            pool[best] = tmp;
        }
        const node_idx = pool[written];
        const node = g_store.getNode(node_idx).?;
        out_threads[written] = .{
            .node_idx = node_idx,
            .h_state = node.h_state,
            .total_constraint_strength = g_store.totalInboundWeight(node_idx),
            .interaction_count = node.interaction_count,
        };
    }
    return written;
}

// ── Zero-copy array views ──────────────────────────────────────────────
//
// Damian's ask: walk N..M nodes/edges/stable-threads without one trampoline
// call per element. These exports give the caller a base pointer + the
// element stride so JS can build a single typed-array view over the
// kernel's contiguous arrays in linear memory and read directly.
//
// The Node and Edge arrays are alive for the lifetime of the kernel —
// no element-shifting on prune (we mark `is_pruned` instead). Indices
// returned from any kernel call remain valid until pask_reset.
//
// The stable-threads array is materialised on demand into the snapshot
// buffer (since it requires a sort by h_state); use pask_stable_range
// to drive that into the buffer once and then read directly.

export fn pask_node_array_ptr() callconv(.c) u32 {
    if (!g_initialized) return 0;
    return @intCast(@intFromPtr(&g_store.nodes));
}

export fn pask_edge_array_ptr() callconv(.c) u32 {
    if (!g_initialized) return 0;
    return @intCast(@intFromPtr(&g_store.edges));
}

export fn pask_node_stride() callconv(.c) u32 {
    return @sizeOf(types.Node);
}

export fn pask_edge_stride() callconv(.c) u32 {
    return @sizeOf(types.Edge);
}

export fn pask_stable_thread_stride() callconv(.c) u32 {
    return @sizeOf(types.StableThread);
}

/// Materialise stable threads sorted by h_state desc into the snapshot
/// buffer (re-used as scratch for output). Returns the number written.
/// After this call, the caller can read [start_offset..end_offset) directly
/// from the snapshot buffer without further trampoline calls. Bounded by
/// `max` and the size of the snapshot buffer.
///
/// Layout of the buffer after this call:
///   [count u32][stride u32][... count * stride bytes ...]
export fn pask_stable_threads_build(max: u32) callconv(.c) i32 {
    if (!g_initialized) return -1;

    const stride: u32 = @sizeOf(types.StableThread);
    const header_bytes: u32 = 8;
    const cap = (SNAPSHOT_BUF_SIZE - header_bytes) / stride;
    const want = @min(max, cap);

    // Write header.
    std.mem.writeInt(u32, g_snapshot_buffer[0..4], 0, .little); // count placeholder
    std.mem.writeInt(u32, g_snapshot_buffer[4..8], stride, .little);

    // Reuse the stable-threads-into export's logic, writing past the header.
    const out_ptr_addr: u32 = @intCast(@intFromPtr(&g_snapshot_buffer) + header_bytes);
    const out_ptr: [*]u8 = @ptrFromInt(out_ptr_addr);
    const written = pask_stable_threads_into(out_ptr, want);

    // Patch the count.
    std.mem.writeInt(u32, g_snapshot_buffer[0..4], written, .little);
    return @intCast(written);
}

/// Pointer to the stable-threads array materialised by
/// pask_stable_threads_build. The buffer layout is documented above.
export fn pask_stable_threads_buf_ptr() callconv(.c) u32 {
    return @intCast(@intFromPtr(&g_snapshot_buffer));
}

// ── Snapshot / restore ─────────────────────────────────────────────────

/// Address of the snapshot buffer in linear memory. Bindings write a blob
/// here directly when restoring (the buffer is sized to fit a full
/// snapshot, so the 16 KB scratch can't hold one).
export fn pask_snapshot_buf_ptr() callconv(.c) u32 {
    return @intCast(@intFromPtr(&g_snapshot_buffer));
}

export fn pask_snapshot_buf_len() callconv(.c) u32 {
    return @intCast(g_snapshot_buffer.len);
}

export fn pask_snapshot_state() callconv(.c) u32 {
    if (!g_initialized) return 0;
    const store_size: u32 = @intCast(@sizeOf(Store));

    std.mem.writeInt(u32, g_snapshot_buffer[0..4], SNAPSHOT_MAGIC, .little);
    std.mem.writeInt(u32, g_snapshot_buffer[4..8], SNAPSHOT_VERSION, .little);
    std.mem.writeInt(u32, g_snapshot_buffer[8..12], store_size, .little);

    const store_bytes = std.mem.asBytes(&g_store);
    @memcpy(g_snapshot_buffer[SNAPSHOT_HEADER_SIZE..][0..store_bytes.len], store_bytes);
    return @intCast(@intFromPtr(&g_snapshot_buffer));
}

/// Restore from a previously-captured snapshot. Returns 0 on success,
/// negative on (-2 magic, -3 version, -4 length) mismatch.
export fn pask_restore_state(ptr: u32) callconv(.c) i32 {
    if (!g_initialized) return -1;
    const header_ptr: [*]const u8 = @ptrFromInt(ptr);
    const magic = std.mem.readInt(u32, header_ptr[0..4], .little);
    const version = std.mem.readInt(u32, header_ptr[4..8], .little);
    const length = std.mem.readInt(u32, header_ptr[8..12], .little);

    if (magic != SNAPSHOT_MAGIC) return -2;
    if (version != SNAPSHOT_VERSION) return -3;
    if (length != @as(u32, @intCast(@sizeOf(Store)))) return -4;

    const payload_ptr: [*]const u8 = @ptrFromInt(ptr + @as(u32, SNAPSHOT_HEADER_SIZE));
    const store_bytes = std.mem.asBytes(&g_store);
    @memcpy(store_bytes, payload_ptr[0..store_bytes.len]);
    return 0;
}

// ── Memory helpers for callers (mirrors cell-engine) ───────────────────
//
// Callers write strings into linear memory. These exports give them a
// scratch area to use without needing to import malloc/free.

var g_scratch: [16 * 1024]u8 align(8) = undefined;

export fn pask_scratch_ptr() callconv(.c) u32 {
    return @intCast(@intFromPtr(&g_scratch));
}

export fn pask_scratch_len() callconv(.c) u32 {
    return @intCast(g_scratch.len);
}

// ── Compile-time export to keep types referenced ───────────────────────
// Without this, dead-code elimination drops the Store struct shape from
// the wasm so the bindings can't query field offsets.
comptime {
    _ = Store;
    _ = types.Node;
    _ = types.Edge;
    _ = types.StableThread;
    _ = config.Config;
}

// ── Layout asserts (load-bearing for the TS bindings) ──────────────────
// adapter.ts hand-rolls struct offsets. Drift here = silent corruption
// on the JS side. Lock the layout at compile time so a struct change
// in types.zig fails the build before it can ship a broken wasm.
comptime {
    if (@sizeOf(types.Node) != 208) @compileError("Node size drift");
    if (@offsetOf(types.Node, "cell_id") != 0) @compileError("Node.cell_id offset drift");
    if (@offsetOf(types.Node, "cell_id_len") != 64) @compileError("Node.cell_id_len offset drift");
    if (@offsetOf(types.Node, "type_path") != 68) @compileError("Node.type_path offset drift");
    if (@offsetOf(types.Node, "type_path_len") != 164) @compileError("Node.type_path_len offset drift");
    if (@offsetOf(types.Node, "h_state") != 168) @compileError("Node.h_state offset drift");
    if (@offsetOf(types.Node, "stability") != 176) @compileError("Node.stability offset drift");
    if (@offsetOf(types.Node, "interaction_count") != 184) @compileError("Node.interaction_count offset drift");
    if (@offsetOf(types.Node, "is_stable") != 188) @compileError("Node.is_stable offset drift");
    if (@offsetOf(types.Node, "is_pruned") != 189) @compileError("Node.is_pruned offset drift");
    if (@offsetOf(types.Node, "created_at") != 192) @compileError("Node.created_at offset drift");
    if (@offsetOf(types.Node, "updated_at") != 200) @compileError("Node.updated_at offset drift");

    if (@sizeOf(types.Edge) != 40) @compileError("Edge size drift");
    if (@offsetOf(types.Edge, "from_idx") != 0) @compileError("Edge.from_idx offset drift");
    if (@offsetOf(types.Edge, "to_idx") != 4) @compileError("Edge.to_idx offset drift");
    if (@offsetOf(types.Edge, "constraint_weight") != 8) @compileError("Edge.constraint_weight offset drift");
    if (@offsetOf(types.Edge, "delta_trend") != 16) @compileError("Edge.delta_trend offset drift");
    if (@offsetOf(types.Edge, "interaction_count") != 24) @compileError("Edge.interaction_count offset drift");
    if (@offsetOf(types.Edge, "last_updated") != 32) @compileError("Edge.last_updated offset drift");

    if (@sizeOf(types.StableThread) != 32) @compileError("StableThread size drift");
    if (@offsetOf(types.StableThread, "node_idx") != 0) @compileError("StableThread.node_idx offset drift");
    if (@offsetOf(types.StableThread, "h_state") != 8) @compileError("StableThread.h_state offset drift");
    if (@offsetOf(types.StableThread, "total_constraint_strength") != 16) @compileError("StableThread.total_constraint_strength offset drift");
    if (@offsetOf(types.StableThread, "interaction_count") != 24) @compileError("StableThread.interaction_count offset drift");

    if (@sizeOf(config.Config) != 48) @compileError("Config size drift");
    if (@offsetOf(config.Config, "prune_threshold") != 0) @compileError("Config.prune_threshold offset drift");
    if (@offsetOf(config.Config, "stability_epsilon") != 8) @compileError("Config.stability_epsilon offset drift");
    if (@offsetOf(config.Config, "min_interactions") != 16) @compileError("Config.min_interactions offset drift");
    if (@offsetOf(config.Config, "propagation_depth") != 20) @compileError("Config.propagation_depth offset drift");
    if (@offsetOf(config.Config, "learning_rate") != 24) @compileError("Config.learning_rate offset drift");
    if (@offsetOf(config.Config, "stability_window_ms") != 32) @compileError("Config.stability_window_ms offset drift");
    if (@offsetOf(config.Config, "stability_check_every") != 40) @compileError("Config.stability_check_every offset drift");
    if (@offsetOf(config.Config, "prune_every") != 44) @compileError("Config.prune_every offset drift");
}

```
