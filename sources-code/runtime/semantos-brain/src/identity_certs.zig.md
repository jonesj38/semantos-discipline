---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/identity_certs.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.224055+00:00
---

# runtime/semantos-brain/src/identity_certs.zig

```zig
// Phase D-W1 / Phase 1 Part 2 — Identity-cert chain store + log replay.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3 (identity_certs
//            row), §2.5 (carpenter+musician hat isolation);
//            docs/spec/protocol-v0.5.md §4.4 (identity DAG), §4.5 (domain
//            flag namespace);
//            docs/design/ODDJOBZ-EXTENSION-PLAN.md §3 Phase O5p (the
//            consumer of this store: child-cert pairing flow).
//
// What this is: an append-only JSON-line log + in-memory index of
// identity certs (one operator-root + N child certs).  Mirrors
// `bearer_tokens.zig`'s shape (Phase 1 Part 1):
//
//   • Append-only log at `<data_dir>/identity-certs.log` with three
//     event kinds: `root` (operator's root cert minted on first
//     `issue_root`), `child` (a paired device cert under the root),
//     `revoked` (a child cert spent / superseded).
//
//   • In-memory index rebuilt at process startup by replaying the log
//     line by line.  Index is a `cert_id → record` hashmap.  Revoked
//     children are dropped from the live index (matching bearer_tokens
//     semantics — `get` returns `cert_not_found` for a revoked id, and
//     `list` excludes revoked).
//
//   • Concurrency v0.1 — single-process only, same caveat as
//     bearer_tokens (see TODO at top of bearer_tokens_handler.zig).
//
// What lives elsewhere:
//
//   • The dispatcher resource handler (capability-gated, JSON
//     args/results) lives in `resources/identity_certs_handler.zig`.
//     This file is the storage seam the handler talks to.
//
//   • The BRC-42 invoice-with-counterparty key-derivation algorithm and
//     the proof shape live in `bkds.zig`.  This file calls into bkds for
//     verification during `issueChild`; it never touches the underlying
//     curve arithmetic.

const std = @import("std");
const bkds = @import("bkds");

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

pub const CertError = error{
    /// The named cert id is not in the live index (either never issued
    /// or already revoked).
    cert_not_found,
    /// The operator's root cert may not be revoked — D-O5p depends on
    /// it as the trust anchor for the entire identity DAG.  Revoking
    /// the root means re-pairing every device, which is a recovery
    /// operation, not a routine `brain device revoke`.
    cannot_revoke_root,
    /// The supplied `derivation_proof` did not bind the declared
    /// (root_pubkey, context_tag) → child_pubkey tuple.  Surfaces both
    /// "forged proof" and "context-tag swap across hats" — the
    /// structural argument for cross-device isolation.
    derivation_context_mismatch,
    /// `issue_child` referenced a `parent_cert_id` that doesn't exist.
    parent_not_found,
    /// `issue_child` referenced a parent cert that is revoked; child
    /// issuance under a revoked parent would create a cert with no
    /// trust anchor.
    parent_revoked,
    /// A capability string in the issue_child allowlist failed validation.
    capability_invalid,
    /// Underlying file I/O / JSON parse failed.
    store_error,
    /// Allocator OOM.
    out_of_memory,
    /// A second `issue_root` attempt arrived but the in-memory index
    /// already holds a root.  The handler maps this to the
    /// idempotent-return path; the underlying error is exposed for
    /// callers that want to detect "would-have-minted-second-root"
    /// explicitly.
    root_already_exists,
    /// Parsing a record from disk produced a length mismatch (e.g.
    /// pubkey not 33 bytes / cert_id not 32 hex chars).
    bad_format,
    /// A `hatId` declared in an envelope (e.g. oddjobz's
    /// `intent_cells.submit` payload) does not match the hat-chain
    /// anchor of the cert it claims to be signed under.  For a child
    /// cert the expected anchor is `parent_cert_id`; for the root cert
    /// it is the cert's own id.  Surfaces "context-tag swap across
    /// hats" at the boundary between a cartridge handler and the cert
    /// store — see `CertStore.verifyCertHatBinding`.
    hat_binding_mismatch,
};

// ─────────────────────────────────────────────────────────────────────
// Record shapes — `pubkey` is a 33-byte compressed-SEC1 secp256k1 point
// (BRC-42 child or operator root).  D-O5p (BRC-52 cert chains) inherits
// this shape unchanged.
// ─────────────────────────────────────────────────────────────────────

pub const CERT_ID_HEX_LEN: usize = 32;

pub const CertKind = enum {
    root,
    child,
};

/// D-O5m.followup-9 Phase A / Sovereign-push D.3 — push platform
/// discriminator carried on each cert record alongside `apns_token` /
/// `fcm_token` / `up_endpoint`.
///
/// Shape mirrors apps/oddjobz-mobile/lib/src/push/push_platform.dart so
/// the wire round-trips cleanly between the brain (this store) and the
/// device (PushTokenRegistration).
///
/// `none` is the default for legacy / unregistered certs and for certs
/// that just had a DELETE /api/v1/push-register call applied.  The
/// store derives the platform from which token / endpoint field is
/// non-empty (apns_token → apns; fcm_token → fcm; up_endpoint →
/// unifiedpush); when all are empty platform stays `none`.
///
/// Sovereign-push D.3: `unifiedpush` is the libre push protocol (see
/// https://unifiedpush.org/spec/).  Operators on Android can install a
/// distributor (ntfy, NextPush, Conversations, …) and route all wakes
/// off Google Firebase entirely.  The cert record holds the
/// distributor's endpoint URL in `up_endpoint`; the dispatcher POSTs
/// the wake JSON envelope directly to that URL — no auth, no provider
/// wrapper, the URL itself is the capability.
pub const PushPlatform = enum {
    none,
    apns,
    fcm,
    unifiedpush,

    pub fn wireName(self: PushPlatform) []const u8 {
        return switch (self) {
            .none => "none",
            .apns => "apns",
            .fcm => "fcm",
            .unifiedpush => "unifiedpush",
        };
    }

    pub fn fromWireName(s: []const u8) ?PushPlatform {
        if (std.mem.eql(u8, s, "none")) return .none;
        if (std.mem.eql(u8, s, "apns")) return .apns;
        if (std.mem.eql(u8, s, "fcm")) return .fcm;
        if (std.mem.eql(u8, s, "unifiedpush")) return .unifiedpush;
        return null;
    }
};

/// One cert in the live index.  `parent_cert_id` is empty for the
/// operator's root; populated for every child.  Capabilities + label
/// are owned by the store (freed in `deinit`).
pub const CertRecord = struct {
    kind: CertKind,
    /// 32-hex-char cert id.  Derived deterministically from the cert's
    /// 32-byte pubkey (sha256 of the pubkey, first 16 bytes hex) so
    /// pairing-time pubkey collisions surface as cert-id collisions.
    id: [CERT_ID_HEX_LEN]u8,
    /// Empty for kind = root; the parent cert id otherwise.
    parent_cert_id: [CERT_ID_HEX_LEN]u8,
    /// Has the parent_cert_id field been populated?  Distinguishes
    /// child certs from the root (the root carries 32 zero bytes in
    /// `parent_cert_id`).
    has_parent: bool,
    /// 0 for the root; the BKDS context tag the child was minted under
    /// (carpenter = 0x10, musician = 0x11, etc.).
    context_tag: u8,
    /// 33-byte compressed-SEC1 secp256k1 pubkey (BRC-42 child for child
    /// certs; operator root identity pubkey for the root cert).
    pubkey: [bkds.KEY_LEN]u8,
    /// Capabilities granted at issuance time (e.g.
    /// "cap.oddjobz.write_customer").  Owned slice-of-slices; freed
    /// alongside the record.
    capabilities: [][]u8,
    /// Operator-supplied label ("Todd's iPhone", "studio-laptop").
    /// Owned.
    label: []u8,
    /// Unix-seconds.
    issued_at: i64,
    /// D-O5m.followup-9 Phase A — APNs device token (Apple Push
    /// Notification service).  Empty unless the device has registered
    /// via POST /api/v1/push-register with `platform=apns`.  Per-string
    /// heap-allocated, owned by the store.
    apns_token: []u8 = &.{},
    /// D-O5m.followup-9 Phase A — FCM registration token (Firebase
    /// Cloud Messaging).  Empty unless the device has registered with
    /// `platform=fcm`.  Owned by the store.
    fcm_token: []u8 = &.{},
    /// Sovereign-push D.3 — UnifiedPush distributor endpoint URL.
    /// Empty unless the device has registered with `platform=
    /// unifiedpush`.  The brain POSTs the wake envelope directly to
    /// this URL with `Content-Type: application/json`; the URL itself
    /// is the capability (no auth, no key signing).  Owned by the
    /// store.
    up_endpoint: []u8 = &.{},
    /// D-O5m.followup-9 Phase A — derived from which token / endpoint
    /// is non-empty.  Default `none`; set to `apns`, `fcm`, or
    /// `unifiedpush` when a registration lands.  When
    /// `updatePushToken` clears all fields this returns to `none` (the
    /// device has unregistered).
    push_platform: PushPlatform = .none,
    /// D-O5m.followup-9 Phase A — ISO-8601 timestamp the most recent
    /// successful POST /api/v1/push-register landed at.  Empty for
    /// legacy / unregistered certs.  Owned.
    push_registered_at: []u8 = &.{},
};

