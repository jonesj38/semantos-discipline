---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/helm_event_broker.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.234744+00:00
---

# runtime/semantos-brain/src/helm_event_broker.zig

```zig
// D-O5.followup-4 — In-process publish/subscribe broker for live helm
// events.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5 (live helm
// substrate); docs/operator-runbooks/push-architecture.md
// (sovereign-push D.1 wake-only flow).
//
// One process-scoped Broker is constructed once at boot (cli.zig
// `cmdRepl` / `cmdServe`) and shared by:
//
//   • wss_wallet.zig — the helm.subscribe RPC registers a per-WSS-
//     connection Subscriber whose callback writes a JSON-RPC
//     notification frame back to the client.  wss_wallet's
//     helm.fetch_since RPC reads the broker's recent-event ring
//     buffer to backfill events that fired while the device was
//     offline.
//   • resources/jobs_handler.zig — after a successful jobs.transition
//     the handler calls `broker.publish` with type="job.transitioned"
//     and a JSON payload of {id, from, to, transitioned_at}.
//
// Substrate scope (this PR): only jobs_handler emits.  Other emitters
// (customers / visits / quotes / invoices / attachments) land in
// followup PRs — adding them is mechanical (just `broker.publish` after
// the store-write).
//
// ─── Threading model ─────────────────────────────────────────────────
//
// publish / subscribe / unsubscribe are mutex-serialised against each
// other.  The mutex is held for the duration of `publish` so a
// subscriber added concurrently with a publish either receives the
// event in full or doesn't see it at all (no torn read).  Callbacks
// themselves are invoked inside the mutex; the contract is that they
// MUST be fast (a single per-connection write-queue push or a single
// stream.writeAll).  Long-running callbacks block other publishers and
// are the subscriber's bug.
//
// Subscriber callbacks receive a borrowed `Event` whose `payload_json`
// slice is owned by the caller of `publish` and lives only for the
// duration of the dispatch.  A subscriber that needs to outlive the
// callback must copy.
//
// ─── Sovereign-push D.1 — wake-only push pipeline ───────────────────
//
// When `event.requires_operator_attention == true` and an optional
// PushHook is wired onto the broker (`setPushHook`), the broker fans
// the event out as a WAKE-ONLY push: the hook receives only an
// opaque envelope (event_id + ts + kind) — NO operator-readable
// title, body, or data fields.  The device decodes the envelope on
// wake and fetches actual event content via WSS using the
// `helm.fetch_since` RPC.
//
// This is the architectural property D.1 introduces: Google/Apple
// stay in the wake-up loop (they have to — OS-level) but they never
// see operator content.  The previous `titleForEvent` /
// `bodyForEvent` helpers that composed human-readable summaries
// have been removed; that text now belongs entirely on-device.
//
// ─── Recent-event ring buffer (D.1) ─────────────────────────────────
//
// Every published event is also stored in a bounded in-memory ring
// buffer keyed by `(event_id, ts)`.  The wss_wallet `helm.fetch_since`
// RPC iterates this buffer to serve a device that just woke up.
// The buffer caps memory at MAX_RECENT_EVENTS entries (oldest evicted
// first); a device offline longer than that window misses events
// (acceptable for v0.1 — D.2 may persist to disk).

const std = @import("std");

/// Bounded number of recent events kept in memory for `helm.fetch_since`.
/// Each entry copies the event_id + payload_json so the broker can
/// outlive the publishing handler's stack-borrowed slices.  Sized
/// for ~24h of medium-volume helm activity at the v0.1 push budget;
/// older events fall off the back as new ones arrive.
pub const MAX_RECENT_EVENTS: usize = 1024;

pub const Event = struct {
    /// Stable event-type token, e.g. "job.transitioned".  Borrowed.
    type: []const u8,
    /// Already-encoded JSON object body (without the surrounding
    /// envelope) — e.g. `{"id":"job-001","from":"lead","to":"quoted",
    /// "transitioned_at":"2026-05-02T14:30:00Z"}`.  Borrowed for the
    /// duration of `publish`.
    payload_json: []const u8,
    /// D-O5m.followup-9 Phase A — true when this event should bubble
    /// up to the operator as a push notification (the device is
    /// expected to surface a banner / badge / alert).  Sovereign-
    /// push D.1: when true the broker fires the wake-only push hook
    /// that carries ONLY (event_id, ts, kind) — never operator
    /// content.
    ///
    /// Today's emit sites set this to true for `lead.created` (when a
    /// chat lead extraction queues a lead) and `job.transitioned` to
    /// state `lead`.  All other emits leave the default `false`.
    requires_operator_attention: bool = false,
    /// D.1 — broker-assigned monotonic event id.  Set by `publish`;
    /// callers leave the default.  Format: 16 hex chars (i64 in hex).
    event_id: [16]u8 = [_]u8{'0'} ** 16,
    /// D.1 — broker-assigned wall-clock timestamp at publish time
    /// (unix seconds).  Set by `publish`.
    ts: i64 = 0,
};

