---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/src/types.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.930886+00:00
---

# core/pask/src/types.zig

```zig
// Pask types — Zig port of friend-semantos/packages/paskian/src/types.ts.
//
// Layout choices vs. TS:
//   - cell_id and type_path are inline fixed buffers, NOT pointers. This
//     is what makes the whole graph a single contiguous struct snapshot-able
//     by @memcpy (same trick the cell-engine uses for kernel_snapshot_state).
//   - is_stable/is_pruned are u8 (booleans) rather than packed bits, for
//     extern-compat with the TS bindings.
//   - edge_id is not stored — it's computed on demand as (from_idx,to_idx).
//     This collapses 64 bytes per edge.

const config = @import("config");

pub const NodeIdx = u32;
pub const EdgeIdx = u32;
pub const NULL_IDX: u32 = 0xFFFF_FFFF;

pub const Node = extern struct {
    cell_id: [config.MAX_CELL_ID_LEN]u8,
    cell_id_len: u32,
    type_path: [config.MAX_TYPE_PATH_LEN]u8,
    type_path_len: u32,
    /// h_i in the paper.
    h_state: f64,
    /// Running average of |ΔH| — used for stability.
    stability: f64,
    interaction_count: u32,
    is_stable: u8,
    is_pruned: u8,
    _pad: [2]u8 = .{0} ** 2,
    /// First update timestamp (ms, caller clock).
    created_at: u64,
    /// Last update timestamp (ms, caller clock).
    updated_at: u64,
};

pub const Edge = extern struct {
    from_idx: NodeIdx,
    to_idx: NodeIdx,
    constraint_weight: f64,
    delta_trend: f64,
    interaction_count: u32,
    _pad: [4]u8 = .{0} ** 4,
    last_updated: u64,
};

/// Per-edge delta sample, kept in a global ring buffer. Used by the
/// stability detector to compute mean |delta| over the recent window.
pub const Delta = extern struct {
    edge_idx: EdgeIdx,
    /// Sentinel-tolerant: NaN/Inf samples are dropped at insert time.
    delta: f64,
    timestamp: u64,
};

pub const StableThread = extern struct {
    node_idx: NodeIdx,
    h_state: f64,
    /// Sum of constraint_weight on inbound edges.
    total_constraint_strength: f64,
    interaction_count: u32,
    _pad: [4]u8 = .{0} ** 4,
};

pub const Interaction = extern struct {
    cell_id_ptr: [*]const u8,
    cell_id_len: u32,
    kind_ptr: [*]const u8,
    kind_len: u32,
    /// Already context-weighted by the caller (matches
    /// adapter.ts:effectiveStrength = strength * contextWeight).
    strength: f64,
    /// Pointer to packed [len:u32, bytes:[len]u8] entries for related cells.
    related_packed_ptr: [*]const u8,
    related_packed_len: u32,
    related_count: u32,
    /// Caller clock (ms). Determinism: kernel never reads a host clock.
    now_ms: u64,
};

pub const PaskError = error{
    not_initialized,
    nodes_full,
    edges_full,
    delta_ring_full,
    cell_id_too_long,
    type_path_too_long,
    too_many_related,
    affected_overflow,
    invalid_index,
    invalid_strength,
};

```
