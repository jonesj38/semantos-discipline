---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/wallet.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.286849+00:00
---

# runtime/semantos-brain/src/cli/wallet.zig

```zig
// Wallet/payment verbs (WSITE4 — revenue / sweep / outputs / sessions /
// refund) extracted from src/cli.zig as Move 7 of the cli-modularize
// refactor.  Pure code motion: no behaviour change.

const std = @import("std");
const cli_common = @import("common.zig");
const cli_site = @import("site.zig");
const auth_handler_mod = @import("auth_handler");
const header_store_fs_mod = @import("header_store_fs");
const output_store_fs_mod = @import("output_store_fs");
const output_store_mod = @import("output_store");
const payment_ledger_mod = @import("payment_ledger");
const payment_verifier_mod = @import("payment_verifier");
const refund_tx_mod = @import("refund_tx");
const site_config_mod = @import("site_config");
const bsvz_mod = @import("bsvz");
const site_server_module = @import("site_server");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;
const resolveDataDir = cli_common.resolveDataDir;
const siteConfigPath = cli_site.siteConfigPath;

pub fn cmdRevenue(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain revenue <domain> [--since N] [--verified-only]\n", .{});
        return .bad_args;
    }
    const domain = args[0];
    var since_ts: i64 = 0;
    var verified_only = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--since") and i + 1 < args.len) {
            since_ts = std.fmt.parseInt(i64, args[i + 1], 10) catch {
                try out.print("revenue: invalid --since `{s}` (expected unix-seconds)\n", .{args[i + 1]});
                return .bad_args;
            };
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--verified-only")) {
            verified_only = true;
        }
    }

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    const log_path = try std.fs.path.join(allocator, &.{ data_dir, "sites", domain, "payments.log" });
    defer allocator.free(log_path);

    var ledger = payment_ledger_mod.PaymentLedger.init(allocator, log_path) catch {
        try out.print("revenue: cannot open ledger at {s}\n", .{log_path});
        return .file_io;
    };
    defer ledger.deinit();

    // WSITE5 — readAllJoined folds in refund intents so the verified/
    // refunded breakdown is accurate.
    const records = ledger.readAllJoined(allocator) catch |e| {
        try out.print("revenue: read failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer payment_ledger_mod.freeRecords(allocator, records);

    // Pre-tally verified vs unverified totals before filtering.  This
    // mirrors the standard "X of Y verified" line so operators can spot
    // the verification ratio at a glance — even when --verified-only is
    // set, we want the denominator visible.
    var total_count: u32 = 0;
    var total_sats_all: u64 = 0;
    var verified_count: u32 = 0;
    var verified_sats: u64 = 0;
    var refunded_count: u32 = 0;
    var refunded_sats: u64 = 0;
    for (records) |r| {
        if (r.ts < since_ts) continue;
        total_count += 1;
        total_sats_all += r.satoshis;
        if (r.verified) {
            verified_count += 1;
            verified_sats += r.satoshis;
        }
        if (r.refunded) {
            refunded_count += 1;
            refunded_sats += r.satoshis;
        }
    }

    // Filtered slice for aggregation: when --verified-only, drop
    // unverified records before passing to aggregateByRoute.
    var filtered = std.ArrayList(payment_ledger_mod.PaymentRecord){};
    defer filtered.deinit(allocator);
    if (verified_only) {
        for (records) |r| {
            if (r.verified) try filtered.append(allocator, r);
        }
    }
    const agg_input: []const payment_ledger_mod.PaymentRecord = if (verified_only)
        filtered.items
    else
        records;

    const agg = payment_ledger_mod.aggregateByRoute(allocator, agg_input, since_ts) catch |e| {
        try out.print("revenue: aggregate failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer payment_ledger_mod.freeAggregation(allocator, agg);

    if (agg.len == 0) {
        try out.print("(no{s} payments recorded for {s}", .{
            if (verified_only) " verified" else "",
            domain,
        });
        if (since_ts > 0) try out.print(" since ts={d}", .{since_ts});
        try out.print(")\n", .{});
        return .ok;
    }

    try out.print("revenue — {s}", .{domain});
    if (verified_only) try out.print(" (verified-only)", .{});
    if (since_ts > 0) try out.print(" since ts={d}", .{since_ts});
    try out.print(":\n\n", .{});

    var grand_total: u64 = 0;
    var grand_count: u32 = 0;
    for (agg) |row| {
        grand_total += row.total_sats;
        grand_count += row.count;
        try out.print("  {s: <30}  {d: >4} payments × avg {d: >6} sats = {d: >10} sats\n", .{
            row.route,
            row.count,
            if (row.count > 0) row.total_sats / row.count else 0,
            row.total_sats,
        });
    }
    try out.print("                                 {s}\n", .{"───────────────────────────────────────"});
    try out.print("  total                          {d: >4} payments                 = {d: >10} sats\n",
        .{ grand_count, grand_total });

    // WSITE4.5 — verified vs total breakdown.  Always print, regardless
    // of --verified-only, so the operator sees the ratio.
    if (total_count > 0) {
        const pending_count = total_count - verified_count;
        const pending_sats = total_sats_all - verified_sats;
        try out.print("\nverification:\n", .{});
        try out.print("  verified:  {d: >4} payments / {d: >10} sats\n", .{ verified_count, verified_sats });
        try out.print("  pending:   {d: >4} payments / {d: >10} sats  (run `brain sweep {s}`)\n", .{
            pending_count, pending_sats, domain,
        });
        // WSITE5 — refund summary.  Only printed when there are refunds
        // to report, so steady-state revenue dashboards stay quiet.
        if (refunded_count > 0) {
            const net_sats = if (total_sats_all >= refunded_sats) total_sats_all - refunded_sats else 0;
            try out.print("\nrefunds:\n", .{});
            try out.print("  refunded:  {d: >4} payments / {d: >10} sats\n", .{ refunded_count, refunded_sats });
            try out.print("  net:                       {d: >10} sats (total − refunded)\n", .{net_sats});
        }
    }
    return .ok;
}

// ─────────────────────────────────────────────────────────────────────
// WSITE4.5 — sweep
// ─────────────────────────────────────────────────────────────────────

pub fn cmdSweep(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain sweep <domain>\n", .{});
        return .bad_args;
    }
    const domain = args[0];

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    // Load the site config so we know the recipient + per-route price.
    const cfg_path = try siteConfigPath(allocator, domain);
    defer allocator.free(cfg_path);
    var cfg = site_config_mod.loadFromPath(allocator, cfg_path) catch |e| {
        try out.print("sweep {s}: failed to load {s}: {s}\n", .{ domain, cfg_path, @errorName(e) });
        return .config_error;
    };
    defer cfg.deinit();

    // Open the ledger.
    const log_path = try std.fs.path.join(allocator, &.{ data_dir, "sites", domain, "payments.log" });
    defer allocator.free(log_path);
    var ledger = payment_ledger_mod.PaymentLedger.init(allocator, log_path) catch {
        try out.print("sweep {s}: cannot open ledger at {s}\n", .{ domain, log_path });
        return .file_io;
    };
    defer ledger.deinit();

    const records = ledger.readAll(allocator) catch |e| {
        try out.print("sweep {s}: read failed: {s}\n", .{ domain, @errorName(e) });
        return .file_io;
    };
    defer payment_ledger_mod.freeRecords(allocator, records);

    // Open the header store (shared across all records).
    var header_fs = header_store_fs_mod.FsHeaderStore.init(allocator, data_dir) catch |e| {
        try out.print("sweep {s}: header store init failed: {s}\n", .{ domain, @errorName(e) });
        return .file_io;
    };
    defer header_fs.deinit();
    const header_handle = header_fs.store();
    const tracker = site_server_module.HeaderStoreTracker{ .store = &header_handle };

    // WSITE4.6 — open the per-site OutputStore so newly-verified
    // payments can be internalized inline.  Lives at
    // <data-dir>/sites/<domain>/outputs.log; same file the running site
    // server appends to during inline verification.
    const site_dir = try std.fs.path.join(allocator, &.{ data_dir, "sites", domain });
    defer allocator.free(site_dir);
    var outputs_fs = output_store_fs_mod.FsOutputStore.init(allocator, site_dir) catch |e| {
        try out.print("sweep {s}: output store init failed: {s}\n", .{ domain, @errorName(e) });
        return .file_io;
    };
    defer outputs_fs.deinit();
    const outputs_handle = outputs_fs.store();

    const beef_dir = try std.fs.path.join(allocator, &.{ data_dir, "sites", domain, "beefs" });
    defer allocator.free(beef_dir);

    var processed: u32 = 0;
    var newly_verified: u32 = 0;
    var still_pending: u32 = 0;
    var beef_missing: u32 = 0;
    var failed: u32 = 0;

    // Dedupe txids — verifying the same txid twice is wasteful.  Take
    // the first record with a given txid (chronologically).
    var seen = std.StringHashMap(void).init(allocator);
    defer {
        var it = seen.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        seen.deinit();
    }

    try out.print("sweep — {s}\n", .{domain});

    for (records) |r| {
        if (r.verified) continue; // already done
        processed += 1;

        const txid_dup = try allocator.dupe(u8, &r.txid_hex);
        const gop = try seen.getOrPut(txid_dup);
        if (gop.found_existing) {
            allocator.free(txid_dup);
            continue;
        }

        const beef_path = try std.fmt.allocPrint(allocator, "{s}/{s}.beef", .{ beef_dir, &r.txid_hex });
        defer allocator.free(beef_path);
        const beef_file = std.fs.cwd().openFile(beef_path, .{}) catch {
            beef_missing += 1;
            try out.print("  {s}  pending — no BEEF on disk\n", .{r.txid_hex[0..16]});
            continue;
        };
        defer beef_file.close();
        const stat = beef_file.stat() catch {
            failed += 1;
            continue;
        };
        const beef_bytes = allocator.alloc(u8, stat.size) catch {
            failed += 1;
            continue;
        };
        defer allocator.free(beef_bytes);
        _ = beef_file.readAll(beef_bytes) catch {
            failed += 1;
            continue;
        };

        // Resolve the route to find recipient + price.  The route may
        // have changed since the payment was claimed (operator edited
        // site.json) — in that case the recipient at claim-time is what
        // matters; we fall back to the site default.
        const route_opt = cfg.routeFor(r.route);
        const recipient = blk: {
            if (route_opt) |rt| {
                if (site_config_mod.effectiveRecipient(&cfg, rt)) |rec| break :blk rec;
            }
            if (cfg.payment_recipient_set) break :blk &cfg.payment_recipient;
            break :blk null;
        } orelse {
            still_pending += 1;
            try out.print("  {s}  pending — route {s} no longer payment_required\n", .{ r.txid_hex[0..16], r.route });
            continue;
        };

        // Use the larger of the claimed amount and the route's current
        // price as the threshold — guards against operators silently
        // raising the price after a sale.
        const expected_sats = if (route_opt) |rt|
            @max(r.satoshis, rt.price_sats)
        else
            r.satoshis;

        const result = payment_verifier_mod.verify(
            allocator,
            beef_bytes,
            &r.txid_hex,
            recipient.*,
            expected_sats,
            tracker,
            allocator,
        ) catch |err| {
            failed += 1;
            try out.print("  {s}  failed — {s}\n", .{ r.txid_hex[0..16], @errorName(err) });
            ledger.recordVerification(&r.txid_hex, false, 0) catch {};
            continue;
        };
        defer if (result.matched_locking_script.len > 0) allocator.free(result.matched_locking_script);

        if (result.verified) {
            newly_verified += 1;
            try out.print("  {s}  ✓ verified ({d} sats)\n", .{ r.txid_hex[0..16], result.matched_satoshis });
            // WSITE4.6 — internalize the matched output into the
            // per-site OutputStore so the admin's wallet sees it as
            // spendable.  Re-verifying an already-internalized record
            // is benign; addOutput returns duplicate_outpoint which we
            // swallow.
            const sweep_basket = if (route_opt) |rt| rt.output_basket else "";
            internalizeSweptOutput(
                outputs_handle,
                r,
                result,
                cfg.payment_recipient_set,
                if (cfg.payment_recipient_set) &cfg.payment_recipient else null,
                &r.payer_hex,
                sweep_basket,
            ) catch |err| switch (err) {
                error.duplicate_outpoint => {},
                else => try out.print("  {s}  warn: internalize failed — {s}\n", .{ r.txid_hex[0..16], @errorName(err) }),
            };
        } else {
            still_pending += 1;
            try out.print("  {s}  pending — spv_ok={any} output_ok={any}\n", .{
                r.txid_hex[0..16], result.spv_ok, result.output_ok,
            });
        }
        ledger.recordVerification(&r.txid_hex, result.verified, result.matched_satoshis) catch {};
    }

    try out.print("\n", .{});
    try out.print("  processed:        {d}\n", .{processed});
    try out.print("  newly verified:   {d}\n", .{newly_verified});
    try out.print("  still pending:    {d}\n", .{still_pending});
    try out.print("  BEEF missing:     {d}\n", .{beef_missing});
    try out.print("  failed:           {d}\n", .{failed});
    if (newly_verified == 0 and processed > 0) {
        try out.print("\nNothing was newly verified.  Possible causes:\n", .{});
        try out.print("  • Header store hasn't caught up — `brain headers sync` (WH3+) lands tip data.\n", .{});
        try out.print("  • Stored BEEFs predate the SPV gate — re-collect via the wallet flow.\n", .{});
        try out.print("  • Build is stub-mode — rebuild with -Denable-wasmtime=true for bsvz-linked verifier.\n", .{});
    }
    return .ok;
}

/// WSITE4.6 / WSITE5 — write a verified output into the per-site
/// OutputStore during sweep.  Mirror of
/// `site_server.internalizeMatchedOutput` but at the CLI layer where we
/// already have the ledger record + verifier result in hand.
fn internalizeSweptOutput(
    outputs: output_store_mod.OutputStore,
    rec: payment_ledger_mod.PaymentRecord,
    result: payment_verifier_mod.VerifyResult,
    has_recipient: bool,
    recipient: ?*const [33]u8,
    payer_hex: *const [66]u8,
    route_basket: []const u8,
) !void {
    if (result.matched_locking_script.len == 0) return; // safety
    var txid_bytes: [32]u8 = undefined;
    try sweepHexDecode(&rec.txid_hex, &txid_bytes);

    var dkh: [32]u8 = undefined;
    if (has_recipient) {
        if (recipient) |r| {
            std.crypto.hash.sha2.Sha256.hash(r, &dkh, .{});
        } else dkh = [_]u8{0} ** 32;
    } else {
        dkh = [_]u8{0} ** 32;
    }

    var counterparty: [33]u8 = [_]u8{0} ** 33;
    sweepHexDecode(payer_hex, &counterparty) catch {
        // Malformed payer hex — record without the counterparty field.
        counterparty = [_]u8{0} ** 33;
    };

    const basket = if (route_basket.len > 0) route_basket else "default";
    const record: output_store_mod.OutputRecord = .{
        .outpoint = .{ .txid = txid_bytes, .vout = result.matched_vout },
        .satoshis = result.matched_output_satoshis,
        .locking_script = result.matched_locking_script,
        .derived_key_hash = dkh,
        .derivation_protocol_hash = [_]u8{0} ** 16,
        .derivation_counterparty = counterparty,
        .derivation_index = 0,
        .beef = &.{},
        .basket = basket,
        .tags = &.{},
        .custom_instructions = rec.route,
        .confirmations = 0,
        .status = .unspent,
        .spending_txid = [_]u8{0} ** 32,
    };
    try outputs.addOutput(record);
}

fn sweepHexDecode(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return error.bad_length;
    for (0..out.len) |i| {
        const hi = try sweepHexNibble(hex[i * 2]);
        const lo = try sweepHexNibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
}

fn sweepHexNibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => error.bad_hex,
    };
}

// ─────────────────────────────────────────────────────────────────────
// WSITE4.6 — outputs (admin's spendable UTXOs)
// ─────────────────────────────────────────────────────────────────────

pub fn cmdOutputs(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain outputs <domain> [--basket NAME] [--include-spent]\n", .{});
        return .bad_args;
    }
    const domain = args[0];
    var basket_filter: ?[]const u8 = null;
    var include_spent = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--basket") and i + 1 < args.len) {
            basket_filter = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--include-spent")) {
            include_spent = true;
        }
    }

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    const site_dir = try std.fs.path.join(allocator, &.{ data_dir, "sites", domain });
    defer allocator.free(site_dir);

    var outputs_fs = output_store_fs_mod.FsOutputStore.init(allocator, site_dir) catch |e| {
        try out.print("outputs {s}: cannot open store at {s}: {s}\n", .{ domain, site_dir, @errorName(e) });
        return .file_io;
    };
    defer outputs_fs.deinit();
    const handle = outputs_fs.store();

    // listOutputs filters spent by default; reach in to include them by
    // toggling the only_unspent semantic.  The vtable's list_outputs
    // already gates on .unspent — when the operator wants to see spent
    // we walk via a manual loop instead.
    if (include_spent) {
        try out.print("outputs — {s} (all, including spent)\n\n", .{domain});
        const listed = handle.listOutputs(basket_filter, null, allocator) catch |e| {
            try out.print("outputs: {s}\n", .{@errorName(e)});
            return .file_io;
        };
        defer allocator.free(listed);
        try renderOutputs(out, listed, true);
        // Note: listOutputs at the vtable level returns only .unspent, so
        // include-spent here under-reports.  WSITE5 admin REPL will add a
        // cleaner all-status surface.
        try out.print("\nnote: vtable's listOutputs filters spent at v0.1; full visibility lands in WSITE5.\n", .{});
        return .ok;
    }

    const listed = handle.listOutputs(basket_filter, null, allocator) catch |e| {
        try out.print("outputs: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer allocator.free(listed);

    if (listed.len == 0) {
        try out.print("(no spendable outputs for {s}", .{domain});
        if (basket_filter) |b| try out.print(" in basket {s}", .{b});
        try out.print(")\n", .{});
        return .ok;
    }

    try out.print("outputs — {s}", .{domain});
    if (basket_filter) |b| try out.print(" basket={s}", .{b});
    try out.print(":\n\n", .{});
    try renderOutputs(out, listed, false);
    return .ok;
}

fn renderOutputs(out: *const Output, records: []const output_store_mod.OutputRecord, include_spent: bool) !void {
    var total: u64 = 0;
    for (records) |r| {
        if (!include_spent and r.status != .unspent) continue;
        total += r.satoshis;
        var hex_buf: [64]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (r.outpoint.txid, 0..) |b, i| {
            hex_buf[i * 2] = hex_chars[(b >> 4) & 0xf];
            hex_buf[i * 2 + 1] = hex_chars[b & 0xf];
        }
        try out.print("  {s}:{d}  {d: >10} sats  basket={s}", .{
            hex_buf[0..],
            r.outpoint.vout,
            r.satoshis,
            r.basket,
        });
        if (r.custom_instructions.len > 0) try out.print("  route={s}", .{r.custom_instructions});
        try out.print("\n", .{});
    }
    try out.print("\n  total: {d} sats across {d} output(s)\n", .{ total, records.len });
}

// ─────────────────────────────────────────────────────────────────────
// WSITE5 — sessions admin
// ─────────────────────────────────────────────────────────────────────

pub fn cmdSessions(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain sessions <domain> [--all]\n", .{});
        try out.print("       brain sessions revoke <domain> <session_id_hex>\n", .{});
        return .bad_args;
    }
    // `brain sessions revoke <domain> <id>` — 3 args.
    if (std.mem.eql(u8, args[0], "revoke")) {
        if (args.len < 3) {
            try out.print("usage: brain sessions revoke <domain> <session_id_hex>\n", .{});
            return .bad_args;
        }
        return try cmdSessionsRevoke(allocator, out, args[1], args[2]);
    }
    // `brain sessions <domain> [--all]` — list.
    const domain = args[0];
    var include_all = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--all")) include_all = true;
    }
    return try cmdSessionsList(allocator, out, domain, include_all);
}

fn cmdSessionsList(
    allocator: std.mem.Allocator,
    out: *const Output,
    domain: []const u8,
    include_all: bool,
) !ExitCode {
    _ = include_all; // v0.1 only stores active; expired entries already GC'd at lookup.
    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    const sess_path = try std.fs.path.join(allocator, &.{ data_dir, "sites", domain, "sessions.log" });
    defer allocator.free(sess_path);

    var store = auth_handler_mod.SessionStore.init(allocator, sess_path) catch {
        try out.print("sessions: cannot open session store at {s}\n", .{sess_path});
        return .file_io;
    };
    defer store.deinit();

    const list = try store.activeSessionsAlloc(allocator);
    defer auth_handler_mod.freeSessionList(allocator, list);

    if (list.len == 0) {
        try out.print("(no active sessions for {s})\n", .{domain});
        return .ok;
    }

    try out.print("sessions — {s} ({d} active):\n\n", .{ domain, list.len });
    const now = std.time.timestamp();
    for (list) |s| {
        const ttl = if (s.expires_at > now) s.expires_at - now else 0;
        var id_hex: [64]u8 = undefined;
        auth_handler_mod.hexEncode(&s.id, &id_hex);
        var pk_hex: [66]u8 = undefined;
        auth_handler_mod.hexEncode(&s.pubkey, &pk_hex);
        try out.print("  id={s}  pk={s}…  ttl={d}s  return_to={s}\n", .{
            id_hex[0..16],
            pk_hex[0..16],
            ttl,
            s.return_to,
        });
    }
    return .ok;
}

fn cmdSessionsRevoke(
    allocator: std.mem.Allocator,
    out: *const Output,
    domain: []const u8,
    id_hex: []const u8,
) !ExitCode {
    if (id_hex.len != 64) {
        try out.print("sessions revoke: id must be 64 hex chars (got {d})\n", .{id_hex.len});
        return .bad_args;
    }
    var id_bytes: [32]u8 = undefined;
    sweepHexDecode(id_hex, &id_bytes) catch {
        try out.print("sessions revoke: invalid hex in id\n", .{});
        return .bad_args;
    };

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    const sess_path = try std.fs.path.join(allocator, &.{ data_dir, "sites", domain, "sessions.log" });
    defer allocator.free(sess_path);

    var store = auth_handler_mod.SessionStore.init(allocator, sess_path) catch {
        try out.print("sessions revoke: cannot open session store at {s}\n", .{sess_path});
        return .file_io;
    };
    defer store.deinit();

    const had = store.lookupSession(id_bytes) != null;
    store.revokeSession(id_bytes);
    if (had) {
        try out.print("revoked session {s}\n", .{id_hex[0..16]});
    } else {
        try out.print("no live session matched id {s} (already revoked or expired?)\n", .{id_hex[0..16]});
    }
    return .ok;
}

// ─────────────────────────────────────────────────────────────────────
// WSITE5 — refund intent
// ─────────────────────────────────────────────────────────────────────

pub fn cmdRefund(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 2) {
        try out.print("usage: brain refund <domain> <txid> [--reason TEXT]\n", .{});
        return .bad_args;
    }
    const domain = args[0];
    const txid_hex = args[1];
    if (txid_hex.len != 64) {
        try out.print("refund: txid must be 64 hex chars (got {d})\n", .{txid_hex.len});
        return .bad_args;
    }
    var reason: []const u8 = "operator-initiated refund";
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--reason") and i + 1 < args.len) {
            reason = args[i + 1];
            i += 1;
        }
    }

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    // Open the ledger to confirm the txid exists + grab the sats amount.
    const log_path = try std.fs.path.join(allocator, &.{ data_dir, "sites", domain, "payments.log" });
    defer allocator.free(log_path);
    var ledger = payment_ledger_mod.PaymentLedger.init(allocator, log_path) catch {
        try out.print("refund: cannot open ledger at {s}\n", .{log_path});
        return .file_io;
    };
    defer ledger.deinit();

    const records = ledger.readAllJoined(allocator) catch |e| {
        try out.print("refund: read failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer payment_ledger_mod.freeRecords(allocator, records);

    var found_sats: ?u64 = null;
    var found_route: []u8 = &.{};
    var already_refunded = false;
    for (records) |r| {
        if (std.mem.eql(u8, &r.txid_hex, txid_hex)) {
            found_sats = r.satoshis;
            found_route = r.route;
            if (r.refunded) already_refunded = true;
            break;
        }
    }
    if (found_sats == null) {
        try out.print("refund: txid {s} not in {s}'s payment ledger\n", .{ txid_hex[0..16], domain });
        return .config_error;
    }
    if (already_refunded) {
        try out.print("refund: txid {s} already has a refund intent recorded; appending another\n", .{txid_hex[0..16]});
    }

    ledger.recordRefund(txid_hex, reason, found_sats.?) catch |e| {
        try out.print("refund: write failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };

    // WSITE5.5 — load the site config so we can pull `signing_key_wif`
    // (the operator's signing key for refunds + admin spends).  Empty
    // wif → fall back to WSITE5 intent-only behaviour (mark with the
    // sentinel spending_txid).  Non-empty wif → try to actually
    // construct + broadcast a refund tx.
    const cfg_path = try siteConfigPath(allocator, domain);
    defer allocator.free(cfg_path);
    var cfg = site_config_mod.loadFromPath(allocator, cfg_path) catch |e| {
        try out.print("refund: failed to load site config {s}: {s}\n", .{ cfg_path, @errorName(e) });
        return .config_error;
    };
    defer cfg.deinit();

    const site_dir = try std.fs.path.join(allocator, &.{ data_dir, "sites", domain });
    defer allocator.free(site_dir);
    var outputs_fs = output_store_fs_mod.FsOutputStore.init(allocator, site_dir) catch null;
    if (outputs_fs) |*fs| {
        defer fs.deinit();
        const handle = fs.store();
        var txid_bytes: [32]u8 = undefined;
        sweepHexDecode(txid_hex, &txid_bytes) catch {
            try out.print("refund: malformed txid hex\n", .{});
            return .bad_args;
        };
        // Iterate every recorded output paying this txid (typically
        // one).  For each: if signing_key_wif is set, build + broadcast
        // a refund tx and mark spent with the real refund-tx id; else
        // mark spent with the WSITE5 sentinel (all-0xFF).
        const all = handle.listOutputs(null, null, allocator) catch |e| {
            try out.print("refund: snapshot failed: {s}\n", .{@errorName(e)});
            return .file_io;
        };
        defer allocator.free(all);
        var marked: u32 = 0;
        var broadcast_ok: u32 = 0;
        for (all) |rec| {
            if (!std.mem.eql(u8, &rec.outpoint.txid, &txid_bytes)) continue;

            var spending_txid: [32]u8 = [_]u8{0xff} ** 32;

            if (cfg.signing_key_wif.len > 0) {
                if (broadcastRefund(allocator, out, &cfg, rec)) |spending| {
                    spending_txid = spending;
                    broadcast_ok += 1;
                } else |err| {
                    try out.print("  ⚠ refund broadcast failed for vout {d}: {s} (recording sentinel)\n", .{ rec.outpoint.vout, @errorName(err) });
                }
            }

            handle.markSpent(rec.outpoint, spending_txid) catch |e| switch (e) {
                error.unknown_outpoint => continue,
                else => {
                    try out.print("refund: markSpent failed: {s}\n", .{@errorName(e)});
                    return .file_io;
                },
            };
            marked += 1;
        }
        try out.print("refund recorded for {s} ({s})  sats={d}  reason=\"{s}\"  marked-utxos={d}", .{
            txid_hex[0..16],
            if (found_route.len > 0) found_route else "?",
            found_sats.?,
            reason,
            marked,
        });
        if (cfg.signing_key_wif.len > 0) {
            try out.print("  broadcast={d}\n", .{broadcast_ok});
        } else {
            try out.print("\n", .{});
        }
    } else {
        try out.print("refund recorded for {s}  sats={d}  reason=\"{s}\"  (note: OutputStore not present; UTXO not marked spent)\n", .{
            txid_hex[0..16],
            found_sats.?,
            reason,
        });
    }

    if (cfg.signing_key_wif.len == 0) {
        try out.print("\nNote: site.json has no `signing_key_wif`.  WSITE5.5 records\n", .{});
        try out.print("refund intent only; construction + broadcast of the refund\n", .{});
        try out.print("transaction is the operator's job until you set the key.\n", .{});
    }
    return .ok;
}

/// WSITE5.5 — construct + sign + broadcast a refund tx for the
/// given OutputStore record.  Returns the broadcast tx's txid (in
/// internal/wire byte order — the same byte order the OutputStore
/// uses for outpoint.txid keys).  Errors are surfaced to the caller
/// for "spending_txid stays sentinel" handling.
fn broadcastRefund(
    allocator: std.mem.Allocator,
    out: *const Output,
    cfg: *const site_config_mod.SiteConfig,
    rec: output_store_mod.OutputRecord,
) !([32]u8) {
    // We rely on `derivation_counterparty` being non-zero (WSITE4.6
    // populated this from the auth-callback's BRC-100 pubkey).  An
    // all-zero counterparty means we don't have a payer to refund to.
    var any_nonzero = false;
    for (rec.derivation_counterparty) |b| if (b != 0) {
        any_nonzero = true;
        break;
    };
    if (!any_nonzero) return error.no_payer_pubkey;
    // ARC URL — operator-overrideable in WSITE5.6 via site config.
    // Default to Taal's free public ARC.
    const arc_url = "https://arc.taal.com/v1/tx";
    const fee_sats_per_kb: u64 = 50;

    const built = refund_tx_mod.buildRefund(
        allocator,
        cfg.signing_key_wif,
        rec.outpoint.txid,
        rec.outpoint.vout,
        rec.locking_script,
        rec.satoshis,
        rec.derivation_counterparty,
        fee_sats_per_kb,
    ) catch |err| {
        try out.print("  refund-tx build error: {s}\n", .{@errorName(err)});
        return err;
    };
    defer refund_tx_mod.freeBuiltRefund(allocator, built);

    // Display-form txid for logging (block-explorer convention =
    // reversed wire form).  The store-side spending_txid uses
    // wire/internal order to match its other fields.
    var disp_hex: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (built.txid_display, 0..) |b, i| {
        const dst = 31 - i;
        disp_hex[dst * 2] = hex_chars[(b >> 4) & 0xf];
        disp_hex[dst * 2 + 1] = hex_chars[b & 0xf];
    }
    try out.print("  refund-tx built: {s} ({d} sats out, {d} sats fee)\n", .{
        disp_hex[0..16], built.output_satoshis, built.fee_satoshis,
    });

    const outcome = refund_tx_mod.broadcastViaArc(allocator, built.raw_bytes, arc_url, null) catch |err| {
        try out.print("  refund-tx broadcast error: {s}\n", .{@errorName(err)});
        return err;
    };
    defer refund_tx_mod.freeBroadcastOutcome(allocator, outcome);
    try out.print("  refund-tx broadcast → {s} (detail={s})\n", .{
        if (outcome.ok) "ok" else "rejected",
        outcome.detail,
    });
    if (!outcome.ok) return error.broadcast_rejected;

    // Reverse to wire/internal byte order for the OutputStore key.
    var spending_internal: [32]u8 = undefined;
    for (built.txid_display, 0..) |b, i| spending_internal[31 - i] = b;
    return spending_internal;
}

```
