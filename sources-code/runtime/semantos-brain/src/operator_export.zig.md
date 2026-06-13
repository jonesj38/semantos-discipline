---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/operator_export.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.262621+00:00
---

# runtime/semantos-brain/src/operator_export.zig

```zig
// W7.7 — OperatorExport: LMDB cell export + Pask snapshot for a single operator.
//
// Produces a deterministic TAR archive that a peer node can import to
// reconstruct the operator's data byte-identically.
//
// Archive layout:
//
//   export/manifest.json        — metadata (op_pkh, version, exported_at, counts)
//   export/cells/<sha256_hex>   — LMDB cells, one file per cell named by hash
//   export/pask_snapshot.bin    — raw Pask snapshot bytes (omitted if no snapshot)
//
// Usage (in cli.zig):
//
//   var tar_file = try std.fs.cwd().createFile(out_path, .{});
//   defer tar_file.close();
//   var buf: [65536]u8 = undefined;
//   var fw = tar_file.writer(&buf);
//   const manifest = try operator_export.writeTar(allocator, &op_pkh, &cell_store_impl, null, &fw.interface);

const std = @import("std");
const lmdb_cell_store_mod = @import("lmdb_cell_store");
const pask_snapshot_store_mod = @import("pask_snapshot_store");

const LmdbCellStore = lmdb_cell_store_mod.LmdbCellStore;
const LmdbPaskSnapshotStore = @import("pask_snapshot_store_lmdb").LmdbPaskSnapshotStore;

pub const OP_PKH_HEX_LEN = 16; // 8 raw bytes × 2 hex chars

pub const ExportManifest = struct {
    op_pkh_hex: [OP_PKH_HEX_LEN]u8,
    cell_count: u64,
    has_pask_snapshot: bool,
    exported_at_ns: i128,
};

pub const ExportError = error{
    persistence_failed,
    io_error,
    out_of_memory,
};

/// Write a TAR archive of all operator data to the `std.Io.Writer` pointed to by `io`.
///
/// `cell_store` must have been initialised via `LmdbCellStore.initForOperator(op_pkh)`.
/// Pass `null` for `pask_store` to skip the Pask snapshot section.
///
/// The archive is deterministic: cells are emitted in LMDB key order (which is
/// the content-addressed SHA256 key order) so the same LMDB state always
/// produces the same archive.
pub fn writeTar(
    allocator: std.mem.Allocator,
    op_pkh: *const [8]u8,
    cell_store: *LmdbCellStore,
    pask_store: ?*LmdbPaskSnapshotStore,
    io: *std.Io.Writer,
) ExportError!ExportManifest {
    var tar = std.tar.Writer{ .underlying_writer = io };
    tar.setRoot("export") catch return error.io_error;

    const vtable = cell_store.store();

    // ── Cell export ──────────────────────────────────────────────────────

    var cell_count: u64 = 0;
    var path_buf: [80]u8 = undefined; // "cells/" + 64-char sha256 hex
    var hash_hex: [64]u8 = undefined;

    const cursor = vtable.cursorOpen() catch return error.persistence_failed;
    defer vtable.cursorClose(cursor);

    while (true) {
        const maybe = vtable.cursorPull(cursor) catch return error.persistence_failed;
        if (maybe == null) break;
        const cell = maybe.?;

        var sha256_result: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(cell, &sha256_result, .{});
        hash_hex = std.fmt.bytesToHex(&sha256_result, .lower);
        const path = std.fmt.bufPrint(&path_buf, "cells/{s}", .{hash_hex}) catch unreachable;

        tar.writeFileBytes(path, cell, .{}) catch return error.io_error;
        cell_count += 1;
    }

    // ── Pask snapshot export ─────────────────────────────────────────────

    var has_pask_snapshot = false;
    if (pask_store) |ps| {
        const snap = ps.exportRaw(allocator) catch null;
        if (snap) |s| {
            defer allocator.free(s);
            tar.writeFileBytes("pask_snapshot.bin", s, .{}) catch return error.io_error;
            has_pask_snapshot = true;
        }
    }

    // ── Manifest ─────────────────────────────────────────────────────────

    var op_pkh_hex: [OP_PKH_HEX_LEN]u8 = undefined;
    op_pkh_hex = std.fmt.bytesToHex(op_pkh, .lower);

    const exported_at_ns = std.time.nanoTimestamp();
    var json_buf: [512]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf,
        \\{{"version":1,"op_pkh":"{s}","cell_count":{d},"has_pask_snapshot":{s},"exported_at_ns":{d}}}
        \\
    , .{
        op_pkh_hex,
        cell_count,
        if (has_pask_snapshot) "true" else "false",
        exported_at_ns,
    }) catch return error.io_error;

    tar.writeFileBytes("manifest.json", json, .{}) catch return error.io_error;

    // End-of-archive marker + flush the underlying buffered writer.
    tar.finishPedantically() catch return error.io_error;
    io.flush() catch return error.io_error;

    return .{
        .op_pkh_hex = op_pkh_hex,
        .cell_count = cell_count,
        .has_pask_snapshot = has_pask_snapshot,
        .exported_at_ns = exported_at_ns,
    };
}

```