pub const SubscriberId = u64;

pub const SubscribeError = error{
    out_of_memory,
};

/// A single subscriber's contract.  `callback` is invoked synchronously
/// inside `publish` on every event the broker fans out; the callback
/// MUST be fast (a write-queue push or a single stream.writeAll —
/// nothing that can block).  `state` is an opaque pointer the
/// subscriber owns; the broker only forwards it.
pub const Subscriber = struct {
    /// Subscriber-owned context pointer.
    state: ?*anyopaque,
    /// Invoked once per `publish`, inside the broker's mutex.
    callback: *const fn (state: ?*anyopaque, event: Event) void,
};

/// Sovereign-push D.1 — wake-only push-dispatch hook.  The broker
/// invokes this when `event.requires_operator_attention == true`.
///
/// `send_fn` receives ONLY the opaque envelope (event_id + ts + kind),
/// already serialised as `payload_json`.  The hook implementation
/// (typically the cli's PushBrokerBridge) is responsible for forwarding
/// it through APNs/FCM as a wake-only payload — no title, no body, no
/// data merge.  The device opens its WSS on wake and fetches the
/// real event via `helm.fetch_since`.
pub const PushHook = struct {
    state: ?*anyopaque,
    /// Resolve the set of cert ids that should receive a push for
    /// this event.  Returns an alloc-owned slice the broker frees.
    /// Empty → no push fans out (still cheap).
    resolve_fn: *const fn (
        state: ?*anyopaque,
        allocator: std.mem.Allocator,
        event: Event,
    ) []const []const u8,
    /// Free the slice returned by `resolve_fn`.  Owned-side
    /// symmetry: the resolver allocs, the freer frees.
    free_fn: *const fn (
        state: ?*anyopaque,
        allocator: std.mem.Allocator,
        cert_ids: []const []const u8,
    ) void,
    /// Send a wake-only push to every cert in the slice.  `payload_json`
    /// is the opaque envelope `{"event_id":"...","ts":<int>,"kind":"<tok>"}`.
    /// Best-effort — the hook implementation logs failures but never
    /// errors back to the broker.
    send_fn: *const fn (
        state: ?*anyopaque,
        cert_ids: []const []const u8,
        payload_json: []const u8,
    ) void,
};

/// One entry in the broker's recent-event ring.  Fully self-owned so
/// it can outlive the publishing handler's stack-borrowed slices.
const RecentEvent = struct {
    event_id: [16]u8,
    ts: i64,
    type_owned: []u8,
    payload_owned: []u8,

    fn deinit(self: *RecentEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.type_owned);
        allocator.free(self.payload_owned);
    }
};

/// One element of the JSON array `helm.fetch_since` returns.  Borrowed
/// from the broker's ring buffer; the caller copies before releasing
/// the broker's mutex.
pub const FetchedEvent = struct {
    event_id: [16]u8,
    ts: i64,
    type: []const u8,
    payload_json: []const u8,
};

