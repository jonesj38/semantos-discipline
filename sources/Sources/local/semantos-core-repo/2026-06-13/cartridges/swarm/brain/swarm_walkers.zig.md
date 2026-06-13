---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/swarm/brain/swarm_walkers.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.678910+00:00
---

# cartridges/swarm/brain/swarm_walkers.zig

```zig
// swarm_walkers — the four cold-path RPC verbs for the paid swarm cartridge,
// routed through verb_dispatcher (extension_id = "swarm"):
//
//   swarm.publish  {infohash, manifestCellHex, semanticPath} → {infohash, stored, anchorStatus}
//   swarm.locate   {infohash}                                → {manifestKnown, manifestCellHex?, seeders[]}
//   swarm.announce {infohash, address, bitfieldHex}          → {ok}
//   swarm.settle   {infohash, receipts[]}                    → {recorded}
//
// These are the ONLY brain touches on the swarm path — the data plane (cells)
// flies peer-to-peer over multicast and never round-trips here. M5 operates on
// an in-memory tracker; M6 binds the CellStore so manifests/receipts persist as
// cells and the tracker rebuilds at boot.

const std = @import("std");
const verb_dispatcher = @import("verb_dispatcher");
const tracker_mod = @import("swarm_tracker");
const cell_store_mod = @import("cell_store");
const swarm_manifest = @import("swarm_manifest");

pub const State = struct {
    tracker: *tracker_mod.Tracker,
    clock_fn: *const fn () i64,
    /// Late-bound by cartridge_boot.bindCellStore (M6). When present, publish
    /// persists the manifest cell and settle mints receipt cells.
    cell_store: ?*const cell_store_mod.CellStore = null,
};

const DispatchError = verb_dispatcher.DispatchError;

// ── JSON helpers ───────────────────────────────────────────────────────────────

fn getStr(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

fn appendJsonString(allocator: std.mem.Allocator, body: *std.ArrayList(u8), s: []const u8) !void {
    try body.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try body.appendSlice(allocator, "\\\""),
            '\\' => try body.appendSlice(allocator, "\\\\"),
            '\n' => try body.appendSlice(allocator, "\\n"),
            '\r' => try body.appendSlice(allocator, "\\r"),
            '\t' => try body.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    var buf: [6]u8 = undefined;
                    const hex = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}) catch unreachable;
                    try body.appendSlice(allocator, hex);
                } else {
                    try body.append(allocator, c);
                }
            },
        }
    }
    try body.append(allocator, '"');
}

fn parseObject(allocator: std.mem.Allocator, params_json: []const u8) DispatchError!std.json.Parsed(std.json.Value) {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch
        return DispatchError.invalid_params;
    if (parsed.value != .object) {
        parsed.deinit();
        return DispatchError.invalid_params;
    }
    return parsed;
}

// ── walkers ────────────────────────────────────────────────────────────────────

pub fn publishWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    const parsed = try parseObject(allocator, params_json);
    defer parsed.deinit();
    const obj = parsed.value.object;

    const infohash = getStr(obj, "infohash") orelse return DispatchError.invalid_params;
    const manifest_cell_hex = getStr(obj, "manifestCellHex") orelse return DispatchError.invalid_params;
    const semantic_path = getStr(obj, "semanticPath") orelse "";

    state.tracker.publish(infohash, manifest_cell_hex, semantic_path) catch return DispatchError.out_of_memory;

    // M6 — persist the manifest cell so the tracker survives restart.
    // M7 — schedule anchoring: mark the cell pending (the brain's anchor runner
    // flips it to confirmed once the manifest is committed on-chain).
    if (state.cell_store) |cs| {
        const cell = swarm_manifest.decodeManifestCellHex(manifest_cell_hex) catch return DispatchError.invalid_params;
        const hash = cs.put(&cell) catch return DispatchError.out_of_memory;
        cs.setAnchorStatus(&hash, .pending) catch {};
        state.tracker.setManifestHash(infohash, hash);
    }

    var body: std.ArrayList(u8) = .{};
    errdefer body.deinit(allocator);
    body.appendSlice(allocator, "{\"infohash\":") catch return DispatchError.out_of_memory;
    appendJsonString(allocator, &body, infohash) catch return DispatchError.out_of_memory;
    // Persisted cells are scheduled for anchoring (pending); without a bound
    // store the manifest lives only in the in-memory tracker (unanchored).
    const status: []const u8 = if (state.cell_store != null) "pending" else "unanchored";
    body.appendSlice(allocator, ",\"stored\":true,\"anchorStatus\":\"") catch return DispatchError.out_of_memory;
    body.appendSlice(allocator, status) catch return DispatchError.out_of_memory;
    body.appendSlice(allocator, "\"}") catch return DispatchError.out_of_memory;
    return body.toOwnedSlice(allocator) catch DispatchError.out_of_memory;
}

pub fn locateWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    const parsed = try parseObject(allocator, params_json);
    defer parsed.deinit();
    const obj = parsed.value.object;
    const infohash = getStr(obj, "infohash") orelse return DispatchError.invalid_params;

    var body: std.ArrayList(u8) = .{};
    errdefer body.deinit(allocator);

    if (state.tracker.locate(infohash)) |e| {
        body.appendSlice(allocator, "{\"manifestKnown\":true,\"manifestCellHex\":") catch return DispatchError.out_of_memory;
        appendJsonString(allocator, &body, e.manifest_cell_hex) catch return DispatchError.out_of_memory;
        // M7 — report the manifest cell's on-chain anchor status.
        const anchor_status: []const u8 = blk: {
            if (state.cell_store) |cs| {
                if (e.manifest_cell_hash) |h| {
                    if (cs.getAnchorStatus(&h)) |st| break :blk switch (st) {
                        .pending => "pending",
                        .confirmed => "confirmed",
                    };
                }
            }
            break :blk "none";
        };
        body.appendSlice(allocator, ",\"anchorStatus\":\"") catch return DispatchError.out_of_memory;
        body.appendSlice(allocator, anchor_status) catch return DispatchError.out_of_memory;
        body.appendSlice(allocator, "\",\"seeders\":[") catch return DispatchError.out_of_memory;
        for (e.seeders.items, 0..) |s, i| {
            if (i != 0) body.append(allocator, ',') catch return DispatchError.out_of_memory;
            body.appendSlice(allocator, "{\"address\":") catch return DispatchError.out_of_memory;
            appendJsonString(allocator, &body, s.address) catch return DispatchError.out_of_memory;
            body.appendSlice(allocator, ",\"bitfield\":") catch return DispatchError.out_of_memory;
            appendJsonString(allocator, &body, s.bitfield_hex) catch return DispatchError.out_of_memory;
            const tail = std.fmt.allocPrint(allocator, ",\"lastSeen\":{d}}}", .{s.last_seen}) catch return DispatchError.out_of_memory;
            defer allocator.free(tail);
            body.appendSlice(allocator, tail) catch return DispatchError.out_of_memory;
        }
        body.appendSlice(allocator, "]}") catch return DispatchError.out_of_memory;
    } else {
        body.appendSlice(allocator, "{\"manifestKnown\":false,\"seeders\":[]}") catch return DispatchError.out_of_memory;
    }
    return body.toOwnedSlice(allocator) catch DispatchError.out_of_memory;
}

fn announceWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    const parsed = try parseObject(allocator, params_json);
    defer parsed.deinit();
    const obj = parsed.value.object;
    const infohash = getStr(obj, "infohash") orelse return DispatchError.invalid_params;
    const address = getStr(obj, "address") orelse return DispatchError.invalid_params;
    const bitfield_hex = getStr(obj, "bitfieldHex") orelse "";

    state.tracker.announce(infohash, address, bitfield_hex, state.clock_fn()) catch return DispatchError.out_of_memory;
    return allocator.dupe(u8, "{\"ok\":true}") catch DispatchError.out_of_memory;
}

fn settleWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    const parsed = try parseObject(allocator, params_json);
    defer parsed.deinit();
    const obj = parsed.value.object;
    const infohash = getStr(obj, "infohash") orelse return DispatchError.invalid_params;

    var n: u32 = 0;
    if (obj.get("receipts")) |v| {
        if (v == .array) n = @intCast(v.array.items.len);
    }
    const recorded = state.tracker.recordReceipts(infohash, n);

    // M6 — mint a swarm.receipt ledger cell committing this settled batch.
    if (state.cell_store) |cs| {
        if (recorded > 0) {
            const cell = swarm_manifest.buildReceiptCell(allocator, infohash, recorded) catch return DispatchError.out_of_memory;
            _ = cs.put(&cell) catch return DispatchError.out_of_memory;
        }
    }
    return std.fmt.allocPrint(allocator, "{{\"recorded\":{d}}}", .{recorded}) catch DispatchError.out_of_memory;
}

// ── registration ────────────────────────────────────────────────────────────────

/// Register the four cold-path control verbs under `extension_id`. The same
/// State backs every namespace, so exposing both "swarm" (legacy) and
/// "transfer" (the canonical data-plane primitive) shares ONE tracker — no
/// forked control plane.
pub fn registerAllAs(reg: *verb_dispatcher.Registry, state: *State, extension_id: []const u8) !void {
    try reg.register(.{ .extension_id = extension_id, .verb = "publish", .walker_fn = publishWalker, .ctx = @ptrCast(state) });
    try reg.register(.{ .extension_id = extension_id, .verb = "locate", .walker_fn = locateWalker, .ctx = @ptrCast(state) });
    try reg.register(.{ .extension_id = extension_id, .verb = "announce", .walker_fn = announceWalker, .ctx = @ptrCast(state) });
    try reg.register(.{ .extension_id = extension_id, .verb = "settle", .walker_fn = settleWalker, .ctx = @ptrCast(state) });
}

/// Legacy alias — registers the verbs under "swarm".
pub fn registerAll(reg: *verb_dispatcher.Registry, state: *State) !void {
    try registerAllAs(reg, state, "swarm");
}

// ─── Tests ───────────────────────────────────────────────────────────────────

const testing = std.testing;

fn testClock() i64 {
    return 1_700_000;
}

test "publish then locate via walkers returns the manifest + seeders" {
    var tr = tracker_mod.Tracker.init(testing.allocator);
    defer tr.deinit();
    var st = State{ .tracker = &tr, .clock_fn = testClock };

    const pub_res = try publishWalker(testing.allocator, &st, "{\"infohash\":\"aa\",\"manifestCellHex\":\"deadbeef\",\"semanticPath\":\"media/clip\"}");
    defer testing.allocator.free(pub_res);
    try testing.expect(std.mem.indexOf(u8, pub_res, "\"stored\":true") != null);
    try testing.expect(std.mem.indexOf(u8, pub_res, "\"anchorStatus\":\"unanchored\"") != null);

    const ann_res = try announceWalker(testing.allocator, &st, "{\"infohash\":\"aa\",\"address\":\"fe80::1\",\"bitfieldHex\":\"ff\"}");
    defer testing.allocator.free(ann_res);
    try testing.expect(std.mem.indexOf(u8, ann_res, "\"ok\":true") != null);

    const loc_res = try locateWalker(testing.allocator, &st, "{\"infohash\":\"aa\"}");
    defer testing.allocator.free(loc_res);
    try testing.expect(std.mem.indexOf(u8, loc_res, "\"manifestKnown\":true") != null);
    try testing.expect(std.mem.indexOf(u8, loc_res, "\"manifestCellHex\":\"deadbeef\"") != null);
    try testing.expect(std.mem.indexOf(u8, loc_res, "\"address\":\"fe80::1\"") != null);
    try testing.expect(std.mem.indexOf(u8, loc_res, "\"lastSeen\":1700000") != null);
}

test "locate an unknown infohash" {
    var tr = tracker_mod.Tracker.init(testing.allocator);
    defer tr.deinit();
    var st = State{ .tracker = &tr, .clock_fn = testClock };
    const res = try locateWalker(testing.allocator, &st, "{\"infohash\":\"zz\"}");
    defer testing.allocator.free(res);
    try testing.expect(std.mem.indexOf(u8, res, "\"manifestKnown\":false") != null);
}

test "settle records one receipt per array element" {
    var tr = tracker_mod.Tracker.init(testing.allocator);
    defer tr.deinit();
    var st = State{ .tracker = &tr, .clock_fn = testClock };
    const pub_res = try publishWalker(testing.allocator, &st, "{\"infohash\":\"aa\",\"manifestCellHex\":\"00\",\"semanticPath\":\"p\"}");
    testing.allocator.free(pub_res);
    const settle_res = try settleWalker(testing.allocator, &st, "{\"infohash\":\"aa\",\"receipts\":[{\"cellIndex\":0},{\"cellIndex\":1},{\"cellIndex\":2}]}");
    defer testing.allocator.free(settle_res);
    try testing.expect(std.mem.indexOf(u8, settle_res, "\"recorded\":3") != null);
    try testing.expectEqual(@as(u32, 3), tr.locate("aa").?.receipts_count);
}

test "malformed params are rejected" {
    var tr = tracker_mod.Tracker.init(testing.allocator);
    defer tr.deinit();
    var st = State{ .tracker = &tr, .clock_fn = testClock };
    try testing.expectError(DispatchError.invalid_params, publishWalker(testing.allocator, &st, "not json"));
    try testing.expectError(DispatchError.invalid_params, publishWalker(testing.allocator, &st, "{\"infohash\":\"aa\"}")); // missing manifestCellHex
    try testing.expectError(DispatchError.invalid_params, locateWalker(testing.allocator, &st, "[]"));
}

test "registerAll wires all four verbs" {
    var tr = tracker_mod.Tracker.init(testing.allocator);
    defer tr.deinit();
    var st = State{ .tracker = &tr, .clock_fn = testClock };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &st);
    try testing.expect(reg.hasExtension("swarm"));
    const res = try reg.dispatch(testing.allocator, "swarm", "publish", "{\"infohash\":\"aa\",\"manifestCellHex\":\"00\",\"semanticPath\":\"p\"}");
    defer testing.allocator.free(res);
    try testing.expect(std.mem.indexOf(u8, res, "\"stored\":true") != null);
}

test "transfer.* namespace shares the same tracker as swarm.*" {
    var tr = tracker_mod.Tracker.init(testing.allocator);
    defer tr.deinit();
    var st = State{ .tracker = &tr, .clock_fn = testClock };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAllAs(&reg, &st, "swarm");
    try registerAllAs(&reg, &st, "transfer");
    try testing.expect(reg.hasExtension("transfer"));

    // Publish via transfer.* …
    const pub_res = try reg.dispatch(testing.allocator, "transfer", "publish", "{\"infohash\":\"bb\",\"manifestCellHex\":\"deadbeef\",\"semanticPath\":\"p\"}");
    testing.allocator.free(pub_res);
    // … and locate the SAME entry via legacy swarm.* (one shared tracker).
    const loc_res = try reg.dispatch(testing.allocator, "swarm", "locate", "{\"infohash\":\"bb\"}");
    defer testing.allocator.free(loc_res);
    try testing.expect(std.mem.indexOf(u8, loc_res, "\"manifestKnown\":true") != null);
    try testing.expect(std.mem.indexOf(u8, loc_res, "\"manifestCellHex\":\"deadbeef\"") != null);
}

```
