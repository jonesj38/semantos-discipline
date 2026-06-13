---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/lmdb/registry_cache_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.278490+00:00
---

# runtime/semantos-brain/src/lmdb/registry_cache_lmdb.zig

```zig
// M6.2 — LmdbRegistryCacheStore: LMDB-backed cache for octave_registry.
//
// Storage layout
// ─────────────
// Database "registry_cache"
//   key:   cell_id[32] ++ be_u32(domain_flag)   = 36 bytes
//   value: fixed-size serialisation of the non-key fields of
//          RegistryCacheEntry (see VALUE_BYTES below)
//
// Database "registry_cache_version"
//   key:   "latest"   (6 bytes)
//   value: be_u64(highest cache_version ever written)
//
// Value serialisation (little-endian throughout, 8-byte-aligned fields):
//   [0]      octave_level     u8
//   [1]      linearity_type   u8
//   [2]      state            u8
//   [3]      _pad             u8  (reserved, always 0)
//   [4..7]   _pad             u32 (reserved, always 0)
//   [8..39]  content_hash     [32]u8
//   [40..47] cache_version    u64  (little-endian)
//   [48..55] registered_at_ms i64  (little-endian)
//   total: 56 bytes
//
// Stale-cache detection
// ─────────────────────
// `isStale(entry, postgres_version)` returns true iff
// entry.cache_version < postgres_version.  The Postgres version is
// obtained by the caller via a separate polling path (out of scope here).
//
// Pravega stub
// ────────────
// `populateFromEvent(payload)` is a placeholder for the M3.2 Pravega
// change-feed integration. It currently returns error.NotImplemented.

const std = @import("std");
const lmdb = @import("lmdb");
const registry_cache = @import("registry_cache");

pub const RegistryCacheEntry = registry_cache.RegistryCacheEntry;

// ── Serialisation constants ───────────────────────────────────────────

/// 36-byte composite key: cell_id[32] ++ be_u32(domain_flag).
const KEY_BYTES: usize = 36;

/// 56-byte value layout (see module doc).
const VALUE_BYTES: usize = 56;

/// Key used in `registry_cache_version` for the high-water mark.
const VERSION_KEY = "latest";

// ── Key / value helpers ───────────────────────────────────────────────

fn encodeKey(cell_id: *const [32]u8, domain_flag: u32) [KEY_BYTES]u8 {
    var buf: [KEY_BYTES]u8 = undefined;
    @memcpy(buf[0..32], cell_id);
    // big-endian u32 for natural sort order.
    buf[32] = @intCast((domain_flag >> 24) & 0xFF);
    buf[33] = @intCast((domain_flag >> 16) & 0xFF);
    buf[34] = @intCast((domain_flag >> 8) & 0xFF);
    buf[35] = @intCast(domain_flag & 0xFF);
    return buf;
}

fn encodeValue(e: RegistryCacheEntry) [VALUE_BYTES]u8 {
    var buf: [VALUE_BYTES]u8 = [_]u8{0} ** VALUE_BYTES;
    buf[0] = e.octave_level;
    buf[1] = e.linearity_type;
    buf[2] = e.state;
    // buf[3..7] reserved / padding — already zero.
    @memcpy(buf[8..40], &e.content_hash);
    std.mem.writeInt(u64, buf[40..48], e.cache_version, .little);
    std.mem.writeInt(i64, buf[48..56], e.registered_at_ms, .little);
    return buf;
}

fn decodeValue(
    cell_id: *const [32]u8,
    domain_flag: u32,
    raw: []const u8,
) RegistryCacheEntry {
    var e: RegistryCacheEntry = undefined;
    e.cell_id = cell_id.*;
    e.domain_flag = domain_flag;
    e.octave_level = raw[0];
    e.linearity_type = raw[1];
    e.state = raw[2];
    @memcpy(&e.content_hash, raw[8..40]);
    e.cache_version = std.mem.readInt(u64, raw[40..48], .little);
    e.registered_at_ms = std.mem.readInt(i64, raw[48..56], .little);
    return e;
}

fn encodeVersion(v: u64) [8]u8 {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, v, .big);
    return buf;
}

fn decodeVersion(raw: []const u8) u64 {
    return std.mem.readInt(u64, raw[0..8], .big);
}

// ── isStale ───────────────────────────────────────────────────────────

/// Returns true if the cached entry is stale relative to `postgres_version`.
/// An entry is stale when its `cache_version` is strictly less than the
/// Postgres version.  Equal versions are considered fresh.
pub fn isStale(entry: RegistryCacheEntry, postgres_version: u64) bool {
    return entry.cache_version < postgres_version;
}

// ── LmdbRegistryCacheStore ────────────────────────────────────────────

pub const LmdbRegistryCacheStore = struct {
    env: *lmdb.Env,
    allocator: std.mem.Allocator,
    dbi_cache: lmdb.Dbi,
    dbi_version: lmdb.Dbi,

    pub fn init(env: *lmdb.Env, allocator: std.mem.Allocator) !LmdbRegistryCacheStore {
        var txn = try env.beginTxn(.read_write);
        errdefer txn.abort();

        const dbi_cache = try txn.openDb("registry_cache", .{ .create = true });
        const dbi_version = try txn.openDb("registry_cache_version", .{ .create = true });

        try txn.commit();
        return .{
            .env = env,
            .allocator = allocator,
            .dbi_cache = dbi_cache,
            .dbi_version = dbi_version,
        };
    }

    pub fn deinit(_: *LmdbRegistryCacheStore) void {}

    pub fn store(self: *LmdbRegistryCacheStore) registry_cache.RegistryCacheStore {
        return .{ .ptr = @ptrCast(self), .vtable = &vtable };
    }

    // ── put ──────────────────────────────────────────────────────────

    fn doPut(self: *LmdbRegistryCacheStore, entry: RegistryCacheEntry) !void {
        const key = encodeKey(&entry.cell_id, entry.domain_flag);
        const val = encodeValue(entry);

        var txn = try self.env.beginTxn(.read_write);
        errdefer txn.abort();

        try txn.put(self.dbi_cache, &key, &val, .{});

        // Update high-water mark if this version is higher.
        const new_ver = entry.cache_version;
        const prev_ver = blk: {
            const raw = txn.get(self.dbi_version, VERSION_KEY) catch |e| {
                if (e == error.not_found) break :blk @as(u64, 0);
                return e;
            };
            if (raw.len < 8) break :blk @as(u64, 0);
            break :blk decodeVersion(raw);
        };
        if (new_ver > prev_ver) {
            const ver_buf = encodeVersion(new_ver);
            try txn.put(self.dbi_version, VERSION_KEY, &ver_buf, .{});
        }

        try txn.commit();
    }

    // ── get ──────────────────────────────────────────────────────────

    fn doGet(
        self: *LmdbRegistryCacheStore,
        cell_id: *const [32]u8,
        domain_flag: u32,
        out: *RegistryCacheEntry,
    ) !bool {
        const key = encodeKey(cell_id, domain_flag);
        var txn = try self.env.beginTxn(.read_only);
        defer txn.abort();

        const raw = txn.get(self.dbi_cache, &key) catch |e| {
            if (e == error.not_found) return false;
            return e;
        };
        if (raw.len < VALUE_BYTES) return false;
        out.* = decodeValue(cell_id, domain_flag, raw);
        return true;
    }

    // ── invalidate ───────────────────────────────────────────────────

    fn doInvalidate(
        self: *LmdbRegistryCacheStore,
        cell_id: *const [32]u8,
        domain_flag: u32,
    ) !void {
        const key = encodeKey(cell_id, domain_flag);
        var txn = try self.env.beginTxn(.read_write);
        errdefer txn.abort();

        txn.del(self.dbi_cache, &key, null) catch |e| {
            if (e == error.not_found) {
                txn.abort();
                return;
            }
            return e;
        };
        try txn.commit();
    }

    // ── latestVersion ─────────────────────────────────────────────────

    fn doLatestVersion(self: *LmdbRegistryCacheStore) !u64 {
        var txn = try self.env.beginTxn(.read_only);
        defer txn.abort();

        const raw = txn.get(self.dbi_version, VERSION_KEY) catch |e| {
            if (e == error.not_found) return 0;
            return e;
        };
        if (raw.len < 8) return 0;
        return decodeVersion(raw);
    }

    // ── populateFromEvent (Pravega stub) ──────────────────────────────

    /// Stub for M3.2 Pravega change-feed integration.
    /// Accepts a JSON event payload and will call `put` once M3.2 is
    /// implemented. Currently returns error.NotImplemented.
    pub fn populateFromEvent(_: *LmdbRegistryCacheStore, event_payload: []const u8) !void {
        _ = event_payload;
        return error.NotImplemented;
    }

    // ── vtable shims ──────────────────────────────────────────────────

    fn vPut(ctx: *anyopaque, entry: RegistryCacheEntry) anyerror!void {
        const self: *LmdbRegistryCacheStore = @ptrCast(@alignCast(ctx));
        return self.doPut(entry);
    }

    fn vGet(
        ctx: *anyopaque,
        cell_id: *const [32]u8,
        domain_flag: u32,
        out: *RegistryCacheEntry,
    ) anyerror!bool {
        const self: *LmdbRegistryCacheStore = @ptrCast(@alignCast(ctx));
        return self.doGet(cell_id, domain_flag, out);
    }

    fn vInvalidate(
        ctx: *anyopaque,
        cell_id: *const [32]u8,
        domain_flag: u32,
    ) anyerror!void {
        const self: *LmdbRegistryCacheStore = @ptrCast(@alignCast(ctx));
        return self.doInvalidate(cell_id, domain_flag);
    }

    fn vLatestVersion(ctx: *anyopaque) anyerror!u64 {
        const self: *LmdbRegistryCacheStore = @ptrCast(@alignCast(ctx));
        return self.doLatestVersion();
    }

    fn vDeinit(ctx: *anyopaque) void {
        const self: *LmdbRegistryCacheStore = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    const vtable = registry_cache.RegistryCacheStore.VTable{
        .put = vPut,
        .get = vGet,
        .invalidate = vInvalidate,
        .latestVersion = vLatestVersion,
        .deinit = vDeinit,
    };
};

```