// ─────────────────────────────────────────────────────────────────────
// Store
// ─────────────────────────────────────────────────────────────────────

pub const CertStore = struct {
    allocator: std.mem.Allocator,
    /// Absolute path to identity-certs.log.  Owned.
    log_path: []u8,
    /// Open log fd held for the store's lifetime; flushed after each
    /// append.
    log_file: ?std.fs.File,
    /// cert_id (hex, 32 chars, owned) → record.  Owned values; freed
    /// in deinit.
    by_id: std.StringHashMap(CertRecord),
    /// Pinned-clock for tests.
    clock: *const fn () i64,
    /// Shortcut to the root's id once minted; empty until then.
    root_id: ?[CERT_ID_HEX_LEN]u8,

    pub fn init(
        allocator: std.mem.Allocator,
        data_dir: []const u8,
        clock_fn: *const fn () i64,
    ) CertError!CertStore {
        const log_path = std.fs.path.join(allocator, &.{ data_dir, "identity-certs.log" }) catch return CertError.out_of_memory;
        std.fs.cwd().makePath(data_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                allocator.free(log_path);
                return CertError.store_error;
            },
        };
        var self = CertStore{
            .allocator = allocator,
            .log_path = log_path,
            .log_file = null,
            .by_id = std.StringHashMap(CertRecord).init(allocator),
            .clock = clock_fn,
            .root_id = null,
        };
        try self.openOrCreateLog();
        try self.replayLog();
        return self;
    }

    pub fn deinit(self: *CertStore) void {
        if (self.log_file) |f| f.close();
        var it = self.by_id.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            freeCertRecord(self.allocator, entry.value_ptr);
        }
        self.by_id.deinit();
        self.allocator.free(self.log_path);
    }

    // ── Issue ops ──

    /// Mint the operator's root cert.  Idempotent: if a root already
    /// exists, return the existing record without writing a new log
    /// entry.  Caller (the dispatcher handler) detects "already
    /// minted" by checking `root_id` after the call — the record
    /// returned is the live one regardless.
    pub fn issueRoot(
        self: *CertStore,
        pubkey: [bkds.KEY_LEN]u8,
        label: []const u8,
    ) CertError!CertRecord {
        if (self.root_id) |id_bytes| {
            // Idempotent — return the existing record verbatim.
            const id_slice: []const u8 = id_bytes[0..];
            const existing = self.by_id.get(id_slice) orelse return CertError.store_error;
            return existing;
        }

        const id_hex = certIdFromPubkey(pubkey);
        const owned_label = try cloneString(self.allocator, label);
        errdefer self.allocator.free(owned_label);

        const rec = CertRecord{
            .kind = .root,
            .id = id_hex,
            .parent_cert_id = [_]u8{0} ** CERT_ID_HEX_LEN,
            .has_parent = false,
            .context_tag = 0,
            .pubkey = pubkey,
            .capabilities = &.{},
            .label = owned_label,
            .issued_at = self.clock(),
        };

        try self.insertRecord(rec);
        try self.appendRoot(rec);
        self.root_id = id_hex;
        return rec;
    }

    /// Mint a child cert under `parent_cert_id`.  The handler is
    /// responsible for verifying the BKDS proof BEFORE calling this —
    /// the store assumes the proof has already passed and only
    /// enforces the cert-graph invariants (parent exists, parent not
    /// revoked, capabilities are well-formed).
    pub fn issueChild(
        self: *CertStore,
        parent_cert_id: []const u8,
        context_tag: u8,
        pubkey: [bkds.KEY_LEN]u8,
        capabilities: []const []const u8,
        label: []const u8,
    ) CertError!CertRecord {
        if (parent_cert_id.len != CERT_ID_HEX_LEN) return CertError.bad_format;
        // Parent must exist + not be revoked.
        const parent_rec = self.by_id.get(parent_cert_id) orelse return CertError.parent_not_found;
        _ = parent_rec; // we only need the membership check; capability
        // delegation happens at the dispatcher layer.

        // Validate capabilities — non-empty, dotted-namespace, ASCII
        // printable, ≤128 chars each.
        for (capabilities) |c| {
            if (!isValidCapability(c)) return CertError.capability_invalid;
        }

        const id_hex = certIdFromPubkey(pubkey);
        // If a cert with this id already lives, treat it as a
        // duplicate-issuance bug.
        if (self.by_id.contains(id_hex[0..])) return CertError.bad_format;

        const owned_caps = try cloneCapabilities(self.allocator, capabilities);
        errdefer freeCapabilities(self.allocator, owned_caps);
        const owned_label = try cloneString(self.allocator, label);
        errdefer self.allocator.free(owned_label);

        var parent_id_arr: [CERT_ID_HEX_LEN]u8 = undefined;
        @memcpy(&parent_id_arr, parent_cert_id);

        const rec = CertRecord{
            .kind = .child,
            .id = id_hex,
            .parent_cert_id = parent_id_arr,
            .has_parent = true,
            .context_tag = context_tag,
            .pubkey = pubkey,
            .capabilities = owned_caps,
            .label = owned_label,
            .issued_at = self.clock(),
        };

        try self.insertRecord(rec);
        try self.appendChild(rec);
        return rec;
    }

    // ── Read ops ──

    pub fn get(self: *CertStore, id: []const u8) CertError!CertRecord {
        if (id.len != CERT_ID_HEX_LEN) return CertError.cert_not_found;
        return self.by_id.get(id) orelse CertError.cert_not_found;
    }

    /// Snapshot of the live index.  Caller frees the slice; pointers
    /// inside are owned by the store (do NOT free record fields).
    pub fn list(self: *CertStore, allocator: std.mem.Allocator) CertError![]CertRecord {
        const out = allocator.alloc(CertRecord, self.by_id.count()) catch return CertError.out_of_memory;
        var i: usize = 0;
        var it = self.by_id.iterator();
        while (it.next()) |entry| {
            out[i] = entry.value_ptr.*;
            i += 1;
        }
        return out;
    }

    pub fn count(self: *const CertStore) usize {
        return self.by_id.count();
    }

    pub fn rootId(self: *const CertStore) ?[CERT_ID_HEX_LEN]u8 {
        return self.root_id;
    }

    /// Verify that `hat_id` is the correct hat-chain anchor for
    /// `cert_id` per the chain rule:
    ///
    ///   - root cert (`has_parent == false`) → anchor is its own id
    ///   - child cert (`has_parent == true`)  → anchor is `parent_cert_id`
    ///
    /// Returns `cert_not_found` if the id is unknown / revoked / wrong
    /// length, `hat_binding_mismatch` if the cert exists but its
    /// anchor differs from the declared `hat_id`, void on success.
    ///
    /// Brain primitive for cartridge handlers whose envelopes carry
    /// both `certId` and `hatId` (e.g. oddjobz `intent_cells.submit`,
    /// per `runtime/semantos-brain/src/resources/intent_cells_handler.zig`).
    /// Centralised here so cartridges call one brain entry point
    /// instead of inlining the lookup + chain check.  See
    /// `docs/prd/UNIFICATION-ROADMAP.md` §11.10 Gap A for the
    /// architectural argument and `docs/design/BRAIN-DISPATCHER-
    /// UNIFICATION.md` for the broader "one brain, many cartridges"
    /// shape this fits into.
    pub fn verifyCertHatBinding(
        self: *CertStore,
        cert_id: []const u8,
        hat_id: []const u8,
    ) CertError!void {
        const rec = try self.get(cert_id);
        const expected_hat: []const u8 = if (rec.has_parent)
            rec.parent_cert_id[0..]
        else
            rec.id[0..];
        if (!std.mem.eql(u8, expected_hat, hat_id)) {
            return CertError.hat_binding_mismatch;
        }
    }

    // ── Revoke ──

    /// Revoke a child cert.  Revoking the root is a separate code
    /// path (caller-checked) — this method only handles children and
    /// returns `cannot_revoke_root` if the operator passes the root id.
    pub fn revoke(self: *CertStore, id: []const u8) CertError!void {
        if (id.len != CERT_ID_HEX_LEN) return CertError.cert_not_found;
        if (self.root_id) |r| {
            if (std.mem.eql(u8, &r, id)) return CertError.cannot_revoke_root;
        }
        const entry = self.by_id.fetchRemove(id) orelse return CertError.cert_not_found;
        // entry owns the key + value; free both.
        defer self.allocator.free(entry.key);
        var rec = entry.value;
        defer freeCertRecord(self.allocator, &rec);
        try self.appendRevoked(rec.id);
    }

    /// D-O5m.followup-9 Phase A — register or unregister a push token
    /// against an existing cert.  The handler validates platform +
    /// token shape; the store enforces that the cert exists and
    /// persists the new fields.
    ///
    /// Semantics:
    ///   • platform = .apns + non-empty token → apns_token set,
    ///     fcm_token cleared, push_platform = .apns,
    ///     push_registered_at = `now_iso`.
    ///   • platform = .fcm + non-empty token → mirror image.
    ///   • platform = .none (token may be empty) → both tokens cleared,
    ///     push_platform = .none, push_registered_at = "" (unregister).
    ///
    /// The on-disk shape: a fresh `push_token` log line is appended so
    /// replay rebuilds the latest state from the log alone (mirrors
    /// the `root_caps` pattern).
    pub fn updatePushToken(
        self: *CertStore,
        cert_id: []const u8,
        platform: PushPlatform,
        token: []const u8,
        now_iso: []const u8,
    ) CertError!void {
        if (cert_id.len != CERT_ID_HEX_LEN) return CertError.cert_not_found;
        const entry = self.by_id.getEntry(cert_id) orelse return CertError.cert_not_found;
        const rec_ptr = entry.value_ptr;

        // Build the new owned strings BEFORE freeing the old ones so an
        // OOM mid-update leaves the record untouched.  Sovereign-push
        // D.3: when platform=unifiedpush, `token` carries the
        // distributor endpoint URL (not an opaque token).
        var new_apns: []u8 = &.{};
        var new_fcm: []u8 = &.{};
        var new_up: []u8 = &.{};
        var new_iso: []u8 = &.{};
        errdefer {
            if (new_apns.len > 0) self.allocator.free(new_apns);
            if (new_fcm.len > 0) self.allocator.free(new_fcm);
            if (new_up.len > 0) self.allocator.free(new_up);
            if (new_iso.len > 0) self.allocator.free(new_iso);
        }

        switch (platform) {
            .apns => {
                if (token.len > 0) {
                    new_apns = self.allocator.dupe(u8, token) catch return CertError.out_of_memory;
                }
                if (now_iso.len > 0) {
                    new_iso = self.allocator.dupe(u8, now_iso) catch return CertError.out_of_memory;
                }
            },
            .fcm => {
                if (token.len > 0) {
                    new_fcm = self.allocator.dupe(u8, token) catch return CertError.out_of_memory;
                }
                if (now_iso.len > 0) {
                    new_iso = self.allocator.dupe(u8, now_iso) catch return CertError.out_of_memory;
                }
            },
            .unifiedpush => {
                if (token.len > 0) {
                    new_up = self.allocator.dupe(u8, token) catch return CertError.out_of_memory;
                }
                if (now_iso.len > 0) {
                    new_iso = self.allocator.dupe(u8, now_iso) catch return CertError.out_of_memory;
                }
            },
            .none => {
                // Unregister — every token / endpoint stays empty;
                // clear timestamp so the operator can tell at-a-glance
                // the device is not subscribed.
            },
        }

        // Free the old owned strings now that we know the allocations
        // for the new ones succeeded.
        if (rec_ptr.apns_token.len > 0) self.allocator.free(rec_ptr.apns_token);
        if (rec_ptr.fcm_token.len > 0) self.allocator.free(rec_ptr.fcm_token);
        if (rec_ptr.up_endpoint.len > 0) self.allocator.free(rec_ptr.up_endpoint);
        if (rec_ptr.push_registered_at.len > 0) self.allocator.free(rec_ptr.push_registered_at);

        rec_ptr.apns_token = new_apns;
        rec_ptr.fcm_token = new_fcm;
        rec_ptr.up_endpoint = new_up;
        rec_ptr.push_platform = derivePushPlatform(
            rec_ptr.apns_token,
            rec_ptr.fcm_token,
            rec_ptr.up_endpoint,
            platform,
        );
        rec_ptr.push_registered_at = new_iso;

        // Persist via a fresh log line so a subsequent process can
        // replay → rebuild the same state.
        try self.appendPushTokenUpdate(rec_ptr.*);
    }

    /// D-O3 — Replace the operator-root cert's capability allowlist
    /// in place.  Used by `extensions.mintFirstBootCapabilities` at
    /// boot to merge declared extension caps into the root cert
    /// without going through the issue/revoke path.
    ///
    /// Idempotent: if `caps` matches the existing list (set semantics
    /// on names), this is effectively a no-op (still rewrites the
    /// log entry to keep the audit trail honest).
    ///
    /// The caller's `caps` slice is duped — caller retains ownership
    /// of the input strings.
    pub fn setRootCapabilities(
        self: *CertStore,
        caps: []const []u8,
    ) CertError!void {
        const root_id_arr = self.root_id orelse return CertError.cert_not_found;
        const root_id_slice: []const u8 = root_id_arr[0..];
        const entry = self.by_id.getEntry(root_id_slice) orelse return CertError.cert_not_found;
        const rec_ptr = entry.value_ptr;

        // Validate first — if any cap is malformed, fail without
        // touching the existing list.
        for (caps) |c| {
            if (!isValidCapability(c)) return CertError.capability_invalid;
        }

        // Build the new owned capability list.
        const owned = self.allocator.alloc([]u8, caps.len) catch return CertError.out_of_memory;
        var n: usize = 0;
        errdefer {
            var i: usize = 0;
            while (i < n) : (i += 1) self.allocator.free(owned[i]);
            self.allocator.free(owned);
        }
        while (n < caps.len) : (n += 1) {
            owned[n] = self.allocator.dupe(u8, caps[n]) catch return CertError.out_of_memory;
        }

        // Free the old list, swap in the new.
        freeCapabilities(self.allocator, rec_ptr.capabilities);
        rec_ptr.capabilities = owned;

        // Append a `root_caps` log line so the audit trail records the
        // mint pass.
        try self.appendRootCapsUpdate(rec_ptr.*);
    }

    // ── Internals ──

    fn insertRecord(self: *CertStore, rec: CertRecord) CertError!void {
        const owned_key = self.allocator.dupe(u8, &rec.id) catch return CertError.out_of_memory;
        errdefer self.allocator.free(owned_key);
        self.by_id.put(owned_key, rec) catch return CertError.out_of_memory;
    }

    fn openOrCreateLog(self: *CertStore) CertError!void {
        const cwd = std.fs.cwd();
        const f = cwd.openFile(self.log_path, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => cwd.createFile(self.log_path, .{ .read = true }) catch return CertError.store_error,
            else => return CertError.store_error,
        };
        f.seekFromEnd(0) catch return CertError.store_error;
        self.log_file = f;
    }

    fn replayLog(self: *CertStore) CertError!void {
        const f = self.log_file orelse return;
        f.seekTo(0) catch return CertError.store_error;
        const max = 1024 * 1024 * 16;
        const text = f.readToEndAlloc(self.allocator, max) catch return CertError.store_error;
        defer self.allocator.free(text);

        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            try self.applyLogLine(line);
        }
        f.seekFromEnd(0) catch return CertError.store_error;
    }

    fn applyLogLine(self: *CertStore, line: []const u8) CertError!void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, line, .{}) catch return; // skip malformed
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const obj = parsed.value.object;

        const kind_v = obj.get("kind") orelse return;
        if (kind_v != .string) return;
        const kind_str = kind_v.string;

        if (std.mem.eql(u8, kind_str, "root") or std.mem.eql(u8, kind_str, "child")) {
            try self.applyIssueLine(kind_str, obj);
            return;
        }
        if (std.mem.eql(u8, kind_str, "revoked")) {
            const id_v = obj.get("cert_id") orelse return;
            if (id_v != .string) return;
            if (id_v.string.len != CERT_ID_HEX_LEN) return;
            const entry = self.by_id.fetchRemove(id_v.string) orelse return;
            self.allocator.free(entry.key);
            var rec = entry.value;
            freeCertRecord(self.allocator, &rec);
            return;
        }
        if (std.mem.eql(u8, kind_str, "push_token")) {
            // D-O5m.followup-9 Phase A — replay an in-place push-token
            // update.  Mirrors `root_caps` shape: pull the current
            // record by id, swap the four push fields into place.
            const id_v = obj.get("cert_id") orelse return;
            if (id_v != .string or id_v.string.len != CERT_ID_HEX_LEN) return;
            const platform_v = obj.get("push_platform") orelse return;
            if (platform_v != .string) return;
            const platform = PushPlatform.fromWireName(platform_v.string) orelse return;
            const apns_token = if (obj.get("apns_token")) |v|
                (if (v == .string) v.string else return)
            else
                "";
            const fcm_token = if (obj.get("fcm_token")) |v|
                (if (v == .string) v.string else return)
            else
                "";
            // Sovereign-push D.3 — `up_endpoint` is the third
            // platform-specific bearer slot.  Older log lines won't
            // carry it; treat absent as empty.
            const up_endpoint = if (obj.get("up_endpoint")) |v|
                (if (v == .string) v.string else return)
            else
                "";
            const registered_at = if (obj.get("push_registered_at")) |v|
                (if (v == .string) v.string else return)
            else
                "";

            const target_entry = self.by_id.getEntry(id_v.string) orelse return;
            const rec_ptr = target_entry.value_ptr;

            const new_apns: []u8 = if (apns_token.len > 0)
                (self.allocator.dupe(u8, apns_token) catch return)
            else
                &.{};
            errdefer if (new_apns.len > 0) self.allocator.free(new_apns);
            const new_fcm: []u8 = if (fcm_token.len > 0)
                (self.allocator.dupe(u8, fcm_token) catch return)
            else
                &.{};
            errdefer if (new_fcm.len > 0) self.allocator.free(new_fcm);
            const new_up: []u8 = if (up_endpoint.len > 0)
                (self.allocator.dupe(u8, up_endpoint) catch return)
            else
                &.{};
            errdefer if (new_up.len > 0) self.allocator.free(new_up);
            const new_iso: []u8 = if (registered_at.len > 0)
                (self.allocator.dupe(u8, registered_at) catch return)
            else
                &.{};
            errdefer if (new_iso.len > 0) self.allocator.free(new_iso);

            if (rec_ptr.apns_token.len > 0) self.allocator.free(rec_ptr.apns_token);
            if (rec_ptr.fcm_token.len > 0) self.allocator.free(rec_ptr.fcm_token);
            if (rec_ptr.up_endpoint.len > 0) self.allocator.free(rec_ptr.up_endpoint);
            if (rec_ptr.push_registered_at.len > 0) self.allocator.free(rec_ptr.push_registered_at);
            rec_ptr.apns_token = new_apns;
            rec_ptr.fcm_token = new_fcm;
            rec_ptr.up_endpoint = new_up;
            rec_ptr.push_platform = platform;
            rec_ptr.push_registered_at = new_iso;
            return;
        }
        if (std.mem.eql(u8, kind_str, "root_caps")) {
            // D-O3 — replay an in-place root cert cap-list update.
            const id_v = obj.get("cert_id") orelse return;
            if (id_v != .string or id_v.string.len != CERT_ID_HEX_LEN) return;
            const caps_v = obj.get("capabilities") orelse return;
            if (caps_v != .array) return;
            const root_entry = self.by_id.getEntry(id_v.string) orelse return;
            const rec_ptr = root_entry.value_ptr;

            const owned = self.allocator.alloc([]u8, caps_v.array.items.len) catch return;
            var n: usize = 0;
            errdefer {
                var i: usize = 0;
                while (i < n) : (i += 1) self.allocator.free(owned[i]);
                if (caps_v.array.items.len > 0) self.allocator.free(owned);
            }
            while (n < caps_v.array.items.len) : (n += 1) {
                const item = caps_v.array.items[n];
                if (item != .string) return;
                if (!isValidCapability(item.string)) return;
                owned[n] = self.allocator.dupe(u8, item.string) catch return;
            }
            freeCapabilities(self.allocator, rec_ptr.capabilities);
            rec_ptr.capabilities = owned;
            return;
        }
    }

    fn applyIssueLine(self: *CertStore, kind_str: []const u8, obj: std.json.ObjectMap) CertError!void {
        const id_v = obj.get("cert_id") orelse return;
        if (id_v != .string or id_v.string.len != CERT_ID_HEX_LEN) return;
        const pub_v = obj.get("pubkey") orelse return;
        if (pub_v != .string or pub_v.string.len != bkds.KEY_LEN * 2) return;
        const label_v = obj.get("label") orelse return;
        if (label_v != .string) return;
        const issued_v = obj.get("issued_at") orelse return;
        if (issued_v != .integer) return;

        var pubkey: [bkds.KEY_LEN]u8 = undefined;
        bkds.hexDecode(pub_v.string, &pubkey) catch return;

        var rec = CertRecord{
            .kind = if (std.mem.eql(u8, kind_str, "root")) .root else .child,
            .id = undefined,
            .parent_cert_id = [_]u8{0} ** CERT_ID_HEX_LEN,
            .has_parent = false,
            .context_tag = 0,
            .pubkey = pubkey,
            .capabilities = &.{},
            .label = undefined,
            .issued_at = issued_v.integer,
        };
        @memcpy(&rec.id, id_v.string);

        if (rec.kind == .child) {
            const parent_v = obj.get("parent_cert_id") orelse return;
            if (parent_v != .string or parent_v.string.len != CERT_ID_HEX_LEN) return;
            @memcpy(&rec.parent_cert_id, parent_v.string);
            rec.has_parent = true;

            const ctx_v = obj.get("context_tag") orelse return;
            if (ctx_v != .integer) return;
            if (ctx_v.integer < 0 or ctx_v.integer > 255) return;
            rec.context_tag = @intCast(ctx_v.integer);

            const caps_v = obj.get("capabilities") orelse return;
            if (caps_v != .array) return;
            var cap_list: std.ArrayList([]u8) = .{};
            errdefer {
                for (cap_list.items) |c| self.allocator.free(c);
                cap_list.deinit(self.allocator);
            }
            for (caps_v.array.items) |c| {
                if (c != .string) return;
                const owned = self.allocator.dupe(u8, c.string) catch return CertError.out_of_memory;
                cap_list.append(self.allocator, owned) catch {
                    self.allocator.free(owned);
                    return CertError.out_of_memory;
                };
            }
            rec.capabilities = cap_list.toOwnedSlice(self.allocator) catch return CertError.out_of_memory;
        }

        rec.label = self.allocator.dupe(u8, label_v.string) catch return CertError.out_of_memory;

        // Insert into index.
        const owned_key = self.allocator.dupe(u8, &rec.id) catch {
            freeCertRecord(self.allocator, &rec);
            return CertError.out_of_memory;
        };
        self.by_id.put(owned_key, rec) catch {
            self.allocator.free(owned_key);
            freeCertRecord(self.allocator, &rec);
            return CertError.out_of_memory;
        };
        if (rec.kind == .root) self.root_id = rec.id;
    }

    fn appendRoot(self: *CertStore, rec: CertRecord) CertError!void {
        const f = self.log_file orelse return;
        var pub_hex: [bkds.KEY_LEN * 2]u8 = undefined;
        bkds.hexEncode(&rec.pubkey, &pub_hex);
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        buf.print(
            self.allocator,
            "{{\"ts\":{d},\"kind\":\"root\",\"cert_id\":\"{s}\",\"pubkey\":\"{s}\",\"label\":",
            .{ self.clock(), rec.id, pub_hex },
        ) catch return CertError.store_error;
        appendJsonString(self.allocator, &buf, rec.label) catch return CertError.store_error;
        buf.print(self.allocator, ",\"issued_at\":{d}}}\n", .{rec.issued_at}) catch return CertError.store_error;
        f.writeAll(buf.items) catch return CertError.store_error;
        f.sync() catch return CertError.store_error;
    }

    fn appendChild(self: *CertStore, rec: CertRecord) CertError!void {
        const f = self.log_file orelse return;
        var pub_hex: [bkds.KEY_LEN * 2]u8 = undefined;
        bkds.hexEncode(&rec.pubkey, &pub_hex);
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        buf.print(
            self.allocator,
            "{{\"ts\":{d},\"kind\":\"child\",\"cert_id\":\"{s}\",\"parent_cert_id\":\"{s}\",\"context_tag\":{d},\"pubkey\":\"{s}\",\"capabilities\":[",
            .{ self.clock(), rec.id, rec.parent_cert_id, rec.context_tag, pub_hex },
        ) catch return CertError.store_error;
        for (rec.capabilities, 0..) |c, i| {
            if (i != 0) buf.append(self.allocator, ',') catch return CertError.store_error;
            appendJsonString(self.allocator, &buf, c) catch return CertError.store_error;
        }
        buf.appendSlice(self.allocator, "],\"label\":") catch return CertError.store_error;
        appendJsonString(self.allocator, &buf, rec.label) catch return CertError.store_error;
        buf.print(self.allocator, ",\"issued_at\":{d}}}\n", .{rec.issued_at}) catch return CertError.store_error;
        f.writeAll(buf.items) catch return CertError.store_error;
        f.sync() catch return CertError.store_error;
    }

    fn appendRevoked(self: *CertStore, id: [CERT_ID_HEX_LEN]u8) CertError!void {
        const f = self.log_file orelse return;
        var buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(
            &buf,
            "{{\"ts\":{d},\"kind\":\"revoked\",\"cert_id\":\"{s}\"}}\n",
            .{ self.clock(), id },
        ) catch return CertError.store_error;
        f.writeAll(line) catch return CertError.store_error;
        f.sync() catch return CertError.store_error;
    }

    /// D-O5m.followup-9 Phase A — log a `push_token` event capturing
    /// the cert's current push registration state.  Both tokens go on
    /// the wire (one is empty unless the operator manually flipped via
    /// a separate channel).  Replay rebuilds the latest state by
    /// applying these in order.
    fn appendPushTokenUpdate(self: *CertStore, rec: CertRecord) CertError!void {
        const f = self.log_file orelse return;
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        buf.print(
            self.allocator,
            "{{\"ts\":{d},\"kind\":\"push_token\",\"cert_id\":\"{s}\",\"push_platform\":\"{s}\",\"apns_token\":",
            .{ self.clock(), rec.id, rec.push_platform.wireName() },
        ) catch return CertError.store_error;
        appendJsonString(self.allocator, &buf, rec.apns_token) catch return CertError.store_error;
        buf.appendSlice(self.allocator, ",\"fcm_token\":") catch return CertError.store_error;
        appendJsonString(self.allocator, &buf, rec.fcm_token) catch return CertError.store_error;
        buf.appendSlice(self.allocator, ",\"up_endpoint\":") catch return CertError.store_error;
        appendJsonString(self.allocator, &buf, rec.up_endpoint) catch return CertError.store_error;
        buf.appendSlice(self.allocator, ",\"push_registered_at\":") catch return CertError.store_error;
        appendJsonString(self.allocator, &buf, rec.push_registered_at) catch return CertError.store_error;
        buf.appendSlice(self.allocator, "}\n") catch return CertError.store_error;
        f.writeAll(buf.items) catch return CertError.store_error;
        f.sync() catch return CertError.store_error;
    }

    /// D-O3 — log a `root_caps` event capturing a fresh cap-allowlist
    /// for the root cert.  Replayed at startup to rebuild the in-
    /// memory allowlist from the log alone.
    fn appendRootCapsUpdate(self: *CertStore, rec: CertRecord) CertError!void {
        const f = self.log_file orelse return;
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        buf.print(
            self.allocator,
            "{{\"ts\":{d},\"kind\":\"root_caps\",\"cert_id\":\"{s}\",\"capabilities\":[",
            .{ self.clock(), rec.id },
        ) catch return CertError.store_error;
        for (rec.capabilities, 0..) |c, i| {
            if (i != 0) buf.append(self.allocator, ',') catch return CertError.store_error;
            appendJsonString(self.allocator, &buf, c) catch return CertError.store_error;
        }
        buf.appendSlice(self.allocator, "]}\n") catch return CertError.store_error;
        f.writeAll(buf.items) catch return CertError.store_error;
        f.sync() catch return CertError.store_error;
    }
};

