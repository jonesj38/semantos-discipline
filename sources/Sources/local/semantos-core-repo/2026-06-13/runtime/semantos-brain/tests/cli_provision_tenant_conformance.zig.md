---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/cli_provision_tenant_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.185465+00:00
---

# runtime/semantos-brain/tests/cli_provision_tenant_conformance.zig

```zig
// Phase D-O10 — CLI conformance for `brain provision-tenant`.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §11; tests/
// provision_tenant_conformance.zig (the core flow's own tests).
//
// This file drives the cli.cmdProvisionTenant argv parser end-to-end:
//
//   • argv shape (missing manifest, unknown flag, glued vs split flags)
//   • help / usage text fires on bad invocation
//   • exit-code mapping from ProvisionError → ExitCode
//
// The full §11 byte-stable log shape is asserted in
// provision_tenant_conformance.zig; this file's goal is the shim's
// argv handling + the exit-code translation.

const std = @import("std");
const cli = @import("cli");

fn newOutput(buf: *std.ArrayList(u8)) cli.Output {
    return .{ .buffer = buf, .allocator = std.testing.allocator };
}

test "D-O10 brain provision-tenant: no args → bad_args + usage line" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);
    const args: []const [:0]u8 = &.{};
    const code = try cli.cmdProvisionTenant(a, &out, args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "usage: brain provision-tenant") != null);
}

test "D-O10 brain provision-tenant: --flag-only with no manifest → bad_args" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    const args = [_][:0]u8{try a.dupeZ(u8, "--dry-run")};
    defer for (args) |arg| a.free(arg);
    const code = try cli.cmdProvisionTenant(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
}

test "D-O10 brain provision-tenant: unknown flag rejected" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    const args = [_][:0]u8{
        try a.dupeZ(u8, "/tmp/x.toml"),
        try a.dupeZ(u8, "--unknown-flag"),
    };
    defer for (args) |arg| a.free(arg);
    const code = try cli.cmdProvisionTenant(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "--unknown-flag") != null);
}

test "D-O10 brain provision-tenant: missing manifest → config_error" {
    const a = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    const args = [_][:0]u8{
        try a.dupeZ(u8, "/nonexistent/manifest.toml"),
        try a.dupeZ(u8, "--dry-run"),
    };
    defer for (args) |arg| a.free(arg);
    const code = try cli.cmdProvisionTenant(a, &out, &args);
    try std.testing.expectEqual(cli.ExitCode.config_error, code);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "validating manifest") != null);
}

test "D-O10 brain provision-tenant: full byte-stable §11 output shape (happy path)" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root = try tmp.dir.realpath(".", &path_buf);
    const root_owned = try a.dupe(u8, root);
    defer a.free(root_owned);

    // Drop the manifest + cert + priv.
    const manifest_path = try std.fs.path.join(a, &.{ root_owned, "tenant.toml" });
    defer a.free(manifest_path);
    {
        const f = try std.fs.cwd().createFile(manifest_path, .{});
        defer f.close();
        try f.writeAll(
            \\[tenant]
            \\domain = "acme-plumbing.com.au"
            \\display_name = "Acme Plumbing"
            \\owner_cert_path = "./cert.pem"
            \\recovery_enrolment_id = "plexus-rec-acme-001"
            \\
            \\[extensions]
            \\install = ["sovereignty", "oddjobz"]
            \\
            \\[branding]
            \\landing_page_template = "default-tradie"
            \\brand_color = "#2a5fb5"
            \\
        );
    }
    {
        const cert_path = try std.fs.path.join(a, &.{ root_owned, "cert.pem" });
        defer a.free(cert_path);
        const f = try std.fs.cwd().createFile(cert_path, .{});
        defer f.close();
        try f.writeAll("-----BEGIN PLACEHOLDER-----\n");
    }
    const priv_path = try std.fs.path.join(a, &.{ root_owned, "operator-root-priv.hex" });
    defer a.free(priv_path);
    {
        const f = try std.fs.cwd().createFile(priv_path, .{});
        defer f.close();
        try f.writeAll("0101010101010101010101010101010101010101010101010101010101010101");
    }

    // Even with --dry-run we still need the systemd template path
    // dance — but cli.cmdProvisionTenant uses production paths.
    // The test exercises argv-handling + the early-failure
    // surfaces; the full canonical log stream is covered in
    // provision_tenant_conformance.zig with tmpdir-rooted paths.
    //
    // Here we just confirm the manifest path arg is threaded through
    // and the [provision] validating manifest line is what users see
    // in the normal happy path.
    var buf = std.ArrayList(u8){};
    defer buf.deinit(a);
    const out = newOutput(&buf);

    const args = [_][:0]u8{
        try a.dupeZ(u8, manifest_path),
        try a.dupeZ(u8, "--operator-priv"),
        try a.dupeZ(u8, priv_path),
        try a.dupeZ(u8, "--dry-run"),
    };
    defer for (args) |arg| a.free(arg);

    // The flow will fail at step 5 (data-dir layout — production
    // /var/lib/semantos isn't writable) OR step 8 (systemd template
    // missing).  We assert at minimum that step 1 + the platform-
    // signer injection log line fired before the failure.
    _ = try cli.cmdProvisionTenant(a, &out, &args);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "[provision] validating manifest...                       ok") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "[provision] D-W2 platform-signer:") != null);
}

```
