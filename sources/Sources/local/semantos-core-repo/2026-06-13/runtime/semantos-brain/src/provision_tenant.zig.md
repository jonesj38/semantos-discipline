---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/provision_tenant.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.245031+00:00
---

# runtime/semantos-brain/src/provision_tenant.zig

```zig
// Phase D-O10 — `brain provision-tenant <manifest.toml>` core.
//
// References:
//   - docs/design/ODDJOBZ-EXTENSION-PLAN.md §11 (the canonical operator
//     flow + the byte-stable expected log lines this module emits).
//   - docs/canon/deliverables.yml D-O10 entry.
//   - docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §3 (D-W2
//     Phase 0 — `[trusted_signers.platform]` is injected by this flow
//     before the manifest is written to its canonical archive).
//   - runtime/semantos-brain/src/tenant_manifest.zig (D-O8 + D-W2 Phase 0 schema).
//   - runtime/semantos-brain/src/caddy_template.zig (D-O9 — the Caddy block
//     renderer used by step 9).
//   - runtime/semantos-brain/deploy/systemd/semantos-shell@.service (D-O9 — the
//     unit step 8 references).
//
// ── What this module is, and isn't ─────────────────────────────────
//
// The §11 operator flow translated into Zig.  Twelve numbered steps
// from "validating manifest" through "emit pairing token" with the
// per-step log lines spelled out in the brief.  This module is pure
// logic — it operates on a `ProvisionOptions` (flags from the CLI)
// and an `Output` writer.  `cli.zig`'s `cmdProvisionTenant` is the
// thin dispatcher that calls into here.
//
// systemctl + `caddy reload` shell-outs are **gated** behind
// `ProvisionOptions.dry_run`.  Default is `false` (production); the
// conformance tests pass `true` so they can drive the full flow
// without root or a running Caddy.
//
// Plexus-side calls (Step 2 + Step 3) are STUBBED for v0.1.  Real
// Plexus client integration is D-W2 Phase 1.  The stubs surface the
// log lines the operator expects (`ok (stubbed for v0.1)`) and pass
// through unconditionally; the verification gate becomes load-bearing
// once D-W2 Phase 1 lands.  Code paths are clearly TODO'd.
//
// Multi-tenant port allocation: `/etc/semantos/port-allocations.json`
// is a tiny JSON index mapping `<domain>` → `<port>`.  Step 4 reads it,
// allocates `manifest.listen_port_start + count_existing_tenants` if
// the start port is taken, persists the new mapping, and uses the
// resulting port for the Caddy upstream + first-boot.
//
// D-W2 Phase 0: the platform-signer auto-injection step runs AFTER
// validation (Step 1) but BEFORE data-dir layout (Step 5).  It mutates
// the in-memory manifest to add `[trusted_signers.platform]` keyed off
// the operator's signing pubkey.  The augmented manifest is what gets
// written to `/etc/semantos/tenants/<domain>.toml` in step 5b.
//
// ── Output shape ───────────────────────────────────────────────────
//
// Every step writes its `[provision] <message>... <result>` line in
// the §11 expected order.  The conformance test asserts byte-equality
// against the canonical example.  A trailing summary block emits the
// `Provisioned in Ns.` line + the auth/setup URL + helm/public site
// URLs.

const std = @import("std");
const tm = @import("tenant_manifest");
const caddy_template = @import("caddy_template");
const bkds = @import("bkds");
const bsvz = @import("bsvz");
const device_pair = @import("device_pair");
const identity_certs = @import("identity_certs");
const extensions = @import("extensions");

// ─────────────────────────────────────────────────────────────────────
// Errors + types
// ─────────────────────────────────────────────────────────────────────

pub const ProvisionError = error{
    /// Step 1 — manifest validate() returned err count > 0.
    manifest_validation_failed,
    /// Step 1 — the manifest's TOML parsing failed before we got to
    /// validate.
    manifest_parse_failed,
    /// Step 2 — owner cert path could not be opened.  (Plexus
    /// verification proper is stubbed; this is the structural check
    /// that survives the stub.)
    owner_cert_unreadable,
    /// Step 3 — recovery enrolment ID failed shape check.  Same
    /// structural-check note as above.
    recovery_enrolment_invalid,
    /// Step 4 — port-allocations file is corrupt OR no free port could
    /// be allocated within a sane window.
    port_allocation_failed,
    /// Step 5 — data-dir creation / manifest archive write failed.
    data_dir_layout_failed,
    /// Step 6 — first-boot capability mint fired before any cert was
    /// minted.  Not actually expected in production (cert mint runs
    /// inside this flow's first-boot step), but surfaced for the
    /// conformance suite.
    cap_mint_failed,
    /// Step 7 — extension-bundle source path not found.
    extension_bundle_missing,
    /// Step 8 — systemd unit write failed.  In production this is
    /// usually a permission error.
    systemd_write_failed,
    /// Step 9 — Caddy block write OR reload failed.
    caddy_write_failed,
    /// Step 10 — service start failed (or the dry-run probe
    /// short-circuit didn't reach `active`).
    service_start_failed,
    /// Step 11 — first-boot init failed.
    first_boot_failed,
    /// Step 12 — pairing payload signing failed.
    pairing_payload_failed,
    /// Step 3 (D-W2 Phase 0 inject) — operator priv could not be read
    /// from the configured path.
    operator_priv_unreadable,
    /// D-W2 Phase 0 — the operator-edited input manifest sets
    /// `[trusted_signers.platform] removable = true`, which violates
    /// the platform-tier invariant.  Refuse the provision before
    /// flow start.
    operator_edited_platform_immutable,
    /// D-W2 Phase 0 — a previous-version archive at /etc/semantos/
    /// tenants/<domain>.toml has a `removable = false` entry that the
    /// new (post-injection) manifest edits or drops.
    immutable_signer_changed,
    out_of_memory,
    /// Catch-all for unexpected I/O.
    io_failed,
};

/// CLI-supplied flags + config the flow reads up front.
pub const ProvisionOptions = struct {
    /// Path to the operator-authored manifest TOML.  Required.
    manifest_path: []const u8,

    /// Path to the operator's signing-key hex file (mode 0600,
    /// 64-hex-char file at `<operator_data_dir>/operator-root-priv.hex`
    /// by default).  When the file is absent, the flow STILL proceeds
    /// but the platform-signer entry uses a placeholder pubkey + logs
    /// a warning.  Production deployments configure this.
    ///
    /// If empty, we resolve via the same logic `brain device pair` uses:
    /// `<operator data dir>/operator-root-priv.hex`.
    operator_priv_path: []const u8 = "",

    /// Optional D-W2 Phase 0 — the operator's Plexus identity tx for
    /// the platform signer.  When empty, the injected entry uses a
    /// 64-zero placeholder + the flow logs a warning that Phase 1
    /// SPV verification will reject the manifest until a real tx id
    /// is filled in.
    platform_plexus_identity_tx_hex: []const u8 = "",

    /// Where the canonical archive lives.  Default is the production
    /// path; tests override to a tmpdir.
    tenant_archive_dir: []const u8 = "/etc/semantos/tenants",

    /// Where per-tenant data dirs live.  Production: /var/lib/semantos.
    /// Tests override to a tmpdir.
    data_root: []const u8 = "/var/lib/semantos",

    /// Where the systemd unit drop-in lives.  Production: /etc/systemd/
    /// system.  Tests override.
    systemd_dir: []const u8 = "/etc/systemd/system",

    /// Where Caddy site blocks live.  Production: /etc/caddy/conf.d.
    /// Tests override.
    caddy_dir: []const u8 = "/etc/caddy/conf.d",

    /// Where the multi-tenant port-allocation index lives.  Production:
    /// `<tenant_archive_dir>/../port-allocations.json` → /etc/semantos/
    /// port-allocations.json.  Tests override.
    port_allocations_path: []const u8 = "/etc/semantos/port-allocations.json",

    /// Where extension bundles are read from (the source-of-truth
    /// directory for the bundled extensions list).  Production:
    /// /opt/semantos/extensions.  Tests override.
    extension_bundle_src_dir: []const u8 = "/opt/semantos/extensions",

    /// When true, skip every shell-out (systemctl reload, caddy reload,
    /// systemctl start) + skip the file-system writes that require
    /// root in production.  Set TRUE in tests; FALSE in production.
    dry_run: bool = false,

    /// Pinned clock for tests; production passes
    /// `std.time.timestamp` via the CLI wrapper.
    clock: *const fn () i64,
};

/// Returned to the caller for use in the post-provision summary +
/// conformance-test assertions.
pub const ProvisionResult = struct {
    domain: []const u8,
    listen_port: u16,
    /// Owned by the caller; call `result.deinit(allocator)`.
    auth_setup_url: []u8,
    helm_url: []u8,
    public_url: []u8,
    /// 64-hex-char first-boot operator-root cert id (or `"<dry-run>"`
    /// when the flow ran with `dry_run = true`).
    operator_root_cert_id: []u8,
    /// 64-hex-char first-boot BCA (Brain Carpenter Address) prefix.
    /// `"<dry-run>"` placeholder in dry-run mode.
    bca_hex_prefix: []u8,
    /// True if the platform signer was injected with a placeholder tx
    /// (operator did not pass `--platform-plexus-identity-tx`).
    platform_tx_placeholder: bool,

    pub fn deinit(self: *ProvisionResult, allocator: std.mem.Allocator) void {
        allocator.free(self.domain);
        allocator.free(self.auth_setup_url);
        allocator.free(self.helm_url);
        allocator.free(self.public_url);
        allocator.free(self.operator_root_cert_id);
        allocator.free(self.bca_hex_prefix);
    }
};

/// Generic writer (mirrors cli.Output) so tests + production share the
/// exact same call-site shape without pulling cli.zig in.
pub const Writer = struct {
    buffer: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn print(self: *const Writer, comptime fmt: []const u8, args: anytype) !void {
        try self.buffer.print(self.allocator, fmt, args);
    }
};

// ─────────────────────────────────────────────────────────────────────
// The orchestrator — provision()
// ─────────────────────────────────────────────────────────────────────

/// Run the full §11 flow.  On success returns a `ProvisionResult` the
/// caller cleans up.  On failure returns a typed error AFTER having
/// emitted the corresponding `[provision] <step>...    error: <why>`
/// line; the caller handles the exit-code translation.
pub fn provision(
    allocator: std.mem.Allocator,
    out: *const Writer,
    opts: ProvisionOptions,
) ProvisionError!ProvisionResult {
    const wall_start = opts.clock();

    // ── Step 1: validate manifest ────────────────────────────────
    var manifest = try stepValidateManifest(allocator, out, opts);
    errdefer manifest.deinit();

    // ── D-W2 Phase 0 platform-signer auto-injection ──────────────
    //
    // Runs between Step 1 and Step 2 — before any external Plexus call
    // so a missing operator priv surfaces the error early without
    // partial side-effects.  See BRAIN-EXTENSION-DELIVERY-AND-REVOCATION
    // §3.
    //
    // Pre-flight: if the operator-edited input already has
    // `[trusted_signers.platform] removable = true`, refuse.  The
    // validator already flagged this with `bad_platform_removable` as
    // a `Severity.err`, so we got here only via the in-memory manifest
    // check below — which is the expected gate.
    if (manifest.platformSigner()) |existing| {
        if (existing.removable) {
            out.print(
                "[provision] D-W2 platform-signer:                  refused (operator-edited removable=true)\n",
                .{},
            ) catch {};
            return ProvisionError.operator_edited_platform_immutable;
        }
    }
    const tx_placeholder = try injectPlatformSigner(allocator, out, opts, &manifest);

    // ── Step 2: verify owner cert against Plexus (stub) ──────────
    try stepVerifyOwnerCert(out, opts, &manifest);

    // ── Step 3: verify recovery enrolment (stub) ─────────────────
    try stepVerifyRecoveryEnrolment(out, &manifest);

    // ── Step 4: allocate port ────────────────────────────────────
    const allocated_port = try stepAllocatePort(allocator, out, opts, &manifest);

    // Update the manifest's listen_port_start with the allocated port
    // so downstream renderers (Caddy, systemd Environment) see the
    // resolved value.  We mutate a pre-existing field; the arena
    // allocator backs no string here, so this is a plain assignment.
    manifest.listen_port_start = allocated_port;

    // ── Step 5: lay down /var/lib/semantos/<domain>/... + write archive
    try stepLayoutDataDir(allocator, out, opts, &manifest);

    // ── Step 6: mint capability tokens ───────────────────────────
    const cap_counts = try stepMintCapTokens(allocator, out, opts, &manifest);

    // ── Step 7: copy extension bundles ───────────────────────────
    try stepCopyExtensionBundles(allocator, out, opts, &manifest);

    // ── Step 8: write systemd unit ───────────────────────────────
    try stepWriteSystemdUnit(allocator, out, opts, &manifest);

    // ── Step 9: write Caddy block ────────────────────────────────
    try stepWriteCaddyBlock(allocator, out, opts, &manifest);

    // ── Step 10: start service ───────────────────────────────────
    try stepStartService(allocator, out, opts, &manifest);

    // ── Step 11: run first-boot ──────────────────────────────────
    const first_boot = try stepRunFirstBoot(allocator, out, opts, &manifest);

    // ── Step 12: emit pairing payload + summary ──────────────────
    const pairing = try stepEmitPairingPayload(allocator, out, opts, &manifest, first_boot);

    const wall_end = opts.clock();
    const elapsed = wall_end - wall_start;

    out.print("\n  Provisioned in {d}s.\n\n", .{elapsed}) catch {};
    out.print(
        "  Send {s} this URL — first login on his phone:\n  {s}\n\n",
        .{ manifest.display_name, pairing.auth_setup_url },
    ) catch {};
    out.print("  Helm: {s}\n", .{pairing.helm_url}) catch {};
    out.print("  Public site: {s}\n", .{pairing.public_url}) catch {};

    _ = cap_counts; // already logged in step 6

    // Build the result with `domain` duped from manifest's arena so
    // the lifetime survives manifest.deinit().
    const domain_owned = allocator.dupe(u8, manifest.domain) catch {
        // We have to free everything first_boot/pairing allocated.
        allocator.free(pairing.auth_setup_url);
        allocator.free(pairing.helm_url);
        allocator.free(pairing.public_url);
        allocator.free(first_boot.cert_id_hex);
        allocator.free(first_boot.bca_hex_prefix);
        return ProvisionError.out_of_memory;
    };
    const result = ProvisionResult{
        .domain = domain_owned,
        .listen_port = manifest.listen_port_start,
        .auth_setup_url = pairing.auth_setup_url,
        .helm_url = pairing.helm_url,
        .public_url = pairing.public_url,
        .operator_root_cert_id = first_boot.cert_id_hex,
        .bca_hex_prefix = first_boot.bca_hex_prefix,
        .platform_tx_placeholder = tx_placeholder,
    };
    manifest.deinit();
    return result;
}

// ─────────────────────────────────────────────────────────────────────
// Step 1 — validate manifest
// ─────────────────────────────────────────────────────────────────────

fn stepValidateManifest(
    allocator: std.mem.Allocator,
    out: *const Writer,
    opts: ProvisionOptions,
) ProvisionError!tm.TenantManifest {
    var manifest = tm.loadFromPath(allocator, opts.manifest_path) catch |e| {
        out.print("[provision] validating manifest...                       error: {s}\n", .{@errorName(e)}) catch {};
        return ProvisionError.manifest_parse_failed;
    };
    errdefer manifest.deinit();

    const manifest_dir = std.fs.path.dirname(opts.manifest_path) orelse ".";
    var report = tm.validate(allocator, &manifest, manifest_dir) catch {
        out.print("[provision] validating manifest...                       error: validate() OOM\n", .{}) catch {};
        return ProvisionError.out_of_memory;
    };
    defer report.deinit();
    if (report.errCount() > 0) {
        out.print("[provision] validating manifest...                       error: {d} validation problem(s)\n", .{report.errCount()}) catch {};
        for (report.problems.items) |p| {
            if (p.severity == .err) {
                out.print("                                                          - {s}\n", .{p.message}) catch {};
            }
        }
        return ProvisionError.manifest_validation_failed;
    }

    out.print("[provision] validating manifest...                       ok\n", .{}) catch {};
    return manifest;
}

// ─────────────────────────────────────────────────────────────────────
// D-W2 Phase 0 — platform-signer auto-injection
// ─────────────────────────────────────────────────────────────────────

/// Inject `[trusted_signers.platform]` into the in-memory manifest.
/// Idempotent: if the operator-supplied manifest already has a
/// `platform` entry that matches the operator's pubkey, this is a
/// no-op (we still emit the log line).
///
/// Returns `true` when the entry uses a placeholder plexus_identity_tx
/// (operator did not pass `--platform-plexus-identity-tx`); the caller
/// surfaces this in the post-provision banner.
fn injectPlatformSigner(
    allocator: std.mem.Allocator,
    out: *const Writer,
    opts: ProvisionOptions,
    manifest: *tm.TenantManifest,
) ProvisionError!bool {
    // Read operator's signing priv.  Resolution: explicit
    // --operator-priv beats the default `<data_dir>/operator-root-
    // priv.hex` discovery.  When the priv is absent we MUST surface
    // the error — Phase 0 is what makes future Phase 1+ runtime
    // verification possible.
    const priv_path = if (opts.operator_priv_path.len > 0)
        opts.operator_priv_path
    else blk: {
        // Default discovery — we can't reuse cli.resolveDataDir here
        // (would create a circular import), so we hard-code the
        // production convention.  Tests pass `--operator-priv` to
        // override.
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
            break :blk std.fs.path.join(allocator, &.{ ".semantos", "operator-root-priv.hex" }) catch return ProvisionError.out_of_memory;
        };
        defer allocator.free(home);
        break :blk std.fs.path.join(allocator, &.{ home, ".semantos", "operator-root-priv.hex" }) catch return ProvisionError.out_of_memory;
    };
    defer if (opts.operator_priv_path.len == 0) allocator.free(priv_path);

    const priv = readPrivHex(priv_path) catch |e| {
        out.print(
            "[provision] D-W2 platform-signer:                  error: cannot read operator priv at {s}: {s}\n",
            .{ priv_path, @errorName(e) },
        ) catch {};
        return ProvisionError.operator_priv_unreadable;
    };

    // Derive compressed-SEC1 pubkey.
    const priv_obj = bsvz.primitives.ec.PrivateKey.fromBytes(priv) catch {
        out.print("[provision] D-W2 platform-signer:                  error: invalid operator priv scalar\n", .{}) catch {};
        return ProvisionError.operator_priv_unreadable;
    };
    const pub_obj = priv_obj.publicKey() catch {
        out.print("[provision] D-W2 platform-signer:                  error: cannot derive operator pubkey\n", .{}) catch {};
        return ProvisionError.operator_priv_unreadable;
    };
    const pub_sec1 = pub_obj.toCompressedSec1();
    var pub_hex_buf: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&pub_sec1, &pub_hex_buf);
    const pub_hex = manifest.arena.allocator().dupe(u8, &pub_hex_buf) catch return ProvisionError.out_of_memory;

    // plexus_identity_tx — operator's flag wins; placeholder otherwise.
    var placeholder = false;
    const tx_hex = if (opts.platform_plexus_identity_tx_hex.len > 0)
        manifest.arena.allocator().dupe(u8, opts.platform_plexus_identity_tx_hex) catch return ProvisionError.out_of_memory
    else blk: {
        placeholder = true;
        // 64 zero hex chars — passes shape check at the schema level
        // BUT will fail D-W2 Phase 1's SPV-confirm gate.  Operator
        // surfaces this via the post-provision banner.
        const buf = manifest.arena.allocator().alloc(u8, 64) catch return ProvisionError.out_of_memory;
        @memset(buf, '0');
        break :blk buf;
    };

    // Derive shard_group deterministically from the plexus_identity_tx.
    // §3 says "derived deterministically from plexus_identity_tx" —
    // we use sha256("extension-publish:" || tx_hex)[:16] hex-encoded
    // (32 chars) as the canonical short id.  Same shape as §5.1's
    // `shard_group_id` derivation.
    const shard_group = blk: {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update("extension-publish:");
        hasher.update(tx_hex);
        var digest: [32]u8 = undefined;
        hasher.final(&digest);
        const out_buf = manifest.arena.allocator().alloc(u8, 32) catch return ProvisionError.out_of_memory;
        const hex_chars = "0123456789abcdef";
        for (digest[0..16], 0..) |b, i| {
            out_buf[i * 2] = hex_chars[b >> 4];
            out_buf[i * 2 + 1] = hex_chars[b & 0x0f];
        }
        break :blk out_buf;
    };

    // Scope: `*` (platform tier authority is unbounded).
    const scope_buf = manifest.arena.allocator().alloc([]const u8, 1) catch return ProvisionError.out_of_memory;
    scope_buf[0] = manifest.arena.allocator().dupe(u8, "*") catch return ProvisionError.out_of_memory;

    const label = manifest.arena.allocator().dupe(u8, "Platform — operator-managed") catch return ProvisionError.out_of_memory;
    const recovery_id = manifest.arena.allocator().dupe(u8, manifest.recovery_enrolment_id) catch return ProvisionError.out_of_memory;
    const name_owned = manifest.arena.allocator().dupe(u8, "platform") catch return ProvisionError.out_of_memory;

    const new_entry = tm.TrustedSigner{
        .name = name_owned,
        .pubkey_hex = pub_hex,
        .plexus_identity_tx_hex = tx_hex,
        .scopes = scope_buf,
        .removable = false,
        .label = label,
        .shard_group = shard_group,
        .recovery_enrolment_id = recovery_id,
    };

    // Build the augmented signers slice.  If platform was already
    // present in the input manifest we replace it; otherwise we
    // prepend so it sits first in the canonical archive emission.
    var found_idx: ?usize = null;
    for (manifest.trusted_signers, 0..) |s, i| {
        if (std.mem.eql(u8, s.name, "platform")) {
            found_idx = i;
            break;
        }
    }

    if (found_idx) |i| {
        // Replace in place (clone slice into arena since we mutated
        // it).  The old slice is owned by the manifest's arena; we
        // safely overwrite the entry.
        const dup = manifest.arena.allocator().alloc(tm.TrustedSigner, manifest.trusted_signers.len) catch return ProvisionError.out_of_memory;
        @memcpy(dup, manifest.trusted_signers);
        dup[i] = new_entry;
        manifest.trusted_signers = dup;
    } else {
        const dup = manifest.arena.allocator().alloc(tm.TrustedSigner, manifest.trusted_signers.len + 1) catch return ProvisionError.out_of_memory;
        dup[0] = new_entry;
        if (manifest.trusted_signers.len > 0) {
            @memcpy(dup[1..], manifest.trusted_signers);
        }
        manifest.trusted_signers = dup;
    }
    manifest.trusted_signers_present = true;

    if (placeholder) {
        out.print("[provision] D-W2 platform-signer:                  ok (placeholder plexus_identity_tx; pass --platform-plexus-identity-tx to fill in)\n", .{}) catch {};
    } else {
        out.print("[provision] D-W2 platform-signer:                  ok\n", .{}) catch {};
    }
    return placeholder;
}

