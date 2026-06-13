---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/flow_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.215690+00:00
---

# runtime/semantos-brain/src/flow_http.zig

```zig
// D-brain-flow-runner-api — Brain-side flow execution state machine HTTP surface.
//
// Flow execution state (FlowRunState) lives in the brain; the shell polls or
// WSS-subscribes for transitions.  Flows are triggered by intent classification
// (D-brain-intent-classifier-api) and stepped by user actions.
//
// Routes:
//   POST /api/v1/flow/run              → start a new flow run
//   GET  /api/v1/flow/{runId}          → get current run state
//   POST /api/v1/flow/{runId}/step     → advance / approve / cancel a run
//
// All deps injected via fn pointers; tests use plain stubs (no persistent state).
// The reactor calls `accept(acceptor, method, path, bearer, body)` with the
// full path starting at "/api/v1/flow".
//
// Run lifecycle:
//   running → completed | cancelled | failed
//
// V1 note: guard evaluation (capability / time / value guards) is deferred to
// D-brain-flow-runner-api phase-2 together with WSS-subscribe for transitions.
// The wire shape is intentionally stable from V1 onwards.

const std = @import("std");

// ── Result kinds ──────────────────────────────────────────────────────

pub const ResultKind = enum {
    ok, // 200
    created, // 201
    bad_request, // 400
    unauthorised, // 401
    not_found, // 404
    method_not_allowed, // 405
    internal_error, // 500

    pub fn httpStatus(self: ResultKind) u16 {
        return switch (self) {
            .ok => 200,
            .created => 201,
            .bad_request => 400,
            .unauthorised => 401,
            .not_found => 404,
            .method_not_allowed => 405,
            .internal_error => 500,
        };
    }
};

pub const AcceptResult = struct {
    kind: ResultKind,
    body: []u8 = &.{},

    pub fn deinit(self: *AcceptResult, allocator: std.mem.Allocator) void {
        if (self.body.len > 0) allocator.free(self.body);
        self.body = &.{};
    }
};

// ── DI fn pointers ────────────────────────────────────────────────────

/// Returns true iff the hex-encoded bearer is valid.
pub const IsBearerValidFn = *const fn (ctx: ?*anyopaque, bearer: []const u8) bool;

/// Start a new flow run.
/// `flow_id`: identifies the flow definition (e.g. "quote-request").
/// `context_json`: initial context as JSON object string.
/// Returns the full run state JSON ({run_id, flow_id, status, current_step}).
/// Caller frees.
pub const StartFlowFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    flow_id: []const u8,
    context_json: []const u8,
) anyerror![]u8;

/// Get the current state of a run by id.
/// Returns the state JSON or null when run_id is not found.
/// Caller frees the non-null slice.
pub const GetFlowStateFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    run_id: []const u8,
) anyerror!?[]u8;

/// Advance a run by one step.
/// `action`: "advance" | "approve" | "cancel".
/// `payload_json`: optional step-specific payload as JSON object string.
/// Returns updated state JSON or null when run_id is not found.
/// Caller frees the non-null slice.
pub const StepFlowFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    run_id: []const u8,
    action: []const u8,
    payload_json: []const u8,
) anyerror!?[]u8;

// ── Acceptor ──────────────────────────────────────────────────────────

pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    is_bearer_valid: IsBearerValidFn,
    is_bearer_valid_ctx: ?*anyopaque = null,
    start_flow: StartFlowFn,
    start_flow_ctx: ?*anyopaque = null,
    get_flow_state: GetFlowStateFn,
    get_flow_state_ctx: ?*anyopaque = null,
    step_flow: StepFlowFn,
    step_flow_ctx: ?*anyopaque = null,
};

// ── Routing ───────────────────────────────────────────────────────────

const FLOW_PREFIX = "/api/v1/flow";

/// Pure-logic acceptor.  `path` starts with "/api/v1/flow".
/// `body` is the raw request body (empty string for GET).
pub fn accept(
    acceptor: *const Acceptor,
    method: []const u8,
    path: []const u8,
    bearer: ?[]const u8,
    body: []const u8,
) anyerror!AcceptResult {
    const alloc = acceptor.allocator;

    // ── Bearer auth ──────────────────────────────────────────────────
    const b = bearer orelse {
        return .{
            .kind = .unauthorised,
            .body = try alloc.dupe(u8, "{\"error\":\"unauthorised\"}"),
        };
    };
    if (!acceptor.is_bearer_valid(acceptor.is_bearer_valid_ctx, b)) {
        return .{
            .kind = .unauthorised,
            .body = try alloc.dupe(u8, "{\"error\":\"unauthorised\"}"),
        };
    }

    if (!std.mem.startsWith(u8, path, FLOW_PREFIX)) {
        return .{ .kind = .not_found, .body = try alloc.dupe(u8, "{\"error\":\"not_found\"}") };
    }
    const suffix = path[FLOW_PREFIX.len..]; // "", "/run", "/{runId}", "/{runId}/step"

    // ── POST /api/v1/flow/run — start a new run ──────────────────────
    if (std.mem.eql(u8, suffix, "/run")) {
        if (!std.mem.eql(u8, method, "POST")) {
            return .{
                .kind = .method_not_allowed,
                .body = try alloc.dupe(u8,
                    "{\"error\":\"method_not_allowed\",\"hint\":\"POST required\"}"),
            };
        }
        // Parse {flow_id, context} from body.
        const flow_id = parseFlowIdFromBody(alloc, body) catch {
            return .{
                .kind = .bad_request,
                .body = try alloc.dupe(u8,
                    "{\"error\":\"bad_request\",\"hint\":\"flow_id required\"}"),
            };
        };
        defer alloc.free(flow_id);
        // extractContextJson returns a borrowed slice (body or literal "{}");
        // it does NOT allocate, so no free is needed.
        const context_json = extractContextJson(alloc, body) catch "{}";

        const state_json = acceptor.start_flow(
            acceptor.start_flow_ctx, alloc, flow_id, context_json) catch {
            return .{
                .kind = .internal_error,
                .body = try alloc.dupe(u8, "{\"error\":\"internal_error\"}"),
            };
        };
        return .{ .kind = .created, .body = state_json };
    }

    // ── Routes with {runId} ──────────────────────────────────────────
    if (suffix.len == 0 or suffix[0] != '/') {
        return .{ .kind = .not_found, .body = try alloc.dupe(u8, "{\"error\":\"not_found\"}") };
    }
    const after_slash = suffix[1..]; // "{runId}" or "{runId}/step"

    // Determine run_id (before optional "/step")
    var run_id: []const u8 = undefined;
    var is_step_endpoint = false;

    if (std.mem.indexOf(u8, after_slash, "/")) |slash_pos| {
        run_id = after_slash[0..slash_pos];
        const rest = after_slash[slash_pos..]; // includes leading "/"
        if (std.mem.eql(u8, rest, "/step")) {
            is_step_endpoint = true;
        } else {
            // Unknown sub-path
            return .{ .kind = .not_found, .body = try alloc.dupe(u8, "{\"error\":\"not_found\"}") };
        }
    } else {
        run_id = after_slash;
    }

    if (run_id.len == 0) {
        return .{ .kind = .not_found, .body = try alloc.dupe(u8, "{\"error\":\"not_found\"}") };
    }

    if (is_step_endpoint) {
        // ── POST /api/v1/flow/{runId}/step ───────────────────────────
        if (!std.mem.eql(u8, method, "POST")) {
            return .{
                .kind = .method_not_allowed,
                .body = try alloc.dupe(u8,
                    "{\"error\":\"method_not_allowed\",\"hint\":\"POST required\"}"),
            };
        }
        const action = parseActionFromBody(alloc, body) catch {
            return .{
                .kind = .bad_request,
                .body = try alloc.dupe(u8,
                    "{\"error\":\"bad_request\",\"hint\":\"action required: advance|approve|cancel\"}"),
            };
        };
        defer alloc.free(action);
        if (!isValidAction(action)) {
            return .{
                .kind = .bad_request,
                .body = try alloc.dupe(u8,
                    "{\"error\":\"bad_request\",\"hint\":\"action must be advance|approve|cancel\"}"),
            };
        }
        const state_opt = acceptor.step_flow(
            acceptor.step_flow_ctx, alloc, run_id, action, body) catch {
            return .{
                .kind = .internal_error,
                .body = try alloc.dupe(u8, "{\"error\":\"internal_error\"}"),
            };
        };
        if (state_opt) |state_json| {
            return .{ .kind = .ok, .body = state_json };
        }
        return .{ .kind = .not_found, .body = try alloc.dupe(u8, "{\"error\":\"not_found\"}") };
    } else {
        // ── GET /api/v1/flow/{runId} ─────────────────────────────────
        if (!std.mem.eql(u8, method, "GET")) {
            return .{
                .kind = .method_not_allowed,
                .body = try alloc.dupe(u8,
                    "{\"error\":\"method_not_allowed\",\"hint\":\"GET required\"}"),
            };
        }
        const state_opt = acceptor.get_flow_state(
            acceptor.get_flow_state_ctx, alloc, run_id) catch {
            return .{
                .kind = .internal_error,
                .body = try alloc.dupe(u8, "{\"error\":\"internal_error\"}"),
            };
        };
        if (state_opt) |state_json| {
            return .{ .kind = .ok, .body = state_json };
        }
        return .{ .kind = .not_found, .body = try alloc.dupe(u8, "{\"error\":\"not_found\"}") };
    }
}

// ── Body-parsing helpers (minimal JSON extraction, no full parse) ─────

/// Extract `flow_id` from `{"flow_id":"<value>",...}`.
/// Returns owned slice; caller frees.
fn parseFlowIdFromBody(alloc: std.mem.Allocator, body: []const u8) ![]u8 {
    return extractStringField(alloc, body, "flow_id");
}

/// Extract `action` from `{"action":"<value>",...}`.
fn parseActionFromBody(alloc: std.mem.Allocator, body: []const u8) ![]u8 {
    return extractStringField(alloc, body, "action");
}

/// Minimal string-field extractor — finds `"<field>":"<value>"` and returns
/// the value as an owned slice.  Does not handle escaped quotes in values
/// (flow_id / action are identifiers; that's fine for V1).
fn extractStringField(alloc: std.mem.Allocator, src: []const u8, field: []const u8) ![]u8 {
    // Build the key pattern: `"field":"`
    var key_buf: [64]u8 = undefined;
    const key = try std.fmt.bufPrint(&key_buf, "\"{s}\":\"", .{field});
    const start_pos = std.mem.indexOf(u8, src, key) orelse return error.not_found;
    const value_start = start_pos + key.len;
    if (value_start >= src.len) return error.not_found;
    const end_pos = std.mem.indexOfScalarPos(u8, src, value_start, '"') orelse return error.not_found;
    const value = src[value_start..end_pos];
    if (value.len == 0) return error.not_found;
    return alloc.dupe(u8, value);
}

