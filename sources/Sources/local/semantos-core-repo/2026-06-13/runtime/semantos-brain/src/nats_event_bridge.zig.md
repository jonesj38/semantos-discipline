---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/nats_event_bridge.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.215130+00:00
---

# runtime/semantos-brain/src/nats_event_bridge.zig

```zig
// NATS → OddjobzEventBus bridge.
//
// The brain runs ONE bridge per process.  It subscribes to the operator's
// NATS subject tree (`op.<op_pkh16>.>` or wildcard `op.>` for single-tenant),
// parses each fsm_transition JSON payload, and republishes to the in-memory
// OddjobzEventBus so /api/v1/events WSS subscribers receive the event.
//
// Architectural role:
//   jobs_handler  ──publish──►  NATS subject  ──MSG frame──►  bridge
//                                                                │
//                                                                ▼ parse + bus.publish
//                                                          OddjobzEventBus
//                                                                │
//                                                                ▼ subscribers
//                                                          /api/v1/events WSS
//
// This replaces jobs_handler's direct `bus.publish` call (which made the
// bus a parallel producer alongside NATS).  With the bridge, NATS is the
// single canonical source and the bus is a fan-out adapter.
//
// V1 limitations:
//   • Only `fsm_transition` events parsed today.  Other event types
//     (intent_outcome, stable_transition) flow through NATS but the
//     bridge ignores them — the bus only carries job FSM transitions
//     today.
//   • Hat filter is applied at subscription time (`filter_subject`); the
//     bridge doesn't re-check.

const std = @import("std");
const nats_subscriber_mod = @import("nats_subscriber");
const oddjobz_event_bus_mod = @import("oddjobz_event_bus");

const Subscriber = nats_subscriber_mod.Subscriber;
const Message = nats_subscriber_mod.Message;
const OddjobzEventBus = oddjobz_event_bus_mod.OddjobzEventBus;

pub const BridgeConfig = struct {
    nats_host: []const u8 = "127.0.0.1",
    nats_port: u16 = 4222,
    /// Subject pattern.  Single-tenant default = `op.>`; multi-tenant
    /// production usage = `op.<op_pkh16>.>`.
    subject_pattern: []const u8 = "op.>",
};

pub const Bridge = struct {
    allocator: std.mem.Allocator,
    bus: *OddjobzEventBus,
    subscriber: ?Subscriber = null,
    cfg: BridgeConfig,

    pub fn init(
        allocator: std.mem.Allocator,
        bus: *OddjobzEventBus,
        cfg: BridgeConfig,
    ) Bridge {
        return .{
            .allocator = allocator,
            .bus = bus,
            .cfg = cfg,
        };
    }

    /// Connect to NATS + start the reader thread.  Returns once SUB is
    /// registered (PONG received).
    pub fn start(self: *Bridge) !void {
        self.subscriber = Subscriber.init(
            self.allocator,
            .{ .host = self.cfg.nats_host, .port = self.cfg.nats_port },
            .{
                .ctx = @ptrCast(self),
                .onMessage = onMessage,
            },
        );
        try self.subscriber.?.subscribe(self.cfg.subject_pattern);
    }

    /// Stop the reader thread + close the NATS connection.  Idempotent.
    pub fn deinit(self: *Bridge) void {
        if (self.subscriber) |*s| {
            s.deinit();
            self.subscriber = null;
        }
    }
};

/// Reader-thread callback: parse the JSON payload, extract the six
/// fsm_transition fields, publish to the bus.  Best-effort — a parse
/// failure logs and drops; we don't propagate errors to NATS.
///
/// `msg` is allocator-owned; we must deinit before returning.
fn onMessage(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, msg_in: Message) void {
    var msg = msg_in;
    defer msg.deinit(allocator);

    const bridge: *Bridge = @ptrCast(@alignCast(ctx_ptr));

    // Only fsm_transition events get republished today.  Other event
    // types (intent_outcome, stable_transition) flow through NATS but
    // the bus doesn't carry them yet.  Subject ends with the event type
    // token: `op.<op_pkh16>.<hat_id>.<event_type>`.
    if (!std.mem.endsWith(u8, msg.subject, ".fsm_transition")) return;

    var parsed = parsePayload(allocator, msg.payload) catch return;
    defer parsed.deinit();

    bridge.bus.publish(
        parsed.job_id,
        parsed.cell_id,
        parsed.from_state,
        parsed.to_state,
        parsed.ts_ms,
        parsed.hat_id,
    );
}

const ParsedFsmTransition = struct {
    arena: std.json.Parsed(std.json.Value),
    job_id: []const u8,
    cell_id: []const u8,
    from_state: []const u8,
    to_state: []const u8,
    ts_ms: u64,
    hat_id: []const u8,

    pub fn deinit(self: *ParsedFsmTransition) void {
        self.arena.deinit();
    }
};

/// Pure-function payload parser.  Extracts the six fields from a
/// `fsm_transition` JSON payload.  Returns an arena-owned ParsedFsmTransition
/// (caller must deinit).
pub fn parsePayload(allocator: std.mem.Allocator, payload: []const u8) !ParsedFsmTransition {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    errdefer parsed.deinit();
    if (parsed.value != .object) return error.MalformedPayload;

    const obj = parsed.value.object;
    const job_id = getString(obj, "job_id") orelse return error.MalformedPayload;
    const cell_id = getString(obj, "cell_id") orelse return error.MalformedPayload;
    const from_state = getString(obj, "from_state") orelse return error.MalformedPayload;
    const to_state = getString(obj, "to_state") orelse return error.MalformedPayload;
    const hat_id = getString(obj, "hat_id") orelse return error.MalformedPayload;
    const ts_ms_val = obj.get("ts_ms") orelse return error.MalformedPayload;
    const ts_ms: u64 = switch (ts_ms_val) {
        .integer => |n| if (n < 0) 0 else @intCast(n),
        .float => |f| @intFromFloat(f),
        else => return error.MalformedPayload,
    };

    return .{
        .arena = parsed,
        .job_id = job_id,
        .cell_id = cell_id,
        .from_state = from_state,
        .to_state = to_state,
        .ts_ms = ts_ms,
        .hat_id = hat_id,
    };
}

fn getString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    if (v != .string) return null;
    return v.string;
}

// ── Inline tests — pure payload parsing ─────────────────────────────────

const testing = std.testing;

test "nats_event_bridge: parsePayload — extracts all six fields" {
    const payload =
        "{" ++
        "\"job_id\":\"j-1\"," ++
        "\"cell_id\":\"abcd1234\"," ++
        "\"from_state\":\"lead\"," ++
        "\"to_state\":\"quoted\"," ++
        "\"ts_ms\":1700000000000," ++
        "\"hat_id\":\"oddjobtodd.info\"," ++
        "\"op_pkh\":\"0000000000000000\"" ++
        "}";
    var parsed = try parsePayload(testing.allocator, payload);
    defer parsed.deinit();
    try testing.expectEqualStrings("j-1", parsed.job_id);
    try testing.expectEqualStrings("abcd1234", parsed.cell_id);
    try testing.expectEqualStrings("lead", parsed.from_state);
    try testing.expectEqualStrings("quoted", parsed.to_state);
    try testing.expectEqual(@as(u64, 1700000000000), parsed.ts_ms);
    try testing.expectEqualStrings("oddjobtodd.info", parsed.hat_id);
}

test "nats_event_bridge: parsePayload — rejects non-object" {
    try testing.expectError(
        error.MalformedPayload,
        parsePayload(testing.allocator, "\"not an object\""),
    );
    try testing.expectError(
        error.MalformedPayload,
        parsePayload(testing.allocator, "[1, 2, 3]"),
    );
}

test "nats_event_bridge: parsePayload — rejects missing required field" {
    const payload = "{\"job_id\":\"j-1\",\"cell_id\":\"abcd\"}";
    try testing.expectError(error.MalformedPayload, parsePayload(testing.allocator, payload));
}

test "nats_event_bridge: parsePayload — rejects wrong-typed field" {
    const payload =
        "{" ++
        "\"job_id\":42," ++ // not a string
        "\"cell_id\":\"abcd\"," ++
        "\"from_state\":\"lead\"," ++
        "\"to_state\":\"quoted\"," ++
        "\"ts_ms\":1," ++
        "\"hat_id\":\"x\"" ++
        "}";
    try testing.expectError(error.MalformedPayload, parsePayload(testing.allocator, payload));
}

test "nats_event_bridge: parsePayload — accepts ts_ms as integer or float" {
    const int_payload =
        "{" ++
        "\"job_id\":\"j\",\"cell_id\":\"c\",\"from_state\":\"a\"," ++
        "\"to_state\":\"b\",\"ts_ms\":5000,\"hat_id\":\"h\"}";
    var parsed_int = try parsePayload(testing.allocator, int_payload);
    defer parsed_int.deinit();
    try testing.expectEqual(@as(u64, 5000), parsed_int.ts_ms);

    const float_payload =
        "{" ++
        "\"job_id\":\"j\",\"cell_id\":\"c\",\"from_state\":\"a\"," ++
        "\"to_state\":\"b\",\"ts_ms\":5000.0,\"hat_id\":\"h\"}";
    var parsed_float = try parsePayload(testing.allocator, float_payload);
    defer parsed_float.deinit();
    try testing.expectEqual(@as(u64, 5000), parsed_float.ts_ms);
}

test "nats_event_bridge: parsePayload — clamps negative ts_ms to 0" {
    const payload =
        "{" ++
        "\"job_id\":\"j\",\"cell_id\":\"c\",\"from_state\":\"a\"," ++
        "\"to_state\":\"b\",\"ts_ms\":-100,\"hat_id\":\"h\"}";
    var parsed = try parsePayload(testing.allocator, payload);
    defer parsed.deinit();
    try testing.expectEqual(@as(u64, 0), parsed.ts_ms);
}

test "nats_event_bridge: onMessage skips non-fsm_transition subjects" {
    // Build a fake bus + check publishCount stays 0 after a wrong-subject msg.
    var bus = OddjobzEventBus.init(testing.allocator);
    defer bus.deinit();
    var bridge = Bridge.init(testing.allocator, &bus, .{});
    defer bridge.deinit(); // safe even though we never started subscriber

    const before = bus.ringCount();
    // Subject doesn't end with .fsm_transition — should drop.
    const msg = Message{
        .subject = try testing.allocator.dupe(u8, "op.0000000000000000.x.intent_outcome"),
        .reply = try testing.allocator.dupe(u8, ""),
        .payload = try testing.allocator.dupe(u8, "{}"),
    };
    onMessage(@ptrCast(&bridge), testing.allocator, msg);
    try testing.expectEqual(before, bus.ringCount());
}

test "nats_event_bridge: onMessage publishes valid fsm_transition payload" {
    var bus = OddjobzEventBus.init(testing.allocator);
    defer bus.deinit();
    var bridge = Bridge.init(testing.allocator, &bus, .{});
    defer bridge.deinit();

    const payload =
        "{" ++
        "\"job_id\":\"j-x\",\"cell_id\":\"deadbeef\"," ++
        "\"from_state\":\"lead\",\"to_state\":\"quoted\"," ++
        "\"ts_ms\":1700000000123,\"hat_id\":\"oddjobtodd.info\"," ++
        "\"op_pkh\":\"0000000000000000\"" ++
        "}";
    const msg = Message{
        .subject = try testing.allocator.dupe(u8, "op.0000000000000000.oddjobtodd.info.fsm_transition"),
        .reply = try testing.allocator.dupe(u8, ""),
        .payload = try testing.allocator.dupe(u8, payload),
    };

    const before = bus.ringCount();
    onMessage(@ptrCast(&bridge), testing.allocator, msg);
    try testing.expectEqual(before + 1, bus.ringCount());
}

```