pub const Broker = struct {
    allocator: std.mem.Allocator,
    mu: std.Thread.Mutex,
    next_id: SubscriberId,
    /// Monotonic counter for event_id assignment.  Starts at 1 so a
    /// `since_ts` filter of 0 matches everything in the ring.
    next_event_seq: u64,
    subs: std.ArrayList(Entry),
    /// D.1 — bounded ring of recent events for `helm.fetch_since`.
    /// Implemented as an ArrayList capped at MAX_RECENT_EVENTS;
    /// when full, the oldest entry is evicted on the next push.
    recent: std.ArrayList(RecentEvent),
    /// Sovereign-push D.1 — optional wake-only push hook.  Null = no
    /// push fans out (legacy / push-disabled deployment).
    push_hook: ?PushHook,
    /// Pinned-clock for tests; defaults to wall-clock seconds.
    clock_fn: *const fn () i64,

    const Entry = struct {
        id: SubscriberId,
        sub: Subscriber,
    };

    pub fn init(allocator: std.mem.Allocator) Broker {
        return .{
            .allocator = allocator,
            .mu = .{},
            .next_id = 1,
            .next_event_seq = 1,
            .subs = .{},
            .recent = .{},
            .push_hook = null,
            .clock_fn = defaultClock,
        };
    }

    pub fn deinit(self: *Broker) void {
        self.subs.deinit(self.allocator);
        for (self.recent.items) |*r| r.deinit(self.allocator);
        self.recent.deinit(self.allocator);
    }

    /// Override the wall-clock for deterministic tests.
    pub fn setClockFn(self: *Broker, f: *const fn () i64) void {
        self.clock_fn = f;
    }

    /// Wire the wake-only push-dispatch hook.  The hook lives at
    /// least as long as the broker.  Idempotent — last call wins;
    /// pass null to clear.
    pub fn setPushHook(self: *Broker, hook: ?PushHook) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.push_hook = hook;
    }

    /// Register a subscriber.  Returns a handle the caller passes to
    /// `unsubscribe` on connection close.
    pub fn subscribe(self: *Broker, sub: Subscriber) SubscribeError!SubscriberId {
        self.mu.lock();
        defer self.mu.unlock();
        const id = self.next_id;
        self.next_id += 1;
        self.subs.append(self.allocator, .{ .id = id, .sub = sub }) catch return error.out_of_memory;
        return id;
    }

    /// Remove a subscriber by id.  Idempotent — repeated calls are
    /// cheap and silent.
    pub fn unsubscribe(self: *Broker, id: SubscriberId) void {
        self.mu.lock();
        defer self.mu.unlock();
        var i: usize = 0;
        while (i < self.subs.items.len) : (i += 1) {
            if (self.subs.items[i].id == id) {
                _ = self.subs.orderedRemove(i);
                return;
            }
        }
    }

    /// Fan out one event to every current subscriber, store it in
    /// the recent-event ring, and (if requires_operator_attention)
    /// fire the wake-only push hook.  Synchronous — returns when the
    /// last callback returns.  Callbacks MUST be fast (see
    /// `Subscriber` doc-comment).
    ///
    /// The broker assigns `event.event_id` and `event.ts` here; any
    /// values the caller put on the struct are overwritten.
    pub fn publish(self: *Broker, event: Event) void {
        self.mu.lock();
        defer self.mu.unlock();

        // Assign broker-side identity + timestamp so subscribers and
        // the recent ring all see the same correlatable shape.
        var stamped = event;
        stamped.event_id = encodeEventId(self.next_event_seq);
        stamped.ts = self.clock_fn();
        self.next_event_seq += 1;

        // Fan out to live subscribers first.
        for (self.subs.items) |entry| {
            entry.sub.callback(entry.sub.state, stamped);
        }

        // Persist into the recent ring (best-effort — OOM drops).
        self.appendRecent(stamped) catch {};

        // Sovereign-push D.1 — fire the wake-only hook for events
        // that require operator attention.  The hook does its own
        // audit-logging of failures; we treat this as best-effort
        // and never fail the publish.
        if (stamped.requires_operator_attention and self.push_hook != null) {
            const hook = self.push_hook.?;
            const cert_ids = hook.resolve_fn(hook.state, self.allocator, stamped);
            defer hook.free_fn(hook.state, self.allocator, cert_ids);
            if (cert_ids.len == 0) return;

            // Build the opaque envelope.  Only event_id + ts + kind
            // — NEVER any operator content.
            var envelope_buf: [128]u8 = undefined;
            const envelope = std.fmt.bufPrint(
                &envelope_buf,
                "{{\"event_id\":\"{s}\",\"ts\":{d},\"kind\":\"helm.event\"}}",
                .{ &stamped.event_id, stamped.ts },
            ) catch return;
            hook.send_fn(hook.state, cert_ids, envelope);
        }
    }

    /// D.1 — read events from the recent-event ring with `ts > since_ts`.
    /// Caps at `limit` (caller-side responsibility to clamp).  Output
    /// slice is allocated; caller frees.  The `payload_json` and
    /// `type` slices inside each entry are borrowed from the broker's
    /// ring buffer and remain valid until the next mutation; the
    /// caller copies before releasing the held mutex (this method
    /// holds the broker mutex for the duration; callers should
    /// dupe out of it before doing anything that may block).
    ///
    /// `next_cursor_ts` (out param) is set to the last returned
    /// event's ts (or `since_ts` if no events matched), enabling the
    /// device to paginate forward.
    pub fn fetchSince(
        self: *Broker,
        allocator: std.mem.Allocator,
        since_ts: i64,
        limit: usize,
        next_cursor_ts_out: *i64,
    ) ![]FetchedEvent {
        self.mu.lock();
        defer self.mu.unlock();

        var matches: usize = 0;
        for (self.recent.items) |r| if (r.ts > since_ts) {
            matches += 1;
        };
        const out_len = @min(matches, limit);
        if (out_len == 0) {
            next_cursor_ts_out.* = since_ts;
            return try allocator.alloc(FetchedEvent, 0);
        }

        const out = try allocator.alloc(FetchedEvent, out_len);
        var idx: usize = 0;
        for (self.recent.items) |r| {
            if (idx >= out_len) break;
            if (r.ts <= since_ts) continue;
            out[idx] = .{
                .event_id = r.event_id,
                .ts = r.ts,
                .type = r.type_owned,
                .payload_json = r.payload_owned,
            };
            idx += 1;
        }
        next_cursor_ts_out.* = out[out_len - 1].ts;
        return out;
    }

    /// Visible for tests — exposes the push-hook field.
    pub fn hasPushHook(self: *Broker) bool {
        self.mu.lock();
        defer self.mu.unlock();
        return self.push_hook != null;
    }

    /// Test-only diagnostic — number of registered subscribers.
    pub fn subscriberCount(self: *Broker) usize {
        self.mu.lock();
        defer self.mu.unlock();
        return self.subs.items.len;
    }

    /// Test-only diagnostic — number of events stored in the ring.
    pub fn recentCount(self: *Broker) usize {
        self.mu.lock();
        defer self.mu.unlock();
        return self.recent.items.len;
    }

    fn appendRecent(self: *Broker, event: Event) !void {
        // Evict the oldest entry if the ring is full.
        if (self.recent.items.len >= MAX_RECENT_EVENTS) {
            var oldest = self.recent.orderedRemove(0);
            oldest.deinit(self.allocator);
        }
        const type_owned = try self.allocator.dupe(u8, event.type);
        errdefer self.allocator.free(type_owned);
        const payload_owned = try self.allocator.dupe(u8, event.payload_json);
        errdefer self.allocator.free(payload_owned);
        try self.recent.append(self.allocator, .{
            .event_id = event.event_id,
            .ts = event.ts,
            .type_owned = type_owned,
            .payload_owned = payload_owned,
        });
    }
};