/// Extract the raw `context` JSON value from the body.
/// If absent returns the literal string "{}" (no allocation).
fn extractContextJson(alloc: std.mem.Allocator, body: []const u8) ![]const u8 {
    _ = alloc;
    // Look for `"context":` and return everything after it to the matching `}`.
    // V1: just return the whole body as context.  Phase-2 can narrow this.
    const marker = "\"context\":";
    if (std.mem.indexOf(u8, body, marker) == null) return "{}";
    return body; // caller treats whole body as context for now
}

fn isValidAction(action: []const u8) bool {
    return std.mem.eql(u8, action, "advance") or
        std.mem.eql(u8, action, "approve") or
        std.mem.eql(u8, action, "cancel");
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

fn stubBearerOk(_: ?*anyopaque, _: []const u8) bool {
    return true;
}
fn stubBearerDeny(_: ?*anyopaque, _: []const u8) bool {
    return false;
}

const RUN_STATE = "{\"run_id\":\"r1\",\"flow_id\":\"quote-request\",\"status\":\"running\",\"current_step\":\"collect_address\"}";
const STEPPED_STATE = "{\"run_id\":\"r1\",\"flow_id\":\"quote-request\",\"status\":\"running\",\"current_step\":\"collect_date\"}";

fn stubStartFlow(
    _: ?*anyopaque,
    allocator: std.mem.Allocator,
    _: []const u8,
    _: []const u8,
) anyerror![]u8 {
    return allocator.dupe(u8, RUN_STATE);
}

fn stubGetFlowState(
    _: ?*anyopaque,
    allocator: std.mem.Allocator,
    run_id: []const u8,
) anyerror!?[]u8 {
    if (std.mem.eql(u8, run_id, "r1")) {
        return @as(?[]u8, try allocator.dupe(u8, RUN_STATE));
    }
    return null;
}

fn stubStepFlow(
    _: ?*anyopaque,
    allocator: std.mem.Allocator,
    run_id: []const u8,
    _: []const u8,
    _: []const u8,
) anyerror!?[]u8 {
    if (std.mem.eql(u8, run_id, "r1")) {
        return @as(?[]u8, try allocator.dupe(u8, STEPPED_STATE));
    }
    return null;
}

fn makeAcceptor(alloc: std.mem.Allocator, bearer_fn: IsBearerValidFn) Acceptor {
    return .{
        .allocator = alloc,
        .is_bearer_valid = bearer_fn,
        .start_flow = stubStartFlow,
        .get_flow_state = stubGetFlowState,
        .step_flow = stubStepFlow,
    };
}

test "POST /api/v1/flow/run — created" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    const body = "{\"flow_id\":\"quote-request\",\"context\":{}}";
    var r = try accept(&a, "POST", "/api/v1/flow/run", "beef", body);
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.created, r.kind);
    try std.testing.expectEqual(@as(u16, 201), r.kind.httpStatus());
    try std.testing.expectEqualStrings(RUN_STATE, r.body);
}

