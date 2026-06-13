---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/payment_ledger_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.189214+00:00
---

# runtime/semantos-brain/tests/payment_ledger_conformance.zig

```zig
// Phase WSITE4 — PaymentLedger conformance tests.

const std = @import("std");
const payment_ledger = @import("payment_ledger");

fn tempPath(name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return std.fs.path.join(allocator, &.{ real, name });
}

var pinned_clock: i64 = 1_700_000_000;
fn fixedClock() i64 {
    return pinned_clock;
}

const SID = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
const PAYER = "020202020202020202020202020202020202020202020202020202020202020202";
const TXID = "abababababababababababababababababababababababababababababababab";

test "WSITE4 ledger: record + readAll round-trip" {
    const path = try tempPath("ledger-rt.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    ledger.setClockFn(fixedClock);
    try ledger.record(SID, "/premium/article/42", PAYER, TXID, 5000);
    ledger.deinit();

    var ledger2 = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger2.deinit();
    const records = try ledger2.readAll(std.testing.allocator);
    defer payment_ledger.freeRecords(std.testing.allocator, records);

    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqual(@as(i64, 1_700_000_000), records[0].ts);
    try std.testing.expectEqualStrings("/premium/article/42", records[0].route);
    try std.testing.expectEqual(@as(u64, 5000), records[0].satoshis);
    try std.testing.expectEqualStrings(SID, &records[0].session_id);
    try std.testing.expectEqualStrings(PAYER, &records[0].payer_hex);
    try std.testing.expectEqualStrings(TXID, &records[0].txid_hex);
    try std.testing.expect(!records[0].verified);
}

test "WSITE4 ledger: persistence across reopens" {
    const path = try tempPath("ledger-persist.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    {
        var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
        defer ledger.deinit();
        ledger.setClockFn(fixedClock);
        try ledger.record(SID, "/a", PAYER, TXID, 100);
        try ledger.record(SID, "/b", PAYER, TXID, 200);
    }
    {
        var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
        defer ledger.deinit();
        try ledger.record(SID, "/c", PAYER, TXID, 300);
    }
    var ledger3 = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger3.deinit();
    const records = try ledger3.readAll(std.testing.allocator);
    defer payment_ledger.freeRecords(std.testing.allocator, records);
    try std.testing.expectEqual(@as(usize, 3), records.len);
    var total: u64 = 0;
    for (records) |r| total += r.satoshis;
    try std.testing.expectEqual(@as(u64, 600), total);
}

test "WSITE4 ledger: record rejects bad-length hex inputs" {
    const path = try tempPath("ledger-badhex.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger.deinit();
    try std.testing.expectError(error.write_failed, ledger.record("short", "/x", PAYER, TXID, 1));
    try std.testing.expectError(error.write_failed, ledger.record(SID, "/x", "short", TXID, 1));
    try std.testing.expectError(error.write_failed, ledger.record(SID, "/x", PAYER, "short", 1));
}

test "WSITE4 ledger: aggregateByRoute sums + sorts descending" {
    const path = try tempPath("ledger-agg.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    ledger.setClockFn(fixedClock);
    try ledger.record(SID, "/a", PAYER, TXID, 100);
    try ledger.record(SID, "/a", PAYER, TXID, 200);
    try ledger.record(SID, "/b", PAYER, TXID, 1000);
    try ledger.record(SID, "/c", PAYER, TXID, 50);
    ledger.deinit();

    var ledger2 = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger2.deinit();
    const records = try ledger2.readAll(std.testing.allocator);
    defer payment_ledger.freeRecords(std.testing.allocator, records);

    const agg = try payment_ledger.aggregateByRoute(std.testing.allocator, records, 0);
    defer payment_ledger.freeAggregation(std.testing.allocator, agg);

    try std.testing.expectEqual(@as(usize, 3), agg.len);
    // Sorted by total_sats descending — /b > /a > /c
    try std.testing.expectEqualStrings("/b", agg[0].route);
    try std.testing.expectEqual(@as(u64, 1000), agg[0].total_sats);
    try std.testing.expectEqualStrings("/a", agg[1].route);
    try std.testing.expectEqual(@as(u32, 2), agg[1].count);
    try std.testing.expectEqual(@as(u64, 300), agg[1].total_sats);
    try std.testing.expectEqualStrings("/c", agg[2].route);
    try std.testing.expectEqual(@as(u64, 50), agg[2].total_sats);
}

test "WSITE4 ledger: since_ts filters older records" {
    const path = try tempPath("ledger-since.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    pinned_clock = 1_000;
    ledger.setClockFn(fixedClock);
    try ledger.record(SID, "/a", PAYER, TXID, 100);
    pinned_clock = 2_000;
    try ledger.record(SID, "/b", PAYER, TXID, 200);
    pinned_clock = 3_000;
    try ledger.record(SID, "/c", PAYER, TXID, 300);
    ledger.deinit();

    var ledger2 = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger2.deinit();
    const records = try ledger2.readAll(std.testing.allocator);
    defer payment_ledger.freeRecords(std.testing.allocator, records);

    const agg = try payment_ledger.aggregateByRoute(std.testing.allocator, records, 1_500);
    defer payment_ledger.freeAggregation(std.testing.allocator, agg);

    try std.testing.expectEqual(@as(usize, 2), agg.len);
    var total: u64 = 0;
    for (agg) |a| total += a.total_sats;
    try std.testing.expectEqual(@as(u64, 500), total);
    pinned_clock = 1_700_000_000;
}

test "WSITE4 ledger: empty ledger yields empty agg" {
    const path = try tempPath("ledger-empty.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger.deinit();
    const records = try ledger.readAll(std.testing.allocator);
    defer payment_ledger.freeRecords(std.testing.allocator, records);
    try std.testing.expectEqual(@as(usize, 0), records.len);
}

// ─────────────────────────────────────────────────────────────────────
// WSITE4.5 — verifications.log + read-side join
// ─────────────────────────────────────────────────────────────────────

const TXID2 = "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd";

test "WSITE4.5 ledger: recordVerification rejects bad-length txid" {
    const path = try tempPath("ledger-verify-badhex.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.fs.cwd().deleteFile(path[0..path.len]) catch {};
        const v_path = std.fmt.allocPrint(std.testing.allocator, "{s}.verifications", .{path}) catch unreachable;
        defer std.testing.allocator.free(v_path);
        std.fs.cwd().deleteFile(v_path) catch {};
        std.testing.allocator.free(path);
    }
    var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger.deinit();
    try std.testing.expectError(error.write_failed, ledger.recordVerification("short", true, 100));
}

test "WSITE4.5 ledger: readAll joins verifications.log → flips verified" {
    const path = try tempPath("ledger-verify-join.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        const v_path = std.fmt.allocPrint(std.testing.allocator, "{s}.verifications", .{path}) catch unreachable;
        defer std.testing.allocator.free(v_path);
        std.fs.cwd().deleteFile(v_path) catch {};
        std.testing.allocator.free(path);
    }

    var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    ledger.setClockFn(fixedClock);
    try ledger.record(SID, "/a", PAYER, TXID, 100);
    try ledger.record(SID, "/b", PAYER, TXID2, 200);
    // Verify only the first txid.
    try ledger.recordVerification(TXID, true, 100);
    ledger.deinit();

    var ledger2 = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger2.deinit();
    const records = try ledger2.readAll(std.testing.allocator);
    defer payment_ledger.freeRecords(std.testing.allocator, records);

    try std.testing.expectEqual(@as(usize, 2), records.len);
    // Records preserve the original order; we look them up by txid.
    var found_a = false;
    var found_b = false;
    for (records) |r| {
        if (std.mem.eql(u8, &r.txid_hex, TXID)) {
            try std.testing.expect(r.verified);
            found_a = true;
        } else if (std.mem.eql(u8, &r.txid_hex, TXID2)) {
            try std.testing.expect(!r.verified);
            found_b = true;
        }
    }
    try std.testing.expect(found_a);
    try std.testing.expect(found_b);
}

test "WSITE4.5 ledger: last-write-wins on verifications" {
    const path = try tempPath("ledger-verify-lww.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        const v_path = std.fmt.allocPrint(std.testing.allocator, "{s}.verifications", .{path}) catch unreachable;
        defer std.testing.allocator.free(v_path);
        std.fs.cwd().deleteFile(v_path) catch {};
        std.testing.allocator.free(path);
    }
    var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    ledger.setClockFn(fixedClock);
    try ledger.record(SID, "/a", PAYER, TXID, 100);
    // First sweep: header store hadn't caught up → unverified.
    try ledger.recordVerification(TXID, false, 0);
    // Later sweep: header store now sees the height → verified.
    try ledger.recordVerification(TXID, true, 100);
    ledger.deinit();

    var ledger2 = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger2.deinit();
    const records = try ledger2.readAll(std.testing.allocator);
    defer payment_ledger.freeRecords(std.testing.allocator, records);

    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expect(records[0].verified);
}

// ─────────────────────────────────────────────────────────────────────
// WSITE5 — refund intent
// ─────────────────────────────────────────────────────────────────────

fn cleanupAuxLogs(path: []const u8) void {
    inline for (&.{ ".verifications", ".refunds" }) |suffix| {
        const p = std.fmt.allocPrint(std.testing.allocator, "{s}{s}", .{ path, suffix }) catch return;
        defer std.testing.allocator.free(p);
        std.fs.cwd().deleteFile(p) catch {};
    }
}

test "WSITE5 ledger: recordRefund + readAllJoined surfaces refunded flag" {
    const path = try tempPath("ledger-refund.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        cleanupAuxLogs(path);
        std.testing.allocator.free(path);
    }
    var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    ledger.setClockFn(fixedClock);
    try ledger.record(SID, "/premium", PAYER, TXID, 5000);
    try ledger.recordRefund(TXID, "service failed", 5000);
    ledger.deinit();

    var ledger2 = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger2.deinit();
    const records = try ledger2.readAllJoined(std.testing.allocator);
    defer payment_ledger.freeRecords(std.testing.allocator, records);

    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expect(records[0].refunded);
    try std.testing.expectEqualStrings("service failed", records[0].refund_reason);
}

test "WSITE5 ledger: readAll (legacy) does not load refund metadata" {
    const path = try tempPath("ledger-refund-readall.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        cleanupAuxLogs(path);
        std.testing.allocator.free(path);
    }
    var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    ledger.setClockFn(fixedClock);
    try ledger.record(SID, "/premium", PAYER, TXID, 5000);
    try ledger.recordRefund(TXID, "operator-initiated refund", 5000);
    ledger.deinit();

    var ledger2 = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger2.deinit();
    const records = try ledger2.readAll(std.testing.allocator);
    defer payment_ledger.freeRecords(std.testing.allocator, records);

    try std.testing.expectEqual(@as(usize, 1), records.len);
    // Legacy reader leaves refunded=false even when refunds.log has the
    // entry — callers wanting the join use readAllJoined.
    try std.testing.expect(!records[0].refunded);
    try std.testing.expectEqualStrings("", records[0].refund_reason);
}

test "WSITE5 ledger: refund last-write-wins by reason" {
    const path = try tempPath("ledger-refund-lww.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        cleanupAuxLogs(path);
        std.testing.allocator.free(path);
    }
    var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    ledger.setClockFn(fixedClock);
    try ledger.record(SID, "/x", PAYER, TXID, 100);
    try ledger.recordRefund(TXID, "first attempt", 100);
    try ledger.recordRefund(TXID, "final reason", 100);
    ledger.deinit();

    var ledger2 = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger2.deinit();
    const records = try ledger2.readAllJoined(std.testing.allocator);
    defer payment_ledger.freeRecords(std.testing.allocator, records);
    try std.testing.expect(records[0].refunded);
    try std.testing.expectEqualStrings("final reason", records[0].refund_reason);
}

test "WSITE5 ledger: recordRefund rejects bad-length txid" {
    const path = try tempPath("ledger-refund-badhex.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        cleanupAuxLogs(path);
        std.testing.allocator.free(path);
    }
    var ledger = try payment_ledger.PaymentLedger.init(std.testing.allocator, path);
    defer ledger.deinit();
    try std.testing.expectError(error.write_failed, ledger.recordRefund("short", "reason", 1));
}

```
