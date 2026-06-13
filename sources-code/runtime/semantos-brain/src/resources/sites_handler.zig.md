---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/resources/sites_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.294210+00:00
---

# runtime/semantos-brain/src/resources/sites_handler.zig

```zig
// Phase D-W1 / Phase 2 — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md
// §3 (the `sites` row) and §8 Phase 2.
//
// Dispatcher resource handler that fronts the existing
// `site_config.zig` parser/validator + the on-disk sites tree at
// `<sites_dir>/<domain>/site.json`.  This is the seam the migration
// picks up from `cmdSite*` in `cli.zig`: every transport (in-process
// REPL, Unix socket CLI-RPC, helm SPA over HTTP, future SignedBundle
// mesh peer) reaches site config through `dispatcher.dispatch(sites,
// <cmd>, ...)` rather than via direct disk I/O at the CLI's address
// space.
//
// Same architectural shape as `bearer_tokens_handler.zig` and
// `identity_certs_handler.zig` (the canonical precedents):
//
//   • Single owner of the sites_dir for this dispatcher's lifetime
//     (the handler instance constructed by `cmdServe` / the embedded-
//     mode CLI fallback / the test fixture).
//   • Mutex-serialised: every entry point locks `mu` for the duration
//     of the disk mutation.  Concurrent issuers are serialised within
//     ONE brain process; cross-process serialisation is left as the
//     same TODO bearer_tokens_handler carries (flock(2) on the parent
//     dir if a real concurrency case ever appears).
//   • Capability gating: `init`, `route_add`, `route_remove`,
//     `set_listen_port`, `list`, `get_config` all require
//     `cap.brain.admin`.  `validate` declares `.none` — anyone with a
//     dispatch context can self-validate (stateless read).
//
// Commands (per the §3 row):
//
//   init           — { domain }
//                    Scaffold `<sites_dir>/<domain>/{site.json,
//                    public/index.html}` from the default template.
//                    Idempotent on missing dir; fails with
//                    duplicate_resource if site.json already exists.
//                    cap = cap.brain.admin
//
//   route_add      — { domain, path, type, file?, handler?,
//                       handler_sha256?, auth?, price_sats? }
//                    Edit `<sites_dir>/<domain>/site.json` to add a
//                    new route entry.  Re-validates the parsed config
//                    after edit; rolls back on validation failure.
//                    cap = cap.brain.admin
//
//   route_remove   — { domain, path }
//                    Drop the route at `path`.  Idempotent on absent
//                    routes (returns `removed:false`).
//                    cap = cap.brain.admin
//
//   set_listen_port — { domain, port }
//                    Update `site.listen_port`.  Validates 1–65535.
//                    cap = cap.brain.admin
//
//   list           — {}
//                    Enumerate `<sites_dir>/*` directory entries.
//                    Returns `{sites: ["domain1", "domain2", ...]}`.
//                    cap = cap.brain.admin
//
//   get_config     — { domain }
//                    Parse + return a JSON view of the site config
//                    (domain, content_root, listen_port, routes,
//                    session_ttl_seconds).  Sensitive fields
//                    (signing_secret, signing_key_wif) are NOT
//                    included in the wire representation — they
//                    stay on disk only.
//                    cap = cap.brain.admin
//
//   validate       — { domain }
//                    Load site.json, run `site_config.validate`,
//                    return `{problems: [{severity, message}, ...]}`.
//                    cap = .none
//
// Audit semantics: `init`, `route_add`, `route_remove`,
// `set_listen_port` are mutating and always emit the dispatcher's
// audit pair (begin + complete).  `list`, `get_config`, `validate`
// are read-typed and skip the audit pair when the dispatcher
// registration sets `audit_reads=false` (see BRAIN-DISPATCHER-
// UNIFICATION.md §10 — the high-frequency-read mitigation).
//
// Serialisation note on JSON edits: `site.json` is written
// straight from a `std.json.Stringify` walk over a dynamic value
// tree — we re-encode the entire document on each mutation rather
// than splice into the source.  For v0.1 sites (one or two routes
// per file) this is fine; if schema-preserving edits become a
// requirement (operator hand-edits with comments), the handler
// can switch to a position-preserving editor in a follow-up.

const std = @import("std");
const dispatcher = @import("dispatcher");
const site_config = @import("site_config");

pub const RESOURCE_NAME = "sites";

pub const HandlerError = error{
    /// JSON args parse failed or required arg missing.
    invalid_args,
    /// Underlying disk I/O failed (permission, ENOSPC, …).
    store_error,
    /// `site.json` not found for the named domain.
    not_found,
    /// `init` of an already-existing domain.
    duplicate_resource,
    /// `route_add` with a path that's already declared.
    duplicate_route,
    /// `set_listen_port` got a port outside 1–65535, or `route_add`
    /// got a route shape that doesn't pass `site_config.validate`.
    validation_failed,
    /// Result-allocation failed.
    out_of_memory,
};

/// State the handler carries.  The dispatcher hands `state` to every
/// callback as `*anyopaque`; we cast it back to `*Handler`.
pub const Handler = struct {
    allocator: std.mem.Allocator,
    /// The root directory under which `<domain>/site.json` lives.
    /// Borrowed; the caller (cmdServe / CLI embedded-mode / tests)
    /// owns the underlying memory.
    sites_dir: []const u8,
    /// Serialises every disk mutation against this handler's
    /// `sites_dir`.  Mirrors bearer_tokens_handler's threading model.
    mu: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, sites_dir: []const u8) Handler {
        return .{
            .allocator = allocator,
            .sites_dir = sites_dir,
            .mu = .{},
        };
    }

    pub fn resourceHandler(self: *Handler) dispatcher.ResourceHandler {
        return .{
            .name = RESOURCE_NAME,
            .state = self,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handle,
            .audit_reads = false,
            .is_read_fn = isRead,
        };
    }
};