// ─── Helpers ─────────────────────────────────────────────────────────

/// Render a 16-char lowercase hex representation of the monotonic
/// event sequence number.  16 chars covers a full u64; the broker's
/// counter starts at 1 so `event_id == "0000000000000000"` is
/// reserved as the "unset" sentinel.
fn encodeEventId(seq: u64) [16]u8 {
    var out: [16]u8 = undefined;
    const hex = "0123456789abcdef";
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const shift: u6 = @intCast((15 - i) * 4);
        out[i] = hex[(seq >> shift) & 0xf];
    }
    return out;
}

fn defaultClock() i64 {
    return std.time.timestamp();
}

// ─── Tests ───────────────────────────────────────────────────────────

const TestSink = struct {
    /// Captured (type, payload) pairs — owned strings so the borrowed
    /// Event slices can be released without disturbing assertions.
    types: std.ArrayList([]u8),
    payloads: std.ArrayList([]u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) TestSink {
        return .{
            .types = .{},
            .payloads = .{},
            .allocator = allocator,
        };
    }

    fn deinit(self: *TestSink) void {
        for (self.types.items) |s| self.allocator.free(s);
        for (self.payloads.items) |s| self.allocator.free(s);
        self.types.deinit(self.allocator);
        self.payloads.deinit(self.allocator);
    }

    fn callback(state: ?*anyopaque, event: Event) void {
        const self: *TestSink = @ptrCast(@alignCast(state.?));
        const t = self.allocator.dupe(u8, event.type) catch return;
        const p = self.allocator.dupe(u8, event.payload_json) catch {
            self.allocator.free(t);
            return;
        };
        self.types.append(self.allocator, t) catch {
            self.allocator.free(t);
            self.allocator.free(p);
            return;
        };
        self.payloads.append(self.allocator, p) catch {
            self.allocator.free(p);
            return;
        };
    }
};

