---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/resources/customers_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.553583+00:00
---

# cartridges/oddjobz/brain/zig/src/resources/customers_handler.zig

```zig
// D-O5.followup-3 — Typed `customers` dispatcher resource.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3, §8;
//            docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5 (helm jobs view —
//            customers slice extends to the helm Customers view).
//
// Dispatcher resource handler that fronts `customers_store_fs.
// CustomersStore`.  Same shape as `jobs_handler.zig` — handler owns the
// live CustomersStore for the dispatcher's lifetime, every transport
// (in-process REPL, Unix socket, HTTP REPL, future mesh peers) goes
// through this one seam.  Closes D-O5.followup-3 (customers slice) by
// giving both helms (`apps/loom-svelte/src/views/CustomerList.svelte`'s
// `parseCustomers` and `apps/oddjobz-mobile/lib/src/repl/customers_
// repository.dart`'s `parseCustomers`) a JSON-shaped response to
// consume.
//
// Commands (per acceptance §2):
//   find         — { name? }             →  [ {id, display_name, phone,
//                                              email, address, created_at},
//                                            ... ]
//                                            cap = cap.oddjobz.read_customers
//                                          NB: list view OMITS notes —
//                                          notes are surfaced by find_by_id
//                                          to keep list payloads compact.
//   create       — { id?, display_name,
//                    phone?, email?,
//                    address?, notes?,
//                    created_at? }       →  { id, status: "created"
//                                                   | "already_exists" }
//                                            cap = cap.oddjobz.write_customer
//   find_by_id   — { id }                →  { id, display_name, phone,
//                                              email, address, notes,
//                                              created_at }
//                                            cap = cap.oddjobz.read_customers
//                                          (or { error: "not_found", id }
//                                           — handler-level NOT a dispatch
//                                           error so transports return 200
//                                           with a typed body, mirroring
//                                           jobs_handler's find_by_id)
//
// Concurrency: a single mutex serialises all handler entry points
// against the live store; same shape as jobs_handler.zig.  Two
// transports issuing simultaneously serialise here and produce well-
// defined ordering on disk.
//
// Audit: every dispatch produces phase=start + phase=end (or an error
// phase) automatically via the dispatcher.  We deliberately do NOT
// turn `audit_reads = false` on for `find` — per the brief, the helm
// reading the customer list IS the audit-relevant event.  Audit volume
// is proportional to operator-driven helm refresh, not machine-driven
// poll, so the noise budget is fine.
//
// Idempotency on create: the underlying store returns
// `AppendOutcome.already_exists` when a duplicate id is written; we
// surface that as `status: "already_exists"` (200, NOT an error) so
// the helm-side outbox flush retry path doesn't get stuck.  Per
// acceptance §3.  ADDITIONAL constraint specific to customers: when
// the same id is re-created with DIFFERENT contents we reject with a
// typed `customer_id_in_use_with_different_contents` error rather than
// silently shadowing.  Jobs accept rewrite-via-replay because the FSM
// state can transition; customer details are lattice-shaped and a
// genuine update should go through a future `customers.update` command.

const std = @import("std");
const dispatcher = @import("dispatcher");
const verb_schema = @import("verb_schema"); // C4 PR-R2b — generic-REPL verb self-description
const customers_store_fs = @import("customers_store_fs");
const helm_event_broker = @import("helm_event_broker");
const audit_log = @import("audit_log");

pub const RESOURCE_NAME = "customers";

/// Capability declarations.
///
/// `cap.oddjobz.read_customers` is the new cap (`0x00010108`) minted in
/// `cartridges/oddjobz/brain/src/capabilities.ts` alongside the existing
/// seven oddjobz caps.  `cap.oddjobz.write_customer` is the existing
/// cap (`0x00010105`) — Customer creation has been a §O3 cap from day
/// one of the oddjobz extension; the new cap is read-only.
pub const CAP_READ_CUSTOMERS: []const u8 = "cap.oddjobz.read_customers";
pub const CAP_WRITE_CUSTOMER: []const u8 = "cap.oddjobz.write_customer";

