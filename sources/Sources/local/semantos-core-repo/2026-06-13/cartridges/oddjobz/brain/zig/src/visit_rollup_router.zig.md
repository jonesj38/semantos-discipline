---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/visit_rollup_router.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.546269+00:00
---

# cartridges/oddjobz/brain/zig/src/visit_rollup_router.zig

```zig
// Tier 3 follow-up — brain-side bridge from `visit.transitioned`
// broker events into the `oddjobz.jobs` FSM via `jobs.transition`.
//
// Reference: cartridges/oddjobz/brain/zig/src/intent_action_router.zig
//   (the proven subscribe → enqueue → tick → dispatch pattern this
//   mirrors 1:1, including the broker-reentrancy guardrail).
//
// What this module adds: when a site Visit reaches `completed` (the
// tradesperson left site / "leave"/"done"), the parent Job is rolled
// forward to `visited` automatically — so the job lands in the
// find_pipeline_gaps `visited_unquoted` bucket from real on-site
// activity, not only from a manual chat transition. This closes the
// "I visited but never got around to quoting" gap the operator
// explicitly called out.
//
// Flow:
//   1. visits_handler.handleTransition applies in_progress→completed
//      and publishes `visit.transitioned`
//      {id, job_id, from, to, transitioned_at} to the helm broker.
//   2. This subscriber's callback filters type=="visit.transitioned"
//      AND to=="completed", dupes job_id, and ENQUEUES (only).
//   3. tick() (driven by the EventLoop poll, same site as the intent
//      router) drains the queue and dispatches
//      jobs.transition {id:job_id, to_state:"visited",
//      principal_kind:"operator"} as in_process_root.
//
// ─── Why queue + tick (not direct dispatch) ────────────────────────
//
// Identical reasoning to intent_action_router: the broker holds a
// non-reentrant mutex while fanning out to subscribers; visits_handler
// publishes `visit.transitioned` from inside that fan-out, and
// jobs.transition itself re-publishes `job.transitioned`. Dispatching
// from the callback would re-enter broker.publish and deadlock. The
// callback only enqueues; the dispatch happens later from the reactor
// tick where no broker mutex is held.
//
// ─── Safety guardrails ──────────────────────────────────────────────
//
//   • Shares the intent-action-router gate (serve.zig only constructs
//     this when the intent router is enabled — both are "automated
//     broker→FSM advancement" subscribers; the systemd unit already
//     passes --enable-intent-action-router). The in-process `enabled`
//     field lets tests exercise the gate without unsubscribing.
//
//   • Fires ONLY on to=="completed". Every other visit transition
//     (scheduled→in_progress, *→cancelled) is ignored silently — no
//     audit noise on the common path.
//
//   • The job rollup is FSM-gated by jobs.transition itself: the only
//     incoming edge to `visited` is `visit_scheduled → visited`. If
//     the parent job is in any other state the dispatcher returns a
//     typed not_reachable body; we audit-skip (no-op) rather than
//     error. `already_in_state` (job already `visited`) returns a
//     success body and is recorded ok — idempotent and harmless.
//
//   • Whole body wrapped in try/catch; a malformed event never
//     crashes the broker thread (callback) or the reactor (tick).
//
//   • Bounded pending queue (MAX_PENDING); oldest evicts with an
//     audit line so a runaway can't OOM the daemon.

const std = @import("std");
const dispatcher = @import("dispatcher");
const helm_event_broker = @import("helm_event_broker");
const audit_log = @import("audit_log");

/// Bounded pending-queue size. Visits complete at human pace (a few
/// per day); 64 is far past any realistic reactor lag.
pub const MAX_PENDING: usize = 64;

/// The broker event we subscribe to and the trigger value.
pub const EVENT_TYPE = "visit.transitioned";
pub const TRIGGER_TO = "completed";
/// The Job FSM state a completed visit rolls its parent into.
pub const TARGET_JOB_STATE = "visited";

pub const RouterError = error{
    out_of_memory,
};

/// One entry in the pending queue. Owned strings — the broker's
/// payload slice is borrowed for the publish call only.
const PendingRollup = struct {
    visit_id: []u8,
    job_id: []u8,

    fn deinit(self: *PendingRollup, allocator: std.mem.Allocator) void {
        allocator.free(self.visit_id);
        allocator.free(self.job_id);
    }
};

/// Router state. Owned at the top of cmdServe so its address is
/// stable for the lifetime of the broker's subscriber list.
pub const Router = struct {
    allocator: std.mem.Allocator,
    /// Borrowed — the broker we subscribe to. Unsubscribed in deinit.
    broker: *helm_event_broker.Broker,
    /// Borrowed — `disp.dispatch(..., "jobs", "transition", ...)` is
    /// how we re-enter the Job FSM. Going through the dispatcher (not
    /// the JobsHandler directly) means the audit pair, broker emit
    /// (`job.transitioned`), and any future gate run uniformly for
    /// rollup-driven and human-driven transitions. Called only from
    /// `tick` — NEVER from the broker callback (re-entry deadlock).
    disp: *dispatcher.Dispatcher,
    /// Optional audit log shared with the dispatcher.
    audit: ?*audit_log.AuditLog,
    /// Subscriber id; held so deinit can unsubscribe. null = not
    /// subscribed.
    sub_id: ?helm_event_broker.SubscriberId,
    /// FIFO queue filled by the broker callback, drained by tick.
    pending: std.ArrayList(PendingRollup),
    /// Guards `pending` (callback thread vs reactor thread).
    pending_mu: std.Thread.Mutex,
    /// When false the callback is a no-op (test gate path).
    enabled: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        broker: *helm_event_broker.Broker,
        disp: *dispatcher.Dispatcher,
        audit_opt: ?*audit_log.AuditLog,
        enabled: bool,
    ) RouterError!*Router {
        const self = allocator.create(Router) catch return error.out_of_memory;
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .broker = broker,
            .disp = disp,
            .audit = audit_opt,
            .sub_id = null,
            .pending = .{},
            .pending_mu = .{},
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

    /// Unsubscribe, drain pending, free. Idempotent unsubscribe.
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

    /// Drain the pending queue. Safe to call on every reactor poll
    /// tick — when empty (common) it's a single mutex acquire +
    /// length check. Wrapped so a dispatcher hiccup never crashes
    /// the reactor.
    pub fn tick(self: *Router) void {
        var to_process: std.ArrayList(PendingRollup) = .{};
        defer to_process.deinit(self.allocator);
        {
            self.pending_mu.lock();
            defer self.pending_mu.unlock();
            if (self.pending.items.len == 0) return;
            to_process.appendSlice(self.allocator, self.pending.items) catch {
                for (self.pending.items) |*p| p.deinit(self.allocator);
                self.pending.clearRetainingCapacity();
                return;
            };
            // Ownership of the owned slices moves to to_process.
            self.pending.clearRetainingCapacity();
        }

        for (to_process.items) |rollup| {
            processRollup(self, rollup) catch |err| {
                if (self.audit) |a| {
                    var buf: [128]u8 = undefined;
                    const detail = std.fmt.bufPrint(
                        &buf,
                        "phase=skip kind=tick_err err={s}",
                        .{@errorName(err)},
                    ) catch "phase=skip kind=tick_err";
                    a.record(self.allocator, .{
                        .module = "visit_rollup",
                        .op = "tick",
                        .result = .err,
                        .detail = detail,
                    }) catch {};
                }
            };
        }
        for (to_process.items) |*p| p.deinit(self.allocator);
        to_process.clearRetainingCapacity();
    }

    /// Test-only diagnostic — entries waiting in the queue.
    pub fn pendingCount(self: *Router) usize {
        self.pending_mu.lock();
        defer self.pending_mu.unlock();
        return self.pending.items.len;
    }
};

// ─── Broker callback (enqueue only) ─────────────────────────────────

/// Fires inside broker.publish with the broker mutex held. MUST NOT
/// call back into broker.publish or dispatcher.dispatch. Parse, dupe,
/// enqueue — the dispatch happens later from tick.
fn onBrokerEvent(state: ?*anyopaque, event: helm_event_broker.Event) void {
    const self: *Router = @ptrCast(@alignCast(state.?));
    if (!self.enabled) return;
    if (!std.mem.eql(u8, event.type, EVENT_TYPE)) return;

    enqueueFromEvent(self, event) catch |err| {
        if (self.audit) |a| {
            var buf: [128]u8 = undefined;
            const detail = std.fmt.bufPrint(
                &buf,
                "phase=skip kind=enqueue_err err={s}",
                .{@errorName(err)},
            ) catch "phase=skip kind=enqueue_err";
            a.record(self.allocator, .{
                .module = "visit_rollup",
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

    const to_state = jsonStringField(obj, "to") orelse {
        recordSkip(self, "", "", "missing_to");
        return;
    };
    // Only a completed visit rolls the job up. Every other visit
    // transition is ignored silently — no audit noise.
    if (!std.mem.eql(u8, to_state, TRIGGER_TO)) return;

    const visit_id = jsonStringField(obj, "id") orelse "";
    const job_id = jsonStringField(obj, "job_id") orelse {
        recordSkip(self, visit_id, "", "missing_job_id");
        return;
    };
    if (job_id.len == 0) {
        recordSkip(self, visit_id, "", "empty_job_id");
        return;
    }

    const visit_id_owned = try allocator.dupe(u8, visit_id);
    errdefer allocator.free(visit_id_owned);
    const job_id_owned = try allocator.dupe(u8, job_id);
    errdefer allocator.free(job_id_owned);

    self.pending_mu.lock();
    defer self.pending_mu.unlock();

    if (self.pending.items.len >= MAX_PENDING) {
        var oldest = self.pending.orderedRemove(0);
        if (self.audit) |a| {
            var buf: [192]u8 = undefined;
            const detail = std.fmt.bufPrint(
                &buf,
                "phase=skip kind=queue_full evicted_visit_id={s}",
                .{oldest.visit_id},
            ) catch "phase=skip kind=queue_full";
            a.record(self.allocator, .{
                .module = "visit_rollup",
                .op = "broker_event",
                .result = .denied,
                .detail = detail,
            }) catch {};
        }
        oldest.deinit(self.allocator);
    }

    try self.pending.append(self.allocator, .{
        .visit_id = visit_id_owned,
        .job_id = job_id_owned,
    });
}

// ─── Rollup processing (drained by tick) ────────────────────────────

fn processRollup(self: *Router, rollup: PendingRollup) !void {
    const allocator = self.allocator;

    // jobs.transition {id, to_state:"visited", principal_kind:operator}
    // The visit_scheduled→visited Job edge needs no cap; in_process
    // root auth root-bypasses dispatcher cap-gating regardless.
    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(allocator);
    try args_buf.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, &args_buf, rollup.job_id);
    try args_buf.appendSlice(allocator, ",\"to_state\":\"" ++ TARGET_JOB_STATE ++ "\",\"principal_kind\":\"operator\"}");

    const ctx: dispatcher.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{
            .request_id = "visit_rollup",
            .transport_label = "visit_rollup",
        },
    };

    var result = self.disp.dispatch(&ctx, "jobs", "transition", args_buf.items) catch |err| {
        recordTransitionErr(self, rollup.visit_id, rollup.job_id, @errorName(err));
        return;
    };
    defer result.deinit();

    if (looksLikeErrorBody(result.payload)) {
        // Expected when the parent job isn't in visit_scheduled (the
        // only incoming edge to `visited`). Graceful audit-skip — the
        // visit completing doesn't always imply the job tracked the
        // pre-visit chain (e.g. a skip-path job, or one already
        // quoted). Not an error.
        recordTransitionRejected(self, rollup.visit_id, rollup.job_id, result.payload);
        return;
    }

    recordTransitionOk(self, rollup.visit_id, rollup.job_id);
}

// ─── Audit helpers ──────────────────────────────────────────────────

fn recordSkip(self: *Router, visit_id: []const u8, job_id: []const u8, reason: []const u8) void {
    const a = self.audit orelse return;
    var buf: [256]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=skip kind={s} visit_id={s} job_id={s}",
        .{ reason, visit_id, job_id },
    ) catch "phase=skip";
    a.record(self.allocator, .{
        .module = "visit_rollup",
        .op = "broker_event",
        .result = .denied,
        .detail = detail,
    }) catch {};
}

fn recordTransitionOk(self: *Router, visit_id: []const u8, job_id: []const u8) void {
    const a = self.audit orelse return;
    var buf: [256]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=transition kind=ok visit_id={s} job_id={s} to=" ++ TARGET_JOB_STATE,
        .{ visit_id, job_id },
    ) catch "phase=transition kind=ok";
    a.record(self.allocator, .{
        .module = "visit_rollup",
        .op = "tick",
        .result = .ok,
        .detail = detail,
    }) catch {};
}

fn recordTransitionErr(
    self: *Router,
    visit_id: []const u8,
    job_id: []const u8,
    err_name: []const u8,
) void {
    const a = self.audit orelse return;
    var buf: [320]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=transition kind=dispatch_err visit_id={s} job_id={s} err={s}",
        .{ visit_id, job_id, err_name },
    ) catch "phase=transition kind=dispatch_err";
    a.record(self.allocator, .{
        .module = "visit_rollup",
        .op = "tick",
        .result = .err,
        .detail = detail,
    }) catch {};
}

fn recordTransitionRejected(
    self: *Router,
    visit_id: []const u8,
    job_id: []const u8,
    body: []const u8,
) void {
    const a = self.audit orelse return;
    const max_body: usize = 64;
    const tail = if (body.len > max_body) body[0..max_body] else body;
    var buf: [320]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=transition kind=fsm_rejected visit_id={s} job_id={s} body={s}",
        .{ visit_id, job_id, tail },
    ) catch "phase=transition kind=fsm_rejected";
    a.record(self.allocator, .{
        .module = "visit_rollup",
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

test "jsonStringField extracts string fields, rejects non-strings" {
    const allocator = std.testing.allocator;
    const j = "{\"id\":\"v-1\",\"job_id\":\"j-9\",\"to\":\"completed\",\"n\":3}";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, j, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("v-1", jsonStringField(obj, "id").?);
    try std.testing.expectEqualStrings("j-9", jsonStringField(obj, "job_id").?);
    try std.testing.expectEqualStrings("completed", jsonStringField(obj, "to").?);
    try std.testing.expectEqual(@as(?[]const u8, null), jsonStringField(obj, "n"));
    try std.testing.expectEqual(@as(?[]const u8, null), jsonStringField(obj, "missing"));
}

test "looksLikeErrorBody distinguishes typed error from success" {
    // not_reachable / already-other: error body → audit-skip.
    try std.testing.expect(looksLikeErrorBody("{\"error\":\"not_reachable\",\"from\":\"quoted\"}"));
    // success transition body → roll-up recorded ok.
    try std.testing.expect(!looksLikeErrorBody("{\"id\":\"j-9\",\"state\":\"visited\"}"));
    // already_in_state returns a success-shaped body (no "error":) —
    // idempotent, treated as ok.
    try std.testing.expect(!looksLikeErrorBody("{\"status\":\"already_in_state\",\"job\":{\"state\":\"visited\"}}"));
}

test "constants pin the contract" {
    try std.testing.expectEqualStrings("visit.transitioned", EVENT_TYPE);
    try std.testing.expectEqualStrings("completed", TRIGGER_TO);
    try std.testing.expectEqualStrings("visited", TARGET_JOB_STATE);
}

```
