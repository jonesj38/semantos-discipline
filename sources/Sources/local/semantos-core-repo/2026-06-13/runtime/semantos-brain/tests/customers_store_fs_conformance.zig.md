---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/customers_store_fs_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.200156+00:00
---

# runtime/semantos-brain/tests/customers_store_fs_conformance.zig

```zig
// D-DOG.1.0c Phase 2A.2 — customers_store_fs.zig conformance tests
// (the v2 graph-aware extension).
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 row C.3;
//            cartridges/oddjobz/brain/src/cell-types/customer.v2.ts (the v2
//            schema this store mirrors a subset of).
//
// The v1-shape conformance lives in `tests/customers_handler_conformance.
// zig` (the resource handler's surface).  This file exercises the
// store-level v2 surface Phase 2A.4's ratify-handler will rely on:
//
//   • appendCreatedV2 round-trips every v2 field across a fresh init
//     (the JSONL line carries the v2 extras and replay reconstructs them).
//   • A v1-shape `append` followed by a v2-shape `appendCreatedV2` on a
//     different row coexist — neither shape clobbers the other on
//     replay.
//   • findByDedupeKey for each of the three key variants (phone, email,
//     name+role+site) — exact match returns the right row; mismatch
//     returns null; v1 rows are correctly skipped on the
//     name+role+site path.
//   • getByCellId round-trips by raw [32]u8 cell-id; v1 rows are
//     unreachable through it.
//   • Mixed v1+v2 row inserts that exercise wide field envelopes
//     survive the within-record arena growth pattern (#308 / sites
//     regression).

const std = @import("std");
const customers_store_fs = @import("customers_store_fs");
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");

const CustomersStore = customers_store_fs.CustomersStore;
const Customer = customers_store_fs.Customer;
const CustomerRole = customers_store_fs.CustomerRole;
const CustomerSourceProvenance = customers_store_fs.CustomerSourceProvenance;
const CustomerV2Payload = CustomersStore.CustomerV2Payload;
const CustomerDedupeKey = CustomersStore.CustomerDedupeKey;

fn pinnedClock() i64 {
    return 1_700_000_000;
}

fn cellIdOf(byte: u8) [32]u8 {
    var out: [32]u8 = undefined;
    @memset(&out, byte);
    return out;
}

const TYPE_HASH_CUSTOMER_V2: [32]u8 = blk: {
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

test "conformance: v1 round-trip still works (regression — visit-side flow preserved)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try CustomersStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    try std.testing.expectEqual(CustomersStore.AppendOutcome.created, try store.append(.{
        .id = "00000000000000000000000000000001",
        .display_name = "Acme Corp",
        .phone = "+61 400 111 222",
        .email = "ops@acme.example",
        .address = "1 Industrial Way, Melbourne",
        .notes = "Regular plumbing customer",
        .created_at = "2026-05-02T10:00:00Z",
    }));
    try std.testing.expectEqual(@as(usize, 1), store.count());

    // Every v2 field stays null on a v1 row — that's the additive-
    // extension invariant.
    const got = store.findById("00000000000000000000000000000001") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("Acme Corp", got.display_name);
    try std.testing.expect(got.cellId == null);
    try std.testing.expect(got.typeHash == null);
    try std.testing.expect(got.role == null);
    try std.testing.expect(got.normalisedPhone == null);
    try std.testing.expect(got.sourceProvenance == null);
    try std.testing.expect(got.siteRef == null);
}

