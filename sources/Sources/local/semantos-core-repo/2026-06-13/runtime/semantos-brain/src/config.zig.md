---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/config.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.251996+00:00
---

# runtime/semantos-brain/src/config.zig

```zig
// Phase Brain 1 — Configuration loader.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 1 deliverable 4).
//
// Schema (the spec calls for TOML; v0.1 ships JSON to avoid a third-party
// TOML parser dependency. The on-disk shape is identical between formats —
// a TOML port can land in Brain 1.5 without breaking config consumers):
//
//     {
//       "shell": {
//         "data_dir":     "/var/lib/semantos",
//         "modules_dir":  "/usr/share/semantos/wasm"
//       },
//       "modules": {
//         "wallet-engine": {
//           "path":        "wallet-engine.wasm",
//           "sha256":      "c091c3...",
//           "max_memory_bytes": 134217728
//         },
//         "headers-verifier": {
//           "path":        "headers-verifier.wasm",
//           "sha256":      "bf4e...c2a1",
//           "max_memory_bytes": 268435456
//         }
//       }
//     }
//
// The hash field is a hex string of the expected SHA-256. Brain 1 enforces
// hash-pinning at module load — any byte mismatch refuses to start.
//
// The module's name (the JSON object key) is the canonical identifier the
// shell uses everywhere — REPL command output, audit log, status display.

const std = @import("std");

pub const ConfigError = error{
    parse_failed,
    schema_mismatch,
    bad_hex,
    out_of_memory,
};

pub const ModuleConfig = struct {
    /// Canonical module name (JSON object key — caller dupes if it needs
    /// to outlive the parent allocator).
    name: []const u8,
    /// Path to the WASM file, relative to `shell.modules_dir` (or absolute).
    path: []const u8,
    /// 32-byte expected SHA-256 of the WASM bytes.
    sha256: [32]u8,
    /// Max linear memory the module is allowed to allocate. Brain 2 enforces
    /// this via wasmtime config; Brain 1 just records it.
    max_memory_bytes: u64,
};

pub const ShellConfig = struct {
    data_dir: []const u8,
    modules_dir: []const u8,
};

pub const Config = struct {
    shell: ShellConfig,
    modules: []ModuleConfig,
    /// Backing arena owned by the parser — Config + every string slice it
    /// holds is freed when this is deinited.
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *Config) void {
        self.arena.deinit();
    }

    /// Look up a module by name. O(N) — N is small.
    pub fn moduleByName(self: *const Config, name: []const u8) ?*const ModuleConfig {
        for (self.modules) |*m| {
            if (std.mem.eql(u8, m.name, name)) return m;
        }
        return null;
    }
};

/// Parse a config from raw JSON bytes. Caller owns the returned `Config`
/// (must call `deinit`).
pub fn parseJson(parent_allocator: std.mem.Allocator, json: []const u8) ConfigError!Config {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();

    const parsed = std.json.parseFromSliceLeaky(std.json.Value, allocator, json, .{}) catch {
        return error.parse_failed;
    };

    if (parsed != .object) return error.schema_mismatch;
    const root = parsed.object;

    // shell.{data_dir, modules_dir}
    const shell_v = root.get("shell") orelse return error.schema_mismatch;
    if (shell_v != .object) return error.schema_mismatch;
    const shell_obj = shell_v.object;

    const data_dir_v = shell_obj.get("data_dir") orelse return error.schema_mismatch;
    const modules_dir_v = shell_obj.get("modules_dir") orelse return error.schema_mismatch;
    if (data_dir_v != .string or modules_dir_v != .string) return error.schema_mismatch;

    const shell_cfg: ShellConfig = .{
        .data_dir = expandTilde(allocator, data_dir_v.string) catch return error.out_of_memory,
        .modules_dir = expandTilde(allocator, modules_dir_v.string) catch return error.out_of_memory,
    };

    // modules.{<name>: {path, sha256, max_memory_bytes}}
    const modules_v = root.get("modules") orelse return error.schema_mismatch;
    if (modules_v != .object) return error.schema_mismatch;
    const modules_obj = modules_v.object;

    var module_list = std.ArrayList(ModuleConfig){};
    var it = modules_obj.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        const m_v = entry.value_ptr.*;
        if (m_v != .object) return error.schema_mismatch;
        const m_obj = m_v.object;

        const path_v = m_obj.get("path") orelse return error.schema_mismatch;
        const sha_v = m_obj.get("sha256") orelse return error.schema_mismatch;
        const mem_v = m_obj.get("max_memory_bytes") orelse return error.schema_mismatch;
        if (path_v != .string or sha_v != .string or mem_v != .integer) return error.schema_mismatch;

        const sha_hex = sha_v.string;
        if (sha_hex.len != 64) return error.bad_hex;
        var sha_bytes: [32]u8 = undefined;
        decodeHex(sha_hex, &sha_bytes) catch return error.bad_hex;

        const mem_bytes = std.math.cast(u64, mem_v.integer) orelse return error.schema_mismatch;

        const m: ModuleConfig = .{
            .name = allocator.dupe(u8, name) catch return error.out_of_memory,
            .path = allocator.dupe(u8, path_v.string) catch return error.out_of_memory,
            .sha256 = sha_bytes,
            .max_memory_bytes = mem_bytes,
        };
        module_list.append(allocator, m) catch return error.out_of_memory;
    }
    const modules_slice = module_list.toOwnedSlice(allocator) catch return error.out_of_memory;

    return .{
        .shell = shell_cfg,
        .modules = modules_slice,
        .arena = arena,
    };
}

/// Read + parse a config file from disk.
pub fn loadFromPath(parent_allocator: std.mem.Allocator, path: []const u8) !Config {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    if (stat.size > 1024 * 1024) return error.parse_failed; // 1MB sanity cap
    const buf = try parent_allocator.alloc(u8, stat.size);
    defer parent_allocator.free(buf);
    _ = try file.readAll(buf);
    return parseJson(parent_allocator, buf);
}

/// Expand a leading `~` or `~/` to the value of `$HOME`.
/// Returns a freshly-allocated copy.  If `HOME` is unset the raw string is
/// returned unchanged.  Non-home-relative `~user` forms are passed through.
fn expandTilde(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (raw.len == 0 or raw[0] != '~') return allocator.dupe(u8, raw);
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
        return allocator.dupe(u8, raw); // $HOME unset — leave as-is
    };
    defer allocator.free(home);
    if (raw.len == 1) return allocator.dupe(u8, home);
    if (raw[1] == '/') return std.fs.path.join(allocator, &.{ home, raw[2..] });
    return allocator.dupe(u8, raw); // ~user form — pass through
}

/// Build the default config payload an operator gets after `brain init`.
/// Hashes are zeroed at init — operator runs `brain hash <module>` once
/// they've placed the WASM files, then pastes the result back into the
/// config to enable startup. This is intentional friction: the trust
/// anchor is something the operator deliberately writes, not something
/// the binary picks up implicitly.
pub fn defaultJsonTemplate(allocator: std.mem.Allocator) ![]u8 {
    // "modules" is empty by default — WASM module files are not bundled
    // in the source tree.  Add entries once you have the .wasm files:
    //
    //   "wallet-engine": {
    //     "path":             "wallet-engine.wasm",
    //     "sha256":           "<run `brain hash wallet-engine.wasm`>",
    //     "max_memory_bytes": 134217728
    //   }
    //
    // Place the wasm files in modules_dir, run `brain hash <file>` to get
    // the sha256, paste it in, then `brain start` will verify + load them.
    const template =
        \\{
        \\  "shell": {
        \\    "data_dir":    "~/.semantos/data",
        \\    "modules_dir": "~/.semantos/wasm"
        \\  },
        \\  "modules": {}
        \\}
        \\
    ;
    return allocator.dupe(u8, template);
}

// ──────────────────────────────────────────────────────────────────────
// Hex helpers
// ──────────────────────────────────────────────────────────────────────

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

pub fn encodeHex(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, bytes.len * 2);
    const charset = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2 + 0] = charset[(b >> 4) & 0xf];
        out[i * 2 + 1] = charset[b & 0xf];
    }
    return out;
}

// ─────────────────────────────────────────────────────────────────────
// D-O5m.followup-9 Phase B — push notification configuration.
//
// `PushConfig` is OPTIONAL — brain runs without push configured (cli
// emits "push not configured" once at boot when both apns and fcm are
// null).  Apns/Fcm sub-configs mirror the dispatcher constructors;
// they are intentionally narrow so the operator can write the .toml
// once and never edit the Zig source.
//
// On-disk shape — `<data_dir>/push-config.json`:
//
//   {
//     "apns": {
//       "bundle_id":   "com.semantos.oddjobz",
//       "key_id":      "ABCDE12345",
//       "team_id":     "TEAM12345Z",
//       "p8_key_path": "<data_dir>/AuthKey_ABCDE12345.p8",
//       "environment": "production"   // or "development"
//     },
//     "fcm": {
//       "project_id":                 "semantos-oddjobz-prod",
//       "service_account_json_path":  "<data_dir>/firebase-sa.json"
//     }
//   }
//
// Either key may be omitted to disable that platform.  An empty
// JSON object disables both — brain logs the "not configured" line at
// boot and leaves the helm_event_broker without a push hook.
//
// Tenant-manifest integration: a future PR can mirror these fields
// onto a `[push]` block in the tenant TOML.  Phase B ships the JSON
// file path only — operators with multiple tenants per host
// duplicate the file per data_dir.
// ─────────────────────────────────────────────────────────────────────

pub const PushApnsConfig = struct {
    bundle_id: []const u8,
    key_id: []const u8,
    team_id: []const u8,
    p8_key_path: []const u8,
    /// "development" or "production"; defaults to "production".
    environment: []const u8 = "production",
};

pub const PushFcmConfig = struct {
    project_id: []const u8,
    service_account_json_path: []const u8,
};

pub const PushConfig = struct {
    apns: ?PushApnsConfig = null,
    fcm: ?PushFcmConfig = null,
    /// Backing arena; freed in `deinit`.
    arena: ?std.heap.ArenaAllocator = null,

    pub fn deinit(self: *PushConfig) void {
        if (self.arena) |*a| a.deinit();
        self.arena = null;
    }

    /// True when neither dispatcher is configured — caller should
    /// log "push not configured" and skip wiring the broker hook.
    pub fn isEmpty(self: *const PushConfig) bool {
        return self.apns == null and self.fcm == null;
    }
};

pub const LoadPushError = error{
    parse_failed,
    schema_mismatch,
    out_of_memory,
};

/// Parse a `push-config.json` blob.  Returns an empty PushConfig
/// (both fields null) when the JSON is `{}`.
pub fn parsePushJson(parent_allocator: std.mem.Allocator, json: []const u8) LoadPushError!PushConfig {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();

    const parsed = std.json.parseFromSliceLeaky(std.json.Value, allocator, json, .{}) catch
        return LoadPushError.parse_failed;
    if (parsed != .object) return LoadPushError.schema_mismatch;
    const root = parsed.object;

    var cfg = PushConfig{ .arena = arena };

    if (root.get("apns")) |a_v| {
        if (a_v != .object) return LoadPushError.schema_mismatch;
        const a = a_v.object;
        const bundle = a.get("bundle_id") orelse return LoadPushError.schema_mismatch;
        const kid = a.get("key_id") orelse return LoadPushError.schema_mismatch;
        const tid = a.get("team_id") orelse return LoadPushError.schema_mismatch;
        const p8p = a.get("p8_key_path") orelse return LoadPushError.schema_mismatch;
        if (bundle != .string or kid != .string or tid != .string or p8p != .string)
            return LoadPushError.schema_mismatch;
        const env = if (a.get("environment")) |v| (if (v == .string) v.string else return LoadPushError.schema_mismatch) else "production";
        cfg.apns = .{
            .bundle_id = allocator.dupe(u8, bundle.string) catch return LoadPushError.out_of_memory,
            .key_id = allocator.dupe(u8, kid.string) catch return LoadPushError.out_of_memory,
            .team_id = allocator.dupe(u8, tid.string) catch return LoadPushError.out_of_memory,
            .p8_key_path = allocator.dupe(u8, p8p.string) catch return LoadPushError.out_of_memory,
            .environment = allocator.dupe(u8, env) catch return LoadPushError.out_of_memory,
        };
    }
    if (root.get("fcm")) |f_v| {
        if (f_v != .object) return LoadPushError.schema_mismatch;
        const f = f_v.object;
        const pid = f.get("project_id") orelse return LoadPushError.schema_mismatch;
        const sap = f.get("service_account_json_path") orelse return LoadPushError.schema_mismatch;
        if (pid != .string or sap != .string) return LoadPushError.schema_mismatch;
        cfg.fcm = .{
            .project_id = allocator.dupe(u8, pid.string) catch return LoadPushError.out_of_memory,
            .service_account_json_path = allocator.dupe(u8, sap.string) catch return LoadPushError.out_of_memory,
        };
    }
    return cfg;
}

/// Read + parse `<data_dir>/push-config.json`.  Returns an empty
/// PushConfig when the file is missing — the cli treats that as the
/// "push not configured" path.
pub fn loadPushConfig(parent_allocator: std.mem.Allocator, data_dir: []const u8) !PushConfig {
    const path = try std.fs.path.join(parent_allocator, &.{ data_dir, "push-config.json" });
    defer parent_allocator.free(path);
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return PushConfig{},
        else => return err,
    };
    defer file.close();
    const stat = try file.stat();
    if (stat.size > 64 * 1024) return error.parse_failed;
    const buf = try parent_allocator.alloc(u8, stat.size);
    defer parent_allocator.free(buf);
    _ = try file.readAll(buf);
    return parsePushJson(parent_allocator, buf);
}

// ── Push-config tests ──

test "parsePushJson handles fully-configured shape" {
    const allocator = std.testing.allocator;
    const json =
        \\{
        \\  "apns": {
        \\    "bundle_id":"com.test.app",
        \\    "key_id":"ABCDE12345",
        \\    "team_id":"TEAMxxxxxx",
        \\    "p8_key_path":"/tmp/key.p8",
        \\    "environment":"development"
        \\  },
        \\  "fcm": {
        \\    "project_id":"test-proj",
        \\    "service_account_json_path":"/tmp/sa.json"
        \\  }
        \\}
    ;
    var cfg = try parsePushJson(allocator, json);
    defer cfg.deinit();
    try std.testing.expect(cfg.apns != null);
    try std.testing.expect(cfg.fcm != null);
    try std.testing.expectEqualStrings("com.test.app", cfg.apns.?.bundle_id);
    try std.testing.expectEqualStrings("development", cfg.apns.?.environment);
    try std.testing.expectEqualStrings("test-proj", cfg.fcm.?.project_id);
}

test "parsePushJson treats {} as empty" {
    const allocator = std.testing.allocator;
    var cfg = try parsePushJson(allocator, "{}");
    defer cfg.deinit();
    try std.testing.expect(cfg.isEmpty());
}

test "parsePushJson missing required apns field surfaces schema_mismatch" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        LoadPushError.schema_mismatch,
        parsePushJson(allocator, "{\"apns\":{\"bundle_id\":\"x\"}}"),
    );
}

```