// ─────────────────────────────────────────────────────────────────────
// Capability declarations
// ─────────────────────────────────────────────────────────────────────

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "init")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "route_add")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "route_remove")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "set_listen_port")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "list")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "get_config")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "validate")) return .none;
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Read classifier — used by the dispatcher's audit_reads opt-out.
// ─────────────────────────────────────────────────────────────────────

/// Per BRAIN-DISPATCHER-UNIFICATION.md §10: explicit per-cmd flag rather
/// than implicit-from-cap.  `list`, `get_config`, `validate` are reads;
/// the rest mutate and audit unconditionally.  Note: this is a static
/// classification consulted by the dispatcher's `recordAudit` path; the
/// handler-level `Handler.resourceHandler.audit_reads = false` toggle
/// turns the opt-out on.
pub fn isRead(cmd: []const u8) bool {
    if (std.mem.eql(u8, cmd, "list")) return true;
    if (std.mem.eql(u8, cmd, "get_config")) return true;
    if (std.mem.eql(u8, cmd, "validate")) return true;
    return false;
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

    if (std.mem.eql(u8, cmd, "init")) return handleInit(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "route_add")) return handleRouteAdd(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "route_remove")) return handleRouteRemove(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "set_listen_port")) return handleSetListenPort(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "list")) return handleList(self, allocator);
    if (std.mem.eql(u8, cmd, "get_config")) return handleGetConfig(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "validate")) return handleValidate(self, allocator, args_json);
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Per-command implementations
// ─────────────────────────────────────────────────────────────────────