test "conformance: appendCreatedV2 round-trips every v2 field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try CustomersStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const cellId = cellIdOf(0xa1);
    const siteRef = cellIdOf(0xb2);
    const payload: CustomerV2Payload = .{
        .id = "11111111111111111111111111111111",
        .display_name = "Sarah Liu",
        .phone = "0400 111 222",
        .email = "sarah@example.com",
        .address = "",
        .notes = "",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellId,
        .typeHash = TYPE_HASH_CUSTOMER_V2,
        .role = .tenant,
        .normalisedPhone = "+61400111222",
        .sourceProvenance = .{
            .providerId = "gmail",
            .providerItemId = "msg-abc123",
            .extractedAt = "2026-05-02T09:55:00Z",
        },
        .siteRef = siteRef,
    };
    try std.testing.expectEqual(CustomersStore.AppendOutcome.created, try store.appendCreatedV2(payload));

    // Direct round-trip through the in-memory record.
    const got = store.getByCellId(cellId) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("Sarah Liu", got.display_name);
    try std.testing.expectEqualStrings("+61400111222", got.normalisedPhone.?);
    try std.testing.expectEqual(CustomerRole.tenant, got.role.?);
    try std.testing.expectEqualStrings("gmail", got.sourceProvenance.?.providerId);
    try std.testing.expectEqualStrings("msg-abc123", got.sourceProvenance.?.providerItemId);
    try std.testing.expectEqualSlices(u8, &cellId, &got.cellId.?);
    try std.testing.expectEqualSlices(u8, &TYPE_HASH_CUSTOMER_V2, &got.typeHash.?);
    try std.testing.expectEqualSlices(u8, &siteRef, &got.siteRef.?);

    // Reload from disk — JSONL replay reconstructs every v2 field.
    var env2 = try openTestEnv(data_dir);
    defer env2.close();
    var cs_impl2 = try lmdb_cell_store.LmdbCellStore.init(&env2, allocator);
    const cs2 = cs_impl2.store();
    var store2 = try CustomersStore.init(allocator, &cs2, pinnedClock);
    defer store2.deinit();
    const got2 = store2.getByCellId(cellId) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("Sarah Liu", got2.display_name);
    try std.testing.expectEqualStrings("+61400111222", got2.normalisedPhone.?);
    try std.testing.expectEqual(CustomerRole.tenant, got2.role.?);
    try std.testing.expectEqualStrings("gmail", got2.sourceProvenance.?.providerId);
    try std.testing.expectEqualSlices(u8, &siteRef, &got2.siteRef.?);
}

test "conformance: appendCreatedV2 with all-nullable v2 fields null" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try CustomersStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    // A "no canonical phone, no site link" row — operator's contact
    // info was vague.
    const cellId = cellIdOf(0xc1);
    _ = try store.appendCreatedV2(.{
        .id = "22222222222222222222222222222222",
        .display_name = "Vague Vinny",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellId,
        .typeHash = TYPE_HASH_CUSTOMER_V2,
        .role = .other,
        .normalisedPhone = null,
        .sourceProvenance = .{
            .providerId = "propertyme",
            .providerItemId = "wo-9911",
            .extractedAt = "2026-05-02T09:00:00Z",
        },
        .siteRef = null,
    });

    var env2 = try openTestEnv(data_dir);
    defer env2.close();
    var cs_impl2 = try lmdb_cell_store.LmdbCellStore.init(&env2, allocator);
    const cs2 = cs_impl2.store();
    var store2 = try CustomersStore.init(allocator, &cs2, pinnedClock);
    defer store2.deinit();
    const got = store2.getByCellId(cellId) orelse return error.MissingRecord;
    try std.testing.expect(got.normalisedPhone == null);
    try std.testing.expect(got.siteRef == null);
    try std.testing.expectEqual(CustomerRole.other, got.role.?);
}

test "conformance: findByDedupeKey by phone returns / null on miss" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try CustomersStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    _ = try store.appendCreatedV2(.{
        .id = "33333333333333333333333333333333",
        .display_name = "Phone Pat",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellIdOf(0xd1),
        .typeHash = TYPE_HASH_CUSTOMER_V2,
        .role = .tenant,
        .normalisedPhone = "+61400999111",
        .sourceProvenance = .{
            .providerId = "gmail",
            .providerItemId = "x",
            .extractedAt = "2026-05-02T09:00:00Z",
        },
        .siteRef = null,
    });

    const hit = store.findByDedupeKey(.{ .phone = "+61400999111" }) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("Phone Pat", hit.display_name);

    try std.testing.expect(store.findByDedupeKey(.{ .phone = "+61400000000" }) == null);
    try std.testing.expect(store.findByDedupeKey(.{ .phone = "" }) == null);
}

test "conformance: findByDedupeKey by email matches v1 + v2 rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try CustomersStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    // v1 row.
    _ = try store.append(.{
        .id = "v1-001",
        .display_name = "Legacy Larry",
        .phone = "",
        .email = "legacy@example.com",
        .address = "",
        .notes = "",
        .created_at = "2026-05-02T10:00:00Z",
    });
    // v2 row.
    _ = try store.appendCreatedV2(.{
        .id = "44444444444444444444444444444444",
        .display_name = "Email Eve",
        .email = "eve@example.com",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellIdOf(0xe1),
        .typeHash = TYPE_HASH_CUSTOMER_V2,
        .role = .agent,
        .normalisedPhone = null,
        .sourceProvenance = .{
            .providerId = "bricksandagent",
            .providerItemId = "lead-77",
            .extractedAt = "2026-05-02T09:00:00Z",
        },
        .siteRef = null,
    });

    const v1_hit = store.findByDedupeKey(.{ .email = "legacy@example.com" }) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("Legacy Larry", v1_hit.display_name);
    const v2_hit = store.findByDedupeKey(.{ .email = "eve@example.com" }) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("Email Eve", v2_hit.display_name);

    try std.testing.expect(store.findByDedupeKey(.{ .email = "nobody@example.com" }) == null);
}

