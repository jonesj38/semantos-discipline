---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/jobs_store_lmdb_entity.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.548577+00:00
---

# cartridges/oddjobz/brain/zig/src/jobs_store_lmdb_entity.zig

```zig
// W0.1 — JobsStore backed by LmdbCellStore (replaces jobs_store_fs.zig JSONL+HashMap).
//
// Reference: docs/design/BRAIN-BRAIN-FIELD-APP-DB-INTEGRATION-PIPELINE.md W0.1
//
// Each job entity is serialised as a JSON payload packed into a 1024-byte
// cell via entity_cell.encodeCell and written to LmdbCellStore.
//
// K4 atomicity: every append/appendCreatedV2 call encodes the cell bytes
// first, then calls cell_store.put().  If put() fails, the in-memory state
// is NOT updated — the FSM sees an error and returns without partial state.
//
// On init, the store scans the cell store for all cells tagged with
// ENTITY_TAG_JOB (0x06) and replays them to rebuild the in-memory index.
//
// The public API is identical to jobs_store_fs.JobsStore so all existing
// callers (jobs_handler, cli.zig, conformance tests) require only the
// change: pass *const cell_store_mod.CellStore instead of data_dir.

const std = @import("std");
const cell_store_mod = @import("cell_store");
const entity_cell = @import("entity_cell");
const substrate_entity = @import("substrate_entity");
const content_store_local_fs = @import("content_store_local_fs");

/// RM-114 — encode a job buffer as a 1024-byte cell. Prefers
/// substrate format (256-byte header + 768-byte payload); falls back
/// to legacy entity_cell encoding for payloads in the 769..1008-byte
/// range. RM-118 will replace the legacy fallback with substrate
/// continuation cells (`cell_count > 1`); until then this dual-path
/// writer is the only way to round-trip fat v2 job payloads without
/// silent data loss. Migration tool RM-115 already handles legacy
/// cells, so re-running it after RM-118 sweeps any holdouts to
/// pure substrate.
// CC-2 — encode a ≤768B job payload as a canonical substrate cell. >768B is NO
// LONGER handled here (the legacy 16-byte entity_cell fallback is dead — see
// JobsStore.putJobCell, which octave-1-escalates fat payloads canonically). Kept
// for the inline tests that mint small job cells directly.
fn encodeJobAsSubstrate(buf: []const u8) ![1024]u8 {
    const state = substrate_entity.extractStateOrStatus(buf);
    const linearity = substrate_entity.linearityFor(substrate_entity.TAG_JOB, state);
    return try substrate_entity.encodeEntity(.{
        .spec = substrate_entity.SPEC_JOB,
        .linearity = linearity,
        .owner_id = [_]u8{0} ** 16,
        .payload_json = buf,
    });
}

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    bad_format,
    invalid_id,
    invalid_customer_name,
    invalid_state,
    invalid_scheduled_at,
    invalid_work_order_number,
    invalid_iso_date,
    invalid_billing_party_type,
    invalid_billing_party_name,
    invalid_property_key,
    invalid_customer_role,
    invalid_primary_count,
    invalid_args,
};

/// Canonical Job FSM state names.  Mirrors JOB_FSM_STATES in
/// cartridges/oddjobz/brain/src/state-machines/job-fsm.ts verbatim — the
/// thirteen-state machine (lead-nurture remodel + the `authorized`
/// directly-authorised branch).  `isValidState` gates every job
/// write, so every canonical state MUST be here or a transition into
/// it is rejected as `invalid_state`.
pub const JOB_FSM_STATES = [_][]const u8{
    "lead",
    "qualified",
    "visit_pending",
    "visit_scheduled",
    "visited",
    "quoted",
    "authorized",
    "scheduled",
    "in_progress",
    "completed",
    "invoiced",
    "paid",
    "closed",
};

pub fn isValidState(s: []const u8) bool {
    for (JOB_FSM_STATES) |valid| {
        if (std.mem.eql(u8, valid, s)) return true;
    }
    return false;
}

/// Customer roles on a v2 job's customerRefs[].
pub const CUSTOMER_ROLES = [_][]const u8{
    "tenant",
    "agent",
    "owner",
    "pm",
    "sub-tradie",
    "other",
};

pub fn isValidCustomerRole(s: []const u8) bool {
    for (CUSTOMER_ROLES) |valid| {
        if (std.mem.eql(u8, valid, s)) return true;
    }
    return false;
}

pub const BILLING_PARTY_TYPES = [_][]const u8{ "agency", "owner" };

pub fn isValidBillingPartyType(s: []const u8) bool {
    for (BILLING_PARTY_TYPES) |valid| {
        if (std.mem.eql(u8, valid, s)) return true;
    }
    return false;
}

/// Per-customer reference on a v2 job row.
/// RM-121 — `name`/`phone` are the resolved contact identity (the
/// customer cell `cell_id` points at), populated by the ingest adapter
/// so the operator's Home tab can show who to call without a second
/// fetch. Empty when unresolved / on pre-RM-121 v2 rows.
pub const CustomerRef = struct {
    cellId: [32]u8,
    role: []const u8,
    primary: bool,
    name: []const u8 = "",
    phone: []const u8 = "",
};

/// RM-121 — a customer cell resolved by its cell-hash, used to
/// enrich ingest jobs at replay (slices live in the transient
/// resolve-index arena; copied into store-owned memory before use).
const ResolvedContact = struct {
    name: []const u8,
    phone: []const u8,
    role: []const u8,
};

/// BillingParty descriptor on a v2 job row.
pub const BillingParty = struct {
    type: []const u8,
    name: []const u8,
};

/// One job record in the in-memory view.  Shared between v1 (legacy) and
/// v2 (graph-aware) rows via the `version` discriminator.
pub const Job = struct {
    version: u8 = 1,
    id: []const u8,
    customer_name: []const u8,
    state: []const u8,
    scheduled_at: []const u8,
    created_at: []const u8,

    // v2-only fields (null on v1 rows)
    cellId: ?[32]u8 = null,
    typeHash: ?[32]u8 = null,
    workOrderNumber: ?[]const u8 = null,
    issuanceDate: ?[]const u8 = null,
    dueDate: ?[]const u8 = null,
    billingParty: ?BillingParty = null,
    hasPhotos: ?bool = null,
    photoCount: ?u32 = null,
    propertyKey: ?[]const u8 = null,
    siteRef: ?[32]u8 = null,
    customerRefs: ?[]const CustomerRef = null,
    /// RM-121 — resolved site street address (siteRef → site cell
    /// `raw_address`) so Home can group/sort by site without a second
    /// fetch. Null when unresolved / on rows with no site.
    propertyAddress: ?[]const u8 = null,
    /// RM-121 — the work description (ingest `summary`). Null on
    /// brain-native rows that have no summary.
    description: ?[]const u8 = null,
    /// RM-125 — ingest `services[]` joined as "a, b, c" so the
    /// operator sees the scope without the WO PDF. Null when none.
    services: ?[]const u8 = null,
    attachmentRefs: ?[]const [32]u8 = null,
    signedBy: ?[33]u8 = null,
    signature: ?[64]u8 = null,
};

pub const MAX_CUSTOMER_NAME_BYTES: usize = 200;
pub const MAX_ID_BYTES: usize = 64;
pub const MAX_SCHEDULED_AT_BYTES: usize = 64;
pub const MAX_WORK_ORDER_NUMBER_BYTES: usize = 128;
pub const MAX_ISO_DATE_BYTES: usize = 16;
pub const MAX_BILLING_PARTY_NAME_BYTES: usize = 200;
pub const MAX_PROPERTY_KEY_BYTES: usize = 128;
pub const MAX_CUSTOMER_REFS: usize = 64;
pub const MAX_ATTACHMENT_REFS: usize = 64;

/// OwnedStrings holds allocator-owned copies of variable-length string
/// fields so the per-record arena approach (string_arena + ref_arena) keeps
/// working identically to the FS store.
const OwnedStrings = struct {
    id: []u8,
    customer_name: []u8,
    state: []u8,
    scheduled_at: []u8,
    created_at: []u8,
    work_order_number: ?[]u8 = null,
    issuance_date: ?[]u8 = null,
    due_date: ?[]u8 = null,
    billing_type: ?[]u8 = null,
    billing_name: ?[]u8 = null,
    property_key: ?[]u8 = null,
    // RM-121 — resolved site address + work description.
    property_address: ?[]u8 = null,
    description: ?[]u8 = null,
    // RM-125 — joined ingest services list.
    services: ?[]u8 = null,
    // CustomerRef roles (one per entry)
    customer_roles: ?[][]u8 = null,

    fn freeAll(self: *OwnedStrings, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.customer_name);
        allocator.free(self.state);
        allocator.free(self.scheduled_at);
        allocator.free(self.created_at);
        if (self.work_order_number) |s| allocator.free(s);
        if (self.issuance_date) |s| allocator.free(s);
        if (self.due_date) |s| allocator.free(s);
        if (self.billing_type) |s| allocator.free(s);
        if (self.billing_name) |s| allocator.free(s);
        if (self.property_key) |s| allocator.free(s);
        if (self.property_address) |s| allocator.free(s);
        if (self.description) |s| allocator.free(s);
        if (self.services) |s| allocator.free(s);
        if (self.customer_roles) |rs| {
            for (rs) |r| allocator.free(r);
            allocator.free(rs);
        }
    }
};

/// OwnedRefs holds allocator-owned slices for CustomerRef and
/// attachmentRef arrays.
const OwnedRefs = struct {
    customer_refs: ?[]CustomerRef = null,
    attachment_refs: ?[][32]u8 = null,
    /// RM-121 — backing store for the resolved CustomerRef.name/phone/
    /// role strings (the CustomerRef slices point into these). Owned
    /// here so they outlive the transient resolve-index arena.
    contact_strings: ?[][]u8 = null,

    fn freeAll(self: *OwnedRefs, allocator: std.mem.Allocator) void {
        if (self.customer_refs) |rs| allocator.free(rs);
        if (self.attachment_refs) |rs| allocator.free(rs);
        if (self.contact_strings) |ss| {
            for (ss) |s| allocator.free(s);
            allocator.free(ss);
        }
    }
};

pub const JobsStore = struct {
    allocator: std.mem.Allocator,
    cell_store: *const cell_store_mod.CellStore,
    records: std.ArrayList(Job),
    by_id: std.StringHashMap(usize),
    /// Tracks the highest ts seen for each id during replay pass 2.
    /// Only "updated" cells whose ts is strictly greater than the tracked value
    /// are applied, so the last-written transition wins even when LMDB cursor
    /// order happens to visit cells out of write order.
    by_id_ts: std.StringHashMap(i64),
    owned_strings: std.ArrayList(OwnedStrings),
    owned_refs: std.ArrayList(OwnedRefs),
    /// Owned cellHash hex strings used as secondary `by_id` keys (indexCellHash).
    /// Tracked so deinit frees them — the record-`id` keys live in owned_strings,
    /// but these content-hash keys are a separate allocation.
    cell_hash_keys: std.ArrayList([]u8) = .{},
    clock: *const fn () i64,
    /// Octave-1 content store. When set, job cells carrying an
    /// escalation pointer descriptor are transparently deref'd at
    /// replay so the full (e.g. long PDF work-scope) payload is parsed,
    /// not the ~100-byte descriptor. Null ⇒ pre-escalation behaviour
    /// (inline cells only) — keeps every existing caller/test working.
    content_store: ?*content_store_local_fs.ContentStoreLocalFs = null,
    /// CC-3 — the operator's 16-byte cell ownerId (first 16 bytes of the operator
    /// root cert-id). Stamped into every job cell so the canonical cell is
    /// OWNER-BOUND (VM-checkable + UTXO-binding-eligible). Zero ⇒ no operator
    /// identity known (fresh/test brain) — back-compat with the unsigned default.
    /// Set via setOwnerId at serve boot (registerInto, from CartridgeDeps).
    owner_id: [16]u8 = [_]u8{0} ** 16,

    /// CC-3 — set the operator ownerId stamped into future job cells.
    pub fn setOwnerId(self: *JobsStore, owner_id: [16]u8) void {
        self.owner_id = owner_id;
    }

    pub fn init(
        allocator: std.mem.Allocator,
        cell_store: *const cell_store_mod.CellStore,
        clock_fn: *const fn () i64,
    ) !JobsStore {
        return initWithContentStore(allocator, cell_store, clock_fn, null);
    }

    /// As `init`, plus an octave-1 content store wired BEFORE replay so
    /// escalated job cells are deref'd as they are read (replay runs
    /// inside this call, so a post-construction setter would be too
    /// late). serve.zig uses this; tests keep using `init`.
    pub fn initWithContentStore(
        allocator: std.mem.Allocator,
        cell_store: *const cell_store_mod.CellStore,
        clock_fn: *const fn () i64,
        content_store: ?*content_store_local_fs.ContentStoreLocalFs,
    ) !JobsStore {
        var self = JobsStore{
            .allocator = allocator,
            .cell_store = cell_store,
            .records = .{},
            .by_id = std.StringHashMap(usize).init(allocator),
            .by_id_ts = std.StringHashMap(i64).init(allocator),
            .owned_strings = .{},
            .owned_refs = .{},
            .clock = clock_fn,
            .content_store = content_store,
        };
        try self.replayCellStore();
        // by_id_ts is only used during replay; clear it after to free memory.
        self.by_id_ts.clearAndFree();
        return self;
    }

    pub fn deinit(self: *JobsStore) void {
        self.records.deinit(self.allocator);
        self.by_id.deinit();
        self.by_id_ts.deinit();
        for (self.owned_strings.items) |*s| s.freeAll(self.allocator);
        self.owned_strings.deinit(self.allocator);
        for (self.owned_refs.items) |*r| r.freeAll(self.allocator);
        self.owned_refs.deinit(self.allocator);
        for (self.cell_hash_keys.items) |k| self.allocator.free(k);
        self.cell_hash_keys.deinit(self.allocator);
    }

    pub fn append(self: *JobsStore, job: Job) !AppendOutcome {
        if (job.id.len == 0 or job.id.len > MAX_ID_BYTES) return StoreError.invalid_id;
        if (job.customer_name.len == 0 or job.customer_name.len > MAX_CUSTOMER_NAME_BYTES) return StoreError.invalid_customer_name;
        if (!isValidState(job.state)) return StoreError.invalid_state;
        if (job.scheduled_at.len > MAX_SCHEDULED_AT_BYTES) return StoreError.invalid_scheduled_at;

        const existing_idx = self.by_id.get(job.id);

        // K4: write to LMDB first; in-memory update only on success.
        // Capture the SHA-256 hash so we can set cellId on the in-memory
        // record — every brain-native job is content-addressed from birth.
        const cell_hash = try self.putCell(job);

        if (existing_idx != null) {
            return .already_exists;
        }

        var job_with_cell_id = job;
        job_with_cell_id.cellId = cell_hash;
        const stored = try self.cloneJobIntoOwned(job_with_cell_id);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        return .created;
    }

    pub fn updateState(
        self: *JobsStore,
        id: []const u8,
        new_state: []const u8,
        new_scheduled_at: ?[]const u8,
    ) !Job {
        if (!isValidState(new_state)) return StoreError.invalid_state;
        if (new_scheduled_at) |s| {
            if (s.len > MAX_SCHEDULED_AT_BYTES) return StoreError.invalid_scheduled_at;
        }

        const idx = self.by_id.get(id) orelse return error.not_found;
        const current = self.records.items[idx];

        // Allocate new owned copies of the updated fields.
        const owned_state = try self.allocator.dupe(u8, new_state);
        errdefer self.allocator.free(owned_state);

        const owned_sched = if (new_scheduled_at) |s|
            try self.allocator.dupe(u8, s)
        else
            null;
        errdefer if (owned_sched) |s| self.allocator.free(s);

        // Track the new owned strings (we append a minimal OwnedStrings with
        // only the new fields; the old ones live in their prior owned_strings
        // entry and will be freed on deinit — this is a minor memory leak per
        // transition but identical to the FS store's arena approach, which
        // also never frees the old slice bytes).
        const extra = OwnedStrings{
            .id = try self.allocator.dupe(u8, ""), // dummy non-null id
            .customer_name = try self.allocator.dupe(u8, ""),
            .state = owned_state,
            .scheduled_at = owned_sched orelse try self.allocator.dupe(u8, ""),
            .created_at = try self.allocator.dupe(u8, ""),
        };
        try self.owned_strings.append(self.allocator, extra);

        var updated = current;
        updated.state = owned_state;
        updated.scheduled_at = if (new_scheduled_at) |_| owned_sched.? else current.scheduled_at;
        self.records.items[idx] = updated;

        // K4: write the "updated" cell (kind=updated, not kind=created).
        self.putUpdatedCell(updated) catch {};

        return updated;
    }

    pub fn findAll(self: *const JobsStore, allocator: std.mem.Allocator) ![]Job {
        const out = try allocator.alloc(Job, self.records.items.len);
        @memcpy(out, self.records.items);
        return out;
    }

    pub fn findById(self: *const JobsStore, id: []const u8) ?Job {
        const idx = self.by_id.get(id) orelse return null;
        return self.records.items[idx];
    }

    pub fn findByState(self: *const JobsStore, allocator: std.mem.Allocator, state: []const u8) ![]Job {
        var n: usize = 0;
        for (self.records.items) |r| {
            if (std.mem.eql(u8, r.state, state)) n += 1;
        }
        const out = try allocator.alloc(Job, n);
        var i: usize = 0;
        for (self.records.items) |r| {
            if (std.mem.eql(u8, r.state, state)) {
                out[i] = r;
                i += 1;
            }
        }
        return out;
    }

    pub fn count(self: *const JobsStore) usize {
        return self.records.items.len;
    }

    pub const AppendOutcome = enum {
        created,
        already_exists,
    };

    pub const JobV2Payload = struct {
        cellId: [32]u8,
        typeHash: [32]u8,
        customer_name: []const u8,
        state: []const u8,
        scheduled_at: []const u8 = "",
        created_at: []const u8,
        workOrderNumber: ?[]const u8 = null,
        issuanceDate: ?[]const u8 = null,
        dueDate: ?[]const u8 = null,
        billingParty: ?BillingParty = null,
        hasPhotos: bool,
        photoCount: ?u32 = null,
        propertyKey: ?[]const u8 = null,
        siteRef: [32]u8,
        customerRefs: []const CustomerRef,
        attachmentRefs: []const [32]u8,
        signedBy: ?[33]u8 = null,
        signature: ?[64]u8 = null,
    };

    pub fn appendCreatedV2(self: *JobsStore, payload: JobV2Payload) !Job {
        // Length-envelope + enum validation
        if (payload.customer_name.len == 0 or payload.customer_name.len > MAX_CUSTOMER_NAME_BYTES) return StoreError.invalid_customer_name;
        if (!isValidState(payload.state)) return StoreError.invalid_state;
        if (payload.scheduled_at.len > MAX_SCHEDULED_AT_BYTES) return StoreError.invalid_scheduled_at;
        if (payload.created_at.len > MAX_SCHEDULED_AT_BYTES) return StoreError.invalid_scheduled_at;
        if (payload.workOrderNumber) |w| {
            if (w.len > MAX_WORK_ORDER_NUMBER_BYTES) return StoreError.invalid_work_order_number;
        }
        if (payload.issuanceDate) |d| {
            if (d.len > MAX_ISO_DATE_BYTES) return StoreError.invalid_iso_date;
        }
        if (payload.dueDate) |d| {
            if (d.len > MAX_ISO_DATE_BYTES) return StoreError.invalid_iso_date;
        }
        if (payload.billingParty) |bp| {
            if (!isValidBillingPartyType(bp.type)) return StoreError.invalid_billing_party_type;
            if (bp.name.len == 0 or bp.name.len > MAX_BILLING_PARTY_NAME_BYTES) return StoreError.invalid_billing_party_name;
        }
        if (payload.propertyKey) |p| {
            if (p.len > MAX_PROPERTY_KEY_BYTES) return StoreError.invalid_property_key;
        }
        if (payload.customerRefs.len > MAX_CUSTOMER_REFS) return StoreError.invalid_args;
        for (payload.customerRefs) |cref| {
            if (!isValidCustomerRole(cref.role)) return StoreError.invalid_customer_role;
        }
        if (payload.customerRefs.len > 0) {
            var primary_count: usize = 0;
            for (payload.customerRefs) |cref| {
                if (cref.primary) primary_count += 1;
            }
            if (primary_count != 1) return StoreError.invalid_primary_count;
        }
        if (payload.attachmentRefs.len > MAX_ATTACHMENT_REFS) return StoreError.invalid_args;

        if (payload.photoCount) |c| {
            if (payload.hasPhotos and c == 0) return StoreError.invalid_args;
            if (!payload.hasPhotos and c > 0) return StoreError.invalid_args;
        }

        const id_hex_arr = std.fmt.bytesToHex(payload.cellId, .lower);
        const id_hex_slice: []const u8 = id_hex_arr[0..];

        const existing_idx = self.by_id.get(id_hex_slice);

        // K4: write LMDB cell first.
        const v2_job: Job = .{
            .version = 2,
            .id = id_hex_slice,
            .customer_name = payload.customer_name,
            .state = payload.state,
            .scheduled_at = payload.scheduled_at,
            .created_at = payload.created_at,
            .cellId = payload.cellId,
            .typeHash = payload.typeHash,
            .workOrderNumber = payload.workOrderNumber,
            .issuanceDate = payload.issuanceDate,
            .dueDate = payload.dueDate,
            .billingParty = payload.billingParty,
            .hasPhotos = payload.hasPhotos,
            .photoCount = payload.photoCount,
            .propertyKey = payload.propertyKey,
            .siteRef = payload.siteRef,
            .customerRefs = payload.customerRefs,
            .attachmentRefs = payload.attachmentRefs,
            .signedBy = payload.signedBy,
            .signature = payload.signature,
        };
        // v2 already knows its cellId from the payload; discard hash return.
        _ = try self.putCell(v2_job);

        if (existing_idx) |idx| {
            return self.records.items[idx];
        }

        const stored = try self.cloneJobV2IntoOwned(payload, id_hex_slice);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        return self.records.items[idx];
    }

    pub fn getById(self: *const JobsStore, cellId: [32]u8) ?Job {
        const id_hex_arr = std.fmt.bytesToHex(cellId, .lower);
        const idx = self.by_id.get(id_hex_arr[0..]) orelse return null;
        return self.records.items[idx];
    }

    /// Register the cell's content hash (cellHash) as a SECOND `by_id` key for
    /// record `idx`, so findById/getById/transition resolve a job by its
    /// content-addressed identity (what the operator app uses after
    /// find→cell.query) in addition to its logical payload id. Best-effort; the
    /// 64-byte key is brain-lifetime (matches the store's leak-at-exit posture).
    fn indexCellHash(self: *JobsStore, idx: usize, cell_hash: [32]u8) void {
        const hex = std.fmt.bytesToHex(cell_hash, .lower);
        if (self.by_id.contains(hex[0..])) return;
        const owned = self.allocator.dupe(u8, hex[0..]) catch return;
        self.by_id.put(owned, idx) catch {
            self.allocator.free(owned);
            return;
        };
        // Track for deinit (the key is now referenced by by_id).
        self.cell_hash_keys.append(self.allocator, owned) catch {};
    }

    pub fn listAll(self: *const JobsStore, allocator: std.mem.Allocator) ![]Job {
        const out = try allocator.alloc(Job, self.records.items.len);
        @memcpy(out, self.records.items);
        return out;
    }

    pub fn listForSite(self: *const JobsStore, allocator: std.mem.Allocator, siteRef: [32]u8) ![]Job {
        var n: usize = 0;
        for (self.records.items) |r| {
            if (r.version != 2) continue;
            const sr = r.siteRef orelse continue;
            if (std.mem.eql(u8, &sr, &siteRef)) n += 1;
        }
        const out = try allocator.alloc(Job, n);
        var i: usize = 0;
        for (self.records.items) |r| {
            if (r.version != 2) continue;
            const sr = r.siteRef orelse continue;
            if (std.mem.eql(u8, &sr, &siteRef)) {
                out[i] = r;
                i += 1;
            }
        }
        return out;
    }

    pub fn listForCustomer(self: *const JobsStore, allocator: std.mem.Allocator, customerRef: [32]u8) ![]Job {
        var n: usize = 0;
        for (self.records.items) |r| {
            if (r.version != 2) continue;
            const refs = r.customerRefs orelse continue;
            for (refs) |cref| {
                if (std.mem.eql(u8, &cref.cellId, &customerRef)) {
                    n += 1;
                    break;
                }
            }
        }
        const out = try allocator.alloc(Job, n);
        var i: usize = 0;
        for (self.records.items) |r| {
            if (r.version != 2) continue;
            const refs = r.customerRefs orelse continue;
            for (refs) |cref| {
                if (std.mem.eql(u8, &cref.cellId, &customerRef)) {
                    out[i] = r;
                    i += 1;
                    break;
                }
            }
        }
        return out;
    }

    pub fn appendSigned(
        self: *JobsStore,
        cell_id: [32]u8,
        signed_by: [33]u8,
        signature: [64]u8,
    ) !void {
        for (self.records.items, 0..) |row, idx| {
            const row_cid = row.cellId orelse continue;
            if (std.mem.eql(u8, &row_cid, &cell_id)) {
                self.records.items[idx].signedBy = signed_by;
                self.records.items[idx].signature = signature;
                _ = self.putCell(self.records.items[idx]) catch {};
                return;
            }
        }
    }

    // ── LMDB cell write ──────────────────────────────────────────────────

    // W0.1 canonical-cell path: putCell/putCellWithTs now return the
    // SHA-256 hash of the written cell so callers can set cellId on the
    // in-memory Job without a second hash computation.
    fn putCell(self: *JobsStore, job: Job) ![32]u8 {
        return self.putCellWithTs(job, self.clock());
    }

    fn putCellWithTs(self: *JobsStore, job: Job, ts: i64) ![32]u8 {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try serializeJob(self.allocator, &buf, job, ts);
        return self.putJobCell(buf.items);
    }

    fn putUpdatedCell(self: *JobsStore, job: Job) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try serializeJobUpdated(self.allocator, &buf, job, self.clock());
        _ = self.putJobCell(buf.items) catch return cell_store_mod.StoreError.persistence_failed;
    }

    /// CC-2 — encode `buf` as a CANONICAL job cell and persist it, octave-1
    /// escalating payloads >768B to the content store (NOT the legacy 16-byte
    /// entity_cell). The overflow body is written BEFORE the cell so replay's
    /// `effectivePayload`/`escalatedSlot` deref always resolves. Recognised on
    /// replay by SPEC_JOB.domain_flag (not an entity-tag), so the canonical +
    /// escalated cells index identically. Returns the cell SHA-256.
    fn putJobCell(self: *JobsStore, buf: []const u8) ![32]u8 {
        const state = substrate_entity.extractStateOrStatus(buf);
        const linearity = substrate_entity.linearityFor(substrate_entity.TAG_JOB, state);
        const esc = substrate_entity.encodeEntityEscalating(.{
            .spec = substrate_entity.SPEC_JOB,
            .linearity = linearity,
            .owner_id = self.owner_id, // CC-3 — operator-bound (set at serve boot)
            .payload_json = buf,
        }) catch return error.persistence_failed;
        if (esc.overflow) |ov| {
            const cs = self.content_store orelse return error.persistence_failed;
            cs.writeSlot(esc.slot, ov) catch return error.persistence_failed;
        }
        return self.cell_store.put(&esc.cell) catch return cell_store_mod.StoreError.persistence_failed;
    }

    // ── Cell store replay ──────────────────────────────────────────────
    //
    // Two-pass replay: pass 1 processes only "kind":"created" and
    // "kind":"signed" cells (inserts records into by_id); pass 2
    // processes only "kind":"updated" cells (applies FSM transitions).
    // This guarantees that "updated" handlers always find the record that
    // the corresponding "created" cell inserted, regardless of LMDB's
    // key-sorted cursor order.

    /// Incremental pass-1 scan: index every `created`/`signed` job
    /// cell currently in the shared entity store.
    ///
    /// `by_id` is otherwise built ONCE at init. A gmail reingest (or
    /// any `entity.encode` mint) that lands a new TAG_JOB cell while
    /// the brain is already running would be invisible to the jobs
    /// handler until the next process restart — the cell IS in the
    /// same LMDB env the cursor-walking agent queries see, but the
    /// handler's in-memory index is stale. That is the "store-split"
    /// symptom: `jobs.transition {id:<freshly-reingested>}` returns
    /// not_found even though find_pipeline_gaps lists the job.
    ///
    /// This makes the index live. It is safe to call on any `by_id`
    /// miss before declaring not_found because it is fully idempotent:
    ///   • v1 created  — guarded by `if (by_id.contains(id)) return;`
    ///   • v2 created  — same contains-guard
    ///   • signed      — sets signature bytes in place (no insert)
    /// and reingested cells are always `kind=created` (never
    /// `updated`), so pass 2 is not needed on a refresh — chat
    /// transitions mutate the in-memory record directly via
    /// updateState, they don't rely on replaying `updated` cells.
    /// RM-121 — first-pass: index every site + customer cell by its
    /// cell-hash (`hex(sha256(cell))` — the same id ingest jobs carry
    /// in `site_ref` / `customer_refs[].cell_id`, verified equal to
    /// the LMDB key hash). Keys + values are allocated in `aa` (a
    /// transient arena owned by the caller); the ingest adapter copies
    /// whatever it needs into store-owned memory before `aa` is freed.
    /// Best-effort: a malformed cell is skipped, never fatal.
    fn buildResolveIndexes(
        self: *JobsStore,
        aa: std.mem.Allocator,
        site_idx: *std.StringHashMap([]const u8),
        cust_idx: *std.StringHashMap(ResolvedContact),
    ) void {
        const cursor = self.cell_store.cursorOpen() catch return;
        defer self.cell_store.cursorClose(cursor);
        while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
            const decoded = substrate_entity.decodeEntity(cell_ptr);
            if (!decoded.magic_ok) continue;
            const is_site = decoded.domain_flag == substrate_entity.SPEC_SITE.domain_flag;
            const is_cust = decoded.domain_flag == substrate_entity.SPEC_CUSTOMER.domain_flag;
            if (!is_site and !is_cust) continue;

            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(cell_ptr[0..substrate_entity.CELL_BYTES], &digest, .{});
            const hx = std.fmt.bytesToHex(digest, .lower); // [64]u8
            const key = aa.dupe(u8, hx[0..]) catch continue;

            // Octave-1 deref (generic): a site/customer cell could also
            // be escalated. Arena-allocated, freed with `aa`.
            const eff_payload = self.effectivePayload(decoded.payload, aa, null);
            const parsed = std.json.parseFromSliceLeaky(
                std.json.Value,
                aa,
                eff_payload,
                .{},
            ) catch continue;
            if (parsed != .object) continue;
            const o = parsed.object;

            if (is_site) {
                const addr = strField(o, "raw_address") orelse
                    strField(o, "normalized_address") orelse continue;
                site_idx.put(key, addr) catch {};
            } else {
                const nm = strField(o, "name") orelse "";
                cust_idx.put(key, .{
                    .name = nm,
                    .phone = strField(o, "phone") orelse "",
                    .role = strField(o, "role") orelse "",
                }) catch {};
            }
        }
    }

    pub fn rescanCreatedCells(self: *JobsStore) void {
        // RM-121 pass-0 — build the transient site/customer resolve
        // indexes (one extra cursor scan; ~67 sites + 170 customers
        // on rbs — small). Freed when this fn returns.
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const aa = arena.allocator();
        var site_idx = std.StringHashMap([]const u8).init(aa);
        var cust_idx = std.StringHashMap(ResolvedContact).init(aa);
        self.buildResolveIndexes(aa, &site_idx, &cust_idx);

        const cursor = self.cell_store.cursorOpen() catch return;
        defer self.cell_store.cursorClose(cursor);
        while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
            // RM-114 — accept both substrate-format and legacy
            // entity_cell-format job cells during the migration
            // window. Once `tools/migrate-entity-cells/` runs on
            // rbs every cell should be substrate-format; the
            // legacy branch is then dead-code and removed in
            // RM-117 alongside `entity_cell.zig`.
            const raw_payload = blk: {
                if (substrate_entity.looksLikeLegacyEntityCell(cell_ptr)) {
                    if (entity_cell.cellEntityTag(cell_ptr) != entity_cell.ENTITY_TAG_JOB) continue;
                    break :blk entity_cell.cellPayload(cell_ptr);
                }
                const decoded = substrate_entity.decodeEntity(cell_ptr);
                if (!decoded.magic_ok) continue;
                if (decoded.domain_flag != substrate_entity.SPEC_JOB.domain_flag) continue;
                break :blk decoded.payload;
            };
            // Octave-1 deref: when the job cell carries a pointer
            // descriptor, parse the FULL payload (freed each iteration,
            // after apply* has dup'd whatever it keeps).
            var deref_buf: ?[]u8 = null;
            defer if (deref_buf) |b| self.allocator.free(b);
            const payload = self.effectivePayload(raw_payload, self.allocator, &deref_buf);
            const kind = kindOfPayload(payload);
            if (kind == .created or kind == .signed) {
                // Compute SHA-256 of the full 1024-byte cell so applyPayload
                // can set cellId on v1 `kind=created` rows during replay.
                var cell_hash: [32]u8 = undefined;
                std.crypto.hash.sha2.Sha256.hash(cell_ptr[0..], &cell_hash, .{});
                self.applyPayload(payload, cell_hash) catch {};
            } else if (kind == .unknown) {
                // RM-119/RM-121 — ingest-shape job cell (no `kind`).
                // Adapt + resolve site/contacts. Self-discriminating
                // + idempotent; a non-ingest .unknown payload no-ops.
                // content_hash = sha256(cell) = the job's cellHash — stamped +
                // indexed so find/transition by cellHash resolve (the identity
                // the operator app now uses post find→cell.query).
                var cell_hash: [32]u8 = undefined;
                std.crypto.hash.sha2.Sha256.hash(cell_ptr[0..], &cell_hash, .{});
                self.applyIngestJobPayload(payload, &site_idx, &cust_idx, cell_hash) catch {};
            }
        }
    }

    /// Octave-1 deref. If `payload` is an escalation pointer descriptor
    /// and a content store is wired, return the full payload (allocated
    /// in `alloc`; the allocation handle is written to `owned` for the
    /// caller to free — pass null when `alloc` is an arena that frees
    /// it anyway). Otherwise returns `payload` unchanged. Degrades
    /// safely: if the slot read fails it returns the descriptor rather
    /// than crashing replay (logged) — generic across every entity, not
    /// job-specific.
    fn effectivePayload(
        self: *JobsStore,
        payload: []const u8,
        alloc: std.mem.Allocator,
        owned: ?*?[]u8,
    ) []const u8 {
        const cs = self.content_store orelse return payload;
        const slot = substrate_entity.escalatedSlot(payload) orelse return payload;
        const full = cs.readSlot(slot, alloc) catch |err| {
            std.debug.print(
                "[jobs replay] octave-1 deref failed slot={} ({s}) — using descriptor\n",
                .{ slot, @errorName(err) },
            );
            return payload;
        };
        if (owned) |o| o.* = full;
        return full;
    }

    /// Small helper: a non-empty string field from a JSON object, else null.
    fn strField(o: std.json.ObjectMap, key: []const u8) ?[]const u8 {
        if (o.get(key)) |v| {
            if (v == .string and v.string.len > 0) return v.string;
        }
        return null;
    }

    fn replayCellStore(self: *JobsStore) !void {
        // Pass 1: created + signed (idempotent — see rescanCreatedCells).
        self.rescanCreatedCells();
        // Pass 2: updated
        {
            const cursor = self.cell_store.cursorOpen() catch return;
            defer self.cell_store.cursorClose(cursor);
            while (self.cell_store.cursorPull(cursor) catch null) |cell_ptr| {
                // RM-114 — accept both substrate-format and legacy
                // entity_cell-format job cells during the migration
                // window. Once `tools/migrate-entity-cells/` runs on
                // rbs every cell should be substrate-format; the
                // legacy branch is then dead-code and removed in
                // RM-117 alongside `entity_cell.zig`.
                const raw_payload = blk: {
                    if (substrate_entity.looksLikeLegacyEntityCell(cell_ptr)) {
                        if (entity_cell.cellEntityTag(cell_ptr) != entity_cell.ENTITY_TAG_JOB) continue;
                        break :blk entity_cell.cellPayload(cell_ptr);
                    }
                    const decoded = substrate_entity.decodeEntity(cell_ptr);
                    if (!decoded.magic_ok) continue;
                    if (decoded.domain_flag != substrate_entity.SPEC_JOB.domain_flag) continue;
                    break :blk decoded.payload;
                };
                var deref_buf: ?[]u8 = null;
                defer if (deref_buf) |b| self.allocator.free(b);
                const payload = self.effectivePayload(raw_payload, self.allocator, &deref_buf);
                if (kindOfPayload(payload) == .updated) {
                    // `updated` cells only carry state transitions; no cellId needed.
                    self.applyPayload(payload, null) catch {};
                }
            }
        }
    }

    const PayloadKind = enum { created, updated, signed, unknown };

    fn kindOfPayload(payload: []const u8) PayloadKind {
        // Quick scan: find the "kind" value without full JSON parse.
        // Payload starts with {"kind":"<value>",...}
        const marker = "\"kind\":\"";
        const start = std.mem.indexOf(u8, payload, marker) orelse return .unknown;
        const after = payload[start + marker.len..];
        if (std.mem.startsWith(u8, after, "created")) return .created;
        if (std.mem.startsWith(u8, after, "updated")) return .updated;
        if (std.mem.startsWith(u8, after, "signed")) return .signed;
        return .unknown;
    }

    // cell_hash: when non-null, set as cellId on v1 `kind=created` rows
    // (canonical cell hash from the 1024-byte cell = SHA-256(cell_bytes)).
    fn applyPayload(self: *JobsStore, payload: []const u8, cell_hash: ?[32]u8) !void {
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            payload,
            .{},
        ) catch return;
        defer parsed.deinit();

        if (parsed.value != .object) return;
        const obj = parsed.value.object;

        const kind_v = obj.get("kind") orelse return;
        if (kind_v != .string) return;

        if (std.mem.eql(u8, kind_v.string, "signed")) {
            try self.applySignedPayload(obj);
            return;
        }

        if (std.mem.eql(u8, kind_v.string, "updated")) {
            try self.applyUpdatedPayload(obj);
            return;
        }

        if (!std.mem.eql(u8, kind_v.string, "created")) return;

        // Sniff v2 by presence of siteRef
        if (obj.get("siteRef") != null) {
            try self.applyV2CreatedPayload(obj, cell_hash);
            return;
        }

        // v1 row
        const id_v = obj.get("id") orelse return;
        if (id_v != .string) return;
        const id = id_v.string;
        if (id.len == 0 or id.len > MAX_ID_BYTES) return;

        const cn_v = obj.get("customer_name") orelse return;
        if (cn_v != .string) return;
        const customer_name = cn_v.string;
        if (customer_name.len == 0 or customer_name.len > MAX_CUSTOMER_NAME_BYTES) return;

        const state_v = obj.get("state") orelse return;
        if (state_v != .string) return;
        if (!isValidState(state_v.string)) return;

        const sched_v = obj.get("scheduled_at") orelse return;
        if (sched_v != .string) return;
        if (sched_v.string.len > MAX_SCHEDULED_AT_BYTES) return;

        const cat_v = obj.get("created_at") orelse return;
        if (cat_v != .string) return;

        if (self.by_id.contains(id)) return;

        const stored = try self.cloneJobIntoOwned(.{
            .id = id,
            .customer_name = customer_name,
            .state = state_v.string,
            .scheduled_at = sched_v.string,
            .created_at = cat_v.string,
            // Propagate canonical cell hash so cellId survives brain restart.
            .cellId = cell_hash,
        });
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        if (cell_hash) |ch| self.indexCellHash(idx, ch); // resolve by cellHash too
    }

    /// RM-119 — ingest→job schema adapter (operator-approved 2026-05-19).
    /// The legacy gmail/Bricks ingest writes job cells in the D-RTC
    /// typed-cell schema `{intent,summary,display_name,state,site_ref,
    /// customer_refs,work_order_number,services,issuance_date,…}` — it
    /// has NO `"kind"` field, so `kindOfPayload` → .unknown and the
    /// replay skipped all of them (the field-reported "~150 missing
    /// jobs": 56 ingest-shape job cells invisible while only 6 `add
    /// job` probes showed). RM-115 migration faithfully preserved the
    /// ingest JSON; this is a READER adapter (no data mutation) that
    /// maps the ingest shape onto a v1 job record so the replay
    /// cursor surfaces them. Idempotent: id = hex(sha256(payload)
    /// [0..32]) is stable per cell, guarded by `by_id.contains`.
    /// Best-effort — a malformed ingest payload is skipped, never
    /// fatal (mirrors the other apply* paths' `catch return`).
    fn applyIngestJobPayload(
        self: *JobsStore,
        payload: []const u8,
        site_idx: *const std.StringHashMap([]const u8),
        cust_idx: *const std.StringHashMap(ResolvedContact),
        cell_hash: [32]u8,
    ) !void {
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            payload,
            .{},
        ) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const obj = parsed.value.object;

        // Discriminate the ingest job shape: no `kind`, but carries
        // `intent` + a work-order/site anchor. (Brain-native cells
        // always have `kind`; they take the applyPayload path.)
        if (obj.get("kind") != null) return;
        if (obj.get("intent") == null) return;
        if (obj.get("work_order_number") == null and obj.get("site_ref") == null) return;

        // Stable, deterministic id (idempotent across replays).
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(payload, &digest, .{});
        const id_hex = std.fmt.bytesToHex(digest, .lower); // [64]u8
        const id: []const u8 = id_hex[0..];
        if (self.by_id.contains(id)) return;

        // state ← ingest state if a canonical FSM state, else `lead`.
        var state: []const u8 = "lead";
        if (obj.get("state")) |st_v| {
            if (st_v == .string and isValidState(st_v.string)) state = st_v.string;
        }
        // created_at ← issuance_date (ISO) when present.
        var created_at: []const u8 = "";
        if (obj.get("issuance_date")) |iss_v| {
            if (iss_v == .string and iss_v.string.len > 0 and iss_v.string.len <= MAX_ISO_DATE_BYTES)
                created_at = iss_v.string;
        }

        // RM-121 — resolve the site address from site_ref.
        var site_address: []const u8 = "";
        if (strField(obj, "site_ref")) |sr| {
            if (site_idx.get(sr)) |addr| site_address = addr;
        }
        // RM-121 — work description = ingest `summary`.
        const description: []const u8 = strField(obj, "summary") orelse "";

        // RM-121 — resolve contacts from customer_refs and pick the
        // operator's point-of-contact. Rule (operator 2026-05-19):
        // the bold contact = the `primary:true` *tenant*; else the
        // first tenant; if there are NO tenants, the first agent /
        // property_manager; else the first ref.
        var refs_buf: [MAX_CUSTOMER_REFS]struct {
            cellId: [32]u8,
            role: []const u8,
            primary: bool,
            name: []const u8,
            phone: []const u8,
        } = undefined;
        var nrefs: usize = 0;
        if (obj.get("customer_refs")) |cr_v| {
            if (cr_v == .array) {
                for (cr_v.array.items) |el| {
                    if (nrefs >= MAX_CUSTOMER_REFS) break;
                    if (el != .object) continue;
                    const eo = el.object;
                    const cid = strField(eo, "cell_id") orelse continue;
                    var cb: [32]u8 = [_]u8{0} ** 32;
                    _ = std.fmt.hexToBytes(&cb, cid) catch {};
                    const rc: ResolvedContact = cust_idx.get(cid) orelse
                        .{ .name = "", .phone = "", .role = "" };
                    const role = strField(eo, "role") orelse rc.role;
                    var is_primary = false;
                    if (eo.get("primary")) |pv| {
                        if (pv == .bool) is_primary = pv.bool;
                    }
                    refs_buf[nrefs] = .{
                        .cellId = cb,
                        .role = role,
                        .primary = is_primary,
                        .name = rc.name,
                        .phone = rc.phone,
                    };
                    nrefs += 1;
                }
            }
        }
        // Pick the point-of-contact index per the rule.
        const isTenant = struct {
            fn f(r: []const u8) bool {
                return std.mem.eql(u8, r, "tenant");
            }
        }.f;
        const isAgentish = struct {
            fn f(r: []const u8) bool {
                return std.mem.eql(u8, r, "agent") or
                    std.mem.eql(u8, r, "property_manager") or
                    std.mem.eql(u8, r, "pm");
            }
        }.f;
        var poc: ?usize = null;
        for (refs_buf[0..nrefs], 0..) |r, i| {
            if (r.primary and isTenant(r.role)) {
                poc = i;
                break;
            }
        }
        if (poc == null) for (refs_buf[0..nrefs], 0..) |r, i| {
            if (isTenant(r.role)) {
                poc = i;
                break;
            }
        };
        if (poc == null) for (refs_buf[0..nrefs], 0..) |r, i| {
            if (isAgentish(r.role)) {
                poc = i;
                break;
            }
        };
        if (poc == null and nrefs > 0) poc = 0;

        // customer_name ← resolved point-of-contact name; fall back to
        // display_name with the trailing " (role)" stripped, then
        // "unknown".
        var customer_name: []const u8 = "unknown";
        if (obj.get("display_name")) |dn_v| {
            if (dn_v == .string and dn_v.string.len > 0) {
                var dn = dn_v.string;
                if (std.mem.lastIndexOf(u8, dn, " (")) |paren| {
                    if (paren > 0) dn = dn[0..paren];
                }
                if (dn.len > 0 and dn.len <= MAX_CUSTOMER_NAME_BYTES) customer_name = dn;
            }
        }
        if (poc) |pi| {
            if (refs_buf[pi].name.len > 0 and refs_buf[pi].name.len <= MAX_CUSTOMER_NAME_BYTES)
                customer_name = refs_buf[pi].name;
        }

        var stored = try self.cloneJobIntoOwned(.{
            .id = id,
            .customer_name = customer_name,
            .state = state,
            .scheduled_at = "",
            .created_at = created_at,
            // Stamp the content-addressed identity (the operator app's job id).
            .cellId = cell_hash,
        });

        // RM-121 — own the resolved strings + the CustomerRef array in
        // the just-appended OwnedStrings/OwnedRefs slots so they
        // outlive the transient resolve-index arena. On any alloc
        // failure we degrade gracefully (leave the field null) rather
        // than fail the whole record.
        const os = &self.owned_strings.items[self.owned_strings.items.len - 1];
        const orf = &self.owned_refs.items[self.owned_refs.items.len - 1];
        if (site_address.len > 0) {
            if (self.allocator.dupe(u8, site_address)) |d| {
                os.property_address = d;
                stored.propertyAddress = d;
            } else |_| {}
        }
        if (description.len > 0) {
            if (self.allocator.dupe(u8, description)) |d| {
                os.description = d;
                stored.description = d;
            } else |_| {}
        }
        // RM-125 — WO metadata so the operator sees scope/details
        // without the PDF: work order #, services, issued/due dates,
        // photo count. String fields owned in `os`; scalars inline.
        if (strField(obj, "work_order_number")) |wo| {
            if (self.allocator.dupe(u8, wo)) |d| {
                os.work_order_number = d;
                stored.workOrderNumber = d;
            } else |_| {}
        }
        if (strField(obj, "issuance_date")) |iss| {
            if (self.allocator.dupe(u8, iss)) |d| {
                os.issuance_date = d;
                stored.issuanceDate = d;
            } else |_| {}
        }
        if (strField(obj, "due_date")) |dd| {
            if (self.allocator.dupe(u8, dd)) |d| {
                os.due_date = d;
                stored.dueDate = d;
            } else |_| {}
        }
        if (obj.get("services")) |sv| {
            if (sv == .array and sv.array.items.len > 0) {
                var sb: std.ArrayList(u8) = .{};
                defer sb.deinit(self.allocator);
                var first = true;
                for (sv.array.items) |el| {
                    if (el != .string or el.string.len == 0) continue;
                    if (!first) sb.appendSlice(self.allocator, ", ") catch break;
                    sb.appendSlice(self.allocator, el.string) catch break;
                    first = false;
                }
                if (sb.items.len > 0) {
                    if (self.allocator.dupe(u8, sb.items)) |d| {
                        os.services = d;
                        stored.services = d;
                    } else |_| {}
                }
            }
        }
        if (obj.get("picture_count")) |pc| {
            if (pc == .integer and pc.integer >= 0)
                stored.photoCount = @intCast(pc.integer);
        }
        if (obj.get("has_pictures")) |hp| {
            if (hp == .bool) stored.hasPhotos = hp.bool;
        }
        if (nrefs > 0) build_refs: {
            const arr = self.allocator.alloc(CustomerRef, nrefs) catch break :build_refs;
            // Exactly 3 owned strings per ref (role, name, phone) —
            // dup'd unconditionally (empty → a freeable 0-len slice)
            // so `bag.len == nrefs*3` and every element is a valid
            // allocation freeAll can release (no sub-slice / mixed-
            // length free).
            const bag = self.allocator.alloc([]u8, nrefs * 3) catch {
                self.allocator.free(arr);
                break :build_refs;
            };
            for (refs_buf[0..nrefs], 0..) |r, i| {
                const ro = self.allocator.dupe(u8, r.role) catch break :build_refs;
                const na = self.allocator.dupe(u8, r.name) catch break :build_refs;
                const ph = self.allocator.dupe(u8, r.phone) catch break :build_refs;
                bag[i * 3 + 0] = ro;
                bag[i * 3 + 1] = na;
                bag[i * 3 + 2] = ph;
                arr[i] = .{
                    .cellId = r.cellId,
                    .role = ro,
                    .primary = r.primary,
                    .name = na,
                    .phone = ph,
                };
            }
            orf.customer_refs = arr;
            orf.contact_strings = bag;
            stored.customerRefs = arr;
        }

        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        self.indexCellHash(idx, cell_hash); // resolve by cellHash too
    }

    fn applyV2CreatedPayload(self: *JobsStore, obj: std.json.ObjectMap, cell_hash: ?[32]u8) !void {
        const id_v = obj.get("id") orelse return;
        if (id_v != .string or id_v.string.len != 64) return;
        const customer_name = (obj.get("customer_name") orelse return).string;
        const state = (obj.get("state") orelse return).string;
        const scheduled_at = (obj.get("scheduled_at") orelse return).string;
        const created_at = (obj.get("created_at") orelse return).string;

        const type_hash_v = obj.get("typeHash") orelse return;
        if (type_hash_v != .string or type_hash_v.string.len != 64) return;
        const site_ref_v = obj.get("siteRef") orelse return;
        if (site_ref_v != .string or site_ref_v.string.len != 64) return;

        if (customer_name.len == 0 or customer_name.len > MAX_CUSTOMER_NAME_BYTES) return;
        if (!isValidState(state)) return;
        if (scheduled_at.len > MAX_SCHEDULED_AT_BYTES) return;

        if (self.by_id.contains(id_v.string)) return;

        var cell_id: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&cell_id, id_v.string) catch return;
        var type_hash: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&type_hash, type_hash_v.string) catch return;
        var site_ref: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&site_ref, site_ref_v.string) catch return;

        const work_order_number: ?[]const u8 = optStringField(obj, "workOrderNumber");
        const issuance_date: ?[]const u8 = optStringField(obj, "issuanceDate");
        const due_date: ?[]const u8 = optStringField(obj, "dueDate");
        const property_key: ?[]const u8 = optStringField(obj, "propertyKey");

        if (work_order_number) |w| { if (w.len > MAX_WORK_ORDER_NUMBER_BYTES) return; }
        if (issuance_date) |d| { if (d.len > MAX_ISO_DATE_BYTES) return; }
        if (due_date) |d| { if (d.len > MAX_ISO_DATE_BYTES) return; }
        if (property_key) |p| { if (p.len > MAX_PROPERTY_KEY_BYTES) return; }

        var billing_party: ?BillingParty = null;
        if (obj.get("billingParty")) |bp_v| {
            switch (bp_v) {
                .object => |bp_obj| {
                    const bp_type_v = bp_obj.get("type") orelse return;
                    if (bp_type_v != .string) return;
                    if (!isValidBillingPartyType(bp_type_v.string)) return;
                    const bp_name_v = bp_obj.get("name") orelse return;
                    if (bp_name_v != .string) return;
                    if (bp_name_v.string.len == 0 or bp_name_v.string.len > MAX_BILLING_PARTY_NAME_BYTES) return;
                    billing_party = .{ .type = bp_type_v.string, .name = bp_name_v.string };
                },
                .null => billing_party = null,
                else => return,
            }
        }

        const has_photos_v = obj.get("hasPhotos") orelse return;
        if (has_photos_v != .bool) return;
        const has_photos = has_photos_v.bool;

        var photo_count: ?u32 = null;
        if (obj.get("photoCount")) |pc_v| {
            switch (pc_v) {
                .integer => |i| {
                    if (i < 0 or i > std.math.maxInt(u32)) return;
                    photo_count = @intCast(i);
                },
                .null => photo_count = null,
                else => return,
            }
        }

        const customer_refs_v = obj.get("customerRefs") orelse return;
        if (customer_refs_v != .array) return;
        if (customer_refs_v.array.items.len > MAX_CUSTOMER_REFS) return;
        var cref_stack: [MAX_CUSTOMER_REFS]CustomerRef = undefined;
        var primary_count: usize = 0;
        for (customer_refs_v.array.items, 0..) |entry_v, i| {
            if (entry_v != .object) return;
            const eobj = entry_v.object;
            const cid_v = eobj.get("cellId") orelse return;
            if (cid_v != .string or cid_v.string.len != 64) return;
            const role_v = eobj.get("role") orelse return;
            if (role_v != .string) return;
            if (!isValidCustomerRole(role_v.string)) return;
            const prim_v = eobj.get("primary") orelse return;
            if (prim_v != .bool) return;
            var cid: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&cid, cid_v.string) catch return;
            cref_stack[i] = .{ .cellId = cid, .role = role_v.string, .primary = prim_v.bool };
            if (prim_v.bool) primary_count += 1;
        }
        if (customer_refs_v.array.items.len > 0 and primary_count != 1) return;

        const attachment_refs_v = obj.get("attachmentRefs") orelse return;
        if (attachment_refs_v != .array) return;
        if (attachment_refs_v.array.items.len > MAX_ATTACHMENT_REFS) return;
        var aref_stack: [MAX_ATTACHMENT_REFS][32]u8 = undefined;
        for (attachment_refs_v.array.items, 0..) |entry_v, i| {
            if (entry_v != .string or entry_v.string.len != 64) return;
            _ = std.fmt.hexToBytes(&aref_stack[i], entry_v.string) catch return;
        }

        if (photo_count) |c| {
            if (has_photos and c == 0) return;
            if (!has_photos and c > 0) return;
        }

        const signed_by_opt: ?[33]u8 = blk: {
            if (obj.get("signedBy")) |v| {
                if (v == .string and v.string.len == 66) {
                    var sb: [33]u8 = undefined;
                    if (std.fmt.hexToBytes(&sb, v.string)) |_| break :blk sb else |_| {}
                }
            }
            break :blk null;
        };
        const signature_opt: ?[64]u8 = blk: {
            if (obj.get("signature")) |v| {
                if (v == .string and v.string.len == 128) {
                    var sig: [64]u8 = undefined;
                    if (std.fmt.hexToBytes(&sig, v.string)) |_| break :blk sig else |_| {}
                }
            }
            break :blk null;
        };

        const cref_input: []const CustomerRef = cref_stack[0..customer_refs_v.array.items.len];
        const aref_input: []const [32]u8 = aref_stack[0..attachment_refs_v.array.items.len];

        const stored = try self.cloneJobV2IntoOwned(.{
            .cellId = cell_id,
            .typeHash = type_hash,
            .customer_name = customer_name,
            .state = state,
            .scheduled_at = scheduled_at,
            .created_at = created_at,
            .workOrderNumber = work_order_number,
            .issuanceDate = issuance_date,
            .dueDate = due_date,
            .billingParty = billing_party,
            .hasPhotos = has_photos,
            .photoCount = photo_count,
            .propertyKey = property_key,
            .siteRef = site_ref,
            .customerRefs = cref_input,
            .attachmentRefs = aref_input,
            .signedBy = signed_by_opt,
            .signature = signature_opt,
        }, id_v.string);

        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].id, idx);
        if (cell_hash) |ch| self.indexCellHash(idx, ch); // resolve by cellHash too
    }

    fn applyUpdatedPayload(self: *JobsStore, obj: std.json.ObjectMap) !void {
        const id_v = obj.get("id") orelse return;
        if (id_v != .string) return;
        const id = id_v.string;
        const idx = self.by_id.get(id) orelse return;
        const current = self.records.items[idx];

        // Extract ts from payload; default to std.math.minInt so that cells
        // without a ts field are still applied (they were written before ts
        // was added to the payload format).
        const cell_ts: i64 = blk: {
            if (obj.get("ts")) |v| {
                switch (v) {
                    .integer => |i| break :blk i,
                    else => {},
                }
            }
            break :blk std.math.minInt(i64);
        };

        // Last-wins: only apply if cell_ts >= the highest ts we have seen for
        // this id.  Use >= (not >) so that cells without ts (minInt) are applied
        // at least once, but a later real ts will always override them.
        const prev_ts = self.by_id_ts.get(id) orelse std.math.minInt(i64);
        if (cell_ts < prev_ts) return;
        // Update tracked ts (put uses owned key from by_id map which outlives replay).
        try self.by_id_ts.put(self.records.items[idx].id, cell_ts);

        const new_state: []const u8 = blk: {
            if (obj.get("state")) |v| {
                if (v == .string and isValidState(v.string)) break :blk v.string;
            }
            break :blk current.state;
        };
        const new_sched: []const u8 = blk: {
            if (obj.get("scheduled_at")) |v| {
                if (v == .string and v.string.len <= MAX_SCHEDULED_AT_BYTES) break :blk v.string;
            }
            break :blk current.scheduled_at;
        };

        // Allocate owned copies of the updated fields.
        const owned_state = try self.allocator.dupe(u8, new_state);
        errdefer self.allocator.free(owned_state);
        const owned_sched = try self.allocator.dupe(u8, new_sched);
        errdefer self.allocator.free(owned_sched);

        const extra = OwnedStrings{
            .id = try self.allocator.dupe(u8, ""),
            .customer_name = try self.allocator.dupe(u8, ""),
            .state = owned_state,
            .scheduled_at = owned_sched,
            .created_at = try self.allocator.dupe(u8, ""),
        };
        try self.owned_strings.append(self.allocator, extra);

        var updated = current;
        updated.state = owned_state;
        updated.scheduled_at = owned_sched;
        self.records.items[idx] = updated;
    }

    fn applySignedPayload(self: *JobsStore, obj: std.json.ObjectMap) !void {
        const cell_v = obj.get("cellId") orelse return;
        if (cell_v != .string or cell_v.string.len != 64) return;
        var cell_id: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&cell_id, cell_v.string) catch return;

        const sb_v = obj.get("signedBy") orelse return;
        if (sb_v != .string or sb_v.string.len != 66) return;
        var signed_by: [33]u8 = undefined;
        _ = std.fmt.hexToBytes(&signed_by, sb_v.string) catch return;

        const sig_v = obj.get("signature") orelse return;
        if (sig_v != .string or sig_v.string.len != 128) return;
        var signature: [64]u8 = undefined;
        _ = std.fmt.hexToBytes(&signature, sig_v.string) catch return;

        for (self.records.items, 0..) |row, idx| {
            const row_cid = row.cellId orelse continue;
            if (std.mem.eql(u8, &row_cid, &cell_id)) {
                self.records.items[idx].signedBy = signed_by;
                self.records.items[idx].signature = signature;
                return;
            }
        }
    }

    // ── Clone helpers ──────────────────────────────────────────────────

    fn cloneJobIntoOwned(self: *JobsStore, job: Job) !Job {
        var owned = OwnedStrings{
            .id = undefined,
            .customer_name = undefined,
            .state = undefined,
            .scheduled_at = undefined,
            .created_at = undefined,
        };
        owned.id = try self.allocator.dupe(u8, job.id);
        errdefer self.allocator.free(owned.id);
        owned.customer_name = try self.allocator.dupe(u8, job.customer_name);
        errdefer self.allocator.free(owned.customer_name);
        owned.state = try self.allocator.dupe(u8, job.state);
        errdefer self.allocator.free(owned.state);
        owned.scheduled_at = try self.allocator.dupe(u8, job.scheduled_at);
        errdefer self.allocator.free(owned.scheduled_at);
        owned.created_at = try self.allocator.dupe(u8, job.created_at);
        errdefer self.allocator.free(owned.created_at);

        try self.owned_strings.append(self.allocator, owned);
        const refs_entry = OwnedRefs{};
        try self.owned_refs.append(self.allocator, refs_entry);

        return .{
            .version = 1,
            .id = owned.id,
            .customer_name = owned.customer_name,
            .state = owned.state,
            .scheduled_at = owned.scheduled_at,
            .created_at = owned.created_at,
            // Preserve canonical cell hash when set by append/applyPayload.
            .cellId = job.cellId,
        };
    }

    fn cloneJobV2IntoOwned(self: *JobsStore, payload: JobV2Payload, id_hex: []const u8) !Job {
        var owned = OwnedStrings{
            .id = undefined,
            .customer_name = undefined,
            .state = undefined,
            .scheduled_at = undefined,
            .created_at = undefined,
        };
        owned.id = try self.allocator.dupe(u8, id_hex);
        errdefer self.allocator.free(owned.id);
        owned.customer_name = try self.allocator.dupe(u8, payload.customer_name);
        errdefer self.allocator.free(owned.customer_name);
        owned.state = try self.allocator.dupe(u8, payload.state);
        errdefer self.allocator.free(owned.state);
        owned.scheduled_at = try self.allocator.dupe(u8, payload.scheduled_at);
        errdefer self.allocator.free(owned.scheduled_at);
        owned.created_at = try self.allocator.dupe(u8, payload.created_at);
        errdefer self.allocator.free(owned.created_at);

        if (payload.workOrderNumber) |w| {
            owned.work_order_number = try self.allocator.dupe(u8, w);
        }
        errdefer if (owned.work_order_number) |s| self.allocator.free(s);

        if (payload.issuanceDate) |d| {
            owned.issuance_date = try self.allocator.dupe(u8, d);
        }
        errdefer if (owned.issuance_date) |s| self.allocator.free(s);

        if (payload.dueDate) |d| {
            owned.due_date = try self.allocator.dupe(u8, d);
        }
        errdefer if (owned.due_date) |s| self.allocator.free(s);

        var owned_billing: ?BillingParty = null;
        if (payload.billingParty) |bp| {
            owned.billing_type = try self.allocator.dupe(u8, bp.type);
            errdefer self.allocator.free(owned.billing_type.?);
            owned.billing_name = try self.allocator.dupe(u8, bp.name);
            errdefer self.allocator.free(owned.billing_name.?);
            owned_billing = .{ .type = owned.billing_type.?, .name = owned.billing_name.? };
        }

        if (payload.propertyKey) |p| {
            owned.property_key = try self.allocator.dupe(u8, p);
        }
        errdefer if (owned.property_key) |s| self.allocator.free(s);

        // Clone CustomerRefs (roles owned; cellId + primary by-value)
        var owned_crefs: ?[]CustomerRef = null;
        var owned_role_strings: ?[][]u8 = null;
        if (payload.customerRefs.len == 0) {
            owned_crefs = &[_]CustomerRef{};
        } else {
            const role_strs = try self.allocator.alloc([]u8, payload.customerRefs.len);
            errdefer self.allocator.free(role_strs);
            var role_count: usize = 0;
            errdefer for (role_strs[0..role_count]) |r| self.allocator.free(r);
            for (payload.customerRefs, 0..) |src, i| {
                role_strs[i] = try self.allocator.dupe(u8, src.role);
                role_count += 1;
            }
            const crefs = try self.allocator.alloc(CustomerRef, payload.customerRefs.len);
            errdefer self.allocator.free(crefs);
            for (payload.customerRefs, 0..) |src, i| {
                crefs[i] = .{ .cellId = src.cellId, .role = role_strs[i], .primary = src.primary };
            }
            owned_crefs = crefs;
            owned_role_strings = role_strs;
        }
        owned.customer_roles = owned_role_strings;

        // Clone attachmentRefs
        var owned_arefs: ?[]const [32]u8 = null;
        if (payload.attachmentRefs.len == 0) {
            owned_arefs = &[_][32]u8{};
        } else {
            const arefs = try self.allocator.alloc([32]u8, payload.attachmentRefs.len);
            errdefer self.allocator.free(arefs);
            for (payload.attachmentRefs, 0..) |src, i| {
                arefs[i] = src;
            }
            owned_arefs = arefs;
        }

        try self.owned_strings.append(self.allocator, owned);
        const refs_entry = OwnedRefs{
            .customer_refs = owned_crefs,
            .attachment_refs = if (owned_arefs) |ar|
                if (ar.len == 0) null else @constCast(ar)
            else
                null,
        };
        try self.owned_refs.append(self.allocator, refs_entry);

        // Adjust attachment_refs pointer for the return value
        const aref_return: ?[]const [32]u8 = owned_arefs;

        return .{
            .version = 2,
            .id = owned.id,
            .customer_name = owned.customer_name,
            .state = owned.state,
            .scheduled_at = owned.scheduled_at,
            .created_at = owned.created_at,
            .cellId = payload.cellId,
            .typeHash = payload.typeHash,
            .workOrderNumber = owned.work_order_number,
            .issuanceDate = owned.issuance_date,
            .dueDate = owned.due_date,
            .billingParty = owned_billing,
            .hasPhotos = payload.hasPhotos,
            .photoCount = payload.photoCount,
            .propertyKey = owned.property_key,
            .siteRef = payload.siteRef,
            .customerRefs = owned_crefs,
            .attachmentRefs = aref_return,
            .signedBy = payload.signedBy,
            .signature = payload.signature,
        };
    }
};

