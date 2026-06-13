---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/common.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.286156+00:00
---

# runtime/semantos-brain/src/cli/common.zig

```zig
// CLI helpers shared across every cmd cluster — extracted from the
// original monolithic src/cli.zig as Move 1 of the cli-modularize
// refactor.  Pure code motion: no behaviour change.  src/cli.zig
// re-exports each symbol so external callers (main.zig, tests/*.zig)
// continue to reach them as `cli.Output`, `cli.ExitCode`, etc.

const std = @import("std");
const config = @import("config");
const wire = @import("wire");

pub const ExitCode = enum(u8) {
    ok = 0,
    bad_args = 2,
    config_error = 10,
    hash_mismatch = 11,
    file_io = 12,
    oom = 13,
    not_yet_implemented = 70,
};

/// Buffers into a slice — stderr/stdout in the binary, or a captured ArrayList
/// in tests. C4 PR-R1: moved to the std-only `repl_output` leaf so the cli +
/// repl layers share ONE nominal writer type (needed for the ReplVerbRegistry's
/// runtime fn-pointers). Re-exported so `cli.Output` callers are unchanged.
pub const Output = @import("repl_output").Output;

pub fn flushOutput(out: *const Output) void {
    const stdout = std.fs.File.stdout();
    _ = stdout.write(out.buffer.items) catch {};
    out.buffer.clearRetainingCapacity();
}

pub fn resolveDataDir(allocator: std.mem.Allocator) ![]u8 {
    // Precedence:
    //   1. $BRAIN_DATA_DIR (operator-supplied env override)
    //   2. shell.data_dir from <home>/.semantos/config.json (if present)
    //   3. <home>/.semantos
    //   4. relative ".semantos" if HOME is unset
    //
    // Pre-fix this only honoured #1 and #3, so an operator who set
    // shell.data_dir = "~/.semantos/data" in config.json would see brain
    // SAY it was reading config but write certs/audit/jobs to
    // ~/.semantos anyway.  The smoke test ran into this — different
    // commands diverged on which dir they used.
    if (std.process.getEnvVarOwned(allocator, "BRAIN_DATA_DIR")) |v| {
        return v;
    } else |_| {}
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch
        return allocator.dupe(u8, ".semantos");
    defer allocator.free(home);
    if (resolveDataDirFromConfig(allocator, home)) |from_cfg| {
        return from_cfg;
    } else |_| {}
    return std.fs.path.join(allocator, &.{ home, ".semantos" });
}

/// Best-effort: open `<home>/.semantos/config.json` and return the
/// resolved `shell.data_dir` field if present.  `~` at the start of
/// the value is expanded to `<home>`.  Returns an error on any failure
/// (file missing, parse error, field missing) — the caller falls back
/// to the legacy `<home>/.semantos` default.
/// Public for conformance testing.
pub fn resolveDataDirFromConfig(allocator: std.mem.Allocator, home: []const u8) ![]u8 {
    const cfg_path = try std.fs.path.join(allocator, &.{ home, ".semantos", "config.json" });
    defer allocator.free(cfg_path);
    var cfg = try config.loadFromPath(allocator, cfg_path);
    defer cfg.deinit();
    const raw = cfg.shell.data_dir;
    if (raw.len == 0) return error.empty;
    return expandHome(allocator, raw, home);
}

/// Expand a leading `~` or `~/` to `<home>`.  Other usages of `~`
/// are not touched.  Caller owns the returned slice.
/// Public for conformance testing.
pub fn expandHome(allocator: std.mem.Allocator, raw: []const u8, home: []const u8) ![]u8 {
    if (raw.len == 0) return allocator.dupe(u8, raw);
    if (raw[0] != '~') return allocator.dupe(u8, raw);
    if (raw.len == 1) return allocator.dupe(u8, home);
    if (raw[1] == '/') {
        return std.fs.path.join(allocator, &.{ home, raw[2..] });
    }
    // `~user/...` form is intentionally NOT supported — operators
    // either use `~/...` (their own home) or an absolute path.  Pass
    // through unchanged so the operator sees it on disk.
    return allocator.dupe(u8, raw);
}

pub fn jsonStringField(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.bad_json;
    const v = parsed.value.object.get(key) orelse return error.missing_key;
    if (v != .string) return error.wrong_type;
    return try allocator.dupe(u8, v.string);
}

pub fn jsonIntField(allocator: std.mem.Allocator, json: []const u8, key: []const u8) !i64 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.bad_json;
    const v = parsed.value.object.get(key) orelse return error.missing_key;
    if (v != .integer) return error.wrong_type;
    return v.integer;
}

/// Wall-clock seconds since the Unix epoch.  Used by every cli sub-cluster
/// that opens a TokenStore / CertStore / view-store — they take a clock
/// function pointer so the embedded path can be unit-tested against a
/// frozen clock without touching production code.
pub fn realClock() i64 {
    return std.time.timestamp();
}

/// Aliases the wire-protocol's ErrorBody so the cli-side socket-dispatch
/// helpers can name it without re-importing `wire` directly.
pub const WireErrorBody = wire.ErrorBody;

/// Generic — daemon error body (from a Unix-socket response envelope) →
/// typed Zig error.  Used by every cli cluster that talks to the daemon
/// via the socket dispatcher (`dispatchBearer` / `dispatchDevice` /
/// `dispatchSites` / etc.).  Returns the error variant directly; the
/// caller's outcome type (BearerOutcome / DeviceOutcome / …) just
/// propagates it through `try`.
pub fn daemonErrorAsZigError(e: WireErrorBody) anyerror {
    return switch (e.kind) {
        .capability_denied => error.daemon_capability_denied,
        .unknown_resource, .unknown_command => error.daemon_protocol_error,
        .validation_failed => error.daemon_validation_failed,
        .not_implemented => error.daemon_not_implemented,
    };
}

```
