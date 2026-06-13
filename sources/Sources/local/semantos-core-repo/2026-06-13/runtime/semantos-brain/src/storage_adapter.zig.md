---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/storage_adapter.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.223179+00:00
---

# runtime/semantos-brain/src/storage_adapter.zig

```zig
// DLO.3a — StorageAdapter Zig interface mirror.
//
// Reference: docs/prd/D-LIFT-ODDJOBZ.md §Deliverables / DLO.3
//            (per DECISION-3: cartridges consume StorageAdapter rather
//            than opening LMDB directly);
//            core/protocol-types/src/storage.ts (Phase 26 TS-side
//            interface this module mirrors).
//
// ── What this module is ──────────────────────────────────────────────
//
// A vtable-style interface that the lifted oddjobz domain stores (jobs,
// quotes, invoices, customers, leads, visits — DLO.3b through DLO.3g)
// will consume instead of opening LMDB directly. Brain-core provides
// concrete implementations (in-memory for tests; LMDB-backed in DLO.3b);
// the cartridge code only knows the StorageAdapter interface.
//
// The Zig interface mirrors the 6 required methods from
// `core/protocol-types/src/storage.ts`'s StorageAdapter, with the
// optional `watch` method deferred until a consumer needs it. The TS
// methods return Promises; the Zig methods return error unions directly
// (no async).
//
// ── Vtable pattern ───────────────────────────────────────────────────
//
// Zig has no formal interfaces, but the convention is a struct with
// function pointers + an opaque ctx (per `slot_store_fs.zig`,
// `state_store_fs.zig`, `header_store_fs.zig` precedents). Callers hold
// a `StorageAdapter` value (16 bytes — ctx pointer + vtable pointer);
// each method dispatches through the vtable to the concrete impl.
//
// ── Implementations ──────────────────────────────────────────────────
//
//   MemoryStorageAdapter — in-memory hashmap; this module ships it for
//                          inline tests + cartridge-test fixtures.
//   LmdbStorageAdapter   — LMDB-backed; arrives in DLO.3b alongside the
//                          jobs_store_lmdb refactor that consumes it.

const std = @import("std");

pub const StorageError = error{
    /// Key not found (only returned by exists/delete when caller treats
    /// "not found" as data, not error; read returns null in that case).
    NotFound,
    /// I/O failure underlying the storage backend.
    IoFailed,
    /// Key violates the safe-shape contract (empty, contains null bytes,
    /// exceeds MAX_KEY_LEN, etc.).
    InvalidKey,
    /// Underlying allocator failed.
    OutOfMemory,
};

/// Max accepted key length. Conservative; backends may enforce tighter
/// limits (e.g. LMDB's 511-byte default). Cartridge code should treat
/// this as the upper bound for portability.
pub const MAX_KEY_LEN: usize = 1024;

pub const StorageStat = struct {
    /// Byte size of the stored value.
    size: u64,
    /// Last modification time, epoch ms.
    modified_at_ms: u64,
    /// SHA-256 of the stored bytes.
    content_hash: [32]u8,
};

/// Vtable shape — one function pointer per StorageAdapter method.
pub const VTable = struct {
    read: *const fn (ctx: *anyopaque, key: []const u8, allocator: std.mem.Allocator) StorageError!?[]u8,
    write: *const fn (ctx: *anyopaque, key: []const u8, data: []const u8) StorageError!void,
    exists: *const fn (ctx: *anyopaque, key: []const u8) StorageError!bool,
    list: *const fn (ctx: *anyopaque, prefix: []const u8, allocator: std.mem.Allocator) StorageError![][]u8,
    delete: *const fn (ctx: *anyopaque, key: []const u8) StorageError!bool,
    stat: *const fn (ctx: *anyopaque, key: []const u8) StorageError!?StorageStat,
};

/// Caller-visible adapter handle. Hold this value; the methods dispatch
/// through the vtable to whichever concrete impl is plugged in.
pub const StorageAdapter = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub fn read(self: StorageAdapter, key: []const u8, allocator: std.mem.Allocator) StorageError!?[]u8 {
        if (!isValidKey(key)) return error.InvalidKey;
        return self.vtable.read(self.ctx, key, allocator);
    }

    pub fn write(self: StorageAdapter, key: []const u8, data: []const u8) StorageError!void {
        if (!isValidKey(key)) return error.InvalidKey;
        return self.vtable.write(self.ctx, key, data);
    }

    pub fn exists(self: StorageAdapter, key: []const u8) StorageError!bool {
        if (!isValidKey(key)) return error.InvalidKey;
        return self.vtable.exists(self.ctx, key);
    }

    pub fn list(self: StorageAdapter, prefix: []const u8, allocator: std.mem.Allocator) StorageError![][]u8 {
        // Empty prefix is valid — lists every key.
        if (prefix.len > MAX_KEY_LEN) return error.InvalidKey;
        return self.vtable.list(self.ctx, prefix, allocator);
    }

    pub fn delete(self: StorageAdapter, key: []const u8) StorageError!bool {
        if (!isValidKey(key)) return error.InvalidKey;
        return self.vtable.delete(self.ctx, key);
    }

    pub fn stat(self: StorageAdapter, key: []const u8) StorageError!?StorageStat {
        if (!isValidKey(key)) return error.InvalidKey;
        return self.vtable.stat(self.ctx, key);
    }
};

/// Key safe-shape: non-empty, ≤ MAX_KEY_LEN, no null bytes.
fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > MAX_KEY_LEN) return false;
    for (key) |c| if (c == 0) return false;
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// MemoryStorageAdapter — in-memory backend for tests + fixtures
// ─────────────────────────────────────────────────────────────────────

pub const MemoryStorageAdapter = struct {
    allocator: std.mem.Allocator,
    /// Owned key/value pairs. We dupe both on insert; free on delete/deinit.
    entries: std.StringHashMap(Entry),

    const Entry = struct {
        value: []u8,
        modified_at_ms: u64,
    };

    pub fn init(allocator: std.mem.Allocator) MemoryStorageAdapter {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(Entry).init(allocator),
        };
    }

    pub fn deinit(self: *MemoryStorageAdapter) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.value);
        }
        self.entries.deinit();
    }

    pub fn adapter(self: *MemoryStorageAdapter) StorageAdapter {
        return .{
            .ctx = @ptrCast(self),
            .vtable = &memory_vtable,
        };
    }

    fn castSelf(ctx: *anyopaque) *MemoryStorageAdapter {
        return @ptrCast(@alignCast(ctx));
    }

    fn readImpl(ctx: *anyopaque, key: []const u8, allocator: std.mem.Allocator) StorageError!?[]u8 {
        const self = castSelf(ctx);
        const entry = self.entries.get(key) orelse return null;
        const dup = allocator.dupe(u8, entry.value) catch return error.OutOfMemory;
        return dup;
    }

    fn writeImpl(ctx: *anyopaque, key: []const u8, data: []const u8) StorageError!void {
        const self = castSelf(ctx);
        // Update existing entry vs insert: free the old value first if present.
        if (self.entries.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value.value);
        }
        const key_dup = self.allocator.dupe(u8, key) catch return error.OutOfMemory;
        errdefer self.allocator.free(key_dup);
        const value_dup = self.allocator.dupe(u8, data) catch return error.OutOfMemory;
        errdefer self.allocator.free(value_dup);
        self.entries.put(key_dup, .{
            .value = value_dup,
            .modified_at_ms = @intCast(std.time.milliTimestamp()),
        }) catch return error.OutOfMemory;
    }

    fn existsImpl(ctx: *anyopaque, key: []const u8) StorageError!bool {
        const self = castSelf(ctx);
        return self.entries.contains(key);
    }

    fn listImpl(ctx: *anyopaque, prefix: []const u8, allocator: std.mem.Allocator) StorageError![][]u8 {
        const self = castSelf(ctx);
        var out = std.ArrayList([]u8).empty;
        errdefer {
            for (out.items) |k| allocator.free(k);
            out.deinit(allocator);
        }
        var it = self.entries.keyIterator();
        while (it.next()) |key_ptr| {
            const key = key_ptr.*;
            if (prefix.len == 0 or std.mem.startsWith(u8, key, prefix)) {
                const dup = allocator.dupe(u8, key) catch return error.OutOfMemory;
                out.append(allocator, dup) catch return error.OutOfMemory;
            }
        }
        return out.toOwnedSlice(allocator) catch return error.OutOfMemory;
    }

    fn deleteImpl(ctx: *anyopaque, key: []const u8) StorageError!bool {
        const self = castSelf(ctx);
        if (self.entries.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value.value);
            return true;
        }
        return false;
    }

    fn statImpl(ctx: *anyopaque, key: []const u8) StorageError!?StorageStat {
        const self = castSelf(ctx);
        const entry = self.entries.get(key) orelse return null;
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(entry.value);
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        return StorageStat{
            .size = entry.value.len,
            .modified_at_ms = entry.modified_at_ms,
            .content_hash = hash,
        };
    }
};

const memory_vtable: VTable = .{
    .read = MemoryStorageAdapter.readImpl,
    .write = MemoryStorageAdapter.writeImpl,
    .exists = MemoryStorageAdapter.existsImpl,
    .list = MemoryStorageAdapter.listImpl,
    .delete = MemoryStorageAdapter.deleteImpl,
    .stat = MemoryStorageAdapter.statImpl,
};

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

test "isValidKey: positive cases" {
    try std.testing.expect(isValidKey("a"));
    try std.testing.expect(isValidKey("objects/create/job/plumbing/job-1774/latest.cell"));
    try std.testing.expect(isValidKey("scope.with.dots"));
}

test "isValidKey: rejects empty + null-byte + oversized" {
    try std.testing.expect(!isValidKey(""));
    try std.testing.expect(!isValidKey("with\x00null"));
    var oversized: [MAX_KEY_LEN + 1]u8 = undefined;
    @memset(&oversized, 'a');
    try std.testing.expect(!isValidKey(&oversized));
}

test "MemoryStorageAdapter: write + read round-trip" {
    var backend = MemoryStorageAdapter.init(std.testing.allocator);
    defer backend.deinit();
    const adapter = backend.adapter();

    try adapter.write("jobs/job-1", "payload-bytes");

    const got = try adapter.read("jobs/job-1", std.testing.allocator) orelse return error.NotFound;
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("payload-bytes", got);
}

test "MemoryStorageAdapter: read returns null for missing key" {
    var backend = MemoryStorageAdapter.init(std.testing.allocator);
    defer backend.deinit();
    const adapter = backend.adapter();

    const got = try adapter.read("nope", std.testing.allocator);
    try std.testing.expect(got == null);
}

test "MemoryStorageAdapter: exists round-trip" {
    var backend = MemoryStorageAdapter.init(std.testing.allocator);
    defer backend.deinit();
    const adapter = backend.adapter();

    try std.testing.expect(!(try adapter.exists("jobs/job-1")));
    try adapter.write("jobs/job-1", "x");
    try std.testing.expect(try adapter.exists("jobs/job-1"));
}

test "MemoryStorageAdapter: write overwrites existing key" {
    var backend = MemoryStorageAdapter.init(std.testing.allocator);
    defer backend.deinit();
    const adapter = backend.adapter();

    try adapter.write("k", "v1");
    try adapter.write("k", "v2-longer");

    const got = try adapter.read("k", std.testing.allocator) orelse return error.NotFound;
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("v2-longer", got);
}

test "MemoryStorageAdapter: list with prefix filters" {
    var backend = MemoryStorageAdapter.init(std.testing.allocator);
    defer backend.deinit();
    const adapter = backend.adapter();

    try adapter.write("jobs/a", "1");
    try adapter.write("jobs/b", "2");
    try adapter.write("quotes/c", "3");

    const got = try adapter.list("jobs/", std.testing.allocator);
    defer {
        for (got) |k| std.testing.allocator.free(k);
        std.testing.allocator.free(got);
    }
    try std.testing.expectEqual(@as(usize, 2), got.len);
    // Order is hashmap-iteration-order; check that both expected keys are present.
    var saw_a = false;
    var saw_b = false;
    for (got) |k| {
        if (std.mem.eql(u8, k, "jobs/a")) saw_a = true;
        if (std.mem.eql(u8, k, "jobs/b")) saw_b = true;
    }
    try std.testing.expect(saw_a and saw_b);
}

test "MemoryStorageAdapter: list with empty prefix returns all" {
    var backend = MemoryStorageAdapter.init(std.testing.allocator);
    defer backend.deinit();
    const adapter = backend.adapter();

    try adapter.write("a", "1");
    try adapter.write("b", "2");
    try adapter.write("c", "3");

    const got = try adapter.list("", std.testing.allocator);
    defer {
        for (got) |k| std.testing.allocator.free(k);
        std.testing.allocator.free(got);
    }
    try std.testing.expectEqual(@as(usize, 3), got.len);
}

test "MemoryStorageAdapter: delete returns true if key existed, false otherwise" {
    var backend = MemoryStorageAdapter.init(std.testing.allocator);
    defer backend.deinit();
    const adapter = backend.adapter();

    try adapter.write("k", "v");
    try std.testing.expect(try adapter.delete("k"));
    try std.testing.expect(!(try adapter.delete("k"))); // already gone
    try std.testing.expect(!(try adapter.exists("k")));
}

test "MemoryStorageAdapter: stat returns size + sha256" {
    var backend = MemoryStorageAdapter.init(std.testing.allocator);
    defer backend.deinit();
    const adapter = backend.adapter();

    try adapter.write("k", "hello");
    const stat = try adapter.stat("k") orelse return error.NotFound;
    try std.testing.expectEqual(@as(u64, 5), stat.size);
    // SHA-256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
    var expected: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
    try std.testing.expectEqualSlices(u8, &expected, &stat.content_hash);
}

test "StorageAdapter: invalid key rejected at vtable boundary" {
    var backend = MemoryStorageAdapter.init(std.testing.allocator);
    defer backend.deinit();
    const adapter = backend.adapter();

    try std.testing.expectError(error.InvalidKey, adapter.read("", std.testing.allocator));
    try std.testing.expectError(error.InvalidKey, adapter.write("", "v"));
    try std.testing.expectError(error.InvalidKey, adapter.exists("with\x00null"));
}

```