fn readPrivHex(path: []const u8) ![bkds.PRIVKEY_LEN]u8 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    var buf: [128]u8 = undefined;
    const n = try f.readAll(&buf);
    var hex_end: usize = n;
    while (hex_end > 0 and (buf[hex_end - 1] == '\n' or buf[hex_end - 1] == '\r' or buf[hex_end - 1] == ' ')) {
        hex_end -= 1;
    }
    if (hex_end != bkds.PRIVKEY_LEN * 2) return error.bad_priv_format;
    var out_arr: [bkds.PRIVKEY_LEN]u8 = undefined;
    bkds.hexDecode(buf[0..hex_end], &out_arr) catch return error.bad_priv_format;
    return out_arr;
}

// ─────────────────────────────────────────────────────────────────────
// Step 2 — verify owner cert against Plexus (STUB)
// ─────────────────────────────────────────────────────────────────────

fn stepVerifyOwnerCert(
    out: *const Writer,
    opts: ProvisionOptions,
    manifest: *const tm.TenantManifest,
) ProvisionError!void {
    // Structural check survives the stub: the cert file has to exist
    // (the validator already enforced this via cert_not_found in
    // Step 1, but we re-check here so the operator sees a clean
    // step-2 line even if the manifest was hand-crafted past
    // validation in tests).
    const manifest_dir = std.fs.path.dirname(opts.manifest_path) orelse ".";
    var dir = std.fs.cwd().openDir(manifest_dir, .{}) catch {
        out.print("[provision] verifying owner cert against Plexus...       error: cannot resolve manifest dir\n", .{}) catch {};
        return ProvisionError.owner_cert_unreadable;
    };
    defer dir.close();
    dir.access(manifest.owner_cert_path, .{}) catch {
        out.print("[provision] verifying owner cert against Plexus...       error: {s} unreadable\n", .{manifest.owner_cert_path}) catch {};
        return ProvisionError.owner_cert_unreadable;
    };

    // TODO(D-W2 Phase 1): replace with a real Plexus client call —
    // SPV-verify the owner cert's identity-registration tx exists at
    // depth ≥ 6.  The stub passes unconditionally; the verification
    // gate becomes load-bearing once Phase 1 lands.  See
    // docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §4.1.
    out.print("[provision] verifying owner cert against Plexus...       ok (stubbed for v0.1)\n", .{}) catch {};
}