// ─────────────────────────────────────────────────────────────────────
// Helpers — owned-memory ergonomics
// ─────────────────────────────────────────────────────────────────────

fn cloneString(allocator: std.mem.Allocator, s: []const u8) CertError![]u8 {
    return allocator.dupe(u8, s) catch CertError.out_of_memory;
}

fn cloneCapabilities(allocator: std.mem.Allocator, caps: []const []const u8) CertError![][]u8 {
    var out = allocator.alloc([]u8, caps.len) catch return CertError.out_of_memory;
    var n: usize = 0;
    errdefer {
        var i: usize = 0;
        while (i < n) : (i += 1) allocator.free(out[i]);
        allocator.free(out);
    }
    while (n < caps.len) : (n += 1) {
        out[n] = allocator.dupe(u8, caps[n]) catch return CertError.out_of_memory;
    }
    return out;
}

fn freeCapabilities(allocator: std.mem.Allocator, caps: [][]u8) void {
    for (caps) |c| allocator.free(c);
    if (caps.len > 0) allocator.free(caps);
}

fn freeCertRecord(allocator: std.mem.Allocator, rec: *CertRecord) void {
    freeCapabilities(allocator, rec.capabilities);
    allocator.free(rec.label);
    if (rec.apns_token.len > 0) allocator.free(rec.apns_token);
    if (rec.fcm_token.len > 0) allocator.free(rec.fcm_token);
    if (rec.up_endpoint.len > 0) allocator.free(rec.up_endpoint);
    if (rec.push_registered_at.len > 0) allocator.free(rec.push_registered_at);
    rec.capabilities = &.{};
    rec.label = &.{};
    rec.apns_token = &.{};
    rec.fcm_token = &.{};
    rec.up_endpoint = &.{};
    rec.push_registered_at = &.{};
}

