---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/oddjobz_query_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.543908+00:00
---

# cartridges/oddjobz/brain/zig/src/oddjobz_query_handler.zig

```zig
// D-DOG.1.0c Phase 2B.3 — cross-store query handler.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 2
//            sub-deliverable D.1 (this PR);
//            runtime/semantos-brain/src/oddjobz_ratify_handler.zig — pattern this
//              handler mirrors;
//            runtime/semantos-brain/src/{sites,customers,jobs,attachments}_store_fs
//              .zig — the four typed view-stores this handler reads from.
//
// What this exists for:
//
//   Phase 2A landed the four typed view-stores; Phase 2A.4 wired the
//   ratify handler's graph-walk that populates them; Phase 2B.1+2B.2
//   wired the TS ingest path's full graph emission.  But there's no
//   READ surface yet — the helm + mobile UI in Phase 3 needs JSON-RPC
//   verbs to ask "what jobs at this site?", "what jobs for this
//   customer?", "what's the source PDF for this job?".
//
//   This handler is a thin read-side fan-out over the four stores'
//   already-existing helpers: each verb calls one store function, JSON-
//   encodes the result, and writes it through the WSS dispatcher.  No
//   in-memory state, no idempotency machinery, no log persistence —
//   the truth lives in the stores.
//
// Verbs (all return JSON-RPC `result`):
//
//   • oddjobz.find_jobs_at_site(siteRef: hex32) → { jobs: Job[] }
//       Calls jobs_store.listForSite.  v2 rows only (v1 has no siteRef).
//
//   • oddjobz.find_jobs_for_customer(customerRef: hex32) → { jobs: Job[] }
//       Calls jobs_store.listForCustomer.  v2 rows only.
//
//   • oddjobz.find_attachments_for_job(jobRef: hex32) → { attachments: Attachment[] }
//       Calls attachments_store.findForJob.  v2 PDF-source rows only;
//       v1 visit-side rows excluded (they have no jobRef).
//
//   • oddjobz.list_sites()       → { sites: Site[] }
//   • oddjobz.list_customers()   → { customers: Customer[] }
//       Both v1 and v2 customer rows (v1 rows carry null v2 fields).
//
//   • oddjobz.get_site(siteRef: hex32)             → { site: Site | null }
//   • oddjobz.get_customer(customerRef: hex32)     → { customer: Customer | null }
//   • oddjobz.get_job(jobRef: hex32)               → { job: Job | null }
//   • oddjobz.get_attachment(attachmentRef: hex32) → { attachment: Attachment | null }
//
// Error surface (all maps to JSON-RPC -32602 `invalid params` or
// -32603 `internal error`):
//   • QueryError.invalid_params       — params not an object / missing
//                                       required field.
//   • QueryError.invalid_cell_ref     — cellRef not 64 lowercase hex.
//   • QueryError.store_unavailable    — required store not wired
//                                       (daemon was started without
//                                       --enable-repl or the store
//                                       failed to open).
//   • QueryError.out_of_memory        — allocator failed.
//
// Wire shape: every cell-typed array element renders the schema's
// REQUIRED-set fields plus the v2 graph-aware fields.  v1 rows carry
// `cellId: null` etc. so the helm SPA can disambiguate without a
// version discriminator.

const std = @import("std");
const sites_store_fs = @import("sites_store_fs");
const customers_store_fs = @import("customers_store_fs");
const jobs_store_fs = @import("jobs_store_fs");
const attachments_store_fs = @import("attachments_store_fs");

pub const QueryError = error{
    /// `params` JSON failed to parse, was not an object, or was
    /// missing the required `cellRef` / `siteRef` / `customerRef` /
    /// `jobRef` / `attachmentRef` field.
    invalid_params,
    /// Cell reference field present but not 64 lowercase hex.
    invalid_cell_ref,
    /// One of the four required view-stores wasn't wired.  Daemon
    /// would need --enable-repl + the store's init not having failed.
    store_unavailable,
    out_of_memory,
};

/// Bag of view-store pointers the handler holds for its lifetime.
/// Same shape as `oddjobz_ratify_handler.RatifyStores`; all four MUST
/// outlive the handler.  Best-effort fields are `?*`-typed so a
/// partial bring-up (one store failed to open) leaves the handler
/// degraded but doesn't crash the daemon — verbs that need an absent
/// store return `store_unavailable`.
pub const QueryStores = struct {
    sites: ?*sites_store_fs.SitesStore = null,
    customers: ?*customers_store_fs.CustomersStore = null,
    jobs: ?*jobs_store_fs.JobsStore = null,
    attachments: ?*attachments_store_fs.AttachmentsStore = null,
};

pub const Handler = struct {
    stores: QueryStores,

    pub fn init(stores: QueryStores) Handler {
        return .{ .stores = stores };
    }

    // ─── List verbs ─────────────────────────────────────────────────

    /// `oddjobz.list_sites()` → `{ sites: Site[] }`.  Caller owns the
    /// returned slice; it's a fresh-allocated JSON body string.
    pub fn listSites(self: *const Handler, allocator: std.mem.Allocator) QueryError![]u8 {
        const sites_ptr = self.stores.sites orelse return QueryError.store_unavailable;
        const rows = sites_ptr.listAll(allocator) catch return QueryError.out_of_memory;
        defer allocator.free(rows);

        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try appendSlice(allocator, &buf, "{\"sites\":[");
        for (rows, 0..) |row, i| {
            if (i != 0) try append(allocator, &buf, ',');
            try writeSite(allocator, &buf, row);
        }
        try appendSlice(allocator, &buf, "]}");
        return buf.toOwnedSlice(allocator) catch QueryError.out_of_memory;
    }

    /// `oddjobz.list_customers()` → `{ customers: Customer[] }`.
    /// Includes both v1 and v2 rows (v1 rows have null v2 fields).
    pub fn listCustomers(self: *const Handler, allocator: std.mem.Allocator) QueryError![]u8 {
        const customers_ptr = self.stores.customers orelse return QueryError.store_unavailable;
        const rows = customers_ptr.listAll(allocator) catch return QueryError.out_of_memory;
        defer allocator.free(rows);

        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try appendSlice(allocator, &buf, "{\"customers\":[");
        for (rows, 0..) |row, i| {
            if (i != 0) try append(allocator, &buf, ',');
            try writeCustomer(allocator, &buf, row);
        }
        try appendSlice(allocator, &buf, "]}");
        return buf.toOwnedSlice(allocator) catch QueryError.out_of_memory;
    }

    // ─── Cross-store query verbs ───────────────────────────────────

    /// `oddjobz.find_jobs_at_site` → `{ jobs: Job[] }`.  v2 rows only.
    pub fn findJobsAtSite(
        self: *const Handler,
        allocator: std.mem.Allocator,
        params_json: []const u8,
    ) QueryError![]u8 {
        const jobs_ptr = self.stores.jobs orelse return QueryError.store_unavailable;
        const site_ref = try parseHexRef(params_json, "siteRef", allocator);
        const rows = jobs_ptr.listForSite(allocator, site_ref) catch return QueryError.out_of_memory;
        defer allocator.free(rows);
        return encodeJobsArray(allocator, rows);
    }

    /// `oddjobz.find_jobs_for_customer` → `{ jobs: Job[] }`.  v2 rows
    /// only; matches when ANY customerRef.cellId equals the argument.
    pub fn findJobsForCustomer(
        self: *const Handler,
        allocator: std.mem.Allocator,
        params_json: []const u8,
    ) QueryError![]u8 {
        const jobs_ptr = self.stores.jobs orelse return QueryError.store_unavailable;
        const customer_ref = try parseHexRef(params_json, "customerRef", allocator);
        const rows = jobs_ptr.listForCustomer(allocator, customer_ref) catch return QueryError.out_of_memory;
        defer allocator.free(rows);
        return encodeJobsArray(allocator, rows);
    }

    /// `oddjobz.find_attachments_for_job` → `{ attachments: Attachment[] }`.
    /// v2 PDF-source rows only; v1 visit-side rows are filtered out by
    /// `findForJob` (they have no jobRef).
    pub fn findAttachmentsForJob(
        self: *const Handler,
        allocator: std.mem.Allocator,
        params_json: []const u8,
    ) QueryError![]u8 {
        const atts_ptr = self.stores.attachments orelse return QueryError.store_unavailable;
        const job_ref = try parseHexRef(params_json, "jobRef", allocator);
        const rows = atts_ptr.findForJob(allocator, job_ref) catch return QueryError.out_of_memory;
        defer allocator.free(rows);

        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try appendSlice(allocator, &buf, "{\"attachments\":[");
        for (rows, 0..) |row, i| {
            if (i != 0) try append(allocator, &buf, ',');
            try writeAttachment(allocator, &buf, row);
        }
        try appendSlice(allocator, &buf, "]}");
        return buf.toOwnedSlice(allocator) catch QueryError.out_of_memory;
    }

    // ─── Single-record getters ─────────────────────────────────────

    /// `oddjobz.get_site(siteRef)` → `{ site: Site | null }`.
    pub fn getSite(
        self: *const Handler,
        allocator: std.mem.Allocator,
        params_json: []const u8,
    ) QueryError![]u8 {
        const sites_ptr = self.stores.sites orelse return QueryError.store_unavailable;
        const site_ref = try parseHexRef(params_json, "siteRef", allocator);

        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try appendSlice(allocator, &buf, "{\"site\":");
        if (sites_ptr.getById(site_ref)) |row| {
            try writeSite(allocator, &buf, row);
        } else {
            try appendSlice(allocator, &buf, "null");
        }
        try append(allocator, &buf, '}');
        return buf.toOwnedSlice(allocator) catch QueryError.out_of_memory;
    }

    /// `oddjobz.get_customer(customerRef)` → `{ customer: Customer | null }`.
    /// Looks up by cellId — v2-only.  v1 rows are unreachable here
    /// (they don't carry a cellId); use the legacy `customers.get`
    /// dispatcher verb for v1 lookup-by-uuid.
    pub fn getCustomer(
        self: *const Handler,
        allocator: std.mem.Allocator,
        params_json: []const u8,
    ) QueryError![]u8 {
        const customers_ptr = self.stores.customers orelse return QueryError.store_unavailable;
        const customer_ref = try parseHexRef(params_json, "customerRef", allocator);

        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try appendSlice(allocator, &buf, "{\"customer\":");
        if (customers_ptr.getByCellId(customer_ref)) |row| {
            try writeCustomer(allocator, &buf, row);
        } else {
            try appendSlice(allocator, &buf, "null");
        }
        try append(allocator, &buf, '}');
        return buf.toOwnedSlice(allocator) catch QueryError.out_of_memory;
    }

    /// `oddjobz.get_job(jobRef)` → `{ job: Job | null }`.
    /// v2 rows only; v1 rows lack a cellId.
    pub fn getJob(
        self: *const Handler,
        allocator: std.mem.Allocator,
        params_json: []const u8,
    ) QueryError![]u8 {
        const jobs_ptr = self.stores.jobs orelse return QueryError.store_unavailable;
        const job_ref = try parseHexRef(params_json, "jobRef", allocator);

        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try appendSlice(allocator, &buf, "{\"job\":");
        if (jobs_ptr.getById(job_ref)) |row| {
            try writeJob(allocator, &buf, row);
        } else {
            try appendSlice(allocator, &buf, "null");
        }
        try append(allocator, &buf, '}');
        return buf.toOwnedSlice(allocator) catch QueryError.out_of_memory;
    }

    /// `oddjobz.get_attachment(attachmentRef)` → `{ attachment: Attachment | null }`.
    /// v2 rows only.
    pub fn getAttachment(
        self: *const Handler,
        allocator: std.mem.Allocator,
        params_json: []const u8,
    ) QueryError![]u8 {
        const atts_ptr = self.stores.attachments orelse return QueryError.store_unavailable;
        const att_ref = try parseHexRef(params_json, "attachmentRef", allocator);

        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try appendSlice(allocator, &buf, "{\"attachment\":");
        if (atts_ptr.getByCellId(att_ref)) |row| {
            try writeAttachment(allocator, &buf, row);
        } else {
            try appendSlice(allocator, &buf, "null");
        }
        try append(allocator, &buf, '}');
        return buf.toOwnedSlice(allocator) catch QueryError.out_of_memory;
    }
};

// ─── Param parsing ─────────────────────────────────────────────────

/// Parse a 64-lowercase-hex cell reference field out of the JSON-RPC
/// params object.  Returns the decoded 32-byte value.  Empty / wrong-
/// length / non-hex / wrong-case → invalid_cell_ref; missing field /
/// non-object / unparseable JSON → invalid_params.
fn parseHexRef(
    params_json: []const u8,
    field: []const u8,
    allocator: std.mem.Allocator,
) QueryError![32]u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch
        return QueryError.invalid_params;
    defer parsed.deinit();
    if (parsed.value != .object) return QueryError.invalid_params;
    const v = parsed.value.object.get(field) orelse return QueryError.invalid_params;
    if (v != .string) return QueryError.invalid_params;
    if (v.string.len != 64) return QueryError.invalid_cell_ref;
    var out: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, v.string) catch return QueryError.invalid_cell_ref;
    return out;
}

// ─── Encoders ──────────────────────────────────────────────────────

fn encodeJobsArray(allocator: std.mem.Allocator, rows: []jobs_store_fs.Job) QueryError![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try appendSlice(allocator, &buf, "{\"jobs\":[");
    for (rows, 0..) |row, i| {
        if (i != 0) try append(allocator, &buf, ',');
        try writeJob(allocator, &buf, row);
    }
    try appendSlice(allocator, &buf, "]}");
    return buf.toOwnedSlice(allocator) catch QueryError.out_of_memory;
}

/// Render a v2-aware `Site` row to JSON.  Required fields populate
/// directly; optional fields write `null` when the store has no value.
fn writeSite(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    site: sites_store_fs.Site,
) QueryError!void {
    try appendSlice(allocator, out, "{\"cellId\":");
    try writeHex32String(allocator, out, &site.cellId);
    try appendSlice(allocator, out, ",\"typeHash\":");
    try writeHex32String(allocator, out, &site.typeHash);
    try appendSlice(allocator, out, ",\"normalisedAddress\":");
    try writeJsonString(allocator, out, site.normalisedAddress);
    try appendSlice(allocator, out, ",\"keyNumber\":");
    try writeOptStr(allocator, out, site.keyNumber);
    try appendSlice(allocator, out, ",\"lookupKey\":");
    try writeJsonString(allocator, out, site.lookupKey);
    try appendSlice(allocator, out, ",\"fullAddress\":");
    try writeJsonString(allocator, out, site.fullAddress);
    try appendSlice(allocator, out, ",\"suburb\":");
    try writeOptStr(allocator, out, site.suburb);
    try appendSlice(allocator, out, ",\"postcode\":");
    try writeOptStr(allocator, out, site.postcode);
    try appendSlice(allocator, out, ",\"state\":");
    try writeOptStr(allocator, out, site.state);
    try appendSlice(allocator, out, ",\"createdAt\":");
    try writeI64(allocator, out, site.createdAt);
    try append(allocator, out, '}');
}

/// Render a v1/v2 mixed-shape `Customer` row to JSON.  v1 rows have
/// the v2 fields (`cellId`, `typeHash`, `role`, `normalisedPhone`,
/// `sourceProvenance`, `siteRef`) all `null`.  Required fields
/// populate directly.
fn writeCustomer(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    cust: customers_store_fs.Customer,
) QueryError!void {
    try appendSlice(allocator, out, "{\"id\":");
    try writeJsonString(allocator, out, cust.id);
    try appendSlice(allocator, out, ",\"display_name\":");
    try writeJsonString(allocator, out, cust.display_name);
    try appendSlice(allocator, out, ",\"phone\":");
    try writeJsonString(allocator, out, cust.phone);
    try appendSlice(allocator, out, ",\"email\":");
    try writeJsonString(allocator, out, cust.email);
    try appendSlice(allocator, out, ",\"address\":");
    try writeJsonString(allocator, out, cust.address);
    try appendSlice(allocator, out, ",\"notes\":");
    try writeJsonString(allocator, out, cust.notes);
    try appendSlice(allocator, out, ",\"created_at\":");
    try writeJsonString(allocator, out, cust.created_at);

    try appendSlice(allocator, out, ",\"cellId\":");
    if (cust.cellId) |c| {
        try writeHex32String(allocator, out, &c);
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"typeHash\":");
    if (cust.typeHash) |c| {
        try writeHex32String(allocator, out, &c);
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"role\":");
    if (cust.role) |r| {
        try writeJsonString(allocator, out, r.toString());
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"normalisedPhone\":");
    try writeOptStr(allocator, out, cust.normalisedPhone);
    try appendSlice(allocator, out, ",\"sourceProvenance\":");
    if (cust.sourceProvenance) |sp| {
        try appendSlice(allocator, out, "{\"providerId\":");
        try writeJsonString(allocator, out, sp.providerId);
        try appendSlice(allocator, out, ",\"providerItemId\":");
        try writeJsonString(allocator, out, sp.providerItemId);
        try appendSlice(allocator, out, ",\"extractedAt\":");
        try writeJsonString(allocator, out, sp.extractedAt);
        try append(allocator, out, '}');
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"siteRef\":");
    if (cust.siteRef) |sr| {
        try writeHex32String(allocator, out, &sr);
    } else {
        try appendSlice(allocator, out, "null");
    }
    try append(allocator, out, '}');
}

/// Render a v1/v2 mixed-shape `Job` row to JSON.  v1 rows have every
/// v2 field `null`.
fn writeJob(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    job: jobs_store_fs.Job,
) QueryError!void {
    try appendSlice(allocator, out, "{\"version\":");
    try writeI64(allocator, out, @intCast(job.version));
    try appendSlice(allocator, out, ",\"id\":");
    try writeJsonString(allocator, out, job.id);
    try appendSlice(allocator, out, ",\"customer_name\":");
    try writeJsonString(allocator, out, job.customer_name);
    try appendSlice(allocator, out, ",\"state\":");
    try writeJsonString(allocator, out, job.state);
    try appendSlice(allocator, out, ",\"scheduled_at\":");
    try writeJsonString(allocator, out, job.scheduled_at);
    try appendSlice(allocator, out, ",\"created_at\":");
    try writeJsonString(allocator, out, job.created_at);

    try appendSlice(allocator, out, ",\"cellId\":");
    if (job.cellId) |c| {
        try writeHex32String(allocator, out, &c);
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"typeHash\":");
    if (job.typeHash) |c| {
        try writeHex32String(allocator, out, &c);
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"workOrderNumber\":");
    try writeOptStr(allocator, out, job.workOrderNumber);
    try appendSlice(allocator, out, ",\"issuanceDate\":");
    try writeOptStr(allocator, out, job.issuanceDate);
    try appendSlice(allocator, out, ",\"dueDate\":");
    try writeOptStr(allocator, out, job.dueDate);
    try appendSlice(allocator, out, ",\"billingParty\":");
    if (job.billingParty) |bp| {
        try appendSlice(allocator, out, "{\"type\":");
        try writeJsonString(allocator, out, bp.type);
        try appendSlice(allocator, out, ",\"name\":");
        try writeJsonString(allocator, out, bp.name);
        try append(allocator, out, '}');
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"hasPhotos\":");
    if (job.hasPhotos) |b| {
        try appendSlice(allocator, out, if (b) "true" else "false");
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"photoCount\":");
    if (job.photoCount) |c| {
        try writeI64(allocator, out, @intCast(c));
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"propertyKey\":");
    try writeOptStr(allocator, out, job.propertyKey);
    try appendSlice(allocator, out, ",\"siteRef\":");
    if (job.siteRef) |sr| {
        try writeHex32String(allocator, out, &sr);
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"customerRefs\":");
    if (job.customerRefs) |refs| {
        try append(allocator, out, '[');
        for (refs, 0..) |cref, i| {
            if (i != 0) try append(allocator, out, ',');
            try appendSlice(allocator, out, "{\"cellId\":");
            try writeHex32String(allocator, out, &cref.cellId);
            try appendSlice(allocator, out, ",\"role\":");
            try writeJsonString(allocator, out, cref.role);
            try appendSlice(allocator, out, ",\"primary\":");
            try appendSlice(allocator, out, if (cref.primary) "true" else "false");
            // RM-121 — resolved contact identity (empty on pre-RM-121
            // v2 rows; the Dart side treats "" as absent).
            try appendSlice(allocator, out, ",\"name\":");
            try writeJsonString(allocator, out, cref.name);
            try appendSlice(allocator, out, ",\"phone\":");
            try writeJsonString(allocator, out, cref.phone);
            try append(allocator, out, '}');
        }
        try append(allocator, out, ']');
    } else {
        try appendSlice(allocator, out, "null");
    }
    // RM-121 — resolved site address + work description (Home groups
    // by site → contact → description). null on rows without them.
    try appendSlice(allocator, out, ",\"propertyAddress\":");
    try writeOptStr(allocator, out, job.propertyAddress);
    try appendSlice(allocator, out, ",\"description\":");
    try writeOptStr(allocator, out, job.description);
    try appendSlice(allocator, out, ",\"attachmentRefs\":");
    if (job.attachmentRefs) |refs| {
        try append(allocator, out, '[');
        for (refs, 0..) |aref, i| {
            if (i != 0) try append(allocator, out, ',');
            try writeHex32String(allocator, out, &aref);
        }
        try append(allocator, out, ']');
    } else {
        try appendSlice(allocator, out, "null");
    }
    try append(allocator, out, '}');
}

/// Render a v1/v2 mixed-shape `Attachment` row to JSON.  v1 rows have
/// every v2 field `null`.
fn writeAttachment(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    att: attachments_store_fs.Attachment,
) QueryError!void {
    try appendSlice(allocator, out, "{\"id\":");
    try writeJsonString(allocator, out, att.id);
    try appendSlice(allocator, out, ",\"visit_id\":");
    try writeJsonString(allocator, out, att.visit_id);
    try appendSlice(allocator, out, ",\"kind\":");
    try writeJsonString(allocator, out, att.kind);
    try appendSlice(allocator, out, ",\"content_hash\":");
    try writeJsonString(allocator, out, att.content_hash);
    try appendSlice(allocator, out, ",\"content_size\":");
    try writeI64(allocator, out, att.content_size);
    try appendSlice(allocator, out, ",\"mime_type\":");
    try writeJsonString(allocator, out, att.mime_type);
    try appendSlice(allocator, out, ",\"captured_at\":");
    try writeJsonString(allocator, out, att.captured_at);
    try appendSlice(allocator, out, ",\"captured_by_cert_id\":");
    try writeJsonString(allocator, out, att.captured_by_cert_id);
    try appendSlice(allocator, out, ",\"caption\":");
    try writeJsonString(allocator, out, att.caption);
    try appendSlice(allocator, out, ",\"created_at\":");
    try writeJsonString(allocator, out, att.created_at);

    try appendSlice(allocator, out, ",\"cellId\":");
    if (att.cellId) |c| {
        try writeHex32String(allocator, out, &c);
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"typeHash\":");
    if (att.typeHash) |c| {
        try writeHex32String(allocator, out, &c);
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"jobRef\":");
    if (att.jobRef) |j| {
        try writeHex32String(allocator, out, &j);
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"sourceBlobKey\":");
    try writeOptStr(allocator, out, att.sourceBlobKey);
    try appendSlice(allocator, out, ",\"pageCount\":");
    if (att.pageCount) |p| {
        try writeI64(allocator, out, @intCast(p));
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"photoCount\":");
    if (att.photoCount) |p| {
        try writeI64(allocator, out, @intCast(p));
    } else {
        try appendSlice(allocator, out, "null");
    }
    try appendSlice(allocator, out, ",\"hasPhotos\":");
    try appendSlice(allocator, out, if (att.hasPhotos) "true" else "false");
    try append(allocator, out, '}');
}

// ─── Tiny appendable helpers ──────────────────────────────────────
//
// The std.ArrayList(u8) APIs need an explicit allocator; centralising
// the OOM-→QueryError mapping here keeps the writers above clear of
// per-call `catch` clauses.

fn append(allocator: std.mem.Allocator, out: *std.ArrayList(u8), c: u8) QueryError!void {
    out.append(allocator, c) catch return QueryError.out_of_memory;
}

fn appendSlice(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) QueryError!void {
    out.appendSlice(allocator, s) catch return QueryError.out_of_memory;
}

fn writeOptStr(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: ?[]const u8) QueryError!void {
    if (s) |v| {
        try writeJsonString(allocator, out, v);
    } else {
        try appendSlice(allocator, out, "null");
    }
}

fn writeJsonString(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    s: []const u8,
) QueryError!void {
    const encoded = std.json.Stringify.valueAlloc(allocator, s, .{}) catch return QueryError.out_of_memory;
    defer allocator.free(encoded);
    try appendSlice(allocator, out, encoded);
}

fn writeHex32String(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    bytes: *const [32]u8,
) QueryError!void {
    const hex = std.fmt.bytesToHex(bytes.*, .lower);
    try append(allocator, out, '"');
    try appendSlice(allocator, out, hex[0..]);
    try append(allocator, out, '"');
}

fn writeI64(allocator: std.mem.Allocator, out: *std.ArrayList(u8), v: i64) QueryError!void {
    var buf: [24]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{d}", .{v}) catch return QueryError.out_of_memory;
    try appendSlice(allocator, out, slice);
}

// ── C4 PR-J2 — public single-element encoders for the cell.query decoder ──
//
// Wrap the private writeX encoders so the cartridge's cell-decoder registration
// (registration.zig) can turn one typed record into its JSON element — the same
// per-record shape cell.query's arrays + cell.get's singular result carry.
// Caller owns the returned slice.

pub fn jobToJson(allocator: std.mem.Allocator, job: jobs_store_fs.Job) QueryError![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    try writeJob(allocator, &buf, job);
    return buf.toOwnedSlice(allocator) catch return QueryError.out_of_memory;
}

pub fn siteToJson(allocator: std.mem.Allocator, site: sites_store_fs.Site) QueryError![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    try writeSite(allocator, &buf, site);
    return buf.toOwnedSlice(allocator) catch return QueryError.out_of_memory;
}

pub fn customerToJson(allocator: std.mem.Allocator, cust: customers_store_fs.Customer) QueryError![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    try writeCustomer(allocator, &buf, cust);
    return buf.toOwnedSlice(allocator) catch return QueryError.out_of_memory;
}

pub fn attachmentToJson(allocator: std.mem.Allocator, att: attachments_store_fs.Attachment) QueryError![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    try writeAttachment(allocator, &buf, att);
    return buf.toOwnedSlice(allocator) catch return QueryError.out_of_memory;
}

```