// ── Serialisation ────────────────────────────────────────────────────────────

fn serializeJob(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    job: Job,
    ts: i64,
) !void {
    if (job.version == 2) {
        try serializeJobV2(allocator, buf, job, ts);
    } else {
        try serializeJobV1(allocator, buf, job, ts);
    }
}

fn serializeJobV1(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    job: Job,
    ts: i64,
) !void {
    try buf.print(allocator, "{{\"ts\":{d},\"kind\":\"created\",\"id\":", .{ts});
    try writeJsonString(allocator, buf, job.id);
    try buf.appendSlice(allocator, ",\"customer_name\":");
    try writeJsonString(allocator, buf, job.customer_name);
    try buf.appendSlice(allocator, ",\"state\":");
    try writeJsonString(allocator, buf, job.state);
    try buf.appendSlice(allocator, ",\"scheduled_at\":");
    try writeJsonString(allocator, buf, job.scheduled_at);
    try buf.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, buf, job.created_at);
    try buf.append(allocator, '}');
}

fn serializeJobV2(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    job: Job,
    ts: i64,
) !void {
    const type_hash = job.typeHash orelse return error.InvalidInput;
    const site_ref = job.siteRef orelse return error.InvalidInput;

    try buf.print(allocator, "{{\"ts\":{d},\"kind\":\"created\",\"id\":", .{ts});
    try writeJsonString(allocator, buf, job.id);
    try buf.appendSlice(allocator, ",\"typeHash\":\"");
    try writeHex32(allocator, buf, &type_hash);
    try buf.appendSlice(allocator, "\",\"customer_name\":");
    try writeJsonString(allocator, buf, job.customer_name);
    try buf.appendSlice(allocator, ",\"state\":");
    try writeJsonString(allocator, buf, job.state);
    try buf.appendSlice(allocator, ",\"scheduled_at\":");
    try writeJsonString(allocator, buf, job.scheduled_at);
    try buf.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, buf, job.created_at);

    try buf.appendSlice(allocator, ",\"workOrderNumber\":");
    try writeOptString(allocator, buf, job.workOrderNumber);
    try buf.appendSlice(allocator, ",\"issuanceDate\":");
    try writeOptString(allocator, buf, job.issuanceDate);
    try buf.appendSlice(allocator, ",\"dueDate\":");
    try writeOptString(allocator, buf, job.dueDate);

    try buf.appendSlice(allocator, ",\"billingParty\":");
    if (job.billingParty) |bp| {
        try buf.appendSlice(allocator, "{\"type\":");
        try writeJsonString(allocator, buf, bp.type);
        try buf.appendSlice(allocator, ",\"name\":");
        try writeJsonString(allocator, buf, bp.name);
        try buf.append(allocator, '}');
    } else {
        try buf.appendSlice(allocator, "null");
    }

    try buf.appendSlice(allocator, ",\"hasPhotos\":");
    try buf.appendSlice(allocator, if (job.hasPhotos orelse false) "true" else "false");
    try buf.appendSlice(allocator, ",\"photoCount\":");
    if (job.photoCount) |c| {
        try buf.print(allocator, "{d}", .{c});
    } else {
        try buf.appendSlice(allocator, "null");
    }
    try buf.appendSlice(allocator, ",\"propertyKey\":");
    try writeOptString(allocator, buf, job.propertyKey);

    try buf.appendSlice(allocator, ",\"siteRef\":\"");
    try writeHex32(allocator, buf, &site_ref);
    try buf.append(allocator, '"');

    try buf.appendSlice(allocator, ",\"customerRefs\":[");
    if (job.customerRefs) |crefs| {
        for (crefs, 0..) |cref, i| {
            if (i != 0) try buf.append(allocator, ',');
            try buf.appendSlice(allocator, "{\"cellId\":\"");
            try writeHex32(allocator, buf, &cref.cellId);
            try buf.appendSlice(allocator, "\",\"role\":");
            try writeJsonString(allocator, buf, cref.role);
            try buf.appendSlice(allocator, ",\"primary\":");
            try buf.appendSlice(allocator, if (cref.primary) "true" else "false");
            try buf.append(allocator, '}');
        }
    }
    try buf.append(allocator, ']');

    try buf.appendSlice(allocator, ",\"attachmentRefs\":[");
    if (job.attachmentRefs) |arefs| {
        for (arefs, 0..) |aref, i| {
            if (i != 0) try buf.append(allocator, ',');
            try buf.append(allocator, '"');
            try writeHex32(allocator, buf, &aref);
            try buf.append(allocator, '"');
        }
    }
    try buf.append(allocator, ']');

    try buf.appendSlice(allocator, ",\"signedBy\":");
    if (job.signedBy) |sb| {
        try buf.append(allocator, '"');
        try writeHex33(allocator, buf, &sb);
        try buf.append(allocator, '"');
    } else {
        try buf.appendSlice(allocator, "null");
    }
    try buf.appendSlice(allocator, ",\"signature\":");
    if (job.signature) |sig| {
        try buf.append(allocator, '"');
        try writeHex64(allocator, buf, &sig);
        try buf.append(allocator, '"');
    } else {
        try buf.appendSlice(allocator, "null");
    }

    try buf.append(allocator, '}');
}