fn handleInit(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const domain = parseDomainArg(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(domain);

    if (!isValidDomainShape(domain)) return HandlerError.invalid_args;

    const site_dir = try std.fs.path.join(allocator, &.{ self.sites_dir, domain });
    defer allocator.free(site_dir);
    const site_json = try std.fs.path.join(allocator, &.{ site_dir, "site.json" });
    defer allocator.free(site_json);
    const public_dir = try std.fs.path.join(allocator, &.{ site_dir, "public" });
    defer allocator.free(public_dir);
    const index_html = try std.fs.path.join(allocator, &.{ public_dir, "index.html" });
    defer allocator.free(index_html);

    if (std.fs.cwd().openFile(site_json, .{})) |f| {
        f.close();
        return HandlerError.duplicate_resource;
    } else |_| {}

    std.fs.cwd().makePath(public_dir) catch return HandlerError.store_error;

    const tmpl = site_config.defaultJsonTemplate(allocator, domain) catch return HandlerError.store_error;
    defer allocator.free(tmpl);
    {
        const f = std.fs.cwd().createFile(site_json, .{}) catch return HandlerError.store_error;
        defer f.close();
        f.writeAll(tmpl) catch return HandlerError.store_error;
    }

    const placeholder = std.fmt.allocPrint(allocator,
        "<!doctype html>\n<title>{s}</title>\n<h1>Hello from {s}</h1>\n<p>Edit {s} to customise.</p>\n",
        .{ domain, domain, index_html }) catch return HandlerError.out_of_memory;
    defer allocator.free(placeholder);
    {
        const f = std.fs.cwd().createFile(index_html, .{}) catch return HandlerError.store_error;
        defer f.close();
        f.writeAll(placeholder) catch return HandlerError.store_error;
    }

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.print(allocator, "{{\"domain\":", .{});
    try writeJsonString(allocator, &buf, domain);
    try buf.print(allocator, ",\"site_json\":", .{});
    try writeJsonString(allocator, &buf, site_json);
    try buf.print(allocator, ",\"content_root\":", .{});
    try writeJsonString(allocator, &buf, public_dir);
    try buf.appendSlice(allocator, "}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

const RouteAddArgs = struct {
    domain: []u8,
    path: []u8,
    kind: []u8, // "static" | "dynamic"
    file: ?[]u8,
    handler: ?[]u8,
    handler_sha256: ?[]u8,
    auth: ?[]u8,
    price_sats: ?u64,

    fn deinit(self: RouteAddArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.domain);
        allocator.free(self.path);
        allocator.free(self.kind);
        if (self.file) |s| allocator.free(s);
        if (self.handler) |s| allocator.free(s);
        if (self.handler_sha256) |s| allocator.free(s);
        if (self.auth) |s| allocator.free(s);
    }
};

fn parseRouteAddArgs(allocator: std.mem.Allocator, args_json: []const u8) !RouteAddArgs {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    const domain_v = obj.get("domain") orelse return error.invalid_args;
    if (domain_v != .string) return error.invalid_args;
    const domain = try allocator.dupe(u8, domain_v.string);
    errdefer allocator.free(domain);

    const path_v = obj.get("path") orelse return error.invalid_args;
    if (path_v != .string) return error.invalid_args;
    const path = try allocator.dupe(u8, path_v.string);
    errdefer allocator.free(path);

    const kind_v = obj.get("type") orelse return error.invalid_args;
    if (kind_v != .string) return error.invalid_args;
    if (!std.mem.eql(u8, kind_v.string, "static") and !std.mem.eql(u8, kind_v.string, "dynamic")) {
        return error.invalid_args;
    }
    const kind = try allocator.dupe(u8, kind_v.string);
    errdefer allocator.free(kind);

    var file: ?[]u8 = null;
    errdefer if (file) |s| allocator.free(s);
    if (obj.get("file")) |v| {
        if (v != .string) return error.invalid_args;
        file = try allocator.dupe(u8, v.string);
    }
    var handler: ?[]u8 = null;
    errdefer if (handler) |s| allocator.free(s);
    if (obj.get("handler")) |v| {
        if (v != .string) return error.invalid_args;
        handler = try allocator.dupe(u8, v.string);
    }
    var handler_sha256: ?[]u8 = null;
    errdefer if (handler_sha256) |s| allocator.free(s);
    if (obj.get("handler_sha256")) |v| {
        if (v != .string) return error.invalid_args;
        if (v.string.len != 64) return error.invalid_args;
        handler_sha256 = try allocator.dupe(u8, v.string);
    }
    var auth: ?[]u8 = null;
    errdefer if (auth) |s| allocator.free(s);
    if (obj.get("auth")) |v| {
        if (v != .string) return error.invalid_args;
        auth = try allocator.dupe(u8, v.string);
    }
    var price_sats: ?u64 = null;
    if (obj.get("price_sats")) |v| {
        if (v != .integer or v.integer < 0) return error.invalid_args;
        price_sats = @intCast(v.integer);
    }

    return .{
        .domain = domain,
        .path = path,
        .kind = kind,
        .file = file,
        .handler = handler,
        .handler_sha256 = handler_sha256,
        .auth = auth,
        .price_sats = price_sats,
    };
}

fn handleRouteAdd(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const args = parseRouteAddArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer args.deinit(allocator);

    if (!isValidDomainShape(args.domain)) return HandlerError.invalid_args;

    // Static routes need `file`; dynamic routes need `handler` +
    // `handler_sha256`.  Surface up-front rather than letting the
    // post-edit re-parse fail.
    if (std.mem.eql(u8, args.kind, "static")) {
        if (args.file == null) return HandlerError.validation_failed;
    } else {
        if (args.handler == null or args.handler_sha256 == null) return HandlerError.validation_failed;
    }

    const site_json = try siteJsonPath(allocator, self.sites_dir, args.domain);
    defer allocator.free(site_json);

    var doc = loadSiteJsonValue(allocator, site_json) catch |err| switch (err) {
        error.FileNotFound => return HandlerError.not_found,
        else => return HandlerError.store_error,
    };
    defer doc.deinit();

    if (doc.value != .object) return HandlerError.store_error;
    const root = &doc.value.object;

    var routes_obj = blk: {
        if (root.get("routes")) |v| {
            if (v != .object) return HandlerError.store_error;
            break :blk v.object;
        }
        const empty = std.json.Value{ .object = std.json.ObjectMap.init(doc.arena.allocator()) };
        try root.put("routes", empty);
        break :blk root.get("routes").?.object;
    };
    if (routes_obj.contains(args.path)) return HandlerError.duplicate_route;

    var entry = std.json.ObjectMap.init(doc.arena.allocator());
    try entry.put("type", .{ .string = try doc.arena.allocator().dupe(u8, args.kind) });
    if (args.file) |f| try entry.put("file", .{ .string = try doc.arena.allocator().dupe(u8, f) });
    if (args.handler) |h| try entry.put("handler", .{ .string = try doc.arena.allocator().dupe(u8, h) });
    if (args.handler_sha256) |h| try entry.put("handler_sha256", .{ .string = try doc.arena.allocator().dupe(u8, h) });
    if (args.auth) |a| try entry.put("auth", .{ .string = try doc.arena.allocator().dupe(u8, a) });
    if (args.price_sats) |p| try entry.put("price_sats", .{ .integer = @intCast(p) });

    try routes_obj.put(try doc.arena.allocator().dupe(u8, args.path), .{ .object = entry });
    // The local `routes_obj` is a value-copy of the inner ObjectMap.
    // `put` mutates the local copy; we must write it back into root.
    try root.put("routes", .{ .object = routes_obj });

    // Re-encode to JSON + validate via `site_config.parseJson` before
    // committing.  Roll back on shape failure (we just don't write).
    const new_json = try stringifyValue(allocator, doc.value);
    defer allocator.free(new_json);
    var cfg = site_config.parseJson(allocator, new_json) catch return HandlerError.validation_failed;
    cfg.deinit();

    try writeFileAtomic(site_json, new_json);

    const payload = try std.fmt.allocPrint(allocator, "{{\"ok\":true,\"path\":\"{s}\"}}", .{args.path});
    return dispatcher.Result.ownedPayload(allocator, payload);
}

const RouteRemoveArgs = struct {
    domain: []u8,
    path: []u8,

    fn deinit(self: RouteRemoveArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.domain);
        allocator.free(self.path);
    }
};

fn parseRouteRemoveArgs(allocator: std.mem.Allocator, args_json: []const u8) !RouteRemoveArgs {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const domain_v = obj.get("domain") orelse return error.invalid_args;
    const path_v = obj.get("path") orelse return error.invalid_args;
    if (domain_v != .string or path_v != .string) return error.invalid_args;
    return .{
        .domain = try allocator.dupe(u8, domain_v.string),
        .path = try allocator.dupe(u8, path_v.string),
    };
}

fn handleRouteRemove(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const args = parseRouteRemoveArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer args.deinit(allocator);

    if (!isValidDomainShape(args.domain)) return HandlerError.invalid_args;

    const site_json = try siteJsonPath(allocator, self.sites_dir, args.domain);
    defer allocator.free(site_json);

    var doc = loadSiteJsonValue(allocator, site_json) catch |err| switch (err) {
        error.FileNotFound => return HandlerError.not_found,
        else => return HandlerError.store_error,
    };
    defer doc.deinit();

    if (doc.value != .object) return HandlerError.store_error;
    const root = &doc.value.object;

    const removed = blk: {
        if (root.get("routes")) |v| {
            if (v != .object) return HandlerError.store_error;
            var routes_obj = v.object;
            const removed = routes_obj.swapRemove(args.path);
            try root.put("routes", .{ .object = routes_obj });
            break :blk removed;
        }
        break :blk false;
    };

    if (removed) {
        const new_json = try stringifyValue(allocator, doc.value);
        defer allocator.free(new_json);
        try writeFileAtomic(site_json, new_json);
    }

    const payload = try std.fmt.allocPrint(allocator, "{{\"removed\":{s}}}", .{if (removed) "true" else "false"});
    return dispatcher.Result.ownedPayload(allocator, payload);
}

const SetPortArgs = struct {
    domain: []u8,
    port: u16,

    fn deinit(self: SetPortArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.domain);
    }
};

