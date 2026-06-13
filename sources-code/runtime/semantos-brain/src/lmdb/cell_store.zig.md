---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/lmdb/cell_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.280643+00:00
---

# runtime/semantos-brain/src/lmdb/cell_store.zig

```zig
// M1.5 — CellStore vtable: raw 1024-byte cell persistence keyed by content hash.
//
// Design notes:
//   • Each cell is exactly CELL_BYTES (1024) bytes — the Semantos kernel cell size.
//   • Keys are the 32-byte SHA256 content hash of the cell bytes.
//   • Values stored in LMDB are padded to PAGE_BYTES (4096) multiples so the
//     LMDB file stays 4 KiB page-aligned. Padding bytes are zero. The LMDB
//     implementation reads only the first CELL_BYTES from the value.
//   • The cursor (CellCursor) is a forward-only pull iterator: each call to
//     `pull` returns one *const [CELL_BYTES]u8 valid for the lifetime of the
//     enclosing read transaction, or null when exhausted.
//   • The vtable is put (idempotent upsert) + exists (cheap check) +
//     cursor_open / cursor_pull / cursor_close + count, plus the additive
//     spent-set seam — `spend` (idempotent upsert into a side index) and
//     `is_spent` (O(1) query). The spent-set is the host-side K1 substrate
//     the kernel-gate model expects: `OP_ASSERTLINEAR` (`0xC5`) is a
//     read-only assertion in the cell-engine; consumption is enforced
//     host-side. The vtable seam decouples the host obligation from
//     any one cartridge — backings (LMDB, in-memory, federated) all
//     answer the same two questions: "is this cell_id spent?" and
//     "mark this cell_id spent (idempotent)".
//
// Implementations: LmdbCellStore (runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig).

const std = @import("std");

pub const CELL_BYTES: usize = 1024;
pub const PAGE_BYTES: usize = 4096;
/// Padded value size: next multiple of PAGE_BYTES >= CELL_BYTES.
pub const VALUE_BYTES: usize = ((CELL_BYTES + PAGE_BYTES - 1) / PAGE_BYTES) * PAGE_BYTES; // 4096

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    invalid_cell,
};

/// Opaque cursor handle. The vtable implementation casts this to its concrete
/// cursor type. Cursors must be closed with `cursor_close` before the
/// associated store or environment is torn down.
pub const CellCursorHandle = *anyopaque;

/// D-LC3 — owner_id size. Matches OWNER_ID_OFFSET=62..78 in the cell header.
/// Lifted here so the vtable can express `cellsByOwner` without leaking the
/// LMDB impl module.
pub const OWNER_ID_BYTES: usize = 16;

/// D-LC5 — anchor-status projection. Brain tracks for each cell whether it
/// is `pending` (minted speculatively, anchor TX not yet observed),
/// `confirmed` (anchor-attestation cell for the corresponding txid has
/// landed), or absent (no anchor expected — the default for cells minted
/// without an anchor flow). Lifted from cell_store_lmdb.zig to the vtable
/// level so any backing can answer the same projection questions; the
/// previous symbol is re-exported from the LMDB impl module for back-compat.
pub const AnchorStatus = enum(u8) {
    pending = 0,
    confirmed = 1,
};

/// D-LC5 follow-up (reorg-sweep substrate) — sweep counts.
pub const SweepResult = struct {
    /// Number of cells whose anchor projection was cleared because they
    /// were `.pending` against the reorged-away txid.
    swept: u32,
    /// Number of cells left untouched. These are either `.confirmed`
    /// (past finality requires explicit invalidation, not silent reorg
    /// rollback) or had no anchor-status entry at all by the time the
    /// sweep ran.
    kept: u32,
};

/// D-LC5 follow-up (anchor-attestation schema v2 — height-keyed reorg
/// substrate) — (height, cell_hash) tuple returned from a height-range
/// scan against `cells_by_anchor_height`. Lifted here so the vtable
/// can express the height-range query without leaking the LMDB impl
/// module.
pub const AnchorHeightEntry = struct {
    height: u64,
    cell_hash: [32]u8,
};

/// D-LC4 follow-up (paginated prev-state range) — result shape for
/// `cellsByPrevStateRange`. Lifted here so the vtable seam can
/// express the paginated query; the impl-side struct in
/// `cell_store_lmdb.zig` is re-exported from this one. Reactor.zig
/// has been calling `cellsByPrevStateRange` on `*const CellStore`
/// since PR #505 even though the vtable promotion in PR #510
/// explicitly deferred it — this entry closes that gap as part of
/// the schema-v2 substrate landing.
pub const PrevStateRangeResult = struct {
    hashes: [][32]u8,
    has_more: bool,
};

pub const CellStore = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Upsert a 1024-byte cell. Idempotent: writing the same cell twice is a
        /// no-op (same hash → same key, same bytes). Returns the 32-byte hash.
        put: *const fn (
            ctx: *anyopaque,
            cell: *const [CELL_BYTES]u8,
        ) StoreError![32]u8,

        /// Return true if a cell with the given hash is already stored.
        exists: *const fn (
            ctx: *anyopaque,
            hash: *const [32]u8,
        ) bool,

        /// Open a cursor positioned before the first cell. The cursor is valid
        /// until `cursor_close` is called.
        cursor_open: *const fn (ctx: *anyopaque) StoreError!CellCursorHandle,

        /// Pull the next cell from the cursor. Returns a pointer into LMDB-managed
        /// memory valid until the next `cursor_pull` or `cursor_close`. Returns
        /// null when there are no more cells.
        cursor_pull: *const fn (
            ctx: *anyopaque,
            cursor: CellCursorHandle,
        ) StoreError!?*const [CELL_BYTES]u8,

        /// Close the cursor and release its resources.
        cursor_close: *const fn (ctx: *anyopaque, cursor: CellCursorHandle) void,

        /// Return the total number of cells in the store (O(1) in LMDB via
        /// mdb_stat).
        count: *const fn (ctx: *anyopaque) StoreError!u64,

        /// Record `cell_id` as spent in the host-side K1 spent-set.
        /// Idempotent: spending an already-spent cell is a no-op. Returns
        /// `true` iff the cell was newly added to the set (was not already
        /// spent). Implementations isolate the spent-set per-operator the
        /// same way `put`/`exists` are isolated by `op_pkh`.
        spend: *const fn (
            ctx: *anyopaque,
            cell_id: *const [32]u8,
        ) StoreError!bool,

        /// O(1) query: is `cell_id` recorded in the spent-set? Mirrors
        /// the host-side `ConsumedCellSet.has(cellId)` shape that the
        /// kernel-gate model defines on the TS side.
        is_spent: *const fn (
            ctx: *anyopaque,
            cell_id: *const [32]u8,
        ) bool,

        // ── Read/query surface (promoted from LmdbCellStore) ──
        //
        // The methods below originated as concrete LmdbCellStore methods
        // (D-LC1 / D-LC3 / D-LC4 / D-LC5 + reorg-sweep substrate); the
        // vtable promotion lifts them so external callers (reactor read
        // paths, future backings) can depend on the seam, not the impl.
        // Operator-exit primitives (deleteAllCells) and impl-specific
        // maintenance helpers stay on LmdbCellStore directly.

        /// D-LC1 — fetch a cell by content hash. Returns the 1024 bytes by
        /// value (copy out of backing-managed memory), or null on miss.
        get_cell: *const fn (
            ctx: *anyopaque,
            hash: *const [32]u8,
        ) StoreError!?[CELL_BYTES]u8,

        /// D-LC3 — enumerate every cell hash whose header `owner_id` (bytes
        /// 62..78) matches the given 16-byte id, scoped to this store's
        /// operator. Returns an owned slice the caller must free.
        cells_by_owner: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            owner_id: *const [OWNER_ID_BYTES]u8,
        ) StoreError![][32]u8,

        /// C4 — enumerate every cell hash of exactly `type_hash` (the structured
        /// 8|8|8|8 typeHash at cell bytes 30..62), scoped to this store's
        /// operator. The generic `cell.query` substrate primitive reads this.
        /// Returns an owned slice the caller must free.
        cells_by_type: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            type_hash: *const [32]u8,
        ) StoreError![][32]u8,

        /// C4 — enumerate every cell hash whose typeHash starts with
        /// `type_prefix` (0..32 bytes of the leading 8|8|8|8 segments — the
        /// hierarchical "index template": 8=namespace, 16=+domain, 24=+sub-type,
        /// 32=exact; empty=all of this operator's cells). Owned slice; free it.
        cells_by_type_prefix: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            type_prefix: []const u8,
        ) StoreError![][32]u8,

        /// D-LC4 — enumerate every cell hash whose header `prev_state_hash`
        /// (bytes 128..160) matches the given 32-byte hash, scoped to this
        /// store's operator. Returns an owned slice the caller must free.
        cells_by_prev_state: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            prev_state_hash: *const [32]u8,
        ) StoreError![][32]u8,

        /// D-LC5 follow-up — enumerate every target cell hash that was
        /// anchored by the given txid, scoped to this store's operator.
        /// Returns an owned slice the caller must free.
        cells_by_anchor_txid: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            anchor_txid: *const [32]u8,
        ) StoreError![][32]u8,

        /// D-LC5 — set the anchor status for a cell. Idempotent: re-marking
        /// with the same status is a no-op.
        set_anchor_status: *const fn (
            ctx: *anyopaque,
            hash: *const [32]u8,
            status: AnchorStatus,
        ) StoreError!void,

        /// D-LC5 — read the anchor status. Returns null when the cell has
        /// no entry (the default for cells minted outside an anchor flow).
        get_anchor_status: *const fn (
            ctx: *anyopaque,
            hash: *const [32]u8,
        ) ?AnchorStatus,

        /// D-LC5 — clear the anchor status. Not-found is treated as
        /// success (idempotent delete).
        clear_anchor_status: *const fn (
            ctx: *anyopaque,
            hash: *const [32]u8,
        ) StoreError!void,

        /// D-LC5 follow-up — clear every `.pending` projection anchored by
        /// `anchor_txid`. `.confirmed` entries are preserved (past finality
        /// requires explicit invalidation). Returns counts of cleared vs
        /// preserved entries.
        sweep_pending_anchors: *const fn (
            ctx: *anyopaque,
            anchor_txid: *const [32]u8,
        ) StoreError!SweepResult,

        /// D-LC5 follow-up (schema v2) — enumerate every target_cell_hash
        /// whose `anchor_height` lies in the inclusive range `[low, high]`,
        /// scoped to this store's operator. Ordering: ascending by height.
        /// Returns an owned slice the caller must free.
        cells_by_anchor_height_range: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            height_low_inclusive: u64,
            height_high_inclusive: u64,
        ) StoreError![]AnchorHeightEntry,

        /// D-LC5 follow-up (schema v2) — clear every `.pending` projection
        /// whose attestation cell was anchored at a height
        /// >= `rollback_from_height`. Same semantics as
        /// `sweep_pending_anchors` but keyed by block height instead of
        /// txid: `.confirmed` entries are preserved, idempotent on
        /// repeated invocation, reverse-index entries themselves are
        /// not removed.
        sweep_reorged_from_height: *const fn (
            ctx: *anyopaque,
            rollback_from_height: u64,
        ) StoreError!SweepResult,

        /// D-LC4 follow-up — paginated variant of `cells_by_prev_state`.
        /// `after` is an optional cursor (strictly-after) and `limit` is
        /// the page size. Returns `(hashes, has_more)` so callers can
        /// emit the standard `x-next-cursor` header without a second
        /// query. (Deferred in PR #510; closed here as a side-fix so
        /// the reactor's existing call resolves through the vtable
        /// seam, not the impl module.)
        cells_by_prev_state_range: *const fn (
            ctx: *anyopaque,
            allocator: std.mem.Allocator,
            prev_state_hash: *const [32]u8,
            after: ?*const [32]u8,
            limit: usize,
        ) StoreError!PrevStateRangeResult,
    };

    pub fn put(self: *const CellStore, cell: *const [CELL_BYTES]u8) StoreError![32]u8 {
        return self.vtable.put(self.ctx, cell);
    }

    pub fn exists(self: *const CellStore, hash: *const [32]u8) bool {
        return self.vtable.exists(self.ctx, hash);
    }

    pub fn cursorOpen(self: *const CellStore) StoreError!CellCursorHandle {
        return self.vtable.cursor_open(self.ctx);
    }

    pub fn cursorPull(
        self: *const CellStore,
        cursor: CellCursorHandle,
    ) StoreError!?*const [CELL_BYTES]u8 {
        return self.vtable.cursor_pull(self.ctx, cursor);
    }

    pub fn cursorClose(self: *const CellStore, cursor: CellCursorHandle) void {
        self.vtable.cursor_close(self.ctx, cursor);
    }

    pub fn count(self: *const CellStore) StoreError!u64 {
        return self.vtable.count(self.ctx);
    }

    pub fn spend(self: *const CellStore, cell_id: *const [32]u8) StoreError!bool {
        return self.vtable.spend(self.ctx, cell_id);
    }

    pub fn isSpent(self: *const CellStore, cell_id: *const [32]u8) bool {
        return self.vtable.is_spent(self.ctx, cell_id);
    }

    // ── Read/query surface (promoted from LmdbCellStore) ──

    pub fn getCell(
        self: *const CellStore,
        hash: *const [32]u8,
    ) StoreError!?[CELL_BYTES]u8 {
        return self.vtable.get_cell(self.ctx, hash);
    }

    pub fn cellsByOwner(
        self: *const CellStore,
        allocator: std.mem.Allocator,
        owner_id: *const [OWNER_ID_BYTES]u8,
    ) StoreError![][32]u8 {
        return self.vtable.cells_by_owner(self.ctx, allocator, owner_id);
    }

    /// C4 — enumerate cell hashes of exactly `type_hash` (see vtable doc).
    pub fn cellsByType(
        self: *const CellStore,
        allocator: std.mem.Allocator,
        type_hash: *const [32]u8,
    ) StoreError![][32]u8 {
        return self.vtable.cells_by_type(self.ctx, allocator, type_hash);
    }

    /// C4 — enumerate cell hashes by a 0..32-byte typeHash template prefix.
    pub fn cellsByTypePrefix(
        self: *const CellStore,
        allocator: std.mem.Allocator,
        type_prefix: []const u8,
    ) StoreError![][32]u8 {
        return self.vtable.cells_by_type_prefix(self.ctx, allocator, type_prefix);
    }

    pub fn cellsByPrevState(
        self: *const CellStore,
        allocator: std.mem.Allocator,
        prev_state_hash: *const [32]u8,
    ) StoreError![][32]u8 {
        return self.vtable.cells_by_prev_state(self.ctx, allocator, prev_state_hash);
    }

    pub fn cellsByAnchorTxid(
        self: *const CellStore,
        allocator: std.mem.Allocator,
        anchor_txid: *const [32]u8,
    ) StoreError![][32]u8 {
        return self.vtable.cells_by_anchor_txid(self.ctx, allocator, anchor_txid);
    }

    pub fn setAnchorStatus(
        self: *const CellStore,
        hash: *const [32]u8,
        status: AnchorStatus,
    ) StoreError!void {
        return self.vtable.set_anchor_status(self.ctx, hash, status);
    }

    pub fn getAnchorStatus(
        self: *const CellStore,
        hash: *const [32]u8,
    ) ?AnchorStatus {
        return self.vtable.get_anchor_status(self.ctx, hash);
    }

    pub fn clearAnchorStatus(
        self: *const CellStore,
        hash: *const [32]u8,
    ) StoreError!void {
        return self.vtable.clear_anchor_status(self.ctx, hash);
    }

    pub fn sweepPendingAnchors(
        self: *const CellStore,
        anchor_txid: *const [32]u8,
    ) StoreError!SweepResult {
        return self.vtable.sweep_pending_anchors(self.ctx, anchor_txid);
    }

    pub fn cellsByAnchorHeightRange(
        self: *const CellStore,
        allocator: std.mem.Allocator,
        height_low_inclusive: u64,
        height_high_inclusive: u64,
    ) StoreError![]AnchorHeightEntry {
        return self.vtable.cells_by_anchor_height_range(
            self.ctx,
            allocator,
            height_low_inclusive,
            height_high_inclusive,
        );
    }

    pub fn sweepReorgedFromHeight(
        self: *const CellStore,
        rollback_from_height: u64,
    ) StoreError!SweepResult {
        return self.vtable.sweep_reorged_from_height(self.ctx, rollback_from_height);
    }

    pub fn cellsByPrevStateRange(
        self: *const CellStore,
        allocator: std.mem.Allocator,
        prev_state_hash: *const [32]u8,
        after: ?*const [32]u8,
        limit: usize,
    ) StoreError!PrevStateRangeResult {
        return self.vtable.cells_by_prev_state_range(
            self.ctx,
            allocator,
            prev_state_hash,
            after,
            limit,
        );
    }
};

```