fn pinnedClockFn() i64 {
    return 1_700_000_000;
}

test "broker: subscribe + publish delivers event to single subscriber" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    defer broker.deinit();

    var sink = TestSink.init(allocator);
    defer sink.deinit();

    _ = try broker.subscribe(.{ .state = &sink, .callback = TestSink.callback });
    broker.publish(.{ .type = "job.transitioned", .payload_json = "{\"id\":\"job-001\"}" });

    try std.testing.expectEqual(@as(usize, 1), sink.types.items.len);
    try std.testing.expectEqualStrings("job.transitioned", sink.types.items[0]);
    try std.testing.expectEqualStrings("{\"id\":\"job-001\"}", sink.payloads.items[0]);
}

test "broker: publish fans out to multiple subscribers in order" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    defer broker.deinit();

    var sink_a = TestSink.init(allocator);
    defer sink_a.deinit();
    var sink_b = TestSink.init(allocator);
    defer sink_b.deinit();
    var sink_c = TestSink.init(allocator);
    defer sink_c.deinit();

    _ = try broker.subscribe(.{ .state = &sink_a, .callback = TestSink.callback });
    _ = try broker.subscribe(.{ .state = &sink_b, .callback = TestSink.callback });
    _ = try broker.subscribe(.{ .state = &sink_c, .callback = TestSink.callback });

    broker.publish(.{ .type = "job.transitioned", .payload_json = "{\"to\":\"quoted\"}" });

    try std.testing.expectEqual(@as(usize, 1), sink_a.types.items.len);
    try std.testing.expectEqual(@as(usize, 1), sink_b.types.items.len);
    try std.testing.expectEqual(@as(usize, 1), sink_c.types.items.len);
    try std.testing.expectEqualStrings("job.transitioned", sink_a.types.items[0]);
    try std.testing.expectEqualStrings("job.transitioned", sink_b.types.items[0]);
    try std.testing.expectEqualStrings("job.transitioned", sink_c.types.items[0]);
}

test "broker: unsubscribe removes the subscriber" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    defer broker.deinit();

    var sink_a = TestSink.init(allocator);
    defer sink_a.deinit();
    var sink_b = TestSink.init(allocator);
    defer sink_b.deinit();

    const id_a = try broker.subscribe(.{ .state = &sink_a, .callback = TestSink.callback });
    _ = try broker.subscribe(.{ .state = &sink_b, .callback = TestSink.callback });

    try std.testing.expectEqual(@as(usize, 2), broker.subscriberCount());
    broker.unsubscribe(id_a);
    try std.testing.expectEqual(@as(usize, 1), broker.subscriberCount());

    broker.publish(.{ .type = "job.transitioned", .payload_json = "{}" });
    // sink_a is gone; sink_b receives the event.
    try std.testing.expectEqual(@as(usize, 0), sink_a.types.items.len);
    try std.testing.expectEqual(@as(usize, 1), sink_b.types.items.len);
}

test "broker: unsubscribe with unknown id is a no-op" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    defer broker.deinit();

    var sink = TestSink.init(allocator);
    defer sink.deinit();
    _ = try broker.subscribe(.{ .state = &sink, .callback = TestSink.callback });

    broker.unsubscribe(99_999);
    try std.testing.expectEqual(@as(usize, 1), broker.subscriberCount());
}

