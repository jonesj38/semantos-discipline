---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/cli_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.192352+00:00
---

# runtime/semantos-brain/tests/cli_conformance.zig

```zig
// Phase Brain 1 — CLI dispatcher conformance tests.
//
// Drives `cli.cmd*` directly with captured output, so each subcommand's
// happy path + error path is asserted without spawning subprocesses.

const std = @import("std");
const cli = @import("cli");
const config = @import("config");
const module_loader = @import("module_loader");

fn newOutput(buf: *std.ArrayList(u8)) cli.Output {
    return .{ .buffer = buf, .allocator = std.testing.allocator };
}

fn tmpFilePath(name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return std.fs.path.join(allocator, &.{ real, name });
}

test "Brain 1 cli: parseCommand recognises every subcommand" {
    try std.testing.expectEqual(cli.Command.init, cli.parseCommand("init").?);
    try std.testing.expectEqual(cli.Command.status, cli.parseCommand("status").?);
    try std.testing.expectEqual(cli.Command.hash, cli.parseCommand("hash").?);
    try std.testing.expectEqual(cli.Command.start, cli.parseCommand("start").?);
    try std.testing.expectEqual(cli.Command.stop, cli.parseCommand("stop").?);
    try std.testing.expectEqual(cli.Command.help, cli.parseCommand("help").?);
    try std.testing.expectEqual(cli.Command.help, cli.parseCommand("--help").?);
    try std.testing.expectEqual(cli.Command.version, cli.parseCommand("version").?);
    // D-W1 Phase 1 Part 2 + Phase 1 follow-up — `brain device pair |
    // claim | list | revoke` are all first-class subcommands.
    try std.testing.expectEqual(cli.Command.device, cli.parseCommand("device").?);
    // Wave 9 follow-up — `brain intent <subcmd>` and `brain cartridge
    // new` shim the TS dogfood-loop tools.
    try std.testing.expectEqual(cli.Command.intent, cli.parseCommand("intent").?);
    try std.testing.expectEqual(cli.Command.cartridge, cli.parseCommand("cartridge").?);
    try std.testing.expect(cli.parseCommand("nonsense") == null);
}

test "Wave 9 cli: cmdIntent without args prints usage" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const code = try cli.cmdIntent(std.testing.allocator, &out, &.{});
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "capture") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "cascade") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "fixturize") != null);
}

test "Wave 9 cli: cmdIntent unknown subcmd returns bad_args" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const args = [_][:0]u8{@constCast("nope")};
    const code = try cli.cmdIntent(std.testing.allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "unknown subcmd 'nope'") != null);
}

test "Wave 9 cli: cmdCartridge without args prints usage" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const code = try cli.cmdCartridge(std.testing.allocator, &out, &.{});
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "new <name>") != null);
}

test "Wave 9 cli: cmdCartridge unknown subcmd returns bad_args" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const args = [_][:0]u8{@constCast("destroy")};
    const code = try cli.cmdCartridge(std.testing.allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "unknown subcmd 'destroy'") != null);
}

test "Wave 9 cli: cmdCartridge new without name prints usage" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const args = [_][:0]u8{@constCast("new")};
    const code = try cli.cmdCartridge(std.testing.allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "brain cartridge new <name>") != null);
}

test "D-W1 P1.2 cli: cmdDevice without args prints usage" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const code = try cli.cmdDevice(std.testing.allocator, &out, &.{});
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "pair|claim|list|revoke") != null);
}

test "D-W1 P1.followup cli: cmdDevice with unknown subcommand returns bad_args" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    // `pair` and `claim` are now first-class; use a genuinely
    // unknown subcommand to exercise the bad-args path.
    const args = [_][:0]u8{@constCast("nonexistent-verb")};
    const code = try cli.cmdDevice(std.testing.allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "unknown device subcommand") != null);
}

test "D-W1 P1.followup cli: cmdDevice pair without --device-name prints usage" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const args = [_][:0]u8{@constCast("pair")};
    const code = try cli.cmdDevice(std.testing.allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "--device-name") != null);
}

test "D-W1 P1.followup cli: cmdDevice claim without --token prints lab-fixture banner" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const args = [_][:0]u8{@constCast("claim")};
    const code = try cli.cmdDevice(std.testing.allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    // The lab-fixture banner must be visible — operators reaching
    // for `claim` need to know it's not the production path.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "LAB FIXTURE") != null);
}

test "D-W1 P1.2 cli: cmdHelp mentions the new `device` subcommand" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    _ = try cli.cmdHelp(&out);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "device") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "D-W1 P1.2") != null);
}

