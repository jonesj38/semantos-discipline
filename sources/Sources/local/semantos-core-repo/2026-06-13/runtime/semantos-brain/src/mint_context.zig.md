---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/mint_context.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.253702+00:00
---

# runtime/semantos-brain/src/mint_context.zig

```zig
//! Mint-context-builder seam — extracted from cells_mint_handler.zig
//! (C4 brain-carve PR-E2) into a LIGHT leaf module so
//! cartridge_seam.CartridgeDeps can expose MintContextRegistry to
//! cartridges WITHOUT importing the ~1500-LOC mint Handler (substrate
//! one-way dep gate, #847). cells_mint_handler re-exports these symbols
//! as aliases for backward-compat; the SPV + MNCA context modules +
//! serve.zig reference them unchanged.
//!
//! Leaf deps: std + the cell-engine CELL_SIZE constant only.

const std = @import("std");
const cell_engine_constants = @import("constants");
const CELL_SIZE: u32 = cell_engine_constants.CELL_SIZE;

/// PR-3d — per-script execution context builder seam.
///
/// The dispatcher calls `build_fn` BEFORE script execution with the
/// input cell + a per-script allocator. The function may inspect the
/// cell's typeHash + payload, decode any wire format it knows, gather
/// brain-side state (trusted roots, allocator references, etc.), and
/// return an opaque `Context` pointer the cell-engine sees via
/// `host.setExecutionContext`.
///
/// After script execution — success OR rejection path — the dispatcher
/// calls `destroy_fn` with the same pointer so the builder can free
/// the Context's dynamic allocations + the Context struct itself.
///
/// Returning `null` from `build_fn` means "no Context for this input
/// cell" — the script runs without setExecutionContext being called.
/// This is the normal path for handler scripts that don't invoke
/// Context-style hostcalls (pure stack computation handlers).
///
/// The seam is OPTIONAL at the dispatcher level: `Handler.context_
/// builder == null` means "always run without Context" — preserves
/// current behavior for callers that haven't wired a builder.
///
/// Reference: LOCKSCRIPT-CLEAVAGE.md §3.5 + §4c (the "wallet receives
/// digest + derivation context only — never the handler script"
/// invariant is enforced HERE — the brain decides what Context shape
/// goes into setExecutionContext, not the script).
pub const ScriptContextBuilder = struct {
    /// Caller-owned state pointer threaded into build_fn / destroy_fn.
    /// Holds the brain-side resources a builder needs (e.g. the
    /// HeaderStore for SPV-context resolution).
    state: *anyopaque,

    /// Called before script execution. Returns an opaque Context
    /// pointer the cell-engine sees via setExecutionContext, or null
    /// to skip Context construction.
    build_fn: *const fn (
        state: *anyopaque,
        input_cell: *const [CELL_SIZE]u8,
        allocator: std.mem.Allocator,
    ) ?*anyopaque,

    /// Called after script execution with the Context pointer
    /// `build_fn` returned. Frees the Context's dynamic allocations +
    /// the Context struct itself.
    destroy_fn: *const fn (
        state: *anyopaque,
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
    ) void,

    /// PR-8b-v — optional callback that returns ADDITIONAL cells the
    /// dispatcher should push onto the PDA main stack BEFORE script
    /// execution. The cells are pushed at slots 1, 2, ... (slot 0
    /// stays as the input cell from step 2 of the dispatch path).
    ///
    /// The dispatcher's existing emit walker picks them up after the
    /// script runs — as long as the handler doesn't OP_DROP them and
    /// their typeHash is in the manifest's emits[] allowlist, they get
    /// persisted via cell_store.put alongside any script-emitted cells.
    ///
    /// Use case: an MNCA-transition handler that emits a successor
    /// LINEAR `mnca.anchor` cell on Valid verdict — the brain pre-
    /// constructs the cell (it has access to predecessor lineage +
    /// rule replay) and pushes it via this callback. The handler
    /// script only emits the transition.result; the successor anchor
    /// flows through the brain-side push + dispatcher walker.
    ///
    /// Returning null OR an empty slice = no extra cells. The
    /// returned slice is borrowed for the duration of the dispatch;
    /// `extra_cells_destroy_fn` (set when `extra_cells_fn` is set)
    /// is called after script execution to free it.
    extra_cells_fn: ?*const fn (
        state: *anyopaque,
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
    ) ?[]const [CELL_SIZE]u8 = null,

    /// PR-8b-v — companion to `extra_cells_fn`. Called after script
    /// execution to free the slice returned by `extra_cells_fn`.
    /// Must be non-null whenever `extra_cells_fn` is non-null.
    extra_cells_destroy_fn: ?*const fn (
        state: *anyopaque,
        extra: []const [CELL_SIZE]u8,
        allocator: std.mem.Allocator,
    ) void = null,
};

