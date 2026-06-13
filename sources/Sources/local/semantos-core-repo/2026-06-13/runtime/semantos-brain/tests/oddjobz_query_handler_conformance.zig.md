---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/oddjobz_query_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.184889+00:00
---

# runtime/semantos-brain/tests/oddjobz_query_handler_conformance.zig

```zig
// D-DOG.1.0c Phase 2B.3 — oddjobz_query_handler conformance suite.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 2
//            sub-deliverable D.1;
//            runtime/semantos-brain/src/oddjobz_query_handler.zig (the handler);
//            runtime/semantos-brain/src/oddjobz_ratify_handler.zig (mints fixture
//              cells via the same pattern Phase 3 will see in
//              production);
//            runtime/semantos-brain/src/{sites,customers,jobs,attachments}_store_fs
//              .zig (the four typed view-stores this handler reads).
//
// What this closes:
//
//   • Each query verb returns the right wire shape on a fixture-
//     populated store (ratify-handler-minted cells).
//   • Empty-store cases return empty arrays / nulls cleanly.
//   • `find_jobs_at_site` excludes v1 rows (no siteRef).
//   • `find_attachments_for_job` excludes visit-side v1 rows (they
//     have no jobRef).
//   • Single-record getters return null for unknown cellIDs.
//   • `invalid_cell_ref` / `invalid_params` surface as typed
//     QueryError values the WSS layer maps to JSON-RPC -32602.

const std = @import("std");
const sites_store_fs = @import("sites_store_fs");
const customers_store_fs = @import("customers_store_fs");
const jobs_store_fs = @import("jobs_store_fs");
const attachments_store_fs = @import("attachments_store_fs");
const oddjobz_ratify = @import("oddjobz_ratify_handler");
const oddjobz_query = @import("oddjobz_query_handler");
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

fn pinnedClock() i64 {
    return 1_700_000_000;
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: cell_store_mod.CellStore,
    sites: sites_store_fs.SitesStore,
    customers: customers_store_fs.CustomersStore,
    jobs: jobs_store_fs.JobsStore,
    attachments: attachments_store_fs.AttachmentsStore,
    ratify: oddjobz_ratify.Handler,
    query: oddjobz_query.Handler,

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        self.allocator = allocator;
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        self.tmp_dir = tmp;
        self.data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(self.data_dir);

        // Initialize LMDB env and cell store in-place so pointers remain stable.
        self.lmdb_env = try openTestEnv(real);
        errdefer self.lmdb_env.close();
        self.cs_impl = try lmdb_cell_store.LmdbCellStore.init(&self.lmdb_env, allocator);
        self.cs = self.cs_impl.store();

        self.sites = try sites_store_fs.SitesStore.init(allocator, &self.cs, pinnedClock);
        self.customers = try customers_store_fs.CustomersStore.init(allocator, &self.cs, pinnedClock);
        self.jobs = try jobs_store_fs.JobsStore.init(allocator, &self.cs, pinnedClock);
        self.attachments = try attachments_store_fs.AttachmentsStore.init(allocator, &self.cs, pinnedClock);

        const ratify_stores: oddjobz_ratify.RatifyStores = .{
            .sites = &self.sites,
            .customers = &self.customers,
            .jobs = &self.jobs,
            .attachments = &self.attachments,
        };
        self.ratify = try oddjobz_ratify.Handler.init(allocator, ratify_stores, self.data_dir, pinnedClock);
        self.query = oddjobz_query.Handler.init(.{
            .sites = &self.sites,
            .customers = &self.customers,
            .jobs = &self.jobs,
            .attachments = &self.attachments,
        });
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.ratify.deinit();
        self.attachments.deinit();
        self.jobs.deinit();
        self.customers.deinit();
        self.sites.deinit();
        self.lmdb_env.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }
};

// ─── helpers ──────────────────────────────────────────────────────

const PayloadHintExtras = struct {
    primary_contact_name: ?[]const u8 = null,
    primary_contact_role: ?[]const u8 = null,
    primary_contact_phone: ?[]const u8 = null,
    primary_contact_email: ?[]const u8 = null,
    property_address: ?[]const u8 = null,
    property_key: ?[]const u8 = null,
    work_order_number: ?[]const u8 = null,
    issuance_date: ?[]const u8 = null,
    due_date: ?[]const u8 = null,
    has_photos: bool = false,
    photo_count: ?u32 = null,
    source_attachment_path: ?[]const u8 = null,
};

fn paramsJson(
    allocator: std.mem.Allocator,
    proposal_id: []const u8,
    action: []const u8,
    customer_name: []const u8,
    extras: PayloadHintExtras,
) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"proposal_id\":");
    try writeJsonStr(allocator, &buf, proposal_id);
    try buf.appendSlice(allocator,
        \\,"sir_program":{"primaryNodeId":"$s0","programGovernance":{},"nodes":[{"id":"$s0","category":{"lexicon":"jural","category":"declaration"},"taxonomy":{},"identity":{},"governance":{},"action":
    );
    try writeJsonStr(allocator, &buf, action);
    try buf.appendSlice(allocator,
        \\,"constraint":{"kind":"literal","value":"true"},"provenance":{"source":"inferred","expressedAt":"2026-05-04T00:00:00Z","trustAtExpression":"cosmetic"}}]},"payload_hint":{"customer_name":
    );
    try writeJsonStr(allocator, &buf, customer_name);
    try buf.appendSlice(allocator, ",\"summary\":\"smoke\",\"reference_number\":\"\",\"source_provider_id\":\"stub\"");

    if (extras.primary_contact_name) |n| {
        try buf.appendSlice(allocator, ",\"primaryContact\":{\"name\":");
        try writeJsonStr(allocator, &buf, n);
        try buf.appendSlice(allocator, ",\"role\":");
        try writeJsonStr(allocator, &buf, extras.primary_contact_role orelse "agent");
        if (extras.primary_contact_phone) |p| {
            try buf.appendSlice(allocator, ",\"phone\":");
            try writeJsonStr(allocator, &buf, p);
        }
        if (extras.primary_contact_email) |e| {
            try buf.appendSlice(allocator, ",\"email\":");
            try writeJsonStr(allocator, &buf, e);
        }
        try buf.appendSlice(allocator, "}");
    }
    if (extras.property_address) |a| {
        try buf.appendSlice(allocator, ",\"propertyAddress\":");
        try writeJsonStr(allocator, &buf, a);
    }
    if (extras.property_key) |k| {
        try buf.appendSlice(allocator, ",\"propertyKey\":");
        try writeJsonStr(allocator, &buf, k);
    }
    if (extras.work_order_number) |w| {
        try buf.appendSlice(allocator, ",\"workOrderNumber\":");
        try writeJsonStr(allocator, &buf, w);
    }
    if (extras.issuance_date) |d| {
        try buf.appendSlice(allocator, ",\"issuanceDate\":");
        try writeJsonStr(allocator, &buf, d);
    }
    if (extras.due_date) |d| {
        try buf.appendSlice(allocator, ",\"dueDate\":");
        try writeJsonStr(allocator, &buf, d);
    }
    if (extras.has_photos) {
        try buf.appendSlice(allocator, ",\"hasPhotos\":true");
    }
    if (extras.photo_count) |c| {
        try buf.print(allocator, ",\"photoCount\":{d}", .{c});
    }
    if (extras.source_attachment_path) |p| {
        try buf.appendSlice(allocator, ",\"sourceAttachmentPath\":");
        try writeJsonStr(allocator, &buf, p);
    }
    try buf.appendSlice(allocator, "}}");
    return buf.toOwnedSlice(allocator);
}

fn writeJsonStr(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

/// Build a minimal `{"<field>":"<hex32>"}` params blob for the cell-
/// ref query verbs.
fn refParams(allocator: std.mem.Allocator, field: []const u8, hex: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"{s}\":\"{s}\"}}", .{ field, hex });
}

/// Parse a JSON body and assert the supplied object key resolves to an
/// array of the expected length.  Returns the parsed envelope (caller
/// `.deinit()`s).
fn arrayLenAt(
    allocator: std.mem.Allocator,
    body: []const u8,
    key: []const u8,
) !struct { parsed: std.json.Parsed(std.json.Value), len: usize } {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    errdefer parsed.deinit();
    const obj = parsed.value.object;
    const arr = obj.get(key) orelse return error.MissingArrayKey;
    if (arr != .array) return error.NotAnArray;
    return .{ .parsed = parsed, .len = arr.array.items.len };
}

// ─── tests ────────────────────────────────────────────────────────

test "oddjobz_query_handler: list_sites + list_customers on empty store return empty arrays" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const sites_body = try fx.query.listSites(allocator);
    defer allocator.free(sites_body);
    const sites_check = try arrayLenAt(allocator, sites_body, "sites");
    defer sites_check.parsed.deinit();
    try std.testing.expectEqual(@as(usize, 0), sites_check.len);

    const customers_body = try fx.query.listCustomers(allocator);
    defer allocator.free(customers_body);
    const customers_check = try arrayLenAt(allocator, customers_body, "customers");
    defer customers_check.parsed.deinit();
    try std.testing.expectEqual(@as(usize, 0), customers_check.len);
}

test "oddjobz_query_handler: list verbs return the ratify-handler-minted graph" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // Ratify two proposals → two sites, two distinct customers,
    // two jobs (two attachments because both carry sourceAttachmentPath).
    const params_a = try paramsJson(allocator, "prop-list-a", "create_lead", "Site A Tenant", .{
        .primary_contact_name = "Alice Tenant",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000201",
        .property_address = "10 List Lane, Brisbane QLD 4000",
        .property_key = "key #10",
        .source_attachment_path = "blob://gmail/list-a",
    });
    defer allocator.free(params_a);
    const params_b = try paramsJson(allocator, "prop-list-b", "create_work_order", "Site B Owner", .{
        .primary_contact_name = "Bob Owner",
        .primary_contact_role = "owner",
        .primary_contact_phone = "+61400000202",
        .property_address = "20 List Lane, Brisbane QLD 4000",
        .property_key = "front",
        .work_order_number = "WO-LIST-B",
        .source_attachment_path = "blob://propertyme/list-b",
    });
    defer allocator.free(params_b);

    var ra = try fx.ratify.handleRatify(allocator, params_a);
    defer ra.deinit();
    var rb = try fx.ratify.handleRatify(allocator, params_b);
    defer rb.deinit();
    try std.testing.expectEqual(@as(usize, 2), fx.sites.count());
    try std.testing.expectEqual(@as(usize, 2), fx.customers.count());

    // list_sites returns both.
    const sites_body = try fx.query.listSites(allocator);
    defer allocator.free(sites_body);
    const sites_check = try arrayLenAt(allocator, sites_body, "sites");
    defer sites_check.parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), sites_check.len);

    // list_customers returns both.
    const customers_body = try fx.query.listCustomers(allocator);
    defer allocator.free(customers_body);
    const customers_check = try arrayLenAt(allocator, customers_body, "customers");
    defer customers_check.parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), customers_check.len);
}

test "oddjobz_query_handler: find_jobs_at_site returns only v2 rows for the requested site" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // Two proposals at the SAME address (two distinct jobs, one
    // shared site under the lookup-or-mint dedupe), then a third at
    // a different address (distinct site).
    const params_a = try paramsJson(allocator, "prop-fs-a", "create_lead", "Tenant A", .{
        .primary_contact_name = "Alice",
        .primary_contact_role = "tenant",
        .property_address = "1 Shared St",
    });
    defer allocator.free(params_a);
    const params_b = try paramsJson(allocator, "prop-fs-b", "create_lead", "Tenant B", .{
        .primary_contact_name = "Bob",
        .primary_contact_role = "tenant",
        .property_address = "1 Shared St",
    });
    defer allocator.free(params_b);
    const params_c = try paramsJson(allocator, "prop-fs-c", "create_lead", "Tenant C", .{
        .primary_contact_name = "Carol",
        .primary_contact_role = "tenant",
        .property_address = "99 Other Pl",
    });
    defer allocator.free(params_c);

    var ra = try fx.ratify.handleRatify(allocator, params_a);
    defer ra.deinit();
    var rb = try fx.ratify.handleRatify(allocator, params_b);
    defer rb.deinit();
    var rc = try fx.ratify.handleRatify(allocator, params_c);
    defer rc.deinit();

    // Pre-seed a v1 job that should NOT show up in find_jobs_at_site
    // results (v1 rows lack siteRef so the store filter excludes them).
    _ = try fx.jobs.append(.{
        .id = "v1-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa00",
        .customer_name = "Legacy Job",
        .state = "lead",
        .scheduled_at = "",
        .created_at = "1970-01-01T00:00:00Z",
    });

    // Look up the shared site by ratify result; query_handler's
    // find_jobs_at_site returns 2 jobs.
    const ref = try refParams(allocator, "siteRef", ra.site_cell_id.?);
    defer allocator.free(ref);
    const jobs_body = try fx.query.findJobsAtSite(allocator, ref);
    defer allocator.free(jobs_body);
    const jobs_check = try arrayLenAt(allocator, jobs_body, "jobs");
    defer jobs_check.parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), jobs_check.len);

    // Each row must carry a v2 cellId (non-null).
    for (jobs_check.parsed.value.object.get("jobs").?.array.items) |job| {
        try std.testing.expect(job.object.get("cellId").? == .string);
        try std.testing.expectEqual(@as(usize, 64), job.object.get("cellId").?.string.len);
        try std.testing.expectEqual(@as(i64, 2), job.object.get("version").?.integer);
    }
}

test "oddjobz_query_handler: find_jobs_for_customer returns only the linked rows" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // Two ratifies with the same primary phone (→ shared customer
    // cell via dedupe) + a third unrelated.
    const params_a = try paramsJson(allocator, "prop-fc-a", "create_lead", "X", .{
        .primary_contact_name = "Carol Shared",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000301",
        .property_address = "1 Carol St",
    });
    defer allocator.free(params_a);
    const params_b = try paramsJson(allocator, "prop-fc-b", "create_lead", "Y", .{
        .primary_contact_name = "Carol Shared (alt)",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000301",
        .property_address = "2 Carol St",
    });
    defer allocator.free(params_b);
    const params_c = try paramsJson(allocator, "prop-fc-c", "create_lead", "Z", .{
        .primary_contact_name = "Other Person",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000302",
        .property_address = "3 Other St",
    });
    defer allocator.free(params_c);

    var ra = try fx.ratify.handleRatify(allocator, params_a);
    defer ra.deinit();
    var rb = try fx.ratify.handleRatify(allocator, params_b);
    defer rb.deinit();
    var rc = try fx.ratify.handleRatify(allocator, params_c);
    defer rc.deinit();
    try std.testing.expectEqual(@as(usize, 2), fx.customers.count());
    try std.testing.expectEqual(@as(usize, 3), fx.jobs.count());

    const ref = try refParams(allocator, "customerRef", ra.customer_cell_ids[0]);
    defer allocator.free(ref);
    const jobs_body = try fx.query.findJobsForCustomer(allocator, ref);
    defer allocator.free(jobs_body);
    const jobs_check = try arrayLenAt(allocator, jobs_body, "jobs");
    defer jobs_check.parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), jobs_check.len);
}

test "oddjobz_query_handler: find_attachments_for_job excludes visit-side v1 rows" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // Ratify with a sourceAttachmentPath → mints a v2 PDF-source
    // attachment.
    const params = try paramsJson(allocator, "prop-att-1", "create_lead", "PDF Customer", .{
        .primary_contact_name = "Pdf Tenant",
        .primary_contact_role = "tenant",
        .property_address = "1 PDF Street",
        .source_attachment_path = "blob://gmail/pdf-1",
    });
    defer allocator.free(params);

    var r = try fx.ratify.handleRatify(allocator, params);
    defer r.deinit();
    try std.testing.expect(r.job_cell_id != null);
    try std.testing.expectEqual(@as(usize, 1), r.attachment_cell_ids.len);

    // Pre-seed a v1 visit-side attachment (no jobRef).  Must be
    // EXCLUDED from find_attachments_for_job's response — the store
    // filter rejects rows where jobRef == null.
    _ = try fx.attachments.append(.{
        .id = "v1-att-id-fffffffffffffffffffffffffffff",
        .visit_id = "visit-id-aaaaaaaaaaaaaaaaaaaaaaaaaa1",
        .kind = "photo",
        .content_hash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        .content_size = 100,
        .mime_type = "image/jpeg",
        .captured_at = "2026-05-04T00:00:00Z",
        .captured_by_cert_id = "deadbeefdeadbeefdeadbeefdeadbeef",
        .caption = "",
        .created_at = "2026-05-04T00:00:00Z",
    });

    const ref = try refParams(allocator, "jobRef", r.job_cell_id.?);
    defer allocator.free(ref);
    const body = try fx.query.findAttachmentsForJob(allocator, ref);
    defer allocator.free(body);
    const check = try arrayLenAt(allocator, body, "attachments");
    defer check.parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), check.len);

    // The single returned row is the v2 PDF row — sourceBlobKey is
    // populated, hasPhotos shape is correct.
    const att = check.parsed.value.object.get("attachments").?.array.items[0];
    try std.testing.expect(att.object.get("sourceBlobKey").? == .string);
    try std.testing.expectEqualStrings("blob://gmail/pdf-1", att.object.get("sourceBlobKey").?.string);
    try std.testing.expect(att.object.get("jobRef").? == .string);
    try std.testing.expectEqual(@as(usize, 64), att.object.get("jobRef").?.string.len);
}

test "oddjobz_query_handler: single-record getters return the row on hit, null on miss" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const params = try paramsJson(allocator, "prop-get-1", "create_quote_request", "GetCust", .{
        .primary_contact_name = "Get Tenant",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000401",
        .property_address = "1 Get St",
        .source_attachment_path = "blob://gmail/get-1",
    });
    defer allocator.free(params);

    var r = try fx.ratify.handleRatify(allocator, params);
    defer r.deinit();

    // Hits — site, customer, job, attachment all present.
    {
        const ref = try refParams(allocator, "siteRef", r.site_cell_id.?);
        defer allocator.free(ref);
        const body = try fx.query.getSite(allocator, ref);
        defer allocator.free(body);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value.object.get("site").? == .object);
    }
    {
        const ref = try refParams(allocator, "customerRef", r.customer_cell_ids[0]);
        defer allocator.free(ref);
        const body = try fx.query.getCustomer(allocator, ref);
        defer allocator.free(body);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value.object.get("customer").? == .object);
    }
    {
        const ref = try refParams(allocator, "jobRef", r.job_cell_id.?);
        defer allocator.free(ref);
        const body = try fx.query.getJob(allocator, ref);
        defer allocator.free(body);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value.object.get("job").? == .object);
        try std.testing.expectEqual(@as(i64, 2), parsed.value.object.get("job").?.object.get("version").?.integer);
    }
    {
        const ref = try refParams(allocator, "attachmentRef", r.attachment_cell_ids[0]);
        defer allocator.free(ref);
        const body = try fx.query.getAttachment(allocator, ref);
        defer allocator.free(body);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value.object.get("attachment").? == .object);
    }

    // Miss — unknown cellId; verb returns null in the response slot.
    const unknown_hex = "ff" ** 32;
    {
        const ref = try refParams(allocator, "siteRef", unknown_hex);
        defer allocator.free(ref);
        const body = try fx.query.getSite(allocator, ref);
        defer allocator.free(body);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value.object.get("site").? == .null);
    }
    {
        const ref = try refParams(allocator, "jobRef", unknown_hex);
        defer allocator.free(ref);
        const body = try fx.query.getJob(allocator, ref);
        defer allocator.free(body);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value.object.get("job").? == .null);
    }
    {
        const ref = try refParams(allocator, "customerRef", unknown_hex);
        defer allocator.free(ref);
        const body = try fx.query.getCustomer(allocator, ref);
        defer allocator.free(body);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value.object.get("customer").? == .null);
    }
    {
        const ref = try refParams(allocator, "attachmentRef", unknown_hex);
        defer allocator.free(ref);
        const body = try fx.query.getAttachment(allocator, ref);
        defer allocator.free(body);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value.object.get("attachment").? == .null);
    }
}

test "oddjobz_query_handler: invalid params surface as typed QueryError values" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // Missing field.
    try std.testing.expectError(
        oddjobz_query.QueryError.invalid_params,
        fx.query.findJobsAtSite(allocator, "{}"),
    );
    // Wrong-length hex.
    try std.testing.expectError(
        oddjobz_query.QueryError.invalid_cell_ref,
        fx.query.findJobsAtSite(allocator, "{\"siteRef\":\"deadbeef\"}"),
    );
    // Right length but non-hex chars.
    const bad_chars = "{\"siteRef\":\"" ++ "zz" ** 32 ++ "\"}";
    try std.testing.expectError(
        oddjobz_query.QueryError.invalid_cell_ref,
        fx.query.findJobsAtSite(allocator, bad_chars),
    );
    // Non-object root.
    try std.testing.expectError(
        oddjobz_query.QueryError.invalid_params,
        fx.query.findJobsAtSite(allocator, "[]"),
    );
}

test "oddjobz_query_handler: store_unavailable when a required pointer is absent" {
    const allocator = std.testing.allocator;
    // Hand-build a query handler with a missing jobs store.  The
    // find_jobs_at_site verb must return store_unavailable.
    const handler = oddjobz_query.Handler.init(.{
        .sites = null,
        .customers = null,
        .jobs = null,
        .attachments = null,
    });
    try std.testing.expectError(
        oddjobz_query.QueryError.store_unavailable,
        handler.listSites(allocator),
    );
    try std.testing.expectError(
        oddjobz_query.QueryError.store_unavailable,
        handler.listCustomers(allocator),
    );
    try std.testing.expectError(
        oddjobz_query.QueryError.store_unavailable,
        handler.findJobsAtSite(allocator, "{\"siteRef\":\"" ++ "00" ** 32 ++ "\"}"),
    );
    try std.testing.expectError(
        oddjobz_query.QueryError.store_unavailable,
        handler.findAttachmentsForJob(allocator, "{\"jobRef\":\"" ++ "00" ** 32 ++ "\"}"),
    );
}

test "oddjobz_query_handler: list_customers includes both v1 and v2 rows" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // Pre-seed a v1 customer row.
    const v1_outcome = try fx.customers.append(.{
        .id = "v1-cust-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1",
        .display_name = "Legacy Customer",
        .phone = "0400999000",
        .email = "",
        .address = "",
        .notes = "",
        .created_at = "1970-01-01T00:00:00Z",
    });
    try std.testing.expectEqual(customers_store_fs.CustomersStore.AppendOutcome.created, v1_outcome);

    // Then ratify a proposal → mints one v2 customer.
    const params = try paramsJson(allocator, "prop-mix-1", "create_lead", "Mixed", .{
        .primary_contact_name = "v2 Tenant",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000501",
        .property_address = "1 Mixed Lane",
    });
    defer allocator.free(params);
    var r = try fx.ratify.handleRatify(allocator, params);
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 2), fx.customers.count());

    const body = try fx.query.listCustomers(allocator);
    defer allocator.free(body);
    const check = try arrayLenAt(allocator, body, "customers");
    defer check.parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), check.len);

    // One row has cellId == null (v1), one has cellId == string (v2).
    var seen_v1 = false;
    var seen_v2 = false;
    for (check.parsed.value.object.get("customers").?.array.items) |row| {
        const cid = row.object.get("cellId").?;
        if (cid == .null) seen_v1 = true;
        if (cid == .string) seen_v2 = true;
    }
    try std.testing.expect(seen_v1);
    try std.testing.expect(seen_v2);
}

```
