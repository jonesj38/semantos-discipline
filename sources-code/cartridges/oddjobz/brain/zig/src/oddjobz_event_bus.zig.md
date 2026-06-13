---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/oddjobz_event_bus.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.545946+00:00
---

# cartridges/oddjobz/brain/zig/src/oddjobz_event_bus.zig

```zig
// W3.2 — OddjobzEventBus: in-process pub/sub for job FSM transition events.
//
// This bus bridges W3.1's OddjobzEventProducer (which writes to Pravega)
// with W3.2's EventsStreamHandler (which fans out to WebSocket clients).
//
// Design decision: rather than tap Pravega on the read side (which would
// require a running Pravega cluster in every deploy), we wire an in-process
// bus alongside the Pravega producer.  The jobs_handler calls both:
//   1. ep.emitJobTransition(...)   — writes to Pravega (W3.1, unchanged)
//   2. event_bus.publish(event)    — notifies in-process WS subscribers
//
// This mirrors the helm_event_broker pattern (broker.zig), but carries the
// exact W3.1 wire shape rather than the generic helm envelope.  Reusing
// helm_event_broker was considered and rejected: helm subscribers receive
// {type, payload_json}, whereas the Flutter client expects the typed
// {job_id, cell_id, from_state, to_state, ts_ms, hat_id} + event_id shape.
//
// ─── Ring buffer for reconnect replay ────────────────────────────────────
//
// Every published event is stored in a bounded ring (MAX_RING_EVENTS).
// When a client reconnects with `resume_after=<event_id>`, the handler
// calls fetchSince(event_id) to replay missed events.  Oldest entries
// are evicted when the ring is full.
//
// ─── Threading model ─────────────────────────────────────────────────────
//
// publish / subscribe / unsubscribe are mutex-serialised (same contract
// as helm_event_broker.zig).  Callbacks are invoked inside the mutex and
// MUST be fast (a write-queue push at most).
//
// References:
//   - runtime/semantos-brain/src/helm_event_broker.zig   (pattern)
//   - runtime/semantos-brain/src/oddjobz_event_producer.zig (W3.1 event shape)
//   - apps/oddjobz-mobile/lib/src/repl/event_subscription_service.dart (W1.4 consumer)

const std = @import("std");

/// Maximum events held in the reconnect-replay ring.  Sized for ~1h of
/// high-volume oddjobz activity at the v0.1 push budget; older events
/// are evicted as new ones arrive.
pub const MAX_RING_EVENTS: usize = 512;

/// The W3.1 wire shape for a job FSM transition event.
/// Matches OddjobzEventProducer.JobTransitionEvent plus a broker-assigned
/// event_id for ordered replay.
pub const JobEvent = struct {
    /// Broker-assigned 16-char lowercase hex sequence id.
    event_id: [16]u8,
    job_id: []const u8,
    cell_id: []const u8,
    from_state: []const u8,
    to_state: []const u8,
    ts_ms: u64,
    hat_id: []const u8,
};

pub const SubscriberId = u64;

pub const Subscriber = struct {
    state: ?*anyopaque,
    /// Called synchronously inside publish; MUST be fast.
    callback: *const fn (state: ?*anyopaque, event: JobEvent) void,
};

/// One entry in the ring buffer — owns its string copies so the bus can
/// outlive the publishing call's stack-borrowed slices.
const RingEntry = struct {
    event_id: [16]u8,
    job_id: []u8,
    cell_id: []u8,
    from_state: []u8,
    to_state: []u8,
    ts_ms: u64,
    hat_id: []u8,

    fn deinit(self: *RingEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.job_id);
        allocator.free(self.cell_id);
        allocator.free(self.from_state);
        allocator.free(self.to_state);
        allocator.free(self.hat_id);
    }

    fn toJobEvent(self: *const RingEntry) JobEvent {
        return .{
            .event_id = self.event_id,
            .job_id = self.job_id,
            .cell_id = self.cell_id,
            .from_state = self.from_state,
            .to_state = self.to_state,
            .ts_ms = self.ts_ms,
            .hat_id = self.hat_id,
        };
    }
};

const Entry = struct {
    id: SubscriberId,
    sub: Subscriber,
};

pub const OddjobzEventBus = struct {
    allocator: std.mem.Allocator,
    mu: std.Thread.Mutex,
    next_id: SubscriberId,
    /// Monotonic counter for event_id assignment.
    next_seq: u64,
    subs: std.ArrayList(Entry),
    /// Bounded ring for reconnect replay.
    ring: std.ArrayList(RingEntry),

    pub fn init(allocator: std.mem.Allocator) OddjobzEventBus {
        return .{
            .allocator = allocator,
            .mu = .{},
            .next_id = 1,
            .next_seq = 1,
            .subs = .{},
            .ring = .{},
        };
    }

    pub fn deinit(self: *OddjobzEventBus) void {
        for (self.ring.items) |*r| r.deinit(self.allocator);
        self.ring.deinit(self.allocator);
        self.subs.deinit(self.allocator);
    }

    /// Register a subscriber.  Returns an opaque handle for unsubscribe.
    pub fn subscribe(self: *OddjobzEventBus, sub: Subscriber) !SubscriberId {
        self.mu.lock();
        defer self.mu.unlock();
        const id = self.next_id;
        self.next_id += 1;
        try self.subs.append(self.allocator, .{ .id = id, .sub = sub });
        return id;
    }

    /// Remove a subscriber.  Idempotent.
    pub fn unsubscribe(self: *OddjobzEventBus, id: SubscriberId) void {
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

    /// Publish a job transition event.  Assigns event_id, fans out to all
    /// live subscribers, and appends to the ring buffer.  All string params
    /// are borrowed — the bus copies them for the ring.
    pub fn publish(
        self: *OddjobzEventBus,
        job_id: []const u8,
        cell_id: []const u8,
        from_state: []const u8,
        to_state: []const u8,
        ts_ms: u64,
        hat_id: []const u8,
    ) void {
        self.mu.lock();
        defer self.mu.unlock();

        const eid = encodeEventId(self.next_seq);
        self.next_seq += 1;

        const stamped = JobEvent{
            .event_id = eid,
            .job_id = job_id,
            .cell_id = cell_id,
            .from_state = from_state,
            .to_state = to_state,
            .ts_ms = ts_ms,
            .hat_id = hat_id,
        };

        // Fan out to live subscribers.
        for (self.subs.items) |e| {
            e.sub.callback(e.sub.state, stamped);
        }

        // Persist in ring (best-effort; OOM drops silently).
        self.appendRing(stamped) catch {};
    }

    /// Return up to `limit` events from the ring whose event_id is
    /// sequentially after `after_event_id`.  Pass "" (empty string) to
    /// get all ring contents from the oldest entry.
    ///
    /// Returns an allocator-owned slice of JobEvent whose string fields
    /// point into the ring; caller must free the slice but NOT the
    /// individual strings (they live in the ring).  The caller MUST copy
    /// any strings it needs beyond the next publish call.
    pub fn fetchSince(
        self: *OddjobzEventBus,
        allocator: std.mem.Allocator,
        after_event_id: []const u8,
        limit: usize,
    ) ![]JobEvent {
        self.mu.lock();
        defer self.mu.unlock();

        // Decode the after_event_id as a u64 sequence number (hex).
        // Empty string → 0 (return everything).
        const after_seq: u64 = if (after_event_id.len == 16)
            std.fmt.parseInt(u64, after_event_id, 16) catch 0
        else
            0;

        var count: usize = 0;
        for (self.ring.items) |r| {
            const seq = std.fmt.parseInt(u64, &r.event_id, 16) catch continue;
            if (seq > after_seq) count += 1;
        }

        const out_len = @min(count, limit);
        const out = try allocator.alloc(JobEvent, out_len);
        var idx: usize = 0;
        for (self.ring.items) |r| {
            if (idx >= out_len) break;
            const seq = std.fmt.parseInt(u64, &r.event_id, 16) catch continue;
            if (seq <= after_seq) continue;
            out[idx] = r.toJobEvent();
            idx += 1;
        }
        return out;
    }

    /// Test-only: number of subscribers.
    pub fn subscriberCount(self: *OddjobzEventBus) usize {
        self.mu.lock();
        defer self.mu.unlock();
        return self.subs.items.len;
    }

    /// Test-only: number of events in the ring.
    pub fn ringCount(self: *OddjobzEventBus) usize {
        self.mu.lock();
        defer self.mu.unlock();
        return self.ring.items.len;
    }

    fn appendRing(self: *OddjobzEventBus, event: JobEvent) !void {
        if (self.ring.items.len >= MAX_RING_EVENTS) {
            var oldest = self.ring.orderedRemove(0);
            oldest.deinit(self.allocator);
        }
        const job_id = try self.allocator.dupe(u8, event.job_id);
        errdefer self.allocator.free(job_id);
        const cell_id = try self.allocator.dupe(u8, event.cell_id);
        errdefer self.allocator.free(cell_id);
        const from_state = try self.allocator.dupe(u8, event.from_state);
        errdefer self.allocator.free(from_state);
        const to_state = try self.allocator.dupe(u8, event.to_state);
        errdefer self.allocator.free(to_state);
        const hat_id = try self.allocator.dupe(u8, event.hat_id);
        errdefer self.allocator.free(hat_id);
        try self.ring.append(self.allocator, .{
            .event_id = event.event_id,
            .job_id = job_id,
            .cell_id = cell_id,
            .from_state = from_state,
            .to_state = to_state,
            .ts_ms = event.ts_ms,
            .hat_id = hat_id,
        });
    }
};

// ─── Helpers ──────────────────────────────────────────────────────────────

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

// ─── Inline tests ─────────────────────────────────────────────────────────

const TestSink = struct {
    events: std.ArrayList(JobEvent),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) TestSink {
        return .{ .events = .{}, .allocator = allocator };
    }

    fn deinit(self: *TestSink) void {
        self.events.deinit(self.allocator);
    }

    fn callback(state: ?*anyopaque, event: JobEvent) void {
        const self: *TestSink = @ptrCast(@alignCast(state.?));
        self.events.append(self.allocator, event) catch {};
    }
};

test "oddjobz_event_bus: subscribe + publish delivers event to subscriber" {
    const allocator = std.testing.allocator;
    var bus = OddjobzEventBus.init(allocator);
    defer bus.deinit();

    var sink = TestSink.init(allocator);
    defer sink.deinit();

    _ = try bus.subscribe(.{ .state = &sink, .callback = TestSink.callback });
    bus.publish("job-1", "aa", "lead", "quoted", 1000, "hat-a");

    try std.testing.expectEqual(@as(usize, 1), sink.events.items.len);
    try std.testing.expectEqualStrings("job-1", sink.events.items[0].job_id);
    try std.testing.expectEqualStrings("quoted", sink.events.items[0].to_state);
}

test "oddjobz_event_bus: unsubscribe stops delivery" {
    const allocator = std.testing.allocator;
    var bus = OddjobzEventBus.init(allocator);
    defer bus.deinit();

    var sink = TestSink.init(allocator);
    defer sink.deinit();

    const id = try bus.subscribe(.{ .state = &sink, .callback = TestSink.callback });
    bus.unsubscribe(id);
    bus.publish("job-2", "bb", "quoted", "scheduled", 2000, "hat-a");
    try std.testing.expectEqual(@as(usize, 0), sink.events.items.len);
}

test "oddjobz_event_bus: ring persists events for fetchSince" {
    const allocator = std.testing.allocator;
    var bus = OddjobzEventBus.init(allocator);
    defer bus.deinit();

    bus.publish("job-3", "cc", "lead", "quoted", 3000, "hat-b");
    bus.publish("job-4", "dd", "quoted", "scheduled", 4000, "hat-b");

    try std.testing.expectEqual(@as(usize, 2), bus.ringCount());

    // fetchSince("") → all events
    const all = try bus.fetchSince(allocator, "", 100);
    defer allocator.free(all);
    try std.testing.expectEqual(@as(usize, 2), all.len);
}

test "oddjobz_event_bus: fetchSince resumes after given event_id" {
    const allocator = std.testing.allocator;
    var bus = OddjobzEventBus.init(allocator);
    defer bus.deinit();

    bus.publish("job-a", "ee", "lead", "quoted", 1000, "hat-c");
    bus.publish("job-b", "ff", "quoted", "scheduled", 2000, "hat-c");
    bus.publish("job-c", "gg", "scheduled", "in_progress", 3000, "hat-c");

    // fetch all first
    const all = try bus.fetchSince(allocator, "", 100);
    defer allocator.free(all);
    try std.testing.expectEqual(@as(usize, 3), all.len);

    // resume after first event → should get 2 more
    const after_first = &all[0].event_id;
    const resumed = try bus.fetchSince(allocator, after_first, 100);
    defer allocator.free(resumed);
    try std.testing.expectEqual(@as(usize, 2), resumed.len);
    try std.testing.expectEqualStrings("job-b", resumed[0].job_id);
}

test "oddjobz_event_bus: hat_id is preserved through publish" {
    const allocator = std.testing.allocator;
    var bus = OddjobzEventBus.init(allocator);
    defer bus.deinit();

    var sink = TestSink.init(allocator);
    defer sink.deinit();
    _ = try bus.subscribe(.{ .state = &sink, .callback = TestSink.callback });

    bus.publish("job-5", "aa", "lead", "quoted", 9000, "hat-xyz");
    try std.testing.expectEqualStrings("hat-xyz", sink.events.items[0].hat_id);
}

test "oddjobz_event_bus: event_id monotonically increases" {
    const allocator = std.testing.allocator;
    var bus = OddjobzEventBus.init(allocator);
    defer bus.deinit();

    var sink = TestSink.init(allocator);
    defer sink.deinit();
    _ = try bus.subscribe(.{ .state = &sink, .callback = TestSink.callback });

    bus.publish("j1", "a", "lead", "quoted", 1, "h");
    bus.publish("j2", "b", "quoted", "scheduled", 2, "h");

    const id1 = std.fmt.parseInt(u64, &sink.events.items[0].event_id, 16) catch unreachable;
    const id2 = std.fmt.parseInt(u64, &sink.events.items[1].event_id, 16) catch unreachable;
    try std.testing.expect(id1 < id2);
}

```
