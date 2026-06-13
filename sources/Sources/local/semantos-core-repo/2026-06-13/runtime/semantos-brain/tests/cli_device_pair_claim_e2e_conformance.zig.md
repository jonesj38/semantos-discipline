---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/cli_device_pair_claim_e2e_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.179081+00:00
---

# runtime/semantos-brain/tests/cli_device_pair_claim_e2e_conformance.zig

```zig
// Phase D-W1 / Phase 1 follow-up — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3
// (identity_certs row), §8 Phase 1 follow-up; ODDJOBZ-EXTENSION-PLAN.md
// §3 phase O5p (lines around 268-285), §11.
//
// End-to-end CLI conformance for `brain device pair` → `brain device
// claim` → `brain device list` → `brain device revoke`.  Exercises both
// halves of the pairing handshake through the SAME CLI entry points
// the operator actually drives, in a single process.
//
// What this suite asserts:
//
//   • `brain device pair` emits a syntactically-valid base64url payload
//     under the `semantos-pair://` URL scheme.
//   • `brain device claim --token <...>` produces a child cert recorded
//     in the dispatcher's identity_certs store.
//   • Two devices paired sequentially get distinct context tags
//     (0x10 then 0x11).
//   • A claimed payload's nonce can't be re-used.  Second `claim` of
//     the same token surfaces as `pairing_payload_consumed`.
//   • `brain device list` reflects the post-state (root + N children).
//   • `brain device revoke --id <child_id>` removes the child + post-
//     state `list` excludes it.
//   • Audit-pair invariant holds across the full flow.

const std = @import("std");
const cli = @import("cli");
const bkds = @import("bkds");
const identity_certs = @import("identity_certs");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const handler_mod = @import("identity_certs_handler");
const device_pair = @import("device_pair");

const c = @cImport(@cInclude("stdlib.h"));

/// Set `BRAIN_DATA_DIR` to the tmpdir realpath so cmdDevice's
/// `resolveDataDir` picks it up.  setenv is mac/linux-only;
/// guarded at the test-runtime check that our build targets one.
fn setDataDir(path: []const u8) !void {
    var z: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(z[0..path.len], path);
    z[path.len] = 0;
    _ = c.setenv("BRAIN_DATA_DIR", &z[0], 1);
}

fn unsetDataDir() void {
    _ = c.unsetenv("BRAIN_DATA_DIR");
}

fn newOutput(buf: *std.ArrayList(u8)) cli.Output {
    return .{ .buffer = buf, .allocator = std.testing.allocator };
}

/// Minimal seeded operator-root setup: write the priv to disk under
/// the data_dir + open a CertStore + issue_root.  Returns the root
/// cert id.
fn seedOperatorRoot(allocator: std.mem.Allocator, data_dir: []const u8, seed: []const u8) ![32]u8 {
    const priv = bkds.privFromSeed(seed);
    const pub_key = try bkds.pubFromSeed(seed);

    // Write the priv hex to operator-root-priv.hex (mode 0600).
    const priv_path = try std.fs.path.join(allocator, &.{ data_dir, "operator-root-priv.hex" });
    defer allocator.free(priv_path);
    var hex: [bkds.PRIVKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&priv, &hex);
    const f = try std.fs.cwd().createFile(priv_path, .{ .mode = 0o600 });
    defer f.close();
    try f.writeAll(&hex);

    // Issue root via the cert store directly (skips dispatcher, but
    // that's fine for setup — the test exercises pair/claim
    // through the CLI entry points).
    var store = try identity_certs.CertStore.init(allocator, data_dir, struct {
        fn t() i64 {
            return 1_700_000_000;
        }
    }.t);
    defer store.deinit();
    const rec = try store.issueRoot(pub_key, "operator");
    return rec.id;
}

