---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/contacts_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.235870+00:00
---

# runtime/semantos-brain/src/contacts_http.zig

```zig
// D-brain-contacts-api — HTTP acceptor for /api/v1/contacts.
//
// Routes:
//   GET  /api/v1/contacts              → list all contacts
//   POST /api/v1/contacts              → add contact
//   GET  /api/v1/contacts/{certId}     → get one contact
//   POST /api/v1/contacts/{certId}/edges   → create edge
//   DELETE /api/v1/contacts/{certId}/edges/{edgeId} → revoke edge
//
// All deps injected via fn pointers; tests use plain stubs (no LMDB).
// The reactor calls `accept(acceptor, method, path, bearer, body)` with
// the full path starting at "/api/v1/contacts".

const std = @import("std");

// ── Result kinds ──────────────────────────────────────────────────────

pub const ResultKind = enum {
    ok, // 200
    created, // 201
    no_content, // 204
    bad_request, // 400
    unauthorised, // 401
    not_found, // 404
    method_not_allowed, // 405
    conflict, // 409
    internal_error, // 500

    pub fn httpStatus(self: ResultKind) u16 {
        return switch (self) {
            .ok => 200,
            .created => 201,
            .no_content => 204,
            .bad_request => 400,
            .unauthorised => 401,
            .not_found => 404,
            .method_not_allowed => 405,
            .conflict => 409,
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

// ── Contact + Edge types exposed to tests ─────────────────────────────

pub const Contact = struct {
    certId: []const u8,
    publicKey: []const u8,
    displayName: []const u8,
    email: ?[]const u8,
    source: []const u8,
    addedAt: i64,
    updatedAt: i64,
};

pub const EdgeRecord = struct {
    edgeId: []const u8,
    certId: []const u8,
    edgeType: []const u8,
    signingKeyIndex: i64,
    recoveryPolicy: []const u8,
    revokedAt: ?i64,
    createdAt: i64,
};

// ── DI fn pointers ────────────────────────────────────────────────────

pub const IsBearerValidFn = *const fn (ctx: ?*anyopaque, bearer: []const u8) bool;

pub const ListContactsFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]Contact;

pub const GetContactFn = *const fn (
    ctx: ?*anyopaque,
    certId: []const u8,
) ?Contact;

pub const AddContactFn = *const fn (
    ctx: ?*anyopaque,
    certId: []const u8,
    publicKey: []const u8,
    displayName: []const u8,
    email: ?[]const u8,
) anyerror!Contact;

pub const AddEdgeFn = *const fn (
    ctx: ?*anyopaque,
    certId: []const u8,
    edgeId: []const u8,
    edgeType: []const u8,
    signingKeyIndex: i64,
    recoveryPolicy: []const u8,
) anyerror!EdgeRecord;

pub const RevokeEdgeFn = *const fn (
    ctx: ?*anyopaque,
    certId: []const u8,
    edgeId: []const u8,
) anyerror!void;

pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    is_bearer_valid: IsBearerValidFn,
    is_bearer_valid_ctx: ?*anyopaque = null,
    list_contacts: ListContactsFn,
    list_contacts_ctx: ?*anyopaque = null,
    get_contact: GetContactFn,
    get_contact_ctx: ?*anyopaque = null,
    add_contact: AddContactFn,
    add_contact_ctx: ?*anyopaque = null,
    add_edge: AddEdgeFn,
    add_edge_ctx: ?*anyopaque = null,
    revoke_edge: RevokeEdgeFn,
    revoke_edge_ctx: ?*anyopaque = null,
};

// ── Entry point ───────────────────────────────────────────────────────

// `path` is the full request path starting with "/api/v1/contacts".
pub fn accept(
    acceptor: *const Acceptor,
    method: []const u8,
    path: []const u8,
    bearer: ?[]const u8,
    body: []const u8,
) anyerror!AcceptResult {
    const bh = bearer orelse return AcceptResult{ .kind = .unauthorised };
    if (!acceptor.is_bearer_valid(acceptor.is_bearer_valid_ctx, bh))
        return AcceptResult{ .kind = .unauthorised };

    const base = "/api/v1/contacts";
    const suffix = path[base.len..]; // "" | "/{certId}" | "/{certId}/edges" | ...

    // GET /api/v1/contacts  or  POST /api/v1/contacts
    if (suffix.len == 0) {
        if (std.mem.eql(u8, method, "GET")) return handleList(acceptor);
        if (std.mem.eql(u8, method, "POST")) return handleAddContact(acceptor, body);
        return AcceptResult{ .kind = .method_not_allowed };
    }

    // /api/v1/contacts/{certId}[/edges[/{edgeId}]]
    if (suffix[0] != '/') return AcceptResult{ .kind = .not_found };
    const rest = suffix[1..]; // "{certId}" or "{certId}/edges" or "{certId}/edges/{edgeId}"

    const slash_pos = std.mem.indexOf(u8, rest, "/");
    const certId = if (slash_pos) |p| rest[0..p] else rest;
    const after_cert = if (slash_pos) |p| rest[p..] else "";

    if (certId.len == 0) return AcceptResult{ .kind = .not_found };

    if (after_cert.len == 0) {
        // GET /api/v1/contacts/{certId}
        if (!std.mem.eql(u8, method, "GET")) return AcceptResult{ .kind = .method_not_allowed };
        return handleGetOne(acceptor, certId);
    }

    if (std.mem.eql(u8, after_cert, "/edges")) {
        // POST /api/v1/contacts/{certId}/edges
        if (!std.mem.eql(u8, method, "POST")) return AcceptResult{ .kind = .method_not_allowed };
        return handleAddEdge(acceptor, certId, body);
    }

    if (std.mem.startsWith(u8, after_cert, "/edges/")) {
        const edgeId = after_cert["/edges/".len..];
        if (edgeId.len == 0) return AcceptResult{ .kind = .not_found };
        // DELETE /api/v1/contacts/{certId}/edges/{edgeId}
        if (!std.mem.eql(u8, method, "DELETE")) return AcceptResult{ .kind = .method_not_allowed };
        return handleRevokeEdge(acceptor, certId, edgeId);
    }

    // POST /api/v1/contacts (body contains certId etc.)
    // This case never reached because suffix=="" is handled above;
    // left for clarity — any unknown sub-path is 404.
    return AcceptResult{ .kind = .not_found };
}

// ── Route handlers ────────────────────────────────────────────────────

fn handleList(acceptor: *const Acceptor) anyerror!AcceptResult {
    const contacts = acceptor.list_contacts(acceptor.list_contacts_ctx, acceptor.allocator) catch
        return AcceptResult{ .kind = .internal_error };
    defer acceptor.allocator.free(contacts);

    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(acceptor.allocator);
    try buf.appendSlice(acceptor.allocator, "{\"contacts\":[");
    for (contacts, 0..) |c, i| {
        if (i != 0) try buf.append(acceptor.allocator, ',');
        try writeContactJson(acceptor.allocator, &buf, c);
    }
    try buf.appendSlice(acceptor.allocator, "]}");

    return AcceptResult{ .kind = .ok, .body = try buf.toOwnedSlice(acceptor.allocator) };
}

fn handleGetOne(acceptor: *const Acceptor, certId: []const u8) anyerror!AcceptResult {
    const c = acceptor.get_contact(acceptor.get_contact_ctx, certId) orelse
        return AcceptResult{ .kind = .not_found };

    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(acceptor.allocator);
    try writeContactJson(acceptor.allocator, &buf, c);

    return AcceptResult{ .kind = .ok, .body = try buf.toOwnedSlice(acceptor.allocator) };
}

fn handleAddContact(acceptor: *const Acceptor, body: []const u8) anyerror!AcceptResult {
    const parsed = std.json.parseFromSlice(std.json.Value, acceptor.allocator, body, .{}) catch
        return AcceptResult{ .kind = .bad_request };
    defer parsed.deinit();
    if (parsed.value != .object) return AcceptResult{ .kind = .bad_request };

    const obj = parsed.value.object;
    const certId = switch (obj.get("certId") orelse return AcceptResult{ .kind = .bad_request }) {
        .string => |s| s,
        else => return AcceptResult{ .kind = .bad_request },
    };
    const publicKey = switch (obj.get("publicKey") orelse return AcceptResult{ .kind = .bad_request }) {
        .string => |s| s,
        else => return AcceptResult{ .kind = .bad_request },
    };
    const displayName = switch (obj.get("displayName") orelse return AcceptResult{ .kind = .bad_request }) {
        .string => |s| s,
        else => return AcceptResult{ .kind = .bad_request },
    };
    const email: ?[]const u8 = switch (obj.get("email") orelse .null) {
        .string => |s| s,
        else => null,
    };

    const c = acceptor.add_contact(acceptor.add_contact_ctx, certId, publicKey, displayName, email) catch |err|
        return switch (err) {
        error.invalid_cert_id, error.invalid_public_key, error.invalid_display_name => AcceptResult{ .kind = .bad_request },
        else => AcceptResult{ .kind = .internal_error },
    };

    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(acceptor.allocator);
    try writeContactJson(acceptor.allocator, &buf, c);

    return AcceptResult{ .kind = .created, .body = try buf.toOwnedSlice(acceptor.allocator) };
}

fn handleAddEdge(acceptor: *const Acceptor, certId: []const u8, body: []const u8) anyerror!AcceptResult {
    const parsed = std.json.parseFromSlice(std.json.Value, acceptor.allocator, body, .{}) catch
        return AcceptResult{ .kind = .bad_request };
    defer parsed.deinit();
    if (parsed.value != .object) return AcceptResult{ .kind = .bad_request };

    const obj = parsed.value.object;
    const edgeId = switch (obj.get("edgeId") orelse return AcceptResult{ .kind = .bad_request }) {
        .string => |s| s,
        else => return AcceptResult{ .kind = .bad_request },
    };
    const edgeType = switch (obj.get("edgeType") orelse return AcceptResult{ .kind = .bad_request }) {
        .string => |s| s,
        else => return AcceptResult{ .kind = .bad_request },
    };
    const ski = switch (obj.get("signingKeyIndex") orelse return AcceptResult{ .kind = .bad_request }) {
        .integer => |n| n,
        else => return AcceptResult{ .kind = .bad_request },
    };
    const recoveryPolicy = switch (obj.get("recoveryPolicy") orelse return AcceptResult{ .kind = .bad_request }) {
        .string => |s| s,
        else => return AcceptResult{ .kind = .bad_request },
    };

    const e = acceptor.add_edge(acceptor.add_edge_ctx, certId, edgeId, edgeType, ski, recoveryPolicy) catch |err|
        return switch (err) {
        error.contact_not_found => AcceptResult{ .kind = .not_found },
        error.invalid_edge_id => AcceptResult{ .kind = .bad_request },
        else => AcceptResult{ .kind = .internal_error },
    };

    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(acceptor.allocator);
    try writeEdgeJson(acceptor.allocator, &buf, e);

    return AcceptResult{ .kind = .created, .body = try buf.toOwnedSlice(acceptor.allocator) };
}

fn handleRevokeEdge(acceptor: *const Acceptor, certId: []const u8, edgeId: []const u8) anyerror!AcceptResult {
    acceptor.revoke_edge(acceptor.revoke_edge_ctx, certId, edgeId) catch |err|
        return switch (err) {
        error.contact_not_found, error.edge_not_found => AcceptResult{ .kind = .not_found },
        error.edge_already_revoked => AcceptResult{ .kind = .conflict },
        else => AcceptResult{ .kind = .internal_error },
    };
    return AcceptResult{ .kind = .no_content };
}

// ── JSON serialisation ────────────────────────────────────────────────

fn writeContactJson(
    allocator: std.mem.Allocator,
    buf: *std.ArrayListUnmanaged(u8),
    c: Contact,
) !void {
    try buf.appendSlice(allocator, "{\"certId\":");
    try writeJsonString(allocator, buf, c.certId);
    try buf.appendSlice(allocator, ",\"publicKey\":");
    try writeJsonString(allocator, buf, c.publicKey);
    try buf.appendSlice(allocator, ",\"displayName\":");
    try writeJsonString(allocator, buf, c.displayName);
    try buf.appendSlice(allocator, ",\"email\":");
    if (c.email) |e| {
        try writeJsonString(allocator, buf, e);
    } else {
        try buf.appendSlice(allocator, "null");
    }
    try buf.appendSlice(allocator, ",\"source\":");
    try writeJsonString(allocator, buf, c.source);
    var ts_buf: [64]u8 = undefined;
    try buf.appendSlice(allocator, ",\"addedAt\":");
    try buf.appendSlice(allocator, try std.fmt.bufPrint(&ts_buf, "{d}", .{c.addedAt}));
    try buf.appendSlice(allocator, ",\"updatedAt\":");
    try buf.appendSlice(allocator, try std.fmt.bufPrint(&ts_buf, "{d}", .{c.updatedAt}));
    try buf.append(allocator, '}');
}

fn writeEdgeJson(
    allocator: std.mem.Allocator,
    buf: *std.ArrayListUnmanaged(u8),
    e: EdgeRecord,
) !void {
    try buf.appendSlice(allocator, "{\"edgeId\":");
    try writeJsonString(allocator, buf, e.edgeId);
    try buf.appendSlice(allocator, ",\"certId\":");
    try writeJsonString(allocator, buf, e.certId);
    try buf.appendSlice(allocator, ",\"edgeType\":");
    try writeJsonString(allocator, buf, e.edgeType);
    var n_buf: [32]u8 = undefined;
    try buf.appendSlice(allocator, ",\"signingKeyIndex\":");
    try buf.appendSlice(allocator, try std.fmt.bufPrint(&n_buf, "{d}", .{e.signingKeyIndex}));
    try buf.appendSlice(allocator, ",\"recoveryPolicy\":");
    try writeJsonString(allocator, buf, e.recoveryPolicy);
    try buf.appendSlice(allocator, ",\"revokedAt\":");
    if (e.revokedAt) |r| {
        try buf.appendSlice(allocator, try std.fmt.bufPrint(&n_buf, "{d}", .{r}));
    } else {
        try buf.appendSlice(allocator, "null");
    }
    try buf.appendSlice(allocator, ",\"createdAt\":");
    try buf.appendSlice(allocator, try std.fmt.bufPrint(&n_buf, "{d}", .{e.createdAt}));
    try buf.append(allocator, '}');
}

fn writeJsonString(allocator: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8), s: []const u8) !void {
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

// ── Routing entry for POST /api/v1/contacts ───────────────────────────
// The reactor passes "POST" + "/api/v1/contacts" for add-contact.
// Re-export handleAddContact under the public API.
pub fn acceptAddContact(
    acceptor: *const Acceptor,
    bearer: ?[]const u8,
    body: []const u8,
) anyerror!AcceptResult {
    const bh = bearer orelse return AcceptResult{ .kind = .unauthorised };
    if (!acceptor.is_bearer_valid(acceptor.is_bearer_valid_ctx, bh))
        return AcceptResult{ .kind = .unauthorised };
    return handleAddContact(acceptor, body);
}

// ── Tests ─────────────────────────────────────────────────────────────

const testing = std.testing;

const TestStore = struct {
    contacts: std.ArrayListUnmanaged(Contact),
    edges: std.ArrayListUnmanaged(EdgeRecord),

    fn init() TestStore {
        return .{
            .contacts = .{},
            .edges = .{},
        };
    }

    fn deinit(self: *TestStore) void {
        self.contacts.deinit(testing.allocator);
        self.edges.deinit(testing.allocator);
    }

    fn listContacts(ctx: ?*anyopaque, allocator: std.mem.Allocator) anyerror![]Contact {
        const self: *TestStore = @ptrCast(@alignCast(ctx.?));
        return allocator.dupe(Contact, self.contacts.items);
    }

    fn getContact(ctx: ?*anyopaque, certId: []const u8) ?Contact {
        const self: *TestStore = @ptrCast(@alignCast(ctx.?));
        for (self.contacts.items) |c| {
            if (std.mem.eql(u8, c.certId, certId)) return c;
        }
        return null;
    }

    fn addContact(
        ctx: ?*anyopaque,
        certId: []const u8,
        publicKey: []const u8,
        displayName: []const u8,
        email: ?[]const u8,
    ) anyerror!Contact {
        const self: *TestStore = @ptrCast(@alignCast(ctx.?));
        const c = Contact{
            .certId = certId, .publicKey = publicKey,
            .displayName = displayName, .email = email,
            .source = "manual", .addedAt = 1000, .updatedAt = 1000,
        };
        try self.contacts.append(testing.allocator, c);
        return c;
    }

    fn addEdge(
        ctx: ?*anyopaque,
        certId: []const u8,
        edgeId: []const u8,
        edgeType: []const u8,
        signingKeyIndex: i64,
        recoveryPolicy: []const u8,
    ) anyerror!EdgeRecord {
        const self: *TestStore = @ptrCast(@alignCast(ctx.?));
        // Check contact exists.
        var found = false;
        for (self.contacts.items) |c| {
            if (std.mem.eql(u8, c.certId, certId)) { found = true; break; }
        }
        if (!found) return error.contact_not_found;
        const e = EdgeRecord{
            .edgeId = edgeId, .certId = certId, .edgeType = edgeType,
            .signingKeyIndex = signingKeyIndex, .recoveryPolicy = recoveryPolicy,
            .revokedAt = null, .createdAt = 1000,
        };
        try self.edges.append(testing.allocator, e);
        return e;
    }

    fn revokeEdge(ctx: ?*anyopaque, certId: []const u8, edgeId: []const u8) anyerror!void {
        const self: *TestStore = @ptrCast(@alignCast(ctx.?));
        _ = certId;
        for (self.edges.items) |*e| {
            if (std.mem.eql(u8, e.edgeId, edgeId)) {
                if (e.revokedAt != null) return error.edge_already_revoked;
                e.revokedAt = 9999;
                return;
            }
        }
        return error.edge_not_found;
    }

    fn validBearer(_: ?*anyopaque, b: []const u8) bool {
        return std.mem.eql(u8, b, "token");
    }

    fn makeAcceptor(self: *TestStore) Acceptor {
        return .{
            .allocator = testing.allocator,
            .is_bearer_valid = validBearer,
            .list_contacts = listContacts,
            .list_contacts_ctx = self,
            .get_contact = getContact,
            .get_contact_ctx = self,
            .add_contact = addContact,
            .add_contact_ctx = self,
            .add_edge = addEdge,
            .add_edge_ctx = self,
            .revoke_edge = revokeEdge,
            .revoke_edge_ctx = self,
        };
    }
};

test "GET /api/v1/contacts — empty list" {
    var ts = TestStore.init();
    defer ts.deinit();
    const a = ts.makeAcceptor();
    var r = try accept(&a, "GET", "/api/v1/contacts", "token", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.ok, r.kind);
    try testing.expectEqualStrings("{\"contacts\":[]}", r.body);
}

test "GET /api/v1/contacts — lists contacts" {
    var ts = TestStore.init();
    defer ts.deinit();
    try ts.contacts.append(testing.allocator, .{
        .certId = "abc", .publicKey = "pk", .displayName = "Alice",
        .email = null, .source = "manual", .addedAt = 1, .updatedAt = 2,
    });
    const a = ts.makeAcceptor();
    var r = try accept(&a, "GET", "/api/v1/contacts", "token", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.ok, r.kind);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"certId\":\"abc\"") != null);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"displayName\":\"Alice\"") != null);
}

test "GET /api/v1/contacts — missing bearer → 401" {
    var ts = TestStore.init();
    defer ts.deinit();
    const a = ts.makeAcceptor();
    var r = try accept(&a, "GET", "/api/v1/contacts", null, "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.unauthorised, r.kind);
}

test "GET /api/v1/contacts — wrong bearer → 401" {
    var ts = TestStore.init();
    defer ts.deinit();
    const a = ts.makeAcceptor();
    var r = try accept(&a, "GET", "/api/v1/contacts", "bad", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.unauthorised, r.kind);
}

test "POST /api/v1/contacts — adds contact, returns 201" {
    var ts = TestStore.init();
    defer ts.deinit();
    const a = ts.makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/contacts", "token",
        "{\"certId\":\"c1\",\"publicKey\":\"pk1\",\"displayName\":\"Alice\"}");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.created, r.kind);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"certId\":\"c1\"") != null);
    try testing.expectEqual(@as(usize, 1), ts.contacts.items.len);
}

test "POST /api/v1/contacts — malformed body → 400" {
    var ts = TestStore.init();
    defer ts.deinit();
    const a = ts.makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/contacts", "token", "not json");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.bad_request, r.kind);
}

test "POST /api/v1/contacts — missing certId → 400" {
    var ts = TestStore.init();
    defer ts.deinit();
    const a = ts.makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/contacts", "token",
        "{\"publicKey\":\"pk\",\"displayName\":\"Bob\"}");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.bad_request, r.kind);
}

test "GET /api/v1/contacts/{certId} — found" {
    var ts = TestStore.init();
    defer ts.deinit();
    try ts.contacts.append(testing.allocator, .{
        .certId = "cert1", .publicKey = "pk", .displayName = "Alice",
        .email = "alice@example.com", .source = "manual", .addedAt = 1, .updatedAt = 1,
    });
    const a = ts.makeAcceptor();
    var r = try accept(&a, "GET", "/api/v1/contacts/cert1", "token", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.ok, r.kind);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"certId\":\"cert1\"") != null);
    try testing.expect(std.mem.indexOf(u8, r.body, "alice@example.com") != null);
}

test "GET /api/v1/contacts/{certId} — not found → 404" {
    var ts = TestStore.init();
    defer ts.deinit();
    const a = ts.makeAcceptor();
    var r = try accept(&a, "GET", "/api/v1/contacts/nobody", "token", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.not_found, r.kind);
}

test "POST /api/v1/contacts/{certId}/edges — creates edge" {
    var ts = TestStore.init();
    defer ts.deinit();
    try ts.contacts.append(testing.allocator, .{
        .certId = "c1", .publicKey = "pk", .displayName = "Alice",
        .email = null, .source = "manual", .addedAt = 1, .updatedAt = 1,
    });
    const a = ts.makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/contacts/c1/edges", "token",
        "{\"edgeId\":\"e1\",\"edgeType\":\"MESSAGING\",\"signingKeyIndex\":42,\"recoveryPolicy\":\"NONE\"}");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.created, r.kind);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"edgeId\":\"e1\"") != null);
    try testing.expect(std.mem.indexOf(u8, r.body, "\"signingKeyIndex\":42") != null);
}

test "POST /api/v1/contacts/{certId}/edges — contact not found → 404" {
    var ts = TestStore.init();
    defer ts.deinit();
    const a = ts.makeAcceptor();
    var r = try accept(&a, "POST", "/api/v1/contacts/nobody/edges", "token",
        "{\"edgeId\":\"e1\",\"edgeType\":\"MESSAGING\",\"signingKeyIndex\":1,\"recoveryPolicy\":\"NONE\"}");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.not_found, r.kind);
}

test "DELETE /api/v1/contacts/{certId}/edges/{edgeId} — revokes edge" {
    var ts = TestStore.init();
    defer ts.deinit();
    try ts.contacts.append(testing.allocator, .{
        .certId = "c1", .publicKey = "pk", .displayName = "Alice",
        .email = null, .source = "manual", .addedAt = 1, .updatedAt = 1,
    });
    try ts.edges.append(testing.allocator, .{
        .edgeId = "e1", .certId = "c1", .edgeType = "MESSAGING",
        .signingKeyIndex = 5, .recoveryPolicy = "NONE",
        .revokedAt = null, .createdAt = 1,
    });
    const a = ts.makeAcceptor();
    var r = try accept(&a, "DELETE", "/api/v1/contacts/c1/edges/e1", "token", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.no_content, r.kind);
    try testing.expect(ts.edges.items[0].revokedAt != null);
}

test "DELETE /api/v1/contacts/{certId}/edges/{edgeId} — double revoke → 409" {
    var ts = TestStore.init();
    defer ts.deinit();
    try ts.contacts.append(testing.allocator, .{
        .certId = "c1", .publicKey = "pk", .displayName = "Alice",
        .email = null, .source = "manual", .addedAt = 1, .updatedAt = 1,
    });
    try ts.edges.append(testing.allocator, .{
        .edgeId = "e1", .certId = "c1", .edgeType = "MESSAGING",
        .signingKeyIndex = 5, .recoveryPolicy = "NONE",
        .revokedAt = 999, .createdAt = 1,
    });
    const a = ts.makeAcceptor();
    var r = try accept(&a, "DELETE", "/api/v1/contacts/c1/edges/e1", "token", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.conflict, r.kind);
}

test "wrong method → 405" {
    var ts = TestStore.init();
    defer ts.deinit();
    const a = ts.makeAcceptor();
    var r = try accept(&a, "DELETE", "/api/v1/contacts", "token", "");
    defer r.deinit(testing.allocator);
    try testing.expectEqual(ResultKind.method_not_allowed, r.kind);
}

```
