---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/intent_action_router.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.545221+00:00
---

# cartridges/oddjobz/brain/zig/src/intent_action_router.zig

```zig
// Tier 3 — brain-side bridge from `intent_cell.created` broker events
// into the `oddjobz.jobs` FSM via `jobs.transition`.
//
// Reference: docs/spec/oddjobz-intent-cell-v1.md (Phase 4 — this slice).
//
// A typed-NL command from the operator's phone today flows:
//
//   1. Llama 3B extracts intent on phone → {action, summary, taxonomy}.
//   2. SIR → OIR → opcode bytes → kernel verifies on phone.
//   3. Cell envelope flushed via REPL `submit-intent-cell`.
//   4. brain intent_cells handler validates + persists + publishes
//      `intent_cell.created` to the helm event broker.
//
// What this module adds: a broker subscriber that, on
// `intent_cell.created`, enqueues a typed-NL action.  A periodic
// `tick()` (driven by the reactor / the EventLoop hook) drains the
// queue, mapping each action's verb to a canonical Job FSM state,
// finding a matching job by heuristic substring search over
// `customer_name`, and calling into the dispatcher's `jobs.transition`
// verb with the operator-typed-state as the target.
//
// ─── Why queue + tick (not direct dispatch) ────────────────────────
//
// The broker's `publish` call holds an internal mutex while it fans
// out to subscribers.  `jobs.transition` itself emits a
// `job.transitioned` broker event after a successful state change —
// re-entering `broker.publish` from inside a subscriber callback
// would re-acquire the same non-reentrant mutex and deadlock.  The
// fix: the callback only enqueues; the dispatch happens later from a
// known-safe call site (the reactor's poll tick) where no broker
// mutex is held.
//
// The cost: a tiny lag between phone-side cell submission and the
// brain-side FSM transition (bounded by the reactor poll interval —
// 100 ms today).  For the meetup demo this is imperceptible; the
// brain-helm-viewer's left-panel state pill flips effectively
// instantly.
//
// ─── Safety guardrails ──────────────────────────────────────────────
//
//   • OFF by default — gated behind a CLI flag (`--enable-intent-
//     action-router`) or env var (`BRAIN_INTENT_ROUTER=1`).  cli.zig
//     constructs and subscribes only when the gate is on; the in-
//     process `enabled` field on `Router` lets tests exercise the
//     gate without going through CLI parsing.
//
//   • Eligibility is delegated to the canonical thirteen-state Job
//     FSM: a (current_state → mapped target) pair fires only if
//     `job_fsm.findTransition` admits it (see isFsmTransitionAllowed).
//     This covers the full lifecycle incl. the qualified/visit_*
//     lead-nurture front and the `authorized` no-quote branch; any
//     edge the FSM rejects is audit-skipped, so a misfire never
//     skips states or regresses live operator data. (Pre-remodel
//     this was a hardcoded `lead`/`open`-only gate — that errant
//     signal is gone; `open` was never a canonical state.)
//
//   • Heuristic substring match must yield exactly one job — zero or
//     multiple matches skip with a clear audit log entry.
//
//   • Unknown actions log + skip.  Quotes / schedule / invoice /
//     accept / close are the supported set; anything else is audit-
//     only.
//
//   • Whole router body wrapped in try/catch; a buggy intent never
//     crashes the broker mutex thread (callback enqueue) or the
//     reactor (tick drain).
//
//   • Stop-list noise filter: tokens of length < 4 are dropped to
//     avoid spurious matches on "for", "the", "and".
//
//   • Bounded pending queue (MAX_PENDING).  When full, the oldest
//     entry is evicted with an audit line — a runaway phone can't
//     OOM the brain.

const std = @import("std");
const dispatcher = @import("dispatcher");
const helm_event_broker = @import("helm_event_broker");
const audit_log = @import("audit_log");
const jobs_store_fs = @import("jobs_store_fs");
const job_fsm = @import("job_fsm");

/// Minimum token length to consider for substring matching.  Anything
/// shorter ("for", "the", "and", "of", "is", "a") is too noisy to
/// uniquely identify a job's customer.
pub const DEFAULT_MIN_TOKEN_LEN: usize = 4;

/// Bounded pending-queue size.  A typed-NL operator types a command
/// every few seconds; 64 entries is ~3-5 minutes of unprocessed
/// backlog at full speed — well past any realistic reactor lag.
/// Evictions land in the audit log so an over-flowing queue is
/// visible without crashing the daemon.
pub const MAX_PENDING: usize = 64;

/// One-to-one mapping from intent action verb (as the phone-side
/// extractor emits it) to the canonical Job FSM state the router
/// should transition into.
pub const ActionMapping = struct {
    action: []const u8,
    target_state: []const u8,
};