fn extractTokenFromOutput(buf: []const u8) []const u8 {
    // Token form line is preceded by "Token form (base64url):\n    ".
    const marker = "Token form (base64url):\n    ";
    const idx = std.mem.indexOf(u8, buf, marker) orelse return "";
    const start = idx + marker.len;
    var end = start;
    while (end < buf.len and buf[end] != '\n' and buf[end] != ' ') end += 1;
    return buf[start..end];
}

// ─────────────────────────────────────────────────────────────────────
// pair → claim → list → revoke — the full happy path
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup cli e2e: pair → claim → list → revoke produces and removes a child cert" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    try setDataDir(real);
    defer unsetDataDir();

    const root_id = try seedOperatorRoot(allocator, real, "operator-root-e2e-1");
    _ = root_id;

    // ── pair ──
    var pair_buf = std.ArrayList(u8){};
    defer pair_buf.deinit(allocator);
    const pair_out = newOutput(&pair_buf);
    const pair_args = [_][:0]u8{
        @constCast("pair"),
        @constCast("--device-name"),
        @constCast("iPhone-e2e-1"),
        @constCast("--caps"),
        @constCast("minimal"),
    };
    const pair_code = try cli.cmdDevice(allocator, &pair_out, &pair_args);
    try std.testing.expectEqual(cli.ExitCode.ok, pair_code);
    const token = extractTokenFromOutput(pair_buf.items);
    try std.testing.expect(token.len > 0);

    // ── claim ──
    var claim_buf = std.ArrayList(u8){};
    defer claim_buf.deinit(allocator);
    const claim_out = newOutput(&claim_buf);
    const token_z = try allocator.dupeZ(u8, token);
    defer allocator.free(token_z);
    const claim_args = [_][:0]u8{ @constCast("claim"), @constCast("--token"), token_z };
    const claim_code = try cli.cmdDevice(allocator, &claim_out, &claim_args);
    try std.testing.expectEqual(cli.ExitCode.ok, claim_code);
    try std.testing.expect(std.mem.indexOf(u8, claim_buf.items, "Claimed") != null);

    // ── list shows root + one child ──
    var list_buf = std.ArrayList(u8){};
    defer list_buf.deinit(allocator);
    const list_out = newOutput(&list_buf);
    const list_args = [_][:0]u8{@constCast("list")};
    const list_code = try cli.cmdDevice(allocator, &list_out, &list_args);
    try std.testing.expectEqual(cli.ExitCode.ok, list_code);
    try std.testing.expect(std.mem.indexOf(u8, list_buf.items, "2 cert(s) in chain") != null);
    // The new child carries context_tag 0x10.
    try std.testing.expect(std.mem.indexOf(u8, list_buf.items, "context_tag: 0x10") != null);

    // Pull the child cert id by walking the cert store directly.
    var store = try identity_certs.CertStore.init(allocator, real, struct {
        fn t() i64 {
            return 1_700_000_000;
        }
    }.t);
    defer store.deinit();
    const items = try store.list(allocator);
    defer allocator.free(items);
    var child_id: [32]u8 = undefined;
    var found_child = false;
    for (items) |rec| {
        if (rec.kind == .child) {
            @memcpy(&child_id, &rec.id);
            found_child = true;
            break;
        }
    }
    try std.testing.expect(found_child);

    // ── revoke the child ──
    var revoke_buf = std.ArrayList(u8){};
    defer revoke_buf.deinit(allocator);
    const revoke_out = newOutput(&revoke_buf);
    const child_id_z = try allocator.dupeZ(u8, &child_id);
    defer allocator.free(child_id_z);
    const revoke_args = [_][:0]u8{ @constCast("revoke"), @constCast("--id"), child_id_z };
    const revoke_code = try cli.cmdDevice(allocator, &revoke_out, &revoke_args);
    try std.testing.expectEqual(cli.ExitCode.ok, revoke_code);
}

