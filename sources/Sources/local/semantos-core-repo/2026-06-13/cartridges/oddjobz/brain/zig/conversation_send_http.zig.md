---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/conversation_send_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.479512+00:00
---

# cartridges/oddjobz/brain/zig/conversation_send_http.zig

```zig
// Operator-initiated SMS send endpoint — pure orchestration.
//
// Endpoint: POST /api/v1/conversation/<id>/send
// Body:     {"body":"text to send"}
//
// W2 of docs/design/CUSTOMER-CONV-LOOP-PLAN.md.
//
// The accept function owns the orchestration:
//   1. Authorize via bearer.
//   2. Parse request body for `body` field.
//   3. Resolve conversation_id → contact E.164 phone (injected lookup).
//   4. Dispatch sendSms via twilio_adapter with injected SenderFn.
//   5. Persist the outbound message-sent record (injected persist fn).
//   6. Return typed AcceptResult that the HTTP wrapper maps to status.
//
// All deps are injected function pointers so unit tests run with no
// LMDB, no Twilio account, no dispatcher. Production wiring (W2.3)
// supplies real implementations.

const std = @import("std");
const twilio_adapter = @import("twilio_adapter");

// ────────────────────────────────────────────────────────────────────
// Result types
// ────────────────────────────────────────────────────────────────────

pub const AcceptResultKind = enum {
    sent, // 200
    unauthorised, // 401
    not_found, // 404
    twilio_disabled, // 503
    malformed_body, // 400
    invalid_recipient, // 422
    rate_limited, // 429
    upstream_error, // 502

    pub fn httpStatus(self: AcceptResultKind) std.http.Status {
        return switch (self) {
            .sent => .ok,
            .unauthorised => .unauthorized,
            .not_found => .not_found,
            .twilio_disabled => .service_unavailable,
            .malformed_body => .bad_request,
            .invalid_recipient => .unprocessable_entity,
            .rate_limited => .too_many_requests,
            .upstream_error => .bad_gateway,
        };
    }
};

pub const AcceptResult = struct {
    kind: AcceptResultKind,
    sid: []u8 = &.{}, // populated on .sent
    twilio_status: []u8 = &.{}, // populated on .sent

    pub fn deinit(self: *AcceptResult, allocator: std.mem.Allocator) void {
        if (self.sid.len > 0) allocator.free(self.sid);
        if (self.twilio_status.len > 0) allocator.free(self.twilio_status);
        self.sid = &.{};
        self.twilio_status = &.{};
    }
};

// ────────────────────────────────────────────────────────────────────
// Injectable dependencies
// ────────────────────────────────────────────────────────────────────

// Bearer validity check. Production wiring delegates to bearer_tokens
// store; tests can pass a trivial closure.
pub const IsBearerValidFn = *const fn (ctx: ?*anyopaque, bearer_hex: []const u8) bool;

// Resolve a conversation_id to an E.164 phone number for the contact.
// Caller owns the returned slice. Returns null if conversation unknown.
pub const LookupContactPhoneFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    conversation_id: []const u8,
) anyerror!?[]u8;

// Persist a record of "operator sent <body> to <conversation_id> via
// SMS sid <sid>". On error, the orchestrator maps to upstream_error —
// the SMS already went out, but the local record failed; surface so
// the operator knows. Caller of acceptSend is responsible for any
// retry policy.
pub const PersistMessageFn = *const fn (
    ctx: ?*anyopaque,
    conversation_id: []const u8,
    body: []const u8,
    sid: []const u8,
) anyerror!void;

pub const Acceptor = struct {
    allocator: std.mem.Allocator,

    is_bearer_valid: IsBearerValidFn,
    is_bearer_valid_ctx: ?*anyopaque = null,

    twilio_config: ?twilio_adapter.TwilioConfig = null,

    sender: twilio_adapter.SenderFn,
    sender_ctx: ?*anyopaque = null,

    lookup_contact: LookupContactPhoneFn,
    lookup_contact_ctx: ?*anyopaque = null,

    persist_message: PersistMessageFn,
    persist_message_ctx: ?*anyopaque = null,
};

// ────────────────────────────────────────────────────────────────────
// Request body parsing — minimal JSON shape {"body":"..."}.
// ────────────────────────────────────────────────────────────────────

pub const ParsedRequest = struct {
    body: []u8,

    pub fn deinit(self: *ParsedRequest, allocator: std.mem.Allocator) void {
        if (self.body.len > 0) allocator.free(self.body);
        self.body = &.{};
    }
};

pub const ParseError = error{ malformed, missing_body, body_empty };

pub fn parseRequest(allocator: std.mem.Allocator, raw: []const u8) ParseError!ParsedRequest {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, raw, .{}) catch {
        return ParseError.malformed;
    };
    defer parsed.deinit();

    if (parsed.value != .object) return ParseError.malformed;
    const obj = parsed.value.object;
    const v = obj.get("body") orelse return ParseError.missing_body;
    if (v != .string) return ParseError.malformed;
    if (v.string.len == 0) return ParseError.body_empty;

    const owned = allocator.dupe(u8, v.string) catch return ParseError.malformed;
    return ParsedRequest{ .body = owned };
}

// ────────────────────────────────────────────────────────────────────
// acceptSend — orchestrator.
//
// W2.1 RED: stub returns .upstream_error for every input.
// W2.2 GREEN: real orchestration.
// ────────────────────────────────────────────────────────────────────

pub fn acceptSend(
    acceptor: *const Acceptor,
    bearer_hex: ?[]const u8,
    conversation_id: []const u8,
    body_json: []const u8,
) anyerror!AcceptResult {
    // 1. Bearer check.
    const bh = bearer_hex orelse return AcceptResult{ .kind = .unauthorised };
    if (!acceptor.is_bearer_valid(acceptor.is_bearer_valid_ctx, bh)) {
        return AcceptResult{ .kind = .unauthorised };
    }

    // 2. Twilio configured?
    const cfg = acceptor.twilio_config orelse return AcceptResult{ .kind = .twilio_disabled };

    // 3. Parse request body.
    var parsed = parseRequest(acceptor.allocator, body_json) catch {
        return AcceptResult{ .kind = .malformed_body };
    };
    defer parsed.deinit(acceptor.allocator);

    // 4. Look up contact phone for this conversation.
    const maybe_phone = acceptor.lookup_contact(
        acceptor.lookup_contact_ctx,
        acceptor.allocator,
        conversation_id,
    ) catch return AcceptResult{ .kind = .upstream_error };

    const phone = maybe_phone orelse return AcceptResult{ .kind = .not_found };
    defer acceptor.allocator.free(phone);

    // 5. Dispatch sendSms.
    var sent = twilio_adapter.sendSms(
        acceptor.allocator,
        cfg,
        phone,
        parsed.body,
        acceptor.sender,
        acceptor.sender_ctx,
    ) catch |err| return switch (err) {
        twilio_adapter.Error.rate_limited => AcceptResult{ .kind = .rate_limited },
        twilio_adapter.Error.invalid_recipient => AcceptResult{ .kind = .invalid_recipient },
        else => AcceptResult{ .kind = .upstream_error },
    };
    // `sent.sid` / `sent.status` are owned by sent; we'll move them into
    // AcceptResult below and clear sent so its deinit is a no-op.
    errdefer sent.deinit(acceptor.allocator);

    // 6. Persist the outbound message-sent record.
    acceptor.persist_message(
        acceptor.persist_message_ctx,
        conversation_id,
        parsed.body,
        sent.sid,
    ) catch {
        // SMS already went out but local record failed — surface as
        // upstream_error. The operator's UI should retry the persist
        // (or refresh) rather than re-sending.
        sent.deinit(acceptor.allocator);
        return AcceptResult{ .kind = .upstream_error };
    };

    // 7. Hand ownership of sid/status to AcceptResult.
    const result = AcceptResult{
        .kind = .sent,
        .sid = sent.sid,
        .twilio_status = sent.status,
    };
    sent.sid = &.{};
    sent.status = &.{};
    return result;
}

// ────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "parseRequest — happy path returns body field" {
    var p = try parseRequest(testing.allocator,
        \\{"body":"hello there"}
    );
    defer p.deinit(testing.allocator);
    try testing.expectEqualStrings("hello there", p.body);
}

test "parseRequest — malformed JSON" {
    try testing.expectError(ParseError.malformed, parseRequest(testing.allocator, "{ not json"));
}

test "parseRequest — missing body field" {
    try testing.expectError(ParseError.missing_body, parseRequest(testing.allocator,
        \\{"other":"x"}
    ));
}

test "parseRequest — empty body string" {
    try testing.expectError(ParseError.body_empty, parseRequest(testing.allocator,
        \\{"body":""}
    ));
}

// Test harness — captures all injected-fn invocations so we can assert
// orchestration ordering.
const TestEnv = struct {
    allocator: std.mem.Allocator,

    // Capture state
    bearer_seen: ?[]u8 = null,
    bearer_valid_returns: bool = true,

    lookup_seen_conversation_id: ?[]u8 = null,
    lookup_returns_phone: ?[]const u8 = null, // null = conversation not found
    lookup_should_error: bool = false,

    sender_seen_url: ?[]u8 = null,
    sender_seen_auth: ?[]u8 = null,
    sender_seen_body: ?[]u8 = null,
    sender_canned_status: u16 = 201,
    sender_canned_body: []const u8 = "{\"sid\":\"SM\",\"status\":\"queued\"}",

    persist_called: bool = false,
    persist_seen_conversation_id: ?[]u8 = null,
    persist_seen_body: ?[]u8 = null,
    persist_seen_sid: ?[]u8 = null,
    persist_should_error: bool = false,

    fn deinit(self: *TestEnv) void {
        if (self.bearer_seen) |b| self.allocator.free(b);
        if (self.lookup_seen_conversation_id) |s| self.allocator.free(s);
        if (self.sender_seen_url) |s| self.allocator.free(s);
        if (self.sender_seen_auth) |s| self.allocator.free(s);
        if (self.sender_seen_body) |s| self.allocator.free(s);
        if (self.persist_seen_conversation_id) |s| self.allocator.free(s);
        if (self.persist_seen_body) |s| self.allocator.free(s);
        if (self.persist_seen_sid) |s| self.allocator.free(s);
    }

    fn isBearerValid(ctx: ?*anyopaque, bearer_hex: []const u8) bool {
        const self: *TestEnv = @ptrCast(@alignCast(ctx.?));
        // Re-use the allocator; copy the bearer for assertion.
        self.bearer_seen = self.allocator.dupe(u8, bearer_hex) catch null;
        return self.bearer_valid_returns;
    }

    fn lookupContact(
        ctx: ?*anyopaque,
        allocator: std.mem.Allocator,
        conversation_id: []const u8,
    ) anyerror!?[]u8 {
        const self: *TestEnv = @ptrCast(@alignCast(ctx.?));
        if (self.lookup_should_error) return error.LookupFailure;
        self.lookup_seen_conversation_id = self.allocator.dupe(u8, conversation_id) catch null;
        const phone = self.lookup_returns_phone orelse return null;
        return try allocator.dupe(u8, phone);
    }

    fn send(req: twilio_adapter.SendRequest, ctx: ?*anyopaque) anyerror!twilio_adapter.SendResponse {
        const self: *TestEnv = @ptrCast(@alignCast(ctx.?));
        self.sender_seen_url = self.allocator.dupe(u8, req.url) catch null;
        self.sender_seen_auth = self.allocator.dupe(u8, req.auth_header) catch null;
        self.sender_seen_body = self.allocator.dupe(u8, req.body) catch null;
        return twilio_adapter.SendResponse{
            .status_code = self.sender_canned_status,
            .body = self.sender_canned_body,
        };
    }

    fn persistMessage(
        ctx: ?*anyopaque,
        conversation_id: []const u8,
        body: []const u8,
        sid: []const u8,
    ) anyerror!void {
        const self: *TestEnv = @ptrCast(@alignCast(ctx.?));
        if (self.persist_should_error) return error.PersistFailure;
        self.persist_called = true;
        self.persist_seen_conversation_id = self.allocator.dupe(u8, conversation_id) catch null;
        self.persist_seen_body = self.allocator.dupe(u8, body) catch null;
        self.persist_seen_sid = self.allocator.dupe(u8, sid) catch null;
    }
};

const test_twilio_config = twilio_adapter.TwilioConfig{
    .account_sid = "AC0123456789",
    .auth_token = "tok",
    .sender_phone = "+61400000000",
};

fn makeAcceptor(env: *TestEnv, twilio_enabled: bool) Acceptor {
    return Acceptor{
        .allocator = env.allocator,
        .is_bearer_valid = TestEnv.isBearerValid,
        .is_bearer_valid_ctx = env,
        .twilio_config = if (twilio_enabled) test_twilio_config else null,
        .sender = TestEnv.send,
        .sender_ctx = env,
        .lookup_contact = TestEnv.lookupContact,
        .lookup_contact_ctx = env,
        .persist_message = TestEnv.persistMessage,
        .persist_message_ctx = env,
    };
}

test "acceptSend — happy path: 201 + persist + sent" {
    var env = TestEnv{ .allocator = testing.allocator };
    defer env.deinit();
    env.bearer_valid_returns = true;
    env.lookup_returns_phone = "+61412345678";

    const acceptor = makeAcceptor(&env, true);

    var result = try acceptSend(&acceptor, "bearer-hex", "conv-abc",
        \\{"body":"hello"}
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(AcceptResultKind.sent, result.kind);
    try testing.expectEqual(std.http.Status.ok, result.kind.httpStatus());

    // Sender was called with the right URL + body shape.
    try testing.expect(env.sender_seen_body != null);
    if (env.sender_seen_body) |b| {
        try testing.expect(std.mem.indexOf(u8, b, "To=%2B61412345678") != null);
        try testing.expect(std.mem.indexOf(u8, b, "Body=hello") != null);
    }

    // Lookup was called with the conversation id.
    try testing.expect(env.lookup_seen_conversation_id != null);
    if (env.lookup_seen_conversation_id) |s| {
        try testing.expectEqualStrings("conv-abc", s);
    }

    // Persist was called with the conversation + body + Twilio sid.
    try testing.expect(env.persist_called);
    if (env.persist_seen_sid) |s| try testing.expectEqualStrings("SM", s);
    if (env.persist_seen_body) |b| try testing.expectEqualStrings("hello", b);
}

test "acceptSend — missing bearer → unauthorised (401)" {
    var env = TestEnv{ .allocator = testing.allocator };
    defer env.deinit();

    const acceptor = makeAcceptor(&env, true);

    var result = try acceptSend(&acceptor, null, "conv-abc",
        \\{"body":"hello"}
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(AcceptResultKind.unauthorised, result.kind);
    // Lookup must not have been called.
    try testing.expectEqual(@as(?[]u8, null), env.lookup_seen_conversation_id);
    try testing.expect(!env.persist_called);
}

test "acceptSend — invalid bearer → unauthorised (401)" {
    var env = TestEnv{ .allocator = testing.allocator };
    defer env.deinit();
    env.bearer_valid_returns = false;

    const acceptor = makeAcceptor(&env, true);

    var result = try acceptSend(&acceptor, "bad-bearer", "conv-abc",
        \\{"body":"hello"}
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(AcceptResultKind.unauthorised, result.kind);
    try testing.expect(!env.persist_called);
}

test "acceptSend — conversation not found → not_found (404)" {
    var env = TestEnv{ .allocator = testing.allocator };
    defer env.deinit();
    env.lookup_returns_phone = null;

    const acceptor = makeAcceptor(&env, true);

    var result = try acceptSend(&acceptor, "bearer", "conv-missing",
        \\{"body":"hello"}
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(AcceptResultKind.not_found, result.kind);
    try testing.expect(env.sender_seen_url == null); // sender NOT called
    try testing.expect(!env.persist_called);
}

test "acceptSend — twilio not configured → twilio_disabled (503)" {
    var env = TestEnv{ .allocator = testing.allocator };
    defer env.deinit();
    env.lookup_returns_phone = "+61412345678";

    const acceptor = makeAcceptor(&env, false); // twilio_enabled = false

    var result = try acceptSend(&acceptor, "bearer", "conv-abc",
        \\{"body":"hello"}
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(AcceptResultKind.twilio_disabled, result.kind);
    try testing.expect(env.sender_seen_url == null);
    try testing.expect(!env.persist_called);
}

test "acceptSend — malformed JSON body → malformed_body (400)" {
    var env = TestEnv{ .allocator = testing.allocator };
    defer env.deinit();
    env.lookup_returns_phone = "+61412345678";

    const acceptor = makeAcceptor(&env, true);

    var result = try acceptSend(&acceptor, "bearer", "conv-abc", "{ not json");
    defer result.deinit(testing.allocator);

    try testing.expectEqual(AcceptResultKind.malformed_body, result.kind);
    try testing.expect(env.sender_seen_url == null);
    try testing.expect(!env.persist_called);
}

test "acceptSend — empty body string → malformed_body (400)" {
    var env = TestEnv{ .allocator = testing.allocator };
    defer env.deinit();
    env.lookup_returns_phone = "+61412345678";

    const acceptor = makeAcceptor(&env, true);

    var result = try acceptSend(&acceptor, "bearer", "conv-abc",
        \\{"body":""}
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(AcceptResultKind.malformed_body, result.kind);
    try testing.expect(env.sender_seen_url == null);
    try testing.expect(!env.persist_called);
}

test "acceptSend — twilio rate-limited → rate_limited (429)" {
    var env = TestEnv{ .allocator = testing.allocator };
    defer env.deinit();
    env.lookup_returns_phone = "+61412345678";
    env.sender_canned_status = 429;
    env.sender_canned_body = "{\"code\":20429,\"message\":\"too many\"}";

    const acceptor = makeAcceptor(&env, true);

    var result = try acceptSend(&acceptor, "bearer", "conv-abc",
        \\{"body":"hello"}
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(AcceptResultKind.rate_limited, result.kind);
    try testing.expect(!env.persist_called); // no persist on send failure
}

test "acceptSend — twilio invalid_recipient → invalid_recipient (422)" {
    var env = TestEnv{ .allocator = testing.allocator };
    defer env.deinit();
    env.lookup_returns_phone = "+61412345678";
    env.sender_canned_status = 400;
    env.sender_canned_body = "{\"code\":21211,\"message\":\"invalid To\"}";

    const acceptor = makeAcceptor(&env, true);

    var result = try acceptSend(&acceptor, "bearer", "conv-abc",
        \\{"body":"hello"}
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(AcceptResultKind.invalid_recipient, result.kind);
    try testing.expect(!env.persist_called);
}

```