test "broker: publish on empty subscriber list is a no-op (still rings)" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    defer broker.deinit();
    broker.publish(.{ .type = "job.transitioned", .payload_json = "{}" });
    // Recent ring still records the event for fetch_since.
    try std.testing.expectEqual(@as(usize, 1), broker.recentCount());
}

test "broker: subscriber ids are monotonic + unique" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    defer broker.deinit();

    var sink = TestSink.init(allocator);
    defer sink.deinit();

    const id_a = try broker.subscribe(.{ .state = &sink, .callback = TestSink.callback });
    const id_b = try broker.subscribe(.{ .state = &sink, .callback = TestSink.callback });
    const id_c = try broker.subscribe(.{ .state = &sink, .callback = TestSink.callback });
    try std.testing.expect(id_a < id_b);
    try std.testing.expect(id_b < id_c);
}

// D-O5m.followup-9 Phase A — sink that captures the
// `requires_operator_attention` flag alongside (type, payload).
const AttentionSink = struct {
    last_attention: bool,
    received: usize,

    fn callback(state: ?*anyopaque, event: Event) void {
        const self: *AttentionSink = @ptrCast(@alignCast(state.?));
        self.last_attention = event.requires_operator_attention;
        self.received += 1;
    }
};

test "broker: requires_operator_attention default-false round-trips through publish" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    defer broker.deinit();
    var sink: AttentionSink = .{ .last_attention = false, .received = 0 };
    _ = try broker.subscribe(.{ .state = &sink, .callback = AttentionSink.callback });

    // No requires_operator_attention specified — defaults to false.
    broker.publish(.{ .type = "customer.upserted", .payload_json = "{}" });
    try std.testing.expectEqual(@as(usize, 1), sink.received);
    try std.testing.expectEqual(false, sink.last_attention);
}

test "broker: requires_operator_attention=true round-trips to subscriber" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    defer broker.deinit();
    var sink: AttentionSink = .{ .last_attention = false, .received = 0 };
    _ = try broker.subscribe(.{ .state = &sink, .callback = AttentionSink.callback });

    // Mirrors the shape jobs_handler emits when a job transitions into
    // the `lead` state (D-O5m.followup-9 Phase A).
    broker.publish(.{
        .type = "job.transitioned",
        .payload_json = "{\"to\":\"lead\"}",
        .requires_operator_attention = true,
    });
    try std.testing.expectEqual(@as(usize, 1), sink.received);
    try std.testing.expectEqual(true, sink.last_attention);
}

test "broker: lifecycle — init, subscribe, publish, unsubscribe, deinit" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    var sink = TestSink.init(allocator);
    defer sink.deinit();

    const id = try broker.subscribe(.{ .state = &sink, .callback = TestSink.callback });
    broker.publish(.{ .type = "job.transitioned", .payload_json = "{}" });
    broker.unsubscribe(id);
    broker.deinit();
    try std.testing.expectEqual(@as(usize, 1), sink.types.items.len);
}

// ─── Sovereign-push D.1 — wake-only push hook coverage ──────────────

const PushSink = struct {
    received: usize = 0,
    last_count: usize = 0,
    last_payload: [256]u8 = undefined,
    last_payload_len: usize = 0,

    fn resolve(state: ?*anyopaque, allocator: std.mem.Allocator, event: Event) []const []const u8 {
        _ = state;
        _ = event;
        // Return a single fixed cert id — owns its slice; freed in `free`.
        const slice = allocator.alloc([]const u8, 1) catch return &.{};
        slice[0] = "deadbeefcafe0000deadbeefcafe0000";
        return slice;
    }

    fn free(state: ?*anyopaque, allocator: std.mem.Allocator, cert_ids: []const []const u8) void {
        _ = state;
        if (cert_ids.len > 0) allocator.free(cert_ids);
    }

    fn send(state: ?*anyopaque, cert_ids: []const []const u8, payload_json: []const u8) void {
        const self: *PushSink = @ptrCast(@alignCast(state.?));
        self.received += 1;
        self.last_count = cert_ids.len;
        if (payload_json.len <= self.last_payload.len) {
            @memcpy(self.last_payload[0..payload_json.len], payload_json);
            self.last_payload_len = payload_json.len;
        }
    }
};