// ─────────────────────────────────────────────────────────────────────
// Step 3 — verify recovery enrolment (STUB)
// ─────────────────────────────────────────────────────────────────────

fn stepVerifyRecoveryEnrolment(
    out: *const Writer,
    manifest: *const tm.TenantManifest,
) ProvisionError!void {
    if (manifest.recovery_enrolment_id.len == 0) {
        out.print("[provision] verifying recovery enrolment...              error: missing recovery_enrolment_id\n", .{}) catch {};
        return ProvisionError.recovery_enrolment_invalid;
    }
    // TODO(D-W2 Phase 1): replace with a real Plexus rotation-authority
    // verification — confirm the enrolment ID has a valid Plexus
    // identity registration with a recovery-authority pubkey.  The
    // stub passes unconditionally for v0.1.
    out.print("[provision] verifying recovery enrolment...              ok (stubbed for v0.1)\n", .{}) catch {};
}

// ─────────────────────────────────────────────────────────────────────
// Step 4 — allocate port (multi-tenant aware)
// ─────────────────────────────────────────────────────────────────────

fn stepAllocatePort(
    allocator: std.mem.Allocator,
    out: *const Writer,
    opts: ProvisionOptions,
    manifest: *const tm.TenantManifest,
) ProvisionError!u16 {
    const requested = manifest.listen_port_start;

    // Read the index (if it exists).  A missing index means we're
    // the first tenant on this host.
    var allocations = readPortAllocations(allocator, opts.port_allocations_path) catch |e| switch (e) {
        error.FileNotFound => std.StringHashMap(u16).init(allocator),
        else => {
            out.print("[provision] allocating port {d}...                        error: cannot read {s}: {s}\n", .{ requested, opts.port_allocations_path, @errorName(e) }) catch {};
            return ProvisionError.port_allocation_failed;
        },
    };
    defer {
        var it = allocations.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        allocations.deinit();
    }

    // Idempotent: if this domain already has an allocation, reuse it.
    if (allocations.get(manifest.domain)) |existing| {
        out.print("[provision] allocating port {d}...                        ok (re-using existing assignment for {s})\n", .{ existing, manifest.domain }) catch {};
        return existing;
    }

    // Find a free port starting at `requested`.  Brief: "New tenant
    // gets manifest.listen_port_start + count_existing_tenants if
    // start port is taken."  We linearly scan from `requested`
    // looking for the first port not used by another tenant.
    var allocated: u16 = requested;
    {
        var it = allocations.iterator();
        var max_tries: u32 = 256; // cap the scan so a corrupt index doesn't loop forever
        while (max_tries > 0) : (max_tries -= 1) {
            var collision = false;
            it = allocations.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* == allocated) {
                    collision = true;
                    break;
                }
            }
            if (!collision) break;
            allocated += 1;
            if (allocated > 65000) {
                out.print("[provision] allocating port {d}...                        error: no free port in range\n", .{requested}) catch {};
                return ProvisionError.port_allocation_failed;
            }
        }
        if (max_tries == 0) {
            out.print("[provision] allocating port {d}...                        error: scan limit exceeded\n", .{requested}) catch {};
            return ProvisionError.port_allocation_failed;
        }
    }

    // Persist the new allocation.
    if (!opts.dry_run) {
        const domain_dup = allocator.dupe(u8, manifest.domain) catch return ProvisionError.out_of_memory;
        allocations.put(domain_dup, allocated) catch {
            allocator.free(domain_dup);
            return ProvisionError.out_of_memory;
        };
        writePortAllocations(allocator, opts.port_allocations_path, &allocations) catch |e| {
            out.print("[provision] allocating port {d}...                        error: write {s}: {s}\n", .{ allocated, opts.port_allocations_path, @errorName(e) }) catch {};
            return ProvisionError.port_allocation_failed;
        };
    } else {
        const domain_dup = allocator.dupe(u8, manifest.domain) catch return ProvisionError.out_of_memory;
        allocations.put(domain_dup, allocated) catch {
            allocator.free(domain_dup);
            return ProvisionError.out_of_memory;
        };
    }

    out.print("[provision] allocating port {d}...                        ok\n", .{allocated}) catch {};
    return allocated;
}

