---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/lmdb/registry_cache.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.279092+00:00
---

# runtime/semantos-brain/src/lmdb/registry_cache.zig

```zig
// M6.2 — RegistryCacheStore vtable: LMDB-side cache for octave_registry.
//
// This module defines the abstract interface (RegistryCacheStore) and the
// entry type (RegistryCacheEntry). Callers depend only on this module;
// the concrete LMDB implementation lives in registry_cache_lmdb.zig.
//
// Stale-cache detection: every entry carries a `cache_version` (u64) that
// is monotonically increasing. A cache hit is considered stale when
// `entry.cache_version < postgres_version` where `postgres_version` is the
// value last polled from Postgres. The polling mechanism is out of scope
// here; consumers call `isStale` (registry_cache_lmdb.zig) directly.
//
// Pravega wiring: the cache is designed to be populated from a Pravega
// change-feed stream. M3.2 (Pravega client) is not yet implemented.
// The LMDB implementation exposes `populateFromEvent(payload)` as a stub
// that returns `error.NotImplemented` until M3.2 lands.

/// A single cached row from octave_registry.
pub const RegistryCacheEntry = struct {
    /// Primary-key component 1: SHA256 cell identifier (32 bytes).
    cell_id: [32]u8,
    /// Primary-key component 2: domain flag.
    domain_flag: u32,
    /// Octave level: 0, 1, or 2 (maps to Postgres enum '0'|'1'|'2').
    octave_level: u8,
    /// SHA256 content hash of the octave (32 bytes).
    content_hash: [32]u8,
    /// Linearity type: 0=linear 1=affine 2=relevant 3=unrestricted.
    linearity_type: u8,
    /// State: 0=unspent 1=spent 2=locked 3=quarantined.
    state: u8,
    /// Monotonically increasing version sourced from Postgres.
    /// The entry is stale if cache_version < postgres_version.
    cache_version: u64,
    /// Unix timestamp (milliseconds) when the row was registered.
    registered_at_ms: i64,
};

/// Vtable-based abstract store.  All LMDB-specific logic is in
/// registry_cache_lmdb.zig.  Future implementations (in-memory, mock,
/// Redis-backed …) implement the same interface.
pub const RegistryCacheStore = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Upsert an entry into the cache.  Overwrites any existing entry
        /// for the same (cell_id, domain_flag) composite key.
        put: *const fn (*anyopaque, entry: RegistryCacheEntry) anyerror!void,

        /// Retrieve an entry by composite key.
        /// Returns true and populates `out` on a cache hit; returns false
        /// (leaving `out` undefined) on a cache miss.
        get: *const fn (
            *anyopaque,
            cell_id: *const [32]u8,
            domain_flag: u32,
            out: *RegistryCacheEntry,
        ) anyerror!bool,

        /// Remove an entry from the cache (e.g. when the row is quarantined
        /// or the cache is explicitly invalidated by the change-feed).
        invalidate: *const fn (
            *anyopaque,
            cell_id: *const [32]u8,
            domain_flag: u32,
        ) anyerror!void,

        /// Return the highest `cache_version` ever written to this store.
        /// Returns 0 if the store is empty.
        latestVersion: *const fn (*anyopaque) anyerror!u64,

        /// Release all resources held by the store.
        deinit: *const fn (*anyopaque) void,
    };

    // ── Convenience forwarding methods ───────────────────────────────

    pub fn put(self: RegistryCacheStore, entry: RegistryCacheEntry) anyerror!void {
        return self.vtable.put(self.ptr, entry);
    }

    pub fn get(
        self: RegistryCacheStore,
        cell_id: *const [32]u8,
        domain_flag: u32,
        out: *RegistryCacheEntry,
    ) anyerror!bool {
        return self.vtable.get(self.ptr, cell_id, domain_flag, out);
    }

    pub fn invalidate(
        self: RegistryCacheStore,
        cell_id: *const [32]u8,
        domain_flag: u32,
    ) anyerror!void {
        return self.vtable.invalidate(self.ptr, cell_id, domain_flag);
    }

    pub fn latestVersion(self: RegistryCacheStore) anyerror!u64 {
        return self.vtable.latestVersion(self.ptr);
    }

    pub fn deinit(self: RegistryCacheStore) void {
        self.vtable.deinit(self.ptr);
    }
};

```
