---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/intent_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.245358+00:00
---

# runtime/semantos-brain/src/intent_http.zig

```zig
// D-brain-intent-classifier-api — HTTP acceptor for /api/v1/intent/*.
//
// Routes:
//   POST /api/v1/intent/classify          → text → IntentClassification JSON
//   GET  /api/v1/intent/taxonomy          → assembled taxonomy tree JSON
//   POST /api/v1/intent/taxonomy/inject   → merge extension grammar nodes
//
// All endpoints are bearer-gated. Deps injected via fn pointers;
// tests use plain stubs (no dispatcher, no LLM).
//
// The classify fn returns raw JSON from the dispatcher — the HTTP layer
// does not introspect the classification shape, it passes it through.
// The taxonomy fn similarly returns raw JSON. This keeps the Zig layer
// thin and avoids coupling it to the TS-side IntentClassification type.

const std = @import("std");

// ── Result kinds ──────────────────────────────────────────────────────

pub const AcceptResultKind = enum {
    ok, // 200
    created, // 201
    no_content, // 204
    bad_request, // 400
    unauthorised, // 401
    not_found, // 404
    method_not_allowed, // 405
    internal_error, // 500

    pub fn httpStatus(self: AcceptResultKind) u16 {
        return switch (self) {
            .ok => 200,
            .created => 201,
            .no_content => 204,
            .bad_request => 400,
            .unauthorised => 401,
            .not_found => 404,
            .method_not_allowed => 405,
            .internal_error => 500,
        };
    }
};

pub const AcceptResult = struct {
    kind: AcceptResultKind,
    body: []u8 = &.{},

    pub fn deinit(self: *AcceptResult, allocator: std.mem.Allocator) void {
        if (self.body.len > 0) allocator.free(self.body);
        self.body = &.{};
    }
};

// ── DI fn-pointer types ───────────────────────────────────────────────

pub const IsBearerValidFn = *const fn (ctx: ?*anyopaque, bearer: []const u8) bool;

/// Classify a text input. Returns owned JSON bytes:
///   {"verb":"create.job","confidence":0.87,"params":{},"correlation_id":"..."}
/// Caller owns the returned slice (allocator.free).
pub const ClassifyFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    text: []const u8,
    source: ?[]const u8,
) anyerror![]u8;

/// Return the assembled taxonomy tree as owned JSON bytes:
///   {"domains":[...],"injected_at":<ms>}
/// Caller owns the returned slice (allocator.free).
pub const GetTaxonomyFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]u8;

/// Inject extension grammar nodes. Body is raw JSON with the injection spec.
/// Returns on success; any error maps to 400.
pub const InjectTaxonomyFn = *const fn (
    ctx: ?*anyopaque,
    grammar_json: []const u8,
) anyerror!void;

pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    is_bearer_valid: IsBearerValidFn,
    is_bearer_valid_ctx: ?*anyopaque = null,

    classify: ClassifyFn,
    classify_ctx: ?*anyopaque = null,

    get_taxonomy: GetTaxonomyFn,
    get_taxonomy_ctx: ?*anyopaque = null,

    /// Optional — if null, inject returns 200 OK without side-effect.
    inject_taxonomy: ?InjectTaxonomyFn = null,
    inject_taxonomy_ctx: ?*anyopaque = null,
};

// ── Entry point ───────────────────────────────────────────────────────

/// `path` starts with "/api/v1/intent".
pub fn accept(
    acceptor: *const Acceptor,
    method: []const u8,
    path: []const u8,
    bearer: ?[]const u8,
    body: []const u8,
) anyerror!AcceptResult {
    // Bearer gate — always first.
    const bh = bearer orelse return AcceptResult{ .kind = .unauthorised };
    if (!acceptor.is_bearer_valid(acceptor.is_bearer_valid_ctx, bh))
        return AcceptResult{ .kind = .unauthorised };

    const base = "/api/v1/intent";
    const suffix = if (path.len >= base.len) path[base.len..] else "";

    // POST /api/v1/intent/classify
    if (std.mem.eql(u8, suffix, "/classify") or std.mem.eql(u8, suffix, "/classify/")) {
        if (!std.mem.eql(u8, method, "POST")) return AcceptResult{ .kind = .method_not_allowed };
        return handleClassify(acceptor, body);
    }

    // GET /api/v1/intent/taxonomy
    if (std.mem.eql(u8, suffix, "/taxonomy") or std.mem.eql(u8, suffix, "/taxonomy/")) {
        if (!std.mem.eql(u8, method, "GET")) return AcceptResult{ .kind = .method_not_allowed };
        return handleGetTaxonomy(acceptor);
    }

    // POST /api/v1/intent/taxonomy/inject
    if (std.mem.eql(u8, suffix, "/taxonomy/inject") or std.mem.eql(u8, suffix, "/taxonomy/inject/")) {
        if (!std.mem.eql(u8, method, "POST")) return AcceptResult{ .kind = .method_not_allowed };
        return handleInjectTaxonomy(acceptor, body);
    }

    return AcceptResult{ .kind = .not_found };
}

// ── Route handlers ────────────────────────────────────────────────────

fn handleClassify(acceptor: *const Acceptor, body: []const u8) anyerror!AcceptResult {
    // Parse request body for `text` field (required) and optional `source`.
    const parsed = std.json.parseFromSlice(std.json.Value, acceptor.allocator, body, .{}) catch
        return AcceptResult{ .kind = .bad_request };
    defer parsed.deinit();

    if (parsed.value != .object) return AcceptResult{ .kind = .bad_request };
    const obj = parsed.value.object;

    const text = switch (obj.get("text") orelse return AcceptResult{ .kind = .bad_request }) {
        .string => |s| s,
        else => return AcceptResult{ .kind = .bad_request },
    };
    if (text.len == 0) return AcceptResult{ .kind = .bad_request };

    const source: ?[]const u8 = blk: {
        if (obj.get("source")) |sv| {
            switch (sv) {
                .string => |s| break :blk s,
                else => break :blk null,
            }
        }
        break :blk null;
    };

    const result_json = acceptor.classify(acceptor.classify_ctx, acceptor.allocator, text, source) catch
        return AcceptResult{ .kind = .internal_error };

    return AcceptResult{ .kind = .ok, .body = result_json };
}

fn handleGetTaxonomy(acceptor: *const Acceptor) anyerror!AcceptResult {
    const taxonomy_json = acceptor.get_taxonomy(acceptor.get_taxonomy_ctx, acceptor.allocator) catch
        return AcceptResult{ .kind = .internal_error };
    return AcceptResult{ .kind = .ok, .body = taxonomy_json };
}

fn handleInjectTaxonomy(acceptor: *const Acceptor, body: []const u8) anyerror!AcceptResult {
    if (body.len == 0) return AcceptResult{ .kind = .bad_request };

    // Validate it's at least parseable JSON object.
    const parsed = std.json.parseFromSlice(std.json.Value, acceptor.allocator, body, .{}) catch
        return AcceptResult{ .kind = .bad_request };
    parsed.deinit();

    if (acceptor.inject_taxonomy) |inj| {
        inj(acceptor.inject_taxonomy_ctx, body) catch
            return AcceptResult{ .kind = .bad_request };
    }

    return AcceptResult{ .kind = .no_content };
}

// ── Tests ─────────────────────────────────────────────────────────────

const testing = std.testing;

fn validBearer(_: ?*anyopaque, b: []const u8) bool {
    return std.mem.eql(u8, b, "testtoken");
}

const StubClassify = struct {
    fn classify(_: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, _: ?[]const u8) anyerror![]u8 {
        const json =
            \\{"verb":"create.job","confidence":0.87,"params":{},"correlation_id":"test-cid-1"}
        ;
        return allocator.dupe(u8, json);
    }
};

const StubTaxonomy = struct {
    fn getTaxonomy(_: ?*anyopaque, allocator: std.mem.Allocator) anyerror![]u8 {
        const json =
            \\{"domains":[{"id":"create","label":"Create","description":"Create objects","children":[]}],"injected_at":0}
        ;
        return allocator.dupe(u8, json);
    }
};

fn makeAcceptor() Acceptor {
    return .{
        .allocator = testing.allocator,
        .is_bearer_valid = validBearer,
        .classify = StubClassify.classify,
        .get_taxonomy = StubTaxonomy.getTaxonomy,
    };
}

test "missing bearer → 401" {
    const a = makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/intent/classify", null, "{\"text\":\"create a job\"}");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.unauthorised, r.kind);
}

test "wrong bearer → 401" {
    const a = makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/intent/classify", "badtoken", "{\"text\":\"create a job\"}");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.unauthorised, r.kind);
}

test "POST classify valid text → 200 with verb and confidence" {
    const a = makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/intent/classify", "testtoken",
        \\{"text":"create a carpentry job for Alice"}
    );
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.ok, r.kind);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"verb\":") != null);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"confidence\":") != null);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"correlation_id\":") != null);
}

test "POST classify with source field → 200" {
    const a = makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/intent/classify", "testtoken",
        \\{"text":"create a job","source":"voice"}
    );
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.ok, r.kind);
}

test "POST classify missing text → 400" {
    const a = makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/intent/classify", "testtoken",
        \\{"source":"nl"}
    );
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.bad_request, r.kind);
}

test "POST classify empty text → 400" {
    const a = makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/intent/classify", "testtoken",
        \\{"text":""}
    );
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.bad_request, r.kind);
}

test "POST classify malformed JSON → 400" {
    const a = makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/intent/classify", "testtoken", "not json");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.bad_request, r.kind);
}

test "GET taxonomy → 200 with domains array" {
    const a = makeAcceptor();
    var r = try accept(&a, "GET", "/api/v1/intent/taxonomy", "testtoken", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.ok, r.kind);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"domains\":") != null);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"id\":\"create\"") != null);
}

test "POST to /taxonomy (not /taxonomy/inject) → 405" {
    const a = makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/intent/taxonomy", "testtoken", "{}");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.method_not_allowed, r.kind);
}

test "POST taxonomy/inject with no inject fn → 204 no-op" {
    const a = makeAcceptor(); // inject_taxonomy is null
    var r = try accept(&a, "POST", "/api/v1/intent/taxonomy/inject", "testtoken",
        \\{"extensionId":"test-ext","inject":[]}
    );
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.no_content, r.kind);
}

test "POST taxonomy/inject empty body → 400" {
    const a = makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/intent/taxonomy/inject", "testtoken", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.bad_request, r.kind);
}

test "GET on classify route → 405" {
    const a = makeAcceptor();
    var r = try accept(&a, "GET", "/api/v1/intent/classify", "testtoken", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.method_not_allowed, r.kind);
}

test "unknown sub-path → 404" {
    const a = makeAcceptor();
    var r = try accept(&a, "GET", "/api/v1/intent/unknown", "testtoken", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.not_found, r.kind);
}

```
