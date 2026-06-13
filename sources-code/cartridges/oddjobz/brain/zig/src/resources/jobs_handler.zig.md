---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/resources/jobs_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.552829+00:00
---

# cartridges/oddjobz/brain/zig/src/resources/jobs_handler.zig

```zig
// D-O5.followup-1 / D-O5m.followup-4 — Typed `jobs` dispatcher resource.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3, §8;
//            docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4 (Job FSM table)
//                                                 §O5 (helm jobs view).
//
// D-O5 followup-1 (this PR — Job FSM cutover) extends the resource
// with a `jobs.transition` command that drives jobs through the
// canonical §O4 FSM (port lives at runtime/semantos-brain/src/job_fsm.zig).  Both
// helms (loom-svelte JobDetail + oddjobz-mobile JobDetailScreen) wire
// state-aware action buttons to this command; the dispatcher's audit
// pair captures every transition because the brief is explicit that
// transitions are the prototypical audit-relevant event.
//
// FSM-level errors (wrong_cap / not_reachable / wrong_principal /
// already_in_state) are returned as typed JSON bodies (200, NOT
// dispatcher errors).  Cap-gating-at-the-DISPATCHER-level for the
// transition command itself uses `cap.oddjobz.read_jobs` as the
// baseline (you have to be able to read jobs to know which one to
// transition); the per-FSM-row cap (cap.oddjobz.quote / dispatch /
// invoice / close) is checked INSIDE the handler against
// `ctx.capabilities` and converted to a typed body on mismatch.  This
// lets the helm distinguish "operator has no oddjobz access at all"
// (capability_denied → 401-shape) from "operator has read access but
// is missing the specific cap for this transition" (200 with a typed
// body that surfaces the required cap name).
//
// Dispatcher resource handler that fronts `jobs_store_fs.JobsStore`.
// Same shape as `bearer_tokens_handler.zig` — handler owns the live
// JobsStore for the dispatcher's lifetime, every transport (in-process
// REPL, Unix socket, HTTP REPL, future mesh peers) goes through this
// one seam.  Closes D-O5.followup-1 + D-O5m.followup-4 by giving both
// helms (`apps/loom-svelte/src/views/JobList.svelte`'s `parseJobs` and
// `apps/oddjobz-mobile/lib/src/repl/jobs_repository.dart`'s `parseJobs`)
// a JSON-shaped response to consume.  Both helms already prefer the
// JSON branch when the response starts with `[` — no helm-side changes
// required.
//
// Commands (per acceptance §2):
//   find         — { state? }            →  [ {id, customer_name, state,
//                                              scheduled_at, created_at}, ... ]
//                                            cap = cap.oddjobz.read_jobs
//   create       — { id?, customer_name,
//                    state, scheduled_at?, created_at? }
//                                        →  { id, status: "created"
//                                                   | "already_exists" }
//                                            cap = cap.oddjobz.write_customer
//   find_by_id   — { id }                →  { id, customer_name, state,
//                                              scheduled_at, created_at }
//                                            cap = cap.oddjobz.read_jobs
//                                          (or { error: "not_found", id }
//                                           — handler-level NOT a dispatch
//                                           error so transports return 200
//                                           with a typed body, mirroring
//                                           bearer_tokens.validate's shape)
//
// D-O5.followup-3 (calendar + attention) — two further commands close the
// followup-3 triad on top of the existing jobs store.  No new caps, no
// new stores; both are derived queries over `findAll()` filtered/grouped
// in the handler.
//
//   find_calendar — { from?, to? }       →  [ {date: "YYYY-MM-DD",
//                                              jobs: [{id, customer_name,
//                                              state, scheduled_at}, ...]},
//                                            ... ]
//                                            cap = cap.oddjobz.read_jobs
//                                          Returns one CalendarDay per day
//                                          in [from, to] (both inclusive),
//                                          ordered ascending.  Days with no
//                                          jobs scheduled return `jobs: []`
//                                          so the helm renders a calendar
//                                          grid without missing-key checks.
//                                          When `from` is omitted, defaults
//                                          to the start of the current week
//                                          (Monday); when `to` is omitted,
//                                          defaults to start-of-week + 7
//                                          days.  Range capped at 31 days
//                                          defensively against runaway
//                                          operator queries.  A job is
//                                          included when its `scheduled_at`
//                                          starts with the day's ISO date
//                                          prefix; jobs with empty
//                                          scheduled_at are excluded.
//   find_attention — {}                  →  { pending_quote: [Job, ...],
//                                              pending_schedule: [Job, ...],
//                                              pending_invoice: [Job, ...],
//                                              total: <int> }
//                                            cap = cap.oddjobz.read_jobs
//                                          Aggregates jobs that need
//                                          operator action right now:
//                                            • pending_quote   ← state=lead
//                                            • pending_schedule← state=quoted
//                                            • pending_invoice ← state=completed
//                                          Each Job carries the same
//                                          {id, customer_name, state,
//                                          scheduled_at} shape `find`
//                                          returns.  `total` is the sum
//                                          across all three categories.
//                                          Jobs in non-action states
//                                          (scheduled, in_progress,
//                                          invoiced, paid, closed) are
//                                          deliberately excluded.
//
// Concurrency: a single mutex serialises all handler entry points
// against the live store; same shape as bearer_tokens_handler.zig.
// Two transports issuing simultaneously serialise here and produce
// well-defined ordering on disk.
//
// Audit: every dispatch produces phase=start + phase=end (or an error
// phase) automatically via the dispatcher.  We deliberately do NOT
// turn `audit_reads = false` on for `find` — per the brief, the helm
// reading the job list IS the audit-relevant event.  Audit volume is
// proportional to operator-driven helm refresh, not machine-driven
// poll, so the noise budget is fine.
//
// Idempotency on create: the underlying store returns
// `AppendOutcome.already_exists` when a duplicate id is written; we
// surface that as `status: "already_exists"` (200, NOT an error) so
// the helm-side outbox flush retry path doesn't get stuck.  Per
// acceptance §3.

const std = @import("std");
const dispatcher = @import("dispatcher");
const verb_schema = @import("verb_schema"); // C4 PR-R2 — generic-REPL verb self-description
const jobs_store_fs = @import("jobs_store_fs");
const attachments_store_fs = @import("attachments_store_fs");
const job_fsm = @import("job_fsm");
const helm_event_broker = @import("helm_event_broker");
const audit_log = @import("audit_log");
// W3.1 OddjobzEventProducer (Pravega) was cut 2026-05-13.  Pravega
// was overkill for the local event stream — NATS JetStream (W7.3)
// remains the canonical local event spine.
// W3.2 — in-process event bus: feeds the /api/v1/events WebSocket endpoint.
// W3.2 OddjobzEventBus direct publish cut 2026-05-13.  NATS is the
// canonical local event stream; the brain-internal nats_event_bridge
// subscribes to NATS and republishes to the bus, so jobs_handler stays
// out of the bus's producer side.
// W7.3 — NATS JetStream producer for the hosted-operator event spine.
const nats_event_producer_mod = @import("nats_event_producer");
const NatsEventProducer = nats_event_producer_mod.NatsEventProducer;

pub const RESOURCE_NAME = "jobs";

/// Capability declarations.
///
/// `cap.oddjobz.read_jobs` is the new cap (`0x00010107`) minted in
/// `cartridges/oddjobz/brain/src/capabilities.ts` alongside the existing six
/// oddjobz caps.  `cap.oddjobz.write_customer` is the existing cap
/// (`0x00010105`) — Job creation is part of the customer workflow per
/// D-O3 acceptance §O4.
pub const CAP_READ_JOBS: []const u8 = "cap.oddjobz.read_jobs";
pub const CAP_WRITE_CUSTOMER: []const u8 = "cap.oddjobz.write_customer";

pub const HandlerError = error{
    /// JSON args parse failed or required arg missing.
    invalid_args,
    /// Underlying JobsStore validator rejected the input.
    invalid_state,
    invalid_id,
    invalid_customer_name,
    invalid_scheduled_at,
    /// D-O5.followup-3 calendar — `from`/`to` not parseable as
    /// YYYY-MM-DD, `from > to`, or range > 31 days.
    invalid_date_range,
    /// D-O5 followup-1 (this PR) — `transition` arg validation: a
    /// missing or non-string `to_state`, missing `id`, missing
    /// `principal_kind`, or a principal_kind not in {"operator",
    /// "service"}.  These are wire-level shape failures (the JSON
    /// itself is malformed for the cmd); FSM-level rejections
    /// (wrong_cap / not_reachable / wrong_principal) flow back as a
    /// typed JSON body, NOT a typed handler error, so the helm can
    /// render a useful operator message.
    invalid_principal_kind,
    /// Underlying store I/O failed.
    store_error,
    /// Result-allocation failed.
    out_of_memory,
};

/// State carried alongside the resource registration.  The handler is
/// the sole owner of the JobsStore for the dispatcher's lifetime; the
/// daemon (or REPL bootstrap) constructs it once at boot and registers
/// the handler via `register`.
pub const Handler = struct {
    allocator: std.mem.Allocator,
    store: *jobs_store_fs.JobsStore,
    /// Serialises find / create / find_by_id against the underlying
    /// store.  The store itself is not thread-safe; this mutex is the
    /// seam between concurrent transport callers.
    mu: std.Thread.Mutex,
    /// D-O5.followup-4 — optional event broker.  When non-null, every
    /// successful `jobs.transition` publishes `job.transitioned` to
    /// the broker so live WSS subscribers (the helms) receive a
    /// notification frame.  Substrate scope: only this handler emits
    /// in this PR; other handlers' emitters land in followup PRs —
    /// adding them is mechanical (plumb the broker pointer through
    /// `init` + call `broker.publish` after the store write).
    broker: ?*helm_event_broker.Broker,
    /// D-O5.followup-4 — optional audit log shared with the
    /// dispatcher.  When non-null, every `broker.publish` call
    /// records a phase=publish line so the audit trail surfaces the
    /// event-emission alongside the dispatcher's existing start/end
    /// pair.  Audit pairs preserved per the substrate brief.
    audit: ?*audit_log.AuditLog,
    /// Hat (tenant / namespace) identifier included in NATS-emitted
    /// events.  Set at init time; empty string when the caller doesn't
    /// supply one.  Not owned.
    hat_id: []const u8,
    // W3.2 event_bus field cut 2026-05-13 — NATS is canonical (see
    // nats_event_bridge for the NATS→bus relay).

    /// W7.3 — optional NATS JetStream producer for the hosted-operator
    /// event spine.  When non-null, every successful `jobs.transition`
    /// also publishes to op.<op_pkh16>.<hat_id>.fsm_transition.
    /// Best-effort: a NATS write failure does NOT fail the transition.
    /// Borrowed; lifetime managed by the caller.
    nats_producer: ?*NatsEventProducer = null,

    /// PDF/photo recovery — optional read-only attachments store so
    /// `find jobs` can emit each job's attachments[] (id/mime/kind)
    /// for the in-app viewer. Late-bound via `setAttachmentsStore`
    /// (the store comes up after this handler in serve.zig; the
    /// pointer is only dereferenced at request time, never at init).
    /// Borrowed; lifetime managed by the caller.
    attachments: ?*const attachments_store_fs.AttachmentsStore = null,

    /// Wire the attachments store after construction (serve.zig sets
    /// this before the server accepts requests).
    pub fn setAttachmentsStore(
        self: *Handler,
        as: *const attachments_store_fs.AttachmentsStore,
    ) void {
        self.attachments = as;
    }

    pub fn init(allocator: std.mem.Allocator, store: *jobs_store_fs.JobsStore) Handler {
        return initWithBroker(allocator, store, null, null);
    }

    /// D-O5.followup-4 — broker-aware constructor.  cli.zig
    /// (`cmdRepl` + `cmdServe`) instantiates the broker once and
    /// passes it here so transitions emit live events.
    pub fn initWithBroker(
        allocator: std.mem.Allocator,
        store: *jobs_store_fs.JobsStore,
        broker: ?*helm_event_broker.Broker,
        audit: ?*audit_log.AuditLog,
    ) Handler {
        return .{
            .allocator = allocator,
            .store = store,
            .mu = .{},
            .broker = broker,
            .audit = audit,
            .hat_id = "",
        };
    }

    // W3.2 attachEventBus removed 2026-05-13 — see nats_event_bridge.

    /// W7.3 — attach the NATS JetStream producer so transitions also
    /// publish to the hosted-operator event spine.  Call after any of
    /// the init* constructors.  Idempotent — last call wins.
    pub fn attachNatsProducer(self: *Handler, producer: *NatsEventProducer) void {
        self.nats_producer = producer;
    }

    /// Build the dispatcher.ResourceHandler v-table entry for this
    /// instance.  Caller registers it via `dispatcher.Dispatcher.register`.
    pub fn resourceHandler(self: *Handler) dispatcher.ResourceHandler {
        return .{
            .name = RESOURCE_NAME,
            .state = self,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handle,
            .verbs_fn = verbsFn, // C4 PR-R2 — generic `jobs <verb>` REPL path
        };
    }
};

// C4 PR-R2 — verb self-description for the generic REPL path. Covers the pure
// read + create verbs (find / find_by_id / create). `transition` is NOT here:
// it needs operator principal-context injection, so it stays a cartridge sugar
// alias (R3). find_calendar/find_attention are derived views added in R2b.
const JOBS_VERBS = [_]verb_schema.VerbSpec{
    .{ .verb = "find", .summary = "list jobs (optionally filtered by state)", .args = &.{
        .{ .name = "state", .kind = .string, .help = "FSM state filter (e.g. lead, quoted)" },
    } },
    .{ .verb = "find_by_id", .summary = "fetch one job by id", .args = &.{
        .{ .name = "id", .kind = .string, .required = true, .positional = true },
    } },
    .{ .verb = "create", .summary = "create a job", .args = &.{
        .{ .name = "customer_name", .kind = .string, .required = true },
        .{ .name = "state", .kind = .string, .required = true, .help = "initial FSM state (e.g. lead)" },
        .{ .name = "id", .kind = .string },
        .{ .name = "scheduled_at", .kind = .string },
        .{ .name = "created_at", .kind = .string },
    } },
    // C4 PR-R2b — derived read views.
    .{ .verb = "find_calendar", .summary = "jobs in a date window (defaults to this week)", .args = &.{
        .{ .name = "from", .kind = .string, .help = "ISO date YYYY-MM-DD" },
        .{ .name = "to", .kind = .string, .help = "ISO date YYYY-MM-DD" },
    } },
    .{ .verb = "find_attention", .summary = "jobs needing attention", .args = &.{} },
};

fn verbsFn(_: ?*anyopaque) []const verb_schema.VerbSpec {
    return &JOBS_VERBS;
}

// ─────────────────────────────────────────────────────────────────────
// Capability declarations
// ─────────────────────────────────────────────────────────────────────

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "find")) return .{ .require = CAP_READ_JOBS };
    if (std.mem.eql(u8, cmd, "find_by_id")) return .{ .require = CAP_READ_JOBS };
    if (std.mem.eql(u8, cmd, "create")) return .{ .require = CAP_WRITE_CUSTOMER };
    // D-O5.followup-3 — calendar + attention are derived queries over
    // jobs_store_fs; both reuse `cap.oddjobz.read_jobs` (read-only views).
    if (std.mem.eql(u8, cmd, "find_calendar")) return .{ .require = CAP_READ_JOBS };
    if (std.mem.eql(u8, cmd, "find_attention")) return .{ .require = CAP_READ_JOBS };
    // D-O5 followup-1 (this PR) — `transition` is dispatcher-gated on
    // the read cap (you must be able to see the job to transition it).
    // The PER-TRANSITION cap (cap.oddjobz.quote / dispatch / invoice /
    // close) is checked INSIDE the handler against `ctx.capabilities`
    // and surfaced as a typed JSON body on mismatch.  This split is
    // deliberate: the dispatcher's CapDecl has no view of args, so it
    // can't route by `to_state`; doing the per-row check inside the
    // handler keeps both a "definitely-can-call-the-cmd" gate (here)
    // and an FSM-table-correct per-transition gate (in handleTransition).
    if (std.mem.eql(u8, cmd, "transition")) return .{ .require = CAP_READ_JOBS };
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
    if (std.mem.eql(u8, cmd, "find_calendar")) return handleFindCalendar(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "find_attention")) return handleFindAttention(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "transition")) return handleTransition(self, ctx, allocator, args_json);
    // Should not be reachable — the dispatcher guards on cap_for_cmd
    // returning unknown_command first.  Defensive return for
    // belt-and-braces.
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Per-command implementations
// ─────────────────────────────────────────────────────────────────────

fn handleFind(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const filter = parseFindArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer if (filter) |f| allocator.free(f);

    const items: []jobs_store_fs.Job = if (filter) |f|
        self.store.findByState(allocator, f) catch return HandlerError.store_error
    else
        self.store.findAll(allocator) catch return HandlerError.store_error;
    defer allocator.free(items);

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.append(allocator, '[');
    for (items, 0..) |row, i| {
        if (i != 0) try buf.append(allocator, ',');
        try writeJobJson(allocator, &buf, row, self.attachments);
    }
    try buf.append(allocator, ']');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleCreate(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    var args = parseCreateArgs(allocator, args_json) catch |err| switch (err) {
        // Per-field errors map to typed handler errors so the
        // dispatcher's audit-end carries the kind=handler_err
        // err=<name> tag operators rely on.
        error.invalid_state => return HandlerError.invalid_state,
        error.invalid_id => return HandlerError.invalid_id,
        error.invalid_customer_name => return HandlerError.invalid_customer_name,
        error.invalid_scheduled_at => return HandlerError.invalid_scheduled_at,
        error.OutOfMemory => return HandlerError.out_of_memory,
        else => return HandlerError.invalid_args,
    };
    defer args.deinit(allocator);

    const job = jobs_store_fs.Job{
        .id = args.id,
        .customer_name = args.customer_name,
        .state = args.state,
        .scheduled_at = args.scheduled_at,
        .created_at = args.created_at,
    };

    const outcome = self.store.append(job) catch |err| switch (err) {
        jobs_store_fs.StoreError.invalid_state => return HandlerError.invalid_state,
        jobs_store_fs.StoreError.invalid_id => return HandlerError.invalid_id,
        jobs_store_fs.StoreError.invalid_customer_name => return HandlerError.invalid_customer_name,
        jobs_store_fs.StoreError.invalid_scheduled_at => return HandlerError.invalid_scheduled_at,
        else => return HandlerError.store_error,
    };

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, &buf, args.id);
    // Include cellId when the store set one (canonical-cell path, W0.1).
    // The Flutter app reads this so the conversation-thread button can anchor
    // to the cell without a second look-up.
    if (self.store.findById(args.id)) |found| {
        if (found.cellId) |cid| {
            const hex = std.fmt.bytesToHex(cid, .lower);
            try buf.appendSlice(allocator, ",\"cellId\":");
            try writeJsonString(allocator, &buf, hex[0..]);
        }
    }
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
        // Index-liveness: the job may be a TAG_JOB cell minted into
        // the shared entity store (gmail reingest) AFTER this store's
        // boot-time replay — present on disk + visible to the agent
        // walkers, but not yet in the handler's in-memory index. Do a
        // one-shot incremental rescan and retry before declaring it
        // gone. Idempotent; only the rare cold-id path pays the scan.
        self.store.rescanCreatedCells();
        if (self.store.findById(id)) |j| break :miss j;
        // Handler-level not_found — return a typed body, NOT an error,
        // so transports return 200 with the same JSON envelope every
        // helm parser can handle.  Mirrors `bearer_tokens.validate`'s
        // `{"valid":false}` shape.
        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try buf.appendSlice(allocator, "{\"error\":\"not_found\",\"id\":");
        try writeJsonString(allocator, &buf, id);
        try buf.append(allocator, '}');
        return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
    };

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try writeJobJson(allocator, &buf, got, self.attachments);
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-3 calendar + attention — derived queries over the live
// jobs store.  Both reuse `cap.oddjobz.read_jobs`; neither writes.
//
// `find_calendar` walks the store and groups jobs whose `scheduled_at`
// ISO prefix falls inside [from, to] into per-day buckets.  Days with
// no jobs scheduled appear with an empty `jobs: []` array — the helms
// render a calendar grid and need every requested day present.
//
// `find_attention` aggregates jobs by FSM state into three operator-
// action buckets (lead → pending_quote, quoted → pending_schedule,
// completed → pending_invoice).  Other states (scheduled, in_progress,
// invoiced, paid, closed) are deliberately excluded.
// ─────────────────────────────────────────────────────────────────────

/// Maximum [from, to] span allowed for `find_calendar`, in days
/// (inclusive on both ends).  Defends against runaway operator queries
/// — 31 days covers the common one-month calendar surface.
pub const MAX_CALENDAR_RANGE_DAYS: i64 = 31;

/// Default span when both `from` and `to` are omitted.  Helm calendar
/// view defaults to the current week; we render Monday → Monday + 7.
pub const DEFAULT_CALENDAR_RANGE_DAYS: i64 = 7;

const CalendarRange = struct {
    /// Owned ISO-8601 date string (YYYY-MM-DD), 10 bytes.
    from: []u8,
    /// Owned ISO-8601 date string (YYYY-MM-DD), 10 bytes; inclusive.
    to: []u8,

    pub fn deinit(self: *CalendarRange, allocator: std.mem.Allocator) void {
        allocator.free(self.from);
        allocator.free(self.to);
    }
};

fn handleFindCalendar(
    self: *Handler,
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !dispatcher.Result {
    var range = parseCalendarArgs(allocator, args_json) catch |err| switch (err) {
        error.invalid_date_range => return HandlerError.invalid_date_range,
        error.OutOfMemory => return HandlerError.out_of_memory,
    };
    defer range.deinit(allocator);

    const items = self.store.findAll(allocator) catch return HandlerError.store_error;
    defer allocator.free(items);

    // Sort jobs in each day by scheduled_at ascending.  Doing this in
    // the inner loop is O(n²) but the data sets are small (helm is a
    // single-operator surface; tens-to-hundreds of jobs per week).
    // Build a fresh list-of-lists keyed on the per-day ISO prefix.
    var days_buf: std.ArrayList([]u8) = .{};
    defer {
        for (days_buf.items) |d| allocator.free(d);
        days_buf.deinit(allocator);
    }

    // Walk the date range from `from` to `to` inclusive.  daysBetween
    // returns the count; the loop appends one ISO date per day.
    const span = daysBetween(range.from, range.to) catch return HandlerError.invalid_date_range;
    if (span < 0 or span > MAX_CALENDAR_RANGE_DAYS) return HandlerError.invalid_date_range;
    var d: i64 = 0;
    while (d <= span) : (d += 1) {
        const date_str = try addDays(allocator, range.from, d);
        try days_buf.append(allocator, date_str);
    }

    // Render the response.
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.append(allocator, '[');
    for (days_buf.items, 0..) |date_str, i| {
        if (i != 0) try buf.append(allocator, ',');
        try buf.appendSlice(allocator, "{\"date\":");
        try writeJsonString(allocator, &buf, date_str);
        try buf.appendSlice(allocator, ",\"jobs\":[");

        // Collect jobs whose scheduled_at starts with this day's date,
        // sorted by scheduled_at ascending.
        var day_jobs: std.ArrayList(jobs_store_fs.Job) = .{};
        defer day_jobs.deinit(allocator);
        for (items) |row| {
            if (row.scheduled_at.len < 10) continue;
            if (!std.mem.eql(u8, row.scheduled_at[0..10], date_str)) continue;
            try day_jobs.append(allocator, row);
        }
        std.mem.sort(jobs_store_fs.Job, day_jobs.items, {}, compareJobsByScheduledAt);

        for (day_jobs.items, 0..) |row, j| {
            if (j != 0) try buf.append(allocator, ',');
            try writeJobCalendarJson(allocator, &buf, row);
        }
        try buf.appendSlice(allocator, "]}");
    }
    try buf.append(allocator, ']');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

/// Return true when a `lead`-state job is an outbound record that should
/// not appear on the operator's action feed.
///
/// Two known outbound patterns come from the Gmail ingest:
///
///   1. "Todd Price is sending an invoice for …"  — operator emailed a
///      customer about completed work; the job is already done.
///   2. "Todd Price sends invoice for …"          — same, present tense.
///   3. "Todd responds to …"                      — a follow-up thread
///      email where Todd is the sender; the real job anchors elsewhere.
///   4. "Todd Price is sending a quote document …" — quote already sent.
///
/// The common marker: the `summary` / `description` field starts with the
/// operator's first name followed by a capital letter or space, meaning
/// the ingest wrote the story from the operator's POV rather than the
/// customer's.  We match on the prefix "Todd " (first name + space).
///
/// This is intentionally conservative — only filter when:
///   • description starts with "Todd " (operator acting, not customer), AND
///   • the job has NO work-order number (i.e. no external anchor that
///     would make it a real actionable item regardless of direction).
///
/// Jobs with a work-order number but an outbound-style description are
/// kept; they represent real WO jobs even if the summary was written from
/// Todd's POV during ingestion.
fn isOutboundRecord(row: jobs_store_fs.Job) bool {
    const desc = row.description orelse return false;
    if (row.workOrderNumber != null) return false; // WO anchored → keep
    // Pollution audit (2026-05-26): the Quote 72 bucket was filling
    // with operator-outbound work that doesn't belong:
    //
    //   • "Todd Price — Invoice submission for latch adjustment…"
    //     → these are outbound INVOICES; they belong in Bill, not Quote.
    //   • "Robert James Realty — Automated acknowledgment of enquiry…"
    //     → inbound robo-reply from an agency, not a real quote request.
    //   • "Robert James Realty — Automated out-of-hours acknowledgment…"
    //     → same shape; agency CRM bot.
    //
    // Proper fix is intent classification at intake time (tag the cell
    // with direction + kind so the attention feed can filter
    // structurally instead of by pattern match).  Until then we
    // pattern-match the substrings that Todd has surfaced as polluters.
    //
    // Match anywhere in the description (not just prefix) because the
    // customer name typically prefixes the summary ("Todd Price — …" /
    // "Robert James Realty — …") so the operator-pov phrase lands mid-
    // string.
    if (containsAny(desc, &.{
        // Operator-outbound invoices (→ Bill bucket, not Quote)
        "— Invoice submission",
        "— Invoice for",
        "Invoice submission for",
        "Invoice for completed",
        // Agency / property-manager auto-replies (not actionable)
        "Automated acknowledgment",
        "Automated out-of-hours",
        "automated acknowledgment",
        "automated out-of-hours",
        "auto-acknowledgement",
        "auto-acknowledgment",
    })) return true;
    // Legacy prefix check kept for the original outbound-style
    // summaries written from Todd's POV during early ingest.
    return std.mem.startsWith(u8, desc, "Todd ");
}

/// True if `haystack` contains any of `needles` as a substring.
/// Plain Zig std.mem.indexOf — kept local so the predicate stays
/// readable.
fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, haystack, needle) != null) return true;
    }
    return false;
}

/// Return true when a `lead`-state job is already work-order authorised
/// and should therefore appear in the *schedule* bucket rather than the
/// *quote* bucket.
///
/// A work order means the property manager has already committed: the
/// operator needs to book a visit, not write a quote.  The proxy is a
/// non-null `workOrderNumber`; the Gmail/Bricks ingest only sets this
/// for PDF work orders and Bricks+Agent structured WO emails.
fn isWorkOrderAuthorised(row: jobs_store_fs.Job) bool {
    return row.workOrderNumber != null;
}

fn handleFindAttention(
    self: *Handler,
    allocator: std.mem.Allocator,
    _: []const u8,
) !dispatcher.Result {
    // No args — empty body is fine.  We deliberately don't parse the
    // args_json: extra keys from helm probes shouldn't fail.
    const items = self.store.findAll(allocator) catch return HandlerError.store_error;
    defer allocator.free(items);

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);

    var total: usize = 0;

    // ── pending_quote ─────────────────────────────────────────────────
    // state=lead AND not a work-order-authorised job AND not an outbound
    // record (email written from the operator's POV — these are noise,
    // not actionable leads).
    try buf.appendSlice(allocator, "{\"pending_quote\":[");
    var first = true;
    for (items) |row| {
        if (!std.mem.eql(u8, row.state, "lead")) continue;
        if (isOutboundRecord(row)) continue;       // skip outbound emails
        if (isWorkOrderAuthorised(row)) continue;  // → pending_schedule instead
        if (!first) try buf.append(allocator, ',');
        try writeJobAttentionJson(allocator, &buf, row);
        first = false;
        total += 1;
    }

    // ── pending_schedule ──────────────────────────────────────────────
    // state=quoted OR state=lead with a work-order number (WO jobs are
    // already authorised; the operator's next action is scheduling, not
    // quoting).
    try buf.appendSlice(allocator, "],\"pending_schedule\":[");
    first = true;
    for (items) |row| {
        const is_quoted = std.mem.eql(u8, row.state, "quoted");
        const is_wo_lead = std.mem.eql(u8, row.state, "lead") and isWorkOrderAuthorised(row);
        if (!is_quoted and !is_wo_lead) continue;
        if (!first) try buf.append(allocator, ',');
        try writeJobAttentionJson(allocator, &buf, row);
        first = false;
        total += 1;
    }

    // ── pending_invoice ───────────────────────────────────────────────
    // state=completed — work done, invoice not yet issued.
    try buf.appendSlice(allocator, "],\"pending_invoice\":[");
    first = true;
    for (items) |row| {
        if (!std.mem.eql(u8, row.state, "completed")) continue;
        if (!first) try buf.append(allocator, ',');
        try writeJobAttentionJson(allocator, &buf, row);
        first = false;
        total += 1;
    }

    try buf.appendSlice(allocator, "],\"total\":");
    try buf.print(allocator, "{d}", .{total});
    try buf.append(allocator, '}');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// D-O5 followup-1 (this PR) — `jobs.transition`.  Drives an existing
// job through the §O4 Job FSM (canonical table at runtime/semantos-brain/src/
// job_fsm.zig).
//
// Args shape:
//   { id: <string>,            -- the job id; must already exist
//     to_state: <string>,      -- one of the thirteen canonical FSM
//                                 states (lead..closed incl. the
//                                 qualified/visit_* lead-nurture front
//                                 and the `authorized` no-quote branch);
//                                 validated against job_fsm, never a
//                                 hardcoded list here
//     presented_cap: <string>?,-- optional; some FSM rows are ungated
//     principal_kind: <string>,-- "operator" | "service"
//     scheduled_at: <string>?  -- optional; updates the job's scheduled_at
//                                 when supplied (the `--at` flag in the
//                                 `schedule job` REPL verb plumbs through)
//   }
//
// Success body (200): the new Job (full shape; same as `jobs.find_by_id`).
//
// Error body (200, NOT a dispatcher error): typed JSON of shape
//   { "error": "<wrong_cap | not_reachable | wrong_principal |
//                unknown_state | not_found>",
//     "from": "<current state, or empty when not_found>",
//     "to": "<requested to_state>",
//     "cap_required": "<cap-or-null>" }
//
// Idempotent already-in-state body (200):
//   { "status": "already_in_state", "job": <Job> }
// per the brief: re-issuing a transition that's already at to_state
// returns the current job rather than an error.
// ─────────────────────────────────────────────────────────────────────

const TransitionArgs = struct {
    id: []u8,
    to_state: []u8,
    presented_cap: ?[]u8,
    principal_kind: job_fsm.PrincipalKind,
    scheduled_at: ?[]u8,
    /// P3d — optional invoice total in cents.  Present only when the
    /// Flutter client supplies `total_cents <n>` after `invoice job <id>`.
    /// Zero/absent means "no total supplied" (not "zero-dollar invoice").
    total_cents: ?i64,

    pub fn deinit(self: *TransitionArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.to_state);
        if (self.presented_cap) |c| allocator.free(c);
        if (self.scheduled_at) |s| allocator.free(s);
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
    if (id_v.string.len == 0 or id_v.string.len > jobs_store_fs.MAX_ID_BYTES) return error.invalid_args;

    const to_v = obj.get("to_state") orelse return error.invalid_args;
    if (to_v != .string) return error.invalid_args;
    if (to_v.string.len == 0) return error.invalid_args;

    const principal_v = obj.get("principal_kind") orelse return error.invalid_principal_kind;
    if (principal_v != .string) return error.invalid_principal_kind;
    const principal_kind = job_fsm.PrincipalKind.fromString(principal_v.string) orelse return error.invalid_principal_kind;

    var presented_cap_owned: ?[]u8 = null;
    if (obj.get("presented_cap")) |v| {
        if (v == .string and v.string.len > 0) {
            presented_cap_owned = try allocator.dupe(u8, v.string);
        }
    }
    errdefer if (presented_cap_owned) |c| allocator.free(c);

    var scheduled_at_owned: ?[]u8 = null;
    if (obj.get("scheduled_at")) |v| {
        if (v == .string) {
            if (v.string.len > jobs_store_fs.MAX_SCHEDULED_AT_BYTES) return error.invalid_scheduled_at;
            scheduled_at_owned = try allocator.dupe(u8, v.string);
        }
    }
    errdefer if (scheduled_at_owned) |s| allocator.free(s);

    // P3d: optional total_cents — present when the Flutter client sends
    // `invoice job <id> total_cents <n>`.  Ignored if absent/zero/negative.
    var total_cents: ?i64 = null;
    if (obj.get("total_cents")) |v| {
        if (v == .integer and v.integer > 0) {
            total_cents = v.integer;
        }
    }

    const id_owned = try allocator.dupe(u8, id_v.string);
    errdefer allocator.free(id_owned);
    const to_owned = try allocator.dupe(u8, to_v.string);

    return .{
        .id = id_owned,
        .to_state = to_owned,
        .presented_cap = presented_cap_owned,
        .principal_kind = principal_kind,
        .scheduled_at = scheduled_at_owned,
        .total_cents = total_cents,
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
        error.invalid_scheduled_at => return HandlerError.invalid_scheduled_at,
        error.OutOfMemory => return HandlerError.out_of_memory,
        else => return HandlerError.invalid_args,
    };
    defer args.deinit(allocator);

    // Look up the current job — if absent, return a typed not_found
    // body (200, NOT an error) so the helm can render a coherent
    // "this job no longer exists" message instead of a transport-
    // level dispatch failure.
    const current = self.store.findById(args.id) orelse current: {
        // Index-liveness (see handleFindById): a chat intent can name
        // a job that was reingested into the shared entity store after
        // this handler booted. Incrementally rescan + retry so the
        // chat-driven transition lands on the freshly-minted cell
        // instead of spuriously returning not_found.
        self.store.rescanCreatedCells();
        if (self.store.findById(args.id)) |j| break :current j;
        return writeTransitionError(
            allocator,
            "not_found",
            "",
            args.to_state,
            null,
        );
    };

    // FSM-table validation.  This produces the typed kind on every
    // failure mode the brief enumerates: wrong_cap, unknown_state,
    // not_reachable, wrong_principal, already_in_state.
    //
    // Resolve the cap the FSM sees as "presented": either the explicit
    // `presented_cap` arg OR — if the dispatcher's CapabilitySet
    // already carries the row's required cap — the required cap value
    // itself.  This lets a bearer whose caps include cap.oddjobz.quote
    // call `jobs.transition` without explicitly re-presenting the cap
    // string in the args body, which is what both helms do (they don't
    // ship cap strings in transition bodies; they rely on the bearer
    // token's cap set).  Without this resolve, the FSM check would
    // always require an explicit args-side cap, defeating the
    // dispatcher-level cap-gating substrate.
    const fsm_cap_for_validation: ?[]const u8 = blk: {
        if (args.presented_cap) |c| break :blk c;
        if (job_fsm.findTransition(current.state, args.to_state)) |row| {
            if (row.cap_required) |required| {
                if (ctx.capabilities.contains(required) or isRootAuth(ctx.auth)) {
                    break :blk required;
                }
            }
        }
        break :blk null;
    };
    const validation = job_fsm.validateTransition(
        current.state,
        args.to_state,
        fsm_cap_for_validation,
        args.principal_kind,
    );

    switch (validation) {
        .err => |e| {
            switch (e.kind) {
                .already_in_state => {
                    // Idempotency contract — return the current job
                    // wrapped in a typed-success body so the helm
                    // doesn't need to distinguish "we were already
                    // there" from "we transitioned this round".
                    return writeAlreadyInStateBody(allocator, current, self.attachments);
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
            // Apply.  updateState records the new state + (optionally)
            // a new scheduled_at; the inner appendUpdated emits an
            // audit-visible `updated` log line and the dispatcher's
            // own audit pair surrounds the whole call.
            const from_state = current.state;
            const updated = self.store.updateState(
                args.id,
                row.to,
                if (args.scheduled_at) |s| s else null,
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

            // D-O5.followup-4 — emit `job.transitioned` to the broker
            // so live WSS subscribers (helms) update in real time.
            // Substrate scope: only the jobs handler emits in this PR;
            // other handlers land in followup PRs.  Best-effort: a
            // payload-encode failure or a callback that crashes does
            // NOT fail the transition (the event is decorative; the
            // store write already landed).
            emitJobTransitioned(self, args.id, from_state, updated.state, updated.scheduled_at) catch {};

            // Derive cell_id once; shared by all three emit paths below.
            const ts_ms: u64 = @intCast(@max(0, std.time.milliTimestamp()));
            var cell_id_buf: [64]u8 = undefined;
            const cell_id: []const u8 = if (updated.cellId) |cid| blk: {
                const hex = std.fmt.bytesToHex(cid, .lower);
                @memcpy(cell_id_buf[0..hex.len], &hex);
                break :blk cell_id_buf[0..hex.len];
            } else updated.id;

            // W7.3 — emit to NATS JetStream (hosted-operator event spine).
            // Best-effort: a NATS write failure does NOT fail the transition.
            // Subject: op.<op_pkh16>.<hat_id>.fsm_transition
            if (self.nats_producer) |np| {
                np.emitJobTransition(
                    self.hat_id,
                    updated.id,
                    cell_id,
                    from_state,
                    updated.state,
                    ts_ms,
                ) catch {};
            }

            // W3.1 OddjobzEventProducer (Pravega) cut 2026-05-13.
            // W3.2 direct bus publish cut 2026-05-13 — NATS is canonical;
            // the brain-internal nats_event_bridge subscribes to NATS and
            // republishes to the bus for /api/v1/events WSS subscribers.

            var buf: std.ArrayList(u8) = .{};
            errdefer buf.deinit(allocator);
            try writeJobJson(allocator, &buf, updated, self.attachments);

            // P3d: when the client supplied total_cents for an invoice
            // transition, append it to the response so the Flutter side
            // can confirm receipt.  We strip the closing `}`, emit the
            // field, then re-close — safe because writeJobJson always
            // ends with `}`.
            if (args.total_cents) |tc| {
                if (std.mem.eql(u8, args.to_state, "invoiced") and tc > 0) {
                    if (buf.items.len > 0 and buf.items[buf.items.len - 1] == '}') {
                        buf.items.len -= 1; // pop closing brace
                        try buf.print(allocator, ",\"invoice_total_cents\":{d}}}", .{tc});
                    }
                }
            }

            return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
        },
    }
}

/// Match the dispatcher's root-scope auth detection.  Root-scope
/// contexts (in_process_root, local_uid) bypass dispatcher cap-gating
/// per BRAIN-DISPATCHER-UNIFICATION.md §4 — the same bypass needs to
/// extend to per-FSM-row caps for the REPL path (the in-process REPL
/// is `in_process_root` and ships an empty CapabilitySet but should
/// still be allowed to drive transitions).  Mirrors
/// `dispatcher.zig::isRootScope`.
fn isRootAuth(auth: dispatcher.AuthContext) bool {
    return switch (auth) {
        .in_process_root, .local_uid => true,
        .bearer, .cert, .anonymous => false,
    };
}

/// D-O5.followup-4 — publish a `job.transitioned` event to the
/// process-scoped broker (when wired) so live WSS subscribers receive
/// a JSON-RPC notification frame.  Best-effort: failure to allocate
/// the payload buffer is silently swallowed (the store write already
/// landed; the live event is decorative).
///
/// Audit pair preserved — when the handler also carries an audit log
/// pointer, we record one phase=publish line per emit alongside the
/// dispatcher's existing start/end pair.  This matches the broker
/// audit shape from runtime/semantos-brain/src/broker.zig (the wasmtime host-
/// import broker) so a `tail -f audit.log` observer sees the same
/// rhythm for every event source.
fn emitJobTransitioned(
    self: *Handler,
    id: []const u8,
    from_state: []const u8,
    to_state: []const u8,
    scheduled_at: []const u8,
) !void {
    const broker = self.broker orelse return;
    const allocator = self.allocator;

    // Render transitioned_at as a wall-clock ISO timestamp.  The helm
    // surfaces this on the live tile so operators see "transitioned
    // 14:32:01Z" without polling.
    const transitioned_at = try renderIsoTimestamp(allocator, std.time.timestamp());
    defer allocator.free(transitioned_at);

    var payload: std.ArrayList(u8) = .{};
    defer payload.deinit(allocator);
    try payload.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, &payload, id);
    try payload.appendSlice(allocator, ",\"from\":");
    try writeJsonString(allocator, &payload, from_state);
    try payload.appendSlice(allocator, ",\"to\":");
    try writeJsonString(allocator, &payload, to_state);
    try payload.appendSlice(allocator, ",\"scheduled_at\":");
    try writeJsonString(allocator, &payload, scheduled_at);
    try payload.appendSlice(allocator, ",\"transitioned_at\":");
    try writeJsonString(allocator, &payload, transitioned_at);
    try payload.append(allocator, '}');

    // D-O5m.followup-9 Phase A — flag transitions INTO `lead` as
    // operator-attention so the brain-side push dispatcher (Phase B)
    // can route an APNs/FCM alert to the operator's mobile device.
    // Other transitions (lead → quoted, scheduled → in_progress, etc.)
    // are background bookkeeping and stay default-false.
    const requires_attention = std.mem.eql(u8, to_state, "lead");

    broker.publish(.{
        .type = "job.transitioned",
        .payload_json = payload.items,
        .requires_operator_attention = requires_attention,
    });

    if (self.audit) |a| {
        // phase=publish + the event type, per the substrate brief.
        a.record(allocator, .{
            .module = "helm.broker",
            .op = "publish",
            .result = .ok,
            .detail = "job.transitioned",
        }) catch {};
    }
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
    current: jobs_store_fs.Job,
    attachments: ?*const attachments_store_fs.AttachmentsStore,
) !dispatcher.Result {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"status\":\"already_in_state\",\"job\":");
    try writeJobJson(allocator, &buf, current, attachments);
    try buf.append(allocator, '}');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

/// Parse `find_calendar` args.  Both `from` and `to` are optional ISO
/// dates (YYYY-MM-DD).  When both omitted, defaults to start-of-week
/// (Monday, anchored on the wall clock) → start-of-week + 7 days.
/// When only one is provided, the other inherits from it (from-only:
/// to = from + 7 days; to-only: from = to - 7 days).  Range must be
/// ≤ MAX_CALENDAR_RANGE_DAYS.
fn parseCalendarArgs(
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !CalendarRange {
    var from_in: ?[]const u8 = null;
    var to_in: ?[]const u8 = null;

    if (args_json.len > 0) {
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch {
            // Permissive: treat unparseable args like an empty object —
            // every field defaults.  Mirrors handleFind's posture.
            return defaultCalendarRange(allocator);
        };
        defer parsed.deinit();
        if (parsed.value == .object) {
            const obj = parsed.value.object;
            if (obj.get("from")) |v| {
                if (v == .string and v.string.len > 0) from_in = v.string;
            }
            if (obj.get("to")) |v| {
                if (v == .string and v.string.len > 0) to_in = v.string;
            }
        }
    }

    if (from_in == null and to_in == null) {
        return defaultCalendarRange(allocator);
    }

    // Validate format on whichever side(s) were supplied.
    if (from_in) |s| if (!isIsoDate(s)) return error.invalid_date_range;
    if (to_in) |s| if (!isIsoDate(s)) return error.invalid_date_range;

    var from_owned: []u8 = undefined;
    var to_owned: []u8 = undefined;

    if (from_in != null and to_in != null) {
        from_owned = try allocator.dupe(u8, from_in.?);
        errdefer allocator.free(from_owned);
        to_owned = try allocator.dupe(u8, to_in.?);
    } else if (from_in != null) {
        from_owned = try allocator.dupe(u8, from_in.?);
        errdefer allocator.free(from_owned);
        to_owned = try addDays(allocator, from_owned, DEFAULT_CALENDAR_RANGE_DAYS);
    } else {
        // to-only — derive from = to - 7 days.
        to_owned = try allocator.dupe(u8, to_in.?);
        errdefer allocator.free(to_owned);
        from_owned = try addDays(allocator, to_owned, -DEFAULT_CALENDAR_RANGE_DAYS);
    }

    // Span check.
    const span = daysBetween(from_owned, to_owned) catch {
        allocator.free(from_owned);
        allocator.free(to_owned);
        return error.invalid_date_range;
    };
    if (span < 0 or span > MAX_CALENDAR_RANGE_DAYS) {
        allocator.free(from_owned);
        allocator.free(to_owned);
        return error.invalid_date_range;
    }

    return .{ .from = from_owned, .to = to_owned };
}

/// Default calendar range when no `from`/`to` supplied: Monday of the
/// current week (UTC) → Monday + 7 days.
fn defaultCalendarRange(allocator: std.mem.Allocator) !CalendarRange {
    const today = todayIsoUtc(allocator) catch return error.invalid_date_range;
    defer allocator.free(today);
    const monday = try mondayOfWeek(allocator, today);
    errdefer allocator.free(monday);
    const sunday_plus = try addDays(allocator, monday, DEFAULT_CALENDAR_RANGE_DAYS);
    return .{ .from = monday, .to = sunday_plus };
}

/// Render the wall clock as an ISO-8601 date string (YYYY-MM-DD).
fn todayIsoUtc(allocator: std.mem.Allocator) ![]u8 {
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(std.time.timestamp()) };
    const epoch_day = epoch_secs.getEpochDay();
    const ymd = epoch_day.calculateYearDay();
    const month_day = ymd.calculateMonthDay();
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}",
        .{ ymd.year, month_day.month.numeric(), month_day.day_index + 1 },
    );
}

/// Compute Monday of the week containing `iso_date`.  std.time.epoch
/// reports day-of-week as 0=Sunday..6=Saturday; we shift to 0=Monday..6=Sunday.
fn mondayOfWeek(allocator: std.mem.Allocator, iso_date: []const u8) ![]u8 {
    const day_index = isoToEpochDay(iso_date) catch return error.invalid_date_range;
    const dow_sunday = @rem(day_index + 4, 7); // 1970-01-01 was a Thursday (4).
    // Convert to Monday-zero: Sunday(0)→6, Mon(1)→0, ..., Sat(6)→5.
    const dow_monday: i64 = if (dow_sunday == 0) 6 else dow_sunday - 1;
    return addDaysFromDayIndex(allocator, day_index - dow_monday);
}

/// Returns true if `s` matches the YYYY-MM-DD shape: 10 chars, digits
/// at positions 0-3, 5-6, 8-9, and dashes at positions 4 and 7.  We
/// also defensively reject impossible months/days; ymd math below
/// would otherwise wrap silently.
fn isIsoDate(s: []const u8) bool {
    if (s.len != 10) return false;
    if (s[4] != '-' or s[7] != '-') return false;
    for ([_]usize{ 0, 1, 2, 3, 5, 6, 8, 9 }) |i| {
        if (s[i] < '0' or s[i] > '9') return false;
    }
    const month = (@as(u8, s[5] - '0') * 10) + (s[6] - '0');
    const day = (@as(u8, s[8] - '0') * 10) + (s[9] - '0');
    if (month < 1 or month > 12) return false;
    if (day < 1 or day > 31) return false;
    return true;
}

/// Convert an ISO-8601 date string (YYYY-MM-DD) into a count of days
/// since the unix epoch (1970-01-01).
fn isoToEpochDay(iso: []const u8) !i64 {
    if (!isIsoDate(iso)) return error.invalid_date_range;
    const year_u: u32 = std.fmt.parseInt(u32, iso[0..4], 10) catch return error.invalid_date_range;
    const month_u: u32 = std.fmt.parseInt(u32, iso[5..7], 10) catch return error.invalid_date_range;
    const day_u: u32 = std.fmt.parseInt(u32, iso[8..10], 10) catch return error.invalid_date_range;
    if (month_u < 1 or month_u > 12) return error.invalid_date_range;
    if (day_u < 1 or day_u > 31) return error.invalid_date_range;

    // Days since 1970-01-01, computed via the standard civil-from-days
    // algorithm (Howard Hinnant).  Handles dates well outside the
    // helm's needs — kept simple for clarity.
    var y: i64 = year_u;
    var m: i64 = month_u;
    if (m <= 2) {
        y -= 1;
        m += 12;
    }
    const era = @divFloor(y, 400);
    const yoe = y - era * 400; // [0, 399]
    const doy = @divFloor(153 * (m - 3) + 2, 5) + @as(i64, day_u) - 1; // [0, 365]
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy; // [0, 146096]
    return era * 146097 + doe - 719468;
}

/// Render an i64 epoch-day count back to a YYYY-MM-DD ISO date string.
fn addDaysFromDayIndex(allocator: std.mem.Allocator, day_index: i64) ![]u8 {
    // Inverse of isoToEpochDay using the same Hinnant algorithm.
    const z = day_index + 719468;
    const era = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe: i64 = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y = yoe + era * 400;
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const d = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m = if (mp < 10) mp + 3 else mp - 9;
    const year = if (m <= 2) y + 1 else y;
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}",
        .{ @as(u32, @intCast(year)), @as(u8, @intCast(m)), @as(u8, @intCast(d)) },
    );
}

/// Return a fresh ISO date `delta` days past `base`.  Caller owns the
/// returned slice.
fn addDays(allocator: std.mem.Allocator, base: []const u8, delta: i64) ![]u8 {
    const day_index = isoToEpochDay(base) catch return error.invalid_date_range;
    return addDaysFromDayIndex(allocator, day_index + delta);
}

/// Inclusive day count from `from` to `to`.  Negative when from > to.
fn daysBetween(from: []const u8, to: []const u8) !i64 {
    const a = isoToEpochDay(from) catch return error.invalid_date_range;
    const b = isoToEpochDay(to) catch return error.invalid_date_range;
    return b - a;
}

/// Compare jobs by scheduled_at lexicographically.  Empty
/// `scheduled_at` strings sort first, but they're already filtered out
/// upstream — the calendar handler skips jobs whose prefix doesn't
/// match the day.
fn compareJobsByScheduledAt(_: void, a: jobs_store_fs.Job, b: jobs_store_fs.Job) bool {
    return std.mem.order(u8, a.scheduled_at, b.scheduled_at) == .lt;
}

/// Render a Job as a CalendarDay-list-element JSON object.  The
/// calendar payload mirrors `find`'s shape but omits `created_at`
/// (the helm calendar tile only renders id / customer / state /
/// scheduled_at).
fn writeJobCalendarJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), job: jobs_store_fs.Job) !void {
    try out.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, out, job.id);
    try out.appendSlice(allocator, ",\"customer_name\":");
    try writeJsonString(allocator, out, job.customer_name);
    try out.appendSlice(allocator, ",\"state\":");
    try writeJsonString(allocator, out, job.state);
    try out.appendSlice(allocator, ",\"scheduled_at\":");
    try writeJsonString(allocator, out, job.scheduled_at);
    if (job.siteRef) |sr| {
        const hex = std.fmt.bytesToHex(sr, .lower);
        try out.appendSlice(allocator, ",\"siteRef\":");
        try writeJsonString(allocator, out, hex[0..]);
    }
    try out.append(allocator, '}');
}

/// Render a Job as an AttentionFeed-list-element JSON object.
///
/// Emits the full writeJobJson payload (minus attachments) so the
/// helm DO tab has the same richness as the find-jobs list — address,
/// description, customerRefs, etc.  Without these fields the DO row
/// shows only a hash + customer name and the operator can't tell what
/// the work is without tapping the info icon.
fn writeJobAttentionJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), job: jobs_store_fs.Job) !void {
    try writeJobJson(allocator, out, job, null);
}

// ─────────────────────────────────────────────────────────────────────
// Args parsing — small JSON walks; never trust the caller's payload.
// Each parser allocates owned copies of every string field so the
// per-command implementations can hold them across the underlying
// store call without lifetime entanglement with the parsed JSON DOM.
// ─────────────────────────────────────────────────────────────────────

const CreateArgs = struct {
    id: []u8,
    customer_name: []u8,
    state: []u8,
    scheduled_at: []u8,
    created_at: []u8,

    pub fn deinit(self: *CreateArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.customer_name);
        allocator.free(self.state);
        allocator.free(self.scheduled_at);
        allocator.free(self.created_at);
    }
};

const ParseError = error{
    invalid_args,
    invalid_state,
    invalid_id,
    invalid_customer_name,
    invalid_scheduled_at,
    out_of_memory,
    /// std.mem.Allocator's documented OOM signal — keep alongside our
    /// snake-cased `out_of_memory` so allocator-returning calls inside
    /// `parseCreateArgs` can `try` directly without a switch translation.
    OutOfMemory,
};

/// `find` accepts an optional `{state: "..."}` filter.  Returns null
/// when no filter is present (caller treats that as "all jobs"); the
/// allocator owns the returned slice when non-null.
fn parseFindArgs(allocator: std.mem.Allocator, args_json: []const u8) !?[]u8 {
    // Empty body is permitted (REPL command with no args).
    if (args_json.len == 0) return null;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const obj = parsed.value.object;
    const v = obj.get("state") orelse return null;
    if (v != .string) return null;
    if (v.string.len == 0) return null;
    return try allocator.dupe(u8, v.string);
}

fn parseCreateArgs(allocator: std.mem.Allocator, args_json: []const u8) ParseError!CreateArgs {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return error.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    // customer_name (required, non-empty, ≤ 200).
    const cn_v = obj.get("customer_name") orelse return error.invalid_customer_name;
    if (cn_v != .string) return error.invalid_customer_name;
    if (cn_v.string.len == 0 or cn_v.string.len > jobs_store_fs.MAX_CUSTOMER_NAME_BYTES) return error.invalid_customer_name;

    // state (required, ∈ JOB_FSM_STATES).
    const st_v = obj.get("state") orelse return error.invalid_state;
    if (st_v != .string) return error.invalid_state;
    if (!jobs_store_fs.isValidState(st_v.string)) return error.invalid_state;

    // id (optional — server-stamped when empty).
    const id_str: []const u8 = blk: {
        if (obj.get("id")) |v| {
            if (v != .string) return error.invalid_id;
            if (v.string.len > jobs_store_fs.MAX_ID_BYTES) return error.invalid_id;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };

    // scheduled_at (optional; ISO-8601 or empty).  We don't parse the
    // timestamp on the Semantos Brain side — the helms emit ISO strings; the cell-
    // engine canon enforces format on the cell-DAG side.  Just check
    // the length envelope.
    const sa_v: []const u8 = blk: {
        if (obj.get("scheduled_at")) |v| {
            if (v != .string) return error.invalid_scheduled_at;
            if (v.string.len > jobs_store_fs.MAX_SCHEDULED_AT_BYTES) return error.invalid_scheduled_at;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // created_at (optional; server-stamps as ISO timestamp when empty).
    const ca_v: []const u8 = blk: {
        if (obj.get("created_at")) |v| {
            if (v != .string) return error.invalid_args;
            if (v.string.len > jobs_store_fs.MAX_SCHEDULED_AT_BYTES) return error.invalid_args;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };

    // Allocate the owned copies.
    var id_owned: []u8 = undefined;
    if (id_str.len == 0) {
        // Server-mint a UUIDv4-shaped id (32 hex chars) with crypto-
        // random bytes — same pattern bearer_tokens.zig uses for its
        // record ids.
        var id_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&id_bytes);
        const id_alloc = try allocator.alloc(u8, 32);
        hexEncode(&id_bytes, id_alloc);
        id_owned = id_alloc;
    } else {
        id_owned = try allocator.dupe(u8, id_str);
    }
    errdefer allocator.free(id_owned);

    const cn_owned = try allocator.dupe(u8, cn_v.string);
    errdefer allocator.free(cn_owned);
    const st_owned = try allocator.dupe(u8, st_v.string);
    errdefer allocator.free(st_owned);
    const sa_owned = try allocator.dupe(u8, sa_v);
    errdefer allocator.free(sa_owned);

    // Server-stamp created_at when not supplied.  We render the wall
    // clock as an ISO-8601 string with second precision so audit-log
    // grep aligns with helm-rendered timestamps.
    var ca_owned: []u8 = undefined;
    if (ca_v.len == 0) {
        ca_owned = try renderIsoTimestamp(allocator, std.time.timestamp());
    } else {
        ca_owned = try allocator.dupe(u8, ca_v);
    }
    errdefer allocator.free(ca_owned);

    return .{
        .id = id_owned,
        .customer_name = cn_owned,
        .state = st_owned,
        .scheduled_at = sa_owned,
        .created_at = ca_owned,
    };
}

fn parseFindByIdArgs(allocator: std.mem.Allocator, args_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const v = obj.get("id") orelse return error.invalid_args;
    if (v != .string) return error.invalid_args;
    if (v.string.len == 0 or v.string.len > jobs_store_fs.MAX_ID_BYTES) return error.invalid_args;
    return try allocator.dupe(u8, v.string);
}

// ─────────────────────────────────────────────────────────────────────
// JSON rendering helpers
// ─────────────────────────────────────────────────────────────────────

/// Map a MIME type to the coarse kind the app switches on.
fn attachmentKind(mime: []const u8) []const u8 {
    if (std.mem.startsWith(u8, mime, "image/")) return "image";
    if (std.mem.eql(u8, mime, "application/pdf")) return "pdf";
    return "other";
}

fn writeJobJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    job: jobs_store_fs.Job,
    attachments: ?*const attachments_store_fs.AttachmentsStore,
) !void {
    try out.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, out, job.id);
    try out.appendSlice(allocator, ",\"customer_name\":");
    try writeJsonString(allocator, out, job.customer_name);
    try out.appendSlice(allocator, ",\"state\":");
    try writeJsonString(allocator, out, job.state);
    try out.appendSlice(allocator, ",\"scheduled_at\":");
    try writeJsonString(allocator, out, job.scheduled_at);
    try out.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, out, job.created_at);
    // v2-only fields: cellId, siteRef, customerRefs
    if (job.cellId) |cid| {
        const hex = std.fmt.bytesToHex(cid, .lower);
        try out.appendSlice(allocator, ",\"cellId\":");
        try writeJsonString(allocator, out, hex[0..]);
    }
    if (job.siteRef) |sr| {
        const hex = std.fmt.bytesToHex(sr, .lower);
        try out.appendSlice(allocator, ",\"siteRef\":");
        try writeJsonString(allocator, out, hex[0..]);
    }
    if (job.dueDate) |dd| {
        try out.appendSlice(allocator, ",\"dueDate\":");
        try writeJsonString(allocator, out, dd);
    }
    // RM-125 — WO metadata so the operator sees scope without the PDF.
    if (job.workOrderNumber) |wo| {
        try out.appendSlice(allocator, ",\"workOrderNumber\":");
        try writeJsonString(allocator, out, wo);
    }
    if (job.issuanceDate) |iss| {
        try out.appendSlice(allocator, ",\"issuanceDate\":");
        try writeJsonString(allocator, out, iss);
    }
    if (job.services) |sv| {
        try out.appendSlice(allocator, ",\"services\":");
        try writeJsonString(allocator, out, sv);
    }
    if (job.photoCount) |pc| {
        var nb: [16]u8 = undefined;
        const ns = std.fmt.bufPrint(&nb, "{d}", .{pc}) catch "0";
        try out.appendSlice(allocator, ",\"photoCount\":");
        try out.appendSlice(allocator, ns);
    }
    if (job.hasPhotos) |hp| {
        try out.appendSlice(allocator, ",\"hasPhotos\":");
        try out.appendSlice(allocator, if (hp) "true" else "false");
    }
    if (job.customerRefs) |crefs| {
        try out.appendSlice(allocator, ",\"customerRefs\":[");
        for (crefs, 0..) |cref, i| {
            if (i != 0) try out.append(allocator, ',');
            const cid_hex = std.fmt.bytesToHex(cref.cellId, .lower);
            try out.appendSlice(allocator, "{\"cellId\":");
            try writeJsonString(allocator, out, cid_hex[0..]);
            try out.appendSlice(allocator, ",\"role\":");
            try writeJsonString(allocator, out, cref.role);
            try out.appendSlice(allocator, ",\"primary\":");
            try out.appendSlice(allocator, if (cref.primary) "true" else "false");
            // RM-121 — resolved contact identity (who to call).
            try out.appendSlice(allocator, ",\"name\":");
            try writeJsonString(allocator, out, cref.name);
            try out.appendSlice(allocator, ",\"phone\":");
            try writeJsonString(allocator, out, cref.phone);
            try out.append(allocator, '}');
        }
        try out.append(allocator, ']');
    }
    // RM-121 — resolved site address + work description so Home can
    // group by site → contact → description without a second fetch.
    if (job.propertyAddress) |pa| {
        try out.appendSlice(allocator, ",\"propertyAddress\":");
        try writeJsonString(allocator, out, pa);
    }
    if (job.description) |d| {
        try out.appendSlice(allocator, ",\"description\":");
        try writeJsonString(allocator, out, d);
    }
    // PDF/photo recovery — resolve this job's attachments (the
    // attachment cells carry `jobRef` = this job's cell-id hash; the
    // bytes are content-addressed at `id` = sha256 = the `<sha>.bin`
    // the brain's /api/v1/attachments/<id>/blob endpoint serves). The
    // app lists these and fetches each blob to render the job-sheet
    // PDF + photos. Best-effort: any failure just omits the array.
    if (attachments) |as| resolve: {
        if (job.id.len != 64) break :resolve;
        var jc: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&jc, job.id) catch break :resolve;
        const rows = as.findForJob(allocator, jc) catch break :resolve;
        defer allocator.free(rows);
        if (rows.len == 0) break :resolve;
        try out.appendSlice(allocator, ",\"attachments\":[");
        for (rows, 0..) |att, i| {
            if (i != 0) try out.append(allocator, ',');
            try out.appendSlice(allocator, "{\"id\":");
            try writeJsonString(allocator, out, att.id);
            try out.appendSlice(allocator, ",\"mime\":");
            try writeJsonString(allocator, out, att.mime_type);
            try out.appendSlice(allocator, ",\"kind\":");
            try writeJsonString(allocator, out, attachmentKind(att.mime_type));
            try out.appendSlice(allocator, ",\"size\":");
            var nb: [24]u8 = undefined;
            const ns = std.fmt.bufPrint(&nb, "{d}", .{att.content_size}) catch "0";
            try out.appendSlice(allocator, ns);
            if (att.caption.len > 0) {
                try out.appendSlice(allocator, ",\"caption\":");
                try writeJsonString(allocator, out, att.caption);
            }
            try out.append(allocator, '}');
        }
        try out.append(allocator, ']');
    }
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
/// MM-DDTHH:MM:SSZ").  Used to server-stamp `created_at` when the
/// caller omits it.  std.time doesn't ship a calendar formatter, so we
/// roll a tiny one — the helm parser only inspects the leading 10
/// chars for date-grouping, so format precision is fine.
fn renderIsoTimestamp(allocator: std.mem.Allocator, unix_seconds: i64) ![]u8 {
    // Build a fresh epoch-day breakdown using std.time.epoch.
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(unix_seconds) };
    const epoch_day = epoch_secs.getEpochDay();
    const day_secs = epoch_secs.getDaySeconds();
    const ymd = epoch_day.calculateYearDay();
    const month_day = ymd.calculateMonthDay();
    const year: u32 = ymd.year;
    // month is 1-based; calculateMonthDay returns a 0-based field.
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