/// PR-8b-iv — composite ScriptContextBuilder that tries each child in
/// order; the first non-null `build_fn` return wins. Used to compose
/// multiple typeHash-gated builders (e.g. the PR-3d SPV builder for
/// `bsv.spv.verify.intent` + the PR-8b-iv MNCA builder for
/// `mnca.anchor.transition.intent`) into one builder the Handler holds
/// in its single `context_builder` slot.
///
/// State machine (relies on the brain's single-threaded reactor —
/// `semantos_brain_single_threaded_reactor` memory):
///
///   1. `build` iterates `children` in order, calls each one's
///      `build_fn`. The first child to return a non-null pointer wins.
///   2. `last_built_child` records the winner's index — used by
///      `destroy` to route teardown back to the right child.
///   3. `destroy` reads `last_built_child` + calls that child's
///      `destroy_fn` with the same pointer the child returned.
///   4. `last_built_child` is reset to `null` after destroy so a
///      subsequent invocation without a corresponding build can be
///      defended against (returns early — defence-in-depth, the
///      dispatcher's defer block won't trigger destroy without a
///      preceding non-null build anyway).
///
/// Reference: LOCKSCRIPT-CLEAVAGE.md §3.5 (the Context construction
/// seam is a dispatcher concern; this composite lets the dispatcher
/// stay agnostic to which cell-type-specific builder fires).
pub const CompositeContextBuilder = struct {
    children: []const ScriptContextBuilder,
    last_built_child: ?usize = null,

    pub fn toBuilder(self: *CompositeContextBuilder) ScriptContextBuilder {
        return .{
            .state = @ptrCast(self),
            .build_fn = compositeBuild,
            .destroy_fn = compositeDestroy,
            // PR-8b-v — extra_cells_fn + extra_cells_destroy_fn route
            // through to the winning child via last_built_child.
            .extra_cells_fn = compositeExtraCells,
            .extra_cells_destroy_fn = compositeExtraCellsDestroy,
        };
    }
};

/// Maximum mint-context builders registrable per brain instance. Substrate
/// wires a couple (MNCA, SPV); cartridges append their own. 8 is a generous
/// ceiling — exceeding it is a deployment misconfiguration, not a runtime path.
pub const MAX_MINT_CONTEXT_BUILDERS: usize = 8;

