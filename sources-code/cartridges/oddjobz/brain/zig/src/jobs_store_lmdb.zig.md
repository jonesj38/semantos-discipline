---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/jobs_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.543246+00:00
---

# cartridges/oddjobz/brain/zig/src/jobs_store_lmdb.zig

```zig
// W0.1 — JobsStoreLmdb: cursor-only LMDB-backed jobs store.
//
// Reference: docs/design/BRAIN-BRAIN-FIELD-APP-DB-INTEGRATION-PIPELINE.md W0.1
//
// Sits behind a feature flag alongside the existing jobs_store_fs.zig (JSONL
// store).  The JSONL store is NOT removed in this PR — coexistence until W2.1
// (Postgres views) lands.
//
// Design:
//   • Wraps LmdbCellStore (runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig).
//   • put_job(cell) upserts a 1024-byte cell that MUST carry the Oddjobz job
//     domain flag at cell header offset 24 (little-endian u32).
//   • JobCursor iterates over ALL cells in the LMDB store and filters to those
//     whose flags field (offset 24, LE u32) equals ODDJOBZ_JOB_DOMAIN_FLAG.
//   • The filter is explicit rather than relying on a separate named database
//     so the same LMDB env can host cells from multiple domains.
//
// Domain flag:
//   • ODDJOBZ_JOB_DOMAIN_FLAG = 0x0001_0107 — "cap.oddjobz.read_jobs"
//     (cartridges/oddjobz/brain/src/capabilities.ts domainFlag 0x00010107).
//   • Stored at cell byte offset 24, little-endian, matching the Semantos
//     kernel cell header layout (constants.zig HEADER_OFFSET_FLAGS = 24).
//
// Cursor semantics:
//   • cursor_open → cursor_pull loop → cursor_close (forward-only, pull
//     iterator, consistent with CellStore vtable).
//   • cursor_pull skips non-job cells transparently; caller sees only cells
//     that pass the domain-flag filter.
//   • The pointer returned by cursor_pull is valid until the next cursor_pull
//     or cursor_close (LMDB memory-mapped lifetime guarantee).
//
// Feature flag:
//   • Build-time: enabled by wiring `jobs_store_lmdb` into the server init
//     path in cli.zig (gated behind `--store-backend=lmdb`, same flag as
//     LmdbCellStore / LmdbHeaderStore).  The JSONL path stays the default
//     until W2.1.  This file declares the store; the flag wiring is a
//     follow-up PR per the W0 plan.

const std = @import("std");
const cell_store_mod = @import("cell_store");

pub const CELL_BYTES = cell_store_mod.CELL_BYTES;
pub const StoreError = cell_store_mod.StoreError;

/// Cell header offset for the domain flags field (little-endian u32).
/// Matches constants.zig HEADER_OFFSET_FLAGS = 24.
pub const CELL_FLAGS_OFFSET: usize = 24;

/// Oddjobz job domain flag — `cap.oddjobz.read_jobs` (0x00010107).
/// Written at CELL_FLAGS_OFFSET in every cell stored via put_job().
/// The cursor filters to cells carrying exactly this flag value.
pub const ODDJOBZ_JOB_DOMAIN_FLAG: u32 = 0x0001_0107;

/// Opaque cursor handle used by JobsStoreLmdb.  Wraps the CellStore's
/// CellCursorHandle so the caller never touches the underlying LMDB cursor.
pub const JobCursorHandle = *anyopaque;

pub const JobsStoreLmdb = struct {
    cell_store: cell_store_mod.CellStore,

    pub fn init(cell_store: cell_store_mod.CellStore) JobsStoreLmdb {
        return .{ .cell_store = cell_store };
    }

    /// Upsert a 1024-byte job cell.  The cell MUST have ODDJOBZ_JOB_DOMAIN_FLAG
    /// at offset CELL_FLAGS_OFFSET (caller's responsibility; conformance tests
    /// verify this).  Returns the SHA256 content hash.  Idempotent.
    pub fn putJob(
        self: *JobsStoreLmdb,
        cell: *const [CELL_BYTES]u8,
    ) StoreError![32]u8 {
        return self.cell_store.put(cell);
    }

    /// Open a cursor positioned before the first cell.  The cursor iterates
    /// all cells in the underlying LMDB store and filters by domain flag.
    pub fn cursorOpen(self: *JobsStoreLmdb) StoreError!JobCursorHandle {
        return self.cell_store.cursorOpen();
    }

    /// Pull the next job cell from the cursor.  Skips cells whose flags field
    /// does not match ODDJOBZ_JOB_DOMAIN_FLAG.  Returns null when exhausted.
    /// The returned pointer is valid until the next cursorPull or cursorClose.
    pub fn cursorPull(
        self: *JobsStoreLmdb,
        cursor: JobCursorHandle,
    ) StoreError!?*const [CELL_BYTES]u8 {
        while (true) {
            const maybe = try self.cell_store.cursorPull(cursor);
            if (maybe == null) return null;
            const cell = maybe.?;
            // Read the flags field at offset 24 (little-endian u32).
            if (cell.len < CELL_FLAGS_OFFSET + 4) continue;
            const flag = std.mem.readInt(
                u32,
                cell[CELL_FLAGS_OFFSET..][0..4],
                .little,
            );
            if (flag == ODDJOBZ_JOB_DOMAIN_FLAG) return cell;
            // Not a job cell — keep iterating.
        }
    }

    /// Close the cursor and release its resources.
    pub fn cursorClose(self: *JobsStoreLmdb, cursor: JobCursorHandle) void {
        self.cell_store.cursorClose(cursor);
    }
};

```