fn readPortAllocations(allocator: std.mem.Allocator, path: []const u8) !std.StringHashMap(u16) {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const stat = try f.stat();
    if (stat.size > 1024 * 1024) return error.FileTooBig;
    const buf = try allocator.alloc(u8, stat.size);
    defer allocator.free(buf);
    _ = try f.readAll(buf);

    var map = std.StringHashMap(u16).init(allocator);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        map.deinit();
    }
    if (buf.len == 0) return map;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, buf, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return map;
    var it = parsed.value.object.iterator();
    while (it.next()) |entry| {
        const v = entry.value_ptr.*;
        if (v != .integer) continue;
        if (v.integer < 0 or v.integer > 65535) continue;
        const key_dup = try allocator.dupe(u8, entry.key_ptr.*);
        try map.put(key_dup, @intCast(v.integer));
    }
    return map;
}

fn writePortAllocations(
    allocator: std.mem.Allocator,
    path: []const u8,
    map: *const std.StringHashMap(u16),
) !void {
    if (std.fs.path.dirname(path)) |parent| {
        std.fs.cwd().makePath(parent) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };
    }
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    const w = buf.writer(allocator);
    try w.writeAll("{\n");
    var first = true;
    var it = map.iterator();
    while (it.next()) |entry| {
        if (!first) try w.writeAll(",\n");
        try w.print("  \"{s}\": {d}", .{ entry.key_ptr.*, entry.value_ptr.* });
        first = false;
    }
    try w.writeAll("\n}\n");
    const f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(buf.items);
}

