---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/resources/estimates_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.552082+00:00
---

# cartridges/oddjobz/brain/zig/src/resources/estimates_handler.zig

```zig
// ODDJOBZ-ESTIMATE-ROM-INGRESS Slice 2 — Typed `estimates` dispatcher
// resource (AFFINE pre-quote ROM estimate).
//
// Reference: docs/design/ODDJOBZ-ESTIMATE-ROM-INGRESS.md §3.1.
//
// Cloned from `resources/quotes_handler.zig` MINUS the FSM-transition
// machinery: the Estimate cell type is AFFINE
// (`cartridges/oddjobz/brain/src/cell-types/estimate.ts`), so there is no
// `transition` verb and no consumed-cell linearity gate.  `ack_status`
// is a plain field set by the idempotent `acknowledge` verb.
//
// Commands:
//   find         — { job_id? }            →  [ Estimate, ... ]
//                                            cap = cap.oddjobz.read_estimates
//                                          When `job_id` is supplied, the
//                                          response is filtered to
//                                          estimates whose parent Job
//                                          matches.
//   create       — { id?, job_id,
//                    estimate_type?,
//                    cost_min, cost_max,
//                    notes?, ack_status? } →  { id, status: "created"
//                                                   | "already_exists" }
//                                            cap = cap.oddjobz.write_estimate
//                                          Validates: job_id exists in
//                                          jobs_store (else `{error:
//                                          "job_not_found", job_id}`);
//                                          estimate_type defaults to
//                                          "auto_rom"; ack_status defaults
//                                          to "pending"; cost_min/max ≥ 0
//                                          and cost_max ≥ cost_min; notes
//                                          ≤ 2000 chars.  Idempotency:
//                                          same id with identical
//                                          contents → already_exists; same
//                                          id with different contents →
//                                          typed error.
//   find_by_id   — { id }                →  Estimate
//                                            cap = cap.oddjobz.read_estimates
//                                          (or { error: "not_found", id }
//                                           on miss — same shape as
//                                           quotes_handler / jobs_handler)
//   acknowledge  — { id, ack_status,
//                    acknowledged_at? }   →  the new Estimate
//                                            cap = cap.oddjobz.write_estimate
//                                          Sets ackStatus (+ optional
//                                          acknowledgedAt).  AFFINE: no
//                                          consumed-cell gate; idempotent
//                                          on an identical re-ack.
//
// FK validation: `estimates.create` calls `jobs_store.findById(job_id)`
// before delegating to the estimates store — the same loose-coupling
// seam quotes_handler uses (the estimates store doesn't know about the
// jobs store; the handler knits them together at the dispatcher layer).
//
// Concurrency: a single mutex serialises all handler entry points
// against the live store; same shape as quotes_handler.zig.

const std = @import("std");
const dispatcher = @import("dispatcher");
const verb_schema = @import("verb_schema"); // C4 PR-R2b — generic-REPL verb self-description
const estimates_store_fs = @import("estimates_store_fs");
const jobs_store_fs = @import("jobs_store_fs");
const helm_event_broker = @import("helm_event_broker");
const audit_log = @import("audit_log");

pub const RESOURCE_NAME = "estimates";

/// Capability declarations.
///
/// `cap.oddjobz.read_estimates` and `cap.oddjobz.write_estimate` are the
/// two new caps minted for the AFFINE Estimate entity, mirroring the
/// quotes `read_quotes` / `write_quote` cap pair.  The canonical cap
/// constants the Zig dispatcher gates on live HERE (same place + style
/// as `quotes_handler.CAP_READ_QUOTES` / `CAP_WRITE_QUOTE` at the top
/// of `resources/quotes_handler.zig`).  The TS-canon cap registry
/// (`cartridges/oddjobz/brain/src/capabilities.ts`) is intentionally NOT
/// touched in this slice (out of scope; the Zig test gate doesn't run
/// the TS capability suite — see the design doc §5 "no new capability"
/// note and the slice scope).
pub const CAP_READ_ESTIMATES: []const u8 = "cap.oddjobz.read_estimates";
pub const CAP_WRITE_ESTIMATE: []const u8 = "cap.oddjobz.write_estimate";

pub const HandlerError = error{
    /// JSON args parse failed or required arg missing.
    invalid_args,
    /// Underlying EstimatesStore validator rejected the input.
    invalid_id,
    invalid_job_id,
    invalid_estimate_type,
    invalid_ack_status,
    invalid_notes,
    invalid_cost,
    invalid_acknowledged_at,
    /// Caller passed an id that already exists in the store but the
    /// other fields disagree with what's on file.  Idempotent recreate
    /// requires byte-identical contents.
    estimate_id_in_use_with_different_contents,
    /// Underlying store I/O failed.
    store_error,
    /// Result-allocation failed.
    out_of_memory,
};

/// State carried alongside the resource registration.  The handler is
/// the sole owner of the EstimatesStore for the dispatcher's lifetime;
/// the daemon constructs it once at boot and registers the handler via
/// `register`.  The handler also borrows a pointer to the JobsStore for
/// FK validation on `estimates.create` — loose-coupling seam (the
/// estimates store itself doesn't know about the jobs store).
pub const Handler = struct {
    allocator: std.mem.Allocator,
    store: *estimates_store_fs.EstimatesStore,
    /// Borrowed pointer to the live JobsStore — used by
    /// `estimates.create` to validate that the caller-supplied `job_id`
    /// references an extant Job record.  May be null when the daemon
    /// stood up the estimates handler without a jobs store; FK
    /// validation is skipped in that case (the estimates store still
    /// validates the length envelope on job_id).
    jobs_store: ?*jobs_store_fs.JobsStore,
    /// Serialises find / create / find_by_id / acknowledge against the
    /// underlying store.  The store itself is not thread-safe; this
    /// mutex is the seam between concurrent transport callers.
    mu: std.Thread.Mutex,
    /// Optional event broker.  Mirrors the quotes_handler pattern.
    broker: ?*helm_event_broker.Broker,
    /// Optional audit log for phase=publish lines.
    audit: ?*audit_log.AuditLog,

    pub fn init(
        allocator: std.mem.Allocator,
        store: *estimates_store_fs.EstimatesStore,
        jobs_store: ?*jobs_store_fs.JobsStore,
    ) Handler {
        return initWithBroker(allocator, store, jobs_store, null, null);
    }

    /// Broker-aware constructor.
    pub fn initWithBroker(
        allocator: std.mem.Allocator,
        store: *estimates_store_fs.EstimatesStore,
        jobs_store: ?*jobs_store_fs.JobsStore,
        broker: ?*helm_event_broker.Broker,
        audit: ?*audit_log.AuditLog,
    ) Handler {
        return .{
            .allocator = allocator,
            .store = store,
            .jobs_store = jobs_store,
            .mu = .{},
            .broker = broker,
            .audit = audit,
        };
    }

    /// Build the dispatcher.ResourceHandler v-table entry for this
    /// instance.  Caller registers it via `dispatcher.Dispatcher.register`.
    pub fn resourceHandler(self: *Handler) dispatcher.ResourceHandler {
        return .{
            .name = RESOURCE_NAME,
            .state = self,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handle,
            .verbs_fn = verbsFn,
        };
    }
};

// C4 PR-R2b — verb self-description for the generic `estimates <verb>` REPL path.
// `acknowledge` is an AFFINE write with no principal-context, so it's drivable.
const ESTIMATES_VERBS = [_]verb_schema.VerbSpec{
    .{ .verb = "find", .summary = "list estimates (optional job_id filter)", .args = &.{
        .{ .name = "job_id", .kind = .string },
    } },
    .{ .verb = "find_by_id", .summary = "fetch one estimate by id", .args = &.{
        .{ .name = "id", .kind = .string, .required = true, .positional = true },
    } },
    .{ .verb = "create", .summary = "create an estimate", .args = &.{
        .{ .name = "job_id", .kind = .string, .required = true },
        .{ .name = "id", .kind = .string },
        .{ .name = "estimate_type", .kind = .string },
        .{ .name = "ack_status", .kind = .string },
        .{ .name = "cost_min", .kind = .int },
        .{ .name = "cost_max", .kind = .int },
        .{ .name = "notes", .kind = .string },
        .{ .name = "acknowledged_at", .kind = .string },
        .{ .name = "created_at", .kind = .string },
        .{ .name = "updated_at", .kind = .string },
    } },
    .{ .verb = "acknowledge", .summary = "acknowledge an estimate", .args = &.{
        .{ .name = "id", .kind = .string, .required = true, .positional = true },
        .{ .name = "ack_status", .kind = .string, .required = true },
        .{ .name = "acknowledged_at", .kind = .string },
    } },
};
fn verbsFn(_: ?*anyopaque) []const verb_schema.VerbSpec {
    return &ESTIMATES_VERBS;
}

// ─────────────────────────────────────────────────────────────────────
// Capability declarations
// ─────────────────────────────────────────────────────────────────────

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "find")) return .{ .require = CAP_READ_ESTIMATES };
    if (std.mem.eql(u8, cmd, "find_by_id")) return .{ .require = CAP_READ_ESTIMATES };
    if (std.mem.eql(u8, cmd, "create")) return .{ .require = CAP_WRITE_ESTIMATE };
    // AFFINE: `acknowledge` is a plain-field write, gated on the write
    // cap (no per-FSM-row split — the Estimate has no FSM).
    if (std.mem.eql(u8, cmd, "acknowledge")) return .{ .require = CAP_WRITE_ESTIMATE };
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Dispatch entry point
// ─────────────────────────────────────────────────────────────────────