/// Serialise a state-transition event as {"ts":...,"kind":"updated","id":...,...}.
/// The `ts` field is used on two-pass replay to apply "updated" cells in
/// ascending timestamp order, ensuring the last transition wins.
fn serializeJobUpdated(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    job: Job,
    ts: i64,
) !void {
    try buf.print(allocator, "{{\"ts\":{d},\"kind\":\"updated\",\"id\":", .{ts});
    try writeJsonString(allocator, buf, job.id);
    try buf.appendSlice(allocator, ",\"customer_name\":");
    try writeJsonString(allocator, buf, job.customer_name);
    try buf.appendSlice(allocator, ",\"state\":");
    try writeJsonString(allocator, buf, job.state);
    try buf.appendSlice(allocator, ",\"scheduled_at\":");
    try writeJsonString(allocator, buf, job.scheduled_at);
    try buf.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, buf, job.created_at);
    try buf.append(allocator, '}');
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

fn writeOptString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: ?[]const u8) !void {
    if (s) |str| {
        try writeJsonString(allocator, out, str);
    } else {
        try out.appendSlice(allocator, "null");
    }
}

fn writeHex32(allocator: std.mem.Allocator, out: *std.ArrayList(u8), bytes: *const [32]u8) !void {
    const hex = std.fmt.bytesToHex(bytes.*, .lower);
    try out.appendSlice(allocator, hex[0..]);
}