test "POST /api/v1/flow/run missing flow_id — bad_request" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "POST", "/api/v1/flow/run", "beef", "{}");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.bad_request, r.kind);
}

test "GET /api/v1/flow/r1 — ok" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "GET", "/api/v1/flow/r1", "beef", "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.ok, r.kind);
    try std.testing.expectEqualStrings(RUN_STATE, r.body);
}

test "GET /api/v1/flow/unknown — not_found" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "GET", "/api/v1/flow/nope", "beef", "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.not_found, r.kind);
}

test "POST /api/v1/flow/r1/step advance — ok" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "POST", "/api/v1/flow/r1/step", "beef", "{\"action\":\"advance\"}");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.ok, r.kind);
    try std.testing.expectEqualStrings(STEPPED_STATE, r.body);
}

test "POST /api/v1/flow/r1/step cancel — ok" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "POST", "/api/v1/flow/r1/step", "beef", "{\"action\":\"cancel\"}");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.ok, r.kind);
}

test "POST /api/v1/flow/r1/step bad action — bad_request" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "POST", "/api/v1/flow/r1/step", "beef", "{\"action\":\"explode\"}");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.bad_request, r.kind);
}

test "POST /api/v1/flow/unknown/step — not_found" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "POST", "/api/v1/flow/nope/step", "beef", "{\"action\":\"advance\"}");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.not_found, r.kind);
}

