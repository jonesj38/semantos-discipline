---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/attachments_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.478281+00:00
---

# cartridges/oddjobz/brain/zig/attachments_handler.zig

```zig
// D-O5m.followup-8 substrate — Typed `attachments` dispatcher resource.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3, §8;
//            docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5m (mobile sensor
//            adapters);
//            cartridges/oddjobz/brain/src/cell-types/attachment.ts (TS canon
//            for the OddjobzAttachment shape).
//
// Mirrors `visits_handler.zig` for the Attachment cell type minus the
// FSM transition cmd (Attachments are AFFINE-ish — write-once, no FSM).
// Both helms wire a read-only attachments list under VisitDetail; the
// dispatcher's audit pair captures every metadata create.
//
// Commands:
//
//   find             — { visit_id? }       →  [ Attachment, ... ]
//                                              cap = cap.oddjobz.read_attachments
//                                            When `visit_id` is supplied,
//                                            the response is filtered to
//                                            attachments under that Visit.
//
//   find_by_id       — { id }              →  Attachment
//                                              cap = cap.oddjobz.read_attachments
//                                            (or { error: "not_found", id }
//                                             on miss — same shape as
//                                             visits_handler / customers_
//                                             handler)
//
//   create_metadata  — { id?, visit_id,
//                        kind, content_hash,
//                        content_size,
//                        mime_type,
//                        captured_at,
//                        captured_by_cert_id,
//                        caption? }        →  { id, status: "created"
//                                                     | "already_exists" }
//                                              cap = cap.oddjobz.write_attachment
//                                            Validates: visit_id exists in
//                                            visits_store (else `{error:
//                                            "visit_not_found", visit_id}`);
//                                            kind ∈ ATTACHMENT_KINDS;
//                                            content_hash is 64 hex chars;
//                                            content_size ≥ 0; mime_type
//                                            is non-empty; captured_at is
//                                            ≤ 64 bytes; captured_by_cert_id
//                                            is 32 hex chars; caption ≤ 500
//                                            chars if present.
//                                            Idempotency: same id with
//                                            identical contents → already_
//                                            exists; same id with different
//                                            contents → typed error.
//
// IMPORTANT: this command writes ONLY the metadata cell.  Binary blob
// upload is a SEPARATE concern handled in the next PR via a multipart
// HTTP endpoint (typed by content_hash on this cell).
//
// FK validation: `attachments.create_metadata` calls
// `visits_store.findById(visit_id)` before delegating to the
// attachments store.  Loose-coupling seam — the attachments store
// doesn't know about the visits store; the handler knits them together
// at the dispatcher layer.
//
// Concurrency: a single mutex serialises all handler entry points
// against the live store; same shape as visits_handler.zig +
// jobs_handler.zig.

const std = @import("std");
const dispatcher = @import("dispatcher");
const verb_schema = @import("verb_schema"); // C4 PR-R2b — generic-REPL verb self-description
const attachments_store_fs = @import("attachments_store_fs");
const visits_store_fs = @import("visits_store_fs");
const helm_event_broker = @import("helm_event_broker");
const audit_log = @import("audit_log");

pub const RESOURCE_NAME = "attachments";

/// Capability declarations.
///
/// `cap.oddjobz.read_attachments` (`0x0001010F`) and
/// `cap.oddjobz.write_attachment` (`0x00010110`) are the two new caps
/// minted in `cartridges/oddjobz/brain/src/capabilities.ts` alongside the
/// existing fourteen oddjobz caps.
pub const CAP_READ_ATTACHMENTS: []const u8 = "cap.oddjobz.read_attachments";
pub const CAP_WRITE_ATTACHMENT: []const u8 = "cap.oddjobz.write_attachment";

pub const HandlerError = error{
    /// JSON args parse failed or required arg missing.
    invalid_args,
    /// Underlying AttachmentsStore validator rejected the input.
    invalid_id,
    invalid_visit_id,
    invalid_kind,
    invalid_content_hash,
    invalid_content_size,
    invalid_mime_type,
    invalid_captured_at,
    invalid_captured_by_cert_id,
    invalid_caption,
    /// Caller passed an id that already exists in the store but the
    /// other fields disagree with what's on file.  Idempotent recreate
    /// requires byte-identical contents.
    attachment_id_in_use_with_different_contents,
    /// Underlying store I/O failed.
    store_error,
    /// Result-allocation failed.
    out_of_memory,
};

/// State carried alongside the resource registration.  Same shape as
/// visits_handler.Handler post-#312 — the handler is the sole owner of
/// the AttachmentsStore for the dispatcher's lifetime; the daemon (or
/// REPL bootstrap) constructs it once at boot and registers the
/// handler via `register`.  The handler also borrows a pointer to the
/// VisitsStore for FK validation on `attachments.create_metadata` —
/// loose-coupling seam (the attachments store itself doesn't know
/// about the visits store).
pub const Handler = struct {
    allocator: std.mem.Allocator,
    store: *attachments_store_fs.AttachmentsStore,
    /// Borrowed pointer to the live VisitsStore — used by
    /// `attachments.create_metadata` to validate that the
    /// caller-supplied `visit_id` references an extant Visit record.
    /// May be null when the daemon stood up the attachments handler
    /// without a visits store (best-effort init posture matches the
    /// cli wiring); FK validation is skipped in that case (the
    /// attachments store still validates length envelope on visit_id).
    visits_store: ?*visits_store_fs.VisitsStore,
    /// Serialises find / find_by_id / create_metadata against the
    /// underlying store.  The store itself is not thread-safe; this
    /// mutex is the seam between concurrent transport callers.
    mu: std.Thread.Mutex,
    /// D-O5.followup-4 — optional event broker.  When non-null, every
    /// successful `attachments.create_metadata` publishes
    /// `attachment.created` to the broker so live WSS subscribers
    /// (the helms) update in real time when a new photo / GPS / voice
    /// memo metadata cell lands under a Visit.  Mirrors the
    /// jobs_handler emit shape from #318.
    broker: ?*helm_event_broker.Broker,
    /// D-O5.followup-4 — optional audit log for phase=publish lines.
    audit: ?*audit_log.AuditLog,

    pub fn init(
        allocator: std.mem.Allocator,
        store: *attachments_store_fs.AttachmentsStore,
        visits_store: ?*visits_store_fs.VisitsStore,
    ) Handler {
        return initWithBroker(allocator, store, visits_store, null, null);
    }

    /// D-O5.followup-4 — broker-aware constructor.
    pub fn initWithBroker(
        allocator: std.mem.Allocator,
        store: *attachments_store_fs.AttachmentsStore,
        visits_store: ?*visits_store_fs.VisitsStore,
        broker: ?*helm_event_broker.Broker,
        audit: ?*audit_log.AuditLog,
    ) Handler {
        return .{
            .allocator = allocator,
            .store = store,
            .visits_store = visits_store,
            .mu = .{},
            .broker = broker,
            .audit = audit,
        };
    }

    /// Build the dispatcher.ResourceHandler v-table entry for this
    /// instance.  Caller registers it via `dispatcher.Dispatcher.register`.
    pub fn resourceHandler(self: *Handler) dispatcher.ResourceHandler {
        return .{
            .name = RESOURCE_NAME,
            .state = self,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handle,
            .verbs_fn = verbsFn,
        };
    }
};

// C4 PR-R2b — verb self-description for the generic `attachments <verb>` REPL
// path. The mutating verb is `create_metadata` (not `create`).
const ATTACHMENTS_VERBS = [_]verb_schema.VerbSpec{
    .{ .verb = "find", .summary = "list attachments (optional visit_id filter)", .args = &.{
        .{ .name = "visit_id", .kind = .string },
    } },
    .{ .verb = "find_by_id", .summary = "fetch one attachment by id", .args = &.{
        .{ .name = "id", .kind = .string, .required = true, .positional = true },
    } },
    .{ .verb = "create_metadata", .summary = "register attachment metadata (FK to visit)", .args = &.{
        .{ .name = "visit_id", .kind = .string, .required = true },
        .{ .name = "kind", .kind = .string, .required = true },
        .{ .name = "content_hash", .kind = .string, .required = true },
        .{ .name = "content_size", .kind = .int, .required = true },
        .{ .name = "mime_type", .kind = .string, .required = true },
        .{ .name = "captured_at", .kind = .string, .required = true },
        .{ .name = "captured_by_cert_id", .kind = .string, .required = true },
        .{ .name = "id", .kind = .string },
        .{ .name = "caption", .kind = .string },
        .{ .name = "created_at", .kind = .string },
    } },
};
fn verbsFn(_: ?*anyopaque) []const verb_schema.VerbSpec {
    return &ATTACHMENTS_VERBS;
}

// ─────────────────────────────────────────────────────────────────────
// Capability declarations
// ─────────────────────────────────────────────────────────────────────

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "find")) return .{ .require = CAP_READ_ATTACHMENTS };
    if (std.mem.eql(u8, cmd, "find_by_id")) return .{ .require = CAP_READ_ATTACHMENTS };
    if (std.mem.eql(u8, cmd, "create_metadata")) return .{ .require = CAP_WRITE_ATTACHMENT };
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Dispatch entry point
// ─────────────────────────────────────────────────────────────────────

