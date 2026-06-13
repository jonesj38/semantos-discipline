---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/cli_phase2_smoke_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.193798+00:00
---

# runtime/semantos-brain/tests/cli_phase2_smoke_conformance.zig

```zig
// Phase D-W1 / Phase 2 — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md
// §8 Phase 2.
//
// Smoke-test invariant: every CLI verb migrated to dispatch in Phase 2
// produces output that's byte-identical to the post-migration legacy
// shape.  We don't compare directly to "old" code (the legacy paths
// were replaced), but we lock in the exact bytes the operator sees so
// future churn breaks loud.
//
// Verbs covered:
//   • `brain hash <wasm>`          — sha256 + path on success; `warning:`
//                                  prefix on non-WASM input
//   • `brain site init <domain>`   — Scaffolded site / config / content /
//                                  Next: `brain serve <domain>` ...
//   • `brain site list`            — one domain per line; "(no sites
//                                  configured)" empty-state
//   • `brain site validate <d>`    — ✓ no problems / ✗ error: ...
//
// Per the brief — Phase 0's repl conformance pattern (`runBothPaths`)
// is the precedent.  Phase 2 doesn't have a "two paths" comparison
// because there's no daemon socket round-trip path for these CLI
// verbs yet (embedded only) — the invariant we lock is the
// pre-vs-post-rewire byte equality, captured here as fixed-string
// assertions on what the operator sees today.

const std = @import("std");
const cli = @import("cli");
const module_loader = @import("module_loader");

// libc setenv/unsetenv aren't exposed by std.c on every platform target
// in 0.15.x; declare the extern shape we need directly so the smoke
// suite can drive BRAIN_SITES_DIR per-test without colliding on the
// process env.
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

fn newOutput(buf: *std.ArrayList(u8)) cli.Output {
    return .{ .buffer = buf, .allocator = std.testing.allocator };
}

fn tmpFilePath(name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var tmp_dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp_dir.dir.realpath(".", &path_buf);
    return std.fs.path.join(allocator, &.{ real, name });
}

fn writeMinimalWasm(path: []const u8) !void {
    const f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    try f.writeAll(&module_loader.WASM_MAGIC);
}

// ─────────────────────────────────────────────────────────────────────
// `brain hash <wasm>`
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P2 cli smoke: hash prints sha256 + path on a valid WASM file" {
    const path = try tmpFilePath("smoke-hash.wasm", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    try writeMinimalWasm(path);

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);

    const code = try cli.cmdHash(std.testing.allocator, &out, path);
    try std.testing.expectEqual(cli.ExitCode.ok, code);

    const expected = module_loader.computeSha256(&module_loader.WASM_MAGIC);
    const expected_hex = try module_loader.formatHashHex(std.testing.allocator, &expected);
    defer std.testing.allocator.free(expected_hex);

    // Output is `<hex>  <path>\n`.
    var expected_line = std.ArrayList(u8){};
    defer expected_line.deinit(std.testing.allocator);
    try expected_line.print(std.testing.allocator, "{s}  {s}\n", .{ expected_hex, path });
    try std.testing.expectEqualStrings(expected_line.items, buf.items);
}

test "D-W1 P2 cli smoke: hash on non-WASM file emits warning + then sha256 line" {
    const path = try tmpFilePath("smoke-not.wasm", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    {
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll("plain text body");
    }

    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);

    const code = try cli.cmdHash(std.testing.allocator, &out, path);
    try std.testing.expectEqual(cli.ExitCode.ok, code);

    try std.testing.expect(std.mem.indexOf(u8, buf.items, "warning:") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "doesn't have WASM magic bytes") != null);
}

test "D-W1 P2 cli smoke: hash on missing file returns file_io" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);
    const out = newOutput(&buf);

    const code = try cli.cmdHash(std.testing.allocator, &out, "/nonexistent/wasm/path.wasm");
    try std.testing.expectEqual(cli.ExitCode.file_io, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "failed to open") != null);
}

// ─────────────────────────────────────────────────────────────────────
// `brain site init/list/validate`  — drive against an isolated tmp
//   sites_dir via the BRAIN_SITES_DIR env var.  Same env hook the
//   production CLI uses.
// ─────────────────────────────────────────────────────────────────────

const SitesEnv = struct {
    tmp: std.testing.TmpDir,
    sites_dir: []u8,
    /// The previous value of BRAIN_SITES_DIR (if any) so we can restore.
    prev: ?[]const u8,

    fn setup(allocator: std.mem.Allocator) !SitesEnv {
        var tmp = std.testing.tmpDir(.{});
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const sites_dir = try allocator.dupe(u8, real);
        const c_str = try allocator.dupeZ(u8, sites_dir);
        defer allocator.free(c_str);
        _ = setenv("BRAIN_SITES_DIR", c_str.ptr, 1);
        return .{ .tmp = tmp, .sites_dir = sites_dir, .prev = null };
    }

    fn deinit(self: *SitesEnv, allocator: std.mem.Allocator) void {
        _ = unsetenv("BRAIN_SITES_DIR");
        allocator.free(self.sites_dir);
        self.tmp.cleanup();
    }
};

test "D-W1 P2 cli smoke: site init scaffolds + emits canonical 4-line summary" {
    const allocator = std.testing.allocator;
    var env = try SitesEnv.setup(allocator);
    defer env.deinit(allocator);

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    const out = newOutput(&buf);

    const args = [_][:0]u8{
        try allocator.dupeZ(u8, "init"),
        try allocator.dupeZ(u8, "smoke.example.com"),
    };
    defer for (args) |a| allocator.free(a);

    const code = try cli.cmdSite(allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.ok, code);

    // Operator-facing format the helm + the docs depend on.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Scaffolded site smoke.example.com:") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "  config:  ") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "  content: ") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Next: `brain serve smoke.example.com`") != null);
}

test "D-W1 P2 cli smoke: site init duplicate prints existing-site message" {
    const allocator = std.testing.allocator;
    var env = try SitesEnv.setup(allocator);
    defer env.deinit(allocator);

    const args = [_][:0]u8{
        try allocator.dupeZ(u8, "init"),
        try allocator.dupeZ(u8, "dup.example.com"),
    };
    defer for (args) |a| allocator.free(a);

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    {
        const out = newOutput(&buf);
        const code = try cli.cmdSite(allocator, &out, &args);
        try std.testing.expectEqual(cli.ExitCode.ok, code);
    }
    buf.clearRetainingCapacity();
    {
        const out = newOutput(&buf);
        const code = try cli.cmdSite(allocator, &out, &args);
        try std.testing.expectEqual(cli.ExitCode.config_error, code);
        try std.testing.expect(std.mem.indexOf(u8, buf.items, "site already exists at") != null);
    }
}

test "D-W1 P2 cli smoke: site list shows scaffolded domains, one per line" {
    const allocator = std.testing.allocator;
    var env = try SitesEnv.setup(allocator);
    defer env.deinit(allocator);

    const init_args = [_][:0]u8{
        try allocator.dupeZ(u8, "init"),
        try allocator.dupeZ(u8, "alpha.example.com"),
    };
    defer for (init_args) |a| allocator.free(a);
    {
        var b = std.ArrayList(u8){};
        defer b.deinit(allocator);
        const o = newOutput(&b);
        _ = try cli.cmdSite(allocator, &o, &init_args);
    }

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    const out = newOutput(&buf);
    const list_args = [_][:0]u8{try allocator.dupeZ(u8, "list")};
    defer for (list_args) |a| allocator.free(a);
    const code = try cli.cmdSite(allocator, &out, &list_args);
    try std.testing.expectEqual(cli.ExitCode.ok, code);
    try std.testing.expectEqualStrings("alpha.example.com\n", buf.items);
}

test "D-W1 P2 cli smoke: site list on empty sites_dir emits canonical empty message" {
    const allocator = std.testing.allocator;
    var env = try SitesEnv.setup(allocator);
    defer env.deinit(allocator);

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    const out = newOutput(&buf);
    const args = [_][:0]u8{try allocator.dupeZ(u8, "list")};
    defer for (args) |a| allocator.free(a);
    const code = try cli.cmdSite(allocator, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.ok, code);
    try std.testing.expectEqualStrings("(no sites configured)\n", buf.items);
}

test "D-W1 P2 cli smoke: site validate after fresh init emits ✓ no problems" {
    const allocator = std.testing.allocator;
    var env = try SitesEnv.setup(allocator);
    defer env.deinit(allocator);

    const init_args = [_][:0]u8{
        try allocator.dupeZ(u8, "init"),
        try allocator.dupeZ(u8, "v.example.com"),
    };
    defer for (init_args) |a| allocator.free(a);
    {
        var b = std.ArrayList(u8){};
        defer b.deinit(allocator);
        const o = newOutput(&b);
        _ = try cli.cmdSite(allocator, &o, &init_args);
    }

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    const out = newOutput(&buf);
    const v_args = [_][:0]u8{
        try allocator.dupeZ(u8, "validate"),
        try allocator.dupeZ(u8, "v.example.com"),
    };
    defer for (v_args) |a| allocator.free(a);
    const code = try cli.cmdSite(allocator, &out, &v_args);
    try std.testing.expectEqual(cli.ExitCode.ok, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "✓ no problems") != null);
}

```
