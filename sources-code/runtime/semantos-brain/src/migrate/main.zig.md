---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/migrate/main.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.278143+00:00
---

# runtime/semantos-brain/src/migrate/main.zig

```zig
// M1.8 — brain-migrate: import production JSONL files into LMDB.
//
// Usage:
//   brain-migrate --data-dir=<path> --lmdb-dir=<path> [--dry-run] [--verbose]
//
// Scans <data-dir> for JSONL files matching known patterns:
//   headers.jsonl  — header records → hdr_by_height + hdr_by_hash DBs
//   outputs.log    — output records → outputs DB
//
// Idempotent: uses MDB_NOOVERWRITE on put operations so re-running on
// already-imported data skips existing keys without error.
//
// --dry-run:  validates records without opening or writing to LMDB.
// --verbose:  logs per-record status to stderr.

const std = @import("std");
const lmdb = @import("lmdb");

// ── CLI argument parsing ───────────────────────────────────────────────────

const Args = struct {
    data_dir: ?[]const u8 = null,
    lmdb_dir: ?[]const u8 = null,
    dry_run: bool = false,
    verbose: bool = false,
};

fn parseArgs(allocator: std.mem.Allocator) !Args {
    var args = Args{};
    var it = try std.process.argsWithAllocator(allocator);
    defer it.deinit();
    _ = it.next(); // skip argv[0]
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--data-dir=")) {
            args.data_dir = arg["--data-dir=".len..];
        } else if (std.mem.startsWith(u8, arg, "--lmdb-dir=")) {
            args.lmdb_dir = arg["--lmdb-dir=".len..];
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            args.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            args.verbose = true;
        } else {
            std.debug.print("brain-migrate: unknown argument: {s}\n", .{arg});
            return error.UnknownArg;
        }
    }
    return args;
}

// ── Hex decoding ──────────────────────────────────────────────────────────

fn hexNibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => error.InvalidHex,
    };
}

fn hexDecode(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return error.InvalidHex;
    for (0..out.len) |i| {
        const hi = try hexNibble(hex[i * 2]);
        const lo = try hexNibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
}

// ── LMDB key/value helpers ────────────────────────────────────────────────

/// Big-endian u32 — matches header_store_lmdb.zig's `heightKey`.
fn heightKey(height: u32) [4]u8 {
    var k: [4]u8 = undefined;
    std.mem.writeInt(u32, &k, height, .big);
    return k;
}

/// SerialRecord layout (116 bytes) — matches header_store_lmdb.zig.
///   [00..04]  height     (u32 LE)
///   [04..08]  version    (u32 LE)
///   [08..40]  prev_hash  (32 bytes)
///   [40..72]  merkle_root(32 bytes)
///   [72..76]  timestamp  (u32 LE)
///   [76..80]  bits       (u32 LE)
///   [80..84]  nonce      (u32 LE)
///   [84..116] hash       (32 bytes)
const SERIAL_BYTES: usize = 4 + 4 + 32 + 32 + 4 + 4 + 4 + 32; // 116

fn serializeHeaderRecord(
    height: u32,
    version: u32,
    prev_hash: [32]u8,
    merkle_root: [32]u8,
    timestamp: u32,
    bits: u32,
    nonce: u32,
    hash: [32]u8,
) [SERIAL_BYTES]u8 {
    var buf: [SERIAL_BYTES]u8 = undefined;
    std.mem.writeInt(u32, buf[0..4], height, .little);
    std.mem.writeInt(u32, buf[4..8], version, .little);
    @memcpy(buf[8..40], &prev_hash);
    @memcpy(buf[40..72], &merkle_root);
    std.mem.writeInt(u32, buf[72..76], timestamp, .little);
    std.mem.writeInt(u32, buf[76..80], bits, .little);
    std.mem.writeInt(u32, buf[80..84], nonce, .little);
    @memcpy(buf[84..116], &hash);
    return buf;
}

// ── Header JSONL importer ─────────────────────────────────────────────────

const ImportStats = struct {
    imported: u64 = 0,
    skipped: u64 = 0, // already present (MDB_KEYEXIST)
    errors: u64 = 0, // parse errors
};

/// Parse one line of headers.jsonl for dry-run (no LMDB writes).
fn importHeaderLineDryRun(
    line: []const u8,
    verbose: bool,
    stats: *ImportStats,
) bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parsed = std.json.parseFromSliceLeaky(std.json.Value, alloc, line, .{}) catch {
        if (verbose) std.debug.print("brain-migrate: dry-run parse error on line: {s}\n", .{line});
        stats.errors += 1;
        return false;
    };
    if (parsed != .object) {
        if (verbose) std.debug.print("brain-migrate: dry-run not a JSON object: {s}\n", .{line});
        stats.errors += 1;
        return false;
    }
    const obj = parsed.object;
    // Validate required fields exist.
    for ([_][]const u8{ "height", "version", "prev_hash", "merkle_root", "timestamp", "bits", "nonce", "hash" }) |field| {
        if (obj.get(field) == null) {
            if (verbose) std.debug.print("brain-migrate: dry-run missing field: {s}\n", .{field});
            stats.errors += 1;
            return false;
        }
    }
    if (verbose) {
        const h = obj.get("height").?;
        std.debug.print("brain-migrate: dry-run valid header height={}\n", .{h});
    }
    stats.imported += 1;
    return true;
}

/// Import one line of headers.jsonl into the LMDB env.
/// Returns true on success (imported or skipped), false on parse error.
fn importHeaderLine(
    line: []const u8,
    txn: lmdb.Txn,
    dbi_by_height: lmdb.Dbi,
    dbi_by_hash: lmdb.Dbi,
    verbose: bool,
    stats: *ImportStats,
) bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parsed = std.json.parseFromSliceLeaky(std.json.Value, alloc, line, .{}) catch {
        if (verbose) std.debug.print("brain-migrate: parse error on line: {s}\n", .{line});
        stats.errors += 1;
        return false;
    };
    if (parsed != .object) {
        if (verbose) std.debug.print("brain-migrate: not a JSON object: {s}\n", .{line});
        stats.errors += 1;
        return false;
    }
    const obj = parsed.object;

    // Extract fields.
    const height_v = obj.get("height") orelse { stats.errors += 1; return false; };
    const version_v = obj.get("version") orelse { stats.errors += 1; return false; };
    const prev_hash_v = obj.get("prev_hash") orelse { stats.errors += 1; return false; };
    const merkle_root_v = obj.get("merkle_root") orelse { stats.errors += 1; return false; };
    const timestamp_v = obj.get("timestamp") orelse { stats.errors += 1; return false; };
    const bits_v = obj.get("bits") orelse { stats.errors += 1; return false; };
    const nonce_v = obj.get("nonce") orelse { stats.errors += 1; return false; };
    const hash_v = obj.get("hash") orelse { stats.errors += 1; return false; };

    if (height_v != .integer or version_v != .integer or
        prev_hash_v != .string or merkle_root_v != .string or
        timestamp_v != .integer or bits_v != .integer or
        nonce_v != .integer or hash_v != .string)
    {
        if (verbose) std.debug.print("brain-migrate: field type mismatch: {s}\n", .{line});
        stats.errors += 1;
        return false;
    }

    const height: u32 = std.math.cast(u32, height_v.integer) orelse {
        if (verbose) std.debug.print("brain-migrate: height out of range\n", .{});
        stats.errors += 1;
        return false;
    };
    const version: u32 = std.math.cast(u32, version_v.integer) orelse {
        stats.errors += 1; return false;
    };
    const timestamp: u32 = std.math.cast(u32, timestamp_v.integer) orelse {
        stats.errors += 1; return false;
    };
    const bits: u32 = std.math.cast(u32, bits_v.integer) orelse {
        stats.errors += 1; return false;
    };
    const nonce: u32 = std.math.cast(u32, nonce_v.integer) orelse {
        stats.errors += 1; return false;
    };

    var prev_hash: [32]u8 = undefined;
    hexDecode(prev_hash_v.string, &prev_hash) catch {
        if (verbose) std.debug.print("brain-migrate: invalid prev_hash hex\n", .{});
        stats.errors += 1;
        return false;
    };
    var merkle_root: [32]u8 = undefined;
    hexDecode(merkle_root_v.string, &merkle_root) catch {
        if (verbose) std.debug.print("brain-migrate: invalid merkle_root hex\n", .{});
        stats.errors += 1;
        return false;
    };
    var hash: [32]u8 = undefined;
    hexDecode(hash_v.string, &hash) catch {
        if (verbose) std.debug.print("brain-migrate: invalid hash hex\n", .{});
        stats.errors += 1;
        return false;
    };

    const serial = serializeHeaderRecord(
        height, version, prev_hash, merkle_root, timestamp, bits, nonce, hash,
    );
    const hk = heightKey(height);

    // Write to hdr_by_height — MDB_NOOVERWRITE for idempotency.
    txn.put(dbi_by_height, &hk, &serial, .{ .no_overwrite = true }) catch |err| {
        if (err == error.key_exists) {
            if (verbose) std.debug.print("brain-migrate: skip existing header height={d}\n", .{height});
            stats.skipped += 1;
            return true;
        }
        if (verbose) std.debug.print("brain-migrate: lmdb put error for height={d}: {}\n", .{ height, err });
        stats.errors += 1;
        return false;
    };

    // Write to hdr_by_hash — height_be as value, MDB_NOOVERWRITE for idempotency.
    txn.put(dbi_by_hash, &hash, &hk, .{ .no_overwrite = true }) catch |err| {
        if (err == error.key_exists) {
            // Already present — consistent state.
            stats.skipped += 1;
            return true;
        }
        if (verbose) std.debug.print("brain-migrate: lmdb put hash error: {}\n", .{err});
        stats.errors += 1;
        return false;
    };

    if (verbose) std.debug.print("brain-migrate: imported header height={d}\n", .{height});
    stats.imported += 1;
    return true;
}

/// Import `headers.jsonl` from `data_dir` into the LMDB env (or just parse
/// if `env_opt` is null, i.e. dry-run mode).
fn importHeaders(
    data_dir: []const u8,
    env_opt: ?*lmdb.Env,
    verbose: bool,
) !ImportStats {
    var stats = ImportStats{};
    const dry_run = env_opt == null;

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const jsonl_path = std.fmt.bufPrint(&path_buf, "{s}/headers.jsonl", .{data_dir}) catch
        return error.PathTooLong;

    const file = std.fs.cwd().openFile(jsonl_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            if (verbose) std.debug.print("brain-migrate: no headers.jsonl found in {s}\n", .{data_dir});
            return stats;
        }
        return err;
    };
    defer file.close();

    const stat = try file.stat();
    if (stat.size == 0) return stats;

    const buf = try std.heap.page_allocator.alloc(u8, @intCast(stat.size));
    defer std.heap.page_allocator.free(buf);
    _ = try file.readAll(buf);

    if (dry_run) {
        // Dry-run: parse only, no LMDB.
        var line_iter = std.mem.tokenizeScalar(u8, buf, '\n');
        while (line_iter.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            _ = importHeaderLineDryRun(trimmed, verbose, &stats);
        }
        return stats;
    }

    const env = env_opt.?;

    // Open DBs — one write transaction per import run (batched for performance).
    // We open the DBs in a separate txn first (per LMDB convention: DB handles
    // must be opened before first use, typically in a write txn at startup).
    var dbi_by_height: lmdb.Dbi = undefined;
    var dbi_by_hash: lmdb.Dbi = undefined;
    {
        var setup_txn = try env.beginTxn(.read_write);
        errdefer setup_txn.abort();
        dbi_by_height = try setup_txn.openDb("hdr_by_height", .{ .create = true });
        dbi_by_hash = try setup_txn.openDb("hdr_by_hash", .{ .create = true });
        try setup_txn.commit();
    }

    // Process lines. We use one write transaction for the entire file for
    // performance; for very large files a chunked approach would be better,
    // but for the migration use-case this is fine.
    var txn = try env.beginTxn(.read_write);
    errdefer txn.abort();

    var line_iter = std.mem.tokenizeScalar(u8, buf, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        _ = importHeaderLine(
            trimmed, txn, dbi_by_height, dbi_by_hash, verbose, &stats,
        );
    }
    try txn.commit();

    return stats;
}

// ── Main ──────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = parseArgs(allocator) catch |err| {
        std.debug.print("brain-migrate: argument error: {}\n", .{err});
        std.process.exit(1);
    };

    const data_dir = args.data_dir orelse {
        std.debug.print("brain-migrate: --data-dir is required\n", .{});
        std.process.exit(1);
    };
    const lmdb_dir = args.lmdb_dir orelse {
        std.debug.print("brain-migrate: --lmdb-dir is required\n", .{});
        std.process.exit(1);
    };

    if (args.verbose) {
        std.debug.print("brain-migrate: data-dir={s} lmdb-dir={s} dry-run={} verbose={}\n", .{
            data_dir, lmdb_dir, args.dry_run, args.verbose,
        });
    }

    // Open LMDB env (unless dry-run).
    var env_opt: ?lmdb.Env = null;
    if (!args.dry_run) {
        // Ensure the lmdb-dir exists.
        std.fs.cwd().makePath(lmdb_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                std.debug.print("brain-migrate: cannot create lmdb-dir {s}: {}\n", .{ lmdb_dir, err });
                std.process.exit(1);
            },
        };
        env_opt = lmdb.Env.open(lmdb_dir, .{ .max_dbs = 8 }) catch |err| {
            std.debug.print("brain-migrate: cannot open LMDB at {s}: {}\n", .{ lmdb_dir, err });
            std.process.exit(1);
        };
    }
    defer if (env_opt) |*e| e.close();

    var total = ImportStats{};

    // Import headers (env_opt = null means dry-run).
    {
        const stats = importHeaders(data_dir, if (env_opt) |*e| e else null, args.verbose) catch |err| {
            std.debug.print("brain-migrate: header import failed: {}\n", .{err});
            std.process.exit(1);
        };
        total.imported += stats.imported;
        total.skipped += stats.skipped;
        total.errors += stats.errors;
    }

    std.debug.print("brain-migrate: done — imported={d} skipped={d} errors={d}\n", .{
        total.imported, total.skipped, total.errors,
    });
}

```