/// The supported set, covering the full canonical Job FSM lifecycle
/// `lead → qualified ┬→ visit_pending → visit_scheduled → visited →
/// quoted │ (qualified └→ quoted skip │ └→ authorized no-quote
/// branch) → quoted/authorized → scheduled → in_progress → completed
/// → invoiced → paid → closed`.  Multiple phone-emitted verb spellings
/// alias onto
/// the same target state (the on-device extractor is non-deterministic
/// about wording — "submit_quote" vs "quote", "arrive" vs "arrived"
/// vs "on_site", etc.).  The router no longer hard-gates on a single
/// from-state: per-action eligibility is delegated to the canonical
/// `job_fsm.findTransition(current, target)` table (see
/// `isFsmTransitionAllowed`), so each verb only fires from the state
/// the FSM actually permits — `arrive` only advances a `scheduled`
/// job, `paid` only an `invoiced` one, etc.  Anything not in this
/// table is audit-logged + skipped (`unknown_action`).
pub const SUPPORTED_ACTIONS = [_]ActionMapping{
    // ── Lead-nurture front (twelve-state remodel). The FSM-path
    //    gate (isFsmTransitionAllowed) picks the legal edge, so a
    //    single target_state works even where two states feed it
    //    (quote fires qualified→quoted OR visited→quoted).
    // lead → qualified  (ROM accepted in the chat widget)
    .{ .action = "accept_rom", .target_state = "qualified" },
    .{ .action = "rom_accepted", .target_state = "qualified" },
    .{ .action = "qualify", .target_state = "qualified" },
    .{ .action = "qualified", .target_state = "qualified" },
    // qualified → visit_pending  (this one needs eyes on site)
    .{ .action = "need_visit", .target_state = "visit_pending" },
    .{ .action = "needs_visit", .target_state = "visit_pending" },
    .{ .action = "request_visit", .target_state = "visit_pending" },
    .{ .action = "visit_needed", .target_state = "visit_pending" },
    .{ .action = "to_quote", .target_state = "visit_pending" },
    // visit_pending → visit_scheduled  (time locked with customer)
    .{ .action = "book_visit", .target_state = "visit_scheduled" },
    .{ .action = "schedule_visit", .target_state = "visit_scheduled" },
    .{ .action = "arrange_visit", .target_state = "visit_scheduled" },
    .{ .action = "visit_booked", .target_state = "visit_scheduled" },
    // visit_scheduled → visited  (been on site; photos attached)
    .{ .action = "mark_visited", .target_state = "visited" },
    .{ .action = "visited", .target_state = "visited" },
    .{ .action = "assessed", .target_state = "visited" },
    .{ .action = "site_assessed", .target_state = "visited" },
    .{ .action = "visit_done", .target_state = "visited" },
    // qualified → quoted (skip path) OR visited → quoted — the
    // FSM-path gate selects whichever edge the job's current state
    // permits.
    .{ .action = "quote", .target_state = "quoted" },
    .{ .action = "submit_quote", .target_state = "quoted" },
    .{ .action = "quoted", .target_state = "quoted" },
    // qualified → authorized (directly-authorised branch — a
    // pre-authorised work order, e.g. an REA-issued WO that IS the
    // authorisation; no customer quote owed. The FSM-path gate only
    // lets this fire from `qualified`).
    .{ .action = "authorize", .target_state = "authorized" },
    .{ .action = "authorise", .target_state = "authorized" },
    .{ .action = "authorized", .target_state = "authorized" },
    .{ .action = "authorised", .target_state = "authorized" },
    .{ .action = "work_order", .target_state = "authorized" },
    .{ .action = "wo_authorized", .target_state = "authorized" },
    .{ .action = "no_quote", .target_state = "authorized" },
    .{ .action = "skip_quote", .target_state = "authorized" },
    .{ .action = "pre_authorized", .target_state = "authorized" },
    // quoted → scheduled  (post-quote WORK dispatch — distinct from
    // the pre-quote site-visit scheduling above)
    .{ .action = "schedule", .target_state = "scheduled" },
    .{ .action = "scheduled", .target_state = "scheduled" },
    .{ .action = "dispatch", .target_state = "scheduled" },
    .{ .action = "book", .target_state = "scheduled" },
    // scheduled → in_progress  ("I've arrived on site / started")
    .{ .action = "arrive", .target_state = "in_progress" },
    .{ .action = "arrived", .target_state = "in_progress" },
    .{ .action = "on_site", .target_state = "in_progress" },
    .{ .action = "start", .target_state = "in_progress" },
    .{ .action = "start_work", .target_state = "in_progress" },
    // in_progress → completed  ("I've left / work done")
    .{ .action = "leave", .target_state = "completed" },
    .{ .action = "left", .target_state = "completed" },
    .{ .action = "depart", .target_state = "completed" },
    .{ .action = "complete", .target_state = "completed" },
    .{ .action = "completed", .target_state = "completed" },
    .{ .action = "done", .target_state = "completed" },
    // completed → invoiced
    .{ .action = "invoice", .target_state = "invoiced" },
    .{ .action = "invoiced", .target_state = "invoiced" },
    .{ .action = "bill", .target_state = "invoiced" },
    // invoiced → paid
    .{ .action = "paid", .target_state = "paid" },
    .{ .action = "payment", .target_state = "paid" },
    .{ .action = "mark_paid", .target_state = "paid" },
    // paid → closed
    .{ .action = "close", .target_state = "closed" },
    .{ .action = "closed", .target_state = "closed" },
};

pub const RouterError = error{
    out_of_memory,
};

/// One entry in the router's pending-action queue.  Owned strings —
/// the broker's `payload_json` slice is borrowed for the duration of
/// the publish call only, so we dupe everything into the router's
/// allocator before enqueueing.
const PendingAction = struct {
    cell_id: []u8,
    intent_action: []u8,
    intent_summary: []u8,
    /// Raw originalIntent.targetJson string (jobId/amount/costMin/
    /// costMax/currency), or "" when the producer supplied none.
    /// Drives the ROM→Estimate mint on accept_rom (Slice 3).
    intent_target_json: []u8,

    fn deinit(self: *PendingAction, allocator: std.mem.Allocator) void {
        allocator.free(self.cell_id);
        allocator.free(self.intent_action);
        allocator.free(self.intent_summary);
        allocator.free(self.intent_target_json);
    }
};