test "no bearer — unauthorised" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "GET", "/api/v1/flow/r1", null, "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.unauthorised, r.kind);
    try std.testing.expectEqual(@as(u16, 401), r.kind.httpStatus());
}

test "invalid bearer — unauthorised" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerDeny);
    var r = try accept(&a, "GET", "/api/v1/flow/r1", "bad", "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.unauthorised, r.kind);
}

test "GET on /flow/run — method_not_allowed" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "GET", "/api/v1/flow/run", "beef", "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.method_not_allowed, r.kind);
    try std.testing.expectEqual(@as(u16, 405), r.kind.httpStatus());
}

test "POST on GET-only state endpoint — method_not_allowed" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "POST", "/api/v1/flow/r1", "beef", "{}");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.method_not_allowed, r.kind);
}

test "httpStatus mapping" {
    try std.testing.expectEqual(@as(u16, 200), ResultKind.ok.httpStatus());
    try std.testing.expectEqual(@as(u16, 201), ResultKind.created.httpStatus());
    try std.testing.expectEqual(@as(u16, 400), ResultKind.bad_request.httpStatus());
    try std.testing.expectEqual(@as(u16, 401), ResultKind.unauthorised.httpStatus());
    try std.testing.expectEqual(@as(u16, 404), ResultKind.not_found.httpStatus());
    try std.testing.expectEqual(@as(u16, 405), ResultKind.method_not_allowed.httpStatus());
    try std.testing.expectEqual(@as(u16, 500), ResultKind.internal_error.httpStatus());
}

```
