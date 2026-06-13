---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/wss_rpc_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.229368+00:00
---

# runtime/semantos-brain/src/wss_rpc_registry.zig

```zig
//! WSS RPC registry + frame codec — the unified `/api/v1/rpc` channel contract.
//!
//! ONE multiplexed WebSocket carries many logical methods for ANY cartridge:
//! substrate reads (`cell.query`/`cell.get`), FSM verbs (`repl.eval`), generic
//! mint (`cells.mint`), subscriptions (`subscribe`/`resume`/`unsubscribe`), and
//! cartridge-contributed methods (`conversation.*`, `voice.submit`). It is the
//! WSS analog of `http_route_registry` (#PR-F1): a growable table the reactor
//! consults per frame, populated at boot via the cartridge seam
//! (`deps.rpc_registry`) — no reactor edit per method.
//!
//! Auth is bound ONCE at the socket upgrade (cert/bearer); per-method gating is
//! a pure capability check the reactor performs against the session's snapshot
//! cap set using `method.required_cap` (null = no extra cap beyond a valid
//! upgrade). Keeping the cap as a plain string (not a dispatcher type) keeps
//! this module a LEAF — std only — so `cartridge_seam` can expose the registry
//! without pulling the reactor (substrate one-way dep gate, #847).
//!
//! Frame contract (RFC 6455 text frames, one JSON object each, `t` discriminates):
//!   client→server  {"t":"req","id":"c-1","method":"cell.query","params":{…}}
//!   client→server  {"t":"ack","sub":"s-1","event_id":"…"}
//!   server→client  {"t":"res","id":"c-1","result":{…}}        // result = handler body verbatim
//!   server→client  {"t":"err","id":"c-1","code":"forbidden","message":"…"}
//!   server→client  {"t":"push","sub":"s-1","channel":"hat.events","payload":{…}}
//!
//! Error codes: unauthorized | forbidden | bad_request | unknown_method |
//!              not_found | internal

const std = @import("std");

// ─────────────────────────────────────────────────────────────────────
// Method registry
// ─────────────────────────────────────────────────────────────────────

/// A method handler's outcome. `ok.body` is JSON (allocated with the
/// per-request allocator the reactor passes to `handle`); it is embedded
/// verbatim as the `result` of the `res` frame, preserving each handler's
/// existing wire shape (e.g. cell.query's `{"jobs":[…]}`). `err` becomes an
/// `err` frame; the handler controls the code + message.
pub const RpcResult = union(enum) {
    ok: []const u8,
    err: RpcError,
};

pub const RpcError = struct {
    /// One of the documented codes above. Borrowed (usually a literal).
    code: []const u8,
    /// Human-readable detail. Borrowed; if allocated, use the per-request
    /// allocator so it outlives the return.
    message: []const u8,
};

/// Uniform RPC method handler. Inspect `params_json` (the raw JSON of the
/// request's `params`, or `"{}"` when absent), do the work, return a
/// RpcResult. An error surfaces as an `internal` err frame — handlers should
/// prefer returning `RpcResult.err` so they control code + message.
pub const RpcHandleFn = *const fn (
    state: *anyopaque,
    params_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!RpcResult;

/// One registered method, keyed on its exact dotted name.
pub const RpcMethod = struct {
    /// Exact method string, e.g. "cell.query", "conversation.turn.propose".
    name: []const u8,
    /// Capability the caller's upgrade-bound cap set must imply, or null when
    /// a valid upgrade is sufficient. The reactor enforces this (it owns the
    /// session cap set + the dispatcher's `impliesCapability`).
    required_cap: ?[]const u8 = null,
    /// Caller-owned state threaded into `handle` (e.g. the cartridge acceptor
    /// or a substrate handler struct). Borrowed; the registry never frees it.
    state: *anyopaque,
    handle: RpcHandleFn,
};

/// Per-instance ceiling. Substrate pre-registers ~7; each cartridge adds a
/// handful. 128 is a generous bound — exceeding it is a deployment
/// misconfiguration, not a runtime path.
pub const MAX_METHODS: usize = 128;

/// Growable, fixed-capacity method table. Boot-time append; read at frame
/// dispatch. Stable-address contract mirrors RouteRegistry: the reactor reads
/// the registry the SiteServer points at, so a cartridge's boot-time `add()`
/// is visible at frame time. Exact-match; first registration of a name wins.
pub const RpcRegistry = struct {
    buf: [MAX_METHODS]RpcMethod = undefined,
    len: usize = 0,

    pub fn add(self: *RpcRegistry, method: RpcMethod) void {
        if (self.len >= MAX_METHODS) {
            std.log.warn(
                "RpcRegistry: method ceiling {d} reached — dropping {s}",
                .{ MAX_METHODS, method.name },
            );
            return;
        }
        // First-wins: ignore a duplicate name so substrate methods can't be
        // shadowed by a cartridge re-registering the same dotted name.
        if (self.match(method.name) != null) {
            std.log.warn("RpcRegistry: duplicate method {s} ignored", .{method.name});
            return;
        }
        self.buf[self.len] = method;
        self.len += 1;
    }

    pub fn count(self: *const RpcRegistry) usize {
        return self.len;
    }

    pub fn match(self: *const RpcRegistry, name: []const u8) ?*const RpcMethod {
        for (self.buf[0..self.len]) |*m| {
            if (std.mem.eql(u8, m.name, name)) return m;
        }
        return null;
    }
};

// ─────────────────────────────────────────────────────────────────────
// Frame codec
// ─────────────────────────────────────────────────────────────────────

/// A parsed client→server frame. String fields are owned by the allocator
/// passed to `parseClientFrame` (use a per-request arena). `params` is the
/// re-serialized JSON of the request's `params` object, or `"{}"` when absent.
pub const ClientFrame = union(enum) {
    request: Request,
    ack: Ack,
    /// Valid JSON but not a frame we handle (unknown `t`, or missing fields).
    unsupported,
    /// Not parseable as a JSON object.
    parse_error,

    pub const Request = struct {
        id: []const u8,
        method: []const u8,
        params: []const u8,
    };
    pub const Ack = struct {
        sub: []const u8,
        event_id: []const u8,
    };
};

/// Parse a client text frame. Never errors on malformed input — returns
/// `.parse_error` / `.unsupported` so the reactor can reply with a `bad_request`
/// err frame instead of tearing down the socket. Allocations are owned by
/// `allocator`.
pub fn parseClientFrame(allocator: std.mem.Allocator, text: []const u8) !ClientFrame {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch
        return .parse_error;
    defer parsed.deinit();
    if (parsed.value != .object) return .parse_error;
    const obj = parsed.value.object;

    const t = valueString(obj, "t") orelse return .unsupported;

    if (std.mem.eql(u8, t, "req")) {
        const id = valueString(obj, "id") orelse return .unsupported;
        const method = valueString(obj, "method") orelse return .unsupported;
        const params_json: []const u8 = if (obj.get("params")) |pv|
            try std.json.Stringify.valueAlloc(allocator, pv, .{})
        else
            try allocator.dupe(u8, "{}");
        return .{ .request = .{
            .id = try allocator.dupe(u8, id),
            .method = try allocator.dupe(u8, method),
            .params = params_json,
        } };
    }

    if (std.mem.eql(u8, t, "ack")) {
        const sub = valueString(obj, "sub") orelse return .unsupported;
        const event_id = valueString(obj, "event_id") orelse return .unsupported;
        return .{ .ack = .{
            .sub = try allocator.dupe(u8, sub),
            .event_id = try allocator.dupe(u8, event_id),
        } };
    }

    return .unsupported;
}

fn valueString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

/// `{"t":"res","id":<id>,"result":<result_body>}` — `result_body` is embedded
/// verbatim (must be valid JSON). Returned slice is owned by `allocator`.
pub fn encodeRes(allocator: std.mem.Allocator, id: []const u8, result_body: []const u8) ![]u8 {
    const id_json = try jsonString(allocator, id);
    defer allocator.free(id_json);
    return std.fmt.allocPrint(allocator, "{{\"t\":\"res\",\"id\":{s},\"result\":{s}}}", .{ id_json, result_body });
}

/// `{"t":"err","id":<id>,"code":<code>,"message":<message>}`.
pub fn encodeErr(allocator: std.mem.Allocator, id: []const u8, code: []const u8, message: []const u8) ![]u8 {
    const id_json = try jsonString(allocator, id);
    defer allocator.free(id_json);
    const code_json = try jsonString(allocator, code);
    defer allocator.free(code_json);
    const msg_json = try jsonString(allocator, message);
    defer allocator.free(msg_json);
    return std.fmt.allocPrint(
        allocator,
        "{{\"t\":\"err\",\"id\":{s},\"code\":{s},\"message\":{s}}}",
        .{ id_json, code_json, msg_json },
    );
}

/// `{"t":"push","sub":<sub>,"channel":<channel>,"payload":<payload>}` —
/// `payload` is embedded verbatim (must be valid JSON).
pub fn encodePush(allocator: std.mem.Allocator, sub: []const u8, channel: []const u8, payload: []const u8) ![]u8 {
    const sub_json = try jsonString(allocator, sub);
    defer allocator.free(sub_json);
    const chan_json = try jsonString(allocator, channel);
    defer allocator.free(chan_json);
    return std.fmt.allocPrint(
        allocator,
        "{{\"t\":\"push\",\"sub\":{s},\"channel\":{s},\"payload\":{s}}}",
        .{ sub_json, chan_json, payload },
    );
}

/// Emit `s` as a quoted, escaped JSON string (delegates escaping to std.json
/// so control chars / quotes / backslashes are handled correctly).
fn jsonString(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, std.json.Value{ .string = s }, .{});
}

// ─────────────────────────────────────────────────────────────────────
const testing = std.testing;

test "RpcRegistry: add/match/first-wins/ceiling" {
    const Dummy = struct {
        fn h(_: *anyopaque, _: []const u8, _: std.mem.Allocator) anyerror!RpcResult {
            return .{ .ok = "{}" };
        }
    };
    var state: u8 = 0;
    var reg = RpcRegistry{};
    try testing.expectEqual(@as(usize, 0), reg.count());

    reg.add(.{ .name = "cell.query", .state = &state, .handle = Dummy.h });
    reg.add(.{ .name = "repl.eval", .required_cap = "cap.brain.admin", .state = &state, .handle = Dummy.h });
    try testing.expectEqual(@as(usize, 2), reg.count());

    try testing.expect(reg.match("cell.query") != null);
    try testing.expect(reg.match("repl.eval").?.required_cap != null);
    try testing.expect(reg.match("nope") == null);

    // duplicate ignored (first-wins)
    reg.add(.{ .name = "cell.query", .state = &state, .handle = Dummy.h });
    try testing.expectEqual(@as(usize, 2), reg.count());

    // ceiling — each name needs stable storage (the registry borrows the
    // slice), so back each with its own row instead of a reused stack buffer.
    var name_store: [MAX_METHODS + 5][8]u8 = undefined;
    var i: usize = 0;
    while (i < MAX_METHODS + 5) : (i += 1) {
        const nm = std.fmt.bufPrint(&name_store[i], "m{d}", .{i}) catch unreachable;
        reg.add(.{ .name = nm, .state = &state, .handle = Dummy.h });
    }
    try testing.expectEqual(MAX_METHODS, reg.count());
}

test "parseClientFrame: req with params" {
    const a = testing.allocator;
    const frame = try parseClientFrame(a, "{\"t\":\"req\",\"id\":\"c-1\",\"method\":\"cell.query\",\"params\":{\"typeHash\":\"oddjobz.job.v2\"}}");
    switch (frame) {
        .request => |r| {
            defer a.free(r.id);
            defer a.free(r.method);
            defer a.free(r.params);
            try testing.expectEqualStrings("c-1", r.id);
            try testing.expectEqualStrings("cell.query", r.method);
            // params re-serialized; must still parse + carry the field
            try testing.expect(std.mem.indexOf(u8, r.params, "oddjobz.job.v2") != null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parseClientFrame: req without params defaults to {}" {
    const a = testing.allocator;
    const frame = try parseClientFrame(a, "{\"t\":\"req\",\"id\":\"7\",\"method\":\"repl.eval\"}");
    switch (frame) {
        .request => |r| {
            defer a.free(r.id);
            defer a.free(r.method);
            defer a.free(r.params);
            try testing.expectEqualStrings("{}", r.params);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parseClientFrame: ack + unsupported + parse_error" {
    const a = testing.allocator;
    const ack = try parseClientFrame(a, "{\"t\":\"ack\",\"sub\":\"s-1\",\"event_id\":\"00ab\"}");
    switch (ack) {
        .ack => |k| {
            defer a.free(k.sub);
            defer a.free(k.event_id);
            try testing.expectEqualStrings("s-1", k.sub);
            try testing.expectEqualStrings("00ab", k.event_id);
        },
        else => return error.TestUnexpectedResult,
    }
    try testing.expect((try parseClientFrame(a, "{\"t\":\"bogus\"}")) == .unsupported);
    try testing.expect((try parseClientFrame(a, "not json")) == .parse_error);
    try testing.expect((try parseClientFrame(a, "[1,2,3]")) == .parse_error);
}

test "encodeRes/encodeErr/encodePush shape + escaping" {
    const a = testing.allocator;
    const res = try encodeRes(a, "c-1", "{\"jobs\":[]}");
    defer a.free(res);
    try testing.expectEqualStrings("{\"t\":\"res\",\"id\":\"c-1\",\"result\":{\"jobs\":[]}}", res);

    const err = try encodeErr(a, "c-2", "forbidden", "need cap");
    defer a.free(err);
    try testing.expectEqualStrings("{\"t\":\"err\",\"id\":\"c-2\",\"code\":\"forbidden\",\"message\":\"need cap\"}", err);

    const push = try encodePush(a, "s-1", "hat.events", "{\"job_id\":\"x\"}");
    defer a.free(push);
    try testing.expectEqualStrings("{\"t\":\"push\",\"sub\":\"s-1\",\"channel\":\"hat.events\",\"payload\":{\"job_id\":\"x\"}}", push);

    // escaping: a quote in the message must be escaped
    const err2 = try encodeErr(a, "x", "bad_request", "he said \"hi\"");
    defer a.free(err2);
    try testing.expect(std.mem.indexOf(u8, err2, "\\\"hi\\\"") != null);
}

```