/// Router state.  Owned at the top of cmdServe so its address is
/// stable for the lifetime of the broker's subscriber list.
pub const Router = struct {
    allocator: std.mem.Allocator,
    /// Borrowed for the router's lifetime — the broker we subscribe
    /// to.  Unsubscribe in `deinit` so a router that outlives its
    /// owner doesn't leave a dangling pointer in the broker's
    /// subscriber list.
    broker: *helm_event_broker.Broker,
    /// Borrowed — used by `tick` to look up the job by
    /// customer_name substring + check current FSM state.
    jobs_store: *jobs_store_fs.JobsStore,
    /// Borrowed — `disp.dispatch(..., "jobs", "transition", ...)` is
    /// how we re-enter the FSM.  Going through the dispatcher rather
    /// than calling the JobsHandler directly means the existing
    /// audit pair, broker emit (`job.transitioned`), and any future
    /// quarantine gate all run uniformly for router-driven and
    /// human-driven transitions.  Called only from `tick` —
    /// NEVER from the broker callback (re-entry deadlock).
    disp: *dispatcher.Dispatcher,
    /// Optional audit log shared with the dispatcher.  When non-null,
    /// the router records phase=match / phase=skip / phase=transition
    /// lines under `module=intent_router`.
    audit: ?*audit_log.AuditLog,
    /// Subscriber id returned by `broker.subscribe`.  Held so
    /// `deinit` can unsubscribe.  null = not subscribed (router
    /// pre-init or post-deinit).
    sub_id: ?helm_event_broker.SubscriberId,
    /// FIFO queue of actions enqueued by the broker callback,
    /// drained by `tick`.  Bounded at MAX_PENDING; oldest evicts
    /// on overflow.
    pending: std.ArrayList(PendingAction),
    /// Mutex guarding `pending`.  The broker callback fires on the
    /// broker's own mutex (which may be on a different thread today
    /// — brain has a single reactor thread but wss_wallet's listener
    /// uses pool threads); `tick` runs on the reactor thread.  Today
    /// these are the same physical thread but the mutex is cheap
    /// and future-proofs against the reactor split.
    pending_mu: std.Thread.Mutex,
    /// Configurable minimum token length for noise filtering.
    min_token_len: usize,
    /// When false the callback is a no-op — used by tests to verify
    /// the gate-disabled path without unsubscribing.  cli.zig sets
    /// this to true when --enable-intent-action-router is on.
    enabled: bool,

    /// Construct a router and subscribe to the broker.  The router
    /// is `enabled`-gated: cli.zig opts in to construction only when
    /// the operator passes the flag, so the gate is enforced one
    /// level up.  Tests construct directly with `enabled = false` to
    /// verify the no-op path.
    pub fn init(
        allocator: std.mem.Allocator,
        broker: *helm_event_broker.Broker,
        jobs_store: *jobs_store_fs.JobsStore,
        disp: *dispatcher.Dispatcher,
        audit_opt: ?*audit_log.AuditLog,
        enabled: bool,
    ) RouterError!*Router {
        const self = allocator.create(Router) catch return error.out_of_memory;
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .broker = broker,
            .jobs_store = jobs_store,
            .disp = disp,
            .audit = audit_opt,
            .sub_id = null,
            .pending = .{},
            .pending_mu = .{},
            .min_token_len = DEFAULT_MIN_TOKEN_LEN,
            .enabled = enabled,
        };
        const sub: helm_event_broker.Subscriber = .{
            .state = self,
            .callback = onBrokerEvent,
        };
        self.sub_id = broker.subscribe(sub) catch |err| switch (err) {
            error.out_of_memory => {
                allocator.destroy(self);
                return error.out_of_memory;
            },
        };
        return self;
    }

    /// Unsubscribe from the broker, drain any pending entries, free
    /// the router.  Idempotent unsubscribe.
    pub fn deinit(self: *Router) void {
        if (self.sub_id) |id| {
            self.broker.unsubscribe(id);
            self.sub_id = null;
        }
        for (self.pending.items) |*p| p.deinit(self.allocator);
        self.pending.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Test-only — flip the gate without re-subscribing.
    pub fn setEnabled(self: *Router, enabled: bool) void {
        self.enabled = enabled;
    }

    /// Drain the pending queue.  Each entry runs through
    /// `processAction` which may call `dispatcher.dispatch`.  Safe to
    /// call on every reactor poll tick — when the queue is empty
    /// (the common case) it's a single mutex acquire + length check.
    ///
    /// Wrapped in a giant try/catch so a buggy intent or a
    /// dispatcher hiccup never crashes the reactor.  Inner helpers
    /// audit-log typed failures.
    pub fn tick(self: *Router) void {
        // Snapshot the current queue length under the mutex, then
        // detach the items so we can process them outside the lock
        // (so a callback firing concurrently can keep enqueueing).
        var to_process: std.ArrayList(PendingAction) = .{};
        defer to_process.deinit(self.allocator);
        {
            self.pending_mu.lock();
            defer self.pending_mu.unlock();
            if (self.pending.items.len == 0) return;
            // Move every pending entry into to_process.  Use append
            // to avoid surfacing a swapRemove-into-arbitrary-order on
            // the FIFO — each entry transfers ownership cleanly.
            to_process.appendSlice(self.allocator, self.pending.items) catch {
                // Allocation failure here is unusual (the slice grows
                // in the same allocator).  Fail safe: drop the queue
                // contents this tick; the OOM will surface again on
                // the next enqueue.
                for (self.pending.items) |*p| p.deinit(self.allocator);
                self.pending.clearRetainingCapacity();
                return;
            };
            // The PendingActions now exist in BOTH lists, but the
            // owned slices have a single owner: we move ownership to
            // to_process by clearing pending without per-element
            // deinit.
            self.pending.clearRetainingCapacity();
        }

        for (to_process.items) |action| {
            processAction(self, action) catch |err| {
                if (self.audit) |a| {
                    var buf: [128]u8 = undefined;
                    const detail = std.fmt.bufPrint(
                        &buf,
                        "phase=skip kind=router_tick_err err={s}",
                        .{@errorName(err)},
                    ) catch "phase=skip kind=router_tick_err";
                    a.record(self.allocator, .{
                        .module = "intent_router",
                        .op = "tick",
                        .result = .err,
                        .detail = detail,
                    }) catch {};
                }
            };
        }
        // Free the moved-in entries.  to_process's deinit-loop frees
        // each PendingAction's owned slices when its scope ends.
        for (to_process.items) |*p| p.deinit(self.allocator);
        to_process.clearRetainingCapacity();
    }

    /// Test-only diagnostic — number of entries waiting in the
    /// queue.  Not racy because tests are single-threaded.
    pub fn pendingCount(self: *Router) usize {
        self.pending_mu.lock();
        defer self.pending_mu.unlock();
        return self.pending.items.len;
    }
};

