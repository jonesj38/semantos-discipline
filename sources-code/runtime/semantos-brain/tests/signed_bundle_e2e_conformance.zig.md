---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/signed_bundle_e2e_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.211491+00:00
---

# runtime/semantos-brain/tests/signed_bundle_e2e_conformance.zig

```zig
// Phase D-W1 / Phase 4 — SignedBundle receive→verify→dispatch→audit
// end-to-end conformance.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §5.4 (mesh
//            transport: mobile Flutter peer + federated tenant nodes
//            send SignedBundle envelopes; the receiving brain decodes,
//            verifies the cert chain, constructs a DispatchContext,
//            calls the dispatcher).  §8 Phase 4.
//
// Coverage:
//   • Happy path — a SignedBundle carrying a wire.Request for
//     `bearer_tokens.list` round-trips through processBundle and
//     produces a wire.Response carrying the resource's result + an
//     audit log pair tagged transport=signed_bundle.
//   • Unknown sender — the leaf cert isn't registered in the brain's
//     CertStore.  Outcome: 401 capability_denied.
//   • Wrong recipient — the bundle's recipient_cert_id ≠ brain's
//     expected_recipient.  Outcome: 403 capability_denied.
//   • Malformed payload — the inner wire.Request is not valid JSON.
//     Outcome: 400 validation_failed.
//   • Capability denied — the leaf cert has no caps and the resource
//     requires `cap.brain.admin`.  Outcome: 403 capability_denied (the
//     dispatcher's own check fires after the bundle decode + cert
//     chain verify pass).
//   • Replay — the same bundle posted twice.  Outcome on retry: 409
//     validation_failed nonce_replay.

const std = @import("std");
const dispatcher_mod = @import("dispatcher");
const wire = @import("wire");
const audit_log_mod = @import("audit_log");
const signed_bundle = @import("signed_bundle");
const transport = @import("signed_bundle_transport");
const identity_certs = @import("identity_certs");
const bkds = @import("bkds");
const bearer_tokens = @import("bearer_tokens");
const bearer_tokens_handler = @import("bearer_tokens_handler");

const allocator = std.testing.allocator;

fn pinnedClock() i64 {
    return 1_700_000_000;
}

const Fixture = struct {
    tmp: std.testing.TmpDir,
    audit: audit_log_mod.AuditLog,
    audit_path: []u8,
    dispatcher: dispatcher_mod.Dispatcher,
    cert_store: identity_certs.CertStore,
    token_store: bearer_tokens.TokenStore,
    bearer: bearer_tokens_handler.Handler,
    acceptor: transport.BundleAcceptor,
    root_priv: [bkds.PRIVKEY_LEN]u8,
    root_pubkey: [bkds.KEY_LEN]u8,
    leaf_priv: [bkds.PRIVKEY_LEN]u8,
    leaf_pubkey: [bkds.KEY_LEN]u8,
    leaf_caps: [][]const u8,

    fn deinit(self: *Fixture) void {
        self.acceptor.deinit();
        self.bearer = self.bearer; // no-op; bearer Handler has no deinit
        self.token_store.deinit();
        self.cert_store.deinit();
        self.dispatcher.deinit();
        self.audit.close();
        allocator.free(self.audit_path);
        for (self.leaf_caps) |c| allocator.free(@constCast(c));
        if (self.leaf_caps.len > 0) allocator.free(self.leaf_caps);
        self.tmp.cleanup();
    }
};

fn realClock() i64 {
    return std.time.timestamp();
}

fn buildFixture(seed_root: []const u8, leaf_caps_in: []const []const u8) !*Fixture {
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    var audit = audit_log_mod.AuditLog.init();
    const audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
    errdefer allocator.free(audit_path);
    try audit.open(audit_path);
    errdefer audit.close();

    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    errdefer disp.deinit();

    var cert_store = try identity_certs.CertStore.init(allocator, real, pinnedClock);
    errdefer cert_store.deinit();

    var token_store = try bearer_tokens.TokenStore.init(allocator, real, pinnedClock);
    errdefer token_store.deinit();

    var bearer = bearer_tokens_handler.Handler.init(allocator, &token_store);
    try disp.register(bearer.resourceHandler());

    // Seed the cert chain — operator root + a child cert with the
    // operator-supplied capability allowlist.
    const root_priv = bkds.privFromSeed(seed_root);
    const root_pubkey = try bkds.pubFromSeed(seed_root);
    _ = try cert_store.issueRoot(root_pubkey, "operator-root");

    const leaf_seed = "phase4-e2e-leaf-seed";
    const leaf_priv = bkds.privFromSeed(leaf_seed);
    const leaf_pubkey_seeded = try bkds.pubFromSeed(leaf_seed);
    // Use leaf_pubkey_seeded as the device counterparty; the BRC-42
    // child pubkey is what gets cert_id'd in the store.  But the test
    // wants the leaf to actually be the signer — so we'll register
    // the leaf_pubkey_seeded directly as the child cert (skipping
    // BRC-42 derivation since that would produce a different pubkey
    // we don't have a priv for).  This is fine for the e2e test —
    // the cert chain verification only checks (cert_id, pubkey,
    // parent_cert_id) consistency, not the BRC-42 proof.
    const root_id = identity_certs.certIdFromPubkey(root_pubkey);

    // Mint the child cert directly with leaf_pubkey_seeded so the
    // bundle's signature (signed by leaf_priv) verifies against the
    // store's recorded pubkey.
    _ = try cert_store.issueChild(&root_id, 0x10, leaf_pubkey_seeded, leaf_caps_in, "phone");

    // Dupe leaf_caps_in into the fixture for cleanup.
    var caps_copy = try allocator.alloc([]const u8, leaf_caps_in.len);
    errdefer {
        for (caps_copy) |c| allocator.free(@constCast(c));
        if (caps_copy.len > 0) allocator.free(caps_copy);
    }
    var built: usize = 0;
    while (built < leaf_caps_in.len) : (built += 1) {
        caps_copy[built] = try allocator.dupe(u8, leaf_caps_in[built]);
    }

    var acceptor = transport.BundleAcceptor.init(allocator, &disp, &cert_store, realClock);
    acceptor.setExpectedRecipient(root_id);

    const fx = try allocator.create(Fixture);
    fx.* = .{
        .tmp = tmp,
        .audit = audit,
        .audit_path = audit_path,
        .dispatcher = disp,
        .cert_store = cert_store,
        .token_store = token_store,
        .bearer = bearer,
        .acceptor = acceptor,
        .root_priv = root_priv,
        .root_pubkey = root_pubkey,
        .leaf_priv = leaf_priv,
        .leaf_pubkey = leaf_pubkey_seeded,
        .leaf_caps = caps_copy,
    };
    // Re-seat acceptor + bearer to point at the in-fixture copies so
    // the borrowed pointers stay valid after the heap-allocated
    // struct's address fixes.
    fx.bearer.store = &fx.token_store;
    // Re-register the bearer handler against the fixture's dispatcher
    // so the handler's `state` pointer refers to the in-fixture
    // bearer instance.  Re-registration would error duplicate;
    // instead we rebuild the dispatcher from scratch on the fixture
    // pointer — but that requires reset semantics.  Simpler: the
    // dispatcher's resourceHandler stores `state = &bearer` from the
    // call above (before fx.* = ... copy).  Re-init.
    fx.dispatcher.deinit();
    fx.dispatcher = dispatcher_mod.Dispatcher.init(allocator, &fx.audit);
    try fx.dispatcher.register(fx.bearer.resourceHandler());
    fx.acceptor.dispatcher = &fx.dispatcher;
    fx.acceptor.cert_store = &fx.cert_store;
    return fx;
}

/// Build + sign a bundle carrying `inner_request` for the leaf cert
/// in the fixture.  Caller frees the returned bytes.  Bundle is
/// addressed to fx.acceptor.expected_recipient.
fn buildSignedBundle(
    fx: *Fixture,
    inner_request: []const u8,
    nonce_byte: u8,
    timestamp: i64,
) ![]u8 {
    return buildSignedBundleWithType(fx, inner_request, "dispatch.request", nonce_byte, timestamp);
}

/// D-O5m.followup-6 Phase 2 — build + sign a bundle with a custom
/// payload_type.  Used by the payload_type_router routing tests.
fn buildSignedBundleWithType(
    fx: *Fixture,
    inner_request: []const u8,
    payload_type: []const u8,
    nonce_byte: u8,
    timestamp: i64,
) ![]u8 {
    const root_id = identity_certs.certIdFromPubkey(fx.root_pubkey);
    const leaf_id = identity_certs.certIdFromPubkey(fx.leaf_pubkey);
    var chain = [_]signed_bundle.CertRef{
        .{
            .cert_id = leaf_id,
            .pubkey = fx.leaf_pubkey,
            .context_tag = 0x10,
            .parent_cert_id = root_id,
        },
        .{
            .cert_id = root_id,
            .pubkey = fx.root_pubkey,
            .context_tag = 0,
            .parent_cert_id = null,
        },
    };
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, nonce_byte);
    var bundle = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = root_id,
        .payload_type = payload_type,
        .payload = inner_request,
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{
            .nonce_hex = nonce,
            .timestamp_unix = timestamp,
        },
    };
    try signed_bundle.signBundle(allocator, &bundle, fx.leaf_priv);
    return signed_bundle.encode(allocator, bundle);
}

// ─────────────────────────────────────────────────────────────────────
// Happy path
// ─────────────────────────────────────────────────────────────────────

test "e2e: signed bundle dispatching bearer_tokens.list returns wire.Response with the list result" {
    const caps = [_][]const u8{"cap.brain.admin"};
    const fx = try buildFixture("phase4-e2e-happy-root", &caps);
    defer {
        fx.deinit();
        allocator.destroy(fx);
    }

    const inner =
        \\{"v":1,"resource":"bearer_tokens","cmd":"list","args":null,"request_id":"req-e2e-1"}
    ;
    const bytes = try buildSignedBundle(fx, inner, 'h', realClock());
    defer allocator.free(bytes);

    const outcome = try transport.processBundle(&fx.acceptor, bytes);
    defer allocator.free(outcome.body);

    try std.testing.expectEqual(std.http.Status.ok, outcome.http_status);
    var owned = try wire.decodeResponse(allocator, outcome.body);
    defer owned.deinit();

    try std.testing.expectEqualStrings("req-e2e-1", owned.response.request_id);
    try std.testing.expect(owned.response.err == null);
    // The list result is `{"tokens":[...]}` — our token store has
    // zero entries; the result must contain "tokens".
    try std.testing.expect(std.mem.indexOf(u8, owned.response.result_json, "tokens") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Negative paths
// ─────────────────────────────────────────────────────────────────────

test "e2e: bundle signed by unknown cert → 401 capability_denied" {
    const caps = [_][]const u8{"cap.brain.admin"};
    const fx = try buildFixture("phase4-e2e-unknown", &caps);
    defer {
        fx.deinit();
        allocator.destroy(fx);
    }

    // Build a "leaf" with a pubkey that was NEVER registered in the
    // cert store.
    const fake_priv = bkds.privFromSeed("phase4-e2e-unknown-fake-priv");
    const fake_pubkey = try bkds.pubFromSeed("phase4-e2e-unknown-fake-priv");
    const fake_id = identity_certs.certIdFromPubkey(fake_pubkey);
    const root_id = identity_certs.certIdFromPubkey(fx.root_pubkey);

    var chain = [_]signed_bundle.CertRef{
        .{
            .cert_id = fake_id,
            .pubkey = fake_pubkey,
            .context_tag = 0x10,
            .parent_cert_id = root_id,
        },
    };
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 'u');
    var bundle = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = root_id,
        .payload_type = "dispatch.request",
        .payload =
            \\{"v":1,"resource":"bearer_tokens","cmd":"list","args":null,"request_id":"req-u"}
        ,
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{ .nonce_hex = nonce, .timestamp_unix = realClock() },
    };
    try signed_bundle.signBundle(allocator, &bundle, fake_priv);
    const bytes = try signed_bundle.encode(allocator, bundle);
    defer allocator.free(bytes);

    const outcome = try transport.processBundle(&fx.acceptor, bytes);
    defer allocator.free(outcome.body);

    try std.testing.expectEqual(std.http.Status.unauthorized, outcome.http_status);
    var owned = try wire.decodeResponse(allocator, outcome.body);
    defer owned.deinit();
    try std.testing.expect(owned.response.err != null);
    try std.testing.expectEqual(wire.ErrorKind.capability_denied, owned.response.err.?.kind);
    try std.testing.expectEqualStrings("leaf_cert_unknown", owned.response.err.?.message);
}

test "e2e: bundle addressed to wrong recipient → 403" {
    const caps = [_][]const u8{"cap.brain.admin"};
    const fx = try buildFixture("phase4-e2e-wrong-recipient", &caps);
    defer {
        fx.deinit();
        allocator.destroy(fx);
    }

    const root_id = identity_certs.certIdFromPubkey(fx.root_pubkey);
    const leaf_id = identity_certs.certIdFromPubkey(fx.leaf_pubkey);

    var chain = [_]signed_bundle.CertRef{
        .{
            .cert_id = leaf_id,
            .pubkey = fx.leaf_pubkey,
            .context_tag = 0x10,
            .parent_cert_id = root_id,
        },
    };
    // Wrong recipient address — wire claims a different brain.
    const wrong_recipient: [signed_bundle.CERT_ID_HEX_LEN]u8 = "11111111111111111111111111111111".*;
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 'w');
    var bundle = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = wrong_recipient,
        .payload_type = "dispatch.request",
        .payload =
            \\{"v":1,"resource":"bearer_tokens","cmd":"list","args":null,"request_id":"req-w"}
        ,
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{ .nonce_hex = nonce, .timestamp_unix = realClock() },
    };
    try signed_bundle.signBundle(allocator, &bundle, fx.leaf_priv);
    const bytes = try signed_bundle.encode(allocator, bundle);
    defer allocator.free(bytes);

    const outcome = try transport.processBundle(&fx.acceptor, bytes);
    defer allocator.free(outcome.body);

    try std.testing.expectEqual(std.http.Status.forbidden, outcome.http_status);
    var owned = try wire.decodeResponse(allocator, outcome.body);
    defer owned.deinit();
    try std.testing.expect(owned.response.err != null);
    try std.testing.expectEqual(wire.ErrorKind.capability_denied, owned.response.err.?.kind);
    try std.testing.expectEqualStrings("recipient_mismatch", owned.response.err.?.message);
}

test "e2e: malformed inner payload → 400 validation_failed" {
    const caps = [_][]const u8{"cap.brain.admin"};
    const fx = try buildFixture("phase4-e2e-malformed", &caps);
    defer {
        fx.deinit();
        allocator.destroy(fx);
    }

    const bytes = try buildSignedBundle(fx, "not-a-valid-json {", 'm', realClock());
    defer allocator.free(bytes);

    const outcome = try transport.processBundle(&fx.acceptor, bytes);
    defer allocator.free(outcome.body);

    try std.testing.expectEqual(std.http.Status.bad_request, outcome.http_status);
    var owned = try wire.decodeResponse(allocator, outcome.body);
    defer owned.deinit();
    try std.testing.expect(owned.response.err != null);
    try std.testing.expectEqual(wire.ErrorKind.validation_failed, owned.response.err.?.kind);
}

test "e2e: capability_denied surfaces typed error from dispatcher" {
    // Empty cap list — the leaf cert exists but holds zero caps.
    // bearer_tokens.list requires `cap.brain.admin` which the leaf
    // does not hold — dispatcher returns capability_denied.
    const fx = try buildFixture("phase4-e2e-cap-denied", &.{});
    defer {
        fx.deinit();
        allocator.destroy(fx);
    }

    const inner =
        \\{"v":1,"resource":"bearer_tokens","cmd":"list","args":null,"request_id":"req-cd"}
    ;
    const bytes = try buildSignedBundle(fx, inner, 'd', realClock());
    defer allocator.free(bytes);

    const outcome = try transport.processBundle(&fx.acceptor, bytes);
    defer allocator.free(outcome.body);

    try std.testing.expectEqual(std.http.Status.forbidden, outcome.http_status);
    var owned = try wire.decodeResponse(allocator, outcome.body);
    defer owned.deinit();
    try std.testing.expect(owned.response.err != null);
    try std.testing.expectEqual(wire.ErrorKind.capability_denied, owned.response.err.?.kind);
}

test "e2e: replay protection — same nonce twice rejects" {
    const caps = [_][]const u8{"cap.brain.admin"};
    const fx = try buildFixture("phase4-e2e-replay", &caps);
    defer {
        fx.deinit();
        allocator.destroy(fx);
    }

    const inner =
        \\{"v":1,"resource":"bearer_tokens","cmd":"list","args":null,"request_id":"req-r"}
    ;
    const bytes = try buildSignedBundle(fx, inner, 'r', realClock());
    defer allocator.free(bytes);

    const first = try transport.processBundle(&fx.acceptor, bytes);
    allocator.free(first.body);
    try std.testing.expectEqual(std.http.Status.ok, first.http_status);

    const second = try transport.processBundle(&fx.acceptor, bytes);
    defer allocator.free(second.body);
    try std.testing.expectEqual(std.http.Status.conflict, second.http_status);

    var owned = try wire.decodeResponse(allocator, second.body);
    defer owned.deinit();
    try std.testing.expect(owned.response.err != null);
    try std.testing.expectEqualStrings("nonce_replay", owned.response.err.?.message);
}

test "e2e: stale timestamp rejected (freshness window)" {
    const caps = [_][]const u8{"cap.brain.admin"};
    const fx = try buildFixture("phase4-e2e-stale", &caps);
    defer {
        fx.deinit();
        allocator.destroy(fx);
    }

    // Timestamp is 1 hour in the past — well outside the 5-min window.
    const inner =
        \\{"v":1,"resource":"bearer_tokens","cmd":"list","args":null,"request_id":"req-s"}
    ;
    const bytes = try buildSignedBundle(fx, inner, 's', realClock() - 3600);
    defer allocator.free(bytes);

    const outcome = try transport.processBundle(&fx.acceptor, bytes);
    defer allocator.free(outcome.body);

    try std.testing.expectEqual(std.http.Status.gone, outcome.http_status);
    var owned = try wire.decodeResponse(allocator, outcome.body);
    defer owned.deinit();
    try std.testing.expect(owned.response.err != null);
    try std.testing.expectEqualStrings("stale_or_future_timestamp", owned.response.err.?.message);
}

// ─────────────────────────────────────────────────────────────────────
// Audit pair invariant
// ─────────────────────────────────────────────────────────────────────

test "e2e: happy path emits audit pair tagged transport=signed_bundle" {
    const caps = [_][]const u8{"cap.brain.admin"};
    const fx = try buildFixture("phase4-e2e-audit", &caps);
    defer {
        fx.deinit();
        allocator.destroy(fx);
    }

    const inner =
        \\{"v":1,"resource":"bearer_tokens","cmd":"list","args":null,"request_id":"req-a"}
    ;
    const bytes = try buildSignedBundle(fx, inner, 'a', realClock());
    defer allocator.free(bytes);

    const outcome = try transport.processBundle(&fx.acceptor, bytes);
    allocator.free(outcome.body);
    try std.testing.expectEqual(std.http.Status.ok, outcome.http_status);

    // Read the audit log; assert phase=start AND phase=end lines
    // tagged transport=signed_bundle.
    fx.audit.close();
    const text = try std.fs.cwd().readFileAlloc(allocator, fx.audit_path, 1024 * 1024);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "transport=signed_bundle") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "phase=start") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "phase=end") != null);
    // Reopen for the deinit's close().
    try fx.audit.open(fx.audit_path);
}

// ─────────────────────────────────────────────────────────────────────
// D-O5m.followup-6 Phase 2 — payload_type router gate
// ─────────────────────────────────────────────────────────────────────

test "e2e: bundle with unknown payload_type returns 400 unknown_payload_type" {
    const caps = [_][]const u8{"cap.brain.admin"};
    const fx = try buildFixture("phase2-payload-router-unknown", &caps);
    defer {
        fx.deinit();
        allocator.destroy(fx);
    }

    const inner =
        \\{"v":1,"resource":"bearer_tokens","cmd":"list","args":null,"request_id":"req-x"}
    ;
    // payload_type doesn't match any router decision → unknown_payload_type.
    const bytes = try buildSignedBundleWithType(fx, inner, "plexus.identity.update", 'x', realClock());
    defer allocator.free(bytes);

    const outcome = try transport.processBundle(&fx.acceptor, bytes);
    defer allocator.free(outcome.body);

    try std.testing.expectEqual(std.http.Status.bad_request, outcome.http_status);
    try std.testing.expect(std.mem.indexOf(u8, outcome.body, "unknown_payload_type") != null);
}

test "e2e: bundle with oddjobz.cell.create payload_type accepted by router" {
    const caps = [_][]const u8{"cap.brain.admin"};
    const fx = try buildFixture("phase2-payload-router-cell", &caps);
    defer {
        fx.deinit();
        allocator.destroy(fx);
    }

    // Router accepts oddjobz.cell.create; the inner payload is still a
    // wire.Request envelope at v0.1 (the dispatcher path is unchanged
    // — Phase 2 ships the seam, not the new handler integration).
    const inner =
        \\{"v":1,"resource":"bearer_tokens","cmd":"list","args":null,"request_id":"req-c"}
    ;
    const bytes = try buildSignedBundleWithType(fx, inner, "oddjobz.cell.create", 'c', realClock());
    defer allocator.free(bytes);

    const outcome = try transport.processBundle(&fx.acceptor, bytes);
    defer allocator.free(outcome.body);

    try std.testing.expectEqual(std.http.Status.ok, outcome.http_status);
}

test "e2e: bundle with oddjobz.attachment.create payload_type accepted by router" {
    const caps = [_][]const u8{"cap.brain.admin"};
    const fx = try buildFixture("phase2-payload-router-att", &caps);
    defer {
        fx.deinit();
        allocator.destroy(fx);
    }

    const inner =
        \\{"v":1,"resource":"bearer_tokens","cmd":"list","args":null,"request_id":"req-a2"}
    ;
    const bytes = try buildSignedBundleWithType(fx, inner, "oddjobz.attachment.create", 'A', realClock());
    defer allocator.free(bytes);

    const outcome = try transport.processBundle(&fx.acceptor, bytes);
    defer allocator.free(outcome.body);

    try std.testing.expectEqual(std.http.Status.ok, outcome.http_status);
}

test "e2e: bundle with invalid signature is rejected before payload_type routing" {
    const caps = [_][]const u8{"cap.brain.admin"};
    const fx = try buildFixture("phase2-payload-router-sig", &caps);
    defer {
        fx.deinit();
        allocator.destroy(fx);
    }

    const root_id = identity_certs.certIdFromPubkey(fx.root_pubkey);
    const leaf_id = identity_certs.certIdFromPubkey(fx.leaf_pubkey);
    var chain = [_]signed_bundle.CertRef{
        .{
            .cert_id = leaf_id,
            .pubkey = fx.leaf_pubkey,
            .context_tag = 0x10,
            .parent_cert_id = root_id,
        },
        .{
            .cert_id = root_id,
            .pubkey = fx.root_pubkey,
            .context_tag = 0,
            .parent_cert_id = null,
        },
    };
    var nonce: [signed_bundle.NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 's');
    // Build the bundle but DO NOT sign — leave signature all-zero so
    // verifySignature fails before payload_type routing runs.
    const bundle = signed_bundle.SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = root_id,
        // Even an unknown payload_type can't matter here — the
        // signature gate runs first.
        .payload_type = "oddjobz.attachment.create",
        .payload = "{\"v\":1,\"resource\":\"bearer_tokens\",\"cmd\":\"list\",\"args\":null,\"request_id\":\"r\"}",
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{ .nonce_hex = nonce, .timestamp_unix = realClock() },
    };
    const bytes = try signed_bundle.encode(allocator, bundle);
    defer allocator.free(bytes);

    const outcome = try transport.processBundle(&fx.acceptor, bytes);
    defer allocator.free(outcome.body);

    // 401 from signature_invalid; the body must NOT contain the
    // payload-type-router error string.
    try std.testing.expectEqual(std.http.Status.unauthorized, outcome.http_status);
    try std.testing.expect(std.mem.indexOf(u8, outcome.body, "unknown_payload_type") == null);
}

```
