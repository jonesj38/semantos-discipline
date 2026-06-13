---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/bearer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.287754+00:00
---

# runtime/semantos-brain/src/cli/bearer.zig

```zig
// Bearer-token verbs extracted from src/cli.zig as Move 4 of the
// cli-modularize refactor.  Pure code motion: no behaviour change.
//
// Owns: BearerOutcome (mode tag + result), dispatchBearer (the
// socket-or-embedded dispatch helper), cmdBearer dispatcher +
// sub-verbs (issue / list / revoke).
//
// realClock + wire_errbody + daemonErrorAsZigError are duplicated
// here (kept private) rather than promoted to common.zig because
// the device cluster (Move 6) needs its own copies too — a follow-up
// cleanup can collapse them once both clusters live in their own
// files.

const std = @import("std");
const cli_common = @import("common.zig");
const bearer_tokens_mod = @import("bearer_tokens");
const bearer_tokens_handler_mod = @import("bearer_tokens_handler");
const audit_log_mod = @import("audit_log");
const dispatcher_mod = @import("dispatcher");
const unix_socket_transport = @import("unix_socket");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;
const resolveDataDir = cli_common.resolveDataDir;
const jsonStringField = cli_common.jsonStringField;
const jsonIntField = cli_common.jsonIntField;
const realClock = cli_common.realClock;
const daemonErrorAsZigError = cli_common.daemonErrorAsZigError;

/// Mode tag returned alongside a dispatch result so the print path
/// can show the operator which seam ran.  `socket` carries the
/// resolved socket path; `embedded` carries the data_dir the
/// in-process dispatcher opened.  Both paths produce identical
/// post-state by construction (same dispatcher code, same handler).
const BearerOutcome = struct {
    result_json: []u8,
    mode: Mode,
    socket_path: []u8 = &.{},
    data_dir: []u8 = &.{},

    const Mode = enum { socket, embedded };

    fn deinit(self: *BearerOutcome, allocator: std.mem.Allocator) void {
        allocator.free(self.result_json);
        if (self.socket_path.len > 0) allocator.free(self.socket_path);
        if (self.data_dir.len > 0) allocator.free(self.data_dir);
    }
};

/// Run one `bearer_tokens.<cmd>` dispatch — over the Unix socket if
/// the daemon is up, otherwise via an in-process dispatcher with the
/// locally-opened TokenStore.  Returns owned result JSON + mode tag.
fn dispatchBearer(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    cmd: []const u8,
    args_json: []const u8,
) !BearerOutcome {
    // ── Socket mode ──
    if (unix_socket_transport.Client.connect(allocator, data_dir)) |client_val| {
        var client = client_val;
        defer client.close();
        var resp = try client.dispatch("bearer_tokens", cmd, args_json, "cli");
        defer resp.deinit();
        if (resp.response.err) |e| {
            return daemonErrorAsZigError(e);
        }
        const sock_path = try std.fs.path.join(allocator, &.{ data_dir, unix_socket_transport.SOCKET_BASENAME });
        errdefer allocator.free(sock_path);
        return .{
            .result_json = try allocator.dupe(u8, resp.response.result_json),
            .mode = .socket,
            .socket_path = sock_path,
            .data_dir = &.{},
        };
    } else |_| {}

    // ── Embedded mode ──
    var audit = audit_log_mod.AuditLog.init();
    const audit_path = try std.fs.path.join(allocator, &.{ data_dir, "audit.log" });
    defer allocator.free(audit_path);
    audit.open(audit_path) catch |err| switch (err) {
        // Best-effort: an audit-log open failure shouldn't kill the
        // command (the operator may not have created the dir yet).
        // The dispatcher swallows audit-log-not-open errors at
        // record-time, so commands still execute.
        else => {},
    };
    defer audit.close();

    var store = try bearer_tokens_mod.TokenStore.init(allocator, data_dir, realClock);
    defer store.deinit();
    var handler = bearer_tokens_handler_mod.Handler.init(allocator, &store);
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();
    try disp.register(handler.resourceHandler());

    const ctx = dispatcher_mod.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "cli-embedded", .transport_label = "embedded" },
    };
    var result = try disp.dispatch(&ctx, "bearer_tokens", cmd, args_json);
    defer result.deinit();

    const dd = try allocator.dupe(u8, data_dir);
    errdefer allocator.free(dd);
    return .{
        .result_json = try allocator.dupe(u8, result.payload),
        .mode = .embedded,
        .data_dir = dd,
        .socket_path = &.{},
    };
}

pub fn cmdBearer(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain bearer <issue|list|revoke> [args...]\n", .{});
        return .bad_args;
    }
    const sub = args[0];
    if (std.mem.eql(u8, sub, "issue")) return try cmdBearerIssue(allocator, out, args[1..]);
    if (std.mem.eql(u8, sub, "list")) return try cmdBearerList(allocator, out);
    if (std.mem.eql(u8, sub, "revoke")) {
        if (args.len < 2) {
            try out.print("usage: brain bearer revoke <token-id>\n", .{});
            return .bad_args;
        }
        return try cmdBearerRevoke(allocator, out, args[1]);
    }
    try out.print("unknown bearer subcommand: {s}\n", .{sub});
    return .bad_args;
}

/// Issue a new bearer token. Required: --label NAME. Optional:
/// --ttl-seconds SECONDS (default 7 days; 0 = never expires).
/// `--ttl` is accepted as a back-compat alias.
///
/// Path: tries the Unix socket first; falls back to embedded mode if
/// the daemon isn't running.  Either way, the dispatcher's bearer_tokens
/// resource handler is the sole writer — the in-memory index and the
/// on-disk log are mutated atomically (closes brain issues #1 + #2).
fn cmdBearerIssue(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    var label: ?[]const u8 = null;
    var ttl_secs: i64 = 7 * 24 * 3600;
    // SH14 / D12 — hat role for the issued token; default operator.
    var role: []const u8 = "operator";
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--label") and i + 1 < args.len) {
            label = args[i + 1];
            i += 1;
        } else if ((std.mem.eql(u8, args[i], "--ttl-seconds") or
            std.mem.eql(u8, args[i], "--ttl")) and i + 1 < args.len)
        {
            ttl_secs = std.fmt.parseInt(i64, args[i + 1], 10) catch {
                try out.print("issue: invalid --ttl-seconds `{s}` (expected seconds)\n", .{args[i + 1]});
                return .bad_args;
            };
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--role") and i + 1 < args.len) {
            const r = args[i + 1];
            if (!std.mem.eql(u8, r, "operator") and !std.mem.eql(u8, r, "admin")) {
                try out.print("issue: invalid --role `{s}` (expected operator|admin)\n", .{r});
                return .bad_args;
            }
            role = r;
            i += 1;
        } else {
            try out.print("issue: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }
    if (label == null) {
        try out.print("usage: brain bearer issue --label NAME [--ttl-seconds N] [--role operator|admin]\n", .{});
        return .bad_args;
    }

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    const args_json = try std.fmt.allocPrint(allocator,
        \\{{"label":"{s}","ttl_seconds":{d},"role":"{s}"}}
    , .{ label.?, ttl_secs, role });
    defer allocator.free(args_json);

    var outcome = dispatchBearer(allocator, data_dir, "issue", args_json) catch |e| {
        try out.print("issue: dispatch failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer outcome.deinit(allocator);

    // Pull id / token / fingerprint / expires_at out of the JSON.
    const id = jsonStringField(allocator, outcome.result_json, "id") catch return .file_io;
    defer allocator.free(id);
    const token = jsonStringField(allocator, outcome.result_json, "token") catch return .file_io;
    defer allocator.free(token);
    const fingerprint = jsonStringField(allocator, outcome.result_json, "fingerprint") catch return .file_io;
    defer allocator.free(fingerprint);
    const expires_at = jsonIntField(allocator, outcome.result_json, "expires_at") catch 0;

    try out.print("\n", .{});
    switch (outcome.mode) {
        .socket => try out.print("Bearer token issued (via daemon at {s}).\n", .{outcome.socket_path}),
        .embedded => try out.print("Bearer token issued (embedded mode — no running daemon).\n  data_dir:    {s}\n", .{outcome.data_dir}),
    }
    try out.print("\n", .{});
    try out.print("  id:          {s}\n", .{id});
    try out.print("  label:       {s}\n", .{label.?});
    try out.print("  fingerprint: {s}\n", .{fingerprint});
    try out.print("  expires_at:  ", .{});
    if (expires_at == 0) {
        try out.print("(never)\n", .{});
    } else {
        try out.print("{d} (unix-seconds)\n", .{expires_at});
    }
    try out.print("\n", .{});
    try out.print("Token (copy this now — it will not be shown again):\n", .{});
    try out.print("\n", .{});
    try out.print("  {s}\n", .{token});
    try out.print("\n", .{});
    try out.print("Use it like: curl -H \"Authorization: Bearer {s}\" \\\n", .{token});
    try out.print("                  https://<your-domain>/api/v1/repl \\\n", .{});
    try out.print("                  -d '{{\"cmd\":\"status\"}}'\n", .{});
    try out.print("\n", .{});
    return .ok;
}

fn cmdBearerList(allocator: std.mem.Allocator, out: *const Output) !ExitCode {
    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    var outcome = dispatchBearer(allocator, data_dir, "list", "{}") catch |e| {
        try out.print("list: dispatch failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer outcome.deinit(allocator);

    switch (outcome.mode) {
        .socket => try out.print("(via daemon at {s})\n\n", .{outcome.socket_path}),
        .embedded => try out.print("(embedded mode — data_dir: {s})\n\n", .{outcome.data_dir}),
    }

    // Parse the result JSON: {"tokens":[{"id","label","fingerprint","issued_at","expires_at","revoked"}, ...]}
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, outcome.result_json, .{}) catch {
        try out.print("list: malformed daemon response\n", .{});
        return .file_io;
    };
    defer parsed.deinit();
    if (parsed.value != .object) return .file_io;
    const tokens_v = parsed.value.object.get("tokens") orelse {
        try out.print("list: malformed daemon response (no tokens field)\n", .{});
        return .file_io;
    };
    if (tokens_v != .array) return .file_io;
    const tokens = tokens_v.array.items;

    if (tokens.len == 0) {
        try out.print("(no bearer tokens issued — `brain bearer issue --label NAME` to create one)\n", .{});
        return .ok;
    }

    try out.print("{d} bearer token(s):\n\n", .{tokens.len});
    const now = realClock();
    for (tokens) |t| {
        if (t != .object) continue;
        const tobj = t.object;
        const id = (tobj.get("id") orelse continue).string;
        const label = (tobj.get("label") orelse continue).string;
        const fp = (tobj.get("fingerprint") orelse continue).string;
        const issued_at = (tobj.get("issued_at") orelse continue).integer;
        const expires_at = (tobj.get("expires_at") orelse continue).integer;
        try out.print("  id:          {s}\n", .{id});
        try out.print("  label:       {s}\n", .{label});
        try out.print("  fingerprint: {s}\n", .{fp});
        try out.print("  issued_at:   {d}\n", .{issued_at});
        if (expires_at == 0) {
            try out.print("  expires_at:  (never)\n", .{});
        } else if (expires_at < now) {
            try out.print("  expires_at:  {d}  (EXPIRED)\n", .{expires_at});
        } else {
            try out.print("  expires_at:  {d}  ({d}s remaining)\n", .{ expires_at, expires_at - now });
        }
        try out.print("\n", .{});
    }
    return .ok;
}

fn cmdBearerRevoke(allocator: std.mem.Allocator, out: *const Output, id_arg: []const u8) !ExitCode {
    if (id_arg.len != 32) {
        try out.print("revoke: id must be 32 hex chars (got {d})\n", .{id_arg.len});
        return .bad_args;
    }
    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    const args_json = try std.fmt.allocPrint(allocator,
        \\{{"id":"{s}"}}
    , .{id_arg});
    defer allocator.free(args_json);

    var outcome = dispatchBearer(allocator, data_dir, "revoke", args_json) catch |e| {
        try out.print("revoke: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer outcome.deinit(allocator);

    switch (outcome.mode) {
        .socket => try out.print("revoked: {s} (via daemon at {s})\n", .{ id_arg, outcome.socket_path }),
        .embedded => try out.print("revoked: {s} (embedded mode — data_dir: {s})\n", .{ id_arg, outcome.data_dir }),
    }
    return .ok;
}

```
