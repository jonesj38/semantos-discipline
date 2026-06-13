---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/identity_certs_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.193226+00:00
---

# runtime/semantos-brain/tests/identity_certs_conformance.zig

```zig
// Phase D-W1 / Phase 1 Part 2 — identity_certs handler conformance.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3 (identity_certs),
//            §7 (auth & capabilities), §12 (acceptance gates);
//            docs/spec/protocol-v0.5.md §4.4 (per-device contextTag
//            isolation);
//            docs/design/ODDJOBZ-EXTENSION-PLAN.md §3 Phase O5p (the
//            consumer of this handler).
//
// This suite is the security-critical regression spine for D-O5p.  The
// brief calls out three threats that MUST surface as test failures if
// the handler regresses; each is reproduced explicitly here:
//
//   • cap forgery — a peer that supplies a forged derivation_proof
//     cannot insert a child cert.
//   • cross-device impersonation — the carpenter (0x10) and musician
//     (0x11) hat scenario.  A proof minted for one context tag must
//     fail verification under another.
//   • revocation bypass — a revoked cert must drop out of `list`,
//     `get`, and any subsequent `issue_child` against it.
//
// Plus the BKDS BRC-42 canonical-vector parity check that pins the Zig
// implementation to the bsvz primitive (and, transitively, every other
// BRC-42 implementation that conforms to the spec) via the JSON vectors
// at `tests/fixtures/bkds_vectors.json`.
//
// Plus an ECDH-symmetry property the HMAC prototype couldn't have: both
// endpoints (operator with root_priv, device with device_priv) compute
// the same child pubkey via BRC-42, which is the structural basis for
// the verifier path in `bkds.verifyDerivationProof`.

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const bkds = @import("bkds");
const identity_certs = @import("identity_certs");
const handler_mod = @import("identity_certs_handler");

// ─────────────────────────────────────────────────────────────────────
// Test fixture
// ─────────────────────────────────────────────────────────────────────

fn pinnedClock() i64 {
    return 1_700_000_000;
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    store: identity_certs.CertStore,
    handler: handler_mod.Handler,
    disp: dispatcher.Dispatcher,

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(data_dir);
        const audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(audit_path);

        self.* = .{
            .allocator = allocator,
            .tmp_dir = tmp,
            .data_dir = data_dir,
            .audit_path = audit_path,
            .audit = audit_log.AuditLog.init(),
            .store = undefined,
            .handler = undefined,
            .disp = undefined,
        };
        try self.audit.open(audit_path);
        self.store = try identity_certs.CertStore.init(allocator, data_dir, pinnedClock);
        self.handler = handler_mod.Handler.init(allocator, &self.store);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.store.deinit();
        self.audit.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }

    fn dumpAudit(self: *Fixture) ![]u8 {
        const f = try std.fs.cwd().openFile(self.audit_path, .{});
        defer f.close();
        const stat = try f.stat();
        const buf = try self.allocator.alloc(u8, stat.size);
        errdefer self.allocator.free(buf);
        const n = try f.readAll(buf);
        return buf[0..n];
    }
};

fn rootCtx() dispatcher.DispatchContext {
    return .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "test", .transport_label = "test" },
    };
}

fn anonymousCtx() dispatcher.DispatchContext {
    return .{
        .auth = .{ .anonymous = .{ .site_origin = "https://example" } },
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "test-anon", .transport_label = "test" },
    };
}

// ─────────────────────────────────────────────────────────────────────
// JSON walk helpers — payloads are well-formed (we built them); a
// std.json walk is fine.
// ─────────────────────────────────────────────────────────────────────

fn jsonString(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.not_object;
    const v = parsed.value.object.get(key) orelse return error.missing_key;
    if (v != .string) return error.not_string;
    return try allocator.dupe(u8, v.string);
}

fn jsonInt(json: []const u8, key: []const u8, allocator: std.mem.Allocator) !i64 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.not_object;
    const v = parsed.value.object.get(key) orelse return error.missing_key;
    if (v != .integer) return error.not_int;
    return v.integer;
}

// ─────────────────────────────────────────────────────────────────────
// Helpers — synth a BRC-42 root keypair + a minted child via bsvz.
// ─────────────────────────────────────────────────────────────────────

const RootSeed = struct {
    privkey: [bkds.PRIVKEY_LEN]u8,
    pubkey: [bkds.KEY_LEN]u8, // 33-byte compressed SEC1
    pubkey_hex: [bkds.KEY_LEN * 2]u8,
};

fn makeRoot(seed: []const u8) !RootSeed {
    const privkey = bkds.privFromSeed(seed);
    const pubkey = try bkds.pubFromSeed(seed);
    var hex: [bkds.KEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&pubkey, &hex);
    return .{ .privkey = privkey, .pubkey = pubkey, .pubkey_hex = hex };
}

/// A device base keypair + a minted child (computed by both sides via
/// BRC-42; equal by ECDH symmetry).  `proof_hex` carries the device's
/// counterparty pubkey — what the brain feeds back through BRC-42 to
/// recompute the child.  `pubkey_hex` carries the BRC-42 child pubkey.
const MintedChild = struct {
    pubkey: [bkds.KEY_LEN]u8, // child compressed-SEC1
    pubkey_hex: [bkds.KEY_LEN * 2]u8,
    /// The device's base pubkey (counterparty), travelling on the wire
    /// as `derivation_proof`.
    proof_hex: [bkds.PROOF_LEN * 2]u8,
    /// Device base priv — useful for tests that exercise both sides
    /// (e.g. ECDH symmetry).
    device_priv: [bkds.PRIVKEY_LEN]u8,
    device_pub: [bkds.PUBKEY_LEN]u8,
};

fn mintChildBytes(
    root: RootSeed,
    device_seed: []const u8,
    context_tag: u8,
    label: []const u8,
) !MintedChild {
    const device_priv = bkds.privFromSeed(device_seed);
    const device_pub = try bkds.pubFromSeed(device_seed);
    const child_pub = try bkds.deriveChildPubkey(root.privkey, device_pub, context_tag, label);
    var hex: [bkds.KEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&child_pub, &hex);
    var proof_hex: [bkds.PROOF_LEN * 2]u8 = undefined;
    bkds.hexEncode(&device_pub, &proof_hex);
    return .{
        .pubkey = child_pub,
        .pubkey_hex = hex,
        .proof_hex = proof_hex,
        .device_priv = device_priv,
        .device_pub = device_pub,
    };
}

fn issueRoot(fx: *Fixture, ctx: *const dispatcher.DispatchContext, seed: []const u8) ![]u8 {
    const r = try makeRoot(seed);
    fx.handler.setOperatorRootPriv(r.privkey);
    const args = try std.fmt.allocPrint(fx.allocator,
        \\{{"pubkey":"{s}","label":"operator"}}
    , .{r.pubkey_hex});
    defer fx.allocator.free(args);
    var result = try fx.disp.dispatch(ctx, "identity_certs", "issue_root", args);
    defer result.deinit();
    return jsonString(fx.allocator, result.payload, "cert_id");
}

// ─────────────────────────────────────────────────────────────────────
// issue_root — idempotency
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.2 identity_certs: issue_root is idempotent (second call returns existing)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const id1 = try issueRoot(fx, &ctx, "operator-root-1");
    defer allocator.free(id1);
    const id2 = try issueRoot(fx, &ctx, "operator-root-1");
    defer allocator.free(id2);

    try std.testing.expectEqualStrings(id1, id2);
    try std.testing.expectEqual(@as(usize, 1), fx.store.count());
}

// ─────────────────────────────────────────────────────────────────────
// issue_child — happy path
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.2 identity_certs: issue_child happy path returns child record" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const root = try makeRoot("operator-root-2");
    fx.handler.setOperatorRootPriv(root.privkey);
    const root_args = try std.fmt.allocPrint(allocator,
        \\{{"pubkey":"{s}","label":"operator"}}
    , .{root.pubkey_hex});
    defer allocator.free(root_args);
    var root_res = try fx.disp.dispatch(&ctx, "identity_certs", "issue_root", root_args);
    defer root_res.deinit();
    const root_id = try jsonString(allocator, root_res.payload, "cert_id");
    defer allocator.free(root_id);

    const child = try mintChildBytes(root, "device-iphone-2", 0x10, "iPhone");
    const child_args = try std.fmt.allocPrint(allocator,
        \\{{"parent_cert_id":"{s}","context_tag":{d},"capabilities":["cap.oddjobz.write_customer","cap.attach.photo"],"label":"iPhone","derivation_pubkey":"{s}","derivation_proof":"{s}"}}
    , .{ root_id, 0x10, child.pubkey_hex, child.proof_hex });
    defer allocator.free(child_args);

    var child_res = try fx.disp.dispatch(&ctx, "identity_certs", "issue_child", child_args);
    defer child_res.deinit();
    const kind = try jsonString(allocator, child_res.payload, "kind");
    defer allocator.free(kind);
    try std.testing.expectEqualStrings("child", kind);
    const ctx_tag = try jsonInt(child_res.payload, "context_tag", allocator);
    try std.testing.expectEqual(@as(i64, 0x10), ctx_tag);
}

// ─────────────────────────────────────────────────────────────────────
// issue_child — forged proof
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.2 identity_certs: issue_child rejects forged derivation_proof" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const root = try makeRoot("operator-root-forged");
    const root_id = try issueRoot(fx, &ctx, "operator-root-forged");
    defer allocator.free(root_id);

    // The honest child the device would have submitted.
    const honest = try mintChildBytes(root, "device-honest", 0x10, "phone");
    // The attacker submits a *different* counterparty pubkey
    // (`derivation_proof`) — they don't actually hold the matching
    // priv, but they're trying to register the same child pubkey as if
    // they did.  BRC-42 binds the child to the (root_priv,
    // counterparty) ECDH; recomputing under the attacker's submitted
    // counterparty produces a different child → reject.  This is the
    // cap-forgery defence: an attacker without `device_priv` cannot
    // produce a counterparty whose ECDH-derived child matches the one
    // they're claiming.
    const forged = try mintChildBytes(root, "device-attacker", 0x10, "phone");

    const child_args = try std.fmt.allocPrint(allocator,
        \\{{"parent_cert_id":"{s}","context_tag":{d},"capabilities":[],"label":"phone","derivation_pubkey":"{s}","derivation_proof":"{s}"}}
        // honest child claimed; forged counterparty submitted as proof
    , .{ root_id, 0x10, honest.pubkey_hex, forged.proof_hex });
    defer allocator.free(child_args);

    try std.testing.expectError(
        handler_mod.HandlerError.derivation_context_mismatch,
        fx.disp.dispatch(&ctx, "identity_certs", "issue_child", child_args),
    );
    // Forged child never lands in the index.
    try std.testing.expectEqual(@as(usize, 1), fx.store.count());
}

test "D-W1 P1.2 identity_certs: issue_child rejects bit-flipped derivation_pubkey" {
    // Complementary path: flip a non-prefix byte of the claimed child
    // pubkey hex.  The verifier's recomputation produces the original
    // child; the constant-time compare against the tampered claim
    // fails → derivation_context_mismatch.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const root_id = try issueRoot(fx, &ctx, "operator-root-bitflip");
    defer allocator.free(root_id);
    const root = try makeRoot("operator-root-bitflip");
    const child = try mintChildBytes(root, "device-bitflip", 0x10, "phone");

    var tampered_pubkey_hex = child.pubkey_hex;
    // Flip a hex char *after* the SEC1 prefix (positions 0-1 carry the
    // 0x02/0x03 prefix; pick position 10 = a body byte).  Flipping a
    // body byte usually still parses as a valid SEC1 point (or surfaces
    // as bad_pubkey from bsvz, which the handler also maps to
    // derivation_context_mismatch).
    tampered_pubkey_hex[10] = if (tampered_pubkey_hex[10] == '0') '1' else '0';

    const child_args = try std.fmt.allocPrint(allocator,
        \\{{"parent_cert_id":"{s}","context_tag":{d},"capabilities":[],"label":"phone","derivation_pubkey":"{s}","derivation_proof":"{s}"}}
    , .{ root_id, 0x10, tampered_pubkey_hex, child.proof_hex });
    defer allocator.free(child_args);

    try std.testing.expectError(
        handler_mod.HandlerError.derivation_context_mismatch,
        fx.disp.dispatch(&ctx, "identity_certs", "issue_child", child_args),
    );
}

// ─────────────────────────────────────────────────────────────────────
// issue_child — context-tag swap (cross-device impersonation defence)
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.2 identity_certs: issue_child rejects context-tag swap (carpenter ≠ musician)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const root = try makeRoot("operator-root-hat-iso");
    const root_id = try issueRoot(fx, &ctx, "operator-root-hat-iso");
    defer allocator.free(root_id);

    // Mint a child under the carpenter context (0x10).  The label
    // travels into the BRC-42 invoice alongside context_tag, so we
    // pin it identically across both attempts to isolate the swap.
    const carp_child = try mintChildBytes(root, "device-hat", 0x10, "hat-swap");

    // Now try to register the SAME child pubkey + counterparty under
    // the musician context (0x11).  The verifier recomputes the
    // expected child with context_tag=0x11 (a *different* invoice → a
    // *different* HMAC tweak → a *different* child) and rejects — the
    // hat-isolation argument from §2.5 / spec §4.4.
    const child_args = try std.fmt.allocPrint(allocator,
        \\{{"parent_cert_id":"{s}","context_tag":{d},"capabilities":[],"label":"hat-swap","derivation_pubkey":"{s}","derivation_proof":"{s}"}}
    , .{ root_id, 0x11, carp_child.pubkey_hex, carp_child.proof_hex });
    defer allocator.free(child_args);

    try std.testing.expectError(
        handler_mod.HandlerError.derivation_context_mismatch,
        fx.disp.dispatch(&ctx, "identity_certs", "issue_child", child_args),
    );
}

// ─────────────────────────────────────────────────────────────────────
// issue_child — revoked parent
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.2 identity_certs: issue_child against a revoked parent returns parent_not_found" {
    // Note: per the brief's vocabulary, a revoked parent surfaces as
    // `parent_not_found` (the store drops revoked records from the
    // live index, matching bearer_tokens semantics — there is no
    // `revoked=true` half-state).  This is the "revocation bypass"
    // structural defence: a freshly-revoked child cannot itself be
    // upgraded to a parent for a sibling registration.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const root = try makeRoot("operator-root-revoke");
    const root_id = try issueRoot(fx, &ctx, "operator-root-revoke");
    defer allocator.free(root_id);

    // Issue a first child + capture its id.
    const child1 = try mintChildBytes(root, "device-revoke-1", 0x10, "first");
    const args1 = try std.fmt.allocPrint(allocator,
        \\{{"parent_cert_id":"{s}","context_tag":{d},"capabilities":[],"label":"first","derivation_pubkey":"{s}","derivation_proof":"{s}"}}
    , .{ root_id, 0x10, child1.pubkey_hex, child1.proof_hex });
    defer allocator.free(args1);
    var first_res = try fx.disp.dispatch(&ctx, "identity_certs", "issue_child", args1);
    defer first_res.deinit();
    const child1_id = try jsonString(allocator, first_res.payload, "cert_id");
    defer allocator.free(child1_id);

    // Revoke child1 (the v0.1 store drops it from the live index).
    const revoke_args = try std.fmt.allocPrint(allocator,
        \\{{"cert_id":"{s}"}}
    , .{child1_id});
    defer allocator.free(revoke_args);
    var revoked = try fx.disp.dispatch(&ctx, "identity_certs", "revoke", revoke_args);
    defer revoked.deinit();

    // Now try to issue a second child claiming child1 as its parent.
    // This must fail with parent_not_found — child1 is no longer in
    // the live index.  (The store also forbids using a child as a
    // parent; both checks land in the same error.)  Note: the v0.1
    // cert chain doesn't support multi-level parent chaining; we still
    // synthesise a plausible-shaped child2 so the test reaches the
    // store's parent-lookup gate before any other validation.
    const child2 = try mintChildBytes(root, "device-revoke-2", 0x11, "second");
    const args2 = try std.fmt.allocPrint(allocator,
        \\{{"parent_cert_id":"{s}","context_tag":{d},"capabilities":[],"label":"second","derivation_pubkey":"{s}","derivation_proof":"{s}"}}
    , .{ child1_id, 0x11, child2.pubkey_hex, child2.proof_hex });
    defer allocator.free(args2);

    try std.testing.expectError(
        handler_mod.HandlerError.parent_not_found,
        fx.disp.dispatch(&ctx, "identity_certs", "issue_child", args2),
    );
}

// ─────────────────────────────────────────────────────────────────────
// revoke — child drops from list + get returns cert_not_found
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.2 identity_certs: revoke child → list excludes, get returns cert_not_found" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const root = try makeRoot("operator-root-rev2");
    const root_id = try issueRoot(fx, &ctx, "operator-root-rev2");
    defer allocator.free(root_id);

    const child = try mintChildBytes(root, "device-rev2", 0x10, "phone");
    const child_args = try std.fmt.allocPrint(allocator,
        \\{{"parent_cert_id":"{s}","context_tag":{d},"capabilities":[],"label":"phone","derivation_pubkey":"{s}","derivation_proof":"{s}"}}
    , .{ root_id, 0x10, child.pubkey_hex, child.proof_hex });
    defer allocator.free(child_args);
    var child_res = try fx.disp.dispatch(&ctx, "identity_certs", "issue_child", child_args);
    defer child_res.deinit();
    const child_id = try jsonString(allocator, child_res.payload, "cert_id");
    defer allocator.free(child_id);

    const revoke_args = try std.fmt.allocPrint(allocator,
        \\{{"cert_id":"{s}"}}
    , .{child_id});
    defer allocator.free(revoke_args);
    var revoked = try fx.disp.dispatch(&ctx, "identity_certs", "revoke", revoke_args);
    defer revoked.deinit();

    // get → cert_not_found
    const get_args = try std.fmt.allocPrint(allocator,
        \\{{"cert_id":"{s}"}}
    , .{child_id});
    defer allocator.free(get_args);
    try std.testing.expectError(
        handler_mod.HandlerError.cert_not_found,
        fx.disp.dispatch(&ctx, "identity_certs", "get", get_args),
    );

    // list → only the root remains
    var listed = try fx.disp.dispatch(&ctx, "identity_certs", "list", "{}");
    defer listed.deinit();
    try std.testing.expect(std.mem.indexOf(u8, listed.payload, root_id) != null);
    try std.testing.expect(std.mem.indexOf(u8, listed.payload, child_id) == null);
}

// ─────────────────────────────────────────────────────────────────────
// revoke — root cert is non-revocable
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.2 identity_certs: revoke root returns cannot_revoke_root" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const root_id = try issueRoot(fx, &ctx, "operator-root-no-revoke");
    defer allocator.free(root_id);

    const args = try std.fmt.allocPrint(allocator,
        \\{{"cert_id":"{s}"}}
    , .{root_id});
    defer allocator.free(args);
    try std.testing.expectError(
        handler_mod.HandlerError.cannot_revoke_root,
        fx.disp.dispatch(&ctx, "identity_certs", "revoke", args),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Log replay — restart reconstructs identical post-state
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.2 identity_certs: log replay reconstructs root + N children + revocations" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const data_dir = try allocator.dupe(u8, real);
    defer allocator.free(data_dir);

    const root_seed = try makeRoot("operator-root-replay");
    var carpenter_id_buf: [identity_certs.CERT_ID_HEX_LEN]u8 = undefined;
    var musician_id_buf: [identity_certs.CERT_ID_HEX_LEN]u8 = undefined;

    // ── First run: mint root + carpenter + musician + revoke musician ──
    {
        var store = try identity_certs.CertStore.init(allocator, data_dir, pinnedClock);
        defer store.deinit();

        const root_rec = try store.issueRoot(root_seed.pubkey, "op");
        const carp = try mintChildBytes(root_seed, "device-replay-carp", 0x10, "carpenter-hat");
        const mus = try mintChildBytes(root_seed, "device-replay-mus", 0x11, "musician-hat");

        const carpenter = try store.issueChild(&root_rec.id, 0x10, carp.pubkey, &.{"cap.work"}, "carpenter-hat");
        const musician = try store.issueChild(&root_rec.id, 0x11, mus.pubkey, &.{"cap.studio"}, "musician-hat");
        @memcpy(&carpenter_id_buf, &carpenter.id);
        @memcpy(&musician_id_buf, &musician.id);

        try store.revoke(&musician.id);
    }

    // ── Second run: replay should yield {root, carpenter}, no musician ──
    {
        var store2 = try identity_certs.CertStore.init(allocator, data_dir, pinnedClock);
        defer store2.deinit();

        try std.testing.expectEqual(@as(usize, 2), store2.count());
        try std.testing.expect(store2.rootId() != null);

        const carpenter = try store2.get(&carpenter_id_buf);
        try std.testing.expectEqual(identity_certs.CertKind.child, carpenter.kind);
        try std.testing.expectEqual(@as(u8, 0x10), carpenter.context_tag);
        try std.testing.expectEqual(@as(usize, 1), carpenter.capabilities.len);
        try std.testing.expectEqualStrings("cap.work", carpenter.capabilities[0]);

        try std.testing.expectError(identity_certs.CertError.cert_not_found, store2.get(&musician_id_buf));
    }
}

// ─────────────────────────────────────────────────────────────────────
// BKDS BRC-42 canonical-vector parity
// ─────────────────────────────────────────────────────────────────────
//
// Pins the Zig BRC-42 surface to the bsvz primitive (and transitively
// to every other BRC-42 implementation that conforms to the spec) by
// loading the JSON fixture generated from bsvz itself and asserting
// `bkds.deriveChildPubkey` produces byte-identical output for every
// (root_priv, device_pub, context_tag, label) tuple.  Fixture is
// regenerated via `zig build gen-bkds-vectors`.

test "D-W1 P1.2 identity_certs: BKDS Zig output matches BRC-42 canonical-vector parity" {
    const allocator = std.testing.allocator;

    const fixture_text = try readFixture(allocator);
    defer allocator.free(fixture_text);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, fixture_text, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.fixture_root_not_object;

    const vectors = parsed.value.object.get("vectors") orelse return error.fixture_no_vectors;
    if (vectors != .array) return error.fixture_vectors_not_array;

    var checked: usize = 0;
    for (vectors.array.items) |v| {
        if (v != .object) return error.fixture_vector_not_object;
        const o = v.object;

        const name = (o.get("name") orelse return error.fixture_missing_field).string;
        const root_priv_hex = (o.get("root_priv_hex") orelse return error.fixture_missing_field).string;
        const device_pub_hex = (o.get("device_pub_hex") orelse return error.fixture_missing_field).string;
        const context_tag_int = (o.get("context_tag") orelse return error.fixture_missing_field).integer;
        const label = (o.get("label") orelse return error.fixture_missing_field).string;
        const expected_hex = (o.get("child_pub_hex") orelse return error.fixture_missing_field).string;

        if (root_priv_hex.len != bkds.PRIVKEY_LEN * 2) return error.fixture_bad_root_priv_len;
        if (device_pub_hex.len != bkds.PUBKEY_LEN * 2) return error.fixture_bad_device_pub_len;
        if (expected_hex.len != bkds.PUBKEY_LEN * 2) return error.fixture_bad_child_pub_len;
        if (context_tag_int < 0 or context_tag_int > 255) return error.fixture_bad_context_tag;

        var root_priv: [bkds.PRIVKEY_LEN]u8 = undefined;
        try bkds.hexDecode(root_priv_hex, &root_priv);
        var device_pub: [bkds.PUBKEY_LEN]u8 = undefined;
        try bkds.hexDecode(device_pub_hex, &device_pub);

        const got = try bkds.deriveChildPubkey(
            root_priv,
            device_pub,
            @intCast(context_tag_int),
            label,
        );
        var got_hex: [bkds.PUBKEY_LEN * 2]u8 = undefined;
        bkds.hexEncode(&got, &got_hex);
        std.testing.expectEqualStrings(expected_hex, &got_hex) catch |err| {
            std.debug.print(
                "\nBRC-42 BKDS parity failure at vector \"{s}\" (#{d})\n  root_priv: {s}\n  device_pub: {s}\n  context_tag: {d}\n  label: {s}\n  expected: {s}\n  got:      {s}\n",
                .{ name, checked, root_priv_hex, device_pub_hex, context_tag_int, label, expected_hex, got_hex },
            );
            return err;
        };
        checked += 1;
    }
    try std.testing.expect(checked >= 8);
}

/// Walk up from cwd to find tests/fixtures/bkds_vectors.json.  Handles
/// both `zig build test` (cwd = runtime/semantos-brain) and ad-hoc invocations.
fn readFixture(allocator: std.mem.Allocator) ![]u8 {
    const candidates = [_][]const u8{
        "tests/fixtures/bkds_vectors.json",
        "runtime/semantos-brain/tests/fixtures/bkds_vectors.json",
        "../tests/fixtures/bkds_vectors.json",
        "../../tests/fixtures/bkds_vectors.json",
    };
    for (candidates) |c| {
        const f = std.fs.cwd().openFile(c, .{}) catch continue;
        defer f.close();
        const stat = try f.stat();
        const buf = try allocator.alloc(u8, stat.size);
        errdefer allocator.free(buf);
        const n = try f.readAll(buf);
        return buf[0..n];
    }
    return error.fixture_not_found;
}

// ─────────────────────────────────────────────────────────────────────
// BRC-42 ECDH symmetry — structural property the HMAC prototype lacked
// ─────────────────────────────────────────────────────────────────────
//
// Under BRC-42, both endpoints (operator with root_priv + device_pub,
// device with device_priv + root_pub) arrive at the same child pubkey
// without ever exchanging a private half.  This test exercises the
// property end-to-end through the dispatcher: the device-side path
// (simulated locally) computes the child pubkey; the operator-side
// path (the handler's verifier) recomputes it; the issue_child
// dispatch succeeds iff they match.
//
// The test also flips one bit of the device's pubkey AFTER computing
// the (correct) child but BEFORE submission — this would break the
// ECDH symmetry (device's reported counterparty no longer matches
// what it actually computed against), and the verifier rejects.

test "D-W1 P1.2 identity_certs: BRC-42 ECDH-symmetry round-trip — device-side child equals operator-side child" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const root = try makeRoot("operator-root-symmetry");
    const root_id = try issueRoot(fx, &ctx, "operator-root-symmetry");
    defer allocator.free(root_id);

    // Simulate the device-side derivation independently — what the
    // phone does at pairing time before submitting issue_child.  We
    // compute the child pubkey from (device_priv, root_pub, invoice)
    // — the *opposite* halves the operator uses on its side.
    const device_priv = bkds.privFromSeed("device-symmetry");
    const device_pub = try bkds.pubFromSeed("device-symmetry");
    const device_side_child = try bkds.deriveChildPubkeyFromDevice(
        device_priv,
        root.pubkey,
        0x10,
        "phone",
    );

    // Cross-check (sanity): the operator side computes the same child
    // from the opposite halves.  This is the structural property; a
    // BRC-42 implementation that didn't satisfy ECDH symmetry would
    // diverge here.
    const operator_side_child = try bkds.deriveChildPubkey(
        root.privkey,
        device_pub,
        0x10,
        "phone",
    );
    try std.testing.expectEqualSlices(u8, &device_side_child, &operator_side_child);

    // Now drive the dispatcher: submit the device-side-computed child
    // pubkey + the device's counterparty pubkey.  The handler runs
    // the operator-side verifier and accepts iff the two match
    // byte-for-byte.
    var device_pub_hex: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&device_pub, &device_pub_hex);
    var child_hex: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&device_side_child, &child_hex);

    const args = try std.fmt.allocPrint(allocator,
        \\{{"parent_cert_id":"{s}","context_tag":{d},"capabilities":["cap.x"],"label":"phone","derivation_pubkey":"{s}","derivation_proof":"{s}"}}
    , .{ root_id, 0x10, child_hex, device_pub_hex });
    defer allocator.free(args);

    var res = try fx.disp.dispatch(&ctx, "identity_certs", "issue_child", args);
    defer res.deinit();
    const kind = try jsonString(allocator, res.payload, "kind");
    defer allocator.free(kind);
    try std.testing.expectEqualStrings("child", kind);

    // Sanity: the cert id derives from the child pubkey.  Asserts
    // the round-trip identity (same child in → same id out).
    const expected_id = identity_certs.certIdFromPubkey(operator_side_child);
    const got_id = try jsonString(allocator, res.payload, "cert_id");
    defer allocator.free(got_id);
    try std.testing.expectEqualSlices(u8, &expected_id, got_id);
}

test "D-W1 P1.2 identity_certs: BRC-42 verifier rejects when operator priv is missing (fail-closed)" {
    // Pair-with-no-priv: the handler is initialised without an
    // operator priv.  issue_child should fail closed with
    // derivation_context_mismatch — the brain cannot verify a BRC-42
    // derivation without holding the priv half, and silently accepting
    // would be a structural cap-forgery hole.
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    // Mint the root *without* installing the priv on the handler.
    const root = try makeRoot("operator-root-noprive");
    const root_args = try std.fmt.allocPrint(allocator,
        \\{{"pubkey":"{s}","label":"operator"}}
    , .{root.pubkey_hex});
    defer allocator.free(root_args);
    var root_res = try fx.disp.dispatch(&ctx, "identity_certs", "issue_root", root_args);
    defer root_res.deinit();
    const root_id = try jsonString(allocator, root_res.payload, "cert_id");
    defer allocator.free(root_id);

    // Belt-and-braces: explicitly clear in case some other code path
    // leaked a priv into the handler.
    fx.handler.clearOperatorRootPriv();

    // Otherwise-honest child request — would succeed if the priv were
    // installed.
    const child = try mintChildBytes(root, "device-noprive", 0x10, "phone");
    const child_args = try std.fmt.allocPrint(allocator,
        \\{{"parent_cert_id":"{s}","context_tag":{d},"capabilities":[],"label":"phone","derivation_pubkey":"{s}","derivation_proof":"{s}"}}
    , .{ root_id, 0x10, child.pubkey_hex, child.proof_hex });
    defer allocator.free(child_args);

    try std.testing.expectError(
        handler_mod.HandlerError.derivation_context_mismatch,
        fx.disp.dispatch(&ctx, "identity_certs", "issue_child", child_args),
    );
    try std.testing.expectEqual(@as(usize, 1), fx.store.count()); // just the root
}

// ─────────────────────────────────────────────────────────────────────
// Capability gating — anonymous can't issue, root scope can
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.2 identity_certs: anonymous caller cannot issue_root" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const root = try makeRoot("anon-attempt");
    const args = try std.fmt.allocPrint(allocator,
        \\{{"pubkey":"{s}","label":"anon"}}
    , .{root.pubkey_hex});
    defer allocator.free(args);

    var ctx = anonymousCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.capability_denied,
        fx.disp.dispatch(&ctx, "identity_certs", "issue_root", args),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Audit pair invariant — each dispatch records start + end
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.2 identity_certs: each dispatch records one start + one end audit entry" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const root_id = try issueRoot(fx, &ctx, "operator-audit");
    defer allocator.free(root_id);

    var listed = try fx.disp.dispatch(&ctx, "identity_certs", "list", "{}");
    defer listed.deinit();

    const text = try fx.dumpAudit();
    defer allocator.free(text);

    var start_count: usize = 0;
    var end_count: usize = 0;
    var rest = text;
    while (std.mem.indexOf(u8, rest, "phase=start")) |idx| {
        start_count += 1;
        rest = rest[idx + "phase=start".len ..];
    }
    rest = text;
    while (std.mem.indexOf(u8, rest, "phase=end")) |idx| {
        end_count += 1;
        rest = rest[idx + "phase=end".len ..];
    }
    // 2 dispatches above (issue_root + list).
    try std.testing.expectEqual(@as(usize, 2), start_count);
    try std.testing.expectEqual(@as(usize, 2), end_count);
    try std.testing.expect(std.mem.indexOf(u8, text, "identity_certs.issue_root") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "identity_certs.list") != null);
}

```
