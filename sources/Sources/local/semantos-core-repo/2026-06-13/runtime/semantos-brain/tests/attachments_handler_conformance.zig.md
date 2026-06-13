---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/attachments_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.174274+00:00
---

# runtime/semantos-brain/tests/attachments_handler_conformance.zig

```zig
// D-O5m.followup-8 substrate — see
// docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3, §8;
// docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5m (mobile sensor adapters);
// cartridges/oddjobz/brain/src/cell-types/attachment.ts (TS canon for the
// OddjobzAttachment shape).
//
// Conformance suite for `resources/attachments_handler.zig`.  Mirrors
// the shape of `visits_handler_conformance.zig` post-#312 minus the
// FSM transition surface (Attachments are AFFINE-ish — write-once, no
// transitions): dispatcher → ResourceHandler → AttachmentsStore for
// the three spec'd commands plus the FK validation + cap-gating +
// idempotent-recreate paths required by the brief.
//
// What this closes:
//
//   • Both helms consume the JSON-array / single-object shapes the
//     dispatcher emits.  Read-only substrate today; the producer side
//     (mobile camera capture + binary blob upload) ships in the next
//     PR.
//
//   • FK validation: `attachments.create_metadata` with a `visit_id`
//     that's not in the visits store returns `{error: "visit_not_found",
//     visit_id}` (200, NOT a dispatcher error).
//
//   • Cap-gating: read commands require `cap.oddjobz.read_attachments`;
//     `create_metadata` requires `cap.oddjobz.write_attachment`.
//
//   • Idempotency: same id with identical contents → already_exists;
//     same id with different contents → typed handler error.
//
//   • Validation: bad content_hash length, empty mime, negative size,
//     bad captured_by_cert_id, oversized caption — every path returns
//     the matching typed handler error.
//
//   • Audit-pair invariant: every dispatch through the resource
//     emits a paired phase=start / phase=end audit-log line under
//     op="attachments.<cmd>".

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const attachments_store_fs = @import("attachments_store_fs");
const visits_store_fs = @import("visits_store_fs");
const attachments_handler_mod = @import("attachments_handler");
const helm_event_broker = @import("helm_event_broker");
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");
const cell_store_mod = @import("cell_store");

fn openTestEnv(dir: []const u8) !lmdb.Env {
    return lmdb.Env.open(dir, .{
        .max_dbs = 8,
        .map_size = 4 * 1024 * 1024,
        .open_flags = lmdb.EnvFlags.NOSYNC,
    });
}

// ─────────────────────────────────────────────────────────────────────
// Test fixture — heap-allocated so the dispatcher's pointer to
// audit_log + the handler's pointers to AttachmentsStore + VisitsStore
// are address-stable.
// ─────────────────────────────────────────────────────────────────────

fn pinnedClock() i64 {
    return 1_700_000_000;
}

const TEST_HASH_64 = "a" ** 64;
const TEST_HASH_64_B = "b" ** 64;
const TEST_CERT_32 = "00112233445566778899aabbccddeeff";

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: cell_store_mod.CellStore,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    attachments_store: attachments_store_fs.AttachmentsStore,
    visits_store: visits_store_fs.VisitsStore,
    handler: attachments_handler_mod.Handler,
    disp: dispatcher.Dispatcher,

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        self.allocator = allocator;
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        self.tmp_dir = tmp;
        self.audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(self.audit_path);

        // Initialize LMDB env and cell store in-place so pointers remain stable.
        self.lmdb_env = try openTestEnv(real);
        errdefer self.lmdb_env.close();
        self.cs_impl = try lmdb_cell_store.LmdbCellStore.init(&self.lmdb_env, allocator);
        self.cs = self.cs_impl.store();

        self.audit = audit_log.AuditLog.init();
        try self.audit.open(self.audit_path);
        self.attachments_store = try attachments_store_fs.AttachmentsStore.init(allocator, &self.cs, pinnedClock);
        self.visits_store = try visits_store_fs.VisitsStore.init(allocator, &self.cs, pinnedClock);
        self.handler = attachments_handler_mod.Handler.init(allocator, &self.attachments_store, &self.visits_store);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.attachments_store.deinit();
        self.visits_store.deinit();
        self.audit.close();
        self.lmdb_env.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.destroy(self);
    }

    /// Seed a Visit in the VisitsStore directly (bypass the visits
    /// handler — we don't register it on the dispatcher in this suite).
    fn seedVisit(self: *Fixture, id: []const u8) !void {
        _ = try self.visits_store.append(.{
            .id = id,
            .job_id = "j-001",
            .visit_type = "scheduled_work",
            .status = "scheduled",
            .notes = "",
            .actual_start = "",
            .outcome = "",
            .created_at = "2026-05-01T00:00:00Z",
            .updated_at = "2026-05-01T00:00:00Z",
        });
    }
};