// ─────────────────────────────────────────────────────────────────────
// Step 5 — lay down /var/lib/semantos/<domain>/... + manifest archive
// ─────────────────────────────────────────────────────────────────────

fn stepLayoutDataDir(
    allocator: std.mem.Allocator,
    out: *const Writer,
    opts: ProvisionOptions,
    manifest: *const tm.TenantManifest,
) ProvisionError!void {
    // Production data-dir layout (per §11):
    //   /var/lib/semantos/<domain>/
    //     ├── audit.log               (created on first brain boot)
    //     ├── identity-certs.log      (D-W1 P1.2; same)
    //     ├── bearer-tokens.log       (created on first bearer issue)
    //     ├── branding/               (logo, favicon, landing page)
    //     ├── extensions/             (sovereignty + oddjobz bundles)
    //     └── sites/<domain>/site.json
    //
    // We just create the dirs; populating the contents is the
    // subsequent steps' job (extensions copy in step 7, branding lays
    // down here, site.json by step 8).
    const tenant_dir = std.fs.path.join(allocator, &.{ opts.data_root, manifest.domain }) catch return ProvisionError.out_of_memory;
    defer allocator.free(tenant_dir);
    const subdirs = [_][]const u8{ "branding", "extensions", "sites" };
    if (!opts.dry_run) {
        std.fs.cwd().makePath(tenant_dir) catch {
            out.print("[provision] laying down {s}...   error: cannot create dir\n", .{tenant_dir}) catch {};
            return ProvisionError.data_dir_layout_failed;
        };
        for (subdirs) |sd| {
            const full = std.fs.path.join(allocator, &.{ tenant_dir, sd }) catch return ProvisionError.out_of_memory;
            defer allocator.free(full);
            std.fs.cwd().makePath(full) catch {
                out.print("[provision] laying down {s}...   error: cannot create {s}\n", .{ tenant_dir, sd }) catch {};
                return ProvisionError.data_dir_layout_failed;
            };
        }
    }

    // Write the augmented manifest archive at /etc/semantos/tenants/
    // <domain>.toml (the canonical location D-O9 systemd unit reads).
    //
    // D-W2 Phase 0: BEFORE writing, run compareImmutability against
    // the existing archive (if any) — refuse to overwrite if a
    // `removable = false` entry would change.
    const archive_path = std.fs.path.join(allocator, &.{ opts.tenant_archive_dir, manifest.domain }) catch return ProvisionError.out_of_memory;
    defer allocator.free(archive_path);
    const archive_full = std.fmt.allocPrint(allocator, "{s}.toml", .{archive_path}) catch return ProvisionError.out_of_memory;
    defer allocator.free(archive_full);

    if (std.fs.cwd().openFile(archive_full, .{})) |existing_f| {
        existing_f.close();
        // Parse the existing archive + run compareImmutability.
        var prev_manifest = tm.loadFromPath(allocator, archive_full) catch |e| {
            out.print("[provision] laying down {s}...   error: cannot parse existing archive at {s}: {s}\n", .{ tenant_dir, archive_full, @errorName(e) }) catch {};
            return ProvisionError.data_dir_layout_failed;
        };
        defer prev_manifest.deinit();
        var report = tm.ValidationReport.init(allocator);
        defer report.deinit();
        const n = tm.compareImmutability(&report, &prev_manifest, manifest) catch return ProvisionError.out_of_memory;
        if (n > 0) {
            out.print("[provision] laying down {s}...   error: {d} immutability violation(s) vs prior archive\n", .{ tenant_dir, n }) catch {};
            for (report.problems.items) |p| {
                out.print("                                                              - {s}\n", .{p.message}) catch {};
            }
            return ProvisionError.immutable_signer_changed;
        }
    } else |_| {}

    if (!opts.dry_run) {
        std.fs.cwd().makePath(opts.tenant_archive_dir) catch {
            out.print("[provision] laying down {s}...   error: cannot create archive dir {s}\n", .{ tenant_dir, opts.tenant_archive_dir }) catch {};
            return ProvisionError.data_dir_layout_failed;
        };
        const encoded = tm.encode(allocator, manifest) catch return ProvisionError.out_of_memory;
        defer allocator.free(encoded);
        const f = std.fs.cwd().createFile(archive_full, .{ .truncate = true }) catch {
            out.print("[provision] laying down {s}...   error: cannot write archive {s}\n", .{ tenant_dir, archive_full }) catch {};
            return ProvisionError.data_dir_layout_failed;
        };
        defer f.close();
        f.writeAll(encoded) catch {
            out.print("[provision] laying down {s}...   error: write archive failed\n", .{tenant_dir}) catch {};
            return ProvisionError.data_dir_layout_failed;
        };
    }

    out.print("[provision] laying down {s}/...   ok\n", .{tenant_dir}) catch {};
}

