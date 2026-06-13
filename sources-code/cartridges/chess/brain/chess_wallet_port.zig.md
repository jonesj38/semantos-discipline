---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/brain/chess_wallet_port.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.425586+00:00
---

# cartridges/chess/brain/chess_wallet_port.zig

```zig
// chess_wallet_port — production WalletPort impl for chess.
//
// Reference:
//   docs/design/CHESS-DOUBLING-CUBE.md §12.6 (reactor safety)
//   docs/CHESS-DOUBLING-CUBE-TRACKING.md Phase 2
//   cartridges/chess/brain/chess_escrow.zig (the seam — WalletPort)
//   cartridges/wallet-headers/brain/src/test-chess-stake.ts (the mint
//     side — produces the anchors manifest this port consumes)
//   src/ffi/exports.zig:1711 (semantos_linear_consume)
//   src/ffi/wallet_exports.zig:83 (semantos_wallet_pay — Phase-2.B
//     submitter, not called here)
//
// Architecture (per the four locked decisions, 2026-05-20):
//
//   Q1 PRE-MINTED — anchors are minted off-reactor by the wallet.html
//     chess-stake panel; this port's `anchor_fn` is a pure LOOKUP into
//     an in-memory manifest. No network calls in the verb path.
//   Q2 MANIFEST IMPORT — the brain ingests a JSON manifest exported
//     from the wallet's outputStore (chess.stake.v1 unspent anchors +
//     their derivation context). No external indexer in V1.
//   Q3 INTENT QUEUE — `pay_fn` does NOT broadcast; it writes a payout
//     intent to a queue directory. A separate detached submitter
//     binary (not in this commit) drains the queue, builds + signs +
//     ARC-broadcasts. This is the 2026-05-18 outage-class rule:
//     verbs never sync-call back into the single-threaded reactor.
//   Q4 TESTABLE CORE — the kernel `linear_consume` extern is injected
//     as a function pointer so this module is unit-testable with a
//     stub. Production wires the real extern via chess_native_bridge.
//
//   anchor_fn  → manifest lookup (no I/O, no network)
//   consume_fn → injected kernel fn (production: semantos_linear_consume)
//   pay_fn     → write payout intent to queue dir (no network)

const std = @import("std");
const escrow_mod = @import("chess_escrow");

pub const Color = escrow_mod.Color;
pub const WalletError = escrow_mod.WalletError;
pub const WalletPort = escrow_mod.WalletPort;

// ── Kernel-consume seam ────────────────────────────────────────────────

/// Production wires `chess_native_bridge.linearConsume` here, which
/// translates rc to ConsumeError. Tests pass a stub.
pub const ConsumeError = error{
    already_consumed,
    not_init,
    denied,
    not_found,
    cell_too_short,
    other,
};
pub const KernelConsumeFn = *const fn (path: []const u8, cert: []const u8) ConsumeError!void;

// ── Anchor manifest ────────────────────────────────────────────────────

pub const Anchor = struct {
    game_id_buf: [64]u8 = undefined,
    game_id_len: u8 = 0,
    color: Color,
    type_hash: [32]u8,
    anchor_index: u64,
    satoshis: u64,
    /// big-endian (display) txid; 32 bytes = 64 hex chars.
    txid_be_hex: [64]u8 = undefined,
    vout: u32,
    /// 33-byte compressed identity (counterparty for BRC-42 self-ECDH).
    owner_pk: [33]u8,
    /// 33-byte compressed anchor-derived pk (so the submitter can
    /// re-derive the spending sk via deriveCellAnchorSk).
    derived_pk: [33]u8,

    /// Has anchor_fn bound this anchor to a chess cell path? Until
    /// then consume_fn would have no cell to consume against.
    bound: bool = false,
    consumed: bool = false,

    /// Cell path the store bound this anchor to (via anchor_fn). The
    /// submitter receives it in the payout intent and calls
    /// `semantos_linear_consume` against this exact path. Empty
    /// (bound_path_len==0) until anchor_fn binds.
    bound_path_buf: [64]u8 = undefined,
    bound_path_len: u8 = 0,

    pub fn gameId(self: *const Anchor) []const u8 {
        return self.game_id_buf[0..self.game_id_len];
    }
    pub fn boundPath(self: *const Anchor) []const u8 {
        return self.bound_path_buf[0..self.bound_path_len];
    }
};

const MAX_ANCHORS = 256;

pub const Manifest = struct {
    items: [MAX_ANCHORS]Anchor = undefined,
    len: usize = 0,

    pub fn push(self: *Manifest, a: Anchor) !void {
        if (self.len >= MAX_ANCHORS) return error.manifest_full;
        self.items[self.len] = a;
        self.len += 1;
    }

    /// Find the first unconsumed, unbound anchor matching (game_id, color).
    pub fn findUnbound(self: *Manifest, game_id: []const u8, color: Color) ?*Anchor {
        for (self.items[0..self.len]) |*a| {
            if (a.consumed or a.bound) continue;
            if (a.color != color) continue;
            if (!std.mem.eql(u8, a.gameId(), game_id)) continue;
            return a;
        }
        return null;
    }

    /// Resolve the anchor previously bound to `path`. `path` shape:
    /// "<game_id>/stake/<w|b>/<leg>" (matches chess_game_store anchorPath).
    fn findBoundByPath(self: *Manifest, path: []const u8) ?*Anchor {
        const game_id = parseGameId(path) orelse return null;
        const color = parseColor(path) orelse return null;
        for (self.items[0..self.len]) |*a| {
            if (!a.bound or a.consumed) continue;
            if (a.color != color) continue;
            if (!std.mem.eql(u8, a.gameId(), game_id)) continue;
            return a;
        }
        return null;
    }
};

fn parseGameId(path: []const u8) ?[]const u8 {
    // First segment before "/stake/".
    const marker = "/stake/";
    const idx = std.mem.indexOf(u8, path, marker) orelse return null;
    return path[0..idx];
}

fn parseColor(path: []const u8) ?Color {
    const marker = "/stake/";
    const idx = std.mem.indexOf(u8, path, marker) orelse return null;
    const after = path[idx + marker.len ..];
    if (after.len == 0) return null;
    return switch (after[0]) {
        'w' => .white,
        'b' => .black,
        else => null,
    };
}

// ── JSON manifest loader ───────────────────────────────────────────────

pub const ManifestParseError = error{
    bad_json,
    missing_field,
    bad_hex,
    bad_color,
    manifest_full,
    out_of_memory,
};

fn hexByte(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(10 + (c - 'a')),
        'A'...'F' => @intCast(10 + (c - 'A')),
        else => null,
    };
}

fn decodeHex(comptime N: usize, hex: []const u8, out: *[N]u8) !void {
    if (hex.len != 2 * N) return ManifestParseError.bad_hex;
    var i: usize = 0;
    while (i < N) : (i += 1) {
        const hi = hexByte(hex[2 * i]) orelse return ManifestParseError.bad_hex;
        const lo = hexByte(hex[2 * i + 1]) orelse return ManifestParseError.bad_hex;
        out[i] = (@as(u8, hi) << 4) | @as(u8, lo);
    }
}

/// Parse a chess-stake anchors manifest produced by the wallet.html
/// chess-stake panel (one JSON object per export run). Schema is
/// documented at the head of this file.
pub fn loadManifestJson(allocator: std.mem.Allocator, json_bytes: []const u8) ManifestParseError!Manifest {
    var manifest = Manifest{};
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{}) catch {
        return ManifestParseError.bad_json;
    };
    defer parsed.deinit();
    if (parsed.value != .object) return ManifestParseError.bad_json;

    const anchors_v = parsed.value.object.get("anchors") orelse return ManifestParseError.missing_field;
    if (anchors_v != .array) return ManifestParseError.bad_json;

    for (anchors_v.array.items) |entry| {
        if (entry != .object) return ManifestParseError.bad_json;
        const obj = entry.object;
        const game_id_v = obj.get("game_id") orelse return ManifestParseError.missing_field;
        const color_v = obj.get("color") orelse return ManifestParseError.missing_field;
        const type_hash_v = obj.get("type_hash_hex") orelse return ManifestParseError.missing_field;
        const idx_v = obj.get("anchor_index") orelse return ManifestParseError.missing_field;
        const outpoint_v = obj.get("outpoint") orelse return ManifestParseError.missing_field;
        const sats_v = obj.get("satoshis") orelse return ManifestParseError.missing_field;
        const owner_pk_v = obj.get("owner_pk_hex") orelse return ManifestParseError.missing_field;
        const derived_pk_v = obj.get("derived_pk_hex") orelse return ManifestParseError.missing_field;

        if (game_id_v != .string or color_v != .string or type_hash_v != .string or
            idx_v != .integer or outpoint_v != .object or sats_v != .integer or
            owner_pk_v != .string or derived_pk_v != .string)
            return ManifestParseError.bad_json;

        var a = Anchor{
            .color = if (std.mem.eql(u8, color_v.string, "white")) .white else if (std.mem.eql(u8, color_v.string, "black")) .black else return ManifestParseError.bad_color,
            .type_hash = undefined,
            .anchor_index = @intCast(idx_v.integer),
            .satoshis = @intCast(sats_v.integer),
            .vout = undefined,
            .owner_pk = undefined,
            .derived_pk = undefined,
        };

        const gid = game_id_v.string;
        if (gid.len > a.game_id_buf.len) return ManifestParseError.bad_json;
        @memcpy(a.game_id_buf[0..gid.len], gid);
        a.game_id_len = @intCast(gid.len);

        try decodeHex(32, type_hash_v.string, &a.type_hash);
        try decodeHex(33, owner_pk_v.string, &a.owner_pk);
        try decodeHex(33, derived_pk_v.string, &a.derived_pk);

        const op = outpoint_v.object;
        const txid_v = op.get("txid_be") orelse return ManifestParseError.missing_field;
        const vout_v = op.get("vout") orelse return ManifestParseError.missing_field;
        if (txid_v != .string or vout_v != .integer) return ManifestParseError.bad_json;
        if (txid_v.string.len != 64) return ManifestParseError.bad_hex;
        @memcpy(&a.txid_be_hex, txid_v.string);
        a.vout = @intCast(vout_v.integer);

        try manifest.push(a);
    }
    return manifest;
}

// ── Payout intent (the queue contract) ─────────────────────────────────

/// The shape the detached submitter (Phase-2.B, not in this commit)
/// reads from the queue dir. One file per intent; append-only. The
/// submitter is responsible for building the spend tx, signing, ARC
/// broadcast, and marking the intent done.
pub const PayoutIntent = struct {
    intent_id: u64, // monotonic per Port
    owner: Color,
    sats: u64,
    /// Anchors this payout will spend (writes the source UTXOs the
    /// submitter must consume). Phase-2 first cut: bound + consumed
    /// anchors from this port's manifest.
    source_outpoints: [][]const u8, // each "<txid_be>:<vout>"
    ts_unix: i64,
};

// ── Port ───────────────────────────────────────────────────────────────

pub const Port = struct {
    allocator: std.mem.Allocator,
    manifest: *Manifest,
    queue_dir: []const u8,
    /// Bytes passed to the kernel `linear_consume` as the consumer cert
    /// (BRC-52 self-issued cert id, typically 32 bytes). Borrowed; the
    /// caller owns the lifetime.
    consumer_cert: []const u8,
    consume_fn: KernelConsumeFn,
    /// Monotonic per-Port intent counter (also used for queue filenames).
    intent_counter: u64 = 0,
    /// Track which manifest anchors were drawn into the most recent
    /// payout, so pay_fn can record their outpoints in the intent.
    /// Reset between payouts; held outside the manifest to keep that
    /// pure (the manifest only tracks bound/consumed).
    pending_source_idx: [MAX_ANCHORS]usize = undefined,
    pending_source_len: usize = 0,

    /// Wallclock fn (ms). Injectable so tests are deterministic.
    clock_fn: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        manifest: *Manifest,
        queue_dir: []const u8,
        consumer_cert: []const u8,
        consume_fn: KernelConsumeFn,
        clock_fn: *const fn () i64,
    ) Port {
        return .{
            .allocator = allocator,
            .manifest = manifest,
            .queue_dir = queue_dir,
            .consumer_cert = consumer_cert,
            .consume_fn = consume_fn,
            .clock_fn = clock_fn,
        };
    }

    pub fn portInterface(self: *Port) WalletPort {
        return .{ .ctx = self, .anchor_fn = anchorFn, .consume_fn = consumeFn, .pay_fn = payFn };
    }

    // ── seam fn impls ─────────────────────────────────────────────

    fn anchorFn(ctx: *anyopaque, owner: Color, sats: u64, path: []const u8) WalletError!void {
        const self: *Port = @ptrCast(@alignCast(ctx));
        const game_id = parseGameId(path) orelse return WalletError.anchor_failed;
        const a = self.manifest.findUnbound(game_id, owner) orelse return WalletError.anchor_failed;
        if (a.satoshis != sats) return WalletError.anchor_failed; // wrong amount minted
        if (path.len > a.bound_path_buf.len) return WalletError.anchor_failed;
        @memcpy(a.bound_path_buf[0..path.len], path);
        a.bound_path_len = @intCast(path.len);
        a.bound = true;
        // Remember this anchor as a payout source candidate (pay_fn at
        // resolution drains these).
        if (self.pending_source_len < MAX_ANCHORS) {
            // Find the index of `a` in manifest.items.
            const base_addr: usize = @intFromPtr(&self.manifest.items[0]);
            const off: usize = @divExact(@intFromPtr(a) - base_addr, @sizeOf(Anchor));
            self.pending_source_idx[self.pending_source_len] = off;
            self.pending_source_len += 1;
        }
    }

    fn consumeFn(ctx: *anyopaque, path: []const u8) WalletError!void {
        const self: *Port = @ptrCast(@alignCast(ctx));
        const a = self.manifest.findBoundByPath(path) orelse return WalletError.port_unavailable;
        self.consume_fn(path, self.consumer_cert) catch |err| return switch (err) {
            error.already_consumed => WalletError.already_consumed,
            error.not_init, error.denied, error.not_found, error.cell_too_short, error.other => WalletError.port_unavailable,
        };
        a.consumed = true;
    }

    fn payFn(ctx: *anyopaque, owner: Color, sats: u64) WalletError!void {
        const self: *Port = @ptrCast(@alignCast(ctx));
        self.intent_counter += 1;
        self.writeIntent(owner, sats) catch return WalletError.pay_failed;
    }

    fn writeIntent(self: *Port, owner: Color, sats: u64) !void {
        var path_buf: [256]u8 = undefined;
        const fname = try std.fmt.bufPrint(
            &path_buf,
            "{s}/{d:0>16}-{s}-{d}.intent.json",
            .{ self.queue_dir, self.intent_counter, if (owner == .white) "white" else "black", sats },
        );

        // Build the JSON body (pure std.json writes — no allocations
        // needed beyond the small intent buffer).
        var body: std.ArrayList(u8) = .{};
        defer body.deinit(self.allocator);
        try body.appendSlice(self.allocator, "{\"version\":1,\"intent_id\":");
        try body.writer(self.allocator).print("{d}", .{self.intent_counter});
        try body.appendSlice(self.allocator, ",\"owner\":");
        try body.appendSlice(self.allocator, if (owner == .white) "\"white\"" else "\"black\"");
        try body.appendSlice(self.allocator, ",\"satoshis\":");
        try body.writer(self.allocator).print("{d}", .{sats});
        try body.appendSlice(self.allocator, ",\"ts_unix\":");
        try body.writer(self.allocator).print("{d}", .{self.clock_fn()});
        try body.appendSlice(self.allocator, ",\"sources\":[");
        for (self.pending_source_idx[0..self.pending_source_len], 0..) |aidx, i| {
            if (i > 0) try body.append(self.allocator, ',');
            const a = &self.manifest.items[aidx];
            try body.appendSlice(self.allocator, "{\"outpoint\":\"");
            try body.appendSlice(self.allocator, a.txid_be_hex[0..]);
            try body.append(self.allocator, ':');
            try body.writer(self.allocator).print("{d}", .{a.vout});
            try body.appendSlice(self.allocator, "\",\"cell_path\":\"");
            try body.appendSlice(self.allocator, a.boundPath());
            try body.appendSlice(self.allocator, "\"}");
        }
        try body.appendSlice(self.allocator, "]}");

        var file = try std.fs.cwd().createFile(fname, .{ .truncate = true });
        defer file.close();
        try file.writeAll(body.items);
    }
};

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

const FIXTURE_MANIFEST =
    \\{
    \\  "version": 1,
    \\  "anchors": [
    \\    {
    \\      "game_id": "chess-test",
    \\      "color": "white",
    \\      "type_hash_hex": "1100000000000000000000000000000000000000000000000000000000000022",
    \\      "anchor_index": 1001,
    \\      "outpoint": { "txid_be": "abababababababababababababababababababababababababababababababab", "vout": 1 },
    \\      "satoshis": 500,
    \\      "owner_pk_hex": "02ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    \\      "derived_pk_hex": "031111111111111111111111111111111111111111111111111111111111111111"
    \\    },
    \\    {
    \\      "game_id": "chess-test",
    \\      "color": "black",
    \\      "type_hash_hex": "1100000000000000000000000000000000000000000000000000000000000022",
    \\      "anchor_index": 2002,
    \\      "outpoint": { "txid_be": "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd", "vout": 2 },
    \\      "satoshis": 500,
    \\      "owner_pk_hex": "02ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    \\      "derived_pk_hex": "022222222222222222222222222222222222222222222222222222222222222222"
    \\    }
    \\  ]
    \\}
;

fn testClockMs() i64 {
    return 1747500000123;
}

/// Stub consume fn for tests: succeeds first time per path, returns
/// already_consumed on replay (mirrors the kernel guarantee).
const StubConsume = struct {
    var consumed: [16][]const u8 = undefined;
    var n: usize = 0;
    fn reset() void {
        n = 0;
    }
    fn call(path: []const u8, cert: []const u8) ConsumeError!void {
        _ = cert;
        for (consumed[0..n]) |p| if (std.mem.eql(u8, p, path)) return ConsumeError.already_consumed;
        consumed[n] = path;
        n += 1;
    }
};

test "manifest JSON loads and exposes both anchors" {
    var m = try loadManifestJson(testing.allocator, FIXTURE_MANIFEST);
    try testing.expectEqual(@as(usize, 2), m.len);
    try testing.expectEqual(Color.white, m.items[0].color);
    try testing.expectEqual(Color.black, m.items[1].color);
    try testing.expectEqualStrings("chess-test", m.items[0].gameId());
    try testing.expectEqual(@as(u64, 1001), m.items[0].anchor_index);
    try testing.expectEqual(@as(u64, 500), m.items[0].satoshis);
    try testing.expectEqual(@as(u32, 1), m.items[0].vout);
}

test "anchor_fn binds the right manifest entry for the path" {
    var m = try loadManifestJson(testing.allocator, FIXTURE_MANIFEST);
    StubConsume.reset();
    var p = Port.init(testing.allocator, &m, "/tmp", "cert", StubConsume.call, testClockMs);
    const port = p.portInterface();

    try port.anchor_fn(port.ctx, .white, 500, "chess-test/stake/w/base");
    try port.anchor_fn(port.ctx, .black, 500, "chess-test/stake/b/base");
    try testing.expect(m.items[0].bound);
    try testing.expect(m.items[1].bound);

    // No more white anchors for the same game.
    try testing.expectError(WalletError.anchor_failed, port.anchor_fn(port.ctx, .white, 500, "chess-test/stake/w/base"));
    // Wrong amount.
    var m2 = try loadManifestJson(testing.allocator, FIXTURE_MANIFEST);
    var p2 = Port.init(testing.allocator, &m2, "/tmp", "cert", StubConsume.call, testClockMs);
    try testing.expectError(WalletError.anchor_failed, p2.portInterface().anchor_fn(@ptrCast(&p2), .white, 999, "chess-test/stake/w/base"));
}

test "consume_fn calls the injected kernel fn; replay surfaces already_consumed" {
    var m = try loadManifestJson(testing.allocator, FIXTURE_MANIFEST);
    StubConsume.reset();
    var p = Port.init(testing.allocator, &m, "/tmp", "cert", StubConsume.call, testClockMs);
    const port = p.portInterface();

    try port.anchor_fn(port.ctx, .white, 500, "chess-test/stake/w/base");
    try port.consume_fn(port.ctx, "chess-test/stake/w/base");
    try testing.expect(m.items[0].consumed);
    // Replay rejected by the stub (mirrors SEMANTOS_ERR_ALREADY_CONSUMED).
    // Re-bind to test the consume_fn's mapping path, then call again.
    m.items[0].bound = true; // simulate stale bound flag
    m.items[0].consumed = false; // pretend it isn't (the kernel will still reject)
    try testing.expectError(WalletError.already_consumed, port.consume_fn(port.ctx, "chess-test/stake/w/base"));
}

test "pay_fn writes an intent file with source outpoints" {
    var m = try loadManifestJson(testing.allocator, FIXTURE_MANIFEST);
    StubConsume.reset();
    // Use the test runner's tmp dir.
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var p = Port.init(testing.allocator, &m, tmp_path, "cert", StubConsume.call, testClockMs);
    const port = p.portInterface();

    try port.anchor_fn(port.ctx, .white, 500, "chess-test/stake/w/base");
    try port.anchor_fn(port.ctx, .black, 500, "chess-test/stake/b/base");
    try port.consume_fn(port.ctx, "chess-test/stake/w/base");
    try port.consume_fn(port.ctx, "chess-test/stake/b/base");
    try port.pay_fn(port.ctx, .white, 1000);

    // Read the intent file back and sanity-check shape.
    var found = false;
    var it = try tmp.dir.openDir(".", .{ .iterate = true });
    defer it.close();
    var walker = it.iterate();
    while (try walker.next()) |e| {
        if (std.mem.endsWith(u8, e.name, ".intent.json")) {
            found = true;
            const data = try tmp.dir.readFileAlloc(testing.allocator, e.name, 4096);
            defer testing.allocator.free(data);
            try testing.expect(std.mem.indexOf(u8, data, "\"version\":1") != null);
            try testing.expect(std.mem.indexOf(u8, data, "\"owner\":\"white\"") != null);
            try testing.expect(std.mem.indexOf(u8, data, "\"satoshis\":1000") != null);
            // Two source anchors (white + black) listed with cell_path.
            try testing.expect(std.mem.indexOf(u8, data, "abababab") != null);
            try testing.expect(std.mem.indexOf(u8, data, "cdcdcdcd") != null);
            try testing.expect(std.mem.indexOf(u8, data, "\"cell_path\":\"chess-test/stake/w/base\"") != null);
            try testing.expect(std.mem.indexOf(u8, data, "\"cell_path\":\"chess-test/stake/b/base\"") != null);
        }
    }
    try testing.expect(found);
}

```