// ─── Broker callback (enqueue only) ─────────────────────────────────

/// Subscriber callback.  Fires inside `broker.publish` with the
/// broker mutex held — we MUST NOT call back into broker.publish or
/// any function that does (e.g. `dispatcher.dispatch` on a handler
/// that emits).  The callback's only job is: parse the payload, dupe
/// the relevant fields, enqueue.  The actual dispatch happens later
/// from `tick`.
fn onBrokerEvent(state: ?*anyopaque, event: helm_event_broker.Event) void {
    const self: *Router = @ptrCast(@alignCast(state.?));
    if (!self.enabled) return;
    if (!std.mem.eql(u8, event.type, "intent_cell.created")) return;

    enqueueFromEvent(self, event) catch |err| {
        if (self.audit) |a| {
            var buf: [128]u8 = undefined;
            const detail = std.fmt.bufPrint(
                &buf,
                "phase=skip kind=enqueue_err err={s}",
                .{@errorName(err)},
            ) catch "phase=skip kind=enqueue_err";
            a.record(self.allocator, .{
                .module = "intent_router",
                .op = "broker_event",
                .result = .err,
                .detail = detail,
            }) catch {};
        }
    };
}

fn enqueueFromEvent(self: *Router, event: helm_event_broker.Event) !void {
    const allocator = self.allocator;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, event.payload_json, .{}) catch {
        recordSkip(self, "", "", "parse_failed");
        return;
    };
    defer parsed.deinit();
    if (parsed.value != .object) {
        recordSkip(self, "", "", "payload_not_object");
        return;
    }
    const obj = parsed.value.object;

    const cell_id = jsonStringField(obj, "cell_id") orelse {
        recordSkip(self, "", "", "missing_cell_id");
        return;
    };
    const intent_action = jsonStringField(obj, "intent_action") orelse {
        recordSkip(self, cell_id, "", "missing_intent_action");
        return;
    };
    const intent_summary = jsonStringField(obj, "intent_summary") orelse {
        recordSkip(self, cell_id, intent_action, "missing_intent_summary");
        return;
    };
    // Optional — the ROM money channel. Absent on every non-ROM
    // intent and on figure-less accept_rom; "" then, handled as
    // "no figure" downstream (existing behaviour unchanged).
    const intent_target_json = jsonStringField(obj, "intent_target_json") orelse "";

    // Dupe everything before enqueueing — the broker's payload_json
    // is borrowed for the duration of the publish call and would
    // dangle by the time tick runs.
    const cell_id_owned = try allocator.dupe(u8, cell_id);
    errdefer allocator.free(cell_id_owned);
    const action_owned = try allocator.dupe(u8, intent_action);
    errdefer allocator.free(action_owned);
    const summary_owned = try allocator.dupe(u8, intent_summary);
    errdefer allocator.free(summary_owned);
    const target_json_owned = try allocator.dupe(u8, intent_target_json);
    errdefer allocator.free(target_json_owned);

    self.pending_mu.lock();
    defer self.pending_mu.unlock();

    // Bounded queue: evict the oldest if we're at MAX_PENDING.
    if (self.pending.items.len >= MAX_PENDING) {
        var oldest = self.pending.orderedRemove(0);
        // Audit-log the eviction so the operator can spot a runaway.
        if (self.audit) |a| {
            var buf: [192]u8 = undefined;
            const detail = std.fmt.bufPrint(
                &buf,
                "phase=skip kind=queue_full evicted_cell_id={s}",
                .{oldest.cell_id},
            ) catch "phase=skip kind=queue_full";
            a.record(self.allocator, .{
                .module = "intent_router",
                .op = "broker_event",
                .result = .denied,
                .detail = detail,
            }) catch {};
        }
        oldest.deinit(self.allocator);
    }

    try self.pending.append(self.allocator, .{
        .cell_id = cell_id_owned,
        .intent_action = action_owned,
        .intent_summary = summary_owned,
        .intent_target_json = target_json_owned,
    });
}

// ─── Action processing (drained by tick) ────────────────────────────

