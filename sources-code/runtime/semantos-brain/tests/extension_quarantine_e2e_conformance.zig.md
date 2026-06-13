---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/extension_quarantine_e2e_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.196409+00:00
---

# runtime/semantos-brain/tests/extension_quarantine_e2e_conformance.zig

```zig
// Phase D-W2 Phase 4 — extension quarantine end-to-end conformance.
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md
//   §7 Phase 4 (deliverable), §3 (`quarantine_on_revoke` top-level
//   option), §6/§10 (quarantine semantics).
//
// Scenarios covered (pure-Zig — no bsvz signing — runs in both
// build modes):
//
//   1. Quarantine on signer revocation:
//        install an extension via Phase 2's apply seam (write
//        bundle.bin + meta.json), publish a nullifier targeting
//        the signer (Phase 3's apply path), verify the extension
//        transitions to quarantined; dispatch returns
//        `handler_quarantined`; bundle file still on disk.
//
//   2. Re-evaluate after rotation:
//        rotate signer X to X', call evaluateQuarantine →
//        quarantined → active; dispatch resumes.
//
//   3. Hard remove via the operator path:
//        run quarantine.hardRemove → bundle file deleted, dispatcher
//        unmarked, `removed` record appended.
//
//   4. Hard-delete-on-revoke via `quarantine_on_revoke = false`:
//        revoke signer with the flag off → extensions are HARD
//        REMOVED in one apply; no quarantine record.
//
//   5. Multiple extensions per signer:
//        signer X has 3 installed extensions; revoke X → all 3
//        transition to quarantine in one apply.
//
//   6. Quarantine doesn't break dispatch for OTHER extensions:
//        signer X is revoked + extensions quarantined, signer Y's
//        extensions remain dispatchable.
//
// Notes:
//   • The "install" path is exercised through extension_subscriber.
//     applyVerifiedFrame, which is what the Phase 2 receive
//     pipeline calls.  We synthesise a VerifiedFrame directly (skipping
//     the BRC-12 outer + BSV signature verify — those are tested in
//     extension_subscribe_e2e_conformance.zig).
//   • The "revoke" path is exercised through extension_nullifier.
//     applyNullifierWithQuarantine directly, with a minimally-
//     populated VerifiedNullifier.  Manifest text rewriting + the
//     quarantine walk are both stub-mode-safe.

const std = @import("std");
const subscriber = @import("extension_subscriber");
const quarantine = @import("extension_quarantine");
const nullifier_mod = @import("extension_nullifier");
const tenant_manifest = @import("tenant_manifest");
const dispatcher_mod = @import("dispatcher");
const audit_log_mod = @import("audit_log");

// ─────────────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────────────

const SIGNER_X_PUBKEY: [33]u8 = .{0x02} ++ [_]u8{0xaa} ** 32;
const SIGNER_X_PUBKEY_HEX: []const u8 = "02" ++ ("aa" ** 32);
const SIGNER_Y_PUBKEY: [33]u8 = .{0x02} ++ [_]u8{0xbb} ** 32;
const SIGNER_Y_PUBKEY_HEX: []const u8 = "02" ++ ("bb" ** 32);
const SIGNER_X_NEW_PUBKEY: [33]u8 = .{0x03} ++ [_]u8{0xcc} ** 32;
const SIGNER_X_NEW_PUBKEY_HEX: []const u8 = "03" ++ ("cc" ** 32);

const TenantTomlOptions = struct {
    signer_x_pubkey_hex: []const u8 = SIGNER_X_PUBKEY_HEX,
    signer_y_pubkey_hex: []const u8 = SIGNER_Y_PUBKEY_HEX,
    quarantine_on_revoke: bool = true,
    include_y: bool = true,
};

fn writeTenantToml(
    allocator: std.mem.Allocator,
    path: []const u8,
    opts: TenantTomlOptions,
) !void {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    try buf.print(allocator,
        \\[tenant]
        \\domain = "x.example"
        \\display_name = "fixture"
        \\owner_cert_path = "/dev/null"
        \\recovery_enrolment_id = "plexus-rec-fixture"
        \\
        \\[extensions]
        \\install = []
        \\
        \\[branding]
        \\landing_page_template = "default"
        \\brand_color = "#000000"
        \\
        \\[trusted_signers]
        \\require_spv = true
        \\quarantine_on_revoke = {s}
        \\
        \\[trusted_signers.x_signer]
        \\pubkey = "{s}"
        \\plexus_identity_tx = "00ff"
        \\scope = "x.*"
        \\removable = true
        \\label = "X Signer"
        \\shard_group = "deadbeef"
        \\
    , .{
        if (opts.quarantine_on_revoke) "true" else "false",
        opts.signer_x_pubkey_hex,
    });
    if (opts.include_y) {
        try buf.print(allocator,
            \\[trusted_signers.y_signer]
            \\pubkey = "{s}"
            \\plexus_identity_tx = "11ee"
            \\scope = "y.*"
            \\removable = true
            \\label = "Y Signer"
            \\shard_group = "beefcafe"
            \\
        , .{opts.signer_y_pubkey_hex});
    }

    if (std.fs.path.dirname(path)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }
    const f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(buf.items);
}

/// Walk the Phase 2 apply seam: write the bundle bytes + meta.json
/// next to it.  We bypass the full SPV+sig pipeline (covered by
/// extension_subscribe_e2e_conformance.zig) — for Phase 4 we just
/// need a credible on-disk install state.
fn installExtensionUnderSigner(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    extension_name: []const u8,
    version: []const u8,
    signer_pubkey: [33]u8,
    signer_name: []const u8,
) !void {
    const bundle_bytes = "fixture-bundle";
    var bundle_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bundle_bytes, &bundle_hash, .{});
    const vf = subscriber.VerifiedFrame{
        .signer_name = signer_name,
        .bundle_bytes = bundle_bytes,
        .publish_txid_display = .{0xdd} ** 32,
        .extension_name = extension_name,
        .version = version,
        .bundle_hash = bundle_hash,
        .signer_pubkey = signer_pubkey,
    };
    var outcome = try subscriber.applyVerifiedFrame(allocator, vf, data_dir, null, null);
    defer outcome.deinit(allocator);
}

/// Build a VerifiedNullifier targeting the signer named `name` in the
/// fixture manifest.  Reason = compromised, no replacement (pure
/// revocation case).
fn makeRevokeNullifier(name: []const u8, pubkey: [33]u8) nullifier_mod.VerifiedNullifier {
    return .{
        .payload = .{
            .revoked_pubkey = pubkey,
            .reason_code = .compromised,
            .timestamp = 1_700_000_000,
        },
        .target_signer_name = name,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Scenarios
// ─────────────────────────────────────────────────────────────────────

test "scenario 1 — quarantine on signer revocation; bundle preserved + dispatcher returns handler_quarantined" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    // Set up tenant manifest with signer X.
    const manifest_path = try std.fs.path.join(allocator, &.{ data_dir, "tenant.toml" });
    defer allocator.free(manifest_path);
    try writeTenantToml(allocator, manifest_path, .{});

    const revoked_index_path = try std.fs.path.join(allocator, &.{ data_dir, "extension-revoked-keys.json" });
    defer allocator.free(revoked_index_path);

    // Install one extension under signer X.
    try installExtensionUnderSigner(allocator, data_dir, "x.foo", "0.1.0", SIGNER_X_PUBKEY, "x_signer");

    // Stand up a dispatcher and pre-register the extension as a
    // resource (Phase 2 metadata-only registration shape).
    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();
    try disp.register(.{
        .name = "x.foo",
        .state = null,
        .cap_for_cmd_fn = stubCapForCmd,
        .handle_fn = stubHandle,
    });

    // Sanity: pre-revocation dispatch succeeds.
    const ctx = dispatcher_mod.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "t1" },
    };
    var pre = try disp.dispatch(&ctx, "x.foo", "ping", "{}");
    pre.deinit();

    // Apply the nullifier with quarantine on.
    const vn = makeRevokeNullifier("x_signer", SIGNER_X_PUBKEY);
    var outcome = try nullifier_mod.applyNullifierWithQuarantine(
        allocator,
        vn,
        manifest_path,
        revoked_index_path,
        data_dir,
        &disp,
        true, // quarantine_on_revoke
        null,
    );
    defer outcome.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 1), outcome.quarantined);
    try std.testing.expect(disp.isQuarantined("x.foo"));
    try std.testing.expectError(
        dispatcher_mod.DispatchError.handler_quarantined,
        disp.dispatch(&ctx, "x.foo", "ping", "{}"),
    );

    // Bundle file still on disk.
    const bundle_path = try std.fs.path.join(allocator, &.{ data_dir, "extensions", "x.foo", "0.1.0", "bundle.bin" });
    defer allocator.free(bundle_path);
    const f = try std.fs.cwd().openFile(bundle_path, .{});
    f.close();
}

test "scenario 2 — evaluateQuarantine flips quarantined → active when a fresh signer covers the namespace" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const manifest_path = try std.fs.path.join(allocator, &.{ data_dir, "tenant.toml" });
    defer allocator.free(manifest_path);
    try writeTenantToml(allocator, manifest_path, .{});
    const revoked_index_path = try std.fs.path.join(allocator, &.{ data_dir, "extension-revoked-keys.json" });
    defer allocator.free(revoked_index_path);

    try installExtensionUnderSigner(allocator, data_dir, "x.foo", "0.1.0", SIGNER_X_PUBKEY, "x_signer");

    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();

    // Quarantine via revocation.
    const vn = makeRevokeNullifier("x_signer", SIGNER_X_PUBKEY);
    var outcome = try nullifier_mod.applyNullifierWithQuarantine(
        allocator,
        vn,
        manifest_path,
        revoked_index_path,
        data_dir,
        &disp,
        true,
        null,
    );
    defer outcome.deinit(allocator);
    try std.testing.expect(disp.isQuarantined("x.foo"));

    // Simulate post-rotation: write a fresh manifest where signer X
    // now covers the same scope under a NEW pubkey.  (In production,
    // applyNullifierWithQuarantine in rotation mode would rewrite
    // the manifest to carry the new pubkey; for Phase 4 we just need
    // the post-state.)
    try writeTenantToml(allocator, manifest_path, .{ .signer_x_pubkey_hex = SIGNER_X_NEW_PUBKEY_HEX });

    var manifest = try tenant_manifest.loadFromPath(allocator, manifest_path);
    defer manifest.deinit();
    const eval = try quarantine.evaluateQuarantine(
        allocator,
        data_dir,
        "x.foo",
        manifest.trusted_signers,
        &disp,
        null,
    );
    try std.testing.expect(eval.transitioned_to_active);
    try std.testing.expectEqual(quarantine.QuarantineState.active, eval.state);
    try std.testing.expect(!disp.isQuarantined("x.foo"));
}

test "scenario 2b — evaluate is idempotent on already-active extensions" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    const manifest_path = try std.fs.path.join(allocator, &.{ data_dir, "tenant.toml" });
    defer allocator.free(manifest_path);
    try writeTenantToml(allocator, manifest_path, .{});

    var manifest = try tenant_manifest.loadFromPath(allocator, manifest_path);
    defer manifest.deinit();
    const eval = try quarantine.evaluateQuarantine(
        allocator,
        data_dir,
        "x.foo",
        manifest.trusted_signers,
        null,
        null,
    );
    try std.testing.expect(eval.no_op);
    try std.testing.expect(!eval.transitioned_to_active);
}

test "scenario 3 — operator hard-remove deletes the bundle + appends a `removed` record" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const manifest_path = try std.fs.path.join(allocator, &.{ data_dir, "tenant.toml" });
    defer allocator.free(manifest_path);
    try writeTenantToml(allocator, manifest_path, .{});
    const revoked_index_path = try std.fs.path.join(allocator, &.{ data_dir, "extension-revoked-keys.json" });
    defer allocator.free(revoked_index_path);

    try installExtensionUnderSigner(allocator, data_dir, "x.foo", "0.1.0", SIGNER_X_PUBKEY, "x_signer");

    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();

    const vn = makeRevokeNullifier("x_signer", SIGNER_X_PUBKEY);
    var outcome = try nullifier_mod.applyNullifierWithQuarantine(
        allocator,
        vn,
        manifest_path,
        revoked_index_path,
        data_dir,
        &disp,
        true,
        null,
    );
    defer outcome.deinit(allocator);

    // Now the operator drives the hard remove.
    const install_path = try std.fs.path.join(allocator, &.{ data_dir, "extensions", "x.foo", "0.1.0" });
    defer allocator.free(install_path);
    const removal = quarantine.QuarantineRecord{
        .extension_name = "x.foo",
        .version = "0.1.0",
        .signer_pubkey_hex = SIGNER_X_PUBKEY_HEX,
        .state = .removed,
        .quarantined_at = 1_700_000_500,
        .reason = .operator_remove,
        .original_install_path = install_path,
        .previous_state = .quarantined,
    };
    try quarantine.hardRemove(allocator, data_dir, removal, &disp, null);

    // Bundle gone.
    const bundle_path = try std.fs.path.join(allocator, &.{ data_dir, "extensions", "x.foo", "0.1.0", "bundle.bin" });
    defer allocator.free(bundle_path);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().openFile(bundle_path, .{}));

    // Latest record is `removed`.
    const recs = try quarantine.loadLatestRecords(allocator, data_dir);
    defer quarantine.freeRecords(allocator, recs);
    try std.testing.expect(recs.len == 1);
    try std.testing.expectEqual(quarantine.QuarantineState.removed, recs[0].state);
    try std.testing.expectEqual(quarantine.QuarantineReason.operator_remove, recs[0].reason);
}

test "scenario 4 — quarantine_on_revoke=false hard-removes instead of quarantining" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const manifest_path = try std.fs.path.join(allocator, &.{ data_dir, "tenant.toml" });
    defer allocator.free(manifest_path);
    try writeTenantToml(allocator, manifest_path, .{ .quarantine_on_revoke = false });
    const revoked_index_path = try std.fs.path.join(allocator, &.{ data_dir, "extension-revoked-keys.json" });
    defer allocator.free(revoked_index_path);

    try installExtensionUnderSigner(allocator, data_dir, "x.foo", "0.1.0", SIGNER_X_PUBKEY, "x_signer");

    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();

    // Apply with quarantine_on_revoke=false.
    const vn = makeRevokeNullifier("x_signer", SIGNER_X_PUBKEY);
    var outcome = try nullifier_mod.applyNullifierWithQuarantine(
        allocator,
        vn,
        manifest_path,
        revoked_index_path,
        data_dir,
        &disp,
        false, // hard-delete-on-revoke
        null,
    );
    defer outcome.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 1), outcome.quarantined);
    // Bundle gone.
    const bundle_path = try std.fs.path.join(allocator, &.{ data_dir, "extensions", "x.foo", "0.1.0", "bundle.bin" });
    defer allocator.free(bundle_path);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().openFile(bundle_path, .{}));

    // Latest record is `removed` with reason `revoke_hard_delete`.
    const recs = try quarantine.loadLatestRecords(allocator, data_dir);
    defer quarantine.freeRecords(allocator, recs);
    try std.testing.expect(recs.len == 1);
    try std.testing.expectEqual(quarantine.QuarantineState.removed, recs[0].state);
    try std.testing.expectEqual(quarantine.QuarantineReason.revoke_hard_delete, recs[0].reason);
}

test "scenario 5 — multiple extensions per signer all quarantine in one apply" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const manifest_path = try std.fs.path.join(allocator, &.{ data_dir, "tenant.toml" });
    defer allocator.free(manifest_path);
    try writeTenantToml(allocator, manifest_path, .{});
    const revoked_index_path = try std.fs.path.join(allocator, &.{ data_dir, "extension-revoked-keys.json" });
    defer allocator.free(revoked_index_path);

    try installExtensionUnderSigner(allocator, data_dir, "x.foo", "0.1.0", SIGNER_X_PUBKEY, "x_signer");
    try installExtensionUnderSigner(allocator, data_dir, "x.bar", "0.1.0", SIGNER_X_PUBKEY, "x_signer");
    try installExtensionUnderSigner(allocator, data_dir, "x.baz", "0.1.0", SIGNER_X_PUBKEY, "x_signer");

    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();

    const vn = makeRevokeNullifier("x_signer", SIGNER_X_PUBKEY);
    var outcome = try nullifier_mod.applyNullifierWithQuarantine(
        allocator,
        vn,
        manifest_path,
        revoked_index_path,
        data_dir,
        &disp,
        true,
        null,
    );
    defer outcome.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 3), outcome.quarantined);
    try std.testing.expect(disp.isQuarantined("x.foo"));
    try std.testing.expect(disp.isQuarantined("x.bar"));
    try std.testing.expect(disp.isQuarantined("x.baz"));
}

test "scenario 6 — quarantine of signer X doesn't break dispatch for signer Y's extensions" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const manifest_path = try std.fs.path.join(allocator, &.{ data_dir, "tenant.toml" });
    defer allocator.free(manifest_path);
    try writeTenantToml(allocator, manifest_path, .{});
    const revoked_index_path = try std.fs.path.join(allocator, &.{ data_dir, "extension-revoked-keys.json" });
    defer allocator.free(revoked_index_path);

    try installExtensionUnderSigner(allocator, data_dir, "x.foo", "0.1.0", SIGNER_X_PUBKEY, "x_signer");
    try installExtensionUnderSigner(allocator, data_dir, "y.bar", "0.1.0", SIGNER_Y_PUBKEY, "y_signer");

    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();
    try disp.register(.{
        .name = "x.foo",
        .state = null,
        .cap_for_cmd_fn = stubCapForCmd,
        .handle_fn = stubHandle,
    });
    try disp.register(.{
        .name = "y.bar",
        .state = null,
        .cap_for_cmd_fn = stubCapForCmd,
        .handle_fn = stubHandle,
    });

    const vn = makeRevokeNullifier("x_signer", SIGNER_X_PUBKEY);
    var outcome = try nullifier_mod.applyNullifierWithQuarantine(
        allocator,
        vn,
        manifest_path,
        revoked_index_path,
        data_dir,
        &disp,
        true,
        null,
    );
    defer outcome.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), outcome.quarantined);

    const ctx = dispatcher_mod.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "t6" },
    };
    // x.foo: quarantined.
    try std.testing.expectError(
        dispatcher_mod.DispatchError.handler_quarantined,
        disp.dispatch(&ctx, "x.foo", "ping", "{}"),
    );
    // y.bar: still dispatchable.
    var ok_y = try disp.dispatch(&ctx, "y.bar", "ping", "{}");
    ok_y.deinit();
}

// ─────────────────────────────────────────────────────────────────────
// Stub handler used by scenario 1 + 6
// ─────────────────────────────────────────────────────────────────────

fn stubCapForCmd(state: ?*anyopaque, cmd_name: []const u8) dispatcher_mod.CapDeclError!dispatcher_mod.CapDecl {
    _ = state;
    if (std.mem.eql(u8, cmd_name, "ping")) return .none;
    return error.unknown_command;
}

fn stubHandle(
    state: ?*anyopaque,
    ctx: *const dispatcher_mod.DispatchContext,
    cmd_name: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher_mod.Result {
    _ = state;
    _ = ctx;
    _ = args_json;
    _ = allocator;
    if (std.mem.eql(u8, cmd_name, "ping")) return dispatcher_mod.Result.empty();
    return error.unknown_command;
}

```
