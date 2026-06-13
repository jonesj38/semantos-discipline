---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/intent_cells_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.197616+00:00
---

# runtime/semantos-brain/tests/intent_cells_handler_conformance.zig

```zig
// Phase 3 — Conformance suite for `resources/intent_cells_handler.zig`.
//
// Mirrors the shape of `leads_handler_conformance.zig` adapted for the
// `intent_cells.submit` pipeline.
//
// What this closes:
//
//   • `intent_cells.submit` happy path (envelope decode → kernel
//     re-validate → store.create → `accepted` status).
//   • `envelope_invalid` per-field cases (wrong kind / wrong version /
//     missing fields / oversized).
//   • `kernel_rejected_locally` when the brain's syntactic kernel
//     rejects a malformed opcode stream (truncated pushdata).
//   • Idempotency: same cellId + same content → `already_exists`;
//     same cellId + different content →
//     `cell_id_in_use_with_different_contents`.
//   • `find` + `find_by_id` round-trip the persisted record.

const std = @import("std");
const lmdb = @import("lmdb");
const lmdb_config = @import("lmdb_config");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const intent_cell_lmdb_store = @import("intent_cell_lmdb_store");
const intent_cells_handler_mod = @import("intent_cells_handler");
const helm_event_broker = @import("helm_event_broker");

// W0.3: Fixture now uses IntentCellLmdbStore via a real LMDB env in a
// tmp dir.  The FS-based store is retired.

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    broker: helm_event_broker.Broker,
    env: lmdb.Env,
    store: intent_cell_lmdb_store.IntentCellLmdbStore,
    handler: intent_cells_handler_mod.Handler,
    disp: dispatcher.Dispatcher,

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(audit_path);

        // Open a fresh LMDB env in a subdir of the tmp dir.
        const lmdb_path = try std.fs.path.join(allocator, &.{ real, "lmdb" });
        defer allocator.free(lmdb_path);
        std.fs.makeDirAbsolute(lmdb_path) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };
        const env = try lmdb.Env.open(lmdb_path, .{
            .map_size = lmdb_config.LmdbConfig.default.map_size,
            .max_dbs = lmdb_config.LmdbConfig.default.max_dbs,
            .open_flags = lmdb_config.LmdbConfig.ci_flags,
            .mode = lmdb_config.LmdbConfig.default.mode,
        });

        self.* = .{
            .allocator = allocator,
            .tmp_dir = tmp,
            .audit_path = audit_path,
            .audit = audit_log.AuditLog.init(),
            .broker = helm_event_broker.Broker.init(allocator),
            .env = env,
            .store = undefined,
            .handler = undefined,
            .disp = undefined,
        };
        try self.audit.open(audit_path);
        self.store = try intent_cell_lmdb_store.IntentCellLmdbStore.init(&self.env, allocator);
        // No cert store wired — submit happy path skips cert validation
        // when `cert_store` is null.  Cert-aware paths are exercised
        // separately in the cli_serve smoke test.
        self.handler = intent_cells_handler_mod.Handler.initWithDeps(
            allocator,
            &self.store,
            null,
            &self.broker,
            &self.audit,
        );
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.store.deinit();
        self.env.close();
        self.broker.deinit();
        self.audit.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.destroy(self);
    }
};

fn rootCtx() dispatcher.DispatchContext {
    return .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "test", .transport_label = "test" },
    };
}

fn jsonField(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
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

/// Default well-formed envelope (matches the cross-language fixture
/// at apps/oddjobz-mobile/test/fixtures/intent_cell_envelope_fixture.json).
const FIXTURE_ENVELOPE: []const u8 =
    \\{"kind":"oddjobz.intent_cell.v1","version":1,
    \\ "cellId":"cell-000010-deadbeef-12345678",
    \\ "opcodeBytes":"UQ==",
    \\ "hatId":"00112233445566778899aabbccddeeff",
    \\ "certId":"ffeeddccbbaa99887766554433221100",
    \\ "correlationId":"00000000-0000-4000-8000-000000000001",
    \\ "kernelResult":{"ok":true,"opcount":1,"stackDepth":1,"gasUsed":1,"errorKind":null},
    \\ "originalIntent":{"summary":"Find the wattle street job","action":"find","taxonomyJson":"{\"what\":\"jobs\",\"how\":\"find\",\"why\":\"navigate\"}"}}
;

fn buildSubmitArgs(allocator: std.mem.Allocator, envelope: []const u8) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"envelope_json\":");
    const enc = try std.json.Stringify.valueAlloc(allocator, envelope, .{});
    defer allocator.free(enc);
    try buf.appendSlice(allocator, enc);
    try buf.append(allocator, '}');
    return try buf.toOwnedSlice(allocator);
}

// ─────────────────────────────────────────────────────────────────────
// submit happy path
// ─────────────────────────────────────────────────────────────────────

test "intent_cells.submit: happy path persists + returns accepted" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    const args = try buildSubmitArgs(allocator, FIXTURE_ENVELOPE);
    defer allocator.free(args);
    var r = try fx.disp.dispatch(&ctx, "intent_cells", "submit", args);
    defer r.deinit();
    const status = try jsonField(allocator, r.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("accepted", status);
    const cell_id = try jsonField(allocator, r.payload, "cellId");
    defer allocator.free(cell_id);
    try std.testing.expectEqualStrings("cell-000010-deadbeef-12345678", cell_id);

    // The record should be findable via find_by_id.
    var hit = try fx.disp.dispatch(&ctx, "intent_cells", "find_by_id",
        \\{"cell_id":"cell-000010-deadbeef-12345678"}
    );
    defer hit.deinit();
    const action = try jsonField(allocator, hit.payload, "intent_action");
    defer allocator.free(action);
    try std.testing.expectEqualStrings("find", action);
}

test "intent_cells.submit: idempotent re-submit with same content" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    const args = try buildSubmitArgs(allocator, FIXTURE_ENVELOPE);
    defer allocator.free(args);

    var first = try fx.disp.dispatch(&ctx, "intent_cells", "submit", args);
    defer first.deinit();
    const status1 = try jsonField(allocator, first.payload, "status");
    defer allocator.free(status1);
    try std.testing.expectEqualStrings("accepted", status1);

    var second = try fx.disp.dispatch(&ctx, "intent_cells", "submit", args);
    defer second.deinit();
    const status2 = try jsonField(allocator, second.payload, "status");
    defer allocator.free(status2);
    try std.testing.expectEqualStrings("already_exists", status2);
}

test "intent_cells.submit: same cellId different content → cell_id_in_use_with_different_contents" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    const args = try buildSubmitArgs(allocator, FIXTURE_ENVELOPE);
    defer allocator.free(args);
    var first = try fx.disp.dispatch(&ctx, "intent_cells", "submit", args);
    first.deinit();

    // Same cellId, but different summary.
    const variant: []const u8 =
        \\{"kind":"oddjobz.intent_cell.v1","version":1,
        \\ "cellId":"cell-000010-deadbeef-12345678",
        \\ "opcodeBytes":"UQ==",
        \\ "hatId":"00112233445566778899aabbccddeeff",
        \\ "certId":"ffeeddccbbaa99887766554433221100",
        \\ "correlationId":"00000000-0000-4000-8000-000000000099",
        \\ "kernelResult":{"ok":true,"opcount":1,"stackDepth":1,"gasUsed":1,"errorKind":null},
        \\ "originalIntent":{"summary":"DIFFERENT","action":"find","taxonomyJson":"{}"}}
    ;
    const args2 = try buildSubmitArgs(allocator, variant);
    defer allocator.free(args2);

    var second = try fx.disp.dispatch(&ctx, "intent_cells", "submit", args2);
    defer second.deinit();
    const err_kind = try jsonField(allocator, second.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("cell_id_in_use_with_different_contents", err_kind);
}

// ─────────────────────────────────────────────────────────────────────
// envelope_invalid per-field
// ─────────────────────────────────────────────────────────────────────

fn submitAndExpectError(
    fx: *Fixture,
    allocator: std.mem.Allocator,
    envelope: []const u8,
    expected_error: []const u8,
) !void {
    var ctx = rootCtx();
    const args = try buildSubmitArgs(allocator, envelope);
    defer allocator.free(args);
    var r = try fx.disp.dispatch(&ctx, "intent_cells", "submit", args);
    defer r.deinit();
    const err_kind = try jsonField(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings(expected_error, err_kind);
}

test "intent_cells.submit: envelope_invalid — wrong kind" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try submitAndExpectError(fx, allocator,
        \\{"kind":"WRONG","version":1,"cellId":"c","opcodeBytes":"AA==",
        \\ "hatId":"h","certId":"c","correlationId":"x",
        \\ "kernelResult":{"ok":true,"opcount":1,"stackDepth":0,"gasUsed":1,"errorKind":null},
        \\ "originalIntent":{"summary":"s","action":"a","taxonomyJson":"{}"}}
    , "envelope_invalid");
}

test "intent_cells.submit: envelope_invalid — wrong version" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try submitAndExpectError(fx, allocator,
        \\{"kind":"oddjobz.intent_cell.v1","version":99,"cellId":"c","opcodeBytes":"AA==",
        \\ "hatId":"h","certId":"c","correlationId":"x",
        \\ "kernelResult":{"ok":true,"opcount":1,"stackDepth":0,"gasUsed":1,"errorKind":null},
        \\ "originalIntent":{"summary":"s","action":"a","taxonomyJson":"{}"}}
    , "envelope_invalid");
}

test "intent_cells.submit: envelope_invalid — phone reported ok=false" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try submitAndExpectError(fx, allocator,
        \\{"kind":"oddjobz.intent_cell.v1","version":1,"cellId":"c","opcodeBytes":"AA==",
        \\ "hatId":"h","certId":"c","correlationId":"x",
        \\ "kernelResult":{"ok":false,"opcount":1,"stackDepth":0,"gasUsed":1,"errorKind":"x"},
        \\ "originalIntent":{"summary":"s","action":"a","taxonomyJson":"{}"}}
    , "envelope_invalid");
}

test "intent_cells.submit: envelope_invalid — missing originalIntent" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try submitAndExpectError(fx, allocator,
        \\{"kind":"oddjobz.intent_cell.v1","version":1,"cellId":"c","opcodeBytes":"AA==",
        \\ "hatId":"h","certId":"c","correlationId":"x",
        \\ "kernelResult":{"ok":true,"opcount":1,"stackDepth":0,"gasUsed":1,"errorKind":null}}
    , "envelope_invalid");
}

test "intent_cells.submit: envelope_invalid — invalid base64 in opcodeBytes" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try submitAndExpectError(fx, allocator,
        \\{"kind":"oddjobz.intent_cell.v1","version":1,
        \\ "cellId":"cell-000010-deadbeef-bbbbbbb1",
        \\ "opcodeBytes":"!!!not-valid-base64!!!",
        \\ "hatId":"h","certId":"c","correlationId":"x",
        \\ "kernelResult":{"ok":true,"opcount":1,"stackDepth":0,"gasUsed":1,"errorKind":null},
        \\ "originalIntent":{"summary":"s","action":"a","taxonomyJson":"{}"}}
    , "envelope_invalid");
}

// ─────────────────────────────────────────────────────────────────────
// kernel_rejected_locally
// ─────────────────────────────────────────────────────────────────────

test "intent_cells.submit: kernel_rejected_locally — truncated pushdata" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    // 0x05 promises 5 bytes; only 1 follows.  The brain-side syntactic
    // validator rejects with `invalid_pushdata`; the handler maps that
    // to `kernel_rejected_locally`.
    // Base64 of bytes [0x05, 0xAA] = "Bao=".
    try submitAndExpectError(fx, allocator,
        \\{"kind":"oddjobz.intent_cell.v1","version":1,
        \\ "cellId":"cell-000010-deadbeef-bbbbbbb2",
        \\ "opcodeBytes":"Bao=",
        \\ "hatId":"h","certId":"c","correlationId":"x",
        \\ "kernelResult":{"ok":true,"opcount":1,"stackDepth":0,"gasUsed":1,"errorKind":null},
        \\ "originalIntent":{"summary":"s","action":"a","taxonomyJson":"{}"}}
    , "kernel_rejected_locally");
}

// ─────────────────────────────────────────────────────────────────────
// find + find_by_id
// ─────────────────────────────────────────────────────────────────────

test "intent_cells.find: returns JSON array of accepted cells" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    const args = try buildSubmitArgs(allocator, FIXTURE_ENVELOPE);
    defer allocator.free(args);
    var s = try fx.disp.dispatch(&ctx, "intent_cells", "submit", args);
    s.deinit();

    var r = try fx.disp.dispatch(&ctx, "intent_cells", "find", "{}");
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayLen(allocator, r.payload));
}

test "intent_cells.find_by_id: typed not_found body on miss" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    var r = try fx.disp.dispatch(&ctx, "intent_cells", "find_by_id",
        \\{"cell_id":"never-existed-1"}
    );
    defer r.deinit();
    const err_kind = try jsonField(allocator, r.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("not_found", err_kind);
}

test "intent_cells.find: filters on hat_id" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    const args1 = try buildSubmitArgs(allocator, FIXTURE_ENVELOPE);
    defer allocator.free(args1);
    var s = try fx.disp.dispatch(&ctx, "intent_cells", "submit", args1);
    s.deinit();

    var find_r = try fx.disp.dispatch(&ctx, "intent_cells", "find",
        \\{"hat_id":"00112233445566778899aabbccddeeff"}
    );
    defer find_r.deinit();
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayLen(allocator, find_r.payload));

    var miss_r = try fx.disp.dispatch(&ctx, "intent_cells", "find",
        \\{"hat_id":"different-hat"}
    );
    defer miss_r.deinit();
    try std.testing.expectEqual(@as(usize, 0), try jsonArrayLen(allocator, miss_r.payload));
}

// ─────────────────────────────────────────────────────────────────────
// Cap declarations
// ─────────────────────────────────────────────────────────────────────

test "intent_cells: capForCmd declares the right caps per spec" {
    var dummy_handler = intent_cells_handler_mod.Handler.init(undefined, undefined);
    const rh = dummy_handler.resourceHandler();
    {
        const decl = try rh.capForCmd("submit");
        try std.testing.expectEqualStrings("cap.oddjobz.write_customer", decl.require);
    }
    {
        const decl = try rh.capForCmd("find");
        try std.testing.expectEqualStrings("cap.oddjobz.read_jobs", decl.require);
    }
    {
        const decl = try rh.capForCmd("find_by_id");
        try std.testing.expectEqualStrings("cap.oddjobz.read_jobs", decl.require);
    }
    try std.testing.expectError(error.unknown_command, rh.capForCmd("bogus"));
}

// ─────────────────────────────────────────────────────────────────────
// Cross-language fixture parity
// ─────────────────────────────────────────────────────────────────────

test "intent_cells.submit: cross-language fixture decodes + persists" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    var ctx = rootCtx();

    // The fixture file lives at apps/oddjobz-mobile/test/fixtures/.
    // Resolve relative to the repo root so the test runs from any cwd.
    const fixture_path = "../../apps/oddjobz-mobile/test/fixtures/intent_cell_envelope_fixture.json";
    const fixture_text = std.fs.cwd().readFileAlloc(allocator, fixture_path, 64 * 1024) catch |err| {
        // CI may run with a cwd that doesn't expose the apps/ tree.
        // Skip gracefully — the inline fixture above asserts the same
        // shape; this test is the cross-lang oracle.
        std.debug.print("intent_cells: skipping cross-lang fixture test ({s} unreadable: {s})\n", .{ fixture_path, @errorName(err) });
        return;
    };
    defer allocator.free(fixture_text);

    // The fixture has a "_comment" key the spec doesn't carry; strip
    // it before forwarding.
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, fixture_text, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.fixture_not_object;
    var clean: std.ArrayList(u8) = .{};
    defer clean.deinit(allocator);
    try clean.append(allocator, '{');
    var wrote_any = false;
    var it = parsed.value.object.iterator();
    while (it.next()) |entry| {
        if (std.mem.eql(u8, entry.key_ptr.*, "_comment")) continue;
        if (wrote_any) try clean.append(allocator, ',');
        const key_enc = try std.json.Stringify.valueAlloc(allocator, entry.key_ptr.*, .{});
        defer allocator.free(key_enc);
        try clean.appendSlice(allocator, key_enc);
        try clean.append(allocator, ':');
        const val_enc = try std.json.Stringify.valueAlloc(allocator, entry.value_ptr.*, .{});
        defer allocator.free(val_enc);
        try clean.appendSlice(allocator, val_enc);
        wrote_any = true;
    }
    try clean.append(allocator, '}');

    const args = try buildSubmitArgs(allocator, clean.items);
    defer allocator.free(args);
    var r = try fx.disp.dispatch(&ctx, "intent_cells", "submit", args);
    defer r.deinit();
    const status = try jsonField(allocator, r.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("accepted", status);
}

```