fn writeHex33(allocator: std.mem.Allocator, out: *std.ArrayList(u8), bytes: *const [33]u8) !void {
    const hex = std.fmt.bytesToHex(bytes.*, .lower);
    try out.appendSlice(allocator, hex[0..]);
}

fn writeHex64(allocator: std.mem.Allocator, out: *std.ArrayList(u8), bytes: *const [64]u8) !void {
    const hex = std.fmt.bytesToHex(bytes.*, .lower);
    try out.appendSlice(allocator, hex[0..]);
}

fn optStringField(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    if (obj.get(key)) |v| {
        switch (v) {
            .string => |s| return s,
            else => return null,
        }
    }
    return null;
}

// ── Inline tests ─────────────────────────────────────────────────────────────

fn testClock() i64 {
    return 1_700_000_000;
}

/// Monotonically incrementing clock for tests that need ordered timestamps.
/// Uses a thread-local so parallel test runs don't race.
threadlocal var mono_clock_val: i64 = 1_700_000_000;
fn monoClock() i64 {
    const v = mono_clock_val;
    mono_clock_val += 1;
    return v;
}

fn resetMonoClock() void {
    mono_clock_val = 1_700_000_000;
}

// Import lmdb + lmdb_cell_store so inline tests can open an env.
const lmdb = @import("lmdb");
const lmdb_cell_store_test_mod = @import("lmdb_cell_store");

