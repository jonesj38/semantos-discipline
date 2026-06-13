---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/intent.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.286548+00:00
---

# runtime/semantos-brain/src/cli/intent.zig

```zig
// Wave 9 follow-up — `brain intent <subcmd>` dispatcher.
//
// Wires the brain CLI into the TS intent-trace tools that landed in
// Wave 9 (RM-090..097). The brain doesn't reimplement the parser /
// renderer / fixturizer — those live in `tools/intent-trace/` as bun
// scripts. The brain provides:
//
//   1. A canonical *capture sink* — `brain intent capture <file>` tees
//      JSONL events from stdin to <file> AND to a "last trace" pointer
//      (~/.semantos/intent/last-trace.jsonl) so downstream verbs can
//      reach for "the most recent trace" without the operator naming
//      it.
//
//   2. Thin shims for `tail` / `cascade` / `show` / `fixturize` that
//      spawn the bun CLI with the right argv. The bun layer owns the
//      formatting; the brain layer owns the path resolution.
//
// Substrate's no-AI rule extends here — none of these verbs touch an
// LLM. The "AI" piece (mic → speech → JSONL trace) sits outside; the
// `capture` verb's contract is "read JSONL on stdin, persist it".
//
// Subprocess spawn pattern mirrors `cli/extension.zig::invokeTsShardPublish`.

const std = @import("std");
const cli_common = @import("common.zig");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;

/// Resolve the canonical intent-trace directory.
///   Precedence:
///     1. $BRAIN_INTENT_DIR
///     2. <data_dir>/intent
///     3. .semantos/intent (cwd fallback)
fn intentDir(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "BRAIN_INTENT_DIR")) |v| {
        return v;
    } else |_| {}
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch
        return allocator.dupe(u8, ".semantos/intent");
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, ".semantos", "intent" });
}

/// Path of the "most recent trace" pointer file.
fn lastTracePath(allocator: std.mem.Allocator) ![]u8 {
    const dir = try intentDir(allocator);
    defer allocator.free(dir);
    return std.fs.path.join(allocator, &.{ dir, "last-trace.jsonl" });
}

pub fn cmdIntent(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print(
            \\usage: brain intent <subcmd> [args...]
            \\
            \\  capture <file>                       Tee JSONL events from stdin → <file>
            \\                                       + the last-trace pointer.
            \\  tail [<file|->]                      Stream a one-line summary per event.
            \\  cascade <file|--last> [--flags]      Render the trace as an indented tree.
            \\  show <correlationId> <file|--last>   Render one correlation group.
            \\  fixturize [<file|--last>]            Emit a regression-test TS file.
            \\                                       --input <FixtureName> required.
            \\                                       --correlation <id> optional.
            \\
            \\Paths support "-" for stdin and "--last" to reference the most
            \\recent captured trace under $BRAIN_INTENT_DIR (default
            \\~/.semantos/intent/last-trace.jsonl).
            \\
        , .{});
        return .bad_args;
    }
    const sub = args[0];

    if (std.mem.eql(u8, sub, "capture")) return cmdIntentCapture(allocator, out, args[1..]);
    if (std.mem.eql(u8, sub, "tail")) return cmdIntentBunShim(allocator, out, "tail", args[1..]);
    if (std.mem.eql(u8, sub, "cascade")) return cmdIntentBunShim(allocator, out, "cascade", args[1..]);
    if (std.mem.eql(u8, sub, "show")) return cmdIntentBunShim(allocator, out, "show", args[1..]);
    if (std.mem.eql(u8, sub, "fixturize")) return cmdIntentBunShim(allocator, out, "fixturize", args[1..]);

    try out.print("brain intent: unknown subcmd '{s}'\n", .{sub});
    return .bad_args;
}

/// Tee stdin JSONL → <file> + last-trace pointer. Idempotent on the
/// pointer; the pointer is overwritten atomically via rename.
fn cmdIntentCapture(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain intent capture <file>\n", .{});
        return .bad_args;
    }
    const out_path = args[0];

    // Ensure the intent dir + parent of <file> exist.
    const dir = try intentDir(allocator);
    defer allocator.free(dir);
    std.fs.cwd().makePath(dir) catch {};

    if (std.fs.path.dirname(out_path)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }

    var file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer file.close();

    const stdin = std.fs.File.stdin();
    var buf: [4096]u8 = undefined;
    var written: usize = 0;
    while (true) {
        const n = try stdin.read(&buf);
        if (n == 0) break;
        try file.writeAll(buf[0..n]);
        written += n;
    }

    // Update last-trace pointer — atomic rename via a sibling temp file.
    const last_path = try lastTracePath(allocator);
    defer allocator.free(last_path);
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{last_path});
    defer allocator.free(tmp_path);
    {
        var tmp_file = try std.fs.cwd().createFile(tmp_path, .{ .truncate = true });
        defer tmp_file.close();
        try tmp_file.writeAll(out_path);
    }
    try std.fs.cwd().rename(tmp_path, last_path);

    try out.print("captured {d} bytes → {s}\n", .{ written, out_path });
    try out.print("last-trace pointer: {s}\n", .{last_path});
    return .ok;
}

/// Generic shim — spawn `bun run tools/intent-trace/src/cli.ts <verb> <args>`.
/// Translates `--last` into the resolved last-trace path so the bun
/// layer doesn't need to know about brain's pointer convention.
fn cmdIntentBunShim(
    allocator: std.mem.Allocator,
    out: *const Output,
    verb: []const u8,
    args: []const [:0]u8,
) !ExitCode {
    var argv = std.ArrayList([]const u8){};
    defer argv.deinit(allocator);
    try argv.append(allocator, "bun");
    try argv.append(allocator, "run");
    try argv.append(allocator, "tools/intent-trace/src/cli.ts");
    try argv.append(allocator, verb);

    // Substitute --last with the resolved last-trace path; pass every
    // other arg through verbatim.
    var last_resolved: ?[]u8 = null;
    defer if (last_resolved) |p| allocator.free(p);

    for (args) |a| {
        if (std.mem.eql(u8, a, "--last")) {
            if (last_resolved == null) {
                last_resolved = try resolveLastTrace(allocator);
            }
            try argv.append(allocator, last_resolved.?);
        } else {
            try argv.append(allocator, a);
        }
    }

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = child.spawnAndWait() catch |err| {
        try out.print("brain intent {s}: failed to spawn bun: {s}\n", .{ verb, @errorName(err) });
        return .file_io;
    };
    switch (term) {
        .Exited => |code| {
            if (code == 0) return .ok;
            return .file_io;
        },
        else => return .file_io,
    }
}

/// Read the last-trace pointer and return the path it points to.
/// Returns a fresh allocation the caller owns.
fn resolveLastTrace(allocator: std.mem.Allocator) ![]u8 {
    const last_path = try lastTracePath(allocator);
    defer allocator.free(last_path);
    const f = std.fs.cwd().openFile(last_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.NoLastTrace,
        else => return err,
    };
    defer f.close();
    const reader = f.deprecatedReader();
    // Read up to 4KB — pointer is just a filesystem path.
    var buf: [4096]u8 = undefined;
    const n = try reader.read(&buf);
    const trimmed = std.mem.trim(u8, buf[0..n], &std.ascii.whitespace);
    return allocator.dupe(u8, trimmed);
}

```