test "conformance: findByDedupeKey by name+role+site skips v1 rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try CustomersStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const site_a = cellIdOf(0xf1);
    const site_b = cellIdOf(0xf2);

    // v1 row that happens to share the display name — must be SKIPPED
    // by the name+role+site dedupe path (no role / siteRef on v1).
    _ = try store.append(.{
        .id = "v1-shadow",
        .display_name = "Pat",
        .phone = "",
        .email = "",
        .address = "",
        .notes = "",
        .created_at = "2026-05-02T10:00:00Z",
    });

    // Same name + same role + DIFFERENT site → no match.
    _ = try store.appendCreatedV2(.{
        .id = "55555555555555555555555555555551",
        .display_name = "Pat",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellIdOf(0xa3),
        .typeHash = TYPE_HASH_CUSTOMER_V2,
        .role = .tenant,
        .normalisedPhone = null,
        .sourceProvenance = .{
            .providerId = "gmail",
            .providerItemId = "x",
            .extractedAt = "2026-05-02T09:00:00Z",
        },
        .siteRef = site_a,
    });
    // Same name + same role + matching site → MATCH.
    _ = try store.appendCreatedV2(.{
        .id = "55555555555555555555555555555552",
        .display_name = "Pat",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellIdOf(0xa4),
        .typeHash = TYPE_HASH_CUSTOMER_V2,
        .role = .agent,
        .normalisedPhone = null,
        .sourceProvenance = .{
            .providerId = "gmail",
            .providerItemId = "y",
            .extractedAt = "2026-05-02T09:00:00Z",
        },
        .siteRef = site_b,
    });

    const hit = store.findByDedupeKey(.{ .nameRoleAndSite = .{
        .name = "Pat",
        .role = .agent,
        .siteRef = site_b,
    } }) orelse return error.MissingRecord;
    const expected_a4 = cellIdOf(0xa4);
    try std.testing.expectEqualSlices(u8, &expected_a4, &hit.cellId.?);

    // Wrong role → null.
    try std.testing.expect(store.findByDedupeKey(.{ .nameRoleAndSite = .{
        .name = "Pat",
        .role = .owner,
        .siteRef = site_b,
    } }) == null);

    // Wrong site → null.
    try std.testing.expect(store.findByDedupeKey(.{ .nameRoleAndSite = .{
        .name = "Pat",
        .role = .agent,
        .siteRef = cellIdOf(0xee),
    } }) == null);
}

test "conformance: getByCellId returns null for v1 rows, hit for v2 rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try CustomersStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    _ = try store.append(.{
        .id = "legacy-001",
        .display_name = "Legacy",
        .phone = "",
        .email = "",
        .address = "",
        .notes = "",
        .created_at = "2026-05-02T10:00:00Z",
    });

    // v1 row exists by string id but is unreachable via getByCellId.
    try std.testing.expect(store.findById("legacy-001") != null);
    try std.testing.expect(store.getByCellId(cellIdOf(0x00)) == null);

    const cellId = cellIdOf(0xb5);
    _ = try store.appendCreatedV2(.{
        .id = "66666666666666666666666666666666",
        .display_name = "Graphy Greg",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellId,
        .typeHash = TYPE_HASH_CUSTOMER_V2,
        .role = .pm,
        .normalisedPhone = null,
        .sourceProvenance = .{
            .providerId = "propertyme",
            .providerItemId = "z",
            .extractedAt = "2026-05-02T09:00:00Z",
        },
        .siteRef = null,
    });
    const got = store.getByCellId(cellId) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("Graphy Greg", got.display_name);
}

test "conformance: idempotent appendCreatedV2 preserves count" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try CustomersStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const payload: CustomerV2Payload = .{
        .id = "77777777777777777777777777777777",
        .display_name = "Idem Iggy",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellIdOf(0xc7),
        .typeHash = TYPE_HASH_CUSTOMER_V2,
        .role = .sub_tradie,
        .normalisedPhone = "+61400777777",
        .sourceProvenance = .{
            .providerId = "gmail",
            .providerItemId = "i",
            .extractedAt = "2026-05-02T09:00:00Z",
        },
        .siteRef = null,
    };
    try std.testing.expectEqual(CustomersStore.AppendOutcome.created, try store.appendCreatedV2(payload));
    try std.testing.expectEqual(CustomersStore.AppendOutcome.already_exists, try store.appendCreatedV2(payload));
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