fn openInlineTestEnv(dir: []const u8) !lmdb.Env {
    return lmdb.Env.open(dir, .{
        .max_dbs = 8,
        .map_size = 4 * 1024 * 1024,
        .open_flags = lmdb.EnvFlags.NOSYNC,
    });
}

test "isValidState recognises the thirteen canonical FSM states" {
    try std.testing.expectEqual(@as(usize, 13), JOB_FSM_STATES.len);
    try std.testing.expect(isValidState("lead"));
    try std.testing.expect(isValidState("qualified"));
    try std.testing.expect(isValidState("visit_pending"));
    try std.testing.expect(isValidState("visit_scheduled"));
    try std.testing.expect(isValidState("visited"));
    try std.testing.expect(isValidState("quoted"));
    try std.testing.expect(isValidState("authorized"));
    try std.testing.expect(isValidState("scheduled"));
    try std.testing.expect(isValidState("in_progress"));
    try std.testing.expect(isValidState("completed"));
    try std.testing.expect(isValidState("invoiced"));
    try std.testing.expect(isValidState("paid"));
    try std.testing.expect(isValidState("closed"));
    try std.testing.expect(!isValidState(""));
    try std.testing.expect(!isValidState("paused"));
    try std.testing.expect(!isValidState("LEAD"));
}

