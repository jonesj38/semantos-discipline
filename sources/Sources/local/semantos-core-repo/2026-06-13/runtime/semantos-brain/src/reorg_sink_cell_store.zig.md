---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/reorg_sink_cell_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.241121+00:00
---

# runtime/semantos-brain/src/reorg_sink_cell_store.zig

```zig
// D-LC5 — brain-side concrete `ReorgSink` implementation backed by
// `LmdbCellStore`. Hands the cartridge a vtable that maps directly to
// `LmdbCellStore.sweepReorgedFromHeight`, with `StoreError` translated
// down to the cartridge-side `SweepError`.
//
// Why this lives in brain, not the cartridge:
//   - `LmdbCellStore` is brain-internal (uses `lmdb.Env`,
//     `lmdb.Txn`); the cartridge ships as wasm32-freestanding and
//     can't see those types.
//   - The cartridge defines the `ReorgSink` shape it expects (see
//     `cartridges/bsv-anchor-bundle/brain/zig/src/reorg_sink.zig`);
//     this file implements that shape on top of brain's storage.
//
// Lifetime: the caller (cmdHeadersServe) owns the backing
// `LmdbCellStore` for the duration of the daemon. Constructing a
// `ReorgSinkCellStore` is zero-cost — just an aliased pointer + a
// pointer to the vtable. The wrapper doesn't open or close any LMDB
// resources of its own.
//
// Thread-safety: `LmdbCellStore.sweepReorgedFromHeight` opens its own
// LMDB transactions, so the sweep call is safe from any thread. The
// daemon loop in cli/headers.zig invokes the sink under the header-
// store mutex (so the chain rollback + anchor sweep are atomic from
// the consumer's perspective), but that's a layering choice, not a
// requirement of this wrapper.
//
// Tests: `runtime/semantos-brain/tests/reorg_sink_cell_store_conformance.zig`.

const std = @import("std");

const reorg_sink_mod = @import("reorg_sink");
const lmdb_cell_store_mod = @import("lmdb_cell_store");

pub const ReorgSink = reorg_sink_mod.ReorgSink;
pub const SweepReport = reorg_sink_mod.SweepReport;
pub const SweepError = reorg_sink_mod.SweepError;

/// Wraps a borrowed `*LmdbCellStore` and exposes the cartridge-side
/// `ReorgSink` vtable. Construct one per daemon process; pass
/// `wrapper.sink()` to the cartridge's reorg-recovery hook.
pub const ReorgSinkCellStore = struct {
    store: *lmdb_cell_store_mod.LmdbCellStore,

    pub fn init(store: *lmdb_cell_store_mod.LmdbCellStore) ReorgSinkCellStore {
        return .{ .store = store };
    }

    /// Materialise a `ReorgSink` view that the cartridge can call
    /// through. The returned struct holds a pointer to `self`, so
    /// `self` MUST outlive every use of the returned sink.
    pub fn sink(self: *ReorgSinkCellStore) ReorgSink {
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
        const self: *ReorgSinkCellStore = @ptrCast(@alignCast(ctx));
        const result = self.store.sweepReorgedFromHeight(rollback_from_height) catch |e| switch (e) {
            // Map every `StoreError` variant onto the cartridge-side
            // `persistence_failed`. The cartridge doesn't need finer
            // granularity — recovery action (log + continue) is the
            // same regardless of which inner cause fired.
            error.persistence_failed,
            error.out_of_memory,
            error.invalid_cell,
            => return error.persistence_failed,
        };
        return SweepReport{ .swept = result.swept, .kept = result.kept };
    }
};

```