/// Pick the `push_platform` discriminator from the (apns_token,
/// fcm_token, up_endpoint) triple.  When `requested` is `.none` the
/// result is `.none` regardless — that's the explicit unregister path.
/// Otherwise the non-empty bearer wins; if none is populated the
/// platform falls back to `.none`.
fn derivePushPlatform(
    apns_token: []const u8,
    fcm_token: []const u8,
    up_endpoint: []const u8,
    requested: PushPlatform,
) PushPlatform {
    if (requested == .none) return .none;
    if (apns_token.len > 0) return .apns;
    if (fcm_token.len > 0) return .fcm;
    if (up_endpoint.len > 0) return .unifiedpush;
    return .none;
}

/// Capability-string sanity check.  Tighter than the dispatcher's own
/// matcher (which just does string compares); we just want to refuse
/// payloads with control bytes / quotes that would break the log line.
fn isValidCapability(c: []const u8) bool {
    if (c.len == 0 or c.len > 128) return false;
    for (c) |b| {
        // Allow only printable ASCII minus quote / backslash / control.
        if (b < 0x21 or b == '\"' or b == '\\') return false;
        if (b > 0x7e) return false;
    }
    return true;
}

fn appendJsonString(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    s: []const u8,
) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

/// Derive the cert id (32 hex chars) from a 32-byte pubkey.  Matches
/// the TS adapter's `generateCertId(key)` which is `sha256(key)[0..16]`
/// hex-encoded — keeping the on-disk shape comparable across language
/// boundaries.
pub fn certIdFromPubkey(pubkey: [bkds.KEY_LEN]u8) [CERT_ID_HEX_LEN]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&pubkey, &hash, .{});
    var out: [CERT_ID_HEX_LEN]u8 = undefined;
    bkds.hexEncode(hash[0..16], &out);
    return out;
}

