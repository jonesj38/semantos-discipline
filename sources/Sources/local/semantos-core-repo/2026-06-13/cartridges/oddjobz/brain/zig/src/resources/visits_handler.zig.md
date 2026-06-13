---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/resources/visits_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.552447+00:00
---

# cartridges/oddjobz/brain/zig/src/resources/visits_handler.zig

```zig
// D-O4.followup-2 — Typed `visits` dispatcher resource (FSM cutover).
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3, §8;
//            docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4 (Visit FSM table)
//                                                 §O5 (helm visits view).
//
// Mirrors `jobs_handler.zig` (post-#311) for the Visit cell type — the
// sequential mirror of what #307 + #311 did for Jobs, applied to
// `oddjobz.visit.v1`.  Both helms (loom-svelte VisitList +
// oddjobz-mobile VisitListScreen) wire state-aware action buttons to
// this resource; the dispatcher's audit pair captures every transition
// because the brief is explicit that transitions are the prototypical
// audit-relevant event.
//
// Commands:
//   find         — { job_id? }            →  [ Visit, ... ]
//                                            cap = cap.oddjobz.read_visits
//                                          When `job_id` is supplied, the
//                                          response is filtered to visits
//                                          whose parent Job matches.
//   create       — { id?, job_id,
//                    visit_type,
//                    notes? }             →  { id, status: "created"
//                                                   | "already_exists" }
//                                            cap = cap.oddjobz.write_visit
//                                          Validates: job_id exists in
//                                          jobs_store (else `{error:
//                                          "job_not_found", job_id}`);
//                                          visit_type ∈ VISIT_TYPES;
//                                          notes ≤ 2000 chars; status
//                                          defaults to "scheduled".
//                                          Idempotency: same id with
//                                          identical contents → already_
//                                          exists; same id with different
//                                          contents → typed error.
//   find_by_id   — { id }                →  Visit
//                                            cap = cap.oddjobz.read_visits
//                                          (or { error: "not_found", id }
//                                           on miss — same shape as
//                                           jobs_handler / customers_handler)
//   transition   — { id, to_state,
//                    presented_cap?,
//                    principal_kind,
//                    actual_start?,
//                    outcome? }           →  the new Visit
//                                            cap = cap.oddjobz.read_visits
//                                          Per-FSM-row cap is checked
//                                          INSIDE the handler against
//                                          ctx.capabilities (every Visit
//                                          row is ungated today; the
//                                          shape is preserved for future
//                                          rows).
//
// FK validation: `visits.create` calls `jobs_store.findById(job_id)`
// before delegating to the visits store.  This is the loose-coupling
// seam the brief calls for — the visits store doesn't know about the
// jobs store, the handler knits them together at the dispatcher layer.
//
// Concurrency: a single mutex serialises all handler entry points
// against the live store; same shape as bearer_tokens_handler.zig +
// jobs_handler.zig.

const std = @import("std");
const dispatcher = @import("dispatcher");
const verb_schema = @import("verb_schema"); // C4 PR-R2b — generic-REPL verb self-description
const visits_store_fs = @import("visits_store_fs");
const jobs_store_fs = @import("jobs_store_fs");
const visit_fsm = @import("visit_fsm");
const helm_event_broker = @import("helm_event_broker");
const audit_log = @import("audit_log");

pub const RESOURCE_NAME = "visits";

/// Capability declarations.
///
/// `cap.oddjobz.read_visits` (`0x00010109`) and `cap.oddjobz.write_visit`
/// (`0x0001010A`) are the two new caps minted in `cartridges/oddjobz/brain/
/// src/capabilities.ts` alongside the existing eight oddjobz caps.
pub const CAP_READ_VISITS: []const u8 = "cap.oddjobz.read_visits";
pub const CAP_WRITE_VISIT: []const u8 = "cap.oddjobz.write_visit";

pub const HandlerError = error{
    /// JSON args parse failed or required arg missing.
    invalid_args,
    /// Underlying VisitsStore validator rejected the input.
    invalid_id,
    invalid_job_id,
    invalid_visit_type,
    invalid_status,
    invalid_notes,
    invalid_actual_start,
    invalid_outcome,
    /// Caller passed an id that already exists in the store but the
    /// other fields disagree with what's on file.  Idempotent recreate
    /// requires byte-identical contents.
    visit_id_in_use_with_different_contents,
    /// `transition` arg validation: a missing or non-string `to_state`,
    /// missing `id`, missing `principal_kind`, or a principal_kind not
    /// in {"operator", "service"}.
    invalid_principal_kind,
    /// Underlying store I/O failed.
    store_error,
    /// Result-allocation failed.
    out_of_memory,
};

/// State carried alongside the resource registration.  The handler is
/// the sole owner of the VisitsStore for the dispatcher's lifetime;
/// the daemon (or REPL bootstrap) constructs it once at boot and
/// registers the handler via `register`.  The handler also borrows a
/// pointer to the JobsStore for FK validation on `visits.create` —
/// loose-coupling seam (the visits store itself doesn't know about
/// the jobs store).
pub const Handler = struct {
    allocator: std.mem.Allocator,
    store: *visits_store_fs.VisitsStore,
    /// Borrowed pointer to the live JobsStore — used by `visits.create`
    /// to validate that the caller-supplied `job_id` references an
    /// extant Job record.  May be null when the daemon stood up the
    /// visits handler without a jobs store (best-effort init posture
    /// matches the cli wiring); FK validation is skipped in that case
    /// (the visits store still validates length envelope on job_id).
    jobs_store: ?*jobs_store_fs.JobsStore,
    /// Serialises find / create / find_by_id / transition against the
    /// underlying store.  The store itself is not thread-safe; this
    /// mutex is the seam between concurrent transport callers.
    mu: std.Thread.Mutex,
    /// D-O5.followup-4 — optional event broker.  When non-null, every
    /// successful `visits.create` publishes `visit.created` and every
    /// successful `visits.transition` publishes `visit.transitioned`.
    /// Mirrors the jobs_handler emit shape from #318.
    broker: ?*helm_event_broker.Broker,
    /// D-O5.followup-4 — optional audit log.  Records phase=publish
    /// per emit so the audit trail surfaces event-emission alongside
    /// the dispatcher's existing start/end pair.
    audit: ?*audit_log.AuditLog,

    pub fn init(
        allocator: std.mem.Allocator,
        store: *visits_store_fs.VisitsStore,
        jobs_store: ?*jobs_store_fs.JobsStore,
    ) Handler {
        return initWithBroker(allocator, store, jobs_store, null, null);
    }

    /// D-O5.followup-4 — broker-aware constructor.  cli.zig
    /// (`cmdRepl` + `cmdServe`) instantiates the shared broker once
    /// and passes it here so visit creates + transitions emit live
    /// events.
    pub fn initWithBroker(
        allocator: std.mem.Allocator,
        store: *visits_store_fs.VisitsStore,
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

// C4 PR-R2b — verb self-description for the generic `visits <verb>` REPL path.
// `transition` is omitted: it needs operator principal-context injection, so it
// stays a cartridge sugar alias (R3).
const VISITS_VERBS = [_]verb_schema.VerbSpec{
    .{ .verb = "find", .summary = "list visits (optional job_id filter)", .args = &.{
        .{ .name = "job_id", .kind = .string },
    } },
    .{ .verb = "find_by_id", .summary = "fetch one visit by id", .args = &.{
        .{ .name = "id", .kind = .string, .required = true, .positional = true },
    } },
    .{ .verb = "create", .summary = "create a visit", .args = &.{
        .{ .name = "job_id", .kind = .string, .required = true },
        .{ .name = "visit_type", .kind = .string, .required = true },
        .{ .name = "id", .kind = .string },
        .{ .name = "status", .kind = .string },
        .{ .name = "notes", .kind = .string },
        .{ .name = "actual_start", .kind = .string },
        .{ .name = "outcome", .kind = .string },
        .{ .name = "created_at", .kind = .string },
        .{ .name = "updated_at", .kind = .string },
    } },
};
fn verbsFn(_: ?*anyopaque) []const verb_schema.VerbSpec {
    return &VISITS_VERBS;
}

// ─────────────────────────────────────────────────────────────────────
// Capability declarations
// ─────────────────────────────────────────────────────────────────────

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "find")) return .{ .require = CAP_READ_VISITS };
    if (std.mem.eql(u8, cmd, "find_by_id")) return .{ .require = CAP_READ_VISITS };
    if (std.mem.eql(u8, cmd, "create")) return .{ .require = CAP_WRITE_VISIT };
    // `transition` is dispatcher-gated on the read cap (you must be
    // able to see the visit to transition it).  The PER-TRANSITION cap
    // (currently null for every Visit row, but reserved for future
    // rows) is checked INSIDE the handler.  Same split as
    // jobs.transition — see jobs_handler.zig::capForCmd doc.
    if (std.mem.eql(u8, cmd, "transition")) return .{ .require = CAP_READ_VISITS };
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
    const self: *Handler = @ptrCast(@alignCast(state.?));
    self.mu.lock();
    defer self.mu.unlock();

    if (std.mem.eql(u8, cmd, "find")) return handleFind(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "create")) return handleCreate(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "find_by_id")) return handleFindById(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "transition")) return handleTransition(self, ctx, allocator, args_json);
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Per-command implementations
// ─────────────────────────────────────────────────────────────────────

