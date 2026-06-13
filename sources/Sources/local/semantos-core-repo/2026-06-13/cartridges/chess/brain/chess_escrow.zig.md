---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/brain/chess_escrow.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.423926+00:00
---

# cartridges/chess/brain/chess_escrow.zig

```zig
// chess_escrow — Path A escrow custody for the chess doubling-cube
// cartridge: the pure, deterministic Satoshi/Spilman pre-signed
// settlement state machine + D2 coverage accounting, with the
// native-only wallet C-ABI behind an injected seam.
//
// Reference:
//   docs/design/CHESS-DOUBLING-CUBE.md §12 (Path A construction),
//     §6 / tracker D2 (commit-more-or-all-in), §12.5 (the guarantee)
//   docs/CHESS-DOUBLING-CUBE-TRACKING.md Phase 2
//   src/ffi/wallet_exports.zig (semantos_wallet_anchor_transition / _pay)
//   src/ffi/exports.zig:1711 (semantos_linear_consume)
//
// Why a seam:
//
//   semantos_wallet_anchor_transition / semantos_wallet_pay /
//   semantos_linear_consume are native-only C-ABI exports that build,
//   sign and BROADCAST to ARC. They cannot run in a unit test. So —
//   exactly as Phase 1 proved the cube/clock state machine with anchors
//   stubbed — Phase 2 proves the *escrow economics* (coverage, the
//   all-in poker cap, the nSequence ratchet, the conservation law,
//   consume-exactly-once) as a pure module. `WalletPort` is the seam:
//   tests inject a recording fake; production wires the real exports
//   (native, behind the detached-grandchild submitter — design §12.6).
//
// What is enforced here (Path A — no game result in any script):
//   • D2 coverage: accept = cover the delta to 2·m·S, or go all-in;
//     once anyone is all-in the cube is dead.
//   • Poker cap: a player only wins up to what the other matched;
//     unmatched stake is returned to its own owner.
//   • Conservation: Σ committed (both sides, base+augments) == Σ payout.
//   • nSequence ratchet: the enforced exit is the highest-seq
//     mutually-signed settlement; a stale state never overrides a
//     fresher one (design §12.3 / §12.5).
//   • Resolution consumes every stake anchor exactly once; replay is
//     rejected (mirrors SEMANTOS_ERR_ALREADY_CONSUMED).

const std = @import("std");

pub const Color = enum(u1) { white = 0, black = 1 };

inline fn other(c: Color) Color {
    return if (c == .white) .black else .white;
}

pub const EscrowError = error{
    not_active,
    already_resolved,
    cube_dead, // an all-in already happened; no further escalation
    offer_uncovered, // offerer cannot even all-in back the new level
    nothing_committed,
};

/// Errors surfaced by the wallet seam. `already_consumed` mirrors
/// SEMANTOS_ERR_ALREADY_CONSUMED — the replay guard.
pub const WalletError = error{
    anchor_failed,
    pay_failed,
    already_consumed,
    port_unavailable,
};

/// An on-chain stake anchor (the result of
/// semantos_wallet_anchor_transition). In the pure model only the
/// identity + amount matter; the real port carries txid/vout.
pub const Anchor = struct {
    owner: Color,
    sats: u64,
    /// Stable key the resolution consume() is keyed by (the LINEAR
    /// cell path). Unique per anchor. Value-owned (copied in) so an
    /// Escrow embedded in a by-value hashmap entry never dangles.
    path_buf: [64]u8 = undefined,
    path_len: usize = 0,
    consumed: bool = false,

    pub fn path(self: *const Anchor) []const u8 {
        return self.path_buf[0..self.path_len];
    }
};

/// Injected seam over the native-only wallet C-ABI. Production wires
/// real exports; tests inject a recording fake.
pub const WalletPort = struct {
    ctx: *anyopaque,
    /// Anchor `sats` for `owner` under cell `path`; returns on success.
    anchor_fn: *const fn (ctx: *anyopaque, owner: Color, sats: u64, path: []const u8) WalletError!void,
    /// Mark the LINEAR stake cell at `path` consumed. Replay ⇒
    /// error.already_consumed (SEMANTOS_ERR_ALREADY_CONSUMED).
    consume_fn: *const fn (ctx: *anyopaque, path: []const u8) WalletError!void,
    /// Pay `sats` to `owner` (winner payout / refund leg).
    pay_fn: *const fn (ctx: *anyopaque, owner: Color, sats: u64) WalletError!void,
};

/// Cooperative-close sequence: 0xFFFFFFFF = immediately final
/// (design §12.3 — the fast path both sign at resolution).
pub const FINAL_SEQ: u32 = 0xFFFFFFFF;

/// A both-signed enforced-exit settlement (design §12.3). The
/// pre-resolution split is stake-neutral (each gets their own
/// committed back); resolution swaps in the win/draw split at
/// FINAL_SEQ. Ratchet: seq strictly increases, n_locktime is
/// non-increasing (tightened) on every refresh.
pub const Settlement = struct {
    seq: u32,
    n_locktime: u64,
    payout_white: u64,
    payout_black: u64,
};

const MAX_STATES = 16; // cube is a handful of doubles; all-in kills it fast
const MAX_ANCHORS = 8; // base ×2 + augments before an all-in terminates it

const Side = struct {
    committed: u64 = 0,
    all_in: bool = false,
};

pub const Outcome = union(enum) {
    winner: Color,
    draw,
};

pub const Escrow = struct {
    base_stake: u64, // S
    multiplier: u32 = 1, // m (1,2,4,…)
    white: Side = .{},
    black: Side = .{},
    cube_dead: bool = false,
    active: bool = false, // both sides funded
    resolved: bool = false,

    anchors: [MAX_ANCHORS]Anchor = undefined,
    n_anchors: usize = 0,

    settlements: [MAX_STATES]Settlement = undefined,
    n_settlements: usize = 0,
    next_locktime: u64, // tightens (decreases) each refresh

    pub fn init(base_stake: u64, initial_locktime: u64) Escrow {
        return .{ .base_stake = base_stake, .next_locktime = initial_locktime };
    }

    fn side(self: *Escrow, c: Color) *Side {
        return if (c == .white) &self.white else &self.black;
    }

    /// Append a both-signed settlement. Ratchet invariant: strictly
    /// increasing seq, non-increasing n_locktime (design §12.3).
    fn pushSettlement(self: *Escrow, seq: u32, locktime: u64, pw: u64, pb: u64) void {
        if (self.n_settlements > 0) {
            const prev = self.settlements[self.n_settlements - 1];
            std.debug.assert(seq > prev.seq); // ratchet up
            std.debug.assert(locktime <= prev.n_locktime); // tighten
        }
        self.settlements[self.n_settlements] = .{
            .seq = seq,
            .n_locktime = locktime,
            .payout_white = pw,
            .payout_black = pb,
        };
        self.n_settlements += 1;
    }

    /// Stake-neutral refresh: each side's enforced exit returns its own
    /// committed (no one has won yet). Used at join and after every
    /// accepted double.
    fn refreshNeutral(self: *Escrow) void {
        const seq: u32 = @intCast(self.n_settlements + 1);
        if (self.next_locktime > 0) self.next_locktime -= 1;
        self.pushSettlement(seq, self.next_locktime, self.white.committed, self.black.committed);
    }

    /// The enforced exit a unilateral broadcaster can settle: the
    /// highest-seq mutually-signed settlement. A stale (lower-seq)
    /// state never overrides a fresher one (design §12.5).
    pub fn enforcedExit(self: *const Escrow) ?Settlement {
        if (self.n_settlements == 0) return null;
        var best = self.settlements[0];
        for (self.settlements[1..self.n_settlements]) |s| {
            if (s.seq > best.seq) best = s;
        }
        return best;
    }

    fn addAnchor(self: *Escrow, port: WalletPort, owner: Color, sats: u64, path: []const u8) WalletError!void {
        std.debug.assert(path.len <= 64);
        try port.anchor_fn(port.ctx, owner, sats, path);
        var a = Anchor{ .owner = owner, .sats = sats };
        @memcpy(a.path_buf[0..path.len], path);
        a.path_len = path.len;
        self.anchors[self.n_anchors] = a;
        self.n_anchors += 1;
        self.side(owner).committed += sats;
    }

    // ── Lifecycle ─────────────────────────────────────────────────────

    /// Creator funds their base stake S. Pre-join enforced exit is a
    /// refund to the creator (nobody can be owed anything yet).
    pub fn open(self: *Escrow, port: WalletPort, creator: Color, creator_path: []const u8) WalletError!void {
        try self.addAnchor(port, creator, self.base_stake, creator_path);
        const pw: u64 = if (creator == .white) self.base_stake else 0;
        const pb: u64 = if (creator == .black) self.base_stake else 0;
        // seq starts at 1; locktime is the pre-set refund deadline.
        self.pushSettlement(1, self.next_locktime, pw, pb);
    }

    /// Opponent funds their base stake S → pot active; stake-neutral
    /// enforced exit (each gets their own S back until the game ends).
    pub fn join(self: *Escrow, port: WalletPort, opponent: Color, opponent_path: []const u8) WalletError!void {
        try self.addAnchor(port, opponent, self.base_stake, opponent_path);
        self.active = true;
        self.refreshNeutral();
    }

    /// Guard for offer_double (design §6 symmetric obligation): the
    /// offerer must be able to back the *new* level 2·m·S, at least
    /// all-in. `offerer_balance` is spendable sats they still hold.
    pub fn canOffer(self: *Escrow, offerer: Color, offerer_balance: u64) EscrowError!void {
        if (!self.active or self.resolved) return EscrowError.not_active;
        if (self.cube_dead) return EscrowError.cube_dead;
        const target = @as(u64, self.multiplier) * 2 * self.base_stake;
        const have = self.side(offerer).committed + offerer_balance;
        if (have == 0) return EscrowError.nothing_committed;
        if (have < target) return EscrowError.offer_uncovered;
    }

    /// Accept a double (m → 2m). Responder covers the delta to 2·m·S,
    /// or goes all-in with `responder_balance` (whatever they hold).
    /// Cube dies once anyone is all-in (design §6 / D2).
    pub fn acceptDouble(
        self: *Escrow,
        port: WalletPort,
        responder: Color,
        responder_balance: u64,
        augment_path: []const u8,
    ) (EscrowError || WalletError)!void {
        if (!self.active or self.resolved) return EscrowError.not_active;
        if (self.cube_dead) return EscrowError.cube_dead;

        const new_mult = self.multiplier * 2;
        const target = @as(u64, new_mult) * self.base_stake; // per-side target at 2m
        const r = self.side(responder);
        const delta = if (target > r.committed) target - r.committed else 0;

        if (responder_balance >= delta) {
            try self.addAnchor(port, responder, delta, augment_path);
        } else {
            // All-in: commit what's left, cap the contested pot, kill
            // the cube (nothing left to escalate — design §6).
            try self.addAnchor(port, responder, responder_balance, augment_path);
            r.all_in = true;
            self.cube_dead = true;
        }
        self.multiplier = new_mult;
        self.refreshNeutral();
    }

    /// Decline a double ⇒ offerer wins the pot at the *pre-double*
    /// level (design §5). Resolution is keyed to the offerer.
    pub fn declineDouble(self: *Escrow, port: WalletPort, offerer: Color) (EscrowError || WalletError)!void {
        return self.resolve(port, .{ .winner = offerer });
    }

    /// Final settlement. Poker cap: the winner only takes up to what
    /// the loser matched; unmatched stake is returned to its owner.
    /// Draw: each side refunded its own committed (no rake). Consumes
    /// every stake anchor exactly once (replay ⇒ already_consumed),
    /// then pays. Conservation asserted: Σ committed == Σ payout.
    pub fn resolve(self: *Escrow, port: WalletPort, outcome: Outcome) (EscrowError || WalletError)!void {
        if (!self.active) return EscrowError.not_active;
        if (self.resolved) return EscrowError.already_resolved;

        const wc = self.white.committed;
        const bc = self.black.committed;
        const matched = @min(wc, bc);

        var pay_white: u64 = 0;
        var pay_black: u64 = 0;
        switch (outcome) {
            .draw => {
                pay_white = wc; // refund-to-self, no rake
                pay_black = bc;
            },
            .winner => |w| {
                const contested = 2 * matched;
                // Unmatched excess returns to whoever over-committed.
                const unmatched_white = wc - matched;
                const unmatched_black = bc - matched;
                pay_white = unmatched_white + (if (w == .white) contested else 0);
                pay_black = unmatched_black + (if (w == .black) contested else 0);
            },
        }

        // Conservation law — the heart of "no sCrypt, types instead".
        std.debug.assert(pay_white + pay_black == wc + bc);

        // Consume every stake anchor exactly once (replay rejected).
        for (self.anchors[0..self.n_anchors]) |*a| {
            try port.consume_fn(port.ctx, a.path());
            a.consumed = true;
        }
        // Pay the legs (cooperative-final settlement, seq = FINAL).
        if (pay_white > 0) try port.pay_fn(port.ctx, .white, pay_white);
        if (pay_black > 0) try port.pay_fn(port.ctx, .black, pay_black);

        self.pushSettlement(FINAL_SEQ, 0, pay_white, pay_black);
        self.resolved = true;
    }

    /// Cancel a never-joined game: refund the creator their stake.
    /// Valid only PRE-join (no opponent committed) — once active the
    /// game must run to resolution. Consumes the lone anchor and pays
    /// each side its own committed (the opponent's is 0).
    pub fn cancel(self: *Escrow, port: WalletPort) (EscrowError || WalletError)!void {
        if (self.resolved) return EscrowError.already_resolved;
        if (self.active) return EscrowError.not_active; // join happened — can't cancel
        const wc = self.white.committed;
        const bc = self.black.committed;
        std.debug.assert(wc == 0 or bc == 0); // only the creator funded

        for (self.anchors[0..self.n_anchors]) |*a| {
            try port.consume_fn(port.ctx, a.path());
            a.consumed = true;
        }
        if (wc > 0) try port.pay_fn(port.ctx, .white, wc);
        if (bc > 0) try port.pay_fn(port.ctx, .black, bc);

        self.pushSettlement(FINAL_SEQ, 0, wc, bc);
        self.resolved = true;
    }

    pub fn pot(self: *const Escrow) u64 {
        return self.white.committed + self.black.committed;
    }
};

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

/// Recording fake WalletPort — models the native exports' observable
/// behaviour: anchors succeed, consume is exactly-once (second ⇒
/// already_consumed, like SEMANTOS_ERR_ALREADY_CONSUMED), pay records.
const FakeWallet = struct {
    anchored: u64 = 0,
    consumed: [16][]const u8 = undefined,
    n_consumed: usize = 0,
    paid_white: u64 = 0,
    paid_black: u64 = 0,

    fn anchor(ctx: *anyopaque, owner: Color, sats: u64, path: []const u8) WalletError!void {
        _ = owner;
        _ = path;
        const self: *FakeWallet = @ptrCast(@alignCast(ctx));
        self.anchored += sats;
    }
    fn consume(ctx: *anyopaque, path: []const u8) WalletError!void {
        const self: *FakeWallet = @ptrCast(@alignCast(ctx));
        for (self.consumed[0..self.n_consumed]) |p| {
            if (std.mem.eql(u8, p, path)) return WalletError.already_consumed;
        }
        self.consumed[self.n_consumed] = path;
        self.n_consumed += 1;
    }
    fn pay(ctx: *anyopaque, owner: Color, sats: u64) WalletError!void {
        const self: *FakeWallet = @ptrCast(@alignCast(ctx));
        if (owner == .white) self.paid_white += sats else self.paid_black += sats;
    }
    fn port(self: *FakeWallet) WalletPort {
        return .{ .ctx = self, .anchor_fn = anchor, .consume_fn = consume, .pay_fn = pay };
    }
};

test "open + join: stake-neutral enforced exit, conservation" {
    var fw = FakeWallet{};
    const p = fw.port();
    var e = Escrow.init(100, 1000);
    try e.open(p, .white, "w/base");
    try e.join(p, .black, "b/base");
    try testing.expect(e.active);
    try testing.expectEqual(@as(u64, 200), e.pot());
    const ex = e.enforcedExit().?;
    try testing.expectEqual(@as(u64, 100), ex.payout_white);
    try testing.expectEqual(@as(u64, 100), ex.payout_black);
    try testing.expectEqual(@as(u64, 200), fw.anchored);
}

test "accept double with full cover: multiplier, conservation, ratchet" {
    var fw = FakeWallet{};
    const p = fw.port();
    var e = Escrow.init(100, 1000);
    try e.open(p, .white, "w/base");
    try e.join(p, .black, "b/base");
    // White offers (it can back 2·1·100=200; has 100 committed + 200 bal).
    try e.canOffer(.white, 200);
    // Black accepts: target per side at m=2 is 200; delta = 200-100 = 100.
    try e.acceptDouble(p, .black, 1000, "b/aug1");
    try testing.expectEqual(@as(u32, 2), e.multiplier);
    try testing.expectEqual(@as(u64, 300), e.pot()); // w100 + b200
    // Enforced exit is the latest, highest-seq, stake-neutral split.
    const ex = e.enforcedExit().?;
    try testing.expectEqual(@as(u64, 100), ex.payout_white);
    try testing.expectEqual(@as(u64, 200), ex.payout_black);
}

test "stale settlement never overrides a fresher one (§12.5)" {
    var fw = FakeWallet{};
    const p = fw.port();
    var e = Escrow.init(100, 1000);
    try e.open(p, .white, "w/b");
    try e.join(p, .black, "b/b"); // seq 2 now latest
    const fresh = e.enforcedExit().?;
    try testing.expectEqual(@as(u32, 2), fresh.seq);
    // Manually inject an older-seq state as if a griefer replayed it.
    e.settlements[e.n_settlements] = .{ .seq = 1, .n_locktime = 999, .payout_white = 200, .payout_black = 0 };
    e.n_settlements += 1;
    const still = e.enforcedExit().?;
    try testing.expectEqual(@as(u32, 2), still.seq); // fresher wins
    try testing.expectEqual(@as(u64, 100), still.payout_white);
}

test "all-in caps the pot poker-style, kills the cube, returns unmatched" {
    var fw = FakeWallet{};
    const p = fw.port();
    var e = Escrow.init(100, 1000);
    try e.open(p, .white, "w/b");
    try e.join(p, .black, "b/b"); // each 100
    // Black accepts a double but only has 30 left (needs delta 100).
    try e.acceptDouble(p, .black, 30, "b/allin");
    try testing.expect(e.cube_dead);
    try testing.expect(e.black.all_in);
    try testing.expectEqual(@as(u64, 130), e.black.committed); // 100 + 30
    try testing.expectEqual(@as(u64, 100), e.white.committed);
    // No further escalation.
    try testing.expectError(EscrowError.cube_dead, e.canOffer(.white, 10_000));
    // White wins: matched = 100, contested = 200; black's 30 unmatched
    // returns to black; white gets 200.
    try e.resolve(p, .{ .winner = .white });
    try testing.expectEqual(@as(u64, 200), fw.paid_white);
    try testing.expectEqual(@as(u64, 30), fw.paid_black); // unmatched refund
    try testing.expectEqual(e.pot(), fw.paid_white + fw.paid_black); // conservation
}

test "decline ⇒ offerer wins; resolve consumes every anchor once" {
    var fw = FakeWallet{};
    const p = fw.port();
    var e = Escrow.init(50, 500);
    try e.open(p, .white, "w/b");
    try e.join(p, .black, "b/b");
    try e.declineDouble(p, .white); // offerer = white wins
    try testing.expectEqual(@as(u64, 100), fw.paid_white);
    try testing.expectEqual(@as(u64, 0), fw.paid_black);
    try testing.expectEqual(@as(usize, 2), fw.n_consumed); // both base anchors
    // Replay guard: a second resolve must not double-pay.
    try testing.expectError(EscrowError.already_resolved, e.resolve(p, .{ .winner = .white }));
}

test "draw refunds each side its own committed, no rake" {
    var fw = FakeWallet{};
    const p = fw.port();
    var e = Escrow.init(100, 1000);
    try e.open(p, .white, "w/b");
    try e.join(p, .black, "b/b");
    try e.acceptDouble(p, .black, 1000, "b/aug"); // w100 b200
    try e.resolve(p, .draw);
    try testing.expectEqual(@as(u64, 100), fw.paid_white);
    try testing.expectEqual(@as(u64, 200), fw.paid_black);
    try testing.expectEqual(e.pot(), fw.paid_white + fw.paid_black);
}

test "offer guard: cannot offer a double you cannot at least all-in back" {
    var fw = FakeWallet{};
    const p = fw.port();
    var e = Escrow.init(100, 1000);
    try e.open(p, .white, "w/b");
    try e.join(p, .black, "b/b");
    // m=1 → target 2·1·100 = 200. White has 100 committed + only 50 bal.
    try testing.expectError(EscrowError.offer_uncovered, e.canOffer(.white, 50));
    // With 100 more it exactly reaches 200 → ok.
    try e.canOffer(.white, 100);
}

test "resolve replay through the port surfaces already_consumed" {
    var fw = FakeWallet{};
    const p = fw.port();
    var e = Escrow.init(100, 1000);
    try e.open(p, .white, "w/b");
    try e.join(p, .black, "b/b");
    try e.resolve(p, .{ .winner = .black });
    // Force a re-consume of an anchor directly (models a replayed
    // settlement hitting SEMANTOS_ERR_ALREADY_CONSUMED).
    try testing.expectError(WalletError.already_consumed, fw.port().consume_fn(&fw, "w/b"));
}

test "cancel before join refunds the creator; not allowed once active" {
    var fw = FakeWallet{};
    const p = fw.port();
    var e = Escrow.init(100, 1000);
    try e.open(p, .white, "w/base"); // creator only
    try e.cancel(p);
    try testing.expectEqual(@as(u64, 100), fw.paid_white);
    try testing.expectEqual(@as(u64, 0), fw.paid_black);
    try testing.expectEqual(@as(usize, 1), fw.n_consumed);
    // Second cancel rejected.
    try testing.expectError(EscrowError.already_resolved, e.cancel(p));

    var fw2 = FakeWallet{};
    const p2 = fw2.port();
    var e2 = Escrow.init(100, 1000);
    try e2.open(p2, .white, "w/b");
    try e2.join(p2, .black, "b/b"); // active now
    try testing.expectError(EscrowError.not_active, e2.cancel(p2));
}

```