// ─────────────────────────────────────────────────────────────────────
// Tests — focus on the in-memory invariants.  The full handler →
// dispatcher → store conformance lives in
// tests/identity_certs_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

fn pinnedClock() i64 {
    return 1_700_000_000;
}

test "issueRoot: idempotent — second call returns existing record" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();

    const pubkey = try bkds.pubFromSeed("operator-root-1");
    const r1 = try store.issueRoot(pubkey, "operator-root");
    const r2 = try store.issueRoot(pubkey, "second-attempt");

    try std.testing.expectEqualSlices(u8, &r1.id, &r2.id);
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

test "issueChild: under valid root succeeds" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();

    const root_priv = bkds.privFromSeed("operator-root-2");
    const root_pub = try bkds.pubFromSeed("operator-root-2");
    const device_pub = try bkds.pubFromSeed("device-iphone-2");
    const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x10, "iPhone");

    const root = try store.issueRoot(root_pub, "operator");
    const caps = [_][]const u8{ "cap.oddjobz.write_customer", "cap.attach.photo" };
    const child = try store.issueChild(&root.id, 0x10, child_pub, &caps, "iPhone");
    try std.testing.expectEqual(CertKind.child, child.kind);
    try std.testing.expectEqual(@as(u8, 0x10), child.context_tag);
    try std.testing.expectEqual(@as(usize, 2), store.count());
}