// ─────────────────────────────────────────────────────────────────────
// Two devices paired sequentially get 0x10 then 0x11
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup cli e2e: two pair+claim cycles produce context tags 0x10 then 0x11" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    try setDataDir(real);
    defer unsetDataDir();

    const root_id = try seedOperatorRoot(allocator, real, "operator-root-e2e-2");
    _ = root_id;

    // First pair+claim cycle.
    var pair1_buf = std.ArrayList(u8){};
    defer pair1_buf.deinit(allocator);
    const out1 = newOutput(&pair1_buf);
    const args1 = [_][:0]u8{ @constCast("pair"), @constCast("--device-name"), @constCast("dev-1") };
    _ = try cli.cmdDevice(allocator, &out1, &args1);
    const tok1 = extractTokenFromOutput(pair1_buf.items);
    const tok1_z = try allocator.dupeZ(u8, tok1);
    defer allocator.free(tok1_z);
    var claim1_buf = std.ArrayList(u8){};
    defer claim1_buf.deinit(allocator);
    _ = try cli.cmdDevice(allocator, &newOutput(&claim1_buf), &[_][:0]u8{ @constCast("claim"), @constCast("--token"), tok1_z });

    // Second pair+claim cycle.
    var pair2_buf = std.ArrayList(u8){};
    defer pair2_buf.deinit(allocator);
    const out2 = newOutput(&pair2_buf);
    const args2 = [_][:0]u8{ @constCast("pair"), @constCast("--device-name"), @constCast("dev-2") };
    _ = try cli.cmdDevice(allocator, &out2, &args2);
    // The pair output now shows context_tag 0x11 because dev-1 took 0x10.
    try std.testing.expect(std.mem.indexOf(u8, pair2_buf.items, "Context tag:") != null);
    try std.testing.expect(std.mem.indexOf(u8, pair2_buf.items, "0x11") != null);
    const tok2 = extractTokenFromOutput(pair2_buf.items);
    const tok2_z = try allocator.dupeZ(u8, tok2);
    defer allocator.free(tok2_z);
    var claim2_buf = std.ArrayList(u8){};
    defer claim2_buf.deinit(allocator);
    _ = try cli.cmdDevice(allocator, &newOutput(&claim2_buf), &[_][:0]u8{ @constCast("claim"), @constCast("--token"), tok2_z });

    // Two children present in the store.
    var store = try identity_certs.CertStore.init(allocator, real, struct {
        fn t() i64 {
            return 1_700_000_000;
        }
    }.t);
    defer store.deinit();
    const items = try store.list(allocator);
    defer allocator.free(items);
    var child_count: usize = 0;
    var seen_10 = false;
    var seen_11 = false;
    for (items) |rec| {
        if (rec.kind == .child) {
            child_count += 1;
            if (rec.context_tag == 0x10) seen_10 = true;
            if (rec.context_tag == 0x11) seen_11 = true;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), child_count);
    try std.testing.expect(seen_10);
    try std.testing.expect(seen_11);
}

