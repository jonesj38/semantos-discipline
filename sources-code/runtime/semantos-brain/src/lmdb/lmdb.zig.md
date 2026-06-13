---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/lmdb/lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.279782+00:00
---

# runtime/semantos-brain/src/lmdb/lmdb.zig

```zig
// M1.1 — LMDB Zig binding.
//
// Binding strategy: system liblmdb via C FFI (`linkSystemLibrary("lmdb")`).
//
// Justification (M1.1 acceptance criterion — written justification required):
//
//   Options evaluated:
//   1. `lmdb-zig` (Karrick McLean) — pure Zig, wraps vendored LMDB C source.
//      Attractive for hermetic builds but last updated for Zig 0.12; the 0.15
//      module API changes would require a fork and maintenance burden.
//   2. `zig-lmdb` (nickelc) — similar vintage issue.
//   3. Hand-rolled C FFI against system liblmdb (chosen).
//
//   Decision: use the system library for now (Zig 0.15.2 ships excellent C
//   interop; the lmdb.h types translate cleanly). The build step requires
//   `liblmdb-dev` (Debian/Ubuntu) or `lmdb` (Homebrew); CI installs it via
//   the `infra/ci/deps.sh` script. When an actively-maintained Zig 0.15-native
//   binding stabilises (expected ~Q3 2026), M1.1 can be revisited without
//   touching any caller code — the wrapper surface below is the only
//   change point.
//
//   LMDB invariants this wrapper enforces:
//   - Every Env gets MDB_NORDAHEAD|MDB_NOMETASYNC by default (M1.9 will add
//     the crash-recovery choice; for now we leave the env open to the caller
//     via `open_flags`).
//   - Cursors are always closed before their parent transaction.
//   - `get` returns a slice pointing into LMDB-managed memory valid only
//     for the lifetime of the enclosing transaction — callers must copy if
//     they need the bytes to outlive the txn.

const std = @import("std");
const c = @cImport(@cInclude("lmdb.h"));

// Re-export low-level C types so LMDB implementation modules (e.g.
// header_store_lmdb.zig) can use them without their own @cImport.
pub const c_types = c;
pub const Dbi = c.MDB_dbi;

pub const LmdbError = error{
    not_found,
    key_exists,
    map_full,
    dbs_full,
    readers_full,
    txn_full,
    cursor_full,
    page_full,
    map_resized,
    incompatible,
    bad_rslot,
    bad_txn,
    bad_valsize,
    bad_dbi,
    panic,
    version_mismatch,
    invalid,
    io,
    lmdb_error,
    permission_denied,
};

fn lmdbErr(rc: c_int) LmdbError!void {
    return switch (rc) {
        0 => {},
        c.MDB_NOTFOUND => error.not_found,
        c.MDB_KEYEXIST => error.key_exists,
        c.MDB_MAP_FULL => error.map_full,
        c.MDB_DBS_FULL => error.dbs_full,
        c.MDB_READERS_FULL => error.readers_full,
        c.MDB_TXN_FULL => error.txn_full,
        c.MDB_CURSOR_FULL => error.cursor_full,
        c.MDB_PAGE_FULL => error.page_full,
        c.MDB_MAP_RESIZED => error.map_resized,
        c.MDB_INCOMPATIBLE => error.incompatible,
        c.MDB_BAD_RSLOT => error.bad_rslot,
        c.MDB_BAD_TXN => error.bad_txn,
        c.MDB_BAD_VALSIZE => error.bad_valsize,
        c.MDB_BAD_DBI => error.bad_dbi,
        c.MDB_PANIC => error.panic,
        c.MDB_VERSION_MISMATCH => error.version_mismatch,
        c.MDB_INVALID => error.invalid,
        else => blk: {
            if (rc == @as(c_int, @intFromEnum(std.posix.E.ACCES)))
                break :blk error.permission_denied;
            break :blk error.lmdb_error;
        },
    };
}

fn toVal(s: []const u8) c.MDB_val {
    return .{
        .mv_size = s.len,
        .mv_data = @constCast(s.ptr),
    };
}

fn fromVal(v: c.MDB_val) []const u8 {
    return @as([*]const u8, @ptrCast(v.mv_data))[0..v.mv_size];
}

// ── EnvFlags ─────────────────────────────────────────────────────────
//
// Named constants for MDB_* flags used during env open.  Collected here
// so callers and LmdbConfig can reference them without a raw hex literal.
//
// Durability trade-offs (M1.9 — see runtime/semantos-brain/LMDB-TUNING.md):
//
//   NOSYNC      — skip ALL fsyncs.  Fastest; risks full data loss on
//                 power-loss.  Acceptable only in CI / benchmarks.
//   NOMETASYNC  — skip fsync of the meta page only.  Data pages are
//                 flushed; on crash LMDB recovers to the previous clean
//                 transaction.  Chosen production default.
//   default     — fdatasync on every commit.  Slowest; strongest guarantee.
//
// Threading:
//   NOTLS       — disables thread-local storage for reader locks.  Required
//                 for single-threaded WASM/async hosts.  Always set.

pub const EnvFlags = struct {
    pub const FIXEDMAP: c_uint = 0x01;
    pub const NOSYNC: c_uint = 0x10000;
    pub const RDONLY: c_uint = 0x20000;
    pub const NOMETASYNC: c_uint = 0x40000;
    pub const WRITEMAP: c_uint = 0x80000;
    pub const MAPASYNC: c_uint = 0x100000;
    pub const NOTLS: c_uint = 0x200000;
};

// ── EnvOptions ───────────────────────────────────────────────────────

pub const EnvOptions = struct {
    /// Maximum number of named databases. 0 → only the anonymous DB.
    max_dbs: c_uint = 16,
    /// Map size in bytes. Default 256 MiB — suitable for development.
    /// Production nodes should set this to match expected dataset size.
    map_size: usize = 256 * 1024 * 1024,
    /// Extra MDB_* flags ORed in (e.g. MDB_NOSYNC for benchmarks).
    open_flags: c_uint = 0,
    /// File mode for the LMDB directory (mdb_mode_t = c_ushort on macOS).
    mode: c.mdb_mode_t = 0o755,
};

// ── DbOptions ────────────────────────────────────────────────────────

pub const DbOptions = struct {
    /// Create the named DB if it does not exist.
    create: bool = true,
    /// Extra MDB_DUPSORT / MDB_INTEGERKEY flags.
    flags: c_uint = 0,
};

// ── PutOptions ───────────────────────────────────────────────────────

pub const PutOptions = struct {
    /// Fail if key already exists.
    no_overwrite: bool = false,
};

// ── CursorEntry ──────────────────────────────────────────────────────

pub const CursorEntry = struct {
    key: []const u8,
    val: []const u8,
};

// ── Cursor ───────────────────────────────────────────────────────────

pub const Cursor = struct {
    ptr: *c.MDB_cursor,
    at_first: bool = true,

    pub fn close(self: *Cursor) void {
        c.mdb_cursor_close(@ptrCast(self.ptr));
    }

    fn cptr(self: *Cursor) ?*c.MDB_cursor {
        return @ptrCast(self.ptr);
    }

    /// Advance to the next entry. Returns null when exhausted.
    pub fn next(self: *Cursor) LmdbError!?CursorEntry {
        var k: c.MDB_val = undefined;
        var v: c.MDB_val = undefined;
        const op: c.MDB_cursor_op = if (self.at_first) c.MDB_FIRST else c.MDB_NEXT;
        self.at_first = false;
        const rc = c.mdb_cursor_get(self.cptr(), &k, &v, op);
        if (rc == c.MDB_NOTFOUND) return null;
        try lmdbErr(rc);
        return .{ .key = fromVal(k), .val = fromVal(v) };
    }

    /// Seek to the first key >= `target`.
    pub fn seek(self: *Cursor, target: []const u8) LmdbError!?CursorEntry {
        var k = toVal(target);
        var v: c.MDB_val = undefined;
        const rc = c.mdb_cursor_get(self.cptr(), &k, &v, c.MDB_SET_RANGE);
        if (rc == c.MDB_NOTFOUND) return null;
        try lmdbErr(rc);
        self.at_first = false;
        return .{ .key = fromVal(k), .val = fromVal(v) };
    }

    /// Position on the last key in the database. Returns null if empty.
    pub fn last(self: *Cursor) LmdbError!?CursorEntry {
        var k: c.MDB_val = undefined;
        var v: c.MDB_val = undefined;
        const rc = c.mdb_cursor_get(self.cptr(), &k, &v, c.MDB_LAST);
        if (rc == c.MDB_NOTFOUND) return null;
        try lmdbErr(rc);
        self.at_first = false;
        return .{ .key = fromVal(k), .val = fromVal(v) };
    }

    /// Delete the record at the current cursor position.
    pub fn del(self: *Cursor) LmdbError!void {
        try lmdbErr(c.mdb_cursor_del(self.cptr(), 0));
    }

    /// Move cursor to next entry (without the at_first tracking of `next`).
    pub fn step(self: *Cursor) LmdbError!?CursorEntry {
        var k: c.MDB_val = undefined;
        var v: c.MDB_val = undefined;
        const rc = c.mdb_cursor_get(self.cptr(), &k, &v, c.MDB_NEXT);
        if (rc == c.MDB_NOTFOUND) return null;
        try lmdbErr(rc);
        return .{ .key = fromVal(k), .val = fromVal(v) };
    }

    /// Return the entry at the current cursor position without advancing.
    pub fn getCurrent(self: *Cursor) LmdbError!?CursorEntry {
        var k: c.MDB_val = undefined;
        var v: c.MDB_val = undefined;
        const rc = c.mdb_cursor_get(self.cptr(), &k, &v, c.MDB_GET_CURRENT);
        if (rc == c.MDB_NOTFOUND) return null;
        try lmdbErr(rc);
        return .{ .key = fromVal(k), .val = fromVal(v) };
    }

    /// Move cursor to the previous entry (MDB_PREV). Returns null at start.
    pub fn prev(self: *Cursor) LmdbError!?CursorEntry {
        var k: c.MDB_val = undefined;
        var v: c.MDB_val = undefined;
        const rc = c.mdb_cursor_get(self.cptr(), &k, &v, c.MDB_PREV);
        if (rc == c.MDB_NOTFOUND) return null;
        try lmdbErr(rc);
        return .{ .key = fromVal(k), .val = fromVal(v) };
    }
};

// ── Txn ──────────────────────────────────────────────────────────────

pub const TxnMode = enum { read_only, read_write };

pub const Txn = struct {
    ptr: *c.MDB_txn,

    fn cptr(self: Txn) ?*c.MDB_txn {
        return @ptrCast(self.ptr);
    }

    pub fn commit(self: Txn) LmdbError!void {
        try lmdbErr(c.mdb_txn_commit(self.cptr()));
    }

    pub fn abort(self: Txn) void {
        c.mdb_txn_abort(self.cptr());
    }

    pub fn openDb(self: Txn, name: ?[*:0]const u8, opts: DbOptions) LmdbError!c.MDB_dbi {
        var dbi: c.MDB_dbi = undefined;
        var flags: c_uint = opts.flags;
        if (opts.create) flags |= c.MDB_CREATE;
        try lmdbErr(c.mdb_dbi_open(self.cptr(), name, flags, &dbi));
        return dbi;
    }

    pub fn get(self: Txn, dbi: c.MDB_dbi, key: []const u8) LmdbError![]const u8 {
        var k = toVal(key);
        var v: c.MDB_val = undefined;
        try lmdbErr(c.mdb_get(self.cptr(), dbi, &k, &v));
        return fromVal(v);
    }

    pub fn put(self: Txn, dbi: c.MDB_dbi, key: []const u8, val: []const u8, opts: PutOptions) LmdbError!void {
        var k = toVal(key);
        var v = toVal(val);
        var flags: c_uint = 0;
        if (opts.no_overwrite) flags |= c.MDB_NOOVERWRITE;
        try lmdbErr(c.mdb_put(self.cptr(), dbi, &k, &v, flags));
    }

    pub fn del(self: Txn, dbi: c.MDB_dbi, key: []const u8, val: ?[]const u8) LmdbError!void {
        var k = toVal(key);
        var v_opt: ?*c.MDB_val = null;
        var v: c.MDB_val = undefined;
        if (val) |s| {
            v = toVal(s);
            v_opt = &v;
        }
        try lmdbErr(c.mdb_del(self.cptr(), dbi, &k, v_opt));
    }

    pub fn openCursor(self: Txn, dbi: c.MDB_dbi) LmdbError!Cursor {
        var ptr: ?*c.MDB_cursor = null;
        try lmdbErr(c.mdb_cursor_open(self.cptr(), dbi, &ptr));
        return .{ .ptr = ptr.? };
    }

    /// Delete all key/value pairs from a database without dropping it.
    /// Equivalent to MDB_EMPTY flag passed to mdb_drop.
    pub fn clear(self: Txn, dbi: c.MDB_dbi) LmdbError!void {
        try lmdbErr(c.mdb_drop(self.cptr(), dbi, 0));
    }
};

// ── Env ──────────────────────────────────────────────────────────────

pub const Env = struct {
    ptr: *c.MDB_env,

    pub fn open(path: []const u8, opts: EnvOptions) LmdbError!Env {
        var ptr: ?*c.MDB_env = null;
        try lmdbErr(c.mdb_env_create(&ptr));
        const env_ptr = ptr.?;
        errdefer c.mdb_env_close(env_ptr);

        try lmdbErr(c.mdb_env_set_maxdbs(env_ptr, opts.max_dbs));
        try lmdbErr(c.mdb_env_set_mapsize(env_ptr, opts.map_size));

        // Null-terminate the path.
        var buf: [std.fs.max_path_bytes + 1]u8 = undefined;
        if (path.len >= buf.len) return error.lmdb_error;
        @memcpy(buf[0..path.len], path);
        buf[path.len] = 0;

        try lmdbErr(c.mdb_env_open(env_ptr, &buf, opts.open_flags, opts.mode));
        return .{ .ptr = env_ptr };
    }

    pub fn close(self: *Env) void {
        c.mdb_env_close(@ptrCast(self.ptr));
    }

    pub fn beginTxn(self: *Env, mode: TxnMode) LmdbError!Txn {
        const flags: c_uint = if (mode == .read_only) c.MDB_RDONLY else 0;
        var ptr: ?*c.MDB_txn = null;
        try lmdbErr(c.mdb_txn_begin(@ptrCast(self.ptr), null, flags, &ptr));
        return .{ .ptr = ptr.? };
    }

    pub fn sync(self: *Env, force: bool) LmdbError!void {
        try lmdbErr(c.mdb_env_sync(@ptrCast(self.ptr), if (force) 1 else 0));
    }

    /// Set or clear runtime MDB_* flags on an already-open env.
    /// Pass `onoff = true` to enable the flags, `false` to clear them.
    /// Typically called before the first transaction when overriding the
    /// flags supplied to `open`.
    pub fn setFlags(self: *Env, flags: c_uint, onoff: bool) LmdbError!void {
        const rc = c.mdb_env_set_flags(@ptrCast(self.ptr), flags, if (onoff) 1 else 0);
        if (rc != 0) return error.lmdb_error;
    }
};

```
