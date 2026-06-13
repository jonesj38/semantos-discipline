---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/push_dispatcher.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.261760+00:00
---

# runtime/semantos-brain/src/push_dispatcher.zig

```zig
// D-O5m.followup-9 Phase B / Sovereign-push D.1+D.3 — top-level Push
// dispatcher.  Routes a wake-only PushNotification to APNs, FCM, or
// UnifiedPush based on the cert's push_platform.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §D-O5m.followup-9
// Phase B (push_dispatcher requirements);
// docs/operator-runbooks/push-architecture.md (sovereign-push D.1
// wake-only flow).
//
// ─── Sovereign push (D.1) ───────────────────────────────────────────
//
// Push notifications are WAKE-ONLY.  The dispatcher carries an
// opaque envelope (event_id + ts in `payload_json`) and NOTHING
// operator-readable.  Apple/Google see nothing more than:
//
//   {"aps":{"content-available":1},"event_id":"...","ts":...}
//
// or the FCM data-only equivalent.  The device, on wake, opens its
// WSS to the brain and calls `helm.fetch_since` to pull the actual
// event content; the local notification banner is composed
// device-side from data the sovereign brain supplied directly.
//
// This preserves the operator's economic execution path: Google/
// Apple are still in the wake-up loop (they have to be, OS-level)
// but they never see operator content.  See the runbook for the
// architectural rationale.
//
// Push is best-effort.  Every send path here:
//   • Looks up the cert by id.
//   • Reads cert.push_platform.
//   • Routes to apns_dispatcher or fcm_dispatcher (or skips with an
//     audit-log message when the relevant dispatcher isn't
//     configured).
//   • Returns ok regardless — the caller (helm_event_broker) treats
//     failures as best-effort and continues publishing the event.
//
// The broker calls `sendToCerts` after every publish where
// `event.requires_operator_attention == true`; helm_event_broker
// determines the cert set via `findCertsForTopic`, which is a
// helm_event_broker concern (this module just fans out).

const std = @import("std");
const apns_mod = @import("apns_dispatcher");
const fcm_mod = @import("fcm_dispatcher");
const unifiedpush_mod = @import("unifiedpush_dispatcher");
const identity_certs = @import("identity_certs");
const audit_log_mod = @import("audit_log");

/// Wake-only notification.  Carries ONLY an opaque JSON envelope —
/// no title, no body, no operator content.  The device decodes
/// `payload_json` after waking and fetches the real event over WSS
/// via `helm.fetch_since`.
///
/// Shape (v0.1 — sovereign push D.1):
///   payload_json = `{"event_id":"<id>","ts":<unix-seconds>,"kind":"<token>"}`
///
/// `kind` is a stable token (e.g. `"helm.event"`); the device uses
/// it to decide whether to fetch + render a notification.  No
/// operator-content tokens (lead summaries, customer names, etc.)
/// flow through this struct — that's the architectural property
/// this PR enforces.
pub const PushNotification = struct {
    /// Opaque, already-encoded JSON object literal.  REQUIRED — the
    /// device fetches event content via WSS keyed by the `event_id`
    /// inside this envelope.
    payload_json: []const u8,
};

pub const DispatchError = error{
    cert_not_found,
    out_of_memory,
};

pub const PushDispatcher = struct {
    allocator: std.mem.Allocator,
    apns: ?*apns_mod.ApnsDispatcher,
    fcm: ?*fcm_mod.FcmDispatcher,
    /// Sovereign-push D.3 — UnifiedPush dispatcher.  Always
    /// constructible (no signing material to load), so production
    /// boot wires this on whenever push-config.json is present at
    /// all.  Skipped only when the operator has explicitly disabled
    /// it.
    unifiedpush: ?*unifiedpush_mod.UnifiedPushDispatcher,
    cert_store: *identity_certs.CertStore,
    audit_log: *audit_log_mod.AuditLog,

    pub fn init(
        allocator: std.mem.Allocator,
        apns: ?*apns_mod.ApnsDispatcher,
        fcm: ?*fcm_mod.FcmDispatcher,
        unifiedpush: ?*unifiedpush_mod.UnifiedPushDispatcher,
        cert_store: *identity_certs.CertStore,
        audit_log: *audit_log_mod.AuditLog,
    ) PushDispatcher {
        return .{
            .allocator = allocator,
            .apns = apns,
            .fcm = fcm,
            .unifiedpush = unifiedpush,
            .cert_store = cert_store,
            .audit_log = audit_log,
        };
    }

    /// Send to a single cert.  Best-effort: logs audit + returns ok
    /// when the cert's push_platform is none, when the relevant
    /// dispatcher isn't configured, or when the underlying transport
    /// errors.  The only hard error is "cert not in store" — the
    /// caller has already filtered by id, so that's a programming
    /// bug and surfaces typed.
    pub fn sendToCert(
        self: *PushDispatcher,
        cert_id: []const u8,
        notification: PushNotification,
    ) DispatchError!void {
        const rec = self.cert_store.get(cert_id) catch {
            return DispatchError.cert_not_found;
        };
        switch (rec.push_platform) {
            .none => {
                self.recordAudit(.ok, "push skipped: cert.push_platform=none");
                return;
            },
            .apns => {
                if (self.apns) |a| {
                    a.send(cert_id, .{
                        .payload_json = notification.payload_json,
                    }) catch |err| {
                        self.recordAudit(.err, switch (err) {
                            error.transport_failed => "apns transport failed",
                            error.apns_rejected => "apns rejected",
                            error.jwt_build_failed => "apns jwt build failed",
                            error.no_apns_token => "apns no token",
                            error.cert_not_found => "apns cert not found",
                            error.p8_key_read_failed => "apns p8 read failed",
                            error.p8_key_parse_failed => "apns p8 parse failed",
                            error.out_of_memory => "apns oom",
                        });
                    };
                    return;
                }
                self.recordAudit(.ok, "apns not configured, skipping");
                return;
            },
            .fcm => {
                if (self.fcm) |f| {
                    f.send(cert_id, .{
                        .payload_json = notification.payload_json,
                    }) catch |err| {
                        self.recordAudit(.err, switch (err) {
                            error.transport_failed => "fcm transport failed",
                            error.fcm_rejected => "fcm rejected",
                            error.oauth_token_failed => "fcm oauth failed",
                            error.no_fcm_token => "fcm no token",
                            error.cert_not_found => "fcm cert not found",
                            error.service_account_read_failed => "fcm sa read failed",
                            error.service_account_parse_failed => "fcm sa parse failed",
                            error.rsa_sign_failed => "fcm rsa sign failed",
                            error.out_of_memory => "fcm oom",
                        });
                    };
                    return;
                }
                self.recordAudit(.ok, "fcm not configured, skipping");
                return;
            },
            .unifiedpush => {
                if (self.unifiedpush) |u| {
                    u.send(cert_id, .{
                        .payload_json = notification.payload_json,
                    }) catch |err| {
                        self.recordAudit(.err, switch (err) {
                            error.transport_failed => "unifiedpush transport failed",
                            error.unifiedpush_rejected => "unifiedpush rejected",
                            error.no_up_endpoint => "unifiedpush no endpoint",
                            error.cert_not_found => "unifiedpush cert not found",
                            error.out_of_memory => "unifiedpush oom",
                        });
                    };
                    return;
                }
                self.recordAudit(.ok, "unifiedpush not configured, skipping");
                return;
            },
        }
    }

    /// Fan out to a slice of cert ids.  Errors per-cert are absorbed
    /// + logged; the function only returns when all certs are
    /// processed.
    pub fn sendToCerts(
        self: *PushDispatcher,
        cert_ids: []const []const u8,
        notification: PushNotification,
    ) void {
        for (cert_ids) |id| {
            self.sendToCert(id, notification) catch |err| {
                self.recordAudit(.err, switch (err) {
                    error.cert_not_found => "push: cert not found",
                    error.out_of_memory => "push: oom",
                });
            };
        }
    }

    fn recordAudit(
        self: *PushDispatcher,
        result: audit_log_mod.Result,
        detail: []const u8,
    ) void {
        self.audit_log.record(self.allocator, .{
            .module = "push-dispatcher",
            .op = "push_send",
            .result = result,
            .detail = detail,
        }) catch {};
    }
};

// ─── Tests ───────────────────────────────────────────────────────────
//
// Inline tests cover the routing-only paths.  The full APNs/FCM
// integration paths (with real cert + http-mock) live in
// tests/push_dispatcher_test.zig.

test "PushDispatcher init holds configured dispatchers" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    var store = try identity_certs.CertStore.init(allocator, real, struct {
        fn c() i64 {
            return 1_700_000_000;
        }
    }.c);
    defer store.deinit();
    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    const audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
    defer allocator.free(audit_path);
    audit.open(audit_path) catch {};

    const pd = PushDispatcher.init(allocator, null, null, null, &store, &audit);
    try std.testing.expect(pd.apns == null);
    try std.testing.expect(pd.fcm == null);
    try std.testing.expect(pd.unifiedpush == null);
}

test "PushNotification struct is wake-only — only payload_json field" {
    // The struct must not carry operator-readable text fields.
    // This test asserts the shape via @typeInfo so a regression that
    // reintroduces title/body fails to compile this test.
    const fields = @typeInfo(PushNotification).@"struct".fields;
    try std.testing.expectEqual(@as(usize, 1), fields.len);
    try std.testing.expectEqualStrings("payload_json", fields[0].name);
}

```
