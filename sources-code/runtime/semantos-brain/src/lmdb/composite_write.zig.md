---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/lmdb/composite_write.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.280081+00:00
---

# runtime/semantos-brain/src/lmdb/composite_write.zig

```zig
// M1.6 — CompositeWrite: atomic multi-cell write across four LMDB stores.
//
// A "composite cell write" bundles four related records that must land
// atomically.  The invariant is: either all four land or none do.
//
// The four cells:
//   Cell 0     — primary 1024-byte payload (stored in "cells" DB)
//   BUMP cell  — BSV UTXO anchor (stored in "outputs" DB)
//   BEEF cell  — merkle-proof block header (stored in "hdr_by_height" /
//                "hdr_by_hash" DBs — same layout as LmdbHeaderStore)
//   Envelope   — signed bundle header (stored in "envelopes" DB)
//
// A single `Txn` (read_write) is opened by `begin` and shared across all
// four `put*` calls.  `commit` commits it; `abort` aborts it.  Any error
// during a `put*` call should be followed by `abort` — the caller is
// responsible (same pattern as all other LMDB modules in this codebase).
//
// Re-exports:
//   The types Outpoint, OutputRecord, HeaderRecord, and Envelope are
//   re-exported so tests can import a single module.

const std = @import("std");
const lmdb = @import("lmdb");

// Re-export store implementations so callers/tests import one module.
pub const LmdbCellStore = @import("cell_store_lmdb").LmdbCellStore;
pub const LmdbOutputStore = @import("output_store_lmdb").LmdbOutputStore;
pub const LmdbHeaderStore = @import("header_store_lmdb").LmdbHeaderStore;

// Re-export domain types.
pub const Outpoint = @import("output_store_lmdb").Outpoint;
pub const OutputRecord = @import("output_store_lmdb").OutputRecord;
pub const HeaderRecord = @import("header_store_lmdb").HeaderRecord;

const cell_store_mod = @import("cell_store");

/// Envelope: a signed bundle header stored in the "envelopes" DB.
/// key  = id (32 bytes)
/// value = payload (arbitrary bytes, caller-owned)
pub const Envelope = struct {
    id: [32]u8,
    payload: []const u8,
};

// ── internal serialisation helpers (mirror header_store_lmdb) ─────────────

const SERIAL_HDR_BYTES: usize = 4 + 4 + 32 + 32 + 4 + 4 + 4 + 32; // 116

fn heightKey(height: u32) [4]u8 {
    var k: [4]u8 = undefined;
    std.mem.writeInt(u32, &k, height, .big);
    return k;
}

fn serializeHeader(rec: HeaderRecord) [SERIAL_HDR_BYTES]u8 {
    var buf: [SERIAL_HDR_BYTES]u8 = undefined;
    std.mem.writeInt(u32, buf[0..4], rec.height, .little);
    std.mem.writeInt(u32, buf[4..8], rec.header.version, .little);
    @memcpy(buf[8..40], &rec.header.prev_hash);
    @memcpy(buf[40..72], &rec.header.merkle_root);
    std.mem.writeInt(u32, buf[72..76], rec.header.timestamp, .little);
    std.mem.writeInt(u32, buf[76..80], rec.header.bits, .little);
    std.mem.writeInt(u32, buf[80..84], rec.header.nonce, .little);
    @memcpy(buf[84..116], &rec.hash);
    return buf;
}

// ── Output serialisation (mirrors output_store_lmdb) ─────────────────────

const FIXED_HDR: usize = 8 + 32 + 16 + 33 + 8 + 4 + 1 + 32; // 134

fn outpointKey(op: Outpoint) [36]u8 {
    var k: [36]u8 = undefined;
    @memcpy(k[0..32], &op.txid);
    std.mem.writeInt(u32, k[32..36], op.vout, .little);
    return k;
}

fn serializedOutputLen(r: OutputRecord) usize {
    return FIXED_HDR +
        4 + r.locking_script.len +
        4 + r.beef.len +
        4 + r.basket.len +
        4 + r.tags.len +
        4 + r.custom_instructions.len;
}

fn serializeOutput(r: OutputRecord, buf: []u8) void {
    var off: usize = 0;
    std.mem.writeInt(u64, buf[off..][0..8], r.satoshis, .little);
    off += 8;
    @memcpy(buf[off .. off + 32], &r.derived_key_hash);
    off += 32;
    @memcpy(buf[off .. off + 16], &r.derivation_protocol_hash);
    off += 16;
    @memcpy(buf[off .. off + 33], &r.derivation_counterparty);
    off += 33;
    std.mem.writeInt(u64, buf[off..][0..8], r.derivation_index, .little);
    off += 8;
    std.mem.writeInt(u32, buf[off..][0..4], r.confirmations, .little);
    off += 4;
    buf[off] = @intFromEnum(r.status);
    off += 1;
    @memcpy(buf[off .. off + 32], &r.spending_txid);
    off += 32;
    inline for ([_][]const u8{
        r.locking_script,
        r.beef,
        r.basket,
        r.tags,
        r.custom_instructions,
    }) |s| {
        std.mem.writeInt(u32, buf[off..][0..4], @intCast(s.len), .little);
        off += 4;
        @memcpy(buf[off .. off + s.len], s);
        off += s.len;
    }
}

// ── CompositeWrite ────────────────────────────────────────────────────────

pub const WriteError = error{
    persistence_failed,
    out_of_memory,
    already_committed,
    already_aborted,
};

/// A single LMDB write transaction that spans all four store operations.
///
/// Lifecycle:
///   1. `begin`         — opens one write txn; resolves DB handles from
///                        the shared Env.
///   2. `putCell`       — writes cell bytes to "cells" DB.
///   3. `putBump`       — writes OutputRecord to "outputs" DB.
///   4. `putBeef`       — writes HeaderRecord to "hdr_by_height" +
///                        "hdr_by_hash" DBs.
///   5. `putEnvelope`   — writes Envelope payload to "envelopes" DB.
///   6. `commit`        — commits the txn (all-or-nothing).
///        or  `abort`   — aborts the txn (none visible).
///
/// Errors from any `put*` call leave the txn open and dirty. The caller
/// must call `abort` after any error — this mirrors the pattern in every
/// other LMDB module in this codebase.
pub const CompositeWrite = struct {
    txn: lmdb.Txn,
    allocator: std.mem.Allocator,
    dbi_cells: lmdb.Dbi,
    dbi_outputs: lmdb.Dbi,
    dbi_hdr_by_height: lmdb.Dbi,
    dbi_hdr_by_hash: lmdb.Dbi,
    dbi_envelopes: lmdb.Dbi,
    done: bool = false,

    /// Open a single LMDB write transaction and resolve the five DB handles.
    /// `cell_store`, `output_store`, and `header_store` supply their
    /// pre-initialised DBI values — the handles are derived from the same Env
    /// that was used to call their `init` functions.
    pub fn begin(
        env: *lmdb.Env,
        cell_store_impl: *LmdbCellStore,
        output_store_impl: *LmdbOutputStore,
        header_store_impl: *LmdbHeaderStore,
    ) WriteError!CompositeWrite {
        var txn = env.beginTxn(.read_write) catch return error.persistence_failed;
        // The "envelopes" DB is composite-write-specific — open (create) it
        // inside this txn.  The other DBIs were created during store init and
        // are re-used here.
        const dbi_env = txn.openDb("envelopes", .{ .create = true }) catch {
            txn.abort();
            return error.persistence_failed;
        };
        return .{
            .txn = txn,
            .allocator = cell_store_impl.allocator,
            .dbi_cells = cell_store_impl.dbi,
            .dbi_outputs = output_store_impl.dbi,
            .dbi_hdr_by_height = header_store_impl.dbi_by_height,
            .dbi_hdr_by_hash = header_store_impl.dbi_by_hash,
            .dbi_envelopes = dbi_env,
        };
    }

    /// Write a 1024-byte cell into the "cells" DB.
    /// Key = SHA256(cell_bytes), value = padded to PAGE_BYTES.
    pub fn putCell(self: *CompositeWrite, cell: *const [cell_store_mod.CELL_BYTES]u8) WriteError!void {
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(cell, &hash, .{});

        var padded: [cell_store_mod.VALUE_BYTES]u8 = [_]u8{0} ** cell_store_mod.VALUE_BYTES;
        @memcpy(padded[0..cell_store_mod.CELL_BYTES], cell);

        self.txn.put(self.dbi_cells, &hash, &padded, .{}) catch return error.persistence_failed;
    }

    /// Write an OutputRecord (BUMP) into the "outputs" DB.
    pub fn putBump(self: *CompositeWrite, op: Outpoint, record: OutputRecord) WriteError!void {
        const key = outpointKey(op);
        const sz = serializedOutputLen(record);
        const buf = self.allocator.alloc(u8, sz) catch return error.out_of_memory;
        defer self.allocator.free(buf);
        serializeOutput(record, buf);
        self.txn.put(self.dbi_outputs, &key, buf, .{}) catch return error.persistence_failed;
    }

    /// Write a HeaderRecord (BEEF) into the "hdr_by_height" and "hdr_by_hash"
    /// DBs.  The `txid` parameter is the block's hash (used as the key in
    /// hdr_by_hash); `header_rec.hash` should equal `txid`.
    pub fn putBeef(
        self: *CompositeWrite,
        txid: [32]u8,
        header_rec: HeaderRecord,
    ) WriteError!void {
        const serial = serializeHeader(header_rec);
        const hk = heightKey(header_rec.height);

        self.txn.put(self.dbi_hdr_by_height, &hk, &serial, .{}) catch return error.persistence_failed;

        // Value in hdr_by_hash is the big-endian height (same as LmdbHeaderStore).
        const height_be = heightKey(header_rec.height);
        self.txn.put(self.dbi_hdr_by_hash, &txid, &height_be, .{}) catch return error.persistence_failed;
    }

    /// Write an Envelope into the "envelopes" DB.
    pub fn putEnvelope(self: *CompositeWrite, envelope: Envelope) WriteError!void {
        self.txn.put(self.dbi_envelopes, &envelope.id, envelope.payload, .{}) catch
            return error.persistence_failed;
    }

    /// Commit all four writes atomically.
    pub fn commit(self: *CompositeWrite) WriteError!void {
        self.done = true;
        self.txn.commit() catch return error.persistence_failed;
    }

    /// Abort the transaction — none of the pending writes become visible.
    pub fn abort(self: *CompositeWrite) void {
        if (!self.done) {
            self.done = true;
            self.txn.abort();
        }
    }
};

```