pub const HandlerError = error{
    /// JSON args parse failed or required arg missing.
    invalid_args,
    /// Underlying CustomersStore validator rejected the input.
    invalid_id,
    invalid_display_name,
    invalid_phone,
    invalid_email,
    invalid_address,
    invalid_notes,
    /// Caller passed an id that already exists in the store but the
    /// other fields disagree with what's on file.  Idempotent recreate
    /// requires byte-identical contents per acceptance §3.
    customer_id_in_use_with_different_contents,
    /// Underlying store I/O failed.
    store_error,
    /// Result-allocation failed.
    out_of_memory,
};

/// State carried alongside the resource registration.  The handler is
/// the sole owner of the CustomersStore for the dispatcher's lifetime;
/// the daemon (or REPL bootstrap) constructs it once at boot and
/// registers the handler via `register`.
pub const Handler = struct {
    allocator: std.mem.Allocator,
    store: *customers_store_fs.CustomersStore,
    /// Serialises find / create / find_by_id against the underlying
    /// store.  The store itself is not thread-safe; this mutex is the
    /// seam between concurrent transport callers.
    mu: std.Thread.Mutex,
    /// D-O5.followup-4 — optional event broker.  When non-null, every
    /// successful `customers.create` publishes `customer.created` to
    /// the broker so live WSS subscribers (the helms) receive a
    /// notification frame.  Mirrors the jobs_handler emit shape from
    /// #318; defensive null-check before publish so pre-existing
    /// init paths that don't pass a broker still work.
    broker: ?*helm_event_broker.Broker,
    /// D-O5.followup-4 — optional audit log shared with the
    /// dispatcher.  When non-null, every `broker.publish` call
    /// records a phase=publish line so the audit trail surfaces the
    /// event-emission alongside the dispatcher's existing start/end
    /// pair.
    audit: ?*audit_log.AuditLog,

    pub fn init(allocator: std.mem.Allocator, store: *customers_store_fs.CustomersStore) Handler {
        return initWithBroker(allocator, store, null, null);
    }

    /// D-O5.followup-4 — broker-aware constructor.  cli.zig
    /// (`cmdRepl` + `cmdServe`) instantiates the shared broker once
    /// and passes it here so customer creates emit live events.
    pub fn initWithBroker(
        allocator: std.mem.Allocator,
        store: *customers_store_fs.CustomersStore,
        broker: ?*helm_event_broker.Broker,
        audit: ?*audit_log.AuditLog,
    ) Handler {
        return .{
            .allocator = allocator,
            .store = store,
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

// C4 PR-R2b — verb self-description for the generic `customers <verb>` REPL path.
const CUSTOMERS_VERBS = [_]verb_schema.VerbSpec{
    .{ .verb = "find", .summary = "list customers (optional name filter)", .args = &.{
        .{ .name = "name", .kind = .string },
    } },
    .{ .verb = "find_by_id", .summary = "fetch one customer by id", .args = &.{
        .{ .name = "id", .kind = .string, .required = true, .positional = true },
    } },
    .{ .verb = "create", .summary = "create a customer", .args = &.{
        .{ .name = "display_name", .kind = .string, .required = true },
        .{ .name = "id", .kind = .string },
        .{ .name = "phone", .kind = .string },
        .{ .name = "email", .kind = .string },
        .{ .name = "address", .kind = .string },
        .{ .name = "notes", .kind = .string },
        .{ .name = "created_at", .kind = .string },
    } },
};
fn verbsFn(_: ?*anyopaque) []const verb_schema.VerbSpec {
    return &CUSTOMERS_VERBS;
}

// ─────────────────────────────────────────────────────────────────────
// Capability declarations
// ─────────────────────────────────────────────────────────────────────

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "find")) return .{ .require = CAP_READ_CUSTOMERS };
    if (std.mem.eql(u8, cmd, "find_by_id")) return .{ .require = CAP_READ_CUSTOMERS };
    if (std.mem.eql(u8, cmd, "create")) return .{ .require = CAP_WRITE_CUSTOMER };
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Dispatch entry point
// ─────────────────────────────────────────────────────────────────────

fn handle(
    state: ?*anyopaque,
    _: *const dispatcher.DispatchContext,
    cmd: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher.Result {
    const self: *Handler = @ptrCast(@alignCast(state.?));
    self.mu.lock();
    defer self.mu.unlock();

    if (std.mem.eql(u8, cmd, "find")) return handleFind(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "create")) return handleCreate(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "find_by_id")) return handleFindById(self, allocator, args_json);
    // Should not be reachable — the dispatcher guards on cap_for_cmd
    // returning unknown_command first.  Defensive return for
    // belt-and-braces.
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Per-command implementations
// ─────────────────────────────────────────────────────────────────────

fn handleFind(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const filter = parseFindArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer if (filter) |f| allocator.free(f);

    const items: []customers_store_fs.Customer = if (filter) |f|
        self.store.findByName(allocator, f) catch return HandlerError.store_error
    else
        self.store.findAll(allocator) catch return HandlerError.store_error;
    defer allocator.free(items);

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.append(allocator, '[');
    for (items, 0..) |row, i| {
        if (i != 0) try buf.append(allocator, ',');
        // List-view payload omits notes (see resource spec) to keep
        // the list response compact.  Use writeCustomerListJson.
        try writeCustomerListJson(allocator, &buf, row);
    }
    try buf.append(allocator, ']');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleCreate(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    var args = parseCreateArgs(allocator, args_json) catch |err| switch (err) {
        // Per-field errors map to typed handler errors so the
        // dispatcher's audit-end carries the kind=handler_err
        // err=<name> tag operators rely on.
        error.invalid_id => return HandlerError.invalid_id,
        error.invalid_display_name => return HandlerError.invalid_display_name,
        error.invalid_phone => return HandlerError.invalid_phone,
        error.invalid_email => return HandlerError.invalid_email,
        error.invalid_address => return HandlerError.invalid_address,
        error.invalid_notes => return HandlerError.invalid_notes,
        error.OutOfMemory => return HandlerError.out_of_memory,
        else => return HandlerError.invalid_args,
    };
    defer args.deinit(allocator);

    // Acceptance §3: when the caller passes an id that already exists,
    // the contents MUST be byte-identical for the request to be
    // idempotent.  Differing contents return a typed validation error
    // instead of silently shadowing the prior record.  Jobs accept
    // rewrite-via-replay because the FSM state can transition;
    // customer fields are lattice-shaped and a genuine update should
    // go through a future `customers.update` command.
    if (self.store.findById(args.id)) |existing| {
        if (!customerContentsEqual(existing, args)) {
            return HandlerError.customer_id_in_use_with_different_contents;
        }
    }

    const customer = customers_store_fs.Customer{
        .id = args.id,
        .display_name = args.display_name,
        .phone = args.phone,
        .email = args.email,
        .address = args.address,
        .notes = args.notes,
        .created_at = args.created_at,
    };

    const outcome = self.store.append(customer) catch |err| switch (err) {
        customers_store_fs.StoreError.invalid_id => return HandlerError.invalid_id,
        customers_store_fs.StoreError.invalid_display_name => return HandlerError.invalid_display_name,
        customers_store_fs.StoreError.invalid_phone => return HandlerError.invalid_phone,
        customers_store_fs.StoreError.invalid_email => return HandlerError.invalid_email,
        customers_store_fs.StoreError.invalid_address => return HandlerError.invalid_address,
        customers_store_fs.StoreError.invalid_notes => return HandlerError.invalid_notes,
        else => return HandlerError.store_error,
    };

    // D-O5.followup-4 — emit `customer.created` to the broker so live
    // WSS subscribers (helms) update in real time.  Only emit on a
    // genuine new write — the idempotent `.already_exists` outcome did
    // not change anything observable.  Best-effort: a payload-encode
    // failure or a callback that crashes does NOT fail the create
    // (the event is decorative; the store write already landed).
    if (outcome == .created) {
        emitCustomerCreated(self, args.id, args.display_name, args.created_at) catch {};
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

/// D-O5.followup-4 — publish a `customer.created` event to the
/// process-scoped broker (when wired).  Mirrors the
/// `emitJobTransitioned` pattern in jobs_handler.zig: payload is a
/// JSON object with the canonical {id, display_name, created_at}
/// shape; audit pair preserved when an audit log is wired.  Best-
/// effort: failure to allocate the payload buffer is silently
/// swallowed.
fn emitCustomerCreated(
    self: *Handler,
    id: []const u8,
    display_name: []const u8,
    created_at: []const u8,
) !void {
    const broker = self.broker orelse return;
    const allocator = self.allocator;

    var payload: std.ArrayList(u8) = .{};
    defer payload.deinit(allocator);
    try payload.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, &payload, id);
    try payload.appendSlice(allocator, ",\"display_name\":");
    try writeJsonString(allocator, &payload, display_name);
    try payload.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, &payload, created_at);
    try payload.append(allocator, '}');

    broker.publish(.{
        .type = "customer.created",
        .payload_json = payload.items,
    });

    if (self.audit) |a| {
        a.record(allocator, .{
            .module = "helm.broker",
            .op = "publish",
            .result = .ok,
            .detail = "customer.created",
        }) catch {};
    }
}

fn handleFindById(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const id = parseFindByIdArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(id);

    const got = self.store.findById(id) orelse {
        // Handler-level not_found — return a typed body, NOT an error,
        // so transports return 200 with the same JSON envelope every
        // helm parser can handle.  Mirrors `jobs_handler.find_by_id`'s
        // shape.
        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try buf.appendSlice(allocator, "{\"error\":\"not_found\",\"id\":");
        try writeJsonString(allocator, &buf, id);
        try buf.append(allocator, '}');
        return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
    };

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    // Detail view INCLUDES notes (unlike the list view).
    try writeCustomerDetailJson(allocator, &buf, got);
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// Args parsing — small JSON walks; never trust the caller's payload.
// Each parser allocates owned copies of every string field so the
// per-command implementations can hold them across the underlying
// store call without lifetime entanglement with the parsed JSON DOM.
// ─────────────────────────────────────────────────────────────────────

const CreateArgs = struct {
    id: []u8,
    display_name: []u8,
    phone: []u8,
    email: []u8,
    address: []u8,
    notes: []u8,
    created_at: []u8,

    pub fn deinit(self: *CreateArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.display_name);
        allocator.free(self.phone);
        allocator.free(self.email);
        allocator.free(self.address);
        allocator.free(self.notes);
        allocator.free(self.created_at);
    }
};

const ParseError = error{
    invalid_args,
    invalid_id,
    invalid_display_name,
    invalid_phone,
    invalid_email,
    invalid_address,
    invalid_notes,
    out_of_memory,
    /// std.mem.Allocator's documented OOM signal — keep alongside our
    /// snake-cased `out_of_memory` so allocator-returning calls inside
    /// `parseCreateArgs` can `try` directly without a switch translation.
    OutOfMemory,
};

/// `find` accepts an optional `{name: "..."}` filter.  Returns null
/// when no filter is present (caller treats that as "all customers");
/// the allocator owns the returned slice when non-null.
fn parseFindArgs(allocator: std.mem.Allocator, args_json: []const u8) !?[]u8 {
    // Empty body is permitted (REPL command with no args).
    if (args_json.len == 0) return null;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const obj = parsed.value.object;
    const v = obj.get("name") orelse return null;
    if (v != .string) return null;
    if (v.string.len == 0) return null;
    return try allocator.dupe(u8, v.string);
}

fn parseCreateArgs(allocator: std.mem.Allocator, args_json: []const u8) ParseError!CreateArgs {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return error.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    // display_name (required, non-empty, ≤ 200).
    const dn_v = obj.get("display_name") orelse return error.invalid_display_name;
    if (dn_v != .string) return error.invalid_display_name;
    if (dn_v.string.len == 0 or dn_v.string.len > customers_store_fs.MAX_DISPLAY_NAME_BYTES) return error.invalid_display_name;

    // id (optional — server-stamped when empty).
    const id_str: []const u8 = blk: {
        if (obj.get("id")) |v| {
            if (v != .string) return error.invalid_id;
            if (v.string.len > customers_store_fs.MAX_ID_BYTES) return error.invalid_id;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };

    // phone (optional, ≤ 50; no format validation).
    const ph_v: []const u8 = blk: {
        if (obj.get("phone")) |v| {
            if (v != .string) return error.invalid_phone;
            if (v.string.len > customers_store_fs.MAX_PHONE_BYTES) return error.invalid_phone;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // email (optional, ≤ 200; no format validation).
    const em_v: []const u8 = blk: {
        if (obj.get("email")) |v| {
            if (v != .string) return error.invalid_email;
            if (v.string.len > customers_store_fs.MAX_EMAIL_BYTES) return error.invalid_email;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // address (optional, ≤ 500).
    const ad_v: []const u8 = blk: {
        if (obj.get("address")) |v| {
            if (v != .string) return error.invalid_address;
            if (v.string.len > customers_store_fs.MAX_ADDRESS_BYTES) return error.invalid_address;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // notes (optional, ≤ 2000).
    const no_v: []const u8 = blk: {
        if (obj.get("notes")) |v| {
            if (v != .string) return error.invalid_notes;
            if (v.string.len > customers_store_fs.MAX_NOTES_BYTES) return error.invalid_notes;
            break :blk v.string;
        }
        break :blk &.{};
    };

    // created_at (optional; server-stamps as ISO timestamp when empty).
    const ca_v: []const u8 = blk: {
        if (obj.get("created_at")) |v| {
            if (v != .string) return error.invalid_args;
            if (v.string.len > customers_store_fs.MAX_CREATED_AT_BYTES) return error.invalid_args;
            if (v.string.len > 0) break :blk v.string;
        }
        break :blk &.{};
    };

    // Allocate the owned copies.
    var id_owned: []u8 = undefined;
    if (id_str.len == 0) {
        // Server-mint a UUIDv4-shaped id (32 hex chars) with crypto-
        // random bytes — same pattern jobs_handler.zig uses.
        var id_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&id_bytes);
        const id_alloc = try allocator.alloc(u8, 32);
        hexEncode(&id_bytes, id_alloc);
        id_owned = id_alloc;
    } else {
        id_owned = try allocator.dupe(u8, id_str);
    }
    errdefer allocator.free(id_owned);

    const dn_owned = try allocator.dupe(u8, dn_v.string);
    errdefer allocator.free(dn_owned);
    const ph_owned = try allocator.dupe(u8, ph_v);
    errdefer allocator.free(ph_owned);
    const em_owned = try allocator.dupe(u8, em_v);
    errdefer allocator.free(em_owned);
    const ad_owned = try allocator.dupe(u8, ad_v);
    errdefer allocator.free(ad_owned);
    const no_owned = try allocator.dupe(u8, no_v);
    errdefer allocator.free(no_owned);

    // Server-stamp created_at when not supplied.  We render the wall
    // clock as an ISO-8601 string with second precision so audit-log
    // grep aligns with helm-rendered timestamps.
    var ca_owned: []u8 = undefined;
    if (ca_v.len == 0) {
        ca_owned = try renderIsoTimestamp(allocator, std.time.timestamp());
    } else {
        ca_owned = try allocator.dupe(u8, ca_v);
    }
    errdefer allocator.free(ca_owned);

    return .{
        .id = id_owned,
        .display_name = dn_owned,
        .phone = ph_owned,
        .email = em_owned,
        .address = ad_owned,
        .notes = no_owned,
        .created_at = ca_owned,
    };
}

fn parseFindByIdArgs(allocator: std.mem.Allocator, args_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const v = obj.get("id") orelse return error.invalid_args;
    if (v != .string) return error.invalid_args;
    if (v.string.len == 0 or v.string.len > customers_store_fs.MAX_ID_BYTES) return error.invalid_args;
    return try allocator.dupe(u8, v.string);
}

/// Compare a stored Customer record (slices) against the parsed
/// CreateArgs (also slices).  All seven fields must match byte-for-
/// byte for an idempotent recreate.  created_at is included: a re-
/// create that omits created_at will server-stamp a fresh timestamp,
/// which intentionally trips this check (the operator should supply a
/// pinned created_at if they want idempotent retry-on-network-flake).
fn customerContentsEqual(stored: customers_store_fs.Customer, args: CreateArgs) bool {
    return std.mem.eql(u8, stored.display_name, args.display_name) and
        std.mem.eql(u8, stored.phone, args.phone) and
        std.mem.eql(u8, stored.email, args.email) and
        std.mem.eql(u8, stored.address, args.address) and
        std.mem.eql(u8, stored.notes, args.notes) and
        std.mem.eql(u8, stored.created_at, args.created_at);
}

// ─────────────────────────────────────────────────────────────────────
// JSON rendering helpers
// ─────────────────────────────────────────────────────────────────────

/// List-view payload — omits notes to keep the response compact.  Used
/// by `customers.find`.
fn writeCustomerListJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), customer: customers_store_fs.Customer) !void {
    try out.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, out, customer.id);
    try out.appendSlice(allocator, ",\"display_name\":");
    try writeJsonString(allocator, out, customer.display_name);
    try out.appendSlice(allocator, ",\"phone\":");
    try writeJsonString(allocator, out, customer.phone);
    try out.appendSlice(allocator, ",\"email\":");
    try writeJsonString(allocator, out, customer.email);
    try out.appendSlice(allocator, ",\"address\":");
    try writeJsonString(allocator, out, customer.address);
    try out.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, out, customer.created_at);
    try out.append(allocator, '}');
}

/// Detail-view payload — includes notes.  Used by `customers.find_by_id`.
fn writeCustomerDetailJson(allocator: std.mem.Allocator, out: *std.ArrayList(u8), customer: customers_store_fs.Customer) !void {
    try out.appendSlice(allocator, "{\"id\":");
    try writeJsonString(allocator, out, customer.id);
    try out.appendSlice(allocator, ",\"display_name\":");
    try writeJsonString(allocator, out, customer.display_name);
    try out.appendSlice(allocator, ",\"phone\":");
    try writeJsonString(allocator, out, customer.phone);
    try out.appendSlice(allocator, ",\"email\":");
    try writeJsonString(allocator, out, customer.email);
    try out.appendSlice(allocator, ",\"address\":");
    try writeJsonString(allocator, out, customer.address);
    try out.appendSlice(allocator, ",\"notes\":");
    try writeJsonString(allocator, out, customer.notes);
    try out.appendSlice(allocator, ",\"created_at\":");
    try writeJsonString(allocator, out, customer.created_at);
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
/// MM-DDTHH:MM:SSZ").  Used to server-stamp `created_at` when the
/// caller omits it.  std.time doesn't ship a calendar formatter, so we
/// roll a tiny one — same shape as `jobs_handler.zig::renderIsoTimestamp`.
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
