---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/oddjobz_ratify_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.178200+00:00
---

# runtime/semantos-brain/tests/oddjobz_ratify_handler_conformance.zig

```zig
// D-DOG.1.0c Phase 2A.4 — oddjobz_ratify_handler conformance suite.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 row C.1;
//            runtime/semantos-brain/src/oddjobz_ratify_handler.zig (the handler);
//            runtime/semantos-brain/src/{sites,customers,jobs,attachments}_store_fs
//              .zig (the four typed view-stores this handler writes to).
//
// What this closes:
//
//   • Phase 2A.4 rewrites the handler to walk an SIRProgram +
//     payload_hint into a GRAPH of cells (site + customers + job +
//     attachments) instead of a single flat job row.  This suite
//     asserts the new return shape (RatifyResult.{site_cell_id,
//     customer_cell_ids, job_cell_id, attachment_cell_ids}) and that
//     all four view-stores get the right rows after each handler call.
//
//   • Idempotency: a repeat ratify for the same proposal_id returns
//     the SAME graph cellIDs without re-walking (the per-proposal
//     idempotency cache).
//
//   • Site dedupe: two SIR programs with the same property address
//     produce the SAME `siteRef` (the lookup-or-mint dedupe gate keyed
//     on `<normalisedAddress>|<keyNumber>`).
//
//   • Customer dedupe: two SIR programs with the same primary tenant
//     phone produce the SAME `customerRefs[0].cellId` (the
//     CustomerDedupeKey.phone gate).
//
//   • Idempotency survives a handler restart (replay loads the log).
//
//   • Invalid params surface as typed RatifyError values the WSS
//     layer maps to JSON-RPC -32000-range errors.

const std = @import("std");
const sites_store_fs = @import("sites_store_fs");
const customers_store_fs = @import("customers_store_fs");
const jobs_store_fs = @import("jobs_store_fs");
const attachments_store_fs = @import("attachments_store_fs");
const oddjobz_ratify = @import("oddjobz_ratify_handler");
// D-DOG.1.0c Phase 4 row B.2 — assert minted cells carry non-null
// signedBy + a verifiable signature when a HatBkds signer is wired
// into the RatifyStores bag.
const hat_bkds = @import("hat_bkds");
const hat_bkds_verifier = @import("hat_bkds_verifier");
const oddjobz_scope = @import("oddjobz_scope"); // C4 — oddjobz cells signed under their own scope

// Verify an oddjobz-signed cell under the cartridge's BKDS scope (not the
// substrate default). C4: oddjobz mint + resign-pending sign under
// oddjobz_scope.CELL_SIGN_PROTOCOL_ID.
fn verifyOddjobzCell(root_priv: [32]u8, payload: []const u8, signed_by: [33]u8, signature: [64]u8) !void {
    return hat_bkds_verifier.verifyCellScoped(
        root_priv,
        payload,
        signed_by,
        signature,
        oddjobz_scope.CELL_SIGN_PROTOCOL_ID,
        hat_bkds.CONTEXT_TAG_CELL_SIGN,
    );
}
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");
const cell_store_mod = @import("cell_store");
const content_store_local_fs = @import("content_store_local_fs");

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
    content: content_store_local_fs.ContentStoreLocalFs,
    sites: sites_store_fs.SitesStore,
    customers: customers_store_fs.CustomersStore,
    jobs: jobs_store_fs.JobsStore,
    attachments: attachments_store_fs.AttachmentsStore,
    ratify: oddjobz_ratify.Handler,

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
        self.content = try content_store_local_fs.ContentStoreLocalFs.init(allocator, self.data_dir);
        self.jobs = try jobs_store_fs.JobsStore.initWithContentStore(allocator, &self.cs, pinnedClock, &self.content);
        self.attachments = try attachments_store_fs.AttachmentsStore.init(allocator, &self.cs, pinnedClock);
        const stores: oddjobz_ratify.RatifyStores = .{
            .sites = &self.sites,
            .customers = &self.customers,
            .jobs = &self.jobs,
            .attachments = &self.attachments,
        };
        self.ratify = try oddjobz_ratify.Handler.init(allocator, stores, self.data_dir, pinnedClock);
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.ratify.deinit();
        self.attachments.deinit();
        self.jobs.deinit();
        self.customers.deinit();
        self.sites.deinit();
        self.content.deinit();
        self.lmdb_env.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }
};

// ─── helpers ──────────────────────────────────────────────────────

/// Build a SIRProgram-shaped JSON params object as a string.  Carries
/// the legacy payload_hint fields by default; the optional
/// PayloadHintExtras knob fills in the Tier 1.7 enriched fields.
const PayloadHintExtras = struct {
    primary_contact_name: ?[]const u8 = null,
    primary_contact_role: ?[]const u8 = null, // "tenant" / "agent" / etc.
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

// ─── tests ────────────────────────────────────────────────────────

test "oddjobz_ratify_handler: ratifying create_lead writes site + customer + job + attachment cells" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const params = try paramsJson(allocator, "prop-001", "create_lead", "AcmeCorp", .{
        .primary_contact_name = "Jane Tenant",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000001",
        .property_address = "13 Orealla Cr, Surfers Paradise QLD 4217",
        .property_key = "key #177",
        .work_order_number = "WO-001",
        .has_photos = true,
        .photo_count = 3,
        .source_attachment_path = "blob://gmail/msg-1#attachment-0",
    });
    defer allocator.free(params);

    var result = try fx.ratify.handleRatify(allocator, params);
    defer result.deinit();

    try std.testing.expectEqualStrings("prop-001", result.proposal_id);
    try std.testing.expect(result.site_cell_id != null);
    try std.testing.expect(result.job_cell_id != null);
    try std.testing.expectEqual(@as(usize, 1), result.customer_cell_ids.len);
    try std.testing.expectEqual(@as(usize, 1), result.attachment_cell_ids.len);

    // All four view-stores must show the rows.
    try std.testing.expectEqual(@as(usize, 1), fx.sites.count());
    try std.testing.expectEqual(@as(usize, 1), fx.customers.count());
    try std.testing.expectEqual(@as(usize, 1), fx.jobs.count());

    // Site cellID is non-empty hex.
    const site_hex = result.site_cell_id.?;
    try std.testing.expectEqual(@as(usize, 64), site_hex.len);

    // Site is findable by lookupKey (the dedupe primary).
    const site = fx.sites.findByLookupKey("13 orealla cr, surfers paradise qld 4217|key #177") orelse return error.MissingSiteRow;
    try std.testing.expectEqualStrings("13 orealla cr, surfers paradise qld 4217", site.normalisedAddress);
    try std.testing.expectEqualStrings("key #177", site.keyNumber.?);

    // Customer is findable by phone.
    const cust = fx.customers.findByDedupeKey(.{ .phone = "+61400000001" }) orelse return error.MissingCustomerRow;
    try std.testing.expectEqualStrings("Jane Tenant", cust.display_name);
    try std.testing.expect(cust.role.? == .tenant);

    // Job is findable for the site.
    const jobs_for_site = try fx.jobs.listForSite(allocator, site.cellId);
    defer allocator.free(jobs_for_site);
    try std.testing.expectEqual(@as(usize, 1), jobs_for_site.len);
    try std.testing.expectEqualStrings("lead", jobs_for_site[0].state);
    try std.testing.expectEqualStrings("WO-001", jobs_for_site[0].workOrderNumber.?);

    // Attachment is findable for the job.
    const job_cell_id = jobs_for_site[0].cellId.?;
    const atts_for_job = try fx.attachments.findForJob(allocator, job_cell_id);
    defer allocator.free(atts_for_job);
    try std.testing.expectEqual(@as(usize, 1), atts_for_job.len);
    try std.testing.expectEqualStrings("blob://gmail/msg-1#attachment-0", atts_for_job[0].sourceBlobKey.?);
    try std.testing.expectEqual(true, atts_for_job[0].hasPhotos);
    try std.testing.expectEqual(@as(u32, 3), atts_for_job[0].photoCount.?);
}

test "oddjobz_ratify_handler: re-ratifying the same proposal_id is idempotent" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const params = try paramsJson(allocator, "prop-002", "create_quote_request", "Bob's Plumbing", .{
        .primary_contact_name = "Bob Owner",
        .primary_contact_role = "owner",
        .property_address = "1 Example St",
    });
    defer allocator.free(params);

    var first = try fx.ratify.handleRatify(allocator, params);
    defer first.deinit();
    try std.testing.expect(first.site_cell_id != null);
    try std.testing.expect(first.job_cell_id != null);
    const first_site = try allocator.dupe(u8, first.site_cell_id.?);
    defer allocator.free(first_site);
    const first_job = try allocator.dupe(u8, first.job_cell_id.?);
    defer allocator.free(first_job);

    // Repeat ratify must return the SAME cell IDs and MUST NOT mint
    // any new cells.
    var second = try fx.ratify.handleRatify(allocator, params);
    defer second.deinit();
    try std.testing.expectEqualStrings(first_site, second.site_cell_id.?);
    try std.testing.expectEqualStrings(first_job, second.job_cell_id.?);

    // No double-mint anywhere in the graph.
    try std.testing.expectEqual(@as(usize, 1), fx.sites.count());
    try std.testing.expectEqual(@as(usize, 1), fx.jobs.count());
    try std.testing.expectEqual(@as(usize, 1), fx.customers.count());
}

test "oddjobz_ratify_handler: two SIRs with the same property address share a siteRef (lookup-or-mint dedupe)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const params_a = try paramsJson(allocator, "prop-site-a", "create_lead", "Tenant A", .{
        .primary_contact_name = "Alice Tenant",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000010",
        .property_address = "29 Foedera Cres, Tewantin QLD 4565",
        .property_key = "front gate",
    });
    defer allocator.free(params_a);
    const params_b = try paramsJson(allocator, "prop-site-b", "create_lead", "Tenant B", .{
        .primary_contact_name = "Bob Tenant",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000011",
        // Same address (capitalisation/whitespace shouldn't matter — the
        // normaliser collapses both to the same canonical form).
        .property_address = "29  Foedera Cres,  Tewantin   QLD 4565",
        .property_key = "front gate",
    });
    defer allocator.free(params_b);

    var ra = try fx.ratify.handleRatify(allocator, params_a);
    defer ra.deinit();
    var rb = try fx.ratify.handleRatify(allocator, params_b);
    defer rb.deinit();

    // Same site cellID, but distinct job cellIDs (each ratify mints
    // its own job).
    try std.testing.expectEqualStrings(ra.site_cell_id.?, rb.site_cell_id.?);
    try std.testing.expect(!std.mem.eql(u8, ra.job_cell_id.?, rb.job_cell_id.?));
    try std.testing.expectEqual(@as(usize, 1), fx.sites.count());
    try std.testing.expectEqual(@as(usize, 2), fx.jobs.count());
}

test "oddjobz_ratify_handler: two SIRs with the same primary phone share a customerRef (dedupe)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const params_a = try paramsJson(allocator, "prop-cust-a", "create_lead", "Site A", .{
        .primary_contact_name = "Carol Tenant",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000020",
        .property_address = "1 Site A Rd",
    });
    defer allocator.free(params_a);
    const params_b = try paramsJson(allocator, "prop-cust-b", "create_lead", "Site B", .{
        // Same person — same phone — different site.  The phone-first
        // dedupe ladder collapses both onto the same customer cell.
        .primary_contact_name = "Carol Tenant (different display)",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000020",
        .property_address = "2 Site B Rd",
    });
    defer allocator.free(params_b);

    var ra = try fx.ratify.handleRatify(allocator, params_a);
    defer ra.deinit();
    var rb = try fx.ratify.handleRatify(allocator, params_b);
    defer rb.deinit();

    try std.testing.expectEqual(@as(usize, 1), ra.customer_cell_ids.len);
    try std.testing.expectEqual(@as(usize, 1), rb.customer_cell_ids.len);
    try std.testing.expectEqualStrings(ra.customer_cell_ids[0], rb.customer_cell_ids[0]);

    // Sites differ, customers don't double-mint.
    try std.testing.expectEqual(@as(usize, 2), fx.sites.count());
    try std.testing.expectEqual(@as(usize, 1), fx.customers.count());
    try std.testing.expectEqual(@as(usize, 2), fx.jobs.count());
}

test "oddjobz_ratify_handler: legacy payload (no Tier 1.7 fields) still produces a graph" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // Legacy minimal payload — no primaryContact, no propertyAddress,
    // no work-order metadata.  Handler synthesises an agent-role
    // primary contact from customer_name; uses customer_name as
    // fullAddress fallback so site lookup-or-mint doesn't blow up.
    const params = try paramsJson(allocator, "prop-legacy-001", "create_lead", "Legacy Customer", .{});
    defer allocator.free(params);

    var result = try fx.ratify.handleRatify(allocator, params);
    defer result.deinit();
    try std.testing.expect(result.site_cell_id != null);
    try std.testing.expect(result.job_cell_id != null);
    try std.testing.expectEqual(@as(usize, 1), result.customer_cell_ids.len);
    // No source_attachment_path → no attachment cell.
    try std.testing.expectEqual(@as(usize, 0), result.attachment_cell_ids.len);
}

test "oddjobz_ratify_handler: noop / attach_reply nodes produce empty graph (no cells minted)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const params = try paramsJson(allocator, "prop-noop", "noop", "ignored", .{});
    defer allocator.free(params);

    var result = try fx.ratify.handleRatify(allocator, params);
    defer result.deinit();

    try std.testing.expect(result.site_cell_id == null);
    try std.testing.expect(result.job_cell_id == null);
    try std.testing.expectEqual(@as(usize, 0), result.customer_cell_ids.len);
    try std.testing.expectEqual(@as(usize, 0), result.attachment_cell_ids.len);
    try std.testing.expectEqual(@as(usize, 0), fx.sites.count());
    try std.testing.expectEqual(@as(usize, 0), fx.jobs.count());
    try std.testing.expectEqual(@as(usize, 0), fx.customers.count());
}

test "oddjobz_ratify_handler: invalid params surface as RatifyError variants" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    // Missing both proposal_id AND sir_program.
    const bogus = "{}";
    try std.testing.expectError(oddjobz_ratify.RatifyError.invalid_params, fx.ratify.handleRatify(allocator, bogus));

    // Empty proposal_id.
    const empty_pid =
        \\{"proposal_id":"","sir_program":{"nodes":[]}}
    ;
    try std.testing.expectError(oddjobz_ratify.RatifyError.invalid_proposal_id, fx.ratify.handleRatify(allocator, empty_pid));

    // SIR with no nodes.
    const empty_sir =
        \\{"proposal_id":"prop-x","sir_program":{"nodes":[]}}
    ;
    try std.testing.expectError(oddjobz_ratify.RatifyError.invalid_sir_program, fx.ratify.handleRatify(allocator, empty_sir));
}

test "oddjobz_ratify_handler: create_work_order produces a graph with workOrderNumber populated" {
    // D-DOG.1.0c Phase 2B.3 — Phase 2B.2 noted the TS-side filter
    // recognises `create_work_order` but the Zig handler's
    // isRatifiableAction set was missing it, so WSS-path proposals
    // with this action produced empty graphs.  This test pins the
    // fix.  Pattern: same as create_lead, plus assert workOrderNumber
    // flows from payload_hint into the minted job row.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const params = try paramsJson(allocator, "prop-wo-001", "create_work_order", "Acme PM", .{
        .primary_contact_name = "Wo Tenant",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000123",
        .property_address = "5 Work Order Way, Brisbane QLD 4000",
        .property_key = "key #5",
        .work_order_number = "WO-2026-0042",
        .issuance_date = "2026-05-01",
        .due_date = "2026-05-15",
        .source_attachment_path = "blob://propertyme/wo-42",
    });
    defer allocator.free(params);

    var result = try fx.ratify.handleRatify(allocator, params);
    defer result.deinit();

    // Graph minted (would have been empty under the pre-fix filter).
    try std.testing.expect(result.site_cell_id != null);
    try std.testing.expect(result.job_cell_id != null);
    try std.testing.expectEqual(@as(usize, 1), result.customer_cell_ids.len);
    try std.testing.expectEqual(@as(usize, 1), result.attachment_cell_ids.len);
    try std.testing.expectEqual(@as(usize, 1), fx.jobs.count());

    // workOrderNumber flows through to the minted job row.
    const all = try fx.jobs.listAll(allocator);
    defer allocator.free(all);
    try std.testing.expectEqualStrings("WO-2026-0042", all[0].workOrderNumber.?);
    try std.testing.expectEqualStrings("2026-05-01", all[0].issuanceDate.?);
    try std.testing.expectEqualStrings("2026-05-15", all[0].dueDate.?);
    try std.testing.expectEqualStrings("lead", all[0].state);
}

test "oddjobz_ratify_handler: create_maintenance_order produces a graph (parity with create_work_order)" {
    // D-DOG.1.0c Phase 2B.3 — TS-side filter parity.  The
    // maintenance-order action takes the same downstream shape as
    // create_work_order; we just need the filter to recognise it.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const params = try paramsJson(allocator, "prop-mo-001", "create_maintenance_order", "MaintCo", .{
        .primary_contact_name = "Maint Tenant",
        .primary_contact_role = "tenant",
        .property_address = "9 Maint Mews",
        .work_order_number = "MO-2026-0007",
    });
    defer allocator.free(params);

    var result = try fx.ratify.handleRatify(allocator, params);
    defer result.deinit();

    try std.testing.expect(result.site_cell_id != null);
    try std.testing.expect(result.job_cell_id != null);
    try std.testing.expectEqual(@as(usize, 1), fx.jobs.count());

    const all = try fx.jobs.listAll(allocator);
    defer allocator.free(all);
    try std.testing.expectEqualStrings("MO-2026-0007", all[0].workOrderNumber.?);
}

test "oddjobz_ratify_handler: idempotency survives handler restart (replay loads the log)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const params = try paramsJson(allocator, "prop-restart", "create_booking", "RestartCo", .{
        .primary_contact_name = "Restart Owner",
        .primary_contact_role = "owner",
        .property_address = "999 Restart Way",
    });
    defer allocator.free(params);

    var first = try fx.ratify.handleRatify(allocator, params);
    defer first.deinit();
    const first_site = try allocator.dupe(u8, first.site_cell_id.?);
    defer allocator.free(first_site);
    const first_job = try allocator.dupe(u8, first.job_cell_id.?);
    defer allocator.free(first_job);

    // Drop the in-memory handler and re-init from the on-disk
    // ratifications log.  The four view-stores are also rebuilt by
    // re-init (their replay paths re-load the JSONL files).
    fx.ratify.deinit();
    fx.attachments.deinit();
    fx.jobs.deinit();
    fx.customers.deinit();
    fx.sites.deinit();
    fx.sites = try sites_store_fs.SitesStore.init(allocator, &fx.cs, pinnedClock);
    fx.customers = try customers_store_fs.CustomersStore.init(allocator, &fx.cs, pinnedClock);
    fx.jobs = try jobs_store_fs.JobsStore.initWithContentStore(allocator, &fx.cs, pinnedClock, &fx.content);
    fx.attachments = try attachments_store_fs.AttachmentsStore.init(allocator, &fx.cs, pinnedClock);
    const stores: oddjobz_ratify.RatifyStores = .{
        .sites = &fx.sites,
        .customers = &fx.customers,
        .jobs = &fx.jobs,
        .attachments = &fx.attachments,
    };
    fx.ratify = try oddjobz_ratify.Handler.init(allocator, stores, fx.data_dir, pinnedClock);

    var second = try fx.ratify.handleRatify(allocator, params);
    defer second.deinit();
    try std.testing.expectEqualStrings(first_site, second.site_cell_id.?);
    try std.testing.expectEqualStrings(first_job, second.job_cell_id.?);

    // No double-mint after replay.
    try std.testing.expectEqual(@as(usize, 1), fx.sites.count());
    try std.testing.expectEqual(@as(usize, 1), fx.jobs.count());
}

// ─── D-DOG.1.0c Phase 4 row B.2 — signed-mint coverage ──────────────

/// Variant of Fixture that wires a HatBkds signer into the
/// RatifyStores bag so every minted cell gets a derived BKDS pubkey
/// + signature on the way to disk.  Mirrors the dogfood + production
/// `brain serve` bring-up path.
const SignedFixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    lmdb_env: lmdb.Env,
    cs_impl: lmdb_cell_store.LmdbCellStore,
    cs: cell_store_mod.CellStore,
    content: content_store_local_fs.ContentStoreLocalFs,
    sites: sites_store_fs.SitesStore,
    customers: customers_store_fs.CustomersStore,
    jobs: jobs_store_fs.JobsStore,
    attachments: attachments_store_fs.AttachmentsStore,
    hat: hat_bkds.HatBkds,
    ratify: oddjobz_ratify.Handler,

    fn init(allocator: std.mem.Allocator) !*SignedFixture {
        const self = try allocator.create(SignedFixture);
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
        self.content = try content_store_local_fs.ContentStoreLocalFs.init(allocator, self.data_dir);
        self.jobs = try jobs_store_fs.JobsStore.initWithContentStore(allocator, &self.cs, pinnedClock, &self.content);
        self.attachments = try attachments_store_fs.AttachmentsStore.init(allocator, &self.cs, pinnedClock);
        self.hat = try hat_bkds.HatBkds.initFromSeed("ratify-handler-signed-fixture-root");
        const stores: oddjobz_ratify.RatifyStores = .{
            .sites = &self.sites,
            .customers = &self.customers,
            .jobs = &self.jobs,
            .attachments = &self.attachments,
            .hat_bkds = &self.hat,
        };
        self.ratify = try oddjobz_ratify.Handler.init(allocator, stores, self.data_dir, pinnedClock);
        return self;
    }

    fn deinit(self: *SignedFixture) void {
        self.ratify.deinit();
        self.hat.deinit();
        self.attachments.deinit();
        self.jobs.deinit();
        self.customers.deinit();
        self.sites.deinit();
        self.content.deinit();
        self.lmdb_env.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }
};

test "oddjobz_ratify_handler: minted cells carry non-null signedBy + verifiable signature" {
    const allocator = std.testing.allocator;
    var fx = try SignedFixture.init(allocator);
    defer fx.deinit();

    const params = try paramsJson(allocator, "prop-signed-001", "create_lead", "AcmeCorp", .{
        .primary_contact_name = "Jane Tenant",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000001",
        .property_address = "13 Orealla Cr, Surfers Paradise QLD 4217",
        .property_key = "key #177",
        .work_order_number = "WO-001",
        .has_photos = true,
        .photo_count = 3,
        .source_attachment_path = "blob://gmail/msg-1#attachment-0",
    });
    defer allocator.free(params);

    var result = try fx.ratify.handleRatify(allocator, params);
    defer result.deinit();

    // Every minted cell carries a non-null signedBy + a verifiable
    // signature.  We pull each row out of its store and run the
    // verifier (operator-side, root_priv-aware) against it.

    // ── Site cell ─────────────────────────────────────────────────
    const site_lookup_key = "13 orealla cr, surfers paradise qld 4217|key #177";
    const site = fx.sites.findByLookupKey(site_lookup_key) orelse return error.MissingSiteRow;
    try std.testing.expect(site.signedBy != null);
    try std.testing.expect(site.signature != null);
    try verifyOddjobzCell(
        fx.hat.root_priv,
        &site.cellId,
        site.signedBy.?,
        site.signature.?,
    );

    // ── Customer cell ─────────────────────────────────────────────
    const cust = fx.customers.findByDedupeKey(.{ .phone = "+61400000001" }) orelse return error.MissingCustomerRow;
    try std.testing.expect(cust.signedBy != null);
    try std.testing.expect(cust.signature != null);
    try verifyOddjobzCell(
        fx.hat.root_priv,
        &cust.cellId.?,
        cust.signedBy.?,
        cust.signature.?,
    );

    // ── Job cell ──────────────────────────────────────────────────
    const jobs_for_site = try fx.jobs.listForSite(allocator, site.cellId);
    defer allocator.free(jobs_for_site);
    try std.testing.expectEqual(@as(usize, 1), jobs_for_site.len);
    const job = jobs_for_site[0];
    try std.testing.expect(job.signedBy != null);
    try std.testing.expect(job.signature != null);
    try verifyOddjobzCell(
        fx.hat.root_priv,
        &job.cellId.?,
        job.signedBy.?,
        job.signature.?,
    );

    // ── Attachment cell ───────────────────────────────────────────
    const atts = try fx.attachments.findForJob(allocator, job.cellId.?);
    defer allocator.free(atts);
    try std.testing.expectEqual(@as(usize, 1), atts.len);
    const att = atts[0];
    try std.testing.expect(att.signedBy != null);
    try std.testing.expect(att.signature != null);
    try verifyOddjobzCell(
        fx.hat.root_priv,
        &att.cellId.?,
        att.signedBy.?,
        att.signature.?,
    );

    // ── Cross-cell unlinkability — each derived pubkey is distinct ──
    // The privacy property: a third party walking the four stores
    // sees four unrelated pubkeys with no cross-cell correlation.
    try std.testing.expect(!std.mem.eql(u8, &site.signedBy.?, &cust.signedBy.?));
    try std.testing.expect(!std.mem.eql(u8, &site.signedBy.?, &job.signedBy.?));
    try std.testing.expect(!std.mem.eql(u8, &site.signedBy.?, &att.signedBy.?));
    try std.testing.expect(!std.mem.eql(u8, &cust.signedBy.?, &job.signedBy.?));
}

test "oddjobz_ratify_handler: no signer wired in → cells stay unsigned (Phase 2A.4 fallback)" {
    // The legacy Fixture (no hat_bkds) should produce cells with
    // signedBy = null.  This is the backward-compat path that
    // `brain resign-pending` (B.4) backfills.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const params = try paramsJson(allocator, "prop-unsigned-001", "create_lead", "AcmeCorp", .{
        .primary_contact_name = "Jane Tenant",
        .primary_contact_role = "tenant",
        .primary_contact_phone = "+61400000001",
        .property_address = "1 Unsigned St",
    });
    defer allocator.free(params);

    var result = try fx.ratify.handleRatify(allocator, params);
    defer result.deinit();

    const site = fx.sites.findByLookupKey("1 unsigned st|") orelse return error.MissingSiteRow;
    try std.testing.expect(site.signedBy == null);
    try std.testing.expect(site.signature == null);
}



```
