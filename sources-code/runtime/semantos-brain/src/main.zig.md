---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/main.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.221427+00:00
---

# runtime/semantos-brain/src/main.zig

```zig
// Phase Brain 1 — brain binary entry point.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 1 deliverable 5).
//
// Thin argv → cli dispatcher. Most logic lives in cli.zig so it's
// directly unit-testable; main.zig handles only argv parsing, exit-code
// translation, and stdout/stderr writers.

const std = @import("std");
const cli = @import("cli");
const module_loader = @import("module_loader");

const DEFAULT_CONFIG_REL = ".semantos/config.json";

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var stdout_buf = std.ArrayList(u8){};
    defer stdout_buf.deinit(allocator);
    const out: cli.Output = .{ .buffer = &stdout_buf, .allocator = allocator };

    const code = try dispatch(allocator, &out, args);

    // Flush captured output to stdout.
    const stdout = std.fs.File.stdout();
    _ = stdout.write(stdout_buf.items) catch {};
    return @intFromEnum(code);
}

fn dispatch(
    allocator: std.mem.Allocator,
    out: *const cli.Output,
    args: [][:0]u8,
) !cli.ExitCode {
    if (args.len < 2) {
        try out.print("{s}", .{cli.HELP_TEXT});
        return .bad_args;
    }
    // Treat `brain <subcmd> --help` / `brain <subcmd> -h` as `brain help`.
    for (args[2..]) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            return try cli.cmdHelp(out);
        }
    }
    const cmd = cli.parseCommand(args[1]) orelse {
        try out.print("unknown command: {s}\n\n{s}", .{ args[1], cli.HELP_TEXT });
        return .bad_args;
    };
    return switch (cmd) {
        .help => try cli.cmdHelp(out),
        .version => try cli.cmdVersion(out),
        .init => blk: {
            const path = try resolveConfigPath(allocator, args[2..]);
            defer allocator.free(path);
            break :blk try cli.cmdInit(allocator, out, path);
        },
        .status => blk: {
            const path = try resolveConfigPath(allocator, args[2..]);
            defer allocator.free(path);
            break :blk try cli.cmdStatus(allocator, out, path);
        },
        .hash => blk: {
            if (args.len < 3) {
                try out.print("usage: brain hash <wasm_file>\n", .{});
                break :blk cli.ExitCode.bad_args;
            }
            break :blk try cli.cmdHash(allocator, out, args[2]);
        },
        .start => blk: {
            const path = try resolveConfigPath(allocator, args[2..]);
            defer allocator.free(path);
            break :blk try cli.cmdStart(allocator, out, path, args[2..]);
        },
        .stop => try cli.cmdStop(out),
        .repl => blk: {
            const path = try resolveConfigPath(allocator, args[2..]);
            defer allocator.free(path);
            break :blk try cli.cmdRepl(allocator, out, path, args[2..]);
        },
        .site => try cli.cmdSite(allocator, out, args[2..]),
        .serve => try cli.cmdServe(allocator, out, args[2..]),
        .revenue => try cli.cmdRevenue(allocator, out, args[2..]),
        .sweep => try cli.cmdSweep(allocator, out, args[2..]),
        .outputs => try cli.cmdOutputs(allocator, out, args[2..]),
        .sessions => try cli.cmdSessions(allocator, out, args[2..]),
        .refund => try cli.cmdRefund(allocator, out, args[2..]),
        .headers => try cli.cmdHeaders(allocator, out, args[2..]),
        .bearer => try cli.cmdBearer(allocator, out, args[2..]),
        .device => try cli.cmdDevice(allocator, out, args[2..]),
        .llm => try cli.cmdLlm(allocator, out, args[2..]),
        .@"provision-tenant" => try cli.cmdProvisionTenant(allocator, out, args[2..]),
        .extension => try cli.cmdExtension(allocator, out, args[2..]),
        .signer => try cli.cmdSigner(allocator, out, args[2..]),
        .@"resign-pending" => try cli.cmdResignPending(allocator, out, args[2..]),
        .@"export-operator" => try cli.cmdExportOperator(allocator, out, args[2..]),
        .@"exit-operator" => try cli.cmdExitOperator(allocator, out, args[2..]),
        .@"orphan-streams" => try cli.cmdOrphanStreams(allocator, out, args[2..]),
        .@"domain-allow" => try cli.cmdDomainAllow(allocator, out, args[2..]),
        .@"domain-disallow" => try cli.cmdDomainDisallow(allocator, out, args[2..]),
        .@"caddy-ask" => try cli.cmdCaddyAsk(allocator, out, args[2..]),
        .@"sni-map" => try cli.cmdSniMap(allocator, out, args[2..]),
        .@"wrapped-dek" => try cli.cmdWrappedDek(allocator, out, args[2..]),
        .@"site-preview" => try cli.cmdSitePreview(allocator, out, args[2..]),
        .@"site-publish" => try cli.cmdSitePublish(allocator, out, args[2..]),
        .intent => try cli.cmdIntent(allocator, out, args[2..]),
        .cartridge => try cli.cmdCartridge(allocator, out, args[2..]),
        .msg => try cli.cmdMsg(allocator, out, args[2..]),
    };
}

/// Parse `--config-path <path>` out of the trailing args; otherwise return
/// the default `~/.semantos/config.json`.
fn resolveConfigPath(allocator: std.mem.Allocator, args: []const [:0]u8) ![]u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--config-path") and i + 1 < args.len) {
            return allocator.dupe(u8, args[i + 1]);
        }
    }
    // Default: $HOME/.semantos/config.json.
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch
        return allocator.dupe(u8, DEFAULT_CONFIG_REL);
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, DEFAULT_CONFIG_REL });
}

```
