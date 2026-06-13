---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/reorg_sink.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.446658+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/reorg_sink.zig

```zig
// D-LC5 — cartridge → brain reorg-recovery callback interface.
//
// When `headers_sync.attemptReorgRecovery` rolls our chain back, the
// brain's per-cell anchor-status projection needs to be told: every
// `.pending` entry whose attestation was anchored at a height >= the
// rollback floor is no longer valid and must be cleared. The substrate
// (`LmdbCellStore.sweepReorgedFromHeight`) ships in brain; this file
// is the cartridge-local seam that lets the cartridge invoke it
// WITHOUT importing brain.
//
// Pattern: vtable-style callback interface (mirrors std.mem.Allocator,
// std.io.Reader, header_store_mod.HeaderStore). The cartridge defines
// the shape; brain (in `runtime/semantos-brain/src/reorg_sink_cell_store.zig`)
// constructs the concrete impl backed by an `LmdbCellStore` and hands
// it to the cartridge at startup.
//
// Why a callback interface instead of `@import("lmdb_cell_store")` from
// the cartridge:
//   - The cartridge ships as a wasm32-freestanding artifact for the
//     marketplace; it must NOT compile-time depend on brain-internal
//     types like `lmdb.Env` or `LmdbCellStore`.
//   - Brain knows what cellstore it wants the cartridge to sweep
//     against (could be the operator-scoped LMDB env, a per-hat env,
//     or in tests a stub). The interface lets brain pick.
//   - When `reorg_sink == null` (e.g. early-deploy brains without an
//     anchor-status projection yet, or unit tests), the reorg-recovery
//     path is a clean no-op and the chain rollback still completes.
//
// Semantics (mirrors brain's `LmdbCellStore.sweepReorgedFromHeight`):
//   - `rollback_from_height` is the LOWEST height that's no longer
//     valid — i.e. the first reorged-away block. Every attestation
//     anchored at height >= rollback_from_height is candidate for
//     pending rollback.
//   - `.confirmed` projections are NOT cleared. Past finality requires
//     explicit invalidation, not silent reorg rollback.
//   - Idempotent: a second call with the same rollback floor returns
//     (0, kept).
//   - Errors do NOT fail the reorg recovery. The caller logs and
//     continues; the chain rollback must complete even if the sweep
//     fails (the next attestation observer pass will eventually
//     re-converge once the chain re-syncs).

const std = @import("std");

/// Result of a reorg-triggered sweep. Mirrors brain's `SweepResult`
/// shape (kept identical so the brain-side impl can pass it through
/// without translation).
pub const SweepReport = struct {
    /// Number of `.pending` anchor projections cleared because they
    /// were bound to a reorged-away attestation height.
    swept: u32,
    /// Number of cells left untouched. These are either `.confirmed`
    /// (past finality — preserved) or had no anchor-status entry by
    /// the time the sweep ran.
    kept: u32,
};

/// Sweep failure modes the cartridge can react to. Today only
/// `persistence_failed` — the impl maps brain's `StoreError` onto this.
/// The cartridge does not get a finer-grained view (e.g.
/// `out_of_memory`, `invalid_cell`) because the recovery action is the
/// same: log and proceed.
pub const SweepError = error{persistence_failed};

/// Callback interface — pass `?*const ReorgSink` to
/// `headers_sync.attemptReorgRecovery`. The vtable shape parallels
/// `header_store_mod.HeaderStore` so adding new methods later (e.g.
/// `onChainExtended` for forward-direction confirmation sweeps) is
/// additive.
pub const ReorgSink = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Sweep every `.pending` anchor projection at heights >=
        /// `rollback_from_height`. The cartridge passes the floor it
        /// computed from the header-store rollback; brain's impl
        /// scans `cells_by_anchor_height` from that floor upward.
        sweep_reorged_from_height: *const fn (
            ctx: *anyopaque,
            rollback_from_height: u64,
        ) SweepError!SweepReport,
    };

    pub fn sweepReorgedFromHeight(
        self: *const ReorgSink,
        rollback_from_height: u64,
    ) SweepError!SweepReport {
        return self.vtable.sweep_reorged_from_height(
            self.ctx,
            rollback_from_height,
        );
    }
};

// ─────────────────────────────────────────────────────────────────────
// Tests — stub sink for cartridge-side conformance. Brain-side wraps
// LmdbCellStore in `runtime/semantos-brain/src/reorg_sink_cell_store.zig`.
// ─────────────────────────────────────────────────────────────────────

/// Test-only stub that records every sweep call. Lifted here so
/// cartridge-side reorg-recovery tests can drive `attemptReorgRecovery`
/// against a known-shape sink without dragging in LMDB.
pub const StubReorgSink = struct {
    last_height: ?u64 = null,
    call_count: u32 = 0,
    next_result: SweepReport = .{ .swept = 0, .kept = 0 },
    /// When non-null, the next sweep returns this error instead of
    /// `next_result`. The error path matters because the daemon must
    /// keep going after a sweep failure.
    next_error: ?SweepError = null,

    pub fn sink(self: *StubReorgSink) ReorgSink {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &.{
                .sweep_reorged_from_height = vSweepReorgedFromHeight,
            },
        };
    }

    fn vSweepReorgedFromHeight(
        ctx: *anyopaque,
        rollback_from_height: u64,
    ) SweepError!SweepReport {
        const self: *StubReorgSink = @ptrCast(@alignCast(ctx));
        self.last_height = rollback_from_height;
        self.call_count += 1;
        if (self.next_error) |e| return e;
        return self.next_result;
    }
};

test "ReorgSink: stub records the rollback floor" {
    var stub: StubReorgSink = .{};
    stub.next_result = .{ .swept = 3, .kept = 7 };
    const sink_ref = stub.sink();

    const report = try sink_ref.sweepReorgedFromHeight(800_000);

    try std.testing.expectEqual(@as(u32, 1), stub.call_count);
    try std.testing.expectEqual(@as(?u64, 800_000), stub.last_height);
    try std.testing.expectEqual(@as(u32, 3), report.swept);
    try std.testing.expectEqual(@as(u32, 7), report.kept);
}

test "ReorgSink: stub surfaces errors" {
    var stub: StubReorgSink = .{};
    stub.next_error = error.persistence_failed;
    const sink_ref = stub.sink();

    try std.testing.expectError(error.persistence_failed, sink_ref.sweepReorgedFromHeight(42));
    try std.testing.expectEqual(@as(u32, 1), stub.call_count);
    try std.testing.expectEqual(@as(?u64, 42), stub.last_height);
}

```