fn handleFind(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const filter = parseFindArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer if (filter) |f| allocator.free(f);

    const items: []visits_store_fs.Visit = if (filter) |f|
        self.store.findByJobId(allocator, f) catch return HandlerError.store_error
    else
        self.store.findAll(allocator) catch return HandlerError.store_error;
    defer allocator.free(items);

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.append(allocator, '[');
    for (items, 0..) |row, i| {
        if (i != 0) try buf.append(allocator, ',');
        try writeVisitJson(allocator, &buf, row, resolveVisitJobCtx(self, row.job_id));
    }
    try buf.append(allocator, ']');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleCreate(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    var args = parseCreateArgs(allocator, args_json) catch |err| switch (err) {
        error.invalid_id => return HandlerError.invalid_id,
        error.invalid_job_id => return HandlerError.invalid_job_id,
        error.invalid_visit_type => return HandlerError.invalid_visit_type,
        error.invalid_status => return HandlerError.invalid_status,
        error.invalid_notes => return HandlerError.invalid_notes,
        error.invalid_actual_start => return HandlerError.invalid_actual_start,
        error.invalid_outcome => return HandlerError.invalid_outcome,
        error.OutOfMemory => return HandlerError.out_of_memory,
        else => return HandlerError.invalid_args,
    };
    defer args.deinit(allocator);

    // FK validation: if the handler was wired with a JobsStore pointer,
    // confirm `job_id` references an extant Job.  Returns a typed
    // `{error: "job_not_found", job_id}` body (200, NOT a dispatcher
    // error) so the helm can render a useful operator message instead
    // of a transport-level dispatch failure.  Without a JobsStore
    // pointer we fall through (best-effort; the visits store still
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

    // Acceptance: when the caller passes an id that already exists,
    // the contents MUST be byte-identical for the request to be
    // idempotent.  Differing contents return a typed validation error
    // instead of silently shadowing the prior record.  Mirrors
    // customers_handler's posture.
    if (self.store.findById(args.id)) |existing| {
        if (!visitContentsEqual(existing, args)) {
            return HandlerError.visit_id_in_use_with_different_contents;
        }
    }

    const visit = visits_store_fs.Visit{
        .id = args.id,
        .job_id = args.job_id,
        .visit_type = args.visit_type,
        .status = args.status,
        .notes = args.notes,
        .actual_start = args.actual_start,
        .outcome = args.outcome,
        .created_at = args.created_at,
        .updated_at = args.updated_at,
    };

    const outcome = self.store.append(visit) catch |err| switch (err) {
        visits_store_fs.StoreError.invalid_id => return HandlerError.invalid_id,
        visits_store_fs.StoreError.invalid_job_id => return HandlerError.invalid_job_id,
        visits_store_fs.StoreError.invalid_visit_type => return HandlerError.invalid_visit_type,
        visits_store_fs.StoreError.invalid_status => return HandlerError.invalid_status,
        visits_store_fs.StoreError.invalid_notes => return HandlerError.invalid_notes,
        visits_store_fs.StoreError.invalid_actual_start => return HandlerError.invalid_actual_start,
        visits_store_fs.StoreError.invalid_outcome => return HandlerError.invalid_outcome,
        else => return HandlerError.store_error,
    };

    // D-O5.followup-4 — emit `visit.created` after a genuine new write.
    // Best-effort; does NOT fail the create on emit error.
    if (outcome == .created) {
        emitVisitCreated(self, args.id, args.job_id, args.visit_type, args.status, args.created_at) catch {};
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

    const got = self.store.findById(id) orelse {
        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try buf.appendSlice(allocator, "{\"error\":\"not_found\",\"id\":");
        try writeJsonString(allocator, &buf, id);
        try buf.append(allocator, '}');
        return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
    };

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try writeVisitJson(allocator, &buf, got, resolveVisitJobCtx(self, got.job_id));
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// `visits.transition` — drives an existing visit through the §O4 Visit
// FSM (canonical table at runtime/semantos-brain/src/visit_fsm.zig).  Mirrors
// jobs.transition.
//
// Args shape:
//   { id: <string>,            -- the visit id; must already exist
//     to_state: <string>,      -- one of the four FSM states
//     presented_cap: <string>?,-- optional; every Visit row is ungated today
//     principal_kind: <string>,-- "operator" | "service"
//     actual_start: <string>?, -- optional; updates actual_start when supplied
//     outcome: <string>?       -- optional; updates outcome when supplied
//   }
//
// Success body (200): the new Visit (full shape; same as
// `visits.find_by_id`).
//
// Error body (200, NOT a dispatcher error): typed JSON
//   { "error": "<wrong_cap | not_reachable | wrong_principal |
//                unknown_state | not_found>",
//     "from": "<current state, or empty when not_found>",
//     "to": "<requested to_state>",
//     "cap_required": "<cap-or-null>" }
//
// Idempotent already-in-state body (200):
//   { "status": "already_in_state", "visit": <Visit> }
// ─────────────────────────────────────────────────────────────────────

const TransitionArgs = struct {
    id: []u8,
    to_state: []u8,
    presented_cap: ?[]u8,
    principal_kind: visit_fsm.PrincipalKind,
    actual_start: ?[]u8,
    outcome: ?[]u8,

    pub fn deinit(self: *TransitionArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.to_state);
        if (self.presented_cap) |c| allocator.free(c);
        if (self.actual_start) |s| allocator.free(s);
        if (self.outcome) |o| allocator.free(o);
    }
};

fn parseTransitionArgs(
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !TransitionArgs {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return error.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    const id_v = obj.get("id") orelse return error.invalid_args;
    if (id_v != .string) return error.invalid_args;
    if (id_v.string.len == 0 or id_v.string.len > visits_store_fs.MAX_ID_BYTES) return error.invalid_args;

    const to_v = obj.get("to_state") orelse return error.invalid_args;
    if (to_v != .string) return error.invalid_args;
    if (to_v.string.len == 0) return error.invalid_args;

    const principal_v = obj.get("principal_kind") orelse return error.invalid_principal_kind;
    if (principal_v != .string) return error.invalid_principal_kind;
    const principal_kind = visit_fsm.PrincipalKind.fromString(principal_v.string) orelse return error.invalid_principal_kind;

    var presented_cap_owned: ?[]u8 = null;
    if (obj.get("presented_cap")) |v| {
        if (v == .string and v.string.len > 0) {
            presented_cap_owned = try allocator.dupe(u8, v.string);
        }
    }
    errdefer if (presented_cap_owned) |c| allocator.free(c);

    var actual_start_owned: ?[]u8 = null;
    if (obj.get("actual_start")) |v| {
        if (v == .string) {
            if (v.string.len > visits_store_fs.MAX_ACTUAL_START_BYTES) return error.invalid_actual_start;
            actual_start_owned = try allocator.dupe(u8, v.string);
        }
    }
    errdefer if (actual_start_owned) |s| allocator.free(s);

    var outcome_owned: ?[]u8 = null;
    if (obj.get("outcome")) |v| {
        if (v == .string) {
            if (v.string.len > visits_store_fs.MAX_OUTCOME_BYTES) return error.invalid_outcome;
            outcome_owned = try allocator.dupe(u8, v.string);
        }
    }
    errdefer if (outcome_owned) |o| allocator.free(o);

    const id_owned = try allocator.dupe(u8, id_v.string);
    errdefer allocator.free(id_owned);
    const to_owned = try allocator.dupe(u8, to_v.string);

    return .{
        .id = id_owned,
        .to_state = to_owned,
        .presented_cap = presented_cap_owned,
        .principal_kind = principal_kind,
        .actual_start = actual_start_owned,
        .outcome = outcome_owned,
    };
}

fn handleTransition(
    self: *Handler,
    ctx: *const dispatcher.DispatchContext,
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !dispatcher.Result {
    var args = parseTransitionArgs(allocator, args_json) catch |err| switch (err) {
        error.invalid_principal_kind => return HandlerError.invalid_principal_kind,
        error.invalid_actual_start => return HandlerError.invalid_actual_start,
        error.invalid_outcome => return HandlerError.invalid_outcome,
        error.OutOfMemory => return HandlerError.out_of_memory,
        else => return HandlerError.invalid_args,
    };
    defer args.deinit(allocator);

    const current = self.store.findById(args.id) orelse {
        return writeTransitionError(
            allocator,
            "not_found",
            "",
            args.to_state,
            null,
        );
    };

    // Resolve presented cap — same shape as jobs.transition: explicit
    // `presented_cap` arg wins; otherwise if the FSM row's required cap
    // is in ctx.capabilities (or the auth is root-scope), we treat it
    // as presented.
    const fsm_cap_for_validation: ?[]const u8 = blk: {
        if (args.presented_cap) |c| break :blk c;
        if (visit_fsm.findTransition(current.status, args.to_state)) |row| {
            if (row.cap_required) |required| {
                if (ctx.capabilities.contains(required) or isRootAuth(ctx.auth)) {
                    break :blk required;
                }
            }
        }
        break :blk null;
    };

    const validation = visit_fsm.validateTransition(
        current.status,
        args.to_state,
        fsm_cap_for_validation,
        args.principal_kind,
    );

    switch (validation) {
        .err => |e| {
            switch (e.kind) {
                .already_in_state => {
                    return writeAlreadyInStateBody(allocator, current, resolveVisitJobCtx(self, current.job_id));
                },
                else => {
                    return writeTransitionError(
                        allocator,
                        e.kind.toString(),
                        e.from,
                        e.to,
                        e.cap_required,
                    );
                },
            }
        },
        .ok => |row| {
            // Stamp actual_start / outcome per the canonical visit-fsm.ts
            // semantics: scheduled → in_progress sets actualStart to the
            // wall clock when the caller didn't supply one; terminal
            // states (completed / cancelled) stamp outcome by default.
            // The store mutates in place + emits an `updated` log line.
            //
            // The server-stamped `ts` allocation lives at THIS scope so
            // its lifetime spans the `updateState` call below.  A nested
            // scope would `defer allocator.free(ts)` before the call,
            // dangling the slice (the store dupes inside updateState
            // but reading freed memory is still UB).
            var stamped_actual_start: ?[]const u8 = if (args.actual_start) |s| s else null;
            var stamped_outcome: ?[]const u8 = if (args.outcome) |o| o else null;
            var server_stamped_ts: ?[]u8 = null;
            defer if (server_stamped_ts) |s| allocator.free(s);

            if (std.mem.eql(u8, row.to, "in_progress") and stamped_actual_start == null and current.actual_start.len == 0) {
                server_stamped_ts = renderIsoTimestamp(allocator, std.time.timestamp()) catch return HandlerError.out_of_memory;
                stamped_actual_start = server_stamped_ts;
            }
            if (std.mem.eql(u8, row.to, "completed") and stamped_outcome == null and current.outcome.len == 0) {
                stamped_outcome = "completed";
            }
            if (std.mem.eql(u8, row.to, "cancelled") and stamped_outcome == null) {
                stamped_outcome = "cancelled";
            }

            // D-O5.followup-4 — capture from-state BEFORE updateState
            // mutates the store.  The visits store frees the old
            // status slice in-place (unlike jobs_store, which uses a
            // never-freed arena), so `current.status` is dangling
            // after updateState returns.  We dupe to keep the slice
            // alive across the emit call.
            const from_state_owned = try allocator.dupe(u8, current.status);
            defer allocator.free(from_state_owned);

            const updated = self.store.updateState(
                args.id,
                row.to,
                stamped_actual_start,
                stamped_outcome,
            ) catch |err| switch (err) {
                error.not_found => return writeTransitionError(
                    allocator,
                    "not_found",
                    "",
                    args.to_state,
                    null,
                ),
                else => return HandlerError.store_error,
            };

            // D-O5.followup-4 — emit `visit.transitioned`.  Best-effort;
            // does NOT fail the transition on emit error.
            emitVisitTransitioned(self, updated.id, updated.job_id, from_state_owned, updated.status) catch {};

            var buf: std.ArrayList(u8) = .{};
            errdefer buf.deinit(allocator);
            try writeVisitJson(allocator, &buf, updated, resolveVisitJobCtx(self, updated.job_id));
            return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
        },
    }
}

/// D-O5.followup-4 — publish a `visit.created` event to the broker
/// (when wired).  Mirrors `emitJobTransitioned` in jobs_handler.zig.
fn emitVisitCreated(
    self: *Handler,
    id: []const u8,
    job_id: []const u8,
    visit_type: []const u8,
    status: []const u8,
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
    try payload.appendSlice(allocator, ",\"visit_type\":");
    try writeJsonString(allocator, &payload, visit_type);
    try payload.appendSlice(allocator, ",\"status\":");
    try writeJsonString(allocator, &payload, status);
    try payload.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, &payload, created_at);
    try payload.append(allocator, '}');

    broker.publish(.{
        .type = "visit.created",
        .payload_json = payload.items,
    });

    if (self.audit) |a| {
        a.record(allocator, .{
            .module = "helm.broker",
            .op = "publish",
            .result = .ok,
            .detail = "visit.created",
        }) catch {};
    }
}

/// D-O5.followup-4 — publish a `visit.transitioned` event to the
/// broker.  Same shape as job.transitioned but keyed against
/// visit fields ({id, job_id, from, to, transitioned_at}).
fn emitVisitTransitioned(
    self: *Handler,
    id: []const u8,
    job_id: []const u8,
    from_state: []const u8,
    to_state: []const u8,
) !void {
    const broker = self.broker orelse return;
    const allocator = self.allocator;

    const transitioned_at = try renderIsoTimestamp(allocator, std.time.timestamp());
    defer allocator.free(transitioned_at);

    var payload: std.ArrayList(u8) = .{};
    defer payload.deinit(allocator);
    try payload.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, &payload, id);
    try payload.appendSlice(allocator, ",\"job_id\":");
    try writeJsonString(allocator, &payload, job_id);
    try payload.appendSlice(allocator, ",\"from\":");
    try writeJsonString(allocator, &payload, from_state);
    try payload.appendSlice(allocator, ",\"to\":");
    try writeJsonString(allocator, &payload, to_state);
    try payload.appendSlice(allocator, ",\"transitioned_at\":");
    try writeJsonString(allocator, &payload, transitioned_at);
    try payload.append(allocator, '}');

    broker.publish(.{
        .type = "visit.transitioned",
        .payload_json = payload.items,
    });

    if (self.audit) |a| {
        a.record(allocator, .{
            .module = "helm.broker",
            .op = "publish",
            .result = .ok,
            .detail = "visit.transitioned",
        }) catch {};
    }
}

/// Match the dispatcher's root-scope auth detection.  Mirrors
/// jobs_handler::isRootAuth.
fn isRootAuth(auth: dispatcher.AuthContext) bool {
    return switch (auth) {
        .in_process_root, .local_uid => true,
        .bearer, .cert, .anonymous => false,
    };
}

fn writeTransitionError(
    allocator: std.mem.Allocator,
    error_kind: []const u8,
    from: []const u8,
    to: []const u8,
    cap_required: ?[]const u8,
) !dispatcher.Result {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"error\":");
    try writeJsonString(allocator, &buf, error_kind);
    try buf.appendSlice(allocator, ",\"from\":");
    try writeJsonString(allocator, &buf, from);
    try buf.appendSlice(allocator, ",\"to\":");
    try writeJsonString(allocator, &buf, to);
    try buf.appendSlice(allocator, ",\"cap_required\":");
    if (cap_required) |c| {
        try writeJsonString(allocator, &buf, c);
    } else {
        try buf.appendSlice(allocator, "null");
    }
    try buf.append(allocator, '}');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn writeAlreadyInStateBody(
    allocator: std.mem.Allocator,
    current: visits_store_fs.Visit,
    job_ctx: VisitJobCtx,
) !dispatcher.Result {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"status\":\"already_in_state\",\"visit\":");
    try writeVisitJson(allocator, &buf, current, job_ctx);
    try buf.append(allocator, '}');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// Args parsing
// ─────────────────────────────────────────────────────────────────────

const CreateArgs = struct {
    id: []u8,
    job_id: []u8,
    visit_type: []u8,
    status: []u8,
    notes: []u8,
    actual_start: []u8,
    outcome: []u8,
    created_at: []u8,
    updated_at: []u8,

    pub fn deinit(self: *CreateArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.job_id);
        allocator.free(self.visit_type);
        allocator.free(self.status);
        allocator.free(self.notes);
        allocator.free(self.actual_start);
        allocator.free(self.outcome);
        allocator.free(self.created_at);
        allocator.free(self.updated_at);
    }
};

const ParseError = error{
    invalid_args,
    invalid_id,
    invalid_job_id,
    invalid_visit_type,
    invalid_status,
    invalid_notes,
    invalid_actual_start,
    invalid_outcome,
    out_of_memory,
    OutOfMemory,
};

/// `find` accepts an optional `{job_id: "..."}` filter.  Returns null
/// when no filter is present (caller treats that as "all visits");
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
    if (ji_v.string.len == 0 or ji_v.string.len > visits_store_fs.MAX_JOB_ID_BYTES) return error.invalid_job_id;

    // visit_type (required, must match VISIT_TYPES).
    const vt_v = obj.get("visit_type") orelse return error.invalid_visit_type;
    if (vt_v != .string) return error.invalid_visit_type;
    if (!visits_store_fs.isValidVisitType(vt_v.string)) return error.invalid_visit_type;

    // id (optional — server-stamped when empty).
    const id_str: []const u8 = blk: {
        if (obj.get("id")) |v| {
            if (v != .string) return error.invalid_id;
            if (v.string.len > visits_store_fs.MAX_ID_BYTES) return error.invalid_id;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };

    // status (optional; defaults to "scheduled").
    const st_str: []const u8 = blk: {
        if (obj.get("status")) |v| {
            if (v != .string) return error.invalid_status;
            if (v.string.len > 0) {
                if (!visits_store_fs.isValidStatus(v.string)) return error.invalid_status;
                break :blk v.string;
            }
        }
        break :blk "scheduled";
    };

    // notes (optional, ≤ 2000).
    const no_v: []const u8 = blk: {
        if (obj.get("notes")) |v| {
            if (v != .string) return error.invalid_notes;
            if (v.string.len > visits_store_fs.MAX_NOTES_BYTES) return error.invalid_notes;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // actual_start (optional).
    const as_v: []const u8 = blk: {
        if (obj.get("actual_start")) |v| {
            if (v != .string) return error.invalid_actual_start;
            if (v.string.len > visits_store_fs.MAX_ACTUAL_START_BYTES) return error.invalid_actual_start;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // outcome (optional).
    const oc_v: []const u8 = blk: {
        if (obj.get("outcome")) |v| {
            if (v != .string) return error.invalid_outcome;
            if (v.string.len > visits_store_fs.MAX_OUTCOME_BYTES) return error.invalid_outcome;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // created_at + updated_at (both optional; server-stamps when empty).
    const ca_v: []const u8 = blk: {
        if (obj.get("created_at")) |v| {
            if (v != .string) return error.invalid_args;
            if (v.string.len > visits_store_fs.MAX_CREATED_AT_BYTES) return error.invalid_args;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };
    const ua_v: []const u8 = blk: {
        if (obj.get("updated_at")) |v| {
            if (v != .string) return error.invalid_args;
            if (v.string.len > visits_store_fs.MAX_UPDATED_AT_BYTES) return error.invalid_args;
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
    const vt_owned = try allocator.dupe(u8, vt_v.string);
    errdefer allocator.free(vt_owned);
    const st_owned = try allocator.dupe(u8, st_str);
    errdefer allocator.free(st_owned);
    const no_owned = try allocator.dupe(u8, no_v);
    errdefer allocator.free(no_owned);
    const as_owned = try allocator.dupe(u8, as_v);
    errdefer allocator.free(as_owned);
    const oc_owned = try allocator.dupe(u8, oc_v);
    errdefer allocator.free(oc_owned);

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
        // moment for a freshly minted visit.
        ua_owned = try allocator.dupe(u8, ca_owned);
    } else {
        ua_owned = try allocator.dupe(u8, ua_v);
    }
    errdefer allocator.free(ua_owned);

    return .{
        .id = id_owned,
        .job_id = ji_owned,
        .visit_type = vt_owned,
        .status = st_owned,
        .notes = no_owned,
        .actual_start = as_owned,
        .outcome = oc_owned,
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
    if (v.string.len == 0 or v.string.len > visits_store_fs.MAX_ID_BYTES) return error.invalid_args;
    return try allocator.dupe(u8, v.string);
}

/// Compare a stored Visit record (slices) against the parsed
/// CreateArgs (also slices).  All fields except updated_at must match
/// byte-for-byte for an idempotent recreate.  Mirrors customers_handler's
/// posture.
fn visitContentsEqual(stored: visits_store_fs.Visit, args: CreateArgs) bool {
    return std.mem.eql(u8, stored.job_id, args.job_id) and
        std.mem.eql(u8, stored.visit_type, args.visit_type) and
        std.mem.eql(u8, stored.status, args.status) and
        std.mem.eql(u8, stored.notes, args.notes) and
        std.mem.eql(u8, stored.actual_start, args.actual_start) and
        std.mem.eql(u8, stored.outcome, args.outcome) and
        std.mem.eql(u8, stored.created_at, args.created_at);
}

// ─────────────────────────────────────────────────────────────────────
// JSON rendering helpers
// ─────────────────────────────────────────────────────────────────────

/// RM-124 — resolved parent-job context so a scheduled visit shows
/// who/where/what instead of bare hex IDs. Slices borrow from the
/// live JobsStore record (stable for the serialize call).
const VisitJobCtx = struct {
    customer_name: []const u8 = "",
    property_address: []const u8 = "",
    description: []const u8 = "",
};

/// Resolve a visit's parent job (RM-121-resolved customer/site/work)
/// via the borrowed JobsStore. Empty ctx when unresolved.
fn resolveVisitJobCtx(self: *Handler, job_id: []const u8) VisitJobCtx {
    const js = self.jobs_store orelse return .{};
    const j = js.findById(job_id) orelse return .{};
    return .{
        .customer_name = j.customer_name,
        .property_address = j.propertyAddress orelse "",
        .description = j.description orelse "",
    };
}

fn writeVisitJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    visit: visits_store_fs.Visit,
    job_ctx: VisitJobCtx,
) !void {
    try out.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, out, visit.id);
    try out.appendSlice(allocator, ",\"job_id\":");
    try writeJsonString(allocator, out, visit.job_id);
    // RM-124 — resolved parent-job context (mirrors RM-121 on jobs).
    try out.appendSlice(allocator, ",\"job_customer_name\":");
    try writeJsonString(allocator, out, job_ctx.customer_name);
    try out.appendSlice(allocator, ",\"job_property_address\":");
    try writeJsonString(allocator, out, job_ctx.property_address);
    try out.appendSlice(allocator, ",\"job_description\":");
    try writeJsonString(allocator, out, job_ctx.description);
    try out.appendSlice(allocator, ",\"visit_type\":");
    try writeJsonString(allocator, out, visit.visit_type);
    try out.appendSlice(allocator, ",\"status\":");
    try writeJsonString(allocator, out, visit.status);
    try out.appendSlice(allocator, ",\"notes\":");
    try writeJsonString(allocator, out, visit.notes);
    try out.appendSlice(allocator, ",\"actual_start\":");
    try writeJsonString(allocator, out, visit.actual_start);
    try out.appendSlice(allocator, ",\"outcome\":");
    try writeJsonString(allocator, out, visit.outcome);
    try out.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, out, visit.created_at);
    try out.appendSlice(allocator, ",\"updated_at\":");
    try writeJsonString(allocator, out, visit.updated_at);
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
/// MM-DDTHH:MM:SSZ").  Mirrors the same helper in jobs_handler.zig and
/// customers_handler.zig.
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
