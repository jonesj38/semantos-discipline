---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/quote_seed_router.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.543547+00:00
---

# cartridges/oddjobz/brain/zig/src/quote_seed_router.zig

```zig
// ODDJOBZ-ESTIMATE-ROM-INGRESS Slice 4 — brain-side bridge from
// `job.transitioned` broker events into a seeded DRAFT Quote
// pre-filled from the job's accepted ROM Estimate.
//
// Reference: docs/design/ODDJOBZ-ESTIMATE-ROM-INGRESS.md §3.3.
//
// Cloned 1:1 from cartridges/oddjobz/brain/zig/src/visit_rollup_router.zig
//   (the proven subscribe → enqueue → tick → dispatch pattern this
//   mirrors, including the broker-reentrancy guardrail). Where
//   visit_rollup_router subscribes to `visit.transitioned` and
//   dispatches `jobs.transition`, this module subscribes to
//   `job.transitioned` and instead does an Estimate→Quote seed.
//
// What this module adds: when a Job takes the skip-path edge
// `qualified → quoted` (the operator quotes straight off the
// prequalified ROM), the most-recent accepted ROM Estimate for the
// job is read and a DRAFT Quote is auto-created from its cost_min /
// cost_max — so the operator never re-keys the ROM figure. This
// closes the ROM→Quote→outcome lineage the brief calls for.
//
// Flow:
//   1. jobs_handler.emitJobTransitioned applies a Job FSM transition
//      and publishes `job.transitioned`
//      {id, from, to, scheduled_at, transitioned_at} to the broker.
//   2. This subscriber's callback filters type=="job.transitioned"
//      AND from=="qualified" AND to=="quoted", dupes the job id, and
//      ENQUEUES (only). Every other job transition (incl.
//      visited→quoted, a from-scratch operator quote — NOT a ROM
//      carry-through) is ignored silently — no audit noise.
//   3. tick() (driven by the EventLoop poll, same site as the visit
//      rollup router) drains the queue and, for the job id:
//        a. quotes.find {job_id} — if a quote already exists, skip
//           (idempotent; do not double-seed).
//        b. estimates.find {job_id} — pick the most-recent estimate
//           whose ack_status=="accepted". None → graceful audit-skip
//           (operator quotes from scratch).
//        c. quotes.create {job_id, cost_min, cost_max, status:"draft",
//           notes:"seeded from auto_rom estimate <id>"} as
//           in_process_root.
//
// ─── Why queue + tick (not direct dispatch) ────────────────────────
//
// Identical reasoning to visit_rollup_router: the broker holds a
// non-reentrant mutex while fanning out to subscribers; jobs_handler
// publishes `job.transitioned` from inside that fan-out, and
// quotes.create itself re-publishes `quote.created`. Dispatching from
// the callback would re-enter broker.publish and deadlock. The
// callback only enqueues; the dispatch happens later from the reactor
// tick where no broker mutex is held.
//
// ─── Safety guardrails ──────────────────────────────────────────────
//
//   • Shares the intent-action-router gate (serve.zig only constructs
//     this when the intent router is enabled — all three are
//     "automated broker→FSM advancement" subscribers; the systemd
//     unit already passes --enable-intent-action-router). The
//     in-process `enabled` field lets tests exercise the gate without
//     unsubscribing.
//
//   • Fires ONLY on from=="qualified" AND to=="quoted" (the
//     skip-path). Every other job transition is ignored silently —
//     no audit noise on the common path.
//
//   • No accepted Estimate / a quote already exists → graceful
//     audit-skip (no-op) rather than error: the operator simply
//     quotes from scratch as today.
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

/// Bounded pending-queue size. Jobs are quoted at human pace (a few
/// per day); 64 is far past any realistic reactor lag.
pub const MAX_PENDING: usize = 64;

/// The broker event we subscribe to and the trigger values. Only the
/// skip-path edge `qualified → quoted` seeds — see design §3.3.
pub const EVENT_TYPE = "job.transitioned";
pub const TRIGGER_FROM = "qualified";
pub const TRIGGER_TO = "quoted";

pub const RouterError = error{
    out_of_memory,
};

/// One entry in the pending queue. Owned strings — the broker's
/// payload slice is borrowed for the publish call only.
const PendingSeed = struct {
    job_id: []u8,

    fn deinit(self: *PendingSeed, allocator: std.mem.Allocator) void {
        allocator.free(self.job_id);
    }
};

/// Router state. Owned at the top of cmdServe so its address is
/// stable for the lifetime of the broker's subscriber list.
pub const Router = struct {
    allocator: std.mem.Allocator,
    /// Borrowed — the broker we subscribe to. Unsubscribed in deinit.
    broker: *helm_event_broker.Broker,
    /// Borrowed — `disp.dispatch(..., "quotes"/"estimates", ...)` is
    /// how we read the accepted Estimate and seed the draft Quote.
    /// Going through the dispatcher (not the handlers directly) means
    /// the audit pair, broker emit (`quote.created`), and any future
    /// gate run uniformly for seed-driven and human-driven creates.
    /// Called only from `tick` — NEVER from the broker callback
    /// (re-entry deadlock).
    disp: *dispatcher.Dispatcher,
    /// Optional audit log shared with the dispatcher.
    audit: ?*audit_log.AuditLog,
    /// Subscriber id; held so deinit can unsubscribe. null = not
    /// subscribed.
    sub_id: ?helm_event_broker.SubscriberId,
    /// FIFO queue filled by the broker callback, drained by tick.
    pending: std.ArrayList(PendingSeed),
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
        var to_process: std.ArrayList(PendingSeed) = .{};
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

        for (to_process.items) |seed| {
            processSeed(self, seed) catch |err| {
                if (self.audit) |a| {
                    var buf: [128]u8 = undefined;
                    const detail = std.fmt.bufPrint(
                        &buf,
                        "phase=seed kind=tick_err err={s}",
                        .{@errorName(err)},
                    ) catch "phase=seed kind=tick_err";
                    a.record(self.allocator, .{
                        .module = "quote_seed",
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
                "phase=seed kind=enqueue_err err={s}",
                .{@errorName(err)},
            ) catch "phase=seed kind=enqueue_err";
            a.record(self.allocator, .{
                .module = "quote_seed",
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
        recordSkip(self, "", "parse_failed");
        return;
    };
    defer parsed.deinit();
    if (parsed.value != .object) {
        recordSkip(self, "", "payload_not_object");
        return;
    }
    const obj = parsed.value.object;

    const from_state = jsonStringField(obj, "from") orelse {
        recordSkip(self, "", "missing_from");
        return;
    };
    const to_state = jsonStringField(obj, "to") orelse {
        recordSkip(self, "", "missing_to");
        return;
    };
    // Only the skip-path edge qualified→quoted seeds a quote from the
    // ROM. Every other job transition (incl. visited→quoted, a
    // from-scratch operator quote) is ignored silently — no audit
    // noise on the common path.
    if (!std.mem.eql(u8, from_state, TRIGGER_FROM)) return;
    if (!std.mem.eql(u8, to_state, TRIGGER_TO)) return;

    const job_id = jsonStringField(obj, "id") orelse {
        recordSkip(self, "", "missing_id");
        return;
    };
    if (job_id.len == 0) {
        recordSkip(self, "", "empty_id");
        return;
    }

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
                "phase=seed kind=queue_full evicted_job_id={s}",
                .{oldest.job_id},
            ) catch "phase=seed kind=queue_full";
            a.record(self.allocator, .{
                .module = "quote_seed",
                .op = "broker_event",
                .result = .denied,
                .detail = detail,
            }) catch {};
        }
        oldest.deinit(self.allocator);
    }

    try self.pending.append(self.allocator, .{
        .job_id = job_id_owned,
    });
}

// ─── Seed processing (drained by tick) ──────────────────────────────

fn processSeed(self: *Router, seed: PendingSeed) !void {
    const allocator = self.allocator;

    const ctx: dispatcher.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{
            .request_id = "quote_seed",
            .transport_label = "quote_seed",
        },
    };

    // (a) Idempotency guard — if a quote already exists for the job,
    // do not double-seed. quotes.find {job_id} returns a JSON array;
    // a non-empty array means at least one quote is on file.
    {
        var find_args: std.ArrayList(u8) = .{};
        defer find_args.deinit(allocator);
        try find_args.appendSlice(allocator, "{\"job_id\":");
        try writeJsonString(allocator, &find_args, seed.job_id);
        try find_args.append(allocator, '}');

        var q_result = self.disp.dispatch(&ctx, "quotes", "find", find_args.items) catch |err| {
            recordDispatchErr(self, seed.job_id, "quotes.find", @errorName(err));
            return;
        };
        defer q_result.deinit();

        if (looksLikeErrorBody(q_result.payload)) {
            recordRejected(self, seed.job_id, q_result.payload);
            return;
        }
        if (jsonArrayNonEmpty(allocator, q_result.payload)) {
            recordAlreadySeeded(self, seed.job_id);
            return;
        }
    }

    // (b) Look up the most-recent accepted Estimate for the job.
    // estimates.find {job_id} returns a JSON array; each element has
    // {id, job_id, estimate_type, cost_min, cost_max, ack_status,
    //  acknowledged_at, notes, created_at, updated_at}.
    var estimate_id: []u8 = &.{};
    var cost_min: i64 = 0;
    var cost_max: i64 = 0;
    var found_accepted = false;
    {
        var find_args: std.ArrayList(u8) = .{};
        defer find_args.deinit(allocator);
        try find_args.appendSlice(allocator, "{\"job_id\":");
        try writeJsonString(allocator, &find_args, seed.job_id);
        try find_args.append(allocator, '}');

        var e_result = self.disp.dispatch(&ctx, "estimates", "find", find_args.items) catch |err| {
            recordDispatchErr(self, seed.job_id, "estimates.find", @errorName(err));
            return;
        };
        defer e_result.deinit();

        if (looksLikeErrorBody(e_result.payload)) {
            recordRejected(self, seed.job_id, e_result.payload);
            return;
        }

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, e_result.payload, .{}) catch {
            recordSkip(self, seed.job_id, "estimates_parse_failed");
            return;
        };
        defer parsed.deinit();
        if (parsed.value != .array) {
            recordSkip(self, seed.job_id, "estimates_not_array");
            return;
        }

        // Pick the most-recent accepted estimate. Prefer the largest
        // created_at (ISO-8601 is lexicographically orderable); ties /
        // missing timestamps fall back to the last accepted in array
        // order.
        var best_created_at: []const u8 = &.{};
        for (parsed.value.array.items) |row| {
            if (row != .object) continue;
            const o = row.object;
            const ack = jsonStringField(o, "ack_status") orelse continue;
            if (!std.mem.eql(u8, ack, "accepted")) continue;
            const this_created_at = jsonStringField(o, "created_at") orelse "";
            // First accepted always wins initially; thereafter keep
            // the row with the lexicographically-greatest created_at.
            if (found_accepted and std.mem.order(u8, this_created_at, best_created_at) == .lt) continue;

            const cmin = jsonIntField(o, "cost_min") orelse 0;
            const cmax = jsonIntField(o, "cost_max") orelse 0;
            const eid = jsonStringField(o, "id") orelse "";

            const eid_owned = try allocator.dupe(u8, eid);
            if (estimate_id.len != 0) allocator.free(estimate_id);
            estimate_id = eid_owned;
            cost_min = cmin;
            cost_max = cmax;
            best_created_at = this_created_at;
            found_accepted = true;
        }
    }
    defer if (estimate_id.len != 0) allocator.free(estimate_id);

    if (!found_accepted) {
        // Graceful no-op: no accepted ROM Estimate on file. The
        // operator simply quotes from scratch as today.
        recordNoAcceptedEstimate(self, seed.job_id);
        return;
    }

    // (c) Seed the DRAFT Quote from the accepted Estimate's cost
    // bounds. in_process_root root-bypasses dispatcher cap-gating.
    var create_args: std.ArrayList(u8) = .{};
    defer create_args.deinit(allocator);
    try create_args.appendSlice(allocator, "{\"job_id\":");
    try writeJsonString(allocator, &create_args, seed.job_id);
    try create_args.print(allocator, ",\"cost_min\":{d},\"cost_max\":{d}", .{ cost_min, cost_max });
    try create_args.appendSlice(allocator, ",\"status\":\"draft\",\"notes\":");
    {
        var notes_buf: std.ArrayList(u8) = .{};
        defer notes_buf.deinit(allocator);
        try notes_buf.appendSlice(allocator, "seeded from auto_rom estimate ");
        try notes_buf.appendSlice(allocator, estimate_id);
        try writeJsonString(allocator, &create_args, notes_buf.items);
    }
    try create_args.append(allocator, '}');

    var c_result = self.disp.dispatch(&ctx, "quotes", "create", create_args.items) catch |err| {
        recordDispatchErr(self, seed.job_id, "quotes.create", @errorName(err));
        return;
    };
    defer c_result.deinit();

    if (looksLikeErrorBody(c_result.payload)) {
        recordRejected(self, seed.job_id, c_result.payload);
        return;
    }

    recordSeedOk(self, seed.job_id, estimate_id, cost_min, cost_max);
}

// ─── Audit helpers ──────────────────────────────────────────────────

fn recordSkip(self: *Router, job_id: []const u8, reason: []const u8) void {
    const a = self.audit orelse return;
    var buf: [256]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=seed kind={s} job_id={s}",
        .{ reason, job_id },
    ) catch "phase=seed kind=skip";
    a.record(self.allocator, .{
        .module = "quote_seed",
        .op = "broker_event",
        .result = .denied,
        .detail = detail,
    }) catch {};
}

fn recordAlreadySeeded(self: *Router, job_id: []const u8) void {
    const a = self.audit orelse return;
    var buf: [256]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=seed kind=already_seeded job_id={s}",
        .{job_id},
    ) catch "phase=seed kind=already_seeded";
    a.record(self.allocator, .{
        .module = "quote_seed",
        .op = "tick",
        .result = .denied,
        .detail = detail,
    }) catch {};
}

fn recordNoAcceptedEstimate(self: *Router, job_id: []const u8) void {
    const a = self.audit orelse return;
    var buf: [256]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=seed kind=no_accepted_estimate job_id={s}",
        .{job_id},
    ) catch "phase=seed kind=no_accepted_estimate";
    a.record(self.allocator, .{
        .module = "quote_seed",
        .op = "tick",
        .result = .denied,
        .detail = detail,
    }) catch {};
}

fn recordSeedOk(
    self: *Router,
    job_id: []const u8,
    estimate_id: []const u8,
    cost_min: i64,
    cost_max: i64,
) void {
    const a = self.audit orelse return;
    var buf: [320]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=seed kind=ok job_id={s} estimate_id={s} cost_min={d} cost_max={d}",
        .{ job_id, estimate_id, cost_min, cost_max },
    ) catch "phase=seed kind=ok";
    a.record(self.allocator, .{
        .module = "quote_seed",
        .op = "tick",
        .result = .ok,
        .detail = detail,
    }) catch {};
}

fn recordDispatchErr(
    self: *Router,
    job_id: []const u8,
    op: []const u8,
    err_name: []const u8,
) void {
    const a = self.audit orelse return;
    var buf: [320]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=seed kind=dispatch_err job_id={s} op={s} err={s}",
        .{ job_id, op, err_name },
    ) catch "phase=seed kind=dispatch_err";
    a.record(self.allocator, .{
        .module = "quote_seed",
        .op = "tick",
        .result = .err,
        .detail = detail,
    }) catch {};
}

fn recordRejected(
    self: *Router,
    job_id: []const u8,
    body: []const u8,
) void {
    const a = self.audit orelse return;
    const max_body: usize = 64;
    const tail = if (body.len > max_body) body[0..max_body] else body;
    var buf: [320]u8 = undefined;
    const detail = std.fmt.bufPrint(
        &buf,
        "phase=seed kind=rejected job_id={s} body={s}",
        .{ job_id, tail },
    ) catch "phase=seed kind=rejected";
    a.record(self.allocator, .{
        .module = "quote_seed",
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

fn jsonIntField(obj: std.json.ObjectMap, key: []const u8) ?i64 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => null,
    };
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

fn looksLikeErrorBody(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "\"error\":") != null;
}

/// True when `body` parses as a non-empty JSON array. A bare `[]`
/// (no quotes existing for the job) is empty; anything with an
/// element is non-empty.
fn jsonArrayNonEmpty(allocator: std.mem.Allocator, body: []const u8) bool {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .array) return false;
    return parsed.value.array.items.len > 0;
}

// ─── Inline tests — pure helpers ─────────────────────────────────────

test "jsonStringField extracts string fields, rejects non-strings" {
    const allocator = std.testing.allocator;
    const j = "{\"id\":\"j-1\",\"from\":\"qualified\",\"to\":\"quoted\",\"n\":3}";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, j, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("j-1", jsonStringField(obj, "id").?);
    try std.testing.expectEqualStrings("qualified", jsonStringField(obj, "from").?);
    try std.testing.expectEqualStrings("quoted", jsonStringField(obj, "to").?);
    try std.testing.expectEqual(@as(?[]const u8, null), jsonStringField(obj, "n"));
    try std.testing.expectEqual(@as(?[]const u8, null), jsonStringField(obj, "missing"));
}

test "jsonIntField extracts integer/float, rejects others" {
    const allocator = std.testing.allocator;
    const j = "{\"cost_min\":5000,\"cost_max\":20000.0,\"s\":\"x\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, j, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try std.testing.expectEqual(@as(?i64, 5000), jsonIntField(obj, "cost_min"));
    try std.testing.expectEqual(@as(?i64, 20000), jsonIntField(obj, "cost_max"));
    try std.testing.expectEqual(@as(?i64, null), jsonIntField(obj, "s"));
    try std.testing.expectEqual(@as(?i64, null), jsonIntField(obj, "missing"));
}

test "looksLikeErrorBody distinguishes typed error from success" {
    try std.testing.expect(looksLikeErrorBody("{\"error\":\"job_not_found\",\"job_id\":\"j-9\"}"));
    try std.testing.expect(!looksLikeErrorBody("{\"id\":\"q-1\",\"status\":\"created\"}"));
    try std.testing.expect(!looksLikeErrorBody("[]"));
}

test "jsonArrayNonEmpty detects a populated quotes.find array" {
    const allocator = std.testing.allocator;
    try std.testing.expect(!jsonArrayNonEmpty(allocator, "[]"));
    try std.testing.expect(jsonArrayNonEmpty(allocator, "[{\"id\":\"q-1\"}]"));
    // Not an array (typed error body) → treated as "no existing quote"
    // so the find-failure path is handled separately by the caller.
    try std.testing.expect(!jsonArrayNonEmpty(allocator, "{\"error\":\"x\"}"));
}

test "constants pin the contract" {
    try std.testing.expectEqualStrings("job.transitioned", EVENT_TYPE);
    try std.testing.expectEqualStrings("qualified", TRIGGER_FROM);
    try std.testing.expectEqualStrings("quoted", TRIGGER_TO);
}

```
