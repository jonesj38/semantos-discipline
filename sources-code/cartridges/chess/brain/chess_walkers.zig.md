---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/brain/chess_walkers.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.424241+00:00
---

# cartridges/chess/brain/chess_walkers.zig

```zig
// chess_walkers — the brain-side write-seam handlers for the chess
// doubling-cube cartridge's action verbs.
//
// Reference:
//   docs/design/CHESS-DOUBLING-CUBE.md §8 (cartridge shape)
//   docs/CHESS-DOUBLING-CUBE-TRACKING.md §1 Phase 1
//   runtime/semantos-brain/src/verb_dispatcher.zig (the WalkerFn contract)
//   cartridges/jambox/brain/jambox_walkers.zig (the walker pattern this
//     follows — parse params, mutate the typed store, return a typed
//     JSON result; registerAll wires every verb at brain boot)
//
// Status — Phase 1 (no money):
//
//   The seven verbs (create_game, join_game, submit_move, offer_double,
//   accept_double, decline_double, resolve) parse their JSON params and
//   drive chess_game_store — the authoritative LINEAR cube / clock /
//   forfeit state machine. NO stake cells are minted (tracker Phase 2).
//
//   Domain refusals (illegal move, not your turn, cube not yours, …)
//   are returned as a 200 result body `{ok:false,reason:…}` rather than
//   a dispatch error: an illegal move is normal game flow, not an RPC
//   fault, and the field shell renders the reason directly. Only
//   malformed params map to DispatchError.invalid_params; OOM maps to
//   out_of_memory.
//
//   Module wiring (serve.zig @import name + build.zig root_source_file,
//   the jambox-style clean pair with chess_engine/chess_game_store) is
//   the remaining Phase-1 integration item — see tracker §1.

const std = @import("std");
const verb_dispatcher = @import("verb_dispatcher");
const store_mod = @import("chess_game_store");
const engine = @import("chess_engine");

pub const Store = store_mod.Store;

/// Shared walker state. Holds the chess game store (which owns its own
/// deterministic clock). cli.zig/serve.zig constructs the store at boot
/// and passes &State here, exactly as jambox passes its State.
pub const State = struct {
    store: *Store,
};

// ─── JSON helpers ────────────────────────────────────────────────────

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    try out.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            else => try out.append(allocator, c),
        }
    }
    try out.append(allocator, '"');
}

fn reqStr(obj: std.json.ObjectMap, key: []const u8) verb_dispatcher.DispatchError![]const u8 {
    const v = obj.get(key) orelse return verb_dispatcher.DispatchError.invalid_params;
    if (v != .string or v.string.len == 0) return verb_dispatcher.DispatchError.invalid_params;
    return v.string;
}

fn parseObj(allocator: std.mem.Allocator, params_json: []const u8) verb_dispatcher.DispatchError!std.json.Parsed(std.json.Value) {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch {
        return verb_dispatcher.DispatchError.invalid_params;
    };
    if (parsed.value != .object) {
        parsed.deinit();
        return verb_dispatcher.DispatchError.invalid_params;
    }
    return parsed;
}

fn rejectionBody(allocator: std.mem.Allocator, reason: []const u8) verb_dispatcher.DispatchError![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"ok\":false,\"reason\":\"{s}\"}}", .{reason}) catch
        verb_dispatcher.DispatchError.out_of_memory;
}

fn mapStoreErr(e: store_mod.StoreError) verb_dispatcher.DispatchError {
    return switch (e) {
        store_mod.StoreError.invalid_id => verb_dispatcher.DispatchError.invalid_params,
        store_mod.StoreError.out_of_memory => verb_dispatcher.DispatchError.out_of_memory,
        store_mod.StoreError.escrow_failed => verb_dispatcher.DispatchError.walker_failed,
    };
}

fn colorName(c: store_mod.Color) []const u8 {
    return if (c == .white) "white" else "black";
}

/// Serialize the full game record. The field shell / world-app renders
/// the board from `fen`, the cube from `multiplier`/`cubeOwner`, and the
/// clocks from `whiteMs`/`blackMs`.
fn gameJson(allocator: std.mem.Allocator, g: *const store_mod.Game) verb_dispatcher.DispatchError![]u8 {
    var b: std.ArrayList(u8) = .{};
    errdefer b.deinit(allocator);
    const w = struct {
        fn s(a: std.mem.Allocator, o: *std.ArrayList(u8), str: []const u8) verb_dispatcher.DispatchError!void {
            appendJsonString(a, o, str) catch return verb_dispatcher.DispatchError.out_of_memory;
        }
        fn raw(a: std.mem.Allocator, o: *std.ArrayList(u8), str: []const u8) verb_dispatcher.DispatchError!void {
            o.appendSlice(a, str) catch return verb_dispatcher.DispatchError.out_of_memory;
        }
    };

    try w.raw(allocator, &b, "{\"ok\":true,\"gameId\":");
    try w.s(allocator, &b, g.id);
    try w.raw(allocator, &b, ",\"status\":");
    try w.s(allocator, &b, @tagName(g.status));
    try w.raw(allocator, &b, ",\"endReason\":");
    try w.s(allocator, &b, @tagName(g.end_reason));
    try w.raw(allocator, &b, ",\"winner\":");
    if (g.winner) |wc| try w.s(allocator, &b, colorName(wc)) else try w.raw(allocator, &b, "null");
    try w.raw(allocator, &b, ",\"fen\":");
    try w.s(allocator, &b, g.fen);
    try w.raw(allocator, &b, ",\"white\":");
    try w.s(allocator, &b, g.white);
    try w.raw(allocator, &b, ",\"black\":");
    try w.s(allocator, &b, g.black);

    const tail = std.fmt.allocPrint(allocator, ",\"stakeSats\":{d},\"multiplier\":{d},\"cubeOwner\":{s},\"whiteMs\":{d},\"blackMs\":{d},\"running\":{s}", .{
        g.stake_sats,
        g.multiplier,
        if (g.cube_owner) |co| (if (co == .white) "\"white\"" else "\"black\"") else "null",
        g.white_ms,
        g.black_ms,
        if (g.running) |rc| (if (rc == .white) "\"white\"" else "\"black\"") else "null",
    }) catch return verb_dispatcher.DispatchError.out_of_memory;
    defer allocator.free(tail);
    try w.raw(allocator, &b, tail);

    if (g.pending) |p| {
        const pj = std.fmt.allocPrint(allocator, ",\"pending\":{{\"offerer\":\"{s}\",\"levelBefore\":{d},\"levelAfter\":{d}}}", .{ colorName(p.offerer), p.level_before, p.level_after }) catch return verb_dispatcher.DispatchError.out_of_memory;
        defer allocator.free(pj);
        try w.raw(allocator, &b, pj);
    } else {
        try w.raw(allocator, &b, ",\"pending\":null");
    }
    try w.raw(allocator, &b, "}");
    return b.toOwnedSlice(allocator) catch verb_dispatcher.DispatchError.out_of_memory;
}

/// After a successful mutating verb, return the fresh game record.
fn okGame(allocator: std.mem.Allocator, store: *Store, game_id: []const u8) verb_dispatcher.DispatchError![]u8 {
    const g = store.get(game_id) orelse return rejectionBody(allocator, "game_not_found");
    return gameJson(allocator, &g);
}

// ─── Walkers ─────────────────────────────────────────────────────────

pub fn createGameWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    var parsed = try parseObj(allocator, params_json);
    defer parsed.deinit();
    const obj = parsed.value.object;

    const game_id = try reqStr(obj, "gameId");
    const creator = try reqStr(obj, "creator");
    const color_s = try reqStr(obj, "color");
    const color: store_mod.Color = if (std.mem.eql(u8, color_s, "white")) .white else if (std.mem.eql(u8, color_s, "black")) .black else return verb_dispatcher.DispatchError.invalid_params;

    const stake_v = obj.get("stakeSats") orelse return verb_dispatcher.DispatchError.invalid_params;
    if (stake_v != .integer or stake_v.integer < 0) return verb_dispatcher.DispatchError.invalid_params;
    const clock_v = obj.get("clockMs") orelse return verb_dispatcher.DispatchError.invalid_params;
    if (clock_v != .integer or clock_v.integer <= 0) return verb_dispatcher.DispatchError.invalid_params;

    state.store.createGame(game_id, creator, color, @intCast(stake_v.integer), clock_v.integer) catch |e| return mapStoreErr(e);
    return okGame(allocator, state.store, game_id);
}

fn twoArgVerb(
    allocator: std.mem.Allocator,
    state: *State,
    params_json: []const u8,
    comptime call: fn (*Store, []const u8, []const u8) store_mod.StoreError!?store_mod.Rejection,
) verb_dispatcher.DispatchError![]u8 {
    var parsed = try parseObj(allocator, params_json);
    defer parsed.deinit();
    const obj = parsed.value.object;
    const game_id = try reqStr(obj, "gameId");
    const player = try reqStr(obj, "player");
    const rej = call(state.store, game_id, player) catch |e| return mapStoreErr(e);
    if (rej) |r| return rejectionBody(allocator, @tagName(r));
    return okGame(allocator, state.store, game_id);
}

pub fn joinGameWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    var parsed = try parseObj(allocator, params_json);
    defer parsed.deinit();
    const obj = parsed.value.object;
    const game_id = try reqStr(obj, "gameId");
    const joiner = try reqStr(obj, "joiner");
    const rej = state.store.joinGame(game_id, joiner) catch |e| return mapStoreErr(e);
    if (rej) |r| return rejectionBody(allocator, @tagName(r));
    return okGame(allocator, state.store, game_id);
}

pub fn submitMoveWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    var parsed = try parseObj(allocator, params_json);
    defer parsed.deinit();
    const obj = parsed.value.object;
    const game_id = try reqStr(obj, "gameId");
    const player = try reqStr(obj, "player");
    const uci = try reqStr(obj, "uci");
    const rej = state.store.submitMove(game_id, player, uci) catch |e| return mapStoreErr(e);
    if (rej) |r| return rejectionBody(allocator, @tagName(r));
    return okGame(allocator, state.store, game_id);
}

pub fn offerDoubleWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    return twoArgVerb(allocator, state, params_json, Store.offerDouble);
}

pub fn acceptDoubleWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    return twoArgVerb(allocator, state, params_json, Store.acceptDouble);
}

pub fn declineDoubleWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    return twoArgVerb(allocator, state, params_json, Store.declineDouble);
}

/// Creator cancels a never-joined game (status=waiting only). Phase-2
/// refunds the base stake to the creator; Phase-1 just marks
/// status=cancelled. Returns `not_a_player` if called by a non-creator,
/// `game_not_waiting` if joined / finished.
pub fn cancelGameWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    return twoArgVerb(allocator, state, params_json, Store.cancelGame);
}

/// Player resigns mid-game. Opponent wins immediately. Returns
/// `not_a_player` if the caller isn't one of the two players,
/// `game_not_active` if the game is waiting or already finished.
pub fn resignGameWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    return twoArgVerb(allocator, state, params_json, Store.resignGame);
}

pub fn resolveWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    var parsed = try parseObj(allocator, params_json);
    defer parsed.deinit();
    const obj = parsed.value.object;
    const game_id = try reqStr(obj, "gameId");
    const res = state.store.resolve(game_id);
    return switch (res) {
        .rejected => |r| rejectionBody(allocator, @tagName(r)),
        .game => |g| gameJson(allocator, &g),
    };
}

/// Returns the legal moves from the game's current FEN as a UCI string
/// array. Pure read — does not touch state at all. Used by the world-app
/// to highlight legal destinations when a player picks up a piece, so
/// the UI doesn't need a second engine and the server stays the single
/// source of legality.
pub fn listLegalMovesWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    var parsed = try parseObj(allocator, params_json);
    defer parsed.deinit();
    const obj = parsed.value.object;
    const game_id = try reqStr(obj, "gameId");

    const g = state.store.get(game_id) orelse return rejectionBody(allocator, "game_not_found");

    var board = engine.Board.fromFen(g.fen) catch return rejectionBody(allocator, "bad_fen");
    var moves = engine.MoveList{};
    board.legalMoves(&moves);

    var b = std.ArrayList(u8){};
    defer b.deinit(allocator);
    b.appendSlice(allocator, "{\"ok\":true,\"moves\":[") catch return verb_dispatcher.DispatchError.out_of_memory;
    var first = true;
    var ubuf: [5]u8 = undefined;
    for (moves.slice()) |m| {
        const uci = engine.Board.moveToUci(m, &ubuf);
        if (!first) b.append(allocator, ',') catch return verb_dispatcher.DispatchError.out_of_memory;
        first = false;
        b.append(allocator, '"') catch return verb_dispatcher.DispatchError.out_of_memory;
        b.appendSlice(allocator, uci) catch return verb_dispatcher.DispatchError.out_of_memory;
        b.append(allocator, '"') catch return verb_dispatcher.DispatchError.out_of_memory;
    }
    b.appendSlice(allocator, "]}") catch return verb_dispatcher.DispatchError.out_of_memory;
    return b.toOwnedSlice(allocator) catch verb_dispatcher.DispatchError.out_of_memory;
}

/// Read the game with clocks settled — used by the world-app's relay tick
/// to refresh state when the other side signals activity. "Read-only" in
/// the sense that no game-logic mutation happens here (no FEN change, no
/// cube transition, no escrow side-effect); the one allowed update is a
/// flag-out that already happened in wall time but hadn't been observed
/// yet. Without this, poll-driven displays would lag the clock authority.
pub fn getGameWalker(allocator: std.mem.Allocator, ctx: *anyopaque, params_json: []const u8) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));
    var parsed = try parseObj(allocator, params_json);
    defer parsed.deinit();
    const obj = parsed.value.object;
    const game_id = try reqStr(obj, "gameId");
    const g = state.store.getSettled(game_id) orelse return rejectionBody(allocator, "game_not_found");
    return gameJson(allocator, &g);
}

// ─── Registration ────────────────────────────────────────────────────

pub fn registerAll(registry: *verb_dispatcher.Registry, state: *State) !void {
    const V = struct { name: []const u8, f: verb_dispatcher.WalkerFn };
    const verbs = [_]V{
        .{ .name = "create_game", .f = createGameWalker },
        .{ .name = "join_game", .f = joinGameWalker },
        .{ .name = "submit_move", .f = submitMoveWalker },
        .{ .name = "offer_double", .f = offerDoubleWalker },
        .{ .name = "accept_double", .f = acceptDoubleWalker },
        .{ .name = "decline_double", .f = declineDoubleWalker },
        .{ .name = "resolve", .f = resolveWalker },
        .{ .name = "get_game", .f = getGameWalker },
        .{ .name = "list_legal_moves", .f = listLegalMovesWalker },
        .{ .name = "cancel_game", .f = cancelGameWalker },
        .{ .name = "resign_game", .f = resignGameWalker },
    };
    for (verbs) |v| {
        try registry.register(.{
            .extension_id = "chess",
            .verb = v.name,
            .walker_fn = v.f,
            .ctx = @ptrCast(state),
        });
    }
}

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

var test_now_ms: i64 = 1_000_000;
fn testClock() i64 {
    return test_now_ms;
}

fn contains(h: []const u8, n: []const u8) bool {
    return std.mem.indexOf(u8, h, n) != null;
}

test "registerAll registers all 11 chess verbs" {
    var store = Store.init(testing.allocator, testClock);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    try testing.expectEqual(@as(usize, 11), reg.count());
    try testing.expect(reg.hasExtension("chess"));
}

test "full game flow through the dispatcher: create → join → mate" {
    test_now_ms = 1_000_000;
    var store = Store.init(testing.allocator, testClock);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);

    const c = try reg.dispatch(testing.allocator, "chess", "create_game", "{\"gameId\":\"x\",\"creator\":\"alice\",\"color\":\"white\",\"stakeSats\":100,\"clockMs\":600000}");
    defer testing.allocator.free(c);
    try testing.expect(contains(c, "\"status\":\"waiting\""));

    const j = try reg.dispatch(testing.allocator, "chess", "join_game", "{\"gameId\":\"x\",\"joiner\":\"bob\"}");
    defer testing.allocator.free(j);
    try testing.expect(contains(j, "\"status\":\"active\""));

    const moves = [_][]const u8{
        "{\"gameId\":\"x\",\"player\":\"alice\",\"uci\":\"f2f3\"}",
        "{\"gameId\":\"x\",\"player\":\"bob\",\"uci\":\"e7e5\"}",
        "{\"gameId\":\"x\",\"player\":\"alice\",\"uci\":\"g2g4\"}",
        "{\"gameId\":\"x\",\"player\":\"bob\",\"uci\":\"d8h4\"}",
    };
    for (moves) |mp| {
        const r = try reg.dispatch(testing.allocator, "chess", "submit_move", mp);
        testing.allocator.free(r);
    }
    const fin = try reg.dispatch(testing.allocator, "chess", "resolve", "{\"gameId\":\"x\"}");
    defer testing.allocator.free(fin);
    try testing.expect(contains(fin, "\"status\":\"black_won\""));
    try testing.expect(contains(fin, "\"endReason\":\"checkmate\""));
}

test "get_game is read-only — does not advance state and 404s unknown ids" {
    test_now_ms = 1_000_000;
    var store = Store.init(testing.allocator, testClock);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);

    // Unknown game id reports the same shape as other rejections.
    {
        const r = try reg.dispatch(testing.allocator, "chess", "get_game", "{\"gameId\":\"nope\"}");
        defer testing.allocator.free(r);
        try testing.expect(contains(r, "\"reason\":\"game_not_found\""));
    }

    {
        const c = try reg.dispatch(testing.allocator, "chess", "create_game", "{\"gameId\":\"g1\",\"creator\":\"alice\",\"color\":\"white\",\"stakeSats\":7,\"clockMs\":600000}");
        testing.allocator.free(c);
    }

    // Snapshot of the waiting-game state.
    const snap1_buf = try reg.dispatch(testing.allocator, "chess", "get_game", "{\"gameId\":\"g1\"}");
    defer testing.allocator.free(snap1_buf);
    try testing.expect(contains(snap1_buf, "\"status\":\"waiting\""));
    try testing.expect(contains(snap1_buf, "\"multiplier\":1"));

    // Waiting status has no running clock — advancing wall time must
    // leave the snapshot stable.
    test_now_ms += 60_000;
    const snap2_buf = try reg.dispatch(testing.allocator, "chess", "get_game", "{\"gameId\":\"g1\"}");
    defer testing.allocator.free(snap2_buf);
    try testing.expect(contains(snap2_buf, "\"status\":\"waiting\""));
}

test "list_legal_moves returns 20 UCI strings from the starting position" {
    test_now_ms = 1_000_000;
    var store = Store.init(testing.allocator, testClock);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);

    // Unknown game id reports game_not_found like other reads.
    {
        const r = try reg.dispatch(testing.allocator, "chess", "list_legal_moves", "{\"gameId\":\"nope\"}");
        defer testing.allocator.free(r);
        try testing.expect(contains(r, "\"reason\":\"game_not_found\""));
    }

    {
        const c = try reg.dispatch(testing.allocator, "chess", "create_game", "{\"gameId\":\"lm\",\"creator\":\"alice\",\"color\":\"white\",\"stakeSats\":1,\"clockMs\":600000}");
        testing.allocator.free(c);
    }

    const list_buf = try reg.dispatch(testing.allocator, "chess", "list_legal_moves", "{\"gameId\":\"lm\"}");
    defer testing.allocator.free(list_buf);
    // Starting position has 20 legal moves (16 pawn pushes + 4 knight moves).
    // Quick smoke: assert a few known-good UCIs are present + assert exactly
    // 20 quoted strings inside the moves array.
    try testing.expect(contains(list_buf, "\"e2e4\""));
    try testing.expect(contains(list_buf, "\"g1f3\""));
    try testing.expect(contains(list_buf, "\"a2a3\""));
    var i: usize = 0;
    var quote_count: usize = 0;
    while (i < list_buf.len) : (i += 1) if (list_buf[i] == '"') { quote_count += 1; };
    // 4 quotes for "ok", "moves", plus 2 per UCI. 4 + 40 = 44.
    try testing.expectEqual(@as(usize, 44), quote_count);
}

test "cancel_game: creator cancels a never-joined game" {
    test_now_ms = 1_000_000;
    var store = Store.init(testing.allocator, testClock);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);

    {
        const c = try reg.dispatch(testing.allocator, "chess", "create_game", "{\"gameId\":\"c1\",\"creator\":\"alice\",\"color\":\"white\",\"stakeSats\":1,\"clockMs\":600000}");
        testing.allocator.free(c);
    }
    // Non-creator can't cancel.
    {
        const r = try reg.dispatch(testing.allocator, "chess", "cancel_game", "{\"gameId\":\"c1\",\"player\":\"mallory\"}");
        defer testing.allocator.free(r);
        try testing.expect(contains(r, "\"reason\":\"not_a_player\""));
    }
    // Creator cancels — status flips to cancelled.
    {
        const r = try reg.dispatch(testing.allocator, "chess", "cancel_game", "{\"gameId\":\"c1\",\"player\":\"alice\"}");
        defer testing.allocator.free(r);
        try testing.expect(contains(r, "\"status\":\"cancelled\""));
        try testing.expect(contains(r, "\"endReason\":\"cancelled\""));
    }
    // Re-cancel after cancelled → game_not_waiting.
    {
        const r = try reg.dispatch(testing.allocator, "chess", "cancel_game", "{\"gameId\":\"c1\",\"player\":\"alice\"}");
        defer testing.allocator.free(r);
        try testing.expect(contains(r, "\"reason\":\"game_not_waiting\""));
    }
}

test "cancel_game: can't cancel after join" {
    test_now_ms = 1_000_000;
    var store = Store.init(testing.allocator, testClock);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    {
        const c = try reg.dispatch(testing.allocator, "chess", "create_game", "{\"gameId\":\"c2\",\"creator\":\"alice\",\"color\":\"white\",\"stakeSats\":1,\"clockMs\":600000}");
        testing.allocator.free(c);
    }
    {
        const j = try reg.dispatch(testing.allocator, "chess", "join_game", "{\"gameId\":\"c2\",\"joiner\":\"bob\"}");
        testing.allocator.free(j);
    }
    const r = try reg.dispatch(testing.allocator, "chess", "cancel_game", "{\"gameId\":\"c2\",\"player\":\"alice\"}");
    defer testing.allocator.free(r);
    try testing.expect(contains(r, "\"reason\":\"game_not_waiting\""));
}

test "resign_game: white resigns → black wins with end_reason=resign" {
    test_now_ms = 1_000_000;
    var store = Store.init(testing.allocator, testClock);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    {
        const c = try reg.dispatch(testing.allocator, "chess", "create_game", "{\"gameId\":\"r1\",\"creator\":\"alice\",\"color\":\"white\",\"stakeSats\":1,\"clockMs\":600000}");
        testing.allocator.free(c);
    }
    {
        const j = try reg.dispatch(testing.allocator, "chess", "join_game", "{\"gameId\":\"r1\",\"joiner\":\"bob\"}");
        testing.allocator.free(j);
    }
    const r = try reg.dispatch(testing.allocator, "chess", "resign_game", "{\"gameId\":\"r1\",\"player\":\"alice\"}");
    defer testing.allocator.free(r);
    try testing.expect(contains(r, "\"status\":\"black_won\""));
    try testing.expect(contains(r, "\"endReason\":\"resign\""));
    try testing.expect(contains(r, "\"winner\":\"black\""));
}

test "resign_game: rejection paths — not_a_player, game_not_active" {
    test_now_ms = 1_000_000;
    var store = Store.init(testing.allocator, testClock);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);

    // Waiting game — can't resign before opponent joins.
    {
        const c = try reg.dispatch(testing.allocator, "chess", "create_game", "{\"gameId\":\"r2\",\"creator\":\"alice\",\"color\":\"white\",\"stakeSats\":1,\"clockMs\":600000}");
        testing.allocator.free(c);
    }
    {
        const r = try reg.dispatch(testing.allocator, "chess", "resign_game", "{\"gameId\":\"r2\",\"player\":\"alice\"}");
        defer testing.allocator.free(r);
        try testing.expect(contains(r, "\"reason\":\"game_not_active\""));
    }
    {
        const j = try reg.dispatch(testing.allocator, "chess", "join_game", "{\"gameId\":\"r2\",\"joiner\":\"bob\"}");
        testing.allocator.free(j);
    }
    // Non-player can't resign someone else's game.
    {
        const r = try reg.dispatch(testing.allocator, "chess", "resign_game", "{\"gameId\":\"r2\",\"player\":\"mallory\"}");
        defer testing.allocator.free(r);
        try testing.expect(contains(r, "\"reason\":\"not_a_player\""));
    }
    // Real resign goes through.
    {
        const r = try reg.dispatch(testing.allocator, "chess", "resign_game", "{\"gameId\":\"r2\",\"player\":\"bob\"}");
        testing.allocator.free(r);
    }
    // Already-terminal game — can't resign again.
    {
        const r = try reg.dispatch(testing.allocator, "chess", "resign_game", "{\"gameId\":\"r2\",\"player\":\"alice\"}");
        defer testing.allocator.free(r);
        try testing.expect(contains(r, "\"reason\":\"game_not_active\""));
    }
}

test "get_game observes a wall-time flag-out — poll is the clock heartbeat" {
    test_now_ms = 1_000_000;
    var store = Store.init(testing.allocator, testClock);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);

    // Short clock so we can flag without millions of ms.
    {
        const c = try reg.dispatch(testing.allocator, "chess", "create_game", "{\"gameId\":\"t\",\"creator\":\"w\",\"color\":\"white\",\"stakeSats\":1,\"clockMs\":5000}");
        testing.allocator.free(c);
    }
    {
        const j = try reg.dispatch(testing.allocator, "chess", "join_game", "{\"gameId\":\"t\",\"joiner\":\"b\"}");
        testing.allocator.free(j);
    }

    // White's clock is running. A read mid-clock must still show active.
    test_now_ms += 2_000;
    const mid_buf = try reg.dispatch(testing.allocator, "chess", "get_game", "{\"gameId\":\"t\"}");
    defer testing.allocator.free(mid_buf);
    try testing.expect(contains(mid_buf, "\"status\":\"active\""));

    // Push past white's clock budget — get_game must observe the flag-out
    // without any further verb call. This is the poll-as-heartbeat path
    // the world-app relies on to mark a flagged game finished on the
    // opponent's screen even if the opponent never moves.
    test_now_ms += 10_000;
    const flag_buf = try reg.dispatch(testing.allocator, "chess", "get_game", "{\"gameId\":\"t\"}");
    defer testing.allocator.free(flag_buf);
    try testing.expect(contains(flag_buf, "\"winner\":\"black\""));
    try testing.expect(contains(flag_buf, "\"endReason\":\"timeout\""));
}

test "illegal move returns ok:false reason body, not a dispatch error" {
    test_now_ms = 1_000_000;
    var store = Store.init(testing.allocator, testClock);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    {
        const a = try reg.dispatch(testing.allocator, "chess", "create_game", "{\"gameId\":\"y\",\"creator\":\"w\",\"color\":\"white\",\"stakeSats\":1,\"clockMs\":600000}");
        testing.allocator.free(a);
    }
    {
        const j = try reg.dispatch(testing.allocator, "chess", "join_game", "{\"gameId\":\"y\",\"joiner\":\"b\"}");
        testing.allocator.free(j);
    }
    const r = try reg.dispatch(testing.allocator, "chess", "submit_move", "{\"gameId\":\"y\",\"player\":\"w\",\"uci\":\"e2e5\"}");
    defer testing.allocator.free(r);
    try testing.expect(contains(r, "\"ok\":false"));
    try testing.expect(contains(r, "\"reason\":\"illegal_move\""));
}

test "offer→accept doubling through the dispatcher" {
    test_now_ms = 1_000_000;
    var store = Store.init(testing.allocator, testClock);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    {
        const a = try reg.dispatch(testing.allocator, "chess", "create_game", "{\"gameId\":\"z\",\"creator\":\"w\",\"color\":\"white\",\"stakeSats\":50,\"clockMs\":600000}");
        testing.allocator.free(a);
    }
    {
        const a = try reg.dispatch(testing.allocator, "chess", "join_game", "{\"gameId\":\"z\",\"joiner\":\"b\"}");
        testing.allocator.free(a);
    }
    {
        const a = try reg.dispatch(testing.allocator, "chess", "offer_double", "{\"gameId\":\"z\",\"player\":\"w\"}");
        defer testing.allocator.free(a);
        try testing.expect(contains(a, "\"pending\":{\"offerer\":\"white\""));
    }
    const acc = try reg.dispatch(testing.allocator, "chess", "accept_double", "{\"gameId\":\"z\",\"player\":\"b\"}");
    defer testing.allocator.free(acc);
    try testing.expect(contains(acc, "\"multiplier\":2"));
    try testing.expect(contains(acc, "\"cubeOwner\":\"black\""));
    try testing.expect(contains(acc, "\"pending\":null"));
}

test "malformed params → invalid_params dispatch error" {
    var store = Store.init(testing.allocator, testClock);
    defer store.deinit();
    var state = State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        reg.dispatch(testing.allocator, "chess", "create_game", "{\"gameId\":\"q\"}"),
    );
}

```