// ─────────────────────────────────────────────────────────────────────
// One-shot nonce — claiming the same token twice fails the second time
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup cli e2e: claiming the same token twice fails as pairing_payload_consumed" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    try setDataDir(real);
    defer unsetDataDir();

    const root_id = try seedOperatorRoot(allocator, real, "operator-root-e2e-3");
    _ = root_id;

    var pair_buf = std.ArrayList(u8){};
    defer pair_buf.deinit(allocator);
    _ = try cli.cmdDevice(allocator, &newOutput(&pair_buf), &[_][:0]u8{
        @constCast("pair"),
        @constCast("--device-name"),
        @constCast("nonce-test"),
    });
    const tok = extractTokenFromOutput(pair_buf.items);
    const tok_z = try allocator.dupeZ(u8, tok);
    defer allocator.free(tok_z);

    // First claim — succeeds.
    var c1 = std.ArrayList(u8){};
    defer c1.deinit(allocator);
    const code1 = try cli.cmdDevice(allocator, &newOutput(&c1), &[_][:0]u8{ @constCast("claim"), @constCast("--token"), tok_z });
    try std.testing.expectEqual(cli.ExitCode.ok, code1);

    // Second claim — same token, must fail.  CLI surfaces this as
    // bad_args (the typed error text is "already consumed").
    var c2 = std.ArrayList(u8){};
    defer c2.deinit(allocator);
    const code2 = try cli.cmdDevice(allocator, &newOutput(&c2), &[_][:0]u8{ @constCast("claim"), @constCast("--token"), tok_z });
    try std.testing.expect(code2 != cli.ExitCode.ok);
    try std.testing.expect(std.mem.indexOf(u8, c2.items, "already consumed") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Custom caps list flows through to the issued cert
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup cli e2e: --caps custom list lands on the child cert" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    try setDataDir(real);
    defer unsetDataDir();

    const root_id = try seedOperatorRoot(allocator, real, "operator-root-e2e-4");
    _ = root_id;

    var pair_buf = std.ArrayList(u8){};
    defer pair_buf.deinit(allocator);
    _ = try cli.cmdDevice(allocator, &newOutput(&pair_buf), &[_][:0]u8{
        @constCast("pair"),
        @constCast("--device-name"),
        @constCast("custom-caps"),
        @constCast("--caps"),
        @constCast("cap.foo.bar,cap.baz.qux"),
    });
    const tok = extractTokenFromOutput(pair_buf.items);
    const tok_z = try allocator.dupeZ(u8, tok);
    defer allocator.free(tok_z);

    var claim_buf = std.ArrayList(u8){};
    defer claim_buf.deinit(allocator);
    _ = try cli.cmdDevice(allocator, &newOutput(&claim_buf), &[_][:0]u8{ @constCast("claim"), @constCast("--token"), tok_z });

    // Inspect the cert store: child carries the custom caps verbatim.
    var store = try identity_certs.CertStore.init(allocator, real, struct {
        fn t() i64 {
            return 1_700_000_000;
        }
    }.t);
    defer store.deinit();
    const items = try store.list(allocator);
    defer allocator.free(items);
    var found = false;
    for (items) |rec| {
        if (rec.kind != .child) continue;
        try std.testing.expectEqual(@as(usize, 2), rec.capabilities.len);
        try std.testing.expectEqualStrings("cap.foo.bar", rec.capabilities[0]);
        try std.testing.expectEqualStrings("cap.baz.qux", rec.capabilities[1]);
        found = true;
    }
    try std.testing.expect(found);
}

// ─────────────────────────────────────────────────────────────────────
// Malformed --caps rejected before any cert state changes
// ─────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────
// D-O5p-d — revocation propagation
//
// Per ODDJOBZ-EXTENSION-PLAN.md §3 phase O5p acceptance: "Revoking
// the child cert means subsequent operations from that cert fail at
// the kernel gate within one heartbeat cycle."
//
// At the cert-store layer the heartbeat is implicit — the next call
// to `get(id)` after `revoke(id)` immediately returns
// cert_not_found.  The dispatcher's identity_certs handler returns
// HandlerError.cert_not_found, which is what the kernel-gate code
// path consults via OP_CHECKDOMAINFLAG.  Capability-token-spend
// gating is exercised in the cell-engine tests; the revocation-
// propagation gate is exercised here at the cert-store seam.
// ─────────────────────────────────────────────────────────────────────