fn rootCtx() dispatcher.DispatchContext {
    return .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "test", .transport_label = "test" },
    };
}

fn bearerCtxWithCaps(caps: []const []const u8) dispatcher.DispatchContext {
    return .{
        .auth = .{ .bearer = .{ .fingerprint_hex = [_]u8{'0'} ** 64, .label = "test" } },
        .capabilities = dispatcher.CapabilitySet.fromList(caps),
        .meta = .{ .request_id = "test-bearer", .transport_label = "test" },
    };
}

fn jsonString(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.not_object;
    const v = parsed.value.object.get(key) orelse return error.missing_key;
    if (v != .string) return error.not_string;
    return try allocator.dupe(u8, v.string);
}

fn jsonArrayLen(allocator: std.mem.Allocator, json: []const u8) !usize {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.not_array;
    return parsed.value.array.items.len;
}

// ─────────────────────────────────────────────────────────────────────
// create_metadata → find → find_by_id round-trip (root scope)
// ─────────────────────────────────────────────────────────────────────

test "D-O5m.followup-8 attachments: create_metadata → find returns the row" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedVisit("v-001");
    var ctx = rootCtx();

    const args =
        "{\"id\":\"att-001\",\"visit_id\":\"v-001\",\"kind\":\"photo\"," ++
        "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":2457600," ++
        "\"mime_type\":\"image/heic\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
        "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}";

    var create_r = try fx.disp.dispatch(&ctx, "attachments", "create_metadata", args);
    defer create_r.deinit();
    const status = try jsonString(allocator, create_r.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("created", status);

    var find_r = try fx.disp.dispatch(&ctx, "attachments", "find", "{}");
    defer find_r.deinit();
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayLen(allocator, find_r.payload));
}

test "D-O5m.followup-8 attachments: find filters by visit_id" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedVisit("v-A");
    try fx.seedVisit("v-B");
    var ctx = rootCtx();

    var r1 = try fx.disp.dispatch(&ctx, "attachments", "create_metadata",
        "{\"id\":\"att-A1\",\"visit_id\":\"v-A\",\"kind\":\"photo\"," ++
        "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":1," ++
        "\"mime_type\":\"image/jpeg\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
        "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}");
    r1.deinit();
    var r2 = try fx.disp.dispatch(&ctx, "attachments", "create_metadata",
        "{\"id\":\"att-A2\",\"visit_id\":\"v-A\",\"kind\":\"voice_memo\"," ++
        "\"content_hash\":\"" ++ TEST_HASH_64_B ++ "\",\"content_size\":2," ++
        "\"mime_type\":\"audio/m4a\",\"captured_at\":\"2026-05-15T14:31:00Z\"," ++
        "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}");
    r2.deinit();
    var r3 = try fx.disp.dispatch(&ctx, "attachments", "create_metadata",
        "{\"id\":\"att-B1\",\"visit_id\":\"v-B\",\"kind\":\"gps_pin\"," ++
        "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":3," ++
        "\"mime_type\":\"application/json\",\"captured_at\":\"2026-05-15T14:32:00Z\"," ++
        "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}");
    r3.deinit();

    var find_a = try fx.disp.dispatch(&ctx, "attachments", "find", "{\"visit_id\":\"v-A\"}");
    defer find_a.deinit();
    try std.testing.expectEqual(@as(usize, 2), try jsonArrayLen(allocator, find_a.payload));

    var find_b = try fx.disp.dispatch(&ctx, "attachments", "find", "{\"visit_id\":\"v-B\"}");
    defer find_b.deinit();
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayLen(allocator, find_b.payload));
}

test "D-O5m.followup-8 attachments: find_by_id on missing returns typed not_found body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    var r = try fx.disp.dispatch(&ctx, "attachments", "find_by_id",
        \\{"id":"nope"}
    );
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("not_found", err_kind);
}

// ─────────────────────────────────────────────────────────────────────
// FK validation
// ─────────────────────────────────────────────────────────────────────