test "JobsStore: append → findAll → findById round-trip" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, testClock);
    defer store.deinit();

    const j = Job{
        .id = "00000000000000000000000000000001",
        .customer_name = "Acme Corp",
        .state = "lead",
        .scheduled_at = "2026-05-15T09:00:00Z",
        .created_at = "2026-05-02T10:00:00Z",
    };
    try std.testing.expectEqual(JobsStore.AppendOutcome.created, try store.append(j));
    try std.testing.expectEqual(@as(usize, 1), store.count());

    const all = try store.findAll(allocator);
    defer allocator.free(all);
    try std.testing.expectEqualStrings("Acme Corp", all[0].customer_name);
    try std.testing.expectEqualStrings("lead", all[0].state);

    const got = store.findById("00000000000000000000000000000001") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("Acme Corp", got.customer_name);
    try std.testing.expect(store.findById("does-not-exist") == null);
}

test "JobsStore: idempotent re-append returns already_exists" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, testClock);
    defer store.deinit();

    const j = Job{
        .id = "00000000000000000000000000000002",
        .customer_name = "Globex",
        .state = "quoted",
        .scheduled_at = "",
        .created_at = "2026-05-02T10:00:00Z",
    };
    try std.testing.expectEqual(JobsStore.AppendOutcome.created, try store.append(j));
    try std.testing.expectEqual(JobsStore.AppendOutcome.already_exists, try store.append(j));
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