/// C4 brain-carve — a GROWABLE composite the substrate and cartridges both
/// append mint-context builders to, replacing the fixed `children` slice that
/// serve.zig used to hand-build from a hardcoded [MNCA, SPV] array. The mint
/// Handler holds ONE context_builder slot (`setContextBuilder`); this registry
/// fans that single slot out across N typeHash-gated builders so a cartridge
/// (e.g. mnca) can contribute its builder at boot via the cartridge seam
/// without serve.zig (or the substrate mint Handler) knowing the cartridge by
/// name.
///
/// Stable-address contract: the registry MUST outlive the Handler (the
/// Handler's context_builder captures `&self.composite`, whose `children`
/// points into `self.buf`). Construct it once at boot in a scope that lives
/// for the brain's run (a cmdServe-scope `var`, like the composite it
/// replaces). `add` after `toBuilder` is safe — the Handler reads the slice
/// live at dispatch (request) time, which is always after boot registration.
pub const MintContextRegistry = struct {
    buf: [MAX_MINT_CONTEXT_BUILDERS]ScriptContextBuilder = undefined,
    composite: CompositeContextBuilder = .{ .children = &.{} },

    /// Append a builder. Silently ignored past the ceiling (logged) — a
    /// dropped builder degrades that cell-type's mints to the no-context
    /// sentinel rather than crashing the daemon.
    pub fn add(self: *MintContextRegistry, builder: ScriptContextBuilder) void {
        const n = self.composite.children.len;
        if (n >= MAX_MINT_CONTEXT_BUILDERS) {
            std.log.warn("MintContextRegistry: builder ceiling {d} reached — dropping builder", .{MAX_MINT_CONTEXT_BUILDERS});
            return;
        }
        self.buf[n] = builder;
        self.composite.children = self.buf[0 .. n + 1];
    }

    pub fn count(self: *const MintContextRegistry) usize {
        return self.composite.children.len;
    }

    /// The single ScriptContextBuilder to hand the mint Handler via
    /// `setContextBuilder`. Delegates to the inner composite (try-each-child,
    /// first non-null wins).
    pub fn toBuilder(self: *MintContextRegistry) ScriptContextBuilder {
        return self.composite.toBuilder();
    }
};

fn compositeBuild(
    state_any: *anyopaque,
    input_cell: *const [CELL_SIZE]u8,
    allocator: std.mem.Allocator,
) ?*anyopaque {
    const composite: *CompositeContextBuilder = @ptrCast(@alignCast(state_any));
    for (composite.children, 0..) |child, i| {
        if (child.build_fn(child.state, input_cell, allocator)) |built| {
            composite.last_built_child = i;
            return built;
        }
    }
    composite.last_built_child = null;
    return null;
}

fn compositeDestroy(
    state_any: *anyopaque,
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
) void {
    const composite: *CompositeContextBuilder = @ptrCast(@alignCast(state_any));
    const idx = composite.last_built_child orelse return; // defence-in-depth
    // Reset last_built_child AFTER reading idx but BEFORE invoking the
    // child — destroy is the LAST defer to fire in the dispatcher's
    // LIFO order (extra_cells_destroy_fn → setExecutionContext(null)
    // → destroy_fn), so resetting here leaves the composite in a
    // clean state for the next dispatch.
    composite.last_built_child = null;
    const child = composite.children[idx];
    child.destroy_fn(child.state, ctx, allocator);
}

/// PR-8b-v — route extra_cells_fn to the winning child.
fn compositeExtraCells(
    state_any: *anyopaque,
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
) ?[]const [CELL_SIZE]u8 {
    const composite: *CompositeContextBuilder = @ptrCast(@alignCast(state_any));
    const idx = composite.last_built_child orelse return null;
    const child = composite.children[idx];
    const fn_opt = child.extra_cells_fn orelse return null;
    return fn_opt(child.state, ctx, allocator);
}

/// PR-8b-v — route extra_cells_destroy_fn to the winning child. Runs
/// FIRST in the dispatcher's defer LIFO (before destroy_fn), so
/// last_built_child must NOT be reset here — destroy_fn still needs
/// it. The reset happens in compositeDestroy.
fn compositeExtraCellsDestroy(
    state_any: *anyopaque,
    extra: []const [CELL_SIZE]u8,
    allocator: std.mem.Allocator,
) void {
    const composite: *CompositeContextBuilder = @ptrCast(@alignCast(state_any));
    const idx = composite.last_built_child orelse return;
    const child = composite.children[idx];
    if (child.extra_cells_destroy_fn) |edf|
        edf(child.state, extra, allocator);
}

```