test "Brain 1 cli: cmdHelp emits the help banner" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const code = try cli.cmdHelp(&out);
    try std.testing.expectEqual(cli.ExitCode.ok, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "brain —") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "init") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "hash") != null);
}

test "Brain 1 cli: cmdVersion prints version" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const code = try cli.cmdVersion(&out);
    try std.testing.expectEqual(cli.ExitCode.ok, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, cli.VERSION) != null);
}

test "Brain 1 cli: init writes a default config and refuses to clobber" {
    const path = try tmpFilePath("brain-test-init.json", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    // Ensure no leftover from a prior run.
    std.fs.cwd().deleteFile(path) catch {};

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);

    const code1 = try cli.cmdInit(std.testing.allocator, &out, path);
    try std.testing.expectEqual(cli.ExitCode.ok, code1);

    // Re-run should refuse.
    buf.clearRetainingCapacity();
    const code2 = try cli.cmdInit(std.testing.allocator, &out, path);
    try std.testing.expectEqual(cli.ExitCode.config_error, code2);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "already exists") != null);

    // The written file parses cleanly.
    var cfg = try config.loadFromPath(std.testing.allocator, path);
    defer cfg.deinit();
    try std.testing.expectEqual(@as(usize, 0), cfg.modules.len);
    try std.testing.expect(cfg.moduleByName("wallet-engine") == null);
}

test "Brain 1 cli: hash prints SHA-256 of a WASM file" {
    const path = try tmpFilePath("brain-test-hash.wasm", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    {
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll(&module_loader.WASM_MAGIC);
    }

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);

    const code = try cli.cmdHash(std.testing.allocator, &out, path);
    try std.testing.expectEqual(cli.ExitCode.ok, code);

    const expected = module_loader.computeSha256(&module_loader.WASM_MAGIC);
    const expected_hex = try module_loader.formatHashHex(std.testing.allocator, &expected);
    defer std.testing.allocator.free(expected_hex);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, expected_hex) != null);
}

test "Brain 1 cli: status reports mismatch when file hash != config pin" {
    const cfg_path = try tmpFilePath("brain-test-status.json", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(cfg_path) catch {};
        std.testing.allocator.free(cfg_path);
    }
    const wasm_path = try tmpFilePath("brain-test-status.wasm", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(wasm_path) catch {};
        std.testing.allocator.free(wasm_path);
    }
    {
        const f = try std.fs.cwd().createFile(wasm_path, .{});
        defer f.close();
        try f.writeAll(&module_loader.WASM_MAGIC);
    }
    // Config pin is all-zeros; actual file hash won't match.
    const json = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "shell": {{ "data_dir": "/d", "modules_dir": "/m" }},
        \\  "modules": {{
        \\    "test-mod": {{
        \\      "path": "{s}",
        \\      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
        \\      "max_memory_bytes": 1024
        \\    }}
        \\  }}
        \\}}
    , .{wasm_path});
    defer std.testing.allocator.free(json);
    {
        const f = try std.fs.cwd().createFile(cfg_path, .{});
        defer f.close();
        try f.writeAll(json);
    }

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);

    const code = try cli.cmdStatus(std.testing.allocator, &out, cfg_path);
    try std.testing.expectEqual(cli.ExitCode.hash_mismatch, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "MISMATCH") != null);
}

test "Brain 1 cli: stop is a no-op stub" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const code = try cli.cmdStop(&out);
    try std.testing.expectEqual(cli.ExitCode.ok, code);
}

// ─────────────────────────────────────────────────────────────────────
// WSITE4.5 / WSITE4.6 — sweep + outputs surface tests
// ─────────────────────────────────────────────────────────────────────

test "WSITE4.6 cli: parseCommand recognises sweep + outputs" {
    try std.testing.expectEqual(cli.Command.sweep, cli.parseCommand("sweep").?);
    try std.testing.expectEqual(cli.Command.outputs, cli.parseCommand("outputs").?);
}

test "WSITE4.6 cli: outputs without domain prints usage" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const code = try cli.cmdOutputs(std.testing.allocator, &out, &.{});
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "usage:") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "outputs") != null);
}

// ─────────────────────────────────────────────────────────────────────
// WSITE5 — sessions / refund command surface
// ─────────────────────────────────────────────────────────────────────

test "WSITE5 cli: parseCommand recognises sessions + refund" {
    try std.testing.expectEqual(cli.Command.sessions, cli.parseCommand("sessions").?);
    try std.testing.expectEqual(cli.Command.refund, cli.parseCommand("refund").?);
}

