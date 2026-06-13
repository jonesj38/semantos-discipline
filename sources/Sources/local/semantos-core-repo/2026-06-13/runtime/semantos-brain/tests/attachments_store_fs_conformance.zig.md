---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/attachments_store_fs_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.175310+00:00
---

# runtime/semantos-brain/tests/attachments_store_fs_conformance.zig

```zig
// D-DOG.1.0c Phase 2A.2 — attachments_store_fs.zig conformance tests
// (the v2 graph-aware extension).
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 row C.5;
//            cartridges/oddjobz/brain/src/cell-types/attachment.v2.ts (the v2
//            schema this store mirrors a subset of).
//
// The v1-shape conformance (visit-side flow — D-O5m mobile-camera
// capture) lives in `tests/attachments_handler_conformance.zig` and
// `src/attachments_store_fs.zig`'s inline tests.  THIS file exercises:
//
//   • Visit-side `append` regression — the v2 extension is additive,
//     v1 row round-trips MUST still work bit-for-bit.
//   • appendV2 with the visit-captured shape (visit_id set, all v1
//     required fields set, plus the v2 graph-aware extras).
//   • appendV2 with the PDF-source shape (visit_id "" + sourceBlobKey
//     set + pageCount/photoCount/hasPhotos populated; the v1 required
//     fields are RELAXED per the schema).
//   • findForJob filters correctly — v2 rows linked to the requested
//     jobRef are returned; rows with mismatched jobRef are skipped;
//     v1 rows (no jobRef) are filtered out.
//   • getByCellId round-trips a v2 row by raw [32]u8.
//   • Mixed v1+v2 row inserts survive within-record arena growth
//     (#308 / sites regression pattern).

const std = @import("std");
const attachments_store_fs = @import("attachments_store_fs");
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");

const AttachmentsStore = attachments_store_fs.AttachmentsStore;
const Attachment = attachments_store_fs.Attachment;
const AttachmentV2Payload = AttachmentsStore.AttachmentV2Payload;

fn pinnedClock() i64 {
    return 1_700_000_000;
}

fn cellIdOf(byte: u8) [32]u8 {
    var out: [32]u8 = undefined;
    @memset(&out, byte);
    return out;
}

const TYPE_HASH_ATTACHMENT_V2: [32]u8 = blk: {
    var out: [32]u8 = undefined;
    for (0..32) |i| out[i] = @intCast(0x80 + i);
    break :blk out;
};

const TEST_HASH_64 = "a" ** 64;
const TEST_CERT_32 = "00112233445566778899aabbccddeeff";

fn openTestEnv(dir: []const u8) !lmdb.Env {
    return lmdb.Env.open(dir, .{
        .max_dbs = 8,
        .map_size = 4 * 1024 * 1024,
        .open_flags = lmdb.EnvFlags.NOSYNC,
    });
}

test "conformance: v1 visit-side append still round-trips (visit-side flow preserved)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try AttachmentsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    try std.testing.expectEqual(AttachmentsStore.AppendOutcome.created, try store.append(.{
        .id = "att-v1-001",
        .visit_id = "v-001",
        .kind = "photo",
        .content_hash = TEST_HASH_64,
        .content_size = 2_457_600,
        .mime_type = "image/heic",
        .captured_at = "2026-05-15T14:30:00Z",
        .captured_by_cert_id = TEST_CERT_32,
        .caption = "Eaves photo",
        .created_at = "2026-05-15T14:30:01Z",
    }));

    // v2 fields default to null on v1 rows.
    const got = store.findById("att-v1-001") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("photo", got.kind);
    try std.testing.expectEqualStrings("v-001", got.visit_id);
    try std.testing.expect(got.cellId == null);
    try std.testing.expect(got.typeHash == null);
    try std.testing.expect(got.jobRef == null);
    try std.testing.expect(got.sourceBlobKey == null);
    try std.testing.expect(got.pageCount == null);
    try std.testing.expect(got.photoCount == null);
    try std.testing.expectEqual(false, got.hasPhotos);

    // Round-trip across re-init — v1 rows replay back at the v1 shape.
    var env2 = try openTestEnv(data_dir);
    defer env2.close();
    var cs_impl2 = try lmdb_cell_store.LmdbCellStore.init(&env2, allocator);
    const cs2 = cs_impl2.store();
    var store2 = try AttachmentsStore.init(allocator, &cs2, pinnedClock);
    defer store2.deinit();
    const reloaded = store2.findById("att-v1-001") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("Eaves photo", reloaded.caption);
    try std.testing.expectEqual(@as(i64, 2_457_600), reloaded.content_size);
    try std.testing.expect(reloaded.cellId == null);
}

test "conformance: appendV2 round-trips a PDF-source row" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try AttachmentsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const cellId = cellIdOf(0xa1);
    const jobRef = cellIdOf(0xb2);

    try std.testing.expectEqual(AttachmentsStore.AppendOutcome.created, try store.appendV2(.{
        .id = "att-pdf-001",
        // PDF-source shape — every visit-side field empty.
        .visit_id = "",
        .kind = "",
        .content_hash = "",
        .content_size = 0,
        .mime_type = "application/pdf",
        .captured_at = "",
        .captured_by_cert_id = "",
        .caption = "Source PDF for WO-12345",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellId,
        .typeHash = TYPE_HASH_ATTACHMENT_V2,
        .jobRef = jobRef,
        .sourceBlobKey = "legacy-ingest/blob/abc123",
        .pageCount = 4,
        .photoCount = 3,
        .hasPhotos = true,
    }));

    const got = store.getByCellId(cellId) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("application/pdf", got.mime_type);
    try std.testing.expectEqualStrings("legacy-ingest/blob/abc123", got.sourceBlobKey.?);
    try std.testing.expectEqual(@as(u32, 4), got.pageCount.?);
    try std.testing.expectEqual(@as(u32, 3), got.photoCount.?);
    try std.testing.expectEqual(true, got.hasPhotos);
    try std.testing.expectEqualSlices(u8, &cellId, &got.cellId.?);
    try std.testing.expectEqualSlices(u8, &jobRef, &got.jobRef.?);
    try std.testing.expectEqualStrings("", got.visit_id);

    // Reload from disk — JSONL replay rebuilds every v2 field.
    var env2 = try openTestEnv(data_dir);
    defer env2.close();
    var cs_impl2 = try lmdb_cell_store.LmdbCellStore.init(&env2, allocator);
    const cs2 = cs_impl2.store();
    var store2 = try AttachmentsStore.init(allocator, &cs2, pinnedClock);
    defer store2.deinit();
    const got2 = store2.getByCellId(cellId) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("legacy-ingest/blob/abc123", got2.sourceBlobKey.?);
    try std.testing.expectEqual(@as(u32, 4), got2.pageCount.?);
    try std.testing.expectEqual(true, got2.hasPhotos);
    try std.testing.expectEqualSlices(u8, &jobRef, &got2.jobRef.?);
}

test "conformance: appendV2 round-trips a visit-captured v2 row" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try AttachmentsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    // Visit-captured v2 — v1 required fields PRESENT plus v2 extras.
    // sourceBlobKey null (the bytes live elsewhere); pageCount /
    // photoCount null (it's a single image, not a multi-page PDF);
    // hasPhotos derives to false.
    const cellId = cellIdOf(0xc3);
    const jobRef = cellIdOf(0xd4);
    try std.testing.expectEqual(AttachmentsStore.AppendOutcome.created, try store.appendV2(.{
        .id = "att-vis-001",
        .visit_id = "v-001",
        .kind = "photo",
        .content_hash = TEST_HASH_64,
        .content_size = 1024,
        .mime_type = "image/jpeg",
        .captured_at = "2026-05-15T14:30:00Z",
        .captured_by_cert_id = TEST_CERT_32,
        .caption = "",
        .created_at = "2026-05-15T14:30:01Z",
        .cellId = cellId,
        .typeHash = TYPE_HASH_ATTACHMENT_V2,
        .jobRef = jobRef,
        .sourceBlobKey = null,
        .pageCount = null,
        .photoCount = null,
        .hasPhotos = false,
    }));

    const got = store.getByCellId(cellId) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("photo", got.kind);
    try std.testing.expectEqualStrings("v-001", got.visit_id);
    try std.testing.expect(got.sourceBlobKey == null);
    try std.testing.expect(got.pageCount == null);
    try std.testing.expectEqual(false, got.hasPhotos);
    try std.testing.expectEqualSlices(u8, &jobRef, &got.jobRef.?);
}

test "conformance: appendV2 rejects has_photos parity mismatch" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try AttachmentsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    // photoCount = 0 but hasPhotos = true → the schema's parity rule
    // is violated.  Phase 2A.4's translator must compute hasPhotos
    // from photoCount, never accept caller-supplied bytes.
    try std.testing.expectError(attachments_store_fs.StoreError.has_photos_mismatch, store.appendV2(.{
        .id = "att-bad",
        .mime_type = "application/pdf",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellIdOf(0xee),
        .typeHash = TYPE_HASH_ATTACHMENT_V2,
        .jobRef = null,
        .sourceBlobKey = "blob/x",
        .pageCount = 1,
        .photoCount = 0,
        .hasPhotos = true,
    }));
}

test "conformance: findForJob returns v2 rows filtered by jobRef; skips v1 rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try AttachmentsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const job_a = cellIdOf(0x11);
    const job_b = cellIdOf(0x22);

    // v1 row — must be filtered out of every findForJob result.
    _ = try store.append(.{
        .id = "att-v1-pre",
        .visit_id = "v-pre",
        .kind = "photo",
        .content_hash = TEST_HASH_64,
        .content_size = 1,
        .mime_type = "image/jpeg",
        .captured_at = "2026-01-01T00:00:00Z",
        .captured_by_cert_id = TEST_CERT_32,
        .caption = "",
        .created_at = "2026-01-01T00:00:00Z",
    });
    // Three v2 rows: 2 against job_a, 1 against job_b.
    _ = try store.appendV2(.{
        .id = "att-pdf-a1",
        .mime_type = "application/pdf",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellIdOf(0xa1),
        .typeHash = TYPE_HASH_ATTACHMENT_V2,
        .jobRef = job_a,
        .sourceBlobKey = "blob/a1",
        .pageCount = 1,
        .photoCount = 0,
        .hasPhotos = false,
    });
    _ = try store.appendV2(.{
        .id = "att-pdf-a2",
        .mime_type = "application/pdf",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellIdOf(0xa2),
        .typeHash = TYPE_HASH_ATTACHMENT_V2,
        .jobRef = job_a,
        .sourceBlobKey = "blob/a2",
        .pageCount = 2,
        .photoCount = 1,
        .hasPhotos = true,
    });
    _ = try store.appendV2(.{
        .id = "att-pdf-b1",
        .mime_type = "application/pdf",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellIdOf(0xb1),
        .typeHash = TYPE_HASH_ATTACHMENT_V2,
        .jobRef = job_b,
        .sourceBlobKey = "blob/b1",
        .pageCount = 5,
        .photoCount = 0,
        .hasPhotos = false,
    });

    const a_rows = try store.findForJob(allocator, job_a);
    defer allocator.free(a_rows);
    try std.testing.expectEqual(@as(usize, 2), a_rows.len);
    // Append-order is preserved.
    try std.testing.expectEqualStrings("att-pdf-a1", a_rows[0].id);
    try std.testing.expectEqualStrings("att-pdf-a2", a_rows[1].id);

    const b_rows = try store.findForJob(allocator, job_b);
    defer allocator.free(b_rows);
    try std.testing.expectEqual(@as(usize, 1), b_rows.len);
    try std.testing.expectEqualStrings("att-pdf-b1", b_rows[0].id);

    // Unknown jobRef → empty.
    const c_rows = try store.findForJob(allocator, cellIdOf(0xee));
    defer allocator.free(c_rows);
    try std.testing.expectEqual(@as(usize, 0), c_rows.len);
}

test "conformance: idempotent appendV2 preserves count" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try AttachmentsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    const payload: AttachmentV2Payload = .{
        .id = "att-idem",
        .mime_type = "application/pdf",
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = cellIdOf(0x77),
        .typeHash = TYPE_HASH_ATTACHMENT_V2,
        .jobRef = null,
        .sourceBlobKey = "blob/idem",
        .pageCount = 1,
        .photoCount = null,
        .hasPhotos = false,
    };
    try std.testing.expectEqual(AttachmentsStore.AppendOutcome.created, try store.appendV2(payload));
    try std.testing.expectEqual(AttachmentsStore.AppendOutcome.already_exists, try store.appendV2(payload));
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

test "conformance: getByCellId returns null for v1 rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try AttachmentsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    _ = try store.append(.{
        .id = "att-only-v1",
        .visit_id = "v",
        .kind = "photo",
        .content_hash = TEST_HASH_64,
        .content_size = 1,
        .mime_type = "image/jpeg",
        .captured_at = "2026-01-01T00:00:00Z",
        .captured_by_cert_id = TEST_CERT_32,
        .caption = "",
        .created_at = "2026-01-01T00:00:00Z",
    });
    try std.testing.expect(store.findById("att-only-v1") != null);
    try std.testing.expect(store.getByCellId(cellIdOf(0x00)) == null);
}

test "conformance: mixed v1+v2 inserts survive within-record arena growth" {
    // Mirrors the analogous customers / sites regression — the
    // per-string `allocator.dupe` posture in attachments_store_fs is
    // already pointer-stable per record (see OwnedStrings), so this is
    // a sanity check that the v2 add-on path keeps that property.
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var env = try openTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try AttachmentsStore.init(allocator, &cs, pinnedClock);
    defer store.deinit();

    // Wide v2 PDF row.
    var caption_buf: [attachments_store_fs.MAX_CAPTION_BYTES]u8 = undefined;
    @memset(&caption_buf, 'c');
    var blob_key_buf: [attachments_store_fs.MAX_SOURCE_BLOB_KEY_BYTES]u8 = undefined;
    @memset(&blob_key_buf, 'k');

    _ = try store.append(.{
        .id = "att-v1-narrow",
        .visit_id = "v-narrow",
        .kind = "photo",
        .content_hash = TEST_HASH_64,
        .content_size = 1,
        .mime_type = "image/jpeg",
        .captured_at = "2026-01-01T00:00:00Z",
        .captured_by_cert_id = TEST_CERT_32,
        .caption = "narrow",
        .created_at = "2026-01-01T00:00:00Z",
    });

    const wide_cell = cellIdOf(0xab);
    _ = try store.appendV2(.{
        .id = "att-wide-pdf",
        .mime_type = "application/pdf",
        .caption = &caption_buf,
        .created_at = "2026-05-02T10:00:00Z",
        .cellId = wide_cell,
        .typeHash = TYPE_HASH_ATTACHMENT_V2,
        .jobRef = cellIdOf(0xcd),
        .sourceBlobKey = &blob_key_buf,
        .pageCount = 99,
        .photoCount = 7,
        .hasPhotos = true,
    });

    _ = try store.append(.{
        .id = "att-v1-post",
        .visit_id = "v-post",
        .kind = "voice_memo",
        .content_hash = TEST_HASH_64,
        .content_size = 1,
        .mime_type = "audio/m4a",
        .captured_at = "2026-01-02T00:00:00Z",
        .captured_by_cert_id = TEST_CERT_32,
        .caption = "post",
        .created_at = "2026-01-02T00:00:00Z",
    });
    try std.testing.expectEqual(@as(usize, 3), store.count());

    const got = store.getByCellId(wide_cell) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings(&caption_buf, got.caption);
    try std.testing.expectEqualStrings(&blob_key_buf, got.sourceBlobKey.?);
    try std.testing.expectEqual(@as(u32, 99), got.pageCount.?);
    try std.testing.expectEqual(true, got.hasPhotos);

    // The pre / post v1 rows are still intact.
    const pre = store.findById("att-v1-narrow") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("narrow", pre.caption);
    const post = store.findById("att-v1-post") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("voice_memo", post.kind);
}

```