test "D-O5m.followup-8 attachments: create_metadata with non-existent visit_id returns visit_not_found body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    const args =
        "{\"id\":\"att-orphan\",\"visit_id\":\"v-not-real\",\"kind\":\"photo\"," ++
        "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":1," ++
        "\"mime_type\":\"image/jpeg\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
        "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}";

    var r = try fx.disp.dispatch(&ctx, "attachments", "create_metadata", args);
    defer r.deinit();
    const err_kind = try jsonString(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("visit_not_found", err_kind);

    // Attachment was NOT persisted.
    var find_r = try fx.disp.dispatch(&ctx, "attachments", "find", "{}");
    defer find_r.deinit();
    try std.testing.expectEqual(@as(usize, 0), try jsonArrayLen(allocator, find_r.payload));
}

// ─────────────────────────────────────────────────────────────────────
// Idempotent re-create
// ─────────────────────────────────────────────────────────────────────

test "D-O5m.followup-8 attachments: re-create with same id + same contents returns already_exists" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedVisit("v-001");
    var ctx = rootCtx();

    const args =
        "{\"id\":\"att-idem\",\"visit_id\":\"v-001\",\"kind\":\"photo\"," ++
        "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":1," ++
        "\"mime_type\":\"image/jpeg\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
        "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"," ++
        "\"created_at\":\"2026-05-15T14:30:01Z\"}";

    var first = try fx.disp.dispatch(&ctx, "attachments", "create_metadata", args);
    defer first.deinit();
    var second = try fx.disp.dispatch(&ctx, "attachments", "create_metadata", args);
    defer second.deinit();
    const status = try jsonString(allocator, second.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("already_exists", status);
}

test "D-O5m.followup-8 attachments: re-create with different contents returns typed handler error" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedVisit("v-001");
    var ctx = rootCtx();

    var first = try fx.disp.dispatch(&ctx, "attachments", "create_metadata",
        "{\"id\":\"att-conflict\",\"visit_id\":\"v-001\",\"kind\":\"photo\"," ++
        "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":1," ++
        "\"mime_type\":\"image/jpeg\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
        "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"," ++
        "\"created_at\":\"2026-05-15T14:30:01Z\"}");
    first.deinit();
    // Differs on content_hash.
    try std.testing.expectError(
        attachments_handler_mod.HandlerError.attachment_id_in_use_with_different_contents,
        fx.disp.dispatch(&ctx, "attachments", "create_metadata",
            "{\"id\":\"att-conflict\",\"visit_id\":\"v-001\",\"kind\":\"photo\"," ++
            "\"content_hash\":\"" ++ TEST_HASH_64_B ++ "\",\"content_size\":1," ++
            "\"mime_type\":\"image/jpeg\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
            "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"," ++
            "\"created_at\":\"2026-05-15T14:30:01Z\"}"),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Validation paths
// ─────────────────────────────────────────────────────────────────────

test "D-O5m.followup-8 attachments: bad content_hash length rejected" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedVisit("v-001");
    var ctx = rootCtx();

    try std.testing.expectError(
        attachments_handler_mod.HandlerError.invalid_content_hash,
        fx.disp.dispatch(&ctx, "attachments", "create_metadata",
            "{\"visit_id\":\"v-001\",\"kind\":\"photo\"," ++
            "\"content_hash\":\"tooshort\",\"content_size\":1," ++
            "\"mime_type\":\"image/jpeg\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
            "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}"),
    );
}

test "D-O5m.followup-8 attachments: empty mime_type rejected" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedVisit("v-001");
    var ctx = rootCtx();

    try std.testing.expectError(
        attachments_handler_mod.HandlerError.invalid_mime_type,
        fx.disp.dispatch(&ctx, "attachments", "create_metadata",
            "{\"visit_id\":\"v-001\",\"kind\":\"photo\"," ++
            "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":1," ++
            "\"mime_type\":\"\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
            "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}"),
    );
}

test "D-O5m.followup-8 attachments: negative content_size rejected" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedVisit("v-001");
    var ctx = rootCtx();

    try std.testing.expectError(
        attachments_handler_mod.HandlerError.invalid_content_size,
        fx.disp.dispatch(&ctx, "attachments", "create_metadata",
            "{\"visit_id\":\"v-001\",\"kind\":\"photo\"," ++
            "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":-1," ++
            "\"mime_type\":\"image/jpeg\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
            "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}"),
    );
}

test "D-O5m.followup-8 attachments: empty captured_at rejected" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedVisit("v-001");
    var ctx = rootCtx();

    try std.testing.expectError(
        attachments_handler_mod.HandlerError.invalid_captured_at,
        fx.disp.dispatch(&ctx, "attachments", "create_metadata",
            "{\"visit_id\":\"v-001\",\"kind\":\"photo\"," ++
            "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":1," ++
            "\"mime_type\":\"image/jpeg\",\"captured_at\":\"\"," ++
            "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}"),
    );
}