test "issueChild: parent_not_found surfaces" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();

    const child_pub = try bkds.pubFromSeed("device-orphan");
    try std.testing.expectError(
        CertError.parent_not_found,
        store.issueChild("00000000000000000000000000000000", 0x10, child_pub, &.{}, "x"),
    );
}

test "revoke: cannot revoke root" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();

    const root_pub = try bkds.pubFromSeed("operator-root-norevoke");
    const root = try store.issueRoot(root_pub, "operator");
    try std.testing.expectError(CertError.cannot_revoke_root, store.revoke(&root.id));
}

test "revoke: child drops from index, get returns cert_not_found" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();

    const root_priv = bkds.privFromSeed("operator-root-revchild");
    const root_pub = try bkds.pubFromSeed("operator-root-revchild");
    const device_pub = try bkds.pubFromSeed("device-revchild");
    const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x10, "phone");

    const root = try store.issueRoot(root_pub, "op");
    const child = try store.issueChild(&root.id, 0x10, child_pub, &.{}, "phone");
    try store.revoke(&child.id);
    try std.testing.expectError(CertError.cert_not_found, store.get(&child.id));
    try std.testing.expectEqual(@as(usize, 1), store.count()); // just the root
}

test "log replay: rebuilds index" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    const root_priv = bkds.privFromSeed("operator-root-replay");
    const root_pub = try bkds.pubFromSeed("operator-root-replay");
    const device_pub = try bkds.pubFromSeed("device-replay");
    const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x10, "phone");
    {
        var store = try CertStore.init(allocator, real, pinnedClock);
        defer store.deinit();
        const root = try store.issueRoot(root_pub, "operator");
        _ = try store.issueChild(&root.id, 0x10, child_pub, &.{"cap.x.y"}, "phone");
    }

    // Reopen — replay should reconstruct exactly the same shape.
    var store2 = try CertStore.init(allocator, real, pinnedClock);
    defer store2.deinit();
    try std.testing.expectEqual(@as(usize, 2), store2.count());
    try std.testing.expect(store2.rootId() != null);
    const child_id = certIdFromPubkey(child_pub);
    const child = try store2.get(&child_id);
    try std.testing.expectEqual(CertKind.child, child.kind);
    try std.testing.expectEqual(@as(u8, 0x10), child.context_tag);
    try std.testing.expectEqual(@as(usize, 1), child.capabilities.len);
    try std.testing.expectEqualStrings("cap.x.y", child.capabilities[0]);
}

