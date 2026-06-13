---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/oddjobz_ratify_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.546603+00:00
---

# cartridges/oddjobz/brain/zig/src/oddjobz_ratify_handler.zig

```zig
// D-DOG.1.0c Phase 2A.4 — Layer-2 ratify seam, graph-walk rewrite.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 2
//            row C.1 (this PR);
//            cartridges/oddjobz/brain/src/cell-types/{site,customer,job,
//              attachment}.v2.ts (the canonical schemas this handler
//              mirrors when minting graph rows);
//            runtime/semantos-brain/src/{sites,customers,jobs,attachments}_store_fs
//              .zig (the four typed view-stores this handler writes to).
//
// What changed in Phase 2A.4 (vs. the Phase 1.0b' ancestor):
//
//   • The handler used to dispatch each ratifiable SIR-action through
//     `dispatcher.dispatch("jobs", "create", ...)` and return a single
//     `{cell_ids: [<job-id>]}` array.
//   • Phase 2A.4 holds direct pointers to the four typed view-stores
//     (sites, customers, jobs, attachments) and walks each ratifiable
//     SIR-action into a graph of cells:
//
//       1. Site         — derive lookupKey via normaliseAddress + the
//                         `<normAddress>|<keyNumber-or-empty>` shape
//                         (mirrors site.v2.ts `deriveLookupKey`); call
//                         `sites_store.findByLookupKey` → mint via
//                         `sites_store.appendCreated` if absent.
//       2. Customer(s)  — for each contact (primary + secondaries),
//                         derive a CustomerDedupeKey (precedence:
//                         phone → email → name+role+site); call
//                         `customers_store.findByDedupeKey` → mint via
//                         `customers_store.appendCreatedV2` if absent.
//       3. Job          — always mint via
//                         `jobs_store.appendCreatedV2`; populate
//                         siteRef + customerRefs[] + workOrderNumber +
//                         issuanceDate + dueDate + propertyKey +
//                         hasPhotos + photoCount + billingParty.
//       4. Attachments  — mint one per source PDF via
//                         `attachments_store.appendV2` linked to the
//                         job's cellId.
//
//   • Return shape changed from `cell_ids: []const []const u8` to a
//     graph: `{site, customers[], job, attachments[]}` of 32-byte
//     content-hash hex strings.  The wss_wallet endpoint serialises
//     the graph as `cellIds: { site, customers, job, attachments }`.
//
//   • Idempotency lives at TWO levels:
//
//       a. Per-proposal: the ratifications-log file
//          `<data_dir>/oddjobz/ratifications.jsonl` records the graph
//          shape for each `proposal_id`; a repeat ratify on the same
//          proposal_id returns the recorded graph unchanged (no store
//          writes happen at all).
//       b. Per-cell: the lookup-or-mint helpers on each store
//          dedupe by their canonical key (lookupKey on sites,
//          dedupeKey on customers; jobs/attachments mint fresh every
//          time with content-addressed cellIDs that collide naturally
//          when the canonical payload is byte-equal).
//
// CellID derivation (this PR): SHA-256 of a deterministic byte string
// built from the cell's load-bearing fields (mirrors what TS' canonical
// JSON encoder would produce for the same inputs, modulo cross-language
// byte-parity which Phase 2B's TS-side rewrite enforces with a vector
// oracle).  The Zig-side cellID is deterministic for a given input
// shape, which is what backs the per-cell idempotency property: re-
// ratifying a proposal that's already been ratified collapses onto the
// same cellIDs through the proposal-level cache (level (a) above), and
// minting through equivalent SIR shapes converges onto the same site /
// customer cells through the lookup-or-mint dedupe (level (b)).
//
// Customer.v2 UUID-vs-cellID resolution:
//
//   The cell-types/customer.v2.ts schema requires `customerId: assertUuid(...)`
//   on the customer cell payload.  Graph linking uses content-hash
//   cellIDs.  These are TWO distinct identifiers per customer cell:
//
//     • `customerId` (UUID v4)            — schema-internal handle on
//                                           the customer cell payload.
//     • `cellId`     (32-byte content     — the cell-DAG primary key
//                     hash, hex)           the job's customerRefs[]
//                                           reference.
//
//   The handler mints a fresh deterministic UUID v5-shape (derived
//   from the cellId so the customerId is reproducible across replays
//   of the same SIR) for `customerId`, and the cellID via
//   content-hash.  Both go onto the customer cell payload.  The job's
//   `customerRefs[].cellId` references the cellID, NOT the UUID.  The
//   customers_store's by_id index keys on the v1 `id` (we set this to
//   the deterministic UUID), and the by_cell_id index keys on the
//   cellID — both indices populate so legacy v1 find-by-id paths
//   continue to work alongside the new graph-aware getByCellId path.
//
// Cells are minted unsigned (signedBy: null, signature: null).  Phase
// 4 retrofits BKDS signing via `brain resign-pending`; per the Option II
// ordering in the matrix, signing lands AFTER the graph-walk + the
// cross-store query handler, so the operator can dogfood the graph
// shape end-to-end before the BKDS surface lights up.

const std = @import("std");
const sites_store_fs = @import("sites_store_fs");
const customers_store_fs = @import("customers_store_fs");
const jobs_store_fs = @import("jobs_store_fs");
const attachments_store_fs = @import("attachments_store_fs");
// D-DOG.1.0c Phase 2B.4 — pure-derivation surface (separator-string
// SHA-256 + UUID-shape from cellID + address normalisation). Extracted
// so the cross-language parity oracle test can drive these without
// pulling in the full ratify handler's I/O scaffolding.
const oddjobz_derivations = @import("oddjobz_derivations.zig");
// D-DOG.1.0c Phase 4 row B.2 — derive-then-sign each cell before
// persistence.  The signer is optional: legacy unit tests + the
// no-hat-key paths leave it null, in which case minted cells go to
// the view stores with `signedBy: null` (the Phase 2A.4 behaviour),
// and `brain resign-pending` (B.4) backfills them later.
const hat_bkds = @import("hat_bkds");
// C4 — oddjobz signs its cells under its own BKDS derivation scope.
const oddjobz_scope = @import("oddjobz_scope");

/// Errors specific to ratify-time validation + graph-mint.  Caller
/// (wss_wallet) maps each to a JSON-RPC error.
pub const RatifyError = error{
    /// `params` JSON failed to parse, was not an object, or was
    /// missing one of `proposal_id` / `sir_program`.
    invalid_params,
    /// `proposal_id` was empty or exceeded the length envelope.
    invalid_proposal_id,
    /// SIRProgram failed minimal shape validation (no `nodes` array,
    /// no primary node, etc.).
    invalid_sir_program,
    /// SIRProgram contained no nodes whose `action` mapped to a
    /// known oddjobz cell-type.
    unsupported_action,
    /// One of the four view-stores rejected an append (length-
    /// envelope / enum / shape error).  The audit log captures the
    /// underlying cause; the wire layer surfaces the generic shape.
    store_append_failed,
    /// Ratifications-log persist failed.
    persist_failed,
    out_of_memory,
};

/// Graph result returned by `handleRatify`.  All hex strings are
/// 64-character lowercase (32-byte content-hash cellIDs).
///
/// Ownership: every byte slice on this struct is owned by `allocator`
/// and freed by `deinit`.
pub const RatifyResult = struct {
    proposal_id: []u8,
    /// Site cell's content-hash hex (always non-null on a successful
    /// graph-mint; null only if NO ratifiable action produced a graph,
    /// in which case the result is "ratification recorded but
    /// produced no cells" — see the no-op SIRProgram path).
    site_cell_id: ?[]u8,
    /// Customer cells' content-hash hex (zero or more).  Zero is a
    /// coherent corner case (an SIR that names a property + work order
    /// but no contacts).
    customer_cell_ids: []const []const u8,
    /// Job cell's content-hash hex (non-null when the SIR produced any
    /// ratifiable action; null on the noop / attach_reply path).
    job_cell_id: ?[]u8,
    /// Attachment cells' content-hash hex (zero or more).
    attachment_cell_ids: []const []const u8,
    persisted_at: i64,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *RatifyResult) void {
        self.allocator.free(self.proposal_id);
        if (self.site_cell_id) |s| self.allocator.free(s);
        for (self.customer_cell_ids) |c| self.allocator.free(c);
        self.allocator.free(@constCast(self.customer_cell_ids));
        if (self.job_cell_id) |s| self.allocator.free(s);
        for (self.attachment_cell_ids) |c| self.allocator.free(c);
        self.allocator.free(@constCast(self.attachment_cell_ids));
    }
};

/// Owned-string graph shape used for the in-memory idempotency map.
/// Each string is its own `allocator.dupe` allocation so re-clone on a
/// repeat-ratify can split off into a caller-owned RatifyResult
/// independently of the handler's lifetime.
const GraphRecord = struct {
    site_cell_id: ?[]u8,
    customer_cell_ids: [][]u8,
    job_cell_id: ?[]u8,
    attachment_cell_ids: [][]u8,
    persisted_at: i64,

    fn freeAll(self: *GraphRecord, allocator: std.mem.Allocator) void {
        if (self.site_cell_id) |s| allocator.free(s);
        for (self.customer_cell_ids) |c| allocator.free(c);
        allocator.free(self.customer_cell_ids);
        if (self.job_cell_id) |s| allocator.free(s);
        for (self.attachment_cell_ids) |c| allocator.free(c);
        allocator.free(self.attachment_cell_ids);
    }
};

/// Bag of view-store pointers the handler holds for its lifetime.
/// All four MUST outlive the handler; the daemon's `cmdServe` builds
/// them once and passes the bag in.  Best-effort fields are `?*`-typed
/// so a partial bring-up (e.g. one store failed to open) leaves
/// graph-walk degraded but doesn't crash the daemon — the handler
/// surfaces `store_append_failed` for any store it lacks.
pub const RatifyStores = struct {
    sites: ?*sites_store_fs.SitesStore = null,
    customers: ?*customers_store_fs.CustomersStore = null,
    jobs: ?*jobs_store_fs.JobsStore = null,
    attachments: ?*attachments_store_fs.AttachmentsStore = null,
    /// D-DOG.1.0c Phase 4 row B.2 — optional BKDS signer.  When set,
    /// each minted cell is signed (derive-then-sign-then-discard) and
    /// its `signedBy` + `signature` fields are populated before the
    /// view-store row is appended.  When null, cells are minted
    /// unsigned (Phase 2A.4 behaviour) and `brain resign-pending` (B.4)
    /// can backfill the signing layer over them later.
    hat_bkds: ?*hat_bkds.HatBkds = null,
};

pub const Handler = struct {
    allocator: std.mem.Allocator,
    stores: RatifyStores,
    log_path: []u8,
    /// proposal_id → recorded graph; rebuilt at init by replaying the
    /// log.  Map keys live in `key_storage`.
    ratifications: std.StringHashMap(GraphRecord),
    key_storage: std.ArrayList([]u8),
    mu: std.Thread.Mutex,
    /// Server-side clock injection (for deterministic tests).  Real
    /// callers pass `realClock` from cli.zig; tests pass a pinned
    /// constant.
    clock: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        stores: RatifyStores,
        data_dir: []const u8,
        clock_fn: *const fn () i64,
    ) !Handler {
        const oddjobz_dir = try std.fs.path.join(allocator, &.{ data_dir, "oddjobz" });
        defer allocator.free(oddjobz_dir);
        std.fs.cwd().makePath(oddjobz_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return RatifyError.persist_failed,
        };
        const log_path = try std.fs.path.join(allocator, &.{ oddjobz_dir, "ratifications.jsonl" });
        errdefer allocator.free(log_path);

        var self = Handler{
            .allocator = allocator,
            .stores = stores,
            .log_path = log_path,
            .ratifications = std.StringHashMap(GraphRecord).init(allocator),
            .key_storage = .{},
            .mu = .{},
            .clock = clock_fn,
        };
        try self.replay();
        return self;
    }

    pub fn deinit(self: *Handler) void {
        var it = self.ratifications.valueIterator();
        while (it.next()) |v| v.freeAll(self.allocator);
        self.ratifications.deinit();
        for (self.key_storage.items) |k| self.allocator.free(k);
        self.key_storage.deinit(self.allocator);
        self.allocator.free(self.log_path);
    }

    fn replay(self: *Handler) !void {
        const file = std.fs.openFileAbsolute(self.log_path, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return RatifyError.persist_failed,
        };
        defer file.close();

        const stat = file.stat() catch return RatifyError.persist_failed;
        if (stat.size == 0) return;
        const bytes = self.allocator.alloc(u8, stat.size) catch return RatifyError.out_of_memory;
        defer self.allocator.free(bytes);
        const read = file.readAll(bytes) catch return RatifyError.persist_failed;
        const slice = bytes[0..read];

        var it = std.mem.splitScalar(u8, slice, '\n');
        while (it.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len == 0) continue;
            self.replayOne(line) catch |err| switch (err) {
                RatifyError.invalid_params,
                RatifyError.invalid_proposal_id,
                RatifyError.invalid_sir_program,
                error.OutOfMemory => continue,
                else => return err,
            };
        }
    }

    fn replayOne(self: *Handler, line: []const u8) !void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, line, .{}) catch return RatifyError.invalid_params;
        defer parsed.deinit();
        if (parsed.value != .object) return RatifyError.invalid_params;
        const obj = parsed.value.object;

        const pid_v = obj.get("proposal_id") orelse return RatifyError.invalid_params;
        if (pid_v != .string or pid_v.string.len == 0) return RatifyError.invalid_proposal_id;
        const persisted_v = obj.get("persisted_at") orelse return RatifyError.invalid_params;
        if (persisted_v != .integer) return RatifyError.invalid_params;

        // Graph fields — all optional in the log shape so a future
        // forward-compat field bump doesn't break replay.
        const site_id: ?[]u8 = if (obj.get("site")) |v| switch (v) {
            .string => |s| try self.allocator.dupe(u8, s),
            else => null,
        } else null;
        errdefer if (site_id) |s| self.allocator.free(s);

        var customer_ids: std.ArrayList([]u8) = .{};
        errdefer {
            for (customer_ids.items) |c| self.allocator.free(c);
            customer_ids.deinit(self.allocator);
        }
        if (obj.get("customers")) |v| switch (v) {
            .array => |arr| for (arr.items) |item| {
                if (item != .string) continue;
                const dup = try self.allocator.dupe(u8, item.string);
                try customer_ids.append(self.allocator, dup);
            },
            else => {},
        };

        const job_id: ?[]u8 = if (obj.get("job")) |v| switch (v) {
            .string => |s| try self.allocator.dupe(u8, s),
            else => null,
        } else null;
        errdefer if (job_id) |s| self.allocator.free(s);

        var attachment_ids: std.ArrayList([]u8) = .{};
        errdefer {
            for (attachment_ids.items) |c| self.allocator.free(c);
            attachment_ids.deinit(self.allocator);
        }
        if (obj.get("attachments")) |v| switch (v) {
            .array => |arr| for (arr.items) |item| {
                if (item != .string) continue;
                const dup = try self.allocator.dupe(u8, item.string);
                try attachment_ids.append(self.allocator, dup);
            },
            else => {},
        };

        const customer_owned = try customer_ids.toOwnedSlice(self.allocator);
        errdefer {
            for (customer_owned) |c| self.allocator.free(c);
            self.allocator.free(customer_owned);
        }
        const attachment_owned = try attachment_ids.toOwnedSlice(self.allocator);
        errdefer {
            for (attachment_owned) |c| self.allocator.free(c);
            self.allocator.free(attachment_owned);
        }

        const key_owned = try self.allocator.dupe(u8, pid_v.string);
        errdefer self.allocator.free(key_owned);
        try self.key_storage.append(self.allocator, key_owned);

        try self.ratifications.put(key_owned, .{
            .site_cell_id = site_id,
            .customer_cell_ids = customer_owned,
            .job_cell_id = job_id,
            .attachment_cell_ids = attachment_owned,
            .persisted_at = persisted_v.integer,
        });
    }

    /// Ratify entry point.  See module head for graph semantics.
    pub fn handleRatify(
        self: *Handler,
        allocator: std.mem.Allocator,
        params_json: []const u8,
    ) RatifyError!RatifyResult {
        self.mu.lock();
        defer self.mu.unlock();

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch return RatifyError.invalid_params;
        defer parsed.deinit();
        if (parsed.value != .object) return RatifyError.invalid_params;
        const obj = parsed.value.object;

        const pid_v = obj.get("proposal_id") orelse return RatifyError.invalid_params;
        if (pid_v != .string) return RatifyError.invalid_proposal_id;
        if (pid_v.string.len == 0 or pid_v.string.len > MAX_PROPOSAL_ID_BYTES) return RatifyError.invalid_proposal_id;
        const proposal_id = pid_v.string;

        // Idempotency hit: re-clone the recorded graph and return.
        if (self.ratifications.get(proposal_id)) |existing| {
            return self.cloneExisting(allocator, proposal_id, existing);
        }

        const sir_v = obj.get("sir_program") orelse return RatifyError.invalid_params;
        if (sir_v != .object) return RatifyError.invalid_sir_program;
        const nodes_v = sir_v.object.get("nodes") orelse return RatifyError.invalid_sir_program;
        if (nodes_v != .array) return RatifyError.invalid_sir_program;
        if (nodes_v.array.items.len == 0) return RatifyError.invalid_sir_program;

        // Whether this SIR contains any ratifiable action at all.  A
        // pure noop / attach_reply SIR persists an empty graph (no
        // cells) so the proposal_id stays idempotent — re-ratifying
        // returns "no cells" rather than re-walking.
        var has_ratifiable = false;
        for (nodes_v.array.items) |node_v| {
            if (node_v != .object) continue;
            const action_v = node_v.object.get("action") orelse continue;
            if (action_v != .string) continue;
            if (isRatifiableAction(action_v.string)) {
                has_ratifiable = true;
                break;
            }
        }

        // Read the payload_hint.  Phase 2A.4 reads BOTH the legacy
        // (customer_name / point_of_contact / summary / reference_
        // number / source_provider_id) AND the Tier 1.7 enriched
        // fields (primaryContact / secondaryContacts / propertyAddress
        // / propertyKey / ownerName / billingParty / workOrderNumber /
        // issuanceDate / dueDate / hasPhotos / photoCount /
        // sourceAttachmentPath).  Phase 2B's TS-side rewrite of
        // brain-rpc.ts will populate the enriched fields; until then
        // they're absent and the handler falls back to the legacy
        // shape.
        const hint = parsePayloadHint(obj.get("payload_hint"));

        // Build the graph.  No ratifiable action → empty graph (the
        // noop / attach_reply path).
        var graph: BuildResult = .{};
        if (has_ratifiable) {
            graph = self.buildGraph(allocator, hint) catch |err| switch (err) {
                error.OutOfMemory => return RatifyError.out_of_memory,
                else => return RatifyError.store_append_failed,
            };
        }
        // graph_owns_strings: every []u8 in `graph` is owned by
        // `allocator`; on any error path below we MUST free them.
        errdefer freeBuildResult(allocator, &graph);

        // Persist the graph to the ratifications log + the in-memory
        // map BEFORE returning.  A crash between here and the wire
        // response would leave the cells minted but the proposal not
        // recorded — re-ratifying would then dedupe at the per-cell
        // level (lookupKey + dedupeKey gates) but mint a fresh job
        // cell.  That's a tolerable race; the alternative (writing
        // the ratifications log first) leaves the cells un-minted on
        // a mid-process crash.  This phase prefers "cells minted, may
        // duplicate-job-on-restart-crash" because the per-proposal
        // idempotency cache is a UX guard, not a correctness invariant
        // (the per-cell dedupe is the correctness invariant).
        const persisted_at = self.clock();
        self.appendLog(allocator, proposal_id, &graph, persisted_at) catch {
            return RatifyError.persist_failed;
        };

        // Move the strings into the in-memory map (re-dupe so the
        // result and the map have independent ownership).
        const recorded = try self.recordGraph(proposal_id, &graph, persisted_at);
        _ = recorded;

        // Construct the caller-owned RatifyResult.
        const proposal_id_owned = allocator.dupe(u8, proposal_id) catch return RatifyError.out_of_memory;
        return RatifyResult{
            .proposal_id = proposal_id_owned,
            .site_cell_id = graph.site_cell_id,
            .customer_cell_ids = takeOwnedSlice(allocator, &graph.customer_cell_ids),
            .job_cell_id = graph.job_cell_id,
            .attachment_cell_ids = takeOwnedSlice(allocator, &graph.attachment_cell_ids),
            .persisted_at = persisted_at,
            .allocator = allocator,
        };
    }

    /// Construct a RatifyResult from a recorded GraphRecord by
    /// re-duplicating each owned string into the caller's allocator.
    fn cloneExisting(
        self: *Handler,
        allocator: std.mem.Allocator,
        proposal_id: []const u8,
        existing: GraphRecord,
    ) RatifyError!RatifyResult {
        _ = self;
        const proposal_id_owned = allocator.dupe(u8, proposal_id) catch return RatifyError.out_of_memory;
        errdefer allocator.free(proposal_id_owned);

        const site_id_owned: ?[]u8 = if (existing.site_cell_id) |s|
            (allocator.dupe(u8, s) catch return RatifyError.out_of_memory)
        else
            null;
        errdefer if (site_id_owned) |s| allocator.free(s);

        const customers_buf = allocator.alloc([]const u8, existing.customer_cell_ids.len) catch return RatifyError.out_of_memory;
        var customers_filled: usize = 0;
        errdefer {
            for (customers_buf[0..customers_filled]) |c| allocator.free(@constCast(c));
            allocator.free(customers_buf);
        }
        for (existing.customer_cell_ids, 0..) |c, i| {
            const dup = allocator.dupe(u8, c) catch return RatifyError.out_of_memory;
            customers_buf[i] = dup;
            customers_filled += 1;
        }

        const job_id_owned: ?[]u8 = if (existing.job_cell_id) |s|
            (allocator.dupe(u8, s) catch return RatifyError.out_of_memory)
        else
            null;
        errdefer if (job_id_owned) |s| allocator.free(s);

        const attachments_buf = allocator.alloc([]const u8, existing.attachment_cell_ids.len) catch return RatifyError.out_of_memory;
        var attachments_filled: usize = 0;
        errdefer {
            for (attachments_buf[0..attachments_filled]) |c| allocator.free(@constCast(c));
            allocator.free(attachments_buf);
        }
        for (existing.attachment_cell_ids, 0..) |c, i| {
            const dup = allocator.dupe(u8, c) catch return RatifyError.out_of_memory;
            attachments_buf[i] = dup;
            attachments_filled += 1;
        }

        return RatifyResult{
            .proposal_id = proposal_id_owned,
            .site_cell_id = site_id_owned,
            .customer_cell_ids = customers_buf,
            .job_cell_id = job_id_owned,
            .attachment_cell_ids = attachments_buf,
            .persisted_at = existing.persisted_at,
            .allocator = allocator,
        };
    }

    // ── graph build ────────────────────────────────────────────────

    /// Walk the parsed payload_hint into a graph of cells.  Returns a
    /// BuildResult whose strings are all owned by `allocator`; the
    /// caller MUST `freeBuildResult` on every error path.
    /// D-DOG.1.0c Phase 4 row B.2 — sign one cellId via the BKDS
    /// signer if attached.  Returns `null` when no signer is wired in
    /// (legacy unsigned path), or a typed RatifyError on derivation /
    /// signing failure.  The cellId is used as both the canonical
    /// payload AND the keyID — since cellId is itself the SHA-256 of
    /// the cell's load-bearing fields (per oddjobz_derivations.zig),
    /// signing the cellId is functionally equivalent to signing the
    /// canonical-bytes the cellId was derived from.  The verifier
    /// reaches the same content_hash via SHA-256(cellId) too, so the
    /// (root, cellId) pair is fully recoverable.
    fn signOne(self: *Handler, cell_id: [32]u8) RatifyError!?struct { signedBy: [33]u8, signature: [64]u8 } {
        const signer = self.stores.hat_bkds orelse return null;
        const signed = signer.signCellScoped(
            &cell_id,
            &cell_id,
            oddjobz_scope.CELL_SIGN_PROTOCOL_ID,
            hat_bkds.CONTEXT_TAG_CELL_SIGN,
        ) catch {
            std.debug.print("[ratify] signOne: signCell failed — minting unsigned\n", .{});
            return null;
        };
        return .{ .signedBy = signed.derived_pubkey, .signature = signed.signature };
    }

    fn buildGraph(self: *Handler, allocator: std.mem.Allocator, hint: PayloadHint) !BuildResult {
        var out: BuildResult = .{};
        errdefer freeBuildResult(allocator, &out);
        std.debug.print("[ratify] buildGraph: entered hat_bkds={}\n", .{self.stores.hat_bkds != null});

        // Stores must all be present for a graph build.
        if (self.stores.sites == null) {
            std.debug.print("[ratify] buildGraph: sites store is null\n", .{});
            return RatifyError.store_append_failed;
        }
        if (self.stores.customers == null) {
            std.debug.print("[ratify] buildGraph: customers store is null\n", .{});
            return RatifyError.store_append_failed;
        }
        if (self.stores.jobs == null) {
            std.debug.print("[ratify] buildGraph: jobs store is null\n", .{});
            return RatifyError.store_append_failed;
        }
        const sites = self.stores.sites.?;
        const customers = self.stores.customers.?;
        const jobs = self.stores.jobs.?;
        // attachments is optional — a SIR without a sourceAttachmentPath
        // doesn't need to mint any attachment rows.

        // ── Site lookup-or-mint ────────────────────────────────────
        const site_full_address = if (hint.property_address) |a| a else hint.customer_name;
        const site_normalised_owned = try normaliseAddress(allocator, site_full_address);
        defer allocator.free(site_normalised_owned);
        const site_lookup_key_owned = try deriveLookupKey(allocator, site_normalised_owned, hint.property_key);
        defer allocator.free(site_lookup_key_owned);

        const site_type_hash = computeSiteTypeHash();
        const site_cell_id: [32]u8 = blk: {
            if (sites.findByLookupKey(site_lookup_key_owned)) |existing| {
                break :blk existing.cellId;
            }
            // Mint fresh.  D-DOG.1.0c Phase 4 row B.2 — sign the
            // cellId with a freshly derived BKDS key before the row
            // hits disk; if no signer is wired the row stays unsigned
            // (Phase 2A.4 fallback).
            const cid = computeSiteCellId(site_normalised_owned, hint.property_key, site_full_address);
            std.debug.print("[ratify] signOne(site) start\n", .{});
            const sig = self.signOne(cid) catch |se| {
                std.debug.print("[ratify] signOne(site) failed: {s}\n", .{@errorName(se)});
                return RatifyError.store_append_failed;
            };
            std.debug.print("[ratify] site.appendCreated normalised='{s}' full='{s}' key={?s}\n", .{ site_normalised_owned, site_full_address, hint.property_key });
            _ = sites.appendCreated(.{
                .cellId = cid,
                .typeHash = site_type_hash,
                .normalisedAddress = site_normalised_owned,
                .keyNumber = hint.property_key,
                .lookupKey = site_lookup_key_owned,
                .fullAddress = site_full_address,
                .suburb = null,
                .postcode = null,
                .state = null,
                .signedBy = if (sig) |s| s.signedBy else null,
                .signature = if (sig) |s| s.signature else null,
            }) catch |e| {
                std.debug.print("[ratify] site.appendCreated failed: {s}\n", .{@errorName(e)});
                return RatifyError.store_append_failed;
            };
            break :blk cid;
        };
        out.site_cell_id = try hexAlloc(allocator, &site_cell_id);

        // ── Customer lookup-or-mint (primary + secondaries) ────────
        const customer_type_hash = computeCustomerTypeHash();
        const created_at_str = self.formatTimestampMs(allocator) catch return RatifyError.out_of_memory;
        defer allocator.free(created_at_str);
        const provider_id = if (hint.source_provider_id.len > 0) hint.source_provider_id else "unknown";
        const provider_item_id = if (hint.reference_number.len > 0) hint.reference_number else "ratify";

        var customer_refs_arr: std.ArrayList(jobs_store_fs.CustomerRef) = .{};
        defer customer_refs_arr.deinit(allocator);

        std.debug.print("[ratify] customers start hint_primary={} poc_len={d} name_len={d}\n", .{ hint.primary_contact != null, hint.point_of_contact.len, hint.customer_name.len });
        if (hint.primary_contact) |pc| {
            const cid = try self.lookupOrMintCustomer(
                allocator,
                customers,
                pc,
                true,
                site_cell_id,
                customer_type_hash,
                created_at_str,
                provider_id,
                provider_item_id,
            );
            try customer_refs_arr.append(allocator, .{
                .cellId = cid,
                .role = customerRoleString(pc.role),
                .primary = true,
            });
            const hex = try hexAlloc(allocator, &cid);
            try out.customer_cell_ids.append(allocator, hex);
        } else if (hint.point_of_contact.len > 0 or hint.customer_name.len > 0) {
            // Legacy fallback: synthesise a primary contact from
            // point_of_contact (Tier 1.6 field) or customer_name
            // (Phase 1.0 field).
            const display = if (hint.point_of_contact.len > 0) hint.point_of_contact else hint.customer_name;
            const synth = ContactInput{
                .name = display,
                .role = .agent,
                .phone = null,
                .email = null,
            };
            const cid = try self.lookupOrMintCustomer(
                allocator,
                customers,
                synth,
                true,
                site_cell_id,
                customer_type_hash,
                created_at_str,
                provider_id,
                provider_item_id,
            );
            try customer_refs_arr.append(allocator, .{
                .cellId = cid,
                .role = customerRoleString(.agent),
                .primary = true,
            });
            const hex = try hexAlloc(allocator, &cid);
            try out.customer_cell_ids.append(allocator, hex);
        }

        for (hint.secondary_contacts) |sc| {
            const cid = try self.lookupOrMintCustomer(
                allocator,
                customers,
                sc,
                false,
                site_cell_id,
                customer_type_hash,
                created_at_str,
                provider_id,
                provider_item_id,
            );
            try customer_refs_arr.append(allocator, .{
                .cellId = cid,
                .role = customerRoleString(sc.role),
                .primary = false,
            });
            const hex = try hexAlloc(allocator, &cid);
            try out.customer_cell_ids.append(allocator, hex);
        }

        // ── Job mint (always fresh) ────────────────────────────────
        const job_type_hash = computeJobTypeHash();
        const job_display_name: []const u8 = if (hint.point_of_contact.len > 0)
            hint.point_of_contact
        else if (hint.customer_name.len > 0)
            hint.customer_name
        else
            "(untitled lead)";
        const job_cell_id = computeJobCellId(
            site_cell_id,
            customer_refs_arr.items,
            hint.work_order_number,
            hint.issuance_date,
            hint.due_date,
            created_at_str,
            job_display_name,
        );
        const billing_party: ?jobs_store_fs.BillingParty = if (hint.billing_party_name) |bp_name|
            .{ .type = if (hint.billing_party_type) |bt| bt else "agency", .name = bp_name }
        else
            null;
        // D-DOG.1.0c Phase 4 row B.2 — sign the job cell.
        std.debug.print("[ratify] signOne(job) start name='{s}' nrefs={d}\n", .{ job_display_name, customer_refs_arr.items.len });
        const job_sig = self.signOne(job_cell_id) catch |je| {
            std.debug.print("[ratify] signOne(job) failed: {s}\n", .{@errorName(je)});
            return RatifyError.store_append_failed;
        };
        std.debug.print("[ratify] jobs.appendCreatedV2 start\n", .{});
        _ = jobs.appendCreatedV2(.{
            .cellId = job_cell_id,
            .typeHash = job_type_hash,
            .customer_name = job_display_name,
            .state = "lead",
            .scheduled_at = "",
            .created_at = created_at_str,
            .workOrderNumber = if (hint.work_order_number.len > 0) hint.work_order_number else null,
            .issuanceDate = if (hint.issuance_date.len > 0) hint.issuance_date else null,
            .dueDate = if (hint.due_date.len > 0) hint.due_date else null,
            .billingParty = billing_party,
            .hasPhotos = hint.has_photos,
            .photoCount = if (hint.photo_count) |c| c else null,
            .propertyKey = hint.property_key,
            .siteRef = site_cell_id,
            .customerRefs = customer_refs_arr.items,
            .attachmentRefs = &.{},
            .signedBy = if (job_sig) |s| s.signedBy else null,
            .signature = if (job_sig) |s| s.signature else null,
        }) catch |je| {
            std.debug.print("[ratify] jobs.appendCreatedV2 failed: {s}\n", .{@errorName(je)});
            return RatifyError.store_append_failed;
        };
        std.debug.print("[ratify] jobs.appendCreatedV2 ok\n", .{});
        out.job_cell_id = try hexAlloc(allocator, &job_cell_id);

        // ── Attachment mint (one per source PDF, optional) ─────────
        if (self.stores.attachments) |atts| {
            if (hint.source_attachment_path.len > 0) {
                const att_type_hash = computeAttachmentTypeHash();
                const att_cell_id = computeAttachmentCellId(
                    job_cell_id,
                    hint.source_attachment_path,
                    created_at_str,
                );
                const att_uuid = try uuidV5LikeFromBytes(allocator, &att_cell_id);
                defer allocator.free(att_uuid);
                // D-DOG.1.0c Phase 4 row B.2 — sign the attachment cell.
                const att_sig = try self.signOne(att_cell_id);
                _ = atts.appendV2(.{
                    .id = att_uuid,
                    .visit_id = "",
                    .kind = "",
                    .content_hash = "",
                    .content_size = 0,
                    .mime_type = "application/pdf",
                    .captured_at = "",
                    .captured_by_cert_id = "",
                    .caption = "",
                    .created_at = created_at_str,
                    .cellId = att_cell_id,
                    .typeHash = att_type_hash,
                    .jobRef = job_cell_id,
                    .sourceBlobKey = hint.source_attachment_path,
                    .pageCount = null,
                    .photoCount = if (hint.photo_count) |c| c else null,
                    .hasPhotos = hint.has_photos,
                    .signedBy = if (att_sig) |s| s.signedBy else null,
                    .signature = if (att_sig) |s| s.signature else null,
                }) catch return RatifyError.store_append_failed;
                const hex = try hexAlloc(allocator, &att_cell_id);
                try out.attachment_cell_ids.append(allocator, hex);
            }
        }

        return out;
    }

    /// Lookup-or-mint one customer cell.  Precedence on dedupe:
    /// phone → email → (name, role, site).  Returns the cellID of the
    /// found-or-minted row.
    fn lookupOrMintCustomer(
        self: *Handler,
        allocator: std.mem.Allocator,
        customers: *customers_store_fs.CustomersStore,
        contact: ContactInput,
        primary: bool,
        site_cell_id: [32]u8,
        type_hash: [32]u8,
        created_at: []const u8,
        provider_id: []const u8,
        provider_item_id: []const u8,
    ) !([32]u8) {
        _ = primary;
        const role = contact.role;
        const role_str = customerRoleString(role);

        // Phone → email → name+role+site lookup ladder.
        if (contact.phone) |phone| {
            if (phone.len > 0) {
                if (customers.findByDedupeKey(.{ .phone = phone })) |existing| {
                    if (existing.cellId) |c| return c;
                }
            }
        }
        if (contact.email) |email| {
            if (email.len > 0) {
                if (customers.findByDedupeKey(.{ .email = email })) |existing| {
                    if (existing.cellId) |c| return c;
                }
            }
        }
        if (contact.name.len > 0) {
            if (customers.findByDedupeKey(.{
                .nameRoleAndSite = .{
                    .name = contact.name,
                    .role = role,
                    .siteRef = site_cell_id,
                },
            })) |existing| {
                if (existing.cellId) |c| return c;
            }
        }

        // Mint fresh.
        const phone_owned: []const u8 = contact.phone orelse "";
        const email_owned: []const u8 = contact.email orelse "";
        const cell_id = computeCustomerCellId(
            contact.name,
            role_str,
            site_cell_id,
            phone_owned,
            email_owned,
        );
        // Deterministic UUID v5-shape derived from the cellId so the
        // customer.v2 schema's `customerId: assertUuid(...)` constraint
        // is met AND the value is reproducible across replays.
        const customer_uuid = try uuidV5LikeFromBytes(allocator, &cell_id);
        defer allocator.free(customer_uuid);

        const normalised_phone: ?[]const u8 = if (phone_owned.len > 0) phone_owned else null;

        // D-DOG.1.0c Phase 4 row B.2 — sign the customer cell.
        std.debug.print("[ratify] signOne(customer) start name='{s}'\n", .{contact.name});
        const sig = self.signOne(cell_id) catch |se| {
            std.debug.print("[ratify] signOne(customer) failed: {s}\n", .{@errorName(se)});
            return se;
        };
        std.debug.print("[ratify] customers.appendCreatedV2 start\n", .{});
        _ = customers.appendCreatedV2(.{
            .id = customer_uuid,
            .display_name = contact.name,
            .phone = phone_owned,
            .email = email_owned,
            .address = "",
            .notes = "",
            .created_at = created_at,
            .cellId = cell_id,
            .typeHash = type_hash,
            .role = role,
            .normalisedPhone = normalised_phone,
            .sourceProvenance = .{
                .providerId = provider_id,
                .providerItemId = provider_item_id,
                .extractedAt = created_at,
            },
            .siteRef = site_cell_id,
            .signedBy = if (sig) |s| s.signedBy else null,
            .signature = if (sig) |s| s.signature else null,
        }) catch |ce| {
            std.debug.print("[ratify] customers.appendCreatedV2 failed: {s}\n", .{@errorName(ce)});
            return RatifyError.store_append_failed;
        };
        std.debug.print("[ratify] customers.appendCreatedV2 ok\n", .{});
        return cell_id;
    }

    fn appendLog(
        self: *Handler,
        scratch: std.mem.Allocator,
        proposal_id: []const u8,
        graph: *const BuildResult,
        persisted_at: i64,
    ) !void {
        var line: std.ArrayList(u8) = .{};
        defer line.deinit(scratch);
        try line.appendSlice(scratch, "{\"proposal_id\":");
        try writeJsonString(scratch, &line, proposal_id);
        try line.appendSlice(scratch, ",\"persisted_at\":");
        try line.print(scratch, "{d}", .{persisted_at});

        try line.appendSlice(scratch, ",\"site\":");
        if (graph.site_cell_id) |s| {
            try writeJsonString(scratch, &line, s);
        } else {
            try line.appendSlice(scratch, "null");
        }

        try line.appendSlice(scratch, ",\"customers\":[");
        for (graph.customer_cell_ids.items, 0..) |c, i| {
            if (i != 0) try line.append(scratch, ',');
            try writeJsonString(scratch, &line, c);
        }
        try line.appendSlice(scratch, "]");

        try line.appendSlice(scratch, ",\"job\":");
        if (graph.job_cell_id) |s| {
            try writeJsonString(scratch, &line, s);
        } else {
            try line.appendSlice(scratch, "null");
        }

        try line.appendSlice(scratch, ",\"attachments\":[");
        for (graph.attachment_cell_ids.items, 0..) |c, i| {
            if (i != 0) try line.append(scratch, ',');
            try writeJsonString(scratch, &line, c);
        }
        try line.appendSlice(scratch, "]}\n");

        var file = std.fs.openFileAbsolute(self.log_path, .{ .mode = .write_only }) catch |err| switch (err) {
            error.FileNotFound => std.fs.createFileAbsolute(self.log_path, .{ .truncate = false }) catch return RatifyError.persist_failed,
            else => return RatifyError.persist_failed,
        };
        defer file.close();
        file.seekFromEnd(0) catch return RatifyError.persist_failed;
        file.writeAll(line.items) catch return RatifyError.persist_failed;
        file.sync() catch {};
    }

    /// Move the graph into the in-memory map.  Re-dupes each string so
    /// ownership in the map is independent of the result struct the
    /// caller will receive.
    fn recordGraph(
        self: *Handler,
        proposal_id: []const u8,
        graph: *const BuildResult,
        persisted_at: i64,
    ) RatifyError!void {
        const allocator = self.allocator;
        const site_dup: ?[]u8 = if (graph.site_cell_id) |s|
            (allocator.dupe(u8, s) catch return RatifyError.out_of_memory)
        else
            null;
        errdefer if (site_dup) |s| allocator.free(s);

        const customers_buf = allocator.alloc([]u8, graph.customer_cell_ids.items.len) catch return RatifyError.out_of_memory;
        var customers_filled: usize = 0;
        errdefer {
            for (customers_buf[0..customers_filled]) |c| allocator.free(c);
            allocator.free(customers_buf);
        }
        for (graph.customer_cell_ids.items, 0..) |c, i| {
            const dup = allocator.dupe(u8, c) catch return RatifyError.out_of_memory;
            customers_buf[i] = dup;
            customers_filled += 1;
        }

        const job_dup: ?[]u8 = if (graph.job_cell_id) |s|
            (allocator.dupe(u8, s) catch return RatifyError.out_of_memory)
        else
            null;
        errdefer if (job_dup) |s| allocator.free(s);

        const attachments_buf = allocator.alloc([]u8, graph.attachment_cell_ids.items.len) catch return RatifyError.out_of_memory;
        var attachments_filled: usize = 0;
        errdefer {
            for (attachments_buf[0..attachments_filled]) |c| allocator.free(c);
            allocator.free(attachments_buf);
        }
        for (graph.attachment_cell_ids.items, 0..) |c, i| {
            const dup = allocator.dupe(u8, c) catch return RatifyError.out_of_memory;
            attachments_buf[i] = dup;
            attachments_filled += 1;
        }

        const key_owned = allocator.dupe(u8, proposal_id) catch return RatifyError.out_of_memory;
        errdefer allocator.free(key_owned);
        self.key_storage.append(allocator, key_owned) catch return RatifyError.out_of_memory;

        self.ratifications.put(key_owned, .{
            .site_cell_id = site_dup,
            .customer_cell_ids = customers_buf,
            .job_cell_id = job_dup,
            .attachment_cell_ids = attachments_buf,
            .persisted_at = persisted_at,
        }) catch return RatifyError.out_of_memory;
    }

    fn formatTimestampMs(self: *Handler, allocator: std.mem.Allocator) ![]u8 {
        const ts = self.clock();
        return std.fmt.allocPrint(allocator, "{d}", .{ts});
    }
};

// ─── Build-time scratch graph ──────────────────────────────────────

/// Working set during `buildGraph`.  Every owned string is freed via
/// `freeBuildResult` on the error path.  On success the slices are
/// transferred into the caller-owned RatifyResult.
const BuildResult = struct {
    site_cell_id: ?[]u8 = null,
    customer_cell_ids: std.ArrayList([]u8) = .{},
    job_cell_id: ?[]u8 = null,
    attachment_cell_ids: std.ArrayList([]u8) = .{},
};

fn freeBuildResult(allocator: std.mem.Allocator, b: *BuildResult) void {
    if (b.site_cell_id) |s| allocator.free(s);
    b.site_cell_id = null;
    for (b.customer_cell_ids.items) |c| allocator.free(c);
    b.customer_cell_ids.deinit(allocator);
    if (b.job_cell_id) |s| allocator.free(s);
    b.job_cell_id = null;
    for (b.attachment_cell_ids.items) |c| allocator.free(c);
    b.attachment_cell_ids.deinit(allocator);
}

/// Move an `ArrayList([]u8)`'s contents into a caller-owned
/// `[]const []const u8`.  Frees the ArrayList's backing buffer; the
/// caller now owns each element.
fn takeOwnedSlice(allocator: std.mem.Allocator, list: *std.ArrayList([]u8)) []const []const u8 {
    const owned = list.toOwnedSlice(allocator) catch unreachable;
    // Reframe as []const []const u8.  No re-allocation: same backing.
    const reframed: [][]const u8 = blk: {
        const buf = allocator.alloc([]const u8, owned.len) catch unreachable;
        for (owned, 0..) |c, i| buf[i] = c;
        allocator.free(owned);
        break :blk buf;
    };
    return reframed;
}

// ─── PayloadHint parsing ───────────────────────────────────────────

const ContactInput = struct {
    name: []const u8,
    role: customers_store_fs.CustomerRole,
    phone: ?[]const u8 = null,
    email: ?[]const u8 = null,
};

const PayloadHint = struct {
    // Legacy Phase 1.0 fields.
    customer_name: []const u8 = "",
    point_of_contact: []const u8 = "",
    summary: []const u8 = "",
    reference_number: []const u8 = "",
    source_provider_id: []const u8 = "",

    // Tier 1.7 enriched fields (Phase 2B will populate these via the
    // TS-side derivePayloadHint rewrite; until then they're absent).
    primary_contact: ?ContactInput = null,
    secondary_contacts: []const ContactInput = &.{},
    property_address: ?[]const u8 = null,
    property_key: ?[]const u8 = null,
    owner_name: ?[]const u8 = null,
    billing_party_type: ?[]const u8 = null,
    billing_party_name: ?[]const u8 = null,
    work_order_number: []const u8 = "",
    issuance_date: []const u8 = "",
    due_date: []const u8 = "",
    has_photos: bool = false,
    photo_count: ?u32 = null,
    source_attachment_path: []const u8 = "",
};

fn parsePayloadHint(maybe_v: ?std.json.Value) PayloadHint {
    var out: PayloadHint = .{};
    const v = maybe_v orelse return out;
    if (v != .object) return out;
    const obj = v.object;

    out.customer_name = optString(obj, "customer_name") orelse "";
    out.point_of_contact = optString(obj, "point_of_contact") orelse "";
    out.summary = optString(obj, "summary") orelse "";
    out.reference_number = optString(obj, "reference_number") orelse "";
    out.source_provider_id = optString(obj, "source_provider_id") orelse "";

    if (optString(obj, "propertyAddress")) |s| {
        if (s.len > 0) out.property_address = s;
    }
    if (optString(obj, "propertyKey")) |s| {
        if (s.len > 0) out.property_key = s;
    }
    if (optString(obj, "ownerName")) |s| {
        if (s.len > 0) out.owner_name = s;
    }
    if (optString(obj, "workOrderNumber")) |s| {
        out.work_order_number = s;
    }
    if (optString(obj, "issuanceDate")) |s| {
        out.issuance_date = s;
    }
    if (optString(obj, "dueDate")) |s| {
        out.due_date = s;
    }
    if (optString(obj, "sourceAttachmentPath")) |s| {
        out.source_attachment_path = s;
    }
    if (obj.get("hasPhotos")) |hv| {
        if (hv == .bool) out.has_photos = hv.bool;
    }
    if (obj.get("photoCount")) |pv| {
        if (pv == .integer and pv.integer >= 0 and pv.integer <= std.math.maxInt(u32)) {
            out.photo_count = @intCast(pv.integer);
        }
    }
    if (obj.get("billingParty")) |bv| {
        if (bv == .object) {
            out.billing_party_type = optString(bv.object, "type");
            out.billing_party_name = optString(bv.object, "name");
        }
    }
    if (obj.get("primaryContact")) |pc| {
        if (pc == .object) {
            out.primary_contact = parseContact(pc.object);
        }
    }
    // secondary_contacts left as &.{} unless we allocate; but the
    // JSON value's slices are owned by `parsed` on the caller side
    // and live for the duration of handleRatify, so we can borrow
    // them here without dup'ing.
    if (obj.get("secondaryContacts")) |sv| {
        if (sv == .array) {
            // Build a per-call slice through a static buffer growing
            // approach: for simplicity, since the SIRProgram caps SIR
            // nodes practically at single-digit counts, we use the
            // arena-backed std.json.Value lifetime.  See
            // parseSecondaryContacts for the implementation.
            // (The borrowed slice is valid for the duration of the
            // calling handleRatify since `parsed.deinit()` runs after
            // we're done with `hint`.)
            out.secondary_contacts = parseSecondaryContacts(sv.array);
        }
    }
    return out;
}

/// Per-call thread-local-ish buffer for secondary contacts.  Sized to
/// the realistic ceiling (a single SIR doesn't carry more than a
/// handful of contacts; 16 is comfortable headroom over the largest
/// dogfood corpus example).  Returned slice borrows from the buffer
/// for the duration of `handleRatify`'s call frame.
threadlocal var secondary_contact_buf: [16]ContactInput = undefined;

fn parseSecondaryContacts(arr: std.json.Array) []const ContactInput {
    var n: usize = 0;
    for (arr.items) |item| {
        if (n >= secondary_contact_buf.len) break;
        if (item != .object) continue;
        secondary_contact_buf[n] = parseContact(item.object) orelse continue;
        n += 1;
    }
    return secondary_contact_buf[0..n];
}

fn parseContact(obj: std.json.ObjectMap) ?ContactInput {
    const name = optString(obj, "name") orelse return null;
    if (name.len == 0) return null;
    const role_str = optString(obj, "role") orelse "agent";
    const role = customers_store_fs.CustomerRole.fromString(role_str) orelse .other;
    return ContactInput{
        .name = name,
        .role = role,
        .phone = optString(obj, "phone"),
        .email = optString(obj, "email"),
    };
}

fn optString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    if (obj.get(key)) |v| {
        switch (v) {
            .string => |s| return s,
            else => return null,
        }
    }
    return null;
}

// ─── Helpers ───────────────────────────────────────────────────────

/// Maximum length envelope on `proposal_id`.
pub const MAX_PROPOSAL_ID_BYTES: usize = 256;

/// Set of SIR-node `action` strings that map to a writable oddjobz
/// cell-type today.  attach_reply / noop are intentionally omitted.
///
/// D-DOG.1.0c Phase 2B.3 — `create_work_order` and
/// `create_maintenance_order` join the existing four.  Phase 2B.2's
/// TS-side filter (cartridges/oddjobz/brain/src/sir/derivePayloadHint.ts) was
/// already producing SIRPrograms with these action types via the legacy
/// PDF-ingest path, but the Zig handler's filter didn't recognise them
/// — so WSS-path proposals carrying these actions produced empty
/// graphs.  All six actions take the same `job.v2 + state:"lead"`
/// downstream shape; `workOrderNumber` (when present in payload_hint)
/// flows through to the minted Job row regardless of action verb.
fn isRatifiableAction(action: []const u8) bool {
    return std.mem.eql(u8, action, "create_lead") or
        std.mem.eql(u8, action, "create_quote_request") or
        std.mem.eql(u8, action, "create_booking") or
        std.mem.eql(u8, action, "log_inquiry") or
        std.mem.eql(u8, action, "create_work_order") or
        std.mem.eql(u8, action, "create_maintenance_order");
}

/// Mirror site.v2.ts `normaliseAddress` — see oddjobz_derivations.zig
/// for the canonical implementation. Wrapper preserved so the existing
/// call sites stay unchanged; the parity oracle (Phase 2B.4) drives
/// the underlying `oddjobz_derivations.normaliseAddress` directly.
fn normaliseAddress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return oddjobz_derivations.normaliseAddress(allocator, input);
}

/// Mirror site.v2.ts `deriveLookupKey` — see oddjobz_derivations.zig.
fn deriveLookupKey(
    allocator: std.mem.Allocator,
    normalised: []const u8,
    key_number: ?[]const u8,
) ![]u8 {
    return oddjobz_derivations.deriveLookupKey(allocator, normalised, key_number);
}

fn customerRoleString(role: customers_store_fs.CustomerRole) []const u8 {
    return role.toString();
}

fn hexAlloc(allocator: std.mem.Allocator, bytes: *const [32]u8) ![]u8 {
    const hex = std.fmt.bytesToHex(bytes.*, .lower);
    return allocator.dupe(u8, hex[0..]);
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

// ─── Type-hash + cell-id derivation ────────────────────────────────

fn sha256Bytes(input: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &out, .{});
    return out;
}

/// Type hash: SHA-256("whatPath:howSlug:instPath") per
/// `cartridges/oddjobz/brain/src/cell-types/type-hash.ts`.  Computed on each
/// call (no state); the result is byte-identical across calls and
/// matches the TS `computeTypeHash` output for the same triple.
fn computeSiteTypeHash() [32]u8 {
    return sha256Bytes("oddjobz.site:locate:inst.location.work-site.v2");
}
fn computeCustomerTypeHash() [32]u8 {
    return sha256Bytes("oddjobz.customer:identify:inst.identity.customer-record.v2");
}
fn computeJobTypeHash() [32]u8 {
    return sha256Bytes("oddjobz.job:worktrack:inst.work.job-record.v2");
}
fn computeAttachmentTypeHash() [32]u8 {
    return sha256Bytes("oddjobz.attachment:capture:inst.evidence.site-artifact.v2");
}

/// Site cellID — see oddjobz_derivations.zig for the canonical impl.
fn computeSiteCellId(
    normalised_address: []const u8,
    key_number: ?[]const u8,
    full_address: []const u8,
) [32]u8 {
    return oddjobz_derivations.computeSiteCellId(normalised_address, key_number, full_address);
}

/// Customer cellID — see oddjobz_derivations.zig.
fn computeCustomerCellId(
    name: []const u8,
    role: []const u8,
    site_cell_id: [32]u8,
    phone: []const u8,
    email: []const u8,
) [32]u8 {
    return oddjobz_derivations.computeCustomerCellId(name, role, site_cell_id, phone, email);
}

/// Job cellID — direct call into the leaf module's hash routine. Note
/// the handler's call sites pass `jobs_store_fs.CustomerRef` slices,
/// which have field name `.cellId` (vs the leaf module's `.cell_id`);
/// we feed each ref through the leaf module's incremental hasher to
/// avoid an intermediate allocation. The byte-level layout is:
///
///   "oddjobz.job.v2|" + site(32) + "|" +
///     each(cellId(32) + ":" + role + (primary ? "*" : " ") + "|") +
///     wo + "|" + issuance + "|" + due + "|" + display + "|" + createdAt
///
/// — identical to `oddjobz_derivations.computeJobCellId`'s output (the
/// parity oracle test asserts byte-equality across both paths).
fn computeJobCellId(
    site_cell_id: [32]u8,
    customer_refs: []const jobs_store_fs.CustomerRef,
    work_order_number: []const u8,
    issuance_date: []const u8,
    due_date: []const u8,
    created_at: []const u8,
    display_name: []const u8,
) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("oddjobz.job.v2|");
    hasher.update(&site_cell_id);
    hasher.update("|");
    for (customer_refs) |cref| {
        hasher.update(&cref.cellId);
        hasher.update(":");
        hasher.update(cref.role);
        hasher.update(if (cref.primary) "*" else " ");
        hasher.update("|");
    }
    hasher.update(work_order_number);
    hasher.update("|");
    hasher.update(issuance_date);
    hasher.update("|");
    hasher.update(due_date);
    hasher.update("|");
    hasher.update(display_name);
    hasher.update("|");
    hasher.update(created_at);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

/// Attachment cellID — see oddjobz_derivations.zig.
fn computeAttachmentCellId(
    job_cell_id: [32]u8,
    source_attachment_path: []const u8,
    created_at: []const u8,
) [32]u8 {
    return oddjobz_derivations.computeAttachmentCellId(job_cell_id, source_attachment_path, created_at);
}

/// UUID-shape derivation from a 32-byte cellID — see oddjobz_derivations.zig.
fn uuidV5LikeFromBytes(allocator: std.mem.Allocator, source: *const [32]u8) ![]u8 {
    return oddjobz_derivations.uuidV5LikeFromBytes(allocator, source);
}

```