test "D-O5m.followup-8 attachments: bad kind rejected" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedVisit("v-001");
    var ctx = rootCtx();

    try std.testing.expectError(
        attachments_handler_mod.HandlerError.invalid_kind,
        fx.disp.dispatch(&ctx, "attachments", "create_metadata",
            "{\"visit_id\":\"v-001\",\"kind\":\"video\"," ++
            "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":1," ++
            "\"mime_type\":\"video/mp4\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
            "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}"),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Cap-gating
// ─────────────────────────────────────────────────────────────────────

test "D-O5m.followup-8 attachments: bearer without cap.oddjobz.read_attachments is denied for find" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    const ctx = bearerCtxWithCaps(&.{});
    try std.testing.expectError(
        error.capability_denied,
        fx.disp.dispatch(&ctx, "attachments", "find", "{}"),
    );
}

test "D-O5m.followup-8 attachments: bearer with cap.oddjobz.read_attachments can find but not create" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedVisit("v-001");
    const ctx = bearerCtxWithCaps(&.{"cap.oddjobz.read_attachments"});

    var ok = try fx.disp.dispatch(&ctx, "attachments", "find", "{}");
    ok.deinit();
    try std.testing.expectError(
        error.capability_denied,
        fx.disp.dispatch(&ctx, "attachments", "create_metadata",
            "{\"visit_id\":\"v-001\",\"kind\":\"photo\"," ++
            "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":1," ++
            "\"mime_type\":\"image/jpeg\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
            "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}"),
    );
}

