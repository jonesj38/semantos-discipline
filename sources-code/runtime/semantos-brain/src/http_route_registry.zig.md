---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/http_route_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.228819+00:00
---

# runtime/semantos-brain/src/http_route_registry.zig

```zig
//! HTTP route registry — C4 PR-F1, the oddjobz-cluster keystone.
//!
//! A growable table of cartridge-contributed HTTP routes that the reactor
//! consults AFTER its hardcoded substrate/cartridge routes and BEFORE the
//! static-file / 404 fallthrough. Lets a cartridge add an HTTP endpoint at
//! boot via the cartridge seam (deps.route_registry) WITHOUT editing
//! reactor.zig's dispatch chain or adding a typed `?*X.Acceptor` field to
//! SiteServer — the HTTP analog of MintContextRegistry (#846) for the
//! mint-context slot.
//!
//! v1 vtable: the handler returns a structured RouteResponse (status +
//! content-type + body) the reactor writes with CORS. This covers the JSON
//! GET/POST acceptors. Heterogeneous shapes (multipart upload, streaming,
//! bun-script shell-outs) get additive vtable extensions as the oddjobz
//! acceptors migrate over the seam (PR-F2+).
//!
//! Leaf deps: std + http_parser (HttpRequest) only — so cartridge_seam can
//! expose the registry on CartridgeDeps without pulling in the reactor
//! (substrate one-way dep gate, #847).

const std = @import("std");
const http_parser = @import("http_parser");

/// A cartridge route handler's response. `body` is allocated with the
/// per-request allocator the reactor passes to `handle`; the reactor copies it
/// into the connection write buffer (with CORS) and the request arena frees
/// it. `status_text` + `content_type` are borrowed (usually literals).
pub const RouteResponse = struct {
    status: u16,
    status_text: []const u8 = "OK",
    content_type: []const u8 = "application/json",
    body: []const u8,
    /// Optional extra response headers, appended after the CORS headers the
    /// reactor emits (e.g. cache-control + a content-hash echo for a binary
    /// download). Borrowed for the duration of the write — a handler that
    /// allocates these must use the per-request allocator so they outlive the
    /// return + are freed with the request arena. Empty by default. C4 PR-H6.
    extra_headers: []const std.http.Header = &.{},
};

/// Uniform cartridge-route handler. Inspect the request, do the work, return a
/// RouteResponse. An error surfaces as a 500 (the reactor logs it + writes a
/// generic body) — handlers should prefer returning a RouteResponse with an
/// error status over erroring, so they control the response body.
pub const RouteHandleFn = *const fn (
    state: *anyopaque,
    req: *const http_parser.HttpRequest,
    allocator: std.mem.Allocator,
) anyerror!RouteResponse;

/// One registered route. Set exactly one of path_exact / path_prefix.
pub const Route = struct {
    /// Optional method filter, case-insensitive (e.g. "POST"); null = any.
    method: ?[]const u8 = null,
    path_exact: ?[]const u8 = null,
    path_prefix: ?[]const u8 = null,
    /// Optional suffix constraint, AND-combined with path_prefix. Lets a
    /// cartridge express "/.../turn/:id/approve"-shaped routes the v1
    /// exact|prefix matcher couldn't. Ignored without path_prefix. C4 PR-G5.
    path_suffix: ?[]const u8 = null,
    /// Caller-owned state threaded into `handle` (e.g. the cartridge's
    /// heap-allocated acceptor). Borrowed; the registry never frees it.
    state: *anyopaque,
    handle: RouteHandleFn,

    pub fn matches(self: *const Route, method: []const u8, path: []const u8) bool {
        if (self.method) |m| {
            if (!std.ascii.eqlIgnoreCase(m, method)) return false;
        }
        if (self.path_exact) |p| return std.mem.eql(u8, p, path);
        if (self.path_prefix) |p| {
            if (!std.mem.startsWith(u8, path, p)) return false;
            if (self.path_suffix) |s| return std.mem.endsWith(u8, path, s);
            return true;
        }
        return false;
    }
};

/// Per-instance ceiling. Cartridges register a handful of routes each; 64 is a
/// generous bound — exceeding it is a deployment misconfiguration, not a
/// runtime path.
pub const MAX_ROUTES: usize = 64;

/// Growable, fixed-capacity route table. Boot-time append; read at request
/// dispatch. Stable-address contract: the reactor reads the registry the
/// SiteServer points at, so a cartridge's boot-time `add()` is visible at
/// request time (same posture as MintContextRegistry). First match wins, in
/// registration order.
pub const RouteRegistry = struct {
    buf: [MAX_ROUTES]Route = undefined,
    len: usize = 0,

    pub fn add(self: *RouteRegistry, route: Route) void {
        if (self.len >= MAX_ROUTES) {
            std.log.warn(
                "RouteRegistry: route ceiling {d} reached — dropping {s}",
                .{ MAX_ROUTES, route.path_exact orelse route.path_prefix orelse "?" },
            );
            return;
        }
        self.buf[self.len] = route;
        self.len += 1;
    }

    pub fn count(self: *const RouteRegistry) usize {
        return self.len;
    }

    pub fn match(self: *const RouteRegistry, method: []const u8, path: []const u8) ?*const Route {
        for (self.buf[0..self.len]) |*r| {
            if (r.matches(method, path)) return r;
        }
        return null;
    }
};

// ─────────────────────────────────────────────────────────────────────
const testing = std.testing;

test "RouteRegistry: exact + prefix + method matching, first-match-wins" {
    const Dummy = struct {
        fn h(_: *anyopaque, _: *const http_parser.HttpRequest, _: std.mem.Allocator) anyerror!RouteResponse {
            return .{ .status = 200, .body = "{}" };
        }
    };
    var state: u8 = 0;
    var reg = RouteRegistry{};
    try testing.expectEqual(@as(usize, 0), reg.count());

    reg.add(.{ .method = "POST", .path_exact = "/api/v1/foo", .state = &state, .handle = Dummy.h });
    reg.add(.{ .path_prefix = "/api/v1/bar/", .state = &state, .handle = Dummy.h });
    try testing.expectEqual(@as(usize, 2), reg.count());

    try testing.expect(reg.match("POST", "/api/v1/foo") != null);
    try testing.expect(reg.match("post", "/api/v1/foo") != null); // method case-insensitive
    try testing.expect(reg.match("GET", "/api/v1/foo") == null); // method filter excludes
    try testing.expect(reg.match("GET", "/api/v1/bar/123") != null); // prefix, any method
    try testing.expect(reg.match("GET", "/api/v1/other") == null); // no match
}

test "RouteRegistry: ceiling drops extras without overflow" {
    const Dummy = struct {
        fn h(_: *anyopaque, _: *const http_parser.HttpRequest, _: std.mem.Allocator) anyerror!RouteResponse {
            return .{ .status = 200, .body = "{}" };
        }
    };
    var state: u8 = 0;
    var reg = RouteRegistry{};
    var i: usize = 0;
    while (i < MAX_ROUTES + 5) : (i += 1) {
        reg.add(.{ .path_exact = "/x", .state = &state, .handle = Dummy.h });
    }
    try testing.expectEqual(MAX_ROUTES, reg.count());
}

test "Route: path_prefix + path_suffix AND-matching (C4 PR-G5)" {
    const Dummy = struct {
        fn h(_: *anyopaque, _: *const http_parser.HttpRequest, _: std.mem.Allocator) anyerror!RouteResponse {
            return .{ .status = 200, .body = "{}" };
        }
    };
    var state: u8 = 0;
    var reg = RouteRegistry{};
    reg.add(.{ .method = "POST", .path_prefix = "/api/v1/conversation/turn/", .path_suffix = "/approve", .state = &state, .handle = Dummy.h });
    try testing.expect(reg.match("POST", "/api/v1/conversation/turn/abc/approve") != null);
    try testing.expect(reg.match("POST", "/api/v1/conversation/turn/abc/re-anchor") == null); // wrong suffix
    try testing.expect(reg.match("POST", "/api/v1/conversation/turn/propose") == null); // wrong suffix
    try testing.expect(reg.match("POST", "/other/abc/approve") == null); // wrong prefix
}

```
