---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/bench/bench_pask.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.267094+00:00
---

# runtime/semantos-brain/bench/bench_pask.zig

```zig
// Pask Kernel Benchmark Suite
//
// Standalone executable — no external dependencies beyond the Pask kernel
// modules (pask_store, pask_config, pask_types, pask_propagation,
// pask_stability, pask_pruner).
//
// Run via:
//   cd core/cell-engine && zig build bench-pask
//
// The benchmark replicates pask_interact_run() using the Store API directly
// (mirroring main.zig:142-224) so we benchmark the pure kernel logic without
// any WASM boundary overhead.
//
// NOTE: Store is ~6 MB (fixed-pool arrays for 16K nodes, 32K edges, 64K
// delta ring). All Store instances live in global BSS to avoid stack overflows.

const std = @import("std");
const store_mod = @import("pask_store");
const config = @import("pask_config");
const types = @import("pask_types");
const propagation = @import("pask_propagation");
const stability_mod = @import("pask_stability");
const pruner = @import("pask_pruner");

const Store = store_mod.Store;
const Affected = propagation.Affected;
const NodeIdx = types.NodeIdx;
const NULL_IDX = types.NULL_IDX;

// Snapshot ABI (mirrors main.zig):
//   [u32 magic = 0x4B534150 LE][u32 version = 1][u32 length = sizeof(Store)][Store bytes]
const SNAPSHOT_MAGIC: u32 = 0x4B534150;
const SNAPSHOT_VERSION: u32 = 1;
const SNAPSHOT_HEADER_SIZE: usize = 12;
const SNAPSHOT_BUF_SIZE: usize = @sizeOf(Store) + SNAPSHOT_HEADER_SIZE;

// ── Global Store pool ──────────────────────────────────────────────────────
//
// Store is ~6 MB. All benchmark stores live in BSS (global) to avoid
// stack overflows.

var g_store_a: Store = undefined; // primary throughput store
var g_store_b: Store = undefined; // secondary (determinism)
var g_store_c: Store = undefined; // restore target

var g_affected: Affected = undefined;

var g_snap_buf_a: [SNAPSHOT_BUF_SIZE]u8 align(8) = undefined;
var g_snap_buf_b: [SNAPSHOT_BUF_SIZE]u8 align(8) = undefined;
var g_snap_buf_c: [SNAPSHOT_BUF_SIZE]u8 align(8) = undefined;

// ── Output helper ──────────────────────────────────────────────────────────
//
// Zig 0.15: std.io.getStdOut() was removed. Use std.fs.File.stdout().

var out_line: [4096]u8 = undefined;

fn print(comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.bufPrint(&out_line, fmt, args) catch return;
    std.fs.File.stdout().writeAll(s) catch {};
}

/// Print a progress message to stderr (keeps stdout clean for table output).
fn progress(msg: []const u8) void {
    std.fs.File.stderr().writeAll(msg) catch {};
    std.fs.File.stderr().writeAll("\n") catch {};
}

// ── Snapshot helpers ───────────────────────────────────────────────────────

fn snapshotStore(store: *const Store, buf: []u8) void {
    std.debug.assert(buf.len >= SNAPSHOT_BUF_SIZE);
    const store_size: u32 = @intCast(@sizeOf(Store));
    std.mem.writeInt(u32, buf[0..4], SNAPSHOT_MAGIC, .little);
    std.mem.writeInt(u32, buf[4..8], SNAPSHOT_VERSION, .little);
    std.mem.writeInt(u32, buf[8..12], store_size, .little);
    const store_bytes = std.mem.asBytes(store);
    @memcpy(buf[SNAPSHOT_HEADER_SIZE..][0..store_bytes.len], store_bytes);
}

fn restoreStore(store: *Store, buf: []const u8) bool {
    if (buf.len < SNAPSHOT_HEADER_SIZE) return false;
    const magic = std.mem.readInt(u32, buf[0..4], .little);
    const version = std.mem.readInt(u32, buf[4..8], .little);
    const length = std.mem.readInt(u32, buf[8..12], .little);
    if (magic != SNAPSHOT_MAGIC) return false;
    if (version != SNAPSHOT_VERSION) return false;
    if (length != @as(u32, @intCast(@sizeOf(Store)))) return false;
    const store_bytes = std.mem.asBytes(store);
    @memcpy(store_bytes, buf[SNAPSHOT_HEADER_SIZE..][0..store_bytes.len]);
    return true;
}

// ── Config variants ────────────────────────────────────────────────────────
//
// Throughput benchmarks use BENCH_CONFIG: stability/prune disabled so we
// measure pure interact() throughput (upsert + propagation) without the
// O(N×E) prune sweep that dominates at scale.
//
// Determinism/snapshot tests use FULL_CONFIG (DEFAULT) to exercise the
// complete pipeline.

// BENCH_CONFIG: propagation_depth=0 (no propagation), no prune/stability.
// This measures the pure upsert + edge + node-state update hot path —
// the minimum per-interaction cost before any graph-walk work.
// With propagation_depth=3 and a saturated graph, each tick is O(N_affected * E)
// which is too slow for 1M-call timing. See README for full-config commentary.
const BENCH_CONFIG: config.Config = .{
    .prune_threshold = -0.3,
    .stability_epsilon = 0.01,
    .min_interactions = 5,
    .propagation_depth = 0, // disabled: measures upsert+edge hot path only
    .learning_rate = 0.1,
    .stability_window_ms = 60_000,
    .stability_check_every = 0, // disabled for throughput bench
    .prune_every = 0, // disabled for throughput bench
};

// ── Core interact() replication ────────────────────────────────────────────
//
// Mirrors pask_interact_run() (core/pask/src/main.zig:142-224).

fn interact(
    store: *Store,
    affected: *Affected,
    primary_idx: NodeIdx,
    related_idxs: []const NodeIdx,
    effective_strength: f64,
    now_ms: u64,
    tick: *u64,
) void {
    affected.init();
    _ = affected.add(primary_idx) catch return;

    for (related_idxs) |related_idx| {
        const edge_idx = store.upsertEdge(primary_idx, related_idx, now_ms) catch continue;
        const weight_delta = effective_strength * store.cfg.learning_rate;
        store.updateEdgeWeight(edge_idx, weight_delta, now_ms);
        store.recordDelta(edge_idx, weight_delta, now_ms);
        _ = affected.add(related_idx) catch {};
    }

    store.updateNodeState(primary_idx, effective_strength, now_ms);
    propagation.propagate(store, affected, now_ms) catch {};

    tick.* += 1;

    if (store.cfg.stability_check_every > 0 and
        tick.* % store.cfg.stability_check_every == 0)
    {
        var i: u32 = 0;
        while (i < affected.count) : (i += 1) {
            _ = stability_mod.checkNode(store, affected.members[i], now_ms);
        }
    }

    if (store.cfg.prune_every > 0 and
        tick.* % store.cfg.prune_every == 0)
    {
        _ = pruner.pruneOnce(store, now_ms);
    }
}

// ── Throughput + graph-size benchmark ─────────────────────────────────────
//
// Run up to `n_max` interact() calls with `n_related` related cells.
// Capture node/edge counts at each of the 4 N milestones (1K, 10K, 100K, 1M).
// If the 100K elapsed time * 10 > 60s, bail before 1M and return that info.
// Uses g_store_a and g_affected.

const BenchResult = struct {
    rate_1k: u64,
    rate_10k: u64,
    rate_100k: u64,
    rate_1m: ?u64, // null = skipped (estimated > 60s)
    nodes_1k: u32,
    nodes_10k: u32,
    nodes_100k: u32,
    nodes_1m: u32, // from 100K if 1M skipped
    edges_1k: u32,
    edges_10k: u32,
    edges_100k: u32,
    edges_1m: u32,
    elapsed_100k_ns: u64,
};

// Vocabulary size: pool of VOCAB_SIZE distinct node IDs for the benchmark.
// Using a small vocabulary means the graph stabilises quickly rather than
// growing to the 16K-node, 32K-edge cap where propagation sweeps become
// very slow (O(affected * edge_count) per tick).
// VOCAB_SIZE = 1000 gives ~1K nodes and ~5K edges at saturation — comparable
// to the chess-rig working set and keeps 1M-interaction runs under 10s.
const VOCAB_SIZE: u32 = 1_000;

fn runBench(n_related: u32) BenchResult {
    var result: BenchResult = undefined;

    // Throughput benchmark uses BENCH_CONFIG (prune/stability disabled) to
    // measure pure interact() throughput (upsert + propagation) without the
    // O(N×E) prune sweep that dominates at graph saturation.
    const strength: f64 = 0.5;
    const base_ms: u64 = 1_000_000;
    const type_path = "bench/cell";

    var primary_id_buf: [32]u8 = undefined;
    var related_id_bufs: [config.MAX_RELATED][32]u8 = undefined;
    var related_idxs: [config.MAX_RELATED]NodeIdx = undefined;

    var tick: u64 = 0;

    // ── 1K ────────────────────────────────────────────────────────────────
    g_store_a.init(BENCH_CONFIG);
    g_affected.init();
    tick = 0;

    var timer = std.time.Timer.start() catch @panic("timer");
    var i: u32 = 0;
    while (i < 1_000) : (i += 1) {
        const now_ms: u64 = base_ms + i;
        const pid = std.fmt.bufPrint(&primary_id_buf, "cell_{d:0>8}", .{i % VOCAB_SIZE}) catch unreachable;
        const pidx = g_store_a.upsertNode(pid, type_path, now_ms) catch continue;
        var r: u32 = 0;
        while (r < n_related) : (r += 1) {
            const rid = std.fmt.bufPrint(&related_id_bufs[r], "rel_{d:0>8}", .{(i * 7 + r * 13) % VOCAB_SIZE}) catch unreachable;
            const ridx = g_store_a.upsertNode(rid, type_path, now_ms) catch break;
            related_idxs[r] = ridx;
        }
        interact(&g_store_a, &g_affected, pidx, related_idxs[0..@min(r, n_related)], strength, now_ms, &tick);
    }
    const ns_1k = timer.read();
    result.rate_1k = if (ns_1k == 0) 0 else (1_000 * 1_000_000_000) / ns_1k;
    result.nodes_1k = g_store_a.node_count;
    result.edges_1k = g_store_a.edge_count;

    // ── 10K — continue from 1K state ─────────────────────────────────────
    timer.reset();
    while (i < 10_000) : (i += 1) {
        const now_ms: u64 = base_ms + i;
        const pid = std.fmt.bufPrint(&primary_id_buf, "cell_{d:0>8}", .{i % VOCAB_SIZE}) catch unreachable;
        const pidx = g_store_a.upsertNode(pid, type_path, now_ms) catch continue;
        var r: u32 = 0;
        while (r < n_related) : (r += 1) {
            const rid = std.fmt.bufPrint(&related_id_bufs[r], "rel_{d:0>8}", .{(i * 7 + r * 13) % VOCAB_SIZE}) catch unreachable;
            const ridx = g_store_a.upsertNode(rid, type_path, now_ms) catch break;
            related_idxs[r] = ridx;
        }
        interact(&g_store_a, &g_affected, pidx, related_idxs[0..@min(r, n_related)], strength, now_ms, &tick);
    }
    const ns_10k = timer.read();
    result.rate_10k = if (ns_10k == 0) 0 else (9_000 * 1_000_000_000) / ns_10k;
    result.nodes_10k = g_store_a.node_count;
    result.edges_10k = g_store_a.edge_count;

    // ── 100K — continue from 10K state ───────────────────────────────────
    timer.reset();
    while (i < 100_000) : (i += 1) {
        const now_ms: u64 = base_ms + i;
        const pid = std.fmt.bufPrint(&primary_id_buf, "cell_{d:0>8}", .{i % VOCAB_SIZE}) catch unreachable;
        const pidx = g_store_a.upsertNode(pid, type_path, now_ms) catch continue;
        var r: u32 = 0;
        while (r < n_related) : (r += 1) {
            const rid = std.fmt.bufPrint(&related_id_bufs[r], "rel_{d:0>8}", .{(i * 7 + r * 13) % VOCAB_SIZE}) catch unreachable;
            const ridx = g_store_a.upsertNode(rid, type_path, now_ms) catch break;
            related_idxs[r] = ridx;
        }
        interact(&g_store_a, &g_affected, pidx, related_idxs[0..@min(r, n_related)], strength, now_ms, &tick);
    }
    const ns_100k = timer.read();
    result.rate_100k = if (ns_100k == 0) 0 else (90_000 * 1_000_000_000) / ns_100k;
    result.elapsed_100k_ns = ns_100k;
    result.nodes_100k = g_store_a.node_count;
    result.edges_100k = g_store_a.edge_count;

    // ── 1M — check if it would exceed 60s ────────────────────────────────
    // 100K took ns_100k for 90K calls → per-call ≈ ns_100k/90_000.
    // Remaining 900K calls: est = ns_100k * 10. If > 60e9 ns → skip.
    const est_remaining_ns = ns_100k * 10;
    if (est_remaining_ns > 60_000_000_000) {
        result.rate_1m = null;
        result.nodes_1m = g_store_a.node_count;
        result.edges_1m = g_store_a.edge_count;
        return result;
    }

    timer.reset();
    while (i < 1_000_000) : (i += 1) {
        const now_ms: u64 = base_ms + i;
        const pid = std.fmt.bufPrint(&primary_id_buf, "cell_{d:0>8}", .{i % VOCAB_SIZE}) catch unreachable;
        const pidx = g_store_a.upsertNode(pid, type_path, now_ms) catch continue;
        var r: u32 = 0;
        while (r < n_related) : (r += 1) {
            const rid = std.fmt.bufPrint(&related_id_bufs[r], "rel_{d:0>8}", .{(i * 7 + r * 13) % VOCAB_SIZE}) catch unreachable;
            const ridx = g_store_a.upsertNode(rid, type_path, now_ms) catch break;
            related_idxs[r] = ridx;
        }
        interact(&g_store_a, &g_affected, pidx, related_idxs[0..@min(r, n_related)], strength, now_ms, &tick);
    }
    const ns_1m = timer.read();
    result.rate_1m = if (ns_1m == 0) 0 else (900_000 * 1_000_000_000) / ns_1m;
    result.nodes_1m = g_store_a.node_count;
    result.edges_1m = g_store_a.edge_count;

    return result;
}

// ── Snapshot benchmarks ────────────────────────────────────────────────────

const SnapStats = struct {
    mean_us: u64,
    stddev_us: u64,
};

fn benchSerialize(store: *const Store, iters: u32) SnapStats {
    const count = @min(iters, 200);
    var samples: [200]u64 = undefined;

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        var timer = std.time.Timer.start() catch @panic("timer");
        snapshotStore(store, &g_snap_buf_b);
        const ns = timer.read();
        samples[i] = (ns + 500) / 1000; // ns → µs
    }
    return computeStats(samples[0..count]);
}

fn benchRestore(buf: []const u8, iters: u32) SnapStats {
    const count = @min(iters, 200);
    var samples: [200]u64 = undefined;

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        var timer = std.time.Timer.start() catch @panic("timer");
        _ = restoreStore(&g_store_c, buf);
        const ns = timer.read();
        samples[i] = (ns + 500) / 1000;
    }
    return computeStats(samples[0..count]);
}

fn computeStats(samples: []const u64) SnapStats {
    var sum: u64 = 0;
    for (samples) |s| sum += s;
    const mean = sum / samples.len;

    var var_sum: u64 = 0;
    for (samples) |s| {
        const diff = if (s > mean) s - mean else mean - s;
        var_sum += diff * diff;
    }
    return .{
        .mean_us = mean,
        .stddev_us = isqrt(var_sum / samples.len),
    };
}

fn isqrt(n: u64) u64 {
    if (n == 0) return 0;
    var x: u64 = n;
    var y: u64 = (x + 1) / 2;
    while (y < x) {
        x = y;
        y = (x + n / x) / 2;
    }
    return x;
}

// ── Determinism helpers ────────────────────────────────────────────────────

/// Run 1K interactions on `store`, snapshot into `buf`.
fn buildDeterministicSnapshot(store: *Store, buf: []u8) void {
    store.init(config.DEFAULT);
    g_affected.init();
    var tick: u64 = 0;
    const type_path = "bench/cell";
    var primary_id_buf: [32]u8 = undefined;
    var related_id_bufs: [3][32]u8 = undefined;
    var related_idxs: [3]NodeIdx = undefined;
    const strength: f64 = 0.7;

    var i: u32 = 0;
    while (i < 1_000) : (i += 1) {
        const now_ms: u64 = 500_000 + i;
        const primary_id = std.fmt.bufPrint(&primary_id_buf, "det_{d:0>8}", .{i % 200}) catch unreachable;
        const primary_idx = store.upsertNode(primary_id, type_path, now_ms) catch continue;
        var r: u32 = 0;
        while (r < 3) : (r += 1) {
            const rel_id = std.fmt.bufPrint(&related_id_bufs[r], "drel_{d:0>7}", .{(i * 3 + r) % 200}) catch unreachable;
            const rel_idx = store.upsertNode(rel_id, type_path, now_ms) catch break;
            related_idxs[r] = rel_idx;
        }
        interact(store, &g_affected, primary_idx, related_idxs[0..3], strength, now_ms, &tick);
    }
    snapshotStore(store, buf);
}

// ── Formatting helpers ─────────────────────────────────────────────────────

/// 8-char wide calls/sec field.
fn fmtRate(buf: []u8, v: u64) []const u8 {
    if (v == 0) return std.fmt.bufPrint(buf, "       -", .{}) catch "       -";
    if (v >= 1_000_000) {
        return std.fmt.bufPrint(buf, "{d:>5.2}M/s", .{@as(f64, @floatFromInt(v)) / 1_000_000.0}) catch "err";
    } else if (v >= 1_000) {
        return std.fmt.bufPrint(buf, "{d:>5.1}K/s", .{@as(f64, @floatFromInt(v)) / 1_000.0}) catch "err";
    } else {
        return std.fmt.bufPrint(buf, " {d:>6}/s", .{v}) catch "err";
    }
}

/// 8-char wide count field.
fn fmtCount(buf: []u8, v: u32) []const u8 {
    if (v >= 1_000_000) {
        return std.fmt.bufPrint(buf, "{d:>5.2}M  ", .{@as(f64, @floatFromInt(v)) / 1_000_000.0}) catch "err";
    } else if (v >= 1_000) {
        return std.fmt.bufPrint(buf, "{d:>5.1}K  ", .{@as(f64, @floatFromInt(v)) / 1_000.0}) catch "err";
    } else {
        return std.fmt.bufPrint(buf, "  {d:>5}  ", .{v}) catch "err";
    }
}

fn fmtSkip(buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, " (skip) ", .{}) catch "(skip)  ";
}

fn printRateCell(v: ?u64, last: bool) void {
    var vbuf: [24]u8 = undefined;
    const sep = if (last) " │\n" else " │";
    if (v) |val| {
        const s = fmtRate(&vbuf, val);
        print(" {s}{s}", .{ s, sep });
    } else {
        const s = fmtSkip(&vbuf);
        print(" {s}{s}", .{ s, sep });
    }
}

fn printCountCell(v: u32, last: bool) void {
    var vbuf: [16]u8 = undefined;
    const sep = if (last) " │\n" else " │";
    const s = fmtCount(&vbuf, v);
    print(" {s}{s}", .{ s, sep });
}

// ── Main ───────────────────────────────────────────────────────────────────

pub fn main() void {
    print("\n=== Pask Kernel Benchmark Suite ===\n", .{});
    print("Zig 0.15 | pure Zig, no external dependencies\n\n", .{});
    print("Target (M3-T-Pask torture test):\n", .{});
    print("  Interactions: 1,000,000 pask_interact_run calls\n", .{});
    print("  Determinism:  replay must be byte-identical\n", .{});
    print("  Note: throughput rows use propagation_depth=0 (no graph-walk),\n", .{});
    print("        stability_check_every=0, prune_every=0, VOCAB_SIZE=1000.\n", .{});
    print("        Measures the upsert+edge+node-state hot path. See README.\n\n", .{});

    const sep_top  = "┌──────────────────────────────────────────────┬──────────┬──────────┬──────────┬────────────┐";
    const sep_head = "├──────────────────────────────────────────────┼──────────┼──────────┼──────────┼────────────┤";
    const sep_snap = "├──────────────────────────────────────────────┼──────────┴──────────┴──────────┴────────────┤";
    const sep_bot  = "└──────────────────────────────────────────────┴──────────────────────────────────────────────┘";

    print("{s}\n", .{sep_top});
    print("│ {s:<44} │ {s:>8} │ {s:>8} │ {s:>8} │ {s:>10} │\n",
        .{ "Benchmark", "1K", "10K", "100K", "1M" });
    print("{s}\n", .{sep_head});

    // ── Throughput rows ───────────────────────────────────────────────────
    //
    // We run 3 separate full benchmarks: 0 related, 5 related, 10 related.
    // Each bench drives the store from 0 → 1M (or stops early) in a single
    // pass, capturing milestone rates and node/edge counts at each checkpoint.
    // The "generic throughput" row reuses the 5-related results.

    progress("  [running 0-related benchmark...]");
    const b0 = runBench(0);

    progress("  [running 5-related benchmark...]");
    const b5 = runBench(5);

    progress("  [running 10-related benchmark...]");
    const b10 = runBench(10);

    // Row: interact() throughput (generic = 5 related)
    print("│ {s:<44} │", .{"interact() throughput (calls/sec)"});
    printRateCell(b5.rate_1k, false);
    printRateCell(b5.rate_10k, false);
    printRateCell(b5.rate_100k, false);
    printRateCell(b5.rate_1m, true);

    // Row: 0 related
    print("│ {s:<44} │", .{"interact() with 0 related cells (calls/sec)"});
    printRateCell(b0.rate_1k, false);
    printRateCell(b0.rate_10k, false);
    printRateCell(b0.rate_100k, false);
    printRateCell(b0.rate_1m, true);

    // Row: 5 related
    print("│ {s:<44} │", .{"interact() with 5 related cells (calls/sec)"});
    printRateCell(b5.rate_1k, false);
    printRateCell(b5.rate_10k, false);
    printRateCell(b5.rate_100k, false);
    printRateCell(b5.rate_1m, true);

    // Row: 10 related (label is exactly 44 chars)
    print("│ {s:<44} │", .{"interact() with 10 related cells (calls/sec)"});
    printRateCell(b10.rate_1k, false);
    printRateCell(b10.rate_10k, false);
    printRateCell(b10.rate_100k, false);
    printRateCell(b10.rate_1m, true);

    // Graph size rows (use 5-related run)
    print("│ {s:<44} │", .{"Graph size after N interactions: nodes"});
    printCountCell(b5.nodes_1k, false);
    printCountCell(b5.nodes_10k, false);
    printCountCell(b5.nodes_100k, false);
    printCountCell(b5.nodes_1m, true);

    print("│ {s:<44} │", .{"Graph size after N interactions: edges"});
    printCountCell(b5.edges_1k, false);
    printCountCell(b5.edges_10k, false);
    printCountCell(b5.edges_100k, false);
    printCountCell(b5.edges_1m, true);

    // ── Snapshot benchmarks ────────────────────────────────────────────────
    print("{s}\n", .{sep_snap});

    // Build a small warm store for snapshot timing (1K interactions, full DEFAULT config).
    // Reuse g_store_a (runBench already finished with it).
    {
        var tick: u64 = 0;
        var pb: [32]u8 = undefined;
        var rb: [4][32]u8 = undefined;
        var ri: [4]NodeIdx = undefined;
        g_store_a.init(config.DEFAULT); // full config for snapshot bench
        g_affected.init();
        var ii: u32 = 0;
        while (ii < 1_000) : (ii += 1) {
            const nms: u64 = 1_000_000 + ii;
            const pid = std.fmt.bufPrint(&pb, "cell_{d:0>8}", .{ii % config.MAX_NODES}) catch unreachable;
            const pidx = g_store_a.upsertNode(pid, "bench/cell", nms) catch continue;
            var r: u32 = 0;
            while (r < 4) : (r += 1) {
                const rid = std.fmt.bufPrint(&rb[r], "rel_{d:0>8}", .{(ii * 4 + r) % config.MAX_NODES}) catch unreachable;
                const ridx = g_store_a.upsertNode(rid, "bench/cell", nms) catch break;
                ri[r] = ridx;
            }
            interact(&g_store_a, &g_affected, pidx, ri[0..4], 0.5, nms, &tick);
        }
    }
    snapshotStore(&g_store_a, &g_snap_buf_a);

    const ser = benchSerialize(&g_store_a, 100);
    print("│ {s:<44} │ {d:>4} ± {d:<4} µs (mean ± stddev, 100 reps)          │\n",
        .{ "Snapshot serialize (µs)", ser.mean_us, ser.stddev_us });

    const res = benchRestore(&g_snap_buf_a, 100);
    print("│ {s:<44} │ {d:>4} ± {d:<4} µs (mean ± stddev, 100 reps)          │\n",
        .{ "Snapshot restore  (µs)", res.mean_us, res.stddev_us });

    // ── Round-trip identity ────────────────────────────────────────────────
    var all_pass = true;
    {
        g_store_c.init(config.DEFAULT);
        const ok = restoreStore(&g_store_c, &g_snap_buf_a);
        snapshotStore(&g_store_c, &g_snap_buf_b);
        const identical = ok and std.mem.eql(u8, &g_snap_buf_a, &g_snap_buf_b);
        if (!identical) all_pass = false;
        const tag = if (identical) "PASS" else "FAIL";
        print("│ {s:<44} │ {s:<52} │\n",
            .{ "Round-trip byte-identical (pass/fail)", tag });
    }

    // ── Replay determinism ─────────────────────────────────────────────────
    // Zero the stores first so trailing padding in cell_id/type_path buffers
    // is the same in both (g_store_a was previously used; its BSS data differs
    // from g_store_b's zero-initialized BSS).
    {
        @memset(std.mem.asBytes(&g_store_a), 0);
        @memset(std.mem.asBytes(&g_store_b), 0);
        buildDeterministicSnapshot(&g_store_a, &g_snap_buf_b);
        buildDeterministicSnapshot(&g_store_b, &g_snap_buf_c);
        const identical = std.mem.eql(u8, &g_snap_buf_b, &g_snap_buf_c);
        if (!identical) all_pass = false;
        const tag = if (identical) "PASS" else "FAIL";
        print("│ {s:<44} │ {s:<52} │\n",
            .{ "Replay 1K events determinism (pass/fail)", tag });
    }

    print("{s}\n", .{sep_bot});

    // ── Estimated time to 1M ──────────────────────────────────────────────
    // From the 5-related 100K run (90K calls, elapsed_100k_ns).
    if (b5.elapsed_100k_ns > 0 and b5.rate_100k > 0) {
        const est_sec = 1_000_000.0 / @as(f64, @floatFromInt(b5.rate_100k));
        print("\nEstimated time to 1M interactions: {d:.2}s  (from 100K rate: {d} calls/sec)\n",
            .{ est_sec, b5.rate_100k });
    }
    if (b5.rate_1m == null) {
        print("Note: 1M column skipped for 5-related (estimated > 60s per run)\n", .{});
    }

    print("\n", .{});

    if (!all_pass) {
        print("ERROR: one or more correctness checks FAILED\n", .{});
        std.process.exit(1);
    }
}

```