fn handle(
    state: ?*anyopaque,
    ctx: *const dispatcher.DispatchContext,
    cmd: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher.Result {
    _ = ctx;
    const self: *Handler = @ptrCast(@alignCast(state.?));
    self.mu.lock();
    defer self.mu.unlock();

    if (std.mem.eql(u8, cmd, "find")) return handleFind(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "find_by_id")) return handleFindById(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "create_metadata")) return handleCreateMetadata(self, allocator, args_json);
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Per-command implementations
// ─────────────────────────────────────────────────────────────────────

fn handleFind(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const filter = parseFindArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer if (filter) |f| allocator.free(f);

    const items: []attachments_store_fs.Attachment = if (filter) |f|
        self.store.findByVisitId(allocator, f) catch return HandlerError.store_error
    else
        self.store.findAll(allocator) catch return HandlerError.store_error;
    defer allocator.free(items);

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.append(allocator, '[');
    for (items, 0..) |row, i| {
        if (i != 0) try buf.append(allocator, ',');
        try writeAttachmentJson(allocator, &buf, row);
    }
    try buf.append(allocator, ']');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleCreateMetadata(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    var args = parseCreateArgs(allocator, args_json) catch |err| switch (err) {
        error.invalid_id => return HandlerError.invalid_id,
        error.invalid_visit_id => return HandlerError.invalid_visit_id,
        error.invalid_kind => return HandlerError.invalid_kind,
        error.invalid_content_hash => return HandlerError.invalid_content_hash,
        error.invalid_content_size => return HandlerError.invalid_content_size,
        error.invalid_mime_type => return HandlerError.invalid_mime_type,
        error.invalid_captured_at => return HandlerError.invalid_captured_at,
        error.invalid_captured_by_cert_id => return HandlerError.invalid_captured_by_cert_id,
        error.invalid_caption => return HandlerError.invalid_caption,
        error.OutOfMemory => return HandlerError.out_of_memory,
        else => return HandlerError.invalid_args,
    };
    defer args.deinit(allocator);

    // FK validation: if the handler was wired with a VisitsStore
    // pointer, confirm `visit_id` references an extant Visit.  Returns
    // a typed `{error: "visit_not_found", visit_id}` body (200, NOT a
    // dispatcher error) so the helm can render a useful operator
    // message instead of a transport-level dispatch failure.  Without
    // a VisitsStore pointer we fall through (best-effort; the
    // attachments store still checks the length envelope).
    if (self.visits_store) |vs| {
        if (vs.findById(args.visit_id) == null) {
            var buf: std.ArrayList(u8) = .{};
            errdefer buf.deinit(allocator);
            try buf.appendSlice(allocator, "{\"error\":\"visit_not_found\",\"visit_id\":");
            try writeJsonString(allocator, &buf, args.visit_id);
            try buf.append(allocator, '}');
            return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
        }
    }

    // Acceptance: when the caller passes an id that already exists,
    // the contents MUST be byte-identical for the request to be
    // idempotent.  Differing contents return a typed validation error
    // instead of silently shadowing the prior record.  Mirrors
    // visits_handler's posture.
    if (self.store.findById(args.id)) |existing| {
        if (!attachmentContentsEqual(existing, args)) {
            return HandlerError.attachment_id_in_use_with_different_contents;
        }
    }

    const att = attachments_store_fs.Attachment{
        .id = args.id,
        .visit_id = args.visit_id,
        .kind = args.kind,
        .content_hash = args.content_hash,
        .content_size = args.content_size,
        .mime_type = args.mime_type,
        .captured_at = args.captured_at,
        .captured_by_cert_id = args.captured_by_cert_id,
        .caption = args.caption,
        .created_at = args.created_at,
    };

    const outcome = self.store.append(att) catch |err| switch (err) {
        attachments_store_fs.StoreError.invalid_id => return HandlerError.invalid_id,
        attachments_store_fs.StoreError.invalid_visit_id => return HandlerError.invalid_visit_id,
        attachments_store_fs.StoreError.invalid_kind => return HandlerError.invalid_kind,
        attachments_store_fs.StoreError.invalid_content_hash => return HandlerError.invalid_content_hash,
        attachments_store_fs.StoreError.invalid_content_size => return HandlerError.invalid_content_size,
        attachments_store_fs.StoreError.invalid_mime_type => return HandlerError.invalid_mime_type,
        attachments_store_fs.StoreError.invalid_captured_at => return HandlerError.invalid_captured_at,
        attachments_store_fs.StoreError.invalid_captured_by_cert_id => return HandlerError.invalid_captured_by_cert_id,
        attachments_store_fs.StoreError.invalid_caption => return HandlerError.invalid_caption,
        else => return HandlerError.store_error,
    };

    // D-O5.followup-4 — emit `attachment.created` after a genuine new
    // metadata write.  Best-effort; does NOT fail the create on emit
    // error.  No FSM on attachments — affine write-once.
    if (outcome == .created) {
        emitAttachmentCreated(
            self,
            args.id,
            args.visit_id,
            args.kind,
            args.content_size,
            args.created_at,
        ) catch {};
    }

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, &buf, args.id);
    try buf.appendSlice(allocator, ",\"status\":\"");
    try buf.appendSlice(allocator, switch (outcome) {
        .created => "created",
        .already_exists => "already_exists",
    });
    try buf.appendSlice(allocator, "\"}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

/// D-O5.followup-4 — publish an `attachment.created` event to the broker.
fn emitAttachmentCreated(
    self: *Handler,
    id: []const u8,
    visit_id: []const u8,
    kind: []const u8,
    content_size: i64,
    created_at: []const u8,
) !void {
    const broker = self.broker orelse return;
    const allocator = self.allocator;

    var payload: std.ArrayList(u8) = .{};
    defer payload.deinit(allocator);
    try payload.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, &payload, id);
    try payload.appendSlice(allocator, ",\"visit_id\":");
    try writeJsonString(allocator, &payload, visit_id);
    try payload.appendSlice(allocator, ",\"kind\":");
    try writeJsonString(allocator, &payload, kind);
    try payload.print(allocator, ",\"content_size\":{d}", .{content_size});
    try payload.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, &payload, created_at);
    try payload.append(allocator, '}');

    broker.publish(.{
        .type = "attachment.created",
        .payload_json = payload.items,
    });

    if (self.audit) |a| {
        a.record(allocator, .{
            .module = "helm.broker",
            .op = "publish",
            .result = .ok,
            .detail = "attachment.created",
        }) catch {};
    }
}

