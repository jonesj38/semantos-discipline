---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/resources/identity_certs_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.294519+00:00
---

# runtime/semantos-brain/src/resources/identity_certs_handler.zig

```zig
// Phase D-W1 / Phase 1 Part 2 — Dispatcher resource handler for identity_certs.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3 (identity_certs
//            row), §7 (auth & capabilities); docs/spec/protocol-v0.5.md
//            §4.4 (per-device contextTag isolation);
//            docs/design/ODDJOBZ-EXTENSION-PLAN.md §3 Phase O5p (the
//            consumer of this handler — child-cert pairing).
//
// Same architectural shape as `bearer_tokens_handler.zig` (Phase 1 Part 1):
//
//   • Dispatcher seam: every transport (in-process REPL, Unix socket
//     CLI-RPC, HTTP from helm SPA, future SignedBundle mesh peer)
//     reaches the cert chain through this handler.  No transport
//     mutates the on-disk log directly.
//
//   • Mutex-serialised: every entry point locks `mu` for the duration
//     of the store call.  In-flight issuances are atomic against the
//     index + log.
//
//   • Capability gating: `issue_root`, `issue_child`, `revoke`, `list`,
//     `get` all require `cap.brain.admin`.  Future revisions (post-D-O5p)
//     will narrow `issue_child` to a per-tenant cap so a child cert
//     pairing flow can be authorised by something more scoped than
//     full root.
//
// Commands (per the brief):
//
//   issue_root   — { pubkey, label }
//                  → existing root record OR newly minted record;
//                    idempotent on second call.
//                    cap = cap.brain.admin
//
//   issue_child  — { parent_cert_id, context_tag, capabilities, label,
//                    derivation_pubkey, derivation_proof }
//                  → child cert record.
//                    Under canonical BRC-42 (invoice-with-counterparty
//                    + secp256k1 scalar tweak), the wire fields carry:
//                      • `derivation_proof`  = device's compressed-SEC1
//                        base/counterparty pubkey (33 bytes hex).
//                      • `derivation_pubkey` = the BRC-42 child pubkey
//                        the device computed via
//                        `device_priv.deriveChild(operator_root_pub,
//                        invoice).publicKey()` (33-byte compressed SEC1).
//                    The handler recomputes the expected child pubkey
//                    on the brain side via
//                    `operator_root_priv.deriveChild(derivation_proof,
//                    invoice).publicKey()` and constant-time compares.
//                    Invoice = "BKDS-BRC42-v1" || u8(context_tag) ||
//                    u32_be(label.len) || label  (see `bkds.zig`).
//                    Mismatch → derivation_context_mismatch.
//                    cap = cap.brain.admin
//
//   list         — {} → { certs: [...] }
//                    Excludes revoked.  cap = cap.brain.admin
//
//   revoke       — { cert_id } → { ok }
//                    Revoking the root → cannot_revoke_root.
//                    cap = cap.brain.admin
//
//   get          — { cert_id } → cert record OR cert_not_found.
//                    cap = cap.brain.admin
//
// Threat model the implementation enforces (the security argument the
// brief asks the tests to exhibit):
//
//   • cap forgery — capabilities ride on the child record bound by the
//     BRC-42 derivation proof.  An attacker without `device_priv`
//     cannot produce a `derivation_pubkey` matching the brain's
//     recomputation under the supplied counterparty (their submitted
//     pubkey would have to ECDH back to a shared secret they can't
//     compute without the real device priv).  Cap minting is gated on
//     cert existence.
//
//   • cross-device impersonation — the carpenter (`0x10`) and musician
//     (`0x11`) hat scenario from §2.5.  Context tag rides into the
//     invoice as a single byte; a swap reshapes the HMAC tweak and
//     therefore the child.  A child computed under 0x10 does not
//     verify when claimed under 0x11.  Surfaces as `proof_mismatch` →
//     `derivation_context_mismatch`.
//
//   • revocation bypass — once a cert is revoked, it is dropped from
//     the live index.  `get` returns `cert_not_found`; `list` excludes
//     it; subsequent `issue_child` against the revoked id surfaces as
//     `parent_not_found`.  This matches the bearer_tokens semantics —
//     revocation propagates within one heartbeat (per the O5p
//     acceptance gate in ODDJOBZ-EXTENSION-PLAN.md).
//
// Operator-priv injection: the brain must hold `operator_root_priv`
// (the secp256k1 scalar matching the cert chain's root pubkey) to
// verify BRC-42 derivations.  `Handler.init` accepts an *optional*
// priv; when unset, `issue_child` fails closed with
// `derivation_context_mismatch`.  The conformance suite installs a
// deterministic priv via `setOperatorRootPriv` before driving
// `issue_child`.
//
// TODO(D-O5p): cmdServe in cli.zig does NOT yet call
// `setOperatorRootPriv`, so the production daemon path returns
// `derivation_context_mismatch` on every `issue_child` until D-O5p
// (Phase O5p — Child-cert pairing flow, see
// docs/design/ODDJOBZ-EXTENSION-PLAN.md §3) wires the priv-source.
// The intended source is a Plexus derivation recipe (algorithm
// version + cert_id + resource_id + parent_cert_id + domain_flag +
// current_index + epoch — see Plexus Tech Reqs v1.3 §23) evaluated
// against a locally-loaded operator seed file.  Domain flag for
// child-cert issuance is `0x06 = CHILD_CREATION` per
// docs/spec/protocol-v0.5.md §4.5.  D-O5p's "Acceptor side"
// (sub-deliverable O5p-c) is the natural place for this wiring
// since that's where the brain first verifies an incoming
// claim_child post.

const std = @import("std");
const dispatcher = @import("dispatcher");
const identity_certs = @import("identity_certs");
const bkds = @import("bkds");

pub const RESOURCE_NAME = "identity_certs";

pub const HandlerError = error{
    /// JSON args parse failed or required arg missing.
    invalid_args,
    /// Underlying CertStore call failed (file I/O, JSON parse, etc.).
    store_error,
    /// `revoke` / `get` referenced an id that doesn't exist (or was
    /// already revoked).
    cert_not_found,
    /// Operator tried to revoke the root cert via `brain device revoke`.
    /// Recovery is the right path; routine revocation is for children.
    cannot_revoke_root,
    /// `issue_child` proof failed verification (forged proof or
    /// context-tag mismatch).
    derivation_context_mismatch,
    /// `issue_child` referenced a parent that doesn't exist.
    parent_not_found,
    /// `issue_child` referenced a parent that is revoked.
    parent_revoked,
    /// One of the supplied capabilities failed validation.
    capability_invalid,
    /// Result-allocation failed.
    out_of_memory,
};

/// State the handler carries.  The dispatcher hands `state` to every
/// callback as `*anyopaque`; we cast it back to `*Handler`.
pub const Handler = struct {
    allocator: std.mem.Allocator,
    store: *identity_certs.CertStore,
    /// secp256k1 scalar matching the cert chain's root pubkey.  When
    /// set, `issue_child` performs canonical BRC-42 verification
    /// (recompute the child pubkey on the brain side and constant-time
    /// compare against the device-submitted `derivation_pubkey`).
    /// When null, `issue_child` fails closed with
    /// `derivation_context_mismatch` — the brain cannot verify a BRC-42
    /// derivation without the priv half.  Production wiring sets it via
    /// `setOperatorRootPriv`.
    operator_root_priv: ?[bkds.PRIVKEY_LEN]u8,
    /// Serialises issue_root / issue_child / revoke / list / get
    /// against the store.  Same threading model as bearer_tokens_handler.
    mu: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, store: *identity_certs.CertStore) Handler {
        return .{
            .allocator = allocator,
            .store = store,
            .operator_root_priv = null,
            .mu = .{},
        };
    }

    /// Install the operator's root secp256k1 priv key so `issue_child`
    /// can verify BRC-42 derivations.  Caller is responsible for
    /// keeping the priv off-disk; this handler holds it in-memory only.
    pub fn setOperatorRootPriv(self: *Handler, priv: [bkds.PRIVKEY_LEN]u8) void {
        self.operator_root_priv = priv;
    }

    /// Clear the operator priv (used by tests that want to exercise
    /// the fail-closed path).
    pub fn clearOperatorRootPriv(self: *Handler) void {
        self.operator_root_priv = null;
    }

    pub fn resourceHandler(self: *Handler) dispatcher.ResourceHandler {
        return .{
            .name = RESOURCE_NAME,
            .state = self,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handle,
        };
    }
};