fn processAction(self: *Router, action: PendingAction) !void {
    const allocator = self.allocator;

    // Action → target state.  Unknown actions audit-skip.
    const target_state = mapAction(action.intent_action) orelse {
        recordSkip(self, action.cell_id, action.intent_action, "unknown_action");
        return;
    };

    // Cold-boot defence: zero jobs in the store → nothing to match.
    if (self.jobs_store.count() == 0) {
        recordSkip(self, action.cell_id, action.intent_action, "store_empty");
        return;
    }

    // Heuristic single-match search across customer_name.
    const matched = findSingleMatchingJob(self, action.intent_summary) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
        error.AmbiguousMatch => {
            recordSkip(self, action.cell_id, action.intent_action, "ambiguous_match");
            return;
        },
        error.NoMatch => {
            recordSkip(self, action.cell_id, action.intent_action, "no_match");
            return;
        },
    };
    defer allocator.free(matched.id);
    defer allocator.free(matched.current_state);

    // Eligibility gate — the (current_state → target_state) pair
    // must be a real edge in the canonical Job FSM.  This replaces
    // the old hard "lead only" gate so the full lifecycle works
    // (`arrive` advances a scheduled job, `paid` an invoiced one,
    // …) while still refusing any transition the FSM doesn't allow —
    // a misfire never skips states or regresses live operator data.
    // Idempotent no-op (current == target, e.g. re-sent "paid" on an
    // already-paid job) is skipped cleanly rather than erroring.
    if (std.mem.eql(u8, matched.current_state, target_state)) {
        recordSkipMatched(self, action.cell_id, action.intent_action, "already_in_state", matched.id, matched.current_state);
        return;
    }
    if (!isFsmTransitionAllowed(matched.current_state, target_state)) {
        recordSkipMatched(self, action.cell_id, action.intent_action, "no_fsm_path", matched.id, matched.current_state);
        return;
    }

    // Build the transition args body and dispatch.  `tick` runs
    // OUTSIDE the broker mutex, so jobs.transition's recursive emit
    // of `job.transitioned` succeeds without deadlock.
    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(allocator);
    try args_buf.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, &args_buf, matched.id);
    try args_buf.appendSlice(allocator, ",\"to_state\":");
    try writeJsonString(allocator, &args_buf, target_state);
    try args_buf.appendSlice(allocator, ",\"principal_kind\":\"operator\"}");

    const ctx: dispatcher.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{
            .request_id = "intent_router",
            .transport_label = "intent_router",
        },
    };

    var result = self.disp.dispatch(&ctx, "jobs", "transition", args_buf.items) catch |err| {
        recordTransitionErr(self, action.cell_id, matched.id, target_state, @errorName(err));
        return;
    };
    defer result.deinit();

    if (looksLikeErrorBody(result.payload)) {
        recordTransitionErrShape(self, action.cell_id, matched.id, target_state, result.payload);
        return;
    }

    recordTransitionOk(self, action.cell_id, matched.id, target_state);

    // Slice 3 — ROM ingress. A ROM-accept (any verb mapping to
    // `qualified`) that carried a figure on the intent cell's
    // targetJson money channel mints an *accepted* auto_rom Estimate
    // for the matched job, so Slice 4's quote-seed router can later
    // pre-fill the draft Quote. Best-effort + additive: the
    // lead→qualified transition already succeeded above; an Estimate
    // mint failure is audit-logged and never unwinds it. Figure-less
    // accept_rom (no targetJson) is a no-op here — unchanged
    // behaviour.
    maybeSeedRomEstimate(self, action, matched.id, target_state);
}

/// Parsed ROM money bounds (cents). costMin/costMax preferred; a
/// single `amount` collapses to a point estimate (min == max).
const RomCost = struct { min: i64, max: i64 };

fn parseTargetCost(allocator: std.mem.Allocator, target_json: []const u8) ?RomCost {
    if (target_json.len == 0) return null;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, target_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const o = parsed.value.object;

    const asInt = struct {
        fn f(v: std.json.Value) ?i64 {
            return switch (v) {
                .integer => |i| i,
                .float => |fl| @as(i64, @intFromFloat(fl)),
                else => null,
            };
        }
    }.f;

    if (o.get("costMin")) |mn_v| {
        if (o.get("costMax")) |mx_v| {
            const mn = asInt(mn_v) orelse return null;
            const mx = asInt(mx_v) orelse return null;
            if (mn < 0 or mx < mn) return null;
            return .{ .min = mn, .max = mx };
        }
    }
    if (o.get("amount")) |a_v| {
        const a = asInt(a_v) orelse return null;
        if (a < 0) return null;
        return .{ .min = a, .max = a };
    }
    return null;
}

fn maybeSeedRomEstimate(
    self: *Router,
    action: PendingAction,
    job_id: []const u8,
    target_state: []const u8,
) void {
    if (!std.mem.eql(u8, target_state, "qualified")) return;
    const cost = parseTargetCost(self.allocator, action.intent_target_json) orelse return;

    const allocator = self.allocator;
    var args: std.ArrayList(u8) = .{};
    defer args.deinit(allocator);
    args.appendSlice(allocator, "{\"job_id\":") catch return;
    writeJsonString(allocator, &args, job_id) catch return;
    args.print(
        allocator,
        ",\"estimate_type\":\"auto_rom\",\"cost_min\":{d},\"cost_max\":{d},\"ack_status\":\"accepted\"}}",
        .{ cost.min, cost.max },
    ) catch return;

    const ctx: dispatcher.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{
            .request_id = "intent_router",
            .transport_label = "intent_router",
        },
    };

    var result = self.disp.dispatch(&ctx, "estimates", "create", args.items) catch |err| {
        if (self.audit) |a| {
            var buf: [256]u8 = undefined;
            const detail = std.fmt.bufPrint(
                &buf,
                "phase=estimate kind=dispatch_err cell_id={s} job_id={s} err={s}",
                .{ action.cell_id, job_id, @errorName(err) },
            ) catch "phase=estimate kind=dispatch_err";
            a.record(allocator, .{
                .module = "intent_router",
                .op = "tick",
                .result = .err,
                .detail = detail,
            }) catch {};
        }
        return;
    };
    defer result.deinit();

    const a = self.audit orelse return;
    const ok = !looksLikeErrorBody(result.payload);
    var buf: [320]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=estimate kind={s} cell_id={s} job_id={s} cost_min={d} cost_max={d}",
        .{ if (ok) "ok" else "rejected", action.cell_id, job_id, cost.min, cost.max },
    ) catch "phase=estimate";
    a.record(allocator, .{
        .module = "intent_router",
        .op = "tick",
        .result = if (ok) .ok else .denied,
        .detail = detail,
    }) catch {};
}

// ─── Heuristic match ────────────────────────────────────────────────

const MatchedJob = struct {
    id: []u8,
    current_state: []u8,
};

const SearchError = error{
    AmbiguousMatch,
    NoMatch,
    OutOfMemory,
};