test "broker: wake-only push hook fires when requires_operator_attention=true" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    broker.setClockFn(pinnedClockFn);
    defer broker.deinit();

    var ps: PushSink = .{};
    broker.setPushHook(.{
        .state = &ps,
        .resolve_fn = PushSink.resolve,
        .free_fn = PushSink.free,
        .send_fn = PushSink.send,
    });

    broker.publish(.{
        .type = "lead.created",
        .payload_json = "{\"customer_name\":\"Alice\",\"summary\":\"roof repair\",\"lead_id\":\"L1\"}",
        .requires_operator_attention = true,
    });
    try std.testing.expectEqual(@as(usize, 1), ps.received);
    try std.testing.expectEqual(@as(usize, 1), ps.last_count);

    // The envelope is opaque — only event_id + ts + kind, NEVER any
    // operator content from the payload.
    const got = ps.last_payload[0..ps.last_payload_len];
    try std.testing.expectEqualStrings(
        "{\"event_id\":\"0000000000000001\",\"ts\":1700000000,\"kind\":\"helm.event\"}",
        got,
    );
    // Defence-in-depth: the operator's actual content must NOT appear.
    try std.testing.expect(std.mem.indexOf(u8, got, "Alice") == null);
    try std.testing.expect(std.mem.indexOf(u8, got, "roof repair") == null);
    try std.testing.expect(std.mem.indexOf(u8, got, "customer_name") == null);
    try std.testing.expect(std.mem.indexOf(u8, got, "summary") == null);
    try std.testing.expect(std.mem.indexOf(u8, got, "lead_id") == null);
    try std.testing.expect(std.mem.indexOf(u8, got, "L1") == null);
    try std.testing.expect(std.mem.indexOf(u8, got, "lead.created") == null);
}

test "broker: push hook does NOT fire when requires_operator_attention=false" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    defer broker.deinit();

    var ps: PushSink = .{};
    broker.setPushHook(.{
        .state = &ps,
        .resolve_fn = PushSink.resolve,
        .free_fn = PushSink.free,
        .send_fn = PushSink.send,
    });

    broker.publish(.{
        .type = "customer.upserted",
        .payload_json = "{}",
        .requires_operator_attention = false,
    });
    try std.testing.expectEqual(@as(usize, 0), ps.received);
}

test "broker: push hook resolver returning empty skips the send" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    defer broker.deinit();

    var ps: PushSink = .{};
    const EmptyHook = struct {
        fn resolve(state: ?*anyopaque, alloc: std.mem.Allocator, event: Event) []const []const u8 {
            _ = state;
            _ = alloc;
            _ = event;
            return &.{};
        }
        fn free(state: ?*anyopaque, alloc: std.mem.Allocator, cert_ids: []const []const u8) void {
            _ = state;
            _ = alloc;
            _ = cert_ids;
        }
    };
    broker.setPushHook(.{
        .state = &ps,
        .resolve_fn = EmptyHook.resolve,
        .free_fn = EmptyHook.free,
        .send_fn = PushSink.send,
    });
    broker.publish(.{
        .type = "lead.created",
        .payload_json = "{}",
        .requires_operator_attention = true,
    });
    try std.testing.expectEqual(@as(usize, 0), ps.received);
}

// ─── D.1 — recent-event ring + helm.fetch_since ─────────────────────

test "broker: publish stamps event_id + ts on the dispatched event" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    broker.setClockFn(pinnedClockFn);
    defer broker.deinit();

    const StampSink = struct {
        last_event_id: [16]u8 = undefined,
        last_ts: i64 = 0,
        fn cb(state: ?*anyopaque, event: Event) void {
            const self: *@This() = @ptrCast(@alignCast(state.?));
            self.last_event_id = event.event_id;
            self.last_ts = event.ts;
        }
    };
    var sink: StampSink = .{};
    _ = try broker.subscribe(.{ .state = &sink, .callback = StampSink.cb });

    broker.publish(.{ .type = "lead.created", .payload_json = "{}" });
    try std.testing.expectEqualStrings("0000000000000001", &sink.last_event_id);
    try std.testing.expectEqual(@as(i64, 1700000000), sink.last_ts);

    broker.publish(.{ .type = "job.transitioned", .payload_json = "{}" });
    try std.testing.expectEqualStrings("0000000000000002", &sink.last_event_id);
}

