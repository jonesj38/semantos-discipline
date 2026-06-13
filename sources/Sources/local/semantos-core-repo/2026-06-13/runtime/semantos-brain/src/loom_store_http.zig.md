---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/loom_store_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.215410+00:00
---

# runtime/semantos-brain/src/loom_store_http.zig

```zig
// D-brain-loom-store-api — Typed HTTP surface for brain-resident loom-objects.
//
// Loom-objects (jobs, customers, sites, visits, quotes, invoices, attachments)
// are brain-resident as sem_objects / cells. This module provides typed REST
// endpoints so the shell doesn't need to string-parse REPL output.
//
// Routes:
//   GET  /api/v1/objects/{type}         → list objects of that type (JSON array)
//   GET  /api/v1/objects/{type}/{id}    → get one object by id (JSON object)
//
// All deps injected via fn pointers; tests use plain stubs (no dispatcher).
// The reactor calls `accept(acceptor, method, path, bearer, body)` with the
// full path starting at "/api/v1/objects".
//
// Allowed resource types guard against dispatcher injection attacks. The
// set is the "core loom object types" recognised at this endpoint; new
// types require an explicit `ALLOWED_TYPES` addition.

const std = @import("std");

// ── Allowed resource types ────────────────────────────────────────────
// Explicit allowlist — unknown types return 404 before hitting dispatcher.

pub const ALLOWED_TYPES = [_][]const u8{
    "jobs",
    "customers",
    "sites",
    "visits",
    "quotes",
    "invoices",
    "attachments",
};

pub fn isAllowedType(t: []const u8) bool {
    for (ALLOWED_TYPES) |allowed| {
        if (std.mem.eql(u8, t, allowed)) return true;
    }
    return false;
}

// ── Result kinds ──────────────────────────────────────────────────────

pub const ResultKind = enum {
    ok, // 200
    bad_request, // 400
    unauthorised, // 401
    not_found, // 404
    method_not_allowed, // 405
    internal_error, // 500

    pub fn httpStatus(self: ResultKind) u16 {
        return switch (self) {
            .ok => 200,
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

/// Returns a JSON array of objects of the given type.  Caller frees.
/// On error (dispatch failure, OOM) return anyerror; the acceptor maps
/// it to a 500 response.
pub const FindObjectsFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    resource_type: []const u8,
) anyerror![]u8;

/// Returns a JSON object for the given id, or null when not found.
/// Caller frees the slice when non-null.
pub const FindObjectByIdFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    resource_type: []const u8,
    id: []const u8,
) anyerror!?[]u8;

// ── Acceptor ──────────────────────────────────────────────────────────

pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    is_bearer_valid: IsBearerValidFn,
    is_bearer_valid_ctx: ?*anyopaque = null,
    find_objects: FindObjectsFn,
    find_objects_ctx: ?*anyopaque = null,
    find_object_by_id: FindObjectByIdFn,
    find_object_by_id_ctx: ?*anyopaque = null,
};

// ── Routing ───────────────────────────────────────────────────────────

const OBJECTS_PREFIX = "/api/v1/objects";

/// Pure-logic acceptor.  `path` starts with "/api/v1/objects".
pub fn accept(
    acceptor: *const Acceptor,
    method: []const u8,
    path: []const u8,
    bearer: ?[]const u8,
    _body: []const u8,
) anyerror!AcceptResult {
    _ = _body;
    const alloc = acceptor.allocator;

    // ── GET only ─────────────────────────────────────────────────────
    if (!std.mem.eql(u8, method, "GET")) {
        return .{
            .kind = .method_not_allowed,
            .body = try alloc.dupe(u8,
                "{\"error\":\"method_not_allowed\",\"hint\":\"GET required\"}"),
        };
    }

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

    // ── Strip prefix ─────────────────────────────────────────────────
    if (!std.mem.startsWith(u8, path, OBJECTS_PREFIX)) {
        return .{
            .kind = .not_found,
            .body = try alloc.dupe(u8, "{\"error\":\"not_found\"}"),
        };
    }
    const suffix = path[OBJECTS_PREFIX.len..];
    // suffix is empty, "/{type}", or "/{type}/{id}"
    if (suffix.len == 0 or suffix[0] != '/') {
        return .{
            .kind = .not_found,
            .body = try alloc.dupe(u8, "{\"error\":\"not_found\"}"),
        };
    }
    const after_slash = suffix[1..]; // skip leading "/"

    // ── Parse {type} and optional {id} ───────────────────────────────
    var resource_type: []const u8 = undefined;
    var obj_id: ?[]const u8 = null;

    if (std.mem.indexOf(u8, after_slash, "/")) |slash_pos| {
        resource_type = after_slash[0..slash_pos];
        const rest = after_slash[slash_pos + 1 ..];
        if (rest.len == 0) {
            // trailing slash — treat same as no id
        } else {
            obj_id = rest;
        }
    } else {
        resource_type = after_slash;
    }

    if (resource_type.len == 0) {
        return .{
            .kind = .bad_request,
            .body = try alloc.dupe(u8,
                "{\"error\":\"bad_request\",\"hint\":\"resource type required\"}"),
        };
    }

    if (!isAllowedType(resource_type)) {
        return .{
            .kind = .not_found,
            .body = try alloc.dupe(u8, "{\"error\":\"not_found\"}"),
        };
    }

    // ── Route to fn pointer ───────────────────────────────────────────
    if (obj_id) |id| {
        const json_opt = acceptor.find_object_by_id(
            acceptor.find_object_by_id_ctx, alloc, resource_type, id) catch {
            return .{
                .kind = .internal_error,
                .body = try alloc.dupe(u8, "{\"error\":\"internal_error\"}"),
            };
        };
        if (json_opt) |json| {
            return .{ .kind = .ok, .body = json };
        }
        return .{
            .kind = .not_found,
            .body = try alloc.dupe(u8, "{\"error\":\"not_found\"}"),
        };
    } else {
        const json = acceptor.find_objects(
            acceptor.find_objects_ctx, alloc, resource_type) catch {
            return .{
                .kind = .internal_error,
                .body = try alloc.dupe(u8, "{\"error\":\"internal_error\"}"),
            };
        };
        return .{ .kind = .ok, .body = json };
    }
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

fn stubFindObjects(
    _: ?*anyopaque,
    allocator: std.mem.Allocator,
    resource_type: []const u8,
) anyerror![]u8 {
    if (std.mem.eql(u8, resource_type, "jobs")) {
        return allocator.dupe(u8, "[{\"id\":\"j1\",\"title\":\"Paint fence\"}]");
    }
    return allocator.dupe(u8, "[]");
}

fn stubFindObjectById(
    _: ?*anyopaque,
    allocator: std.mem.Allocator,
    resource_type: []const u8,
    id: []const u8,
) anyerror!?[]u8 {
    if (std.mem.eql(u8, resource_type, "jobs") and std.mem.eql(u8, id, "j1")) {
        return @as(?[]u8, try allocator.dupe(u8, "{\"id\":\"j1\",\"title\":\"Paint fence\"}"));
    }
    return null;
}

fn makeAcceptor(alloc: std.mem.Allocator, bearer_fn: IsBearerValidFn) Acceptor {
    return .{
        .allocator = alloc,
        .is_bearer_valid = bearer_fn,
        .find_objects = stubFindObjects,
        .find_object_by_id = stubFindObjectById,
    };
}

test "GET /api/v1/objects/jobs — list ok" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "GET", "/api/v1/objects/jobs", "beef", "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.ok, r.kind);
    try std.testing.expectEqual(@as(u16, 200), r.kind.httpStatus());
    try std.testing.expectEqualStrings("[{\"id\":\"j1\",\"title\":\"Paint fence\"}]", r.body);
}

test "GET /api/v1/objects/jobs/j1 — single ok" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "GET", "/api/v1/objects/jobs/j1", "beef", "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.ok, r.kind);
    try std.testing.expectEqualStrings("{\"id\":\"j1\",\"title\":\"Paint fence\"}", r.body);
}

test "GET /api/v1/objects/jobs/unknown — not_found" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "GET", "/api/v1/objects/jobs/nope", "beef", "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.not_found, r.kind);
}

test "GET /api/v1/objects/customers — empty list ok" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "GET", "/api/v1/objects/customers", "beef", "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.ok, r.kind);
    try std.testing.expectEqualStrings("[]", r.body);
}

test "no bearer — unauthorised" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "GET", "/api/v1/objects/jobs", null, "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.unauthorised, r.kind);
    try std.testing.expectEqual(@as(u16, 401), r.kind.httpStatus());
}

test "invalid bearer — unauthorised" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerDeny);
    var r = try accept(&a, "GET", "/api/v1/objects/jobs", "bad", "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.unauthorised, r.kind);
}

test "POST — method_not_allowed" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "POST", "/api/v1/objects/jobs", "beef", "{}");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.method_not_allowed, r.kind);
    try std.testing.expectEqual(@as(u16, 405), r.kind.httpStatus());
}

test "unknown resource type — not_found" {
    const alloc = std.testing.allocator;
    const a = makeAcceptor(alloc, stubBearerOk);
    var r = try accept(&a, "GET", "/api/v1/objects/frobnicators", "beef", "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.not_found, r.kind);
}

test "isAllowedType allowlist" {
    try std.testing.expect(isAllowedType("jobs"));
    try std.testing.expect(isAllowedType("customers"));
    try std.testing.expect(isAllowedType("sites"));
    try std.testing.expect(isAllowedType("visits"));
    try std.testing.expect(isAllowedType("quotes"));
    try std.testing.expect(isAllowedType("invoices"));
    try std.testing.expect(isAllowedType("attachments"));
    try std.testing.expect(!isAllowedType("frobnicators"));
    try std.testing.expect(!isAllowedType(""));
}

test "httpStatus mapping" {
    try std.testing.expectEqual(@as(u16, 200), ResultKind.ok.httpStatus());
    try std.testing.expectEqual(@as(u16, 400), ResultKind.bad_request.httpStatus());
    try std.testing.expectEqual(@as(u16, 401), ResultKind.unauthorised.httpStatus());
    try std.testing.expectEqual(@as(u16, 404), ResultKind.not_found.httpStatus());
    try std.testing.expectEqual(@as(u16, 405), ResultKind.method_not_allowed.httpStatus());
    try std.testing.expectEqual(@as(u16, 500), ResultKind.internal_error.httpStatus());
}

```
