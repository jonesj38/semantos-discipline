---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/site.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.285019+00:00
---

# runtime/semantos-brain/src/cli/site.zig

```zig
// Site verbs (WSITE1) extracted from src/cli.zig as Move 3 of the
// cli-modularize refactor.  Pure code motion: no behaviour change.
//
// Owns: sitesDir, siteConfigPath (path helpers — kept pub because
// cli.zig still uses them from cmdServe / cmdRepl / cmdSweep), the
// cmdSite dispatcher + sub-verbs (init / validate / list), the
// shared dispatchSites helper, and the dead renderValidation
// helper (kept verbatim during code motion — separate clean-up).
//
// Cluster owners deferred to later moves: cmdSitePreview /
// cmdSitePublish (handled by operator.zig in a later Move).

const std = @import("std");
const cli_common = @import("common.zig");
const audit_log_mod = @import("audit_log");
const dispatcher_mod = @import("dispatcher");
const sites_handler_mod = @import("sites_handler");
const site_config_mod = @import("site_config");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;
const resolveDataDir = cli_common.resolveDataDir;

/// Resolve `~/.semantos/sites` (or override via BRAIN_SITES_DIR).
pub fn sitesDir(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "BRAIN_SITES_DIR")) |v| {
        return v;
    } else |_| {}
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch
        return allocator.dupe(u8, ".semantos/sites");
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, ".semantos/sites" });
}

pub fn siteConfigPath(allocator: std.mem.Allocator, domain: []const u8) ![]u8 {
    const dir = try sitesDir(allocator);
    defer allocator.free(dir);
    return std.fs.path.join(allocator, &.{ dir, domain, "site.json" });
}

pub fn cmdSite(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain site <init|validate|list> [args...]\n", .{});
        return .bad_args;
    }
    const sub = args[0];

    if (std.mem.eql(u8, sub, "init")) {
        if (args.len < 2) {
            try out.print("usage: brain site init <domain>\n", .{});
            return .bad_args;
        }
        return try cmdSiteInit(allocator, out, args[1]);
    }
    if (std.mem.eql(u8, sub, "validate")) {
        if (args.len < 2) {
            try out.print("usage: brain site validate <domain>\n", .{});
            return .bad_args;
        }
        return try cmdSiteValidate(allocator, out, args[1]);
    }
    if (std.mem.eql(u8, sub, "list")) {
        return try cmdSiteList(allocator, out);
    }
    try out.print("unknown site subcommand: {s}\n", .{sub});
    return .bad_args;
}

/// D-W1 Phase 2 — `brain site init <domain>` rewires through
/// `dispatcher.dispatch(sites, init, ...)`.  Output formatting stays
/// byte-identical to the pre-Phase-2 path.
fn cmdSiteInit(allocator: std.mem.Allocator, out: *const Output, domain: []const u8) !ExitCode {
    const dir = try sitesDir(allocator);
    defer allocator.free(dir);
    const site_json = try std.fs.path.join(allocator, &.{ dir, domain, "site.json" });
    defer allocator.free(site_json);
    const public_dir = try std.fs.path.join(allocator, &.{ dir, domain, "public" });
    defer allocator.free(public_dir);

    // Pre-flight: emit the legacy "already exists" branch before going
    // through the dispatcher, so the operator sees the same message.
    if (std.fs.cwd().openFile(site_json, .{})) |f| {
        f.close();
        try out.print("site already exists at {s}\n", .{site_json});
        return .config_error;
    } else |_| {}

    const args_json = try std.fmt.allocPrint(allocator,
        \\{{"domain":"{s}"}}
    , .{domain});
    defer allocator.free(args_json);

    const result_json = dispatchSites(allocator, dir, "init", args_json) catch |err| switch (err) {
        sites_handler_mod.HandlerError.duplicate_resource => {
            try out.print("site already exists at {s}\n", .{site_json});
            return .config_error;
        },
        sites_handler_mod.HandlerError.invalid_args => {
            try out.print("invalid domain: {s}\n", .{domain});
            return .bad_args;
        },
        else => {
            try out.print("failed to create site dir: {s}\n", .{@errorName(err)});
            return .file_io;
        },
    };
    defer allocator.free(result_json);

    try out.print("Scaffolded site {s}:\n", .{domain});
    try out.print("  config:  {s}\n", .{site_json});
    try out.print("  content: {s}\n", .{public_dir});
    try out.print("\nNext: `brain serve {s}` to start the HTTP server on port 8080.\n", .{domain});
    return .ok;
}

/// D-W1 Phase 2 — `brain site validate <domain>` rewires through
/// `dispatcher.dispatch(sites, validate, ...)`.  Same output format.
fn cmdSiteValidate(allocator: std.mem.Allocator, out: *const Output, domain: []const u8) !ExitCode {
    const dir = try sitesDir(allocator);
    defer allocator.free(dir);
    const path = try siteConfigPath(allocator, domain);
    defer allocator.free(path);

    const args_json = try std.fmt.allocPrint(allocator,
        \\{{"domain":"{s}"}}
    , .{domain});
    defer allocator.free(args_json);

    const result_json = dispatchSites(allocator, dir, "validate", args_json) catch |err| switch (err) {
        sites_handler_mod.HandlerError.not_found => {
            try out.print("validate {s}: {s} (FileNotFound)\n", .{ domain, path });
            return .config_error;
        },
        sites_handler_mod.HandlerError.invalid_args => {
            try out.print("validate {s}: invalid domain\n", .{domain});
            return .bad_args;
        },
        sites_handler_mod.HandlerError.validation_failed => {
            try out.print("validate {s}: {s} (parse_failed)\n", .{ domain, path });
            return .config_error;
        },
        else => {
            try out.print("validate {s}: {s} ({s})\n", .{ domain, path, @errorName(err) });
            return .config_error;
        },
    };
    defer allocator.free(result_json);

    // Render the validation report in the same shape the legacy path
    // produced.  Parse the JSON `{err_count:N, problems:[...]}` and
    // walk it to print "✗ error: ..." / "⚠ warn: ..." per problem.
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, result_json, .{}) catch {
        try out.print("validate {s}: malformed dispatcher response\n", .{domain});
        return .config_error;
    };
    defer parsed.deinit();
    if (parsed.value != .object) return .config_error;
    const err_count_v = parsed.value.object.get("err_count") orelse return .config_error;
    if (err_count_v != .integer) return .config_error;
    const err_count: i64 = err_count_v.integer;

    const problems_v = parsed.value.object.get("problems") orelse return .config_error;
    if (problems_v != .array) return .config_error;
    if (problems_v.array.items.len == 0) {
        try out.print("✓ no problems\n", .{});
    } else {
        for (problems_v.array.items) |p| {
            if (p != .object) continue;
            const sev_v = p.object.get("severity") orelse continue;
            const msg_v = p.object.get("message") orelse continue;
            if (sev_v != .string or msg_v != .string) continue;
            const sev_label: []const u8 = if (std.mem.eql(u8, sev_v.string, "err")) "✗ error" else "⚠ warn";
            try out.print("{s}: {s}\n", .{ sev_label, msg_v.string });
        }
        if (err_count > 0) {
            try out.print("\n{d} error(s) — config not deployable.\n", .{err_count});
        }
    }
    return if (err_count > 0) .config_error else .ok;
}

fn renderValidation(out: *const Output, report: *const site_config_mod.ValidationReport) !void {
    if (report.problems.items.len == 0) {
        try out.print("✓ no problems\n", .{});
        return;
    }
    for (report.problems.items) |p| {
        const sev = switch (p.severity) {
            .err => "✗ error",
            .warn => "⚠ warn",
        };
        try out.print("{s}: {s}\n", .{ sev, p.message });
    }
    if (report.errCount() > 0) {
        try out.print("\n{d} error(s) — config not deployable.\n", .{report.errCount()});
    }
}

/// D-W1 Phase 2 — `brain site list` rewires through
/// `dispatcher.dispatch(sites, list, {})`.  Output stays byte-identical
/// to the pre-Phase-2 path (one domain per line; "(no sites
/// configured)" or "(no sites configured at <dir>)" empty fallback).
fn cmdSiteList(allocator: std.mem.Allocator, out: *const Output) !ExitCode {
    const dir = try sitesDir(allocator);
    defer allocator.free(dir);

    // Mirror the legacy "(no sites configured at <dir>)" path when
    // the directory itself doesn't exist — preserves operator-facing
    // message exactly.
    if (std.fs.cwd().access(dir, .{})) |_| {} else |_| {
        try out.print("(no sites configured at {s})\n", .{dir});
        return .ok;
    }

    const result_json = dispatchSites(allocator, dir, "list", "{}") catch |err| {
        try out.print("(no sites configured at {s}; {s})\n", .{ dir, @errorName(err) });
        return .ok;
    };
    defer allocator.free(result_json);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, result_json, .{}) catch {
        try out.print("list: malformed dispatcher response\n", .{});
        return .file_io;
    };
    defer parsed.deinit();
    if (parsed.value != .object) return .file_io;
    const sites_v = parsed.value.object.get("sites") orelse return .file_io;
    if (sites_v != .array) return .file_io;

    if (sites_v.array.items.len == 0) {
        try out.print("(no sites configured)\n", .{});
        return .ok;
    }
    for (sites_v.array.items) |s| {
        if (s != .string) continue;
        try out.print("{s}\n", .{s.string});
    }
    return .ok;
}

/// One `sites.<cmd>` dispatch through the in-process dispatcher.
/// Constructs the dispatcher + sites_handler + audit log on the
/// stack, runs the dispatch, copies the result payload out, and
/// tears everything down before returning.  Mirrors the embedded
/// path `dispatchBearer` uses for `brain bearer`.
///
/// Returns the result JSON allocated from `allocator`.  Caller frees.
fn dispatchSites(
    allocator: std.mem.Allocator,
    sites_dir: []const u8,
    cmd: []const u8,
    args_json: []const u8,
) ![]u8 {
    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    // Best-effort audit log open — share `<data_dir>/audit.log` when
    // available so dispatcher entries land in the same log as bearer/
    // device.  Dispatcher's recordAudit swallows audit-not-open errors
    // so commands still execute.
    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    const audit_path = try std.fs.path.join(allocator, &.{ data_dir, "audit.log" });
    defer allocator.free(audit_path);
    audit.open(audit_path) catch {};

    var handler = sites_handler_mod.Handler.init(allocator, sites_dir);
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();
    try disp.register(handler.resourceHandler());

    const ctx = dispatcher_mod.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "cli-site", .transport_label = "embedded" },
    };
    var result = try disp.dispatch(&ctx, "sites", cmd, args_json);
    defer result.deinit();
    return try allocator.dupe(u8, result.payload);
}

```