test "fetchSince returns events strictly newer than since_ts" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    // Publish a few events with a hand-rolled clock that advances per call.
    const TickClock = struct {
        var tick: i64 = 1_700_000_000;
        fn now() i64 {
            const v = tick;
            tick += 1;
            return v;
        }
    };
    TickClock.tick = 1_700_000_000;
    broker.setClockFn(TickClock.now);
    defer broker.deinit();

    broker.publish(.{ .type = "lead.created", .payload_json = "{\"a\":1}" }); // ts=...000
    broker.publish(.{ .type = "lead.created", .payload_json = "{\"b\":2}" }); // ts=...001
    broker.publish(.{ .type = "lead.created", .payload_json = "{\"c\":3}" }); // ts=...002

    var cursor: i64 = 0;
    const got = try broker.fetchSince(allocator, 1_700_000_000, 100, &cursor);
    defer allocator.free(got);
    // since_ts=...000 → strictly newer means ts=...001 + ts=...002.
    try std.testing.expectEqual(@as(usize, 2), got.len);
    try std.testing.expectEqual(@as(i64, 1_700_000_001), got[0].ts);
    try std.testing.expectEqual(@as(i64, 1_700_000_002), got[1].ts);
    try std.testing.expectEqual(@as(i64, 1_700_000_002), cursor);
    try std.testing.expectEqualStrings("lead.created", got[0].type);
    try std.testing.expectEqualStrings("{\"b\":2}", got[0].payload_json);
}

test "fetchSince paginates via next_cursor_ts" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    const TickClock2 = struct {
        var tick: i64 = 2_000_000_000;
        fn now() i64 {
            const v = tick;
            tick += 1;
            return v;
        }
    };
    TickClock2.tick = 2_000_000_000;
    broker.setClockFn(TickClock2.now);
    defer broker.deinit();

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        broker.publish(.{ .type = "lead.created", .payload_json = "{}" });
    }

    var cursor: i64 = 0;
    const page1 = try broker.fetchSince(allocator, 0, 2, &cursor);
    defer allocator.free(page1);
    try std.testing.expectEqual(@as(usize, 2), page1.len);
    try std.testing.expectEqual(@as(i64, 2_000_000_001), cursor);

    const page2 = try broker.fetchSince(allocator, cursor, 2, &cursor);
    defer allocator.free(page2);
    try std.testing.expectEqual(@as(usize, 2), page2.len);
    try std.testing.expectEqual(@as(i64, 2_000_000_003), cursor);

    const page3 = try broker.fetchSince(allocator, cursor, 2, &cursor);
    defer allocator.free(page3);
    try std.testing.expectEqual(@as(usize, 1), page3.len);
    try std.testing.expectEqual(@as(i64, 2_000_000_004), cursor);

    // Another fetch past the end yields zero events; cursor stays put.
    const page4 = try broker.fetchSince(allocator, cursor, 2, &cursor);
    defer allocator.free(page4);
    try std.testing.expectEqual(@as(usize, 0), page4.len);
    try std.testing.expectEqual(@as(i64, 2_000_000_004), cursor);
}

test "fetchSince returns empty slice when no events match" {
    const allocator = std.testing.allocator;
    var broker = Broker.init(allocator);
    broker.setClockFn(pinnedClockFn);
    defer broker.deinit();
    var cursor: i64 = 0;
    const got = try broker.fetchSince(allocator, 9_999_999_999, 100, &cursor);
    defer allocator.free(got);
    try std.testing.expectEqual(@as(usize, 0), got.len);
    try std.testing.expectEqual(@as(i64, 9_999_999_999), cursor);
}

test "encodeEventId zero-pads to 16 lowercase hex chars" {
    const id = encodeEventId(1);
    try std.testing.expectEqualStrings("0000000000000001", &id);
    const id2 = encodeEventId(0xdeadbeefcafe0001);
    try std.testing.expectEqualStrings("deadbeefcafe0001", &id2);
}

```
