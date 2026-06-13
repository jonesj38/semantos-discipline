---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/brain/chess_game_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.425889+00:00
---

# cartridges/chess/brain/chess_game_store.zig

```zig
// chess_game_store — in-memory game-state tracker for the chess
// doubling-cube cartridge.
//
// Reference:
//   docs/design/CHESS-DOUBLING-CUBE.md §4 (cube state machine),
//     §5 (clock + fairness), §6 (coverage model)
//   docs/CHESS-DOUBLING-CUBE-TRACKING.md §1 Phase 1
//   cartridges/jambox/brain/jam_clip_state_store.zig (the store shape
//     this mirrors — init / mutate / get / count; LMDB-backed impl
//     follows the same API in Phase 2)
//
// Status — Phase 1 (no money):
//
//   This is the authoritative LINEAR cube / pending-double / per-player
//   clock state machine, backed by the in-cartridge chess_engine for
//   move legality and terminal verdicts. NO stake cells are minted or
//   anchored — `stake_sats` is recorded for the eventual Phase-2
//   anchor/consume wiring but nothing goes on-chain. The forfeit and
//   timeout rules are enforced here as state transitions; the LINEAR
//   guarantee they encode (a pending double cannot be dropped) is
//   modelled by there being no transition that leaves a pending double
//   un-resolved — every clock/decline path consumes it.
//
// Return convention:
//
//   Mutating verbs return `StoreError!?Rejection`. A real error
//   (StoreError) is OOM / bad input. A non-null Rejection is a
//   domain refusal the walker turns into {ok:false,reason:…}. `null`
//   means the verb succeeded. `resolve` returns the game record or a
//   Rejection via ResolveResult.

const std = @import("std");
const engine = @import("chess_engine");
const escrow_mod = @import("chess_escrow");

pub const Color = engine.Color;
pub const WalletPort = escrow_mod.WalletPort;

pub const StoreError = error{
    invalid_id,
    out_of_memory,
    escrow_failed, // wallet seam failed during create/join funding
};

/// Why a verb was refused. Walkers turn these into a structured JSON
/// `{ok:false,reason:...}` body.
pub const Rejection = enum {
    game_not_found,
    not_a_player,
    game_not_active,
    game_not_waiting,
    not_your_turn,
    illegal_move,
    double_pending, // can't move / can't re-offer while one is pending
    no_pending_double,
    not_the_responder,
    cube_not_yours, // centered cube is offerable; opponent-owned is not
    already_all_in,
    escrow_uncovered, // can't even all-in back the new level (design §6)
    escrow_failed, // wallet seam returned an error (anchor/pay/consume)
};

pub const Status = enum {
    waiting, // created, awaiting opponent join
    active,
    white_won,
    black_won,
    draw,
    cancelled, // creator cancelled a never-joined game (stake refunded)
};

pub const EndReason = enum {
    none,
    checkmate,
    stalemate,
    fifty_move,
    insufficient_material,
    threefold,
    decline_forfeit, // responder declined a double
    timeout, // a clock ran out
    timeout_pending, // clock ran out while a double was pending → offerer wins
    cancelled, // never-joined game cancelled by the creator
    resign, // player resigned mid-game; opponent wins
};

const Pending = struct {
    offerer: Color,
    level_before: u32,
    level_after: u32,
};

pub const Game = struct {
    id: []const u8,
    white: []const u8, // player identity (empty until joined for that side)
    black: []const u8,
    creator_color: Color,

    fen: []const u8, // current position (full FEN)
    status: Status = .waiting,
    end_reason: EndReason = .none,
    winner: ?Color = null,

    // ── Stake / cube (no money in Phase 1) ────────────────────────────
    stake_sats: u64, // base stake per side (recorded, not anchored)
    multiplier: u32 = 1, // doubling cube value (1,2,4,8,…)
    cube_owner: ?Color = null, // null = centered (either may offer)
    white_all_in: bool = false,
    black_all_in: bool = false,
    pending: ?Pending = null,

    // ── Phase-2 escrow (Path A; only driven when a WalletPort is
    //    attached — null ⇒ exact Phase-1 no-money behaviour) ──────────
    /// Total spendable per side (incl. base stake). Doubling headroom
    /// is `bankroll - escrow.committed`. Defaults set at create/join to
    /// the base stake (no headroom unless explicitly funded).
    white_bankroll: u64 = 0,
    black_bankroll: u64 = 0,
    escrow: ?escrow_mod.Escrow = null,

    // ── Clock (milliseconds remaining per side) ───────────────────────
    white_ms: i64,
    black_ms: i64,
    /// Whose clock is currently decrementing. null when not active or
    /// (transiently) settled. While a double is pending this is the
    /// RESPONDER — the offerer's clock is frozen (design §5).
    running: ?Color = null,
    last_settle_ms: i64,

    pub fn playerColor(self: *const Game, who: []const u8) ?Color {
        if (self.white.len > 0 and std.mem.eql(u8, self.white, who)) return .white;
        if (self.black.len > 0 and std.mem.eql(u8, self.black, who)) return .black;
        return null;
    }
};

pub const ResolveResult = union(enum) {
    rejected: Rejection,
    game: Game,
};

inline fn other(c: Color) Color {
    return if (c == .white) .black else .white;
}

/// engine.Color → escrow.Color (distinct nominal enums, identical
/// `enum(u1)` layout).
inline fn ecol(c: Color) escrow_mod.Color {
    return @enumFromInt(@intFromEnum(c));
}

pub const Store = struct {
    allocator: std.mem.Allocator,
    games: std.StringHashMap(Game),
    /// position-key → occurrence count, for threefold. Key is
    /// "<gameId>\x00<fen-first-4-fields>".
    reps: std.StringHashMap(u32),
    mu: std.Thread.Mutex,
    /// Unix milliseconds. Deterministic in tests.
    clock_fn: *const fn () i64,
    /// Phase-2 wallet seam. null ⇒ no money: escrow is never created,
    /// behaviour is byte-identical to Phase 1 (all P1 tests untouched).
    wallet: ?WalletPort = null,
    /// Initial pre-signed-settlement nLockTime horizon (design §12.3).
    /// Only its monotonic tightening matters to the pure ratchet; the
    /// absolute value is a game-creation parameter, not a constant.
    lock_horizon: u64 = 1_000_000,

    pub fn init(allocator: std.mem.Allocator, clock_fn: *const fn () i64) Store {
        return .{
            .allocator = allocator,
            .games = std.StringHashMap(Game).init(allocator),
            .reps = std.StringHashMap(u32).init(allocator),
            .mu = .{},
            .clock_fn = clock_fn,
        };
    }

    /// Attach the wallet seam (production wires the native C-ABI behind
    /// the detached submitter — design §12.6). Enables escrow on games
    /// created after this call.
    pub fn attachWallet(self: *Store, port: WalletPort) void {
        self.wallet = port;
    }

    /// Set a side's total spendable (incl. base stake) so the cube has
    /// doubling headroom. No-op for unknown game / unattached wallet.
    pub fn setBankroll(self: *Store, game_id: []const u8, color: Color, sats: u64) void {
        self.mu.lock();
        defer self.mu.unlock();
        const g = self.games.getPtr(game_id) orelse return;
        if (color == .white) g.white_bankroll = sats else g.black_bankroll = sats;
    }

    /// Spendable headroom a side can still commit (bankroll − committed).
    fn balanceOf(g: *const Game, c: Color) u64 {
        if (g.escrow) |e| {
            const bank = if (c == .white) g.white_bankroll else g.black_bankroll;
            const committed = if (c == .white) e.white.committed else e.black.committed;
            return if (bank > committed) bank - committed else 0;
        }
        return 0;
    }

    /// Map an escrow stake-cell path for (game, color, leg) into `buf`.
    fn anchorPath(buf: []u8, game_id: []const u8, c: Color, leg: []const u8) []const u8 {
        const cs = if (c == .white) "w" else "b";
        return std.fmt.bufPrint(buf, "{s}/stake/{s}/{s}", .{ game_id, cs, leg }) catch unreachable;
    }

    pub fn deinit(self: *Store) void {
        var it = self.games.iterator();
        while (it.next()) |e| {
            self.allocator.free(e.key_ptr.*);
            self.freeGame(e.value_ptr);
        }
        self.games.deinit();
        var rit = self.reps.iterator();
        while (rit.next()) |e| self.allocator.free(e.key_ptr.*);
        self.reps.deinit();
    }

    fn freeGame(self: *Store, g: *Game) void {
        self.allocator.free(g.id);
        if (g.white.len > 0) self.allocator.free(g.white);
        if (g.black.len > 0) self.allocator.free(g.black);
        self.allocator.free(g.fen);
    }

    pub fn count(self: *Store) usize {
        self.mu.lock();
        defer self.mu.unlock();
        return self.games.count();
    }

    pub fn get(self: *Store, game_id: []const u8) ?Game {
        self.mu.lock();
        defer self.mu.unlock();
        return self.games.get(game_id);
    }

    /// Read the game after bringing its clock current — observing any flag-
    /// out that already happened in wall time. The brain still doesn't tick
    /// games on its own (no separate timer thread), so without this every
    /// poll between two write-verbs would see a stale "active" status for
    /// a player whose clock already hit zero. With this, the world-app's
    /// every-tick get_game poll is the authoritative clock heartbeat.
    pub fn getSettled(self: *Store, game_id: []const u8) ?Game {
        self.mu.lock();
        defer self.mu.unlock();
        const g = self.games.getPtr(game_id) orelse return null;
        self.settle(g);
        return g.*;
    }

    // ── Position key / repetition ─────────────────────────────────────

    /// First 4 space-separated FEN fields (placement, stm, castling, ep)
    /// — the bits that define position identity for repetition.
    fn positionKey(fen: []const u8, buf: []u8) []const u8 {
        var spaces: u8 = 0;
        var n: usize = 0;
        for (fen) |ch| {
            if (ch == ' ') {
                spaces += 1;
                if (spaces == 4) break;
            }
            buf[n] = ch;
            n += 1;
        }
        return buf[0..n];
    }

    fn bumpRepetition(self: *Store, game_id: []const u8, fen: []const u8) StoreError!u32 {
        var pbuf: [100]u8 = undefined;
        const pk = positionKey(fen, &pbuf);
        var kbuf: [180]u8 = undefined;
        const key = std.fmt.bufPrint(&kbuf, "{s}\x00{s}", .{ game_id, pk }) catch return StoreError.out_of_memory;
        if (self.reps.getEntry(key)) |e| {
            e.value_ptr.* += 1;
            return e.value_ptr.*;
        }
        const owned = self.allocator.dupe(u8, key) catch return StoreError.out_of_memory;
        self.reps.put(owned, 1) catch {
            self.allocator.free(owned);
            return StoreError.out_of_memory;
        };
        return 1;
    }

    // ── Clock settlement ──────────────────────────────────────────────

    /// Deduct elapsed real time from whoever's clock is running. If a
    /// clock reaches zero this resolves the game per design §5:
    ///   • pending double, responder's clock (the only one running while
    ///     pending) → offerer wins (timeout_pending)
    ///   • otherwise the flagged side loses, opponent wins (timeout)
    fn settle(self: *Store, g: *Game) void {
        if (g.status != .active) return;
        const now = self.clock_fn();
        defer g.last_settle_ms = now;
        const run = g.running orelse return;
        const elapsed = now - g.last_settle_ms;
        if (elapsed <= 0) return;

        const clk = if (run == .white) &g.white_ms else &g.black_ms;
        clk.* -= elapsed;
        if (clk.* > 0) return;

        clk.* = 0;
        g.running = null;
        if (g.pending) |p| {
            // Only the responder's clock runs while pending, so a flag
            // here is the responder failing to answer → offerer wins.
            g.status = if (p.offerer == .white) .white_won else .black_won;
            g.winner = p.offerer;
            g.end_reason = .timeout_pending;
            g.pending = null;
        } else {
            const loser = run;
            g.status = if (loser == .white) .black_won else .white_won;
            g.winner = other(loser);
            g.end_reason = .timeout;
        }
    }

    fn finishFromEngine(g: *Game, b: *engine.Board, mover: Color) void {
        switch (b.status()) {
            .checkmate => {
                // Side to move is mated → the mover delivered mate.
                g.status = if (mover == .white) .white_won else .black_won;
                g.winner = mover;
                g.end_reason = .checkmate;
            },
            .stalemate => {
                g.status = .draw;
                g.end_reason = .stalemate;
            },
            .draw_fifty => {
                g.status = .draw;
                g.end_reason = .fifty_move;
            },
            .draw_insufficient => {
                g.status = .draw;
                g.end_reason = .insufficient_material;
            },
            .ongoing => {},
        }
    }

    // ── Verbs ─────────────────────────────────────────────────────────

    pub fn createGame(
        self: *Store,
        game_id: []const u8,
        creator: []const u8,
        creator_color: Color,
        stake_sats: u64,
        clock_ms: i64,
    ) StoreError!void {
        if (game_id.len == 0 or creator.len == 0) return StoreError.invalid_id;
        self.mu.lock();
        defer self.mu.unlock();

        const id_key = self.allocator.dupe(u8, game_id) catch return StoreError.out_of_memory;
        errdefer self.allocator.free(id_key);
        const id_dup = self.allocator.dupe(u8, game_id) catch return StoreError.out_of_memory;
        errdefer self.allocator.free(id_dup);
        const creator_dup = self.allocator.dupe(u8, creator) catch return StoreError.out_of_memory;
        errdefer self.allocator.free(creator_dup);
        const fen_dup = self.allocator.dupe(u8, engine.Board.START_FEN) catch return StoreError.out_of_memory;
        errdefer self.allocator.free(fen_dup);

        const now = self.clock_fn();
        var g = Game{
            .id = id_dup,
            .white = if (creator_color == .white) creator_dup else "",
            .black = if (creator_color == .black) creator_dup else "",
            .creator_color = creator_color,
            .fen = fen_dup,
            .stake_sats = stake_sats,
            .cube_owner = null, // centered (design D6)
            .white_ms = clock_ms,
            .black_ms = clock_ms,
            .last_settle_ms = now,
        };

        // Phase-2: when a wallet seam is attached, open the escrow and
        // anchor the creator's base stake. Default bankroll = base (no
        // doubling headroom until setBankroll). No wallet ⇒ skipped
        // entirely → Phase-1 behaviour unchanged.
        if (self.wallet) |port| {
            g.white_bankroll = stake_sats;
            g.black_bankroll = stake_sats;
            g.escrow = escrow_mod.Escrow.init(stake_sats, self.lock_horizon);
            var pbuf: [96]u8 = undefined;
            const cpath = anchorPath(&pbuf, game_id, creator_color, "base");
            g.escrow.?.open(port, ecol(creator_color), cpath) catch return StoreError.escrow_failed;
        }
        self.games.put(id_key, g) catch return StoreError.out_of_memory;
    }

    pub fn joinGame(self: *Store, game_id: []const u8, joiner: []const u8) StoreError!?Rejection {
        if (joiner.len == 0) return StoreError.invalid_id;
        self.mu.lock();
        defer self.mu.unlock();
        const g = self.games.getPtr(game_id) orelse return .game_not_found;
        if (g.status != .waiting) return .game_not_waiting;

        const joiner_dup = self.allocator.dupe(u8, joiner) catch return StoreError.out_of_memory;
        if (g.creator_color == .white) g.black = joiner_dup else g.white = joiner_dup;
        g.status = .active;
        g.running = .white; // White moves first; White's clock starts.
        g.last_settle_ms = self.clock_fn();

        if (self.wallet) |port| {
            if (g.escrow != null) {
                const opp = other(g.creator_color);
                var pbuf: [96]u8 = undefined;
                const opath = anchorPath(&pbuf, game_id, opp, "base");
                g.escrow.?.join(port, ecol(opp), opath) catch return StoreError.escrow_failed;
            }
        }
        return null;
    }

    pub fn submitMove(
        self: *Store,
        game_id: []const u8,
        who: []const u8,
        uci: []const u8,
    ) StoreError!?Rejection {
        self.mu.lock();
        defer self.mu.unlock();
        const g = self.games.getPtr(game_id) orelse return .game_not_found;
        self.settle(g);
        if (g.status != .active) return .game_not_active;
        const pc = g.playerColor(who) orelse return .not_a_player;
        if (g.pending != null) return .double_pending;

        var b = engine.Board.fromFen(g.fen) catch unreachable;
        if (b.stm != pc) return .not_your_turn;
        const mv = b.parseUci(uci) orelse return .illegal_move;

        _ = b.makeMove(mv);
        var fbuf: [100]u8 = undefined;
        const new_fen = b.toFen(&fbuf);
        const owned = self.allocator.dupe(u8, new_fen) catch return StoreError.out_of_memory;
        self.allocator.free(g.fen);
        g.fen = owned;

        finishFromEngine(g, &b, pc);
        if (g.status == .active) {
            const rep = try self.bumpRepetition(game_id, new_fen);
            if (rep >= 3) {
                g.status = .draw;
                g.end_reason = .threefold;
            }
        }
        if (g.status == .active) {
            g.running = other(pc);
            g.last_settle_ms = self.clock_fn();
        } else {
            g.running = null;
        }
        return null;
    }

    pub fn offerDouble(self: *Store, game_id: []const u8, who: []const u8) StoreError!?Rejection {
        self.mu.lock();
        defer self.mu.unlock();
        const g = self.games.getPtr(game_id) orelse return .game_not_found;
        self.settle(g);
        if (g.status != .active) return .game_not_active;
        const pc = g.playerColor(who) orelse return .not_a_player;
        if (g.pending != null) return .double_pending;
        if ((pc == .white and g.white_all_in) or (pc == .black and g.black_all_in)) return .already_all_in;
        // Backgammon: the cube is offered on your turn, instead of moving.
        const b = engine.Board.fromFen(g.fen) catch unreachable;
        if (b.stm != pc) return .not_your_turn;
        if (g.cube_owner != null and g.cube_owner.? != pc) return .cube_not_yours;

        // Phase-2: the offerer must be able to back the new level at
        // least all-in (design §6 symmetric obligation).
        if (g.escrow) |*e| {
            e.canOffer(ecol(pc), balanceOf(g, pc)) catch |err| return switch (err) {
                error.cube_dead => Rejection.already_all_in,
                error.offer_uncovered, error.nothing_committed => Rejection.escrow_uncovered,
                error.not_active, error.already_resolved => Rejection.game_not_active,
            };
        }

        g.pending = .{ .offerer = pc, .level_before = g.multiplier, .level_after = g.multiplier * 2 };
        // Offerer clock freezes; responder's clock runs (design §5).
        g.running = other(pc);
        g.last_settle_ms = self.clock_fn();
        return null;
    }

    pub fn acceptDouble(self: *Store, game_id: []const u8, who: []const u8) StoreError!?Rejection {
        self.mu.lock();
        defer self.mu.unlock();
        const g = self.games.getPtr(game_id) orelse return .game_not_found;
        self.settle(g);
        if (g.status != .active) return .game_not_active;
        const pc = g.playerColor(who) orelse return .not_a_player;
        const p = g.pending orelse return .no_pending_double;
        if (pc == p.offerer) return .not_the_responder;

        // Phase-2: responder covers the delta to the new level, or goes
        // all-in (design §6 / D2). Cube dies once anyone is all-in.
        if (self.wallet) |port| {
            if (g.escrow != null) {
                var pbuf: [96]u8 = undefined;
                const apath = std.fmt.bufPrint(&pbuf, "{s}/stake/{s}/aug{d}", .{
                    game_id, if (pc == .white) "w" else "b", p.level_before,
                }) catch unreachable;
                g.escrow.?.acceptDouble(port, ecol(pc), balanceOf(g, pc), apath) catch |err| return switch (err) {
                    error.cube_dead => Rejection.already_all_in,
                    error.not_active, error.already_resolved => Rejection.game_not_active,
                    error.offer_uncovered, error.nothing_committed => Rejection.escrow_uncovered,
                    error.anchor_failed, error.pay_failed, error.already_consumed, error.port_unavailable => Rejection.escrow_failed,
                };
                // Mirror all-in into the Phase-1 flags the cube guards use.
                g.white_all_in = g.escrow.?.white.all_in;
                g.black_all_in = g.escrow.?.black.all_in;
            }
        }

        g.multiplier = p.level_after;
        g.cube_owner = pc; // cube transfers to the accepter
        g.pending = null;
        // Control returns to the offerer to actually move; their clock
        // resumes.
        g.running = p.offerer;
        g.last_settle_ms = self.clock_fn();
        return null;
    }

    pub fn declineDouble(self: *Store, game_id: []const u8, who: []const u8) StoreError!?Rejection {
        self.mu.lock();
        defer self.mu.unlock();
        const g = self.games.getPtr(game_id) orelse return .game_not_found;
        self.settle(g);
        if (g.status != .active) return .game_not_active;
        const pc = g.playerColor(who) orelse return .not_a_player;
        const p = g.pending orelse return .no_pending_double;
        if (pc == p.offerer) return .not_the_responder;

        // Decline ⇒ game ends, offerer wins the pot at the pre-double
        // level (design §5).
        g.status = if (p.offerer == .white) .white_won else .black_won;
        g.winner = p.offerer;
        g.end_reason = .decline_forfeit;
        g.multiplier = p.level_before;
        g.pending = null;
        g.running = null;
        return null;
    }

    /// Creator cancels a never-joined game and is refunded the base
    /// stake (design Phase-2 refund-to-self). Only the creator, only
    /// while still `waiting`.
    pub fn cancelGame(self: *Store, game_id: []const u8, who: []const u8) StoreError!?Rejection {
        self.mu.lock();
        defer self.mu.unlock();
        const g = self.games.getPtr(game_id) orelse return .game_not_found;
        if (g.status != .waiting) return .game_not_waiting;
        const creator = if (g.creator_color == .white) g.white else g.black;
        if (creator.len == 0 or !std.mem.eql(u8, creator, who)) return .not_a_player;

        if (self.wallet) |port| {
            if (g.escrow) |*e| {
                e.cancel(port) catch |err| return switch (err) {
                    error.already_resolved, error.not_active => Rejection.game_not_active,
                    error.cube_dead, error.offer_uncovered, error.nothing_committed => Rejection.escrow_failed,
                    error.anchor_failed, error.pay_failed, error.already_consumed, error.port_unavailable => Rejection.escrow_failed,
                };
            }
        }
        g.status = .cancelled;
        g.end_reason = .cancelled;
        g.running = null;
        return null;
    }

    /// Player resigns mid-game. Opponent wins. Only allowed while
    /// status=active and the resigner is one of the two players. The
    /// terminal status carries the WINNER's color, end_reason=resign.
    pub fn resignGame(self: *Store, game_id: []const u8, who: []const u8) StoreError!?Rejection {
        self.mu.lock();
        defer self.mu.unlock();
        const g = self.games.getPtr(game_id) orelse return .game_not_found;
        if (g.status != .active) return .game_not_active;
        const pc = g.playerColor(who) orelse return .not_a_player;
        const winner = other(pc);
        // Phase-2: any pending double offer is dead — the resigner can't
        // shake a forced double by resigning to escape it. The cube
        // doesn't pay out beyond what the resign settlement consumes.
        if (g.pending) |_| g.pending = null;
        g.status = if (winner == .white) .white_won else .black_won;
        g.winner = winner;
        g.end_reason = .resign;
        g.running = null;
        return null;
    }

    /// Settle clocks (may trigger a timeout resolution) and return the
    /// authoritative game record. Phase 2 consumes the LINEAR stake +
    /// augment cells into the winner anchor here.
    pub fn resolve(self: *Store, game_id: []const u8) ResolveResult {
        self.mu.lock();
        defer self.mu.unlock();
        const g = self.games.getPtr(game_id) orelse return .{ .rejected = .game_not_found };
        self.settle(g);

        // Phase-2 resolution chokepoint: the single place stake cells
        // are consumed into the winner/refund payout (design §12.3).
        // Idempotent — escrow.resolve rejects a second call.
        if (self.wallet) |port| {
            if (g.escrow) |*e| {
                if (!e.resolved) {
                    const outcome: ?escrow_mod.Outcome = switch (g.status) {
                        .white_won => .{ .winner = .white },
                        .black_won => .{ .winner = .black },
                        .draw => .draw,
                        .waiting, .active => null, // not terminal yet
                        .cancelled => null, // escrow already settled by cancelGame
                    };
                    if (outcome) |oc| {
                        e.resolve(port, oc) catch |err| return switch (err) {
                            error.already_resolved => .{ .game = g.* }, // benign
                            error.not_active, error.cube_dead, error.offer_uncovered, error.nothing_committed => .{ .rejected = .escrow_failed },
                            error.anchor_failed, error.pay_failed, error.already_consumed, error.port_unavailable => .{ .rejected = .escrow_failed },
                        };
                    }
                }
            }
        }
        return .{ .game = g.* };
    }
};

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

// Mutable test clock (milliseconds).
var test_now_ms: i64 = 1_000_000;
fn testClock() i64 {
    return test_now_ms;
}
fn resetClock() void {
    test_now_ms = 1_000_000;
}
fn advance(ms: i64) void {
    test_now_ms += ms;
}

fn newStore() Store {
    resetClock();
    return Store.init(testing.allocator, testClock);
}

/// Assert a verb succeeded (returned null Rejection).
fn ok(r: StoreError!?Rejection) !void {
    const rej = try r;
    if (rej) |x| {
        std.debug.print("unexpected rejection: {s}\n", .{@tagName(x)});
        return error.UnexpectedRejection;
    }
}

test "create + join activates the game, white to move" {
    var s = newStore();
    defer s.deinit();
    try s.createGame("g1", "alice", .white, 100, 60_000);
    try ok(s.joinGame("g1", "bob"));
    const g = s.get("g1").?;
    try testing.expectEqual(Status.active, g.status);
    try testing.expectEqualStrings("alice", g.white);
    try testing.expectEqualStrings("bob", g.black);
    try testing.expectEqual(@as(?Color, .white), g.running);
    try testing.expectEqual(@as(?Color, null), g.cube_owner); // centered
}

test "illegal move rejected, legal move switches the clock" {
    var s = newStore();
    defer s.deinit();
    try s.createGame("g", "w", .white, 100, 60_000);
    try ok(s.joinGame("g", "b"));
    try testing.expectEqual(@as(?Rejection, .illegal_move), try s.submitMove("g", "w", "e2e5"));
    try testing.expectEqual(@as(?Rejection, .not_your_turn), try s.submitMove("g", "b", "e7e5"));
    try ok(s.submitMove("g", "w", "e2e4"));
    try testing.expectEqual(@as(?Color, .black), s.get("g").?.running);
}

test "fool's mate → black_won by checkmate" {
    var s = newStore();
    defer s.deinit();
    try s.createGame("m", "w", .white, 100, 600_000);
    try ok(s.joinGame("m", "b"));
    try ok(s.submitMove("m", "w", "f2f3"));
    try ok(s.submitMove("m", "b", "e7e5"));
    try ok(s.submitMove("m", "w", "g2g4"));
    try ok(s.submitMove("m", "b", "d8h4")); // Qh4#
    const g = s.get("m").?;
    try testing.expectEqual(Status.black_won, g.status);
    try testing.expectEqual(EndReason.checkmate, g.end_reason);
}

test "offer → accept doubles multiplier and transfers cube" {
    var s = newStore();
    defer s.deinit();
    try s.createGame("d", "w", .white, 100, 600_000);
    try ok(s.joinGame("d", "b"));
    try ok(s.offerDouble("d", "w")); // White offers on its turn
    var g = s.get("d").?;
    try testing.expect(g.pending != null);
    try testing.expectEqual(@as(?Color, .black), g.running); // responder clock
    try ok(s.acceptDouble("d", "b"));
    g = s.get("d").?;
    try testing.expectEqual(@as(u32, 2), g.multiplier);
    try testing.expectEqual(@as(?Color, .black), g.cube_owner);
    try testing.expect(g.pending == null);
    try testing.expectEqual(@as(?Color, .white), g.running); // offerer resumes
}

test "decline → offerer wins at pre-double level" {
    var s = newStore();
    defer s.deinit();
    try s.createGame("d", "w", .white, 100, 600_000);
    try ok(s.joinGame("d", "b"));
    try ok(s.offerDouble("d", "w"));
    try ok(s.declineDouble("d", "b"));
    const g = s.get("d").?;
    try testing.expectEqual(Status.white_won, g.status);
    try testing.expectEqual(EndReason.decline_forfeit, g.end_reason);
    try testing.expectEqual(@as(u32, 1), g.multiplier); // level_before
}

test "pending double + responder clock runs out → offerer wins (fair rule §5)" {
    var s = newStore();
    defer s.deinit();
    try s.createGame("t", "w", .white, 100, 5_000);
    try ok(s.joinGame("t", "b"));
    try ok(s.offerDouble("t", "w")); // black (responder) clock now runs
    advance(6_000); // black flags while sitting on the decision
    const r = s.resolve("t");
    try testing.expectEqual(Status.white_won, r.game.status);
    try testing.expectEqual(EndReason.timeout_pending, r.game.end_reason);
    try testing.expectEqual(@as(?Color, .white), r.game.winner);
}

test "normal flag → opponent wins" {
    var s = newStore();
    defer s.deinit();
    try s.createGame("f", "w", .white, 100, 3_000);
    try ok(s.joinGame("f", "b")); // white clock running
    advance(4_000);
    const r = s.resolve("f");
    try testing.expectEqual(Status.black_won, r.game.status);
    try testing.expectEqual(EndReason.timeout, r.game.end_reason);
}

test "cannot move while a double is pending" {
    var s = newStore();
    defer s.deinit();
    try s.createGame("p", "w", .white, 100, 600_000);
    try ok(s.joinGame("p", "b"));
    try ok(s.offerDouble("p", "w"));
    try testing.expectEqual(@as(?Rejection, .double_pending), try s.submitMove("p", "b", "e7e5"));
}

test "cannot offer when it is not your turn" {
    var s = newStore();
    defer s.deinit();
    try s.createGame("o", "w", .white, 100, 600_000);
    try ok(s.joinGame("o", "b"));
    // It is White to move; Black cannot offer.
    try testing.expectEqual(@as(?Rejection, .not_your_turn), try s.offerDouble("o", "b"));
}

test "cube ownership gates a second offer" {
    var s = newStore();
    defer s.deinit();
    try s.createGame("c", "w", .white, 100, 600_000);
    try ok(s.joinGame("c", "b"));
    try ok(s.offerDouble("c", "w"));
    try ok(s.acceptDouble("c", "b")); // cube now owned by black
    // White to move again; White no longer owns the cube.
    try testing.expectEqual(@as(?Rejection, .cube_not_yours), try s.offerDouble("c", "w"));
}

// ── Phase-2: escrow integration through the store (fake WalletPort) ──

const IFake = struct {
    anchored: u64 = 0,
    n_consumed: usize = 0,
    paid_white: u64 = 0,
    paid_black: u64 = 0,
    fn anchor(ctx: *anyopaque, owner: escrow_mod.Color, sats: u64, path: []const u8) escrow_mod.WalletError!void {
        _ = owner;
        _ = path;
        const s: *IFake = @ptrCast(@alignCast(ctx));
        s.anchored += sats;
    }
    fn consume(ctx: *anyopaque, path: []const u8) escrow_mod.WalletError!void {
        _ = path;
        const s: *IFake = @ptrCast(@alignCast(ctx));
        s.n_consumed += 1;
    }
    fn pay(ctx: *anyopaque, owner: escrow_mod.Color, sats: u64) escrow_mod.WalletError!void {
        const s: *IFake = @ptrCast(@alignCast(ctx));
        if (owner == .white) s.paid_white += sats else s.paid_black += sats;
    }
    fn port(self: *IFake) WalletPort {
        return .{ .ctx = self, .anchor_fn = anchor, .consume_fn = consume, .pay_fn = pay };
    }
};

test "no wallet attached ⇒ escrow never created (Phase-1 behaviour intact)" {
    var s = newStore();
    defer s.deinit();
    try s.createGame("p1", "w", .white, 100, 600_000);
    try ok(s.joinGame("p1", "b"));
    try testing.expect(s.get("p1").?.escrow == null);
}

test "funded game: create→join→offer→accept→resolve drives escrow, conserves" {
    var fake = IFake{};
    var s = newStore();
    defer s.deinit();
    s.attachWallet(fake.port());
    try s.createGame("fg", "w", .white, 100, 600_000);
    s.setBankroll("fg", .white, 400); // headroom to double
    s.setBankroll("fg", .black, 400);
    try ok(s.joinGame("fg", "b"));
    try testing.expectEqual(@as(u64, 200), fake.anchored); // two base anchors
    // White offers on its turn; Black accepts (covers delta to 2·100).
    try ok(s.offerDouble("fg", "w"));
    try ok(s.acceptDouble("fg", "b"));
    try testing.expectEqual(@as(u64, 300), fake.anchored); // +100 augment
    try testing.expectEqual(@as(u32, 2), s.get("fg").?.multiplier);
    // Offering isn't a move — it's still White to move. White plays,
    // then Black (now the cube owner) offers and White declines ⇒
    // Black wins at the pre-double level.
    try ok(s.submitMove("fg", "w", "e2e4"));
    try ok(s.offerDouble("fg", "b"));
    try ok(s.declineDouble("fg", "w"));
    const r = s.resolve("fg");
    try testing.expectEqual(Status.black_won, r.game.status);
    // Conservation: every committed sat paid out, nothing minted/lost.
    try testing.expectEqual(fake.anchored, fake.paid_white + fake.paid_black);
    try testing.expect(fake.n_consumed >= 3); // 2 base + 1 augment consumed
}

test "offer rejected when no doubling headroom (bankroll == base)" {
    var fake = IFake{};
    var s = newStore();
    defer s.deinit();
    s.attachWallet(fake.port());
    try s.createGame("nh", "w", .white, 100, 600_000);
    try ok(s.joinGame("nh", "b")); // default bankroll == base, no headroom
    try testing.expectEqual(@as(?Rejection, .escrow_uncovered), try s.offerDouble("nh", "w"));
}

test "cancelGame: creator of a never-joined funded game is refunded" {
    var fake = IFake{};
    var s = newStore();
    defer s.deinit();
    s.attachWallet(fake.port());
    try s.createGame("cg", "alice", .white, 100, 600_000);
    // Non-creator cannot cancel.
    try testing.expectEqual(@as(?Rejection, .not_a_player), try s.cancelGame("cg", "mallory"));
    try ok(s.cancelGame("cg", "alice"));
    const g = s.get("cg").?;
    try testing.expectEqual(Status.cancelled, g.status);
    try testing.expectEqual(@as(u64, 100), fake.paid_white); // stake refunded
    try testing.expectEqual(fake.anchored, fake.paid_white + fake.paid_black);
}

test "cancelGame rejected once the opponent has joined" {
    var fake = IFake{};
    var s = newStore();
    defer s.deinit();
    s.attachWallet(fake.port());
    try s.createGame("cg2", "w", .white, 100, 600_000);
    try ok(s.joinGame("cg2", "b"));
    try testing.expectEqual(@as(?Rejection, .game_not_waiting), try s.cancelGame("cg2", "w"));
}

test "cancelGame works with no wallet attached (Phase-1: just status)" {
    var s = newStore();
    defer s.deinit();
    try s.createGame("cg3", "w", .white, 100, 600_000);
    try ok(s.cancelGame("cg3", "w"));
    try testing.expectEqual(Status.cancelled, s.get("cg3").?.status);
}

```
