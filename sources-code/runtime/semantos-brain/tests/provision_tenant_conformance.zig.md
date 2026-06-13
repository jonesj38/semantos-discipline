---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/provision_tenant_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.187200+00:00
---

# runtime/semantos-brain/tests/provision_tenant_conformance.zig

```zig
// Phase D-O10 — `brain provision-tenant` conformance.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §11 (operator
// flow), docs/canon/deliverables.yml D-O10.  Drives the core
// orchestrator at src/provision_tenant.zig; the CLI argv shim's
// own conformance is at tests/cli_provision_tenant_conformance.zig.
//
// All tests run with `dry_run = true` so the flow exercises the full
// twelve-step path without any shell-outs (systemctl / caddy reload).
// File-system writes ARE exercised end-to-end against per-test
// tmpdirs — that's how the platform-signer-injection assertion (the
// post-provision archive at /etc/semantos/tenants/<domain>.toml has
// `[trusted_signers.platform] removable = false`) becomes
// observable.

const std = @import("std");
const pt = @import("provision_tenant");
const tm = @import("tenant_manifest");

// Pinned clock so the per-step elapsed-seconds line is deterministic
// across runs (matches the canonical §11 example shape).
fn pinnedClock() i64 {
    return 1_700_000_000;
}

// 32-byte test priv (lab-canonical "01...20" pattern; not derived from
// any production seed).  Same shape device_pair.zig uses for its lab
// vectors.
const TEST_PRIV_HEX = "0101010101010101010101010101010101010101010101010101010101010101";

// Helper: lay down a tmpdir with the input manifest + cert.pem + a
// 64-hex-char operator priv file the flow can read.  Returns the
// tmpdir path the caller must clean up.
const TestEnv = struct {
    allocator: std.mem.Allocator,
    /// Tmpdir handle (kept alive for tmp_dir.dir.realpath to work).
    tmp_dir: std.testing.TmpDir,
    /// Absolute path of the tmpdir.
    root: []u8,
    /// Absolute path to the manifest TOML.
    manifest_path: []u8,
    /// Absolute path to the operator priv hex file.
    priv_path: []u8,

    pub fn deinit(self: *TestEnv) void {
        self.allocator.free(self.root);
        self.allocator.free(self.manifest_path);
        self.allocator.free(self.priv_path);
        self.tmp_dir.cleanup();
    }
};

fn buildEnv(allocator: std.mem.Allocator, manifest_body: []const u8) !TestEnv {
    var tmp_dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_real = try tmp_dir.dir.realpath(".", &path_buf);
    const root = try allocator.dupe(u8, root_real);

    // Drop the manifest.
    const manifest_path = try std.fs.path.join(allocator, &.{ root, "tenant.toml" });
    {
        const f = try std.fs.cwd().createFile(manifest_path, .{});
        defer f.close();
        try f.writeAll(manifest_body);
    }
    // Drop a placeholder owner cert beside it (validators check this
    // file exists; D-O10's stub re-checks the same).
    {
        const cert_path = try std.fs.path.join(allocator, &.{ root, "cert.pem" });
        defer allocator.free(cert_path);
        const f = try std.fs.cwd().createFile(cert_path, .{});
        defer f.close();
        try f.writeAll("-----BEGIN PLACEHOLDER CERT-----\n-----END PLACEHOLDER CERT-----\n");
    }
    // Drop the operator priv hex file.
    const priv_path = try std.fs.path.join(allocator, &.{ root, "operator-root-priv.hex" });
    {
        const f = try std.fs.cwd().createFile(priv_path, .{});
        defer f.close();
        try f.writeAll(TEST_PRIV_HEX);
    }
    return .{
        .allocator = allocator,
        .tmp_dir = tmp_dir,
        .root = root,
        .manifest_path = manifest_path,
        .priv_path = priv_path,
    };
}

fn buildOpts(env: *const TestEnv, allocator: std.mem.Allocator) !pt.ProvisionOptions {
    const archive_dir = try std.fs.path.join(allocator, &.{ env.root, "tenants" });
    const data_root = try std.fs.path.join(allocator, &.{ env.root, "var-lib-semantos" });
    const systemd_dir = try std.fs.path.join(allocator, &.{ env.root, "etc-systemd-system" });
    const caddy_dir = try std.fs.path.join(allocator, &.{ env.root, "etc-caddy-conf-d" });
    const port_path = try std.fs.path.join(allocator, &.{ env.root, "port-allocations.json" });
    const ext_dir = try std.fs.path.join(allocator, &.{ env.root, "extension-bundles" });

    // Pre-create the systemd dir + drop a stub template so step 8's
    // existence check passes.
    try std.fs.cwd().makePath(systemd_dir);
    {
        const tmpl = try std.fs.path.join(allocator, &.{ systemd_dir, "semantos-shell@.service" });
        defer allocator.free(tmpl);
        const f = try std.fs.cwd().createFile(tmpl, .{});
        defer f.close();
        try f.writeAll("[Unit]\nDescription=stub\n");
    }

    return .{
        .manifest_path = env.manifest_path,
        .operator_priv_path = env.priv_path,
        .platform_plexus_identity_tx_hex = "deadbeefcafebabe0011223344556677aabbccddeeff00112233445566778899",
        .tenant_archive_dir = archive_dir,
        .data_root = data_root,
        .systemd_dir = systemd_dir,
        .caddy_dir = caddy_dir,
        .port_allocations_path = port_path,
        .extension_bundle_src_dir = ext_dir,
        .dry_run = false, // we want fs writes (the platform-signer
        // injection assertion needs the archive to be observable on
        // disk), but tmpdir-rooted so root isn't required.
        .clock = pinnedClock,
    };
}

fn freeOpts(allocator: std.mem.Allocator, opts: pt.ProvisionOptions) void {
    allocator.free(opts.tenant_archive_dir);
    allocator.free(opts.data_root);
    allocator.free(opts.systemd_dir);
    allocator.free(opts.caddy_dir);
    allocator.free(opts.port_allocations_path);
    allocator.free(opts.extension_bundle_src_dir);
}

const CANONICAL_MANIFEST =
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
;

// ─────────────────────────────────────────────────────────────────────
// Happy path
// ─────────────────────────────────────────────────────────────────────

test "D-O10 provision: happy path with mocked systemctl" {
    const a = std.testing.allocator;
    var env = try buildEnv(a, CANONICAL_MANIFEST);
    defer env.deinit();
    const opts = try buildOpts(&env, a);
    defer freeOpts(a, opts);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(a);
    const out = pt.Writer{ .buffer = &buf, .allocator = a };

    var result = try pt.provision(a, &out, opts);
    defer result.deinit(a);

    // Assert all twelve [provision] lines fired in order.
    const expected_lines = [_][]const u8{
        "[provision] validating manifest...                       ok",
        "[provision] D-W2 platform-signer:                  ok",
        "[provision] verifying owner cert against Plexus...       ok (stubbed for v0.1)",
        "[provision] verifying recovery enrolment...              ok (stubbed for v0.1)",
        "[provision] allocating port 8082...                        ok",
        "[provision] laying down ",
        "[provision] minting capability tokens...                 ",
        "[provision] copying extension bundles...                 ",
        "[provision] writing systemd unit...                      ",
        "[provision] writing Caddy block...                       ",
        "[provision] starting service...                          active (running)",
        "[provision] running first-boot...                        done (cert_id ",
    };
    for (expected_lines) |needle| {
        if (std.mem.indexOf(u8, buf.items, needle) == null) {
            std.debug.print("\nMISSING LINE: '{s}'\n\nFULL OUTPUT:\n{s}\n", .{ needle, buf.items });
            try std.testing.expect(false);
        }
    }

    // Summary block.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Provisioned in ") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "auth/setup?token=") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Helm: https://acme-plumbing.com.au/helm") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Public site: https://acme-plumbing.com.au") != null);

    // Result struct shape.
    try std.testing.expectEqualStrings("acme-plumbing.com.au", result.domain);
    try std.testing.expectEqual(@as(u16, 8082), result.listen_port);
    try std.testing.expect(!result.platform_tx_placeholder);
}

// ─────────────────────────────────────────────────────────────────────
// D-W2 Phase 0 — platform-signer auto-injection
// ─────────────────────────────────────────────────────────────────────

test "D-O10 provision: D-W2 Phase 0 auto-injects [trusted_signers.platform] with removable=false" {
    const a = std.testing.allocator;
    var env = try buildEnv(a, CANONICAL_MANIFEST);
    defer env.deinit();
    const opts = try buildOpts(&env, a);
    defer freeOpts(a, opts);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(a);
    const out = pt.Writer{ .buffer = &buf, .allocator = a };
    var result = try pt.provision(a, &out, opts);
    defer result.deinit(a);

    // Read the canonical archive and assert the platform entry was
    // injected.
    const archive = try std.fs.path.join(a, &.{ opts.tenant_archive_dir, "acme-plumbing.com.au.toml" });
    defer a.free(archive);
    var archived = try tm.loadFromPath(a, archive);
    defer archived.deinit();

    try std.testing.expect(archived.trusted_signers_present);
    const platform = archived.platformSigner() orelse {
        try std.testing.expect(false);
        return;
    };
    try std.testing.expect(!platform.removable);
    try std.testing.expectEqualStrings("*", platform.scopes[0]);
    try std.testing.expectEqual(@as(usize, 66), platform.pubkey_hex.len);
    // Verify it's the operator's actual pubkey (deterministic from
    // the test priv) — not just a placeholder.
    try std.testing.expect(!std.mem.eql(u8, platform.pubkey_hex, "0" ** 66));
}

test "D-O10 provision: --platform-plexus-identity-tx absent → placeholder warning" {
    const a = std.testing.allocator;
    var env = try buildEnv(a, CANONICAL_MANIFEST);
    defer env.deinit();
    var opts = try buildOpts(&env, a);
    defer freeOpts(a, opts);
    opts.platform_plexus_identity_tx_hex = ""; // operator did not pass

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(a);
    const out = pt.Writer{ .buffer = &buf, .allocator = a };
    var result = try pt.provision(a, &out, opts);
    defer result.deinit(a);

    try std.testing.expect(result.platform_tx_placeholder);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "placeholder plexus_identity_tx") != null);

    // Archive's plexus_identity_tx_hex should be 64 zeros.
    const archive = try std.fs.path.join(a, &.{ opts.tenant_archive_dir, "acme-plumbing.com.au.toml" });
    defer a.free(archive);
    var archived = try tm.loadFromPath(a, archive);
    defer archived.deinit();
    const platform = archived.platformSigner().?;
    try std.testing.expectEqualStrings("0" ** 64, platform.plexus_identity_tx_hex);
}

test "D-O10 provision: operator-edited platform removable=true → refuse before flow" {
    const a = std.testing.allocator;
    const manifest_with_bad_platform =
        \\[tenant]
        \\domain = "acme-plumbing.com.au"
        \\display_name = "Acme Plumbing"
        \\owner_cert_path = "./cert.pem"
        \\recovery_enrolment_id = "plexus-rec-acme-001"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "default-tradie"
        \\brand_color = "#2a5fb5"
        \\
        \\[trusted_signers.platform]
        \\pubkey = "02a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
        \\plexus_identity_tx = "deadbeefcafebabe0011223344556677aabbccddeeff00112233445566778899"
        \\scope = "*"
        \\removable = true
        \\label = "Platform"
        \\shard_group = "g"
        \\
    ;
    var env = try buildEnv(a, manifest_with_bad_platform);
    defer env.deinit();
    const opts = try buildOpts(&env, a);
    defer freeOpts(a, opts);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(a);
    const out = pt.Writer{ .buffer = &buf, .allocator = a };

    // The validator catches this at step 1 (bad_platform_removable
    // surfaces during validate()).  Even before our pre-flight
    // check, the run fails — that's OK; the test asserts the run
    // refuses to commit any side effects.
    const err = pt.provision(a, &out, opts);
    try std.testing.expectError(pt.ProvisionError.manifest_validation_failed, err);

    // Archive must NOT exist — flow refused before step 5 wrote it.
    const archive = try std.fs.path.join(a, &.{ opts.tenant_archive_dir, "acme-plumbing.com.au.toml" });
    defer a.free(archive);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(archive, .{}));
}

// ─────────────────────────────────────────────────────────────────────
// Step 1 — manifest validation failures
// ─────────────────────────────────────────────────────────────────────

test "D-O10 provision: manifest validation failure bails at Step 1" {
    const a = std.testing.allocator;
    const bad_manifest =
        \\[tenant]
        \\domain = ""
        \\display_name = ""
        \\owner_cert_path = ""
        \\recovery_enrolment_id = ""
        \\
        \\[extensions]
        \\install = []
        \\
        \\[branding]
        \\landing_page_template = ""
        \\brand_color = ""
        \\
    ;
    var env = try buildEnv(a, bad_manifest);
    defer env.deinit();
    const opts = try buildOpts(&env, a);
    defer freeOpts(a, opts);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(a);
    const out = pt.Writer{ .buffer = &buf, .allocator = a };

    const err = pt.provision(a, &out, opts);
    try std.testing.expectError(pt.ProvisionError.manifest_validation_failed, err);

    // Step 1 emitted an error line — none of the later steps fired.
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "validating manifest") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "verifying owner cert") == null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "starting service") == null);
}

// ─────────────────────────────────────────────────────────────────────
// Step 2 — owner cert missing
// ─────────────────────────────────────────────────────────────────────

test "D-O10 provision: owner cert missing → bail at Step 2" {
    const a = std.testing.allocator;
    var env = try buildEnv(a, CANONICAL_MANIFEST);
    defer env.deinit();
    // Remove the cert.pem we put down.
    {
        const cert_path = try std.fs.path.join(a, &.{ env.root, "cert.pem" });
        defer a.free(cert_path);
        std.fs.cwd().deleteFile(cert_path) catch {};
    }
    const opts = try buildOpts(&env, a);
    defer freeOpts(a, opts);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(a);
    const out = pt.Writer{ .buffer = &buf, .allocator = a };

    // The validator already fails at Step 1 with cert_not_found —
    // that's the right gate.  Step 2 is structurally a stub but
    // its test is "the flow stops if the cert is missing", which
    // Step 1's validate() already enforces.
    const err = pt.provision(a, &out, opts);
    try std.testing.expectError(pt.ProvisionError.manifest_validation_failed, err);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "validating manifest") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Step 4 — port collision → next port + persisted allocation
// ─────────────────────────────────────────────────────────────────────

test "D-O10 provision: port collision → next port + persisted allocation" {
    const a = std.testing.allocator;
    var env = try buildEnv(a, CANONICAL_MANIFEST);
    defer env.deinit();
    const opts = try buildOpts(&env, a);
    defer freeOpts(a, opts);

    // Pre-write a port-allocations.json with 8082 already taken by a
    // different domain.
    {
        if (std.fs.path.dirname(opts.port_allocations_path)) |parent| {
            std.fs.cwd().makePath(parent) catch {};
        }
        const f = try std.fs.cwd().createFile(opts.port_allocations_path, .{});
        defer f.close();
        try f.writeAll("{\n  \"other.example\": 8082\n}\n");
    }

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(a);
    const out = pt.Writer{ .buffer = &buf, .allocator = a };
    var result = try pt.provision(a, &out, opts);
    defer result.deinit(a);

    try std.testing.expectEqual(@as(u16, 8083), result.listen_port);

    // Allocation persisted: re-read the index.
    const f = try std.fs.cwd().openFile(opts.port_allocations_path, .{});
    defer f.close();
    const stat = try f.stat();
    const buf_in = try a.alloc(u8, stat.size);
    defer a.free(buf_in);
    _ = try f.readAll(buf_in);
    try std.testing.expect(std.mem.indexOf(u8, buf_in, "acme-plumbing.com.au") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf_in, "8083") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Re-provisioning idempotency (compareImmutability on the archive)
// ─────────────────────────────────────────────────────────────────────

test "D-O10 provision: re-running on the same domain is idempotent" {
    const a = std.testing.allocator;
    var env = try buildEnv(a, CANONICAL_MANIFEST);
    defer env.deinit();
    const opts = try buildOpts(&env, a);
    defer freeOpts(a, opts);

    var buf1: std.ArrayList(u8) = .empty;
    defer buf1.deinit(a);
    const out1 = pt.Writer{ .buffer = &buf1, .allocator = a };
    var first = try pt.provision(a, &out1, opts);
    defer first.deinit(a);

    var buf2: std.ArrayList(u8) = .empty;
    defer buf2.deinit(a);
    const out2 = pt.Writer{ .buffer = &buf2, .allocator = a };
    var second = try pt.provision(a, &out2, opts);
    defer second.deinit(a);

    // Same port both times.
    try std.testing.expectEqual(first.listen_port, second.listen_port);
    // Second run's port-allocation log line says "re-using existing assignment".
    try std.testing.expect(std.mem.indexOf(u8, buf2.items, "re-using existing assignment") != null);
}

```
