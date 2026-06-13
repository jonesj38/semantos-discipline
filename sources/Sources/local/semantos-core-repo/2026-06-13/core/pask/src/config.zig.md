---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/src/config.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.931998+00:00
---

# core/pask/src/config.zig

```zig
// Pask tuning parameters. Values lifted verbatim from
// friend-semantos/packages/paskian/src/grammar.ts so the Zig port matches
// TS bit-for-bit unless a caller overrides via pask_set_config.
//
// The stability window is in milliseconds — callers must pass a clock
// (epoch ms or any monotonic ms source) on every interact / step / prune
// call. The kernel does not call into a host clock; determinism wins.

pub const Config = extern struct {
    /// Constraint trend below which a node is pruned. -0.3 default.
    prune_threshold: f64,
    /// |ΔH| threshold below which a node is considered stable. 0.01 default.
    stability_epsilon: f64,
    /// Minimum interaction count before a node can be declared stable. 5 default.
    min_interactions: u32,
    /// Number of propagation iterations per interact() call. 3 default.
    propagation_depth: u32,
    /// Learning rate scaling all delta applications. 0.1 default.
    learning_rate: f64,
    /// Time window (caller-supplied units, conventionally ms) for avgDelta. 60_000 default.
    stability_window_ms: u64,
    /// Run stability check every N interactions. 0 disables. 1 default.
    stability_check_every: u32,
    /// Run prune sweep every N interactions. 0 disables. 1 default.
    prune_every: u32,
};

pub const DEFAULT: Config = .{
    .prune_threshold = -0.3,
    .stability_epsilon = 0.01,
    .min_interactions = 5,
    .propagation_depth = 3,
    .learning_rate = 0.1,
    .stability_window_ms = 60_000,
    .stability_check_every = 1,
    .prune_every = 1,
};

// ── Capacity limits (compile-time) ─────────────────────────────────────
//
// These are the static bounds for the embedded build. The TS impl uses
// SQLite which is unbounded; the WASM impl pre-allocates a fixed pool so
// it runs in a known-size linear-memory budget. For the chess rig at
// ~50k games × 12 plies the working set sits well under these numbers.
//
// Sized so the static state takes ~1.5 MB:
//   nodes:    65_536 * 80  bytes ≈ 5.2 MB cap (resized when we ship)
//   edges:    131_072 * 64 bytes ≈ 8.4 MB
//   delta_log: 524_288 * 24 bytes ≈ 12.6 MB
//
// For Damian's slice we stay smaller; production callers that need more
// can rebuild with overrides.

pub const MAX_NODES: u32 = 16_384;
pub const MAX_EDGES: u32 = 32_768;
pub const MAX_CELL_ID_LEN: u32 = 64;
pub const MAX_TYPE_PATH_LEN: u32 = 96;
pub const DELTA_RING_CAP: u32 = 65_536;

// ── Affected-set / region capacities (per interact() call) ─────────────

/// Maximum nodes that one interact() call can touch (direct + propagation).
/// Bounds the worst-case degree × propagation_depth expansion.
pub const MAX_AFFECTED: u32 = 4096;

/// Maximum related-cells in a single interact() call.
pub const MAX_RELATED: u32 = 32;

```
