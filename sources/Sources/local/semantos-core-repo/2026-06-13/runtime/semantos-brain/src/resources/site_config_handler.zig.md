---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/resources/site_config_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.293026+00:00
---

# runtime/semantos-brain/src/resources/site_config_handler.zig

```zig
// D-O5.followup-5 — site config editor backend handler.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md (D-O5 followup-5
// row), docs/canon/deliverables.yml (D-O5.followup-5).
//
// Tenant operators currently edit `<sites_dir>/<domain>/site.json` by
// hand to configure their public site routes (static / dynamic /
// directory / chat).  The helm SPA wants a "site config" editor view
// so operators can read + write the config from the browser.
//
// This handler exposes two commands behind the dispatcher seam:
//
//   read   — { domain }                      → { domain, json, written_at? }
//            cap = cap.brain.admin
//
//   write  — { domain, json, dry_run? }      → { ok, written_at? }
//            cap = cap.brain.admin
//
// `read` loads `<sites_dir>/<domain>/site.json`, parses it (so a
// corrupt-on-disk file surfaces as a typed error rather than the
// browser receiving garbage), and returns the raw JSON bytes verbatim
// so the editor renders them with the operator's original whitespace
// and ordering.  Sensitive fields (`signing_secret`, `signing_key_wif`)
// are NOT redacted on read — the editor surface is operator-root only,
// and stripping them would force a separate "fetch sensitive bits"
// step before write, which would break round-trip semantics.  The
// existing `sites_handler.get_config` already has the redacted-view
// shape for any non-editor surface that needs it.
//
// `write` accepts a full SiteConfig JSON blob, validates it via
// `site_config.parseJson` (refuses on parse / schema / route / auth /
// CORS errors with the typed `validation_failed` reason), and atomically
// replaces the on-disk file via the same write-to-temp-and-rename dance
// `sites_handler` uses.  The `dry_run` flag lets the helm SPA's
// "Validate" button check a draft without touching disk; on success
// the response is `{ok:true}` and no audit entry is emitted (the
// dispatcher's audit pair uses the cmd verb, so dry_run callers go
// through the same audit path as a real write — by design, since the
// validation step is the part operators want logged).
//
// Architectural note — why a separate handler from `sites_handler`:
//   • `sites_handler` ships targeted edits (route_add, route_remove,
//     set_listen_port).  Each command knows the field shape and
//     mutates one slice of the JSON tree.  That keeps each operator
//     verb auditable on its own — the audit log sees "route_add /foo
//     static foo.html" rather than "the operator wrote 4 KiB of JSON".
//   • The editor view's UX is fundamentally "give me the whole blob
//     so I can edit any field".  Splitting the editor's Save button
//     into a sequence of route_add / route_remove / set_listen_port /
//     set_anonymous_caps / set_cors_* calls would (a) make the brain-
//     side surface huge, and (b) lose write atomicity — a half-applied
//     edit on a network blip would leave the site config in a state
//     no editor session asked for.  One-shot whole-blob write is the
//     only sane shape for a UI editor.
//   • The two handlers cohabit cleanly: `sites_handler` is for the CLI
//     scripting surface (`brain site route add ...`), `site_config_handler`
//     is for the GUI editor surface.  Both gate on `cap.brain.admin`.
//
// Concurrency: same model as `sites_handler` — one mutex serialises
// writes against this handler's `sites_dir` within ONE brain process.
// Cross-process serialisation is left as the same TODO (flock(2)).
//
// Audit semantics: `read` is classified as a read via `is_read_fn` so
// it can be opt-out from `audit_reads` if a future high-frequency
// caller appears (the editor itself fires `read` once per view-mount,
// so we leave audit on by default for now).  `write` always emits the
// dispatcher's begin/complete pair.

const std = @import("std");
const dispatcher = @import("dispatcher");
const site_config = @import("site_config");

pub const RESOURCE_NAME = "site_config";

pub const HandlerError = error{
    /// JSON args parse failed or required arg missing.
    invalid_args,
    /// Underlying disk I/O failed (permission, ENOSPC, …).
    store_error,
    /// `<sites_dir>/<domain>/site.json` not found.
    not_found,
    /// `write` payload didn't pass `site_config.parseJson`.  The
    /// editor surface translates this into a typed inline error.
    validation_failed,
    /// Result-allocation failed.
    out_of_memory,
};

/// State the handler carries.  The dispatcher hands `state` to every
/// callback as `*anyopaque`; we cast back to `*Handler`.
pub const Handler = struct {
    allocator: std.mem.Allocator,
    /// The root directory under which `<domain>/site.json` lives.
    /// Borrowed; the caller (cmdServe / CLI embedded-mode / tests)
    /// owns the underlying memory.
    sites_dir: []const u8,
    /// Serialises every disk mutation against this handler's
    /// `sites_dir`.  Mirrors sites_handler's threading model.
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
            .audit_reads = true,
            .is_read_fn = isRead,
        };
    }
};

// ─────────────────────────────────────────────────────────────────────
// Capability declarations
// ─────────────────────────────────────────────────────────────────────

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "read")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "write")) return .{ .require = "cap.brain.admin" };
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Read classifier
// ─────────────────────────────────────────────────────────────────────

pub fn isRead(cmd: []const u8) bool {
    if (std.mem.eql(u8, cmd, "read")) return true;
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

    if (std.mem.eql(u8, cmd, "read")) return handleRead(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "write")) return handleWrite(self, allocator, args_json);
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Per-command implementations
// ─────────────────────────────────────────────────────────────────────

fn handleRead(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const domain = parseDomainArg(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(domain);

    if (!isValidDomainShape(domain)) return HandlerError.invalid_args;

    const site_json = try siteJsonPath(allocator, self.sites_dir, domain);
    defer allocator.free(site_json);

    const file = std.fs.cwd().openFile(site_json, .{}) catch |err| switch (err) {
        error.FileNotFound => return HandlerError.not_found,
        else => return HandlerError.store_error,
    };
    defer file.close();
    const stat = file.stat() catch return HandlerError.store_error;
    if (stat.size > 1024 * 1024) return HandlerError.store_error;
    const raw = allocator.alloc(u8, stat.size) catch return HandlerError.out_of_memory;
    defer allocator.free(raw);
    _ = file.readAll(raw) catch return HandlerError.store_error;

    // Round-trip through the parser so a corrupt-on-disk file fails
    // loud rather than handing a broken blob to the editor (which
    // would then look like the editor itself was busted).  We don't
    // re-encode — we just verify the file parses, then ship the raw
    // bytes verbatim so the operator's whitespace + ordering survive.
    var cfg = site_config.parseJson(allocator, raw) catch return HandlerError.validation_failed;
    cfg.deinit();

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"domain\":");
    try writeJsonString(allocator, &buf, domain);
    try buf.appendSlice(allocator, ",\"json\":");
    try writeJsonString(allocator, &buf, raw);
    try buf.print(allocator, ",\"size\":{d},\"mtime_unix\":{d}}}", .{
        stat.size,
        @divTrunc(stat.mtime, std.time.ns_per_s),
    });
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

const WriteArgs = struct {
    domain: []u8,
    json: []u8,
    dry_run: bool,

    fn deinit(self: WriteArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.domain);
        allocator.free(self.json);
    }
};

fn parseWriteArgs(allocator: std.mem.Allocator, args_json: []const u8) !WriteArgs {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    const domain_v = obj.get("domain") orelse return error.invalid_args;
    if (domain_v != .string) return error.invalid_args;
    const domain = try allocator.dupe(u8, domain_v.string);
    errdefer allocator.free(domain);

    const json_v = obj.get("json") orelse return error.invalid_args;
    if (json_v != .string) return error.invalid_args;
    const json_str = try allocator.dupe(u8, json_v.string);
    errdefer allocator.free(json_str);

    var dry_run = false;
    if (obj.get("dry_run")) |v| {
        if (v != .bool) return error.invalid_args;
        dry_run = v.bool;
    }

    return .{ .domain = domain, .json = json_str, .dry_run = dry_run };
}

fn handleWrite(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const args = parseWriteArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer args.deinit(allocator);

    if (!isValidDomainShape(args.domain)) return HandlerError.invalid_args;

    // Defense-in-depth: cap the inbound payload at 1 MiB to match the
    // on-disk read cap in `site_config.loadFromPath`.  An editor that
    // tries to push more than that is either buggy or hostile.
    if (args.json.len > 1024 * 1024) return HandlerError.validation_failed;

    // Validate first, no matter the dry_run flag.  The post-validate
    // path branches on dry_run.
    var cfg = site_config.parseJson(allocator, args.json) catch return HandlerError.validation_failed;
    cfg.deinit();

    if (args.dry_run) {
        const payload = try allocator.dupe(u8, "{\"ok\":true,\"dry_run\":true}");
        return dispatcher.Result.ownedPayload(allocator, payload);
    }

    // Confirm the per-domain directory exists.  We don't auto-create —
    // operators initialise sites with `brain site init`, so a missing
    // directory means the operator typo'd the domain in the editor.
    const site_dir = try std.fs.path.join(allocator, &.{ self.sites_dir, args.domain });
    defer allocator.free(site_dir);
    std.fs.cwd().access(site_dir, .{}) catch return HandlerError.not_found;

    const site_json = try siteJsonPath(allocator, self.sites_dir, args.domain);
    defer allocator.free(site_json);

    try writeFileAtomic(site_json, args.json);

    const written_at = std.time.timestamp();
    const payload = try std.fmt.allocPrint(
        allocator,
        "{{\"ok\":true,\"written_at\":{d}}}",
        .{written_at},
    );
    return dispatcher.Result.ownedPayload(allocator, payload);
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

/// Refuse path-traversal / weird characters in `domain`.  Domains are
/// directory names under `sites_dir` so we want a tight allowlist.
/// Mirrors the validator in sites_handler.zig.
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

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

/// Write contents to `path` via a sibling .tmp file + rename.  Crash-
/// safe under POSIX semantics: a partial write never replaces the
/// existing file.  Mirrors `sites_handler.writeFileAtomic` so atomicity
/// behaviour is identical across the two handlers.
fn writeFileAtomic(path: []const u8, contents: []const u8) !void {
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

```
