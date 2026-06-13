---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/lmdb/drift_detector.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.280938+00:00
---

# runtime/semantos-brain/src/lmdb/drift_detector.zig

```zig
// M6.5 — DriftDetector: compares LMDB registry cache against a canonical
// Postgres snapshot and auto-quarantines divergent rows.
//
// Design
// ──────
// The detector holds a RegistryCacheStore (for put/get) and accepts a
// CanonicalSnapshot (sorted []const CanonicalEntry) pushed from a polling
// background job or Pravega change feed.  The polling mechanism is out of
// scope; the detector just accepts whatever snapshot it is given.
//
// runWalk iterates all entries in the LMDB `registry_cache` database via a
// cursor, binary-searches the canonical snapshot for each key, and collects
// divergences into a DriftReport.
//
// applyQuarantine writes back each drifted entry with state=3 (quarantined)
// and an incremented cache_version so downstream consumers can detect the
// update.
//
// Drift rules
// ───────────
// A row is drifted when:
//   1. It exists in LMDB but not in the canonical snapshot
//      (LMDB has a row Postgres doesn't know about).
//   2. It exists in both but content_hash differs.
// Clean rows are ignored.
//
// Run: zig build test-drift-detector

const std = @import("std");
const lmdb = @import("lmdb");
const registry_cache = @import("registry_cache");
const registry_cache_lmdb = @import("registry_cache_lmdb");

pub const RegistryCacheEntry = registry_cache.RegistryCacheEntry;

// ── Public types ─────────────────────────────────────────────────────────

/// A single row from the authoritative Postgres snapshot.
/// The snapshot slice passed to `runWalk` MUST be sorted by
/// (cell_id lexicographically, then domain_flag ascending).
pub const CanonicalEntry = struct {
    cell_id: [32]u8,
    domain_flag: u32,
    content_hash: [32]u8,
};

/// A single detected drift: what LMDB had vs what Postgres says.
/// When the LMDB row is absent from the snapshot, canon_hash is all-zero.
pub const DriftEntry = struct {
    cell_id: [32]u8,
    domain_flag: u32,
    lmdb_hash: [32]u8,
    canon_hash: [32]u8,
};

/// Aggregated result of a single walk.
pub const DriftReport = struct {
    total_scanned: u32,
    drifted: u32,
    quarantined: u32,
    errors: u32,
    /// Caller-owned slice; free with `deinit(report, allocator)`.
    drift_entries: []DriftEntry,
};

/// Free the `drift_entries` slice allocated by `runWalk`.
pub fn deinit(report: DriftReport, allocator: std.mem.Allocator) void {
    allocator.free(report.drift_entries);
}

// ── Key parsing constants (mirrors registry_cache_lmdb.zig) ─────────────

/// 36-byte composite key: cell_id[32] ++ be_u32(domain_flag).
const KEY_BYTES: usize = 36;

/// 56-byte value layout (see registry_cache_lmdb.zig).
const VALUE_BYTES: usize = 56;

fn keyToCellId(key: []const u8) [32]u8 {
    var id: [32]u8 = undefined;
    @memcpy(&id, key[0..32]);
    return id;
}

fn keyToDomainFlag(key: []const u8) u32 {
    return (@as(u32, key[32]) << 24) |
        (@as(u32, key[33]) << 16) |
        (@as(u32, key[34]) << 8) |
        @as(u32, key[35]);
}

fn valueToContentHash(val: []const u8) [32]u8 {
    var h: [32]u8 = undefined;
    // content_hash lives at bytes [8..40] in the value layout.
    @memcpy(&h, val[8..40]);
    return h;
}

fn valueToCacheVersion(val: []const u8) u64 {
    return std.mem.readInt(u64, val[40..48], .little);
}

// ── Binary search helper ──────────────────────────────────────────────────

/// Binary-search `snapshot` for (cell_id, domain_flag).
/// Returns a pointer to the matching CanonicalEntry, or null if absent.
fn findInSnapshot(
    snapshot: []const CanonicalEntry,
    cell_id: *const [32]u8,
    domain_flag: u32,
) ?*const CanonicalEntry {
    var lo: usize = 0;
    var hi: usize = snapshot.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const e = &snapshot[mid];
        const cmp_id = std.mem.order(u8, &e.cell_id, cell_id);
        if (cmp_id == .lt or (cmp_id == .eq and e.domain_flag < domain_flag)) {
            lo = mid + 1;
        } else if (cmp_id == .gt or (cmp_id == .eq and e.domain_flag > domain_flag)) {
            hi = mid;
        } else {
            return e; // exact match
        }
    }
    return null;
}

// ── DriftDetector ─────────────────────────────────────────────────────────

pub const DriftDetector = struct {
    /// Abstract store used for put/get operations (vtable).
    store: registry_cache.RegistryCacheStore,

    /// Walk every entry in the LMDB cache, compare against the canonical
    /// snapshot, and return a DriftReport.  The report's `drift_entries`
    /// slice is allocated into `allocator` and must be freed with `deinit`.
    ///
    /// The `snapshot` MUST be sorted by (cell_id lex, domain_flag asc).
    pub fn runWalk(
        self: *DriftDetector,
        allocator: std.mem.Allocator,
        snapshot: []const CanonicalEntry,
    ) !DriftReport {
        // We need direct LMDB cursor access.  The vtable gives us put/get but
        // not iteration; downcast to the concrete impl via the opaque ptr.
        const impl: *registry_cache_lmdb.LmdbRegistryCacheStore =
            @ptrCast(@alignCast(self.store.ptr));

        var total: u32 = 0;
        var n_drifted: u32 = 0;
        var n_errors: u32 = 0;
        var entries: std.ArrayList(DriftEntry) = .empty;
        errdefer entries.deinit(allocator);

        // Open a read-only cursor over the registry_cache database.
        var txn = try impl.env.beginTxn(.read_only);
        defer txn.abort();

        var cursor = try txn.openCursor(impl.dbi_cache);
        defer cursor.close();

        while (try cursor.next()) |kv| {
            if (kv.key.len < KEY_BYTES or kv.val.len < VALUE_BYTES) {
                n_errors += 1;
                continue;
            }
            total += 1;

            const cell_id = keyToCellId(kv.key);
            const domain_flag = keyToDomainFlag(kv.key);
            const lmdb_hash = valueToContentHash(kv.val);

            const canon = findInSnapshot(snapshot, &cell_id, domain_flag);
            if (canon) |c| {
                // Present in snapshot — check hash.
                if (!std.mem.eql(u8, &c.content_hash, &lmdb_hash)) {
                    n_drifted += 1;
                    try entries.append(allocator, .{
                        .cell_id = cell_id,
                        .domain_flag = domain_flag,
                        .lmdb_hash = lmdb_hash,
                        .canon_hash = c.content_hash,
                    });
                }
            } else {
                // Absent from snapshot — treat as drift.
                n_drifted += 1;
                try entries.append(allocator, .{
                    .cell_id = cell_id,
                    .domain_flag = domain_flag,
                    .lmdb_hash = lmdb_hash,
                    .canon_hash = [_]u8{0} ** 32,
                });
            }
        }

        return DriftReport{
            .total_scanned = total,
            .drifted = n_drifted,
            .quarantined = 0, // populated by applyQuarantine
            .errors = n_errors,
            .drift_entries = try entries.toOwnedSlice(allocator),
        };
    }

    /// For each drifted entry in `report`, update the LMDB cache entry to
    /// state=3 (quarantined) with an incremented cache_version.
    pub fn applyQuarantine(
        self: *DriftDetector,
        allocator: std.mem.Allocator,
        report: DriftReport,
    ) !void {
        _ = allocator;
        for (report.drift_entries) |de| {
            // Read the current entry so we preserve all other fields.
            var current: RegistryCacheEntry = undefined;
            const found = try self.store.get(&de.cell_id, de.domain_flag, &current);
            if (!found) continue; // entry may have been removed concurrently

            current.state = 3; // quarantined
            current.cache_version += 1;
            try self.store.put(current);
        }
    }
};

```
