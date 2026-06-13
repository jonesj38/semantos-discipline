---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/tenant_serve_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.201384+00:00
---

# runtime/semantos-brain/tests/tenant_serve_conformance.zig

```zig
// Phase D-O9 — `brain serve --tenant-manifest` conformance.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §11 (the
// `[provision] writing systemd unit ...` step that ends with
// `brain serve --tenant-manifest=<path>` as the unit's ExecStart);
// docs/canon/deliverables.yml D-O9.
//
// Drives the new `--tenant-manifest <path>` flag on `brain serve`:
//
//   • missing path                 → config_error
//   • path to invalid TOML        → config_error
//   • path to schema-valid manifest with bad fields
//                                   → config_error (validate() error)
//   • path to a valid manifest, but no site_config laid down on disk
//                                   → config_error (post-manifest, on
//                                     site.json open) — confirms the
//                                     manifest WAS parsed + validated
//                                     and the `[tenant] domain` was
//                                     used to locate the site dir
//
// This test deliberately does NOT bind to a port — we expect cmdServe
// to fail BEFORE reaching server.serve() because the test harness
// hasn't laid down a site config.  The lifecycle the test walks is:
//
//   parse manifest → validate → resolve domain → siteConfigPath() →
//   loadFromPath(site.json) → fails (ENOENT) → return config_error
//
// That's the contract the systemd unit relies on too: a misconfigured
// manifest produces a clean exit + a journald error, not a half-bound
// daemon.

const std = @import("std");
const cli = @import("cli");

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

fn writeManifest(path: []const u8, body: []const u8) !void {
    const f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    try f.writeAll(body);
}

// ─────────────────────────────────────────────────────────────────────
// Argument-parsing surface
// ─────────────────────────────────────────────────────────────────────

test "D-O9 brain serve: --tenant-manifest with non-existent path returns config_error" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    const args = [_][:0]u8{
        try a.dupeZ(u8, "--tenant-manifest"),
        try a.dupeZ(u8, "/nonexistent/path/to/tenant.toml"),
    };
    defer for (args) |arg| a.free(arg);

    const code = try cli.cmdServe(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.config_error, code);

    // Operator-friendly error message: the failing path is echoed
    // back so the journald log makes the misconfiguration obvious.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "/nonexistent/path/to/tenant.toml") != null);
}

test "D-O9 brain serve: --tenant-manifest pointing at malformed TOML returns config_error" {
    const a = std.testing.allocator;
    const path = try tmpFilePath("d-o9-malformed.toml", a);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        a.free(path);
    }
    try writeManifest(path,
        \\[tenant]
        \\domain = NOT_A_STRING
        \\
    );

    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    const args = [_][:0]u8{
        try a.dupeZ(u8, "--tenant-manifest"),
        try a.dupeZ(u8, path),
    };
    defer for (args) |arg| a.free(arg);

    const code = try cli.cmdServe(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.config_error, code);
}

test "D-O9 brain serve: --tenant-manifest with schema-valid TOML but failing validation returns config_error" {
    const a = std.testing.allocator;
    const path = try tmpFilePath("d-o9-bad-schema.toml", a);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        a.free(path);
    }
    // Missing required fields — schema-valid TOML, but validate()
    // returns multiple errors (missing display_name, missing
    // owner_cert_path, etc.).
    try writeManifest(path,
        \\[tenant]
        \\domain = "foo"
        \\
        \\[extensions]
        \\install = []
        \\
        \\[branding]
        \\landing_page_template = ""
        \\brand_color = ""
        \\
    );

    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    const args = [_][:0]u8{
        try a.dupeZ(u8, "--tenant-manifest"),
        try a.dupeZ(u8, path),
    };
    defer for (args) |arg| a.free(arg);

    const code = try cli.cmdServe(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.config_error, code);

    // Validator surfaced the count + the per-error breakdown to the
    // operator-facing log.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "validation error") != null);
}

test "D-O9 brain serve: --tenant-manifest=<path> glued form is accepted (matches systemd ExecStart)" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    const args = [_][:0]u8{
        try a.dupeZ(u8, "--tenant-manifest=/nonexistent/glued/path.toml"),
    };
    defer for (args) |arg| a.free(arg);

    const code = try cli.cmdServe(a, &out, &args);
    // Path doesn't exist → config_error, but the IMPORTANT bit is
    // the path was extracted out of the glued `=` form (otherwise
    // we'd see a usage error).
    try std.testing.expectEqual(cli.ExitCode.config_error, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "/nonexistent/glued/path.toml") != null);
}

test "D-O9 brain serve: bare invocation (no domain, no --tenant-manifest) prints usage" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    const args = [_][:0]u8{};
    const code = try cli.cmdServe(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "usage:") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "--tenant-manifest") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Resolved-identity surface
// ─────────────────────────────────────────────────────────────────────
//
// Verifies the [tenant] info block is logged at startup so operators
// reading journald can confirm `%i` substitution.  We use a manifest
// pointing at a missing site.json: cmdServe gets through manifest
// parse + validate (logging the [tenant] block), then fails to load
// site.json.  The crucial post-manifest log lines must already be in
// the captured buffer.

test "D-O9 brain serve: valid manifest logs [tenant] domain + listen_port + extensions before failing on missing site.json" {
    const a = std.testing.allocator;
    // ONE tmp dir for both cert + manifest so the cert basename
    // resolves correctly when validate() does the manifest_dir join.
    var tdir = std.testing.tmpDir(.{});
    defer tdir.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tdir_real = try tdir.dir.realpath(".", &path_buf);

    // Lay down a side-by-side cert file the manifest can reference
    // (validate() opens the cert path via std.fs.cwd().access).
    const cert_path = try std.fs.path.join(a, &.{ tdir_real, "d-o9-tenant-cert.pem" });
    defer a.free(cert_path);
    {
        const f = try std.fs.cwd().createFile(cert_path, .{});
        defer f.close();
        try f.writeAll("-----BEGIN PLACEHOLDER CERT-----\n-----END PLACEHOLDER CERT-----\n");
    }

    // Manifest references the cert by basename; cmdServe resolves
    // owner_cert_path against the manifest's directory.
    const manifest_path = try std.fs.path.join(a, &.{ tdir_real, "d-o9-tenant.toml" });
    defer a.free(manifest_path);
    const cert_basename = std.fs.path.basename(cert_path);
    const body = try std.fmt.allocPrint(a,
        \\[tenant]
        \\domain = "tenant-d-o9.example"
        \\display_name = "D-O9 Tenant"
        \\owner_cert_path = "{s}"
        \\recovery_enrolment_id = "plexus-rec-d-o9"
        \\listen_port_start = 9091
        \\
        \\[extensions]
        \\install = ["sovereignty", "oddjobz"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#abc"
        \\
    , .{cert_basename});
    defer a.free(body);
    try writeManifest(manifest_path, body);

    // Point BRAIN_SITES_DIR at a fresh empty subdir of the same tmp
    // dir so siteConfigPath() resolves to a location that
    // definitely doesn't have a site.json — guarantees the
    // cmdServe failure is on site.json load, AFTER the [tenant]
    // block has been logged.
    const sites_dir = try std.fs.path.join(a, &.{ tdir_real, "d-o9-empty-sites" });
    defer a.free(sites_dir);
    std.fs.cwd().makeDir(sites_dir) catch {};
    const sites_z = try a.dupeZ(u8, sites_dir);
    defer a.free(sites_z);
    _ = setenv("BRAIN_SITES_DIR", sites_z.ptr, 1);
    defer _ = unsetenv("BRAIN_SITES_DIR");

    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    const args = [_][:0]u8{
        try a.dupeZ(u8, "--tenant-manifest"),
        try a.dupeZ(u8, manifest_path),
    };
    defer for (args) |arg| a.free(arg);

    const code = try cli.cmdServe(a, &out, &args);
    // Failure on site.json load (post-manifest).
    try std.testing.expectEqual(cli.ExitCode.config_error, code);

    // The pre-failure [tenant] log block is the load-bearing
    // assertion: it confirms the manifest was parsed + validated
    // successfully and the resolved identity threaded all the way
    // through to the operator-facing log line.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "[tenant] domain:          tenant-d-o9.example") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "[tenant] listen_port:     9091") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "[tenant] extensions:      sovereignty, oddjobz") != null);
}

```
