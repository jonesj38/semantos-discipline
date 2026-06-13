---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/unifiedpush_dispatcher.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.240843+00:00
---

# runtime/semantos-brain/src/unifiedpush_dispatcher.zig

```zig
// Sovereign-push D.3 — UnifiedPush HTTP dispatcher.
//
// Reference: docs/operator-runbooks/push-architecture.md (Phase D.3
//            section);
//            UnifiedPush server spec: https://unifiedpush.org/spec/server/
//
// ─── What UnifiedPush is, and why we ship a dispatcher for it ───────
//
// UnifiedPush (UP) is a libre push protocol.  The brain POSTs the
// wake JSON envelope DIRECTLY to a distributor URL the operator's
// device chose at registration time.  No Google Firebase, no Apple
// APNs, no provider wrapper, no token rotation, no auth — the URL
// itself is the capability (the distributor minted it for this
// device's instance, not for the brain).
//
// This is the third backend behind PushPlatform.unifiedpush.
// Operator picks a distributor on their device:
//   - ntfy (self-hosted or ntfy.sh)
//   - Conversations (XMPP-backed)
//   - NextPush (Nextcloud app)
//   - any other distributor implementing the UP spec
//
// The brain never knows or cares which one — just POSTs to the URL.
//
// ─── Wire shape ─────────────────────────────────────────────────────
//
//   POST <cert.up_endpoint>
//     Content-Type: application/json
//
//     <payload_json>
//
// Where <payload_json> is the raw wake envelope from
// PushNotification.payload_json — the same opaque
// `{"event_id":"...","ts":...,"kind":"helm.event"}` shape that goes to
// FCM's `data` blob.  No provider wrapping — the device's UP plugin
// hands the raw bytes to the app callback verbatim.
//
// ─── Failure model ──────────────────────────────────────────────────
//
// Push is best-effort.  On non-2xx response or transport error we log
// to the audit channel and return.  The PushDispatcher absorbs the
// error and continues to other certs.  Unlike APNs/FCM there's no
// token-expiry signal to interpret — UP distributors are expected to
// either succeed (2xx) or 410-Gone the endpoint when the device has
// unregistered upstream.  On 410 we clear the cert's UP endpoint so
// the next registration cycle can re-register.

const std = @import("std");
const transport_mod = @import("push_http_transport");
const identity_certs = @import("identity_certs");
const audit_log_mod = @import("audit_log");

// ─── Public types ────────────────────────────────────────────────────

/// One wake-only push notification.  Mirrors apns_dispatcher /
/// fcm_dispatcher exactly so the upper-level PushDispatcher can pass
/// the same payload to either transport.
pub const PushNotification = struct {
    /// Already-encoded JSON object literal — the wake envelope.  The
    /// dispatcher posts this byte-for-byte as the request body.
    payload_json: []const u8,
};

pub const DispatchError = error{
    transport_failed,
    unifiedpush_rejected,
    no_up_endpoint,
    cert_not_found,
    out_of_memory,
};

// ─── Dispatcher ──────────────────────────────────────────────────────

pub const UnifiedPushDispatcher = struct {
    allocator: std.mem.Allocator,
    cert_store: *identity_certs.CertStore,
    audit_log: *audit_log_mod.AuditLog,
    http_transport: transport_mod.HttpTransport,
    now_iso_fn: *const fn (allocator: std.mem.Allocator) anyerror![]u8,

    pub fn init(
        allocator: std.mem.Allocator,
        cert_store: *identity_certs.CertStore,
        audit_log: *audit_log_mod.AuditLog,
        http_transport: transport_mod.HttpTransport,
    ) UnifiedPushDispatcher {
        return .{
            .allocator = allocator,
            .cert_store = cert_store,
            .audit_log = audit_log,
            .http_transport = http_transport,
            .now_iso_fn = defaultNowIso,
        };
    }

    pub fn deinit(self: *UnifiedPushDispatcher) void {
        // No persistent state — everything is per-call.
        _ = self;
    }

    pub fn setNowIsoFn(
        self: *UnifiedPushDispatcher,
        f: *const fn (allocator: std.mem.Allocator) anyerror![]u8,
    ) void {
        self.now_iso_fn = f;
    }

    pub fn send(
        self: *UnifiedPushDispatcher,
        cert_id: []const u8,
        notification: PushNotification,
    ) DispatchError!void {
        const rec = self.cert_store.get(cert_id) catch return DispatchError.cert_not_found;
        if (rec.push_platform != .unifiedpush or rec.up_endpoint.len == 0) {
            return DispatchError.no_up_endpoint;
        }

        const headers = [_]transport_mod.Header{
            .{ .name = "content-type", .value = "application/json" },
        };

        var attempt: usize = 0;
        while (attempt < 3) : (attempt += 1) {
            var resp = self.http_transport.post(self.allocator, .{
                .url = rec.up_endpoint,
                .headers = &headers,
                .body = notification.payload_json,
            }) catch |err| switch (err) {
                error.transport_error => continue,
                error.out_of_memory => return DispatchError.out_of_memory,
            };
            defer resp.deinit();

            if (resp.status >= 200 and resp.status < 300) {
                self.recordAudit(.ok, "unifiedpush send ok");
                return;
            }
            // 410 Gone — distributor reports the endpoint is dead.
            // Clear the cert's UP endpoint so the device's next
            // foreground re-registration re-mints a fresh one.
            if (resp.status == 410) {
                self.clearCertEndpoint(cert_id) catch {};
                self.recordAudit(.ok, "unifiedpush endpoint gone; cleared");
                return;
            }
            if (resp.status >= 500) continue;
            self.recordAudit(.err, "unifiedpush rejected (4xx)");
            return DispatchError.unifiedpush_rejected;
        }
        self.recordAudit(.err, "unifiedpush transport budget exhausted");
        return DispatchError.transport_failed;
    }

    // ── Internals ──

    fn clearCertEndpoint(self: *UnifiedPushDispatcher, cert_id: []const u8) !void {
        const now_iso = try self.now_iso_fn(self.allocator);
        defer self.allocator.free(now_iso);
        try self.cert_store.updatePushToken(cert_id, .none, "", now_iso);
    }

    fn recordAudit(
        self: *UnifiedPushDispatcher,
        result: audit_log_mod.Result,
        detail: []const u8,
    ) void {
        self.audit_log.record(self.allocator, .{
            .module = "unifiedpush-dispatcher",
            .op = "unifiedpush_send",
            .result = result,
            .detail = detail,
        }) catch {};
    }
};

// ─── Default helpers ─────────────────────────────────────────────────

fn defaultNowIso(allocator: std.mem.Allocator) anyerror![]u8 {
    // Match the apns/fcm dispatcher's defaultNowIso shape: emit a
    // YYYY-MM-DDTHH:MM:SSZ string.  std.time.timestamp() gives us
    // unix seconds; convert to a calendar date by hand (no full
    // chrono lib needed for the audit log line).
    const ts = std.time.timestamp();
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(ts) };
    const day_seconds = epoch_seconds.getDaySeconds();
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        },
    );
}

// ─── Tests ───────────────────────────────────────────────────────────
//
// Inline tests cover the routing-only paths.  The full
// dispatcher↔store↔transport conformance lives in
// tests/unifiedpush_dispatcher_test.zig.

test "UnifiedPushDispatcher init has no persistent state" {
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

    var mock = transport_mod.MockTransport.init(allocator);
    defer mock.deinit();
    var d = UnifiedPushDispatcher.init(allocator, &store, &audit, mock.transport());
    d.deinit();
}

test "PushNotification struct is wake-only — only payload_json field" {
    const fields = @typeInfo(PushNotification).@"struct".fields;
    try std.testing.expectEqual(@as(usize, 1), fields.len);
    try std.testing.expectEqualStrings("payload_json", fields[0].name);
}

```
