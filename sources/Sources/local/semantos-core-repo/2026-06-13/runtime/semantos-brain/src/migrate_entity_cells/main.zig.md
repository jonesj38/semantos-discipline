---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/migrate_entity_cells/main.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.290351+00:00
---

# runtime/semantos-brain/src/migrate_entity_cells/main.zig

```zig
// RM-115 — brain-migrate-entity-cells: convert legacy entity_cell-format
// rows in the "cells" DB to the substrate cell format produced by
// substrate_entity.zig. (+ read-only --census forensic mode.)
//
// Usage:
//   brain-migrate-entity-cells --lmdb-dir=<path> \
//                              [--owner-id=<32-hex>] \
//                              [--dry-run] [--verbose]
//
// The tool opens the LMDB env at <lmdb-dir>, cursor-scans the `cells` DB,
// and for every row:
//
//   1. Peeks bytes [0..4]. If equal to substrate magic (0xDEADBEEF LE),
//      the cell is already substrate-format → counted as `skipped` and
//      left untouched.
//   2. Otherwise treats the row as legacy entity_cell:
//        offset  0..4    entity_tag        u32 LE
//        offset  4..8    version           u32 LE   (= 1)
//        offset  8..12   payload_len       u32 LE
//        offset 12..16   pad
//        offset 16..16+N JSON payload
//      Looks up the EntityTypeSpec by tag. If the tag isn't one of the
//      8 known oddjobz entity tags → counted as `unknown_tag_skipped`.
//   3. Derives a linearity class from the payload's `"state"` /
//      `"status"` field (via `substrate_entity.extractStateOrStatus` +
//      `linearityFor`).
//   4. Encodes a substrate cell with the matched spec, the derived
//      linearity, and the supplied --owner-id (or all-zeros default,
//      matching the in-store writers).
//   5. In a single LMDB write transaction: deletes the old key
//      (op_pkh ‖ legacy_hash) and puts the new cell under its new
//      key (op_pkh ‖ sha256(new_cell)).
//
// Idempotent. Safe to re-run — already-substrate cells are skipped.
// Crash-safe — the delete + put for any one cell happens inside the
// same write txn. If the process dies mid-run, partial commits are
// limited to a per-batch boundary (we commit every BATCH_SIZE rows).

const std = @import("std");
const lmdb = @import("lmdb");
const entity_cell = @import("entity_cell");
const substrate_entity = @import("substrate_entity");

const CELL_BYTES: usize = 1024;
/// Same op_pkh ‖ hash key as cell_store_lmdb.zig.
const OP_PKH_BYTES: usize = 8;
const KEY_BYTES: usize = OP_PKH_BYTES + 32;
const VALUE_BYTES: usize = 4096; // matches cell_store.VALUE_BYTES
const BATCH_SIZE: usize = 256;

// ── CLI argument parsing ───────────────────────────────────────────────────

const Args = struct {
    lmdb_dir: ?[]const u8 = null,
    owner_id: [16]u8 = [_]u8{0} ** 16,
    dry_run: bool = false,
    verbose: bool = false,
    /// Read-only forensic mode: scan every cell and tally, per distinct
    /// 8-byte `op_pkh` key-prefix, the substrate/legacy split + entity-
    /// kind histogram + distinct header owner_ids. NO writes, NO write
    /// txn, NO write lock — safe to run against a live store concurrently
    /// with the daemon (LMDB MVCC, NOTLS). Used to confirm/deny the
    /// "146 invisible due to op_pkh key-scope mismatch" hypothesis
    /// (the per-operator `find jobs` cursor scans one op_pkh prefix;
    /// migrated cells keep their ingest-time op_pkh).
    census: bool = false,
};

fn parseArgs(allocator: std.mem.Allocator) !Args {
    var args = Args{};
    var it = try std.process.argsWithAllocator(allocator);
    defer it.deinit();
    _ = it.next(); // skip argv[0]
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--lmdb-dir=")) {
            args.lmdb_dir = arg["--lmdb-dir=".len..];
        } else if (std.mem.startsWith(u8, arg, "--owner-id=")) {
            const hex = arg["--owner-id=".len..];
            if (hex.len != 32) {
                std.debug.print("brain-migrate-entity-cells: --owner-id must be 32 hex chars (= 16 bytes); got {} chars\n", .{hex.len});
                return error.BadOwnerId;
            }
            try hexDecode(hex, args.owner_id[0..]);
        } else if (std.mem.eql(u8, arg, "--census")) {
            args.census = true;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            args.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            args.verbose = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        } else {
            std.debug.print("brain-migrate-entity-cells: unknown argument: {s}\n", .{arg});
            return error.UnknownArg;
        }
    }
    return args;
}

fn printUsage() void {
    std.debug.print("Usage: brain-migrate-entity-cells --lmdb-dir=<path> [options]\n\n", .{});
    std.debug.print("Required:\n", .{});
    std.debug.print("  --lmdb-dir=<path>     path to the cell-store LMDB env directory\n\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  --owner-id=<32-hex>   16-byte owner_id to embed in substrate headers\n", .{});
    std.debug.print("                        (default: all-zeros, matches in-store writers)\n", .{});
    std.debug.print("  --census              READ-ONLY forensic: per op_pkh key-prefix\n", .{});
    std.debug.print("                        tally (substrate/legacy + entity-kind +\n", .{});
    std.debug.print("                        header owner_ids). No writes/write-lock —\n", .{});
    std.debug.print("                        safe alongside a live daemon.\n", .{});
    std.debug.print("  --dry-run             scan only -- no writes\n", .{});
    std.debug.print("  --verbose             log per-cell decisions to stderr\n", .{});
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

// ── Stats ──────────────────────────────────────────────────────────────────

const Stats = struct {
    seen: usize = 0,
    migrated: usize = 0,
    already_substrate: usize = 0,
    unknown_tag_skipped: usize = 0,
    too_large_skipped: usize = 0,
    payload_overflow_skipped: usize = 0,
    errors: usize = 0,

    fn print(self: Stats) void {
        std.debug.print("seen: {d}\n", .{self.seen});
        std.debug.print("migrated: {d}\n", .{self.migrated});
        std.debug.print("already-substrate (skipped): {d}\n", .{self.already_substrate});
        std.debug.print("unknown-tag (skipped): {d}\n", .{self.unknown_tag_skipped});
        std.debug.print("value-too-small (skipped): {d}\n", .{self.too_large_skipped});
        std.debug.print("payload-overflow (skipped): {d}\n", .{self.payload_overflow_skipped});
        std.debug.print("errors: {d}\n", .{self.errors});
    }
};

// ── Cell classification ────────────────────────────────────────────────────

/// Substrate magic_1 at offset 0 (LE u32).
const SUBSTRATE_MAGIC_1: u32 = 0xDEADBEEF;

fn isSubstrate(cell: *const [CELL_BYTES]u8) bool {
    return std.mem.readInt(u32, cell[0..4], .little) == SUBSTRATE_MAGIC_1;
}

// ── Per-row migration ──────────────────────────────────────────────────────

const RowAction = union(enum) {
    skip_already_substrate,
    skip_unknown_tag: u32,
    skip_payload_overflow,
    rewrite: [CELL_BYTES]u8,
};

fn classifyRow(cell: *const [CELL_BYTES]u8, owner_id: [16]u8) RowAction {
    if (isSubstrate(cell)) return .skip_already_substrate;

    const tag = entity_cell.cellEntityTag(cell);
    const spec_opt = substrate_entity.specByTag(tag);
    if (spec_opt == null) return .{ .skip_unknown_tag = tag };
    const spec = spec_opt.?;

    const payload = entity_cell.cellPayload(cell);
    if (payload.len > substrate_entity.PAYLOAD_BUDGET) {
        // Legacy entity_cell allowed 1008-byte payloads; substrate
        // header budget is 768. Anything larger can't fit — flag and
        // skip rather than silently truncate.
        return .skip_payload_overflow;
    }

    const state = substrate_entity.extractStateOrStatus(payload);
    const linearity = substrate_entity.linearityFor(tag, state);

    const new_cell = substrate_entity.encodeEntity(.{
        .spec = spec,
        .linearity = linearity,
        .owner_id = owner_id,
        .payload_json = payload,
    }) catch return .skip_payload_overflow;

    return .{ .rewrite = new_cell };
}

// ── LMDB scan + rewrite ────────────────────────────────────────────────────

fn sha256(bytes: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &out, .{});
    return out;
}

fn buildKey(op_pkh: []const u8, hash: *const [32]u8) [KEY_BYTES]u8 {
    var key: [KEY_BYTES]u8 = undefined;
    std.debug.assert(op_pkh.len == OP_PKH_BYTES);
    @memcpy(key[0..OP_PKH_BYTES], op_pkh[0..OP_PKH_BYTES]);
    @memcpy(key[OP_PKH_BYTES..], hash);
    return key;
}

const PendingRewrite = struct {
    old_key: [KEY_BYTES]u8,
    new_value: [VALUE_BYTES]u8,
};

fn runMigration(
    allocator: std.mem.Allocator,
    env: *lmdb.Env,
    owner_id: [16]u8,
    dry_run: bool,
    verbose: bool,
) !Stats {
    var stats = Stats{};

    // Open the "cells" DB once; LMDB requires DB handles to be opened
    // inside a txn but the handle itself outlives the txn so we can
    // reuse it across batches.
    var dbi: lmdb.Dbi = undefined;
    {
        var setup_txn = try env.beginTxn(.read_write);
        errdefer setup_txn.abort();
        dbi = setup_txn.openDb("cells", .{ .create = false }) catch |e| {
            setup_txn.abort();
            return e;
        };
        try setup_txn.commit();
    }

    // Single full read-only scan: classify every cell, accumulate the
    // pending rewrites in memory (copies — cursor slices die with the
    // txn). Then apply the rewrites in BATCH_SIZE chunks under separate
    // write transactions. We can't write inside an LMDB read cursor's
    // txn, so the two-phase pattern is mandatory.
    //
    // Capacity sketch for an "old" production env: 100K cells × 4 KiB
    // ≈ 400 MiB of pending-rewrites in RAM. For the rbs migration this
    // is comfortably under-budget; if needed we can chunk the scan by
    // op_pkh range in a follow-up.

    var pending: std.ArrayList(PendingRewrite) = .{};
    defer pending.deinit(allocator);

    {
        var scan_txn = try env.beginTxn(.read_only);
        defer scan_txn.abort();
        var cursor = try scan_txn.openCursor(dbi);
        defer cursor.close();

        var entry_opt = cursor.next() catch null;
        while (entry_opt) |entry| : (entry_opt = cursor.next() catch null) {
            if (entry.val.len < CELL_BYTES) {
                stats.too_large_skipped += 1;
                continue;
            }
            stats.seen += 1;
            const cell: *const [CELL_BYTES]u8 = @ptrCast(entry.val.ptr);
            const action = classifyRow(cell, owner_id);
            switch (action) {
                .skip_already_substrate => {
                    stats.already_substrate += 1;
                },
                .skip_unknown_tag => |t| {
                    if (verbose) std.debug.print("skip unknown_tag={x}\n", .{t});
                    stats.unknown_tag_skipped += 1;
                },
                .skip_payload_overflow => {
                    stats.payload_overflow_skipped += 1;
                },
                .rewrite => |new_cell| {
                    if (entry.key.len != KEY_BYTES) {
                        stats.errors += 1;
                        continue;
                    }
                    var pr: PendingRewrite = undefined;
                    @memcpy(pr.old_key[0..], entry.key);
                    pr.new_value = [_]u8{0} ** VALUE_BYTES;
                    @memcpy(pr.new_value[0..CELL_BYTES], new_cell[0..]);
                    pending.append(allocator, pr) catch return error.OutOfMemory;
                },
            }
        }
    }

    if (dry_run) {
        stats.migrated = pending.items.len;
        return stats;
    }

    // Apply pending rewrites in BATCH_SIZE chunks under separate write txns.
    var idx: usize = 0;
    while (idx < pending.items.len) {
        const end = @min(idx + BATCH_SIZE, pending.items.len);
        var write_txn = try env.beginTxn(.read_write);
        errdefer write_txn.abort();
        for (pending.items[idx..end]) |pr| {
            // Derive the new key from the new cell bytes.
            const new_hash = sha256(pr.new_value[0..CELL_BYTES]);
            const new_key = buildKey(pr.old_key[0..OP_PKH_BYTES], &new_hash);

            // Delete the old key. If it's already gone (shouldn't happen
            // mid-run) we treat that as a no-op.
            write_txn.del(dbi, &pr.old_key, null) catch |e| {
                if (e != error.not_found) {
                    stats.errors += 1;
                    continue;
                }
            };
            // Put the new cell under its new key. NOOVERWRITE in case
            // some concurrent path beat us to it.
            write_txn.put(dbi, &new_key, &pr.new_value, .{ .no_overwrite = true }) catch |e| {
                if (e != error.key_exists) {
                    stats.errors += 1;
                    continue;
                }
            };
            stats.migrated += 1;
            if (verbose) std.debug.print("migrated 1 cell\n", .{});
        }
        try write_txn.commit();
        idx = end;
    }

    return stats;
}

// ── Read-only census (forensic) ────────────────────────────────────────────

/// Human label for a substrate `domain_flag` (oddjobz per-entity flags,
/// `substrate_entity.zig` SPEC_* table). Unknown → "other".
fn kindForDomainFlag(df: u32) []const u8 {
    return switch (df) {
        0x00010107 => "job",
        0x00010108 => "customer",
        0x00010109 => "visit",
        0x0001010B => "quote",
        0x0001010C => "invoice",
        0x0001010D => "attachment",
        0x0001010E => "site",
        0x0001010F => "lead",
        0x00010111 => "estimate",
        else => "other",
    };
}

/// Legacy `entity_cell` tag → label (pre-substrate cells).
fn kindForLegacyTag(tag: u32) []const u8 {
    return switch (tag) {
        0x01 => "customer",
        0x06 => "job",
        else => "other",
    };
}

const Bucket = struct {
    total: usize = 0,
    substrate: usize = 0,
    legacy: usize = 0,
    job: usize = 0,
    customer: usize = 0,
    other: usize = 0,
    /// Up to 4 distinct substrate header owner_ids seen under this
    /// key-prefix (hex16). The header owner_id is independent of the
    /// 8-byte key op_pkh — both are reported so a key/owner skew is
    /// visible.
    owner_ids: [4][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 4,
    owner_id_count: usize = 0,

    fn noteOwner(self: *Bucket, oid: [16]u8) void {
        var i: usize = 0;
        while (i < self.owner_id_count) : (i += 1) {
            if (std.mem.eql(u8, &self.owner_ids[i], &oid)) return;
        }
        if (self.owner_id_count < self.owner_ids.len) {
            self.owner_ids[self.owner_id_count] = oid;
            self.owner_id_count += 1;
        }
    }
};

/// READ-ONLY: one read txn, one read cursor, abort. Never opens a write
/// txn, so it cannot take the LMDB write mutex or block the daemon.
fn runCensus(allocator: std.mem.Allocator, env: *lmdb.Env) !void {
    var buckets = std.AutoHashMap([OP_PKH_BYTES]u8, Bucket).init(allocator);
    defer buckets.deinit();

    // LMDB requires the FIRST `mdb_dbi_open` of a named DB in this
    // process to happen inside a write txn (a read-only txn that has
    // never seen the DBI returns MDB_BAD_DBI → null deref in the
    // wrapper). Mirror runMigration: open+commit the handle in a
    // throwaway write txn (NO data writes — dbi-open only, so it is
    // effectively read-only in effect), then do the actual scan in a
    // read-only txn. We run against a COPY of the store anyway.
    var dbi: lmdb.Dbi = undefined;
    {
        var setup_txn = try env.beginTxn(.read_write);
        errdefer setup_txn.abort();
        dbi = setup_txn.openDb("cells", .{ .create = false }) catch |e| {
            setup_txn.abort();
            std.debug.print("census: openDb(\"cells\") failed: {} (store empty or different DBI name)\n", .{e});
            return e;
        };
        try setup_txn.commit();
    }

    var scan_txn = try env.beginTxn(.read_only);
    defer scan_txn.abort();
    var cursor = try scan_txn.openCursor(dbi);
    defer cursor.close();

    var total_keys: usize = 0;
    var short_keys: usize = 0;
    var short_vals: usize = 0;

    var entry_opt = cursor.next() catch null;
    while (entry_opt) |entry| : (entry_opt = cursor.next() catch null) {
        total_keys += 1;
        if (entry.key.len < OP_PKH_BYTES) {
            short_keys += 1;
            continue;
        }
        var prefix: [OP_PKH_BYTES]u8 = undefined;
        @memcpy(&prefix, entry.key[0..OP_PKH_BYTES]);
        const gop = try buckets.getOrPut(prefix);
        if (!gop.found_existing) gop.value_ptr.* = Bucket{};
        const b = gop.value_ptr;
        b.total += 1;

        if (entry.val.len < CELL_BYTES) {
            short_vals += 1;
            b.other += 1;
            continue;
        }
        const cell: *const [CELL_BYTES]u8 = @ptrCast(entry.val.ptr);
        const dec = substrate_entity.decodeEntity(cell);
        var kind: []const u8 = "other";
        if (dec.magic_ok) {
            b.substrate += 1;
            b.noteOwner(dec.owner_id);
            kind = kindForDomainFlag(dec.domain_flag);
        } else {
            b.legacy += 1;
            kind = kindForLegacyTag(entity_cell.cellEntityTag(cell));
        }
        if (std.mem.eql(u8, kind, "job")) {
            b.job += 1;
        } else if (std.mem.eql(u8, kind, "customer")) {
            b.customer += 1;
        } else {
            b.other += 1;
        }
    }

    std.debug.print("=== entity_cells census (READ-ONLY) ===\n", .{});
    std.debug.print("total keys: {d}  short-keys: {d}  short-values: {d}  distinct op_pkh prefixes: {d}\n\n", .{
        total_keys, short_keys, short_vals, buckets.count(),
    });
    var it = buckets.iterator();
    while (it.next()) |kv| {
        const p = kv.key_ptr.*;
        const b = kv.value_ptr.*;
        const p_hex = std.fmt.bytesToHex(p, .lower);
        std.debug.print(
            "op_pkh={s} | total={d} substrate={d} legacy={d} | job={d} customer={d} other={d} | owner_ids[{d}]:",
            .{ &p_hex, b.total, b.substrate, b.legacy, b.job, b.customer, b.other, b.owner_id_count },
        );
        var i: usize = 0;
        while (i < b.owner_id_count) : (i += 1) {
            const oid_hex = std.fmt.bytesToHex(b.owner_ids[i], .lower);
            std.debug.print(" {s}", .{&oid_hex});
        }
        std.debug.print("\n", .{});
    }
    std.debug.print(
        "\nInterpretation: if the 6 visible probe jobs and the ~146/106 ingested\n" ++
            "entities fall under DIFFERENT op_pkh prefixes, the per-operator\n" ++
            "`find jobs` cursor (scoped to one prefix) explains the invisibility.\n",
        .{},
    );
}

// ── Main ──────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = parseArgs(allocator) catch |err| {
        std.debug.print("brain-migrate-entity-cells: argument error: {}\n", .{err});
        std.process.exit(1);
    };

    const lmdb_dir = args.lmdb_dir orelse {
        std.debug.print("brain-migrate-entity-cells: --lmdb-dir is required\n", .{});
        printUsage();
        std.process.exit(1);
    };

    if (args.verbose) {
        std.debug.print(
            "brain-migrate-entity-cells: lmdb-dir={s} dry-run={} owner-id-zero={}\n",
            .{ lmdb_dir, args.dry_run, std.mem.allEqual(u8, args.owner_id[0..], 0) },
        );
    }

    var env = try lmdb.Env.open(lmdb_dir, .{
        .max_dbs = 16,
        .map_size = 1024 * 1024 * 1024, // 1 GiB headroom; cell rows are 4 KiB each
        .open_flags = lmdb.EnvFlags.NOTLS,
    });
    defer env.close();

    if (args.census) {
        runCensus(allocator, &env) catch |e| {
            std.debug.print("brain-migrate-entity-cells: census error: {}\n", .{e});
            std.process.exit(2);
        };
        return;
    }

    const stats = try runMigration(
        allocator,
        &env,
        args.owner_id,
        args.dry_run,
        args.verbose,
    );

    stats.print();
    if (stats.errors > 0) std.process.exit(2);
}

```