fn parseSetPortArgs(allocator: std.mem.Allocator, args_json: []const u8) !SetPortArgs {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const domain_v = obj.get("domain") orelse return error.invalid_args;
    const port_v = obj.get("port") orelse return error.invalid_args;
    if (domain_v != .string) return error.invalid_args;
    if (port_v != .integer) return error.invalid_args;
    if (port_v.integer < 1 or port_v.integer > 65535) return error.invalid_args;
    return .{
        .domain = try allocator.dupe(u8, domain_v.string),
        .port = @intCast(port_v.integer),
    };
}

fn handleSetListenPort(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const args = parseSetPortArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer args.deinit(allocator);

    if (!isValidDomainShape(args.domain)) return HandlerError.invalid_args;

    const site_json = try siteJsonPath(allocator, self.sites_dir, args.domain);
    defer allocator.free(site_json);

    var doc = loadSiteJsonValue(allocator, site_json) catch |err| switch (err) {
        error.FileNotFound => return HandlerError.not_found,
        else => return HandlerError.store_error,
    };
    defer doc.deinit();

    if (doc.value != .object) return HandlerError.store_error;
    const root = &doc.value.object;
    const site_v = root.get("site") orelse return HandlerError.store_error;
    if (site_v != .object) return HandlerError.store_error;
    var site_obj = site_v.object;
    try site_obj.put("listen_port", .{ .integer = @intCast(args.port) });
    try root.put("site", .{ .object = site_obj });

    const new_json = try stringifyValue(allocator, doc.value);
    defer allocator.free(new_json);

    // Re-validate to make sure the edit didn't break the schema.
    var cfg = site_config.parseJson(allocator, new_json) catch return HandlerError.validation_failed;
    cfg.deinit();

    try writeFileAtomic(site_json, new_json);

    const payload = try std.fmt.allocPrint(allocator, "{{\"ok\":true,\"port\":{d}}}", .{args.port});
    return dispatcher.Result.ownedPayload(allocator, payload);
}

