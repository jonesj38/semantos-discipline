---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/src/store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.931164+00:00
---

# core/pask/src/store.zig

```zig
// Pask store — fixed-pool implementation of the SQLite-backed
// PaskianStore (friend-semantos/packages/paskian/src/store.ts).
//
// Layout: nodes/edges live in arrays; the cell_id → node_idx and
// (from_idx,to_idx) → edge_idx maps are linear-probed open-addressed
// hash tables sitting in adjacent arrays. Rationale: this lets us pack
// the entire store into a single struct that a snapshot/restore pair
// can move with a single @memcpy, matching the kernel's PDA layout.
//
// Edges use composite keys (from_idx, to_idx). The TS impl keys on
// the string form `${from}-${to}` — same uniqueness, just cheaper.
//
// No SQLite. The avgDelta / inboundTrend queries are O(N) sweeps over
// fixed-size arrays. For graphs at chess-rig scale (~10k nodes,
// ~30k edges) this is cache-friendly and faster than SQLite anyway.

const std = @import("std");
const config = @import("config");
const types = @import("types");

const Node = types.Node;
const Edge = types.Edge;
const Delta = types.Delta;
const NodeIdx = types.NodeIdx;
const EdgeIdx = types.EdgeIdx;
const NULL_IDX = types.NULL_IDX;

// Linear-probe hash table sizes: must be powers of two and at least
// 2× the data capacity to keep load factor below 0.5.
const NODE_TABLE_CAP: u32 = blk: {
    var cap: u32 = 1;
    while (cap < config.MAX_NODES * 2) cap <<= 1;
    break :blk cap;
};
const EDGE_TABLE_CAP: u32 = blk: {
    var cap: u32 = 1;
    while (cap < config.MAX_EDGES * 2) cap <<= 1;
    break :blk cap;
};

pub const Store = extern struct {
    cfg: config.Config,

    nodes: [config.MAX_NODES]Node,
    node_count: u32,
    /// Open-addressed hash table: cell_id → node_idx (NULL_IDX = empty).
    node_table: [NODE_TABLE_CAP]NodeIdx,

    edges: [config.MAX_EDGES]Edge,
    edge_count: u32,
    /// Open-addressed hash table: (from_idx, to_idx) → edge_idx.
    edge_table: [EDGE_TABLE_CAP]EdgeIdx,

    /// Per-edge delta ring buffer. avgDelta() walks back from `delta_head`
    /// summing entries within the stability window.
    delta_buf: [config.DELTA_RING_CAP]Delta,
    /// Number of inserted samples; head = (delta_head - 1) mod CAP.
    /// Wraps freely; old entries get overwritten — this is the "windowed"
    /// behaviour of the TS impl, which used `WHERE timestamp > since`.
    delta_head: u32,
    delta_filled: u8,
    _pad0: [3]u8 = .{0} ** 3,

    pub fn init(self: *Store, cfg: config.Config) void {
        self.cfg = cfg;
        self.node_count = 0;
        @memset(self.node_table[0..NODE_TABLE_CAP], NULL_IDX);
        self.edge_count = 0;
        @memset(self.edge_table[0..EDGE_TABLE_CAP], NULL_IDX);
        self.delta_head = 0;
        self.delta_filled = 0;
    }

    // ── Hashing ─────────────────────────────────────────────────────────

    fn hashCellId(bytes: []const u8) u32 {
        // FNV-1a, fold to u32. Identical bytes → identical hash → table hit.
        var h: u64 = 0xcbf29ce484222325;
        for (bytes) |b| {
            h ^= b;
            h *%= 0x100000001b3;
        }
        return @truncate(h ^ (h >> 32));
    }

    fn hashEdge(from: NodeIdx, to: NodeIdx) u32 {
        // Mix two indices. Splittable-mix style.
        var x: u64 = (@as(u64, from) << 32) | @as(u64, to);
        x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
        x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
        x = x ^ (x >> 31);
        return @truncate(x);
    }

    // ── Nodes ───────────────────────────────────────────────────────────

    /// Look up an existing node by cell_id. Returns NULL_IDX if absent.
    pub fn findNode(self: *const Store, cell_id: []const u8) NodeIdx {
        const mask = NODE_TABLE_CAP - 1;
        var slot = hashCellId(cell_id) & mask;
        while (true) {
            const idx = self.node_table[slot];
            if (idx == NULL_IDX) return NULL_IDX;
            const n = &self.nodes[idx];
            if (n.cell_id_len == cell_id.len and
                std.mem.eql(u8, n.cell_id[0..n.cell_id_len], cell_id))
            {
                return idx;
            }
            slot = (slot + 1) & mask;
        }
    }

    /// Insert-or-fetch (mirrors TS upsertNode). Sets created_at on insert,
    /// updates updated_at on every call.
    pub fn upsertNode(
        self: *Store,
        cell_id: []const u8,
        type_path: []const u8,
        now_ms: u64,
    ) types.PaskError!NodeIdx {
        if (cell_id.len == 0 or cell_id.len > config.MAX_CELL_ID_LEN) {
            return error.cell_id_too_long;
        }
        if (type_path.len > config.MAX_TYPE_PATH_LEN) {
            return error.type_path_too_long;
        }

        const mask = NODE_TABLE_CAP - 1;
        var slot = hashCellId(cell_id) & mask;
        while (true) {
            const idx = self.node_table[slot];
            if (idx == NULL_IDX) {
                if (self.node_count >= config.MAX_NODES) return error.nodes_full;
                const new_idx = self.node_count;
                var n = &self.nodes[new_idx];
                n.* = .{
                    .cell_id = undefined,
                    .cell_id_len = @intCast(cell_id.len),
                    .type_path = undefined,
                    .type_path_len = @intCast(type_path.len),
                    .h_state = 0,
                    .stability = 0,
                    .interaction_count = 0,
                    .is_stable = 0,
                    .is_pruned = 0,
                    .created_at = now_ms,
                    .updated_at = now_ms,
                };
                @memcpy(n.cell_id[0..cell_id.len], cell_id);
                @memcpy(n.type_path[0..type_path.len], type_path);
                self.nodes[new_idx] = n.*;
                self.node_table[slot] = new_idx;
                self.node_count += 1;
                return new_idx;
            }
            const n = &self.nodes[idx];
            if (n.cell_id_len == cell_id.len and
                std.mem.eql(u8, n.cell_id[0..n.cell_id_len], cell_id))
            {
                n.updated_at = now_ms;
                return idx;
            }
            slot = (slot + 1) & mask;
        }
    }

    pub fn getNode(self: *const Store, idx: NodeIdx) ?*const Node {
        if (idx >= self.node_count) return null;
        return &self.nodes[idx];
    }

    pub fn getNodeMut(self: *Store, idx: NodeIdx) ?*Node {
        if (idx >= self.node_count) return null;
        return &self.nodes[idx];
    }

    /// store.ts:171 — guard: drop NaN/Inf deltas at the boundary.
    pub fn updateNodeState(self: *Store, idx: NodeIdx, delta_h: f64, now_ms: u64) void {
        if (!std.math.isFinite(delta_h)) return;
        if (idx >= self.node_count) return;
        const n = &self.nodes[idx];
        n.h_state += delta_h;
        n.interaction_count += 1;
        n.updated_at = now_ms;
    }

    pub fn markStable(self: *Store, idx: NodeIdx, is_stable: bool) void {
        if (idx >= self.node_count) return;
        self.nodes[idx].is_stable = if (is_stable) 1 else 0;
    }

    pub fn markPruned(self: *Store, idx: NodeIdx) void {
        if (idx >= self.node_count) return;
        self.nodes[idx].is_pruned = 1;
    }

    // ── Edges ───────────────────────────────────────────────────────────

    pub fn findEdge(self: *const Store, from: NodeIdx, to: NodeIdx) EdgeIdx {
        const mask = EDGE_TABLE_CAP - 1;
        var slot = hashEdge(from, to) & mask;
        while (true) {
            const idx = self.edge_table[slot];
            if (idx == NULL_IDX) return NULL_IDX;
            const e = &self.edges[idx];
            if (e.from_idx == from and e.to_idx == to) return idx;
            slot = (slot + 1) & mask;
        }
    }

    pub fn upsertEdge(
        self: *Store,
        from: NodeIdx,
        to: NodeIdx,
        now_ms: u64,
    ) types.PaskError!EdgeIdx {
        const mask = EDGE_TABLE_CAP - 1;
        var slot = hashEdge(from, to) & mask;
        while (true) {
            const idx = self.edge_table[slot];
            if (idx == NULL_IDX) {
                if (self.edge_count >= config.MAX_EDGES) return error.edges_full;
                const new_idx = self.edge_count;
                self.edges[new_idx] = .{
                    .from_idx = from,
                    .to_idx = to,
                    .constraint_weight = 0,
                    .delta_trend = 0,
                    .interaction_count = 0,
                    .last_updated = now_ms,
                };
                self.edge_table[slot] = new_idx;
                self.edge_count += 1;
                return new_idx;
            }
            const e = &self.edges[idx];
            if (e.from_idx == from and e.to_idx == to) {
                e.last_updated = now_ms;
                return idx;
            }
            slot = (slot + 1) & mask;
        }
    }

    pub fn getEdge(self: *const Store, idx: EdgeIdx) ?*const Edge {
        if (idx >= self.edge_count) return null;
        return &self.edges[idx];
    }

    pub fn getEdgeMut(self: *Store, idx: EdgeIdx) ?*Edge {
        if (idx >= self.edge_count) return null;
        return &self.edges[idx];
    }

    pub fn updateEdgeWeight(self: *Store, idx: EdgeIdx, delta: f64, now_ms: u64) void {
        if (idx >= self.edge_count) return;
        if (!std.math.isFinite(delta)) return;
        const e = &self.edges[idx];
        e.constraint_weight += delta;
        e.interaction_count += 1;
        e.last_updated = now_ms;
    }

    pub fn updateEdgeTrend(self: *Store, idx: EdgeIdx, trend: f64) void {
        if (idx >= self.edge_count) return;
        if (!std.math.isFinite(trend)) return;
        self.edges[idx].delta_trend = trend;
    }

    // ── Neighbour iteration ─────────────────────────────────────────────
    //
    // O(N) sweep over the edge array. Acceptable for graphs at the
    // configured cap. If callers ever need it faster, materialize an
    // adjacency index in the snapshot — but the TS impl was also O(N) at
    // the SQL level under the hood (SQLite scans the indexed table).

    /// Visit each outgoing edge from `node`. Callback returns false to halt.
    pub fn forEachOutgoing(
        self: *const Store,
        node: NodeIdx,
        ctx: anytype,
        comptime callback: fn (@TypeOf(ctx), EdgeIdx, *const Edge) bool,
    ) void {
        var i: u32 = 0;
        while (i < self.edge_count) : (i += 1) {
            const e = &self.edges[i];
            if (e.from_idx == node) {
                if (!callback(ctx, i, e)) return;
            }
        }
    }

    /// Visit every edge touching `node` (either direction).
    pub fn forEachTouching(
        self: *const Store,
        node: NodeIdx,
        ctx: anytype,
        comptime callback: fn (@TypeOf(ctx), EdgeIdx, *const Edge) bool,
    ) void {
        var i: u32 = 0;
        while (i < self.edge_count) : (i += 1) {
            const e = &self.edges[i];
            if (e.from_idx == node or e.to_idx == node) {
                if (!callback(ctx, i, e)) return;
            }
        }
    }

    // ── Delta log ──────────────────────────────────────────────────────

    pub fn recordDelta(self: *Store, edge: EdgeIdx, delta: f64, now_ms: u64) void {
        if (!std.math.isFinite(delta)) return;
        if (edge >= self.edge_count) return;
        self.delta_buf[self.delta_head] = .{
            .edge_idx = edge,
            .delta = delta,
            .timestamp = now_ms,
        };
        self.delta_head = (self.delta_head + 1) % config.DELTA_RING_CAP;
        if (self.delta_head == 0) self.delta_filled = 1;
    }

    /// Mean of |delta| over samples for `edge` whose timestamp falls
    /// within `[now_ms - window_ms, now_ms]`. Returns 0 if no samples.
    pub fn avgDelta(
        self: *const Store,
        edge: EdgeIdx,
        window_ms: u64,
        now_ms: u64,
    ) f64 {
        const since: u64 = if (now_ms > window_ms) now_ms - window_ms else 0;
        var sum: f64 = 0;
        var count: u32 = 0;
        const limit: u32 = if (self.delta_filled == 1)
            config.DELTA_RING_CAP
        else
            self.delta_head;
        var i: u32 = 0;
        while (i < limit) : (i += 1) {
            const d = &self.delta_buf[i];
            if (d.edge_idx == edge and d.timestamp >= since) {
                sum += @abs(d.delta);
                count += 1;
            }
        }
        if (count == 0) return 0;
        return sum / @as(f64, @floatFromInt(count));
    }

    // ── Inbound trend (used by pruner) ─────────────────────────────────
    //
    // Mean of delta_trend across all edges where to_idx == node.

    pub fn inboundTrend(self: *const Store, node: NodeIdx) f64 {
        var sum: f64 = 0;
        var count: u32 = 0;
        var i: u32 = 0;
        while (i < self.edge_count) : (i += 1) {
            const e = &self.edges[i];
            if (e.to_idx == node) {
                sum += e.delta_trend;
                count += 1;
            }
        }
        if (count == 0) return 0;
        return sum / @as(f64, @floatFromInt(count));
    }

    /// Sum of inbound constraint weights (used by stableThreads ranking).
    pub fn totalInboundWeight(self: *const Store, node: NodeIdx) f64 {
        var sum: f64 = 0;
        var i: u32 = 0;
        while (i < self.edge_count) : (i += 1) {
            const e = &self.edges[i];
            if (e.to_idx == node) sum += e.constraint_weight;
        }
        return sum;
    }
};

```
