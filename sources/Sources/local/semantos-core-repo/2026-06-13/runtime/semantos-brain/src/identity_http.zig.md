---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/identity_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.252851+00:00
---

# runtime/semantos-brain/src/identity_http.zig

```zig
// D-brain-identity-store-api — HTTP acceptor for /api/v1/identity/*.
//
// Routes:
//   GET  /api/v1/identity/hat            → active hat for the authenticated bearer
//   GET  /api/v1/identity/hats           → list all known hats (admin view)
//   POST /api/v1/identity/hat/switch     → switch active hat  {hat_id: string}
//   GET  /api/v1/identity/cert           → cert snapshot for the authenticated bearer
//
// All endpoints are bearer-gated.  Deps injected via fn pointers;
// tests use plain stubs (no LMDB, no identity_certs).
//
// Design: hat sessions become brain-side state consistent with the
// sovereign-node framing — identity belongs to the brain, not the
// browser.  loom-svelte previously held hat sessions in localStorage;
// these endpoints let the shell replace localStorage reads with brain
// API calls (Pattern T shell-port arc, D-brain-identity-store-api).
//
// Fn pointers return owned JSON bytes (like intent_http) so the Zig
// layer does not own or free any string fields — ownership is simple
// and the serving code stays thin.

const std = @import("std");

// ── Result kinds ──────────────────────────────────────────────────────

pub const AcceptResultKind = enum {
    ok, // 200
    no_content, // 204
    bad_request, // 400
    unauthorised, // 401
    not_found, // 404
    method_not_allowed, // 405
    internal_error, // 500

    pub fn httpStatus(self: AcceptResultKind) u16 {
        return switch (self) {
            .ok => 200,
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
//
// All fn pointers return owned JSON bytes (caller must allocator.free)
// or null for "not found".  This avoids the struct-with-string-slices
// ownership problem — the fn pointer impl serialises its own data.

pub const IsBearerValidFn = *const fn (ctx: ?*anyopaque, bearer: []const u8) bool;

/// Return JSON bytes for the active hat of the given bearer, or null.
/// Shape: {"id":...,"hat_id":...,"hat_name":...,"cert_id":...,
///         "bearer_fingerprint":...,"brain_base_url":...,"color_hex":...,
///         "logged_in_at":<ms>,"last_used_at":<ms>,"is_active":true}
/// Caller owns the returned slice (allocator.free). null = not found.
pub const GetActiveHatFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    bearer: []const u8,
) anyerror!?[]u8;

/// Return JSON bytes for all hats.
/// Shape: {"hats":[<HatInfo>, ...]}
/// Caller owns the returned slice (allocator.free).
pub const ListHatsFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]u8;

/// Switch the active hat.  `hat_id` is the hat's stable id field.
/// Returns `error.NotFound` if no hat with that id exists.
pub const SwitchHatFn = *const fn (
    ctx: ?*anyopaque,
    hat_id: []const u8,
) anyerror!void;

/// Return JSON bytes for the cert snapshot of the given bearer, or null.
/// Shape: {"cert_id":...,"label":...,"issued_at":...,"push_platform":...,"active":true}
/// Caller owns the returned slice. null = no cert linked to this bearer.
pub const GetCertFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    bearer: []const u8,
) anyerror!?[]u8;

pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    is_bearer_valid: IsBearerValidFn,
    is_bearer_valid_ctx: ?*anyopaque = null,

    get_active_hat: GetActiveHatFn,
    get_active_hat_ctx: ?*anyopaque = null,

    list_hats: ListHatsFn,
    list_hats_ctx: ?*anyopaque = null,

    /// Optional — if null, switch returns 204 No Content without side-effect.
    switch_hat: ?SwitchHatFn = null,
    switch_hat_ctx: ?*anyopaque = null,

    /// Optional — if null, GET /api/v1/identity/cert returns 404.
    get_cert: ?GetCertFn = null,
    get_cert_ctx: ?*anyopaque = null,
};

// ── Entry point ───────────────────────────────────────────────────────

/// `path` starts with "/api/v1/identity".
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

    const base = "/api/v1/identity";
    const suffix = if (path.len >= base.len) path[base.len..] else "";

    // GET /api/v1/identity/hat
    if (std.mem.eql(u8, suffix, "/hat") or std.mem.eql(u8, suffix, "/hat/")) {
        if (!std.mem.eql(u8, method, "GET")) return AcceptResult{ .kind = .method_not_allowed };
        return handleGetActiveHat(acceptor, bh);
    }

    // POST /api/v1/identity/hat/switch
    if (std.mem.eql(u8, suffix, "/hat/switch") or std.mem.eql(u8, suffix, "/hat/switch/")) {
        if (!std.mem.eql(u8, method, "POST")) return AcceptResult{ .kind = .method_not_allowed };
        return handleSwitchHat(acceptor, body);
    }

    // GET /api/v1/identity/hats
    if (std.mem.eql(u8, suffix, "/hats") or std.mem.eql(u8, suffix, "/hats/")) {
        if (!std.mem.eql(u8, method, "GET")) return AcceptResult{ .kind = .method_not_allowed };
        return handleListHats(acceptor);
    }

    // GET /api/v1/identity/cert
    if (std.mem.eql(u8, suffix, "/cert") or std.mem.eql(u8, suffix, "/cert/")) {
        if (!std.mem.eql(u8, method, "GET")) return AcceptResult{ .kind = .method_not_allowed };
        return handleGetCert(acceptor, bh);
    }

    return AcceptResult{ .kind = .not_found };
}

// ── Route handlers ────────────────────────────────────────────────────

fn handleGetActiveHat(acceptor: *const Acceptor, bearer: []const u8) anyerror!AcceptResult {
    const json = acceptor.get_active_hat(
        acceptor.get_active_hat_ctx,
        acceptor.allocator,
        bearer,
    ) catch return AcceptResult{ .kind = .internal_error };

    const body = json orelse return AcceptResult{ .kind = .not_found };
    return AcceptResult{ .kind = .ok, .body = body };
}

fn handleListHats(acceptor: *const Acceptor) anyerror!AcceptResult {
    const body = acceptor.list_hats(
        acceptor.list_hats_ctx,
        acceptor.allocator,
    ) catch return AcceptResult{ .kind = .internal_error };
    return AcceptResult{ .kind = .ok, .body = body };
}

fn handleSwitchHat(acceptor: *const Acceptor, body: []const u8) anyerror!AcceptResult {
    // Parse body for hat_id field.
    const parsed = std.json.parseFromSlice(std.json.Value, acceptor.allocator, body, .{}) catch
        return AcceptResult{ .kind = .bad_request };
    defer parsed.deinit();

    if (parsed.value != .object) return AcceptResult{ .kind = .bad_request };
    const hat_id = switch (parsed.value.object.get("hat_id") orelse
        return AcceptResult{ .kind = .bad_request })
    {
        .string => |s| s,
        else => return AcceptResult{ .kind = .bad_request },
    };
    if (hat_id.len == 0) return AcceptResult{ .kind = .bad_request };

    if (acceptor.switch_hat) |sf| {
        sf(acceptor.switch_hat_ctx, hat_id) catch |e| switch (e) {
            error.NotFound => return AcceptResult{ .kind = .not_found },
            else => return AcceptResult{ .kind = .internal_error },
        };
    }

    return AcceptResult{ .kind = .no_content };
}

fn handleGetCert(acceptor: *const Acceptor, bearer: []const u8) anyerror!AcceptResult {
    const get_cert = acceptor.get_cert orelse return AcceptResult{ .kind = .not_found };

    const json = get_cert(acceptor.get_cert_ctx, acceptor.allocator, bearer) catch
        return AcceptResult{ .kind = .internal_error };
    const body = json orelse return AcceptResult{ .kind = .not_found };
    return AcceptResult{ .kind = .ok, .body = body };
}

// ── Tests ─────────────────────────────────────────────────────────────

const testing = std.testing;

fn validBearer(_: ?*anyopaque, b: []const u8) bool {
    return std.mem.eql(u8, b, "testtoken");
}

const hatJson =
    \\{"id":"hat-uuid-1","hat_id":"tradie","hat_name":"Todd's Tradie Hat","cert_id":"abcdef12","bearer_fingerprint":"aaaa","brain_base_url":"","color_hex":"#4A90D9","logged_in_at":1716512345000,"last_used_at":1716519999000,"is_active":true}
;

const hatsJson =
    \\{"hats":[{"id":"hat-uuid-1","hat_id":"tradie","hat_name":"Todd's Tradie Hat","cert_id":"","bearer_fingerprint":"","brain_base_url":"","color_hex":"","logged_in_at":0,"last_used_at":0,"is_active":true}]}
;

const emptyHatsJson =
    \\{"hats":[]}
;

const StubHatStore = struct {
    has_hat: bool,

    fn getActiveHat(ctx: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8) anyerror!?[]u8 {
        const self: *const StubHatStore = @ptrCast(@alignCast(ctx.?));
        if (!self.has_hat) return null;
        return @as(?[]u8, try allocator.dupe(u8, hatJson));
    }

    fn listHats(ctx: ?*anyopaque, allocator: std.mem.Allocator) anyerror![]u8 {
        const self: *const StubHatStore = @ptrCast(@alignCast(ctx.?));
        if (self.has_hat) return allocator.dupe(u8, hatsJson);
        return allocator.dupe(u8, emptyHatsJson);
    }
};

fn makeAcceptor(store: *const StubHatStore) Acceptor {
    return .{
        .allocator = testing.allocator,
        .is_bearer_valid = validBearer,
        .get_active_hat = StubHatStore.getActiveHat,
        .get_active_hat_ctx = @constCast(@ptrCast(store)),
        .list_hats = StubHatStore.listHats,
        .list_hats_ctx = @constCast(@ptrCast(store)),
    };
}

test "missing bearer → 401" {
    const store = StubHatStore{ .has_hat = true };
    const a = makeAcceptor(&store);
    var r = try accept(&a, "GET", "/api/v1/identity/hat", null, "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.unauthorised, r.kind);
}

test "wrong bearer → 401" {
    const store = StubHatStore{ .has_hat = true };
    const a = makeAcceptor(&store);
    var r = try accept(&a, "GET", "/api/v1/identity/hat", "wrongtoken", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.unauthorised, r.kind);
}

test "GET hat with active hat → 200 with hat fields" {
    const store = StubHatStore{ .has_hat = true };
    const a = makeAcceptor(&store);
    var r = try accept(&a, "GET", "/api/v1/identity/hat", "testtoken", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.ok, r.kind);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"hat_id\":\"tradie\"") != null);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"hat_name\":") != null);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"is_active\":true") != null);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"logged_in_at\":") != null);
}

test "GET hat when no hat exists → 404" {
    const store = StubHatStore{ .has_hat = false };
    const a = makeAcceptor(&store);
    var r = try accept(&a, "GET", "/api/v1/identity/hat", "testtoken", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.not_found, r.kind);
}

test "GET hats with one hat → 200 with hats array" {
    const store = StubHatStore{ .has_hat = true };
    const a = makeAcceptor(&store);
    var r = try accept(&a, "GET", "/api/v1/identity/hats", "testtoken", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.ok, r.kind);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"hats\":[") != null);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"hat_id\":\"tradie\"") != null);
}

test "GET hats when empty → 200 with empty array" {
    const store = StubHatStore{ .has_hat = false };
    const a = makeAcceptor(&store);
    var r = try accept(&a, "GET", "/api/v1/identity/hats", "testtoken", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.ok, r.kind);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"hats\":[]") != null);
}

test "POST hat/switch with no switch fn → 204 no-op" {
    const store = StubHatStore{ .has_hat = true };
    const a = makeAcceptor(&store); // switch_hat is null
    var r = try accept(&a, "POST", "/api/v1/identity/hat/switch", "testtoken",
        \\{"hat_id":"hat-uuid-1"}
    );
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.no_content, r.kind);
}

test "POST hat/switch missing hat_id → 400" {
    const store = StubHatStore{ .has_hat = true };
    const a = makeAcceptor(&store);
    var r = try accept(&a, "POST", "/api/v1/identity/hat/switch", "testtoken",
        \\{"other":"field"}
    );
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.bad_request, r.kind);
}

test "POST hat/switch empty hat_id → 400" {
    const store = StubHatStore{ .has_hat = true };
    const a = makeAcceptor(&store);
    var r = try accept(&a, "POST", "/api/v1/identity/hat/switch", "testtoken",
        \\{"hat_id":""}
    );
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.bad_request, r.kind);
}

test "POST hat/switch malformed JSON → 400" {
    const store = StubHatStore{ .has_hat = true };
    const a = makeAcceptor(&store);
    var r = try accept(&a, "POST", "/api/v1/identity/hat/switch", "testtoken", "not json");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.bad_request, r.kind);
}

test "GET cert with no get_cert fn → 404" {
    const store = StubHatStore{ .has_hat = true };
    const a = makeAcceptor(&store); // get_cert is null
    var r = try accept(&a, "GET", "/api/v1/identity/cert", "testtoken", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.not_found, r.kind);
}

test "wrong method on /hat → 405" {
    const store = StubHatStore{ .has_hat = true };
    const a = makeAcceptor(&store);
    var r = try accept(&a, "POST", "/api/v1/identity/hat", "testtoken", "{}");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.method_not_allowed, r.kind);
}

test "wrong method on /hats → 405" {
    const store = StubHatStore{ .has_hat = true };
    const a = makeAcceptor(&store);
    var r = try accept(&a, "DELETE", "/api/v1/identity/hats", "testtoken", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.method_not_allowed, r.kind);
}

test "unknown sub-path → 404" {
    const store = StubHatStore{ .has_hat = true };
    const a = makeAcceptor(&store);
    var r = try accept(&a, "GET", "/api/v1/identity/unknown", "testtoken", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.not_found, r.kind);
}

```
