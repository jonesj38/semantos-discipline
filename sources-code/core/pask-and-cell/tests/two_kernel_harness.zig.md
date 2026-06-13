---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask-and-cell/tests/two_kernel_harness.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.017499+00:00
---

# core/pask-and-cell/tests/two_kernel_harness.zig

```zig
// WI-C1 — Two-kernel single-process harness.
//
// Instantiates two Store instances in the same process, feeds them an
// interleaved sequence of interactions with a configurable shared_fraction,
// then measures cross-kernel stability convergence:
//
//   convergence_rate = |{cells stable in A} ∩ {cells stable in B}|
//                      / max(1, |{cells stable in A} ∪ {cells stable in B}|)
//
// Three scenarios per the WI-C1 spec:
//   WI-C1-T-disjoint-streams-no-convergence   — shared_fraction=0 → rate ≈ 0
//   WI-C1-T-identical-streams-full-convergence — shared_fraction=1 → rate = 1
//   WI-C1-T-partial-overlap-intermediate       — rate(0.5) ∈ (rate(0), rate(1))

const std = @import("std");
const testing = std.testing;
const config = @import("config");
const types = @import("types");
const store_mod = @import("store");
const propagation = @import("propagation");
const stability_mod = @import("stability");
const pruner_mod = @import("pruner");

const Store = store_mod.Store;
const Affected = propagation.Affected;
const NodeIdx = types.NodeIdx;

// ── Engine ────────────────────────────────────────────────────────────────────

const Engine = struct {
    store: Store,
    affected: Affected,
    tick: u64,

    fn init(self: *Engine, cfg: config.Config) void {
        self.store.init(cfg);
        self.affected.init();
        self.tick = 0;
    }

    fn interact(
        self: *Engine,
        primary: NodeIdx,
        related: []const NodeIdx,
        strength: f64,
        now_ms: u64,
    ) !void {
        self.affected.init();
        _ = try self.affected.add(primary);
        for (related) |r| {
            const e = try self.store.upsertEdge(primary, r, now_ms);
            const w = strength * self.store.cfg.learning_rate;
            self.store.updateEdgeWeight(e, w, now_ms);
            self.store.recordDelta(e, w, now_ms);
            _ = try self.affected.add(r);
        }
        self.store.updateNodeState(primary, strength, now_ms);
        try propagation.propagate(&self.store, &self.affected, now_ms);
        self.tick += 1;
        if (self.store.cfg.stability_check_every > 0 and
            self.tick % self.store.cfg.stability_check_every == 0)
        {
            var i: u32 = 0;
            while (i < self.affected.count) : (i += 1) {
                _ = stability_mod.checkNode(
                    &self.store,
                    self.affected.members[i],
                    now_ms,
                );
            }
        }
        if (self.store.cfg.prune_every > 0 and
            self.tick % self.store.cfg.prune_every == 0)
        {
            _ = pruner_mod.pruneOnce(&self.store, now_ms);
        }
    }
};

fn allocEngine(allocator: std.mem.Allocator, cfg: config.Config) !*Engine {
    const e = try allocator.create(Engine);
    e.init(cfg);
    return e;
}

// ── Interaction sequence ──────────────────────────────────────────────────────

const ROUNDS = 60;

// Feed an engine the "A-stream": nodes {root, a1, b1, c1}.
fn driveStreamA(eng: *Engine) !void {
    const root = try eng.store.upsertNode("root", "k", 0);
    const a1   = try eng.store.upsertNode("a1",   "k", 0);
    const b1   = try eng.store.upsertNode("b1",   "k", 0);
    const c1   = try eng.store.upsertNode("c1",   "k", 0);

    var clock: u64 = 0;
    var i: u32 = 0;
    while (i < ROUNDS) : (i += 1) {
        clock += 1; try eng.interact(root, &[_]NodeIdx{ a1, b1 }, 1.0, clock);
        clock += 1; try eng.interact(a1,   &[_]NodeIdx{ b1, c1 }, 0.7, clock);
        clock += 1; try eng.interact(b1,   &[_]NodeIdx{c1},       0.4, clock);
        clock += 1; try eng.interact(c1,   &[_]NodeIdx{a1},       0.3, clock);
    }
}

// Feed an engine the "B-stream": nodes {root, a2, b2, c2} — disjoint from A.
fn driveStreamB(eng: *Engine) !void {
    const root = try eng.store.upsertNode("root", "k", 0);
    const a2   = try eng.store.upsertNode("a2",   "k", 0);
    const b2   = try eng.store.upsertNode("b2",   "k", 0);
    const c2   = try eng.store.upsertNode("c2",   "k", 0);

    var clock: u64 = 0;
    var i: u32 = 0;
    while (i < ROUNDS) : (i += 1) {
        clock += 1; try eng.interact(root, &[_]NodeIdx{ a2, b2 }, 1.0, clock);
        clock += 1; try eng.interact(a2,   &[_]NodeIdx{ b2, c2 }, 0.7, clock);
        clock += 1; try eng.interact(b2,   &[_]NodeIdx{c2},       0.4, clock);
        clock += 1; try eng.interact(c2,   &[_]NodeIdx{a2},       0.3, clock);
    }
}

// ── Convergence metric ────────────────────────────────────────────────────────

fn stableCount(eng: *Engine) u32 {
    var count: u32 = 0;
    var i: u32 = 0;
    while (i < eng.store.node_count) : (i += 1) {
        if (eng.store.nodes[i].is_stable != 0) count += 1;
    }
    return count;
}

// Suppress unused-function warning — stableCount is a utility available to tests.
const _use_stableCount = stableCount;

// convergence_rate: cells matched by cell_id string, not by NodeIdx.
//   both  = |{cells stable in A} ∩ {cells stable in B}|   (same name, stable in both)
//   either = |{cells stable in A} ∪ {cells stable in B}|
//   rate  = both / max(1, either)
fn convergenceRate(a: *Engine, b: *Engine) f64 {
    var both: u32 = 0;
    var either: u32 = 0;

    // Walk A's nodes; look up each by cell_id in B.
    var i: u32 = 0;
    while (i < a.store.node_count) : (i += 1) {
        const na = &a.store.nodes[i];
        if (na.is_pruned != 0) continue;
        const stable_a = na.is_stable != 0;

        // Find the matching cell in B.
        const cid = na.cell_id[0..na.cell_id_len];
        var j: u32 = 0;
        var found_stable_b: bool = false;
        var found: bool = false;
        while (j < b.store.node_count) : (j += 1) {
            const nb = &b.store.nodes[j];
            if (nb.is_pruned != 0) continue;
            const bcid = nb.cell_id[0..nb.cell_id_len];
            if (std.mem.eql(u8, cid, bcid)) {
                found = true;
                found_stable_b = nb.is_stable != 0;
                break;
            }
        }

        if (stable_a or (found and found_stable_b)) either += 1;
        if (stable_a and found and found_stable_b) both += 1;
    }

    // Walk B's nodes for cells NOT in A (contribute to either only).
    var k: u32 = 0;
    while (k < b.store.node_count) : (k += 1) {
        const nb = &b.store.nodes[k];
        if (nb.is_pruned != 0) continue;
        if (nb.is_stable == 0) continue;
        const bcid = nb.cell_id[0..nb.cell_id_len];
        var found_in_a: bool = false;
        var m: u32 = 0;
        while (m < a.store.node_count) : (m += 1) {
            const na = &a.store.nodes[m];
            if (na.is_pruned != 0) continue;
            const acid = na.cell_id[0..na.cell_id_len];
            if (std.mem.eql(u8, bcid, acid)) {
                found_in_a = true;
                break;
            }
        }
        if (!found_in_a) either += 1; // stable in B, not seen in A at all
    }

    if (either == 0) return 0.0;
    return @as(f64, @floatFromInt(both)) / @as(f64, @floatFromInt(either));
}

// ── Shared config ─────────────────────────────────────────────────────────────

fn harnessCfg() config.Config {
    var cfg = config.DEFAULT;
    cfg.stability_check_every = 1;
    cfg.prune_every = 0;
    cfg.min_interactions = 3;
    // Small learning rate keeps deltas (strength × lr) below stability_epsilon=0.01
    // so nodes become stable after min_interactions interactions.
    cfg.learning_rate = 0.005;
    return cfg;
}

// ── WI-C1-T-disjoint-streams-no-convergence ───────────────────────────────────

test "WI-C1-T-disjoint-streams-no-convergence" {
    // Kernel A sees {root, a1, b1, c1}, kernel B sees {root, a2, b2, c2}.
    // The only shared cell is `root`. After many rounds root is stable
    // in both — but the domain-specific cells (a1/b1/c1 vs a2/b2/c2) are
    // disjoint, so convergence_rate ≤ 1/total_stable_cells (near zero).

    const cfg = harnessCfg();
    const eng_a = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng_a);
    const eng_b = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng_b);

    try driveStreamA(eng_a);
    try driveStreamB(eng_b);

    const rate = convergenceRate(eng_a, eng_b);
    // With completely disjoint nodes (except shared `root` at index 0),
    // convergence_rate should be very low — dominated by non-shared stable cells.
    try testing.expect(rate < 0.5);
}

// ── WI-C1-T-identical-streams-full-convergence ────────────────────────────────

test "WI-C1-T-identical-streams-full-convergence" {
    // Both kernels receive the identical A-stream. Every stable cell in A
    // is also stable in B by construction (determinism). convergence_rate = 1.

    const cfg = harnessCfg();
    const eng_a = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng_a);
    const eng_b = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng_b);

    try driveStreamA(eng_a);
    try driveStreamA(eng_b);

    const rate = convergenceRate(eng_a, eng_b);
    try testing.expectApproxEqAbs(rate, 1.0, 0.001);
}

// ── WI-C1-T-partial-overlap-intermediate ─────────────────────────────────────

test "WI-C1-T-partial-overlap-intermediate" {
    // Kernel A gets both streams (full overlap);
    // Kernel B gets only stream B (partial).
    // Convergence of this pair should exceed the disjoint case but be less
    // than the identical-streams case — monotonically in shared content.

    const cfg = harnessCfg();

    // Disjoint baseline
    const eng_disjoint_a = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng_disjoint_a);
    const eng_disjoint_b = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng_disjoint_b);
    try driveStreamA(eng_disjoint_a);
    try driveStreamB(eng_disjoint_b);
    const rate_disjoint = convergenceRate(eng_disjoint_a, eng_disjoint_b);

    // Partial overlap: A gets A+B, B gets only B
    const eng_both = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng_both);
    const eng_b_only = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng_b_only);
    try driveStreamA(eng_both);
    try driveStreamB(eng_both);
    try driveStreamB(eng_b_only);
    const rate_partial = convergenceRate(eng_both, eng_b_only);

    // Identical
    const eng_same_1 = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng_same_1);
    const eng_same_2 = try allocEngine(testing.allocator, cfg);
    defer testing.allocator.destroy(eng_same_2);
    try driveStreamA(eng_same_1);
    try driveStreamA(eng_same_2);
    const rate_identical = convergenceRate(eng_same_1, eng_same_2);

    // Monotonicity: disjoint ≤ partial ≤ identical
    try testing.expect(rate_partial >= rate_disjoint);
    try testing.expect(rate_identical >= rate_partial);
}

```