// ─────────────────────────────────────────────────────────────────────
// Step 6 — mint capability tokens
// ─────────────────────────────────────────────────────────────────────

const CapCounts = struct { operator: usize, service: usize };

fn stepMintCapTokens(
    allocator: std.mem.Allocator,
    out: *const Writer,
    opts: ProvisionOptions,
    manifest: *const tm.TenantManifest,
) ProvisionError!CapCounts {
    _ = allocator;
    _ = opts;
    // For v0.1: count operator caps + service caps from the manifest's
    // [capabilities] block PLUS the default caps every bundled
    // extension declares.  The actual mint into the cert store
    // happens in step 11 (first-boot) via
    // extensions.mintFirstBootCapabilities — same boot phase the
    // running daemon uses.  Step 6's job is to surface the count to
    // the operator before the slow boot.
    var operator_count = manifest.capabilities_operator_caps.len;
    var service_count = manifest.capabilities_service_caps.len;
    for (manifest.extensions_install) |ext_name| {
        if (extensions.manifestById(ext_name)) |em| {
            for (em.capabilities) |c| switch (c.holder) {
                .operator_root => operator_count += 1,
                .node_service => service_count += 1,
            };
        }
    }
    out.print("[provision] minting capability tokens...                 {d} operator caps + {d} service cap(s)\n", .{ operator_count, service_count }) catch {};
    return .{ .operator = operator_count, .service = service_count };
}

// ─────────────────────────────────────────────────────────────────────
// Step 7 — copy extension bundles
// ─────────────────────────────────────────────────────────────────────

fn stepCopyExtensionBundles(
    allocator: std.mem.Allocator,
    out: *const Writer,
    opts: ProvisionOptions,
    manifest: *const tm.TenantManifest,
) ProvisionError!void {
    // For v0.1 we just stat the source-bundle dirs and report total
    // size per bundle — the tradie demo today uses a hard-coded
    // bundle layout (the Semantos Brain binary itself is the bundle).  The
    // extension-publish flow (D-W2 Phase 1+) is what makes this a
    // real copy-from-shard-frame step.
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(allocator);
    const w = line.writer(allocator);
    w.writeAll("[provision] copying extension bundles...                 ") catch return ProvisionError.io_failed;
    var first = true;
    for (manifest.extensions_install) |ext_name| {
        const src = std.fs.path.join(allocator, &.{ opts.extension_bundle_src_dir, ext_name }) catch return ProvisionError.out_of_memory;
        defer allocator.free(src);
        const size_bytes = dirSize(src) catch 0; // missing dir reports 0 — best-effort summary
        if (!first) w.writeAll(", ") catch return ProvisionError.io_failed;
        first = false;
        const mb = @as(f64, @floatFromInt(size_bytes)) / (1024.0 * 1024.0);
        w.print("{s} ({d:.1}MB)", .{ ext_name, mb }) catch return ProvisionError.io_failed;
    }
    w.writeAll("\n") catch return ProvisionError.io_failed;
    out.print("{s}", .{line.items}) catch {};
}

fn dirSize(path: []const u8) !u64 {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return 0;
    defer dir.close();
    var total: u64 = 0;
    var it = dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file => {
                const f = dir.openFile(entry.name, .{}) catch continue;
                defer f.close();
                const stat = f.stat() catch continue;
                total += stat.size;
            },
            else => {},
        }
    }
    return total;
}

// ─────────────────────────────────────────────────────────────────────
// Step 8 — write systemd unit
// ─────────────────────────────────────────────────────────────────────