/// Tokenize the summary on whitespace + punctuation, lowercase + drop
/// short tokens, then for each token scan the jobs store for jobs
/// whose customer_name (lower-cased) contains the token.  If exactly
/// one distinct job matches across all tokens, return it.
///
/// W4.1 — h_state ranking: when multiple jobs match the same name
/// fragment, prefer the one with the most recent `created_at`
/// timestamp (lexicographic ISO-8601 comparison — the fixed-width
/// format makes this a valid proxy for chronological order).  This is
/// a pragmatic approximation of Pask h_state elevation until the full
/// Pask graph integration lands in M5.10.  Same-timestamp tiebreak:
/// the lowest candidate index (store-scan order) wins — deterministic
/// and avoids returning AmbiguousMatch for the common "two jobs
/// created at the same second" edge case.
fn findSingleMatchingJob(self: *Router, summary: []const u8) SearchError!MatchedJob {
    const allocator = self.allocator;

    const jobs = self.jobs_store.findAll(allocator) catch return error.OutOfMemory;
    defer allocator.free(jobs);

    if (jobs.len == 0) return error.NoMatch;

    var match_indexes: std.ArrayList(usize) = .{};
    defer match_indexes.deinit(allocator);

    const summary_lower = allocator.alloc(u8, summary.len) catch return error.OutOfMemory;
    defer allocator.free(summary_lower);
    asciiLower(summary_lower, summary);

    var any_token_seen = false;
    var token_start: usize = 0;
    var i: usize = 0;
    while (i <= summary_lower.len) : (i += 1) {
        const at_end = i == summary_lower.len;
        const is_boundary = at_end or !isTokenByte(summary_lower[i]);
        if (!is_boundary) continue;

        if (i > token_start) {
            const token = summary_lower[token_start..i];
            if (token.len >= self.min_token_len) {
                any_token_seen = true;
                try addMatchesForToken(allocator, &match_indexes, jobs, token);
            }
        }
        token_start = i + 1;
    }

    if (!any_token_seen) return error.NoMatch;
    if (match_indexes.items.len == 0) return error.NoMatch;

    // W4.1: resolve ambiguity by picking the most recently created job.
    // When exactly one match exists the loop below is a single-pass
    // identity; no behavioural change from the pre-W4.1 path.
    const best_idx = pickMostRecentJob(jobs, match_indexes.items);

    const job = jobs[best_idx];
    const id_owned = allocator.dupe(u8, job.id) catch return error.OutOfMemory;
    errdefer allocator.free(id_owned);
    const state_owned = allocator.dupe(u8, job.state) catch return error.OutOfMemory;
    return .{ .id = id_owned, .current_state = state_owned };
}

/// Return the index (into `jobs`) of the candidate with the latest
/// `created_at` string.  ISO-8601 fixed-width timestamps compare
/// correctly under lexicographic order.  Tiebreak: lowest candidate
/// index (store-scan order) — gives a stable, deterministic result
/// without allocating a secondary sort key.
fn pickMostRecentJob(jobs: []jobs_store_fs.Job, candidates: []const usize) usize {
    std.debug.assert(candidates.len > 0);
    var best: usize = candidates[0];
    for (candidates[1..]) |idx| {
        if (std.mem.order(u8, jobs[idx].created_at, jobs[best].created_at) == .gt) {
            best = idx;
        }
    }
    return best;
}

fn addMatchesForToken(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(usize),
    jobs: []jobs_store_fs.Job,
    token: []const u8,
) SearchError!void {
    var stack_buf: [256]u8 = undefined;
    for (jobs, 0..) |job, idx| {
        if (containsIndex(out.items, idx)) continue;

        const heap_lower: ?[]u8 = if (job.customer_name.len > stack_buf.len)
            allocator.alloc(u8, job.customer_name.len) catch return error.OutOfMemory
        else
            null;
        defer if (heap_lower) |h| allocator.free(h);
        const lower = if (heap_lower) |h| h else stack_buf[0..job.customer_name.len];
        asciiLower(lower, job.customer_name);

        if (std.mem.indexOf(u8, lower, token) != null) {
            out.append(allocator, idx) catch return error.OutOfMemory;
        }
    }
}

fn containsIndex(list: []const usize, target: usize) bool {
    for (list) |v| {
        if (v == target) return true;
    }
    return false;
}

fn isTokenByte(b: u8) bool {
    if (b >= 'a' and b <= 'z') return true;
    if (b >= '0' and b <= '9') return true;
    return false;
}

fn asciiLower(dst: []u8, src: []const u8) void {
    std.debug.assert(dst.len >= src.len);
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        const c = src[i];
        dst[i] = if (c >= 'A' and c <= 'Z') c + 32 else c;
    }
}

// ─── Action mapping ─────────────────────────────────────────────────

pub fn mapAction(action: []const u8) ?[]const u8 {
    for (SUPPORTED_ACTIONS) |row| {
        if (std.mem.eql(u8, row.action, action)) return row.target_state;
    }
    return null;
}

/// True iff `from → to` is a real edge in the canonical Job FSM
/// transition table.  Delegates to job_fsm so the router and the
/// dispatcher's `jobs.transition` validate against the exact same
/// source of truth — no second, drifting copy of the lifecycle.
fn isFsmTransitionAllowed(from: []const u8, to: []const u8) bool {
    return job_fsm.findTransition(from, to) != null;
}

// ─── Audit helpers ──────────────────────────────────────────────────

fn recordSkip(self: *Router, cell_id: []const u8, action: []const u8, reason: []const u8) void {
    const a = self.audit orelse return;
    var buf: [256]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=skip kind={s} cell_id={s} action={s}",
        .{ reason, cell_id, action },
    ) catch "phase=skip";
    a.record(self.allocator, .{
        .module = "intent_router",
        .op = "broker_event",
        .result = .denied,
        .detail = detail,
    }) catch {};
}