// ─────────────────────────────────────────────────────────────────────
// Capability declarations
// ─────────────────────────────────────────────────────────────────────

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "issue_root")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "issue_child")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "list")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "revoke")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "get")) return .{ .require = "cap.brain.admin" };
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Dispatch entry point
// ─────────────────────────────────────────────────────────────────────

fn handle(
    state: ?*anyopaque,
    _: *const dispatcher.DispatchContext,
    cmd: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher.Result {
    const self: *Handler = @ptrCast(@alignCast(state.?));
    self.mu.lock();
    defer self.mu.unlock();

    if (std.mem.eql(u8, cmd, "issue_root")) return handleIssueRoot(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "issue_child")) return handleIssueChild(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "list")) return handleList(self, allocator);
    if (std.mem.eql(u8, cmd, "revoke")) return handleRevoke(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "get")) return handleGet(self, allocator, args_json);
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Per-command implementations
// ─────────────────────────────────────────────────────────────────────

fn handleIssueRoot(
    self: *Handler,
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !dispatcher.Result {
    const args = parseIssueRootArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(args.label);

    const rec = self.store.issueRoot(args.pubkey, args.label) catch |err| switch (err) {
        identity_certs.CertError.out_of_memory => return HandlerError.out_of_memory,
        else => return HandlerError.store_error,
    };

    return ownedRecordPayload(allocator, rec);
}

fn handleIssueChild(
    self: *Handler,
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !dispatcher.Result {
    const args = parseIssueChildArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer args.deinit(allocator);

    // Look up parent — must exist + not be revoked.  parent_revoked is
    // also surfaced as parent_not_found by the underlying store (the
    // store drops revoked records from the live index), but we make
    // the distinction visible at the handler boundary for any future
    // soft-revoke variants by checking the kind here.  Today both
    // paths return parent_not_found.
    const parent = self.store.get(args.parent_cert_id) catch |err| switch (err) {
        identity_certs.CertError.cert_not_found => return HandlerError.parent_not_found,
        else => return HandlerError.store_error,
    };
    if (parent.kind == .child) {
        // A child cert can't be a parent in v0.1 — only the operator's
        // root issues children.  This protects the cert DAG from
        // accidental two-level chains the dispatcher can't yet evaluate.
        return HandlerError.parent_not_found;
    }

    // BRC-42 proof verification — the structural argument the brief
    // asks the tests to exhibit.  The brain holds operator_root_priv;
    // it recomputes the child pubkey on its side from
    // (operator_root_priv, derivation_proof_pubkey, context_tag, label)
    // and constant-time compares against derivation_pubkey.  Failure
    // modes:
    //   • operator priv not installed (handler init only) → fail
    //     closed with derivation_context_mismatch
    //   • forged counterparty pubkey (derivation_proof) → recomputed
    //     child differs → derivation_context_mismatch
    //   • context-tag or label swap → recomputed child differs →
    //     derivation_context_mismatch
    //
    // Note: parent.pubkey (the operator-root cert's *public* half) is
    // not used in BRC-42 verification — the brain uses its priv.  We
    // still require the root cert to exist (parent_not_found check
    // above) so the binding "this child is under this root chain"
    // surfaces in the audit log + cert graph.
    const root_priv = self.operator_root_priv orelse return HandlerError.derivation_context_mismatch;
    bkds.verifyDerivationProof(
        root_priv,
        args.derivation_proof,
        args.context_tag,
        args.label,
        args.derivation_pubkey,
    ) catch return HandlerError.derivation_context_mismatch;

    const rec = self.store.issueChild(
        args.parent_cert_id,
        args.context_tag,
        args.derivation_pubkey,
        args.capabilities,
        args.label,
    ) catch |err| switch (err) {
        identity_certs.CertError.parent_not_found => return HandlerError.parent_not_found,
        identity_certs.CertError.parent_revoked => return HandlerError.parent_revoked,
        identity_certs.CertError.capability_invalid => return HandlerError.capability_invalid,
        identity_certs.CertError.out_of_memory => return HandlerError.out_of_memory,
        else => return HandlerError.store_error,
    };

    return ownedRecordPayload(allocator, rec);
}

fn handleList(self: *Handler, allocator: std.mem.Allocator) !dispatcher.Result {
    const items = self.store.list(allocator) catch return HandlerError.store_error;
    defer allocator.free(items);

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"certs\":[");
    for (items, 0..) |rec, i| {
        if (i != 0) try buf.append(allocator, ',');
        try writeRecordJson(allocator, &buf, rec);
    }
    try buf.appendSlice(allocator, "]}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleRevoke(
    self: *Handler,
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !dispatcher.Result {
    const id = parseCertIdArg(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(id);

    self.store.revoke(id) catch |err| switch (err) {
        identity_certs.CertError.cannot_revoke_root => return HandlerError.cannot_revoke_root,
        identity_certs.CertError.cert_not_found => return HandlerError.cert_not_found,
        else => return HandlerError.store_error,
    };

    const payload = try allocator.dupe(u8, "{\"ok\":true}");
    return dispatcher.Result.ownedPayload(allocator, payload);
}

fn handleGet(
    self: *Handler,
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !dispatcher.Result {
    const id = parseCertIdArg(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(id);

    const rec = self.store.get(id) catch |err| switch (err) {
        identity_certs.CertError.cert_not_found => return HandlerError.cert_not_found,
        else => return HandlerError.store_error,
    };
    return ownedRecordPayload(allocator, rec);
}

// ─────────────────────────────────────────────────────────────────────
// Argument parsing
// ─────────────────────────────────────────────────────────────────────

const IssueRootArgs = struct {
    pubkey: [bkds.KEY_LEN]u8,
    label: []u8, // owned
};

fn parseIssueRootArgs(allocator: std.mem.Allocator, args_json: []const u8) !IssueRootArgs {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    const pub_v = obj.get("pubkey") orelse return error.invalid_args;
    if (pub_v != .string) return error.invalid_args;
    if (pub_v.string.len != bkds.KEY_LEN * 2) return error.invalid_args;
    var pubkey: [bkds.KEY_LEN]u8 = undefined;
    bkds.hexDecode(pub_v.string, &pubkey) catch return error.invalid_args;

    const label_v = obj.get("label") orelse return error.invalid_args;
    if (label_v != .string) return error.invalid_args;
    const label = try allocator.dupe(u8, label_v.string);

    return .{ .pubkey = pubkey, .label = label };
}

const IssueChildArgs = struct {
    parent_cert_id: []u8, // owned, 32 hex chars
    context_tag: u8,
    capabilities: [][]u8, // owned slice-of-owned-strings
    label: []u8, // owned
    /// 33-byte compressed-SEC1 secp256k1 child pubkey — what the device
    /// computed via `device_priv.deriveChild(operator_root_pub, invoice)
    /// .publicKey()`.  Stored verbatim in the cert record once verified.
    derivation_pubkey: [bkds.KEY_LEN]u8,
    /// 33-byte compressed-SEC1 secp256k1 device base/counterparty pubkey
    /// — what the brain feeds back through BRC-42 with `operator_root_
    /// priv` to recompute the expected `derivation_pubkey`.  Under the
    /// HMAC-SHA-512 prototype this carried a 32-byte HMAC tag; under
    /// canonical BRC-42 it's the device's identity pubkey.
    derivation_proof: [bkds.PROOF_LEN]u8,

    fn deinit(self: IssueChildArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.parent_cert_id);
        for (self.capabilities) |c| allocator.free(c);
        if (self.capabilities.len > 0) allocator.free(self.capabilities);
        allocator.free(self.label);
    }
};

fn parseIssueChildArgs(allocator: std.mem.Allocator, args_json: []const u8) !IssueChildArgs {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    const parent_v = obj.get("parent_cert_id") orelse return error.invalid_args;
    if (parent_v != .string or parent_v.string.len != identity_certs.CERT_ID_HEX_LEN) {
        return error.invalid_args;
    }
    const parent_cert_id = try allocator.dupe(u8, parent_v.string);
    errdefer allocator.free(parent_cert_id);

    const ctx_v = obj.get("context_tag") orelse return error.invalid_args;
    if (ctx_v != .integer or ctx_v.integer < 0 or ctx_v.integer > 255) {
        return error.invalid_args;
    }
    const context_tag: u8 = @intCast(ctx_v.integer);

    const caps_v = obj.get("capabilities") orelse return error.invalid_args;
    if (caps_v != .array) return error.invalid_args;
    var cap_list: std.ArrayList([]u8) = .{};
    errdefer {
        for (cap_list.items) |c| allocator.free(c);
        cap_list.deinit(allocator);
    }
    for (caps_v.array.items) |c| {
        if (c != .string) return error.invalid_args;
        const owned = try allocator.dupe(u8, c.string);
        try cap_list.append(allocator, owned);
    }
    const capabilities = try cap_list.toOwnedSlice(allocator);
    errdefer {
        for (capabilities) |c| allocator.free(c);
        if (capabilities.len > 0) allocator.free(capabilities);
    }

    const label_v = obj.get("label") orelse return error.invalid_args;
    if (label_v != .string) return error.invalid_args;
    const label = try allocator.dupe(u8, label_v.string);
    errdefer allocator.free(label);

    const dp_v = obj.get("derivation_pubkey") orelse return error.invalid_args;
    if (dp_v != .string or dp_v.string.len != bkds.KEY_LEN * 2) return error.invalid_args;
    var derivation_pubkey: [bkds.KEY_LEN]u8 = undefined;
    bkds.hexDecode(dp_v.string, &derivation_pubkey) catch return error.invalid_args;

    const proof_v = obj.get("derivation_proof") orelse return error.invalid_args;
    if (proof_v != .string) return error.invalid_args;
    if (proof_v.string.len != bkds.PROOF_LEN * 2) return error.invalid_args;
    var derivation_proof: [bkds.PROOF_LEN]u8 = undefined;
    bkds.hexDecode(proof_v.string, &derivation_proof) catch return error.invalid_args;

    return .{
        .parent_cert_id = parent_cert_id,
        .context_tag = context_tag,
        .capabilities = capabilities,
        .label = label,
        .derivation_pubkey = derivation_pubkey,
        .derivation_proof = derivation_proof,
    };
}

fn parseCertIdArg(allocator: std.mem.Allocator, args_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const id_v = obj.get("cert_id") orelse return error.invalid_args;
    if (id_v != .string or id_v.string.len != identity_certs.CERT_ID_HEX_LEN) {
        return error.invalid_args;
    }
    return try allocator.dupe(u8, id_v.string);
}

// ─────────────────────────────────────────────────────────────────────
// JSON shape — one cert record on the wire.
// ─────────────────────────────────────────────────────────────────────

fn ownedRecordPayload(
    allocator: std.mem.Allocator,
    rec: identity_certs.CertRecord,
) !dispatcher.Result {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try writeRecordJson(allocator, &buf, rec);
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn writeRecordJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    rec: identity_certs.CertRecord,
) !void {
    var pub_hex: [bkds.KEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&rec.pubkey, &pub_hex);
    const kind_str: []const u8 = if (rec.kind == .root) "root" else "child";
    try out.print(
        allocator,
        "{{\"kind\":\"{s}\",\"cert_id\":\"{s}\",\"context_tag\":{d},\"pubkey\":\"{s}\",",
        .{ kind_str, rec.id, rec.context_tag, pub_hex },
    );
    if (rec.has_parent) {
        try out.print(allocator, "\"parent_cert_id\":\"{s}\",", .{rec.parent_cert_id});
    }
    try out.appendSlice(allocator, "\"capabilities\":[");
    for (rec.capabilities, 0..) |c, i| {
        if (i != 0) try out.append(allocator, ',');
        try writeJsonString(allocator, out, c);
    }
    try out.appendSlice(allocator, "],\"label\":");
    try writeJsonString(allocator, out, rec.label);
    try out.print(allocator, ",\"issued_at\":{d},\"revoked\":false}}", .{rec.issued_at});
}

fn writeJsonString(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    s: []const u8,
) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

```