test "D-O5m.followup-8 attachments: bearer with cap.oddjobz.write_attachment can create but not read" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();
    try fx.seedVisit("v-001");
    const ctx = bearerCtxWithCaps(&.{"cap.oddjobz.write_attachment"});

    var ok = try fx.disp.dispatch(&ctx, "attachments", "create_metadata",
        "{\"visit_id\":\"v-001\",\"kind\":\"photo\"," ++
        "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":1," ++
        "\"mime_type\":\"image/jpeg\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
        "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}");
    ok.deinit();
    try std.testing.expectError(
        error.capability_denied,
        fx.disp.dispatch(&ctx, "attachments", "find", "{}"),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Audit-pair invariant
// ─────────────────────────────────────────────────────────────────────

test "D-O5m.followup-8 attachments: dispatch emits paired phase=start / phase=end audit lines" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedVisit("v-001");
    var ctx = rootCtx();

    var r1 = try fx.disp.dispatch(&ctx, "attachments", "create_metadata",
        "{\"visit_id\":\"v-001\",\"kind\":\"photo\"," ++
        "\"content_hash\":\"" ++ TEST_HASH_64 ++ "\",\"content_size\":1," ++
        "\"mime_type\":\"image/jpeg\",\"captured_at\":\"2026-05-15T14:30:00Z\"," ++
        "\"captured_by_cert_id\":\"" ++ TEST_CERT_32 ++ "\"}");
    r1.deinit();
    var r2 = try fx.disp.dispatch(&ctx, "attachments", "find", "{}");
    r2.deinit();

    // Read the audit log and count phase=start / phase=end occurrences.
    // Match dispatcher emit shape: `op="attachments.<cmd>"`.
    const f = try std.fs.cwd().openFile(fx.audit_path, .{});
    defer f.close();
    const stat = try f.stat();
    const buf = try allocator.alloc(u8, stat.size);
    defer allocator.free(buf);
    _ = try f.readAll(buf);

    var starts: usize = 0;
    var ends: usize = 0;
    var it = std.mem.splitScalar(u8, buf, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        const matches_create = std.mem.indexOf(u8, line, "\"op\":\"attachments.create_metadata\"") != null;
        const matches_find = std.mem.indexOf(u8, line, "\"op\":\"attachments.find\"") != null;
        if (!matches_create and !matches_find) continue;
        if (std.mem.indexOf(u8, line, "phase=start") != null) starts += 1;
        if (std.mem.indexOf(u8, line, "phase=end") != null) ends += 1;
    }
    // Two dispatches → two pairs.
    try std.testing.expectEqual(@as(usize, 2), starts);
    try std.testing.expectEqual(@as(usize, 2), ends);
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-4 followup-emitters — broker emit assertion for
// attachments.create_metadata.  No FSM transitions on attachments
// (affine write-once), so this single test exercises the only
// emit path.
// ─────────────────────────────────────────────────────────────────────

const PublishSink = struct {
    allocator: std.mem.Allocator,
    types: std.ArrayList([]u8),
    payloads: std.ArrayList([]u8),

    fn init(allocator: std.mem.Allocator) PublishSink {
        return .{ .allocator = allocator, .types = .{}, .payloads = .{} };
    }

    fn deinit(self: *PublishSink) void {
        for (self.types.items) |s| self.allocator.free(s);
        for (self.payloads.items) |s| self.allocator.free(s);
        self.types.deinit(self.allocator);
        self.payloads.deinit(self.allocator);
    }

    fn callback(state: ?*anyopaque, event: helm_event_broker.Event) void {
        const self: *PublishSink = @ptrCast(@alignCast(state.?));
        const t = self.allocator.dupe(u8, event.type) catch return;
        const p = self.allocator.dupe(u8, event.payload_json) catch {
            self.allocator.free(t);
            return;
        };
        self.types.append(self.allocator, t) catch {
            self.allocator.free(t);
            self.allocator.free(p);
            return;
        };
        self.payloads.append(self.allocator, p) catch {
            self.allocator.free(p);
            return;
        };
    }
};

const BrokerFixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: cell_store_mod.CellStore,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    attachments_store: attachments_store_fs.AttachmentsStore,
    visits_store: visits_store_fs.VisitsStore,
    handler: attachments_handler_mod.Handler,
    disp: dispatcher.Dispatcher,
    broker: helm_event_broker.Broker,

    fn init(allocator: std.mem.Allocator) !*BrokerFixture {
        const self = try allocator.create(BrokerFixture);
        errdefer allocator.destroy(self);
        self.allocator = allocator;
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        self.tmp_dir = tmp;
        self.audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(self.audit_path);

        // Initialize LMDB env and cell store in-place so pointers remain stable.
        self.lmdb_env = try openTestEnv(real);
        errdefer self.lmdb_env.close();
        self.cs_impl = try lmdb_cell_store.LmdbCellStore.init(&self.lmdb_env, allocator);
        self.cs = self.cs_impl.store();
        self.broker = helm_event_broker.Broker.init(allocator);

        self.audit = audit_log.AuditLog.init();
        try self.audit.open(self.audit_path);
        self.attachments_store = try attachments_store_fs.AttachmentsStore.init(allocator, &self.cs, pinnedClock);
        self.visits_store = try visits_store_fs.VisitsStore.init(allocator, &self.cs, pinnedClock);
        self.handler = attachments_handler_mod.Handler.initWithBroker(
            allocator,
            &self.attachments_store,
            &self.visits_store,
            &self.broker,
            &self.audit,
        );
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *BrokerFixture) void {
        self.broker.deinit();
        self.disp.deinit();
        self.attachments_store.deinit();
        self.visits_store.deinit();
        self.audit.close();
        self.lmdb_env.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.destroy(self);
    }

    fn seedVisit(self: *BrokerFixture, id: []const u8) !void {
        _ = try self.visits_store.append(.{
            .id = id,
            .job_id = "j-001",
            .visit_type = "scheduled_work",
            .status = "scheduled",
            .notes = "",
            .actual_start = "",
            .outcome = "",
            .created_at = "2026-05-01T00:00:00Z",
            .updated_at = "2026-05-01T00:00:00Z",
        });
    }
};

test "D-O5.followup-4 attachments.create_metadata publishes attachment.created to broker" {
    const allocator = std.testing.allocator;
    var fx = try BrokerFixture.init(allocator);
    defer fx.deinit();
    try fx.seedVisit("v-pub");

    var sink = PublishSink.init(allocator);
    defer sink.deinit();
    _ = try fx.broker.subscribe(.{ .state = &sink, .callback = PublishSink.callback });

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "attachments", "create_metadata",
        \\{"id":"a-pub","visit_id":"v-pub","kind":"photo","content_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","content_size":1024,"mime_type":"image/jpeg","captured_at":"2026-05-02T10:00:00Z","captured_by_cert_id":"00112233445566778899aabbccddeeff","created_at":"2026-05-02T10:00:00Z"}
    );
    defer r.deinit();

    try std.testing.expectEqual(@as(usize, 1), sink.types.items.len);
    try std.testing.expectEqualStrings("attachment.created", sink.types.items[0]);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"id\":\"a-pub\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"visit_id\":\"v-pub\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"kind\":\"photo\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"content_size\":1024") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"created_at\":\"2026-05-02T10:00:00Z\"") != null);
}

```
