---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/intent_cell_lmdb_store_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.195566+00:00
---

# runtime/semantos-brain/tests/intent_cell_lmdb_store_conformance.zig

```zig
// W0.3 — Conformance suite for `intent_cell_lmdb_store.zig`.
//
// Tests that intent cells (phase 0x06) can be stored and retrieved via
// LmdbCellStore.  Each test constructs its own tmp LMDB env so the DB is
// hermetic.  Verifies:
//
//   • put() → findById() round-trip
//   • cursor pulls intent cells back
//   • sir_program_hash is present and 32 bytes in the cell payload
//   • phase byte in the cell is 0x06 (PHASE_ACTION)
//   • idempotent put (same cell_id + same content → already_exists)
//   • count() reflects stored records

const std = @import("std");
const lmdb = @import("lmdb");
const lmdb_config = @import("lmdb_config");
const intent_cell_lmdb_store = @import("intent_cell_lmdb_store");

const PHASE_ACTION: u8 = 0x06;
const HEADER_OFFSET_COMMERCE_PHASE: usize = 94;
const PAYLOAD_OFFSET: usize = 256;
const SIR_HASH_OFFSET: usize = PAYLOAD_OFFSET; // first 32 bytes of payload

fn openEnv(tmp_dir: std.testing.TmpDir, allocator: std.mem.Allocator) !lmdb.Env {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp_dir.dir.realpath(".", &path_buf);
    const lmdb_path = try std.fs.path.join(allocator, &.{ dir_path, "lmdb" });
    defer allocator.free(lmdb_path);
    std.fs.makeDirAbsolute(lmdb_path) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
    return lmdb.Env.open(lmdb_path, .{
        .map_size = lmdb_config.LmdbConfig.default.map_size,
        .max_dbs = lmdb_config.LmdbConfig.default.max_dbs,
        .open_flags = lmdb_config.LmdbConfig.ci_flags,
        .mode = lmdb_config.LmdbConfig.default.mode,
    });
}

fn fixtureRecord() intent_cell_lmdb_store.IntentCellRecord {
    return .{
        .cell_id = "cell-000010-deadbeef-12345678",
        .hat_id = "hat-001",
        .cert_id = "cert-001",
        .correlation_id = "00000000-0000-4000-8000-000000000001",
        .opcount = 8,
        .stack_depth = 1,
        .gas_used = 8,
        .kernel_ok = true,
        .phone_kernel_result_json = "{\"ok\":true}",
        .opcode_bytes_b64 = "AA==",
        .intent_summary = "Find the wattle street job",
        .intent_action = "find",
        .intent_taxonomy_json = "{\"what\":\"jobs\"}",
        .received_at = "2026-05-07T14:36:00Z",
    };
}

test "intent_cell_lmdb_store: put → findById round-trip" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    var store = try intent_cell_lmdb_store.IntentCellLmdbStore.init(&env, allocator);
    defer store.deinit();

    const r = fixtureRecord();
    const result = try store.create(r);
    try std.testing.expectEqual(intent_cell_lmdb_store.CreateResult.created, result);

    const got = try store.findById(allocator, r.cell_id);
    defer if (got) |rec| rec.deinit(allocator);
    try std.testing.expect(got != null);
    try std.testing.expectEqualStrings(r.cell_id, got.?.record.cell_id);
    try std.testing.expectEqualStrings("find", got.?.record.intent_action);
    try std.testing.expectEqualStrings(r.intent_summary, got.?.record.intent_summary);
}

test "intent_cell_lmdb_store: phase byte is 0x06 in LMDB cell" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    var store = try intent_cell_lmdb_store.IntentCellLmdbStore.init(&env, allocator);
    defer store.deinit();

    const r = fixtureRecord();
    _ = try store.create(r);

    // Open a cursor on the cells DB and read the raw cell bytes.
    const cell_store = store.cellStore();
    const cursor = try cell_store.cursorOpen();
    defer cell_store.cursorClose(cursor);

    const cell_ptr = try cell_store.cursorPull(cursor);
    try std.testing.expect(cell_ptr != null);

    // Byte 94 is the commerce phase.
    try std.testing.expectEqual(PHASE_ACTION, cell_ptr.?[HEADER_OFFSET_COMMERCE_PHASE]);
}

test "intent_cell_lmdb_store: sir_program_hash is 32 bytes at payload offset" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    var store = try intent_cell_lmdb_store.IntentCellLmdbStore.init(&env, allocator);
    defer store.deinit();

    const r = fixtureRecord();
    _ = try store.create(r);

    const cell_store = store.cellStore();
    const cursor = try cell_store.cursorOpen();
    defer cell_store.cursorClose(cursor);

    const cell_ptr = try cell_store.cursorPull(cursor);
    try std.testing.expect(cell_ptr != null);

    // The sir_program_hash occupies bytes [PAYLOAD_OFFSET..PAYLOAD_OFFSET+32].
    // For M5.14 prereq these are all zero.
    const sir_hash = cell_ptr.?[SIR_HASH_OFFSET .. SIR_HASH_OFFSET + 32];
    for (sir_hash) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
}

test "intent_cell_lmdb_store: cursor pulls all stored cells" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    var store = try intent_cell_lmdb_store.IntentCellLmdbStore.init(&env, allocator);
    defer store.deinit();

    var r1 = fixtureRecord();
    r1.cell_id = "cell-000010-aaaaaa-00000001";
    var r2 = fixtureRecord();
    r2.cell_id = "cell-000010-aaaaaa-00000002";

    _ = try store.create(r1);
    _ = try store.create(r2);

    // Count must be 2.
    const n = try store.count();
    try std.testing.expectEqual(@as(u64, 2), n);

    // Cursor must yield exactly 2 cells.
    const cell_store = store.cellStore();
    const cursor = try cell_store.cursorOpen();
    defer cell_store.cursorClose(cursor);

    var pulled: usize = 0;
    while (try cell_store.cursorPull(cursor)) |_| {
        pulled += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), pulled);
}

test "intent_cell_lmdb_store: idempotent put with same content → already_exists" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    var store = try intent_cell_lmdb_store.IntentCellLmdbStore.init(&env, allocator);
    defer store.deinit();

    const r = fixtureRecord();
    try std.testing.expectEqual(intent_cell_lmdb_store.CreateResult.created, try store.create(r));
    try std.testing.expectEqual(intent_cell_lmdb_store.CreateResult.already_exists, try store.create(r));
    try std.testing.expectEqual(@as(u64, 1), try store.count());
}

test "intent_cell_lmdb_store: different cell_id with same hat_id" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    var store = try intent_cell_lmdb_store.IntentCellLmdbStore.init(&env, allocator);
    defer store.deinit();

    var r1 = fixtureRecord();
    r1.cell_id = "cell-000010-aaaaaa-hat-a-001";
    r1.hat_id = "hat-A";
    var r2 = fixtureRecord();
    r2.cell_id = "cell-000010-aaaaaa-hat-a-002";
    r2.hat_id = "hat-A";

    _ = try store.create(r1);
    _ = try store.create(r2);

    try std.testing.expectEqual(@as(u64, 2), try store.count());

    const got1 = try store.findById(allocator, r1.cell_id);
    defer if (got1) |rec| rec.deinit(allocator);
    try std.testing.expect(got1 != null);
    try std.testing.expectEqualStrings("hat-A", got1.?.record.hat_id);

    const got2 = try store.findById(allocator, r2.cell_id);
    defer if (got2) |rec| rec.deinit(allocator);
    try std.testing.expect(got2 != null);
    try std.testing.expectEqualStrings("hat-A", got2.?.record.hat_id);
}

test "intent_cell_lmdb_store: findById returns null for unknown cell_id" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    var store = try intent_cell_lmdb_store.IntentCellLmdbStore.init(&env, allocator);
    defer store.deinit();

    const got = try store.findById(allocator, "cell-000010-nonexistent-000");
    try std.testing.expectEqual(@as(?intent_cell_lmdb_store.OwnedRecord, null), got);
}

test "intent_cell_lmdb_store: list round-trip" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = try openEnv(tmp, allocator);
    defer env.close();

    var store = try intent_cell_lmdb_store.IntentCellLmdbStore.init(&env, allocator);
    defer store.deinit();

    var r1 = fixtureRecord();
    r1.cell_id = "cell-000010-list-00000001";
    var r2 = fixtureRecord();
    r2.cell_id = "cell-000010-list-00000002";

    _ = try store.create(r1);
    _ = try store.create(r2);

    const items = try store.list(allocator, .{});
    defer {
        for (items) |*item| item.deinit(allocator);
        allocator.free(items);
    }
    try std.testing.expectEqual(@as(usize, 2), items.len);
}

```