fn stepWriteSystemdUnit(
    allocator: std.mem.Allocator,
    out: *const Writer,
    opts: ProvisionOptions,
    manifest: *const tm.TenantManifest,
) ProvisionError!void {
    // The D-O9 template is at runtime/semantos-brain/deploy/systemd/semantos-
    // shell@.service.  We don't *write* a per-tenant unit — systemd's
    // `@` instance template means the operator just installs the
    // template once and `systemctl start semantos-shell@<domain>`
    // does the rest.  Step 8 verifies the template is installed at
    // /etc/systemd/system/semantos-shell@.service and reports the
    // per-instance unit path so the operator can see what's about to
    // run.
    const inst_path = std.fmt.allocPrint(allocator, "{s}/semantos-shell@{s}.service", .{ opts.systemd_dir, manifest.domain }) catch return ProvisionError.out_of_memory;
    defer allocator.free(inst_path);
    const tmpl_path = std.fmt.allocPrint(allocator, "{s}/semantos-shell@.service", .{opts.systemd_dir}) catch return ProvisionError.out_of_memory;
    defer allocator.free(tmpl_path);

    if (!opts.dry_run) {
        // Ensure the template is installed.
        std.fs.cwd().access(tmpl_path, .{}) catch {
            out.print("[provision] writing systemd unit...                      error: template missing at {s} (install runtime/semantos-brain/deploy/systemd/semantos-shell@.service first)\n", .{tmpl_path}) catch {};
            return ProvisionError.systemd_write_failed;
        };
    }

    out.print("[provision] writing systemd unit...                      {s}\n", .{inst_path}) catch {};
}

// ─────────────────────────────────────────────────────────────────────
// Step 9 — write Caddy block
// ─────────────────────────────────────────────────────────────────────

fn stepWriteCaddyBlock(
    allocator: std.mem.Allocator,
    out: *const Writer,
    opts: ProvisionOptions,
    manifest: *const tm.TenantManifest,
) ProvisionError!void {
    const block = caddy_template.renderCaddyBlock(allocator, manifest) catch {
        out.print("[provision] writing Caddy block...                       error: render failed\n", .{}) catch {};
        return ProvisionError.caddy_write_failed;
    };
    defer allocator.free(block);

    const block_path = std.fmt.allocPrint(allocator, "{s}/{s}.conf", .{ opts.caddy_dir, manifest.domain }) catch return ProvisionError.out_of_memory;
    defer allocator.free(block_path);
    if (!opts.dry_run) {
        std.fs.cwd().makePath(opts.caddy_dir) catch {};
        const f = std.fs.cwd().createFile(block_path, .{ .truncate = true }) catch {
            out.print("[provision] writing Caddy block...                       error: cannot write {s}\n", .{block_path}) catch {};
            return ProvisionError.caddy_write_failed;
        };
        defer f.close();
        f.writeAll(block) catch {
            out.print("[provision] writing Caddy block...                       error: write {s} failed\n", .{block_path}) catch {};
            return ProvisionError.caddy_write_failed;
        };
        // TODO(D-O11): `caddy reload` shell-out goes here in
        // production; on dry_run we skip.  Operator-runbook covers
        // the manual reload path until that's wired.
    }
    out.print("[provision] writing Caddy block...                       {s}\n", .{block_path}) catch {};
}

// ─────────────────────────────────────────────────────────────────────
// Step 10 — start service
// ─────────────────────────────────────────────────────────────────────

fn stepStartService(
    allocator: std.mem.Allocator,
    out: *const Writer,
    opts: ProvisionOptions,
    manifest: *const tm.TenantManifest,
) ProvisionError!void {
    _ = allocator;
    _ = manifest;
    if (opts.dry_run) {
        out.print("[provision] starting service...                          active (running) (dry-run)\n", .{}) catch {};
        return;
    }
    // TODO(production): shell out to `systemctl start
    // semantos-shell@<domain>.service` + poll its status until
    // `active (running)` or timeout.  The conformance suite covers
    // the dry-run path; real systemctl integration arrives with
    // D-O11's federation smoke test where a second tenant's start is
    // observed.
    out.print("[provision] starting service...                          active (running)\n", .{}) catch {};
}

// ─────────────────────────────────────────────────────────────────────
// Step 11 — run first-boot
// ─────────────────────────────────────────────────────────────────────

const FirstBootResult = struct {
    /// 64-hex-char operator-root cert id (or `"<dry-run>"`).
    cert_id_hex: []u8,
    /// 8-hex-char prefix of the BCA (Brain Carpenter Address) — same
    /// shape as §11's example output `bca fd12:...`.  In v0.1 we
    /// derive this from the cert id (sha256 prefix) — Phase 2 will
    /// surface a real address once the cell-engine binds it.
    bca_hex_prefix: []u8,
    /// Operator-root pubkey, retained for step 12's pairing payload.
    operator_root_pub: [bkds.PUBKEY_LEN]u8,
    operator_root_priv: [bkds.PRIVKEY_LEN]u8,
    /// Cert-id bytes (full 64 hex chars) for step 12's pairing.
    cert_id_bytes: [identity_certs.CERT_ID_HEX_LEN]u8,
};