fn handle(
    state: ?*anyopaque,
    ctx: *const dispatcher.DispatchContext,
    cmd: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher.Result {
    _ = ctx;
    const self: *Handler = @ptrCast(@alignCast(state.?));
    self.mu.lock();
    defer self.mu.unlock();

    if (std.mem.eql(u8, cmd, "find")) return handleFind(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "create")) return handleCreate(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "find_by_id")) return handleFindById(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "acknowledge")) return handleAcknowledge(self, allocator, args_json);
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Per-command implementations
// ─────────────────────────────────────────────────────────────────────

fn handleFind(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const filter = parseFindArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer if (filter) |f| allocator.free(f);

    const items: []estimates_store_fs.Estimate = if (filter) |f|
        self.store.findByJobId(allocator, f) catch return HandlerError.store_error
    else
        self.store.findAll(allocator) catch return HandlerError.store_error;
    defer allocator.free(items);

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.append(allocator, '[');
    for (items, 0..) |row, i| {
        if (i != 0) try buf.append(allocator, ',');
        try writeEstimateJson(allocator, &buf, row);
    }
    try buf.append(allocator, ']');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleCreate(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    var args = parseCreateArgs(allocator, args_json) catch |err| switch (err) {
        error.invalid_id => return HandlerError.invalid_id,
        error.invalid_job_id => return HandlerError.invalid_job_id,
        error.invalid_estimate_type => return HandlerError.invalid_estimate_type,
        error.invalid_ack_status => return HandlerError.invalid_ack_status,
        error.invalid_notes => return HandlerError.invalid_notes,
        error.invalid_cost => return HandlerError.invalid_cost,
        error.invalid_acknowledged_at => return HandlerError.invalid_acknowledged_at,
        error.OutOfMemory => return HandlerError.out_of_memory,
        else => return HandlerError.invalid_args,
    };
    defer args.deinit(allocator);

    // FK validation: if the handler was wired with a JobsStore pointer,
    // confirm `job_id` references an extant Job.  Returns a typed
    // `{error: "job_not_found", job_id}` body (200, NOT a dispatcher
    // error) so the helm can render a useful operator message instead
    // of a transport-level dispatch failure.  Without a JobsStore
    // pointer we fall through (best-effort; the estimates store still
    // checks the length envelope).
    if (self.jobs_store) |js| {
        if (js.findById(args.job_id) == null) {
            var buf: std.ArrayList(u8) = .{};
            errdefer buf.deinit(allocator);
            try buf.appendSlice(allocator, "{\"error\":\"job_not_found\",\"job_id\":");
            try writeJsonString(allocator, &buf, args.job_id);
            try buf.append(allocator, '}');
            return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
        }
    }

    // Acceptance: when the caller passes an id that already exists, the
    // contents MUST be byte-identical for the request to be idempotent.
    // Differing contents return a typed validation error instead of
    // silently shadowing the prior record.  Mirrors quotes_handler.
    if (self.store.findById(args.id)) |existing| {
        if (!estimateContentsEqual(existing, args)) {
            return HandlerError.estimate_id_in_use_with_different_contents;
        }
    }

    const estimate = estimates_store_fs.Estimate{
        .id = args.id,
        .job_id = args.job_id,
        .estimate_type = args.estimate_type,
        .cost_min = args.cost_min,
        .cost_max = args.cost_max,
        .ack_status = args.ack_status,
        .acknowledged_at = args.acknowledged_at,
        .notes = args.notes,
        .created_at = args.created_at,
        .updated_at = args.updated_at,
    };

    const outcome = self.store.append(estimate) catch |err| switch (err) {
        estimates_store_fs.StoreError.invalid_id => return HandlerError.invalid_id,
        estimates_store_fs.StoreError.invalid_job_id => return HandlerError.invalid_job_id,
        estimates_store_fs.StoreError.invalid_estimate_type => return HandlerError.invalid_estimate_type,
        estimates_store_fs.StoreError.invalid_ack_status => return HandlerError.invalid_ack_status,
        estimates_store_fs.StoreError.invalid_notes => return HandlerError.invalid_notes,
        estimates_store_fs.StoreError.invalid_cost => return HandlerError.invalid_cost,
        estimates_store_fs.StoreError.invalid_acknowledged_at => return HandlerError.invalid_acknowledged_at,
        else => return HandlerError.store_error,
    };

    // Emit `estimate.created` after a genuine new write.
    if (outcome == .created) {
        emitEstimateCreated(
            self,
            args.id,
            args.job_id,
            args.estimate_type,
            args.ack_status,
            args.cost_min,
            args.cost_max,
            args.created_at,
        ) catch {};
    }

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, &buf, args.id);
    try buf.appendSlice(allocator, ",\"status\":\"");
    try buf.appendSlice(allocator, switch (outcome) {
        .created => "created",
        .already_exists => "already_exists",
    });
    try buf.appendSlice(allocator, "\"}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleFindById(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const id = parseFindByIdArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(id);

    const got = self.store.findById(id) orelse miss: {
        // Index-liveness: the estimate may be a TAG_ESTIMATE cell
        // minted into the shared entity store (Slice-3 intent-action
        // router) AFTER this store's boot-time replay — present on
        // disk, but not yet in the handler's in-memory index. Do a
        // one-shot incremental rescan and retry before declaring it
        // gone. Idempotent; only the rare cold-id path pays the scan.
        // Mirrors jobs_handler.zig exactly.
        self.store.rescanCreatedCells();
        if (self.store.findById(id)) |e| break :miss e;
        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try buf.appendSlice(allocator, "{\"error\":\"not_found\",\"id\":");
        try writeJsonString(allocator, &buf, id);
        try buf.append(allocator, '}');
        return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
    };

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try writeEstimateJson(allocator, &buf, got);
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// `estimates.acknowledge` — AFFINE plain-field write of `ack_status`
// (+ optional `acknowledged_at`).  No FSM, no consumed-cell gate.
//
// Args shape:
//   { id: <string>,             -- the estimate id; must already exist
//     ack_status: <string>,     -- one of ESTIMATE_ACK_STATUSES (required)
//     acknowledged_at: <string>? -- optional ISO timestamp
//   }
//
// Success body (200): the new Estimate (full shape; same as
// `estimates.find_by_id`).
//
// Error body (200, NOT a dispatcher error): typed JSON
//   { "error": "not_found", "id": "<id>" }
// ─────────────────────────────────────────────────────────────────────

const AcknowledgeArgs = struct {
    id: []u8,
    ack_status: []u8,
    acknowledged_at: ?[]u8,

    pub fn deinit(self: *AcknowledgeArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.ack_status);
        if (self.acknowledged_at) |s| allocator.free(s);
    }
};

fn parseAcknowledgeArgs(
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !AcknowledgeArgs {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return error.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    const id_v = obj.get("id") orelse return error.invalid_args;
    if (id_v != .string) return error.invalid_args;
    if (id_v.string.len == 0 or id_v.string.len > estimates_store_fs.MAX_ID_BYTES) return error.invalid_args;

    const ack_v = obj.get("ack_status") orelse return error.invalid_ack_status;
    if (ack_v != .string) return error.invalid_ack_status;
    if (ack_v.string.len == 0) return error.invalid_ack_status;
    if (!estimates_store_fs.isValidAckStatus(ack_v.string)) return error.invalid_ack_status;

    var ack_at_owned: ?[]u8 = null;
    if (obj.get("acknowledged_at")) |v| {
        if (v == .string and v.string.len > 0) {
            if (v.string.len > estimates_store_fs.MAX_ACKNOWLEDGED_AT_BYTES) return error.invalid_acknowledged_at;
            ack_at_owned = try allocator.dupe(u8, v.string);
        }
    }
    errdefer if (ack_at_owned) |s| allocator.free(s);

    const id_owned = try allocator.dupe(u8, id_v.string);
    errdefer allocator.free(id_owned);
    const ack_owned = try allocator.dupe(u8, ack_v.string);

    return .{
        .id = id_owned,
        .ack_status = ack_owned,
        .acknowledged_at = ack_at_owned,
    };
}

fn handleAcknowledge(
    self: *Handler,
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !dispatcher.Result {
    var args = parseAcknowledgeArgs(allocator, args_json) catch |err| switch (err) {
        error.invalid_ack_status => return HandlerError.invalid_ack_status,
        error.invalid_acknowledged_at => return HandlerError.invalid_acknowledged_at,
        error.OutOfMemory => return HandlerError.out_of_memory,
        else => return HandlerError.invalid_args,
    };
    defer args.deinit(allocator);

    // Live-index miss recovery before declaring not_found — same
    // rescan-then-retry shape jobs_handler uses for transitions.
    if (self.store.findById(args.id) == null) {
        self.store.rescanCreatedCells();
        if (self.store.findById(args.id) == null) {
            var buf: std.ArrayList(u8) = .{};
            errdefer buf.deinit(allocator);
            try buf.appendSlice(allocator, "{\"error\":\"not_found\",\"id\":");
            try writeJsonString(allocator, &buf, args.id);
            try buf.append(allocator, '}');
            return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
        }
    }

    // Capture from-status BEFORE acknowledge mutates the store. The
    // estimates store frees the old ack_status slice in-place, so
    // reading it after the call would dangle; dupe to keep it alive.
    const before = self.store.findById(args.id).?;
    const from_ack_owned = try allocator.dupe(u8, before.ack_status);
    defer allocator.free(from_ack_owned);

    const acknowledged_at: ?[]const u8 = if (args.acknowledged_at) |s| s else null;

    const updated = self.store.acknowledge(
        args.id,
        args.ack_status,
        acknowledged_at,
    ) catch |err| switch (err) {
        error.not_found => {
            var buf: std.ArrayList(u8) = .{};
            errdefer buf.deinit(allocator);
            try buf.appendSlice(allocator, "{\"error\":\"not_found\",\"id\":");
            try writeJsonString(allocator, &buf, args.id);
            try buf.append(allocator, '}');
            return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
        },
        error.invalid_ack_status => return HandlerError.invalid_ack_status,
        error.invalid_acknowledged_at => return HandlerError.invalid_acknowledged_at,
        else => return HandlerError.store_error,
    };

    emitEstimateAcknowledged(self, updated.id, updated.job_id, from_ack_owned, updated.ack_status) catch {};

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try writeEstimateJson(allocator, &buf, updated);
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

/// Publish an `estimate.created` event to the broker.
fn emitEstimateCreated(
    self: *Handler,
    id: []const u8,
    job_id: []const u8,
    estimate_type: []const u8,
    ack_status: []const u8,
    cost_min: i64,
    cost_max: i64,
    created_at: []const u8,
) !void {
    const broker = self.broker orelse return;
    const allocator = self.allocator;

    var payload: std.ArrayList(u8) = .{};
    defer payload.deinit(allocator);
    try payload.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, &payload, id);
    try payload.appendSlice(allocator, ",\"job_id\":");
    try writeJsonString(allocator, &payload, job_id);
    try payload.appendSlice(allocator, ",\"estimate_type\":");
    try writeJsonString(allocator, &payload, estimate_type);
    try payload.appendSlice(allocator, ",\"ack_status\":");
    try writeJsonString(allocator, &payload, ack_status);
    try payload.print(allocator, ",\"cost_min\":{d}", .{cost_min});
    try payload.print(allocator, ",\"cost_max\":{d}", .{cost_max});
    try payload.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, &payload, created_at);
    try payload.append(allocator, '}');

    broker.publish(.{
        .type = "estimate.created",
        .payload_json = payload.items,
    });

    if (self.audit) |a| {
        a.record(allocator, .{
            .module = "helm.broker",
            .op = "publish",
            .result = .ok,
            .detail = "estimate.created",
        }) catch {};
    }
}

/// Publish an `estimate.acknowledged` event to the broker.
fn emitEstimateAcknowledged(
    self: *Handler,
    id: []const u8,
    job_id: []const u8,
    from_ack: []const u8,
    to_ack: []const u8,
) !void {
    const broker = self.broker orelse return;
    const allocator = self.allocator;

    const acknowledged_at = try renderIsoTimestamp(allocator, std.time.timestamp());
    defer allocator.free(acknowledged_at);

    var payload: std.ArrayList(u8) = .{};
    defer payload.deinit(allocator);
    try payload.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, &payload, id);
    try payload.appendSlice(allocator, ",\"job_id\":");
    try writeJsonString(allocator, &payload, job_id);
    try payload.appendSlice(allocator, ",\"from\":");
    try writeJsonString(allocator, &payload, from_ack);
    try payload.appendSlice(allocator, ",\"to\":");
    try writeJsonString(allocator, &payload, to_ack);
    try payload.appendSlice(allocator, ",\"acknowledged_at\":");
    try writeJsonString(allocator, &payload, acknowledged_at);
    try payload.append(allocator, '}');

    broker.publish(.{
        .type = "estimate.acknowledged",
        .payload_json = payload.items,
    });

    if (self.audit) |a| {
        a.record(allocator, .{
            .module = "helm.broker",
            .op = "publish",
            .result = .ok,
            .detail = "estimate.acknowledged",
        }) catch {};
    }
}

// ─────────────────────────────────────────────────────────────────────
// Args parsing
// ─────────────────────────────────────────────────────────────────────

const CreateArgs = struct {
    id: []u8,
    job_id: []u8,
    estimate_type: []u8,
    cost_min: i64,
    cost_max: i64,
    ack_status: []u8,
    acknowledged_at: []u8,
    notes: []u8,
    created_at: []u8,
    updated_at: []u8,

    pub fn deinit(self: *CreateArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.job_id);
        allocator.free(self.estimate_type);
        allocator.free(self.ack_status);
        allocator.free(self.acknowledged_at);
        allocator.free(self.notes);
        allocator.free(self.created_at);
        allocator.free(self.updated_at);
    }
};

