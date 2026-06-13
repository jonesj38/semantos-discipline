---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.279418+00:00
---

# runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig

```zig
// M1.5 / W7.1 — LmdbCellStore: CellStore vtable backed by LMDB.
//
// ── Key layout (W7.1) ─────────────────────────────────────────────────────
//
//   key:   op_pkh (16B) ‖ SHA256(cell_bytes) (32B)  → 48 bytes total
//   value: cell_bytes(1024) || padding(3072)          → 4096 bytes (1 × PAGE)
//
// op_pkh is the first 16 hex chars of the operator's pubkey hash (8 bytes).
// For single-operator deployments, op_pkh is all-zero bytes.  All keys are
// 48 bytes regardless of whether the zero-prefix or a real operator prefix is
// in use — this ensures the cursor prefix-scan always works correctly.
//
// Prefix isolation: cursor scans seek to `op_pkh` and stop when the key
// no longer starts with that prefix.  Cross-operator cursor scans return
// empty; cross-operator point lookups (exists/put) use the wrong 48-byte
// key and therefore miss — by construction.
//
// ── Spent-set side index (P4a) ───────────────────────────────────────────
//
// A sibling sub-DB `cells_spent` records cell_ids that have been consumed
// by a successor mint (host-side K1: cells are immutable, so spent-ness
// must live outside the cell payload — a side index keyed by cell_id).
// Key layout mirrors `cells`: op_pkh (8B) ‖ cell_id (32B) = 40 bytes.
// Value: a 1-byte sentinel (membership only; no payload).
//
// Lazy creation: the sub-DB is opened with `create:true`, so existing
// envs that predate this change upgrade in place on first open.
//
// ── Constructors ─────────────────────────────────────────────────────────
//
//   init(env, allocator)                      — single-tenant (zero op_pkh)
//   initForOperator(env, allocator, op_pkh)   — hosted-operator (W7.1)
//
// All existing call sites using `init` continue to work unchanged; they use
// the zero op_pkh and see their cells in the `\x00`×16 prefix range.
//
// ── Management operations (not in vtable) ────────────────────────────────
//
//   deleteAllCells(self) !void   — delete all cells AND spent-set entries
//                                  for this op_pkh. Used by W7.8 operator
//                                  exit; both sub-DBs are scrubbed
//                                  together so exit is atomic.
//
// References:
//   - docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md W7.1
//   - docs/design/ — spent-set design doc (host-side K1 plan, P4a)
//   - runtime/semantos-brain/src/lmdb/cell_store.zig          (vtable interface)
//   - runtime/semantos-brain/src/lmdb/lmdb.zig                (LMDB wrapper)

const std = @import("std");
const lmdb = @import("lmdb");
const cell_store_mod = @import("cell_store");
const constants = @import("constants");

pub const CELL_BYTES = cell_store_mod.CELL_BYTES;
pub const PAGE_BYTES = cell_store_mod.PAGE_BYTES;
pub const VALUE_BYTES = cell_store_mod.VALUE_BYTES;
pub const StoreError = cell_store_mod.StoreError;

/// W7.1 — op_pkh prefix length in bytes (8 raw bytes = 16 hex chars in ASCII).
/// We store the raw 8 bytes in the LMDB key, not the hex string, for compactness.
pub const OP_PKH_BYTES: usize = 8;

/// Total LMDB key length: 8 bytes op_pkh + 32 bytes SHA256 = 40 bytes.
const KEY_BYTES: usize = OP_PKH_BYTES + 32;

/// D-LC3 — owner_id is 16 bytes at offset 62 in the 1024-byte cell. The
/// `cells_by_owner` secondary index lets callers enumerate every cell hash
/// for a given (op_pkh, owner_id) without scanning the main "cells" DB.
/// Key shape: op_pkh(8B) ‖ owner_id(16B) ‖ cell_hash(32B) = 56 bytes. Value
/// is empty — the key alone carries the mapping.
const OWNER_ID_BYTES: usize = 16;
const OWNER_ID_OFFSET_IN_CELL: usize = 62;
const OWNER_KEY_BYTES: usize = OP_PKH_BYTES + OWNER_ID_BYTES + 32;

/// C4 (substrate-generalization) — the structured 8|8|8|8 typeHash is 32 bytes
/// at offset 30 in the 1024-byte cell (HEADER_OFFSET_TYPE_HASH). The
/// `cells_by_type` secondary index lets a generic `cell.query` enumerate every
/// cell of a given typeHash WITHOUT a per-cartridge typed store. Key shape:
/// op_pkh(8B) ‖ type_hash(32B) ‖ cell_hash(32B) = 72 bytes, empty value. Because
/// the embedded typeHash is itself four independent 8-byte segments
/// (namespace|domain|sub-type|qualifier), a SHORTER op_pkh‖segments prefix
/// gives hierarchical "index template" scans for free (namespace, +domain, …).
const TYPE_HASH_BYTES: usize = 32;
const TYPE_HASH_OFFSET_IN_CELL: usize = 30;
const TYPE_KEY_BYTES: usize = OP_PKH_BYTES + TYPE_HASH_BYTES + 32;

/// D-LC4 — prev_state_hash is 32 bytes at offset 128 in the 1024-byte cell
/// (matches HEADER_OFFSET_PREV_STATE_HASH in core/cell-engine/src/constants.zig).
/// The `cells_by_prev_state` secondary index lets callers walk the
/// state-DAG forward from any given prev_state_hash to its immediate
/// successor cells. Key: op_pkh(8B) ‖ prev_state_hash(32B) ‖ cell_hash(32B)
/// = 72 bytes; empty value.
const PREV_STATE_HASH_BYTES: usize = 32;
const PREV_STATE_HASH_OFFSET_IN_CELL: usize = 128;
const PREV_STATE_KEY_BYTES: usize = OP_PKH_BYTES + PREV_STATE_HASH_BYTES + 32;

/// D-LC5 — anchor-status projection. Brain tracks for each cell whether
/// it is `pending` (minted speculatively, anchor TX not yet observed),
/// `confirmed` (anchor-attestation cell for the corresponding txid has
/// landed), or absent (no anchor expected — the default for cells minted
/// without an anchor flow). Key: op_pkh(8B) ‖ cell_hash(32B) = 40 bytes
/// (same shape as the primary `cells` key); value: 1 byte enum.
///
/// The enum itself now lives at the vtable level
/// (`cell_store_mod.AnchorStatus`) so callers that talk through
/// `*const CellStore` need not import the LMDB impl module. The local
/// alias here is re-exported for source compatibility with existing
/// `lmdb_cell_store_mod.AnchorStatus` references (tests, callers that
/// happen to import the impl module directly).
pub const AnchorStatus = cell_store_mod.AnchorStatus;
const ANCHOR_KEY_BYTES: usize = OP_PKH_BYTES + 32;

/// D-LC5 follow-up — domain_flag field lives at cell offset 24, u32 LE
/// (mirrors HEADER_OFFSET_FLAGS in core/cell-engine/src/constants.zig).
const DOMAIN_FLAG_OFFSET_IN_CELL: usize = 24;
const DOMAIN_FLAG_SIZE_IN_CELL: usize = 4;

/// D-LC5 follow-up — anchor-attestation payload starts at cell offset 256
/// (HEADER_SIZE in constants.zig). targetCellId is the first 32 bytes of
/// the payload per anchorAttestationSchemaV1 (field offset 0, u256, 32B).
/// Pinned to schema v1 — if the schema layout changes, this offset and
/// the dispatch logic in doPut must be updated together.
const ATTESTATION_TARGET_CELL_ID_OFFSET: usize = 256;
const ATTESTATION_TARGET_CELL_ID_SIZE: usize = 32;

/// D-LC5 follow-up (reorg-sweep substrate) — anchor-attestation txid is the
/// second field of the payload per anchorAttestationSchemaV2 (field offset
/// 32, u256, 32B). Absolute cell offset = HEADER_SIZE (256) + payload offset
/// (32) = 288. Offset is unchanged between schema v1 and v2 — see the v2
/// layout note in core/plexus-schema-registry/src/schemas/anchor-attestation.ts.
/// If the schema layout ever changes again, the offset and the dispatch
/// logic in doPut must be updated together.
const ATTESTATION_TXID_OFFSET: usize = 288;
const ATTESTATION_TXID_SIZE: usize = 32;

/// D-LC5 follow-up (anchor-attestation schema v2 — D-LC5-reorg-by-height
/// substrate) — anchor-attestation `anchor_height` is the third field of
/// the payload per anchorAttestationSchemaV2 (field offset 64, u64, 8B,
/// little-endian within the cell). Absolute cell offset = HEADER_SIZE
/// (256) + payload offset (64) = 320. Pinned to schema v2; if the schema
/// layout ever changes, this offset and the dispatch logic in doPut
/// must be updated together.
const ATTESTATION_ANCHOR_HEIGHT_OFFSET: usize = 320;
const ATTESTATION_ANCHOR_HEIGHT_SIZE: usize = 8;

/// D-LC5 follow-up (reorg-sweep substrate) — `cells_by_anchor_txid` reverse
/// index. Lets the reorg sweep look up "which target cells were anchored by
/// this txid?" in one cursor prefix-scan, instead of walking the whole
/// `cells_anchor_status` projection and re-reading every attestation cell.
/// Key shape: op_pkh(8B) ‖ anchor_txid(32B) ‖ target_cell_hash(32B) = 72
/// bytes (mirrors the D-LC4 `cells_by_prev_state` key topology). Value is
/// empty — the key alone carries the mapping. Maintained by doPut at the
/// same atomic step as the primary attestation cell.
const ANCHOR_TXID_KEY_BYTES: usize = OP_PKH_BYTES + ATTESTATION_TXID_SIZE + 32;

/// D-LC5 follow-up (anchor-attestation schema v2 — D-LC5-reorg-by-height
/// substrate) — `cells_by_anchor_height` reverse index. Lets the reorg
/// sweep enumerate every attestation cell whose anchor block sits in a
/// rolled-back height range. Key shape:
///   op_pkh(8B) ‖ anchor_height(8B BIG-ENDIAN) ‖ target_cell_hash(32B)
///   = 48 bytes.
/// Big-endian encoding of `anchor_height` in the LMDB key is deliberate:
/// LMDB orders keys lexicographically, so BE encoding makes lex-sort
/// match numeric-sort. The range query "all heights >= H" then becomes
/// a cursor seek to `op_pkh ‖ BE(H)` followed by step() until either
/// the op_pkh prefix breaks or the height upper bound is exceeded.
/// (LE in the payload bytes is fine — consistent with the rest of the
/// cell — but LE in the LMDB key would give nonsensical sort order.)
/// Value is empty — the key alone carries the mapping. Maintained by
/// doPut at the same atomic step as the primary attestation cell.
const ANCHOR_HEIGHT_KEY_BYTES: usize = OP_PKH_BYTES + ATTESTATION_ANCHOR_HEIGHT_SIZE + 32;

/// D-LC5 follow-up — canonical wire value for anchor-attestation cells.
/// Source of truth: core/plexus-contracts/src/domain-flags.ts
/// (SemantosDomainFlags.ANCHOR_ATTESTATION = 0x0001FE02; relocated from
/// 0x00010102 per audit B-1, mirrored by the schema registration in
/// core/plexus-schema-registry/src/schemas/anchor-attestation.ts).
///
/// Promoted from a local const into the generated constants registry
/// per D-Const-domainflag-genfix — entry lives in
/// core/constants/constants.json and is emitted into
/// core/cell-engine/src/constants.zig as DOMAIN_FLAG_ANCHOR_ATTESTATION_V1.
const DOMAIN_FLAG_ANCHOR_ATTESTATION_V1: u32 = constants.DOMAIN_FLAG_ANCHOR_ATTESTATION_V1;

/// Heap-allocated cursor state. Allocated by cursor_open, freed by cursor_close.
const CursorState = struct {
    txn: lmdb.Txn,
    cur: lmdb.Cursor,
    /// The op_pkh prefix this cursor is scoped to.  Copied at cursor_open.
    op_pkh: [OP_PKH_BYTES]u8,
    /// True immediately after seek, before the first pull.  The cursor is
    /// already positioned at the seek result; getCurrent() returns it without
    /// advancing.  Cleared on first pull.
    at_seek: bool,
};

pub const LmdbCellStore = struct {
    env: *lmdb.Env,
    allocator: std.mem.Allocator,
    dbi: lmdb.Dbi,
    /// P4a — sibling sub-DB recording spent cell_ids (host-side K1).
    dbi_spent: lmdb.Dbi,
    /// D-LC3 — secondary index sub-DB. Maintained automatically by doPut;
    /// `cellsByOwner` reads it via a cursor prefix-scan.
    dbi_by_owner: lmdb.Dbi,
    /// D-LC4 — forward state-DAG index. Maintained automatically by doPut;
    /// `cellsByPrevState` reads it via a cursor prefix-scan.
    dbi_by_prev_state: lmdb.Dbi,
    /// D-LC5 — anchor-status projection. NOT maintained by doPut; callers
    /// must explicitly mark pending/confirmed via `setAnchorStatus`. The
    /// default for an unmarked cell is "no anchor expected".
    dbi_anchor_status: lmdb.Dbi,
    /// D-LC5 follow-up (reorg-sweep substrate) — reverse index
    /// `cells_by_anchor_txid`. Maintained automatically by doPut when an
    /// anchor-attestation cell is stored. `sweepPendingAnchors` reads it
    /// via a cursor prefix-scan to find every target cell that was
    /// anchored by a given (reorged-away) txid.
    dbi_by_anchor_txid: lmdb.Dbi,
    /// D-LC5 follow-up (anchor-attestation schema v2 — height-keyed reorg
    /// substrate) — reverse index `cells_by_anchor_height`. Maintained
    /// automatically by doPut when an anchor-attestation cell is stored.
    /// `cellsByAnchorHeightRange` and `sweepReorgedFromHeight` cursor-scan
    /// this index to find every attestation cell whose anchor block lies
    /// in a rolled-back height range. Key uses BIG-ENDIAN encoding of
    /// `anchor_height` so LMDB lex-sort matches numeric sort.
    dbi_by_anchor_height: lmdb.Dbi,
    /// C4 (substrate-generalization) — `cells_by_type` index. Maintained
    /// automatically by doPut; `cellsByType` / `cellsByTypePrefix` read it via a
    /// cursor prefix-scan. The generic `cell.query(typeHash)` substrate primitive
    /// reads this instead of the oddjobz typed stores.
    dbi_by_type: lmdb.Dbi,
    /// W7.1 — operator prefix.  Zero bytes for single-tenant deployments.
    op_pkh: [OP_PKH_BYTES]u8,

    // ── Constructors ──────────────────────────────────────────────────────

    /// Single-tenant constructor.  op_pkh = all-zero bytes.
    /// All existing call sites use this form — no signature change.
    pub fn init(env: *lmdb.Env, allocator: std.mem.Allocator) StoreError!LmdbCellStore {
        return initInternal(env, allocator, [_]u8{0} ** OP_PKH_BYTES);
    }

    /// W7.1 — hosted-operator constructor.  `op_pkh` must be exactly
    /// OP_PKH_BYTES bytes (first 8 bytes of the operator's pubkey hash).
    pub fn initForOperator(
        env: *lmdb.Env,
        allocator: std.mem.Allocator,
        op_pkh: [OP_PKH_BYTES]u8,
    ) StoreError!LmdbCellStore {
        return initInternal(env, allocator, op_pkh);
    }

    fn initInternal(
        env: *lmdb.Env,
        allocator: std.mem.Allocator,
        op_pkh: [OP_PKH_BYTES]u8,
    ) StoreError!LmdbCellStore {
        var txn = env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();
        const dbi = txn.openDb("cells", .{ .create = true }) catch
            return error.persistence_failed;
        // P4a — `create:true` makes this lazy: existing envs that predate
        // the spent-set gain the sub-DB on first open with this version.
        const dbi_spent = txn.openDb("cells_spent", .{ .create = true }) catch
            return error.persistence_failed;
        // D-LC3 — secondary index. Lazily created on first init; existing
        // stores that predate this deliverable get the empty DB and start
        // populating it on the next put. For cells that pre-date this
        // deliverable and never get re-put, run the one-shot bin
        // `brain-backfill-cell-indices` (D-LC3 follow-up); the same
        // method is exposed on this struct as `backfillSecondaryIndices`.
        const dbi_by_owner = txn.openDb("cells_by_owner", .{ .create = true }) catch
            return error.persistence_failed;
        // D-LC4 — forward state-DAG index. Same lazy-creation posture.
        const dbi_by_prev_state = txn.openDb("cells_by_prev_state", .{ .create = true }) catch
            return error.persistence_failed;
        // D-LC5 — anchor-status projection. Same lazy-creation posture.
        const dbi_anchor_status = txn.openDb("cells_anchor_status", .{ .create = true }) catch
            return error.persistence_failed;
        // D-LC5 follow-up (reorg-sweep substrate) — `cells_by_anchor_txid`
        // reverse index. Same lazy-creation posture; envs that predate
        // this change gain the sub-DB on first open and start populating
        // it as new attestation cells arrive.
        const dbi_by_anchor_txid = txn.openDb("cells_by_anchor_txid", .{ .create = true }) catch
            return error.persistence_failed;
        // D-LC5 follow-up (anchor-attestation schema v2) —
        // `cells_by_anchor_height` reverse index. Same lazy-creation
        // posture; envs that predate the v2 cut gain the sub-DB on
        // first open and start populating it as new v2 attestation
        // cells arrive. v1 attestation cells (none exist in production
        // per project memory v1_production_is_test_data.md) would
        // populate the entry with whatever bytes happened to sit at
        // cell offset 320; that's pre-cutover data and not a concern.
        const dbi_by_anchor_height = txn.openDb("cells_by_anchor_height", .{ .create = true }) catch
            return error.persistence_failed;
        // C4 (substrate-generalization) — `cells_by_type` index. Same lazy-
        // creation posture; envs that predate it gain the sub-DB on first open
        // and start populating as new cells arrive. Pre-existing cells are
        // repaired by backfillSecondaryIndices (the one-shot bin).
        const dbi_by_type = txn.openDb("cells_by_type", .{ .create = true }) catch
            return error.persistence_failed;
        txn.commit() catch return error.persistence_failed;
        return .{
            .env = env,
            .allocator = allocator,
            .dbi = dbi,
            .dbi_spent = dbi_spent,
            .dbi_by_owner = dbi_by_owner,
            .dbi_by_prev_state = dbi_by_prev_state,
            .dbi_anchor_status = dbi_anchor_status,
            .dbi_by_anchor_txid = dbi_by_anchor_txid,
            .dbi_by_anchor_height = dbi_by_anchor_height,
            .dbi_by_type = dbi_by_type,
            .op_pkh = op_pkh,
        };
    }

    pub fn deinit(_: *LmdbCellStore) void {}

    pub fn store(self: *LmdbCellStore) cell_store_mod.CellStore {
        return .{ .ctx = @ptrCast(self), .vtable = &vtable };
    }

    // ── Key helpers ───────────────────────────────────────────────────────

    /// Build a 40-byte LMDB key: op_pkh (8B) ‖ hash (32B).
    fn buildKey(op_pkh: *const [OP_PKH_BYTES]u8, hash: *const [32]u8) [KEY_BYTES]u8 {
        var key: [KEY_BYTES]u8 = undefined;
        @memcpy(key[0..OP_PKH_BYTES], op_pkh);
        @memcpy(key[OP_PKH_BYTES..], hash);
        return key;
    }

    fn sha256(bytes: []const u8) [32]u8 {
        var out: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &out, .{});
        return out;
    }

    /// True if the given key slice (any length) starts with `op_pkh`.
    fn hasPrefix(key: []const u8, op_pkh: *const [OP_PKH_BYTES]u8) bool {
        if (key.len < OP_PKH_BYTES) return false;
        return std.mem.eql(u8, key[0..OP_PKH_BYTES], op_pkh);
    }

    // ── put ──────────────────────────────────────────────────────────────

    /// D-LC3 — build the 56-byte owner-index key: op_pkh ‖ owner_id ‖ hash.
    fn buildOwnerKey(
        op_pkh: *const [OP_PKH_BYTES]u8,
        owner_id: *const [OWNER_ID_BYTES]u8,
        hash: *const [32]u8,
    ) [OWNER_KEY_BYTES]u8 {
        var key: [OWNER_KEY_BYTES]u8 = undefined;
        @memcpy(key[0..OP_PKH_BYTES], op_pkh);
        @memcpy(key[OP_PKH_BYTES .. OP_PKH_BYTES + OWNER_ID_BYTES], owner_id);
        @memcpy(key[OP_PKH_BYTES + OWNER_ID_BYTES ..], hash);
        return key;
    }

    /// C4 — build the 72-byte type-index key: op_pkh ‖ type_hash ‖ cell_hash.
    fn buildTypeKey(
        op_pkh: *const [OP_PKH_BYTES]u8,
        type_hash: *const [TYPE_HASH_BYTES]u8,
        hash: *const [32]u8,
    ) [TYPE_KEY_BYTES]u8 {
        var key: [TYPE_KEY_BYTES]u8 = undefined;
        @memcpy(key[0..OP_PKH_BYTES], op_pkh);
        @memcpy(key[OP_PKH_BYTES .. OP_PKH_BYTES + TYPE_HASH_BYTES], type_hash);
        @memcpy(key[OP_PKH_BYTES + TYPE_HASH_BYTES ..], hash);
        return key;
    }

    /// D-LC4 — build the 72-byte prev-state-index key:
    /// op_pkh ‖ prev_state_hash ‖ cell_hash.
    fn buildPrevStateKey(
        op_pkh: *const [OP_PKH_BYTES]u8,
        prev_state_hash: *const [PREV_STATE_HASH_BYTES]u8,
        hash: *const [32]u8,
    ) [PREV_STATE_KEY_BYTES]u8 {
        var key: [PREV_STATE_KEY_BYTES]u8 = undefined;
        @memcpy(key[0..OP_PKH_BYTES], op_pkh);
        @memcpy(key[OP_PKH_BYTES .. OP_PKH_BYTES + PREV_STATE_HASH_BYTES], prev_state_hash);
        @memcpy(key[OP_PKH_BYTES + PREV_STATE_HASH_BYTES ..], hash);
        return key;
    }

    /// D-LC5 follow-up (reorg-sweep substrate) — build the 72-byte
    /// reverse-index key: op_pkh ‖ anchor_txid ‖ target_cell_hash.
    fn buildAnchorTxidKey(
        op_pkh: *const [OP_PKH_BYTES]u8,
        anchor_txid: *const [ATTESTATION_TXID_SIZE]u8,
        target_hash: *const [32]u8,
    ) [ANCHOR_TXID_KEY_BYTES]u8 {
        var key: [ANCHOR_TXID_KEY_BYTES]u8 = undefined;
        @memcpy(key[0..OP_PKH_BYTES], op_pkh);
        @memcpy(key[OP_PKH_BYTES .. OP_PKH_BYTES + ATTESTATION_TXID_SIZE], anchor_txid);
        @memcpy(key[OP_PKH_BYTES + ATTESTATION_TXID_SIZE ..], target_hash);
        return key;
    }

    /// D-LC5 follow-up (anchor-attestation schema v2) — build the 48-byte
    /// height-keyed reverse-index key:
    ///   op_pkh ‖ BE(anchor_height) ‖ target_cell_hash.
    /// `anchor_height` is encoded BIG-ENDIAN in the LMDB key so that
    /// lexicographic ordering equals numeric ordering (LMDB's
    /// `seek` + `step` then walks ascending heights naturally). The
    /// payload bytes inside the cell stay little-endian; this BE
    /// encoding is local to the LMDB key shape.
    fn buildAnchorHeightKey(
        op_pkh: *const [OP_PKH_BYTES]u8,
        anchor_height: u64,
        target_hash: *const [32]u8,
    ) [ANCHOR_HEIGHT_KEY_BYTES]u8 {
        var key: [ANCHOR_HEIGHT_KEY_BYTES]u8 = undefined;
        @memcpy(key[0..OP_PKH_BYTES], op_pkh);
        std.mem.writeInt(
            u64,
            key[OP_PKH_BYTES..][0..ATTESTATION_ANCHOR_HEIGHT_SIZE],
            anchor_height,
            .big,
        );
        @memcpy(key[OP_PKH_BYTES + ATTESTATION_ANCHOR_HEIGHT_SIZE ..], target_hash);
        return key;
    }

    fn doPut(self: *LmdbCellStore, cell: *const [CELL_BYTES]u8) StoreError![32]u8 {
        const hash = sha256(cell);
        const key = buildKey(&self.op_pkh, &hash);

        // D-LC3 — pre-compute the owner-index key from the cell header.
        var owner_id: [OWNER_ID_BYTES]u8 = undefined;
        @memcpy(&owner_id, cell[OWNER_ID_OFFSET_IN_CELL .. OWNER_ID_OFFSET_IN_CELL + OWNER_ID_BYTES]);
        const owner_key = buildOwnerKey(&self.op_pkh, &owner_id, &hash);

        // D-LC4 — pre-compute the prev-state-index key from the cell header.
        // Cells with all-zero prev_state_hash (genesis cells) still get an
        // index entry; callers can either skip the all-zero prev when walking
        // or use it to find chain roots cheaply.
        var prev_state: [PREV_STATE_HASH_BYTES]u8 = undefined;
        @memcpy(&prev_state, cell[PREV_STATE_HASH_OFFSET_IN_CELL .. PREV_STATE_HASH_OFFSET_IN_CELL + PREV_STATE_HASH_BYTES]);
        const prev_state_key = buildPrevStateKey(&self.op_pkh, &prev_state, &hash);

        // C4 — pre-compute the type-index key from the cell header (bytes 30..62).
        var type_hash: [TYPE_HASH_BYTES]u8 = undefined;
        @memcpy(&type_hash, cell[TYPE_HASH_OFFSET_IN_CELL .. TYPE_HASH_OFFSET_IN_CELL + TYPE_HASH_BYTES]);
        const type_key = buildTypeKey(&self.op_pkh, &type_hash, &hash);

        // D-LC5 follow-up — peek the cell's domain_flag (u32 LE @ offset 24).
        // When it matches the canonical anchor-attestation wire value, we
        // extract `targetCellId` from the payload (first 32B at offset 256
        // per anchorAttestationSchemaV1) and flip that target's anchor
        // status to .confirmed inside the same write txn. This makes the
        // attestation cell and the projection update atomic — the same
        // posture as the D-LC3 / D-LC4 secondary indices. Pinned to
        // schema v1; if anchorAttestationSchemaV1's targetCellId offset
        // moves, this dispatch must be updated together with the schema.
        const domain_flag = std.mem.readInt(
            u32,
            cell[DOMAIN_FLAG_OFFSET_IN_CELL..][0..DOMAIN_FLAG_SIZE_IN_CELL],
            .little,
        );
        const is_attestation = domain_flag == DOMAIN_FLAG_ANCHOR_ATTESTATION_V1;
        var target_cell_id: [ATTESTATION_TARGET_CELL_ID_SIZE]u8 = undefined;
        var anchor_txid: [ATTESTATION_TXID_SIZE]u8 = undefined;
        var anchor_txid_key: [ANCHOR_TXID_KEY_BYTES]u8 = undefined;
        var anchor_height: u64 = 0;
        var anchor_height_key: [ANCHOR_HEIGHT_KEY_BYTES]u8 = undefined;
        if (is_attestation) {
            @memcpy(
                &target_cell_id,
                cell[ATTESTATION_TARGET_CELL_ID_OFFSET .. ATTESTATION_TARGET_CELL_ID_OFFSET + ATTESTATION_TARGET_CELL_ID_SIZE],
            );
            // D-LC5 follow-up (reorg-sweep substrate) — also extract the
            // txid (anchorAttestationSchemaV2 field 1, u256, payload offset
            // 32 → cell offset 288) so we can write the txid reverse-index
            // entry in the same write txn as the primary cell.
            @memcpy(
                &anchor_txid,
                cell[ATTESTATION_TXID_OFFSET .. ATTESTATION_TXID_OFFSET + ATTESTATION_TXID_SIZE],
            );
            anchor_txid_key = buildAnchorTxidKey(&self.op_pkh, &anchor_txid, &target_cell_id);
            // D-LC5 follow-up (schema v2) — extract anchor_height
            // (anchorAttestationSchemaV2 field 2, u64 LE, payload offset
            // 64 → cell offset 320) and build the height-keyed reverse-
            // index key. Height is read LE from the cell (payload
            // encoding) and immediately re-encoded BE into the LMDB
            // key by buildAnchorHeightKey — see that helper for the
            // rationale on the BE-in-key / LE-in-payload split.
            anchor_height = std.mem.readInt(
                u64,
                cell[ATTESTATION_ANCHOR_HEIGHT_OFFSET..][0..ATTESTATION_ANCHOR_HEIGHT_SIZE],
                .little,
            );
            anchor_height_key = buildAnchorHeightKey(&self.op_pkh, anchor_height, &target_cell_id);
        }

        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;

        _ = txn.get(self.dbi, &key) catch |e| {
            if (e != error.not_found) {
                txn.abort();
                return error.persistence_failed;
            }
            var padded: [VALUE_BYTES]u8 = [_]u8{0} ** VALUE_BYTES;
            @memcpy(padded[0..CELL_BYTES], cell);
            txn.put(self.dbi, &key, &padded, .{}) catch {
                txn.abort();
                return error.persistence_failed;
            };
            // D-LC3 — write the owner-index entry inside the same txn so
            // the primary cell and the index land atomically. Empty value;
            // the key alone carries the (owner_id, hash) mapping. Idempotent
            // on retry: writing the same 56-byte key twice is a no-op since
            // the value is empty.
            txn.put(self.dbi_by_owner, &owner_key, &[_]u8{}, .{}) catch {
                txn.abort();
                return error.persistence_failed;
            };
            // D-LC4 — same posture for the forward state-DAG index.
            txn.put(self.dbi_by_prev_state, &prev_state_key, &[_]u8{}, .{}) catch {
                txn.abort();
                return error.persistence_failed;
            };
            // C4 — same posture for the cells_by_type index.
            txn.put(self.dbi_by_type, &type_key, &[_]u8{}, .{}) catch {
                txn.abort();
                return error.persistence_failed;
            };
            // D-LC5 follow-up — attestation observer. If this cell is an
            // anchor-attestation, flip the target cell's status to
            // .confirmed inside the same txn AND write the txid →
            // target-cell reverse-index entry that the reorg sweep
            // needs. Both the projection update and the index write
            // commit atomically with the attestation cell itself.
            if (is_attestation) {
                self.writeAnchorStatusInTxn(&txn, &target_cell_id, .confirmed) catch {
                    txn.abort();
                    return error.persistence_failed;
                };
                txn.put(self.dbi_by_anchor_txid, &anchor_txid_key, &[_]u8{}, .{}) catch {
                    txn.abort();
                    return error.persistence_failed;
                };
                // D-LC5 follow-up (schema v2) — height-keyed reverse index
                // (op_pkh ‖ BE(anchor_height) ‖ target_hash). Empty value;
                // idempotent on retry.
                txn.put(self.dbi_by_anchor_height, &anchor_height_key, &[_]u8{}, .{}) catch {
                    txn.abort();
                    return error.persistence_failed;
                };
            }
            txn.commit() catch return error.persistence_failed;
            return hash;
        };
        // Cell already present in main DB. Backfill both indices
        // opportunistically — covers cells that were written before D-LC3
        // / D-LC4 shipped. The puts are idempotent so this is safe to
        // re-run.
        txn.put(self.dbi_by_owner, &owner_key, &[_]u8{}, .{}) catch {
            txn.abort();
            return error.persistence_failed;
        };
        txn.put(self.dbi_by_prev_state, &prev_state_key, &[_]u8{}, .{}) catch {
            txn.abort();
            return error.persistence_failed;
        };
        // C4 — opportunistic backfill of the cells_by_type index too.
        txn.put(self.dbi_by_type, &type_key, &[_]u8{}, .{}) catch {
            txn.abort();
            return error.persistence_failed;
        };
        // D-LC5 follow-up — re-puts of an attestation cell still re-assert
        // .confirmed on the target AND re-assert the reverse-index entries.
        // Cell content is hash-bound, so a re-put always carries the same
        // (targetCellId, txid, anchor_height); all three writes are
        // idempotent (same key+value).
        if (is_attestation) {
            self.writeAnchorStatusInTxn(&txn, &target_cell_id, .confirmed) catch {
                txn.abort();
                return error.persistence_failed;
            };
            txn.put(self.dbi_by_anchor_txid, &anchor_txid_key, &[_]u8{}, .{}) catch {
                txn.abort();
                return error.persistence_failed;
            };
            // D-LC5 follow-up (schema v2) — re-assert the height-keyed
            // reverse-index entry too.
            txn.put(self.dbi_by_anchor_height, &anchor_height_key, &[_]u8{}, .{}) catch {
                txn.abort();
                return error.persistence_failed;
            };
        }
        txn.commit() catch return error.persistence_failed;
        return hash;
    }

    // ── cellsByOwner (D-LC3) ──────────────────────────────────────────────

    /// Enumerate all cell hashes stored for the given owner_id under this
    /// store's op_pkh. Returns an owned slice the caller must free. Pure
    /// cursor prefix-scan; O(n) in the number of matching cells, no
    /// secondary lookups.
    pub fn cellsByOwner(
        self: *LmdbCellStore,
        allocator: std.mem.Allocator,
        owner_id: *const [OWNER_ID_BYTES]u8,
    ) StoreError![][32]u8 {
        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();
        var cur = txn.openCursor(self.dbi_by_owner) catch return error.persistence_failed;
        defer cur.close();

        // Prefix = op_pkh ‖ owner_id (24 bytes). Anything starting with this
        // matches; the cell_hash is the last 32 bytes of each key.
        var prefix: [OP_PKH_BYTES + OWNER_ID_BYTES]u8 = undefined;
        @memcpy(prefix[0..OP_PKH_BYTES], &self.op_pkh);
        @memcpy(prefix[OP_PKH_BYTES..], owner_id);

        var out = std.ArrayList([32]u8){};
        errdefer out.deinit(allocator);

        var entry = cur.seek(&prefix) catch null;
        while (entry) |e| {
            if (e.key.len != OWNER_KEY_BYTES) break;
            if (!std.mem.eql(u8, e.key[0..prefix.len], &prefix)) break;
            var hash: [32]u8 = undefined;
            @memcpy(&hash, e.key[prefix.len..]);
            out.append(allocator, hash) catch return error.out_of_memory;
            entry = cur.next() catch null;
        }
        return out.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    // ── cellsByType / cellsByTypePrefix (C4 substrate-generalization) ─────

    /// Enumerate every cell hash whose 8|8|8|8 typeHash matches `type_prefix`
    /// (under this store's op_pkh), where `type_prefix` is 0..32 bytes of the
    /// leading typeHash segments — the "index template". 32 bytes = exact
    /// typeHash; 8 = namespace; 16 = namespace+domain; 24 = +sub-type. An empty
    /// prefix enumerates ALL of this operator's cells. Pure cursor prefix-scan;
    /// returns an owned slice the caller must free.
    pub fn cellsByTypePrefix(
        self: *LmdbCellStore,
        allocator: std.mem.Allocator,
        type_prefix: []const u8,
    ) StoreError![][32]u8 {
        // Defensive: a template prefix can't be longer than the 32-byte typeHash.
        // (invalid_cell is the store's catch-all "bad input" — kept in the
        // existing StoreError set to avoid rippling a new variant through every
        // exhaustive switch.)
        if (type_prefix.len > TYPE_HASH_BYTES) return error.invalid_cell;
        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();
        var cur = txn.openCursor(self.dbi_by_type) catch return error.persistence_failed;
        defer cur.close();

        // Prefix = op_pkh ‖ type_prefix (8 + 0..32 bytes). The cell_hash is the
        // last 32 bytes of each (full 72-byte) key.
        var prefix_buf: [OP_PKH_BYTES + TYPE_HASH_BYTES]u8 = undefined;
        @memcpy(prefix_buf[0..OP_PKH_BYTES], &self.op_pkh);
        @memcpy(prefix_buf[OP_PKH_BYTES .. OP_PKH_BYTES + type_prefix.len], type_prefix);
        const prefix = prefix_buf[0 .. OP_PKH_BYTES + type_prefix.len];

        var out = std.ArrayList([32]u8){};
        errdefer out.deinit(allocator);

        var entry = cur.seek(prefix) catch null;
        while (entry) |e| {
            if (e.key.len != TYPE_KEY_BYTES) break;
            if (!std.mem.eql(u8, e.key[0..prefix.len], prefix)) break;
            var hash: [32]u8 = undefined;
            @memcpy(&hash, e.key[OP_PKH_BYTES + TYPE_HASH_BYTES ..]);
            out.append(allocator, hash) catch return error.out_of_memory;
            entry = cur.next() catch null;
        }
        return out.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    /// Enumerate every cell hash of exactly `type_hash` under this store's
    /// op_pkh. Convenience wrapper over `cellsByTypePrefix` with the full
    /// 32-byte typeHash. Returns an owned slice the caller must free.
    pub fn cellsByType(
        self: *LmdbCellStore,
        allocator: std.mem.Allocator,
        type_hash: *const [TYPE_HASH_BYTES]u8,
    ) StoreError![][32]u8 {
        return self.cellsByTypePrefix(allocator, type_hash[0..]);
    }

    // ── cellsByPrevState (D-LC4) ─────────────────────────────────────────

    /// Enumerate every cell hash whose `prev_state_hash` header field equals
    /// the given 32-byte hash, scoped to this store's `op_pkh`. These are the
    /// immediate forward-DAG children of the given state. To walk a chain
    /// forward, call repeatedly with each returned hash. Returns an owned
    /// slice the caller must free.
    pub fn cellsByPrevState(
        self: *LmdbCellStore,
        allocator: std.mem.Allocator,
        prev_state_hash: *const [PREV_STATE_HASH_BYTES]u8,
    ) StoreError![][32]u8 {
        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();
        var cur = txn.openCursor(self.dbi_by_prev_state) catch return error.persistence_failed;
        defer cur.close();

        // Prefix = op_pkh ‖ prev_state_hash (40 bytes).
        var prefix: [OP_PKH_BYTES + PREV_STATE_HASH_BYTES]u8 = undefined;
        @memcpy(prefix[0..OP_PKH_BYTES], &self.op_pkh);
        @memcpy(prefix[OP_PKH_BYTES..], prev_state_hash);

        var out = std.ArrayList([32]u8){};
        errdefer out.deinit(allocator);

        var entry = cur.seek(&prefix) catch null;
        while (entry) |e| {
            if (e.key.len != PREV_STATE_KEY_BYTES) break;
            if (!std.mem.eql(u8, e.key[0..prefix.len], &prefix)) break;
            var hash: [32]u8 = undefined;
            @memcpy(&hash, e.key[prefix.len..]);
            out.append(allocator, hash) catch return error.out_of_memory;
            entry = cur.next() catch null;
        }
        return out.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    /// D-LC4 follow-up — paginated variant of `cellsByPrevState`. Cursor seeks
    /// inside the `(op_pkh ‖ prev_state_hash)` prefix and returns up to
    /// `limit` cell hashes in LMDB lex order. If `after` is provided, the
    /// enumeration starts STRICTLY AFTER that hash (i.e. the cell whose hash
    /// equals `after` is NOT included in the page; it's expected to be the
    /// last hash from the previous page).
    ///
    /// `has_more` is `true` iff the underlying enumeration has at least one
    /// more entry under the same `(op_pkh, prev_state_hash)` prefix beyond
    /// the last hash returned — the caller uses it to decide whether to emit
    /// an `x-next-cursor` response header.
    ///
    /// LMDB's `seek` (`MDB_SET_RANGE`) returns the first key `>= target`. To
    /// implement "strictly after X" we seek to `prefix ‖ X` and, if the
    /// returned key matches X exactly, advance the cursor once. This is the
    /// cheapest seek that works with LMDB's cursor API; alternatives like
    /// "increment-by-1 then seek" run into byte-wraparound edge cases that
    /// this skip-on-equal pattern sidesteps.
    /// D-LC4 follow-up — re-export of the canonical vtable type so
    /// direct callers of the impl and vtable callers share the same
    /// nominal type.
    pub const PrevStateRangeResult = cell_store_mod.PrevStateRangeResult;

    pub fn cellsByPrevStateRange(
        self: *LmdbCellStore,
        allocator: std.mem.Allocator,
        prev_state_hash: *const [PREV_STATE_HASH_BYTES]u8,
        after: ?*const [32]u8,
        limit: usize,
    ) StoreError!PrevStateRangeResult {
        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();
        var cur = txn.openCursor(self.dbi_by_prev_state) catch return error.persistence_failed;
        defer cur.close();

        // Prefix = op_pkh ‖ prev_state_hash (40 bytes).
        var prefix: [OP_PKH_BYTES + PREV_STATE_HASH_BYTES]u8 = undefined;
        @memcpy(prefix[0..OP_PKH_BYTES], &self.op_pkh);
        @memcpy(prefix[OP_PKH_BYTES..], prev_state_hash);

        var out = std.ArrayList([32]u8){};
        errdefer out.deinit(allocator);

        if (limit == 0) {
            return .{
                .hashes = out.toOwnedSlice(allocator) catch return error.out_of_memory,
                .has_more = false,
            };
        }

        // Seek target — without `after`, seek to the prefix; with `after`,
        // seek to (prefix ‖ after) so we land at/just-past the `after` cell.
        var entry: ?lmdb.CursorEntry = blk: {
            if (after) |after_hash| {
                var seek_key: [PREV_STATE_KEY_BYTES]u8 = undefined;
                @memcpy(seek_key[0..prefix.len], &prefix);
                @memcpy(seek_key[prefix.len..], after_hash);
                var e = cur.seek(&seek_key) catch break :blk null;
                // If we landed exactly on `after`, advance — the contract is
                // "strictly after". A key length mismatch can't happen for a
                // well-formed prev-state DB, but bail safely if it does.
                if (e) |hit| {
                    if (hit.key.len == PREV_STATE_KEY_BYTES and
                        std.mem.eql(u8, hit.key, &seek_key))
                    {
                        e = cur.next() catch null;
                    }
                }
                break :blk e;
            } else {
                break :blk cur.seek(&prefix) catch null;
            }
        };

        while (entry) |e| {
            if (out.items.len >= limit) break;
            if (e.key.len != PREV_STATE_KEY_BYTES) break;
            if (!std.mem.eql(u8, e.key[0..prefix.len], &prefix)) break;
            var hash: [32]u8 = undefined;
            @memcpy(&hash, e.key[prefix.len..]);
            out.append(allocator, hash) catch return error.out_of_memory;
            entry = cur.next() catch null;
        }

        // has_more = there is at least one more entry under the prefix beyond
        // the last hash we just collected. `entry` is currently positioned at
        // the next-untaken entry (or null if exhausted). We trust the cursor
        // position rather than re-seeking.
        const has_more: bool = if (entry) |e|
            e.key.len == PREV_STATE_KEY_BYTES and
                std.mem.eql(u8, e.key[0..prefix.len], &prefix)
        else
            false;

        return .{
            .hashes = out.toOwnedSlice(allocator) catch return error.out_of_memory,
            .has_more = has_more,
        };
    }

    // ── cellsByAnchorTxid (D-LC5 follow-up, reorg-sweep substrate) ───────

    /// Enumerate every target_cell_hash that was anchored by the given
    /// `anchor_txid` under this store's `op_pkh`. Pure cursor prefix-scan
    /// against the `cells_by_anchor_txid` reverse index — O(n) in the
    /// number of attestations recorded for the txid, no secondary lookups.
    /// Returns an owned slice the caller must free.
    ///
    /// Used by `sweepPendingAnchors` (this file) and by the cartridge
    /// reorg hook (separate PR) to find every cell that needs its anchor
    /// projection re-evaluated when `anchor_txid` is reorged away.
    pub fn cellsByAnchorTxid(
        self: *LmdbCellStore,
        allocator: std.mem.Allocator,
        anchor_txid: *const [ATTESTATION_TXID_SIZE]u8,
    ) StoreError![][32]u8 {
        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();
        var cur = txn.openCursor(self.dbi_by_anchor_txid) catch return error.persistence_failed;
        defer cur.close();

        // Prefix = op_pkh ‖ anchor_txid (40 bytes). Anything starting with
        // this matches; the target_cell_hash is the last 32 bytes.
        var prefix: [OP_PKH_BYTES + ATTESTATION_TXID_SIZE]u8 = undefined;
        @memcpy(prefix[0..OP_PKH_BYTES], &self.op_pkh);
        @memcpy(prefix[OP_PKH_BYTES..], anchor_txid);

        var out = std.ArrayList([32]u8){};
        errdefer out.deinit(allocator);

        var entry = cur.seek(&prefix) catch null;
        while (entry) |e| {
            if (e.key.len != ANCHOR_TXID_KEY_BYTES) break;
            if (!std.mem.eql(u8, e.key[0..prefix.len], &prefix)) break;
            var hash: [32]u8 = undefined;
            @memcpy(&hash, e.key[prefix.len..]);
            out.append(allocator, hash) catch return error.out_of_memory;
            entry = cur.next() catch null;
        }
        return out.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    // ── Anchor status projection (D-LC5) ─────────────────────────────────

    fn buildAnchorKey(
        op_pkh: *const [OP_PKH_BYTES]u8,
        hash: *const [32]u8,
    ) [ANCHOR_KEY_BYTES]u8 {
        var key: [ANCHOR_KEY_BYTES]u8 = undefined;
        @memcpy(key[0..OP_PKH_BYTES], op_pkh);
        @memcpy(key[OP_PKH_BYTES..], hash);
        return key;
    }

    /// Set the anchor status for a cell. Idempotent — re-marking with the
    /// same status is a no-op (LMDB put of the same key+value). Caller
    /// owns the state machine: typically markPending happens at mint time,
    /// markConfirmed when the anchor-attestation cell lands.
    pub fn setAnchorStatus(
        self: *LmdbCellStore,
        hash: *const [32]u8,
        status: AnchorStatus,
    ) StoreError!void {
        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        self.writeAnchorStatusInTxn(&txn, hash, status) catch {
            txn.abort();
            return error.persistence_failed;
        };
        txn.commit() catch return error.persistence_failed;
    }

    /// D-LC5 follow-up — write the anchor status using a caller-owned txn.
    /// Used by `doPut` to flip pending → confirmed for an attestation's
    /// target cell inside the same write txn as the attestation cell's
    /// primary put, so the projection update is atomic with the cell that
    /// caused it. The caller is responsible for txn lifecycle (commit/
    /// abort); this function only writes.
    fn writeAnchorStatusInTxn(
        self: *LmdbCellStore,
        txn: *lmdb.Txn,
        hash: *const [32]u8,
        status: AnchorStatus,
    ) StoreError!void {
        const key = buildAnchorKey(&self.op_pkh, hash);
        const value = [_]u8{@intFromEnum(status)};
        txn.put(self.dbi_anchor_status, &key, &value, .{}) catch
            return error.persistence_failed;
    }

    /// Read the anchor status. Returns null when the cell has no entry —
    /// the default for cells minted outside an anchor flow.
    pub fn getAnchorStatus(
        self: *LmdbCellStore,
        hash: *const [32]u8,
    ) ?AnchorStatus {
        const key = buildAnchorKey(&self.op_pkh, hash);
        var txn = self.env.beginTxn(.read_only) catch return null;
        defer txn.abort();
        const value = txn.get(self.dbi_anchor_status, &key) catch return null;
        if (value.len < 1) return null;
        return switch (value[0]) {
            0 => AnchorStatus.pending,
            1 => AnchorStatus.confirmed,
            else => null,
        };
    }

    /// Clear the anchor status for a cell. Used to roll back a pending
    /// mark when the anchor TX is rejected (chain reorg, double-spend).
    /// Not-found is treated as success (idempotent delete).
    pub fn clearAnchorStatus(
        self: *LmdbCellStore,
        hash: *const [32]u8,
    ) StoreError!void {
        const key = buildAnchorKey(&self.op_pkh, hash);
        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();
        try self.clearAnchorStatusInTxn(&txn, &key);
        txn.commit() catch return error.persistence_failed;
    }

    /// D-LC5 follow-up (reorg-sweep substrate) — caller-owned-txn variant of
    /// `clearAnchorStatus`. Used by `sweepPendingAnchors` to clear many
    /// entries inside a single write txn. `key` must be a pre-built 40-byte
    /// anchor-status key (op_pkh ‖ cell_hash); building it outside lets
    /// the caller avoid copying op_pkh repeatedly. Not-found is treated
    /// as success.
    fn clearAnchorStatusInTxn(
        self: *LmdbCellStore,
        txn: *lmdb.Txn,
        key: *const [ANCHOR_KEY_BYTES]u8,
    ) StoreError!void {
        txn.del(self.dbi_anchor_status, key, null) catch |e| {
            if (e != error.not_found) return error.persistence_failed;
        };
    }

    /// D-LC5 follow-up (reorg-sweep substrate) — read the anchor status
    /// for a cell using a caller-owned (typically read_write) txn. Mirrors
    /// `getAnchorStatus` but lets the sweep walk every target and clear
    /// inside a single transaction. Returns null when no entry exists.
    fn getAnchorStatusInTxn(
        self: *LmdbCellStore,
        txn: *lmdb.Txn,
        hash: *const [32]u8,
    ) ?AnchorStatus {
        const key = buildAnchorKey(&self.op_pkh, hash);
        const value = txn.get(self.dbi_anchor_status, &key) catch return null;
        if (value.len < 1) return null;
        return switch (value[0]) {
            0 => AnchorStatus.pending,
            1 => AnchorStatus.confirmed,
            else => null,
        };
    }

    /// D-LC5 follow-up (reorg-sweep substrate) — sweep result. Now lives
    /// at the vtable level (`cell_store_mod.SweepResult`); re-exported
    /// here so callers that imported it through the impl module
    /// (`LmdbCellStore.SweepResult`) keep compiling unchanged.
    pub const SweepResult = cell_store_mod.SweepResult;

    /// D-LC5 follow-up (reorg-sweep substrate) — clear every `.pending`
    /// anchor projection that was bound to `anchor_txid`. Reads the reverse
    /// index `cells_by_anchor_txid`, walks every recorded target cell, and
    /// inside a single write txn deletes those whose status is `.pending`.
    /// Returns counts of cleared vs preserved entries so callers can
    /// log/audit the sweep.
    ///
    /// Semantic: `.confirmed` is NOT cleared by reorg. Past finality
    /// requires explicit invalidation; silently rolling back a confirmed
    /// projection on every transient reorg would mask real on-chain
    /// changes from downstream consumers. Pending only.
    ///
    /// Idempotent: a second call on the same txid with the same projection
    /// state returns (0, kept) — the first call cleared every pending it
    /// could find. The reverse-index entries themselves are NOT removed
    /// (the attestation cell remains as a historical record); only the
    /// derived anchor-status projection is rolled back.
    pub fn sweepPendingAnchors(
        self: *LmdbCellStore,
        anchor_txid: *const [ATTESTATION_TXID_SIZE]u8,
    ) StoreError!SweepResult {
        // Two-phase: (1) read every target hash for this txid via the
        // reverse index in a short read-only txn, then (2) reopen a
        // write txn that walks the gathered list, reads each entry's
        // current status, and clears the pending ones. Splitting the
        // phases avoids holding a cursor open across writes to a
        // sibling sub-DB (mdb_del can invalidate cursors at the page
        // level even across sub-DBs in some configurations). The
        // operation is still atomic from the caller's perspective:
        // the write txn either commits all clears together or aborts.
        const targets = try self.cellsByAnchorTxid(self.allocator, anchor_txid);
        defer self.allocator.free(targets);

        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();

        var swept: u32 = 0;
        var kept: u32 = 0;

        for (targets) |target_hash| {
            const status = self.getAnchorStatusInTxn(&txn, &target_hash);
            switch (status orelse AnchorStatus.confirmed) {
                .pending => {
                    const anchor_key = buildAnchorKey(&self.op_pkh, &target_hash);
                    try self.clearAnchorStatusInTxn(&txn, &anchor_key);
                    swept += 1;
                },
                .confirmed => {
                    // Confirmed entries are preserved across reorg — past
                    // finality requires explicit invalidation. The
                    // "status is null" case (cell has no projection
                    // entry to begin with) falls into this branch via
                    // `orelse .confirmed` above: nothing to clear.
                    kept += 1;
                },
            }
        }

        txn.commit() catch return error.persistence_failed;
        return .{ .swept = swept, .kept = kept };
    }

    // ── cellsByAnchorHeightRange (schema v2 — height-keyed reorg substrate) ──

    /// D-LC5 follow-up (schema v2) — re-export the canonical
    /// `AnchorHeightEntry` shape from cell_store_mod so direct callers
    /// of the impl and vtable callers share the same nominal type.
    pub const AnchorHeightEntry = cell_store_mod.AnchorHeightEntry;

    /// D-LC5 follow-up (schema v2) — enumerate every target_cell_hash whose
    /// `anchor_height` lies in the inclusive range `[low, high]`, scoped to
    /// this store's `op_pkh`. Pure cursor range-scan against the
    /// `cells_by_anchor_height` reverse index — O(n) in the number of
    /// matching attestations, no secondary lookups. Returns an owned slice
    /// the caller must free.
    ///
    /// Ordering: ascending by `anchor_height` (LMDB lex-sort = numeric
    /// sort thanks to the BE encoding of height in the key). Within a
    /// single height, secondary order is lexicographic on target hash —
    /// callers that care about a stable order across heights can rely
    /// on the primary height-ascending sort.
    ///
    /// `low > high` returns an empty slice (caller error; no need to
    /// raise — empty is the right answer for an empty range).
    pub fn cellsByAnchorHeightRange(
        self: *LmdbCellStore,
        allocator: std.mem.Allocator,
        height_low_inclusive: u64,
        height_high_inclusive: u64,
    ) StoreError![]AnchorHeightEntry {
        var out = std.ArrayList(AnchorHeightEntry){};
        errdefer out.deinit(allocator);

        if (height_low_inclusive > height_high_inclusive) {
            return out.toOwnedSlice(allocator) catch return error.out_of_memory;
        }

        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();
        var cur = txn.openCursor(self.dbi_by_anchor_height) catch return error.persistence_failed;
        defer cur.close();

        // Seek key = op_pkh ‖ BE(low) ‖ 0x00*32. Any real index entry at
        // height==low for some target_hash will lex-sort >= this prefix;
        // the seek positions us at the first entry whose key bytes are
        // >= the seek key. The cursor then walks forward in ascending
        // (height, target_hash) order until either the op_pkh prefix
        // breaks (we've fallen off this operator's range) or we
        // overshoot `height_high_inclusive`.
        var seek_key: [ANCHOR_HEIGHT_KEY_BYTES]u8 = undefined;
        @memcpy(seek_key[0..OP_PKH_BYTES], &self.op_pkh);
        std.mem.writeInt(
            u64,
            seek_key[OP_PKH_BYTES..][0..ATTESTATION_ANCHOR_HEIGHT_SIZE],
            height_low_inclusive,
            .big,
        );
        @memset(seek_key[OP_PKH_BYTES + ATTESTATION_ANCHOR_HEIGHT_SIZE ..], 0);

        var entry = cur.seek(&seek_key) catch null;
        while (entry) |e| {
            if (e.key.len != ANCHOR_HEIGHT_KEY_BYTES) break;
            // Bail on operator-prefix break.
            if (!std.mem.eql(u8, e.key[0..OP_PKH_BYTES], &self.op_pkh)) break;
            // Decode the height from the key (BE) and stop once we
            // exceed the upper bound — LMDB's lex order means every
            // subsequent entry has height >= this one.
            const h = std.mem.readInt(
                u64,
                e.key[OP_PKH_BYTES..][0..ATTESTATION_ANCHOR_HEIGHT_SIZE],
                .big,
            );
            if (h > height_high_inclusive) break;

            var hash: [32]u8 = undefined;
            @memcpy(&hash, e.key[OP_PKH_BYTES + ATTESTATION_ANCHOR_HEIGHT_SIZE ..]);
            out.append(allocator, .{ .height = h, .cell_hash = hash }) catch
                return error.out_of_memory;

            entry = cur.next() catch null;
        }
        return out.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    // ── sweepReorgedFromHeight (schema v2 — height-keyed reorg substrate) ─

    /// D-LC5 follow-up (schema v2) — sweep every `.pending` anchor
    /// projection whose attestation cell was anchored at a height >=
    /// `rollback_from_height`. Returns the same shape as
    /// `sweepPendingAnchors`: (swept, kept) counts.
    ///
    /// Semantics mirror `sweepPendingAnchors` exactly:
    ///   - `.confirmed` projections are NOT cleared. Past finality
    ///     requires explicit invalidation, not silent reorg rollback.
    ///   - Cells with no anchor-status entry (null) are counted as
    ///     `kept` (nothing to clear).
    ///   - Idempotent: a second call returns (0, kept).
    ///   - Reverse-index entries themselves are NOT removed (the
    ///     attestation cell remains as a historical record); only the
    ///     derived anchor-status projection is rolled back.
    ///
    /// Heights covered: inclusive lower bound. The typical caller is
    /// the cartridge reorg hook, which knows the highest block height
    /// that was rolled back and passes the next-lowest reorged block
    /// (so everything from that height upward is candidate for
    /// pending rollback).
    pub fn sweepReorgedFromHeight(
        self: *LmdbCellStore,
        rollback_from_height: u64,
    ) StoreError!SweepResult {
        // Two-phase mirror of sweepPendingAnchors: gather targets in a
        // read txn so the cursor is closed before the write txn opens,
        // then walk-and-clear in a single write txn. The upper bound
        // is std.math.maxInt(u64) — every height at-or-above the
        // rollback floor.
        const entries = try self.cellsByAnchorHeightRange(
            self.allocator,
            rollback_from_height,
            std.math.maxInt(u64),
        );
        defer self.allocator.free(entries);

        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();

        var swept: u32 = 0;
        var kept: u32 = 0;

        for (entries) |e| {
            const status = self.getAnchorStatusInTxn(&txn, &e.cell_hash);
            switch (status orelse AnchorStatus.confirmed) {
                .pending => {
                    const anchor_key = buildAnchorKey(&self.op_pkh, &e.cell_hash);
                    try self.clearAnchorStatusInTxn(&txn, &anchor_key);
                    swept += 1;
                },
                .confirmed => {
                    // Confirmed projections survive reorg by design;
                    // null projections fall through to this branch via
                    // `orelse .confirmed` and also count as kept.
                    kept += 1;
                },
            }
        }

        txn.commit() catch return error.persistence_failed;
        return .{ .swept = swept, .kept = kept };
    }

    // ── backfillSecondaryIndices (D-LC3 follow-up) ────────────────────────

    /// D-LC3 follow-up — one-shot backfill report. Counters reflect index
    /// puts ATTEMPTED, not unique inserts. LMDB puts of (same key, empty
    /// value) are idempotent no-ops at the storage layer, so the counters
    /// double as a per-shape census of cells visited under this op_pkh:
    ///   - `owner_index_writes` / `prev_state_index_writes` == cells visited
    ///   - `anchor_status_writes` / `anchor_txid_index_writes` == attestation
    ///     cells visited (subset of all cells)
    /// Treating the counter as "attempts" keeps the implementation simple and
    /// the report meaningful for the operator running the migration —
    /// distinguishing first-write from no-op writes would require a get-
    /// before-put per index entry, doubling the LMDB cost for no observable
    /// gain (the indices end in the same state either way).
    pub const BackfillReport = struct {
        cells_visited: u32,
        owner_index_writes: u32,
        prev_state_index_writes: u32,
        anchor_txid_index_writes: u32,
        /// D-LC5 follow-up (schema v2) — count of height-keyed reverse-
        /// index writes attempted. == anchor_txid_index_writes by
        /// construction (every attestation gets both indices), but
        /// reported separately so an operator can confirm both indices
        /// were repaired symmetrically.
        anchor_height_index_writes: u32,
        anchor_status_writes: u32,
        /// C4 — count of cells_by_type index entries written.
        type_index_writes: u32,
    };

    /// D-LC3 follow-up — one-shot backfill of every secondary index for
    /// cells already in the primary `cells` sub-DB. Idempotent: running it
    /// twice is a no-op (the index puts collapse on LMDB's same-key-same-
    /// value path). Operator-scoped — only cells under this store's
    /// `op_pkh` are visited; other operators' indices are untouched.
    ///
    /// Why this exists: D-LC3 (owner index), D-LC4 (prev-state index), and
    /// D-LC5 (anchor-status + reorg-substrate reverse index) all lazily
    /// open their sub-DBs (`create:true`) and are maintained by `doPut`
    /// for cells written on or after the deliverable's landing. Cells
    /// written BEFORE the indices existed have entries in `cells` but no
    /// corresponding entries in the secondary indices. `doPut` does
    /// opportunistic backfill when re-putting an existing cell, but cells
    /// that never get re-put stay out-of-band — hence this explicit one-
    /// shot.
    ///
    /// Concurrency: takes one short read_only txn (scan) followed by one
    /// read_write txn (writes). Existing brain code uses LMDB MVCC + a
    /// single-threaded reactor, so this is safe to invoke inline; the
    /// daemon's read-only txns continue to see the pre-backfill snapshot
    /// until commit. The brain process should not be holding a long-
    /// lived write txn at the same time.
    ///
    /// Two-phase pattern (scan-then-write): cursor slices on the
    /// primary `cells` sub-DB would be invalidated by puts into any
    /// sibling sub-DB at the page level (mdb_put can rebalance pages
    /// across sub-DBs in a single env). Walking the cursor in a
    /// read-only txn first and accumulating the per-cell index data
    /// into an in-memory list keeps cursor lifecycle and write txn
    /// strictly separate. The same posture
    /// `runtime/semantos-brain/src/migrate_entity_cells/main.zig` uses.
    pub fn backfillSecondaryIndices(self: *LmdbCellStore) StoreError!BackfillReport {
        var report = BackfillReport{
            .cells_visited = 0,
            .owner_index_writes = 0,
            .prev_state_index_writes = 0,
            .anchor_txid_index_writes = 0,
            .anchor_height_index_writes = 0,
            .anchor_status_writes = 0,
            .type_index_writes = 0,
        };

        // Per-cell extract: everything the write phase needs, copied
        // out of LMDB-managed memory so the read txn can close before
        // we open the write txn.
        const Extract = struct {
            hash: [32]u8,
            owner_id: [OWNER_ID_BYTES]u8,
            prev_state: [PREV_STATE_HASH_BYTES]u8,
            type_hash: [TYPE_HASH_BYTES]u8,
            is_attestation: bool,
            target_cell_id: [ATTESTATION_TARGET_CELL_ID_SIZE]u8,
            anchor_txid: [ATTESTATION_TXID_SIZE]u8,
            anchor_height: u64,
        };
        var pending: std.ArrayList(Extract) = .{};
        defer pending.deinit(self.allocator);

        // ── Phase 1: read-only cursor scan, populate `pending`. ───────
        {
            var scan_txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
            defer scan_txn.abort();
            var cur = scan_txn.openCursor(self.dbi) catch return error.persistence_failed;
            defer cur.close();

            // Seek to this operator's prefix range. If the store is empty
            // (or this operator has never written a cell) the seek returns
            // null and we drop straight through to phase 2 with an empty
            // `pending` — counters stay at zero, which is exactly the
            // right report for "nothing to backfill".
            var entry_opt = cur.seek(&self.op_pkh) catch null;
            while (entry_opt) |entry| {
                if (!hasPrefix(entry.key, &self.op_pkh)) break;
                if (entry.key.len != KEY_BYTES or entry.val.len < CELL_BYTES) {
                    // Malformed row — leave it alone and let an external
                    // census tool surface it. Skip without bumping any
                    // counter so the report stays truthful.
                    entry_opt = cur.step() catch null;
                    continue;
                }
                const cell: *const [CELL_BYTES]u8 = @ptrCast(entry.val.ptr);
                const domain_flag = std.mem.readInt(
                    u32,
                    cell[DOMAIN_FLAG_OFFSET_IN_CELL..][0..DOMAIN_FLAG_SIZE_IN_CELL],
                    .little,
                );
                const is_attestation = domain_flag == DOMAIN_FLAG_ANCHOR_ATTESTATION_V1;

                var ex: Extract = undefined;
                @memcpy(&ex.hash, entry.key[OP_PKH_BYTES..]);
                @memcpy(&ex.owner_id, cell[OWNER_ID_OFFSET_IN_CELL .. OWNER_ID_OFFSET_IN_CELL + OWNER_ID_BYTES]);
                @memcpy(&ex.prev_state, cell[PREV_STATE_HASH_OFFSET_IN_CELL .. PREV_STATE_HASH_OFFSET_IN_CELL + PREV_STATE_HASH_BYTES]);
                @memcpy(&ex.type_hash, cell[TYPE_HASH_OFFSET_IN_CELL .. TYPE_HASH_OFFSET_IN_CELL + TYPE_HASH_BYTES]);
                ex.is_attestation = is_attestation;
                if (is_attestation) {
                    @memcpy(
                        &ex.target_cell_id,
                        cell[ATTESTATION_TARGET_CELL_ID_OFFSET .. ATTESTATION_TARGET_CELL_ID_OFFSET + ATTESTATION_TARGET_CELL_ID_SIZE],
                    );
                    @memcpy(
                        &ex.anchor_txid,
                        cell[ATTESTATION_TXID_OFFSET .. ATTESTATION_TXID_OFFSET + ATTESTATION_TXID_SIZE],
                    );
                    ex.anchor_height = std.mem.readInt(
                        u64,
                        cell[ATTESTATION_ANCHOR_HEIGHT_OFFSET..][0..ATTESTATION_ANCHOR_HEIGHT_SIZE],
                        .little,
                    );
                } else {
                    ex.target_cell_id = [_]u8{0} ** ATTESTATION_TARGET_CELL_ID_SIZE;
                    ex.anchor_txid = [_]u8{0} ** ATTESTATION_TXID_SIZE;
                    ex.anchor_height = 0;
                }
                pending.append(self.allocator, ex) catch return error.out_of_memory;

                entry_opt = cur.step() catch null;
            }
        }

        // ── Phase 2: single write txn — apply every index entry. ──────
        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();

        for (pending.items) |ex| {
            report.cells_visited += 1;

            // D-LC3 — owner-index entry.
            const owner_key = buildOwnerKey(&self.op_pkh, &ex.owner_id, &ex.hash);
            txn.put(self.dbi_by_owner, &owner_key, &[_]u8{}, .{}) catch
                return error.persistence_failed;
            report.owner_index_writes += 1;

            // D-LC4 — prev-state-index entry. Genesis cells (all-zero
            // prev_state_hash) still get an entry; callers can either
            // skip the all-zero prev when walking or use it to find
            // chain roots cheaply. Matches the doPut posture.
            const prev_state_key = buildPrevStateKey(&self.op_pkh, &ex.prev_state, &ex.hash);
            txn.put(self.dbi_by_prev_state, &prev_state_key, &[_]u8{}, .{}) catch
                return error.persistence_failed;
            report.prev_state_index_writes += 1;

            // C4 — cells_by_type index entry.
            const type_key = buildTypeKey(&self.op_pkh, &ex.type_hash, &ex.hash);
            txn.put(self.dbi_by_type, &type_key, &[_]u8{}, .{}) catch
                return error.persistence_failed;
            report.type_index_writes += 1;

            // D-LC5 follow-up — attestation observer dispatch. The
            // attestation cell exists on disk, so its txid was
            // observed at mint time → write .confirmed. Pinned to
            // anchorAttestationSchemaV2 (see schema v2 layout note);
            // shares the same offset for target_cell_id and txid as
            // v1, plus an additional anchor_height index entry.
            if (ex.is_attestation) {
                self.writeAnchorStatusInTxn(&txn, &ex.target_cell_id, .confirmed) catch
                    return error.persistence_failed;
                report.anchor_status_writes += 1;

                const anchor_txid_key = buildAnchorTxidKey(&self.op_pkh, &ex.anchor_txid, &ex.target_cell_id);
                txn.put(self.dbi_by_anchor_txid, &anchor_txid_key, &[_]u8{}, .{}) catch
                    return error.persistence_failed;
                report.anchor_txid_index_writes += 1;

                const anchor_height_key = buildAnchorHeightKey(&self.op_pkh, ex.anchor_height, &ex.target_cell_id);
                txn.put(self.dbi_by_anchor_height, &anchor_height_key, &[_]u8{}, .{}) catch
                    return error.persistence_failed;
                report.anchor_height_index_writes += 1;
            }
        }

        txn.commit() catch return error.persistence_failed;
        return report;
    }

    // ── exists ────────────────────────────────────────────────────────────

    fn doExists(self: *LmdbCellStore, hash: *const [32]u8) bool {
        const key = buildKey(&self.op_pkh, hash);
        var txn = self.env.beginTxn(.read_only) catch return false;
        defer txn.abort();
        _ = txn.get(self.dbi, &key) catch return false;
        return true;
    }

    // ── spend / is_spent (P4a) ────────────────────────────────────────────

    fn doSpend(self: *LmdbCellStore, cell_id: *const [32]u8) StoreError!bool {
        const key = buildKey(&self.op_pkh, cell_id);

        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        // Idempotent: already-spent → no write, return false (not newly spent).
        _ = txn.get(self.dbi_spent, &key) catch |e| {
            if (e != error.not_found) {
                txn.abort();
                return error.persistence_failed;
            }
            const sentinel = [_]u8{1};
            txn.put(self.dbi_spent, &key, &sentinel, .{}) catch {
                txn.abort();
                return error.persistence_failed;
            };
            txn.commit() catch return error.persistence_failed;
            return true;
        };
        txn.abort();
        return false;
    }

    fn doIsSpent(self: *LmdbCellStore, cell_id: *const [32]u8) bool {
        const key = buildKey(&self.op_pkh, cell_id);
        var txn = self.env.beginTxn(.read_only) catch return false;
        defer txn.abort();
        _ = txn.get(self.dbi_spent, &key) catch return false;
        return true;
    }

    // ── get ───────────────────────────────────────────────────────────────

    /// Fetch a cell by its 32-byte content hash. Returns the 1024 bytes by
    /// value (a copy out of LMDB-managed memory so the caller is independent
    /// of the read txn), or null on miss. Used by the D-LC1 raw-cell-over-HTTP
    /// endpoint; not in the CellStore vtable yet — adding it there is a wider
    /// change that doesn't pay for itself for a single read path.
    pub fn getCell(self: *LmdbCellStore, hash: *const [32]u8) StoreError!?[CELL_BYTES]u8 {
        const key = buildKey(&self.op_pkh, hash);
        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();
        const val = txn.get(self.dbi, &key) catch |e| {
            if (e == error.not_found) return null;
            return error.persistence_failed;
        };
        if (val.len < CELL_BYTES) return error.persistence_failed;
        var out: [CELL_BYTES]u8 = undefined;
        @memcpy(&out, val[0..CELL_BYTES]);
        return out;
    }

    // ── cursor ────────────────────────────────────────────────────────────

    fn doCursorOpen(self: *LmdbCellStore) StoreError!cell_store_mod.CellCursorHandle {
        const state = self.allocator.create(CursorState) catch return error.out_of_memory;
        errdefer self.allocator.destroy(state);

        const txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        var cur = txn.openCursor(self.dbi) catch {
            txn.abort();
            return error.persistence_failed;
        };

        // Seek to the start of this operator's prefix range.  The cursor lands
        // AT the first matching entry; we record that in at_seek so the first
        // pull returns it via getCurrent() instead of advancing past it.
        const found = cur.seek(&self.op_pkh) catch null;
        const at_seek = found != null and hasPrefix(found.?.key, &self.op_pkh);

        state.* = .{ .txn = txn, .cur = cur, .op_pkh = self.op_pkh, .at_seek = at_seek };
        return @ptrCast(state);
    }

    fn doCursorPull(
        _: *LmdbCellStore,
        handle: cell_store_mod.CellCursorHandle,
    ) StoreError!?*const [CELL_BYTES]u8 {
        const state: *CursorState = @ptrCast(@alignCast(handle));

        // First pull after seek: return the entry the cursor is already AT.
        // Subsequent pulls: advance with step() (MDB_NEXT).
        const entry = if (state.at_seek) blk: {
            state.at_seek = false;
            break :blk state.cur.getCurrent() catch return error.persistence_failed;
        } else blk: {
            break :blk state.cur.step() catch return error.persistence_failed;
        };

        if (entry == null) return null;

        // W7.1 — stop when we leave this operator's prefix range.
        if (!hasPrefix(entry.?.key, &state.op_pkh)) return null;

        const val = entry.?.val;
        if (val.len < CELL_BYTES) return error.invalid_cell;
        return @ptrCast(val.ptr);
    }

    fn doCursorClose(self: *LmdbCellStore, handle: cell_store_mod.CellCursorHandle) void {
        const state: *CursorState = @ptrCast(@alignCast(handle));
        state.cur.close();
        state.txn.abort();
        self.allocator.destroy(state);
    }

    // ── count ─────────────────────────────────────────────────────────────

    fn doCount(self: *LmdbCellStore) StoreError!u64 {
        var txn = self.env.beginTxn(.read_only) catch return error.persistence_failed;
        defer txn.abort();
        var cur = txn.openCursor(self.dbi) catch return error.persistence_failed;
        defer cur.close();

        // W7.1 — seek to op_pkh prefix and count only matching entries.
        const first = cur.seek(&self.op_pkh) catch return 0;
        if (first == null or !hasPrefix(first.?.key, &self.op_pkh)) return 0;

        var n: u64 = 1;
        while (cur.step() catch return error.persistence_failed) |entry| {
            if (!hasPrefix(entry.key, &self.op_pkh)) break;
            n += 1;
        }
        return n;
    }

    // ── deleteAllCells (W7.8 operator exit) ──────────────────────────────

    /// Delete every cell AND its sibling-index/projection entries belonging
    /// to this operator. Called during operator exit (W7.8). All sub-DBs
    /// are scrubbed inside the SAME write transaction so exit is atomic —
    /// either everything drops together or nothing does.
    pub fn deleteAllCells(self: *LmdbCellStore) StoreError!void {
        var txn = self.env.beginTxn(.read_write) catch return error.persistence_failed;
        errdefer txn.abort();

        try deletePrefixRange(&txn, self.dbi, &self.op_pkh);
        try deletePrefixRange(&txn, self.dbi_spent, &self.op_pkh);
        // D-LC3 / D-LC4 / D-LC5 / D-LC5-reorg — same op_pkh prefix scrubs
        // every secondary index entry alongside the primary cells. Sub-DBs
        // all key with op_pkh first, so the existing deletePrefixRange
        // helper applies unchanged.
        try deletePrefixRange(&txn, self.dbi_by_owner, &self.op_pkh);
        try deletePrefixRange(&txn, self.dbi_by_prev_state, &self.op_pkh);
        try deletePrefixRange(&txn, self.dbi_anchor_status, &self.op_pkh);
        try deletePrefixRange(&txn, self.dbi_by_anchor_txid, &self.op_pkh);
        // D-LC5 follow-up (schema v2) — scrub the height-keyed index too.
        try deletePrefixRange(&txn, self.dbi_by_anchor_height, &self.op_pkh);
        // C4 — scrub the cells_by_type index too.
        try deletePrefixRange(&txn, self.dbi_by_type, &self.op_pkh);

        txn.commit() catch return error.persistence_failed;
    }

    /// Delete every key in `dbi` whose prefix matches `op_pkh`. No-op if
    /// the prefix range is empty. Caller owns the surrounding txn.
    fn deletePrefixRange(
        txn: *lmdb.Txn,
        dbi: lmdb.Dbi,
        op_pkh: *const [OP_PKH_BYTES]u8,
    ) StoreError!void {
        var cur = txn.openCursor(dbi) catch return error.persistence_failed;
        defer cur.close();

        const first = cur.seek(op_pkh) catch return;
        if (first == null or !hasPrefix(first.?.key, op_pkh)) return;

        cur.del() catch return error.persistence_failed;

        while (cur.step() catch null) |entry| {
            if (!hasPrefix(entry.key, op_pkh)) break;
            cur.del() catch return error.persistence_failed;
        }
    }

    // ── vtable shims ──────────────────────────────────────────────────────

    fn vPut(ctx: *anyopaque, cell: *const [CELL_BYTES]u8) StoreError![32]u8 {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.doPut(cell);
    }
    fn vExists(ctx: *anyopaque, hash: *const [32]u8) bool {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.doExists(hash);
    }
    fn vCursorOpen(ctx: *anyopaque) StoreError!cell_store_mod.CellCursorHandle {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.doCursorOpen();
    }
    fn vCursorPull(
        ctx: *anyopaque,
        cursor: cell_store_mod.CellCursorHandle,
    ) StoreError!?*const [CELL_BYTES]u8 {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.doCursorPull(cursor);
    }
    fn vCursorClose(ctx: *anyopaque, cursor: cell_store_mod.CellCursorHandle) void {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        self.doCursorClose(cursor);
    }
    fn vCount(ctx: *anyopaque) StoreError!u64 {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.doCount();
    }
    fn vSpend(ctx: *anyopaque, cell_id: *const [32]u8) StoreError!bool {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.doSpend(cell_id);
    }
    fn vIsSpent(ctx: *anyopaque, cell_id: *const [32]u8) bool {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.doIsSpent(cell_id);
    }

    // ── Read/query surface shims (promoted vtable methods) ───────────────

    fn vGetCell(
        ctx: *anyopaque,
        hash: *const [32]u8,
    ) StoreError!?[CELL_BYTES]u8 {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.getCell(hash);
    }

    fn vCellsByOwner(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        owner_id: *const [cell_store_mod.OWNER_ID_BYTES]u8,
    ) StoreError![][32]u8 {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.cellsByOwner(allocator, owner_id);
    }

    fn vCellsByType(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        type_hash: *const [32]u8,
    ) StoreError![][32]u8 {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.cellsByType(allocator, type_hash);
    }

    fn vCellsByTypePrefix(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        type_prefix: []const u8,
    ) StoreError![][32]u8 {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.cellsByTypePrefix(allocator, type_prefix);
    }

    fn vCellsByPrevState(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        prev_state_hash: *const [32]u8,
    ) StoreError![][32]u8 {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.cellsByPrevState(allocator, prev_state_hash);
    }

    fn vCellsByAnchorTxid(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        anchor_txid: *const [32]u8,
    ) StoreError![][32]u8 {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.cellsByAnchorTxid(allocator, anchor_txid);
    }

    fn vSetAnchorStatus(
        ctx: *anyopaque,
        hash: *const [32]u8,
        status: cell_store_mod.AnchorStatus,
    ) StoreError!void {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.setAnchorStatus(hash, status);
    }

    fn vGetAnchorStatus(
        ctx: *anyopaque,
        hash: *const [32]u8,
    ) ?cell_store_mod.AnchorStatus {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.getAnchorStatus(hash);
    }

    fn vClearAnchorStatus(
        ctx: *anyopaque,
        hash: *const [32]u8,
    ) StoreError!void {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.clearAnchorStatus(hash);
    }

    fn vSweepPendingAnchors(
        ctx: *anyopaque,
        anchor_txid: *const [32]u8,
    ) StoreError!cell_store_mod.SweepResult {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.sweepPendingAnchors(anchor_txid);
    }

    fn vCellsByAnchorHeightRange(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        height_low_inclusive: u64,
        height_high_inclusive: u64,
    ) StoreError![]cell_store_mod.AnchorHeightEntry {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.cellsByAnchorHeightRange(allocator, height_low_inclusive, height_high_inclusive);
    }

    fn vSweepReorgedFromHeight(
        ctx: *anyopaque,
        rollback_from_height: u64,
    ) StoreError!cell_store_mod.SweepResult {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.sweepReorgedFromHeight(rollback_from_height);
    }

    fn vCellsByPrevStateRange(
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        prev_state_hash: *const [32]u8,
        after: ?*const [32]u8,
        limit: usize,
    ) StoreError!cell_store_mod.PrevStateRangeResult {
        const self: *LmdbCellStore = @ptrCast(@alignCast(ctx));
        return self.cellsByPrevStateRange(allocator, prev_state_hash, after, limit);
    }

    const vtable = cell_store_mod.CellStore.VTable{
        .put = vPut,
        .exists = vExists,
        .cursor_open = vCursorOpen,
        .cursor_pull = vCursorPull,
        .cursor_close = vCursorClose,
        .count = vCount,
        .spend = vSpend,
        .is_spent = vIsSpent,
        .get_cell = vGetCell,
        .cells_by_owner = vCellsByOwner,
        .cells_by_type = vCellsByType,
        .cells_by_type_prefix = vCellsByTypePrefix,
        .cells_by_prev_state = vCellsByPrevState,
        .cells_by_anchor_txid = vCellsByAnchorTxid,
        .set_anchor_status = vSetAnchorStatus,
        .get_anchor_status = vGetAnchorStatus,
        .clear_anchor_status = vClearAnchorStatus,
        .sweep_pending_anchors = vSweepPendingAnchors,
        .cells_by_anchor_height_range = vCellsByAnchorHeightRange,
        .sweep_reorged_from_height = vSweepReorgedFromHeight,
        .cells_by_prev_state_range = vCellsByPrevStateRange,
    };
};

// ── Inline tests ──────────────────────────────────────────────────────────
//
// W7.1 acceptance: cell read/write paths take an operator context; cursor
// scans scoped by prefix; cross-operator read returns empty.

test "W7.1: single-tenant init uses zero op_pkh" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 4 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
    defer env.close();

    var store = try LmdbCellStore.init(&env, std.testing.allocator);
    defer store.deinit();

    // Zero op_pkh.
    const expected_prefix = [_]u8{0} ** OP_PKH_BYTES;
    try std.testing.expectEqualSlices(u8, &expected_prefix, &store.op_pkh);
}

test "W7.1: put and exists are scoped to op_pkh" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 4 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = [_]u8{ 0xAA, 0xBB, 0xCC, 0xDD, 0x11, 0x22, 0x33, 0x44 };
    const pkh_b: [OP_PKH_BYTES]u8 = [_]u8{ 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC };

    var store_a = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var store_b = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer store_a.deinit();
    defer store_b.deinit();

    var cell: [CELL_BYTES]u8 = [_]u8{0} ** CELL_BYTES;
    cell[0] = 0x42; // distinctive value

    const hash = try store_a.doPut(&cell);

    // Operator A can find the cell.
    try std.testing.expect(store_a.doExists(&hash));

    // Operator B cannot find the same cell — cross-operator read returns false.
    try std.testing.expect(!store_b.doExists(&hash));
}

test "W7.1: cursor scan is scoped to op_pkh prefix" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 4 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = [_]u8{ 0x01 } ++ [_]u8{0} ** (OP_PKH_BYTES - 1);
    const pkh_b: [OP_PKH_BYTES]u8 = [_]u8{ 0x02 } ++ [_]u8{0} ** (OP_PKH_BYTES - 1);

    var store_a = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var store_b = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer store_a.deinit();
    defer store_b.deinit();

    // Write one cell for each operator.
    var cell_a: [CELL_BYTES]u8 = [_]u8{0xAA} ** CELL_BYTES;
    var cell_b: [CELL_BYTES]u8 = [_]u8{0xBB} ** CELL_BYTES;
    _ = try store_a.doPut(&cell_a);
    _ = try store_b.doPut(&cell_b);

    // A's cursor should see exactly one cell (its own).
    const store_a_vtable = store_a.store();
    const cur_a = try store_a_vtable.cursorOpen();
    defer store_a_vtable.cursorClose(cur_a);

    const c1 = try store_a_vtable.cursorPull(cur_a);
    try std.testing.expect(c1 != null);
    try std.testing.expectEqualSlices(u8, &cell_a, c1.?);

    const c2 = try store_a_vtable.cursorPull(cur_a);
    try std.testing.expect(c2 == null); // B's cell is not visible to A

    // B's cursor should see exactly one cell (its own).
    const store_b_vtable = store_b.store();
    const cur_b = try store_b_vtable.cursorOpen();
    defer store_b_vtable.cursorClose(cur_b);

    const cb1 = try store_b_vtable.cursorPull(cur_b);
    try std.testing.expect(cb1 != null);
    try std.testing.expectEqualSlices(u8, &cell_b, cb1.?);

    const cb2 = try store_b_vtable.cursorPull(cur_b);
    try std.testing.expect(cb2 == null);
}

test "W7.1: count is scoped to op_pkh prefix" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 4 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = [_]u8{ 0xA0 } ++ [_]u8{0} ** (OP_PKH_BYTES - 1);
    const pkh_b: [OP_PKH_BYTES]u8 = [_]u8{ 0xB0 } ++ [_]u8{0} ** (OP_PKH_BYTES - 1);

    var store_a = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var store_b = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer store_a.deinit();
    defer store_b.deinit();

    var cell1: [CELL_BYTES]u8 = [_]u8{0x01} ** CELL_BYTES;
    var cell2: [CELL_BYTES]u8 = [_]u8{0x02} ** CELL_BYTES;
    var cell3: [CELL_BYTES]u8 = [_]u8{0x03} ** CELL_BYTES;
    _ = try store_a.doPut(&cell1);
    _ = try store_a.doPut(&cell2);
    _ = try store_b.doPut(&cell3);

    const store_a_vtable = store_a.store();
    const store_b_vtable = store_b.store();

    try std.testing.expectEqual(@as(u64, 2), try store_a_vtable.count());
    try std.testing.expectEqual(@as(u64, 1), try store_b_vtable.count());
}

test "P4a: spend records cell_id; is_spent observes it; idempotent re-spend returns false" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 4 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
    defer env.close();

    var store = try LmdbCellStore.init(&env, std.testing.allocator);
    defer store.deinit();
    const vt = store.store();

    var cell_id: [32]u8 = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF } ++ [_]u8{0} ** 28;

    // Fresh cell_id: not yet spent.
    try std.testing.expect(!vt.isSpent(&cell_id));

    // First spend: returns true (newly added).
    try std.testing.expect(try vt.spend(&cell_id));
    try std.testing.expect(vt.isSpent(&cell_id));

    // Re-spend: returns false (idempotent).
    try std.testing.expect(!(try vt.spend(&cell_id)));
    try std.testing.expect(vt.isSpent(&cell_id));
}

test "P4a: is_spent default is false for unknown cell_id" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 4 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
    defer env.close();

    var store = try LmdbCellStore.init(&env, std.testing.allocator);
    defer store.deinit();
    const vt = store.store();

    const never_seen: [32]u8 = [_]u8{0x42} ** 32;
    try std.testing.expect(!vt.isSpent(&never_seen));
}

test "P4a: spent-set is operator-isolated (cross-operator is_spent returns false)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 4 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = [_]u8{0xAA} ++ [_]u8{0} ** (OP_PKH_BYTES - 1);
    const pkh_b: [OP_PKH_BYTES]u8 = [_]u8{0xBB} ++ [_]u8{0} ** (OP_PKH_BYTES - 1);

    var store_a = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var store_b = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer store_a.deinit();
    defer store_b.deinit();
    const vt_a = store_a.store();
    const vt_b = store_b.store();

    const id: [32]u8 = [_]u8{0xC0} ** 32;

    // A spends the cell_id; B's view is unaffected.
    try std.testing.expect(try vt_a.spend(&id));
    try std.testing.expect(vt_a.isSpent(&id));
    try std.testing.expect(!vt_b.isSpent(&id));

    // B can independently spend the same cell_id under its own prefix —
    // and A still sees its own spend (no collision).
    try std.testing.expect(try vt_b.spend(&id));
    try std.testing.expect(vt_b.isSpent(&id));
    try std.testing.expect(vt_a.isSpent(&id));
}

test "P4a: spend does not affect the cells sub-DB (count + exists unchanged)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 4 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
    defer env.close();

    var store = try LmdbCellStore.init(&env, std.testing.allocator);
    defer store.deinit();
    const vt = store.store();

    // Put a cell; record its hash; spend the hash; cells count + exists
    // must be unchanged — the side index is independent of the value store.
    var cell: [CELL_BYTES]u8 = [_]u8{0x77} ** CELL_BYTES;
    const hash = try store.doPut(&cell);
    try std.testing.expectEqual(@as(u64, 1), try vt.count());
    try std.testing.expect(vt.exists(&hash));

    try std.testing.expect(try vt.spend(&hash));

    try std.testing.expectEqual(@as(u64, 1), try vt.count()); // unchanged
    try std.testing.expect(vt.exists(&hash)); // still present
    try std.testing.expect(vt.isSpent(&hash)); // additionally spent
}

test "P4a: deleteAllCells scrubs spent-set entries for this operator only" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 4 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = [_]u8{0xD1} ++ [_]u8{0} ** (OP_PKH_BYTES - 1);
    const pkh_b: [OP_PKH_BYTES]u8 = [_]u8{0xD2} ++ [_]u8{0} ** (OP_PKH_BYTES - 1);

    var store_a = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var store_b = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer store_a.deinit();
    defer store_b.deinit();

    const id_a: [32]u8 = [_]u8{0x0A} ** 32;
    const id_b: [32]u8 = [_]u8{0x0B} ** 32;
    try std.testing.expect(try store_a.store().spend(&id_a));
    try std.testing.expect(try store_b.store().spend(&id_b));

    // Operator-exit: A's spent-set drops; B's stays.
    try store_a.deleteAllCells();
    try std.testing.expect(!store_a.store().isSpent(&id_a));
    try std.testing.expect(store_b.store().isSpent(&id_b));
}

test "P4a: opening an env that pre-dates cells_spent succeeds (lazy create)" {
    // Simulates the upgrade-in-place path: an env where ONLY the `cells`
    // sub-DB exists. Open it with this LmdbCellStore — the `create:true`
    // flag on `cells_spent` makes the open idempotent, so the call
    // succeeds AND the new sub-DB lands in the same env.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 4 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
    defer env.close();

    // Pre-seed: open ONLY the `cells` sub-DB to simulate the pre-P4a env.
    {
        var txn = try env.beginTxn(.read_write);
        _ = try txn.openDb("cells", .{ .create = true });
        try txn.commit();
    }

    // Now open the full LmdbCellStore — must succeed and add cells_spent.
    var store = try LmdbCellStore.init(&env, std.testing.allocator);
    defer store.deinit();
    const vt = store.store();

    // The spent-set is functional immediately on the upgraded env.
    const id: [32]u8 = [_]u8{0xFE} ** 32;
    try std.testing.expect(!vt.isSpent(&id));
    try std.testing.expect(try vt.spend(&id));
    try std.testing.expect(vt.isSpent(&id));
}

test "W7.1: deleteAllCells removes only this operator's cells" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 4 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
    defer env.close();

    const pkh_a: [OP_PKH_BYTES]u8 = [_]u8{ 0xC1 } ++ [_]u8{0} ** (OP_PKH_BYTES - 1);
    const pkh_b: [OP_PKH_BYTES]u8 = [_]u8{ 0xC2 } ++ [_]u8{0} ** (OP_PKH_BYTES - 1);

    var store_a = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_a);
    var store_b = try LmdbCellStore.initForOperator(&env, std.testing.allocator, pkh_b);
    defer store_a.deinit();
    defer store_b.deinit();

    var cell_a: [CELL_BYTES]u8 = [_]u8{0xAA} ** CELL_BYTES;
    var cell_b: [CELL_BYTES]u8 = [_]u8{0xBB} ** CELL_BYTES;
    _ = try store_a.doPut(&cell_a);
    _ = try store_b.doPut(&cell_b);

    try store_a.deleteAllCells();

    const store_a_vtable = store_a.store();
    const store_b_vtable = store_b.store();

    try std.testing.expectEqual(@as(u64, 0), try store_a_vtable.count());
    try std.testing.expectEqual(@as(u64, 1), try store_b_vtable.count()); // B unaffected
}

test "C4: cells_by_type exact match + 8|8|8|8 segment-template prefix" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var env = try lmdb.Env.open(path, .{ .map_size = 8 * 1024 * 1024, .open_flags = lmdb.EnvFlags.NOTLS });
    defer env.close();

    var store = try LmdbCellStore.init(&env, std.testing.allocator);
    defer store.deinit();
    const alloc = std.testing.allocator;

    // Two typeHashes sharing namespace seg1 (bytes 30..38) but differing in the
    // domain seg2; a third in a different namespace. typeHash lives at cell[30..62].
    var th_job: [TYPE_HASH_BYTES]u8 = [_]u8{0} ** TYPE_HASH_BYTES;
    var th_cust: [TYPE_HASH_BYTES]u8 = [_]u8{0} ** TYPE_HASH_BYTES;
    var th_other: [TYPE_HASH_BYTES]u8 = [_]u8{0} ** TYPE_HASH_BYTES;
    // Shared namespace prefix (seg1) for job + customer.
    const ns_oddjobz = [_]u8{ 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88 };
    @memcpy(th_job[0..8], &ns_oddjobz);
    @memcpy(th_cust[0..8], &ns_oddjobz);
    th_job[8] = 0xAA; // domain seg2 = job
    th_cust[8] = 0xBB; // domain seg2 = customer
    @memcpy(th_other[0..8], &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22, 0x33 }); // different namespace

    // Build 3 distinct cells (distinct byte[0] → distinct hashes), each carrying
    // its typeHash at [30..62].
    var cell_job: [CELL_BYTES]u8 = [_]u8{0} ** CELL_BYTES;
    var cell_cust: [CELL_BYTES]u8 = [_]u8{0} ** CELL_BYTES;
    var cell_other: [CELL_BYTES]u8 = [_]u8{0} ** CELL_BYTES;
    cell_job[0] = 0x01;
    cell_cust[0] = 0x02;
    cell_other[0] = 0x03;
    @memcpy(cell_job[TYPE_HASH_OFFSET_IN_CELL .. TYPE_HASH_OFFSET_IN_CELL + TYPE_HASH_BYTES], &th_job);
    @memcpy(cell_cust[TYPE_HASH_OFFSET_IN_CELL .. TYPE_HASH_OFFSET_IN_CELL + TYPE_HASH_BYTES], &th_cust);
    @memcpy(cell_other[TYPE_HASH_OFFSET_IN_CELL .. TYPE_HASH_OFFSET_IN_CELL + TYPE_HASH_BYTES], &th_other);

    const h_job = try store.doPut(&cell_job);
    const h_cust = try store.doPut(&cell_cust);
    _ = try store.doPut(&cell_other);

    // Exact typeHash match → just the job cell.
    {
        const hits = try store.cellsByType(alloc, &th_job);
        defer alloc.free(hits);
        try std.testing.expectEqual(@as(usize, 1), hits.len);
        try std.testing.expectEqualSlices(u8, &h_job, &hits[0]);
    }

    // Namespace template (seg1, 8 bytes) → both job + customer, not other.
    {
        const hits = try store.cellsByTypePrefix(alloc, ns_oddjobz[0..]);
        defer alloc.free(hits);
        try std.testing.expectEqual(@as(usize, 2), hits.len);
        var saw_job = false;
        var saw_cust = false;
        for (hits) |hh| {
            if (std.mem.eql(u8, &hh, &h_job)) saw_job = true;
            if (std.mem.eql(u8, &hh, &h_cust)) saw_cust = true;
        }
        try std.testing.expect(saw_job and saw_cust);
    }

    // namespace+domain template (16 bytes) → only the job cell.
    {
        const hits = try store.cellsByTypePrefix(alloc, th_job[0..16]);
        defer alloc.free(hits);
        try std.testing.expectEqual(@as(usize, 1), hits.len);
        try std.testing.expectEqualSlices(u8, &h_job, &hits[0]);
    }

    // Empty prefix → all 3 of this operator's cells.
    {
        const hits = try store.cellsByTypePrefix(alloc, &[_]u8{});
        defer alloc.free(hits);
        try std.testing.expectEqual(@as(usize, 3), hits.len);
    }

    // Over-long prefix → invalid_cell.
    {
        const too_long = [_]u8{0} ** (TYPE_HASH_BYTES + 1);
        try std.testing.expectError(error.invalid_cell, store.cellsByTypePrefix(alloc, too_long[0..]));
    }
}

```