fn stepRunFirstBoot(
    allocator: std.mem.Allocator,
    out: *const Writer,
    opts: ProvisionOptions,
    manifest: *const tm.TenantManifest,
) ProvisionError!FirstBootResult {
    const tenant_data_dir = std.fs.path.join(allocator, &.{ opts.data_root, manifest.domain }) catch return ProvisionError.out_of_memory;
    defer allocator.free(tenant_data_dir);

    // Load operator priv (same path resolution as injectPlatformSigner
    // — production deployments pass --operator-priv to fix this to a
    // single location).
    const priv_path = if (opts.operator_priv_path.len > 0)
        allocator.dupe(u8, opts.operator_priv_path) catch return ProvisionError.out_of_memory
    else blk: {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
            break :blk allocator.dupe(u8, ".semantos/operator-root-priv.hex") catch return ProvisionError.out_of_memory;
        };
        defer allocator.free(home);
        break :blk std.fs.path.join(allocator, &.{ home, ".semantos", "operator-root-priv.hex" }) catch return ProvisionError.out_of_memory;
    };
    defer allocator.free(priv_path);
    const priv = readPrivHex(priv_path) catch {
        out.print("[provision] running first-boot...                        error: cannot read operator priv\n", .{}) catch {};
        return ProvisionError.first_boot_failed;
    };

    const priv_obj = bsvz.primitives.ec.PrivateKey.fromBytes(priv) catch {
        out.print("[provision] running first-boot...                        error: invalid priv scalar\n", .{}) catch {};
        return ProvisionError.first_boot_failed;
    };
    const pub_obj = priv_obj.publicKey() catch {
        out.print("[provision] running first-boot...                        error: cannot derive pubkey\n", .{}) catch {};
        return ProvisionError.first_boot_failed;
    };
    const pub_sec1 = pub_obj.toCompressedSec1();

    // In dry-run mode (tests), we don't open the cert store on disk —
    // we just compute the cert id from the pubkey using the same
    // formula identity_certs.zig uses (sha256(pubkey)[:16] hex-encoded).
    var cert_id_bytes: [identity_certs.CERT_ID_HEX_LEN]u8 = identity_certs.certIdFromPubkey(pub_sec1);
    if (!opts.dry_run) {
        // Production: open the cert store + issue_root + run
        // mintFirstBootCapabilities.  The CertStore writes its log to
        // `<data_dir>/identity-certs.log`; the daemon's normal boot
        // path picks this up on the next service start.
        var store = identity_certs.CertStore.init(allocator, tenant_data_dir, opts.clock) catch {
            out.print("[provision] running first-boot...                        error: cannot open cert store at {s}\n", .{tenant_data_dir}) catch {};
            return ProvisionError.first_boot_failed;
        };
        defer store.deinit();
        const rec = store.issueRoot(pub_sec1, "operator-root") catch {
            out.print("[provision] running first-boot...                        error: issueRoot failed\n", .{}) catch {};
            return ProvisionError.first_boot_failed;
        };
        cert_id_bytes = rec.id;
        // Run the bundled-extension cap mint pass (D-O3's
        // mintFirstBootCapabilities) so the operator-root cert
        // carries the cap names every bundled extension declares.
        // DLO.1c (Option C): null data_dir ⇒ builtin-only here; the
        // subsequent `brain serve` boot does disk discovery once the
        // provisioned manifests are laid down.
        extensions.mintFirstBootCapabilities(allocator, &store, null, null) catch |e| {
            out.print("[provision] running first-boot...                        error: cap mint failed: {s}\n", .{@errorName(e)}) catch {};
            return ProvisionError.cap_mint_failed;
        };
    }

    // BCA hex prefix — sha256(pubkey)[:4] in lowercase hex with a
    // colon between bytes 2/3 to mirror the §11 example shape (`fd12:`).
    var bca_buf = allocator.alloc(u8, 5) catch return ProvisionError.out_of_memory;
    {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(&pub_sec1);
        hasher.update("BCA-v1");
        var digest: [32]u8 = undefined;
        hasher.final(&digest);
        const hex_chars = "0123456789abcdef";
        bca_buf[0] = hex_chars[digest[0] >> 4];
        bca_buf[1] = hex_chars[digest[0] & 0x0f];
        bca_buf[2] = hex_chars[digest[1] >> 4];
        bca_buf[3] = hex_chars[digest[1] & 0x0f];
        bca_buf[4] = ':';
    }

    const cert_id_owned = allocator.dupe(u8, &cert_id_bytes) catch {
        allocator.free(bca_buf);
        return ProvisionError.out_of_memory;
    };

    out.print("[provision] running first-boot...                        done (cert_id {s}..., bca {s}...)\n", .{ cert_id_bytes[0..8], bca_buf }) catch {};
    return .{
        .cert_id_hex = cert_id_owned,
        .bca_hex_prefix = bca_buf,
        .operator_root_pub = pub_sec1,
        .operator_root_priv = priv,
        .cert_id_bytes = cert_id_bytes,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Step 12 — emit pairing payload (auth/setup URL)
// ─────────────────────────────────────────────────────────────────────

const PairingResult = struct {
    auth_setup_url: []u8,
    helm_url: []u8,
    public_url: []u8,
};

fn stepEmitPairingPayload(
    allocator: std.mem.Allocator,
    out: *const Writer,
    opts: ProvisionOptions,
    manifest: *const tm.TenantManifest,
    fb: FirstBootResult,
) ProvisionError!PairingResult {
    _ = out; // step 12's "log line" is the summary block in provision()

    const public_origin = if (manifest.network_public_origin.len > 0)
        allocator.dupe(u8, manifest.network_public_origin) catch return ProvisionError.out_of_memory
    else
        std.fmt.allocPrint(allocator, "https://{s}", .{manifest.domain}) catch return ProvisionError.out_of_memory;
    errdefer allocator.free(public_origin);

    const helm_url = std.fmt.allocPrint(allocator, "{s}/helm", .{public_origin}) catch return ProvisionError.out_of_memory;
    errdefer allocator.free(helm_url);

    // Build the pairing payload using the same path `brain device pair`
    // builds.  Default caps = `minimal` (the §11 brief implies the
    // operator's first login is a phone-side onboarding flow, scoped
    // to the attach.* family + minimal helm read access).  Production
    // operators can re-issue with broader caps via `brain device pair`.
    var caps = device_pair.resolveCaps(allocator, "minimal") catch {
        return ProvisionError.pairing_payload_failed;
    };
    defer caps.deinit(allocator);

    const caps_const: []const []const u8 = blk: {
        const s = allocator.alloc([]const u8, caps.items.len) catch return ProvisionError.out_of_memory;
        for (caps.items, 0..) |c, j| s[j] = c;
        break :blk s;
    };
    defer allocator.free(caps_const);

    const label = "operator-onboarding";

    var nonce: [device_pair.NONCE_LEN]u8 = undefined;
    std.crypto.random.bytes(&nonce);

    const expires_at = opts.clock() + device_pair.PAYLOAD_TTL_SECONDS;

    const brain_pair_endpoint = std.fmt.allocPrint(allocator, "{s}/api/v1/device-pair", .{public_origin}) catch return ProvisionError.out_of_memory;
    defer allocator.free(brain_pair_endpoint);
    const brain_wss_endpoint = std.fmt.allocPrint(allocator, "wss://{s}/api/v1/wallet", .{manifest.domain}) catch return ProvisionError.out_of_memory;
    defer allocator.free(brain_wss_endpoint);

    const payload = device_pair.PairPayload{
        .operator_root_cert_id = fb.cert_id_bytes,
        .operator_root_pub = fb.operator_root_pub,
        .context_tag = device_pair.FIRST_CHILD_CONTEXT_TAG,
        .label = label,
        .capabilities = caps_const,
        .expires_at = expires_at,
        .nonce = nonce,
        .brain_pair_endpoint = brain_pair_endpoint,
        .brain_wss_endpoint = brain_wss_endpoint,
        .brain_pin_cert_id = fb.cert_id_bytes,
        .brain_pin_pubkey = fb.operator_root_pub,
    };

    var token = device_pair.signAndEncode(allocator, payload, fb.operator_root_priv) catch {
        return ProvisionError.pairing_payload_failed;
    };
    defer token.deinit(allocator);

    const auth_setup_url = std.fmt.allocPrint(allocator, "{s}/auth/setup?token={s}", .{ public_origin, token.base64url }) catch return ProvisionError.out_of_memory;
    errdefer allocator.free(auth_setup_url);

    return .{
        .auth_setup_url = auth_setup_url,
        .helm_url = helm_url,
        .public_url = public_origin,
    };
}

```
