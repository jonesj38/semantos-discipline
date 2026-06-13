---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/backfill_cell_indices/main.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.291712+00:00
---

# runtime/semantos-brain/src/backfill_cell_indices/main.zig

```zig
// D-LC3 follow-up — brain-backfill-cell-indices: one-shot migration that
// scans the primary `cells` sub-DB and populates every secondary index
// entry (`cells_by_owner`, `cells_by_prev_state`, `cells_anchor_status`,
// `cells_by_anchor_txid`) for every cell already on disk.
//
// Usage:
//   brain-backfill-cell-indices --lmdb-dir=<path> \
//                               [--op-pkh=<16-hex>] \
//                               [--verbose]
//
// Required:
//   --lmdb-dir=<path>     path to the cell-store LMDB env directory
//
// Optional:
//   --op-pkh=<16-hex>     8-byte operator prefix in lowercase hex (16 hex
//                         chars). Defaults to all-zero, matching the
//                         single-tenant LmdbCellStore.init() path. Multi-
//                         operator deployments should run this per
//                         operator (one process per op_pkh).
//   --verbose             log per-cell shape decisions to stderr.
//
// Idempotent — safe to re-run. The cell-store does opportunistic backfill
// for any cell that gets re-put via the normal write path; this bin
// covers the rest (cells written before D-LC3 / D-LC4 / D-LC5 shipped
// and never touched again).
//
// Why this is a separate bin instead of folded into the daemon's
// startup: the migration writes potentially every cell's index entries,
// which is too much work to do silently on every boot. Operators
// running pre-existing brains should invoke this once after upgrading;
// subsequent boots see all-zero index gaps and skip directly to normal
// operation.
//
// The bin opens just the LMDB env + the LmdbCellStore — no brain
// reactor, no HTTP server, no cert store, no hat registry. The
// migration only needs access to the cell-store sub-DBs.

const std = @import("std");
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");

const OP_PKH_BYTES: usize = lmdb_cell_store.OP_PKH_BYTES;

// ── CLI argument parsing ───────────────────────────────────────────────────

const Args = struct {
    lmdb_dir: ?[]const u8 = null,
    op_pkh: [OP_PKH_BYTES]u8 = [_]u8{0} ** OP_PKH_BYTES,
    verbose: bool = false,
};

fn parseArgs(allocator: std.mem.Allocator) !Args {
    var args = Args{};
    var it = try std.process.argsWithAllocator(allocator);
    defer it.deinit();
    _ = it.next(); // skip argv[0]
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--lmdb-dir=")) {
            args.lmdb_dir = arg["--lmdb-dir=".len..];
        } else if (std.mem.startsWith(u8, arg, "--op-pkh=")) {
            const hex = arg["--op-pkh=".len..];
            if (hex.len != OP_PKH_BYTES * 2) {
                std.debug.print(
                    "brain-backfill-cell-indices: --op-pkh must be {d} hex chars (= {d} bytes); got {d} chars\n",
                    .{ OP_PKH_BYTES * 2, OP_PKH_BYTES, hex.len },
                );
                return error.BadOpPkh;
            }
            try hexDecode(hex, args.op_pkh[0..]);
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            args.verbose = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        } else {
            std.debug.print("brain-backfill-cell-indices: unknown argument: {s}\n", .{arg});
            return error.UnknownArg;
        }
    }
    return args;
}

fn printUsage() void {
    std.debug.print("Usage: brain-backfill-cell-indices --lmdb-dir=<path> [options]\n\n", .{});
    std.debug.print("Required:\n", .{});
    std.debug.print("  --lmdb-dir=<path>     path to the cell-store LMDB env directory\n\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  --op-pkh=<16-hex>     8-byte operator prefix in lowercase hex\n", .{});
    std.debug.print("                        (default: all-zeros, matches single-tenant init)\n", .{});
    std.debug.print("  --verbose             log per-cell shape decisions to stderr\n", .{});
    std.debug.print("  -h, --help            print this help and exit\n", .{});
}

// ── Hex helpers ────────────────────────────────────────────────────────────

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

// ── Main ───────────────────────────────────────────────────────────────────

pub fn main() !void {
    // Page allocator: the migration is a one-shot CLI, lifetime ends at
    // process exit, so we don't need GPA's leak detection (which fires
    // SIGABRT on any leak — useful in tests, noisy in a CLI). Memory
    // released by the OS on exit instead.
    const allocator = std.heap.page_allocator;

    const args = parseArgs(allocator) catch |err| {
        std.debug.print("brain-backfill-cell-indices: argument error: {}\n", .{err});
        std.process.exit(1);
    };

    const lmdb_dir = args.lmdb_dir orelse {
        std.debug.print("brain-backfill-cell-indices: --lmdb-dir is required\n", .{});
        printUsage();
        std.process.exit(1);
    };

    if (args.verbose) {
        const op_pkh_hex = std.fmt.bytesToHex(args.op_pkh, .lower);
        std.debug.print(
            "brain-backfill-cell-indices: lmdb-dir={s} op-pkh={s}\n",
            .{ lmdb_dir, &op_pkh_hex },
        );
    }

    var env = try lmdb.Env.open(lmdb_dir, .{
        .max_dbs = 16,
        // 1 GiB headroom: cell rows are 4 KiB each + secondary index
        // entries are tiny (40–72 B keys, empty/1-B values). 1 GiB
        // covers ~250K cells worth of primary + every secondary index.
        // Matches the brain-migrate-entity-cells bin for consistency.
        .map_size = 1024 * 1024 * 1024,
        .open_flags = lmdb.EnvFlags.NOTLS,
    });
    defer env.close();

    var store = lmdb_cell_store.LmdbCellStore.initForOperator(&env, allocator, args.op_pkh) catch |e| {
        std.debug.print("brain-backfill-cell-indices: store init failed: {}\n", .{e});
        std.process.exit(2);
    };
    defer store.deinit();

    const report = store.backfillSecondaryIndices() catch |e| {
        std.debug.print("brain-backfill-cell-indices: backfill failed: {}\n", .{e});
        std.process.exit(2);
    };

    std.debug.print("=== brain-backfill-cell-indices report ===\n", .{});
    std.debug.print("cells_visited:             {d}\n", .{report.cells_visited});
    std.debug.print("owner_index_writes:        {d}\n", .{report.owner_index_writes});
    std.debug.print("prev_state_index_writes:   {d}\n", .{report.prev_state_index_writes});
    std.debug.print("anchor_status_writes:      {d}\n", .{report.anchor_status_writes});
    std.debug.print("anchor_txid_index_writes:  {d}\n", .{report.anchor_txid_index_writes});
    std.debug.print("(counts reflect index puts attempted; LMDB collapses same-key writes, so re-running this bin is a no-op.)\n", .{});
}

```