test "WSITE5 cli: sessions without args prints usage" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const code = try cli.cmdSessions(std.testing.allocator, &out, &.{});
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "usage:") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "sessions") != null);
}

test "WSITE5 cli: refund with too few args prints usage" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const code = try cli.cmdRefund(std.testing.allocator, &out, &.{});
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "usage:") != null);
}

test "WSITE5 cli: refund with bad-length txid is rejected" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const args: [2][:0]u8 = .{
        @constCast("test.local"),
        @constCast("nottxid"),
    };
    const code = try cli.cmdRefund(std.testing.allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "64 hex") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Smoke-test pass #1, fix #7 — resolveDataDir honours
// shell.data_dir from <home>/.semantos/config.json with `~` expansion.
//
// Pre-fix the value was structurally dead code: every command derived
// data_dir from $HOME/.semantos regardless of what config.json said.
// ─────────────────────────────────────────────────────────────────────

test "smoke-fix #7 expandHome: leading tilde-slash expands to home" {
    const got = try cli.expandHome(std.testing.allocator, "~/foo/bar", "/Users/toddprice");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("/Users/toddprice/foo/bar", got);
}

test "smoke-fix #7 expandHome: bare tilde returns home" {
    const got = try cli.expandHome(std.testing.allocator, "~", "/home/op");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("/home/op", got);
}

test "smoke-fix #7 expandHome: absolute path passes through" {
    const got = try cli.expandHome(std.testing.allocator, "/var/lib/semantos", "/home/op");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("/var/lib/semantos", got);
}

test "smoke-fix #7 expandHome: tilde-user form passes through unchanged" {
    // We deliberately don't expand `~user/...` — operators use either
    // `~/` (their own home) or an absolute path.  The unchanged value
    // surfaces on disk so it's obvious what happened.
    const got = try cli.expandHome(std.testing.allocator, "~bob/x", "/home/op");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("~bob/x", got);
}

test "smoke-fix #7 resolveDataDirFromConfig: reads + expands tilde from on-disk config" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_real = try tmp.dir.realpath(".", &path_buf);
    const fake_home = try std.testing.allocator.dupe(u8, tmp_real);
    defer std.testing.allocator.free(fake_home);

    // Write <fake_home>/.semantos/config.json with shell.data_dir = "~/.semantos/data".
    // Config parsing expands `~` against the process HOME; the fake_home
    // argument only controls where this isolated config file is read from.
    try tmp.dir.makePath(".semantos");
    const cfg_payload =
        \\{
        \\  "shell": { "data_dir": "~/.semantos/data", "modules_dir": "~/.semantos/wasm" },
        \\  "modules": {}
        \\}
    ;
    const cfg_file = try tmp.dir.createFile(".semantos/config.json", .{});
    try cfg_file.writeAll(cfg_payload);
    cfg_file.close();

    const got = try cli.resolveDataDirFromConfig(std.testing.allocator, fake_home);
    defer std.testing.allocator.free(got);

    const actual_home = try std.process.getEnvVarOwned(std.testing.allocator, "HOME");
    defer std.testing.allocator.free(actual_home);
    var expect_buf: [std.fs.max_path_bytes]u8 = undefined;
    const expected = try std.fmt.bufPrint(&expect_buf, "{s}/.semantos/data", .{actual_home});
    try std.testing.expectEqualStrings(expected, got);
}

test "smoke-fix #7 resolveDataDirFromConfig: returns error when config missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_real = try tmp.dir.realpath(".", &path_buf);
    const fake_home = try std.testing.allocator.dupe(u8, tmp_real);
    defer std.testing.allocator.free(fake_home);

    // No config.json on disk → caller falls back to <home>/.semantos.
    try std.testing.expectError(error.FileNotFound, cli.resolveDataDirFromConfig(std.testing.allocator, fake_home));
}

// ─────────────────────────────────────────────────────────────────────
// Smoke-test pass #1, fix #8 — `brain device init` exists + bootstraps
// the operator-root priv + cert.
//
// Pre-fix the error messages in cmdServe + cmdDevicePair told
// operators to "run `brain device init` first" but the subcommand
// didn't exist.  These tests pin the new subcommand's contract.
// ─────────────────────────────────────────────────────────────────────

const c_stdlib = @cImport(@cInclude("stdlib.h"));

fn setDataDirEnv(path: []const u8) !void {
    var z: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(z[0..path.len], path);
    z[path.len] = 0;
    _ = c_stdlib.setenv("BRAIN_DATA_DIR", &z[0], 1);
}

fn unsetDataDirEnv() void {
    _ = c_stdlib.unsetenv("BRAIN_DATA_DIR");
}

