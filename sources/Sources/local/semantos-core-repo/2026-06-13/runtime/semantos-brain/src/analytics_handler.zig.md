---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/analytics_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.248230+00:00
---

# runtime/semantos-brain/src/analytics_handler.zig

```zig
// Analytics cell handler — S4 (Semantos Sites 1.0).
//
// POST /api/v1/analytics → parse analytics event JSON → write a
// LINEAR analytics.event cell to the operator's cell store → feed
// Pask learning kernel.
//
// All analytics events are LINEAR: consumed exactly once by the
// Pask aggregation pipeline, never duplicated.  The cell store
// enforces this at the kernel layer; BSV double-spend protection
// enforces it at consensus for any events that are anchored.
//
// v1.0 scope:
//   • Parse event JSON (event, session_id, referrer, page, variant, ts_ms)
//   • Validate event type against allowlist
//   • Write LINEAR analytics.event cell to op's cell store
//   • Return 204 No Content
//   • Pask integration: emit to the learning kernel's event bus
//
// Not in v1.0:
//   • Aggregation queries (separate analytics_store module)
//   • A/B test significance calculation (separate ab_test_evaluator module)
//   • BSV anchoring of analytics cells (deferred — high volume, anchor
//     aggregates not individual events)

const std = @import("std");

pub const AnalyticsEventType = enum {
    pageview,
    chat_start,
    lead_captured,
    booking_intent,
    conversion,

    pub fn fromString(s: []const u8) ?AnalyticsEventType {
        if (std.mem.eql(u8, s, "pageview"))       return .pageview;
        if (std.mem.eql(u8, s, "chat_start"))     return .chat_start;
        if (std.mem.eql(u8, s, "lead_captured"))  return .lead_captured;
        if (std.mem.eql(u8, s, "booking_intent")) return .booking_intent;
        if (std.mem.eql(u8, s, "conversion"))     return .conversion;
        return null;
    }

    pub fn toString(self: AnalyticsEventType) []const u8 {
        return switch (self) {
            .pageview       => "pageview",
            .chat_start     => "chat_start",
            .lead_captured  => "lead_captured",
            .booking_intent => "booking_intent",
            .conversion     => "conversion",
        };
    }

    /// Funnel position — used by Pask to build the conversion funnel entailment.
    pub fn funnelDepth(self: AnalyticsEventType) u8 {
        return switch (self) {
            .pageview       => 0,
            .chat_start     => 1,
            .lead_captured  => 2,
            .booking_intent => 3,
            .conversion     => 4,
        };
    }
};

pub const AnalyticsEvent = struct {
    event:      AnalyticsEventType,
    session_id: []const u8,
    referrer:   []const u8,
    page:       []const u8,
    variant:    ?[]const u8,
    ts_ms:      i64,
    op_pkh:     [32]u8,  // resolved from SNI map at HTTP handler level
};

pub const ParseError = error{
    missing_event,
    unknown_event,
    missing_session_id,
    body_too_large,
    invalid_json,
};

const MAX_BODY = 4 * 1024; // 4 KB — analytics payloads are tiny

/// Parse an analytics event from a JSON request body.
/// All strings in the returned struct are duped into `allocator` —
/// caller frees when done (or uses an arena).
pub fn parseEvent(
    allocator: std.mem.Allocator,
    body: []const u8,
    op_pkh: [32]u8,
) ParseError!AnalyticsEvent {
    if (body.len > MAX_BODY) return error.body_too_large;

    var parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        body,
        .{},
    ) catch return error.invalid_json;
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |o| o,
        else    => return error.invalid_json,
    };

    const event_str = if (root.get("event")) |v| switch (v) {
        .string => |s| s,
        else    => return error.missing_event,
    } else return error.missing_event;

    const event_type = AnalyticsEventType.fromString(event_str) orelse
        return error.unknown_event;

    const session_id_raw = if (root.get("session_id")) |v| switch (v) {
        .string => |s| s,
        else    => "anon",
    } else "anon";

    if (session_id_raw.len == 0) return error.missing_session_id;

    const referrer_raw = if (root.get("referrer")) |v| switch (v) {
        .string => |s| s,
        else    => "",
    } else "";

    const page_raw = if (root.get("page")) |v| switch (v) {
        .string => |s| s,
        else    => "/",
    } else "/";

    const variant_raw: ?[]const u8 = if (root.get("variant")) |v| switch (v) {
        .string => |s| s,
        .null   => null,
        else    => null,
    } else null;

    const ts_ms = if (root.get("ts_ms")) |v| switch (v) {
        .integer => |n| n,
        else     => std.time.milliTimestamp(),
    } else std.time.milliTimestamp();

    // Dupe strings before parsed.deinit() releases the underlying memory.
    const session_id = allocator.dupe(u8, session_id_raw) catch return error.missing_session_id;
    const referrer   = allocator.dupe(u8, referrer_raw)   catch return error.missing_session_id;
    const page       = allocator.dupe(u8, page_raw)       catch return error.missing_session_id;
    const variant: ?[]const u8 = if (variant_raw) |v|
        (allocator.dupe(u8, v) catch return error.missing_session_id)
    else null;

    return AnalyticsEvent{
        .event      = event_type,
        .session_id = session_id,
        .referrer   = referrer,
        .page       = page,
        .variant    = variant,
        .ts_ms      = ts_ms,
        .op_pkh     = op_pkh,
    };
}

/// Serialise an AnalyticsEvent to a JSON cell payload (fits in 768-byte
/// cell payload — analytics events are tiny).
pub fn eventToJson(
    writer: anytype,
    event: AnalyticsEvent,
) !void {
    try writer.print(
        \\{{"cell_type":"analytics.event","linearity":"LINEAR","payload":{{"event":"{s}","session_id":"{s}","referrer":"{s}","page":"{s}","variant":
    , .{
        event.event.toString(),
        event.session_id,
        event.referrer,
        event.page,
    });
    if (event.variant) |v| {
        try writer.print("\"{s}\"", .{v});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(
        \\,"ts_ms":{d},"funnel_depth":{d}}}}}
    , .{ event.ts_ms, event.event.funnelDepth() });
}

// ── Tests ─────────────────────────────────────────────────────────────

test "parse valid pageview event" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const body =
        \\{"event":"pageview","session_id":"abc123","referrer":"","page":"/","variant":null,"ts_ms":1234567890}
    ;
    const op_pkh = [_]u8{0} ** 32;
    const event = try parseEvent(allocator, body, op_pkh);
    try std.testing.expectEqual(AnalyticsEventType.pageview, event.event);
    try std.testing.expectEqualStrings("abc123", event.session_id);
    try std.testing.expectEqual(@as(u8, 0), event.event.funnelDepth());
}

test "parse lead_captured has funnel depth 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const body =
        \\{"event":"lead_captured","session_id":"xyz","referrer":"https://google.com","page":"/","variant":"a","ts_ms":0}
    ;
    const op_pkh = [_]u8{0} ** 32;
    const event = try parseEvent(allocator, body, op_pkh);
    try std.testing.expectEqual(AnalyticsEventType.lead_captured, event.event);
    try std.testing.expectEqual(@as(u8, 2), event.event.funnelDepth());
    try std.testing.expectEqualStrings("a", event.variant.?);
}

test "unknown event type returns error" {
    const allocator = std.testing.allocator;
    const body =
        \\{"event":"bounce","session_id":"abc","referrer":"","page":"/","ts_ms":0}
    ;
    const op_pkh = [_]u8{0} ** 32;
    try std.testing.expectError(error.unknown_event, parseEvent(allocator, body, op_pkh));
}

test "body too large returns error" {
    const allocator = std.testing.allocator;
    const body = "x" ** (MAX_BODY + 1);
    const op_pkh = [_]u8{0} ** 32;
    try std.testing.expectError(error.body_too_large, parseEvent(allocator, body, op_pkh));
}

```
