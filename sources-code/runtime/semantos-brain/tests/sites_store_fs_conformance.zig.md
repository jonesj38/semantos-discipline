---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/sites_store_fs_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.209214+00:00
---

# runtime/semantos-brain/tests/sites_store_fs_conformance.zig

```zig
// D-DOG.1.0c Phase 2A.1 — sites_store_fs.zig conformance tests.
// W6.2: updated to use LmdbCellStore fixture (sites_store_lmdb.zig).
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 row C.2;
//            cartridges/oddjobz/brain/src/cell-types/site.v2.ts (the schema
//            this store mirrors a subset of).
//
// Exercises the same lookup-or-mint contract as before:
//   • appendCreated round-trips bytes correctly across a full set of fields
//   • findByLookupKey returns null for unknown keys / correct Site for known
//   • getById round-trips by raw [32]u8 cellId
//   • listAll returns rows in insertion order
//   • Re-init (new LmdbCellStore over same env) rebuilds both indexes

const std = @import("std");
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");
const cell_store_mod = @import("cell_store");
const sites_store_fs = @import("sites_store_fs");

const SitesStore = sites_store_fs.SitesStore;
const Site = sites_store_fs.Site;
const SitePayload = SitesStore.SitePayload;

fn pinnedClock() i64 {
    return 1_700_000_000;
}

fn cellIdOf(byte: u8) [32]u8 {
    var out: [32]u8 = undefined;
    @memset(&out, byte);
    return out;
}

const TYPE_HASH_SITE_V2: [32]u8 = blk: {
    var out: [32]u8 = undefined;
    for (0..32) |i| out[i] = @intCast(i);
    break :blk out;
};

fn openTestEnv(dir: []const u8) !lmdb.Env {
    return lmdb.Env.open(dir, .{
        .max_dbs = 8,
        .map_size = 4 * 1024 * 1024,
        .open_flags = lmdb.EnvFlags.NOSYNC,
    });
}

test "conformance: appendCreated round-trips every field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try SitesStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const cellId = cellIdOf(0xa1);

    const stored = try store.appendCreated(.{
        .cellId = cellId,
        .typeHash = TYPE_HASH_SITE_V2,
        .normalisedAddress = "13 orealla cr",
        .keyNumber = "key #177",
        .lookupKey = "13 orealla cr|key #177",
        .fullAddress = "13 Orealla Cr, Surfers Paradise",
        .suburb = "Surfers Paradise",
        .postcode = "4217",
        .state = "QLD",
    });

    try std.testing.expectEqualSlices(u8, &cellId, &stored.cellId);
    try std.testing.expectEqualSlices(u8, &TYPE_HASH_SITE_V2, &stored.typeHash);
    try std.testing.expectEqualStrings("13 orealla cr", stored.normalisedAddress);
    try std.testing.expectEqualStrings("key #177", stored.keyNumber.?);
    try std.testing.expectEqualStrings("13 orealla cr|key #177", stored.lookupKey);
    try std.testing.expectEqualStrings("13 Orealla Cr, Surfers Paradise", stored.fullAddress);
    try std.testing.expectEqualStrings("Surfers Paradise", stored.suburb.?);
    try std.testing.expectEqualStrings("4217", stored.postcode.?);
    try std.testing.expectEqualStrings("QLD", stored.state.?);
    try std.testing.expect(stored.signedBy == null);
    try std.testing.expect(stored.signature == null);
    try std.testing.expectEqual(pinnedClock(), stored.createdAt);
}

test "conformance: appendCreated round-trips with all optionals null" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try SitesStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const cellId = cellIdOf(0xa2);
    const stored = try store.appendCreated(.{
        .cellId = cellId,
        .typeHash = TYPE_HASH_SITE_V2,
        .normalisedAddress = "1 anywhere st",
        .keyNumber = null,
        .lookupKey = "1 anywhere st|",
        .fullAddress = "1 Anywhere St",
        .suburb = null,
        .postcode = null,
        .state = null,
    });
    try std.testing.expect(stored.keyNumber == null);
    try std.testing.expect(stored.suburb == null);
    try std.testing.expect(stored.postcode == null);
    try std.testing.expect(stored.state == null);

    // Round-trip across re-init — replay must reconstruct the null optional shape.
    const reread: Site = blk: {
        var cs_impl2 = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
        const cs2 = cs_impl2.store();
        var store2 = try SitesStore.init(allocator, &cs2, pinnedClock);
        defer store2.deinit();
        const got = store2.getById(cellId) orelse return error.MissingRecord;
        break :blk Site{
            .cellId = got.cellId,
            .typeHash = got.typeHash,
            .normalisedAddress = "<consumed>",
            .keyNumber = if (got.keyNumber == null) null else "<present>",
            .lookupKey = "<consumed>",
            .fullAddress = "<consumed>",
            .suburb = if (got.suburb == null) null else "<present>",
            .postcode = if (got.postcode == null) null else "<present>",
            .state = if (got.state == null) null else "<present>",
            .signedBy = got.signedBy,
            .signature = got.signature,
            .createdAt = got.createdAt,
        };
    };
    try std.testing.expect(reread.keyNumber == null);
    try std.testing.expect(reread.suburb == null);
    try std.testing.expect(reread.postcode == null);
    try std.testing.expect(reread.state == null);
}

test "conformance: findByLookupKey returns null for unknown / right Site for known" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try SitesStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    try std.testing.expect(store.findByLookupKey("nothing|here") == null);

    const cellId_a = cellIdOf(0xb1);
    const cellId_b = cellIdOf(0xb2);
    _ = try store.appendCreated(.{
        .cellId = cellId_a,
        .typeHash = TYPE_HASH_SITE_V2,
        .normalisedAddress = "13 a st",
        .keyNumber = null,
        .lookupKey = "13 a st|",
        .fullAddress = "13 A St",
        .suburb = null,
        .postcode = null,
        .state = null,
    });
    _ = try store.appendCreated(.{
        .cellId = cellId_b,
        .typeHash = TYPE_HASH_SITE_V2,
        .normalisedAddress = "13 a st",
        .keyNumber = "unit 7",
        .lookupKey = "13 a st|unit 7",
        .fullAddress = "13 A St, Unit 7",
        .suburb = null,
        .postcode = null,
        .state = null,
    });

    const a = store.findByLookupKey("13 a st|") orelse return error.MissingRecord;
    try std.testing.expectEqualSlices(u8, &cellId_a, &a.cellId);
    const b = store.findByLookupKey("13 a st|unit 7") orelse return error.MissingRecord;
    try std.testing.expectEqualSlices(u8, &cellId_b, &b.cellId);
    try std.testing.expectEqual(@as(usize, 2), store.count());
}

test "conformance: getById round-trips" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try SitesStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const cellId = cellIdOf(0xc1);
    _ = try store.appendCreated(.{
        .cellId = cellId,
        .typeHash = TYPE_HASH_SITE_V2,
        .normalisedAddress = "5 by-id st",
        .keyNumber = null,
        .lookupKey = "5 by-id st|",
        .fullAddress = "5 By-Id St",
        .suburb = null,
        .postcode = null,
        .state = null,
    });

    const got = store.getById(cellId) orelse return error.MissingRecord;
    try std.testing.expectEqualSlices(u8, &cellId, &got.cellId);
    try std.testing.expectEqualStrings("5 by-id st", got.normalisedAddress);

    try std.testing.expect(store.getById(cellIdOf(0xee)) == null);
}

test "conformance: listAll returns rows in insertion order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try SitesStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    inline for (.{ 0xd1, 0xd2, 0xd3 }, 0..) |b, i| {
        const lookup_str = std.fmt.comptimePrint("{d}|", .{i});
        _ = try store.appendCreated(.{
            .cellId = cellIdOf(b),
            .typeHash = TYPE_HASH_SITE_V2,
            .normalisedAddress = lookup_str[0 .. lookup_str.len - 1],
            .keyNumber = null,
            .lookupKey = lookup_str,
            .fullAddress = "X",
            .suburb = null,
            .postcode = null,
            .state = null,
        });
    }

    const all = try store.listAll(allocator);
    defer allocator.free(all);
    try std.testing.expectEqual(@as(usize, 3), all.len);
    try std.testing.expectEqual(@as(u8, 0xd1), all[0].cellId[0]);
    try std.testing.expectEqual(@as(u8, 0xd2), all[1].cellId[0]);
    try std.testing.expectEqual(@as(u8, 0xd3), all[2].cellId[0]);
}

test "conformance: idempotent appendCreated returns the prior row" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try SitesStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const cellId = cellIdOf(0xe1);
    const payload: SitePayload = .{
        .cellId = cellId,
        .typeHash = TYPE_HASH_SITE_V2,
        .normalisedAddress = "1 idem st",
        .keyNumber = null,
        .lookupKey = "1 idem st|",
        .fullAddress = "1 Idem St",
        .suburb = null,
        .postcode = null,
        .state = null,
    };

    const first = try store.appendCreated(payload);
    const again = try store.appendCreated(payload);
    try std.testing.expectEqualSlices(u8, &first.cellId, &again.cellId);
    try std.testing.expectEqual(@as(usize, 1), store.count());

    const by_id = store.getById(cellId) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("1 idem st", by_id.normalisedAddress);
    const by_lookup = store.findByLookupKey("1 idem st|") orelse return error.MissingRecord;
    try std.testing.expectEqualSlices(u8, &cellId, &by_lookup.cellId);
}

test "conformance: idempotent re-init reads LMDB back" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openTestEnv(data_dir);
    defer env.close();

    const cellId_a = cellIdOf(0xf1);
    const cellId_b = cellIdOf(0xf2);

    {
        var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
        const cs = cs_impl.store();
        var store = try SitesStore.init(allocator, &cs, pinnedClock);
        defer store.deinit();
        _ = try store.appendCreated(.{
            .cellId = cellId_a,
            .typeHash = TYPE_HASH_SITE_V2,
            .normalisedAddress = "1 reload st",
            .keyNumber = null,
            .lookupKey = "1 reload st|",
            .fullAddress = "1 Reload St",
            .suburb = null,
            .postcode = null,
            .state = null,
        });
        _ = try store.appendCreated(.{
            .cellId = cellId_b,
            .typeHash = TYPE_HASH_SITE_V2,
            .normalisedAddress = "2 \"loud\" rd",
            .keyNumber = "unit 9",
            .lookupKey = "2 \"loud\" rd|unit 9",
            .fullAddress = "2 \"Loud\" Rd",
            .suburb = "Brisbane",
            .postcode = "4000",
            .state = "QLD",
        });
    }

    // Re-init: new LmdbCellStore over the same env replays both cells.
    var cs_impl2 = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs2 = cs_impl2.store();
    var store2 = try SitesStore.init(allocator, &cs2, pinnedClock);
    defer store2.deinit();
    try std.testing.expectEqual(@as(usize, 2), store2.count());

    const a = store2.getById(cellId_a) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("1 reload st", a.normalisedAddress);
    try std.testing.expect(a.keyNumber == null);

    const b_by_id = store2.getById(cellId_b) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("2 \"loud\" rd", b_by_id.normalisedAddress);
    try std.testing.expectEqualStrings("unit 9", b_by_id.keyNumber.?);
    try std.testing.expectEqualStrings("Brisbane", b_by_id.suburb.?);
    try std.testing.expectEqualStrings("4000", b_by_id.postcode.?);
    try std.testing.expectEqualStrings("QLD", b_by_id.state.?);

    const b_by_lookup = store2.findByLookupKey("2 \"loud\" rd|unit 9") orelse return error.MissingRecord;
    try std.testing.expectEqualSlices(u8, &cellId_b, &b_by_lookup.cellId);

    // listAll returns both records (LMDB replay is hash-sorted, not
    // insertion-ordered, so we don't assert the exact order here —
    // the getById lookups above already verify both records are present).
    const all = try store2.listAll(allocator);
    defer allocator.free(all);
    try std.testing.expectEqual(@as(usize, 2), all.len);
}

```
