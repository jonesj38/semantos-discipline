---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/resources/quotes_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.553230+00:00
---

# cartridges/oddjobz/brain/zig/src/resources/quotes_handler.zig

```zig
// D-O4.followup-3 — Typed `quotes` dispatcher resource (Quote FSM cutover).
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3, §8;
//            docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4 (Quote FSM table)
//                                                 §O5 (helm quotes view).
//
// Mirrors `visits_handler.zig` (post-#312) for the Quote cell type —
// the sequential mirror of what #311 + #312 did for Jobs and Visits,
// applied to `oddjobz.quote.v1`.  Both helms (loom-svelte QuoteList +
// oddjobz-mobile QuoteListScreen) wire state-aware action buttons to
// this resource; the dispatcher's audit pair captures every transition
// because the brief is explicit that transitions are the prototypical
// audit-relevant event.
//
// Commands:
//   find         — { job_id? }            →  [ Quote, ... ]
//                                            cap = cap.oddjobz.read_quotes
//                                          When `job_id` is supplied, the
//                                          response is filtered to quotes
//                                          whose parent Job matches.
//   create       — { id?, job_id,
//                    cost_min?, cost_max?,
//                    notes?, status? }    →  { id, status: "created"
//                                                   | "already_exists" }
//                                            cap = cap.oddjobz.write_quote
//                                          Validates: job_id exists in
//                                          jobs_store (else `{error:
//                                          "job_not_found", job_id}`);
//                                          cost_min/max ≥ 0 and
//                                          cost_max ≥ cost_min; notes ≤
//                                          2000 chars; status defaults to
//                                          "draft".  Idempotency: same
//                                          id with identical contents →
//                                          already_exists; same id with
//                                          different contents → typed
//                                          error.
//   find_by_id   — { id }                →  Quote
//                                            cap = cap.oddjobz.read_quotes
//                                          (or { error: "not_found", id }
//                                           on miss — same shape as
//                                           visits_handler / jobs_handler /
//                                           customers_handler)
//   transition   — { id, to_state,
//                    presented_cap?,
//                    principal_kind,
//                    accepted_at?,
//                    rejected_at? }       →  the new Quote
//                                            cap = cap.oddjobz.read_quotes
//                                          Per-FSM-row cap is checked
//                                          INSIDE the handler against
//                                          ctx.capabilities (every Quote
//                                          row is ungated today; the
//                                          shape is preserved for future
//                                          rows).
//
// FK validation: `quotes.create` calls `jobs_store.findById(job_id)`
// before delegating to the quotes store.  This is the loose-coupling
// seam the brief calls for — the quotes store doesn't know about the
// jobs store, the handler knits them together at the dispatcher layer.
//
// Concurrency: a single mutex serialises all handler entry points
// against the live store; same shape as bearer_tokens_handler.zig +
// jobs_handler.zig + visits_handler.zig.

const std = @import("std");
const dispatcher = @import("dispatcher");
const verb_schema = @import("verb_schema"); // C4 PR-R2b — generic-REPL verb self-description
const quotes_store_fs = @import("quotes_store_fs");
const jobs_store_fs = @import("jobs_store_fs");
const quote_fsm = @import("quote_fsm");
const helm_event_broker = @import("helm_event_broker");
const audit_log = @import("audit_log");

pub const RESOURCE_NAME = "quotes";

/// Capability declarations.
///
/// `cap.oddjobz.read_quotes` (`0x0001010B`) and `cap.oddjobz.write_quote`
/// (`0x0001010C`) are the two new caps minted in `cartridges/oddjobz/brain/
/// src/capabilities.ts` alongside the existing ten oddjobz caps.
pub const CAP_READ_QUOTES: []const u8 = "cap.oddjobz.read_quotes";
pub const CAP_WRITE_QUOTE: []const u8 = "cap.oddjobz.write_quote";

pub const HandlerError = error{
    /// JSON args parse failed or required arg missing.
    invalid_args,
    /// Underlying QuotesStore validator rejected the input.
    invalid_id,
    invalid_job_id,
    invalid_status,
    invalid_notes,
    invalid_cost,
    invalid_accepted_at,
    invalid_rejected_at,
    /// Caller passed an id that already exists in the store but the
    /// other fields disagree with what's on file.  Idempotent recreate
    /// requires byte-identical contents.
    quote_id_in_use_with_different_contents,
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
/// the sole owner of the QuotesStore for the dispatcher's lifetime;
/// the daemon (or REPL bootstrap) constructs it once at boot and
/// registers the handler via `register`.  The handler also borrows a
/// pointer to the JobsStore for FK validation on `quotes.create` —
/// loose-coupling seam (the quotes store itself doesn't know about
/// the jobs store).
pub const Handler = struct {
    allocator: std.mem.Allocator,
    store: *quotes_store_fs.QuotesStore,
    /// Borrowed pointer to the live JobsStore — used by `quotes.create`
    /// to validate that the caller-supplied `job_id` references an
    /// extant Job record.  May be null when the daemon stood up the
    /// quotes handler without a jobs store (best-effort init posture
    /// matches the cli wiring); FK validation is skipped in that case
    /// (the quotes store still validates length envelope on job_id).
    jobs_store: ?*jobs_store_fs.JobsStore,
    /// Serialises find / create / find_by_id / transition against the
    /// underlying store.  The store itself is not thread-safe; this
    /// mutex is the seam between concurrent transport callers.
    mu: std.Thread.Mutex,
    /// D-O5.followup-4 — optional event broker.  Mirrors the
    /// jobs_handler / visits_handler pattern.
    broker: ?*helm_event_broker.Broker,
    /// D-O5.followup-4 — optional audit log for phase=publish lines.
    audit: ?*audit_log.AuditLog,

    pub fn init(
        allocator: std.mem.Allocator,
        store: *quotes_store_fs.QuotesStore,
        jobs_store: ?*jobs_store_fs.JobsStore,
    ) Handler {
        return initWithBroker(allocator, store, jobs_store, null, null);
    }

    /// D-O5.followup-4 — broker-aware constructor.
    pub fn initWithBroker(
        allocator: std.mem.Allocator,
        store: *quotes_store_fs.QuotesStore,
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

// C4 PR-R2b — verb self-description for the generic `quotes <verb>` REPL path.
// `transition` omitted (needs principal-context injection → R3 sugar alias).
const QUOTES_VERBS = [_]verb_schema.VerbSpec{
    .{ .verb = "find", .summary = "list quotes (optional job_id filter)", .args = &.{
        .{ .name = "job_id", .kind = .string },
    } },
    .{ .verb = "find_by_id", .summary = "fetch one quote by id", .args = &.{
        .{ .name = "id", .kind = .string, .required = true, .positional = true },
    } },
    .{ .verb = "create", .summary = "create a quote", .args = &.{
        .{ .name = "job_id", .kind = .string, .required = true },
        .{ .name = "id", .kind = .string },
        .{ .name = "status", .kind = .string },
        .{ .name = "cost_min", .kind = .int },
        .{ .name = "cost_max", .kind = .int },
        .{ .name = "notes", .kind = .string },
        .{ .name = "accepted_at", .kind = .string },
        .{ .name = "rejected_at", .kind = .string },
        .{ .name = "created_at", .kind = .string },
        .{ .name = "updated_at", .kind = .string },
    } },
};
fn verbsFn(_: ?*anyopaque) []const verb_schema.VerbSpec {
    return &QUOTES_VERBS;
}

// ─────────────────────────────────────────────────────────────────────
// Capability declarations
// ─────────────────────────────────────────────────────────────────────

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "find")) return .{ .require = CAP_READ_QUOTES };
    if (std.mem.eql(u8, cmd, "find_by_id")) return .{ .require = CAP_READ_QUOTES };
    if (std.mem.eql(u8, cmd, "create")) return .{ .require = CAP_WRITE_QUOTE };
    // `transition` is dispatcher-gated on the read cap (you must be
    // able to see the quote to transition it).  The PER-TRANSITION cap
    // (currently null for every Quote row, but reserved for future
    // rows) is checked INSIDE the handler.  Same split as
    // visits.transition / jobs.transition.
    if (std.mem.eql(u8, cmd, "transition")) return .{ .require = CAP_READ_QUOTES };
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

    const items: []quotes_store_fs.Quote = if (filter) |f|
        self.store.findByJobId(allocator, f) catch return HandlerError.store_error
    else
        self.store.findAll(allocator) catch return HandlerError.store_error;
    defer allocator.free(items);

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.append(allocator, '[');
    for (items, 0..) |row, i| {
        if (i != 0) try buf.append(allocator, ',');
        try writeQuoteJson(allocator, &buf, row);
    }
    try buf.append(allocator, ']');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleCreate(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    var args = parseCreateArgs(allocator, args_json) catch |err| switch (err) {
        error.invalid_id => return HandlerError.invalid_id,
        error.invalid_job_id => return HandlerError.invalid_job_id,
        error.invalid_status => return HandlerError.invalid_status,
        error.invalid_notes => return HandlerError.invalid_notes,
        error.invalid_cost => return HandlerError.invalid_cost,
        error.invalid_accepted_at => return HandlerError.invalid_accepted_at,
        error.invalid_rejected_at => return HandlerError.invalid_rejected_at,
        error.OutOfMemory => return HandlerError.out_of_memory,
        else => return HandlerError.invalid_args,
    };
    defer args.deinit(allocator);

    // FK validation: if the handler was wired with a JobsStore pointer,
    // confirm `job_id` references an extant Job.  Returns a typed
    // `{error: "job_not_found", job_id}` body (200, NOT a dispatcher
    // error) so the helm can render a useful operator message instead
    // of a transport-level dispatch failure.  Without a JobsStore
    // pointer we fall through (best-effort; the quotes store still
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
    // visits_handler / customers_handler posture.
    if (self.store.findById(args.id)) |existing| {
        if (!quoteContentsEqual(existing, args)) {
            return HandlerError.quote_id_in_use_with_different_contents;
        }
    }

    const quote = quotes_store_fs.Quote{
        .id = args.id,
        .job_id = args.job_id,
        .status = args.status,
        .cost_min = args.cost_min,
        .cost_max = args.cost_max,
        .notes = args.notes,
        .accepted_at = args.accepted_at,
        .rejected_at = args.rejected_at,
        .created_at = args.created_at,
        .updated_at = args.updated_at,
    };

    const outcome = self.store.append(quote) catch |err| switch (err) {
        quotes_store_fs.StoreError.invalid_id => return HandlerError.invalid_id,
        quotes_store_fs.StoreError.invalid_job_id => return HandlerError.invalid_job_id,
        quotes_store_fs.StoreError.invalid_status => return HandlerError.invalid_status,
        quotes_store_fs.StoreError.invalid_notes => return HandlerError.invalid_notes,
        quotes_store_fs.StoreError.invalid_cost => return HandlerError.invalid_cost,
        quotes_store_fs.StoreError.invalid_accepted_at => return HandlerError.invalid_accepted_at,
        quotes_store_fs.StoreError.invalid_rejected_at => return HandlerError.invalid_rejected_at,
        else => return HandlerError.store_error,
    };

    // D-O5.followup-4 — emit `quote.created` after a genuine new write.
    if (outcome == .created) {
        emitQuoteCreated(
            self,
            args.id,
            args.job_id,
            args.status,
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
    try writeQuoteJson(allocator, &buf, got);
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// `quotes.transition` — drives an existing quote through the §O4 Quote
// FSM (canonical table at runtime/semantos-brain/src/quote_fsm.zig).  Mirrors
// visits.transition.
//
// Args shape:
//   { id: <string>,            -- the quote id; must already exist
//     to_state: <string>,      -- one of the six FSM states
//     presented_cap: <string>?,-- optional; every Quote row is ungated today
//     principal_kind: <string>,-- "operator" | "service"
//     accepted_at: <string>?,  -- optional; updates accepted_at when supplied
//     rejected_at: <string>?   -- optional; updates rejected_at when supplied
//   }
//
// Success body (200): the new Quote (full shape; same as
// `quotes.find_by_id`).
//
// Error body (200, NOT a dispatcher error): typed JSON
//   { "error": "<wrong_cap | not_reachable | wrong_principal |
//                unknown_state | not_found>",
//     "from": "<current state, or empty when not_found>",
//     "to": "<requested to_state>",
//     "cap_required": "<cap-or-null>" }
//
// Idempotent already-in-state body (200):
//   { "status": "already_in_state", "quote": <Quote> }
// ─────────────────────────────────────────────────────────────────────

const TransitionArgs = struct {
    id: []u8,
    to_state: []u8,
    presented_cap: ?[]u8,
    principal_kind: quote_fsm.PrincipalKind,
    accepted_at: ?[]u8,
    rejected_at: ?[]u8,

    pub fn deinit(self: *TransitionArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.to_state);
        if (self.presented_cap) |c| allocator.free(c);
        if (self.accepted_at) |s| allocator.free(s);
        if (self.rejected_at) |r| allocator.free(r);
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
    if (id_v.string.len == 0 or id_v.string.len > quotes_store_fs.MAX_ID_BYTES) return error.invalid_args;

    const to_v = obj.get("to_state") orelse return error.invalid_args;
    if (to_v != .string) return error.invalid_args;
    if (to_v.string.len == 0) return error.invalid_args;

    const principal_v = obj.get("principal_kind") orelse return error.invalid_principal_kind;
    if (principal_v != .string) return error.invalid_principal_kind;
    const principal_kind = quote_fsm.PrincipalKind.fromString(principal_v.string) orelse return error.invalid_principal_kind;

    var presented_cap_owned: ?[]u8 = null;
    if (obj.get("presented_cap")) |v| {
        if (v == .string and v.string.len > 0) {
            presented_cap_owned = try allocator.dupe(u8, v.string);
        }
    }
    errdefer if (presented_cap_owned) |c| allocator.free(c);

    var accepted_at_owned: ?[]u8 = null;
    if (obj.get("accepted_at")) |v| {
        if (v == .string) {
            if (v.string.len > quotes_store_fs.MAX_ACCEPTED_AT_BYTES) return error.invalid_accepted_at;
            accepted_at_owned = try allocator.dupe(u8, v.string);
        }
    }
    errdefer if (accepted_at_owned) |s| allocator.free(s);

    var rejected_at_owned: ?[]u8 = null;
    if (obj.get("rejected_at")) |v| {
        if (v == .string) {
            if (v.string.len > quotes_store_fs.MAX_REJECTED_AT_BYTES) return error.invalid_rejected_at;
            rejected_at_owned = try allocator.dupe(u8, v.string);
        }
    }
    errdefer if (rejected_at_owned) |r| allocator.free(r);

    const id_owned = try allocator.dupe(u8, id_v.string);
    errdefer allocator.free(id_owned);
    const to_owned = try allocator.dupe(u8, to_v.string);

    return .{
        .id = id_owned,
        .to_state = to_owned,
        .presented_cap = presented_cap_owned,
        .principal_kind = principal_kind,
        .accepted_at = accepted_at_owned,
        .rejected_at = rejected_at_owned,
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
        error.invalid_accepted_at => return HandlerError.invalid_accepted_at,
        error.invalid_rejected_at => return HandlerError.invalid_rejected_at,
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

    // Resolve presented cap — same shape as visits.transition: explicit
    // `presented_cap` arg wins; otherwise if the FSM row's required cap
    // is in ctx.capabilities (or the auth is root-scope), we treat it
    // as presented.
    const fsm_cap_for_validation: ?[]const u8 = blk: {
        if (args.presented_cap) |c| break :blk c;
        if (quote_fsm.findTransition(current.status, args.to_state)) |row| {
            if (row.cap_required) |required| {
                if (ctx.capabilities.contains(required) or isRootAuth(ctx.auth)) {
                    break :blk required;
                }
            }
        }
        break :blk null;
    };

    const validation = quote_fsm.validateTransition(
        current.status,
        args.to_state,
        fsm_cap_for_validation,
        args.principal_kind,
    );

    switch (validation) {
        .err => |e| {
            switch (e.kind) {
                .already_in_state => {
                    return writeAlreadyInStateBody(allocator, current);
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
            // Stamp accepted_at / rejected_at per the canonical
            // quote-fsm.ts semantics: presented → accepted sets
            // acceptedAt to the wall clock when the caller didn't
            // supply one; presented → rejected sets rejectedAt by
            // default.  The store mutates in place + emits an
            // `updated` log line.
            //
            // The server-stamped `ts` allocation lives at THIS scope so
            // its lifetime spans the `updateState` call below.  A
            // nested scope would `defer allocator.free(ts)` before the
            // call, dangling the slice (the store dupes inside
            // updateState but reading freed memory is still UB).
            var stamped_accepted_at: ?[]const u8 = if (args.accepted_at) |s| s else null;
            var stamped_rejected_at: ?[]const u8 = if (args.rejected_at) |r| r else null;
            var server_stamped_ts: ?[]u8 = null;
            defer if (server_stamped_ts) |s| allocator.free(s);

            if (std.mem.eql(u8, row.to, "accepted") and stamped_accepted_at == null and current.accepted_at.len == 0) {
                server_stamped_ts = renderIsoTimestamp(allocator, std.time.timestamp()) catch return HandlerError.out_of_memory;
                stamped_accepted_at = server_stamped_ts;
            }
            if (std.mem.eql(u8, row.to, "rejected") and stamped_rejected_at == null and current.rejected_at.len == 0) {
                if (server_stamped_ts == null) {
                    server_stamped_ts = renderIsoTimestamp(allocator, std.time.timestamp()) catch return HandlerError.out_of_memory;
                }
                stamped_rejected_at = server_stamped_ts;
            }

            // D-O5.followup-4 — capture from-state BEFORE updateState
            // mutates the store.  The quotes store frees the old
            // status slice in-place, so `current.status` would dangle
            // after updateState returns; dupe to keep it alive.
            const from_state_owned = try allocator.dupe(u8, current.status);
            defer allocator.free(from_state_owned);

            const updated = self.store.updateState(
                args.id,
                row.to,
                stamped_accepted_at,
                stamped_rejected_at,
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

            // D-O5.followup-4 — emit `quote.transitioned`.
            emitQuoteTransitioned(self, updated.id, updated.job_id, from_state_owned, updated.status) catch {};

            var buf: std.ArrayList(u8) = .{};
            errdefer buf.deinit(allocator);
            try writeQuoteJson(allocator, &buf, updated);
            return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
        },
    }
}

/// D-O5.followup-4 — publish a `quote.created` event to the broker.
fn emitQuoteCreated(
    self: *Handler,
    id: []const u8,
    job_id: []const u8,
    status: []const u8,
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
    try payload.appendSlice(allocator, ",\"status\":");
    try writeJsonString(allocator, &payload, status);
    try payload.print(allocator, ",\"cost_min\":{d}", .{cost_min});
    try payload.print(allocator, ",\"cost_max\":{d}", .{cost_max});
    try payload.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, &payload, created_at);
    try payload.append(allocator, '}');

    broker.publish(.{
        .type = "quote.created",
        .payload_json = payload.items,
    });

    if (self.audit) |a| {
        a.record(allocator, .{
            .module = "helm.broker",
            .op = "publish",
            .result = .ok,
            .detail = "quote.created",
        }) catch {};
    }
}

/// D-O5.followup-4 — publish a `quote.transitioned` event to the broker.
fn emitQuoteTransitioned(
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
        .type = "quote.transitioned",
        .payload_json = payload.items,
    });

    if (self.audit) |a| {
        a.record(allocator, .{
            .module = "helm.broker",
            .op = "publish",
            .result = .ok,
            .detail = "quote.transitioned",
        }) catch {};
    }
}

/// Match the dispatcher's root-scope auth detection.  Mirrors
/// jobs_handler::isRootAuth + visits_handler::isRootAuth.
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
    current: quotes_store_fs.Quote,
) !dispatcher.Result {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"status\":\"already_in_state\",\"quote\":");
    try writeQuoteJson(allocator, &buf, current);
    try buf.append(allocator, '}');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// Args parsing
// ─────────────────────────────────────────────────────────────────────

const CreateArgs = struct {
    id: []u8,
    job_id: []u8,
    status: []u8,
    cost_min: i64,
    cost_max: i64,
    notes: []u8,
    accepted_at: []u8,
    rejected_at: []u8,
    created_at: []u8,
    updated_at: []u8,

    pub fn deinit(self: *CreateArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.job_id);
        allocator.free(self.status);
        allocator.free(self.notes);
        allocator.free(self.accepted_at);
        allocator.free(self.rejected_at);
        allocator.free(self.created_at);
        allocator.free(self.updated_at);
    }
};

const ParseError = error{
    invalid_args,
    invalid_id,
    invalid_job_id,
    invalid_status,
    invalid_notes,
    invalid_cost,
    invalid_accepted_at,
    invalid_rejected_at,
    out_of_memory,
    OutOfMemory,
};

/// `find` accepts an optional `{job_id: "..."}` filter.  Returns null
/// when no filter is present (caller treats that as "all quotes");
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
    if (ji_v.string.len == 0 or ji_v.string.len > quotes_store_fs.MAX_JOB_ID_BYTES) return error.invalid_job_id;

    // id (optional — server-stamped when empty).
    const id_str: []const u8 = blk: {
        if (obj.get("id")) |v| {
            if (v != .string) return error.invalid_id;
            if (v.string.len > quotes_store_fs.MAX_ID_BYTES) return error.invalid_id;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };

    // status (optional; defaults to "draft").
    const st_str: []const u8 = blk: {
        if (obj.get("status")) |v| {
            if (v != .string) return error.invalid_status;
            if (v.string.len > 0) {
                if (!quotes_store_fs.isValidStatus(v.string)) return error.invalid_status;
                break :blk v.string;
            }
        }
        break :blk "draft";
    };

    // cost_min / cost_max (both optional integer; default 0 — the
    // store enforces non-negative + cost_max ≥ cost_min, so omitting
    // both yields {0, 0} which is valid).
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
            if (v.string.len > quotes_store_fs.MAX_NOTES_BYTES) return error.invalid_notes;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // accepted_at (optional).
    const aa_v: []const u8 = blk: {
        if (obj.get("accepted_at")) |v| {
            if (v != .string) return error.invalid_accepted_at;
            if (v.string.len > quotes_store_fs.MAX_ACCEPTED_AT_BYTES) return error.invalid_accepted_at;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // rejected_at (optional).
    const ra_v: []const u8 = blk: {
        if (obj.get("rejected_at")) |v| {
            if (v != .string) return error.invalid_rejected_at;
            if (v.string.len > quotes_store_fs.MAX_REJECTED_AT_BYTES) return error.invalid_rejected_at;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // created_at + updated_at (both optional; server-stamps when empty).
    const ca_v: []const u8 = blk: {
        if (obj.get("created_at")) |v| {
            if (v != .string) return error.invalid_args;
            if (v.string.len > quotes_store_fs.MAX_CREATED_AT_BYTES) return error.invalid_args;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };
    const ua_v: []const u8 = blk: {
        if (obj.get("updated_at")) |v| {
            if (v != .string) return error.invalid_args;
            if (v.string.len > quotes_store_fs.MAX_UPDATED_AT_BYTES) return error.invalid_args;
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
    const st_owned = try allocator.dupe(u8, st_str);
    errdefer allocator.free(st_owned);
    const no_owned = try allocator.dupe(u8, no_v);
    errdefer allocator.free(no_owned);
    const aa_owned = try allocator.dupe(u8, aa_v);
    errdefer allocator.free(aa_owned);
    const ra_owned = try allocator.dupe(u8, ra_v);
    errdefer allocator.free(ra_owned);

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
        // moment for a freshly minted quote.
        ua_owned = try allocator.dupe(u8, ca_owned);
    } else {
        ua_owned = try allocator.dupe(u8, ua_v);
    }
    errdefer allocator.free(ua_owned);

    return .{
        .id = id_owned,
        .job_id = ji_owned,
        .status = st_owned,
        .cost_min = cmin,
        .cost_max = cmax,
        .notes = no_owned,
        .accepted_at = aa_owned,
        .rejected_at = ra_owned,
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
    if (v.string.len == 0 or v.string.len > quotes_store_fs.MAX_ID_BYTES) return error.invalid_args;
    return try allocator.dupe(u8, v.string);
}

/// Compare a stored Quote record (slices) against the parsed
/// CreateArgs (also slices).  All fields except updated_at must match
/// byte-for-byte for an idempotent recreate.  Mirrors
/// visits_handler / customers_handler posture.
fn quoteContentsEqual(stored: quotes_store_fs.Quote, args: CreateArgs) bool {
    return std.mem.eql(u8, stored.job_id, args.job_id) and
        std.mem.eql(u8, stored.status, args.status) and
        stored.cost_min == args.cost_min and
        stored.cost_max == args.cost_max and
        std.mem.eql(u8, stored.notes, args.notes) and
        std.mem.eql(u8, stored.accepted_at, args.accepted_at) and
        std.mem.eql(u8, stored.rejected_at, args.rejected_at) and
        std.mem.eql(u8, stored.created_at, args.created_at);
}

// ─────────────────────────────────────────────────────────────────────
// JSON rendering helpers
// ─────────────────────────────────────────────────────────────────────

fn writeQuoteJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), quote: quotes_store_fs.Quote) !void {
    try out.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, out, quote.id);
    try out.appendSlice(allocator, ",\"job_id\":");
    try writeJsonString(allocator, out, quote.job_id);
    try out.appendSlice(allocator, ",\"status\":");
    try writeJsonString(allocator, out, quote.status);
    try out.print(allocator, ",\"cost_min\":{d}", .{quote.cost_min});
    try out.print(allocator, ",\"cost_max\":{d}", .{quote.cost_max});
    try out.appendSlice(allocator, ",\"notes\":");
    try writeJsonString(allocator, out, quote.notes);
    try out.appendSlice(allocator, ",\"accepted_at\":");
    try writeJsonString(allocator, out, quote.accepted_at);
    try out.appendSlice(allocator, ",\"rejected_at\":");
    try writeJsonString(allocator, out, quote.rejected_at);
    try out.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, out, quote.created_at);
    try out.appendSlice(allocator, ",\"updated_at\":");
    try writeJsonString(allocator, out, quote.updated_at);
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
/// MM-DDTHH:MM:SSZ").  Mirrors the same helper in jobs_handler.zig +
/// visits_handler.zig + customers_handler.zig.
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