test "JobsStore: findByState filters" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, testClock);
    defer store.deinit();

    _ = try store.append(.{ .id = "j-001", .customer_name = "A", .state = "lead", .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z" });
    _ = try store.append(.{ .id = "j-002", .customer_name = "B", .state = "scheduled", .scheduled_at = "2026-05-15T09:00Z", .created_at = "2026-01-02T00:00:00Z" });
    _ = try store.append(.{ .id = "j-003", .customer_name = "C", .state = "lead", .scheduled_at = "", .created_at = "2026-01-03T00:00:00Z" });

    const leads = try store.findByState(allocator, "lead");
    defer allocator.free(leads);
    try std.testing.expectEqual(@as(usize, 2), leads.len);

    const sched = try store.findByState(allocator, "scheduled");
    defer allocator.free(sched);
    try std.testing.expectEqual(@as(usize, 1), sched.len);
    try std.testing.expectEqualStrings("B", sched[0].customer_name);

    const none = try store.findByState(allocator, "paid");
    defer allocator.free(none);
    try std.testing.expectEqual(@as(usize, 0), none.len);
}

test "JobsStore: rejects invalid state / empty id / oversized customer_name" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, testClock);
    defer store.deinit();

    try std.testing.expectError(StoreError.invalid_state, store.append(.{
        .id = "j-bad-state", .customer_name = "X", .state = "PAUSED",
        .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z",
    }));
    try std.testing.expectError(StoreError.invalid_id, store.append(.{
        .id = "", .customer_name = "X", .state = "lead",
        .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z",
    }));
    try std.testing.expectError(StoreError.invalid_customer_name, store.append(.{
        .id = "j-empty-cust", .customer_name = "", .state = "lead",
        .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z",
    }));
}

test "JobsStore: wide field envelopes round-trip correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, testClock);
    defer store.deinit();

    var name_buf: [MAX_CUSTOMER_NAME_BYTES]u8 = undefined;
    var sched_buf: [MAX_SCHEDULED_AT_BYTES]u8 = undefined;
    @memset(&name_buf, 'n');
    @memset(&sched_buf, 's');

    _ = try store.append(.{
        .id = "00000000000000000000000000000001",
        .customer_name = &name_buf,
        .state = "scheduled",
        .scheduled_at = &sched_buf,
        .created_at = "2026-05-02T10:00:00Z",
    });
    try std.testing.expectEqual(@as(usize, 1), store.count());

    const got = store.findById("00000000000000000000000000000001") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("00000000000000000000000000000001", got.id);
    try std.testing.expectEqualStrings(&name_buf, got.customer_name);
    try std.testing.expectEqualStrings("scheduled", got.state);
    try std.testing.expectEqualStrings(&sched_buf, got.scheduled_at);
}

test "JobsStore: updateState transitions an existing job" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, testClock);
    defer store.deinit();

    _ = try store.append(.{ .id = "j-fsm-001", .customer_name = "Acme", .state = "lead", .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z" });
    const updated = try store.updateState("j-fsm-001", "quoted", null);
    try std.testing.expectEqualStrings("quoted", updated.state);

    const got = store.findById("j-fsm-001") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("quoted", got.state);
    try std.testing.expectEqualStrings("Acme", got.customer_name);
}

test "JobsStore: updateState updates scheduled_at when supplied" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, testClock);
    defer store.deinit();

    _ = try store.append(.{ .id = "j-fsm-sched", .customer_name = "Acme", .state = "quoted", .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z" });
    const updated = try store.updateState("j-fsm-sched", "scheduled", "2026-05-15T09:00:00Z");
    try std.testing.expectEqualStrings("scheduled", updated.state);
    try std.testing.expectEqualStrings("2026-05-15T09:00:00Z", updated.scheduled_at);

    const started = try store.updateState("j-fsm-sched", "in_progress", null);
    try std.testing.expectEqualStrings("in_progress", started.state);
    try std.testing.expectEqualStrings("2026-05-15T09:00:00Z", started.scheduled_at);
}

test "JobsStore: updateState rejects unknown id and invalid state" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, testClock);
    defer store.deinit();

    try std.testing.expectError(error.not_found, store.updateState("nope", "quoted", null));

    _ = try store.append(.{ .id = "j-fsm-002", .customer_name = "Acme", .state = "lead", .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z" });
    try std.testing.expectError(StoreError.invalid_state, store.updateState("j-fsm-002", "PAUSED", null));
}

test "JobsStore: replay rebuilds in-memory state after updateState" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();

    // Reset the monotonic clock so this test is deterministic regardless of
    // the order in which the test runner executes inline tests.
    resetMonoClock();

    {
        var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
        const cs = cs_impl.store();
        // Use monoClock so each updateState call produces a distinct ts.
        // This ensures that on replay the last-written "updated" cell
        // (ts = 1_700_000_002) beats the earlier "quoted" cell (ts = 1_700_000_001).
        var store = try JobsStore.init(allocator, &cs, monoClock);
        defer store.deinit();
        _ = try store.append(.{ .id = "j-fsm-replay", .customer_name = "Acme", .state = "lead", .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z" });
        _ = try store.updateState("j-fsm-replay", "quoted", null);
        _ = try store.updateState("j-fsm-replay", "scheduled", "2026-05-15T09:00:00Z");
    }

    resetMonoClock();
    var cs_impl2 = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs2 = cs_impl2.store();
    var store2 = try JobsStore.init(allocator, &cs2, monoClock);
    defer store2.deinit();
    const got = store2.findById("j-fsm-replay") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("scheduled", got.state);
    try std.testing.expectEqualStrings("2026-05-15T09:00:00Z", got.scheduled_at);
}

test "JobsStore: replay rebuilds in-memory state" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();

    {
        var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
        const cs = cs_impl.store();
        var store = try JobsStore.init(allocator, &cs, testClock);
        defer store.deinit();
        _ = try store.append(.{ .id = "j-001", .customer_name = "A", .state = "lead", .scheduled_at = "", .created_at = "2026-01-01T00:00:00Z" });
        _ = try store.append(.{ .id = "j-002", .customer_name = "B \"quoted\"", .state = "quoted", .scheduled_at = "2026-05-15T09:00Z", .created_at = "2026-01-02T00:00:00Z" });
    }

    var cs_impl2 = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs2 = cs_impl2.store();
    var store2 = try JobsStore.init(allocator, &cs2, testClock);
    defer store2.deinit();
    try std.testing.expectEqual(@as(usize, 2), store2.count());
    const got = store2.findById("j-002") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("B \"quoted\"", got.customer_name);
}

test "JobsStore: rescanCreatedCells picks up a cell minted after boot (store-split fix)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    // The jobs handler's store — boots over an empty cell store, so
    // its in-memory by_id index starts empty.
    var handler_store = try JobsStore.init(allocator, &cs, testClock);
    defer handler_store.deinit();

    // Simulate a gmail reingest landing a NEW job cell into the SAME
    // shared entity store AFTER the handler booted (a separate writer
    // — the entity.encode walker in production — over the same env).
    var reingest = try JobsStore.init(allocator, &cs, testClock);
    defer reingest.deinit();
    _ = try reingest.append(.{ .id = "j-reingested", .customer_name = "Pergola Co", .state = "lead", .scheduled_at = "", .created_at = "2026-05-10T00:00:00Z" });

    // Stale index: the handler's store cannot see it yet — this is
    // exactly the "store-split" not_found symptom (the cell IS in the
    // shared env; the agent walkers see it; the handler index doesn't).
    try std.testing.expect(handler_store.findById("j-reingested") == null);

    // Index-liveness: one incremental rescan and the post-boot cell is
    // indexed + transitionable via chat.
    handler_store.rescanCreatedCells();
    const found = handler_store.findById("j-reingested") orelse return error.RescanMissedCell;
    try std.testing.expectEqualStrings("lead", found.state);

    const qualified = try handler_store.updateState("j-reingested", "qualified", null);
    try std.testing.expectEqualStrings("qualified", qualified.state);

    // Idempotent: a second rescan neither duplicates the record nor
    // clobbers the just-applied transition (pass-1 contains-guard +
    // updated cells skipped on rescan).
    const before_count = handler_store.count();
    handler_store.rescanCreatedCells();
    try std.testing.expectEqual(before_count, handler_store.count());
    const after = handler_store.findById("j-reingested") orelse return error.RescanMissedCell;
    try std.testing.expectEqualStrings("qualified", after.state);
}

