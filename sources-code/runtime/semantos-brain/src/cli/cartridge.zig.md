---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/cartridge.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.287476+00:00
---

# runtime/semantos-brain/src/cli/cartridge.zig

```zig
// Wave 9 follow-up — `brain cartridge <subcmd>` dispatcher.
//
// `brain cartridge new <name> [--target <dir>] [--from-last]
//                              [--from-trace <file>]
//                              [--input <FixtureName>]`
//
// Shells out to `tools/cartridge-scaffold/bin/scaffold.ts` after
// resolving `--from-last` into the brain's canonical last-trace path
// (~/.semantos/intent/last-trace.jsonl by default). The scaffold tool
// generates a working cartridge skeleton with RM-096 typed cells +
// an RM-094 regression-test fixture.
//
// Substrate's no-AI rule extends here — no template-completion LLM,
// no inferred names. The author supplies the kebab-case name; the
// scaffold lays down deterministic files.

const std = @import("std");
const cli_common = @import("common.zig");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;

fn intentDir(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "BRAIN_INTENT_DIR")) |v| return v else |_| {}
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch
        return allocator.dupe(u8, ".semantos/intent");
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, ".semantos", "intent" });
}

fn lastTracePath(allocator: std.mem.Allocator) ![]u8 {
    const dir = try intentDir(allocator);
    defer allocator.free(dir);
    return std.fs.path.join(allocator, &.{ dir, "last-trace.jsonl" });
}

pub fn cmdCartridge(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print(
            \\usage: brain cartridge <subcmd> [args...]
            \\
            \\  new <name> [--target <dir>] [--from-last | --from-trace <file>]
            \\             [--input <FixtureName>]
            \\
            \\Scaffolds a typed-cell cartridge skeleton.
            \\
            \\  --from-last        embed the brain's most recent captured trace.
            \\  --from-trace <f>   embed the trace at <f> (or `-` for stdin).
            \\  --input <name>     reducer fixture to assert against
            \\                     (default T1_REPORT_DRIPPING_TAP).
            \\
        , .{});
        return .bad_args;
    }
    const sub = args[0];
    if (std.mem.eql(u8, sub, "new")) return cmdCartridgeNew(allocator, out, args[1..]);

    try out.print("brain cartridge: unknown subcmd '{s}'\n", .{sub});
    return .bad_args;
}

fn cmdCartridgeNew(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain cartridge new <name> [...]\n", .{});
        return .bad_args;
    }

    var argv = std.ArrayList([]const u8){};
    defer argv.deinit(allocator);
    try argv.append(allocator, "bun");
    try argv.append(allocator, "run");
    try argv.append(allocator, "tools/cartridge-scaffold/bin/scaffold.ts");
    try argv.append(allocator, "new");

    var last_resolved: ?[]u8 = null;
    defer if (last_resolved) |p| allocator.free(p);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--from-last")) {
            if (last_resolved == null) {
                last_resolved = resolveLastTrace(allocator) catch |err| {
                    try out.print("brain cartridge new: --from-last requested but no captured trace found ({s})\n", .{@errorName(err)});
                    return .file_io;
                };
            }
            try argv.append(allocator, "--from-trace");
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
        try out.print("brain cartridge new: failed to spawn bun: {s}\n", .{@errorName(err)});
        return .file_io;
    };
    switch (term) {
        .Exited => |code| if (code == 0) return .ok else return .file_io,
        else => return .file_io,
    }
}

fn resolveLastTrace(allocator: std.mem.Allocator) ![]u8 {
    const last_path = try lastTracePath(allocator);
    defer allocator.free(last_path);
    const f = std.fs.cwd().openFile(last_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.NoLastTrace,
        else => return err,
    };
    defer f.close();
    const reader = f.deprecatedReader();
    var buf: [4096]u8 = undefined;
    const n = try reader.read(&buf);
    const trimmed = std.mem.trim(u8, buf[0..n], &std.ascii.whitespace);
    return allocator.dupe(u8, trimmed);
}

```