const ParseError = error{
    invalid_args,
    invalid_id,
    invalid_job_id,
    invalid_estimate_type,
    invalid_ack_status,
    invalid_notes,
    invalid_cost,
    invalid_acknowledged_at,
    out_of_memory,
    OutOfMemory,
};

/// `find` accepts an optional `{job_id: "..."}` filter.  Returns null
/// when no filter is present (caller treats that as "all estimates");
/// the allocator owns the returned slice when non-null.
fn parseFindArgs(allocator: std.mem.Allocator, args_json: []const u8) !?[]u8 {
    if (args_json.len == 0) return null;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const obj = parsed.value.object;
    const v = obj.get("job_id") orelse return null;
    if (v != .string) return null;
    if (v.string.len == 0) return null;
    return try allocator.dupe(u8, v.string);
}

fn parseCreateArgs(allocator: std.mem.Allocator, args_json: []const u8) ParseError!CreateArgs {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return error.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    // job_id (required, non-empty, ≤ 64).
    const ji_v = obj.get("job_id") orelse return error.invalid_job_id;
    if (ji_v != .string) return error.invalid_job_id;
    if (ji_v.string.len == 0 or ji_v.string.len > estimates_store_fs.MAX_JOB_ID_BYTES) return error.invalid_job_id;

    // id (optional — server-stamped when empty).
    const id_str: []const u8 = blk: {
        if (obj.get("id")) |v| {
            if (v != .string) return error.invalid_id;
            if (v.string.len > estimates_store_fs.MAX_ID_BYTES) return error.invalid_id;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };

    // estimate_type (optional; defaults to "auto_rom").
    const et_str: []const u8 = blk: {
        if (obj.get("estimate_type")) |v| {
            if (v != .string) return error.invalid_estimate_type;
            if (v.string.len > 0) {
                if (!estimates_store_fs.isValidEstimateType(v.string)) return error.invalid_estimate_type;
                break :blk v.string;
            }
        }
        break :blk "auto_rom";
    };

    // ack_status (optional; defaults to "pending").
    const as_str: []const u8 = blk: {
        if (obj.get("ack_status")) |v| {
            if (v != .string) return error.invalid_ack_status;
            if (v.string.len > 0) {
                if (!estimates_store_fs.isValidAckStatus(v.string)) return error.invalid_ack_status;
                break :blk v.string;
            }
        }
        break :blk "pending";
    };

    // cost_min / cost_max (both optional integer; default 0 — the store
    // enforces non-negative + cost_max ≥ cost_min, so omitting both
    // yields {0, 0} which is valid).
    const cmin: i64 = blk: {
        if (obj.get("cost_min")) |v| {
            switch (v) {
                .integer => |i| break :blk i,
                .float => |f| break :blk @intFromFloat(f),
                else => return error.invalid_cost,
            }
        }
        break :blk 0;
    };
    const cmax: i64 = blk: {
        if (obj.get("cost_max")) |v| {
            switch (v) {
                .integer => |i| break :blk i,
                .float => |f| break :blk @intFromFloat(f),
                else => return error.invalid_cost,
            }
        }
        break :blk 0;
    };
    if (cmin < 0 or cmax < 0) return error.invalid_cost;
    if (cmax < cmin) return error.invalid_cost;

    // notes (optional, ≤ 2000).
    const no_v: []const u8 = blk: {
        if (obj.get("notes")) |v| {
            if (v != .string) return error.invalid_notes;
            if (v.string.len > estimates_store_fs.MAX_NOTES_BYTES) return error.invalid_notes;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // acknowledged_at (optional).
    const aa_v: []const u8 = blk: {
        if (obj.get("acknowledged_at")) |v| {
            if (v != .string) return error.invalid_acknowledged_at;
            if (v.string.len > estimates_store_fs.MAX_ACKNOWLEDGED_AT_BYTES) return error.invalid_acknowledged_at;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // created_at + updated_at (both optional; server-stamps when empty).
    const ca_v: []const u8 = blk: {
        if (obj.get("created_at")) |v| {
            if (v != .string) return error.invalid_args;
            if (v.string.len > estimates_store_fs.MAX_CREATED_AT_BYTES) return error.invalid_args;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };
    const ua_v: []const u8 = blk: {
        if (obj.get("updated_at")) |v| {
            if (v != .string) return error.invalid_args;
            if (v.string.len > estimates_store_fs.MAX_UPDATED_AT_BYTES) return error.invalid_args;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };

    // Allocate owned copies.
    var id_owned: []u8 = undefined;
    if (id_str.len == 0) {
        var id_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&id_bytes);
        const id_alloc = try allocator.alloc(u8, 32);
        hexEncode(&id_bytes, id_alloc);
        id_owned = id_alloc;
    } else {
        id_owned = try allocator.dupe(u8, id_str);
    }
    errdefer allocator.free(id_owned);

    const ji_owned = try allocator.dupe(u8, ji_v.string);
    errdefer allocator.free(ji_owned);
    const et_owned = try allocator.dupe(u8, et_str);
    errdefer allocator.free(et_owned);
    const as_owned = try allocator.dupe(u8, as_str);
    errdefer allocator.free(as_owned);
    const no_owned = try allocator.dupe(u8, no_v);
    errdefer allocator.free(no_owned);
    const aa_owned = try allocator.dupe(u8, aa_v);
    errdefer allocator.free(aa_owned);

    var ca_owned: []u8 = undefined;
    if (ca_v.len == 0) {
        ca_owned = try renderIsoTimestamp(allocator, std.time.timestamp());
    } else {
        ca_owned = try allocator.dupe(u8, ca_v);
    }
    errdefer allocator.free(ca_owned);

    var ua_owned: []u8 = undefined;
    if (ua_v.len == 0) {
        // Default updated_at to created_at when omitted — same calendar
        // moment for a freshly minted estimate.
        ua_owned = try allocator.dupe(u8, ca_owned);
    } else {
        ua_owned = try allocator.dupe(u8, ua_v);
    }
    errdefer allocator.free(ua_owned);

    return .{
        .id = id_owned,
        .job_id = ji_owned,
        .estimate_type = et_owned,
        .cost_min = cmin,
        .cost_max = cmax,
        .ack_status = as_owned,
        .acknowledged_at = aa_owned,
        .notes = no_owned,
        .created_at = ca_owned,
        .updated_at = ua_owned,
    };
}

fn parseFindByIdArgs(allocator: std.mem.Allocator, args_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const v = obj.get("id") orelse return error.invalid_args;
    if (v != .string) return error.invalid_args;
    if (v.string.len == 0 or v.string.len > estimates_store_fs.MAX_ID_BYTES) return error.invalid_args;
    return try allocator.dupe(u8, v.string);
}

/// Compare a stored Estimate record (slices) against the parsed
/// CreateArgs (also slices).  All fields except updated_at must match
/// byte-for-byte for an idempotent recreate.  Mirrors quotes_handler.
fn estimateContentsEqual(stored: estimates_store_fs.Estimate, args: CreateArgs) bool {
    return std.mem.eql(u8, stored.job_id, args.job_id) and
        std.mem.eql(u8, stored.estimate_type, args.estimate_type) and
        stored.cost_min == args.cost_min and
        stored.cost_max == args.cost_max and
        std.mem.eql(u8, stored.ack_status, args.ack_status) and
        std.mem.eql(u8, stored.acknowledged_at, args.acknowledged_at) and
        std.mem.eql(u8, stored.notes, args.notes) and
        std.mem.eql(u8, stored.created_at, args.created_at);
}

// ─────────────────────────────────────────────────────────────────────
// JSON rendering helpers
// ─────────────────────────────────────────────────────────────────────

fn writeEstimateJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), estimate: estimates_store_fs.Estimate) !void {
    try out.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, out, estimate.id);
    try out.appendSlice(allocator, ",\"job_id\":");
    try writeJsonString(allocator, out, estimate.job_id);
    try out.appendSlice(allocator, ",\"estimate_type\":");
    try writeJsonString(allocator, out, estimate.estimate_type);
    try out.print(allocator, ",\"cost_min\":{d}", .{estimate.cost_min});
    try out.print(allocator, ",\"cost_max\":{d}", .{estimate.cost_max});
    try out.appendSlice(allocator, ",\"ack_status\":");
    try writeJsonString(allocator, out, estimate.ack_status);
    try out.appendSlice(allocator, ",\"acknowledged_at\":");
    try writeJsonString(allocator, out, estimate.acknowledged_at);
    try out.appendSlice(allocator, ",\"notes\":");
    try writeJsonString(allocator, out, estimate.notes);
    try out.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, out, estimate.created_at);
    try out.appendSlice(allocator, ",\"updated_at\":");
    try writeJsonString(allocator, out, estimate.updated_at);
    try out.append(allocator, '}');
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

fn hexEncode(bytes: []const u8, out: []u8) void {
    std.debug.assert(out.len == bytes.len * 2);
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

/// Render a unix timestamp as a minimal ISO-8601 UTC string ("YYYY-
/// MM-DDTHH:MM:SSZ").  Mirrors the same helper in quotes_handler.zig.
fn renderIsoTimestamp(allocator: std.mem.Allocator, unix_seconds: i64) ![]u8 {
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(unix_seconds) };
    const epoch_day = epoch_secs.getEpochDay();
    const day_secs = epoch_secs.getDaySeconds();
    const ymd = epoch_day.calculateYearDay();
    const month_day = ymd.calculateMonthDay();
    const year: u32 = ymd.year;
    const month: u8 = month_day.month.numeric();
    const day: u8 = month_day.day_index + 1;
    const hour: u8 = day_secs.getHoursIntoDay();
    const minute: u8 = day_secs.getMinutesIntoHour();
    const second: u8 = day_secs.getSecondsIntoMinute();
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{ year, month, day, hour, minute, second },
    );
}

```
