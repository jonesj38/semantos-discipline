---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/brain/chess_engine.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.425284+00:00
---

# cartridges/chess/brain/chess_engine.zig

```zig
// chess_engine — a real, self-contained chess engine for the chess
// doubling-cube cartridge.
//
// Reference:
//   docs/design/CHESS-DOUBLING-CUBE.md §7 (real engine, in-cartridge)
//   docs/CHESS-DOUBLING-CUBE-TRACKING.md §1 Phase 1
//
// Why this exists:
//
//   chessgammon never validated chess moves — submitMove was a frontend
//   TODO and the sCrypt contract only checked state transitions. Here,
//   move legality is enforced inside the cartridge: chess_walkers calls
//   legalMoves / applyUci, and an illegal move never produces a
//   chess.move.v1 cell, so the relay never broadcasts an illegal
//   position. The engine also produces terminal verdicts (checkmate,
//   stalemate, fifty-move, insufficient material) that drive
//   chess.resolve without both players co-signing an outcome.
//
// Design notes:
//
//   • Pure std, allocation-free. Move lists are fixed [256]Move buffers
//     on the caller stack; perft recurses without the heap. This keeps
//     the engine callable from a brain walker with no allocator churn.
//   • 8x8 mailbox board (squares[64], a1=0 .. h8=63). Legality is the
//     make→"is my king attacked?"→unmake filter, which correctly handles
//     the awkward cases (pinned en-passant discovered check, castling
//     through check) without special-case pin logic.
//   • Correctness is pinned by perft against known node counts
//     (startpos + "Kiwipete") in the test block below — the standard
//     gold standard for move-generator correctness.

const std = @import("std");

// ─── Piece / colour encoding ─────────────────────────────────────────

/// Piece kind. `none` = empty square.
pub const Kind = enum(u3) {
    none = 0,
    pawn = 1,
    knight = 2,
    bishop = 3,
    rook = 4,
    queen = 5,
    king = 6,
};

pub const Color = enum(u1) { white = 0, black = 1 };

/// A square is 0..63. file = sq & 7 (a=0..h=7), rank = sq >> 3
/// (rank 1 = 0 .. rank 8 = 7). a1 = 0, h1 = 7, a8 = 56, h8 = 63.
pub const Square = u6;

inline fn fileOf(sq: Square) u3 {
    return @intCast(sq & 7);
}
inline fn rankOf(sq: Square) u3 {
    return @intCast(sq >> 3);
}
inline fn sqOf(file: i32, rank: i32) Square {
    return @intCast(rank * 8 + file);
}

/// squares[] cell: 0 = empty; +1..+6 = white pawn..king; -1..-6 = black.
const Cell = i8;

inline fn cellKind(c: Cell) Kind {
    const a: u8 = @intCast(if (c < 0) -c else c);
    return @enumFromInt(a);
}
inline fn cellColor(c: Cell) Color {
    return if (c > 0) .white else .black;
}
inline fn makeCell(kind: Kind, color: Color) Cell {
    const k: i8 = @intCast(@intFromEnum(kind));
    return if (color == .white) k else -k;
}

inline fn opp(c: Color) Color {
    return if (c == .white) .black else .white;
}

// ─── Castling rights bitmask ─────────────────────────────────────────

const CASTLE_WK: u4 = 1; // white king-side
const CASTLE_WQ: u4 = 2; // white queen-side
const CASTLE_BK: u4 = 4; // black king-side
const CASTLE_BQ: u4 = 8; // black queen-side

// ─── Move ────────────────────────────────────────────────────────────

pub const MoveKind = enum(u3) {
    normal,
    double_push,
    en_passant,
    castle_king,
    castle_queen,
    promotion,
};

pub const Move = struct {
    from: Square,
    to: Square,
    /// For MoveKind.promotion only: the promoted-to kind (knight..queen).
    promo: Kind = .none,
    kind: MoveKind = .normal,

    pub fn eqUci(self: Move, from: Square, to: Square, promo: Kind) bool {
        return self.from == from and self.to == to and
            (self.kind != .promotion or self.promo == promo);
    }
};

pub const MoveList = struct {
    items: [256]Move = undefined,
    len: usize = 0,

    inline fn push(self: *MoveList, m: Move) void {
        self.items[self.len] = m;
        self.len += 1;
    }
    pub fn slice(self: *const MoveList) []const Move {
        return self.items[0..self.len];
    }
};

// ─── Board ───────────────────────────────────────────────────────────

pub const Board = struct {
    squares: [64]Cell = [_]Cell{0} ** 64,
    stm: Color = .white,
    castling: u4 = 0,
    ep: ?Square = null,
    halfmove: u16 = 0,
    fullmove: u16 = 1,

    pub const FenError = error{
        bad_fen,
    };

    /// Parse a full FEN string. Only the fields chess needs.
    pub fn fromFen(fen: []const u8) FenError!Board {
        var b = Board{};
        var it = std.mem.tokenizeScalar(u8, fen, ' ');

        const placement = it.next() orelse return error.bad_fen;
        var rank: i32 = 7;
        var file: i32 = 0;
        for (placement) |ch| {
            switch (ch) {
                '/' => {
                    if (file != 8) return error.bad_fen;
                    rank -= 1;
                    file = 0;
                },
                '1'...'8' => file += @as(i32, ch - '0'),
                else => {
                    if (file > 7 or rank < 0) return error.bad_fen;
                    const color: Color = if (ch >= 'a') .black else .white;
                    const kind: Kind = switch (std.ascii.toLower(ch)) {
                        'p' => .pawn,
                        'n' => .knight,
                        'b' => .bishop,
                        'r' => .rook,
                        'q' => .queen,
                        'k' => .king,
                        else => return error.bad_fen,
                    };
                    b.squares[sqOf(file, rank)] = makeCell(kind, color);
                    file += 1;
                },
            }
        }
        if (rank != 0 or file != 8) return error.bad_fen;

        const stm = it.next() orelse return error.bad_fen;
        b.stm = if (std.mem.eql(u8, stm, "w")) .white else if (std.mem.eql(u8, stm, "b")) .black else return error.bad_fen;

        const cr = it.next() orelse return error.bad_fen;
        if (!std.mem.eql(u8, cr, "-")) {
            for (cr) |ch| b.castling |= switch (ch) {
                'K' => CASTLE_WK,
                'Q' => CASTLE_WQ,
                'k' => CASTLE_BK,
                'q' => CASTLE_BQ,
                else => return error.bad_fen,
            };
        }

        const ep = it.next() orelse return error.bad_fen;
        if (!std.mem.eql(u8, ep, "-")) {
            if (ep.len != 2) return error.bad_fen;
            const f: i32 = @as(i32, ep[0]) - 'a';
            const r: i32 = @as(i32, ep[1]) - '1';
            if (f < 0 or f > 7 or r < 0 or r > 7) return error.bad_fen;
            b.ep = sqOf(f, r);
        }

        // halfmove / fullmove are optional (some FENs omit them).
        if (it.next()) |hm| b.halfmove = std.fmt.parseInt(u16, hm, 10) catch 0;
        if (it.next()) |fm| b.fullmove = std.fmt.parseInt(u16, fm, 10) catch 1;
        return b;
    }

    pub const START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

    pub fn initial() Board {
        return fromFen(START_FEN) catch unreachable;
    }

    /// Full FEN. `buf` must be >= 100 bytes; returns the written slice.
    pub fn toFen(self: *const Board, buf: []u8) []const u8 {
        var w: usize = 0;
        var rank: i32 = 7;
        while (rank >= 0) : (rank -= 1) {
            var empty: u8 = 0;
            var file: i32 = 0;
            while (file < 8) : (file += 1) {
                const c = self.squares[sqOf(file, rank)];
                if (c == 0) {
                    empty += 1;
                    continue;
                }
                if (empty > 0) {
                    buf[w] = '0' + empty;
                    w += 1;
                    empty = 0;
                }
                const letter: u8 = switch (cellKind(c)) {
                    .pawn => 'p',
                    .knight => 'n',
                    .bishop => 'b',
                    .rook => 'r',
                    .queen => 'q',
                    .king => 'k',
                    .none => unreachable,
                };
                buf[w] = if (cellColor(c) == .white) std.ascii.toUpper(letter) else letter;
                w += 1;
            }
            if (empty > 0) {
                buf[w] = '0' + empty;
                w += 1;
            }
            if (rank > 0) {
                buf[w] = '/';
                w += 1;
            }
        }
        buf[w] = ' ';
        w += 1;
        buf[w] = if (self.stm == .white) 'w' else 'b';
        w += 1;
        buf[w] = ' ';
        w += 1;
        if (self.castling == 0) {
            buf[w] = '-';
            w += 1;
        } else {
            if (self.castling & CASTLE_WK != 0) {
                buf[w] = 'K';
                w += 1;
            }
            if (self.castling & CASTLE_WQ != 0) {
                buf[w] = 'Q';
                w += 1;
            }
            if (self.castling & CASTLE_BK != 0) {
                buf[w] = 'k';
                w += 1;
            }
            if (self.castling & CASTLE_BQ != 0) {
                buf[w] = 'q';
                w += 1;
            }
        }
        buf[w] = ' ';
        w += 1;
        if (self.ep) |e| {
            buf[w] = 'a' + @as(u8, fileOf(e));
            w += 1;
            buf[w] = '1' + @as(u8, rankOf(e));
            w += 1;
        } else {
            buf[w] = '-';
            w += 1;
        }
        w += (std.fmt.bufPrint(buf[w..], " {d} {d}", .{ self.halfmove, self.fullmove }) catch unreachable).len;
        return buf[0..w];
    }

    fn kingSquare(self: *const Board, color: Color) Square {
        const target = makeCell(.king, color);
        for (self.squares, 0..) |c, i| {
            if (c == target) return @intCast(i);
        }
        unreachable; // a legal position always has both kings
    }

    /// Is `sq` attacked by any piece of colour `by`?
    pub fn isAttacked(self: *const Board, sq: Square, by: Color) bool {
        const f: i32 = fileOf(sq);
        const r: i32 = rankOf(sq);

        // Pawn attacks: a `by` pawn attacks `sq` from the rank behind it
        // (relative to `by`'s advance direction).
        const pr: i32 = if (by == .white) r - 1 else r + 1;
        if (pr >= 0 and pr <= 7) {
            const pawn = makeCell(.pawn, by);
            if (f - 1 >= 0 and self.squares[sqOf(f - 1, pr)] == pawn) return true;
            if (f + 1 <= 7 and self.squares[sqOf(f + 1, pr)] == pawn) return true;
        }

        // Knight.
        const kn = makeCell(.knight, by);
        const KN = [8][2]i32{ .{ 1, 2 }, .{ 2, 1 }, .{ 2, -1 }, .{ 1, -2 }, .{ -1, -2 }, .{ -2, -1 }, .{ -2, 1 }, .{ -1, 2 } };
        for (KN) |d| {
            const nf = f + d[0];
            const nr = r + d[1];
            if (nf >= 0 and nf <= 7 and nr >= 0 and nr <= 7 and self.squares[sqOf(nf, nr)] == kn) return true;
        }

        // King.
        const kg = makeCell(.king, by);
        var df: i32 = -1;
        while (df <= 1) : (df += 1) {
            var dr: i32 = -1;
            while (dr <= 1) : (dr += 1) {
                if (df == 0 and dr == 0) continue;
                const nf = f + df;
                const nr = r + dr;
                if (nf >= 0 and nf <= 7 and nr >= 0 and nr <= 7 and self.squares[sqOf(nf, nr)] == kg) return true;
            }
        }

        // Sliding: rook/queen orthogonal, bishop/queen diagonal.
        const ORTH = [4][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
        const DIAG = [4][2]i32{ .{ 1, 1 }, .{ 1, -1 }, .{ -1, 1 }, .{ -1, -1 } };
        if (self.raySliderHit(f, r, &ORTH, .rook, by)) return true;
        if (self.raySliderHit(f, r, &DIAG, .bishop, by)) return true;
        return false;
    }

    fn raySliderHit(self: *const Board, f: i32, r: i32, dirs: []const [2]i32, line_kind: Kind, by: Color) bool {
        for (dirs) |d| {
            var nf = f + d[0];
            var nr = r + d[1];
            while (nf >= 0 and nf <= 7 and nr >= 0 and nr <= 7) : ({
                nf += d[0];
                nr += d[1];
            }) {
                const c = self.squares[sqOf(nf, nr)];
                if (c == 0) continue;
                if (cellColor(c) == by) {
                    const k = cellKind(c);
                    if (k == .queen or k == line_kind) return true;
                }
                break; // blocked
            }
        }
        return false;
    }

    pub fn inCheck(self: *const Board, color: Color) bool {
        return self.isAttacked(self.kingSquare(color), opp(color));
    }

    // ── Pseudo-legal move generation ──────────────────────────────────

    fn genPseudo(self: *const Board, list: *MoveList) void {
        list.len = 0;
        const us = self.stm;
        const dir: i32 = if (us == .white) 1 else -1;
        const start_rank: i32 = if (us == .white) 1 else 6;
        const promo_rank: i32 = if (us == .white) 7 else 0;

        for (self.squares, 0..) |c, idx| {
            if (c == 0 or cellColor(c) != us) continue;
            const sq: Square = @intCast(idx);
            const f: i32 = fileOf(sq);
            const r: i32 = rankOf(sq);
            switch (cellKind(c)) {
                .pawn => {
                    // Single push.
                    const r1 = r + dir;
                    if (r1 >= 0 and r1 <= 7 and self.squares[sqOf(f, r1)] == 0) {
                        self.emitPawn(list, sq, sqOf(f, r1), r1 == promo_rank, .normal);
                        // Double push.
                        if (r == start_rank and self.squares[sqOf(f, r + 2 * dir)] == 0) {
                            list.push(.{ .from = sq, .to = sqOf(f, r + 2 * dir), .kind = .double_push });
                        }
                    }
                    // Captures + en passant.
                    for ([_]i32{ -1, 1 }) |cf| {
                        const nf = f + cf;
                        if (nf < 0 or nf > 7 or r1 < 0 or r1 > 7) continue;
                        const t = sqOf(nf, r1);
                        const tc = self.squares[t];
                        if (tc != 0 and cellColor(tc) != us) {
                            self.emitPawn(list, sq, t, r1 == promo_rank, .normal);
                        } else if (self.ep != null and self.ep.? == t) {
                            list.push(.{ .from = sq, .to = t, .kind = .en_passant });
                        }
                    }
                },
                .knight => {
                    const KN = [8][2]i32{ .{ 1, 2 }, .{ 2, 1 }, .{ 2, -1 }, .{ 1, -2 }, .{ -1, -2 }, .{ -2, -1 }, .{ -2, 1 }, .{ -1, 2 } };
                    for (KN) |d| self.emitLeap(list, us, sq, f + d[0], r + d[1]);
                },
                .king => {
                    var df: i32 = -1;
                    while (df <= 1) : (df += 1) {
                        var dr: i32 = -1;
                        while (dr <= 1) : (dr += 1) {
                            if (df == 0 and dr == 0) continue;
                            self.emitLeap(list, us, sq, f + df, r + dr);
                        }
                    }
                    self.genCastles(list, us, sq);
                },
                .bishop => self.emitSlide(list, us, sq, &[_][2]i32{ .{ 1, 1 }, .{ 1, -1 }, .{ -1, 1 }, .{ -1, -1 } }),
                .rook => self.emitSlide(list, us, sq, &[_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }),
                .queen => self.emitSlide(list, us, sq, &[_][2]i32{ .{ 1, 1 }, .{ 1, -1 }, .{ -1, 1 }, .{ -1, -1 }, .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }),
                .none => unreachable,
            }
        }
    }

    fn emitPawn(self: *const Board, list: *MoveList, from: Square, to: Square, is_promo: bool, _: MoveKind) void {
        _ = self;
        if (is_promo) {
            inline for ([_]Kind{ .queen, .rook, .bishop, .knight }) |pk| {
                list.push(.{ .from = from, .to = to, .promo = pk, .kind = .promotion });
            }
        } else {
            list.push(.{ .from = from, .to = to, .kind = .normal });
        }
    }

    fn emitLeap(self: *const Board, list: *MoveList, us: Color, from: Square, nf: i32, nr: i32) void {
        if (nf < 0 or nf > 7 or nr < 0 or nr > 7) return;
        const t = sqOf(nf, nr);
        const tc = self.squares[t];
        if (tc == 0 or cellColor(tc) != us) list.push(.{ .from = from, .to = t, .kind = .normal });
    }

    fn emitSlide(self: *const Board, list: *MoveList, us: Color, from: Square, dirs: []const [2]i32) void {
        const f: i32 = fileOf(from);
        const r: i32 = rankOf(from);
        for (dirs) |d| {
            var nf = f + d[0];
            var nr = r + d[1];
            while (nf >= 0 and nf <= 7 and nr >= 0 and nr <= 7) : ({
                nf += d[0];
                nr += d[1];
            }) {
                const t = sqOf(nf, nr);
                const tc = self.squares[t];
                if (tc == 0) {
                    list.push(.{ .from = from, .to = t, .kind = .normal });
                } else {
                    if (cellColor(tc) != us) list.push(.{ .from = from, .to = t, .kind = .normal });
                    break;
                }
            }
        }
    }

    fn genCastles(self: *const Board, list: *MoveList, us: Color, ksq: Square) void {
        // King must not currently be in check; cannot castle out of check.
        if (self.isAttacked(ksq, opp(us))) return;
        const rank: i32 = if (us == .white) 0 else 7;
        const k_right: u4 = if (us == .white) CASTLE_WK else CASTLE_BK;
        const q_right: u4 = if (us == .white) CASTLE_WQ else CASTLE_BQ;

        if (self.castling & k_right != 0) {
            const f5 = sqOf(5, rank);
            const f6 = sqOf(6, rank);
            if (self.squares[f5] == 0 and self.squares[f6] == 0 and
                !self.isAttacked(f5, opp(us)) and !self.isAttacked(f6, opp(us)))
            {
                list.push(.{ .from = ksq, .to = f6, .kind = .castle_king });
            }
        }
        if (self.castling & q_right != 0) {
            const f1 = sqOf(1, rank);
            const f2 = sqOf(2, rank);
            const f3 = sqOf(3, rank);
            if (self.squares[f1] == 0 and self.squares[f2] == 0 and self.squares[f3] == 0 and
                !self.isAttacked(f3, opp(us)) and !self.isAttacked(f2, opp(us)))
            {
                list.push(.{ .from = ksq, .to = f2, .kind = .castle_queen });
            }
        }
    }

    // ── Make / unmake ─────────────────────────────────────────────────

    pub const Undo = struct {
        move: Move,
        captured: Cell,
        prev_castling: u4,
        prev_ep: ?Square,
        prev_halfmove: u16,
        prev_fullmove: u16,
    };

    pub fn makeMove(self: *Board, m: Move) Undo {
        const us = self.stm;
        const piece = self.squares[m.from];
        var u = Undo{
            .move = m,
            .captured = self.squares[m.to],
            .prev_castling = self.castling,
            .prev_ep = self.ep,
            .prev_halfmove = self.halfmove,
            .prev_fullmove = self.fullmove,
        };

        const is_pawn = cellKind(piece) == .pawn;
        const is_capture = u.captured != 0 or m.kind == .en_passant;

        self.squares[m.from] = 0;
        self.squares[m.to] = piece;
        self.ep = null;

        switch (m.kind) {
            .double_push => {
                const mid: i32 = @divExact(@as(i32, rankOf(m.from)) + @as(i32, rankOf(m.to)), 2);
                self.ep = sqOf(fileOf(m.from), mid);
            },
            .en_passant => {
                // Captured pawn sits on the moving side's destination file,
                // at the from-rank.
                const cap_sq = sqOf(fileOf(m.to), rankOf(m.from));
                u.captured = self.squares[cap_sq];
                self.squares[cap_sq] = 0;
            },
            .promotion => self.squares[m.to] = makeCell(m.promo, us),
            .castle_king => {
                const rank: i32 = if (us == .white) 0 else 7;
                self.squares[sqOf(5, rank)] = self.squares[sqOf(7, rank)];
                self.squares[sqOf(7, rank)] = 0;
            },
            .castle_queen => {
                const rank: i32 = if (us == .white) 0 else 7;
                self.squares[sqOf(3, rank)] = self.squares[sqOf(0, rank)];
                self.squares[sqOf(0, rank)] = 0;
            },
            .normal => {},
        }

        // Castling-right revocation: king move, rook move, rook captured.
        if (cellKind(piece) == .king) {
            if (us == .white) self.castling &= ~(CASTLE_WK | CASTLE_WQ) else self.castling &= ~(CASTLE_BK | CASTLE_BQ);
        }
        self.revokeForSquare(m.from);
        self.revokeForSquare(m.to);

        self.halfmove = if (is_pawn or is_capture) 0 else self.halfmove + 1;
        if (us == .black) self.fullmove += 1;
        self.stm = opp(us);
        return u;
    }

    fn revokeForSquare(self: *Board, sq: Square) void {
        self.castling &= switch (sq) {
            0 => ~CASTLE_WQ,
            7 => ~CASTLE_WK,
            56 => ~CASTLE_BQ,
            63 => ~CASTLE_BK,
            else => ~@as(u4, 0),
        };
    }

    pub fn unmakeMove(self: *Board, u: Undo) void {
        const m = u.move;
        self.stm = opp(self.stm);
        const us = self.stm;
        self.castling = u.prev_castling;
        self.ep = u.prev_ep;
        self.halfmove = u.prev_halfmove;
        self.fullmove = u.prev_fullmove;

        const moved = self.squares[m.to];
        switch (m.kind) {
            .promotion => self.squares[m.from] = makeCell(.pawn, us),
            else => self.squares[m.from] = moved,
        }
        self.squares[m.to] = 0;

        switch (m.kind) {
            .en_passant => {
                self.squares[sqOf(fileOf(m.to), rankOf(m.from))] = u.captured;
            },
            .castle_king => {
                const rank: i32 = if (us == .white) 0 else 7;
                self.squares[sqOf(7, rank)] = self.squares[sqOf(5, rank)];
                self.squares[sqOf(5, rank)] = 0;
                self.squares[m.to] = 0;
                self.squares[m.from] = makeCell(.king, us);
            },
            .castle_queen => {
                const rank: i32 = if (us == .white) 0 else 7;
                self.squares[sqOf(0, rank)] = self.squares[sqOf(3, rank)];
                self.squares[sqOf(3, rank)] = 0;
                self.squares[m.to] = 0;
                self.squares[m.from] = makeCell(.king, us);
            },
            else => {
                self.squares[m.to] = u.captured;
            },
        }
    }

    // ── Legal move generation ─────────────────────────────────────────

    pub fn legalMoves(self: *Board, out: *MoveList) void {
        var pseudo = MoveList{};
        self.genPseudo(&pseudo);
        out.len = 0;
        const us = self.stm;
        for (pseudo.slice()) |m| {
            const u = self.makeMove(m);
            const illegal = self.isAttacked(self.kingSquare(us), opp(us));
            self.unmakeMove(u);
            if (!illegal) out.push(m);
        }
    }

    // ── Terminal status ───────────────────────────────────────────────

    pub const Status = enum {
        ongoing,
        checkmate, // side to move is mated → side to move LOST
        stalemate,
        draw_fifty,
        draw_insufficient,
    };

    pub fn status(self: *Board) Status {
        var moves = MoveList{};
        self.legalMoves(&moves);
        if (moves.len == 0) {
            return if (self.inCheck(self.stm)) .checkmate else .stalemate;
        }
        if (self.halfmove >= 100) return .draw_fifty;
        if (self.insufficientMaterial()) return .draw_insufficient;
        return .ongoing;
    }

    fn insufficientMaterial(self: *const Board) bool {
        var minors: u32 = 0;
        var bishop_light: bool = false;
        var bishop_dark: bool = false;
        for (self.squares, 0..) |c, i| {
            if (c == 0) continue;
            switch (cellKind(c)) {
                .king => {},
                .pawn, .rook, .queen => return false,
                .knight => minors += 1,
                .bishop => {
                    minors += 1;
                    // Square colour: (file+rank) parity. light if even.
                    if ((fileOf(@intCast(i)) + rankOf(@intCast(i))) % 2 == 0) bishop_light = true else bishop_dark = true;
                },
                .none => unreachable,
            }
        }
        if (minors <= 1) return true; // KvK, KNvK, KBvK
        // KBvKB with both bishops on the same colour is a dead draw.
        if (minors == 2 and (bishop_light != bishop_dark)) return true;
        return false;
    }

    // ── UCI coordinate notation ───────────────────────────────────────

    /// Parse a UCI move ("e2e4", "e7e8q") and, if it is legal in this
    /// position, return the fully-formed Move (correct kind/flags).
    pub fn parseUci(self: *Board, uci: []const u8) ?Move {
        if (uci.len < 4 or uci.len > 5) return null;
        const ff: i32 = @as(i32, uci[0]) - 'a';
        const fr: i32 = @as(i32, uci[1]) - '1';
        const tf: i32 = @as(i32, uci[2]) - 'a';
        const tr: i32 = @as(i32, uci[3]) - '1';
        if (ff < 0 or ff > 7 or fr < 0 or fr > 7 or tf < 0 or tf > 7 or tr < 0 or tr > 7) return null;
        const from = sqOf(ff, fr);
        const to = sqOf(tf, tr);
        var promo: Kind = .none;
        if (uci.len == 5) promo = switch (std.ascii.toLower(uci[4])) {
            'q' => .queen,
            'r' => .rook,
            'b' => .bishop,
            'n' => .knight,
            else => return null,
        };
        var moves = MoveList{};
        self.legalMoves(&moves);
        for (moves.slice()) |m| {
            if (m.eqUci(from, to, promo)) return m;
        }
        return null;
    }

    pub fn moveToUci(m: Move, buf: []u8) []const u8 {
        buf[0] = 'a' + @as(u8, fileOf(m.from));
        buf[1] = '1' + @as(u8, rankOf(m.from));
        buf[2] = 'a' + @as(u8, fileOf(m.to));
        buf[3] = '1' + @as(u8, rankOf(m.to));
        if (m.kind == .promotion) {
            buf[4] = switch (m.promo) {
                .queen => 'q',
                .rook => 'r',
                .bishop => 'b',
                .knight => 'n',
                else => 'q',
            };
            return buf[0..5];
        }
        return buf[0..4];
    }
};

/// perft — count leaf nodes at `depth`. The move-generator correctness
/// gold standard.
pub fn perft(b: *Board, depth: u32) u64 {
    if (depth == 0) return 1;
    var moves = MoveList{};
    b.legalMoves(&moves);
    if (depth == 1) return moves.len;
    var nodes: u64 = 0;
    for (moves.slice()) |m| {
        const u = b.makeMove(m);
        nodes += perft(b, depth - 1);
        b.unmakeMove(u);
    }
    return nodes;
}

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

test "fen round-trip start position" {
    var b = Board.initial();
    var buf: [100]u8 = undefined;
    try testing.expectEqualStrings(Board.START_FEN, b.toFen(&buf));
}

test "perft startpos depths 1-4" {
    var b = Board.initial();
    try testing.expectEqual(@as(u64, 20), perft(&b, 1));
    try testing.expectEqual(@as(u64, 400), perft(&b, 2));
    try testing.expectEqual(@as(u64, 8902), perft(&b, 3));
    try testing.expectEqual(@as(u64, 197281), perft(&b, 4));
}

test "perft kiwipete depths 1-3 (castling/ep/promo edge cases)" {
    var b = try Board.fromFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
    try testing.expectEqual(@as(u64, 48), perft(&b, 1));
    try testing.expectEqual(@as(u64, 2039), perft(&b, 2));
    try testing.expectEqual(@as(u64, 97862), perft(&b, 3));
}

test "perft position 3 (ep discovered-check correctness)" {
    var b = try Board.fromFen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1");
    try testing.expectEqual(@as(u64, 14), perft(&b, 1));
    try testing.expectEqual(@as(u64, 191), perft(&b, 2));
    try testing.expectEqual(@as(u64, 2812), perft(&b, 3));
}

test "checkmate detection — fool's mate" {
    var b = try Board.fromFen("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3");
    try testing.expectEqual(Board.Status.checkmate, b.status());
}

test "stalemate detection" {
    var b = try Board.fromFen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1");
    try testing.expectEqual(Board.Status.stalemate, b.status());
}

test "insufficient material — K vs K and KB vs K" {
    var kk = try Board.fromFen("8/8/4k3/8/8/3K4/8/8 w - - 0 1");
    try testing.expectEqual(Board.Status.draw_insufficient, kk.status());
    var kbk = try Board.fromFen("8/8/4k3/8/8/3K4/5B2/8 w - - 0 1");
    try testing.expectEqual(Board.Status.draw_insufficient, kbk.status());
}

test "fifty-move rule" {
    var b = try Board.fromFen("4k3/8/8/8/8/8/8/4K3 w - - 100 80");
    try testing.expectEqual(Board.Status.draw_fifty, b.status());
}

test "parseUci accepts legal, rejects illegal, handles promotion" {
    var b = Board.initial();
    const e2e4 = b.parseUci("e2e4").?;
    try testing.expectEqual(MoveKind.double_push, e2e4.kind);
    try testing.expect(b.parseUci("e2e5") == null); // illegal
    try testing.expect(b.parseUci("e1e3") == null); // illegal king
    var promo = try Board.fromFen("8/P3k3/8/8/8/8/4K3/8 w - - 0 1");
    const p = promo.parseUci("a7a8q").?;
    try testing.expectEqual(MoveKind.promotion, p.kind);
    try testing.expectEqual(Kind.queen, p.promo);
}

test "make/unmake restores position exactly (incl. castling/ep rights)" {
    var b = try Board.fromFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
    var before: [100]u8 = undefined;
    const fen_before = b.toFen(&before);
    var moves = MoveList{};
    b.legalMoves(&moves);
    for (moves.slice()) |m| {
        const u = b.makeMove(m);
        b.unmakeMove(u);
        var after: [100]u8 = undefined;
        try testing.expectEqualStrings(fen_before, b.toFen(&after));
    }
}

```