fn recordSkipMatched(
    self: *Router,
    cell_id: []const u8,
    action: []const u8,
    reason: []const u8,
    job_id: []const u8,
    current_state: []const u8,
) void {
    const a = self.audit orelse return;
    var buf: [320]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=skip kind={s} cell_id={s} action={s} job_id={s} from={s}",
        .{ reason, cell_id, action, job_id, current_state },
    ) catch "phase=skip";
    a.record(self.allocator, .{
        .module = "intent_router",
        .op = "tick",
        .result = .denied,
        .detail = detail,
    }) catch {};
}

fn recordTransitionOk(self: *Router, cell_id: []const u8, job_id: []const u8, target_state: []const u8) void {
    const a = self.audit orelse return;
    var buf: [256]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=transition kind=ok cell_id={s} job_id={s} to={s}",
        .{ cell_id, job_id, target_state },
    ) catch "phase=transition kind=ok";
    a.record(self.allocator, .{
        .module = "intent_router",
        .op = "tick",
        .result = .ok,
        .detail = detail,
    }) catch {};
}

fn recordTransitionErr(
    self: *Router,
    cell_id: []const u8,
    job_id: []const u8,
    target_state: []const u8,
    err_name: []const u8,
) void {
    const a = self.audit orelse return;
    var buf: [320]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=transition kind=dispatch_err cell_id={s} job_id={s} to={s} err={s}",
        .{ cell_id, job_id, target_state, err_name },
    ) catch "phase=transition kind=dispatch_err";
    a.record(self.allocator, .{
        .module = "intent_router",
        .op = "tick",
        .result = .err,
        .detail = detail,
    }) catch {};
}

fn recordTransitionErrShape(
    self: *Router,
    cell_id: []const u8,
    job_id: []const u8,
    target_state: []const u8,
    body: []const u8,
) void {
    const a = self.audit orelse return;
    const max_body: usize = 64;
    const tail = if (body.len > max_body) body[0..max_body] else body;
    var buf: [320]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=transition kind=fsm_rejected cell_id={s} job_id={s} to={s} body={s}",
        .{ cell_id, job_id, target_state, tail },
    ) catch "phase=transition kind=fsm_rejected";
    a.record(self.allocator, .{
        .module = "intent_router",
        .op = "tick",
        .result = .denied,
        .detail = detail,
    }) catch {};
}

// ─── JSON helpers ───────────────────────────────────────────────────

fn jsonStringField(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    if (v != .string) return null;
    return v.string;
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

fn looksLikeErrorBody(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "\"error\":") != null;
}

// ─── Inline tests — pure helpers ─────────────────────────────────────

test "mapAction: full lifecycle verb set + phone aliases" {
    // lead-nurture front
    try std.testing.expectEqualStrings("qualified", mapAction("accept_rom").?);
    try std.testing.expectEqualStrings("qualified", mapAction("rom_accepted").?);
    try std.testing.expectEqualStrings("qualified", mapAction("qualify").?);
    try std.testing.expectEqualStrings("visit_pending", mapAction("need_visit").?);
    try std.testing.expectEqualStrings("visit_pending", mapAction("request_visit").?);
    try std.testing.expectEqualStrings("visit_scheduled", mapAction("book_visit").?);
    try std.testing.expectEqualStrings("visit_scheduled", mapAction("schedule_visit").?);
    try std.testing.expectEqualStrings("visited", mapAction("mark_visited").?);
    try std.testing.expectEqualStrings("visited", mapAction("assessed").?);
    // qualified→quoted (skip) OR visited→quoted — same target verb
    try std.testing.expectEqualStrings("quoted", mapAction("quote").?);
    try std.testing.expectEqualStrings("quoted", mapAction("submit_quote").?);
    try std.testing.expectEqualStrings("quoted", mapAction("quoted").?);
    // qualified→authorized (directly-authorised, no-quote branch)
    try std.testing.expectEqualStrings("authorized", mapAction("authorize").?);
    try std.testing.expectEqualStrings("authorized", mapAction("authorised").?);
    try std.testing.expectEqualStrings("authorized", mapAction("work_order").?);
    try std.testing.expectEqualStrings("authorized", mapAction("no_quote").?);
    // quoted → scheduled (post-quote work dispatch)
    try std.testing.expectEqualStrings("scheduled", mapAction("schedule").?);
    try std.testing.expectEqualStrings("scheduled", mapAction("dispatch").?);
    try std.testing.expectEqualStrings("scheduled", mapAction("book").?);
    // scheduled → in_progress
    try std.testing.expectEqualStrings("in_progress", mapAction("arrive").?);
    try std.testing.expectEqualStrings("in_progress", mapAction("arrived").?);
    try std.testing.expectEqualStrings("in_progress", mapAction("on_site").?);
    try std.testing.expectEqualStrings("in_progress", mapAction("start").?);
    // in_progress → completed
    try std.testing.expectEqualStrings("completed", mapAction("leave").?);
    try std.testing.expectEqualStrings("completed", mapAction("left").?);
    try std.testing.expectEqualStrings("completed", mapAction("done").?);
    // completed → invoiced
    try std.testing.expectEqualStrings("invoiced", mapAction("invoice").?);
    try std.testing.expectEqualStrings("invoiced", mapAction("invoiced").?);
    try std.testing.expectEqualStrings("invoiced", mapAction("bill").?);
    // invoiced → paid
    try std.testing.expectEqualStrings("paid", mapAction("paid").?);
    try std.testing.expectEqualStrings("paid", mapAction("mark_paid").?);
    // paid → closed
    try std.testing.expectEqualStrings("closed", mapAction("close").?);
    try std.testing.expectEqualStrings("closed", mapAction("closed").?);
}

test "mapAction: unknown action returns null" {
    try std.testing.expectEqual(@as(?[]const u8, null), mapAction("bogus"));
    try std.testing.expectEqual(@as(?[]const u8, null), mapAction(""));
    try std.testing.expectEqual(@as(?[]const u8, null), mapAction("Quote"));
    // `accept` is intentionally NOT supported — the brief's mapping
    // (lead → open) targets a non-existent FSM state.
    try std.testing.expectEqual(@as(?[]const u8, null), mapAction("accept"));
}

