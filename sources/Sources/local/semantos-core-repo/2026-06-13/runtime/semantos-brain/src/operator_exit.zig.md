---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/operator_exit.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.238746+00:00
---

# runtime/semantos-brain/src/operator_exit.zig

```zig
// W7.8 — OperatorExit: export grace tarball then delete all operator data.
//
// Exit sequence (ordered; no cross-subsystem transaction):
//   1. Export TAR to grace_io (W7.7 re-use via operator_export.writeTar)
//   2. Delete all LMDB entity cells for op_pkh prefix
//   3. Delete all LMDB Pask snapshots for op_pkh prefix
//   4. (Best-effort) delete NATS stream
//
// Postgres/Caddy cleanup is NOT done here — no libpq in the Zig brain.
// `runExit` prints nothing; callers report the ExitSummary + next-steps.

const std = @import("std");

const LmdbCellStore = @import("lmdb_cell_store").LmdbCellStore;
const LmdbPaskSnapshotStore = @import("pask_snapshot_store_lmdb").LmdbPaskSnapshotStore;
const NatsEventProducer = @import("nats_event_producer").NatsEventProducer;
const operator_export = @import("operator_export");

pub const ExitSummary = struct {
    op_pkh_hex: [16]u8,
    cells_exported: u64,
    pask_exported: bool,
    cells_deleted: bool,
    pask_deleted: bool,
    nats_stream_deleted: bool,
};

pub const ExitError = error{
    export_failed,
    delete_cells_failed,
    delete_pask_failed,
    out_of_memory,
};

/// Orchestrate the operator exit sequence.
///
/// Steps (in order):
///   1. Export grace TAR archive via operator_export.writeTar.
///   2. If `!dry_run`:
///      a. Delete all LMDB entity cells.
///      b. Delete all LMDB Pask snapshots (if pask_store provided).
///      c. Delete NATS stream (best-effort; never fails the exit).
///
/// Returns ExitSummary with counts from the manifest and deletion flags.
/// Prints nothing — callers are responsible for output and next-steps.
pub fn runExit(
    allocator: std.mem.Allocator,
    op_pkh: *const [8]u8,
    cell_store: *LmdbCellStore,
    pask_store: ?*LmdbPaskSnapshotStore,
    nats_producer: ?*NatsEventProducer,
    grace_io: *std.Io.Writer,
    dry_run: bool,
) ExitError!ExitSummary {
    // Step 1 — export grace tarball (always, including dry-run).
    const manifest = operator_export.writeTar(
        allocator,
        op_pkh,
        cell_store,
        pask_store,
        grace_io,
    ) catch return error.export_failed;

    var cells_deleted = false;
    var pask_deleted = false;
    var nats_stream_deleted = false;

    if (!dry_run) {
        // Step 2a — delete all LMDB entity cells.
        cell_store.deleteAllCells() catch return error.delete_cells_failed;
        cells_deleted = true;

        // Step 2b — delete all LMDB Pask snapshots (optional).
        if (pask_store) |ps| {
            ps.deleteAllSnapshots() catch return error.delete_pask_failed;
            pask_deleted = true;
        }

        // Step 2c — delete NATS stream (best-effort; errors are swallowed).
        if (nats_producer) |np| {
            np.deleteStream() catch {};
            nats_stream_deleted = true;
        }
    }

    return ExitSummary{
        .op_pkh_hex = manifest.op_pkh_hex,
        .cells_exported = manifest.cell_count,
        .pask_exported = manifest.has_pask_snapshot,
        .cells_deleted = cells_deleted,
        .pask_deleted = pask_deleted,
        .nats_stream_deleted = nats_stream_deleted,
    };
}

```
