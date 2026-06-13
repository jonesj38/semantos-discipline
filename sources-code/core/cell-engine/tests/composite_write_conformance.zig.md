---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/composite_write_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.961424+00:00
---

# core/cell-engine/tests/composite_write_conformance.zig

```zig
// M1.6 — CompositeWrite conformance tests.
//
// TDD red phase: written before the implementation.
// These tests define the atomic multi-cell write contract.
//
// The invariant: either all four cells land or none do.  A single LMDB
// write transaction spans all four store operations so the OS-level
// crash-safety guarantee (write txn is either committed or absent) covers
// the composite bundle.
//
// Test IDs: M1.6-T-commit, M1.6-T-abort, M1.6-T-partial-abort
//
// Run: zig build test-composite-write

const std = @import("std");
const lmdb = @import("lmdb");
const cell_store = @import("cell_store");
const composite_write = @import("composite_write");

// ── helpers ──────────────────────────────────────────────────────────────

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "/tmp/composite-write-test-{d}",
        .{std.time.nanoTimestamp()},
    );
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

fn makeCell(fill: u8) [cell_store.CELL_BYTES]u8 {
    var c: [cell_store.CELL_BYTES]u8 = undefined;
    @memset(&c, fill);
    return c;
}

fn makeOutpoint(txid_byte: u8, vout: u32) composite_write.Outpoint {
    var txid: [32]u8 = undefined;
    @memset(&txid, txid_byte);
    return .{ .txid = txid, .vout = vout };
}

fn makeOutputRecord(txid_byte: u8, vout: u32) composite_write.OutputRecord {
    var txid: [32]u8 = undefined;
    @memset(&txid, txid_byte);
    return .{
        .outpoint = .{ .txid = txid, .vout = vout },
        .satoshis = 1000,
        .locking_script = &[_]u8{ 0x76, 0xa9 },
        .derived_key_hash = [_]u8{txid_byte} ** 32,
        .derivation_protocol_hash = [_]u8{txid_byte} ** 16,
        .derivation_counterparty = [_]u8{txid_byte} ** 33,
        .derivation_index = 0,
        .beef = &[_]u8{},
        .basket = "default",
        .tags = &[_]u8{},
        .custom_instructions = &[_]u8{},
        .confirmations = 0,
        .status = .unspent,
        .spending_txid = [_]u8{0} ** 32,
    };
}

fn makeHeaderRecord(height: u32) composite_write.HeaderRecord {
    return .{
        .height = height,
        .header = .{
            .version = 1,
            .prev_hash = [_]u8{0} ** 32,
            .merkle_root = [_]u8{0xAB} ** 32,
            .timestamp = 1_700_000_000,
            .bits = 0x1d00ffff,
            .nonce = 42,
        },
        .hash = [_]u8{0xCD} ** 32,
    };
}

fn makeEnvelope(id_byte: u8) composite_write.Envelope {
    var id: [32]u8 = undefined;
    @memset(&id, id_byte);
    return .{
        .id = id,
        .payload = &[_]u8{ 0x01, 0x02, 0x03 },
    };
}

// ── M1.6-T-commit ────────────────────────────────────────────────────────

test "M1.6: commit → all four records readable" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    // Prepare store instances (they open their named DBs).
    var cell_s = try composite_write.LmdbCellStore.init(&env, allocator);
    defer cell_s.deinit();
    var output_s = try composite_write.LmdbOutputStore.init(&env, allocator);
    defer output_s.deinit();
    var header_s = try composite_write.LmdbHeaderStore.init(&env, allocator);
    defer header_s.deinit();

    // Fixtures.
    const cell = makeCell(0xA1);
    const op = makeOutpoint(0xB2, 0);
    const output = makeOutputRecord(0xB2, 0);
    const header_rec = makeHeaderRecord(0);
    const envelope = makeEnvelope(0xD4);

    // Compute expected cell hash.
    var expected_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&cell, &expected_hash, .{});

    // Composite write, commit.
    var cw = try composite_write.CompositeWrite.begin(&env, &cell_s, &output_s, &header_s);
    try cw.putCell(&cell);
    try cw.putBump(op, output);
    try cw.putBeef(header_rec.hash, header_rec);
    try cw.putEnvelope(envelope);
    try cw.commit();

    // Verify cell.
    const cell_store_v = cell_s.store();
    try std.testing.expect(cell_store_v.exists(&expected_hash));

    // Verify output (BUMP).
    const output_store_v = output_s.store();
    const got_output = output_store_v.getOutput(op);
    try std.testing.expect(got_output != null);
    try std.testing.expectEqual(@as(u64, 1000), got_output.?.satoshis);

    // Verify header (BEEF).
    const header_store_v = header_s.store();
    const got_header = header_store_v.getByHash(&header_rec.hash);
    try std.testing.expect(got_header != null);
    try std.testing.expectEqual(@as(u32, 0), got_header.?.height);

    // Verify envelope.
    var rtxn = try env.beginTxn(.read_only);
    defer rtxn.abort();
    const env_dbi = try rtxn.openDb("envelopes", .{ .create = false });
    const raw = try rtxn.get(env_dbi, &envelope.id);
    try std.testing.expectEqualSlices(u8, envelope.payload, raw);
}

// ── M1.6-T-abort ─────────────────────────────────────────────────────────

test "M1.6: abort → none of the four records visible" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var cell_s = try composite_write.LmdbCellStore.init(&env, allocator);
    defer cell_s.deinit();
    var output_s = try composite_write.LmdbOutputStore.init(&env, allocator);
    defer output_s.deinit();
    var header_s = try composite_write.LmdbHeaderStore.init(&env, allocator);
    defer header_s.deinit();

    const cell = makeCell(0x11);
    const op = makeOutpoint(0x22, 1);
    const output = makeOutputRecord(0x22, 1);
    const header_rec = makeHeaderRecord(1);
    const envelope = makeEnvelope(0x33);

    var expected_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&cell, &expected_hash, .{});

    var cw = try composite_write.CompositeWrite.begin(&env, &cell_s, &output_s, &header_s);
    try cw.putCell(&cell);
    try cw.putBump(op, output);
    try cw.putBeef(header_rec.hash, header_rec);
    try cw.putEnvelope(envelope);
    cw.abort(); // <── explicit abort

    // None of the records should be visible.
    const cell_store_v = cell_s.store();
    try std.testing.expect(!cell_store_v.exists(&expected_hash));

    const output_store_v = output_s.store();
    try std.testing.expect(output_store_v.getOutput(op) == null);

    const header_store_v = header_s.store();
    try std.testing.expect(header_store_v.getByHash(&header_rec.hash) == null);

    // Envelope DB: after abort the DB may not exist yet (if this is the
    // first write attempt).  Open it in a write txn with create=true so we
    // can perform the negative read — if the key is absent, mdb_get returns
    // MDB_NOTFOUND which our wrapper surfaces as error.not_found.
    {
        var wtxn = try env.beginTxn(.read_write);
        const env_dbi = try wtxn.openDb("envelopes", .{ .create = true });
        const result = wtxn.get(env_dbi, &envelope.id);
        wtxn.abort();
        try std.testing.expectError(error.not_found, result);
    }
}

// ── M1.6-T-partial-abort ─────────────────────────────────────────────────

test "M1.6: partial write (3 of 4) + abort → none readable" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var cell_s = try composite_write.LmdbCellStore.init(&env, allocator);
    defer cell_s.deinit();
    var output_s = try composite_write.LmdbOutputStore.init(&env, allocator);
    defer output_s.deinit();
    var header_s = try composite_write.LmdbHeaderStore.init(&env, allocator);
    defer header_s.deinit();

    const cell = makeCell(0x55);
    const op = makeOutpoint(0x66, 2);
    const output = makeOutputRecord(0x66, 2);
    const header_rec = makeHeaderRecord(2);

    var expected_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&cell, &expected_hash, .{});

    // Write only three of four, then abort (simulates mid-write crash / error).
    var cw = try composite_write.CompositeWrite.begin(&env, &cell_s, &output_s, &header_s);
    try cw.putCell(&cell);
    try cw.putBump(op, output);
    try cw.putBeef(header_rec.hash, header_rec);
    // intentionally skip putEnvelope — simulate partial write
    cw.abort();

    // All three already-queued writes must be gone.
    const cell_store_v = cell_s.store();
    try std.testing.expect(!cell_store_v.exists(&expected_hash));

    const output_store_v = output_s.store();
    try std.testing.expect(output_store_v.getOutput(op) == null);

    const header_store_v = header_s.store();
    try std.testing.expect(header_store_v.getByHash(&header_rec.hash) == null);
}

```