test "JobsStore: RM-119 ingest-shape job cell is surfaced via the schema adapter" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    var store = try JobsStore.init(allocator, &cs, testClock);
    defer store.deinit();

    // A real gmail/Bricks ingest job payload shape — NO `"kind"`,
    // carries `intent` + `work_order_number` + `display_name`
    // "Name (role)" + ISO `issuance_date`. Pre-RM-119 this returned
    // .unknown from kindOfPayload and was skipped → invisible.
    const ingest_json =
        \\{"intent":"work_order","summary":"Robert James Realty — gutters","display_name":"Kelly Moriarty (tenant)","state":"lead","site_ref":"94853141726c2520e456ad3bc3e26947b52f0f6a7e963ddf110197bf08642071","customer_refs":[{"cell_id":"x","role":"tenant","primary":true}],"work_order_number":"2601011476","services":["gutter-cleaning"],"issuance_date":"2026-01-07","due_date":"2026-01-14"}
    ;
    const cell = try encodeJobAsSubstrate(ingest_json);
    _ = try cs.put(&cell);

    // Pre-adapter the replay would skip it; post-RM-119 the adapter
    // maps it onto a v1 record.
    store.rescanCreatedCells();
    try std.testing.expectEqual(@as(usize, 1), store.count());

    // Find it (id is sha256-derived, so scan by mapped customer_name).
    var found: ?Job = null;
    for (store.records.items) |r| {
        if (std.mem.eql(u8, r.customer_name, "Kelly Moriarty")) found = r;
    }
    const j = found orelse return error.IngestJobNotSurfaced;
    // " (tenant)" stripped, state mapped, issuance_date → created_at.
    try std.testing.expectEqualStrings("Kelly Moriarty", j.customer_name);
    try std.testing.expectEqualStrings("lead", j.state);
    try std.testing.expectEqualStrings("2026-01-07", j.created_at);

    // Idempotent: a second rescan neither duplicates nor errors.
    store.rescanCreatedCells();
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

test "JobsStore: RM-121 resolves site address + primary-tenant contact + description" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();
    var store = try JobsStore.init(allocator, &cs, testClock);
    defer store.deinit();

    // Site cell — its cell-hash is what an ingest job's site_ref points at.
    const site_cell = try substrate_entity.encodeEntity(.{
        .spec = substrate_entity.SPEC_SITE,
        .linearity = substrate_entity.linearityFor(substrate_entity.SPEC_SITE.tag, "active"),
        .owner_id = [_]u8{0} ** 16,
        .payload_json = "{\"raw_address\":\"24 Gympie St, Tewantin, QLD, 4565\",\"normalized_address\":\"24 gympie st\",\"state\":\"active\"}",
    });
    _ = try cs.put(&site_cell);
    var sd: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(site_cell[0..], &sd, .{});
    const site_hex = std.fmt.bytesToHex(sd, .lower);

    // Primary tenant customer cell.
    const ten_cell = try substrate_entity.encodeEntity(.{
        .spec = substrate_entity.SPEC_CUSTOMER,
        .linearity = substrate_entity.linearityFor(substrate_entity.SPEC_CUSTOMER.tag, "active"),
        .owner_id = [_]u8{0} ** 16,
        .payload_json = "{\"name\":\"Kelly Moriarty\",\"phone\":\"+61401210240\",\"role\":\"tenant\",\"state\":\"active\"}",
    });
    _ = try cs.put(&ten_cell);
    var td: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(ten_cell[0..], &td, .{});
    const ten_hex = std.fmt.bytesToHex(td, .lower);

    // Ingest job referencing the site + tenant by their cell-hash.
    const job_json = try std.fmt.allocPrint(
        allocator,
        "{{\"intent\":\"work_order\",\"summary\":\"gutters need clearing\",\"display_name\":\"Kelly Moriarty (tenant)\",\"state\":\"lead\",\"site_ref\":\"{s}\",\"customer_refs\":[{{\"cell_id\":\"{s}\",\"role\":\"tenant\",\"primary\":true}}],\"work_order_number\":\"260\",\"issuance_date\":\"2026-01-07\"}}",
        .{ site_hex[0..], ten_hex[0..] },
    );
    defer allocator.free(job_json);
    const job_cell = try encodeJobAsSubstrate(job_json);
    _ = try cs.put(&job_cell);

    store.rescanCreatedCells();
    try std.testing.expectEqual(@as(usize, 1), store.count());

    var found: ?Job = null;
    for (store.records.items) |r| {
        if (std.mem.eql(u8, r.state, "lead")) found = r;
    }
    const j = found orelse return error.IngestJobNotSurfaced;
    // customer_name resolved to the primary tenant's real name.
    try std.testing.expectEqualStrings("Kelly Moriarty", j.customer_name);
    // site_ref → resolved address.
    try std.testing.expect(j.propertyAddress != null);
    try std.testing.expectEqualStrings("24 Gympie St, Tewantin, QLD, 4565", j.propertyAddress.?);
    // summary → description.
    try std.testing.expect(j.description != null);
    try std.testing.expectEqualStrings("gutters need clearing", j.description.?);
    // customerRefs resolved with name + phone.
    try std.testing.expect(j.customerRefs != null);
    try std.testing.expectEqual(@as(usize, 1), j.customerRefs.?.len);
    try std.testing.expectEqualStrings("Kelly Moriarty", j.customerRefs.?[0].name);
    try std.testing.expectEqualStrings("+61401210240", j.customerRefs.?[0].phone);
    try std.testing.expect(j.customerRefs.?[0].primary);

    // Idempotent.
    store.rescanCreatedCells();
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

test "CC-2: >768B job mints a canonical octave-1 cell (no 16B entity_cell fallback)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();
    var content = try content_store_local_fs.ContentStoreLocalFs.init(allocator, data_dir);
    defer content.deinit();
    var store = try JobsStore.initWithContentStore(allocator, &cs, testClock, &content);
    defer store.deinit();

    // A payload well over the 768-byte inline budget forces octave-1 escalation.
    const big = "{\"kind\":\"created\",\"state\":\"lead\",\"summary\":\"" ++ ("x" ** 1000) ++ "\"}";
    _ = try store.putJobCell(big);

    // The persisted cell must be CANONICAL (256B header) + escalated — NEVER the
    // legacy 16-byte entity_cell fallback.
    const cursor = try cs.cursorOpen();
    defer cs.cursorClose(cursor);
    var saw_canonical_job = false;
    while (try cs.cursorPull(cursor)) |cell_ptr| {
        // No job is ever stored as a legacy entity_cell anymore.
        try std.testing.expect(!(substrate_entity.looksLikeLegacyEntityCell(cell_ptr) and
            entity_cell.cellEntityTag(cell_ptr) == entity_cell.ENTITY_TAG_JOB));
        const dec = substrate_entity.decodeEntity(cell_ptr);
        if (dec.magic_ok and dec.domain_flag == substrate_entity.SPEC_JOB.domain_flag) {
            saw_canonical_job = true;
            // The fat payload escalated: the inline payload is an octave-1 pointer.
            try std.testing.expect(substrate_entity.escalatedSlot(dec.payload) != null);
        }
    }
    try std.testing.expect(saw_canonical_job);
}

test "CC-2: >768B job without a content store fails cleanly (no bastard fallback)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();
    var store = try JobsStore.init(allocator, &cs, testClock); // no content store
    defer store.deinit();

    const big = "{\"kind\":\"created\",\"state\":\"lead\",\"summary\":\"" ++ ("x" ** 1000) ++ "\"}";
    try std.testing.expectError(error.persistence_failed, store.putJobCell(big));
}

test "CC-3: job cell is owner-bound (ownerId@62) when an operator ownerId is set" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();
    var store = try JobsStore.init(allocator, &cs, testClock);
    defer store.deinit();

    const owner = [_]u8{0xab} ** 16;
    store.setOwnerId(owner);
    _ = try store.putJobCell("{\"kind\":\"created\",\"state\":\"lead\",\"summary\":\"small\"}");

    const cursor = try cs.cursorOpen();
    defer cs.cursorClose(cursor);
    var saw = false;
    while (try cs.cursorPull(cursor)) |cell_ptr| {
        const dec = substrate_entity.decodeEntity(cell_ptr);
        if (dec.magic_ok and dec.domain_flag == substrate_entity.SPEC_JOB.domain_flag) {
            saw = true;
            // ownerId occupies header bytes [62..78) — must equal the operator's.
            try std.testing.expectEqualSlices(u8, &owner, cell_ptr[62..78]);
        }
    }
    try std.testing.expect(saw);
}

test "ingest job cell is findable by its cellHash (find→cell.query identity, step 3b)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    var env = try openInlineTestEnv(data_dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, allocator);
    const cs = cs_impl.store();

    // Canonical ingest-shape job cell (no `kind`; carries intent + WO#).
    const payload =
        "{\"intent\":\"work_order\",\"work_order_number\":\"WO-1\",\"summary\":\"leak\",\"state\":\"lead\"}";
    const cell = try substrate_entity.encodeEntity(.{
        .spec = substrate_entity.SPEC_JOB,
        .linearity = .affine,
        .owner_id = [_]u8{0} ** 16,
        .payload_json = payload,
    });
    const chash = try cs.put(&cell);

    var store = try JobsStore.init(allocator, &cs, testClock);
    defer store.deinit();

    // Resolvable by the content hash (the operator app's job id post
    // find→cell.query) via BOTH getById (bytes) and findById (hex string) —
    // the paths the detail screen + FSM transition verbs use.
    const by_get = store.getById(chash) orelse return error.NotFoundByCellHashBytes;
    try std.testing.expectEqualStrings("lead", by_get.state);
    try std.testing.expect(by_get.cellId != null);
    try std.testing.expectEqualSlices(u8, &chash, &by_get.cellId.?);

    const chash_hex = std.fmt.bytesToHex(chash, .lower);
    const by_find = store.findById(chash_hex[0..]) orelse return error.NotFoundByCellHashHex;
    try std.testing.expectEqualStrings("lead", by_find.state);
}

```
