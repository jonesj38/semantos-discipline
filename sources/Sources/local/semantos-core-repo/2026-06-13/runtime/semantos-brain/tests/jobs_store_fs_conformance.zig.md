---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/jobs_store_fs_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.207884+00:00
---

# runtime/semantos-brain/tests/jobs_store_fs_conformance.zig

```zig
// W0.1 — jobs_store_fs conformance tests (LMDB-backed implementation).
//
// After W0.1 the jobs_store_fs module is backed by jobs_store_lmdb_entity.zig
// rather than the JSONL jobs_store_fs.zig.  This file exercises the same
// contract as before but uses an LmdbCellStore as the backing store instead
// of a data_dir + JSONL file.
//
// Test contract:
//   • v1 round-trip — legacy append path still works.
//   • v2 round-trip — appendCreatedV2 + getById round-trips every field.
//   • Mixed v1+v2 — listAll returns both in insertion order.
//   • Replay round-trip — a second JobsStore.init on the same LMDB env
//     reconstructs both v1 and v2 rows.
//   • listForSite / listForCustomer — graph-aware query filters.
//   • Validation regressions — bad inputs are rejected with typed errors.

const std = @import("std");
const jobs_store_fs = @import("jobs_store_fs");
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");
const content_store_local_fs = @import("content_store_local_fs");

const JobsStore = jobs_store_fs.JobsStore;
const Job = jobs_store_fs.Job;
const JobV2Payload = JobsStore.JobV2Payload;
const CustomerRef = jobs_store_fs.CustomerRef;
const BillingParty = jobs_store_fs.BillingParty;

fn pinnedClock() i64 {
    return 1_700_000_000;
}

fn cellIdOf(byte: u8) [32]u8 {
    var out: [32]u8 = undefined;
    @memset(&out, byte);
    return out;
}

const TYPE_HASH_JOB_V2: [32]u8 = blk: {
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

// ─────────────────────────────────────────────────────────────────────
// v1 conformance
// ─────────────────────────────────────────────────────────────────────

test "conformance v1: append + findById round-trip on legacy row" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const outcome = try store.append(.{
        .id = "00000000000000000000000000000001",
        .customer_name = "Acme Corp",
        .state = "lead",
        .scheduled_at = "",
        .created_at = "2026-05-02T10:00:00Z",
    });
    try std.testing.expectEqual(JobsStore.AppendOutcome.created, outcome);

    const got = store.findById("00000000000000000000000000000001") orelse return error.MissingRecord;
    try std.testing.expectEqual(@as(u8, 1), got.version);
    try std.testing.expectEqualStrings("Acme Corp", got.customer_name);
    try std.testing.expectEqualStrings("lead", got.state);
    // v1 rows written via append() now have cellId set (SHA-256 of the cell bytes).
    // All other v2-only fields remain null.
    try std.testing.expect(got.cellId != null);
    try std.testing.expect(got.typeHash == null);
    try std.testing.expect(got.workOrderNumber == null);
    try std.testing.expect(got.siteRef == null);
    try std.testing.expect(got.customerRefs == null);
    try std.testing.expect(got.attachmentRefs == null);
    try std.testing.expect(got.hasPhotos == null);
    try std.testing.expect(got.signedBy == null);
    try std.testing.expect(got.signature == null);
}

test "conformance v1: idempotent re-append still returns already_exists" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const j: Job = .{
        .id = "j-idem-001",
        .customer_name = "Globex",
        .state = "quoted",
        .scheduled_at = "",
        .created_at = "2026-05-02T10:00:00Z",
    };
    try std.testing.expectEqual(JobsStore.AppendOutcome.created, try store.append(j));
    try std.testing.expectEqual(JobsStore.AppendOutcome.already_exists, try store.append(j));
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

// ─────────────────────────────────────────────────────────────────────
// v2 conformance
// ─────────────────────────────────────────────────────────────────────

test "conformance v2: appendCreatedV2 round-trips every field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var content = try content_store_local_fs.ContentStoreLocalFs.init(allocator, data_dir);
    defer content.deinit();
    var store = try JobsStore.initWithContentStore(allocator, &cs, pinnedClock, &content);
    defer store.deinit();

    const cell_id = cellIdOf(0xa1);
    const site_ref = cellIdOf(0xb1);
    const customer_a = cellIdOf(0xc1);
    const customer_b = cellIdOf(0xc2);
    const attachment_a = cellIdOf(0xd1);
    const attachment_b = cellIdOf(0xd2);

    const cref_input = [_]CustomerRef{
        .{ .cellId = customer_a, .role = "tenant", .primary = true },
        .{ .cellId = customer_b, .role = "agent", .primary = false },
    };
    const aref_input = [_][32]u8{ attachment_a, attachment_b };

    const stored = try store.appendCreatedV2(.{
        .cellId = cell_id,
        .typeHash = TYPE_HASH_JOB_V2,
        .customer_name = "Sarah Liu (tenant)",
        .state = "lead",
        .scheduled_at = "",
        .created_at = "2026-05-02T10:00:00Z",
        .workOrderNumber = "RJR-2025-0142",
        .issuanceDate = "2026-05-01",
        .dueDate = "2026-05-15",
        .billingParty = .{ .type = "agency", .name = "Acme Real Estate Pty Ltd" },
        .hasPhotos = true,
        .photoCount = 3,
        .propertyKey = "key #177",
        .siteRef = site_ref,
        .customerRefs = &cref_input,
        .attachmentRefs = &aref_input,
    });

    try std.testing.expectEqual(@as(u8, 2), stored.version);
    try std.testing.expectEqualSlices(u8, &cell_id, &stored.cellId.?);
    try std.testing.expectEqualSlices(u8, &TYPE_HASH_JOB_V2, &stored.typeHash.?);
    try std.testing.expectEqualStrings("Sarah Liu (tenant)", stored.customer_name);
    try std.testing.expectEqualStrings("lead", stored.state);
    try std.testing.expectEqualStrings("RJR-2025-0142", stored.workOrderNumber.?);
    try std.testing.expectEqualStrings("2026-05-01", stored.issuanceDate.?);
    try std.testing.expectEqualStrings("2026-05-15", stored.dueDate.?);
    try std.testing.expectEqualStrings("agency", stored.billingParty.?.type);
    try std.testing.expectEqualStrings("Acme Real Estate Pty Ltd", stored.billingParty.?.name);
    try std.testing.expect(stored.hasPhotos.?);
    try std.testing.expectEqual(@as(u32, 3), stored.photoCount.?);
    try std.testing.expectEqualStrings("key #177", stored.propertyKey.?);
    try std.testing.expectEqualSlices(u8, &site_ref, &stored.siteRef.?);
    try std.testing.expectEqual(@as(usize, 2), stored.customerRefs.?.len);
    try std.testing.expectEqualSlices(u8, &customer_a, &stored.customerRefs.?[0].cellId);
    try std.testing.expectEqualStrings("tenant", stored.customerRefs.?[0].role);
    try std.testing.expect(stored.customerRefs.?[0].primary);
    try std.testing.expectEqualSlices(u8, &customer_b, &stored.customerRefs.?[1].cellId);
    try std.testing.expectEqualStrings("agent", stored.customerRefs.?[1].role);
    try std.testing.expect(!stored.customerRefs.?[1].primary);
    try std.testing.expectEqual(@as(usize, 2), stored.attachmentRefs.?.len);
    try std.testing.expectEqualSlices(u8, &attachment_a, &stored.attachmentRefs.?[0]);
    try std.testing.expectEqualSlices(u8, &attachment_b, &stored.attachmentRefs.?[1]);
    try std.testing.expect(stored.signedBy == null);
    try std.testing.expect(stored.signature == null);

    const expected_id_hex = std.fmt.bytesToHex(cell_id, .lower);
    try std.testing.expectEqualStrings(expected_id_hex[0..], stored.id);
}

test "conformance v2: appendCreatedV2 round-trips with all optionals null" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const cell_id = cellIdOf(0xa2);
    const site_ref = cellIdOf(0xb2);

    const stored = try store.appendCreatedV2(.{
        .cellId = cell_id,
        .typeHash = TYPE_HASH_JOB_V2,
        .customer_name = "<unknown tenant>",
        .state = "lead",
        .scheduled_at = "",
        .created_at = "2026-05-02T10:00:00Z",
        .workOrderNumber = null,
        .issuanceDate = null,
        .dueDate = null,
        .billingParty = null,
        .hasPhotos = false,
        .photoCount = null,
        .propertyKey = null,
        .siteRef = site_ref,
        .customerRefs = &.{},
        .attachmentRefs = &.{},
    });
    try std.testing.expectEqual(@as(u8, 2), stored.version);
    try std.testing.expect(stored.workOrderNumber == null);
    try std.testing.expect(stored.issuanceDate == null);
    try std.testing.expect(stored.dueDate == null);
    try std.testing.expect(stored.billingParty == null);
    try std.testing.expect(!stored.hasPhotos.?);
    try std.testing.expect(stored.photoCount == null);
    try std.testing.expect(stored.propertyKey == null);
    try std.testing.expectEqual(@as(usize, 0), stored.customerRefs.?.len);
    try std.testing.expectEqual(@as(usize, 0), stored.attachmentRefs.?.len);
}

test "conformance v2: getById returns null for v1 rows even when hex-id matches" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    _ = try store.append(.{
        .id = "abababababababababababababababab",
        .customer_name = "Legacy",
        .state = "lead",
        .scheduled_at = "",
        .created_at = "2026-01-01T00:00:00Z",
    });
    var maybe_cell_id: [32]u8 = undefined;
    @memset(&maybe_cell_id, 0xab);
    try std.testing.expect(store.getById(maybe_cell_id) == null);

    const v1_legacy = store.findById("abababababababababababababababab") orelse return error.MissingRecord;
    try std.testing.expectEqual(@as(u8, 1), v1_legacy.version);
}

// ─────────────────────────────────────────────────────────────────────
// Mixed v1+v2
// ─────────────────────────────────────────────────────────────────────

test "conformance mixed: listAll returns v1 and v2 rows in insertion order" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    _ = try store.append(.{
        .id = "j-legacy-001",
        .customer_name = "Legacy A",
        .state = "lead",
        .scheduled_at = "",
        .created_at = "2026-01-01T00:00:00Z",
    });

    const cell_id = cellIdOf(0x10);
    const site_ref = cellIdOf(0x20);
    const customer_a = cellIdOf(0x30);
    const cref_input = [_]CustomerRef{
        .{ .cellId = customer_a, .role = "tenant", .primary = true },
    };
    _ = try store.appendCreatedV2(.{
        .cellId = cell_id,
        .typeHash = TYPE_HASH_JOB_V2,
        .customer_name = "Graph B",
        .state = "lead",
        .scheduled_at = "",
        .created_at = "2026-05-02T10:00:00Z",
        .workOrderNumber = "WO-1",
        .issuanceDate = null,
        .dueDate = null,
        .billingParty = null,
        .hasPhotos = false,
        .photoCount = null,
        .propertyKey = null,
        .siteRef = site_ref,
        .customerRefs = &cref_input,
        .attachmentRefs = &.{},
    });

    _ = try store.append(.{
        .id = "j-legacy-002",
        .customer_name = "Legacy C",
        .state = "quoted",
        .scheduled_at = "",
        .created_at = "2026-01-02T00:00:00Z",
    });

    const all = try store.listAll(allocator);
    defer allocator.free(all);
    try std.testing.expectEqual(@as(usize, 3), all.len);
    try std.testing.expectEqual(@as(u8, 1), all[0].version);
    try std.testing.expectEqualStrings("Legacy A", all[0].customer_name);
    try std.testing.expectEqual(@as(u8, 2), all[1].version);
    try std.testing.expectEqualStrings("Graph B", all[1].customer_name);
    try std.testing.expectEqual(@as(u8, 1), all[2].version);
    try std.testing.expectEqualStrings("Legacy C", all[2].customer_name);
}

test "conformance mixed: replay reconstructs both v1 and v2 rows" {
    // LMDB replay: write to a store, deinit, open a NEW JobsStore on the
    // same LMDB env and verify all records survive.
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    // Open a single LMDB env for the full test.
    var env = try openTestEnv(data_dir);
    defer env.close();

    var content = try content_store_local_fs.ContentStoreLocalFs.init(allocator, data_dir);
    defer content.deinit();

    const v1_id = "j-legacy-replay";
    const v2_cell_id = cellIdOf(0xa3);
    const v2_site_ref = cellIdOf(0xb3);
    const v2_customer = cellIdOf(0xc3);
    const v2_attachment = cellIdOf(0xd3);

    // First store: write records.
    {
        var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
        const cs = cs_impl.store();
        var store = try JobsStore.initWithContentStore(allocator, &cs, pinnedClock, &content);
        defer store.deinit();

        _ = try store.append(.{
            .id = v1_id,
            .customer_name = "Legacy Round-Trip",
            .state = "lead",
            .scheduled_at = "",
            .created_at = "2026-01-01T00:00:00Z",
        });
        const cref_input = [_]CustomerRef{
            .{ .cellId = v2_customer, .role = "tenant", .primary = true },
        };
        const aref_input = [_][32]u8{v2_attachment};
        _ = try store.appendCreatedV2(.{
            .cellId = v2_cell_id,
            .typeHash = TYPE_HASH_JOB_V2,
            .customer_name = "Graph Round-Trip",
            .state = "scheduled",
            .scheduled_at = "2026-05-15T09:00:00Z",
            .created_at = "2026-05-02T10:00:00Z",
            .workOrderNumber = "WO-RT",
            .issuanceDate = "2026-05-01",
            .dueDate = "2026-05-15",
            .billingParty = .{ .type = "owner", .name = "Self-Managed Owner" },
            .hasPhotos = true,
            .photoCount = 5,
            .propertyKey = "lockbox 4291",
            .siteRef = v2_site_ref,
            .customerRefs = &cref_input,
            .attachmentRefs = &aref_input,
        });
    }

    // Second store: replay from same LMDB env.
    var cs_impl2 = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs2 = cs_impl2.store();
    var store2 = try JobsStore.initWithContentStore(allocator, &cs2, pinnedClock, &content);
    defer store2.deinit();

    try std.testing.expectEqual(@as(usize, 2), store2.count());

    const v1_replayed = store2.findById(v1_id) orelse return error.MissingRecord;
    try std.testing.expectEqual(@as(u8, 1), v1_replayed.version);
    try std.testing.expectEqualStrings("Legacy Round-Trip", v1_replayed.customer_name);
    try std.testing.expect(v1_replayed.cellId != null); // v1 rows get cellId from cell hash on replay
    try std.testing.expect(v1_replayed.siteRef == null);

    const v2_replayed = store2.getById(v2_cell_id) orelse return error.MissingRecord;
    try std.testing.expectEqual(@as(u8, 2), v2_replayed.version);
    try std.testing.expectEqualStrings("Graph Round-Trip", v2_replayed.customer_name);
    try std.testing.expectEqualStrings("scheduled", v2_replayed.state);
    try std.testing.expectEqualStrings("2026-05-15T09:00:00Z", v2_replayed.scheduled_at);
    try std.testing.expectEqualStrings("WO-RT", v2_replayed.workOrderNumber.?);
    try std.testing.expectEqualStrings("2026-05-01", v2_replayed.issuanceDate.?);
    try std.testing.expectEqualStrings("2026-05-15", v2_replayed.dueDate.?);
    try std.testing.expectEqualStrings("owner", v2_replayed.billingParty.?.type);
    try std.testing.expectEqualStrings("Self-Managed Owner", v2_replayed.billingParty.?.name);
    try std.testing.expect(v2_replayed.hasPhotos.?);
    try std.testing.expectEqual(@as(u32, 5), v2_replayed.photoCount.?);
    try std.testing.expectEqualStrings("lockbox 4291", v2_replayed.propertyKey.?);
    try std.testing.expectEqualSlices(u8, &v2_site_ref, &v2_replayed.siteRef.?);
    try std.testing.expectEqual(@as(usize, 1), v2_replayed.customerRefs.?.len);
    try std.testing.expectEqualSlices(u8, &v2_customer, &v2_replayed.customerRefs.?[0].cellId);
    try std.testing.expectEqualStrings("tenant", v2_replayed.customerRefs.?[0].role);
    try std.testing.expect(v2_replayed.customerRefs.?[0].primary);
    try std.testing.expectEqual(@as(usize, 1), v2_replayed.attachmentRefs.?.len);
    try std.testing.expectEqualSlices(u8, &v2_attachment, &v2_replayed.attachmentRefs.?[0]);
}

// ─────────────────────────────────────────────────────────────────────
// listForSite + listForCustomer
// ─────────────────────────────────────────────────────────────────────

test "conformance v2: listForSite filters v2 rows by siteRef, excludes v1" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const target_site = cellIdOf(0x40);
    const other_site = cellIdOf(0x41);

    _ = try store.append(.{
        .id = "j-v1-skip",
        .customer_name = "V1 Skip",
        .state = "lead",
        .scheduled_at = "",
        .created_at = "2026-01-01T00:00:00Z",
    });

    _ = try store.appendCreatedV2(makeV2Payload(0x50, target_site, "First job at target", "lead"));
    _ = try store.appendCreatedV2(makeV2Payload(0x51, other_site, "At other site", "lead"));
    _ = try store.appendCreatedV2(makeV2Payload(0x52, target_site, "Second job at target", "scheduled"));

    const at_target = try store.listForSite(allocator, target_site);
    defer allocator.free(at_target);
    try std.testing.expectEqual(@as(usize, 2), at_target.len);
    try std.testing.expectEqualStrings("First job at target", at_target[0].customer_name);
    try std.testing.expectEqualStrings("Second job at target", at_target[1].customer_name);

    const at_unknown = try store.listForSite(allocator, cellIdOf(0xff));
    defer allocator.free(at_unknown);
    try std.testing.expectEqual(@as(usize, 0), at_unknown.len);
}

test "conformance v2: listForCustomer filters by ANY role match, excludes v1" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var content = try content_store_local_fs.ContentStoreLocalFs.init(allocator, data_dir);
    defer content.deinit();
    var store = try JobsStore.initWithContentStore(allocator, &cs, pinnedClock, &content);
    defer store.deinit();

    const sarah = cellIdOf(0x60);
    const tom = cellIdOf(0x61);
    const site_a = cellIdOf(0x70);
    const site_b = cellIdOf(0x71);

    _ = try store.append(.{
        .id = "j-v1-cust-skip",
        .customer_name = "Sarah Liu",
        .state = "lead",
        .scheduled_at = "",
        .created_at = "2026-01-01T00:00:00Z",
    });

    {
        const cref = [_]CustomerRef{.{ .cellId = sarah, .role = "tenant", .primary = true }};
        _ = try store.appendCreatedV2(.{
            .cellId = cellIdOf(0x80),
            .typeHash = TYPE_HASH_JOB_V2,
            .customer_name = "Sarah's tenancy at A",
            .state = "lead",
            .scheduled_at = "",
            .created_at = "2026-05-02T10:00:00Z",
            .workOrderNumber = null,
            .issuanceDate = null,
            .dueDate = null,
            .billingParty = null,
            .hasPhotos = false,
            .photoCount = null,
            .propertyKey = null,
            .siteRef = site_a,
            .customerRefs = &cref,
            .attachmentRefs = &.{},
        });
    }

    {
        const cref = [_]CustomerRef{
            .{ .cellId = sarah, .role = "agent", .primary = false },
            .{ .cellId = tom, .role = "tenant", .primary = true },
        };
        _ = try store.appendCreatedV2(.{
            .cellId = cellIdOf(0x81),
            .typeHash = TYPE_HASH_JOB_V2,
            .customer_name = "Tom's tenancy at B (Sarah agenting)",
            .state = "scheduled",
            .scheduled_at = "2026-05-15T09:00:00Z",
            .created_at = "2026-05-02T10:00:00Z",
            .workOrderNumber = null,
            .issuanceDate = null,
            .dueDate = null,
            .billingParty = null,
            .hasPhotos = false,
            .photoCount = null,
            .propertyKey = null,
            .siteRef = site_b,
            .customerRefs = &cref,
            .attachmentRefs = &.{},
        });
    }

    {
        const stranger = cellIdOf(0x62);
        const cref = [_]CustomerRef{.{ .cellId = stranger, .role = "tenant", .primary = true }};
        _ = try store.appendCreatedV2(.{
            .cellId = cellIdOf(0x82),
            .typeHash = TYPE_HASH_JOB_V2,
            .customer_name = "Stranger's job",
            .state = "lead",
            .scheduled_at = "",
            .created_at = "2026-05-02T10:00:00Z",
            .workOrderNumber = null,
            .issuanceDate = null,
            .dueDate = null,
            .billingParty = null,
            .hasPhotos = false,
            .photoCount = null,
            .propertyKey = null,
            .siteRef = cellIdOf(0x72),
            .customerRefs = &cref,
            .attachmentRefs = &.{},
        });
    }

    const sarah_jobs = try store.listForCustomer(allocator, sarah);
    defer allocator.free(sarah_jobs);
    try std.testing.expectEqual(@as(usize, 2), sarah_jobs.len);
    try std.testing.expectEqualStrings("Sarah's tenancy at A", sarah_jobs[0].customer_name);
    try std.testing.expectEqualStrings("Tom's tenancy at B (Sarah agenting)", sarah_jobs[1].customer_name);

    const tom_jobs = try store.listForCustomer(allocator, tom);
    defer allocator.free(tom_jobs);
    try std.testing.expectEqual(@as(usize, 1), tom_jobs.len);
    try std.testing.expectEqualStrings("Tom's tenancy at B (Sarah agenting)", tom_jobs[0].customer_name);

    const ghost_jobs = try store.listForCustomer(allocator, cellIdOf(0xff));
    defer allocator.free(ghost_jobs);
    try std.testing.expectEqual(@as(usize, 0), ghost_jobs.len);
}

// ─────────────────────────────────────────────────────────────────────
// Validation regressions
// ─────────────────────────────────────────────────────────────────────

test "conformance v2: rejects non-canonical customerRole" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const cref_bad = [_]CustomerRef{
        .{ .cellId = cellIdOf(0xa0), .role = "stakeholder", .primary = true },
    };
    try std.testing.expectError(jobs_store_fs.StoreError.invalid_customer_role, store.appendCreatedV2(.{
        .cellId = cellIdOf(0xa1),
        .typeHash = TYPE_HASH_JOB_V2,
        .customer_name = "Bad role",
        .state = "lead",
        .scheduled_at = "",
        .created_at = "2026-05-02T10:00:00Z",
        .workOrderNumber = null,
        .issuanceDate = null,
        .dueDate = null,
        .billingParty = null,
        .hasPhotos = false,
        .photoCount = null,
        .propertyKey = null,
        .siteRef = cellIdOf(0xb1),
        .customerRefs = &cref_bad,
        .attachmentRefs = &.{},
    }));
}

test "conformance v2: rejects non-canonical billingParty.type" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    try std.testing.expectError(jobs_store_fs.StoreError.invalid_billing_party_type, store.appendCreatedV2(.{
        .cellId = cellIdOf(0xa2),
        .typeHash = TYPE_HASH_JOB_V2,
        .customer_name = "Bad billing",
        .state = "lead",
        .scheduled_at = "",
        .created_at = "2026-05-02T10:00:00Z",
        .workOrderNumber = null,
        .issuanceDate = null,
        .dueDate = null,
        .billingParty = .{ .type = "tenant_pays_directly", .name = "X" },
        .hasPhotos = false,
        .photoCount = null,
        .propertyKey = null,
        .siteRef = cellIdOf(0xb2),
        .customerRefs = &.{},
        .attachmentRefs = &.{},
    }));
}

test "conformance v2: rejects customerRefs with not-exactly-one primary" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    // Zero primaries.
    {
        const cref = [_]CustomerRef{
            .{ .cellId = cellIdOf(0xc1), .role = "tenant", .primary = false },
            .{ .cellId = cellIdOf(0xc2), .role = "agent", .primary = false },
        };
        try std.testing.expectError(jobs_store_fs.StoreError.invalid_primary_count, store.appendCreatedV2(.{
            .cellId = cellIdOf(0xa3),
            .typeHash = TYPE_HASH_JOB_V2,
            .customer_name = "No primary",
            .state = "lead",
            .scheduled_at = "",
            .created_at = "2026-05-02T10:00:00Z",
            .workOrderNumber = null,
            .issuanceDate = null,
            .dueDate = null,
            .billingParty = null,
            .hasPhotos = false,
            .photoCount = null,
            .propertyKey = null,
            .siteRef = cellIdOf(0xb3),
            .customerRefs = &cref,
            .attachmentRefs = &.{},
        }));
    }

    // Two primaries.
    {
        const cref = [_]CustomerRef{
            .{ .cellId = cellIdOf(0xc1), .role = "tenant", .primary = true },
            .{ .cellId = cellIdOf(0xc2), .role = "agent", .primary = true },
        };
        try std.testing.expectError(jobs_store_fs.StoreError.invalid_primary_count, store.appendCreatedV2(.{
            .cellId = cellIdOf(0xa4),
            .typeHash = TYPE_HASH_JOB_V2,
            .customer_name = "Two primary",
            .state = "lead",
            .scheduled_at = "",
            .created_at = "2026-05-02T10:00:00Z",
            .workOrderNumber = null,
            .issuanceDate = null,
            .dueDate = null,
            .billingParty = null,
            .hasPhotos = false,
            .photoCount = null,
            .propertyKey = null,
            .siteRef = cellIdOf(0xb4),
            .customerRefs = &cref,
            .attachmentRefs = &.{},
        }));
    }
}

test "conformance backward-compat: legacy append produces v1 row" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const outcome = try store.append(.{
        .id = "j-repl-001",
        .customer_name = "AcmeCorp",
        .state = "lead",
        .scheduled_at = "",
        .created_at = "2026-05-02T10:00:00Z",
    });
    try std.testing.expectEqual(JobsStore.AppendOutcome.created, outcome);

    const got = store.findById("j-repl-001") orelse return error.MissingRecord;
    try std.testing.expectEqual(@as(u8, 1), got.version);
    try std.testing.expectEqualStrings("AcmeCorp", got.customer_name);
    try std.testing.expect(got.cellId != null); // v1 rows now get cellId from cell hash
    try std.testing.expect(got.workOrderNumber == null);
    try std.testing.expect(got.siteRef == null);
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

fn makeV2Payload(cell_byte: u8, site_ref: [32]u8, name: []const u8, state: []const u8) JobV2Payload {
    return .{
        .cellId = cellIdOf(cell_byte),
        .typeHash = TYPE_HASH_JOB_V2,
        .customer_name = name,
        .state = state,
        .scheduled_at = "",
        .created_at = "2026-05-02T10:00:00Z",
        .workOrderNumber = null,
        .issuanceDate = null,
        .dueDate = null,
        .billingParty = null,
        .hasPhotos = false,
        .photoCount = null,
        .propertyKey = null,
        .siteRef = site_ref,
        .customerRefs = &.{},
        .attachmentRefs = &.{},
    };
}

```