test "smoke-fix #8 cmdDevice: init subcommand exists + appears in usage" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const code = try cli.cmdDevice(std.testing.allocator, &out, &.{});
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    // Usage line lists `init` as a subcommand.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "init") != null);
}

test "smoke-fix #8 cmdDeviceInit: --help prints usage + returns ok" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var pbuf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &pbuf);
    try setDataDirEnv(real);
    defer unsetDataDirEnv();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const args = [_][:0]u8{ @constCast("init"), @constCast("--help") };
    const code = try cli.cmdDevice(std.testing.allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.ok, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "operator-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "0600") != null);
}

test "smoke-fix #8 cmdDeviceInit: mints priv + root cert on first run" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var pbuf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &pbuf);
    try setDataDirEnv(real);
    defer unsetDataDirEnv();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const args = [_][:0]u8{@constCast("init")};
    const code = try cli.cmdDevice(std.testing.allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.ok, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "minted root cert id=") != null);

    // operator-root-priv.hex now exists on disk under the tmp data dir.
    var priv_check_buf: [std.fs.max_path_bytes]u8 = undefined;
    const priv_path = try std.fmt.bufPrint(&priv_check_buf, "{s}/operator-root-priv.hex", .{real});
    const f = try std.fs.cwd().openFile(priv_path, .{});
    f.close();
}

test "smoke-fix #8 cmdDeviceInit: idempotent on second run with same data_dir" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var pbuf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &pbuf);
    try setDataDirEnv(real);
    defer unsetDataDirEnv();

    // First run — mints priv + root.
    {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(std.testing.allocator);
        const out = newOutput(&buf);
        const args = [_][:0]u8{@constCast("init")};
        _ = try cli.cmdDevice(std.testing.allocator, &out, &args);
    }

    // Second run — must reuse priv + report the existing cert id.
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const args = [_][:0]u8{@constCast("init")};
    const code = try cli.cmdDevice(std.testing.allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.ok, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "priv exists at") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "existing root cert id=") != null);
}

// ─────────────────────────────────────────────────────────────────────
// fix/brain-device-data-dir-flag — --data-dir flag wins over $BRAIN_DATA_DIR
//
// Regression guard for the sudo env-strip failure mode: `sudo -u
// semantos brain device init` drops $BRAIN_DATA_DIR, so without the flag
// the command writes to ~/.semantos/data/ while `brain serve` reads from
// /var/lib/semantos.  The explicit flag must take precedence.
// ─────────────────────────────────────────────────────────────────────

test "cmdDeviceInit --data-dir flag wins over BRAIN_DATA_DIR env" {
    // env_dir — what $BRAIN_DATA_DIR points at (wrong dir from sudo's POV)
    var env_tmp = std.testing.tmpDir(.{});
    defer env_tmp.cleanup();
    var env_buf: [std.fs.max_path_bytes]u8 = undefined;
    const env_dir = try env_tmp.dir.realpath(".", &env_buf);

    // flag_dir — where the operator actually wants the files
    var flag_tmp = std.testing.tmpDir(.{});
    defer flag_tmp.cleanup();
    // Use a sentinel-terminated buffer so we can produce a [:0]u8 arg.
    var flag_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    const flag_dir_slice = try flag_tmp.dir.realpath(".", flag_buf[0..std.fs.max_path_bytes]);
    flag_buf[flag_dir_slice.len] = 0;
    const flag_dir_z: [:0]u8 = flag_buf[0..flag_dir_slice.len :0];

    // Set BRAIN_DATA_DIR to the "wrong" path to simulate sudo env.
    try setDataDirEnv(env_dir);
    defer unsetDataDirEnv();

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);
    const args = [_][:0]u8{
        @constCast("init"),
        @constCast("--data-dir"),
        flag_dir_z,
    };
    const code = try cli.cmdDevice(std.testing.allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.ok, code);

    // The priv must be written to flag_dir, not env_dir.
    var priv_check_buf: [std.fs.max_path_bytes]u8 = undefined;
    const priv_path = try std.fmt.bufPrint(&priv_check_buf, "{s}/operator-root-priv.hex", .{flag_dir_slice});
    const f = try std.fs.cwd().openFile(priv_path, .{});
    f.close();

    // Nothing should be written to the env dir.
    var env_priv_buf: [std.fs.max_path_bytes]u8 = undefined;
    const env_priv_path = try std.fmt.bufPrint(&env_priv_buf, "{s}/operator-root-priv.hex", .{env_dir});
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(env_priv_path, .{}));
}

```