fn handleList(self: *Handler, allocator: std.mem.Allocator) !dispatcher.Result {
    var d = std.fs.cwd().openDir(self.sites_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            const payload = try allocator.dupe(u8, "{\"sites\":[]}");
            return dispatcher.Result.ownedPayload(allocator, payload);
        },
        else => return HandlerError.store_error,
    };
    defer d.close();

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"sites\":[");
    var any = false;
    var it = d.iterate();
    while (true) {
        const entry = it.next() catch return HandlerError.store_error;
        if (entry == null) break;
        const e = entry.?;
        if (e.kind != .directory) continue;
        if (any) try buf.append(allocator, ',');
        try writeJsonString(allocator, &buf, e.name);
        any = true;
    }
    try buf.appendSlice(allocator, "]}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleGetConfig(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const domain = parseDomainArg(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(domain);

    if (!isValidDomainShape(domain)) return HandlerError.invalid_args;

    const site_json = try siteJsonPath(allocator, self.sites_dir, domain);
    defer allocator.free(site_json);

    var cfg = site_config.loadFromPath(allocator, site_json) catch |err| switch (err) {
        error.FileNotFound => return HandlerError.not_found,
        else => return HandlerError.store_error,
    };
    defer cfg.deinit();

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"domain\":");
    try writeJsonString(allocator, &buf, cfg.domain);
    try buf.appendSlice(allocator, ",\"content_root\":");
    try writeJsonString(allocator, &buf, cfg.content_root);
    try buf.print(allocator, ",\"listen_port\":{d},\"session_ttl_seconds\":{d},\"routes\":[", .{
        cfg.listen_port,
        cfg.session_ttl_seconds,
    });
    for (cfg.routes, 0..) |r, i| {
        if (i != 0) try buf.append(allocator, ',');
        try buf.appendSlice(allocator, "{\"path\":");
        try writeJsonString(allocator, &buf, r.path);
        try buf.appendSlice(allocator, ",\"type\":");
        try writeJsonString(allocator, &buf, switch (r.kind) {
            .static => "static",
            .dynamic => "dynamic",
            // D-O6a — chat routes are brain-native; SiteConfig
            // serialises them with no `file` / `handler` field.
            .chat => "chat",
            // D-O5 / brain issue #274 — directory routes serve a static
            // tree (e.g. the helm SPA) with SPA-fallback for deep links.
            .directory => "directory",
            // D-O7 — intake routes spawn a Bun subprocess per request.
            .intake => "intake",
            // S10a — operator profile-driven site renderer.
            .operator_home => "operator_home",
        });
        if (r.kind == .static) {
            try buf.appendSlice(allocator, ",\"file\":");
            try writeJsonString(allocator, &buf, r.file);
        } else {
            try buf.appendSlice(allocator, ",\"handler\":");
            try writeJsonString(allocator, &buf, r.handler);
        }
        try buf.appendSlice(allocator, ",\"auth\":");
        try writeJsonString(allocator, &buf, r.auth.label());
        try buf.print(allocator, ",\"price_sats\":{d}}}", .{r.price_sats});
    }
    try buf.appendSlice(allocator, "]}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleValidate(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const domain = parseDomainArg(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(domain);

    if (!isValidDomainShape(domain)) return HandlerError.invalid_args;

    const site_json = try siteJsonPath(allocator, self.sites_dir, domain);
    defer allocator.free(site_json);

    var cfg = site_config.loadFromPath(allocator, site_json) catch |err| switch (err) {
        error.FileNotFound => return HandlerError.not_found,
        else => return HandlerError.validation_failed,
    };
    defer cfg.deinit();

    // Run validate from inside the site dir so relative content_root
    // resolves against `<sites_dir>/<domain>/<content_root>`, mirroring
    // the legacy CLI behaviour.
    const site_dir = std.fs.path.dirname(site_json) orelse ".";
    const original_cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(original_cwd);
    var dir_handle = std.fs.cwd().openDir(site_dir, .{}) catch null;
    if (dir_handle) |*h| {
        h.setAsCwd() catch {};
    }
    var report = site_config.validate(allocator, &cfg) catch return HandlerError.store_error;
    defer report.deinit();
    if (dir_handle != null) {
        var orig = std.fs.cwd().openDir(original_cwd, .{}) catch null;
        if (orig) |*h| h.setAsCwd() catch {};
    }

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.print(allocator, "{{\"err_count\":{d},\"problems\":[", .{report.errCount()});
    for (report.problems.items, 0..) |p, i| {
        if (i != 0) try buf.append(allocator, ',');
        const sev: []const u8 = switch (p.severity) {
            .err => "err",
            .warn => "warn",
        };
        try buf.appendSlice(allocator, "{\"severity\":");
        try writeJsonString(allocator, &buf, sev);
        try buf.appendSlice(allocator, ",\"message\":");
        try writeJsonString(allocator, &buf, p.message);
        try buf.append(allocator, '}');
    }
    try buf.appendSlice(allocator, "]}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

/// Refuse path-traversal / weird characters in `domain`.  Domains are
/// directory names under `sites_dir` so we want a tight allowlist.
fn isValidDomainShape(domain: []const u8) bool {
    if (domain.len == 0 or domain.len > 253) return false;
    for (domain) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or c == '.' or c == '-' or c == '_';
        if (!ok) return false;
    }
    if (domain[0] == '.' or domain[0] == '-') return false;
    return true;
}

fn siteJsonPath(allocator: std.mem.Allocator, sites_dir: []const u8, domain: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ sites_dir, domain, "site.json" });
}

