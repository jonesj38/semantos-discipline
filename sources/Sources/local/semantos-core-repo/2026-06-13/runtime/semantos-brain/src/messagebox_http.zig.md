---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/messagebox_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.236443+00:00
---

# runtime/semantos-brain/src/messagebox_http.zig

```zig
// D-network-messagebox-first-class — MessageBox HTTP acceptor.
//
// Provides a store-and-forward relay for BRC-77 signed and BRC-78
// encrypted envelopes between brains.  The relay is sovereign:
// it runs inside semantos-brain with no Cloudflare or third-party
// dependency.
//
// Routes served under /api/v1/messages:
//
//   POST   /api/v1/messages/send
//     Body: { "recipient": "<hex33B>", "kind": "signed"|"encrypted",
//             "payload": "<base64>" }
//     Stores the envelope in the in-memory store keyed by recipient.
//     Returns { "id": "<hex16B>" }.
//
//   GET    /api/v1/messages/list?recipient=<hex33B>
//     Lists pending envelopes for the given recipient pubkey.
//     Returns { "messages": [{ "id", "sender", "kind", "payload", "ts" }] }
//     The caller must be the bearer-authorised owner of the recipient key.
//     V1: bearer validity is checked via is_bearer_valid (same as contacts).
//
//   POST   /api/v1/messages/ack
//     Body: { "id": "<hex16B>" }
//     Marks the message as acknowledged and removes it from the store.
//     Returns 204 No Content.
//
// Design: DI fn-pointer style (same as contacts_http, intent_http).
// V1 store is in-memory (no LMDB persistence).  A follow-on deliverable
// adds LMDB persistence via the same DI seam.

const std = @import("std");

// ─────────────────────────────────────────────────────────────────────
// Message record (V1)
// ─────────────────────────────────────────────────────────────────────

pub const MessageKind = enum {
    signed,
    encrypted,

    pub fn fromString(s: []const u8) ?MessageKind {
        if (std.mem.eql(u8, s, "signed")) return .signed;
        if (std.mem.eql(u8, s, "encrypted")) return .encrypted;
        return null;
    }

    pub fn toString(self: MessageKind) []const u8 {
        return switch (self) {
            .signed => "signed",
            .encrypted => "encrypted",
        };
    }
};

/// A stored message envelope.  All string fields are owned by the
/// store or were supplied by the DI layer; lifetimes managed by the
/// DI store implementation.
pub const MessageRecord = struct {
    /// 16-byte message ID (random, hex-encoded for JSON).
    id: [32]u8,      // hex of 16 raw bytes = 32 chars
    /// Sender's compressed-SEC1 pubkey (hex 66 chars).
    sender_hex: [66]u8,
    /// Recipient's compressed-SEC1 pubkey (hex 66 chars).
    recipient_hex: [66]u8,
    kind: MessageKind,
    /// Base64-encoded raw envelope bytes.
    payload_b64: []const u8, // allocator-owned slice
    /// Unix timestamp ms.
    received_at: i64,
};

// ─────────────────────────────────────────────────────────────────────
// Result kinds
// ─────────────────────────────────────────────────────────────────────

pub const ResultKind = enum {
    ok,
    created,
    no_content,
    bad_request,
    unauthorised,
    not_found,
    method_not_allowed,
    internal_error,

    pub fn httpStatus(self: ResultKind) u16 {
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
    kind: ResultKind,
    body: []u8 = &.{},

    pub fn deinit(self: *AcceptResult, allocator: std.mem.Allocator) void {
        if (self.body.len > 0) allocator.free(self.body);
        self.body = &.{};
    }
};

// ─────────────────────────────────────────────────────────────────────
// DI fn pointer types
// ─────────────────────────────────────────────────────────────────────

pub const IsBearerValidFn = *const fn (ctx: ?*anyopaque, bearer: []const u8) bool;

pub const SendMessageFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    recipient_hex: []const u8,
    sender_hex: []const u8,
    kind: MessageKind,
    payload_b64: []const u8,
    id_out: *[32]u8,
) error{StoreFull, OutOfMemory, Internal}!void;

/// Context passed to ListMessagesFn: matches messages for a recipient.
/// The callback fn allocates the returned slice; caller frees.
pub const ListMessagesFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    recipient_hex: []const u8,
) error{OutOfMemory, Internal}![]MessageRecord;

pub const AckMessageFn = *const fn (
    ctx: ?*anyopaque,
    id_hex: []const u8,
) error{NotFound, Internal}!void;

pub const FreeRecordsFn = *const fn (
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    records: []MessageRecord,
) void;

// ─────────────────────────────────────────────────────────────────────
// Acceptor
// ─────────────────────────────────────────────────────────────────────

/// Optional event-emit callback.  Called after a message is stored
/// successfully by handleSend.  ctx is emit_event_ctx.
/// msg_id points to the 32-char hex message ID (stack lifetime of the
/// handleSend frame — callee must not retain the pointer).
/// recipient_hex is the 66-char hex pubkey of the recipient.
/// kind and ts_ms describe the envelope.
pub const EmitEventFn = *const fn (
    ctx: ?*anyopaque,
    msg_id: *const [32]u8,
    recipient_hex: []const u8,
    kind: MessageKind,
    ts_ms: i64,
) void;

pub const Acceptor = struct {
    allocator: std.mem.Allocator,

    is_bearer_valid: IsBearerValidFn,
    is_bearer_valid_ctx: ?*anyopaque,

    send_message: SendMessageFn,
    send_message_ctx: ?*anyopaque,

    list_messages: ListMessagesFn,
    list_messages_ctx: ?*anyopaque,

    ack_message: AckMessageFn,
    ack_message_ctx: ?*anyopaque,

    free_records: FreeRecordsFn,
    free_records_ctx: ?*anyopaque,

    /// Optional: when non-null, called after every successful /send so that
    /// callers can fan-out a push notification (e.g. OddjobzEventBus).
    emit_event: ?EmitEventFn = null,
    emit_event_ctx: ?*anyopaque = null,
};

// ─────────────────────────────────────────────────────────────────────
// Route dispatch
// ─────────────────────────────────────────────────────────────────────

const BASE = "/api/v1/messages";

/// query is the HTTP query string (the part after '?'), already separated
/// from path by the HTTP parser.  It is passed through to handleList for
/// the ?recipient= lookup.  Empty slice when no query string is present.
///
/// Auth model:
///   POST /send   — unauthenticated.  BRC-77/78 envelopes are self-
///                  authenticating; any remote brain can deposit a message
///                  addressed to any recipient on this brain.
///   GET  /list   — bearer required (recipient-only: only the owner fetches).
///   POST /ack    — bearer required (recipient-only: only the owner acks).
pub fn accept(
    a: *const Acceptor,
    method: []const u8,
    path: []const u8,
    query: []const u8,
    bearer: ?[]const u8,
    body: []const u8,
) !AcceptResult {
    if (!std.mem.startsWith(u8, path, BASE)) return .{ .kind = .not_found };

    const tail = path[BASE.len..];

    // POST /api/v1/messages/send — no bearer required.
    // The envelope carries its own sender identity; bearer auth is
    // intentionally absent so remote brains can deposit messages without
    // needing a token issued by this brain.
    if (std.mem.eql(u8, tail, "/send")) {
        if (!std.mem.eql(u8, method, "POST")) return .{ .kind = .method_not_allowed };
        return handleSend(a, body);
    }

    // All remaining routes (list, ack) require a valid bearer token.
    // These are recipient-only operations: only the owner of the inbox
    // may read or acknowledge messages.
    const bearer_str = bearer orelse return .{ .kind = .unauthorised };
    if (!a.is_bearer_valid(a.is_bearer_valid_ctx, bearer_str)) {
        return .{ .kind = .unauthorised };
    }

    // GET /api/v1/messages/list?recipient=<hex>
    if (std.mem.eql(u8, tail, "/list")) {
        if (!std.mem.eql(u8, method, "GET")) return .{ .kind = .method_not_allowed };
        return handleList(a, query);
    }

    // POST /api/v1/messages/ack
    if (std.mem.eql(u8, tail, "/ack")) {
        if (!std.mem.eql(u8, method, "POST")) return .{ .kind = .method_not_allowed };
        return handleAck(a, body);
    }

    return .{ .kind = .not_found };
}

// ─────────────────────────────────────────────────────────────────────
// Route handlers
// ─────────────────────────────────────────────────────────────────────

fn handleSend(a: *const Acceptor, body: []const u8) !AcceptResult {
    const alloc = a.allocator;

    // Parse JSON: { recipient, kind, payload, sender? }
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, body, .{}) catch {
        return makeErr(alloc, .bad_request, "invalid JSON");
    };
    defer parsed.deinit();
    const root = parsed.value.object;

    const recipient_hex = (root.get("recipient") orelse return makeErr(alloc, .bad_request, "missing recipient")).string;
    const kind_str = (root.get("kind") orelse return makeErr(alloc, .bad_request, "missing kind")).string;
    const payload_b64 = (root.get("payload") orelse return makeErr(alloc, .bad_request, "missing payload")).string;
    const sender_hex = if (root.get("sender")) |s| s.string else "unknown";

    if (recipient_hex.len != 66) return makeErr(alloc, .bad_request, "recipient must be 66 hex chars (33B pubkey)");

    const kind = MessageKind.fromString(kind_str) orelse
        return makeErr(alloc, .bad_request, "kind must be 'signed' or 'encrypted'");

    var id_hex: [32]u8 = undefined;
    a.send_message(
        a.send_message_ctx,
        alloc,
        recipient_hex,
        sender_hex,
        kind,
        payload_b64,
        &id_hex,
    ) catch |err| switch (err) {
        error.StoreFull => return makeErr(alloc, .internal_error, "store full"),
        error.OutOfMemory => return makeErr(alloc, .internal_error, "oom"),
        error.Internal => return makeErr(alloc, .internal_error, "store error"),
    };

    // Notify event subscribers (e.g. OddjobzEventBus → /api/v1/events WSS).
    if (a.emit_event) |emit_fn| {
        emit_fn(a.emit_event_ctx, &id_hex, recipient_hex, kind, std.time.milliTimestamp());
    }

    // { "id": "<hex32>" }
    const resp = std.fmt.allocPrint(alloc, "{{\"id\":\"{s}\"}}", .{id_hex}) catch
        return .{ .kind = .internal_error };
    return .{ .kind = .created, .body = resp };
}

/// query is the HTTP query string without the leading '?' (already parsed
/// by the HTTP parser layer, e.g. "recipient=029cf8e4...").
fn handleList(a: *const Acceptor, query: []const u8) !AcceptResult {
    const alloc = a.allocator;

    // query is already the bare query string (no leading '?').
    if (query.len == 0)
        return makeErr(alloc, .bad_request, "missing ?recipient= query");
    const recipient_hex = extractQueryParam(query, "recipient") orelse
        return makeErr(alloc, .bad_request, "missing recipient query param");

    if (recipient_hex.len != 66) return makeErr(alloc, .bad_request, "recipient must be 66 hex chars");

    const records = a.list_messages(a.list_messages_ctx, alloc, recipient_hex) catch |err| switch (err) {
        error.OutOfMemory => return .{ .kind = .internal_error },
        error.Internal => return .{ .kind = .internal_error },
    };
    defer a.free_records(a.free_records_ctx, alloc, records);

    // Build JSON array
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(alloc);
    errdefer buf.deinit(alloc);

    try buf.appendSlice(alloc, "{\"messages\":[");
    for (records, 0..) |*rec, i| {
        if (i > 0) try buf.append(alloc, ',');
        try buf.appendSlice(alloc, "{\"id\":\"");
        try buf.appendSlice(alloc, &rec.id);
        try buf.appendSlice(alloc, "\",\"sender\":\"");
        try buf.appendSlice(alloc, &rec.sender_hex);
        try buf.appendSlice(alloc, "\",\"kind\":\"");
        try buf.appendSlice(alloc, rec.kind.toString());
        try buf.appendSlice(alloc, "\",\"payload\":\"");
        try buf.appendSlice(alloc, rec.payload_b64);
        try buf.appendSlice(alloc, "\",\"ts\":");
        var ts_buf: [24]u8 = undefined;
        const ts_str = std.fmt.bufPrint(&ts_buf, "{d}", .{rec.received_at}) catch "0";
        try buf.appendSlice(alloc, ts_str);
        try buf.append(alloc, '}');
    }
    try buf.appendSlice(alloc, "]}");

    const resp = try buf.toOwnedSlice(alloc);
    return .{ .kind = .ok, .body = resp };
}

fn handleAck(a: *const Acceptor, body: []const u8) !AcceptResult {
    const alloc = a.allocator;

    const parsed = std.json.parseFromSlice(std.json.Value, alloc, body, .{}) catch {
        return makeErr(alloc, .bad_request, "invalid JSON");
    };
    defer parsed.deinit();

    const id_hex = (parsed.value.object.get("id") orelse
        return makeErr(alloc, .bad_request, "missing id")).string;

    a.ack_message(a.ack_message_ctx, id_hex) catch |err| switch (err) {
        error.NotFound => return makeErr(alloc, .not_found, "message not found"),
        error.Internal => return makeErr(alloc, .internal_error, "store error"),
    };

    return .{ .kind = .no_content };
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

fn makeErr(alloc: std.mem.Allocator, kind: ResultKind, msg: []const u8) !AcceptResult {
    const body = std.fmt.allocPrint(alloc, "{{\"error\":\"{s}\"}}", .{msg}) catch
        return .{ .kind = kind };
    return .{ .kind = kind, .body = body };
}

fn extractQueryParam(query: []const u8, name: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |part| {
        const eq = std.mem.indexOfScalar(u8, part, '=') orelse continue;
        if (std.mem.eql(u8, part[0..eq], name)) return part[eq + 1 ..];
    }
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// In-memory store (V1 — no persistence)
// ─────────────────────────────────────────────────────────────────────
//
// The store is a simple ArrayList.  For V1 production, the brain
// restarts clear the store.  A follow-on adds LMDB persistence.
//
// Concurrency: the single-threaded brain reactor owns this store;
// no locks needed (same guarantee as other brain stores).

pub const MemStore = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayListUnmanaged(StoredMsg),

    const StoredMsg = struct {
        id_hex: [32]u8,
        sender_hex: [66]u8,
        recipient_hex: [66]u8,
        kind: MessageKind,
        payload_b64: []u8, // owned
        received_at: i64,
    };

    pub fn init(allocator: std.mem.Allocator) MemStore {
        return .{
            .allocator = allocator,
            .messages = .{},
        };
    }

    pub fn deinit(self: *MemStore) void {
        for (self.messages.items) |*m| self.allocator.free(m.payload_b64);
        self.messages.deinit(self.allocator);
    }

    // ── DI fn implementations ──────────────────────────────────────

    pub fn send(
        ctx: ?*anyopaque,
        allocator: std.mem.Allocator,
        recipient_hex: []const u8,
        sender_hex: []const u8,
        kind: MessageKind,
        payload_b64: []const u8,
        id_out: *[32]u8,
    ) error{StoreFull, OutOfMemory, Internal}!void {
        const self: *MemStore = @ptrCast(@alignCast(ctx.?));

        // Random 16-byte ID, hex-encoded to 32 chars
        var id_raw: [16]u8 = undefined;
        std.crypto.random.bytes(&id_raw);
        var id_hex: [32]u8 = undefined;
        hexEncode(&id_raw, &id_hex);
        @memcpy(id_out, &id_hex);

        var m = StoredMsg{
            .id_hex = id_hex,
            .sender_hex = undefined,
            .recipient_hex = undefined,
            .kind = kind,
            .payload_b64 = undefined,
            .received_at = std.time.milliTimestamp(),
        };
        // Copy fixed-len hex fields (caller may have shorter strings)
        hexCopyPad(&m.sender_hex, sender_hex);
        hexCopyPad(&m.recipient_hex, recipient_hex);
        m.payload_b64 = allocator.dupe(u8, payload_b64) catch return error.OutOfMemory;
        errdefer allocator.free(m.payload_b64);

        self.messages.append(self.allocator, m) catch return error.OutOfMemory;
    }

    pub fn list(
        ctx: ?*anyopaque,
        allocator: std.mem.Allocator,
        recipient_hex: []const u8,
    ) error{OutOfMemory, Internal}![]MessageRecord {
        const self: *MemStore = @ptrCast(@alignCast(ctx.?));
        var out: std.ArrayListUnmanaged(MessageRecord) = .{};
        errdefer {
            for (out.items) |*rec| allocator.free(rec.payload_b64);
            out.deinit(allocator);
        }
        for (self.messages.items) |*m| {
            if (!std.mem.eql(u8, m.recipient_hex[0..recipient_hex.len], recipient_hex)) continue;
            const rec = MessageRecord{
                .id = m.id_hex,
                .sender_hex = m.sender_hex,
                .recipient_hex = m.recipient_hex,
                .kind = m.kind,
                .payload_b64 = allocator.dupe(u8, m.payload_b64) catch return error.OutOfMemory,
                .received_at = m.received_at,
            };
            out.append(allocator, rec) catch return error.OutOfMemory;
        }
        return try out.toOwnedSlice(allocator);
    }

    pub fn ack(ctx: ?*anyopaque, id_hex: []const u8) error{NotFound, Internal}!void {
        const self: *MemStore = @ptrCast(@alignCast(ctx.?));
        for (self.messages.items, 0..) |*m, i| {
            if (std.mem.eql(u8, &m.id_hex, id_hex)) {
                self.allocator.free(m.payload_b64);
                _ = self.messages.orderedRemove(i);
                return;
            }
        }
        return error.NotFound;
    }

    pub fn freeRecords(
        ctx: ?*anyopaque,
        allocator: std.mem.Allocator,
        records: []MessageRecord,
    ) void {
        _ = ctx;
        for (records) |*rec| allocator.free(rec.payload_b64);
        allocator.free(records);
    }

    fn hexEncode(src: []const u8, out: []u8) void {
        const chars = "0123456789abcdef";
        for (src, 0..) |b, i| {
            out[i * 2] = chars[b >> 4];
            out[i * 2 + 1] = chars[b & 0xf];
        }
    }

    fn hexCopyPad(dst: *[66]u8, src: []const u8) void {
        @memset(dst, '0');
        const n = @min(src.len, dst.len);
        @memcpy(dst[0..n], src[0..n]);
    }
};

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

fn alwaysValid(_: ?*anyopaque, _: []const u8) bool {
    return true;
}

fn makeTestAcceptor(allocator: std.mem.Allocator, store: *MemStore) Acceptor {
    return .{
        .allocator = allocator,
        .is_bearer_valid = alwaysValid,
        .is_bearer_valid_ctx = null,
        .send_message = MemStore.send,
        .send_message_ctx = store,
        .list_messages = MemStore.list,
        .list_messages_ctx = store,
        .ack_message = MemStore.ack,
        .ack_message_ctx = store,
        .free_records = MemStore.freeRecords,
        .free_records_ctx = null,
    };
}

const TEST_RECIPIENT = "02" ++ "a5" ** 32; // 66 hex chars, dummy pubkey

test "messagebox: send + list + ack round-trip" {
    const alloc = std.testing.allocator;
    var store = MemStore.init(alloc);
    defer store.deinit();
    const a = makeTestAcceptor(alloc, &store);

    // Send — no bearer required (open deposit endpoint).
    const send_body =
        \\{"recipient":"02a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5",
        \\"kind":"signed","payload":"aGVsbG8gd29ybGQ=","sender":"03b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"}
    ;
    var r = try accept(&a, "POST", BASE ++ "/send", "", null, send_body);
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.created, r.kind);
    try std.testing.expect(std.mem.startsWith(u8, r.body, "{\"id\":\""));

    // Extract returned id
    const id_start = std.mem.indexOf(u8, r.body, "\"id\":\"").? + 6;
    const id_end = std.mem.indexOfScalar(u8, r.body[id_start..], '"').? + id_start;
    const msg_id = r.body[id_start..id_end];
    try std.testing.expectEqual(@as(usize, 32), msg_id.len);

    // List — query string passed separately (no '?' prefix)
    var list_r = try accept(&a, "GET", BASE ++ "/list", "recipient=02a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5", "tok", "");
    defer list_r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.ok, list_r.kind);
    try std.testing.expect(std.mem.indexOf(u8, list_r.body, "aGVsbG8gd29ybGQ=") != null);

    // Ack
    const ack_body = try std.fmt.allocPrint(alloc, "{{\"id\":\"{s}\"}}", .{msg_id});
    defer alloc.free(ack_body);
    var ack_r = try accept(&a, "POST", BASE ++ "/ack", "", "tok", ack_body);
    defer ack_r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.no_content, ack_r.kind);

    // List again — should be empty
    var list_r2 = try accept(&a, "GET", BASE ++ "/list", "recipient=02a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5", "tok", "");
    defer list_r2.deinit(alloc);
    try std.testing.expect(std.mem.eql(u8, list_r2.body, "{\"messages\":[]}"));
}

test "messagebox: ack unknown id returns 404" {
    const alloc = std.testing.allocator;
    var store = MemStore.init(alloc);
    defer store.deinit();
    const a = makeTestAcceptor(alloc, &store);

    // Ack requires bearer; use a valid one here.
    var r = try accept(&a, "POST", BASE ++ "/ack", "", "tok", "{\"id\":\"deadbeef00000000deadbeef00000000\"}");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.not_found, r.kind);
}

test "messagebox: unauthorised bearer rejected" {
    const alloc = std.testing.allocator;
    var store = MemStore.init(alloc);
    defer store.deinit();
    var a = makeTestAcceptor(alloc, &store);

    // Replace with a validator that always rejects
    const always_invalid = struct {
        fn f(_: ?*anyopaque, _: []const u8) bool { return false; }
    }.f;
    a.is_bearer_valid = always_invalid;

    var r = try accept(&a, "GET", BASE ++ "/list", "recipient=02a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5", "bad", "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.unauthorised, r.kind);
}

test "messagebox: send accepts no bearer (open deposit)" {
    const alloc = std.testing.allocator;
    var store = MemStore.init(alloc);
    defer store.deinit();
    const a = makeTestAcceptor(alloc, &store);

    // No bearer — /send must still succeed.
    var r = try accept(&a, "POST", BASE ++ "/send", "", null,
        \\{"recipient":"02a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5",
        \\"kind":"signed","payload":"dGVzdA==","sender":"03b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"}
    );
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.created, r.kind);
}

test "messagebox: list requires bearer (401 without)" {
    const alloc = std.testing.allocator;
    var store = MemStore.init(alloc);
    defer store.deinit();
    const a = makeTestAcceptor(alloc, &store);

    var r = try accept(&a, "GET", BASE ++ "/list",
        "recipient=02a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5",
        null, "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.unauthorised, r.kind);
}

test "messagebox: missing bearer returns 401" {
    const alloc = std.testing.allocator;
    var store = MemStore.init(alloc);
    defer store.deinit();
    const a = makeTestAcceptor(alloc, &store);

    var r = try accept(&a, "GET", BASE ++ "/list", "recipient=02a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5", null, "");
    defer r.deinit(alloc);
    try std.testing.expectEqual(ResultKind.unauthorised, r.kind);
}

```
