---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/resources/modules_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.292728+00:00
---

# runtime/semantos-brain/src/resources/modules_handler.zig

```zig
// Phase D-W1 / Phase 2 — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md
// §3 (the `modules` row) and §8 Phase 2.
//
// Dispatcher resource handler that fronts `module_loader.zig`
// (hash + WASM-shape verification) + `instance_manager.zig`
// (LOADED/RUNNING/CRASHED state machine).  The CLI verbs `brain hash`,
// `brain modules list`, and `brain modules verify` all route through
// this handler — same shape `brain bearer ...` already uses post-Phase-1.
//
// Same architectural shape as `bearer_tokens_handler.zig`:
//
//   • Mutex-serialised: `register` / `unregister` mutate the
//     instance manager + the operator's `brain.json` modules section;
//     reads are also serialised against any concurrent register.
//   • Capability gating: `register`, `unregister`, `list`, `get_hash`
//     all require `cap.brain.admin`.  `verify` declares `.none` —
//     anyone can ask the daemon "does this byte slice hash to X
//     and have valid WASM magic?"  The handler doesn't keep state
//     about the WASM bytes either way, so leaking that yes/no isn't
//     a confidentiality concern.
//
// Commands (per the §3 row):
//
//   register     — { name, path, expected_sha256 }      MUTATING
//                  Verify + register a module under `<name>`.
//                  cap = cap.brain.admin
//                  Phase 2 MVP: declared as a typed
//                  `not_yet_implemented` error.  The wiring needs
//                  the handler to own a stable `std.ArrayList
//                  (LoadedModule)` so InstanceManager's borrowed
//                  pointers stay valid across registers — the
//                  same pattern `cmdStart` uses today.  Lands
//                  alongside D-O7 (substrate cutover) when
//                  hot-reload of modules at runtime first
//                  becomes a real requirement.
//
//   unregister   — { name }                              MUTATING
//                  Drop the named module from the live registry.
//                  cap = cap.brain.admin
//                  Returns `{removed:true|false}`.
//                  Same Phase 2 MVP defer as `register`.
//
//   list         — {}                                    READ
//                  Enumerate the registered modules + their
//                  state, sha256 hex, restart counts.
//                  cap = cap.brain.admin
//
//   get_hash     — { path }                              READ
//                  Read the file at `path`, return its SHA-256
//                  hex.  This is the "brain hash <wasm_file>" verb's
//                  new home.  Operators paste the result into
//                  `site.json`'s `handler_sha256` or `brain.json`'s
//                  modules section.
//                  cap = cap.brain.admin
//
//   verify       — { path, expected_sha256 }             READ
//                  Read + sha256 + WASM-magic check.  Returns
//                  `{ok:bool, kind:"hash_mismatch"|"not_wasm"|...}`.
//                  cap = .none  — see threat-model note above.
//
// Audit semantics: `register`, `unregister` always emit the dispatcher's
// audit pair.  `list`, `get_hash`, `verify` are reads and skip the
// audit pair when the handler's `audit_reads = false` flag is set
// (per §10 of the design doc).

const std = @import("std");
const dispatcher = @import("dispatcher");
const module_loader = @import("module_loader");
const instance_manager = @import("instance_manager");

pub const RESOURCE_NAME = "modules";

pub const HandlerError = error{
    invalid_args,
    /// File I/O failed on a read path.
    io_failed,
    /// Module file too large.
    file_too_large,
    /// File not found at the given path.
    not_found,
    /// File didn't have WASM magic bytes.
    not_wasm,
    /// File hash didn't match the caller's expected_sha256.
    hash_mismatch,
    /// `register` / `unregister` referenced an absent name.
    module_not_found,
    /// `register` of an already-registered name.
    duplicate_module,
    /// Phase 2 MVP — register / unregister deferred (see module
    /// header note + BRAIN-DISPATCHER-UNIFICATION.md §8 Phase 2).
    not_yet_implemented,
    out_of_memory,
};

pub const Handler = struct {
    allocator: std.mem.Allocator,
    /// In-memory registry the daemon's lifecycle uses.  Borrowed —
    /// caller (cmdServe) constructs the InstanceManager once at boot
    /// and registers it here.  `null` is allowed: tests + embedded-mode
    /// CLI runs that only need `get_hash` / `verify` (the file-only
    /// commands) can pass null and get a typed error if they reach
    /// the in-memory ops.
    manager: ?*instance_manager.InstanceManager,
    mu: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, manager: ?*instance_manager.InstanceManager) Handler {
        return .{
            .allocator = allocator,
            .manager = manager,
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

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "register")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "unregister")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "list")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "get_hash")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "verify")) return .none;
    return error.unknown_command;
}

