---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/intent_cells_store_fs_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.199428+00:00
---

# runtime/semantos-brain/tests/intent_cells_store_fs_conformance.zig

```zig
// Phase 3 — Conformance suite for `intent_cells_store_fs.zig`.
//
// Mirrors `leads_store_fs_conformance.zig`'s shape: each test
// constructs its own tmp data dir + IntentCellsStore so the JSONL
// log is hermetic, asserts the round-trip / idempotency / dangling-
// slice properties, then tears down.
//
// What this closes:
//
//   • create / findById / list round-trip
//   • Idempotency on cellId: same content → already_exists; different
//     content → cell_id_in_use_with_different_contents
//   • list filters: hat_id, since (ISO-8601 lexicographic), limit
//   • Replay rebuilds the in-memory state from the JSONL log
//   • Dangling-slice avoidance: 1500+ records appended in a tight
//     loop without a HashMap-key panic (the post-#422 hazard the
//     per-record OwnedStrings pattern guards against)

const std = @import("std");
const intent_cells_store_fs = @import("intent_cells_store_fs");

fn pinnedClock() i64 {
    return 1_700_000_000;
}

fn baseRecord() intent_cells_store_fs.IntentCellRecord {
    return .{
        .cell_id = "cell-000010-deadbeef-12345678",
        .hat_id = "hat-001",
        .cert_id = "cert-001",
        .correlation_id = "00000000-0000-4000-8000-000000000001",
        .opcount = 1,
        .stack_depth = 1,
        .gas_used = 1,
        .kernel_ok = true,
        .phone_kernel_result_json = "{\"ok\":true,\"opcount\":1,\"stackDepth\":1,\"gasUsed\":1,\"errorKind\":null}",
        // PR-2b: real-executor accept = single OP_1 (0x51 = base64 "UQ==").
        // Replaces the pre-PR-2b synthetic `01 58 07 "summary" b0 87 9a ...`
        // fixture which failed under real executor with stack_underflow
        // (push 'X', push "summary", OP_NOP1, OP_EQUAL → [0], OP_BOOLAND
        // needs 2 items has 1).  Single OP_1 = minimal valid accept.
        .opcode_bytes_b64 = "UQ==",
        .intent_summary = "Find the wattle street job",
        .intent_action = "find",
        .intent_taxonomy_json = "{\"what\":\"jobs\",\"how\":\"find\",\"why\":\"navigate\"}",
        .received_at = "2026-05-07T14:36:00Z",
    };
}

test "intent_cells store: create → findById → list round-trip" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try intent_cells_store_fs.IntentCellsStore.init(allocator, data_dir, pinnedClock);
    defer store.deinit();

    const r = baseRecord();
    try std.testing.expectEqual(intent_cells_store_fs.CreateResult.created, try store.create(r));

    const got = store.findById(r.cell_id) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings(r.cell_id, got.cell_id);
    try std.testing.expectEqualStrings(r.intent_action, got.intent_action);

    const list = try store.list(allocator, .{});
    defer allocator.free(list);
    try std.testing.expectEqual(@as(usize, 1), list.len);
}

test "intent_cells store: idempotent re-create with same content" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try intent_cells_store_fs.IntentCellsStore.init(allocator, data_dir, pinnedClock);
    defer store.deinit();

    const r = baseRecord();
    try std.testing.expectEqual(intent_cells_store_fs.CreateResult.created, try store.create(r));
    try std.testing.expectEqual(intent_cells_store_fs.CreateResult.already_exists, try store.create(r));
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

test "intent_cells store: cellId reuse with different content errors (first-write-wins)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try intent_cells_store_fs.IntentCellsStore.init(allocator, data_dir, pinnedClock);
    defer store.deinit();

    var r = baseRecord();
    _ = try store.create(r);
    r.intent_summary = "Different summary";
    try std.testing.expectError(
        intent_cells_store_fs.StoreError.cell_id_in_use_with_different_contents,
        store.create(r),
    );

    // First write wins.
    const got = store.findById(r.cell_id) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("Find the wattle street job", got.intent_summary);
}

test "intent_cells store: list filters on hat_id" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try intent_cells_store_fs.IntentCellsStore.init(allocator, data_dir, pinnedClock);
    defer store.deinit();

    var r1 = baseRecord();
    r1.cell_id = "cell-000010-deadbeef-aaaaaaa1";
    r1.hat_id = "hat-A";
    _ = try store.create(r1);

    var r2 = baseRecord();
    r2.cell_id = "cell-000010-deadbeef-aaaaaaa2";
    r2.hat_id = "hat-B";
    _ = try store.create(r2);

    const filtered = try store.list(allocator, .{ .hat_id = "hat-A" });
    defer allocator.free(filtered);
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqualStrings("hat-A", filtered[0].hat_id);
}

test "intent_cells store: list filters on since (ISO-8601 lexicographic)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try intent_cells_store_fs.IntentCellsStore.init(allocator, data_dir, pinnedClock);
    defer store.deinit();

    var r1 = baseRecord();
    r1.cell_id = "cell-000010-deadbeef-zzzzzzz1";
    r1.received_at = "2026-01-01T00:00:00Z";
    _ = try store.create(r1);

    var r2 = baseRecord();
    r2.cell_id = "cell-000010-deadbeef-zzzzzzz2";
    r2.received_at = "2026-06-01T00:00:00Z";
    _ = try store.create(r2);

    const recent = try store.list(allocator, .{ .since = "2026-03-01T00:00:00Z" });
    defer allocator.free(recent);
    try std.testing.expectEqual(@as(usize, 1), recent.len);
    try std.testing.expectEqualStrings("2026-06-01T00:00:00Z", recent[0].received_at);
}

test "intent_cells store: list applies limit (tail-cut: most-recent N)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try intent_cells_store_fs.IntentCellsStore.init(allocator, data_dir, pinnedClock);
    defer store.deinit();

    inline for (.{ "1", "2", "3" }) |suffix| {
        var r = baseRecord();
        r.cell_id = "cell-000010-deadbeef-aaaaaaa" ++ suffix;
        _ = try store.create(r);
    }
    const last_two = try store.list(allocator, .{ .limit = 2 });
    defer allocator.free(last_two);
    try std.testing.expectEqual(@as(usize, 2), last_two.len);
    try std.testing.expectEqualStrings("cell-000010-deadbeef-aaaaaaa2", last_two[0].cell_id);
    try std.testing.expectEqualStrings("cell-000010-deadbeef-aaaaaaa3", last_two[1].cell_id);
}

test "intent_cells store: replay rebuilds in-memory state from JSONL" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    {
        var store = try intent_cells_store_fs.IntentCellsStore.init(allocator, data_dir, pinnedClock);
        defer store.deinit();
        _ = try store.create(baseRecord());
    }

    var store2 = try intent_cells_store_fs.IntentCellsStore.init(allocator, data_dir, pinnedClock);
    defer store2.deinit();
    try std.testing.expectEqual(@as(usize, 1), store2.count());
    const got = store2.findById("cell-000010-deadbeef-12345678") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("find", got.intent_action);
}

test "intent_cells store: dangling-slice avoidance over 1500 records" {
    // Exercises the per-record OwnedStrings pattern: every record's
    // string fields are individually heap-allocated.  If any of them
    // were stored in a shared `ArrayList(u8)` arena, the realloc on
    // grow would invalidate prior HashMap keys and the next put would
    // panic with "reached unreachable code" inside std HashMap.  This
    // test runs 1500 distinct records through `create` in a tight
    // loop and asserts the index stays consistent.
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try intent_cells_store_fs.IntentCellsStore.init(allocator, data_dir, pinnedClock);
    defer store.deinit();

    var i: usize = 0;
    while (i < 1500) : (i += 1) {
        var id_buf: [40]u8 = undefined;
        const id = try std.fmt.bufPrint(&id_buf, "cell-000010-deadbeef-{d:0>8}", .{i});
        var r = baseRecord();
        r.cell_id = id;
        const result = try store.create(r);
        try std.testing.expectEqual(intent_cells_store_fs.CreateResult.created, result);
    }
    try std.testing.expectEqual(@as(usize, 1500), store.count());

    // Spot-check: random middle id resolves correctly.
    var probe_buf: [40]u8 = undefined;
    const probe_id = try std.fmt.bufPrint(&probe_buf, "cell-000010-deadbeef-{d:0>8}", .{777});
    const got = store.findById(probe_id) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings(probe_id, got.cell_id);
}

test "intent_cells store: validates length envelopes on create" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try intent_cells_store_fs.IntentCellsStore.init(allocator, data_dir, pinnedClock);
    defer store.deinit();

    var r = baseRecord();
    r.cell_id = "";
    try std.testing.expectError(intent_cells_store_fs.StoreError.invalid_cell_id, store.create(r));

    r = baseRecord();
    r.intent_action = "";
    try std.testing.expectError(intent_cells_store_fs.StoreError.invalid_intent_action, store.create(r));

    r = baseRecord();
    r.intent_summary = "";
    try std.testing.expectError(intent_cells_store_fs.StoreError.invalid_intent_summary, store.create(r));

    r = baseRecord();
    r.hat_id = "";
    try std.testing.expectError(intent_cells_store_fs.StoreError.invalid_hat_id, store.create(r));
}

```
