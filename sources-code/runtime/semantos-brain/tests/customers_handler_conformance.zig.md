---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/customers_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.177595+00:00
---

# runtime/semantos-brain/tests/customers_handler_conformance.zig

```zig
// D-O5.followup-3 — see
// docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3, §8;
// docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5 (helm Customers view).
//
// Conformance suite for `resources/customers_handler.zig`.  Mirrors the
// shape of `jobs_handler_conformance.zig`: dispatcher → ResourceHandler
// → CustomersStore for the three spec'd commands plus the cap-gating +
// name-filter + idempotent-recreate + contents-differ rejection paths
// required by acceptance §6.
//
// What this closes:
//
//   • Both helms (loom-svelte CustomerList.svelte + oddjobz-mobile
//     customers_repository.dart) prefer the JSON-array branch when the
//     REPL response starts with `[`.  This suite asserts the bytes the
//     dispatcher returns satisfy that branch — id / display_name /
//     phone / email / address / created_at all show up as JSON
//     strings (notes is omitted from the list view to keep payloads
//     compact).
//
//   • Idempotent re-create with byte-identical contents: helm-side
//     outbox flushes retry naively; the second call must return
//     `status: "already_exists"` (200, not error) so the offline path
//     doesn't get stuck.
//
//   • Re-create with same id but DIFFERENT contents: returns a typed
//     `customer_id_in_use_with_different_contents` validation error
//     rather than silently shadowing the prior record.  Customer
//     fields are lattice-shaped — a genuine update should go through
//     a future `customers.update` command.
//
//   • Cap-gating: `customers.find` and `customers.find_by_id` require
//     `cap.oddjobz.read_customers`; `customers.create` requires
//     `cap.oddjobz.write_customer`.  Bearer contexts without the cap
//     are rejected with `capability_denied` — root-scope contexts
//     bypass per the dispatcher contract.

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const customers_store_fs = @import("customers_store_fs");
const customers_handler_mod = @import("customers_handler");
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
// audit_log + the handler's pointer to CustomersStore are address-stable.
// ─────────────────────────────────────────────────────────────────────

fn pinnedClock() i64 {
    return 1_700_000_000;
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: @import("cell_store").CellStore,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    store: customers_store_fs.CustomersStore,
    handler: customers_handler_mod.Handler,
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
        self.store = try customers_store_fs.CustomersStore.init(allocator, &self.cs, pinnedClock);
        self.handler = customers_handler_mod.Handler.init(allocator, &self.store);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.store.deinit();
        self.audit.close();
        self.lmdb_env.close();
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
// create → find → find_by_id round-trip (root scope)
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-3 customers: create → find returns the customer (JSON shape)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();

    var create_result = try fx.disp.dispatch(&ctx, "customers", "create",
        \\{"id":"cust-001","display_name":"Acme Corp","phone":"+61 400 111 222","email":"ops@acme.example","address":"1 Industrial Way","notes":"Regular plumbing customer","created_at":"2026-05-02T10:00:00Z"}
    );
    defer create_result.deinit();

    const status = try jsonString(allocator, create_result.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("created", status);
    const id_back = try jsonString(allocator, create_result.payload, "id");
    defer allocator.free(id_back);
    try std.testing.expectEqualStrings("cust-001", id_back);

    // find — empty filter returns all customers.
    var find_result = try fx.disp.dispatch(&ctx, "customers", "find", "{}");
    defer find_result.deinit();
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayLen(allocator, find_result.payload));
    // Assert the JSON-array list-view shape (notes intentionally
    // omitted from list payload — surfaced only via find_by_id).
    try std.testing.expect(std.mem.indexOf(u8, find_result.payload, "\"id\":\"cust-001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, find_result.payload, "\"display_name\":\"Acme Corp\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, find_result.payload, "\"phone\":\"+61 400 111 222\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, find_result.payload, "\"email\":\"ops@acme.example\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, find_result.payload, "\"address\":\"1 Industrial Way\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, find_result.payload, "\"created_at\":\"2026-05-02T10:00:00Z\"") != null);
    // List view OMITS notes — assert that explicitly.
    try std.testing.expect(std.mem.indexOf(u8, find_result.payload, "\"notes\":") == null);

    // find_by_id — single customer back, INCLUDES notes.
    var byid_result = try fx.disp.dispatch(&ctx, "customers", "find_by_id",
        \\{"id":"cust-001"}
    );
    defer byid_result.deinit();
    const dn_back = try jsonString(allocator, byid_result.payload, "display_name");
    defer allocator.free(dn_back);
    try std.testing.expectEqualStrings("Acme Corp", dn_back);
    const notes_back = try jsonString(allocator, byid_result.payload, "notes");
    defer allocator.free(notes_back);
    try std.testing.expectEqualStrings("Regular plumbing customer", notes_back);
}

// ─────────────────────────────────────────────────────────────────────
// name filter
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-3 customers: find with name filter narrows result set (case-insensitive)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var c1 = try fx.disp.dispatch(&ctx, "customers", "create",
        \\{"id":"cust-001","display_name":"Acme Corp","created_at":"2026-01-01T00:00:00Z"}
    );
    c1.deinit();
    var c2 = try fx.disp.dispatch(&ctx, "customers", "create",
        \\{"id":"cust-002","display_name":"Globex","created_at":"2026-01-02T00:00:00Z"}
    );
    c2.deinit();
    var c3 = try fx.disp.dispatch(&ctx, "customers", "create",
        \\{"id":"cust-003","display_name":"Acme Apartments","created_at":"2026-01-03T00:00:00Z"}
    );
    c3.deinit();

    // Lowercase "acme" matches both Acme entries.
    var acmes = try fx.disp.dispatch(&ctx, "customers", "find",
        \\{"name":"acme"}
    );
    defer acmes.deinit();
    try std.testing.expectEqual(@as(usize, 2), try jsonArrayLen(allocator, acmes.payload));

    // Uppercase "GLOBEX" matches via case-fold.
    var globex = try fx.disp.dispatch(&ctx, "customers", "find",
        \\{"name":"GLOBEX"}
    );
    defer globex.deinit();
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayLen(allocator, globex.payload));
    try std.testing.expect(std.mem.indexOf(u8, globex.payload, "\"display_name\":\"Globex\"") != null);

    // No match — empty array, no error.
    var none = try fx.disp.dispatch(&ctx, "customers", "find",
        \\{"name":"nonexistent"}
    );
    defer none.deinit();
    try std.testing.expectEqual(@as(usize, 0), try jsonArrayLen(allocator, none.payload));
}

// ─────────────────────────────────────────────────────────────────────
// idempotent re-create (acceptance §3) — identical contents
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-3 customers: re-create with same id + identical contents returns already_exists" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var first = try fx.disp.dispatch(&ctx, "customers", "create",
        \\{"id":"cust-x","display_name":"X","created_at":"2026-01-01T00:00:00Z"}
    );
    defer first.deinit();
    const status1 = try jsonString(allocator, first.payload, "status");
    defer allocator.free(status1);
    try std.testing.expectEqualStrings("created", status1);

    var second = try fx.disp.dispatch(&ctx, "customers", "create",
        \\{"id":"cust-x","display_name":"X","created_at":"2026-01-01T00:00:00Z"}
    );
    defer second.deinit();
    const status2 = try jsonString(allocator, second.payload, "status");
    defer allocator.free(status2);
    try std.testing.expectEqualStrings("already_exists", status2);
}

// ─────────────────────────────────────────────────────────────────────
// re-create with same id but DIFFERENT contents → rejected
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-3 customers: re-create with same id but different contents is rejected" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var first = try fx.disp.dispatch(&ctx, "customers", "create",
        \\{"id":"cust-y","display_name":"Original","phone":"","email":"","address":"","notes":"","created_at":"2026-01-01T00:00:00Z"}
    );
    first.deinit();

    // Same id but display_name differs → typed validation error.
    try std.testing.expectError(
        customers_handler_mod.HandlerError.customer_id_in_use_with_different_contents,
        fx.disp.dispatch(&ctx, "customers", "create",
            \\{"id":"cust-y","display_name":"Mutated","phone":"","email":"","address":"","notes":"","created_at":"2026-01-01T00:00:00Z"}
        ),
    );
}

// ─────────────────────────────────────────────────────────────────────
// validation paths
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-3 customers: create with empty display_name returns invalid_display_name" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        customers_handler_mod.HandlerError.invalid_display_name,
        fx.disp.dispatch(&ctx, "customers", "create",
            \\{"id":"cust-bad","display_name":""}
        ),
    );
}

test "D-O5.followup-3 customers: server-stamps id when caller passes empty" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var result = try fx.disp.dispatch(&ctx, "customers", "create",
        \\{"display_name":"Stamped"}
    );
    defer result.deinit();
    const id_back = try jsonString(allocator, result.payload, "id");
    defer allocator.free(id_back);
    // 16 random bytes hex-encoded = 32 chars.
    try std.testing.expectEqual(@as(usize, 32), id_back.len);
    const status = try jsonString(allocator, result.payload, "status");
    defer allocator.free(status);
    try std.testing.expectEqualStrings("created", status);
}

test "D-O5.followup-3 customers: find_by_id on missing returns typed not_found body" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var result = try fx.disp.dispatch(&ctx, "customers", "find_by_id",
        \\{"id":"cust-does-not-exist"}
    );
    defer result.deinit();
    const err_kind = try jsonString(allocator, result.payload, "error");
    defer allocator.free(err_kind);
    try std.testing.expectEqualStrings("not_found", err_kind);
}

// ─────────────────────────────────────────────────────────────────────
// cap-gating
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-3 customers: bearer without cap.oddjobz.read_customers is denied for find" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    // Empty cap set on a bearer-auth'd context.
    const ctx = bearerCtxWithCaps(&.{});
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&ctx, "customers", "find", "{}"));
}

test "D-O5.followup-3 customers: bearer with cap.oddjobz.read_customers can find but not create" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // First seed via root so there's something to find.
    var root = rootCtx();
    var seeded = try fx.disp.dispatch(&root, "customers", "create",
        \\{"id":"cust-r","display_name":"R","created_at":"2026-01-01T00:00:00Z"}
    );
    seeded.deinit();

    const reader = bearerCtxWithCaps(&.{"cap.oddjobz.read_customers"});
    var find_ok = try fx.disp.dispatch(&reader, "customers", "find", "{}");
    defer find_ok.deinit();
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayLen(allocator, find_ok.payload));

    // Reader cannot create — that needs cap.oddjobz.write_customer.
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&reader, "customers", "create",
        \\{"id":"cust-r2","display_name":"R2"}
    ));
}

test "D-O5.followup-3 customers: bearer with cap.oddjobz.write_customer can create but not read" {
    var fx = try Fixture.init(std.testing.allocator);
    defer fx.deinit();

    const writer = bearerCtxWithCaps(&.{"cap.oddjobz.write_customer"});
    var ok = try fx.disp.dispatch(&writer, "customers", "create",
        \\{"id":"cust-w","display_name":"W"}
    );
    defer ok.deinit();

    // write_customer doesn't imply read_customers — find is denied.
    try std.testing.expectError(error.capability_denied, fx.disp.dispatch(&writer, "customers", "find", "{}"));
}

// ─────────────────────────────────────────────────────────────────────
// audit-pair invariant — both phases logged for every dispatch
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-3 customers: dispatch emits paired phase=start / phase=end audit lines" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "customers", "create",
        \\{"id":"cust-audit","display_name":"AuditCo"}
    );
    r.deinit();
    var find_r = try fx.disp.dispatch(&ctx, "customers", "find", "{}");
    find_r.deinit();

    // Read the audit log + count phase=start / phase=end pairs.  The
    // dispatcher's recordAudit emits both with `module="dispatcher"`
    // and `op="<resource>.<cmd>"`; for `customers.*` we expect 2
    // starts + 2 ends across our two dispatches.
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
        if (std.mem.indexOf(u8, line, "\"op\":\"customers.") == null) continue;
        if (std.mem.indexOf(u8, line, "phase=start") != null) starts += 1;
        if (std.mem.indexOf(u8, line, "phase=end") != null) ends += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), starts);
    try std.testing.expectEqual(@as(usize, 2), ends);
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-4 followup-emitters — broker-emit assertion.  A
// successful customers.create publishes "customer.created" to the
// broker; both helms (mobile + svelte) consume the same fan-out as
// `helm.event` JSON-RPC notifications over WSS.  Mirrors the shape of
// the jobs.transition emit-test in jobs_handler_conformance.zig.
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

/// Variant fixture that wires a broker into the handler.  Mirrors the
/// main Fixture but uses Handler.initWithBroker so the emit path is
/// exercised.
const BrokerFixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: @import("cell_store").CellStore,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    store: customers_store_fs.CustomersStore,
    handler: customers_handler_mod.Handler,
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
        self.store = try customers_store_fs.CustomersStore.init(allocator, &self.cs, pinnedClock);
        self.handler = customers_handler_mod.Handler.initWithBroker(
            allocator,
            &self.store,
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
        self.store.deinit();
        self.audit.close();
        self.lmdb_env.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.destroy(self);
    }
};

test "D-O5.followup-4 customers.create publishes customer.created to broker" {
    const allocator = std.testing.allocator;
    var fx = try BrokerFixture.init(allocator);
    defer fx.deinit();

    var sink = PublishSink.init(allocator);
    defer sink.deinit();
    _ = try fx.broker.subscribe(.{ .state = &sink, .callback = PublishSink.callback });

    var ctx = rootCtx();
    var r = try fx.disp.dispatch(&ctx, "customers", "create",
        \\{"id":"cust-pub","display_name":"PubCo","created_at":"2026-05-02T10:00:00Z"}
    );
    defer r.deinit();

    // Exactly one event published — the create we just drove.
    try std.testing.expectEqual(@as(usize, 1), sink.types.items.len);
    try std.testing.expectEqualStrings("customer.created", sink.types.items[0]);

    // Payload carries the canonical {id, display_name, created_at} shape.
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"id\":\"cust-pub\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"display_name\":\"PubCo\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sink.payloads.items[0], "\"created_at\":\"2026-05-02T10:00:00Z\"") != null);

    // Re-create with byte-identical contents → already_exists, NOT a
    // second publish (idempotent flush retry must not fire decorative
    // events twice).
    var r2 = try fx.disp.dispatch(&ctx, "customers", "create",
        \\{"id":"cust-pub","display_name":"PubCo","created_at":"2026-05-02T10:00:00Z"}
    );
    defer r2.deinit();
    try std.testing.expectEqual(@as(usize, 1), sink.types.items.len);
}

```
