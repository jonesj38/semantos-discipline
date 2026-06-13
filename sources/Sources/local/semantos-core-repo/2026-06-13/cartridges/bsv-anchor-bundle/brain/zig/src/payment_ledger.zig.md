---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/payment_ledger.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.446038+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/payment_ledger.zig

```zig
// Phase WSITE4 — Payment ledger.
//
// Reference: docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md §3 (WSITE4).
//
// Append-only JSON log of payment claims.  Each line is one record:
//
//   {"ts":<unix>,
//    "session_id":"<32-byte hex>",
//    "route":"/path",
//    "payer":"<33-byte compressed SEC1 hex>",
//    "txid":"<32-byte hex>",
//    "satoshis":5000,
//    "verified":false}
//
// `verified` is `false` at v0.1 because real BEEF→UTXO internalisation
// requires `broker.internalizeAction` (deferred to WSITE4.5).  Operators
// can spot-check the recorded txids against their own indexer / WoC; a
// future WSITE4.5 sweep will mark records `verified:true` after SPV
// confirmation.
//
// The ledger is append-only on disk; in-memory we keep the last N
// records cached for cheap revenue queries.  Older records are read
// back from disk on demand.

const std = @import("std");

pub const LedgerError = error{
    open_failed,
    write_failed,
    out_of_memory,
};

pub const PaymentRecord = struct {
    ts: i64,
    /// 32-byte session id (hex).
    session_id: [64]u8,
    /// Route path, e.g. "/premium/article/42".
    route: []u8,
    /// Payer's compressed SEC1 pubkey (hex).
    payer_hex: [66]u8,
    /// txid the payer cited as their payment (hex).
    txid_hex: [64]u8,
    /// satoshis claimed.
    satoshis: u64,
    /// Whether broker.internalizeAction has confirmed the BEEF.  v0.1
    /// always false — WSITE4.5 sets this true after the verifier sweep.
    verified: bool,
    /// WSITE5 — true iff `recordRefund` has been called for this txid.
    /// Joined at read time the same way `verified` is.
    refunded: bool = false,
    /// WSITE5 — operator-supplied reason from the most recent refund
    /// intent, or empty if not refunded.  Allocator-owned; caller frees
    /// via `freeRecords`.
    refund_reason: []u8 = &.{},
};

pub const RefundEntry = struct {
    ts: i64,
    satoshis: u64,
    reason: []u8, // allocator-owned
};

pub fn freeRefundMap(allocator: std.mem.Allocator, m: *std.StringHashMap(RefundEntry)) void {
    var it = m.iterator();
    while (it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.reason);
    }
    m.deinit();
}

pub const PaymentLedger = struct {
    allocator: std.mem.Allocator,
    log_path: []const u8,
    log_file: ?std.fs.File,
    /// WSITE4.5 — separate verifications log.  Append-only; readAll
    /// joins on txid to flip records' `verified` flag.
    verifications_path: []const u8,
    verifications_file: ?std.fs.File,
    /// WSITE5 — append-only refund-intent log.  Each line:
    ///   {"ts":N,"txid":"<hex>","reason":"...","sats":N}
    /// `brain refund <domain> <txid>` writes here; the OutputStore is
    /// updated separately to mark the UTXO spent with a sentinel
    /// spending_txid (all-0xFF) until WSITE5.5 wires real broadcasting.
    refunds_path: []const u8,
    refunds_file: ?std.fs.File,
    /// Pinned-clock for tests.
    clock_fn: *const fn () i64,

    pub fn init(allocator: std.mem.Allocator, log_path: []const u8) !PaymentLedger {
        if (std.fs.path.dirname(log_path)) |parent| {
            std.fs.cwd().makePath(parent) catch {};
        }
        const f = std.fs.cwd().createFile(log_path, .{ .read = false, .truncate = false }) catch null;
        if (f) |fh| fh.seekFromEnd(0) catch {};

        // Verifications log lives next to payments.log.
        const v_path = try std.fmt.allocPrint(allocator, "{s}.verifications", .{log_path});
        errdefer allocator.free(v_path);
        const vf = std.fs.cwd().createFile(v_path, .{ .read = false, .truncate = false }) catch null;
        if (vf) |fh| fh.seekFromEnd(0) catch {};

        // WSITE5 — refunds log alongside the others.
        const r_path = try std.fmt.allocPrint(allocator, "{s}.refunds", .{log_path});
        errdefer allocator.free(r_path);
        const rf = std.fs.cwd().createFile(r_path, .{ .read = false, .truncate = false }) catch null;
        if (rf) |fh| fh.seekFromEnd(0) catch {};

        return .{
            .allocator = allocator,
            .log_path = try allocator.dupe(u8, log_path),
            .log_file = f,
            .verifications_path = v_path,
            .verifications_file = vf,
            .refunds_path = r_path,
            .refunds_file = rf,
            .clock_fn = defaultClock,
        };
    }

    pub fn deinit(self: *PaymentLedger) void {
        if (self.log_file) |f| f.close();
        if (self.verifications_file) |f| f.close();
        if (self.refunds_file) |f| f.close();
        self.allocator.free(self.log_path);
        self.allocator.free(self.verifications_path);
        self.allocator.free(self.refunds_path);
    }

    pub fn setClockFn(self: *PaymentLedger, f: *const fn () i64) void {
        self.clock_fn = f;
    }

    /// Append a fresh payment record to the log.
    pub fn record(
        self: *PaymentLedger,
        session_id_hex: []const u8, // 64-char hex
        route: []const u8,
        payer_hex: []const u8, // 66-char hex
        txid_hex: []const u8, // 64-char hex
        satoshis: u64,
    ) LedgerError!void {
        if (session_id_hex.len != 64 or payer_hex.len != 66 or txid_hex.len != 64) {
            return error.write_failed;
        }
        const f = self.log_file orelse return error.open_failed;
        var line_buf: [1024]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf,
            "{{\"ts\":{d},\"session_id\":\"{s}\",\"route\":\"{s}\",\"payer\":\"{s}\",\"txid\":\"{s}\",\"satoshis\":{d},\"verified\":false}}\n",
            .{ self.clock_fn(), session_id_hex, route, payer_hex, txid_hex, satoshis },
        ) catch return error.write_failed;
        f.writeAll(line) catch return error.write_failed;
    }

    /// WSITE4.5 — record a verification result for a previously-claimed
    /// txid.  Append-only; the `verified` flag on read-time joins
    /// against the payment log.
    pub fn recordVerification(
        self: *PaymentLedger,
        txid_hex: []const u8,
        verified: bool,
        matched_satoshis: u64,
    ) LedgerError!void {
        if (txid_hex.len != 64) return error.write_failed;
        const f = self.verifications_file orelse return error.open_failed;
        var line_buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf,
            "{{\"ts\":{d},\"txid\":\"{s}\",\"verified\":{s},\"matched_satoshis\":{d}}}\n",
            .{ self.clock_fn(), txid_hex, if (verified) "true" else "false", matched_satoshis },
        ) catch return error.write_failed;
        f.writeAll(line) catch return error.write_failed;
    }

    /// WSITE5 — record a refund intent against a previously-recorded
    /// payment.  v0.1 doesn't yet broadcast the refund tx — that's
    /// WSITE5.5 wallet-engine work — but the intent is logged so:
    ///   • `brain revenue --include-refunds` can deduct refunded payments
    ///   • the operator has an audit trail of "what I owe back"
    ///   • a future sweep can build, sign, and broadcast the refund
    ///     transaction using the cited UTXO from the OutputStore
    ///
    /// `reason` is operator-supplied (e.g. "duplicate charge",
    /// "service failure").  Free-form; not parsed by the tooling.
    pub fn recordRefund(
        self: *PaymentLedger,
        txid_hex: []const u8, // the original payment's txid
        reason: []const u8,
        satoshis: u64,
    ) LedgerError!void {
        if (txid_hex.len != 64) return error.write_failed;
        const f = self.refunds_file orelse return error.open_failed;
        // Allocate enough for a long reason; cap defensively.
        var line_buf: [2048]u8 = undefined;
        const reason_len = @min(reason.len, 1024);
        const line = std.fmt.bufPrint(&line_buf,
            "{{\"ts\":{d},\"txid\":\"{s}\",\"sats\":{d},\"reason\":\"{s}\"}}\n",
            .{ self.clock_fn(), txid_hex, satoshis, reason[0..reason_len] },
        ) catch return error.write_failed;
        f.writeAll(line) catch return error.write_failed;
    }

    /// WSITE5 — read all refund intents.  Returns a map (caller-owned)
    /// from txid_hex → most-recent reason.  Used by `brain revenue` to
    /// flag refunded records.  Caller frees via `freeRefundMap`.
    pub fn readAllRefunds(
        self: *const PaymentLedger,
        allocator: std.mem.Allocator,
    ) !std.StringHashMap(RefundEntry) {
        var out = std.StringHashMap(RefundEntry).init(allocator);
        errdefer freeRefundMap(allocator, &out);
        const file = std.fs.cwd().openFile(self.refunds_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return out,
            else => return err,
        };
        defer file.close();
        const stat = try file.stat();
        if (stat.size == 0) return out;
        const buf = try allocator.alloc(u8, stat.size);
        defer allocator.free(buf);
        _ = try file.readAll(buf);

        var line_iter = std.mem.tokenizeScalar(u8, buf, '\n');
        while (line_iter.next()) |line| {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), line, .{}) catch continue;
            if (parsed != .object) continue;
            const o = parsed.object;
            const txid_v = o.get("txid") orelse continue;
            const sats_v = o.get("sats") orelse continue;
            const reason_v = o.get("reason") orelse continue;
            const ts_v = o.get("ts") orelse continue;
            if (txid_v != .string or txid_v.string.len != 64) continue;
            if (sats_v != .integer or ts_v != .integer or reason_v != .string) continue;

            const txid_dup = try allocator.dupe(u8, txid_v.string);
            const reason_dup = try allocator.dupe(u8, reason_v.string);
            const entry: RefundEntry = .{
                .ts = ts_v.integer,
                .satoshis = @intCast(sats_v.integer),
                .reason = reason_dup,
            };
            // Last write wins so the latest reason takes precedence.
            if (out.fetchRemove(txid_dup)) |kv| {
                allocator.free(kv.key);
                allocator.free(kv.value.reason);
            }
            out.put(txid_dup, entry) catch {
                allocator.free(txid_dup);
                allocator.free(reason_dup);
                continue;
            };
        }
        return out;
    }

    /// Read all records back from disk. Caller owns the returned slice
    /// (and every record's `route` slice).  WSITE4.5 — joins against the
    /// verifications log so `verified` reflects post-hoc SPV checks.
    pub fn readAll(self: *const PaymentLedger, allocator: std.mem.Allocator) ![]PaymentRecord {
        // First load verifications into a txid → bool map so we can fold
        // them into the payment records as we parse.
        var verifications = std.StringHashMap(bool).init(allocator);
        defer {
            var it = verifications.keyIterator();
            while (it.next()) |k| allocator.free(k.*);
            verifications.deinit();
        }
        if (std.fs.cwd().openFile(self.verifications_path, .{})) |vf| {
            defer vf.close();
            const stat = vf.stat() catch return error.write_failed;
            if (stat.size > 0) {
                const buf = try allocator.alloc(u8, stat.size);
                defer allocator.free(buf);
                _ = try vf.readAll(buf);
                var line_iter = std.mem.tokenizeScalar(u8, buf, '\n');
                while (line_iter.next()) |line| {
                    var arena = std.heap.ArenaAllocator.init(allocator);
                    defer arena.deinit();
                    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), line, .{}) catch continue;
                    if (parsed != .object) continue;
                    const o = parsed.object;
                    const txid_v = o.get("txid") orelse continue;
                    const verified_v = o.get("verified") orelse continue;
                    if (txid_v != .string or verified_v != .bool) continue;
                    if (txid_v.string.len != 64) continue;
                    const txid_dup = try allocator.dupe(u8, txid_v.string);
                    // Last write wins (later verification can flip earlier
                    // false → true after WH header sync catches up).
                    if (verifications.fetchRemove(txid_dup)) |kv| {
                        allocator.free(kv.key);
                    }
                    try verifications.put(txid_dup, verified_v.bool);
                }
            }
        } else |_| {}

        const file = std.fs.cwd().openFile(self.log_path, .{}) catch return &[_]PaymentRecord{};
        defer file.close();
        const stat = try file.stat();
        if (stat.size == 0) return &[_]PaymentRecord{};

        const buf = try allocator.alloc(u8, stat.size);
        defer allocator.free(buf);
        _ = try file.readAll(buf);

        var out = std.ArrayList(PaymentRecord){};
        var line_iter = std.mem.tokenizeScalar(u8, buf, '\n');
        while (line_iter.next()) |line| {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), line, .{}) catch continue;
            if (parsed != .object) continue;
            const o = parsed.object;
            const ts_v = o.get("ts") orelse continue;
            const sid_v = o.get("session_id") orelse continue;
            const route_v = o.get("route") orelse continue;
            const payer_v = o.get("payer") orelse continue;
            const txid_v = o.get("txid") orelse continue;
            const sats_v = o.get("satoshis") orelse continue;

            if (ts_v != .integer or sid_v != .string or route_v != .string or
                payer_v != .string or txid_v != .string or sats_v != .integer) continue;
            if (sid_v.string.len != 64 or payer_v.string.len != 66 or txid_v.string.len != 64) continue;
            if (sats_v.integer < 0) continue;

            var rec: PaymentRecord = undefined;
            rec.ts = ts_v.integer;
            @memcpy(&rec.session_id, sid_v.string[0..64]);
            @memcpy(&rec.payer_hex, payer_v.string[0..66]);
            @memcpy(&rec.txid_hex, txid_v.string[0..64]);
            rec.satoshis = @intCast(sats_v.integer);
            rec.route = try allocator.dupe(u8, route_v.string);
            // verified: take the latest verifications log entry for
            // this txid; fall through to the original record's flag.
            rec.verified = if (verifications.get(txid_v.string)) |v|
                v
            else if (o.get("verified")) |v|
                if (v == .bool) v.bool else false
            else
                false;
            // WSITE5 — refunded flag + reason: filled by `readAllJoined`
            // (the legacy `readAll` doesn't open the refunds log to keep
            // bandwidth lower for callers that don't care).  Default to
            // unrefunded here.
            rec.refunded = false;
            rec.refund_reason = &.{};
            try out.append(allocator, rec);
        }
        return out.toOwnedSlice(allocator);
    }

    /// WSITE5 — variant of readAll that also joins refunds.log.
    /// Slightly more expensive (extra file scan) but the right call for
    /// `brain revenue` and `brain refund` lookups.
    pub fn readAllJoined(self: *const PaymentLedger, allocator: std.mem.Allocator) ![]PaymentRecord {
        const records = try self.readAll(allocator);
        var refunds = self.readAllRefunds(allocator) catch {
            return records;
        };
        defer freeRefundMap(allocator, &refunds);
        for (records) |*r| {
            if (refunds.get(&r.txid_hex)) |entry| {
                r.refunded = true;
                r.refund_reason = try allocator.dupe(u8, entry.reason);
            }
        }
        return records;
    }
};

fn defaultClock() i64 {
    return std.time.timestamp();
}

// ─────────────────────────────────────────────────────────────────────
// Revenue summary helpers
// ─────────────────────────────────────────────────────────────────────

pub const RevenueByRoute = struct {
    route: []u8, // owned by the caller's allocator
    count: u32,
    total_sats: u64,
};

/// Aggregate `records` by route, returning `RevenueByRoute[]` sorted by
/// total_sats descending.  Caller owns the returned slice + each entry's
/// route bytes.
pub fn aggregateByRoute(
    allocator: std.mem.Allocator,
    records: []const PaymentRecord,
    since_ts: i64,
) ![]RevenueByRoute {
    var map = std.StringHashMap(RevenueByRoute).init(allocator);
    defer {
        var it = map.valueIterator();
        while (it.next()) |_| {}
        map.deinit();
    }

    for (records) |r| {
        if (r.ts < since_ts) continue;
        if (map.getPtr(r.route)) |entry| {
            entry.count += 1;
            entry.total_sats += r.satoshis;
        } else {
            const route_dup = try allocator.dupe(u8, r.route);
            try map.put(route_dup, .{
                .route = route_dup,
                .count = 1,
                .total_sats = r.satoshis,
            });
        }
    }

    var out = try allocator.alloc(RevenueByRoute, map.count());
    var i: usize = 0;
    var it = map.valueIterator();
    while (it.next()) |v| : (i += 1) {
        out[i] = v.*;
    }

    std.sort.insertion(RevenueByRoute, out, {}, struct {
        fn lessThan(_: void, a: RevenueByRoute, b: RevenueByRoute) bool {
            return a.total_sats > b.total_sats;
        }
    }.lessThan);

    return out;
}

pub fn freeAggregation(allocator: std.mem.Allocator, agg: []RevenueByRoute) void {
    for (agg) |a| allocator.free(a.route);
    allocator.free(agg);
}

pub fn freeRecords(allocator: std.mem.Allocator, records: []PaymentRecord) void {
    for (records) |r| {
        allocator.free(r.route);
        if (r.refund_reason.len > 0) allocator.free(r.refund_reason);
    }
    allocator.free(records);
}

```