fn handleFindById(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const id = parseFindByIdArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(id);

    const got = self.store.findById(id) orelse {
        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try buf.appendSlice(allocator, "{\"error\":\"not_found\",\"id\":");
        try writeJsonString(allocator, &buf, id);
        try buf.append(allocator, '}');
        return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
    };

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try writeAttachmentJson(allocator, &buf, got);
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// Args parsing
// ─────────────────────────────────────────────────────────────────────

const CreateArgs = struct {
    id: []u8,
    visit_id: []u8,
    kind: []u8,
    content_hash: []u8,
    content_size: i64,
    mime_type: []u8,
    captured_at: []u8,
    captured_by_cert_id: []u8,
    caption: []u8,
    created_at: []u8,

    pub fn deinit(self: *CreateArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.visit_id);
        allocator.free(self.kind);
        allocator.free(self.content_hash);
        allocator.free(self.mime_type);
        allocator.free(self.captured_at);
        allocator.free(self.captured_by_cert_id);
        allocator.free(self.caption);
        allocator.free(self.created_at);
    }
};

const ParseError = error{
    invalid_args,
    invalid_id,
    invalid_visit_id,
    invalid_kind,
    invalid_content_hash,
    invalid_content_size,
    invalid_mime_type,
    invalid_captured_at,
    invalid_captured_by_cert_id,
    invalid_caption,
    out_of_memory,
    OutOfMemory,
};

