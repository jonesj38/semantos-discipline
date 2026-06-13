---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/resources/bearer_tokens_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.295467+00:00
---

# runtime/semantos-brain/src/resources/bearer_tokens_handler.zig

```zig
// Phase D-W1 / Phase 1 — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3, §8.
//
// Dispatcher resource handler that fronts the existing
// `bearer_tokens.TokenStore` (runtime/semantos-brain/src/bearer_tokens.zig).  This
// is the seam where brain issues #1 (CLI/daemon path divergence) and #2
// (daemon doesn't pick up new tokens until restart) die: the dispatcher
// owns the only live `TokenStore`, and every transport (CLI-as-socket-
// client, helm SPA over HTTP, future mesh peers) talks to that one
// instance.  Issuing a token immediately mutates the in-memory index
// AND writes the append-only log under one mutex; subsequent
// `validate` calls see the new fingerprint without a daemon restart.
//
// Commands (per Phase 1 spec):
//   issue     — { label, ttl_seconds? }  →  { id, token, fingerprint, expires_at }
//                                            cap = cap.brain.admin
//   revoke    — { id }                   →  { ok }
//                                            cap = cap.brain.admin
//   list      — {}                       →  { tokens: [...] }
//                                            cap = cap.brain.admin
//   validate  — { token }                →  { valid, fingerprint?, label? }
//                                            cap = none (anyone with a
//                                                  token can self-validate)
//
// Args & results are JSON; the handler parses args_json into typed
// values, mutates the store under its own mutex, and returns an
// allocator-owned JSON result.  The dispatcher takes care of audit
// pairing — this file only emits domain errors.
//
// Concurrency: all four entry points lock `mu` for the duration of the
// store call.  The store's own append-only log writes are O(1) and the
// hashmap mutations are also bounded — no awaiting, no callouts under
// the lock.  Two transports issuing simultaneously serialise here and
// produce two distinct ids by construction (each `issue` reads
// `std.crypto.random.bytes` afresh).
//
// Concurrency v0.1 — single-process only.  This mutex serialises
// callers within ONE brain process (daemon-mode + its accepted
// connections, OR a single embedded-mode CLI).  Two embedded-mode
// CLIs racing on the same data_dir, or an embedded CLI racing the
// daemon's socket clients, are NOT serialised — both processes
// open the same bearer-tokens.log file independently.  Operator
// is expected to run one CLI invocation at a time against a given
// data_dir; if the daemon is up, the CLI auto-routes to it via the
// Unix socket.  TODO(D-W1 Phase 2): add flock(2) on the log file in
// TokenStore for cross-process serialisation if a real concurrency
// case appears (it hasn't yet — bearer issuance is a human-paced
// operator action).
//
// Index ↔ log atomicity v0.1 — TODO(D-W1 Phase 2): the underlying
// `bearer_tokens.TokenStore.issue` updates the in-memory index
// BEFORE appending the log line.  If the log append fails (disk
// full, signal during write) the in-memory state holds a token
// that's not durable — it'll vanish on the next process restart
// + replayLog.  A subsequent dispatch in the same process would
// successfully validate against the in-memory entry; after restart
// the same token would fail validation.  The Phase 1 brief said
// "Do NOT rewrite the storage layer", so the fix lands separately.
// Reorder to log → fsync → index in a follow-up.

const std = @import("std");
const dispatcher = @import("dispatcher");
const bearer_tokens = @import("bearer_tokens");

pub const RESOURCE_NAME = "bearer_tokens";

/// Default TTL when the caller omits `ttl_seconds`.  7 days, matching
/// the historical `brain bearer issue` CLI default.
pub const DEFAULT_TTL_SECONDS: i64 = 7 * 24 * 3600;

pub const HandlerError = error{
    /// JSON args parse failed or required arg missing.
    invalid_args,
    /// Underlying TokenStore call failed (file I/O, bad format, …).
    store_error,
    /// `revoke` / `validate` referenced a token that doesn't exist.
    not_found,
    /// Result-allocation failed.
    out_of_memory,
};

/// State carried alongside the resource registration.  The handler is
/// the sole owner of the TokenStore for the dispatcher's lifetime; the
/// daemon constructs it once at boot and registers it via `register`.
pub const Handler = struct {
    allocator: std.mem.Allocator,
    store: *bearer_tokens.TokenStore,
    /// Serialises issue / revoke / list / validate against the store.
    /// The store itself is not thread-safe; this mutex is the seam
    /// between concurrent transport callers.
    mu: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, store: *bearer_tokens.TokenStore) Handler {
        return .{
            .allocator = allocator,
            .store = store,
            .mu = .{},
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
        };
    }
};

// ─────────────────────────────────────────────────────────────────────
// Capability declarations
// ─────────────────────────────────────────────────────────────────────

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "issue")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "revoke")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "list")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "validate")) return .none;
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

    if (std.mem.eql(u8, cmd, "issue")) return handleIssue(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "revoke")) return handleRevoke(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "list")) return handleList(self, allocator);
    if (std.mem.eql(u8, cmd, "validate")) return handleValidate(self, allocator, args_json);
    // Should not be reachable — the dispatcher guards on cap_for_cmd
    // returning unknown_command first.  Defensive return for
    // belt-and-braces.
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Per-command implementations
// ─────────────────────────────────────────────────────────────────────

fn handleIssue(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const args = parseIssueArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(args.label);

    const issued = self.store.issueWithRole(args.label, args.ttl_seconds, args.role) catch return HandlerError.store_error;

    var hex: [64]u8 = undefined;
    bearer_tokens.hexEncode(&issued.token, &hex);

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.print(
        allocator,
        "{{\"id\":\"{s}\",\"token\":\"{s}\",\"fingerprint\":\"{s}\",\"expires_at\":{d}}}",
        .{ &issued.record.id, &hex, &issued.record.fingerprint, issued.record.expires_at },
    );
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleRevoke(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const id = parseRevokeArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(id);

    // The underlying store.revoke is idempotent on unknown ids (it
    // appends a no-op revocation line for audit completeness).  We
    // still want callers to know whether their target id existed; we
    // check membership before calling so we can report `not_found`
    // distinctly from a successful revoke.
    var found = false;
    {
        const items = try self.store.list(allocator);
        defer allocator.free(items);
        for (items) |rec| {
            if (std.mem.eql(u8, &rec.id, id)) {
                found = true;
                break;
            }
        }
    }
    if (!found) return HandlerError.not_found;

    self.store.revoke(id) catch return HandlerError.store_error;

    const payload = try allocator.dupe(u8, "{\"ok\":true}");
    return dispatcher.Result.ownedPayload(allocator, payload);
}

fn handleList(self: *Handler, allocator: std.mem.Allocator) !dispatcher.Result {
    const items = try self.store.list(allocator);
    defer allocator.free(items);

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"tokens\":[");
    for (items, 0..) |rec, i| {
        if (i != 0) try buf.append(allocator, ',');
        try buf.print(
            allocator,
            "{{\"id\":\"{s}\",\"label\":",
            .{&rec.id},
        );
        // label is operator-supplied — escape via std.json so embedded
        // quotes / backslashes don't corrupt the envelope.
        try writeJsonString(allocator, &buf, rec.label);
        try buf.print(
            allocator,
            ",\"fingerprint\":\"{s}\",\"issued_at\":{d},\"expires_at\":{d},\"revoked\":false}}",
            .{ &rec.fingerprint, rec.issued_at, rec.expires_at },
        );
    }
    try buf.appendSlice(allocator, "]}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleValidate(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const token_hex = parseValidateArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(token_hex);

    const rec = self.store.verifyHex(token_hex) catch |err| switch (err) {
        bearer_tokens.TokenError.not_found,
        bearer_tokens.TokenError.expired,
        bearer_tokens.TokenError.revoked,
        bearer_tokens.TokenError.bad_format,
        => {
            const payload = try allocator.dupe(u8, "{\"valid\":false}");
            return dispatcher.Result.ownedPayload(allocator, payload);
        },
        else => return HandlerError.store_error,
    };

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"valid\":true,\"fingerprint\":\"");
    try buf.appendSlice(allocator, &rec.fingerprint);
    try buf.appendSlice(allocator, "\",\"label\":");
    try writeJsonString(allocator, &buf, rec.label);
    try buf.append(allocator, '}');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// Args parsing — small JSON walks; never trust the caller's payload
// ─────────────────────────────────────────────────────────────────────

const IssueArgs = struct {
    label: []u8, // owned
    ttl_seconds: i64,
    /// SH14 / D12 — hat role; a static literal ("operator" | "admin"), not
    /// owned (coerced to one of two literals, so no allocation to free).
    role: []const u8,
};

fn parseIssueArgs(allocator: std.mem.Allocator, args_json: []const u8) !IssueArgs {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    const label_v = obj.get("label") orelse return error.invalid_args;
    if (label_v != .string) return error.invalid_args;
    const label = try allocator.dupe(u8, label_v.string);
    errdefer allocator.free(label);

    var ttl: i64 = DEFAULT_TTL_SECONDS;
    if (obj.get("ttl_seconds")) |v| {
        if (v == .integer) ttl = v.integer;
    }

    // SH14 / D12 — optional hat role; coerce to a static literal (only the
    // literal "admin" elevates; everything else → "operator", fail-safe).
    var role: []const u8 = "operator";
    if (obj.get("role")) |v| {
        if (v == .string and std.mem.eql(u8, v.string, "admin")) role = "admin";
    }
    return .{ .label = label, .ttl_seconds = ttl, .role = role };
}

fn parseRevokeArgs(allocator: std.mem.Allocator, args_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const id_v = obj.get("id") orelse return error.invalid_args;
    if (id_v != .string) return error.invalid_args;
    if (id_v.string.len != 32) return error.invalid_args;
    return try allocator.dupe(u8, id_v.string);
}

fn parseValidateArgs(allocator: std.mem.Allocator, args_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const token_v = obj.get("token") orelse return error.invalid_args;
    if (token_v != .string) return error.invalid_args;
    return try allocator.dupe(u8, token_v.string);
}

// ─────────────────────────────────────────────────────────────────────
// JSON helpers
// ─────────────────────────────────────────────────────────────────────

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

```