fn parseDomainArg(allocator: std.mem.Allocator, args_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const v = obj.get("domain") orelse return error.invalid_args;
    if (v != .string) return error.invalid_args;
    return try allocator.dupe(u8, v.string);
}

const LoadedDoc = struct {
    /// Heap-allocated so `arena.allocator()` captures a stable
    /// pointer.  Returning a `LoadedDoc` by value would move the
    /// arena and dangle every Value-internal allocation that
    /// captured `&arena.state`.
    arena: *std.heap.ArenaAllocator,
    value: std.json.Value,
    parent_allocator: std.mem.Allocator,

    fn deinit(self: *LoadedDoc) void {
        self.arena.deinit();
        self.parent_allocator.destroy(self.arena);
    }

    /// The arena allocator for `value`.  Use this when extending the
    /// JSON tree (new ObjectMap entries, dup'd strings) so the
    /// extensions live inside the doc arena and are freed alongside it.
    fn allocator(self: *LoadedDoc) std.mem.Allocator {
        return self.arena.allocator();
    }
};

fn loadSiteJsonValue(parent_allocator: std.mem.Allocator, path: []const u8) !LoadedDoc {
    const arena = try parent_allocator.create(std.heap.ArenaAllocator);
    errdefer parent_allocator.destroy(arena);
    arena.* = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const stat = try f.stat();
    if (stat.size > 1024 * 1024) return error.file_too_large;
    const buf = try allocator.alloc(u8, stat.size);
    _ = try f.readAll(buf);
    const value = try std.json.parseFromSliceLeaky(std.json.Value, allocator, buf, .{});
    return .{ .arena = arena, .value = value, .parent_allocator = parent_allocator };
}

fn stringifyValue(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, value, .{ .whitespace = .indent_2 });
}

fn writeFileAtomic(path: []const u8, contents: []const u8) !void {
    // Write to a sibling .tmp file, fsync, rename.  Crash-safe under
    // POSIX semantics — a partial write never replaces the existing
    // file.
    const tmp_path = blk: {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const out = try std.fmt.bufPrint(&path_buf, "{s}.tmp", .{path});
        break :blk out;
    };
    {
        const f = std.fs.cwd().createFile(tmp_path, .{}) catch return error.persistence_failed;
        defer f.close();
        f.writeAll(contents) catch return error.persistence_failed;
        f.sync() catch return error.persistence_failed;
    }
    std.fs.cwd().rename(tmp_path, path) catch return error.persistence_failed;
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

```