/// `find` accepts an optional `{visit_id: "..."}` filter.  Returns
/// null when no filter is present (caller treats that as "all
/// attachments"); the allocator owns the returned slice when non-null.
fn parseFindArgs(allocator: std.mem.Allocator, args_json: []const u8) !?[]u8 {
    if (args_json.len == 0) return null;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const obj = parsed.value.object;
    const v = obj.get("visit_id") orelse return null;
    if (v != .string) return null;
    if (v.string.len == 0) return null;
    return try allocator.dupe(u8, v.string);
}

fn parseCreateArgs(allocator: std.mem.Allocator, args_json: []const u8) ParseError!CreateArgs {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return error.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    // visit_id (required, non-empty, ≤ 64).
    const vi_v = obj.get("visit_id") orelse return error.invalid_visit_id;
    if (vi_v != .string) return error.invalid_visit_id;
    if (vi_v.string.len == 0 or vi_v.string.len > attachments_store_fs.MAX_VISIT_ID_BYTES) return error.invalid_visit_id;

    // kind (required, must match ATTACHMENT_KINDS).
    const k_v = obj.get("kind") orelse return error.invalid_kind;
    if (k_v != .string) return error.invalid_kind;
    if (!attachments_store_fs.isValidKind(k_v.string)) return error.invalid_kind;

    // content_hash (required, exactly 64 lowercase hex).
    const ch_v = obj.get("content_hash") orelse return error.invalid_content_hash;
    if (ch_v != .string) return error.invalid_content_hash;
    if (!attachments_store_fs.isValidHex(ch_v.string, attachments_store_fs.CONTENT_HASH_LEN)) return error.invalid_content_hash;

    // content_size (required, integer ≥ 0).
    const cs_v = obj.get("content_size") orelse return error.invalid_content_size;
    const content_size: i64 = switch (cs_v) {
        .integer => |n| n,
        .float => |f| @intFromFloat(f),
        else => return error.invalid_content_size,
    };
    if (content_size < 0) return error.invalid_content_size;

    // mime_type (required, non-empty, ≤ 128).
    const mt_v = obj.get("mime_type") orelse return error.invalid_mime_type;
    if (mt_v != .string) return error.invalid_mime_type;
    if (mt_v.string.len == 0 or mt_v.string.len > attachments_store_fs.MAX_MIME_TYPE_BYTES) return error.invalid_mime_type;

    // captured_at (required, ≤ 64; minimal length-envelope check —
    // operators surface a richer ISO-8601 check on the cell side).
    const ca_v = obj.get("captured_at") orelse return error.invalid_captured_at;
    if (ca_v != .string) return error.invalid_captured_at;
    if (ca_v.string.len == 0 or ca_v.string.len > attachments_store_fs.MAX_CAPTURED_AT_BYTES) return error.invalid_captured_at;

    // captured_by_cert_id (required, exactly 32 lowercase hex).
    const cci_v = obj.get("captured_by_cert_id") orelse return error.invalid_captured_by_cert_id;
    if (cci_v != .string) return error.invalid_captured_by_cert_id;
    if (!attachments_store_fs.isValidHex(cci_v.string, attachments_store_fs.CERT_ID_LEN)) return error.invalid_captured_by_cert_id;

    // id (optional — server-stamped when empty).
    const id_str: []const u8 = blk: {
        if (obj.get("id")) |v| {
            if (v != .string) return error.invalid_id;
            if (v.string.len > attachments_store_fs.MAX_ID_BYTES) return error.invalid_id;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };

    // caption (optional, ≤ 500).
    const cap_v: []const u8 = blk: {
        if (obj.get("caption")) |v| {
            if (v != .string) return error.invalid_caption;
            if (v.string.len > attachments_store_fs.MAX_CAPTION_BYTES) return error.invalid_caption;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // created_at (optional; server-stamps when empty).
    const cra_v: []const u8 = blk: {
        if (obj.get("created_at")) |v| {
            if (v != .string) return error.invalid_args;
            if (v.string.len > attachments_store_fs.MAX_CREATED_AT_BYTES) return error.invalid_args;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };

    // Allocate owned copies.
    var id_owned: []u8 = undefined;
    if (id_str.len == 0) {
        var id_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&id_bytes);
        const id_alloc = try allocator.alloc(u8, 32);
        hexEncode(&id_bytes, id_alloc);
        id_owned = id_alloc;
    } else {
        id_owned = try allocator.dupe(u8, id_str);
    }
    errdefer allocator.free(id_owned);

    const vi_owned = try allocator.dupe(u8, vi_v.string);
    errdefer allocator.free(vi_owned);
    const k_owned = try allocator.dupe(u8, k_v.string);
    errdefer allocator.free(k_owned);
    const ch_owned = try allocator.dupe(u8, ch_v.string);
    errdefer allocator.free(ch_owned);
    const mt_owned = try allocator.dupe(u8, mt_v.string);
    errdefer allocator.free(mt_owned);
    const ca_owned = try allocator.dupe(u8, ca_v.string);
    errdefer allocator.free(ca_owned);
    const cci_owned = try allocator.dupe(u8, cci_v.string);
    errdefer allocator.free(cci_owned);
    const cap_owned = try allocator.dupe(u8, cap_v);
    errdefer allocator.free(cap_owned);

    var cra_owned: []u8 = undefined;
    if (cra_v.len == 0) {
        cra_owned = try renderIsoTimestamp(allocator, std.time.timestamp());
    } else {
        cra_owned = try allocator.dupe(u8, cra_v);
    }
    errdefer allocator.free(cra_owned);

    return .{
        .id = id_owned,
        .visit_id = vi_owned,
        .kind = k_owned,
        .content_hash = ch_owned,
        .content_size = content_size,
        .mime_type = mt_owned,
        .captured_at = ca_owned,
        .captured_by_cert_id = cci_owned,
        .caption = cap_owned,
        .created_at = cra_owned,
    };
}

fn parseFindByIdArgs(allocator: std.mem.Allocator, args_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const v = obj.get("id") orelse return error.invalid_args;
    if (v != .string) return error.invalid_args;
    if (v.string.len == 0 or v.string.len > attachments_store_fs.MAX_ID_BYTES) return error.invalid_args;
    return try allocator.dupe(u8, v.string);
}

/// Compare a stored Attachment record (slices) against the parsed
/// CreateArgs (also slices).  All fields except created_at must match
/// byte-for-byte for an idempotent recreate.  Mirrors visits_handler's
/// posture.
fn attachmentContentsEqual(stored: attachments_store_fs.Attachment, args: CreateArgs) bool {
    return std.mem.eql(u8, stored.visit_id, args.visit_id) and
        std.mem.eql(u8, stored.kind, args.kind) and
        std.mem.eql(u8, stored.content_hash, args.content_hash) and
        stored.content_size == args.content_size and
        std.mem.eql(u8, stored.mime_type, args.mime_type) and
        std.mem.eql(u8, stored.captured_at, args.captured_at) and
        std.mem.eql(u8, stored.captured_by_cert_id, args.captured_by_cert_id) and
        std.mem.eql(u8, stored.caption, args.caption);
}

// ─────────────────────────────────────────────────────────────────────
// JSON rendering helpers
// ─────────────────────────────────────────────────────────────────────

fn writeAttachmentJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), att: attachments_store_fs.Attachment) !void {
    try out.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, out, att.id);
    try out.appendSlice(allocator, ",\"visit_id\":");
    try writeJsonString(allocator, out, att.visit_id);
    try out.appendSlice(allocator, ",\"kind\":");
    try writeJsonString(allocator, out, att.kind);
    try out.appendSlice(allocator, ",\"content_hash\":");
    try writeJsonString(allocator, out, att.content_hash);
    try out.print(allocator, ",\"content_size\":{d}", .{att.content_size});
    try out.appendSlice(allocator, ",\"mime_type\":");
    try writeJsonString(allocator, out, att.mime_type);
    try out.appendSlice(allocator, ",\"captured_at\":");
    try writeJsonString(allocator, out, att.captured_at);
    try out.appendSlice(allocator, ",\"captured_by_cert_id\":");
    try writeJsonString(allocator, out, att.captured_by_cert_id);
    try out.appendSlice(allocator, ",\"caption\":");
    try writeJsonString(allocator, out, att.caption);
    try out.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, out, att.created_at);
    try out.append(allocator, '}');
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

fn hexEncode(bytes: []const u8, out: []u8) void {
    std.debug.assert(out.len == bytes.len * 2);
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

/// Render a unix timestamp as a minimal ISO-8601 UTC string ("YYYY-
/// MM-DDTHH:MM:SSZ").  Mirrors the same helper in visits_handler.zig.
fn renderIsoTimestamp(allocator: std.mem.Allocator, unix_seconds: i64) ![]u8 {
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(unix_seconds) };
    const epoch_day = epoch_secs.getEpochDay();
    const day_secs = epoch_secs.getDaySeconds();
    const ymd = epoch_day.calculateYearDay();
    const month_day = ymd.calculateMonthDay();
    const year: u32 = ymd.year;
    const month: u8 = month_day.month.numeric();
    const day: u8 = month_day.day_index + 1;
    const hour: u8 = day_secs.getHoursIntoDay();
    const minute: u8 = day_secs.getMinutesIntoHour();
    const second: u8 = day_secs.getSecondsIntoMinute();
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{ year, month, day, hour, minute, second },
    );
}

```