test "verifyCertHatBinding: root cert — hat_id equals own cert_id succeeds" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();

    const root_pub = try bkds.pubFromSeed("operator-root-vhb-root");
    const root = try store.issueRoot(root_pub, "operator");

    // Root acts as its own hat anchor.
    try store.verifyCertHatBinding(&root.id, &root.id);
}

test "verifyCertHatBinding: child cert — hat_id equals parent_cert_id succeeds" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();

    const root_priv = bkds.privFromSeed("operator-root-vhb-child");
    const root_pub = try bkds.pubFromSeed("operator-root-vhb-child");
    const device_pub = try bkds.pubFromSeed("device-vhb-child");
    const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x10, "phone");

    const root = try store.issueRoot(root_pub, "operator");
    const child = try store.issueChild(&root.id, 0x10, child_pub, &.{}, "phone");

    // Child is anchored under the operator root — hat_id must be the root's id.
    try store.verifyCertHatBinding(&child.id, &root.id);
}

test "verifyCertHatBinding: unknown cert → cert_not_found" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();

    try std.testing.expectError(
        CertError.cert_not_found,
        store.verifyCertHatBinding(
            "00000000000000000000000000000000",
            "11111111111111111111111111111111",
        ),
    );
}

test "verifyCertHatBinding: child with wrong hat_id → hat_binding_mismatch" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();

    const root_priv = bkds.privFromSeed("operator-root-vhb-bad");
    const root_pub = try bkds.pubFromSeed("operator-root-vhb-bad");
    const device_pub = try bkds.pubFromSeed("device-vhb-bad");
    const child_pub = try bkds.deriveChildPubkey(root_priv, device_pub, 0x10, "phone");

    const root = try store.issueRoot(root_pub, "operator");
    const child = try store.issueChild(&root.id, 0x10, child_pub, &.{}, "phone");

    // Wrong hat anchor — would-be "context-tag swap across hats".
    try std.testing.expectError(
        CertError.hat_binding_mismatch,
        store.verifyCertHatBinding(&child.id, "ffffffffffffffffffffffffffffffff"),
    );
}

test "verifyCertHatBinding: root with wrong hat_id → hat_binding_mismatch" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try CertStore.init(allocator, real, pinnedClock);
    defer store.deinit();

    const root_pub = try bkds.pubFromSeed("operator-root-vhb-rootbad");
    const root = try store.issueRoot(root_pub, "operator");

    try std.testing.expectError(
        CertError.hat_binding_mismatch,
        store.verifyCertHatBinding(&root.id, "ffffffffffffffffffffffffffffffff"),
    );
}

```
