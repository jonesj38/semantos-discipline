---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cursor_host.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.228286+00:00
---

# runtime/semantos-brain/src/cursor_host.zig

```zig
// M1.10 — CursorHost: host-side implementation of the three cursor imports.
//
// In the full runtime (brain), the WASM kernel calls back into these functions
// via the wasmtime host-import mechanism. In native conformance tests, they are
// called directly through the CursorHost struct.
//
// API surface (mirrors the WASM host-import signatures):
//
//   openCursor(filter_ptr, filter_len) → cursor_id  (0 = error)
//   pullCell(cursor_id, out_ptr)       → 1 = cell written, 0 = done/error
//   closeCursor(cursor_id)             → void
//
// A CursorHost owns a fixed table of MAX_CURSORS slots. Slot index is 1-based
// so that 0 can serve as the error sentinel returned by openCursor.
//
// Peak heap is bounded at one cell (1024 bytes): the scratch buffer lives
// inside the CursorHost struct on the caller's stack, and cursorScan() reuses
// it on every pull rather than allocating per-cell.

const std = @import("std");
const cell_store_mod = @import("cell_store");

pub const CELL_BYTES = cell_store_mod.CELL_BYTES;

/// Maximum number of simultaneously open cursors. 8 slots is sufficient for
/// the M1.10 conformance test requirements; increase if needed.
pub const MAX_CURSORS = 8;

/// Callback signature for cursorScan — mirrors the WASM function-pointer
/// convention used by kernel_cursor_scan.
pub const ScanCallback = *const fn (ctx: ?*anyopaque, cell: *const [CELL_BYTES]u8) void;

pub const CursorHost = struct {
    store: *const cell_store_mod.CellStore,
    /// Cursor slot table. Index 0 = unused sentinel; valid cursor_ids are 1..MAX_CURSORS.
    slots: [MAX_CURSORS + 1]?cell_store_mod.CellCursorHandle,
    /// Single 1024-byte scratch buffer — reused on every pull (peak heap = 1 cell).
    scratch: [CELL_BYTES]u8,

    pub fn init(store: *const cell_store_mod.CellStore) CursorHost {
        return .{
            .store = store,
            .slots = [_]?cell_store_mod.CellCursorHandle{null} ** (MAX_CURSORS + 1),
            .scratch = undefined,
        };
    }

    // ── openCursor ──────────────────────────────────────────────────────────
    // Opens a CellStore cursor and stores it in the first free slot.
    // filter_ptr / filter_len are reserved for future predicate filtering.
    // Returns slot index (1..MAX_CURSORS) on success, 0 on error.

    pub fn openCursor(
        self: *CursorHost,
        filter_ptr: ?*const anyopaque,
        filter_len: u32,
    ) u32 {
        _ = filter_ptr;
        _ = filter_len;

        // Find a free slot (index 1..MAX_CURSORS; slot 0 is the error sentinel).
        var slot_idx: usize = 1;
        while (slot_idx <= MAX_CURSORS) : (slot_idx += 1) {
            if (self.slots[slot_idx] == null) break;
        }
        if (slot_idx > MAX_CURSORS) return 0; // no free slots

        const handle = self.store.cursorOpen() catch return 0;
        self.slots[slot_idx] = handle;
        return @intCast(slot_idx);
    }

    // ── pullCell ────────────────────────────────────────────────────────────
    // Pulls the next cell from cursor `cursor_id` into `out_ptr`.
    // Returns 1 on success (cell written), 0 on end-of-data or error.
    // The caller's out_ptr must point to at least CELL_BYTES of writable memory.

    pub fn pullCell(
        self: *CursorHost,
        cursor_id: u32,
        out_ptr: *[CELL_BYTES]u8,
    ) u32 {
        if (cursor_id == 0 or cursor_id > MAX_CURSORS) return 0;
        const handle = self.slots[cursor_id] orelse return 0;

        const cell_ptr = self.store.cursorPull(handle) catch return 0;
        const cell = cell_ptr orelse return 0; // null = exhausted

        @memcpy(out_ptr, cell);
        return 1;
    }

    // ── closeCursor ─────────────────────────────────────────────────────────
    // Closes the cursor and frees the slot. Safe to call on an already-closed
    // or invalid cursor_id (no-op).

    pub fn closeCursor(self: *CursorHost, cursor_id: u32) void {
        if (cursor_id == 0 or cursor_id > MAX_CURSORS) return;
        const handle = self.slots[cursor_id] orelse return;
        self.store.cursorClose(handle);
        self.slots[cursor_id] = null;
    }

    // ── cursorScan ──────────────────────────────────────────────────────────
    // High-level scan: open cursor, loop pulling cells, call `callback` for each,
    // close cursor. The scratch buffer inside this struct is reused on every pull
    // so peak heap is exactly one cell (1024 bytes).
    //
    // filter_ptr / filter_len are passed through to openCursor (reserved).
    // callback may be null (cells are counted but not processed).
    // ctx is forwarded to callback as the first argument.
    //
    // Returns the number of cells scanned, or a negative error code:
    //   -1 = could not open cursor (store error or no free slots)

    pub fn cursorScan(
        self: *CursorHost,
        callback: ?ScanCallback,
        ctx: ?*anyopaque,
        filter_len: u32,
    ) i32 {
        const cursor_id = self.openCursor(null, filter_len);
        if (cursor_id == 0) return -1;
        defer self.closeCursor(cursor_id);

        var count: i32 = 0;
        while (self.pullCell(cursor_id, &self.scratch) == 1) {
            count += 1;
            if (callback) |cb| {
                cb(ctx, &self.scratch);
            }
        }
        return count;
    }
};

```