pub fn isRead(cmd: []const u8) bool {
    if (std.mem.eql(u8, cmd, "list")) return true;
    if (std.mem.eql(u8, cmd, "get_hash")) return true;
    if (std.mem.eql(u8, cmd, "verify")) return true;
    return false;
}

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

    if (std.mem.eql(u8, cmd, "get_hash")) return handleGetHash(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "verify")) return handleVerify(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "list")) return handleList(self, allocator);
    if (std.mem.eql(u8, cmd, "register")) return handleRegister(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "unregister")) return handleUnregister(self, allocator, args_json);
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// get_hash
// ─────────────────────────────────────────────────────────────────────

fn handleGetHash(
    _: *Handler,
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !dispatcher.Result {
    const path = parsePathArg(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(path);

    const f = std.fs.cwd().openFile(path, .{}) catch return HandlerError.not_found;
    defer f.close();
    const stat = f.stat() catch return HandlerError.io_failed;
    if (stat.size > module_loader.MAX_MODULE_BYTES) return HandlerError.file_too_large;
    const buf = try allocator.alloc(u8, stat.size);
    defer allocator.free(buf);
    _ = f.readAll(buf) catch return HandlerError.io_failed;

    const h = module_loader.computeSha256(buf);
    const hex = try module_loader.formatHashHex(allocator, &h);
    defer allocator.free(hex);
    const valid_shape = module_loader.isValidWasmShape(buf);

    const payload = try std.fmt.allocPrint(allocator,
        "{{\"sha256\":\"{s}\",\"size\":{d},\"valid_wasm_shape\":{s},\"path\":\"{s}\"}}",
        .{ hex, stat.size, if (valid_shape) "true" else "false", path });
    return dispatcher.Result.ownedPayload(allocator, payload);
}

// ─────────────────────────────────────────────────────────────────────
// verify
// ─────────────────────────────────────────────────────────────────────

const VerifyArgs = struct {
    path: []u8,
    expected_sha256: []u8, // 64-char hex

    fn deinit(self: VerifyArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.expected_sha256);
    }
};

fn parseVerifyArgs(allocator: std.mem.Allocator, args_json: []const u8) !VerifyArgs {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const p_v = obj.get("path") orelse return error.invalid_args;
    if (p_v != .string) return error.invalid_args;
    const path = try allocator.dupe(u8, p_v.string);
    errdefer allocator.free(path);
    const sha_v = obj.get("expected_sha256") orelse return error.invalid_args;
    if (sha_v != .string or sha_v.string.len != 64) return error.invalid_args;
    const sha = try allocator.dupe(u8, sha_v.string);
    return .{ .path = path, .expected_sha256 = sha };
}

fn handleVerify(
    _: *Handler,
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !dispatcher.Result {
    const args = parseVerifyArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer args.deinit(allocator);

    var expected: [32]u8 = undefined;
    decodeHex(args.expected_sha256, &expected) catch return HandlerError.invalid_args;

    const f = std.fs.cwd().openFile(args.path, .{}) catch {
        const payload = try allocator.dupe(u8, "{\"ok\":false,\"kind\":\"file_not_found\"}");
        return dispatcher.Result.ownedPayload(allocator, payload);
    };
    defer f.close();
    const stat = f.stat() catch return HandlerError.io_failed;
    if (stat.size > module_loader.MAX_MODULE_BYTES) {
        const payload = try allocator.dupe(u8, "{\"ok\":false,\"kind\":\"file_too_large\"}");
        return dispatcher.Result.ownedPayload(allocator, payload);
    }
    const buf = try allocator.alloc(u8, stat.size);
    defer allocator.free(buf);
    _ = f.readAll(buf) catch return HandlerError.io_failed;

    if (!module_loader.isValidWasmShape(buf)) {
        const payload = try allocator.dupe(u8, "{\"ok\":false,\"kind\":\"not_wasm\"}");
        return dispatcher.Result.ownedPayload(allocator, payload);
    }
    const actual = module_loader.computeSha256(buf);
    if (!std.mem.eql(u8, &actual, &expected)) {
        const payload = try allocator.dupe(u8, "{\"ok\":false,\"kind\":\"hash_mismatch\"}");
        return dispatcher.Result.ownedPayload(allocator, payload);
    }
    const payload = try allocator.dupe(u8, "{\"ok\":true}");
    return dispatcher.Result.ownedPayload(allocator, payload);
}

// ─────────────────────────────────────────────────────────────────────
// list
// ─────────────────────────────────────────────────────────────────────

fn handleList(self: *Handler, allocator: std.mem.Allocator) !dispatcher.Result {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"modules\":[");
    if (self.manager) |mgr| {
        for (mgr.list(), 0..) |inst, i| {
            if (i != 0) try buf.append(allocator, ',');
            var hex: [64]u8 = undefined;
            const charset = "0123456789abcdef";
            for (inst.loaded.sha256, 0..) |b, j| {
                hex[j * 2] = charset[(b >> 4) & 0xf];
                hex[j * 2 + 1] = charset[b & 0xf];
            }
            try buf.appendSlice(allocator, "{\"name\":");
            try writeJsonString(allocator, &buf, inst.name);
            try buf.appendSlice(allocator, ",\"state\":");
            try writeJsonString(allocator, &buf, stateLabel(inst.state));
            try buf.print(allocator, ",\"sha256\":\"{s}\",\"path\":", .{hex});
            try writeJsonString(allocator, &buf, inst.loaded.path);
            try buf.print(allocator, ",\"restart_count\":{d}}}", .{inst.restart_count});
        }
    }
    try buf.appendSlice(allocator, "]}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn stateLabel(s: instance_manager.ModuleState) []const u8 {
    return switch (s) {
        .LOADED => "LOADED",
        .RUNNING => "RUNNING",
        .STOPPED => "STOPPED",
        .CRASHED => "CRASHED",
    };
}

// ─────────────────────────────────────────────────────────────────────
// register / unregister
// ─────────────────────────────────────────────────────────────────────

const RegisterArgs = struct {
    name: []u8,
    path: []u8,
    expected_sha256: []u8,

    fn deinit(self: RegisterArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.path);
        allocator.free(self.expected_sha256);
    }
};

fn parseRegisterArgs(allocator: std.mem.Allocator, args_json: []const u8) !RegisterArgs {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const n_v = obj.get("name") orelse return error.invalid_args;
    if (n_v != .string or n_v.string.len == 0) return error.invalid_args;
    const name = try allocator.dupe(u8, n_v.string);
    errdefer allocator.free(name);
    const p_v = obj.get("path") orelse return error.invalid_args;
    if (p_v != .string) return error.invalid_args;
    const path = try allocator.dupe(u8, p_v.string);
    errdefer allocator.free(path);
    const sha_v = obj.get("expected_sha256") orelse return error.invalid_args;
    if (sha_v != .string or sha_v.string.len != 64) return error.invalid_args;
    const sha = try allocator.dupe(u8, sha_v.string);
    return .{ .name = name, .path = path, .expected_sha256 = sha };
}

fn handleRegister(_: *Handler, _: std.mem.Allocator, _: []const u8) !dispatcher.Result {
    // Phase 2 MVP — see module header note.  Register requires the
    // handler to own a pin-stable list of LoadedModules so the
    // InstanceManager's borrowed pointers stay valid; that wiring
    // lands alongside D-O7's hot-reload story.  Until then this
    // surface is reserved.
    return HandlerError.not_yet_implemented;
}

const UnregisterArgs = struct {
    name: []u8,
};

fn parseUnregisterArgs(allocator: std.mem.Allocator, args_json: []const u8) !UnregisterArgs {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const n_v = obj.get("name") orelse return error.invalid_args;
    if (n_v != .string or n_v.string.len == 0) return error.invalid_args;
    return .{ .name = try allocator.dupe(u8, n_v.string) };
}

fn handleUnregister(_: *Handler, _: std.mem.Allocator, _: []const u8) !dispatcher.Result {
    // Phase 2 MVP — see module header note + handleRegister.
    return HandlerError.not_yet_implemented;
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

fn parsePathArg(allocator: std.mem.Allocator, args_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const v = obj.get("path") orelse return error.invalid_args;
    if (v != .string) return error.invalid_args;
    return try allocator.dupe(u8, v.string);
}

fn decodeHex(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return error.bad_length;
    for (0..out.len) |i| {
        const hi = try nibble(hex[i * 2]);
        const lo = try nibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
}

fn nibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => error.bad_hex,
    };
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

```