test "conformance: mixed v1+v2 inserts survive within-record arena growth" {
    // Regression for the latent string-arena dangling-slice bug — a
    // wide v2 row (long display_name + email + sourceProvenance.* + a
    // long normalisedPhone) inserted between two v1 rows must land
    // every slice on a stable arena address even when the per-field
    // appendArenaAssumeCapacity sequence triggers a within-clone grow.
    // Mirrors jobs_store_fs.zig:702-755 + sites regression.
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try CustomersStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    // First v1 row at modest envelope so the arena has some pre-grow
    // bytes that must survive across the wide v2 insert.
    _ = try store.append(.{
        .id = "v1-pre",
        .display_name = "First",
        .phone = "+61 400 000 001",
        .email = "first@example.com",
        .address = "1 Anywhere",
        .notes = "Note",
        .created_at = "2026-05-02T10:00:00Z",
    });

    // Wide v2 insert — every string field at or near its byte cap.
    var name_buf: [customers_store_fs.MAX_DISPLAY_NAME_BYTES]u8 = undefined;
    @memset(&name_buf, 'n');
    var email_buf: [customers_store_fs.MAX_EMAIL_BYTES]u8 = undefined;
    @memset(&email_buf, 'e');
    var phone_buf: [customers_store_fs.MAX_NORMALISED_PHONE_BYTES]u8 = undefined;
    @memset(&phone_buf, '+');
    var pid_buf: [customers_store_fs.MAX_PROVIDER_ID_BYTES]u8 = undefined;
    @memset(&pid_buf, 'p');
    var pii_buf: [customers_store_fs.MAX_PROVIDER_ITEM_ID_BYTES]u8 = undefined;
    @memset(&pii_buf, 'q');
    var ext_buf: [customers_store_fs.MAX_EXTRACTED_AT_BYTES]u8 = undefined;
    @memset(&ext_buf, 'x');
    var notes_buf: [customers_store_fs.MAX_NOTES_BYTES]u8 = undefined;
    @memset(&notes_buf, 'z');

    const wide_cell = cellIdOf(0xab);
    _ = try store.appendCreatedV2(.{
        .id = "wide-v2-row-padded-to-thirty-two",
        .display_name = &name_buf,
        .phone = "",
        .email = &email_buf,
        .address = "",
        .notes = &notes_buf,
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = wide_cell,
        .typeHash = TYPE_HASH_CUSTOMER_V2,
        .role = .other,
        .normalisedPhone = &phone_buf,
        .sourceProvenance = .{
            .providerId = &pid_buf,
            .providerItemId = &pii_buf,
            .extractedAt = &ext_buf,
        },
        .siteRef = null,
    });

    // Second v1 row to exercise the arena's post-v2 state.
    _ = try store.append(.{
        .id = "v1-post",
        .display_name = "Last",
        .phone = "",
        .email = "last@example.com",
        .address = "",
        .notes = "",
        .created_at = "2026-05-02T10:00:00Z",
    });
    try std.testing.expectEqual(@as(usize, 3), store.count());

    // Round-trip every field on the wide row — this is the assertion
    // an arena-grow bug would break (the first-appended slices would
    // dangle).
    const got = store.getByCellId(wide_cell) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings(&name_buf, got.display_name);
    try std.testing.expectEqualStrings(&email_buf, got.email);
    try std.testing.expectEqualStrings(&phone_buf, got.normalisedPhone.?);
    try std.testing.expectEqualStrings(&pid_buf, got.sourceProvenance.?.providerId);
    try std.testing.expectEqualStrings(&pii_buf, got.sourceProvenance.?.providerItemId);
    try std.testing.expectEqualStrings(&ext_buf, got.sourceProvenance.?.extractedAt);
    try std.testing.expectEqualStrings(&notes_buf, got.notes);

    // The earlier v1 row's slices must also still be intact.
    const first = store.findById("v1-pre") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("First", first.display_name);
    try std.testing.expectEqualStrings("first@example.com", first.email);
    const last = store.findById("v1-post") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("Last", last.display_name);
    try std.testing.expectEqualStrings("last@example.com", last.email);
}

```