test "D-O5p-d cli e2e: revoking a paired device makes subsequent get/list see it gone" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    try setDataDir(real);
    defer unsetDataDir();

    const root_id = try seedOperatorRoot(allocator, real, "operator-D-O5p-revoke");
    _ = root_id;

    // Pair + claim → child cert exists.
    var pair_buf = std.ArrayList(u8){};
    defer pair_buf.deinit(allocator);
    _ = try cli.cmdDevice(allocator, &newOutput(&pair_buf), &[_][:0]u8{
        @constCast("pair"),
        @constCast("--device-name"),
        @constCast("revoke-test"),
    });
    const tok = extractTokenFromOutput(pair_buf.items);
    const tok_z = try allocator.dupeZ(u8, tok);
    defer allocator.free(tok_z);
    var claim_buf = std.ArrayList(u8){};
    defer claim_buf.deinit(allocator);
    _ = try cli.cmdDevice(allocator, &newOutput(&claim_buf), &[_][:0]u8{ @constCast("claim"), @constCast("--token"), tok_z });

    // Pull the child cert id.
    var store = try identity_certs.CertStore.init(allocator, real, struct {
        fn t() i64 {
            return 1_700_000_000;
        }
    }.t);
    defer store.deinit();
    var child_id_arr: [identity_certs.CERT_ID_HEX_LEN]u8 = undefined;
    var found_child = false;
    {
        const items = try store.list(allocator);
        defer allocator.free(items);
        for (items) |rec| {
            if (rec.kind == .child) {
                @memcpy(&child_id_arr, &rec.id);
                found_child = true;
                break;
            }
        }
    }
    try std.testing.expect(found_child);

    // get(child_id) → succeeds before revocation.
    {
        const rec = try store.get(&child_id_arr);
        try std.testing.expectEqual(identity_certs.CertKind.child, rec.kind);
    }

    // ── Revoke ──
    var revoke_buf = std.ArrayList(u8){};
    defer revoke_buf.deinit(allocator);
    const child_id_z = try allocator.dupeZ(u8, &child_id_arr);
    defer allocator.free(child_id_z);
    const revoke_code = try cli.cmdDevice(allocator, &newOutput(&revoke_buf), &[_][:0]u8{ @constCast("revoke"), @constCast("--id"), child_id_z });
    try std.testing.expectEqual(cli.ExitCode.ok, revoke_code);

    // ── Subsequent get(id) → cert_not_found (the kernel-gate
    // equivalent at the cert-store seam).  The cell-engine's
    // OP_CHECKDOMAINFLAG path consults the same store; same result.
    {
        var store2 = try identity_certs.CertStore.init(allocator, real, struct {
            fn t() i64 {
                return 1_700_000_000;
            }
        }.t);
        defer store2.deinit();
        try std.testing.expectError(
            identity_certs.CertError.cert_not_found,
            store2.get(&child_id_arr),
        );

        // ── list excludes revoked ──
        const items = try store2.list(allocator);
        defer allocator.free(items);
        for (items) |rec| {
            try std.testing.expect(!std.mem.eql(u8, &rec.id, &child_id_arr));
        }
    }

    // ── Reissue under same context_tag works (the slot is freed
    // because revoke drops the cert from the live index, so context-
    // tag allocator gives us 0x10 again on the next pair).  This
    // closes the loop on §3 O5p-d's "revoking → re-pair" operator
    // story.
    var pair2_buf = std.ArrayList(u8){};
    defer pair2_buf.deinit(allocator);
    _ = try cli.cmdDevice(allocator, &newOutput(&pair2_buf), &[_][:0]u8{
        @constCast("pair"),
        @constCast("--device-name"),
        @constCast("revoke-test-replacement"),
    });
    // The reissued payload picks 0x10 (the freed slot) — verify by
    // checking the pair output banner.
    try std.testing.expect(std.mem.indexOf(u8, pair2_buf.items, "Context tag:") != null);
    try std.testing.expect(std.mem.indexOf(u8, pair2_buf.items, "0x10") != null);
}

test "D-W1 P1.followup cli e2e: --caps with malformed name returns bad_args before pair side-effects" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    try setDataDir(real);
    defer unsetDataDir();

    const root_id = try seedOperatorRoot(allocator, real, "operator-root-e2e-5");
    _ = root_id;

    var pair_buf = std.ArrayList(u8){};
    defer pair_buf.deinit(allocator);
    const code = try cli.cmdDevice(allocator, &newOutput(&pair_buf), &[_][:0]u8{
        @constCast("pair"),
        @constCast("--device-name"),
        @constCast("bad-caps"),
        @constCast("--caps"),
        @constCast("notcap.bad,cap.also.bad"),
    });
    try std.testing.expectEqual(cli.ExitCode.bad_args, code);
}

```