test "isFsmTransitionAllowed: thirteen-state lifecycle edges + branches" {
    // Lead-nurture front + the branch at qualified.
    try std.testing.expect(isFsmTransitionAllowed("lead", "qualified"));
    try std.testing.expect(isFsmTransitionAllowed("qualified", "visit_pending"));
    try std.testing.expect(isFsmTransitionAllowed("qualified", "quoted")); // skip path
    try std.testing.expect(isFsmTransitionAllowed("qualified", "authorized")); // no-quote branch
    try std.testing.expect(isFsmTransitionAllowed("visit_pending", "visit_scheduled"));
    try std.testing.expect(isFsmTransitionAllowed("visit_scheduled", "visited"));
    try std.testing.expect(isFsmTransitionAllowed("visited", "quoted"));
    // Post-quote chain — quoted AND authorized both feed scheduled.
    try std.testing.expect(isFsmTransitionAllowed("quoted", "scheduled"));
    try std.testing.expect(isFsmTransitionAllowed("authorized", "scheduled"));
    try std.testing.expect(isFsmTransitionAllowed("scheduled", "in_progress"));
    try std.testing.expect(isFsmTransitionAllowed("in_progress", "completed"));
    try std.testing.expect(isFsmTransitionAllowed("completed", "invoiced"));
    try std.testing.expect(isFsmTransitionAllowed("invoiced", "paid"));
    try std.testing.expect(isFsmTransitionAllowed("paid", "closed"));
    // The OLD direct lead→quoted is GONE — must pass through qualified.
    try std.testing.expect(!isFsmTransitionAllowed("lead", "quoted"));
    // State-skips refused (no misfire leapfrogs the visit chain).
    try std.testing.expect(!isFsmTransitionAllowed("qualified", "visit_scheduled"));
    try std.testing.expect(!isFsmTransitionAllowed("visit_pending", "quoted"));
    try std.testing.expect(!isFsmTransitionAllowed("lead", "scheduled"));
    // SD2 incr.2 — `lead → authorized` IS a real edge: a WO/
    // maintenance-order ingested via the converged seam IS its own
    // authorisation (REA/PM-issued, no customer quote owed), so it
    // skips straight from the genesis `lead` to `authorized` (see
    // job_fsm.JOB_TRANSITIONS[1] + runtime/legacy-ingest converged-
    // seam WORK_ORDER_ACTIONS). NOT a leapfrog. (This negative
    // assertion pre-dated SD2 incr.2 and was stale — the sibling fix
    // a34b0825 only corrected job_fsm.zig's own tests.)
    try std.testing.expect(isFsmTransitionAllowed("lead", "authorized"));
    // These remain non-edges — no leapfrog past the quote/visit gate.
    try std.testing.expect(!isFsmTransitionAllowed("qualified", "scheduled"));
    try std.testing.expect(!isFsmTransitionAllowed("authorized", "quoted"));
    // Backwards refused.
    try std.testing.expect(!isFsmTransitionAllowed("paid", "invoiced"));
    try std.testing.expect(!isFsmTransitionAllowed("quoted", "lead"));
    // Garbage refused.
    try std.testing.expect(!isFsmTransitionAllowed("", "quoted"));
    try std.testing.expect(!isFsmTransitionAllowed("lead", ""));
}

test "isTokenByte: ASCII letters + digits only" {
    try std.testing.expect(isTokenByte('a'));
    try std.testing.expect(isTokenByte('z'));
    try std.testing.expect(isTokenByte('0'));
    try std.testing.expect(isTokenByte('9'));
    try std.testing.expect(!isTokenByte('A'));
    try std.testing.expect(!isTokenByte(' '));
    try std.testing.expect(!isTokenByte('$'));
    try std.testing.expect(!isTokenByte('-'));
    try std.testing.expect(!isTokenByte('_'));
}

test "asciiLower: round-trip" {
    var buf: [16]u8 = undefined;
    asciiLower(buf[0..5], "Hello");
    try std.testing.expectEqualStrings("hello", buf[0..5]);
    asciiLower(buf[0..7], "WATTLE!");
    try std.testing.expectEqualStrings("wattle!", buf[0..7]);
}

test "looksLikeErrorBody: matches typed error envelope" {
    try std.testing.expect(looksLikeErrorBody("{\"error\":\"not_found\",\"from\":\"\"}"));
    try std.testing.expect(!looksLikeErrorBody("{\"id\":\"job-001\",\"state\":\"quoted\"}"));
}

test "parseTargetCost: costMin/costMax range, amount point, and rejects" {
    const A = std.testing.allocator;
    // Explicit range.
    const r = parseTargetCost(A, "{\"jobId\":\"j\",\"costMin\":40000,\"costMax\":60000}").?;
    try std.testing.expectEqual(@as(i64, 40000), r.min);
    try std.testing.expectEqual(@as(i64, 60000), r.max);
    // Single amount → point estimate (min == max).
    const p = parseTargetCost(A, "{\"amount\":52500,\"currency\":\"AUD\"}").?;
    try std.testing.expectEqual(@as(i64, 52500), p.min);
    try std.testing.expectEqual(@as(i64, 52500), p.max);
    // Empty / absent / malformed / no-figure → null (transition-only).
    try std.testing.expect(parseTargetCost(A, "") == null);
    try std.testing.expect(parseTargetCost(A, "{\"jobId\":\"j\"}") == null);
    try std.testing.expect(parseTargetCost(A, "not json") == null);
    // Inverted / negative range refused.
    try std.testing.expect(parseTargetCost(A, "{\"costMin\":900,\"costMax\":100}") == null);
    try std.testing.expect(parseTargetCost(A, "{\"amount\":-5}") == null);
}

```
