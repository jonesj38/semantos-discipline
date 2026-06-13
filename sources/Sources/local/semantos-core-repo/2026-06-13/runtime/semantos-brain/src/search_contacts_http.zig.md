---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/search_contacts_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.230555+00:00
---

# runtime/semantos-brain/src/search_contacts_http.zig

```zig
// POST /api/v1/search/contacts — HTTP wrapper around contact_search.
//
// Body shape: {"query": "smith"}
// Response on .matched:
//   {"matches":[{"id":"c1","display_name":"...","phone":"...",
//                "siteRef":"<hex|null>"}]}
//
// W3.3 RED: stub returns .upstream_error.
// W3.4 GREEN: real orchestration (bearer → parse → list customers +
//             sites → searchContacts → JSON response).
//
// All deps injected via fn pointers so unit tests use plain arrays
// (no LMDB).  Production wiring (W3.5) supplies real list functions.

const std = @import("std");
const contact_search = @import("contact_search");
const customers_store_fs = @import("customers_store_fs");
const sites_store_lmdb = @import("sites_store_lmdb");

pub const AcceptResultKind = enum {
    matched, // 200
    unauthorised, // 401
    malformed_body, // 400
    empty_query, // 400
    upstream_error, // 500

    pub fn httpStatus(self: AcceptResultKind) std.http.Status {
        return switch (self) {
            .matched => .ok,
            .unauthorised => .unauthorized,
            .malformed_body, .empty_query => .bad_request,
            .upstream_error => .internal_server_error,
        };
    }
};

pub const AcceptResult = struct {
    kind: AcceptResultKind,
    // On .matched: owned JSON array body (caller writes as response).
    response_body: []u8 = &.{},

    pub fn deinit(self: *AcceptResult, allocator: std.mem.Allocator) void {
        if (self.response_body.len > 0) allocator.free(self.response_body);
        self.response_body = &.{};
    }
};

pub const IsBearerValidFn = *const fn (ctx: ?*anyopaque, bearer_hex: []const u8) bool;

// Provide all customers + sites as owned slices.  Caller is
// responsible for any internal locking; the slices must be valid for
// the duration of the searchContacts call.  Production wiring calls
// store.listAll under the store's own mutex.
pub const ListCustomersFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]customers_store_fs.Customer;

pub const ListSitesFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]sites_store_lmdb.Site;

pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    is_bearer_valid: IsBearerValidFn,
    is_bearer_valid_ctx: ?*anyopaque = null,
    list_customers: ListCustomersFn,
    list_customers_ctx: ?*anyopaque = null,
    list_sites: ListSitesFn,
    list_sites_ctx: ?*anyopaque = null,
};

pub const ParsedRequest = struct {
    query: []u8,

    pub fn deinit(self: *ParsedRequest, allocator: std.mem.Allocator) void {
        if (self.query.len > 0) allocator.free(self.query);
        self.query = &.{};
    }
};

pub const ParseError = error{ malformed, missing_query };

pub fn parseRequest(allocator: std.mem.Allocator, raw: []const u8) ParseError!ParsedRequest {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, raw, .{}) catch {
        return ParseError.malformed;
    };
    defer parsed.deinit();
    if (parsed.value != .object) return ParseError.malformed;
    const v = parsed.value.object.get("query") orelse return ParseError.missing_query;
    if (v != .string) return ParseError.malformed;
    const owned = allocator.dupe(u8, v.string) catch return ParseError.malformed;
    return ParsedRequest{ .query = owned };
}

pub fn acceptSearch(
    acceptor: *const Acceptor,
    bearer_hex: ?[]const u8,
    body_json: []const u8,
) anyerror!AcceptResult {
    // 1. Bearer check.
    const bh = bearer_hex orelse return AcceptResult{ .kind = .unauthorised };
    if (!acceptor.is_bearer_valid(acceptor.is_bearer_valid_ctx, bh)) {
        return AcceptResult{ .kind = .unauthorised };
    }

    // 2. Parse body.
    var parsed = parseRequest(acceptor.allocator, body_json) catch {
        return AcceptResult{ .kind = .malformed_body };
    };
    defer parsed.deinit(acceptor.allocator);

    if (parsed.query.len == 0) return AcceptResult{ .kind = .empty_query };

    // 3. Load customers + sites.
    const customers = acceptor.list_customers(acceptor.list_customers_ctx, acceptor.allocator) catch
        return AcceptResult{ .kind = .upstream_error };
    defer acceptor.allocator.free(customers);

    const sites = acceptor.list_sites(acceptor.list_sites_ctx, acceptor.allocator) catch
        return AcceptResult{ .kind = .upstream_error };
    defer acceptor.allocator.free(sites);

    // 4. Search.
    const hits = contact_search.searchContacts(acceptor.allocator, customers, sites, parsed.query) catch |err|
        switch (err) {
        contact_search.Error.empty_query => return AcceptResult{ .kind = .empty_query },
        contact_search.Error.out_of_memory => return AcceptResult{ .kind = .upstream_error },
    };
    defer acceptor.allocator.free(hits);

    // 5. Build response JSON.
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(acceptor.allocator);
    try buf.appendSlice(acceptor.allocator, "{\"matches\":[");
    for (hits, 0..) |c, i| {
        if (i != 0) try buf.append(acceptor.allocator, ',');
        try writeCustomerJson(acceptor.allocator, &buf, c);
    }
    try buf.appendSlice(acceptor.allocator, "]}");

    return AcceptResult{
        .kind = .matched,
        .response_body = try buf.toOwnedSlice(acceptor.allocator),
    };
}

fn writeCustomerJson(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    c: customers_store_fs.Customer,
) !void {
    try buf.append(allocator, '{');
    try buf.appendSlice(allocator, "\"id\":");
    try writeJsonString(allocator, buf, c.id);
    try buf.appendSlice(allocator, ",\"display_name\":");
    try writeJsonString(allocator, buf, c.display_name);
    try buf.appendSlice(allocator, ",\"phone\":");
    if (c.normalisedPhone) |np| {
        try writeJsonString(allocator, buf, np);
    } else {
        try writeJsonString(allocator, buf, c.phone);
    }
    try buf.appendSlice(allocator, ",\"siteRef\":");
    if (c.siteRef) |sr| {
        try buf.append(allocator, '"');
        for (sr) |byte| {
            const hi = std.fmt.digitToChar(byte >> 4, .lower);
            const lo = std.fmt.digitToChar(byte & 0x0F, .lower);
            try buf.append(allocator, hi);
            try buf.append(allocator, lo);
        }
        try buf.append(allocator, '"');
    } else {
        try buf.appendSlice(allocator, "null");
    }
    try buf.append(allocator, '}');
}

fn writeJsonString(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    try buf.append(allocator, '"');
    for (s) |ch| {
        switch (ch) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, ch),
        }
    }
    try buf.append(allocator, '"');
}

// ────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn mkCustomer(id: []const u8, name: []const u8, phone: []const u8) customers_store_fs.Customer {
    return .{
        .id = id,
        .display_name = name,
        .phone = phone,
        .email = "",
        .address = "",
        .notes = "",
        .created_at = "2026-05-14T00:00:00Z",
    };
}

const TestEnv = struct {
    allocator: std.mem.Allocator,
    bearer_valid_returns: bool = true,
    customers: []const customers_store_fs.Customer = &.{},
    sites: []const sites_store_lmdb.Site = &.{},

    fn isBearerValid(ctx: ?*anyopaque, bearer_hex: []const u8) bool {
        _ = bearer_hex;
        const self: *TestEnv = @ptrCast(@alignCast(ctx.?));
        return self.bearer_valid_returns;
    }

    fn listCustomers(ctx: ?*anyopaque, allocator: std.mem.Allocator) anyerror![]customers_store_fs.Customer {
        const self: *TestEnv = @ptrCast(@alignCast(ctx.?));
        return try allocator.dupe(customers_store_fs.Customer, self.customers);
    }

    fn listSites(ctx: ?*anyopaque, allocator: std.mem.Allocator) anyerror![]sites_store_lmdb.Site {
        const self: *TestEnv = @ptrCast(@alignCast(ctx.?));
        return try allocator.dupe(sites_store_lmdb.Site, self.sites);
    }
};

fn makeAcceptor(env: *TestEnv) Acceptor {
    return Acceptor{
        .allocator = env.allocator,
        .is_bearer_valid = TestEnv.isBearerValid,
        .is_bearer_valid_ctx = env,
        .list_customers = TestEnv.listCustomers,
        .list_customers_ctx = env,
        .list_sites = TestEnv.listSites,
        .list_sites_ctx = env,
    };
}

test "acceptSearch — happy path returns matches JSON" {
    const customers = [_]customers_store_fs.Customer{
        mkCustomer("c1", "John Smith", "+61400000001"),
        mkCustomer("c2", "Jane Doe", "+61400000002"),
    };
    var env = TestEnv{ .allocator = testing.allocator, .customers = customers[0..] };
    const acceptor = makeAcceptor(&env);

    var result = try acceptSearch(&acceptor, "bearer", "{\"query\":\"smith\"}");
    defer result.deinit(testing.allocator);

    try testing.expectEqual(AcceptResultKind.matched, result.kind);
    try testing.expect(std.mem.indexOf(u8, result.response_body, "\"id\":\"c1\"") != null);
    try testing.expect(std.mem.indexOf(u8, result.response_body, "John Smith") != null);
    try testing.expect(std.mem.indexOf(u8, result.response_body, "+61400000001") != null);
    try testing.expect(std.mem.indexOf(u8, result.response_body, "Jane Doe") == null); // not matched
}

test "acceptSearch — empty matches returns matches:[]" {
    const customers = [_]customers_store_fs.Customer{
        mkCustomer("c1", "Smith", "+61400000001"),
    };
    var env = TestEnv{ .allocator = testing.allocator, .customers = customers[0..] };
    const acceptor = makeAcceptor(&env);
    var result = try acceptSearch(&acceptor, "bearer", "{\"query\":\"zzz\"}");
    defer result.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.matched, result.kind);
    try testing.expectEqualStrings("{\"matches\":[]}", result.response_body);
}

test "acceptSearch — missing bearer → unauthorised" {
    var env = TestEnv{ .allocator = testing.allocator };
    const acceptor = makeAcceptor(&env);
    var result = try acceptSearch(&acceptor, null, "{\"query\":\"x\"}");
    defer result.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.unauthorised, result.kind);
}

test "acceptSearch — invalid bearer → unauthorised" {
    var env = TestEnv{ .allocator = testing.allocator, .bearer_valid_returns = false };
    const acceptor = makeAcceptor(&env);
    var result = try acceptSearch(&acceptor, "bad", "{\"query\":\"x\"}");
    defer result.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.unauthorised, result.kind);
}

test "acceptSearch — malformed body → 400" {
    var env = TestEnv{ .allocator = testing.allocator };
    const acceptor = makeAcceptor(&env);
    var result = try acceptSearch(&acceptor, "b", "{ not json");
    defer result.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.malformed_body, result.kind);
}

test "acceptSearch — missing query field → 400" {
    var env = TestEnv{ .allocator = testing.allocator };
    const acceptor = makeAcceptor(&env);
    var result = try acceptSearch(&acceptor, "b", "{\"other\":\"x\"}");
    defer result.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.malformed_body, result.kind);
}

test "acceptSearch — empty query string → empty_query (400)" {
    var env = TestEnv{ .allocator = testing.allocator };
    const acceptor = makeAcceptor(&env);
    var result = try acceptSearch(&acceptor, "b", "{\"query\":\"\"}");
    defer result.deinit(testing.allocator);
    try testing.expectEqual(AcceptResultKind.empty_query, result.kind);
}

```
